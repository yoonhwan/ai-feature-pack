#!/usr/bin/env bash
# test_directive_watch_archive_month_r1255.sh — r1255 지시 감시: 아카이브/<YYYY-MM>/<카드>.md 도 담당 카드로 센다(R1~R4 + 변이 2).
# 임시 git 리포 · 가상 시각 --now · 네트워크 0 · 자기 재호출 0 · 고정 sleep 0 · 변이 = 소스 사본 문자열 치환(되돌림이 먹었는지 확인).
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_directive_watch_archive_month_r1255.sh
set -uo pipefail
export TZ=Asia/Seoul
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TOOL="$REPO/harness/bin/ft_directive_watch.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
E=$(date -j -f '%Y-%m-%d %H:%M:%S' '2026-10-20 10:00:00' +%s)
PLANNER='byz-planner-master-claude#9'

gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
put() { mkdir -p "$(dirname "$R/$1")"; local f="$1"; shift; printf '%s\n' "$@" > "$R/$f"; }
setup() {  # 임시 루트 R: 판정 5행(3001~3005) + 카드 5장(각 «- 지시: 판정 N»)
  R="$(mktemp -d "$T/r.XXXXXX")"; R="$(cd "$R" && pwd -P)"; mkdir -p "$R/.fable-team/state"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "2026-10-01 09:00:00 +0900" init
  printf '*\t.\tmain\tdesign/teams/*/indices\nplanner\t.\tmain\tdesign/teams/planner/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s","%s":{"role":"master"}}\n' "$PLANNER" "$PLANNER" > "$R/.fable-team/seats-planner.json"
  printf '{"_master":"byz-lecture-master-claude#1"}\n' > "$R/.fable-team/seats-lecture.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  printf '#!/usr/bin/env bash\necho "QUEUED seq=1 to=$2"\n' > "$R/mbox.sh"
  put design/teams/planner/VERDICTS-planner-99-x.md \
    "| 3001 | 10-20 10:00 | 오빠 지시 slack $E.1 진행 카드 |" "| 3002 | 10-20 10:00 | 오빠 지시 slack $E.2 아카이브 바로 아래 |" \
    "| 3003 | 10-20 10:00 | 오빠 지시 slack $E.3 월 폴더 아카이브 |" "| 3004 | 10-20 10:00 | 오빠 지시 slack $E.4 inbox 아래 |" \
    "| 3005 | 10-20 10:00 | 오빠 지시 slack $E.5 월 꼴 아닌 폴더 |"
  put design/teams/lecture/indices/진행/r9001-x.md "# 카드" "- 지시: 판정 3001"
  put design/teams/lecture/indices/아카이브/r9002-y.md "# 카드" "- 지시: 판정 3002"
  put design/teams/lecture/indices/아카이브/2026-10/L76-live.md "# 카드" "- 지시: 판정 3003"
  put design/teams/lecture/indices/inbox/arch/01-z.md "# 문서" "- 지시: 판정 3004"
  put design/teams/lecture/indices/아카이브/old/r9005-z.md "# 카드" "- 지시: 판정 3005"
  git -C "$R" add -A design; gc "$R" "2026-10-20 10:30:00 +0900" "cards"
}
run() {  # <툴>
  OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" FT_DIRECTIVE_NANO_REPOS="$R" FT_DIRECTIVE_FLOOR=0 python3 "$1" status --now 2026-10-20T11:01:00 2>&1)"; RC=$?
}
orphan() { printf '%s\n' "$OUT" | grep -c "^담당 없음 판정 $1 "; }  # 1 = 담당 없음 줄 있음 · 0 = 담당 있음

# 변이 사본 = bin 폴더 통째 복사 + 소스 문자열 치환 · 치환이 실제로 먹었는지(cmp) 확인
mutate() {  # <사본 이름> <지울 문자열>
  mkdir -p "$T/$1"; cp -R "$REPO/harness/bin/." "$T/$1/"
  python3 -I - "$T/$1/ft_directive_watch.py" "$2" <<'PY'
import sys
p, old = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
assert old in s, "치환 대상 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, "", 1) if old.startswith(" or ") else s.replace(old, "True", 1))
PY
  cmp -s "$REPO/harness/bin/ft_directive_watch.py" "$T/$1/ft_directive_watch.py" && return 1 || return 0
}

# R1 — 월 폴더 아카이브 카드 = 담당(판정 3003 담당 없음 0)
setup; run "$TOOL"
[ "$(orphan 3003)" = 0 ] && ok "R1 아카이브/2026-10/ 카드 → 판정 3003 담당 있음" || bad "R1 판정 3003 담당 없음 :: $OUT"
lap R1

# R2·R3 — 진행 카드 · 아카이브 바로 아래 카드는 지금과 같음(담당 있음)
[ "$(orphan 3001)" = 0 ] && [ "$(orphan 3002)" = 0 ] && ok "R2·R3 진행·아카이브 바로 아래 카드 = 담당 있음(지금과 같음)" || bad "R2·R3 :: $OUT"

# R4 — inbox 아래 · 월 꼴 아닌 아카이브 하위 = 담당 아님(담당 없음 줄 유지) · 합계 2건
[ "$(orphan 3004)" = 1 ] && [ "$(orphan 3005)" = 1 ] && case "$OUT" in "담당 없는 오빠 지시 2 · "*) true;; *) false;; esac \
  && ok "R4 inbox/arch·아카이브/old 카드 = 담당 아님(담당 없음 3004·3005 · 합계 2)" || bad "R4 :: $OUT"
lap R2R3R4

# 변이 1 — 새 갈래 지움 → R1 FAIL 이어야 한다
if mutate m1 ' or len(parts) == depth + 3 and parts[depth] == "아카이브" and ARCHIVE_MONTH.fullmatch(parts[depth + 1])'; then
  setup; run "$T/m1/ft_directive_watch.py"
  [ "$(orphan 3003)" = 1 ] && ok "변이1 새 갈래 지움 → R1 FAIL(잡힘 · 3003 담당 없음)" || bad "변이1 못 잡음 :: $OUT"
else bad "변이1 치환이 안 먹음"; fi
lap 변이1

# 변이 2 — 월 꼴 검사 지움 → R4 old 칸 FAIL 이어야 한다
if mutate m2 'ARCHIVE_MONTH.fullmatch(parts[depth + 1])'; then
  setup; run "$T/m2/ft_directive_watch.py"
  [ "$(orphan 3005)" = 0 ] && ok "변이2 월 꼴 검사 지움 → R4 old 칸 FAIL(잡힘 · 3005 담당 생김)" || bad "변이2 못 잡음 :: $OUT"
else bad "변이2 치환이 안 먹음"; fi
lap 변이2

echo "단계별 초:$STEP"; [ "$fail" = 0 ] && echo "ALL PASS" || echo "FAIL $fail"; exit "$fail"
