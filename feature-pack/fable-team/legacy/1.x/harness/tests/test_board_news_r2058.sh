#!/usr/bin/env bash
# test_board_news_r2058.sh — ft-board-publish.sh --news (r2058 · 판정 4175): 바뀌었을 때만 오빠 thread 에 답글 1통 · 5분 디바운스 · 골 진행 막대.
# 실 Slack 0 · 실 tmux 0 · sleep 0: FT_BOARD_BIN 스텁(collect --out = 준비한 dict) · FT_THREAD_POST 스텁(인자·본문을 파일에) · 시계 FT_BOARD_NOW.
# R2058_BIN = 시험할 bin 폴더(변이 사본용 · 기본 harness/bin).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BIN="${R2058_BIN:-$ROOT/harness/bin}"
PUB="$BIN/ft-board-publish.sh"
TSV=1794729663.977629
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ft/.fable-team" "$T/stub"
LAST="$T/ft/.fable-team/state/board/news-last.json"

cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
D="$(dirname "$0")"
[ -f "$D/collect_rc" ] && exit "$(cat "$D/collect_rc")"
[ "$1 $2" = "collect --out" ] || exit 9
cp "$D/collect.json" "$3"
EOF
chmod +x "$T/stub/board"
cat > "$T/stub/tp.py" <<'EOF'
import os, sys
d = os.path.dirname(os.path.abspath(__file__))
n = sum(1 for _ in open(f"{d}/tp.log")) if os.path.exists(f"{d}/tp.log") else 0
open(f"{d}/tp.log", "a").write(" ".join(sys.argv[1:]) + "\n")
body = open(sys.argv[sys.argv.index("--text-file") + 1], encoding="utf-8").read()
open(f"{d}/body.{n + 1}.txt", "w", encoding="utf-8").write(body)
sys.exit(int(open(f"{d}/tp_rc").read()) if os.path.exists(f"{d}/tp_rc") else 0)
EOF
# mk <spec json> — 한 팀(하네스) collect dict. spec: cards{id:폴더} · seats{이름:글자} · on{좌석:진행 카드} · h[번호] · nseats(추가 좌석 수)
cat > "$T/stub/mk.py" <<'EOF'
import json, sys
s = json.loads(sys.argv[1]); cards = s.get("cards", {}); seats = dict(s.get("seats", {}))
for i in range(s.get("nseats", 0)):
    seats[f"byz-harness-worker-x{i:02d}#1"] = "작업중"
for i in range(s.get("ncards", 0)):  # r2063: 카드 든 나노 좌석(진행 카드 c<i>)
    cards[f"c{i:02d}"] = "진행"; seats[f"byz-harness-nano-c{i:02d}#0"] = "작업중"
tt = s.get("titles", {})  # r2058 R5: 카드 제목 = axes entries(k=card) · progress title
prog = {c: {"title": tt.get(c, c), "seats": [{"name": n, "state": seats[n]} for n, cc in s.get("on", {}).items() if cc == c]}
        for c, st in cards.items() if st == "진행"}
counts = {k: sum(1 for v in cards.values() if v == k) for k in ("완성", "진행", "대기", "중복")}
team = {"key": "harness", "label": "하네스", "states": cards, "counts": counts, "progress": prog,
        "seats": {n: {"text": t} for n, t in seats.items()}, "oppa_todo": s.get("h", []),
        "axes": [{"title": "축", "entries": [{"k": "card", "idx": c, "text": t} for c, t in tt.items()]}]}
if s.get("err"):  # r2058 R1: 팀 수집 부분 실패 = {key,label,error} 블록 · 전체 rc 0
    team = {"key": "harness", "label": "하네스", "error": "inbox 조회 시간 초과"}
print(json.dumps({"date": "2026-11-15", "verdicts": [], "issues": [], "teams": [team, {"key": "x", "label": "엑스", "error": "깨짐"}]}, ensure_ascii=False))
EOF
mk() { python3 "$T/stub/mk.py" "$1" > "$T/stub/collect.json"; }
goal() { { echo "# 원장"; echo; echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; echo; echo "## 다른 절"; } > "$T/goal.md"; }
reset() { rm -rf "$T/ft/.fable-team/state" "$T/stub/tp.log" "$T/stub"/body.*.txt "$T/stub/tp_rc" "$T/stub/collect_rc"; }
replies() { [ -f "$T/stub/tp.log" ] && wc -l < "$T/stub/tp.log" | tr -d ' ' || echo 0; }
lastbody() { cat "$T/stub/body.$(replies).txt"; }
now_section() { lastbody | awk '/^② 지금/{f=1;next} /^③ /{f=0} f'; }
next_section() { lastbody | awk '/^③ 다음/{f=1;next} /^④ /{f=0} f'; }
run() { RC=0; env -u FT_BOARD_THREAD_TS FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" \
  FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="$1" ${TS_ENV-FT_BOARD_THREAD_TS=$TSV} bash "$PUB" --news > "$T/out" 2> "$T/err" || RC=$?; }

BASE='{"cards":{"r2058-oppa-a":"대기","r2059-beta":"진행"},"seats":{"byz-harness-nano-r2059-beta#0":"작업중","byz-harness-master-pi#283":"정지 3분"},"h":[7]}'
G1="1 | ft 2.0 완성 | 20 | 23 | 진행 중"; G2="2 | 하네스 운영 | 3 | 5 | 진행 중"

# ① 첫 실행
reset; goal "$G1" "$G2"; mk "$BASE"; run 2026-11-15T10:00:00
chk "① rc 0" '[ "$RC" = 0 ]'
chk "① reply 1회" '[ "$(replies)" = 1 ]'
chk "① --ts $TSV" 'grep -q -- "reply.*--ts $TSV" "$T/stub/tp.log"'
chk "① 막대 2줄" '[ "$(lastbody | grep -c "[▓░]")" = 2 ]'
chk "① 20/23 막대 8칸" 'lastbody | grep -qF "ft 2.0 완성 \`▓▓▓▓▓▓▓▓░░\` 20/23"'
chk "① news-last 생김" '[ -f "$LAST" ]'
chk "① 다음 줄 = 세션별" 'next_section | grep -qF "하네스 · nano-beta · beta · 진행"'
chk "① 오빠 할 일 1건" 'lastbody | grep -q "1건"'
chk "⑫ 첫 발행 = «엑스 확인 불가» 0줄(직전에 없던 error 팀)" '! lastbody | grep -q "엑스 확인 불가"'
# ② 같은 입력 +600초
run 2026-11-15T10:10:00
chk "② rc 0 · reply 0 · 변화 없음" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && grep -q "변화 없음" "$T/out"'
# ④ 열쇠 밖 변화만(좌석 BUSY→IDLE · 유휴 분 · 시각)
mk "${BASE//작업중/⚠정지 9분(턴 끝 10:05)}"; run 2026-11-15T10:20:00
chk "④ reply 0" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ]'
# ⑤ 골 20/23 → 21/23 → 23/23
goal "1 | ft 2.0 완성 | 21 | 23 | 진행 중" "$G2"; run 2026-11-15T10:30:00
chk "⑤ reply 1회" '[ "$(replies)" = 2 ]'
chk "⑤ 지금 «20→21 (23 중)»" 'now_section | grep -qF "ft 2.0 완성 20→21 (23 중)"'
chk "⑤ 막대 9칸" 'lastbody | grep -qF "\`▓▓▓▓▓▓▓▓▓░\` 21/23"'
goal "1 | ft 2.0 완성 | 23 | 23 | 끝" "$G2"; run 2026-11-15T10:40:00
chk "⑤ 23/23 완성" 'lastbody | grep -qE "\`▓{10}\` 23/23 완성$"'
# ⑥ 카드 대기→진행 + 세션 새로 열림(같은 틱) → 지금 2줄
mk '{"cards":{"r2058-oppa-a":"진행","r2059-beta":"진행"},"seats":{"byz-harness-nano-r2059-beta#0":"작업중","byz-harness-master-pi#283":"정지 3분","byz-harness-nano-r2058-oppa-a#0":"작업중"},"h":[7]}'
run 2026-11-15T10:50:00
chk "⑥ reply 1회" '[ "$(replies)" = 4 ]'
chk "⑥ 지금 2줄" '[ "$(now_section | wc -l | tr -d " ")" = 2 ]'
chk "⑥ 카드 줄" 'now_section | grep -qF "하네스 oppa-a 대기→진행"'
chk "⑥ 세션 줄" 'now_section | grep -qF "nano-oppa-a 열림"'
mk '{"cards":{"r2058-oppa-a":"진행","r2059-beta":"진행","c1":"대기","c2":"대기","c3":"대기","c4":"대기","c5":"대기","c6":"대기","c7":"대기"},"seats":{"byz-harness-nano-r2059-beta#0":"작업중","byz-harness-master-pi#283":"정지 3분","byz-harness-nano-r2058-oppa-a#0":"작업중"},"h":[7]}'
run 2026-11-15T11:00:00
chk "⑥ 7건 → 5줄 + 외 2건" '[ "$(now_section | wc -l | tr -d " ")" = 6 ] && now_section | tail -1 | grep -qx "외 2건"'
# ⑦ 디바운스
reset; goal "$G1" "$G2"; mk "$BASE"; run 2026-11-15T12:00:00
cp "$LAST" "$T/last0"
goal "1 | ft 2.0 완성 | 21 | 23 | 진행 중" "$G2"; run 2026-11-15T12:02:00
chk "⑦ 120초 = reply 0 · news-last 그대로" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && cmp -s "$LAST" "$T/last0"'
goal "1 | ft 2.0 완성 | 21 | 23 | 진행 중" "2 | 하네스 운영 | 4 | 5 | 진행 중"; run 2026-11-15T12:05:00
chk "⑦ 300초 = reply 1회 · 변화 2건" '[ "$(replies)" = 2 ] && now_section | grep -qF "20→21" && now_section | grep -qF "3→4"'
# ③ 발행 실패 → rc 1 · news-last 그대로 → 다음 실행 같은 변화로 1회
reset; goal "$G1" "$G2"; mk "$BASE"; echo 1 > "$T/stub/tp_rc"; run 2026-11-15T13:00:00
chk "③ 첫 실행 실패 rc 1 · news-last 없음" '[ "$RC" = 1 ] && [ ! -f "$LAST" ]'
rm -f "$T/stub/tp_rc"; run 2026-11-15T13:10:00
chk "③ 성공 스텁 = 발행" '[ "$RC" = 0 ] && [ -f "$LAST" ]'
cp "$LAST" "$T/last1"; goal "1 | ft 2.0 완성 | 21 | 23 | 진행 중" "$G2"; echo 1 > "$T/stub/tp_rc"; run 2026-11-15T13:20:00
chk "③ 실패 rc 1 · news-last 그대로" '[ "$RC" = 1 ] && cmp -s "$LAST" "$T/last1"'
n0="$(replies)"; rm -f "$T/stub/tp_rc"; run 2026-11-15T13:30:00
chk "③ 다음 실행 = 같은 변화로 1회" '[ "$RC" = 0 ] && [ "$(replies)" = $((n0 + 1)) ] && now_section | grep -qF "20→21"'
# ⑧ 골 진행 절 없음 · n=— · n>m · thread ts 없음 · collect 실패
reset; printf '# 원장\n\n## 다른 절\n' > "$T/goal.md"; mk "$BASE"; run 2026-11-15T14:00:00
chk "⑧ 절 없음 = reply 1회 · 표 없음 1줄 · WARN" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && lastbody | grep -q "골 진행 표 없음" && grep -q WARN "$T/err" && lastbody | grep -q "^② 지금"'
reset; goal "1 | ft 2.0 완성 | — | — | 정본 확인 중" "2 | 하네스 운영 | 25 | 23 | 진행 중"; run 2026-11-15T14:00:00
chk "⑧ n=— = 막대 없는 줄" 'lastbody | grep -qx "ft 2.0 완성 — 정본 확인 중"'
chk "⑧ n>m = 수 판독 불가" 'lastbody | grep -qx "하네스 운영 수 판독 불가" && [ "$(lastbody | grep -c "[▓░]")" = 0 ]'
reset; goal "$G1"; TS_ENV= run 2026-11-15T14:00:00
chk "⑧ thread ts 없음 = rc 2 · reply 0" '[ "$RC" = 2 ] && [ "$(replies)" = 0 ] && grep -q ERROR "$T/err"'
reset; echo 1 > "$T/stub/collect_rc"; run 2026-11-15T14:00:00
chk "⑧ collect rc 1 = rc 1 · reply 0" '[ "$RC" = 1 ] && [ "$(replies)" = 0 ]'
# ⑨ 꼴: 30석 → 12줄 + 외 18석 · 표·코드블록 0 · 3500B · 끝 줄 밖 번호·sha·ts 0
reset; goal "$G1" "$G2"; mk '{"cards":{"r2058-oppa-a":"대기"},"seats":{},"ncards":30}'; run 2026-11-15T15:00:00
chk "⑨ 다음 = 12줄 + 외 18석" '[ "$(next_section | wc -l | tr -d " ")" = 13 ] && next_section | tail -1 | grep -qx "외 18석"'
mk "$BASE"; run 2026-11-15T15:10:00
for f in "$T/stub"/body.*.txt; do
  chk "⑨ $(basename "$f") 표·코드블록 0 · 3500B" '! grep -q "|---" "$f" && ! grep -qF "\`\`\`" "$f" && [ "$(wc -c < "$f")" -le 3500 ]'
  chk "⑨ $(basename "$f") 끝 줄 밖 번호·sha·ts 0" '! sed "\$d" "$f" | grep -qE "r[0-9]{3,4}|[0-9a-f]{10,}|[0-9]{10}\.[0-9]{6}|#[0-9]+"'
done
chk "⑨ kit 사본 = bin" 'cmp -s "$ROOT/harness/bin/ft-board-publish.sh" "$ROOT/harness/kit/fable-team/bin/ft-board-publish.sh" && cmp -s "$ROOT/harness/bin/ft_board_news.py" "$ROOT/harness/kit/fable-team/bin/ft_board_news.py"'
PL="$ROOT/harness/kit/slack-mirror/com.byz.ft-board-news.plist.template"; OLD="$ROOT/harness/kit/slack-mirror/com.byz.ft-board-publish.plist.template"
chk "⑨ plist 템플릿" 'python3 - "$PL" "$OLD" <<'"'"'PY'"'"'
import plistlib, sys
d = plistlib.loads(open(sys.argv[1], "rb").read()); o = plistlib.loads(open(sys.argv[2], "rb").read())
e = d["EnvironmentVariables"]
assert d["Label"] == "com.byz.ft-board-news" and d["ProgramArguments"][-1] == "--news"
assert d["StartInterval"] == 300 and d["RunAtLoad"] is False and d["ProcessType"] == "Interactive"
assert e["FT_BOARD_THREAD_TS"] == "1794729663.977629" and e["FT_ROOT"] == "__BYZ_ROOT__" and e["PATH"] == o["EnvironmentVariables"]["PATH"]
assert o["ProgramArguments"][-1] == "--sheet"
PY'

# ⑩ 정상 → 팀 수집 부분 실패 → 복구 (DA R1): 거짓 «닫힘»·«→없음»·«열림» 0
reset; goal "$G1" "$G2"; mk "$BASE"; run 2026-11-15T16:00:00
cp "$LAST" "$T/last10"; mk '{"err":true}'; run 2026-11-15T16:10:00
chk "⑩ 부분 실패만 = reply 0 · news-last 그대로" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && cmp -s "$LAST" "$T/last10"'
goal "1 | ft 2.0 완성 | 21 | 23 | 진행 중" "$G2"; run 2026-11-15T16:20:00
chk "⑩ 부분 실패 + 골 변화 = reply 1 · 지금 = 골 1줄" '[ "$(replies)" = 2 ] && [ "$(now_section | wc -l | tr -d " ")" = 1 ] && now_section | grep -qF "20→21"'
chk "⑩ 본문 «하네스 확인 불가» 1줄" '[ "$(lastbody | grep -c "^하네스 확인 불가")" = 1 ] && ! lastbody | grep -qE "닫힘|→없음"'
chk "⑫ 부분 실패 본문에도 «엑스 확인 불가» 0줄" '! lastbody | grep -q "엑스 확인 불가"'
chk "⑬ 팀 수집 실패 중 «오빠 승인 대기 1건» 유지" 'lastbody | grep -qx "오빠 승인 대기 1건" && ! lastbody | grep -qx "없음"'
mk "$BASE"; run 2026-11-15T16:30:00
chk "⑩ 복구 = 가짜 열림 0 · reply 0" '[ "$RC" = 0 ] && [ "$(replies)" = 2 ]'
reset; goal "$G1"; mk '{"err":true}'; run 2026-11-15T17:00:00
mk "$BASE"; run 2026-11-15T17:10:00
chk "⑩ 첫 발행부터 실패 → 복구 = 열림·없음→ 0" '[ "$(replies)" = 2 ] && ! now_section | grep -qE "열림|없음→"'
# ⑪ 명부 닫힌 좌석 제외 + BUSY/IDLE 무발행 (DA R2)
reset; goal "$G1"; mk "${BASE/\"byz-harness-master-pi/\"byz-harness-arch-pi#9\":\"닫힘\",\"byz-harness-master-pi}"; run 2026-11-15T18:00:00
chk "⑪ 닫힌 좌석 = 다음 줄 0" '[ "$(replies)" = 1 ] && ! next_section | grep -q "arch-pi"'
mk "${BASE//작업중/⚠정지 9분(턴 끝 17:55)}"; run 2026-11-15T18:10:00
chk "⑪ 닫힌 좌석 빠짐 + BUSY/IDLE 만 = reply 0" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ]'
# ⑭ 본문의 카드 = «하는 일 이름» (R5) · 제목만 바뀜 = 발행 0
TB='"r2059-beta":"r2059-beta — 끝: 보드 뉴스 이름 시험(판정 4175 · #308536)","r2060-long":"r2060-long — 아주아주 긴 하는 일 이름이 스물다섯 글자를 넘는 경우"'
S14='"seats":{"byz-harness-nano-r2059-beta#0":"작업중"}'
reset; goal "$G1"; mk "{\"cards\":{\"r2058-oppa-a\":\"대기\",\"r2059-beta\":\"진행\",\"r2060-long\":\"대기\"},$S14,\"titles\":{$TB}}"; run 2026-11-15T19:00:00
chk "⑭ 다음 줄 = 하는 일 이름" 'next_section | grep -qxF "하네스 · nano-beta · 보드 뉴스 이름 시험 · 진행"'
mk "{\"cards\":{\"r2058-oppa-a\":\"진행\",\"r2059-beta\":\"완성\",\"r2060-long\":\"진행\"},$S14,\"titles\":{$TB}}"; run 2026-11-15T19:10:00
chk "⑭ 지금 = 이름 · beta slug 0" 'now_section | grep -qxF "하네스 보드 뉴스 이름 시험 진행→완성" && ! now_section | grep -q beta'
chk "⑭ 25자 넘는 제목 = 24자 + …" 'now_section | grep -qxF "하네스 아주아주 긴 하는 일 이름이 스물다섯 글자를… 대기→진행"'
chk "⑭ 제목 없는 카드 = slug" 'now_section | grep -qxF "하네스 oppa-a 대기→진행"'
chk "⑭ 근거 줄 = ② 카드 번호 순서" 'lastbody | tail -1 | grep -q " · 카드 r2058 r2059 r2060$"'
n14="$(replies)"; mk "{\"cards\":{\"r2058-oppa-a\":\"진행\",\"r2059-beta\":\"완성\",\"r2060-long\":\"진행\"},$S14,\"titles\":{\"r2059-beta\":\"다른 제목\"}}"; run 2026-11-15T19:20:00
chk "⑭ 제목만 바뀜 = reply 0" '[ "$RC" = 0 ] && [ "$(replies)" = "$n14" ]'
# ⑮ L 번호 카드 → ② 줄에 번호 0 · 근거 줄에 «카드 L102» (R6)
TL='"titles":{"L102-sealed-gap":"L102-sealed-gap — 켬 강의 번역 빈칸"}'
reset; goal "$G1"; mk "{\"cards\":{\"L102-sealed-gap\":\"진행\"},$TL}"; run 2026-11-15T20:00:00
mk "{\"cards\":{\"L102-sealed-gap\":\"완성\"},$TL}"; run 2026-11-15T20:10:00
chk "⑮ ② 줄 = 이름 · L102 0" 'now_section | grep -qxF "하네스 켬 강의 번역 빈칸 진행→완성" && ! now_section | grep -q L102'
chk "⑮ 근거 줄 «카드 L102»" 'lastbody | tail -1 | grep -q " · 카드 L102$"'
chk "⑮ 끝 줄 밖 번호 0" '! lastbody | sed "\$d" | grep -qE "r[0-9]{3,4}|L[0-9]{2,}|[0-9a-f]{10,}|[0-9]{10}\.[0-9]{6}|#[0-9]+"'

echo "fail=$fail"; [ "$fail" = 0 ]
