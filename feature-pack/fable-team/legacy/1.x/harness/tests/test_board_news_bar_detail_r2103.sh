#!/usr/bin/env bash
# test_board_news_bar_detail_r2103.sh — 뉴스 글 골 줄 막대 + «진행 중인 일» 줄 되살림 (r2103 · A1~A5).
#   ① 막대(A1): 3/10 · 1/3 · 0/5 · «—» · 7/5 · 코드블록·표 줄 0
#   ② 진행 중인 일(A2): 팀 이름 순 · 카드 없는 좌석 1줄 · 상한 8 + «그 밖 N개» · 좌석 0 · mention 꺾쇠 빼기
#   ③ 열쇠(A3): 좌석만 바뀜 = 변화 없음 · n 3 → 4 = POST + 막대 칸 바뀜
#   ④ 길이(A4): 판정문 R1 입력 = ⓑ 3488B · ⓐ · ⓒ · ⓓ · 기준판에서도 넘는 입력(rc 1)
#   ⑤ 불변(A5): 줄 순서 · bin = kit cmp 0 (기존 시험 5개는 따로 돌린다)
# 실 Slack 0 · sleep 0: ft_board_news.py 를 직접 부름 · 시계 FT_BOARD_NOW. R2103_BIN = 시험할 bin(변이 사본용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R2103_BIN:-$HERE/../bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# mk <spec json> — teams[{label, seats{이름: 카드 id | null}, titles{id: 제목}}] → collect dict(카드 = 진행)
mk() {
  python3 - "$1" > "$T/collect.json" <<'PY'
import json, sys
teams = []
for i, t in enumerate(json.loads(sys.argv[1])):
    cards = {c: "진행" for c in t["seats"].values() if c}
    teams.append({"key": f"t{i}", "label": t["label"], "states": cards, "counts": {"완성": 0, "진행": len(cards), "대기": 0, "중복": 0},
                  "progress": {c: {"title": t.get("titles", {}).get(c, c), "seats": []} for c in cards},
                  "seats": {n: {"text": "작업중"} for n in t["seats"]}, "oppa_todo": [], "axes": []})
print(json.dumps({"date": "2026-11-16", "verdicts": [], "issues": [], "teams": teams}, ensure_ascii=False))
PY
}
goal() { { echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; } > "$T/goal.md"; }
reset() { rm -f "$T/last.json" "$T/body.txt"; }
run() { rm -f "$T/body.txt"; env FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="$1" python3 "$BIN/ft_board_news.py" \
  --collect "$T/collect.json" --last "$T/last.json" --body "$T/body.txt" --state "$T/last.json" > "$T/out" 2> "$T/err"; echo $? > "$T/rc"; }
body() { cat "$T/body.txt" 2>/dev/null; }
# group — «진행 중인 일» 묶음(골 줄 뒤 · «다음» 앞) 줄들
group() { body | awk '/^진행 중인 일/{on=1} /^다음$/{on=0} on'; }
TEAM1='{"label":"하네스","seats":{"byz-t0-nano-r2201-alpha#0":"r2201-alpha","byz-t0-worker-x#1":null},"titles":{"r2201-alpha":"r2201-alpha 알파 일 고치기"}}'
TEAM2='{"label":"개발","seats":{"byz-t1-nano-r2202-beta#0":"r2202-beta"},"titles":{"r2202-beta":"r2202-beta — 끝: 베타 일 (설명)"}}'

# ① 막대(A1)
reset; goal "1 | 골 셋 | 3 | 10 | 진행" "2 | 골 하나 | 1 | 3 | 시작" "3 | 골 영 | 0 | 5 | 준비" "4 | 골 대시 | — | — | 따로 셈" "5 | 골 칠 | 7 | 5 | 이상"
mk "[$TEAM1]"; run 2026-11-16T10:00:00
chk "① 3/10 → «골 셋 ▓▓▓░░░░░░░ 3/10. 진행»" 'body | grep -qxF "골 셋 ▓▓▓░░░░░░░ 3/10. 진행"'
chk "① 1/3 → 채운 칸 3(내림)" 'body | grep -qxF "골 하나 ▓▓▓░░░░░░░ 1/3. 시작"'
chk "① 0/5 → 채운 칸 0" 'body | grep -qxF "골 영 ░░░░░░░░░░ 0/5. 준비"'
chk "① «—» → 막대 0 · «<골>: <상태>»" 'body | grep -qxF "골 대시: 따로 셈"'
chk "① 7/5 → «수 판독 불가» · 막대 0" 'body | grep -qxF "골 칠: 수 판독 불가. 이상"'
chk "① 본문에 «\`\`\`» · «|» 로 시작하는 줄 0" '! body | grep -q "^\`\`\`\|^|" && [ -s "$T/body.txt" ]'

# ② 진행 중인 일(A2)
reset; goal "1 | 골 셋 | 3 | 10 | 진행"; mk "[$TEAM1,$TEAM2]"; run 2026-11-16T10:10:00
WANT2="$(printf '%s\n' "진행 중인 일" "개발: 베타 일, 진행" "하네스: 알파 일 고치기, 진행" "카드 없이 열린 좌석 1석")"
chk "② 좌석 3(팀 2) → 머리 + 2줄(팀 이름 순) + «카드 없이 열린 좌석 1석»" '[ "$(group)" = "$WANT2" ]'
chk "② 묶음 줄에 좌석 이름 · «#» · r번호 0" '! group | grep -q "byz-\|#\|r22"'
chk "② 묶음 = 골 줄 바로 뒤 · «다음» 바로 앞" '[ "$(body | grep -B1 -x "진행 중인 일")" = "$(printf "%s\n" "골 셋 ▓▓▓░░░░░░░ 3/10. 진행" "진행 중인 일")" ] && [ "$(body | grep -B1 -x "다음" | head -1)" = "카드 없이 열린 좌석 1석" ]'
S11="$(python3 -c 'import json; print(json.dumps({"label":"하네스","seats":{f"byz-t0-nano-r2301-w{i:02d}#0":f"r2301-w{i:02d}" for i in range(11)},"titles":{f"r2301-w{i:02d}":f"r2301-w{i:02d} 일 {i:02d}" for i in range(11)}}, ensure_ascii=False))')"
reset; mk "[$S11]"; run 2026-11-16T10:20:00
WANT11="$(printf '%s\n' "진행 중인 일" "하네스: 일 00, 진행" "하네스: 일 01, 진행" "하네스: 일 02, 진행" "하네스: 일 03, 진행" "하네스: 일 04, 진행" "하네스: 일 05, 진행" "하네스: 일 06, 진행" "하네스: 일 07, 진행" "그 밖 3개")"
chk "② 카드 있는 좌석 11 → 8줄 + «그 밖 3개»" '[ "$(group)" = "$WANT11" ]'
reset; mk '[{"label":"하네스","seats":{}}]'; run 2026-11-16T10:30:00
chk "② 열린 좌석 0 → «진행 중인 일 없음» 1줄" '[ "$(body | grep -A1 -x "골 셋 ▓▓▓░░░░░░░ 3/10. 진행")" = "$(printf "%s\n" "골 셋 ▓▓▓░░░░░░░ 3/10. 진행" "진행 중인 일 없음")" ]'
reset; mk '[{"label":"하네스","seats":{"byz-t0-nano-r2203-gamma#0":"r2203-gamma"},"titles":{"r2203-gamma":"r2203-gamma 알림 <@U0AC2JF0M7D> 확인"}}]'; run 2026-11-16T10:40:00
chk "② 하는 일 이름 «<@U0AC2JF0M7D>» → «@U0AC2JF0M7D» · 본문 «<@» 0(승인 대기 0)" 'body | grep -qxF "하네스: 알림 @U0AC2JF0M7D 확인, 진행" && ! body | grep -q "<@"'

# ③ 열쇠(A3)
reset; goal "1 | 골 셋 | 3 | 10 | 진행"; mk "[$TEAM1]"; run 2026-11-16T11:00:00
mk "[$TEAM1,$TEAM2]"; run 2026-11-16T11:10:00
chk "③ 같은 골 표 + 좌석만 바뀜 → «변화 없음 — 발행 0»" 'grep -qx "변화 없음 — 발행 0" "$T/out" && [ ! -e "$T/body.txt" ]'
goal "1 | 골 셋 | 4 | 10 | 진행"; run 2026-11-16T11:20:00
chk "③ n 3 → 4 → POST · 막대 채운 칸 4" 'grep -qx POST "$T/out" && body | grep -qxF "골 셋 ▓▓▓▓░░░░░░ 4/10. 진행"'
# ⑤ 줄 순서(A5) — 바뀐 것 줄이 있는 본문
chk "⑤ 줄 순서 = 머리 → 지금 → 바뀐 것 → 골 줄 → 진행 중인 일 → 다음 → 막힌 것, 오빠 할 일 → 근거" '[ "$(body | sed -n "1s/^골 진행 알림:.*/머리/p;2p;3s/^바뀜:.*/바뀜/p;4s/^골 셋 .*/골/p;5p;/^다음$/p;/^막힌 것, 오빠 할 일$/p;\$s/^근거:.*/근거/p" | tr "\n" " ")" = "머리 지금 바뀜 골 진행 중인 일 다음 막힌 것, 오빠 할 일 근거 " ]'

# ④ 길이(A4) — 본문 직접(판정문 R1 꼴 입력) + CLI 2회(rc)
python3 - "$BIN" "$T" <<'PY' > "$T/len.out" 2>&1
import sys
from datetime import datetime
sys.path.insert(0, sys.argv[1])
import ft_board_news_body as b
fails = 0
def chk(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name); fails += 0 if cond else 1
NOW, SHA = datetime(2026, 11, 16, 15), "1234567890"
def cur(size, nxt="", seats=8):
    return {"goals": [[str(i), f"골{i}", "1", "3", "가" * size, nxt] for i in range(1, 10)], "h": 0, "carried": [], "cards": {}, "err": [],
            "sessions": {f"seat{i}": ["팀", f"card{i}", "진행"] for i in range(seats)}}
def base(size, steps):  # 기준판(r2102) 본문 — 막대 0 · 묶음 0 · «다음» 칸 접기
    for k in range(len(steps), -1, -1):
        nxt = steps[:k] + ([f"그 밖의 골 {len(steps) - k}개"] if k < len(steps) else []) if steps else ["정해진 다음 한 수 없음"]
        lines = ["골 진행 알림: 열린 골 9개, 닫힌 골 0개", "지금", *[f"골{i}: 3단계 중 1단계 끝남. {'가' * size}" for i in range(1, 10)],
                 "다음", *nxt, "막힌 것, 오빠 할 일", "없음", f"근거: 발행 {NOW:%Y-%m-%d %H:%M}, 골 진행 원장 {SHA}"]
        out = "\n".join(lines) + "\n"
        if len(out.encode()) <= 3500:
            break
    return out
def whole(out, size):  # 골 이름 · 상태 글 글자 같음 · 막대 = 9줄 모두 | 0줄
    bars = sum(f"골{i} ▓▓▓░░░░░░░ 1/3. {'가' * size}" in out.splitlines() for i in range(1, 10))
    plain = sum(f"골{i}: 3단계 중 1단계 끝남. {'가' * size}" in out.splitlines() for i in range(1, 10))
    return (bars, plain) in ((9, 0), (0, 9))
o = b.body(cur(108), None, NOW, SHA)
chk(f"④ R1 입력 → ⓑ 단계 3488B(실측 {len(o.encode())}B) · 막대 9줄 · «진행 중인 일» 0회",
    len(o.encode()) == 3488 and o.count("▓▓▓░░░░░░░ 1/3.") == 9 and "진행 중인 일" not in o and whole(o, 108))
o = b.body(cur(104), None, NOW, SHA)
kept = [ln for ln in o.splitlines() if ln.startswith("팀: card")]
chk(f"④ ⓐ 단계 → 막대 있음 · 진행 줄 아래부터 줄어 {len(kept)}줄 + «그 밖 {8 - len(kept)}개» · {len(o.encode())}B ≤ 3500B",
    0 < len(kept) < 8 and kept == [f"팀: card{i}, 진행" for i in range(len(kept))] and f"그 밖 {8 - len(kept)}개" in o.splitlines()
    and "진행 중인 일" in o.splitlines() and o.count("▓") > 0 and len(o.encode()) <= 3500 and whole(o, 104))
o = b.body(cur(110), None, NOW, SHA)
chk(f"④ ⓒ 단계 → 기준판 본문과 글자 같음({len(o.encode())}B) · 막대 0 · 묶음 0줄",
    o == base(110, []) and "▓" not in o and "░" not in o and "진행 중인 일" not in o and whole(o, 110))
steps = [f"골{i}: {'나' * 60}" for i in range(1, 10)]
o = b.body(cur(60, "나" * 60), None, NOW, SHA)
chk(f"④ ⓓ 단계 → 기준판 «다음» 칸 접기와 글자 같음({len(o.encode())}B)", o == base(60, steps) and "그 밖의 골" in o and whole(o, 60))
o = b.body(cur(120), None, NOW, SHA)
chk(f"④ 기준판에서도 넘는 입력 → 출력 = 기준판 본문({len(o.encode())}B)", o == base(120, []) and len(o.encode()) > 3500 and whole(o, 120))
open(f"{sys.argv[2]}/over.bytes", "w").write(str(len(base(120, []).encode())))
sys.exit(1 if fails else 0)
PY
cat "$T/len.out"; fail=$((fail + $(grep -c '^FAIL' "$T/len.out"))); grep -q '^PASS' "$T/len.out" || bad "④ 길이 시험 못 돎"
nine() { local s="$1" r=(); for i in 1 2 3 4 5 6 7 8 9; do r+=("$i | 골$i | 1 | 3 | $s"); done; goal "${r[@]}"; }
S8="$(python3 -c 'import json; print(json.dumps({"label":"팀","seats":{f"byz-t0-nano-card{i}#0":f"card{i}" for i in range(8)}}))')"
reset; nine "$(python3 -c 'print("가"*108)')"; mk "[$S8]"; run 2026-11-16T15:00:00
chk "④ R1 입력(CLI) → rc 0 · POST · 본문 3488B" '[ "$(cat "$T/rc")" = 0 ] && grep -qx POST "$T/out" && [ "$(wc -c < "$T/body.txt" | tr -d " ")" = 3488 ]'
reset; nine "$(python3 -c 'print("가"*120)')"; run 2026-11-16T15:00:00
chk "④ 기준판에서도 넘는 입력(CLI) → rc 1 · «본문 $(cat "$T/over.bytes")B > 3500B» · 본문 0" '[ "$(cat "$T/rc")" = 1 ] && grep -q "본문 $(cat "$T/over.bytes")B > 3500B — 발행 0" "$T/err" && [ ! -e "$T/body.txt" ]'

# ⑤ bin = kit 사본(A5)
[ -z "${R2103_BIN:-}" ] && chk "⑤ bin 과 kit 사본 cmp 0" 'cmp -s "$BIN/ft_board_news_body.py" "$HERE/../kit/fable-team/bin/ft_board_news_body.py"'

echo "fail=$fail"; [ "$fail" = 0 ]
