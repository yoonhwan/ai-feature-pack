#!/usr/bin/env bash
# test_board_news_four_slot_r2095.sh — 보드 뉴스: 읽는 글이 바뀔 때만 1통 · Slack 4칸 꼴 · 잘림 0 · 낡은 원장 글 WARN (r2095 반례 ①~⑨).
# 실 Slack 0 · 실 launchd 0 · 설치 0 · sleep 0: FT_BOARD_BIN 스텁(collect --out = 준비한 dict) · FT_THREAD_POST 스텁(본문을 파일에) · 시계 FT_BOARD_NOW.
# R2095_BIN = 시험할 bin 폴더(변이 사본 · 기준판용 · 기본 harness/bin).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BIN="${R2095_BIN:-$ROOT/harness/bin}"
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
# mk <spec> — 하네스 팀 + 수집 실패 팀 «엑스». spec: cards{id:폴더} · titles{id:제목} · seats{이름:글자} · h[] · nseats · ncards(진행 카드 c<i>) · err
cat > "$T/stub/mk.py" <<'EOF'
import json, sys
s = json.loads(sys.argv[1]); cards = dict(s.get("cards", {})); seats = dict(s.get("seats", {})); tt = dict(s.get("titles", {}))
for i in range(s.get("nseats", 0)):
    seats[f"byz-harness-worker-x{i:02d}#1"] = "작업중"
for i in range(s.get("ncards", 0)):
    cards[f"c{i:02d}"] = "진행"; tt[f"c{i:02d}"] = f"c{i:02d} — 끝: 아주 길게 이어지는 진행 중인 일 {i:02d}"
prog = {c: {"title": tt.get(c, c), "seats": []} for c, st in cards.items() if st == "진행"}
counts = {k: sum(1 for v in cards.values() if v == k) for k in ("완성", "진행", "대기", "중복")}
team = {"key": "harness", "label": "하네스", "states": cards, "counts": counts, "progress": prog,
        "seats": {n: {"text": t} for n, t in seats.items()}, "oppa_todo": s.get("h", []),
        "axes": [{"title": "축", "entries": [{"k": "card", "idx": c, "text": t} for c, t in tt.items()]}]}
if s.get("err"):
    team = {"key": "harness", "label": "하네스", "error": "inbox 조회 시간 초과"}
print(json.dumps({"date": "2026-11-16", "teams": [team, {"key": "x", "label": "엑스", "error": "깨짐"}]}, ensure_ascii=False))
EOF
mk() { python3 "$T/stub/mk.py" "$1" > "$T/stub/collect.json"; }
goal() { { echo "# 원장"; echo; echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; echo; echo "## 다른 절"; } > "$T/goal.md"; }
reset() { rm -rf "$T/ft/.fable-team/state" "$T/stub/tp.log" "$T/stub"/body.*.txt; }
replies() { [ -f "$T/stub/tp.log" ] && wc -l < "$T/stub/tp.log" | tr -d ' ' || echo 0; }
lastbody() { cat "$T/stub/body.$(replies).txt"; }
now_section() { lastbody | awk '/^지금$/{f=1;next} /^다음$/{f=0} f'; }
next_section() { lastbody | awk '/^다음$/{f=1;next} /^막힌 것, 오빠 할 일$/{f=0} f'; }
run() { RC=0; env FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" FT_BOARD_POST_ARGS= \
  FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="$1" FT_BOARD_THREAD_TS=1794790937.978069 bash "$BIN/ft-board-publish.sh" --news > "$T/out" 2> "$T/err" || RC=$?; }
rep() { python3 -c "import sys; print(sys.argv[1] * int(sys.argv[2]))" "$1" "$2"; }

G1="1 | ft 2.0 완성 | 20 | 23 | 진행 중"; G2="2 | 하네스 운영 | 3 | 5 | 진행 중"
W1='"w1":"w1 — 끝: 보드 뉴스 끝난 일 시험"'
BASE="{\"cards\":{\"a\":\"대기\",\"b\":\"대기\",\"c\":\"대기\",\"w1\":\"진행\"},\"titles\":{$W1},\"seats\":{\"byz-harness-nano-w1#0\":\"작업중\"},\"h\":[7]}"

# ① 팀 카드 수 · 좌석만 다름 = 발행 0 · 본문 0 · 상태 파일 그대로
reset; goal "$G1" "$G2"; mk "$BASE"; run 2026-11-16T10:00:00
chk "① 첫 실행 POST" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ]'
cp "$LAST" "$T/last1"
mk "{\"cards\":{\"a\":\"대기\",\"b\":\"대기\",\"c\":\"대기\",\"d\":\"대기\",\"w1\":\"진행\"},\"titles\":{$W1},\"seats\":{\"byz-harness-nano-w1#0\":\"작업중\"},\"nseats\":2,\"h\":[7]}"
run 2026-11-16T10:10:00
chk "① 대기 3→4 · 좌석 2석 열림 = 변화 없음 — 발행 0" '[ "$RC" = 0 ] && grep -qF "변화 없음 — 발행 0" "$T/out"'
chk "① 본문 0 · news-last 그대로" '[ "$(replies)" = 1 ] && cmp -s "$LAST" "$T/last1"'
# ② 일 1개 진행 → 완성 = POST · 끝난 일 1줄 · 좌석 이름 0
mk "{\"cards\":{\"a\":\"대기\",\"b\":\"대기\",\"c\":\"대기\",\"w1\":\"완성\"},\"titles\":{$W1},\"seats\":{\"byz-harness-nano-w1#0\":\"작업중\"},\"h\":[7]}"
run 2026-11-16T10:20:00
chk "② POST" '[ "$RC" = 0 ] && [ "$(replies)" = 2 ]'
chk "② 지금 = «끝난 일: 보드 뉴스 끝난 일 시험» 1줄" '[ "$(now_section | grep -cxF "끝난 일: 보드 뉴스 끝난 일 시험")" = 1 ]'
chk "② 본문에 좌석 이름 0" '! lastbody | grep -qE "nano-|byz-|worker-|좌석"'
# ③ 골 n 3 → 4 = POST · 바뀜 줄 1 · 같은 입력 300초 뒤 = 변화 없음
goal "$G1" "2 | 하네스 운영 | 4 | 5 | 진행 중"; run 2026-11-16T10:30:00
chk "③ POST · «바뀜:» 1줄" '[ "$(replies)" = 3 ] && [ "$(now_section | grep -c "^바뀜: ")" = 1 ] && now_section | grep -qxF "바뀜: 하네스 운영 3단계 → 4단계(전체 5)"'
chk "③ 골 줄 = m단계 중 n단계 끝남" 'now_section | grep -qxF "하네스 운영: 5단계 중 4단계 끝남. 진행 중"'
run 2026-11-16T10:35:00
chk "③ 같은 입력 300초 뒤 = 변화 없음" '[ "$RC" = 0 ] && [ "$(replies)" = 3 ] && grep -q "변화 없음" "$T/out"'
# ④ 상태 글 200자 = 그대로 · «…» 0 · 끝 줄 «근거:»
L200="$(rep 가 200)"; reset; goal "$G1" "3 | 긴 골 | — | — | $L200"; mk "$BASE"; run 2026-11-16T11:00:00
chk "④ 200자 그대로" '[ "$RC" = 0 ] && now_section | grep -qxF "긴 골: $L200"'
chk "④ «…» 0 · 끝 줄 «근거:»" '! lastbody | grep -qF "…" && lastbody | tail -1 | grep -q "^근거:"'
# ⑤ 진행 중인 일 40개 + 긴 골 3개 = ≤3500B · «외 N개» 1번 · 골 줄 전부 남음
L330="$(rep 나 330)"; reset; goal "4 | 넘침 하나 | — | — | $L330" "5 | 넘침 둘 | 1 | 4 | $L330" "6 | 넘침 셋 | — | — | $L330"
mk '{"ncards":40}'; run 2026-11-16T12:00:00
chk "⑤ rc 0 · POST · ≤3500B" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && [ "$(lastbody | wc -c | tr -d " ")" -le 3500 ]'
chk "⑤ «외 N개» 1번 · 진행 중인 일 40개" '[ "$(lastbody | grep -oE "외 [0-9]+개" | wc -l | tr -d " ")" = 1 ] && next_section | grep -q "^진행 중인 일 40개"'
chk "⑤ 골 줄 3개 전부" '[ "$(now_section | grep -cF "$L330")" = 3 ]'
L350="$(rep 다 355)"; reset; goal "4 | 넘침 하나 | — | — | $L350" "5 | 넘침 둘 | 1 | 4 | $L350" "6 | 넘침 셋 | — | — | $L350"  # 355자 = 이름 1개면 3500B 넘고 0개면 안 넘는 자리
mk '{"ncards":40}'; run 2026-11-16T12:00:00  # DA HOLD R1: 이름 0개 경계
chk "⑤ 이름 0개 경계 = ≤3500B · «외 40개» 1번 · 골 줄 3개" '[ "$RC" = 0 ] && [ "$(lastbody | wc -c | tr -d " ")" -le 3500 ] && [ "$(lastbody | grep -oE "외 [0-9]+개" | wc -l | tr -d " ")" = 1 ] && next_section | grep -q "외 40개$" && [ "$(now_section | grep -cF "$L350")" = 3 ]'
# ⑥ 꼴: 골 9행(닫힌 2 · 수 있는 열린 1 · 수 없는 열린 6) = 5덩이 순서 · 장식·표·코드블록·가운뎃점 0
reset; goal "1 | 닫힌 하나 | 4 | 4 | 끝" "2 | 닫힌 둘 | 2 | 2 | 끝" "3 | 수 있는 골 | 1 | 3 | 진행 · 시험 중" \
  "4 | 골 넷 | — | — | 사전 · 준비" "5 | 골 다섯 | — | — | 대기" "6 | 골 여섯 | — | — | 대기" "7 | 골 일곱 | — | — | 대기" "8 | 골 여덟 | — | — | 대기" "9 | 골 아홉 | — | — | 대기"
mk "$BASE"; run 2026-11-16T13:00:00
chk "⑥ 첫 줄" 'lastbody | head -1 | grep -qxF "골 진행 알림: 열린 골 7개, 닫힌 골 2개(닫힌 하나, 닫힌 둘)"'
chk "⑥ 5덩이 순서" '[ "$(lastbody | grep -nE "^(골 진행 알림:|지금$|다음$|막힌 것, 오빠 할 일$|근거:)" | cut -d: -f2 | tr "\n" "/")" = "골 진행 알림/지금/다음/막힌 것, 오빠 할 일/근거/" ] && lastbody | tail -1 | grep -q "^근거:"'
chk "⑥ 열린 골 7줄 · 수 있는 골 꼴" '[ "$(now_section | wc -l | tr -d " ")" = 7 ] && now_section | grep -qxF "수 있는 골: 3단계 중 1단계 끝남. 진행, 시험 중" && now_section | grep -qxF "골 넷: 사전, 준비"'
chk "⑥ 다음 = 진행 중인 일 1개" '[ "$(next_section)" = "진행 중인 일 1개: 보드 뉴스 끝난 일 시험" ]'
chk "⑥ « · » · ▓░ · 줄 머리 | · 코드블록 0" '! lastbody | grep -qE " · |[▓░]|^\||\`\`\`"'
chk "⑥ 근거 줄 밖 r번호 · sha · HH:MM 0" '! lastbody | sed "\$d" | grep -qE "r[0-9]{3,4}|[0-9a-f]{10}|[0-9]{2}:[0-9]{2}"'
# ⑦ 닫힌 골 = 첫 줄 괄호에만
chk "⑦ 지금 칸에 닫힌 골 줄 0" '! now_section | grep -qE "^닫힌 (하나|둘)"'
# ⑧ 낡은 원장 글 = 그대로 싣고(가운뎃점만 «, ») · WARN 1줄
OLD="닫는 증거 칸 재집계 없음(11-14 판) · 전팀 정지 중"
reset; goal "$G1" "2 | 하네스 운영 | 3 | 5 | $OLD"; mk "$BASE"; run 2026-11-16T14:00:00
chk "⑧ rc 0 · 글 그대로(«, »)" '[ "$RC" = 0 ] && now_section | grep -qxF "하네스 운영: 5단계 중 3단계 끝남. 닫는 증거 칸 재집계 없음(11-14 판), 전팀 정지 중"'
chk "⑧ WARN 1줄 · 골 이름 + 낱말 2개" '[ "$(grep -c "^WARN 원장 상태 글 손볼 곳: " "$T/err")" = 1 ] && grep -qxF "WARN 원장 상태 글 손볼 곳: 하네스 운영 — 닫는 증거 칸, (11-14 판)" "$T/err"'
# ⑨ 불변: 299초 디바운스 · 골 표 없음 · 수집 실패 팀 확인 불가
reset; goal "$G1" "$G2"; mk "$BASE"; run 2026-11-16T15:00:00
goal "$G1" "2 | 하네스 운영 | 4 | 5 | 진행 중"; run 2026-11-16T15:04:59
chk "⑨ 299초 = 디바운스 · 발행 0" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && grep -q "디바운스" "$T/out"'
mk '{"err":true}'; goal "$G1" "2 | 하네스 운영 | 4 | 5 | 진행 중"; run 2026-11-16T15:10:00
chk "⑨ 수집 실패 팀 = «하네스 확인 불가» 1줄" '[ "$(replies)" = 2 ] && [ "$(lastbody | grep -c "^하네스 확인 불가")" = 1 ] && ! lastbody | grep -q "엑스"'
reset; printf '# 원장\n\n## 다른 절\n' > "$T/goal.md"; mk "$BASE"; run 2026-11-16T16:00:00
chk "⑨ 골 표 없음 = 그 문구 1줄 · WARN" '[ "$RC" = 0 ] && lastbody | grep -q "골 진행 표 없음" && grep -q "^WARN ft_board_news" "$T/err"'
chk "⑨ bin = kit 사본" '( for f in ft_board_news.py ft_board_news_body.py ft_board_news_name.py; do cmp -s "$ROOT/harness/bin/$f" "$ROOT/harness/kit/fable-team/bin/$f" || exit 1; done )'

echo "fail=$fail"; [ "$fail" = 0 ]
