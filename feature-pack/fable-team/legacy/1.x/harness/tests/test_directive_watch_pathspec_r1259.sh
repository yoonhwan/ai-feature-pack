#!/usr/bin/env bash
# test_directive_watch_pathspec_r1259.sh — r1259 지시 감시의 git grep·log pathspec = 카드 폴더 글롭(R1~R4 + 변이 1).
# 옛 판 = 새 판 소스의 card_pathspec(r) 호출을 접두(별표 앞 잘라냄)로 되돌린 사본(변이와 같은 사본) · 임시 git 리포 · 가상 시각 --now · git 기록기(PATH) · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_directive_watch_pathspec_r1259.sh
set -uo pipefail
export TZ=Asia/Seoul
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TOOL="$REPO/harness/bin/ft_directive_watch.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
E=$(date -j -f '%Y-%m-%d %H:%M:%S' '2026-10-20 10:00:00' +%s)
GLOB_TEAMS=':(glob)design/teams/*/indices/**'; GLOB_HARN=':(glob)design/harness/indices/**'
PLANNER='byz-planner-master-claude#9'; HMASTER='byz-harness-master-claude#33'

# 옛 판 사본 = 접두 pathspec 으로 되돌림 (변이 1 과 같은 파일) · 되돌림이 실제로 먹었는지 확인
OLD="$T/old/ft_directive_watch.py"; cp -R "$REPO/harness/bin" "$T/old"
sed 's|card_pathspec(r)|r[3].split("*")[0].rstrip("/")|g' "$TOOL" > "$OLD"
[ "$(grep -c 'r\[3\].split("\*")\[0\]' "$OLD")" = 2 ] && ok "준비 옛 판 사본 = 접두 호출 2곳" || bad "준비 옛 판 사본 접두 호출 수 != 2"

gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
put() { mkdir -p "$(dirname "$R/$1")"; shift_1="$1"; shift; printf '%s\n' "$@" > "$R/$shift_1"; }
setup() {  # 임시 루트 R: 카드 폴더 4종 + 카드 폴더 밖 «- 지시:» 문서 2개 + 큰 더미 폴더
  R="$(mktemp -d "$T/r.XXXXXX")"; R="$(cd "$R" && pwd -P)"; mkdir -p "$R/.fable-team/state"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "2026-10-01 09:00:00 +0900" init
  printf 'harness\t.\tmain\tdesign/harness/indices\n*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s","%s":{"role":"master"}}\n' "$PLANNER" "$PLANNER" > "$R/.fable-team/seats-planner.json"
  printf '{"_master":"%s","%s":{"role":"master"}}\n' "$HMASTER" "$HMASTER" > "$R/.fable-team/seats-harness.json"
  printf '{"_master":"byz-room-master-claude#1"}\n' > "$R/.fable-team/seats-room.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/usr/bin/env bash\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  put design/teams/planner/VERDICTS-planner-99-x.md \
    "| 3001 | 10-20 10:00 | 오빠 지시 slack $E.1 방 카드 |" "| 3002 | 10-20 10:00 | 오빠 지시 slack $E.2 담당 없음 |" \
    "| 3003 | 10-20 10:00 | 오빠 지시 slack $E.3 월 폴더 아카이브 |"
  put design/teams/room/indices/진행/r9001-room.md "# 카드 r9001" "- 지시: 판정 3001"
  put design/harness/indices/완성/r9004-harn.md "# 카드 r9004" "- 지시: 판정 3004"
  put design/teams/room/indices/아카이브/2026-10/r9003-archived.md "# 카드 r9003" "- 지시: 판정 3003"
  put design/teams/room/DESIGN-outside.md "# 문서" "- 지시: 판정 3002"
  put design/teams/room/evidence/INSTRUMENT-outside.md "# 문서" "- 지시: 판정 3002"
  mkdir -p "$R/design/teams/room/evidence/big"; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '더미 %s\n' "$i" > "$R/design/teams/room/evidence/big/d$i.md"; done
  git -C "$R" add -A design; gc "$R" "2026-10-20 10:30:00 +0900" "cards"
}
run() {  # <툴> <기록 파일|-> [가상 시각]
  local tool="$1" rec="$2" now="${3:-2026-10-20T11:01:00}" real; real="$(command -v git)"
  if [ "$rec" != "-" ]; then mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$rec" "$real" > "$T/bin/git"; chmod +x "$T/bin/git"; fi
  OUT="$(cd "$R" && env PATH="$([ "$rec" != "-" ] && echo "$T/bin:")$PATH" FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" FT_DIRECTIVE_NANO_REPOS="$R" FT_DIRECTIVE_FLOOR=0 python3 "$tool" status --now "$now" 2>&1)"; RC=$?
}
pathspec_ok() {  # 기록 파일: grep·log 호출이 둘 다 카드 글롭 두 행(팀·harness)을 쓰고 접두 «-- design/teams» 0
  local rec="$1"
  [ -s "$rec" ] && grep -qE ' grep ' "$rec" && grep -qE ' log ' "$rec" || return 2  # 기록 자체가 없으면 판정 불가(변이 «잡힘» 으로 읽지 않는다)
  grep -E ' (grep|log) ' "$rec" | grep -qF -- "-- $GLOB_TEAMS" && grep -E ' grep ' "$rec" | grep -qF -- "-- $GLOB_HARN" \
    && grep -E ' log ' "$rec" | grep -qF -- "-- $GLOB_HARN" && grep -E ' grep ' "$rec" | grep -qF -- "-- $GLOB_TEAMS" \
    && ! grep -E ' (grep|log) ' "$rec" | grep -Eq -- '-- design/(teams|harness)( |$)'
}

# R1·R3·R4 — 같은 결과: 새 판 = 옛 판(접두) 의 출력·rc 동일 · 카드 폴더 밖 문서 2개·월 폴더 아카이브 카드 포함 · 담당 없음 = 3002·3003(2건)
setup; run "$OLD" - ; oo="$OUT"; orc=$RC; run "$TOOL" - ; no="$OUT"; nrc=$RC
case "$no" in "담당 없는 오빠 지시 1 · 멈춘 오빠 지시 0 · 판본 "*) h=1;; *) h=0;; esac  # r1255: 월 폴더 아카이브 카드(3003)는 담당으로 센다 → 담당 없음 = 3002 만
[ "$orc" = "$nrc" ] && [ "$h" = 1 ] && [ "$(printf '%s' "$oo" | sed 's/ · 판본 .*//')" = "$(printf '%s' "$no" | sed 's/ · 판본 .*//')" ] && [ "$(printf '%s\n' "$oo" | grep -c '^담당 없음 판정 3002')" = "$(printf '%s\n' "$no" | grep -c '^담당 없음 판정 3002')" ] \
  && ok "R1·R3·R4 새 판 = 옛 판 출력·rc 같음(rc=$nrc · 담당 없음 3002 · 월 폴더 카드 담당 · 폴더 밖 문서 제외)" || bad "R1·R3·R4 old rc=$orc new rc=$nrc :: $oo :: $no"
lap R1R3R4

# R2·R3 — 범위: git 기록기 · grep·log 둘 다 카드 폴더 글롭(팀 행 + harness 행 · 접두 0)
setup; run "$TOOL" "$T/new.rec"
pathspec_ok "$T/new.rec" && ok "R2·R3 grep·log pathspec = $GLOB_TEAMS · $GLOB_HARN · 접두 0" || bad "R2·R3 기록 :: $(grep -E ' (grep|log) ' "$T/new.rec" | grep -o -- '-- .*' | sort -u | tr '\n' ' ')"
lap R2R3

# 변이 1 — 접두로 되돌림 → R2 FAIL 이어야 한다
setup; run "$OLD" "$T/old.rec"
pathspec_ok "$T/old.rec"; mrc=$?
[ "$mrc" = 1 ] && ok "변이1 접두로 되돌림 → R2 FAIL(잡힘)" || bad "변이1 rc=$mrc (1 이어야 함 · 0 = 못 잡음 · 2 = 기록 없음)"
lap 변이1

echo "단계별 초:$STEP"; [ "$fail" = 0 ] && echo "ALL PASS" || echo "FAIL $fail"; exit "$fail"
