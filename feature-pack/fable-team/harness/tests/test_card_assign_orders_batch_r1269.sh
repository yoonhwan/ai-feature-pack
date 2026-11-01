#!/usr/bin/env bash
# test_card_assign_orders_batch_r1269.sh — r1269 status 가 inbox 발주문 본문을 «루트마다 git cat-file --batch 1회» 로 읽는다. 반례 R1~R5 + 변이 2(show 반복 · 빈 본문) + bin·kit 같음.
# 임시 git 리포(실 git · 가짜 git 0) · 실 STATE·실 좌석·실 쪽지 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0. 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_orders_batch_r1269.sh
[ -z "${R1269_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1269_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1269_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_card_assign_watch.py"; NOW=$(date +%s); TM=design/teams/a/indices; C="$TM/진행/c1.md"
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" GIT_TRACE="${TRACE:-0}" ${BUDGET:+FT_CARD_ASSIGN_STATUS_SEC=$BUDGET} python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
hd() { printf '%s\n' "$OUT" | head -1; }
same() { printf '%s\n' "$OUT" | sed -E 's/ · 판본 [^ ]+//'; }  # 판본(시각·해시)만 빼고 비교
order() {  # <역할> <파일명> <본문 줄...> — 발주문 1개(생성 시각은 age 인자: 마지막 커밋 때 정해진다)
  local d="$R/$TM/inbox/$1"; mkdir -p "$d"; local f="$2"; shift 2; printf '%s\n' "# 발주" "$@" > "$d/$f"
}
env_root() {  # <age 초> <발주문 수 m1> <m2> · 카드 c1 1장(원장 seat) + 발주문(m1 은 끝 3개가 미연결 꼴)
  local age="$1" n1="$2" n2="$3" i; R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign" "$R/design/teams/a/indices"
  mkdir -p "$R/design"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| a | design/teams/a/ | a | 현역 |\n' > "$R/design/TEAMS.md"
  printf '*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"; printf '{"_master":"byz-a-master-claude#1"}\n' > "$R/.fable-team/seats-a.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/bin/sh\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  mkdir -p "$R/$TM/진행"; printf '%s\n' "# c1" "- 상태: 진행" "## 상태" > "$R/$C"; printf '{"state":"seat","seat":"x"}\n' > "$R/.fable-team/state/card-assign/c1.json"
  for i in $(seq 1 "$n1"); do
    case $i in
      $((n1-2))) order m1 "$(printf %02d $i)-s1.md" "1. 빈 포인터" "   - 카드:";;
      $((n1-1))) order m1 "$(printf %02d $i)-s2.md" "1. 없는 경로" "   - 카드: $TM/진행/nope.md";;
      $n1) order m1 "$(printf %02d $i)-s3.md" "1. 긴급 항목 긴급" "   - 카드: $C";;
      *) order m1 "$(printf %02d $i)-n.md" "1. 항목 $i" "   - 카드: $C";;
    esac
  done
  for i in $(seq 1 "$n2"); do order m2 "$(printf %02d $i)-n.md" "1. 항목 $i" "   - 카드: $C"; done
  git -C "$R" add -A design; gc "$R" "$((NOW - age)) +0900" orders; run prepare >/dev/null
}
cat_n() { grep -Ec 'built-in: git cat-file' "$1"; }; show_n() { grep -Ec 'built-in: git show' "$1"; }
# R1·R2 발주문 120개(2시간 넘김) · 3개 미연결
env_root 90000 60 60; TRACE="$T/t1"; run status; unset TRACE; NEW="$(same)"; RC_NEW=$RC
[ "$(cat_n "$T/t1")" = 1 ] && [ "$(show_n "$T/t1")" = 0 ] && { [ "$RC_NEW" = 0 ] || [ "$RC_NEW" = 1 ]; } && ok "R1 발주문 120개 → cat-file 1회 · show 0회 · rc=$RC_NEW" || bad "R1 cat=$(cat_n "$T/t1") show=$(show_n "$T/t1") rc=$RC_NEW :: $(hd)"
r2="$(printf '%s\n' "$NEW" | grep -c '^발주 a ')"
printf '%s' "$NEW" | grep -q '58-s1#1 · 포인터 없음' && printf '%s' "$NEW" | grep -q '59-s2#1 · 없는 경로' && printf '%s' "$NEW" | grep -q '60-s3#1 · 카드 긴급 줄 없음' && [ "$r2" = 3 ] && printf '%s' "$NEW" | head -1 | grep -q '카드 없는 발주 3' && ok "R2 미연결 3꼴 = 발주 행 정확히 3개(빈 포인터 · 없는 경로 · 긴급 미표시)" || bad "R2 행=$r2 :: $NEW"
lap R1-R2
# R3 Git 예산 0.001초(env) → «판정 불가» 1줄 rc3 · cat-file 단계 예산 넘김 = 파이썬으로 직접 «git 상한 넘김(cat-file …)»
BUDGET=0.001 run status; unset BUDGET
[ "$RC" = 3 ] && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] && case "$OUT" in 배정\ 감시\ 판정\ 불가*) true;; *) false;; esac && ok "R3 예산 0.001초 → 판정 불가 1줄 rc3" || bad "R3 rc=$RC :: $OUT"
CAT="$(cd "$R" && FT_ROOT="$R" python3 - "$BIN" "$R" <<'PY' 2>&1
import sys, time
sys.path.insert(0, sys.argv[1])
from pathlib import Path
import ft_card_assign_watch as m
st = m.Status(Path(sys.argv[2]), time.time(), True)
st.git.end = time.monotonic() - 1
try:
    st.bodies(sys.argv[2], "HEAD", ["design/teams/a/indices/inbox/m1/01-n.md"])
    print("NO-RAISE")
except m.Undecided as e:
    print(e)
PY
)"
case "$CAT" in "git 상한 넘김(cat-file "*) ok "R3 cat-file 단계 예산 넘김 = «git 상한 넘김(cat-file …)»";; *) bad "R3 cat-file :: $CAT";; esac
lap R3
# R4 발주문 0개 · R5 2시간 안 새 발주문만 → cat-file 0 · show 0 (나이로 먼저 거른다)
env_root 90000 3 0; rm -rf "$R/$TM/inbox"; git -C "$R" add -A design; gc "$R" "$((NOW - 80000)) +0900" rm-orders; run prepare >/dev/null
TRACE="$T/t4"; run status; unset TRACE
[ "$(cat_n "$T/t4")" = 0 ] && [ "$(show_n "$T/t4")" = 0 ] && [ "$RC" = 0 ] && ok "R4 발주문 0개 → cat-file 0 · show 0 · rc0" || bad "R4 cat=$(cat_n "$T/t4") show=$(show_n "$T/t4") rc=$RC :: $(hd)"
env_root 60 5 5; TRACE="$T/t5"; run status; unset TRACE
[ "$(cat_n "$T/t5")" = 0 ] && [ "$(show_n "$T/t5")" = 0 ] && [ "$RC" = 0 ] && ok "R5 2시간 안 발주문만 → cat-file 0 · show 0 · rc0" || bad "R5 cat=$(cat_n "$T/t5") show=$(show_n "$T/t5") rc=$RC :: $(hd)"
lap R4-R5
# 변이 1 — batch 를 show 반복으로 되돌리면(= 옛 판) R1 빨강(show ≥100) 이고 배정 표는 새 판과 같은 줄 · 변이 2 — 빈 본문이면 R2 빨강
mutate() {  # <산출 경로> <삽입 return 줄>
  mkdir -p "$(dirname "$1")"; cp "$BIN"/ft_*.py "$(dirname "$1")/"
  python3 - "$TOOL" "$1" "$2" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); a = "        if not paths:\n            return {}\n"
assert a in s, a
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, a + sys.argv[3] + "\n", 1))
PY
}
mutate "$T/m1/ft_card_assign_watch.py" '        return {(repo, tip, x): subprocess.run(["git", "-C", repo, "show", f"{tip}:{x}"], capture_output=True, text=True).stdout for x in paths}'
env_root 90000 60 60; TRACE="$T/t6" TOOL_RUN="$T/m1/ft_card_assign_watch.py" run status; OLD="$(same)"
[ "$(show_n "$T/t6")" -ge 100 ] && [ "$(cat_n "$T/t6")" = 0 ] && ok "변이 1(show 반복) → R1 빨강(show $(show_n "$T/t6") · cat-file 0)" || bad "변이 1 이 R1 에 안 잡힘 show=$(show_n "$T/t6") cat=$(cat_n "$T/t6")"
[ "$OLD" = "$NEW" ] && ok "R1 배정 표 = 옛 방식(show 반복) 출력과 같은 줄" || bad "R1 출력 다름 :: $(diff <(printf '%s\n' "$OLD") <(printf '%s\n' "$NEW") | head -6)"
mutate "$T/m2/ft_card_assign_watch.py" '        return {(repo, tip, x): "" for x in paths}'
env_root 90000 60 60; TOOL_RUN="$T/m2/ft_card_assign_watch.py" run status; m2="$(printf '%s\n' "$OUT" | grep -c '^발주 a ')"
[ "$m2" -gt 3 ] && ok "변이 2(빈 본문) → R2 빨강(발주 행 $m2 ≠ 3)" || bad "변이 2 가 R2 에 안 잡힘 행=$m2"
lap mutation
for f in ft_card_assign_watch.py; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
