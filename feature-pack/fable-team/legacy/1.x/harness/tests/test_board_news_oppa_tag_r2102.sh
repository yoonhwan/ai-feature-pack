#!/usr/bin/env bash
# test_board_news_oppa_tag_r2102.sh — 뉴스 본문 «막힌 것, 오빠 할 일» 칸의 오빠 태그 (r2102 · A1 · A2).
#   ① 열쇠와 발행: 승인 대기 0 → 1 = POST · 같은 입력 = 변화 없음 · 승인 대기 1 인 채 골 줄만 바뀜 = POST + 태그 1회 · 줄 순서 = 기준판
#   ② 승인 대기 2 → `<@U0AC2JF0M7D> 오빠 승인 대기 2건` 1줄 · `<@` 1회
#   ③ 승인 대기 0 → «없음» · `<@` 0회 / FT_OPPA_SLACK_UID=UTEST → `<@UTEST>` 1회 · 기본 id 0회 / 기본 id = ft_oppa_slack_check 상수
#   ②③ 원장 상태 글의 mention 꼴(`<@…>` · `<!…>`) = 꺾쇠를 뺀다 → 본문 `<@` 수 = 도구 태그 수 · `<!` 0
#   ⑦ 같은 열쇠 2회 = «변화 없음» · 발행 도구 호출 0 / 열쇠가 바뀐 입력 300초 안 = «디바운스» · 호출 0
# 실 Slack 0 · sleep 0: FT_BOARD_BIN 스텁 · FT_THREAD_POST 스텁(본문을 파일에) · 시계 FT_BOARD_NOW. R2102_BIN = 시험할 bin(변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2102_BIN:-$HERE/../bin}"
PUB="$BIN/ft-board-publish.sh"
UID0=U0AC2JF0M7D
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ft/.fable-team" "$T/stub"
cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "collect --out" ] || exit 9
cp "$(dirname "$0")/collect.json" "$3"
EOF
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
d = os.path.dirname(os.path.abspath(__file__))
n = sum(1 for _ in open(f"{d}/tp.log")) if os.path.exists(f"{d}/tp.log") else 0
open(f"{d}/tp.log", "a").write(" ".join(sys.argv[1:]) + "\n")
open(f"{d}/body.{n + 1}.txt", "w", encoding="utf-8").write(open(sys.argv[sys.argv.index("--text-file") + 1], encoding="utf-8").read())
EOF
chmod +x "$T/stub/board"
mk() {  # mk <승인 대기 수> — 한 팀 collect dict(카드 1장 · 좌석 0)
  python3 - "$1" > "$T/stub/collect.json" <<'PY'
import json, sys
team = {"key": "harness", "label": "하네스", "states": {"r1-a": "대기"}, "counts": {"완성": 0, "진행": 0, "대기": 1, "중복": 0},
        "progress": {}, "seats": {}, "oppa_todo": list(range(int(sys.argv[1]))), "axes": []}
print(json.dumps({"date": "2026-11-16", "verdicts": [], "issues": [], "teams": [team]}, ensure_ascii=False))
PY
}
goal() { { echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; } > "$T/goal.md"; }
reset() { rm -rf "$T/ft/.fable-team/state" "$T/stub/tp.log" "$T/stub"/body.*.txt; }
replies() { [ -f "$T/stub/tp.log" ] && wc -l < "$T/stub/tp.log" | tr -d ' ' || echo 0; }
lastbody() { cat "$T/stub/body.$(replies).txt"; }
tags() { lastbody | grep -o '<@' | wc -l | tr -d ' '; }
run() { env FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" FT_GOAL_PROGRESS_MD="$T/goal.md" \
  FT_BOARD_NOW="$1" FT_BOARD_THREAD_TS=1794729663.977629 bash "$PUB" --news > "$T/out" 2> "$T/err"; }
G1="1 | 하네스 운영 | 3 | 5 | 진행 중"

# ① 열쇠와 발행(A1)
reset; goal "$G1"; mk 0; run 2026-11-16T10:00:00
chk "① 첫 발행(승인 대기 0) · 태그 0" '[ "$(replies)" = 1 ] && [ "$(tags)" = 0 ]'
mk 1; run 2026-11-16T10:10:00
chk "① 승인 대기 0 → 1 = POST(열쇠 다름)" '[ "$(replies)" = 2 ]'
run 2026-11-16T10:20:00
chk "① 같은 입력 다시 = «변화 없음 — 발행 0»" '[ "$(replies)" = 2 ] && grep -q "변화 없음" "$T/out"'
goal "1 | 하네스 운영 | 4 | 5 | 진행 중"; run 2026-11-16T10:30:00
chk "① 승인 대기 1 인 채 골 줄만 바뀜 = POST · 태그 1회" '[ "$(replies)" = 3 ] && [ "$(tags)" = 1 ]'
WANT="$(printf '%s\n' "골 진행 알림: 열린 골 1개, 닫힌 골 0개" "지금" "바뀜: 하네스 운영 3단계 → 4단계(전체 5)" "하네스 운영 ▓▓▓▓▓▓▓▓░░ 4/5. 진행 중" \
  "진행 중인 일 없음" "다음" "정해진 다음 한 수 없음" "막힌 것, 오빠 할 일" "오빠 승인 대기 1건")"
chk "① 본문 줄 순서 = 기준판(태그 글자 빼고 · 근거 줄 앞까지)" '[ "$(lastbody | sed "\$d" | sed "s/^<@[A-Z0-9]*> //")" = "$WANT" ]'

# ② 태그 있음(A2)
reset; goal "$G1"; mk 2; run 2026-11-16T11:00:00
chk "② «<@${UID0}> 오빠 승인 대기 2건» 1줄" '[ "$(lastbody | grep -cxF "<@${UID0}> 오빠 승인 대기 2건")" = 1 ]'
chk "② 본문 전체 «<@» 1회" '[ "$(tags)" = 1 ]'
GM="1 | 하네스 운영 | 3 | 5 | 결정 담당 <@${UID0}>"
reset; goal "$GM"; mk 2; run 2026-11-16T11:10:00
chk "② 상태 글 «<@id>» + 승인 대기 2 → «<@» 1회(막힌 것 줄)" '[ "$(tags)" = 1 ] && [ "$(lastbody | grep -c "^<@${UID0}> 오빠 승인 대기 2건$")" = 1 ]'
chk "② 골 줄 = «@${UID0}»(꺾쇠 없음)" 'lastbody | grep -qxF "하네스 운영 ▓▓▓▓▓▓░░░░ 3/5. 결정 담당 @${UID0}"'

# ③ 태그 없음(A2) · id 바꾸기 · 기본 id 출처
reset; goal "$G1"; mk 0; run 2026-11-16T12:00:00
chk "③ 승인 대기 0 → «없음» · «<@» 0회" 'lastbody | grep -qx "없음" && [ "$(tags)" = 0 ]'
reset; mk 1; FT_OPPA_SLACK_UID=UTEST run 2026-11-16T12:10:00
chk "③ FT_OPPA_SLACK_UID=UTEST → «<@UTEST>» 1회 · 기본 id 0회" '[ "$(lastbody | grep -o "<@UTEST>" | wc -l | tr -d " ")" = 1 ] && ! lastbody | grep -q "${UID0}"'
reset; goal "$GM"; mk 0; run 2026-11-16T12:20:00
chk "③ 상태 글 «<@id>» + 승인 대기 0 → «<@» 0회 · 골 줄 «@id»" '[ "$(tags)" = 0 ] && lastbody | grep -qxF "하네스 운영 ▓▓▓▓▓▓░░░░ 3/5. 결정 담당 @${UID0}"'
reset; goal "1 | 하네스 운영 | 3 | 5 | 모두 보세요 <!channel>"; mk 0; run 2026-11-16T12:30:00
chk "③ 상태 글 «<!channel>» → 본문 «<!» 0회 · «!channel» 남음" '! lastbody | grep -q "<!" && lastbody | grep -q "보세요 !channel"'
chk "③ 기본 id = ft_oppa_slack_check.OPPA_SLACK_UID" '[ "$(cd "$BIN" && python3 -c "import ft_oppa_slack_check as m; print(m.OPPA_SLACK_UID)")" = "${UID0}" ]'

# ⑦ 의미 없는 글 0(A6) — 기준판에서도 PASS(고정 시험)
reset; goal "$G1"; mk 1; run 2026-11-16T13:00:00; n7="$(replies)"
run 2026-11-16T13:02:00
chk "⑦ 같은 열쇠 둘째 틱 = «변화 없음 — 발행 0» · 발행 도구 호출 0" 'grep -q "변화 없음 — 발행 0" "$T/out" && [ "$(replies)" = "$n7" ]'
mk 2; run 2026-11-16T13:03:00
chk "⑦ 열쇠 바뀜 + 300초 안 = «디바운스» · 호출 0" 'grep -q "디바운스" "$T/out" && [ "$(replies)" = "$n7" ]'

echo "fail=$fail"; [ "$fail" = 0 ]
