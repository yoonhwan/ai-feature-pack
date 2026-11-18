#!/usr/bin/env bash
# test_seat_open_work_refs_r2268.sh — r2268: 받을 일 판정이 진행 카드를 루트 작업 트리 대신 카드 루트 표(directive-roots.tsv)의 행마다 정본 ref 1개에서 읽는다.
#   반례 ①~⑥ · ③ⓐⓑ (카드 동결 · 사전 DA H1 보정) · C1 표의 정본 ref · C2 표·ref 없음 = 작업 트리 꼴(표 읽기 실패 = rc3) · C3 git 실패 = 판정 불가 · C4 indices 없음 판정 불변.
# 격리만: 임시 bare origin + 클론(작업 트리를 일부러 뒤처지게) · 임시 우편함 · fetch 0 · 실 루트·실 리포 0 · sleep 0.
# 변이용: R2268_TOOL=<사본 경로> 로 판정 도구를 바꿔 끼운다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/.." && pwd)"
TOOL="${R2268_TOOL:-$REPO/bin/ft-seat-open-work.py}"; KITTOOL="$REPO/kit/fable-team/bin/ft-seat-open-work.py"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_NOSYSTEM=1 HOME="$T/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME" "$T/mbox"; : > "$T/mbox/mailbox.jsonl"

cmp -s "$REPO/bin/ft-seat-open-work.py" "$KITTOOL" && ok "bin · kit 같은 바이트" || bad "bin · kit 다름"
python3 -m py_compile "$TOOL" && ok "py_compile" || bad "py_compile"

branch() {   # branch <가지> <경로=본문>... — 작업 리포 W 에 고아 가지 1커밋
  local b="$1" kv; shift
  git -C "$W" checkout -q --orphan "$b" && git -C "$W" rm -rqf . >/dev/null 2>&1; find "$W" -mindepth 1 -not -path "$W/.git*" -delete
  for kv in "$@"; do mkdir -p "$W/$(dirname "${kv%%=*}")"; printf '%s\n' "${kv#*=}" > "$W/${kv%%=*}"; done
  git -C "$W" add -A && git -C "$W" commit -qm "$b" && git -C "$W" push -q "$O" "$b" 2>/dev/null
}
world() {   # world — W(작업) → O(bare origin) → R(클론 = 데이터 루트 · main checkout)
  local d="$T/w.$RANDOM$RANDOM"; W="$d/W"; O="$d/O.git"; R="$d/R"
  git init -q -b main "$W" && git init -q --bare -b main "$O"
}
TSV=$'*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\torigin/ops/main-base\tdesign/harness/indices'   # 실 표와 같은 2행
table() { mkdir -p "$1/.fable-team/state"; printf '# 팀\t리포\tref\t루트\n%s\n' "$TSV" > "$1/.fable-team/state/directive-roots.tsv"; }
clone() { git clone -q "$O" "$R" 2>/dev/null; table "$R"; }
run_tool() { OUT="$(PATH="${FAKE:+$FAKE:}$PATH" python3 "$TOOL" "$1" --root "$2" --mbox-dir "$T/mbox" 2>"$T/err")"; RC=$?; }
KEEP='design/teams/ccu/indices/진행/.gitkeep=' HKEEP='design/harness/indices/진행/.gitkeep='
LEAD='byz-ccu-master-pi#41'

# ① 작업 트리 팀 진행/ 에 옛 카드 1장 · 두 ref 같은 폴더 = .gitkeep 만 · 팀장 → rc 0
world; branch main "$KEEP"; branch ops/main-base "$KEEP" "$HKEEP"; clone
printf -- '- 상태: 진행\n' > "$R/design/teams/ccu/indices/진행/old.md"
run_tool "$LEAD" "$R"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 '; } && ok "① 작업 트리 옛 카드 · ref 빈 폴더 → rc0" || bad "① rc=$RC out=$OUT"

# ② 작업 트리에 없고 origin/main 진행/ 에만 배정 카드 → rc 1 «배정 1»
world; branch main "$KEEP" 'design/teams/ccu/indices/진행/a.md=- 배정: 좌석 byz-ccu-nano-x#3'; branch ops/main-base "$HKEEP"; clone
rm -f "$R/design/teams/ccu/indices/진행/a.md"
run_tool 'byz-ccu-nano-x#0' "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=배정 1 (a.md)$'; } && ok "② origin/main 에만 배정 카드 → rc1 배정 1" || bad "② rc=$RC out=$OUT"

# ③ ops/main-base 에만 팀 진행 카드 · 팀장 → rc 1 · ③b 두 ref 같은 경로 = 1장
world; branch main "$KEEP"; branch ops/main-base "$KEEP" 'design/harness/indices/진행/h.md=- 상태: 진행'; clone
run_tool 'byz-harness-master-pi#1' "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=팀 진행 1$'; } && ok "③ ops/main-base 에만 팀 진행 → rc1" || bad "③ rc=$RC out=$OUT"
world; branch main "$KEEP" 'design/harness/indices/진행/h.md=- 상태: 진행'; branch ops/main-base 'design/harness/indices/진행/h.md=- 상태: 진행'; clone
rm -f "$R/design/harness/indices/진행/h.md"
run_tool 'byz-harness-master-pi#1' "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=팀 진행 1$'; } && ok "③b 두 ref 같은 경로 → 1장" || bad "③b rc=$RC out=$OUT"

# ③ⓐ design/harness 가 main 진행/ · ops(정본) 완성/ → 안 셈 rc 0 · ③ⓑ design/teams/ops 가 ops 대기 1 · main(정본) 진행 2 → 2장 rc 1
world; branch main "$KEEP" 'design/harness/indices/진행/h.md=- 상태: 진행'; branch ops/main-base 'design/harness/indices/완성/h.md=- 상태: 완성'; clone   # 작업 트리 = main checkout(진행/h.md 남음)
run_tool 'byz-harness-master-pi#1' "$R"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 '; } && ok "③ⓐ main 낡은 harness 진행 · ops 완성 → 안 셈 rc0" || bad "③ⓐ rc=$RC out=$OUT"
world; branch main 'design/teams/ops/indices/진행/a.md=- 상태: 진행' 'design/teams/ops/indices/진행/b.md=- 상태: 진행'; branch ops/main-base 'design/teams/ops/indices/대기/c.md=- 상태: 대기' "$HKEEP"; clone
run_tool 'byz-ops-master-pi#2' "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=팀 진행 2$'; } && ok "③ⓑ teams/ops = main 정본 진행 2 → rc1" || bad "③ⓑ rc=$RC out=$OUT"
# ③ⓒ 표 밖 옛 루트(ops design/v65) 배정 카드 = 안 읽음 · ③ⓓ 표 없는 git 루트 = 작업 트리 꼴 · ③ⓔ 표 읽기 실패(인코딩) = rc3
world; branch main "$KEEP"; branch ops/main-base "$HKEEP" 'design/v65/indices/진행/v.md=- 배정: 좌석 byz-ccu-nano-x#3'; clone
run_tool 'byz-ccu-nano-x#0' "$R"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 '; } && ok "③ⓒ 표 밖 옛 루트 배정 → 안 셈 rc0" || bad "③ⓒ rc=$RC out=$OUT"
rm -f "$R/.fable-team/state/directive-roots.tsv"; printf -- '- 배정: 좌석 byz-ccu-nano-x#3\n' > "$R/design/teams/ccu/indices/진행/w.md"
run_tool 'byz-ccu-nano-x#0' "$R"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=배정 1 (w.md)$'; } && ok "③ⓓ 표 없음 → 작업 트리 꼴" || bad "③ⓓ rc=$RC out=$OUT"
printf '*\t.\torigin/main\tdesign/teams/\377/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
run_tool 'byz-ccu-nano-x#0' "$R"
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 불가 '; } && ok "③ⓔ 표 읽기 실패 → rc3" || bad "③ⓔ rc=$RC out=$OUT"

# ③ⓕ 표 ref 일부만 있음(ops 미fetch 클론 · main 만) → rc3 «카드 ref 판독»(그 행 작업 트리로 안 내려감 · DA#27 #340140 ①)
world; branch main "$KEEP"; clone
mkdir -p "$R/design/harness/indices/진행"; printf -- '- 상태: 진행\n' > "$R/design/harness/indices/진행/old.md"
run_tool 'byz-harness-master-pi#1' "$R"
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 불가 이유=카드 ref 판독'; } && ok "③ⓕ 표 ref 일부만 → rc3 카드 ref 판독" || bad "③ⓕ rc=$RC out=$OUT"
# ③ⓖ 표 2칸(리포)이 «.» 아님 = <root>/<2칸> 리포에서 읽음(DA#27 #340140 ②)
world; branch main 'design/teams/ccu/indices/진행/a.md=- 배정: 좌석 byz-ccu-nano-x#3'; branch ops/main-base "$HKEEP"
G="$T/g.$RANDOM"; mkdir -p "$G/.fable-team/state"; git clone -q "$O" "$G/cards" 2>/dev/null; rm -f "$G/cards/design/teams/ccu/indices/진행/a.md"
printf '*\tcards\torigin/main\tdesign/teams/*/indices\n' > "$G/.fable-team/state/directive-roots.tsv"
run_tool 'byz-ccu-nano-x#0' "$G"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=배정 1 (a.md)$'; } && ok "③ⓖ 표 2칸 cards → <root>/cards 리포 ref 읽음" || bad "③ⓖ rc=$RC out=$OUT"
# ④ 루트가 git 리포 아님 → 작업 트리 꼴 그대로 · ④b 리포 안 하위 폴더도 루트 리포 아님(위로 올라가 남의 ref 를 읽지 않음)
P="$T/plain"; mkdir -p "$P/design/teams/ccu/indices/진행"; printf -- '- 상태: 진행\n' > "$P/design/teams/ccu/indices/진행/x.md"
run_tool "$LEAD" "$P"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=팀 진행 1$'; } && ok "④ git 리포 아님 → 작업 트리 카드 rc1" || bad "④ rc=$RC out=$OUT"
world; branch main "$KEEP"; branch ops/main-base "$KEEP"; clone
S="$R/sub"; table "$S"; mkdir -p "$S/design/teams/ccu/indices/진행"; printf -- '- 상태: 진행\n' > "$S/design/teams/ccu/indices/진행/x.md"
run_tool "$LEAD" "$S"
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 있음 이유=팀 진행 1$'; } && ok "④b 리포 하위 폴더 → 작업 트리 꼴" || bad "④b rc=$RC out=$OUT"

# ⑤ ref 는 있는데 git ls-tree 실패(rc 128) → rc 3 «OPEN-WORK 불가» · 작업 트리 카드가 있어도 rc1 아님
world; branch main "$KEEP"; branch ops/main-base "$KEEP"; clone
printf -- '- 상태: 진행\n' > "$R/design/teams/ccu/indices/진행/old.md"
FAKE="$T/fake"; mkdir -p "$FAKE"; REAL="$(command -v git)"
printf '#!/bin/sh\nfor a; do [ "$a" = ls-tree ] && { echo "fatal: fake" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$REAL" > "$FAKE/git"; chmod +x "$FAKE/git"
run_tool "$LEAD" "$R"; unset FAKE
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 불가 이유=카드 ref 판독'; } && ok "⑤ git 실패 → rc3 불가(작업 트리로 안 내려감)" || bad "⑤ rc=$RC out=$OUT"

# ⑥ 두 ref 에 indices/ 하나도 없음 → rc 3 «카드 폴더 없음» · ⑥b indices 는 있고 진행/ 만 없음 → rc 0(r1541 그대로)
world; branch main 'README.md=x'; branch ops/main-base 'README.md=x'; clone
mkdir -p "$R/design/teams/ccu/indices/진행"; printf -- '- 상태: 진행\n' > "$R/design/teams/ccu/indices/진행/old.md"
run_tool "$LEAD" "$R"
{ [ "$RC" = 3 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 불가 이유=카드 폴더 없음'; } && ok "⑥ ref 에 indices 없음 → rc3 카드 폴더 없음" || bad "⑥ rc=$RC out=$OUT"
world; branch main 'design/teams/ccu/indices/대기/.gitkeep='; branch ops/main-base 'README.md=x'; clone
run_tool "$LEAD" "$R"
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '^OPEN-WORK 0 '; } && ok "⑥b ref 진행/ 만 없음 → rc0" || bad "⑥b rc=$RC out=$OUT"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
