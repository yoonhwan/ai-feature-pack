#!/usr/bin/env bash
# test_board_news_bar_fold_r2063.sh — 보드 뉴스 막대 내림 · 카드 없는 좌석 1줄 접기 · 채널 env · 뉴스 답글 머리줄 끔 (r2063 반례 ①~⑥ · ⑨).
# 실 Slack 0 · 실 tmux 0 · sleep 0: FT_BOARD_BIN 스텁(collect --out = 준비한 dict) · FT_THREAD_POST 스텁(인자·본문을 파일에) · 시계 FT_BOARD_NOW.
# R2063_BIN = 시험할 bin 폴더(변이 사본용 · 기본 harness/bin) · R2063_BASE_BIN = 기준판 bin(기본 = 팩 origin/main 의 bin 을 임시 폴더에 꺼냄).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BIN="${R2063_BIN:-$ROOT/harness/bin}"
TSV=1794729663.977629
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ft/.fable-team" "$T/stub" "$T/base"
LAST="$T/ft/.fable-team/state/board/news-last.json"
REL="feature-pack/fable-team/legacy/1.x/harness"
BASE="${R2063_BASE_BIN:-}"
if [ -z "$BASE" ]; then
  BASE="$T/base"
  for f in ft-board-publish.sh ft_board_news.py ft_board_news_name.py; do
    git -C "$HERE" show "origin/main:$REL/bin/$f" > "$BASE/$f" 2>/dev/null || { echo "판정 불가 — 기준판 $f 못 꺼냄(git show origin/main)"; exit 2; }
  done
  git -C "$HERE" show "origin/main:$REL/kit/slack-mirror/com.byz.ft-board-news.plist.template" > "$T/base.plist" 2>/dev/null \
    || { echo "판정 불가 — 기준판 plist 못 꺼냄"; exit 2; }
fi

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
body = open(sys.argv[sys.argv.index("--text-file") + 1], encoding="utf-8").read()
open(f"{d}/body.{n + 1}.txt", "w", encoding="utf-8").write(body)
EOF
# mk <spec json> — 팀 목록 collect dict. 팀: label · key · card(카드 든 나노 좌석 수 = 진행 카드 c<i>) · bare(카드 없는 좌석 수) · miss(카드 파일 없는 나노 좌석 수) · err
cat > "$T/stub/mk.py" <<'EOF'
import json, sys
teams = []
for s in json.loads(sys.argv[1]):
    k = s["key"]
    if s.get("err"):
        teams.append({"key": k, "label": s["label"], "error": "inbox 조회 시간 초과"}); continue
    cards = {f"{k}c{i:02d}": "진행" for i in range(s.get("card", 0))}
    seats = {f"byz-{k}-nano-{c}#0": "작업중" for c in cards}
    seats.update({f"byz-{k}-lead-x{i:02d}#1": "정지 3분" for i in range(s.get("bare", 0))})
    seats.update({f"byz-{k}-nano-gone{i}#0": "작업중" for i in range(s.get("miss", 0))})
    counts = {f: sum(1 for v in cards.values() if v == f) for f in ("완성", "진행", "대기", "중복")}
    teams.append({"key": k, "label": s["label"], "states": cards, "counts": counts, "progress": {c: {"title": c, "seats": []} for c in cards},
                  "seats": {n: {"text": t} for n, t in seats.items()}, "oppa_todo": [], "axes": []})
print(json.dumps({"date": "2026-11-16", "verdicts": [], "issues": [], "teams": teams}, ensure_ascii=False))
EOF
mk() { python3 "$T/stub/mk.py" "$1" > "$T/stub/collect.json"; }
goal() { { echo "# 원장"; echo; echo "## 골 진행"; echo; echo "| 골 번호 | 골 짧은 이름 | 닫힘 n | 전체 m | 지금 상태 1줄 |"; echo "|---|---|---|---|---|"
  for r in "$@"; do echo "| $r |"; done; echo; echo "## 다른 절"; } > "$T/goal.md"; }
reset() { rm -rf "$T/ft/.fable-team/state" "$T/stub/tp.log" "$T/stub"/body.*.txt; }
replies() { [ -f "$T/stub/tp.log" ] && wc -l < "$T/stub/tp.log" | tr -d ' ' || echo 0; }
lastbody() { cat "$T/stub/body.$(replies).txt"; }
now_section() { lastbody | awk '/^② 지금/{f=1;next} /^③ /{f=0} f'; }
next_section() { lastbody | awk '/^③ 다음/{f=1;next} /^④ /{f=0} f'; }
# run <시각> [bin] — FT_BOARD_POST_ARGS 는 부르는 쪽 env 그대로(없으면 비움)
run() { RC=0; env -u FT_BOARD_THREAD_TS FT_ROOT="$T/ft" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" \
  FT_GOAL_PROGRESS_MD="$T/goal.md" FT_BOARD_NOW="$1" FT_BOARD_THREAD_TS=$TSV FT_BOARD_POST_ARGS="${PA:-}" \
  bash "${2:-$BIN}/ft-board-publish.sh" --news > "$T/out" 2> "$T/err" || RC=$?; }
H='{"key":"harness","label":"하네스"'

# ① · ② 막대 내림
reset; goal "1 | 골 22 | 22 | 23 | 진행" "2 | 골 23 | 23 | 23 | 끝" "3 | 골 0 | 0 | 23 | 시작" "4 | 골 20 | 20 | 23 | 진행" \
  "5 | 골 1 | 1 | 23 | 진행" "6 | 골 5of6 | 5 | 6 | 진행" "7 | 골 넘침 | 25 | 23 | 진행"
mk "[$H}]"; run 2026-11-16T10:00:00
chk "① rc 0 · reply 1" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ]'
chk "① 22/23 = 9칸 · 완성 0" 'lastbody | grep -qxF "골 22 \`▓▓▓▓▓▓▓▓▓░\` 22/23"'
chk "② 23/23 = 10칸 완성" 'lastbody | grep -qxF "골 23 \`▓▓▓▓▓▓▓▓▓▓\` 23/23 완성"'
chk "② 0/23 = ░ 10칸" 'lastbody | grep -qxF "골 0 \`░░░░░░░░░░\` 0/23"'
chk "② 20/23 = 8칸" 'lastbody | grep -qxF "골 20 \`▓▓▓▓▓▓▓▓░░\` 20/23"'
chk "② 1/23 = 0칸" 'lastbody | grep -qxF "골 1 \`░░░░░░░░░░\` 1/23"'
chk "② 5/6 = 8칸" 'lastbody | grep -qxF "골 5of6 \`▓▓▓▓▓▓▓▓░░\` 5/6"'
chk "② 25/23 = 수 판독 불가" 'lastbody | grep -qxF "골 넘침 수 판독 불가"'
chk "② 완성 = n = m 줄만" '[ "$(lastbody | grep -c "완성$")" = 1 ]'

# ③ 카드 없는 좌석 6석
goal "1 | 골 | 22 | 23 | 진행"
reset; mk "[$H,\"bare\":3},{\"key\":\"planner\",\"label\":\"플래너\",\"bare\":3}]"; run 2026-11-16T11:00:00
chk "③ 다음 = «카드 없이 열린 좌석 6석» 1줄" '[ "$(next_section)" = "카드 없이 열린 좌석 6석" ]'
chk "③ 본문 «— · —» 0" '! lastbody | grep -qF "— · —"'

# ④ 섞임 · 상한 · 0석 · 카드 파일 없음 · 카드 없는 좌석 0 · 수집 실패 팀
reset; mk "[$H,\"card\":2,\"bare\":3}]"; run 2026-11-16T12:00:00
chk "④ 카드 2 + 없음 3 = 2줄 + 접는 줄" '[ "$(next_section | wc -l | tr -d " ")" = 3 ] && [ "$(next_section | grep -c "^하네스 · nano-")" = 2 ] && next_section | tail -1 | grep -qx "카드 없이 열린 좌석 3석"'
reset; mk "[$H,\"card\":30,\"bare\":2}]"; run 2026-11-16T12:00:00
chk "④ 카드 30 + 없음 2 = 12줄 + 외 18석 + 접는 줄" '[ "$(next_section | wc -l | tr -d " ")" = 14 ] && next_section | sed -n 13p | grep -qx "외 18석" && next_section | tail -1 | grep -qx "카드 없이 열린 좌석 2석"'
reset; mk "[$H}]"; run 2026-11-16T12:00:00
chk "④ 좌석 0 = «열린 팀 세션 없음»" '[ "$(next_section)" = "열린 팀 세션 없음" ]'
reset; mk "[$H,\"miss\":1,\"bare\":1}]"; run 2026-11-16T12:00:00
chk "④ 카드 파일 없는 나노 = 줄 그대로 · 접는 줄 셈 밖" 'next_section | grep -qxF "하네스 · nano-gone0 · gone0 · 카드 없음" && next_section | tail -1 | grep -qx "카드 없이 열린 좌석 1석"'
reset; mk "[$H,\"card\":2}]"; run 2026-11-16T12:00:00
chk "④ 카드 없는 좌석 0 = 접는 줄 0" '[ "$(next_section | wc -l | tr -d " ")" = 2 ] && ! lastbody | grep -q "카드 없이 열린 좌석"'
reset; mk "[{\"key\":\"aa\",\"label\":\"에이\",\"bare\":2},{\"key\":\"bb\",\"label\":\"비\",\"bare\":3}]"; run 2026-11-16T12:00:00
goal "1 | 골 | 23 | 23 | 끝"; mk "[{\"key\":\"aa\",\"label\":\"에이\",\"err\":true},{\"key\":\"bb\",\"label\":\"비\",\"bare\":3}]"; run 2026-11-16T12:10:00
chk "④ 수집 실패 팀 이어 쓴 좌석 = 셈 밖 → 3석" '[ "$(replies)" = 2 ] && [ "$(next_section)" = "카드 없이 열린 좌석 3석" ]'
chk "④ 수집 실패 팀 «확인 불가» 줄 그대로" '[ "$(lastbody | grep -c "^에이 확인 불가")" = 1 ]'
goal "1 | 골 | 22 | 23 | 진행"

# ⑤ 열쇠·상태 불변 (기준판 대조)
S5="[$H,\"card\":1,\"bare\":2,\"miss\":1},{\"key\":\"planner\",\"label\":\"플래너\",\"bare\":3}]"
reset; mk "$S5"; run 2026-11-16T13:00:00 "$BASE"; cp "$LAST" "$T/base-last.json"
run 2026-11-16T13:10:00
chk "⑤ 기준판 news-last 위 새 판 = 변화 없음 · reply 0" '[ "$RC" = 0 ] && [ "$(replies)" = 1 ] && grep -q "변화 없음" "$T/out"'
reset; run 2026-11-16T13:00:00
chk "⑤ 같은 입력 = 상태 파일 key · snap 같음" 'python3 -c "import json,sys; a,b=(json.load(open(p)) for p in sys.argv[1:]); sys.exit(0 if (a[\"key\"],a[\"snap\"])==(b[\"key\"],b[\"snap\"]) else 1)" "$T/base-last.json" "$LAST"'
mk "[$H,\"card\":1,\"bare\":3,\"miss\":1},{\"key\":\"planner\",\"label\":\"플래너\",\"bare\":3}]"; run 2026-11-16T13:10:00
chk "⑤ 카드 없는 좌석 1석 열림 = reply 1 · «lead-x02 열림»" '[ "$(replies)" = 2 ] && now_section | grep -qx "lead-x02 열림"'

# ⑥ 채널 env
reset; mk "[$H,\"bare\":1}]"; PA="--channel C0C9GRFHJE5" run 2026-11-16T14:00:00
chk "⑥ env 있음 = --channel C0C9GRFHJE5 · --ts" 'grep -qF -- "--channel C0C9GRFHJE5" "$T/stub/tp.log" && grep -qF -- "--ts $TSV" "$T/stub/tp.log"'
reset; run 2026-11-16T14:00:00
chk "⑥ env 없음 = --channel 0" '[ "$(replies)" = 1 ] && ! grep -qF -- "--channel" "$T/stub/tp.log"'
PL="$ROOT/harness/kit/slack-mirror/com.byz.ft-board-news.plist.template"
chk "⑥ plist 템플릿 env · 그 밖 키 불변" 'python3 - "$PL" "${R2063_BASE_PLIST:-$T/base.plist}" <<'"'"'PY'"'"'
import plistlib, sys
d = plistlib.loads(open(sys.argv[1], "rb").read()); o = plistlib.loads(open(sys.argv[2], "rb").read())
assert d["EnvironmentVariables"].pop("FT_BOARD_POST_ARGS") == "--channel C0C9GRFHJE5"
o["EnvironmentVariables"].pop("FT_BOARD_POST_ARGS", None)
assert d["Label"] == "com.byz.ft-board-news" and d["ProgramArguments"][-1] == "--news" and d["StartInterval"] == 300
assert d == o
PY'

# ⑨ 뉴스 갈래 = --no-status-head 1개 · 그 밖 갈래 바이트 불변
reset; mk "[$H,\"bare\":1}]"; run 2026-11-16T15:00:00
chk "⑨ --news reply = --no-status-head 1개 · --ts · --text-file" '[ "$(grep -o -- "--no-status-head" "$T/stub/tp.log" | wc -l | tr -d " ")" = 1 ] && grep -qE -- "--no-status-head --ts $TSV --text-file " "$T/stub/tp.log"'
chk "⑨ 그 밖 갈래 = 기준판과 바이트 같음(--no-status-head 1곳 뺀 꼴)" 'cmp -s <(sed "s/ --no-status-head//" "$BIN/ft-board-publish.sh") <(sed "s/ --no-status-head//" "$BASE/ft-board-publish.sh") && [ "$(grep -c -- "--no-status-head" "$BIN/ft-board-publish.sh")" = 1 ] && grep -- "--no-status-head" "$BIN/ft-board-publish.sh" | grep -q "reply"'
chk "⑦ kit 사본 = bin" 'cmp -s "$ROOT/harness/bin/ft-board-publish.sh" "$ROOT/harness/kit/fable-team/bin/ft-board-publish.sh" && cmp -s "$ROOT/harness/bin/ft_board_news.py" "$ROOT/harness/kit/fable-team/bin/ft_board_news.py"'

echo "fail=$fail"; [ "$fail" = 0 ]
