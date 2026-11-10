#!/usr/bin/env bash
# test_card_assign_status_grep_scope_r1251.sh — r1251 status 의 «- 긴급:»·«## » git grep 범위 = 루트 표 카드 폴더의 .md 만. 반례 R1~R5 + 변이 1(옛 base) + bin·kit 같음.
# 임시 git 리포(실 git · 가짜 git 0) · 실 STATE·실 좌석·실 쪽지 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0. 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_status_grep_scope_r1251.sh
[ -z "${R1251_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1251_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1251_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_REQUIRE_PREVERIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_card_assign_watch.py"; NOW=$(date +%s); H=design/harness/indices; TM=design/teams/a/indices
gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
card() {  # <상대경로> <머리 줄...> — 카드 .md 1장 + 커밋
  local p="$1"; shift; mkdir -p "$(dirname "$R/$p")"; printf '%s\n' "# 카드 $(basename "$p" .md)" "$@" "## 상태" "- 시험" > "$R/$p"; git -C "$R" add -A design; gc "$R" "$((NOW - 90000)) +0900" "card $p"
}
led() { mkdir -p "$R/.fable-team/state/card-assign"; printf '%s\n' "$2" > "$R/.fable-team/state/card-assign/$1.json"; }
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" GIT_TRACE="${TRACE:-0}" python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
hd() { printf '%s\n' "$OUT" | head -1; }
SEAT='{"state":"waiting","reason":"석","since":'$((NOW-7200))'}'  # 석 2시간 = 긴급(2시간 초과)만 초과로 잡힌다
env_root() {  # 루트 표(harness + 별표) · 카드: 팀 긴급 u1 · 팀 일반 n1 · 팀 절 안 긴급 s1 · harness 긴급 hu · evidence .md 200개(큰 파일) + 긴급 줄 든 증거 1개
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state"
  git -C "$R" init -q -b main; printf '.fable-team/\nmbox.sh\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000)) +0900" init
  printf 'harness\t.\tmain\t%s\n*\t.\tmain\tdesign/teams/*/indices\n' "$H" > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"byz-planner-master-claude#9"}\n' > "$R/.fable-team/seats-planner.json"; printf '{"_master":"byz-harness-master-claude#33"}\n' > "$R/.fable-team/seats-harness.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/bin/sh\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  card "$TM/진행/u1.md" "- 상태: 진행" "- 긴급: 예"; card "$TM/진행/n1.md" "- 상태: 진행"; card "$H/대기/hu.md" "- 상태: 대기" "- 긴급: 예"
  mkdir -p "$R/design/teams/a/evidence"; for i in $(seq 1 200); do yes '증거 한 줄 — 큰 파일 시험' | head -60 > "$R/design/teams/a/evidence/big$i.md"; done
  printf '%s\n' '# 증거' '- 긴급: 예' > "$R/design/teams/a/evidence/urgent-ev.md"
  printf '%s\n' '# s1' '## 절' '- 긴급: 예' '## 상태' > "$R/$TM/진행/s1.md"; git -C "$R" add -A design; gc "$R" "$((NOW - 90000)) +0900" evidence
  for c in u1 n1 s1; do led "$c" "$SEAT"; done; led hu "$SEAT"; led urgent-ev "$SEAT"; run prepare >/dev/null
}
env_root; TRACE="$T/trace1"; run status; unset TRACE
grep_line="$(grep -F 'git grep' "$T/trace1" | head -1)"
# R1 팀 폴더 카드 «- 긴급: 예» → 긴급으로 잡힘 · 일반 카드는 안 잡힘
printf '%s' "$OUT" | grep -q '^초과 a u1 · 대기(석) · .* · 긴급$' && ! printf '%s' "$OUT" | grep -qE ' n1 ' && ok "R1 팀 폴더 긴급 카드 = 초과 긴급 · 일반 카드 0" || bad "R1 :: $OUT"
# R2 evidence .md 의 «- 긴급: 예» → 카드가 아니라 효과 0(출력에 증거 파일 없음)
! printf '%s' "$OUT" | grep -q 'urgent-ev' && ok "R2 증거 폴더 긴급 줄 = 출력 0" || bad "R2 :: $OUT"
# R3 절(## ) 안의 긴급 줄 = 긴급 아님(지금과 같은 판정)
! printf '%s' "$OUT" | grep -qE ' s1 ' && ok "R3 절 안 긴급 줄 = 긴급 아님" || bad "R3 :: $OUT"
# R4 harness 행(별표 없음) 카드 긴급 → 지금과 같은 결과
printf '%s' "$OUT" | grep -q '^초과 harness hu · 대기(석) · .* · 긴급$' && ok "R4 harness 행 긴급 카드 = 초과 긴급" || bad "R4 :: $OUT"
# R5 증거 .md 200개 리포 · 판정 불가 0 · git grep pathspec = 카드 폴더 .md 두 범위만(GIT_TRACE · 가짜 git 0)
n_ev="$(grep -F 'git grep' "$T/trace1" | grep -c ':(glob)design/teams/\*/indices/\*\*/\*.md')"; n_h="$(grep -F 'git grep' "$T/trace1" | grep -c ":(glob)$H/\*\*/\*.md")"
bare="$(grep -F 'git grep' "$T/trace1" | grep -cE -- '-- design/(teams/?|harness/indices)( |$)')"
case "$(hd)" in *판정\ 불가*) pj=1;; *) pj=0;; esac
[ "$n_ev" = 1 ] && [ "$n_h" = 1 ] && [ "$bare" = 0 ] && [ "$pj" = 0 ] && ok "R5 증거 200개에서 판정 불가 0 · grep pathspec = :(glob) 카드 폴더 .md (팀 1 · harness 1 · 옛 base 0)" || bad "R5 팀=$n_ev h=$n_h bare=$bare pj=$pj :: $grep_line :: $(hd)"
lap R1-R5
# 변이 1 — 옛 pathspec(base) 로 되돌리면 R5 가 빨강이어야 한다(그 칸만)
mkdir -p "$T/m"; cp "$BIN"/ft_*.py "$T/m/"
python3 - "$TOOL" "$T/m/ft_card_assign_watch.py" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); a = "f\":(glob){r[3].rstrip('/')}/**/*.md\""
assert a in s, a
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(a, "base"))
PY
env_root; TRACE="$T/trace2" TOOL_RUN="$T/m/ft_card_assign_watch.py" run status
m_new="$(grep -F 'git grep' "$T/trace2" | grep -c ':(glob)')"; m_bare="$(grep -F 'git grep' "$T/trace2" | grep -cE -- '-- design/(teams|harness/indices)( |$)')"
[ "$m_new" = 0 ] && [ "$m_bare" -ge 1 ] && ok "변이 1(옛 base) → R5 빨강(glob 0 · 팀 폴더 전체 grep 재현)" || bad "변이 1 이 R5 에 안 잡힘 glob=$m_new bare=$m_bare"
lap mutation
for f in ft_card_assign_watch.py; do cmp -s "$BIN/$f" "$KIT/$f" || bad "bin·kit 다름 $f"; done && ok "bin·kit 같은 내용"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
