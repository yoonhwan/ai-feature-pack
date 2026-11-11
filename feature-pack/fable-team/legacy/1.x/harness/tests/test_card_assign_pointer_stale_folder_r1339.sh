#!/usr/bin/env bash
# test_card_assign_pointer_stale_folder_r1339.sh — r1339: 발주서 «- 카드:» 토큰이 카드 경로 집합에 없을 때,
#   같은 팀 카드 칸에 «같은 파일 이름» 이 있으면 칸 이름만 낡은 포인터로 본다 —
#   열린 칸(대기·진행)이면 연결(행 0) · 닫힌 칸(완성·아카이브/*)에만 있으면 사유 «닫힌 카드»(«카드 없는 발주» 수에서 빼고 머리에 «닫힌 카드 발주 N») · 어디에도 없으면 «없는 경로» · 다른 팀 칸은 보지 않는다.
# 반례 S1~S5 · 변이 3 · 기준판 = 고정 sha(HEAD 금지 — r1341 사고) · 임시 git 리포 · 실 STATE·실 좌석·실 쪽지 0 · 네트워크 0 · cwd = /
[ -z "${R1339_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1339_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1339_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"; REPO="$HERE/../.."
BASE_SHA=0241f6f4   # 기준판 = 고치기 전 판(origin/main · r1339 착수 시점) · HEAD 를 쓰면 커밋 뒤 고친 판이 기준판이 된다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_card_assign_watch.py"; NOW=$(date +%s)
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
run() { OUT="$(cd / && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
row() { printf '%s\n' "$OUT" | grep -F "$1" | head -1; }
card() {  # card <팀> <칸…경로> <이름> — 카드 파일 + 원장(열린 칸만 원장 필요)
  local p="$R/design/teams/$1/indices/$2"; mkdir -p "$p"
  printf '%s\n' "# $3" "- 상태: 진행" "## 상태" > "$p/$3.md"
}
mkstate() { printf '{"state":"seat","seat":"x"}\n' > "$R/.fable-team/state/card-assign/$1.json"; }
env_root() {
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  mkdir -p "$R/design"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| a | design/teams/a/ | a | 현역 |\n| b | design/teams/b/ | b | 현역 |\n' > "$R/design/TEAMS.md"
  printf '*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"
  printf '{"_master":"byz-a-master-claude#1"}\n' > "$R/.fable-team/seats-a.json"; printf '{"_master":"byz-b-master-claude#1"}\n' > "$R/.fable-team/seats-b.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\necho "QUEUED seq=1 to=$2"\n' "$R/mbox.log" > "$R/mbox.sh"
  mkdir -p "$R/design/teams/a/indices/inbox/m1" "$R/design/teams/b/indices/inbox/m1"
  card a 대기 s1; mkstate s1          # S1 = 열린 칸에 같은 이름(칸 이름만 낡음)
  card a 완성 s2                      # S2 = 닫힌 칸(완성)
  card a 아카이브/2026-10 s3           # S3 = 닫힌 칸(아카이브/*)
  card b 대기 s5; mkstate s5          # S5 = «다른 팀» 열린 칸에만 같은 이름
}
put() { printf '%s\n' "$2" > "$R/design/teams/a/indices/inbox/m1/$1"; }
fill() {  # 발주서 5벌 — 포인터 칸 이름만 낡음
  put 01-s1.md "- 카드: design/teams/a/indices/진행/s1.md"
  put 02-s2.md "- 카드: design/teams/a/indices/진행/s2.md"
  put 03-s3.md "- 카드: design/teams/a/indices/진행/s3.md"
  put 04-s4.md "- 카드: design/teams/a/indices/진행/s4.md"
  put 05-s5.md "- 카드: design/teams/a/indices/진행/s5.md"
}
mk_commit() { git -C "$R" add -A design; gc "$R" "$((NOW - 90000)) +0900" orders; run prepare >/dev/null; }
mutate() {  # mutate <산출 폴더> <원 줄> <바꿀 줄>
  local dir="$1"; mkdir -p "$dir"; cp "$BIN"/ft_*.py "$dir"/
  python3 - "$BIN/ft_card_assign_watch.py" "$dir/ft_card_assign_watch.py" "$2" "$3" <<'PY' || { echo "FAIL 변이 — 자리 못 찾음"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
a, b = sys.argv[3:5]
assert s.count(a) == 1, s.count(a)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, b))
PY
}
# 기준판 = 고정 sha 사본(형제 ft_*.py 필요)
mkdir -p "$T/base"; cp "$BIN"/ft_*.py "$T/base"/
( cd "$REPO" && git show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/ft_card_assign_watch.py" ) > "$T/base/ft_card_assign_watch.py" \
  && ok "기준판 사본 = $BASE_SHA 판" || bad "기준판 사본"

env_root; fill; mk_commit; run status
ck() { [ "$2" = 0 ] && ok "$1" || bad "$1 :: $(row "${3:-}")"; }
[ -z "$(row '01-s1#')" ]; ck "S1 열린 칸(대기)에 같은 이름 → 경보 0(연결)" $?
[ -n "$(row '02-s2#1 · 닫힌 카드')" ]; ck "S2 닫힌 칸(완성) → «닫힌 카드»" $?
[ -n "$(row '03-s3#1 · 닫힌 카드')" ]; ck "S3 닫힌 칸(아카이브/*) → «닫힌 카드»" $?
[ -n "$(row '04-s4#1 · 없는 경로')" ]; ck "S4 어디에도 없음 → «없는 경로» 그대로" $?
[ -n "$(row '05-s5#1 · 없는 경로')" ]; ck "S5 다른 팀 칸에만 있음 → «없는 경로»(A5)" $?
head1="$(printf '%s\n' "$OUT" | head -1)"   # 카드 없는 발주 = S4·S5(2) · 닫힌 카드 발주 = S2·S3(2)
{ printf '%s' "$head1" | grep -q '카드 없는 발주 2 ' && printf '%s' "$head1" | grep -q '닫힌 카드 발주 2'; }; ck "머리 «카드 없는 발주 2 · 닫힌 카드 발주 2» :: $head1" $?
lap 새 판
# 기준판(sha 고정) — S1·S2·S3 이 «없는 경로» 로 나와야 한다(새 시험이 기준판을 가른다)
TOOL_RUN="$T/base/ft_card_assign_watch.py" run status; unset TOOL_RUN
{ [ -n "$(row '01-s1#1 · 없는 경로')" ] && [ -n "$(row '02-s2#1 · 없는 경로')" ] && [ -n "$(row '03-s3#1 · 없는 경로')" ] && ! printf '%s' "$OUT" | head -1 | grep -q '닫힌 카드 발주'; } \
  && ok "기준판($BASE_SHA) → S1·S2·S3 «없는 경로»(고칠 자리 확인)" || bad "기준판 :: $OUT"
lap 기준판
# S6 — 닫힌 카드 포인터만 있는 판 = 화면 줄 1 + rc0 · tick 0통 · stamps K 0 (DA/arch #4013)
R2R="$(mktemp -d "$T/c.XXXXXX")"; R="$R2R"; mkdir -p "$R/.fable-team/state/card-assign"
git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
mkdir -p "$R/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| a | design/teams/a/ | a | 현역 |\n' > "$R/design/TEAMS.md"
printf '*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"; printf '{"_master":"byz-a-master-claude#1"}\n' > "$R/.fable-team/seats-a.json"; printf '{}\n' > "$R/.fable-team/seats.json"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\necho "QUEUED seq=1 to=$2"\n' "$R/mbox.log" > "$R/mbox.sh"
mkdir -p "$R/design/teams/a/indices/inbox/m1"; card a 완성 c6
printf '%s\n' "- 카드: design/teams/a/indices/진행/c6.md" > "$R/design/teams/a/indices/inbox/m1/01-c6.md"
git -C "$R" add -A design; gc "$R" "$((NOW - 90000)) +0900" orders; run prepare >/dev/null
run status; head6="$(printf '%s\n' "$OUT" | head -1)"
{ [ "$RC" = 0 ] && printf '%s' "$head6" | grep -q '카드 없는 발주 0 · 닫힌 카드 발주 1' && [ -n "$(row '01-c6#1 · 닫힌 카드')" ]; } \
  && ok "S6 닫힌 카드만 = 화면 줄 1 · rc=0" || bad "S6 rc=$RC :: $head6"
run tick; n6=0; [ ! -f "$R/mbox.log" ] || n6="$(grep -c . "$R/mbox.log")"
[ "$n6" = 0 ] && ok "S6 tick 0통(닫힌 카드는 경보 아님)" || bad "S6 tick ${n6}통 :: $(cat "$R/mbox.log" 2>/dev/null)"
k6="$(awk -F'\t' 'END{print $4}' "$R/.fable-team/state/card-assign/stamps.tsv" 2>/dev/null)"
[ "$k6" = 0 ] && ok "S6 stamps K 0" || bad "S6 stamps K=${k6}"

# 변이 — 사본에서만
mutate "$T/m1" '                if (team, name) in open_by:   # A2 · A5(같은 팀 · 열린 칸이면 어느 쪽이든 연결)' '                if False and (team, name) in open_by:'
env_root; fill; mk_commit; TOOL_RUN="$T/m1/ft_card_assign_watch.py" run status; unset TOOL_RUN
[ -n "$(row '01-s1#1 · 없는 경로')" ] && ok "변이 1 A2 제거 → S1 빨강" || bad "변이 1 :: $(row '01-s1#')"
mutate "$T/m2" '                    why = "닫힌 카드"          # A3' '                    real = closed_by[(team, name)]   # 변이 = 닫힌 칸도 연결로'
env_root; fill; mk_commit; TOOL_RUN="$T/m2/ft_card_assign_watch.py" run status; unset TOOL_RUN
[ -z "$(row '02-s2#')" ] && ok "변이 2 A3 를 연결로 → S2 빨강" || bad "변이 2 :: $(row '02-s2#')"
mutate "$T/m3" '                if (team, name) in open_by:   # A2 · A5(같은 팀 · 열린 칸이면 어느 쪽이든 연결)
                    ptr = open_by[(team, name)]   # 긴급 대조는 이 «실제 경로» 로(A4)' '                if name in {k[1] for k in open_by}:   # 변이 = 팀 제한 제거
                    ptr = next(v for k, v in open_by.items() if k[1] == name)'
env_root; fill; mk_commit; TOOL_RUN="$T/m3/ft_card_assign_watch.py" run status; unset TOOL_RUN
[ -z "$(row '05-s5#')" ] && ok "변이 3 팀 제한 제거 → S5 빨강" || bad "변이 3 :: $(row '05-s5#')"
lap 변이
mutate "$T/m4" '    return x.get("kind") == "발주" and x.get("reason") == "닫힌 카드"' '    return False   # 변이 = 닫힌 카드 제외 끔'
R="$R2R"; TOOL_RUN="$T/m4/ft_card_assign_watch.py" run status; unset TOOL_RUN
[ "$RC" = 1 ] && ok "변이 4 닫힌 카드 제외 제거 → S6 빨강(rc=1)" || bad "변이 4 :: rc=$RC"
cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit 같은 내용" || bad "bin·kit 다름"
[ "$(stat -f %Lp "$HERE/test_card_assign_pointer_stale_folder_r1339.sh")" = 644 ] && ok "새 시험 파일 모드 644" || bad "새 시험 파일 모드"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
