#!/usr/bin/env bash
# test_goal_count_follows_canon_r668.sh — 골 개수 6 을 코드에 박아 두어 닫힌 골(방·강의 10-20 ✅)을 내리거나 새 골을 올리면 ERROR 로 멈추던 것 → 골 수 N = 정본 표 행 수(r668).
#   ⓐ 5행·6행·7행 정본 + 같은 행 수 원장 → 골 표 rc0(N행)   ⓑ 골좌표 1~N 통과 · n=N+1 REJECT + «새 번호표 N줄» 문구
#   ⓒ 정본 행 수 ≠ 원장 행 수 = ERROR rc1(조용한 절단 0)   ⓓ 0행 · FT_GOAL_MAX(12) 초과 = ERROR rc1
#   ⓔ 원장 절 이름 «메인 골 6줄»·«메인 골»·«메인 골 5줄» 모두 읽힘(옛 원장 호환)
#   ⓕ 옛 번호 골좌표(«골좌표: 6 — …»)를 새 판(5행)에 대면 REJECT 문구에 새 번호표 5줄
#   ⓖ 정본 sha·번호표가 바뀐 첫 렌더 = 전 팀장 공지 1통(명부 `_master` 전부) · 같은 정본 sha 로는 1회(표식)
#   ⓗ 뉴스 렌더·lint 가 N행(5)으로 rc0 — «골 5개» 절 머리 + 카드 5장 + 린트 위반 0
# 픽스처 = mktemp 임시 git 리포·임시 루트·가짜 mbox(인자 기록만) — 실 리포·실 원장·실 좌석·외부 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TOOL="$REPO/harness/bin/ft_goal_table.py"; LINT="$REPO/harness/bin/ft_news_html_lint.py"; RENDER="$REPO/harness/bin/ft_news_html_render.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
CPATH=design/planner/AUTONOMY-GOAL-A6-20261021.md; LPATH=design/planner/PLAN-oppa-ledger.md
R="$T/repo"; mkdir -p "$R/design/planner" "$R/.fable-team/comm"; git -C "$R" init -q -b main
canon() {  # <행 수>
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local i; for i in $(seq 1 "$1"); do printf '| goal-%s-test | 팀%s | 착지 sha |\n' "$i" "$i"; done
}
ledger() {  # <행 수> [절 제목]
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n%s\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' \
    "$(date '+%Y-%m-%d %H:%M')" "${2:-## 메인 골 6줄 — 지금 상태}"
  local i; for i in $(seq 1 "$1"); do printf '| 원장 글자 %s | 상태%s 진행 | 남은%s |\n' "$i" "$i" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
put() { canon "$1" > "$R/$CPATH"; ledger "$1" "${2:-}" > "$R/$LPATH"; commit "c$1"; }  # <행 수> [절 제목]
render() { env -u FT_GOAL_MAX -u FT_MBOX FT_ROOT="$R" FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_A6_LEDGER="gitref:origin/main:$LPATH" \
  FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" ${EXTRA[@]+"${EXTRA[@]}"} python3 "$TOOL" 2>&1; }
check() { printf '%s\n' "$1" | env -u FT_ROOT FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" python3 "$TOOL" check - 2>&1; }
rows() { printf '%s\n' "$1" | grep -c '^| .* | .* | .* | .* |$'; }
EXTRA=()

# ── ⓐ 5행·6행·7행 모두 rc0(N행)
for n in 5 6 7; do
  put "$n"; OUT="$(render)"; RC=$?
  [ "$RC" = 0 ] && [ "$(rows "$OUT")" = $((n + 1)) ] && ok "ⓐ ${n}행 정본 → rc0 · 표 $((n + 1))줄(제목+골 ${n})" || bad "ⓐ ${n}행 rc=$RC :: $OUT"
done
# ── ⓑ 골좌표 1~N 통과 · n=N+1 REJECT + «새 번호표 N줄»
put 5; BLOCK="$(render)"
for k in 1 5; do OUT="$(check "$BLOCK"$'\n'"골좌표: $k — goal-$k-test")"; [ "$OUT" = "GOAL-OK n=$k" ] && ok "ⓑ 골좌표 $k → GOAL-OK n=$k" || bad "ⓑ n=$k :: $OUT"; done
OUT="$(check "$BLOCK"$'\n'"골좌표: 6 — goal-6-test")"; RC=$?
[ "$RC" = 3 ] && case "$OUT" in *'새 번호표 5줄: 1 — goal-1-test'*'5 — goal-5-test'*) true;; *) false;; esac \
  && ok "ⓑ 골좌표 6(>N) → REJECT · 문구에 새 번호표 5줄" || bad "ⓑ n=6 rc=$RC :: $OUT"
OUT="$(check "$BLOCK")"; RC=$?
case "$OUT" in *'골좌표: <1~5>'*'새 번호표 5줄'*) ok "ⓑ 골좌표 줄 없음 → REJECT 문구에 <1~5> + 새 번호표" ;; *) bad "ⓑ 줄없음 rc=$RC :: $OUT" ;; esac
# ── ⓒ 정본 행 수 ≠ 원장 행 수 = ERROR rc1
put 5; ledger 6 > "$T/l6"; cp "$T/l6" "$R/$LPATH"; commit "ledger6"
OUT="$(render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 원장 행 수 6≠5'*) true;; *) false;; esac && ok "ⓒ 정본 5 · 원장 6 → ERROR rc1(조용한 절단 0)" || bad "ⓒ rc=$RC :: $OUT"
# ── ⓓ 0행 · 상한 초과
printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n' > "$R/$CPATH"
printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 0줄\n\n| a | b | c |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')" > "$R/$LPATH"
commit zero; OUT="$(render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 정본'*) true;; *) false;; esac && ok "ⓓ 0행 → ERROR rc1" || bad "ⓓ 0행 rc=$RC :: $OUT"
put 13; OUT="$(render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'1~12행'*) true;; *) false;; esac && ok "ⓓ 13행 > FT_GOAL_MAX(12) → ERROR rc1" || bad "ⓓ 13행 rc=$RC :: $OUT"
put 6; EXTRA=(FT_GOAL_MAX=5); OUT="$(render)"; RC=$?; EXTRA=()
[ "$RC" = 1 ] && ok "ⓓ FT_GOAL_MAX=5 면 6행 → ERROR rc1(상한이 env 를 따른다)" || bad "ⓓ FT_GOAL_MAX rc=$RC :: $OUT"
# ── ⓔ 원장 절 이름 3종
for h in "## 메인 골 6줄 — 지금 상태" "## 메인 골" "## 메인 골 5줄"; do
  put 5 "$h"; OUT="$(render)"; RC=$?
  [ "$RC" = 0 ] && [ "$(rows "$OUT")" = 6 ] && printf '%s' "$OUT" | grep -q '상태1 진행' && ok "ⓔ 절 «${h}» → 읽힘(rc0)" || bad "ⓔ «$h» rc=$RC :: $OUT"
done
# ── ⓕ 옛 번호 골좌표를 새 판(5행)에 대면 새 번호표
put 5; BLOCK="$(render)"; OUT="$(check "$BLOCK"$'\n'"골좌표: 6 — 메모리 세션 제한으로")"; RC=$?
[ "$RC" = 3 ] && case "$OUT" in *'새 번호표 5줄'*) true;; *) false;; esac && ok "ⓕ 옛 번호(6) 골좌표 → REJECT + 새 번호표 5줄" || bad "ⓕ rc=$RC :: $OUT"
# ── ⓖ 번호 바뀜 공지 1통(전 팀장) · 같은 정본 sha 로는 1회
mkdir -p "$T/mbox"; cat > "$T/mbox/mbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MBOX_LOG"
SH
chmod +x "$T/mbox/mbox.sh"
printf '{"_master":"master-a#1"}\n' > "$R/.fable-team/seats-a.json"
printf '{"_master":"master-b#2"}\n' > "$R/.fable-team/seats-b.json"
printf '{"_master":"master-a#1"}\n' > "$R/.fable-team/seats-a.json.bak-x"   # 백업은 세지 않는다
mkdir -p "$R/.fable-team/state"; printf "%s/\n" "$T" > "$R/.fable-team/LIVE_ROOT"; : > "$R/.fable-team/LIVE_BIN"
export MBOX_LOG="$T/mbox.log"; : > "$MBOX_LOG"
put 6; render >/dev/null                                            # 첫 렌더 = 기준선만(공지 0)
[ ! -s "$MBOX_LOG" ] && ok "ⓖ1 첫 렌더(기준선) = 공지 0" || bad "ⓖ1 첫 렌더에 공지 :: $(cat "$MBOX_LOG")"
put 5; EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null; RC=$?; 
N1="$(wc -l < "$MBOX_LOG" | tr -d ' ')"; head -1 "$MBOX_LOG" | grep -q '^send master-a#1 ft-goal-table \[골 번호 바뀜\]' \
  && head -2 "$MBOX_LOG" | tail -1 | grep -q '^send master-b#2 ' && [ "$N1" = 2 ] \
  && ok "ⓖ2 정본 sha·번호표 바뀐 첫 렌더 = 팀장마다 1통(2명 → 2통 · 백업 명부 제외)" || bad "ⓖ2 rc=$RC n=$N1 :: $(cat "$MBOX_LOG")"
grep -q '새 번호표 5줄' "$MBOX_LOG" && ok "ⓖ3 공지 본문에 새 번호표 5줄" || bad "ⓖ3 :: $(cat "$MBOX_LOG")"
render >/dev/null; [ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && ok "ⓖ4 같은 정본 sha 재렌더 = 추가 공지 0(표식 state/)" || bad "ⓖ4 재렌더 :: $(cat "$MBOX_LOG")"
put 7; EXTRA=(FT_MBOX="$T/mbox/none.sh"); OUT="$(render)"; RC=$?; EXTRA=()
[ "$RC" = 0 ] && case "$OUT" in *'WARN 골 번호 공지 못 함'*) true;; *) false;; esac && ok "ⓖ5 mbox 없음 = WARN 1줄 · 렌더는 rc0" || bad "ⓖ5 mbox 없음 rc=$RC :: $OUT"
unset MBOX_LOG
# ── ⓗ 뉴스 렌더·lint 가 N행(5)으로 rc0
OUT="$(python3 - "$LINT" "$RENDER" <<'PY' 2>&1
import sys, importlib.util
from datetime import datetime
from pathlib import Path
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); sys.modules[name] = m; spec.loader.exec_module(m); return m
sys.path[:0] = [str(Path(sys.argv[1]).parent)]
lint = load("ft_news_html_lint", sys.argv[1]); rd = load("ft_news_html_render", sys.argv[2])
goals = [{"n": i, "goal": f"골 글 {i}", "team": f"t{i} (byz-t{i}-master)", "state": "지금"} for i in range(1, 6)]
c = {"summary": ["가"], "important": [{"title": "일", "detail": "설명", "who": "t"}], "goals": [{"done": "끝", "now": "지금", "left": "남음"} for _ in range(5)],
     "working": [], "unknown": [], "resting": [], "refs": [], "dropped": []}
page = rd.render(c, goals, datetime(2026, 10, 21, 23, 30))
hard = [p for p in lint.problems(page, "가") if p in ("절 6 아님 — h1=[] h2=[]",) or "골 " in p or "절" in p]
print("CARDS", page.count('<section class="goal">'), "H2", "<h2>골 5개</h2>" in page, "LINT", hard)
print("LINT_ALL", lint.problems(page, "가"))
PY
)"
case "$OUT" in "CARDS 5 H2 True LINT []"*'LINT_ALL []'*) ok "ⓗ 뉴스 렌더 = 카드 5장 · 절 머리 «골 5개» · 린트 위반 0" ;; *) bad "ⓗ :: $OUT" ;; esac
OUT="$(python3 - "$LINT" <<'PY' 2>&1
import sys, importlib.util
from pathlib import Path
sys.path[:0] = [str(Path(sys.argv[1]).parent)]
spec = importlib.util.spec_from_file_location("ft_news_html_lint", sys.argv[1]); lint = importlib.util.module_from_spec(spec); spec.loader.exec_module(lint)
h2 = "".join(f"<h2>{h}</h2>" for h in lint.h2_titles(5))
goals = '  <section class="goal">\n    골\n  </section>\n' * 5
page = f"<h1>{lint.H1}</h1>{h2}<section class=\"prio\"><ol><li>가</li></ol></section>{goals}<p class=\"foot\">근거: 원장 · 자율 ON</p>"
print("OK5", lint.problems(page, "가"))
print("BAD6", [p for p in lint.problems(page.replace("골 5개", "골 6개"), "가") if "골" in p])
print("BAD7", [p for p in lint.problems(page + goals + goals, "가") if "골" in p])
PY
)"
case "$OUT" in "OK5 []"*"BAD6 ['골 5행 (6행이어야 · 1~12)']"*"BAD7 ['골 15행 (5행이어야 · 1~12)']"*) ok "ⓗ2 린트 = 카드 수 ↔ «골 N개» 일치 · 불일치·상한 초과는 위반 문구" ;; *) bad "ⓗ2 :: $OUT" ;; esac

# ── ⓘ DA⑥ r1 H1~H4 빠진 칸(정본 뒤 다른 표 · 원장 빈 칸 행 · 옛 sha 마커 · «메인 골 참고» 절 · 같은 N 재배열 · 동시 공지 · 깨진 명부 · 1행·12행 경계 · 정본→뉴스 연결)
canon_of() {  # <골 이름...> — 같은 픽스처에 다른 골 이름·다른 순서를 넣을 때
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local g; for g in "$@"; do printf '| %s | 팀x | 착지 sha |\n' "$g"; done
}
reset_mark() { rm -f "$R/.fable-team/state/goal-numbering.tsv"; }
export MBOX_LOG="$T/mbox.log"; : > "$MBOX_LOG"
# ⓘ1 정본 표 뒤에 다른 절의 표가 있어도 N = 첫 표의 연속 행만(r668 H1)
{ canon_of g1 g2 g3 g4 g5; printf '\n## 뒤쪽 절\n\n| a | b | c |\n|---|---|---|\n| x | 새면안됨 | z |\n| y | 새면안됨 | z |\n'; } > "$R/$CPATH"
ledger 5 > "$R/$LPATH"; commit "canon-tail-table"
OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && [ "$(rows "$OUT")" = 6 ] && ! printf '%s' "$OUT" | grep -q '새면안됨' \
  && ok "ⓘ1 정본 표 뒤 다른 표 → N=5(뒤 표를 세지 않는다)" || bad "ⓘ1 rc=$RC :: $OUT"
# ⓘ2 원장 빈 칸 행 = ERROR(r668 H1 — 구분선만 빼고 조용한 행 감소 0)
put 5; sed -i.bak 's/^| 원장 글자 3 | 상태3 진행 |/| 원장 글자 3 |  |/' "$R/$LPATH"; rm -f "$R/$LPATH.bak"; commit "ledger-empty-cell"
OUT="$(render)"; RC=$?
[ "$RC" = 1 ] && case "$OUT" in *'ERROR 골 표 원장 빈 칸'*) true;; *) false;; esac && ok "ⓘ2 원장 빈 칸 행 = ERROR rc1(구분선 --- 만 뺀다)" || bad "ⓘ2 rc=$RC :: $OUT"
# ⓘ3 옛 마커 sha 허용은 «번호표(행 수·각 행 골 12자)가 같을 때»만(r668 H2)
{ canon_of g1 g2 g3 g4 g5; } > "$R/$CPATH"; ledger 5 > "$R/$LPATH"; commit "num5-a"
OLD_BLOCK="$(render)"
printf '\n<!-- 주석 -->\n' >> "$R/$CPATH"; commit "num5-a-same-numbering"
OUT="$(check "$OLD_BLOCK"$'\n'"골좌표: 2 — g2")"; RC=$?
[ "$RC" = 0 ] && ok "ⓘ3a 옛 마커 sha — 번호표가 같으면 통과(파일 내용만 바뀐 판)" || bad "ⓘ3a rc=$RC :: $OUT"
{ canon_of h1 h2 h3 h4 h5; } > "$R/$CPATH"; commit "num5-b"
OUT="$(check "$OLD_BLOCK"$'\n'"골좌표: 2 — g2")"; RC=$?
[ "$RC" = 3 ] && case "$OUT" in *'새 번호표 5줄: 1 — h1'*) true;; *) false;; esac && ok "ⓘ3b 옛 마커 sha — 번호표가 바뀌면 REJECT + 새 번호표" || bad "ⓘ3b rc=$RC :: $OUT"
# ⓘ4 «## 메인 골 참고» 는 그 절이 아니다(r668 H3 끝 경계)
put 5 "## 메인 골 참고"; OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | grep -o '상태 없음' | wc -l | tr -d ' ')" -ge 6 ] && [ "$(printf '%s' "$OUT" | grep -c '^WARN 골 표 원장')" = 1 ] \
  && ok "ⓘ4 «## 메인 골 참고» → 그 절 아님(«상태 없음» 5칸 + WARN 1줄 rc0)" || bad "ⓘ4 rc=$RC :: $OUT"
# ⓘ5 같은 N 재배열 = 번호가 바뀐 것 → 공지 1통(r668 H4)
reset_mark; { canon_of a1 a2 a3 a4 a5 a6; } > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit "reorder-base"
EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null; EXTRA=()   # 표식 없는 첫 렌더 6행 = 옛 고정과 같아 공지 0(r668 H4①)
[ ! -s "$MBOX_LOG" ] && ok "ⓘ5a 표식 없음 + 정본 6행 = 공지 0(설치 직후 첫 렌더)" || bad "ⓘ5a :: $(cat "$MBOX_LOG")"
{ canon_of a6 a5 a4 a3 a2 a1; } > "$R/$CPATH"; commit "reorder"
EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null; EXTRA=()
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && grep -q '새 번호표 6줄: 1 — a6' "$MBOX_LOG" \
  && ok "ⓘ5b 같은 N 재배열 = 공지 1통(팀장 2명 → 2통)" || bad "ⓘ5b :: $(cat "$MBOX_LOG")"
# ⓘ5c 표식 없음 + 정본이 옛 고정(6행)과 다르면 공지 1통(r668 H4① — 설치 직후 첫 렌더가 새 5행이면 놓치던 것)
reset_mark; : > "$MBOX_LOG"; { canon_of s1 s2 s3 s4 s5; } > "$R/$CPATH"; ledger 5 > "$R/$LPATH"; commit "first-render-5"
EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null; EXTRA=()
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && grep -q '새 번호표 5줄: 1 — s1' "$MBOX_LOG" \
  && ok "ⓘ5c 표식 없음 + 정본 5행(≠6) = 첫 렌더에서 공지 1통" || bad "ⓘ5c :: $(cat "$MBOX_LOG")"
# ⓘ6 동시 렌더 = 잠금으로 1통(r668 H4②)
cat > "$T/mbox/slow.sh" <<'SH'
#!/usr/bin/env bash
sleep 0.3
printf '%s\n' "$*" >> "$MBOX_LOG"
SH
chmod +x "$T/mbox/slow.sh"
bg_render() { env -u FT_GOAL_MAX FT_ROOT="$R" FT_MBOX="$1" FT_GOAL_A6_MD="gitref:origin/main:$CPATH" FT_GOAL_A6_LEDGER="gitref:origin/main:$LPATH" \
  FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" MBOX_LOG="$MBOX_LOG" python3 "$TOOL" >/dev/null 2>&1; }
reset_mark; { canon_of m1 m2 m3 m4 m5 m6; } > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit "concurrent-base"
bg_render "$T/mbox/slow.sh"                       # 6행 기준선 = 표식만
{ canon_of n1 n2 n3 n4 n5 n6; } > "$R/$CPATH"; commit "concurrent"
: > "$MBOX_LOG"
bg_render "$T/mbox/slow.sh" & bg_render "$T/mbox/slow.sh" & wait
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && ok "ⓘ6 동시 렌더 2건 = 공지 1통(잠금 · 2명 → 2통)" || bad "ⓘ6 :: $(cat "$MBOX_LOG")"
# ⓘ6b 송신 7초 상한(r668 H4④) — mbox 가 멈춰도 렌더가 끝나고 WARN 1줄(표식 전진 0)
cat > "$T/mbox/hang.sh" <<'SH'
#!/usr/bin/env bash
sleep 30
SH
chmod +x "$T/mbox/hang.sh"
mv "$R/.fable-team/seats-b.json" "$R/.fable-team/seats-b.hidden"   # 팀장 1명만(상한 1회 × 7초)
reset_mark; { canon_of t1 t2 t3 t4 t5; } > "$R/$CPATH"; ledger 5 > "$R/$LPATH"; commit "timeout-base"
T0=$SECONDS
EXTRA=(FT_MBOX="$T/mbox/hang.sh"); OUT="$(render)"; RC=$?; EXTRA=()
ELAPSED=$((SECONDS - T0))
mv "$R/.fable-team/seats-b.hidden" "$R/.fable-team/seats-b.json"
[ "$RC" = 0 ] && [ "$ELAPSED" -lt 15 ] && printf '%s' "$OUT" | grep -q 'WARN 골 번호 공지 실패' \
  && ok "ⓘ6b 송신 상한 7초 — 멈춘 mbox 에도 렌더 rc0(경과 ${ELAPSED}s) · WARN 1줄" || bad "ⓘ6b rc=$RC ${ELAPSED}s :: $OUT"
# ⓘ7 깨진 명부 = WARN + 표식 전진 0(r668 H4③)
reset_mark; { canon_of p1 p2 p3 p4 p5 p6; } > "$R/$CPATH"; ledger 6 > "$R/$LPATH"; commit "broken-base"
EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null; EXTRA=()
printf '{broken\n' > "$R/.fable-team/seats-broken.json"; : > "$MBOX_LOG"
{ canon_of q1 q2 q3 q4 q5 q6; } > "$R/$CPATH"; commit "broken"
EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); OUT="$(render)"; RC=$?; EXTRA=()
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q '깨진 명부' && [ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] \
  && ok "ⓘ7a 깨진 명부 = WARN 1줄 · 읽히는 팀장에게는 보냄 · 렌더 rc0" || bad "ⓘ7a rc=$RC :: $(cat "$MBOX_LOG") :: $OUT"
: > "$MBOX_LOG"; EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null 2>&1; EXTRA=()
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && ok "ⓘ7b 깨진 명부 = 표식 전진 0(다음 렌더가 다시 시도)" || bad "ⓘ7b :: $(cat "$MBOX_LOG")"
rm -f "$R/.fable-team/seats-broken.json"; : > "$MBOX_LOG"
EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null 2>&1; EXTRA=()
[ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 2 ] && ok "ⓘ7c 명부 고침 → 1통 더 보낸 뒤 표식 전진" || bad "ⓘ7c :: $(cat "$MBOX_LOG")"
: > "$MBOX_LOG"; EXTRA=(FT_MBOX="$T/mbox/mbox.sh"); render >/dev/null 2>&1; EXTRA=()
[ ! -s "$MBOX_LOG" ] && ok "ⓘ7d 표식 전진 뒤 추가 공지 0" || bad "ⓘ7d :: $(cat "$MBOX_LOG")"
# ⓘ8 1행·12행 경계(1 ≤ N ≤ FT_GOAL_MAX)
put 1; OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && [ "$(rows "$OUT")" = 2 ] && ok "ⓘ8a 1행 정본 → rc0(N=1 경계)" || bad "ⓘ8a rc=$RC :: $OUT"
put 12; OUT="$(render)"; RC=$?
[ "$RC" = 0 ] && [ "$(rows "$OUT")" = 13 ] && ok "ⓘ8b 12행 정본 = FT_GOAL_MAX 경계 rc0" || bad "ⓘ8b rc=$RC :: $OUT"
# ⓘ9 정본 N → 뉴스 카드·절 머리·린트가 같은 N 을 따른다(연결 1칸)
OUT="$(python3 - "$LINT" "$RENDER" <<'PY' 2>&1
import sys, importlib.util
from datetime import datetime
from pathlib import Path
sys.path[:0] = [str(Path(sys.argv[1]).parent)]
spec = importlib.util.spec_from_file_location("ft_news_html_lint", sys.argv[1]); lint = importlib.util.module_from_spec(spec); spec.loader.exec_module(lint)
spec = importlib.util.spec_from_file_location("ft_news_html_render", sys.argv[2]); rd = importlib.util.module_from_spec(spec); sys.modules["ft_news_html_render"] = rd; spec.loader.exec_module(rd)
N = 7
goals = [{"n": i, "goal": f"골 글 {i}", "team": f"t{i} (byz-t{i}-master)", "state": "지금"} for i in range(1, N + 1)]
c = {"summary": ["가"], "important": [{"title": "일", "detail": "설명", "who": "t"}],
     "goals": [{"done": "끝", "now": "지금", "left": "남음"} for _ in range(N)],
     "working": [], "unknown": [], "resting": [], "refs": [], "dropped": []}
page = rd.render(c, goals, datetime(2026, 10, 22, 0, 30))
print("CARDS", page.count('<section class="goal">'), "H2", f"<h2>골 {N}개</h2>" in page, "LINT", lint.problems(page, "가"))
PY
)"
case "$OUT" in "CARDS 7 H2 True LINT []") ok "ⓘ9 정본 N=7 → 뉴스 카드 7장 · «골 7개» · 린트 위반 0" ;; *) bad "ⓘ9 :: $OUT" ;; esac
unset MBOX_LOG

echo "== test_goal_count_follows_canon_r668: fail=$fail"
[ "$fail" = 0 ]