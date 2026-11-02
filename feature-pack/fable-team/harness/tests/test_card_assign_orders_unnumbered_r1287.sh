#!/usr/bin/env bash
# test_card_assign_orders_unnumbered_r1287.sh — r1287 번호 «1.» 항목이 없는 발주서는 본문 전체를 한 단위로 훑어 «- 카드:» 줄을 찾는다. 반례 R1~R5 + 변이 2 + bin·kit 같음.
# 임시 git 리포(실 git) · 실 STATE·실 좌석·실 쪽지 0 · 네트워크 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0. 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_orders_unnumbered_r1287.sh
[ -z "${R1287_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1287_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1287_TEST_ACTIVE=1
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
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
same() { printf '%s\n' "$OUT" | sed -E 's/ · 판본 [^ ]+//'; }  # 판본(시각·해시)만 빼고 비교
row() { printf '%s\n' "$OUT" | grep -F "$1" | head -1; }
put() { printf '%s' "$2" > "$R/$TM/inbox/m1/$1"; }  # <파일명> <본문 그대로(개행 포함)>
env_root() {  # 카드 c1 1장(원장 seat) + 발주문 폴더 m1 비움 · 발주문은 호출쪽이 put 으로 채우고 mk_commit 으로 2시간 넘긴 커밋을 만든다
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  mkdir -p "$R/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| a | design/teams/a/ | a | 현역 |\n' > "$R/design/TEAMS.md"  # r1298: 팀 명단 없으면 판정 불가(rc3)
  printf '*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"; printf '{"_master":"byz-a-master-claude#1"}\n' > "$R/.fable-team/seats-a.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/bin/sh\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  mkdir -p "$R/$TM/진행" "$R/$TM/inbox/m1"; printf '%s\n' "# c1" "- 상태: 진행" "## 상태" > "$R/$C"; printf '{"state":"seat","seat":"x"}\n' > "$R/.fable-team/state/card-assign/c1.json"
}
mk_commit() { git -C "$R" add -A design; gc "$R" "$((NOW - 90000)) +0900" orders; run prepare >/dev/null; }
fill_nonum() {  # 번호 없는 발주서 5벌(R1~R4 + 빈 파일)
  put 01-nonum-ok.md "$(printf '%s\n' '# 발주' '본문 설명' "- 카드: $C")"
  put 02-nonum-none.md "$(printf '%s\n' '# 발주' '본문 설명만 있고 카드 줄 없음')"
  put 03-nonum-missing.md "$(printf '%s\n' '# 발주' '본문 설명' "- 카드: $TM/진행/nope.md")"
  put 04-nonum-hot.md "$(printf '\n%s\n%s\n' '[긴급] 머리 줄이 첫 줄이 아닌 본문' "- 카드: $C")"
  put 05-empty.md ""
}
fill_num() {  # 번호 있는 발주서 2벌(항목마다 카드 · 한 벌은 항목 하나가 포인터 없음)
  put 06-num-ok.md "$(printf '%s\n' '# 발주' '1. 항목 가' "   - 카드: $C" '2. 항목 나' "   - 카드: $C")"
  put 07-num-bad.md "$(printf '%s\n' '# 발주' '1. 항목 가' "   - 카드: $C" '2. 항목 나 긴급' '   - 카드:')"
}
# R1~R4 번호 없는 발주서 5벌
env_root; fill_nonum; mk_commit; run status; NEW="$(same)"; RC_NEW=$RC
printf '%s' "$NEW" | grep -q '01-nonum-ok#' && bad "R1 번호 없음 + 본문 «- 카드:» 있는 경로 → 경보 0 이어야 함 :: $(row 01-nonum-ok)" || ok "R1 번호 없음 + 카드 줄 있는 경로 → 경보 0"
[ -n "$(row '02-nonum-none#1 · 포인터 없음')" ] && ok "R2 번호 없음 + 카드 줄 없음 → 포인터 없음" || bad "R2 :: $NEW"
[ -n "$(row '05-empty#1 · 포인터 없음')" ] && ok "R2b 빈 본문 → 포인터 없음 그대로(조용한 통과 0)" || bad "R2b :: $NEW"
[ -n "$(row '03-nonum-missing#1 · 없는 경로')" ] && ok "R3 번호 없음 + 없는 경로 → 없는 경로" || bad "R3 :: $NEW"
r4="$(row '04-nonum-hot#1 · 카드 긴급 줄 없음')"
case "$r4" in *" · 긴급") ok "R4 번호 없음 + 본문 머리 [긴급] + 카드 긴급 줄 없음 → 카드 긴급 줄 없음 · 긴급";; *) bad "R4 :: $r4 :: $NEW";; esac
printf '%s' "$NEW" | head -1 | grep -q '카드 없는 발주 4' && [ "$RC_NEW" = 1 ] && ok "R1~R4 머리 «카드 없는 발주 4» rc=1" || bad "머리 rc=$RC_NEW :: $(printf '%s' "$NEW" | head -1)"
lap R1-R4
# R5 번호 있는 발주서 — 지금(옛 판 = 변이 1 꼴)과 같은 출력(diff 0)
mutate() {  # <산출 경로> <원 줄> <바꿀 줄>
  mkdir -p "$(dirname "$1")"; cp "$BIN"/ft_*.py "$(dirname "$1")/"
  python3 - "$TOOL" "$1" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); a = sys.argv[3]
assert a in s, a
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, sys.argv[4], 1))
PY
}
SUB1='items or [lines if any(x.strip() for x in lines) else [path]]'; SUB2='next((x for x in it if x.strip()), "")'
mutate "$T/m1/ft_card_assign_watch.py" "$SUB1" 'items or [[path]]'
mutate "$T/m2/ft_card_assign_watch.py" "$SUB2" 'it[0]'
env_root; fill_num; mk_commit; run status; NUMNEW="$(same)"; RCNEW=$RC
TOOL_RUN="$T/m1/ft_card_assign_watch.py" run status; NUMOLD="$(same)"; unset TOOL_RUN
[ "$NUMNEW" = "$NUMOLD" ] && printf '%s' "$NUMNEW" | head -1 | grep -q '카드 없는 발주 1' && [ "$(printf '%s\n' "$NUMNEW" | grep -c '^발주 a ')" = 1 ] && printf '%s' "$NUMNEW" | grep -q '07-num-bad#2 · 포인터 없음' && ok "R5 번호 있음 → 옛 판과 출력 diff 0 (발주 1행 · 항목 #2 · rc=$RCNEW)" || bad "R5 :: $(diff <(printf '%s\n' "$NUMOLD") <(printf '%s\n' "$NUMNEW") | head -6) :: $NUMNEW"
lap R5
# 변이 1 대체값을 [path] 로 되돌림 → R1 FAIL · 변이 2 hot 을 단위 첫 줄(it[0])로 → R4 FAIL
env_root; fill_nonum; mk_commit; TOOL_RUN="$T/m1/ft_card_assign_watch.py" run status; unset TOOL_RUN; M1="$(same)"
printf '%s' "$M1" | grep -q '01-nonum-ok#1 · 포인터 없음' && ok "변이 1([path] 되돌림) → R1 빨강(01-nonum-ok 가 포인터 없음으로 셈)" || bad "변이 1 이 R1 에 안 잡힘 :: $M1"
TOOL_RUN="$T/m2/ft_card_assign_watch.py" run status; unset TOOL_RUN; M2="$(same)"
case "$(printf '%s\n' "$M2" | grep -F '04-nonum-hot#1 · 카드 긴급 줄 없음' | head -1)" in *" · 긴급") bad "변이 2 가 R4 에 안 잡힘 :: $M2";; *) ok "변이 2(hot = it[0]) → R4 빨강(머리가 첫 줄이 아니라 긴급 행 자체가 사라짐)";; esac
lap mutation
for f in ft_card_assign_watch.py; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
