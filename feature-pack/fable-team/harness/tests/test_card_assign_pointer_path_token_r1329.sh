#!/usr/bin/env bash
# test_card_assign_pointer_path_token_r1329.sh — r1329 발주서 «- 카드:» 줄 꼬리(백틱·괄호 주석·«— 설명»)에서 첫 design/….md 토큰만 경로로 대조한다. 반례 P1~P7 + 변이 W1~W3 + bin·kit 같음.
# 임시 git 리포(실 git) · 실 STATE·실 좌석·실 쪽지 0 · 네트워크 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0 · cwd=/ 에서 부른다. 돌리기: ulimit -u <지금+여유>; cd / && timeout 70 bash <이 파일>
# 기준판 확인: R1329_TOOL=<옛 ft_card_assign_watch.py> 를 주면 그 판으로 P1~P7 을 돈다(P1·P2·P3·P7 이 FAIL 이어야 한다) — 옛 판 옆에 ft_*.py 형제 모듈이 있어야 한다.
[ -z "${R1329_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1329_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1329_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="${R1329_TOOL:-$BIN/ft_card_assign_watch.py}"; NOW=$(date +%s); TM=design/teams/a/indices
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
run() { OUT="$(cd / && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
same() { printf '%s\n' "$OUT" | sed -E 's/ · 판본 [^ ]+//'; }  # 판본(시각·해시)만 빼고 비교
row() { printf '%s\n' "$OUT" | grep -F "$1" | head -1; }
put() { printf '%s' "$2" > "$R/$TM/inbox/m1/$1"; }  # <파일명> <본문 그대로(개행 포함)>
card() { printf '%s\n' "# $2" "- 상태: 진행" ${3:+"$3"} "## 상태" > "$R/$TM/$1/$2.md"; printf '{"state":"seat","seat":"x"}\n' > "$R/.fable-team/state/card-assign/$2.json"; }  # <폴더> <이름> [추가 줄]
env_root() {  # 카드 4장(x 진행 · w 대기 · y 진행+긴급 예 · z 진행) 전부 원장 seat + 발주문 폴더 m1 비움
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  mkdir -p "$R/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| a | design/teams/a/ | a | 현역 |\n' > "$R/design/TEAMS.md"
  printf '*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"; printf '{"_master":"byz-a-master-claude#1"}\n' > "$R/.fable-team/seats-a.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/bin/sh\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  mkdir -p "$R/$TM/대기" "$R/$TM/진행" "$R/$TM/inbox/m1"
  card 진행 x; card 대기 w; card 진행 y '- 긴급: 예'; card 진행 z
}
mk_commit() { git -C "$R" add -A design; gc "$R" "$((NOW - 90000)) +0900" orders; run prepare >/dev/null; }
fill() {  # 발주서 8벌 — P1~P7 (P7 은 카드 y/z 두 벌)
  put 01-p1.md "$(printf '%s\n' '# 발주' "- 카드: \`$TM/진행/x.md\` (주석 · \`docs/가지\`)")"
  put 02-p2.md "$(printf '%s\n' '# 발주' "- 카드: $TM/진행/x.md(가지 \`docs/b\`)")"
  put 03-p3.md "$(printf '%s\n' '# 발주' "- 카드: $TM/대기/w.md — 설명 …")"
  put 04-p4.md "$(printf '%s\n' '# 발주' '- 카드: `x.md` (설명)')"
  put 05-p5.md "$(printf '%s\n' '# 발주' "- 카드: \`$TM/진행/없는카드.md\`")"
  put 06-p6.md "$(printf '%s\n' '# 발주' '- 카드:')"
  put 07-p7y.md "$(printf '%s\n' '[긴급] 머리' "- 카드: \`$TM/진행/y.md\` (주석)")"
  put 08-p7z.md "$(printf '%s\n' '[긴급] 머리' "- 카드: \`$TM/진행/z.md\` (주석)")"
}
mutate() {  # <산출 폴더> <원 줄> <바꿀 줄> [<원 줄> <바꿀 줄>…] — 형제 모듈까지 통째 복사 후 줄 바꾸기
  local dir="$1"; shift; mkdir -p "$dir"; cp "$BIN"/ft_*.py "$dir/"
  python3 - "$BIN/ft_card_assign_watch.py" "$dir/ft_card_assign_watch.py" "$@" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); a = sys.argv[3:]
for i in range(0, len(a), 2):
    assert a[i] in s, a[i]
    s = s.replace(a[i], a[i + 1], 1)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
}
chk() {  # P1~P7 판정 — $OUT 은 status 출력
  [ -z "$(row '01-p1#')" ] && ok "P1 백틱+괄호 주석 · 카드 있음 → 경보 0" || bad "P1 :: $(row 01-p1#)"
  [ -z "$(row '02-p2#')" ] && ok "P2 경로(가지 …) 붙은 괄호 · 카드 있음 → 경보 0" || bad "P2 :: $(row 02-p2#)"
  [ -z "$(row '03-p3#')" ] && ok "P3 «— 설명» 꼬리 · 대기 카드 있음 → 경보 0" || bad "P3 :: $(row 03-p3#)"
  [ -n "$(row '04-p4#1 · 없는 경로')" ] && ok "P4 경로 토큰 없음 → 없는 경로(지금과 같음)" || bad "P4 :: $(row 04-p4#)"
  [ -n "$(row '05-p5#1 · 없는 경로')" ] && ok "P5 토큰은 있으나 없는 카드 → 없는 경로" || bad "P5 :: $(row 05-p5#)"
  [ -n "$(row '06-p6#1 · 포인터 없음')" ] && ok "P6 빈 값 → 포인터 없음" || bad "P6 :: $(row 06-p6#)"
  [ -z "$(row '07-p7y#')" ] && ok "P7a [긴급] + 토큰 카드에 «- 긴급: 예» → 경보 0" || bad "P7a :: $(row 07-p7y#)"
  case "$(row '08-p7z#1 · 카드 긴급 줄 없음')" in *" · 긴급") ok "P7b [긴급] + 카드에 긴급 줄 없음 → 카드 긴급 줄 없음 · 긴급";; *) bad "P7b :: $(row 08-p7z#)";; esac
  printf '%s' "$OUT" | head -1 | grep -q '카드 없는 발주 4 ' && [ "$RC" = 1 ] && ok "머리 «카드 없는 발주 4» rc=1" || bad "머리 rc=$RC :: $(printf '%s' "$OUT" | head -1)"
}
env_root; fill; mk_commit; run status; chk
lap P1-P7
# 변이 W1 추출 삭제 → P1·P2·P3·P7a FAIL · W2 토큰 없으면 빈 값 → P4 FAIL · W3 긴급 대조만 꼬리 전체 → P7a FAIL
EXT='ptr = (CARD_PATH.search(ptr) or [ptr])[0]'; URG='hot and ptr not in urgent_paths'
mutate "$T/w1" "$EXT" 'ptr = ptr'
mutate "$T/w2" "$EXT" 'ptr = (CARD_PATH.search(ptr) or [""])[0]'
mutate "$T/w3" "$EXT" "tail = ptr; $EXT" "$URG" 'hot and tail not in urgent_paths'
env_root; fill; mk_commit
TOOL_RUN="$T/w1/ft_card_assign_watch.py" run status; unset TOOL_RUN
{ [ -n "$(row '01-p1#')" ] && [ -n "$(row '02-p2#')" ] && [ -n "$(row '03-p3#')" ] && [ -n "$(row '07-p7y#')" ]; } && ok "W1(추출 삭제) → P1·P2·P3·P7a 빨강" || bad "W1 이 안 잡힘 :: $OUT"
TOOL_RUN="$T/w2/ft_card_assign_watch.py" run status; unset TOOL_RUN
[ -n "$(row '04-p4#1 · 포인터 없음')" ] && [ -z "$(row '04-p4#1 · 없는 경로')" ] && ok "W2(토큰 없음 → 빈 값) → P4 빨강" || bad "W2 가 안 잡힘 :: $(row 04-p4#)"
TOOL_RUN="$T/w3/ft_card_assign_watch.py" run status; unset TOOL_RUN
[ -n "$(row '07-p7y#')" ] && ok "W3(긴급 대조를 꼬리 전체로) → P7a 빨강" || bad "W3 이 안 잡힘 :: $OUT"
lap mutation
for f in ft_card_assign_watch.py; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
