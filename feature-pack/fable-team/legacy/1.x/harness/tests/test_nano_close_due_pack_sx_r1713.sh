#!/usr/bin/env bash
# test_nano_close_due_pack_sx_r1713.sh — r1713: 나노 자동 닫기 목록(ft-nano-close-due.sh)이 ⓐ 팩에서 일한 나노를 «팩 최신 main» 으로 판정하고
#   ⓑ 카드 세트 S 가 착지 끝줄 head X 의 조상(S..X = main 병합뿐 · 자기 변경 patch-id 같음 · 공용 ft-landed-sx.sh = nano-close r1084 과 같은 판정)이면 squash 착지로 본다.
#   반례 ①~⑩(카드 «반례 집합» 그대로) · ⑪ = 기존 test_nano_close_landed_set_pre_merge_r1084.sh 재실행(이 파일 밖 · 70초 상한 때문에 따로 돈다)
#   변이 M1~M5 = bin 사본(같은 폴더 4파일)에서 한 곳만 바꾼다 · 변이마다 원본 BIN 으로 같은 사례 1회 더(반대 결과 대조) · 각 뒤 bin·kit cmp0
#   기준판 대조 = FT_CLOSE_DUE_UNDER_TEST=<팩 origin/main bin 사본>/ft-nano-close-due.sh 로 돌리면 ①·⑤ 가 FAIL 이어야 한다
#   임시 리포(팩 꼴·pane 꼴 각각 bare origin) + 가짜 tmux·ft-seat-status 만 쓴다 — 실 명부·실 팩·실 tmux 0 · sleep 0 · 70초 안
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
TOOL="${FT_CLOSE_DUE_UNDER_TEST:-$BIN/ft-nano-close-due.sh}"; LSX="$BIN/ft-landed-sx.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$(date +%s); TL=$T0; STEPS=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:500}";; *) ok "$3";; esac; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got=[$1] want=[$2])"; }
lap()  { local n; n=$(date +%s); STEPS="$STEPS $1=$((n-TL))s"; TL=$n; }
cmp0() { for f in ft-nano-close-due.sh ft-nano-close.sh ft-landed-sx.sh; do cmp -s "$BIN/$f" "$KIT/$f" || { bad "$1 cmp bin≠kit $f"; return; }; done; ok "$1 bin·kit cmp0(3파일)"; }

echo "== 짝 cmp · bash -n"
cmp0 "처음"
for f in ft-nano-close-due.sh ft-nano-close.sh ft-landed-sx.sh; do /bin/bash -n "$BIN/$f" && ok "/bin/bash 3.2 -n $f" || bad "bash -n $f"; done

FK="$T/fake"; mkdir -p "$FK"
printf '#!/usr/bin/env bash\ncase "$1" in list-sessions) echo "$FAKE_SEAT";; display-message) cat "$FAKE_CWD";; *) exit 9;; esac\n' > "$FK/tmux"
printf '#!/usr/bin/env bash\n[ "${1:-}" = turn ] && { echo "IDLE - - - jsonl"; exit 0; }\nexit 1\n' > "$FK/ss.sh"
chmod +x "$FK/tmux" "$FK/ss.sh"
SEAT="byz-harness-nano-sx#0"; export FAKE_SEAT="$SEAT"
NOX=1234567890abcdef1234567890abcdef12345678   # 어느 리포에도 없는 40hex

# ── 픽스처 — 사례마다 새 폴더: pane 리포 W · 팩 리포 P(각각 bare origin) · 데이터 루트 ROOT(카드·명부) ──
mkr() { git init -q --bare -b main "$1.git"; git init -q -b main "$1"; git -C "$1" remote add origin "$1.git"
  echo a > "$1/a"; git -C "$1" add a; git -C "$1" commit -qm M0; git -C "$1" push -q origin main 2>/dev/null; git -C "$1" fetch -q origin; }
wk() { printf '%s\n' "$3" > "$R/$1"; git -C "$R" add "$1"; git -C "$R" commit -qm "$2"; git -C "$R" rev-parse HEAD; }   # wk <파일> <메시지> <내용>
pubm() { git -C "$R" push -q --force origin "$1:refs/heads/main" 2>/dev/null; git -C "$R" update-ref refs/remotes/origin/main "$1"; }
adv() { local base blob tree; base="$(git -C "$R" rev-parse refs/remotes/origin/main)"   # 원격 main 에 다른 커밋 1개
  blob="$(printf '%s\n' "$1" | git -C "$R" hash-object -w --stdin)"
  GIT_INDEX_FILE="$C/idx" git -C "$R" read-tree "$base"; GIT_INDEX_FILE="$C/idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,$1"
  tree="$(GIT_INDEX_FILE="$C/idx" git -C "$R" write-tree)"; rm -f "$C/idx"; pubm "$(git -C "$R" commit-tree "$tree" -p "$base" -m "main $1")"; }
sq() { SQ="$(printf 'squash 착지\n\n%s\n' "$2" | git -C "$R" commit-tree "$(git -C "$R" rev-parse "$1^{tree}")" -p "$(git -C "$R" rev-parse refs/remotes/origin/main)")"; pubm "$SQ"; }   # sq <트리 커밋> <끝줄들>
card() { local s="$1"; shift; { printf '# 인덱스: sx\n## 상태\n- 세트: %s · 시험: bash x rc=0 · 이슈: 0\n' "$s"; [ $# -gt 0 ] && printf '%s\n' "$@"; } > "$ROOT/design/teams/harness/indices/진행/sx.md"; }
base_case() { C="$T/$1"; rm -rf "$C"; mkdir -p "$C"; W="$C/w"; P="$C/pack"; mkr "$W"; mkr "$P"; ROOT="$C/root"
  mkdir -p "$ROOT/design/teams/harness/indices/진행" "$ROOT/.fable-team/state"; printf '%s\n' "$W" > "$C/cwd"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |\n' > "$ROOT/design/TEAMS.md"
  printf '{"_master":"byz-harness-master-pi#1","%s":{"role":"nano","agent":"pi","cwd":"/nonexistent/bogus","index":"design/teams/harness/indices/진행/sx.md"}}\n' "$SEAT" > "$ROOT/.fable-team/seats-harness.json"; }
pack_S() { R="$P"; git -C "$P" checkout -q -b nano/sx; S="$(wk s.txt "work s" s1)"; }
merge_main() { git -C "$R" merge -q --no-ff -m "merge main" refs/remotes/origin/main; X="$(git -C "$R" rev-parse HEAD)"; }
sx_graph() { pack_S; adv g1.txt; merge_main; }   # S → main 병합 1 → X(끝줄 head) · 자기 변경 같음(r1672 꼴)
stale() { git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse main)"; }   # 로컬 remote-tracking 을 옛 판(M0)으로

mk1()  { base_case c1; pack_S; sq "$S" "PR #7 (head $S)"; card "$S"; stale; }   # ① 팩 착지가 remote 에만
mk2()  { mk1; git -C "$P" remote set-url origin "$C/없는리포.git"; }            # ② 팩 fetch 실패
mk3()  { base_case c3; R="$W"; git -C "$W" checkout -q -b nano/sx; S="$(wk s.txt "work s" s1)"; sq "$S" "PR #7 (head $S)"; card "$S"; stale; }   # ③ pane 세트 = 끝줄 head
mk4()  { base_case c4; R="$W"; git -C "$W" checkout -q -b nano/sx; S="$(wk s.txt "work s" s1)"
  sq "$S" "$(printf 'PR #7 (head %s)\nmain 자동 병합(코드 · 승인 EQUIV) C=%s' "$S" "$NOX")"; card "$S"; stale; }   # ④ EQUIV 꼬리
mk5()  { base_case c5; sx_graph; sq "$X" "PR #7 (head $X)"; card "$S"; }
mk6()  { base_case c6; pack_S; git -C "$P" commit -q --allow-empty -m "승인 뒤 일반 커밋(빈 · patch-id 그대로 = 일반 커밋 검사만 잡는다)"; adv g1.txt; merge_main; sq "$X" "PR #7 (head $X)"; card "$S"; }
mk7()  { base_case c7; pack_S; adv g1.txt; git -C "$P" merge -q --no-ff --no-commit refs/remotes/origin/main; printf 's2\n' > "$P/s.txt"; git -C "$P" add s.txt
  git -C "$P" commit -qm "merge main (손댐)"; X="$(git -C "$P" rev-parse HEAD)"; sq "$X" "PR #7 (head $X)"; card "$S"; }
mk8()  { base_case c8; pack_S; git -C "$P" checkout -q -b other main; Y="$(wk y.txt other y1)"; sq "$Y" "PR #7 (head $Y)"; card "$S"; }
mk9a() { base_case c9a; sx_graph; sq "$X" "PR #44 (head $X)"; card "$S" "- 착지: PR #4 squash"; }   # 접두 겹침 «PR #44» vs N=4
mk9b() { base_case c9b; sx_graph; sq "$X" "PR #7 (head $X) (cherry-picked)"; card "$S"; }
mk9c() { base_case c9c; sx_graph; sq "$X" "$(printf 'PR #7 (head %s)\n다른 꼬리 줄' "$X")"; card "$S"; }
mk10() { base_case c10; pack_S; sq "$S" "PR #7 (head $NOX)"; card "$S"; }   # 공용 판정 git 실패(X 가 리포에 없음)

due() { OUT="$(cd "$ROOT" && PATH="$FK:$PATH" FT_ROOT="$ROOT" FT_PACK_REPO="$P" FT_CLOSE_DUE_SEAT_STATUS="$FK/ss.sh" FAKE_CWD="$C/cwd" \
  FT_CLOSE_DUE_CURSOR="$C/cursor" bash "${1:-$TOOL}" --all --why 2>&1)"; RC=$?; }
is_sq() { case "$OUT" in *"닫기 차례 $SEAT 팀=harness "*"landed=squash"*) return 0;; esac; return 1; }
NONE="제외 $SEAT main 에 산출 없음(ff 0 · squash 끝줄 0)"
want_sq() { has "$OUT" "닫기 차례 $SEAT 팀=harness" "$1 닫기 차례 줄"; has "$OUT" "landed=squash" "$1 갈래 squash"; has "$OUT" "--landed-pr 7" "$1 PR 번호 7"; eq "$RC" 0 "$1 rc 0"; }
want_none() { has "$OUT" "$NONE" "$1 «산출 없음»"; hasnt "$OUT" "닫기 차례 $SEAT" "$1 닫기 차례 0"; eq "$RC" 0 "$1 rc 0"; }
lap 준비

echo "== ① in_pack · 착지가 팩 remote 에만(로컬 팩 ref 옛 판) → 팩 fetch 뒤 squash"
mk1; due; want_sq ①
echo "== ② in_pack · 팩 fetch 실패(remote URL 없는 경로) → 판정 불가 1줄 · 닫기 차례 0"
mk2; due; has "$OUT" "판정 불가 $SEAT git fetch origin main rc=" "② 판정 불가 «git fetch origin main rc=…»"
eq "$(printf '%s\n' "$OUT" | grep -c "^판정 불가 $SEAT")" 1 "② 판정 불가 1줄"; hasnt "$OUT" "닫기 차례" "② 닫기 차례 0"; eq "$RC" 3 "② rc 3"
echo "== ③ 세트 = 끝줄 head(정확 일치) → squash (회귀)"
mk3; due; want_sq ③
echo "== ④ EQUIV 꼬리 + PR 줄 + 정확 일치 → squash (회귀)"
mk4; due; want_sq ④
lap ①~④
echo "== ⑤ 세트 S ⊂ 끝줄 head X · main 병합 1 · patch-id 같음(r1672 꼴) → squash"
mk5; due; want_sq ⑤; has "$OUT" "main=$(git -C "$P" rev-parse --short "$SQ")" "⑤ main = 그 착지 커밋"
o="$(bash "$LSX" "$P" "$S" "$X" 2>&1)"; eq "$o / $?" "SX-OK merges=1 / 0" "⑤ 공용 판정 직접 = rc0 «SX-OK merges=1»"
echo "== ⑥ S..X 에 일반 커밋 1 → 산출 없음"
mk6; due; want_none ⑥
echo "== ⑦ 병합 해결로 자기 변경이 바뀜(patch-id 다름) → 산출 없음"
mk7; due; want_none ⑦
echo "== ⑧ S 가 어느 끝줄 head 의 조상도 아님 → 산출 없음"
mk8; due; want_none ⑧
echo "== ⑨ 끝줄 꼴 밖 3종 → 후보 0 · 산출 없음"
mk9a; due; want_none "⑨a «PR #44» vs 카드 N=4"
mk9b; due; want_none "⑨b 꼬리 붙은 줄"
mk9c; due; want_none "⑨c PR 줄이 가운데"
echo "== ⑩ 공용 판정 git 실패 → 판정 불가 1줄 · 통과 0"
mk10; due; has "$OUT" "판정 불가 $SEAT ft-landed-sx rc=2 판정 불가 ancestor rc=" "⑩ 판정 불가 «ft-landed-sx rc=2 … ancestor»"
hasnt "$OUT" "닫기 차례" "⑩ 닫기 차례 0"; eq "$RC" 3 "⑩ rc 3"
e="$(bash "$LSX" "$P" "$NOX" "$S" 2>&1 >/dev/null)"; r=$?; o="$(bash "$LSX" "$P" "$NOX" "$S" 2>/dev/null)"
eq "$r" 2 "⑩ 직접(S 가 팩에 없는 40hex) rc 2"; eq "$(printf '%s\n' "$e" | grep -c .)" 1 "⑩ 직접 stderr 1줄"; has "$e" "판정 불가 ancestor rc=" "⑩ 직접 문구"; eq "$o" "" "⑩ 직접 stdout 0"
lap ⑤~⑩

# ── 변이 — 사본 4파일(close-due · ft_team_lib · ft_nano_record* · ft-landed-sx)에서 한 곳만 · 원본 BIN 대조 ──
mutdir() { local M="$T/m-$1"; rm -rf "$M"; mkdir -p "$M"
  cp "$BIN/ft-nano-close-due.sh" "$BIN/ft_team_lib.py" "$BIN"/ft_nano_record*.py "$BIN/ft-landed-sx.sh" "$M/"
  python3 - "$M/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:60]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
killed() {   # killed <이름> <사례 mk> <변이에서 기대: sq|none>
  local nm="$1" mk="$2" want="$3" got
  "$mk"; due "$T/m-$nm/ft-nano-close-due.sh"; is_sq && got=sq || got=none
  [ "$got" = "$want" ] && ok "$nm 변이 → $mk 반대 결과($got) = 시험이 잡는다" || bad "$nm 변이 안 먹음($mk got=$got want=$want)"
  "$mk"; due; is_sq && got=sq || got=none
  [ "$got" != "$want" ] && ok "$nm 원본 BIN 대조 = $got" || bad "$nm 원본 대조 실패($got)"
  cmp0 "$nm 뒤"
}
mutdir M1 ft-nano-close-due.sh '        fetch_once(pkey, ptop)   # r1713-mut:packfetch' '        pass'
killed M1 mk1 none
mutdir M2 ft-nano-close-due.sh 'rc, _o, err = run(["bash", HERE + "/ft-landed-sx.sh"' 'rc, _o, err = (1, "", "") if 1 else run(["bash", HERE + "/ft-landed-sx.sh"'
killed M2 mk5 none
mutdir M3 ft-landed-sx.sh 'if out: sys.exit(1)' 'pass'
killed M3 mk6 sq
mutdir M4 ft-landed-sx.sh 'if not p1 or not p2 or p1 != p2: sys.exit(1)' 'pass'
killed M4 mk7 sq
mutdir M5 ft-nano-close-due.sh 'SX_TAIL.fullmatch(' 'SX_TAIL.search('
killed M5 mk9b sq
lap 변이

echo "단계별 초: 전체=$(( $(date +%s) - T0 ))s ·$STEPS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
