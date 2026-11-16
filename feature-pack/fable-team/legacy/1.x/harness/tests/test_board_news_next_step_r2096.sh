#!/usr/bin/env bash
# test_board_news_next_step_r2096.sh — 보드 뉴스 «다음» 칸 = 골별 다음 한 수(원장 여섯째 column) · 팀장 빈 팀 줄 0 (r2096 반례 ①~⑧).
# 실 Slack 0 · 실 launchd 0 · 설치 0 · sleep 0: FT_BOARD_BIN 스텁(collect --out = 준비한 dict) · FT_THREAD_POST 스텁(본문을 파일에) · 시계 FT_BOARD_NOW.
# R2096_BIN = 시험할 bin 폴더(변이 사본 · 기준판용 · 기본 harness/bin).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BIN="${R2096_BIN:-$ROOT/harness/bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ft/.fable-team" "$T/stub"
LAST="$T/ft/.fable-team/state/board/news-last.json"
cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "collect --out" ] || exit 9
cp "$(dirname "$0")/collect.json" "$3"
EOF
chmod +x "$T/stub/board"
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
d = os.path.dirname(os.path.abspath(__file__))
n = sum(1 for _ in open(f"{d}/tp.log")) if os.path.exists(f"{d}/tp.log") else 0
open(f"{d}/tp.log", "a").write(" ".join(sys.argv[1:]) + "\n")
open(f"{d}/body.{n + 1}.txt", "w", encoding="utf-8").write(open(sys.argv[sys.argv.index("--text-file") + 1], encoding="utf-8").read())
EOF
# mk <ncards> [팀=ok|<error 글>]... — 하네스 팀(진행 카드 c<i> ncards장) + 덧붙일 팀(ok = 카드 1장 있는 정상 팀)
cat > "$T/stub/mk.py" <<'EOF'
import json, sys
def team(key, cards):
    return {"key": key, "label": key, "states": cards, "counts": {"진행": sum(v == "진행" for v in cards.values())},
            "progress": {c: {"title": f"{c} — 끝: 진행 일 {c}", "seats": []} for c in cards}, "seats": {}, "oppa_todo": [],
            "axes": [{"title": "축", "entries": [{"k": "card", "idx": c, "text": f"{c} — 끝: 진행 일 {c}"} for c in cards]}]}
teams = [team("harness", {f"c{i:03d}": "진행" for i in range(int(sys.argv[1]))})]
for spec in sys.argv[2:]:
    k, v = spec.split("=", 1)
    teams.append(team(k, {f"{k}-w": "진행"}) if v == "ok" else {"key": k, "label": k, "error": v})
print(json.dumps({"date": "2026-11-16", "teams": teams}, ensure_ascii=False))
EOF
mk() { python3 "$T/stub/mk.py" "$@" > "$T/stub/collect.json"; }
# goal5 행... = 5 column 표(지금 원장 꼴) · goal6 행... = 여섯째 column «다음 한 수 1줄»
goal5() { { echo "# 원장"; echo; echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; echo; echo "## 다른 절"; } > "$T/goal.md"; }
goal6() { { echo "# 원장"; echo; echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 | 다음 한 수 1줄 |"; echo "|---|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; echo; echo "## 다른 절"; } > "$T/goal.md"; }
reset() { rm -rf "$T/ft/.fable-team/state" "$T/stub/tp.log" "$T/stub"/body.*.txt; }
replies() { [ -f "$T/stub/tp.log" ] && wc -l < "$T/stub/tp.log" | tr -d ' ' || echo 0; }
lastbody() { cat "$T/stub/body.$(replies).txt"; }
now_section() { lastbody | awk '/^지금$/{f=1;next} /^다음$/{f=0} f'; }
next_section() { lastbody | awk '/^다음$/{f=1;next} /^막힌 것, 오빠 할 일$/{f=0} f'; }
run() { RC=0; env FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" FT_BOARD_POST_ARGS= \
  FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="$1" FT_BOARD_THREAD_TS=1794790937.978069 bash "$BIN/ft-board-publish.sh" --news > "$T/out" 2> "$T/err" || RC=$?; }
lastkey() { python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['key'], ensure_ascii=False))" "$LAST"; }
rep() { python3 -c "import sys; print(sys.argv[1] * int(sys.argv[2]))" "$1" "$2"; }
MB="판정 불가(_master 빔)"

# ① 진행 카드 149장 · 열린 골 6 중 4골에 값 = 골별 4줄(표 순서) · 카드 이름 0
SIX=("1 | 골 하나 | 1 | 3 | 진행 | 시험 붙이기 · 검토" "2 | 골 둘 | — | — | 대기 | " "3 | 골 셋 | 2 | 5 | 진행 | 설치 확인" \
  "4 | 골 넷 | — | — | 대기 | —" "5 | 골 다섯 | 0 | 2 | 대기 | 원장 고치기" "6 | 골 여섯 | — | — | 대기 | 첫 글 읽기" "7 | 닫힌 골 | 2 | 2 | 끝 | 닫힌 골 값")
reset; goal6 "${SIX[@]}"; mk 149; run 2026-11-16T10:00:00
chk "① rc 0 · POST" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ]'
chk "① 다음 = 4줄 표 순서 · « · » → «, »" '[ "$(next_section | tr "\n" "/")" = "골 하나: 시험 붙이기, 검토/골 셋: 설치 확인/골 다섯: 원장 고치기/골 여섯: 첫 글 읽기/" ]'
chk "① 카드 이름 0 · 다음 칸 «진행 중인 일» 0 · «외 » 0(r2103: 좌석 0 = 지금 칸 «진행 중인 일 없음»)" '! lastbody | grep -qE "c[0-9]{3}|진행 일|외 " && ! next_section | grep -q "진행 중인 일"'
# ② 값 없음 = «정해진 다음 한 수 없음» 1줄
reset; goal5 "1 | 골 하나 | 1 | 3 | 진행" "2 | 골 둘 | — | — | 대기"; mk 3; run 2026-11-16T10:00:00
chk "② 5 column = 1줄 · rc 0" '[ "$RC" = 0 ] && [ "$(next_section)" = "정해진 다음 한 수 없음" ]'
chk "② 5 column «지금» 칸 = 그대로" '[ "$(now_section | tr "\n" "/")" = "골 하나 ▓▓▓░░░░░░░ 1/3. 진행/골 둘: 대기/진행 중인 일 없음/" ]'
reset; goal6 "1 | 골 하나 | 1 | 3 | 진행 | " "2 | 골 둘 | — | — | 대기 | —"; mk 3; run 2026-11-16T10:00:00
chk "② 6 column 값 빈칸 · «—» = 같은 1줄" '[ "$RC" = 0 ] && [ "$(next_section)" = "정해진 다음 한 수 없음" ]'
# ③ 열쇠: 값 1칸 바뀜 = POST · 같은 입력 300초 뒤 = 변화 없음 · 진행 카드만 늘어남 = 변화 없음
reset; goal6 "1 | 골 하나 | 1 | 3 | 진행 | 시험 붙이기"; mk 5; run 2026-11-16T11:00:00
goal6 "1 | 골 하나 | 1 | 3 | 진행 | 설치하기"; run 2026-11-16T11:05:00
chk "③ 값 1칸 바뀜 = POST" '[ "$RC" = 0 ] && [ "$(replies)" = 2 ] && [ "$(next_section)" = "골 하나: 설치하기" ]'
run 2026-11-16T11:10:00
chk "③ 같은 입력 300초 뒤 = 변화 없음" '[ "$(replies)" = 2 ] && grep -qF "변화 없음" "$T/out"'
mk 8; run 2026-11-16T11:15:00
chk "③ 진행 카드 3장 늘어남 = 변화 없음" '[ "$RC" = 0 ] && [ "$(replies)" = 2 ] && grep -qF "변화 없음" "$T/out"'
# ④ 팀장 빈 팀 = 본문 줄 0 · 열쇠 0 · INFO 1줄
reset; goal6 "1 | 골 하나 | 1 | 3 | 진행 | 시험 붙이기"; mk 3; run 2026-11-16T12:00:00; KA="$(lastkey)"
reset; mk 3 "chatbot=$MB"; run 2026-11-16T12:00:00
chk "④ 첫 실행 = POST · chatbot 0 · 확인 불가 0" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && ! lastbody | grep -qE "chatbot|확인 불가"'
chk "④ 열쇠 = chatbot 블록 없는 입력과 같음" '[ "$(lastkey)" = "$KA" ]'
chk "④ stderr «INFO 팀장 빈 팀: chatbot» 1줄" '[ "$(grep -cxF "INFO 팀장 빈 팀: chatbot" "$T/err")" = 1 ]'
reset; mk 3 "chatbot=ok"; run 2026-11-16T12:00:00
mk 3 "chatbot=$MB"; run 2026-11-16T12:10:00
chk "④ 직전 상태에 chatbot 있음 = «확인 불가» 줄 0 · 변화 없음" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && grep -qF "변화 없음" "$T/out" && [ "$(lastkey)" = "$KA" ]'
# ⑤ 다른 실패 = «확인 불가» 줄 그대로 · 팀장 빈 팀과 함께면 그 팀만
reset; mk 3 "graphics=ok"; run 2026-11-16T13:00:00
mk 3 "graphics=판정 불가(원천 모양 오류)"; run 2026-11-16T13:10:00
chk "⑤ graphics 확인 불가 줄 그대로" '[ "$(replies)" = 2 ] && lastbody | grep -qxF "graphics 확인 불가(수집 실패, 직전 상태 유지)"'
reset; mk 3 "chatbot=ok" "graphics=ok"; run 2026-11-16T13:00:00
mk 3 "chatbot=$MB" "graphics=판정 불가(원천 모양 오류)"; run 2026-11-16T13:10:00
chk "⑤ chatbot + graphics = 확인 불가 줄 1개(graphics)" '[ "$(replies)" = 2 ] && [ "$(lastbody | grep -c "확인 불가")" = 1 ] && lastbody | grep -q "^graphics 확인 불가" && ! lastbody | grep -q chatbot'
# ⑥ 넘침: 열린 골 12행 · 값 400자 = ≤3500B · «그 밖의 골 N개» 1번 · 지금 칸 12줄 · 끝 줄 근거
V400="$(rep 가 400)"; ROWS=(); for i in $(seq 1 12); do ROWS+=("$i | 넘침 골 $i | — | — | 대기 | $V400"); done
reset; goal6 "${ROWS[@]}"; mk 3; run 2026-11-16T14:00:00
chk "⑥ rc 0 · POST · ≤3500B" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && [ "$(lastbody | wc -c | tr -d " ")" -le 3500 ]'
chk "⑥ «그 밖의 골 N개» 1번 · 마지막 줄" '[ "$(lastbody | grep -cE "^그 밖의 골 [0-9]+개$")" = 1 ] && next_section | tail -1 | grep -qE "^그 밖의 골 [0-9]+개$"'
chk "⑥ 지금 칸 골 줄 12개 · 끝 줄 «근거:»" '[ "$(now_section | grep -c "^넘침 골 ")" = 12 ] && lastbody | tail -1 | grep -q "^근거:"'
# ⑦ 옛 상태 파일(r2095 판 · 5 column 행 · carried = chatbot) = rc 0 · 다음 실행 변화 없음
reset; goal6 "1 | 골 하나 | 1 | 3 | 진행 | 시험 붙이기"; mk 3 "chatbot=$MB"; mkdir -p "$(dirname "$LAST")"
python3 - "$LAST" <<'EOF'
import json, sys
snap = {"goals": [["1", "골 하나", "1", "3", "진행"]], "cards": {"harness": {"c000": "진행"}, "chatbot": {"chatbot-w": "진행"}},
        "counts": {"harness": [0, 1, 0], "chatbot": [0, 1, 0]}, "sessions": {}, "h_by": {"harness": [], "chatbot": []},
        "err": ["chatbot"], "carried": ["chatbot"], "h": 0}
key = ["골 진행 알림: 열린 골 1개, 닫힌 골 0개", "지금", "골 하나: 3단계 중 1단계 끝남. 진행", "막힌 것, 오빠 할 일", "없음", "chatbot 확인 불가(수집 실패, 직전 상태 유지)"]
json.dump({"at": "2026-11-16T09:00:00", "key": key, "snap": snap}, open(sys.argv[1], "w"), ensure_ascii=False)
EOF
run 2026-11-16T15:00:00
chk "⑦ 옛 상태 파일 = rc 0 · 수집 복구 0 · chatbot 0" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && ! lastbody | grep -qE "수집 복구|chatbot"'
run 2026-11-16T15:10:00
chk "⑦ 다음 실행 = 변화 없음" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && grep -qF "변화 없음 — 발행 0" "$T/out"'
# ⑧ 불변: 299초 디바운스 · 골 표 없음 · bin = kit 사본
reset; goal6 "1 | 골 하나 | 1 | 3 | 진행 | 시험 붙이기"; mk 3; run 2026-11-16T16:00:00
goal6 "1 | 골 하나 | 1 | 3 | 진행 | 설치하기"; run 2026-11-16T16:04:59
chk "⑧ 299초 = 디바운스" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && grep -q "디바운스 — " "$T/out"'
reset; printf '# 원장\n\n## 다른 절\n' > "$T/goal.md"; mk 3; run 2026-11-16T16:00:00
chk "⑧ 골 표 없음 = 그 문구 · 다음 = 정해진 다음 한 수 없음" '[ "$RC" = 0 ] && lastbody | grep -q "골 진행 표 없음" && [ "$(next_section)" = "정해진 다음 한 수 없음" ]'
chk "⑧ bin = kit 사본" '( for f in ft_board_news.py ft_board_news_body.py ft_board_news_name.py; do cmp -s "$ROOT/harness/bin/$f" "$ROOT/harness/kit/fable-team/bin/$f" || exit 1; done )'

echo "fail=$fail"; [ "$fail" = 0 ]
