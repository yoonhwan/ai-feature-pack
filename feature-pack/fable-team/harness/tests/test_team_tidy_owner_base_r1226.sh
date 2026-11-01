#!/usr/bin/env bash
# test_team_tidy_owner_base_r1226.sh — r1226: ft-team-tidy 사본 주인 집합에 «명부 행이 지워진 나노»(state/nano-card-base)를 더한다. 반례 R1~R4 + 변이 1.
# 전부 mktemp — 임시 저장소·명부·장부·가짜 tmux·가짜 ft-card-flow/ft-index-move/ft-seat-close(호출 기록). ft-scratch-repo 는 기록 뒤 실물. 실 좌석·실 STATE·자기 재호출 0.
# 픽스처 nano-card-base 5개: design/<팀>/indices 정확 1 · design/teams/<팀>/indices 정확 1 · design/teams/<팀>-extra/indices 1 · card_path 없음 1 · JSON 아님 1
#   (카드의 4번째 칸이 «card_path 없음·JSON 아님» 두 갈래라 파일 2개로 나눴다 — R3 이 두 갈래를 다 본다.)
# 돌리는 법: ulimit -u <지금 사용자 프로세스 수 + 여유>; timeout 70 bash 이 파일
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR FT_FINISHED_MAIN FT_SCRATCH_OWNER FT_RES_ROOT FT_TIDY_CARD_FLOW FT_TIDY_INDEX_MOVE FT_TIDY_SEAT_CLOSE FT_TIDY_SCRATCH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
for f in ft-team-tidy.sh; do
  bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"
done
LINES="$(wc -l < "$BIN/ft-team-tidy.sh")"; [ "$LINES" -le 200 ] && ok "ft-team-tidy.sh ${LINES}줄 ≤ 200" || bad "ft-team-tidy.sh ${LINES}줄 > 200"

FAKE="$T/fake"; LOGD="$T/log"; mkdir -p "$FAKE" "$LOGD"
cat > "$FAKE/tmux" <<EOF
#!/bin/sh
case "\$1" in ls|list-sessions) cat "$T/sessions.txt";; *) exit 1;; esac
EOF
for x in cf im sc; do printf '#!/bin/sh\necho "STUB %s $*" >> "%s/%s.calls"\necho "STUB ok"\n' "$x" "$LOGD" "$x" > "$FAKE/$x.sh"; done
cat > "$FAKE/sr.sh" <<EOF
#!/bin/bash
echo "\$* owner=\${FT_SCRATCH_OWNER-unset}" >> "$LOGD/sr.calls"
exec bash "$BIN/ft-scratch-repo.sh" "\$@"
EOF
chmod 755 "$FAKE"/*

NB=""; CD=""; R=""; SCR=""
mkfix() { # 임시 저장소 R(카드 폴더·명부·nano-card-base·장부) · 사본 자리 SCR
  rm -rf "$T/w" "$LOGD"; mkdir -p "$T/w" "$LOGD"; R="$T/w/repo"; SCR="$T/w/scr"; NB="$R/.fable-team/state/nano-card-base"
  git init -q -b main "$R"; G() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
  CD="$R/design/teams/tteam/indices"; mkdir -p "$CD"/{대기,진행,완성} "$NB" "$SCR/repo-live"
  echo x > "$R/f"; G add -A >/dev/null; G commit -q -m base
  printf '%s\n' '{"byz-tteam-master-claude#1":{"role":"master"}}' > "$R/.fable-team/seats-tteam.json"
  printf '%s\n' '{"name":"byz-tteam-nano-cardflip#0","card_path":"design/tteam/indices/진행/n1.md"}' > "$NB/byz-tteam-nano-cardflip#0.json"
  printf '%s\n' '{"name":"byz-tteam-nano-teams#0","card_path":"design/teams/tteam/indices/진행/n2.md"}' > "$NB/byz-tteam-nano-teams#0.json"
  printf '%s\n' '{"name":"byz-tteam-nano-extra#0","card_path":"design/teams/tteam-extra/indices/진행/n3.md"}' > "$NB/byz-tteam-nano-extra#0.json"
  printf '%s\n' '{"name":"byz-tteam-nano-nopath#0","branch":"nano/n1"}' > "$NB/byz-tteam-nano-nopath#0.json"
  printf 'not json {\n' > "$NB/byz-tteam-nano-broken#0.json"
  { printf '%s\tbyz-tteam-nano-cardflip#0\t1\n' "$SCR/repo-flip"; printf '%s\tbyz-tteam-nano-teams#0\t1\n' "$SCR/repo-teams"
    printf '%s\tbyz-tteam-nano-extra#0\t1\n' "$SCR/repo-extra"; printf '%s\tbyz-tteam-nano-nopath#0\t1\n' "$SCR/repo-nopath"
    printf '%s\tbyz-tteam-nano-broken#0\t1\n' "$SCR/repo-broken"; printf '%s\tbyz-tteam-master-claude#1\t1\n' "$SCR/repo-live"; } > "$R/.fable-team/state/scratch-repos.tsv"
  printf '%s\n' byz-tteam-master-claude#1 > "$T/sessions.txt"
}
tidy() { OUT="$(cd "$R" && env -u FT_SCRATCH_OWNER PATH="$FAKE:$PATH" FT_TIDY_CARD_FLOW="$FAKE/cf.sh" FT_TIDY_INDEX_MOVE="$FAKE/im.sh" FT_TIDY_SEAT_CLOSE="$FAKE/sc.sh" \
  FT_TIDY_SCRATCH="$FAKE/sr.sh" FT_SCRATCH_DIR="$SCR" FT_BG_FINITE_LEDGER="$T/bg.tsv" bash "${TOOL:-$BIN/ft-team-tidy.sh}" --team tteam --root "$R" "$@" 2>&1)"; RC=$?; }
calls() { cat "$LOGD/$1.calls" 2>/dev/null; }
ncalls() { calls "$1" | awk 'END{print NR}'; }
row() { printf '%s\n' "$OUT" | grep "^| $1 |"; }
LEDGER() { printf '%s\n' "$(cat "$R/.fable-team/state/scratch-repos.tsv")"; }

# R1 — 보기만: 닫힌 나노 2명(정확 일치 2갈래)이 주인으로 잡혀 «경로 없음 후보» 목록에 오른다 · 쓰기 0
mkfix; TSV0="$(LEDGER)"; ROST0="$(cat "$R/.fable-team/seats-tteam.json")"; tidy
[ "$RC" = 0 ] && ok "R1 rc0" || bad "R1 rc=$RC ${OUT:0:400}"
[ "$(ncalls im)$(ncalls sc)$(ncalls sr)" = 000 ] && ok "R1 집행 도구 호출 0" || bad "R1 호출 있음 im=$(ncalls im) sc=$(ncalls sc) sr=$(ncalls sr)"
[ "$TSV0" = "$(LEDGER)" ] && ok "R1 장부 무변경" || bad "R1 장부 바뀜"
has "$OUT" "목록 사본 $SCR/repo-flip — 경로 없음(--prune-missing 후보)" "R1 design/<팀> 정확 일치 주인"
has "$OUT" "목록 사본 $SCR/repo-teams — 경로 없음(--prune-missing 후보)" "R1 design/teams/<팀> 정확 일치 주인"
hasnt "$OUT" "repo-extra" "R2 tteam-extra 는 목록에도 없음(접두 0)"
hasnt "$OUT" "repo-nopath" "R3 card_path 없는 기록은 주인 아님(목록 0)"
hasnt "$OUT" "repo-broken" "R3 못 읽는 기록은 주인 아님(목록 0)"
has "$(row 사본)" "장부 3 · 경로 없음 2" "R1 표 사본 전(주인 3 = 명부 1 + 닫힌 나노 2)"

# --apply 1회 → R1(집행) R2 R3
mkfix; tidy --apply
[ "$RC" = 0 ] && ok "R1 apply rc0" || bad "R1 apply rc=$RC ${OUT:0:600}"
L="$(LEDGER)"
hasnt "$L" "repo-flip" "R1 design/<팀> 정확 일치 나노의 경로 없는 줄 빠짐"
hasnt "$L" "repo-teams" "R1 design/teams/<팀> 정확 일치 나노의 경로 없는 줄 빠짐"
has "$L" "repo-extra" "R2 tteam-extra 줄 그대로(정리 대상 아님)"
has "$L" "repo-nopath" "R3 card_path 없는 기록의 줄 그대로"
has "$L" "repo-broken" "R3 못 읽는 기록의 줄 그대로"
has "$L" "repo-live" "R1 현역 줄 그대로"
has "$OUT" "집행 사본 $SCR/repo-flip rc=0" "R1 집행 줄"
r3w="$(printf '%s\n' "$OUT" | grep -c '^경고 사본 — ')"
[ "$r3w" = 2 ] && ok "R3 경고 2줄(card_path 없음 1 · 못 읽음 1)" || bad "R3 경고 $r3w 줄 «$(printf '%s\n' "$OUT" | grep '^경고')»"
has "$OUT" "card_path 없음 · 건너뜀" "R3 경고 원문(card_path 없음)"
has "$OUT" "기록 못 읽음" "R3 경고 원문(JSON 아님)"
has "$(row 사본)" "| 장부 1 · 경로 없음 0 · 주인 세션 없음 0 | 2 |" "R1 표 사본 후(집행 2)"
[ "$ROST0" = "$(cat "$R/.fable-team/seats-tteam.json")" ] && ok "명부 쓰기 0" || bad "명부 바뀜"
[ "$(ls "$NB" | wc -l | tr -d ' ')" = 5 ] && ok "nano-card-base 읽기만(파일 5 그대로)" || bad "nano-card-base 바뀜"

# R4 — r1223 회귀: 옛 시험 그대로 PASS(주인 집합 확장이 기존 세기·집행을 흔들지 않았다)
R4="$(cd "$HERE" && timeout 70 bash test_team_tidy_r1223.sh 2>&1)"; r4rc=$?
[ "$r4rc" = 0 ] && ok "R4 r1223 시험 rc0" || bad "R4 r1223 시험 rc=$r4rc"
has "$R4" "ALL PASS" "R4 r1223 ALL PASS"

# 변이 1 — 팀 칸 «정확 일치» 를 접두 일치로 바꾸면 R2 가 FAIL 로 잡아야 한다(도구 사본만 바꾼다 · 자기 파일 재호출 0)
MB="$T/mbin"; cp -R "$BIN" "$MB"
sed "s/p\[2\]==team and p\[3\]=='indices'/p[2].startswith(team) and p[3]=='indices'/" "$BIN/ft-team-tidy.sh" > "$MB/ft-team-tidy.sh"
mkfix; TOOL="$MB/ft-team-tidy.sh" tidy --apply
cmp -s "$BIN/ft-team-tidy.sh" "$MB/ft-team-tidy.sh" && bad "변이1 적용 안 됨" || { case "$(LEDGER)" in *repo-extra*) bad "변이1(접두 일치) 살아남음 — R2 못 잡음";; *) ok "변이1(접두 일치) R2 가 FAIL 로 잡음";; esac; }

rm -rf "$MB"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
