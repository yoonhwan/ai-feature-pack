#!/usr/bin/env bash
# test_goal_table_procs_r644.sh — 골 표·뉴스·매거진이 원장 «메인 골 6줄» 만 읽어 오늘 등록한 표준절차 골 파일이 보고에서 빠졌다 → `procs` 하위 명령(r644).
#   ⓐ 골 파일 2(a = 진행표 행 있음 · b = 행 없음) → 마커 2줄 사이 2줄: a = «골 이름 · 담당 · 지금 단계» · b = «… · 진행표 행 없음» + stderr WARN 1줄
#   ⓑ 새 골 파일 커밋 1개 → 다음 렌더에 1줄 자동 추가(손 등록 0)   ⓒ «지금 단계» 가 `완료` + 저장소에 실재하는 sha10 → «완성 N: 이름» 1줄로 위에 / sha 없음 = 완성 아님 + WARN
#   ⓓ 행 git blame 시각이 FT_GOAL_PROC_STALE_H(24) 넘음 → 그 줄 끝 «⚠ N시간 정지» + 블록 끝 «정지 골 N: …» 1줄
#   ⓔ 담당 = 진행표 «담당» 칸 → 골 파일 «담당:» 줄 → «—»   ⓕ 날짜 붙은 `GOAL-*-<8자리>.md` 만(AUTONOMY-GOAL-A6·GOAL-planner.md·날짜 없음 제외) · 0개 = «표준절차 골 0» 1줄
#   ⓖ 예산 1600B 넘으면 «지금 단계» 칸부터 줄임 · 원장 못 읽음/폴더 못 풂 = ERROR rc1(조용히 빈 블록 0)
#   ⓗ 기존 render·teams 바이트 동일(base 대조) · 뉴스 첫 판 순서 = 골 표 → 팀별 완성 진행 → 표준절차 골
# 픽스처 = mktemp 임시 git 리포 1 · 실 리포·실 원장·실 좌석·외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="${R644_REPO:-$HERE/../..}"
TOOL="${R644_TOOL:-$REPO/harness/bin/ft_goal_table.py}"  # R644_TOOL = «전» 판(base) 대조용
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
R="$T/repo"; F=design/teams/planner
git -C "$T" init -q -b main "$R"; mkdir -p "$R/$F" "$R/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `%s/` | x | 현역 |\n' "$F" > "$R/design/TEAMS.md"
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -qm "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
goal_file() { printf '# 골 — %s\n\n> 골 파일 = 불변%s\n\n## 골\n%s 골 문장\n' "$1" "${3:-}" "$1" > "$R/$F/$2"; }  # <이름> <파일> [«담당:» 줄 꼬리]
ledger() {  # <a 의 지금 단계> [b 의 지금 단계 — "" = 진행표에 b 행 없음] [«담당» 열: "" | 담당]
  local a="${1:-}" b="${2:-}" col="${3:-}"
  { printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 6줄 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')"
    for i in 1 2 3 4 5 6; do printf '| 원장 골 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done
    printf '\n## 표준절차 골 진행표\n\n'
    if [ -n "$col" ]; then printf '| 골 | 골 파일 | 담당 | 지금 단계 | 다음 |\n|---|---|---|---|---|\n| 골A | GOAL-a-20261021.md | 팀A | %s | 다음A |\n' "$a"
    else printf '| 골 | 골 파일 | 지금 단계 | 다음 |\n|---|---|---|---|\n| 골A | GOAL-a-20261021.md | %s | 다음A |\n' "$a"; fi
    [ -z "$b" ] || { [ -n "$col" ] && printf '| 골B | GOAL-b-20261021.md | 팀B | %s | 다음B |\n' "$b" || printf '| 골B | GOAL-b-20261021.md | %s | 다음B |\n' "$b"; }
  } > "$R/$F/PLAN-oppa-ledger.md"
}
procs() { env -u FT_GOAL_A6_MD -u FT_GOAL_A6_LEDGER -u FT_LEDGER_PATH -u FT_GOAL_PROC_STALE_H -u FT_NOW -u FT_ROOT \
  FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF="${REF:-origin/main}" "${EXTRA[@]}" python3 "$TOOL" procs 2>"$T/err"; }
line1() { printf '%s\n' "$1" | sed -n '1p'; }
# ── ⓐ 골 파일 2(a 행 있음 · b 행 없음)
goal_file "골-A" GOAL-a-20261021.md
goal_file "골-B" GOAL-b-20261021.md; ledger "② 제안서 진행"; commit c0
SHA0="$(git -C "$R" rev-parse origin/main | cut -c1-10)"
EXTRA=(); OUT="$(procs)"; RC=$?
[ "$RC" = 0 ] && [ "$(line1 "$OUT")" = "★표준절차 골 ($SHA0)★" ] && ok "ⓐ1 rc0 · 머리 = ★표준절차 골 (<원장 sha10>)★" || bad "ⓐ1 rc=$RC :: $(line1 "$OUT")"
printf '%s\n' "$OUT" | sed -n '2p' | grep -qxF -- "- 골-A · — · ② 제안서 진행" && ok "ⓐ2 a = «골 이름 · 담당 · 지금 단계(원장 행)»" || bad "ⓐ2 :: $(printf '%s\n' "$OUT" | sed -n '2p')"
printf '%s\n' "$OUT" | sed -n '3p' | grep -qxF -- "- 골-B · — · 진행표 행 없음" && ok "ⓐ3 b = «… · 진행표 행 없음»" || bad "ⓐ3 :: $(printf '%s\n' "$OUT" | sed -n '3p')"
grep -q "WARN 표준절차 골 진행표 행 없음: GOAL-b-20261021.md" "$T/err" && [ "$(grep -c WARN "$T/err")" = 1 ] && ok "ⓐ4 stderr WARN 1줄(행 없는 골 파일 지목)" || bad "ⓐ4 :: $(cat "$T/err")"
[ "$(printf '%s\n' "$OUT" | tail -1)" = "★/표준절차 골★" ] && ok "ⓐ5 꼬리 마커" || bad "ⓐ5 :: $(printf '%s\n' "$OUT" | tail -1)"
# ── ⓑ 새 골 파일 커밋 1개 → 자동 1줄 추가
goal_file "골-C" GOAL-c-20261021.md; commit c1
OUT="$(procs)"
[ "$(printf '%s\n' "$OUT" | grep -c '^- ')" = 3 ] && printf '%s\n' "$OUT" | grep -qxF -- "- 골-C · — · 진행표 행 없음" && ok "ⓑ 새 골 파일 = 다음 렌더에 1줄 자동 추가(손 등록 0)" || bad "ⓑ :: $OUT"
# ── ⓒ «완료» + 저장소에 실재하는 sha10 → «완성 N: 이름» 위로 · 없는 sha = 완성 아님 + WARN
REALSHA="$(git -C "$R" rev-parse HEAD | cut -c1-10)"
ledger "② 제안서 진행" "완료 $REALSHA"; commit c2
OUT="$(procs)"
[ "$(printf '%s\n' "$OUT" | sed -n '2p')" = "완성 1: 골-B" ] && ! printf '%s\n' "$OUT" | grep -q '^- 골-B' && ok "ⓒ1 «지금 단계» = 완료 + 실재 sha10 → «완성 1: 골-B» 1줄로 위로" || bad "ⓒ1 :: $OUT"
ledger "② 제안서 진행" "완료 deadbeef99"; commit c3
OUT="$(procs)"
printf '%s\n' "$OUT" | grep -qxF -- "- 골-B · — · 완료 deadbeef99" && ! printf '%s\n' "$OUT" | grep -q '^완성 ' && grep -q 'WARN 표준절차 골 완료 표기인데 저장소에 닫는 증거 sha 가 없다: GOAL-b-20261021.md' "$T/err" \
  && ok "ⓒ2 sha 가 저장소에 없음 = 완성 아님 + WARN" || bad "ⓒ2 :: $OUT / $(cat "$T/err")"
# ── ⓓ blame 시각이 FT_GOAL_PROC_STALE_H 넘음 → «⚠ N시간 정지» + «정지 골 N: …»
ledger "② 제안서 진행" "① 골 등록 끝"; commit c4
EXTRA=(FT_NOW="$(python3 -c 'import datetime;print((datetime.datetime.now()+datetime.timedelta(hours=30)).strftime("%Y-%m-%d %H:%M"))')")
OUT="$(procs)"; EXTRA=()
printf '%s\n' "$OUT" | grep -qE '^- 골-A · — · ② 제안서 진행 ⚠ [0-9]+시간 정지$' && [ "$(printf '%s\n' "$OUT" | tail -2 | head -1)" = "정지 골 2: 골-A, 골-B" ] \
  && ok "ⓓ 24시간 넘게 안 바뀐 행 = «⚠ N시간 정지» + «정지 골 N: …» 1줄" || bad "ⓓ :: $OUT"
EXTRA=(FT_GOAL_PROC_STALE_H=1000); OUT="$(procs)"; EXTRA=()
printf '%s\n' "$OUT" | grep -q '정지' && bad "ⓓ2 문턱을 올리면 정지 0" || ok "ⓓ2 FT_GOAL_PROC_STALE_H 로 문턱을 바꾼다(24h 기본)"
# ── ⓔ 담당 = 진행표 «담당» 칸 → 골 파일 «담당:» 줄 → «—»
ledger "② 제안서 진행" "① 골 등록 끝" 담당; commit c5
OUT="$(procs)"
printf '%s\n' "$OUT" | grep -qxF -- "- 골-A · 팀A · ② 제안서 진행" && printf '%s\n' "$OUT" | grep -qxF -- "- 골-B · 팀B · ① 골 등록 끝" && ok "ⓔ1 진행표 «담당» 칸이 있으면 그 칸" || bad "ⓔ1 :: $OUT"
goal_file "골-A" GOAL-a-20261021.md $'\n담당: 팀C\n'; ledger "② 제안서 진행" "① 골 등록 끝"; commit c6
OUT="$(procs)"
printf '%s\n' "$OUT" | grep -qxF -- "- 골-A · 팀C · ② 제안서 진행" && ok "ⓔ2 «담당» 칸이 없으면 골 파일 «담당:» 줄" || bad "ⓔ2 :: $OUT"
goal_file "골-A" GOAL-a-20261021.md; ledger "② 제안서 진행" "① 골 등록 끝"; commit c7
OUT="$(procs)"
printf '%s\n' "$OUT" | grep -qxF -- "- 골-A · — · ② 제안서 진행" && ! printf '%s\n' "$OUT" | grep -q '·  ·' && ok "ⓔ3 둘 다 없으면 «—»(조용히 빈칸 0)" || bad "ⓔ3 :: $OUT"
# ── ⓕ 날짜 붙은 골 파일만
cp "$R/$F/GOAL-a-20261021.md" "$R/$F/GOAL-planner.md"; cp "$R/$F/GOAL-a-20261021.md" "$R/$F/GOAL-nodate.md"
cp "$R/$F/GOAL-a-20261021.md" "$R/$F/AUTONOMY-GOAL-A6-20261018.md"; commit c8
OUT="$(procs)"
[ "$(printf '%s\n' "$OUT" | grep -c '^- ')" = 3 ] && ! printf '%s\n' "$OUT" | grep -q 'GOAL-planner\|GOAL-nodate\|AUTONOMY' && ok "ⓕ GOAL-*-<8자리>.md 만(AUTONOMY-GOAL-A6·GOAL-planner.md·날짜 없음 제외)" || bad "ⓕ :: $OUT"
git -C "$R" rm -q "$F/GOAL-a-20261021.md" "$F/GOAL-b-20261021.md" "$F/GOAL-c-20261021.md"; commit c9
OUT="$(procs)"
printf '%s\n' "$OUT" | grep -qxF "표준절차 골 0" && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 3 ] && ok "ⓕ2 골 파일 0개 = «표준절차 골 0» 1줄" || bad "ⓕ2 :: $OUT"
# ── ⓖ 예산 1600B · ERROR rc1
goal_file "골-긴이름" GOAL-a-20261021.md; ledger "$(python3 -c 'print("가"*400)')" ""; commit c10
OUT="$(procs)"
[ "$(printf '%s' "$OUT" | wc -c | tr -d ' ')" -le 1600 ] && printf '%s\n' "$OUT" | grep -qxF '★/표준절차 골★' && printf '%s\n' "$OUT" | grep -q '…$' \
  && ok "ⓖ1 예산 1600B 안 — «지금 단계» 칸부터 줄임" || bad "ⓖ1 $(printf '%s' "$OUT" | wc -c)B :: $OUT"
RC="$(env -u FT_ROOT FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF=origin/main FT_GOAL_A6_LEDGER="gitref:origin/main:$F/NOPE.md" python3 "$TOOL" procs >/dev/null 2>"$T/err2"; echo $?)"
OUT="$(cat "$T/err2")"
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 표준절차 골 원장 못 읽음'*) true;; *) false;; esac && ok "ⓖ2 원장 못 읽음 = ERROR rc1(조용히 빈 블록 0)" || bad "ⓖ2 rc=$RC :: $OUT"
RC="$(env -u FT_ROOT FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF=nosuchref python3 "$TOOL" procs >/dev/null 2>"$T/err3"; echo $?)"
[ "$RC" = 1 ] && ok "ⓖ3 planner 폴더 못 풂(ref 없음) = rc1" || bad "ⓖ3 rc=$RC :: $(cat "$T/err3")"
# ── ⓗ 기존 render·teams 바이트 동일(base 대조) + 뉴스 첫 판 순서(골 표 → 팀별 → 표준절차)
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"; BASE="$T/basebin/ft_goal_table.py"  # base 판 = 형제 모듈(ft_goal_ledger·ft_team_lib)까지 같이 사본
cp -R "$REPO/harness/bin" "$T/basebin"
git -C "$ROOT" show origin/main:feature-pack/fable-team/harness/bin/ft_goal_table.py > "$BASE"
printf '# 자율 골 A6\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n' > "$R/$F/AUTONOMY-GOAL-A6-20261018.md"
for i in 1 2 3 4 5 6; do printf '| goal-%s | 팀%s | 착지 sha |\n' "$i" "$i" >> "$R/$F/AUTONOMY-GOAL-A6-20261018.md"; done
ledger "② 제안서 진행" "① 골 등록 끝"; commit c11
same() {  # <하위 명령> — 새 판과 origin/main 판 출력이 바이트 동일
  A="$(env -u FT_ROOT FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF=origin/main FT_GOAL_A6_LEDGER="$R/$F/PLAN-oppa-ledger.md" FT_GOAL_A6_MD="$R/$F/AUTONOMY-GOAL-A6-20261018.md" python3 "$TOOL" "$1" 2>/dev/null)"
  B="$(env -u FT_ROOT FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF=origin/main FT_GOAL_A6_LEDGER="$R/$F/PLAN-oppa-ledger.md" FT_GOAL_A6_MD="$R/$F/AUTONOMY-GOAL-A6-20261018.md" python3 "$BASE" "$1" 2>/dev/null)"
  [ -n "$A" ] && [ "$A" = "$B" ]
}
same render && ok "ⓗ1 render 바이트 동일(메인 6줄 블록 무변경)" || bad "ⓗ1 render"
printf '\n## 팀별 완성 진행\n\n| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |\n|---|---|---|---|\n| planner | 3/5 | a1b2 | 골 표 |\n' >> "$R/$F/PLAN-oppa-ledger.md"; commit c12
same teams && ok "ⓗ2 teams 바이트 동일" || bad "ⓗ2 teams"
ORDER="$(cd "$(dirname "$TOOL")" && env -u FT_ROOT FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" FT_TEAMS_REF=origin/main python3 - <<'PY'
import sys
from datetime import datetime
import ft_news_ledger_text as nt, ft_goal_table as gt
goal, teams, procs = gt.render(), gt.render_teams(), gt.render_procs()
parts = nt.render_parts(datetime(2026, 10, 21, 12, 0), {("now", "", "지금 전체 상태"): ("가동",)}, [], "PLAN-oppa-ledger.md", (("*지금*", ["가동"]),), goal=goal, teams=teams + procs)
body = parts[0]
pos = [body.find(k) for k in ("★골 표 A6", "★팀별 완성 진행", "★표준절차 골")]
print(" ".join(map(str, pos)))
sys.exit(0 if all(p >= 0 for p in pos) and pos == sorted(pos) else 1)
PY
)"; RC=$?
[ "$RC" = 0 ] && ok "ⓗ3 뉴스 첫 판 순서 = 골 표 → 팀별 완성 진행 → 표준절차 골($ORDER)" || bad "ⓗ3 순서 $ORDER"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAIL $fail"; exit 1
