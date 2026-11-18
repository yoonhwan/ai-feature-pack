#!/usr/bin/env bash
# test_cards_wt_sync_r2117.sh — r2117: 명부 _cards_wt worktree 를 origin/<가지> 로 따라간다(ft-cards-wt-sync.sh).
#   ① 깨끗 · 뒤 3 → 따라감 · 줄 0   ② ① + untracked(원격에 없는 경로) → 따라감 · 파일 그대로
#   ③ tracked 수정 1 · 뒤 3 → 그대로 · «수정 1» 1줄 · 바퀴 2 = 0줄 · 재기동 뒤 바퀴 3 = 0줄
#   ④ 앞 1(같은 패치) · 뒤 3 → «앞 1» 1줄 / 사유 바뀜 → 1줄 더 / 손 정렬 뒤 따라감 → 기억 지움 / 다시 갈라짐 → 1줄
#   ⑤ untracked 가 원격 새 경로 → ff 실패 1줄 · 파일 그대로 / ignored cache.txt 를 원격이 add -f → ff 0 · 바이트 그대로 · 1줄
#   ⑥ worktree 없음 / 원격 가지 없음 / fetch rc≠0(가짜 git) → 각 1줄 · 쓰기 0
# 임시 bare 원격 + 임시 리포 + .worktrees/<이름> 만 쓴다 — 실 리포 · 실 명부 · 실 tmux 0 · sleep 0.
# FT_CARDS_WT_SYNC_BIN = 변이 사본 경로(없으면 ../bin/ft-cards-wt-sync.sh).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SYNC="${FT_CARDS_WT_SYNC_BIN:-$HERE/../bin/ft-cards-wt-sync.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 HOME="$T"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 값 «${1}» 기대 «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — «$2» 없음: «$1»";; esac; }
nl()  { printf '%s' "$1" | grep -c .; }

# mk <칸> — 원격 R(가지 ops) · 씨앗 S · 루트 X(.worktrees/cw = ops) · 명부 seats-x.json
mk() {
  C="$T/$1"; R="$C/r.git"; S="$C/s"; X="$C/x"; W="$X/.worktrees/cw"; ST="$C/state"
  git init -q --bare -b main "$R"
  git clone -q "$R" "$S" 2>/dev/null
  git -C "$S" checkout -q -b ops
  mkdir -p "$S/cards"; echo a > "$S/cards/a.md"; printf 'cache.txt\n' > "$S/.gitignore"
  git -C "$S" add -A; git -C "$S" commit -qm base; git -C "$S" push -q origin ops:ops ops:main 2>/dev/null
  git clone -q "$R" "$X" 2>/dev/null
  git -C "$X" worktree add -q "$W" ops 2>/dev/null
  mkdir -p "$X/.fable-team"
  printf '{"_master": "m", "_cards": "cards", "_cards_wt": "cw"}\n' > "$X/.fable-team/seats-x.json"
}
push_n() { local i; for i in $(seq "$1"); do echo "r$i-$RANDOM" > "$S/cards/r$i.md"; git -C "$S" add -A; git -C "$S" commit -qm "r$i"; done; git -C "$S" push -q origin ops; }
run() { OUT="$(bash "$SYNC" "$X" "$ST" 2>&1)"; RC=$?; }
head_of() { git -C "$W" rev-parse HEAD; }
remote_of() { git -C "$S" rev-parse ops; }
snap() { ( cd "$W" && git rev-parse HEAD && git status --porcelain --ignored && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 shasum ) 2>/dev/null; }

# ① 깨끗 · 뒤 3 → 따라감 · 줄 0
mk c1; push_n 3; run
eq "$(head_of)" "$(remote_of)" "① HEAD = origin/ops (뒤 3 → 0)"
eq "$(nl "$OUT")" 0 "① 줄 0"; eq "$RC" 0 "① rc 0"

# ② untracked(원격에 없는 경로) 있음 → 따라감 · 파일 그대로
mk c2; echo keep > "$W/local-only.txt"; push_n 3; run
eq "$(head_of)" "$(remote_of)" "② untracked 있어도 따라감"
eq "$(cat "$W/local-only.txt" 2>/dev/null)" keep "② untracked 파일 그대로"
eq "$(nl "$OUT")" 0 "② 줄 0"

# ③ tracked 수정 1 · 뒤 3 → 그대로 · 1줄 · 바퀴 2·3 = 0줄
mk c3; echo mine > "$W/cards/a.md"; h0="$(head_of)"; push_n 3; run
eq "$(head_of)" "$h0" "③ HEAD 그대로"
eq "$(cat "$W/cards/a.md")" mine "③ 수정 그대로"
eq "$(nl "$OUT")" 1 "③ 바퀴 1 = 1줄"
has "$OUT" "판정 불가 카드 원천 x .worktrees/cw 뒤 3 · 앞 0 · 수정 1 · " "③ 줄 꼴(팀 · worktree · 뒤 · 앞 · 수정)"
has "$OUT" "— 정렬 h" "③ 줄 끝 «— 정렬 h»"
run; eq "$(nl "$OUT")" 0 "③ 바퀴 2 = 0줄"
run; eq "$(nl "$OUT")" 0 "③ 재기동 뒤 바퀴 3 = 0줄(상태 파일)"
eq "$(head_of)" "$h0" "③ 바퀴 3 뒤에도 HEAD 그대로"

# ④ 앞 1(같은 패치) · 뒤 3
mk c4; push_n 1; p="$(remote_of)"
git -C "$W" fetch -q origin; git -C "$W" cherry-pick "$p" >/dev/null 2>&1
git -C "$W" commit -q --amend --no-edit --date=@1 >/dev/null 2>&1
[ "$(git -C "$W" cherry origin/ops HEAD | cut -c1)" = - ] && ok "④ 입력: 앞 1 = 같은 패치(git cherry «-»)" || bad "④ 입력: 같은 패치 아님"
push_n 2; h0="$(head_of)"; run
eq "$(head_of)" "$h0" "④ 앞 1 → HEAD 그대로"
eq "$(nl "$OUT")" 1 "④ 앞 1 · 1줄"; has "$OUT" "뒤 3 · 앞 1 · 수정 0" "④ 줄에 «뒤 3 · 앞 1»"
echo mine > "$W/cards/a.md"; run
eq "$(nl "$OUT")" 1 "④ 사유가 수정으로 바뀜 → 1줄 더"; has "$OUT" "수정 1" "④ 바뀐 줄에 «수정 1»"
run; eq "$(nl "$OUT")" 0 "④ 같은 사유 다시 = 0줄"
git -C "$W" checkout -q -- cards/a.md; git -C "$W" reset -q --keep "$h0~1"   # 사람 손 정렬(시험이 대신 함)
run; eq "$(nl "$OUT")" 0 "④ 손 정렬 뒤 따라감 = 0줄"; eq "$(head_of)" "$(remote_of)" "④ 손 정렬 뒤 HEAD = origin"
eq "$(ls "$ST/cards-wt-sync" 2>/dev/null | grep -c .)" 0 "④ 따라가면 기억 지움"
echo again > "$W/cards/b.md"; git -C "$W" add -A; git -C "$W" commit -qm local; push_n 1; run
eq "$(nl "$OUT")" 1 "④ 다시 갈라지면 1줄"

# ⑤ⓐ untracked 파일이 원격 새 커밋의 같은 경로 → ff 실패 · 파일 그대로
mk c5; echo LOCAL > "$W/cards/r1.md"; h0="$(head_of)"; push_n 1; run
eq "$(head_of)" "$h0" "⑤ⓐ HEAD 그대로"; eq "$(cat "$W/cards/r1.md")" LOCAL "⑤ⓐ untracked 파일 그대로"
eq "$(nl "$OUT")" 1 "⑤ⓐ 1줄"; has "$OUT" "ff 실패" "⑤ⓐ 사유 «ff 실패»"
# ⑤ⓑ ignored cache.txt 를 원격이 add -f 로 새로 추적 → ff 0 · 바이트 그대로
mk c6; printf 'LOCAL KEEP\n' > "$W/cache.txt"; h0="$(head_of)"
echo remote > "$S/cache.txt"; git -C "$S" add -f cache.txt; git -C "$S" commit -qm cache; git -C "$S" push -q origin ops
eq "$(git -C "$W" status --porcelain)" "" "⑤ⓑ 입력: status 빈 줄"
run
eq "$(head_of)" "$h0" "⑤ⓑ HEAD 그대로"; eq "$(cat "$W/cache.txt")" "LOCAL KEEP" "⑤ⓑ cache.txt 바이트 그대로"
eq "$(nl "$OUT")" 1 "⑤ⓑ 1줄"; has "$OUT" "뒤 1 · 앞 0 · 수정 0 · ff 실패" "⑤ⓑ 사유 «ff 실패»(앞 0 · 뒤 1)"

# ⑥ⓐ worktree 없음
mk c7; printf '{"_master": "m", "_cards": "cards", "_cards_wt": "nope"}\n' > "$X/.fable-team/seats-x.json"; run
eq "$(nl "$OUT")" 1 "⑥ⓐ worktree 없음 1줄"; has "$OUT" "worktree 없음" "⑥ⓐ 사유"
[ ! -e "$X/.worktrees/nope" ] && ok "⑥ⓐ 쓰기 0(폴더 안 만듦)" || bad "⑥ⓐ 폴더 생김"
# ⑥ⓑ 원격 가지 없음
mk c8; git -C "$W" checkout -q -b lonely; s0="$(snap)"; run
eq "$(nl "$OUT")" 1 "⑥ⓑ 원격 가지 없음 1줄"; has "$OUT" "원격 가지 없음" "⑥ⓑ 사유"
eq "$(snap)" "$s0" "⑥ⓑ 쓰기 0"
# ⑥ⓒ fetch rc≠0 (가짜 git)
mk c9; push_n 2; mkdir -p "$C/fake"; real="$(command -v git)"
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = fetch ] && { echo "fake: fetch refused" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$real" > "$C/fake/git"; chmod +x "$C/fake/git"
s0="$(snap)"; OUT="$(PATH="$C/fake:$PATH" bash "$SYNC" "$X" "$ST" 2>&1)"; RC=$?
eq "$(nl "$OUT")" 1 "⑥ⓒ fetch 실패 1줄"; has "$OUT" "판정 불가" "⑥ⓒ «판정 불가»"; has "$OUT" "fetch" "⑥ⓒ 사유 fetch"
[ "$RC" != 0 ] && ok "⑥ⓒ rc≠0 ($RC)" || bad "⑥ⓒ rc=0"
eq "$(snap)" "$s0" "⑥ⓒ 쓰기 0"

echo "SUMMARY fail=$fail"
[ "$fail" = 0 ]
