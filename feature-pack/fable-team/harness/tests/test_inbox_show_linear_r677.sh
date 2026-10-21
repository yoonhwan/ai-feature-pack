#!/usr/bin/env bash
# test_inbox_show_linear_r677.sh — ft-inbox.sh show 가 큐 행을 «한 번만» 훑는지(큐 5000행) + 상태판이 쪽지함이 늦은 팀을 «확인 불가» 로 드러내는지.
#   ⓐ 기준선: 고치기 전 판(fixtures/r677/ft-inbox-base.py) 의 show 경과 시간 원문
#   ⓑ 후판 = 출력 바이트가 전판과 «같고»(골든) · 5000행에서 1초 이하
#   ⓒ 정본 술어(ft_inbox_core.py obligation_closed·group_closed) = 고치기 전 판과 바이트 동일(재작성 0)
#   ⓔ 상태판 팀 칸 = «확인 불가» 글자이지 «미보고 0» 이 아니다 + collect 가 그 팀을 inbox_fail 로 표시
# 임시 FT_ROOT(mktemp) 만 · 실 큐·실 좌석·실 슬랙 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
BIN="$ROOT/harness/bin"
FIX="$ROOT/harness/fixtures/r677"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (없음: $3)"; }
lacks() { printf '%s' "$2" | grep -qF -- "$3" && bad "$1 (있으면 안 됨: $3)" || ok "$1"; }
le()  { [ "$2" -le "$3" ] && ok "$1 ($2 ≤ $3)" || bad "$1 ($2 > $3)"; }

bash -n "$BIN/ft-inbox.sh" && ok "bash -n ft-inbox.sh" || bad "bash -n ft-inbox.sh"
bash -n "$BIN/ft-sheet-publish.sh" && ok "bash -n ft-sheet-publish.sh" || bad "bash -n ft-sheet-publish.sh"

# ── 큐 5000행 ──
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT"
rows="$(python3 "$FIX/make_queue.py" "$FT_ROOT" 5000)"; echo "fixture: $rows"
show() { python3 "$1" show 'master-x#1' 2>"$T/show.err"; }
ms()   { python3 -c 'import time;print(int(time.time()*1000))'; }

# ⓐ 기준선 — 고치기 전 판 경과 시간(원문)
t0="$(ms)"; show "$FIX/ft-inbox-base.py" > "$T/base.out" || bad "ⓐ 전판 show rc≠0 ($(cat "$T/show.err"))"; t1="$(ms)"
BASE_MS=$((t1 - t0)); echo "ⓐ 전판 show 경과 = ${BASE_MS}ms · 줄 $(wc -l < "$T/base.out" | tr -d ' ')"

t0="$(ms)"; show "$BIN/ft-inbox.py" > "$T/new.out" || bad "ⓑ 후판 show rc≠0 ($(cat "$T/show.err"))"; t1="$(ms)"
NEW_MS=$((t1 - t0)); echo "ⓑ 후판 show 경과 = ${NEW_MS}ms · 줄 $(wc -l < "$T/new.out" | tr -d ' ')"
cmp -s "$T/base.out" "$T/new.out" && ok "ⓑ 출력 바이트 = 전판과 동일(골든)" || bad "ⓑ 출력이 전판과 다름: $(diff "$T/base.out" "$T/new.out" | head -4)"
[ -s "$T/new.out" ] && ok "ⓑ 출력이 비지 않음(EMPTY 아님)" || bad "ⓑ 출력 EMPTY"
le "ⓑ 5000행 show 1초 이하" "$NEW_MS" 1000
[ "$NEW_MS" -lt "$BASE_MS" ] && ok "ⓑ 전판보다 빠름 (${NEW_MS}ms < ${BASE_MS}ms)" || bad "ⓑ 전판보다 느림/같음 (${NEW_MS}ms vs ${BASE_MS}ms)"

# ⓒ 정본 술어 = 전판 그대로(재작성 0) · show 경로에서 group_closed 를 다시 부르지 않는다(제곱 제거의 근거)
cmp -s "$FIX/ft_inbox_core.py" "$BIN/ft_inbox_core.py" && ok "ⓒ obligation_closed·group_closed 바이트 동일(전판 그대로)" || bad "ⓒ 술어가 바뀜"
python3 - "$BIN/ft-inbox.py" <<'PY'
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
fn = next(n for n in ast.parse(src).body if isinstance(n, ast.FunctionDef) and n.name == "view")
calls = [c.func.id for c in ast.walk(fn) if isinstance(c, ast.Call) and isinstance(c.func, ast.Name)]
print("view calls:", sorted(set(calls)))
sys.exit(0 if "group_closed" not in calls else 1)
PY
[ $? = 0 ] && ok "ⓒ view 가 group_closed(전체 훑기)를 부르지 않는다" || bad "ⓒ view 가 아직 group_closed 를 부른다"

# ── ⓔ 상태판: 쪽지함이 늦은 팀 = «확인 불가» (0 으로 위장 0) ──
mkdir -p "$T/root2/.fable-team"
cat > "$T/root2/.fable-team/seats-fast.json" <<'EOF'
{"_label": "빠른팀", "_master": "f-master#1"}
EOF
cat > "$T/root2/.fable-team/seats-slow.json" <<'EOF'
{"_label": "느린팀", "_master": "s-master#1"}
EOF
printf '#!/bin/sh\necho EMPTY\n' > "$T/inbox-fast.sh"
printf '#!/bin/sh\nsleep 30\n' > "$T/inbox-slow.sh"; chmod +x "$T"/inbox-*.sh
printf '#!/bin/sh\necho f-master#1\\ns-master#1\\n' > "$T/tmux.sh"
# FT_BOARD_INBOX 는 팀을 구분하지 못하므로 «느린팀만 늦는» 스텁을 하나 더 둔다(좌석 이름으로 가른다)
cat > "$T/inbox.sh" <<'EOF'
#!/bin/sh
case "$1" in s-master*) sleep 30;; *) echo EMPTY;; esac
EOF
chmod +x "$T/inbox.sh"
export FT_ROOT="$T/root2"
export FT_BOARD_INBOX="bash $T/inbox.sh" FT_BOARD_TMUX="bash $T/tmux.sh" FT_VERDICT_BIN="$BIN/ft-verdict.sh"
export FT_BOARD_GH="cat $T/gh.json" FT_BOARD_GH_REFRESH=0 FT_BOARD_NOW="2026-10-22T00:30:00"
export FT_ROOT="$T/root2"
echo '[]' > "$T/gh.json"
# collect 는 실제 ft-board.py 를 쓰되 카드 폴더·tree 가 없는 명부라 «쪽지함» 만 부른다
COL="$(python3 "$BIN/ft-board.py" collect 2>"$T/collect.err")"
has "ⓔ 쪽지함 늦은 팀 = stderr ERROR 1줄" "$(cat "$T/collect.err")" "ft-inbox.sh show 실패(7초 초과"
has "ⓔ collect 가 그 팀을 inbox_fail 로 표시" "$COL" '"inbox_fail": true'
has "ⓔ 다른 팀은 error 0" "$COL" '"label": "빠른팀"'
python3 - "$COL" <<'PY' && ok "ⓔ 느린팀 칸 글자 = «확인 불가» 이고 미보고 0 이 아니다" || bad "ⓔ 칸 글자가 확인 불가가 아님"
import json, sys
d = json.loads(sys.argv[1])
slow = [t for t in d["teams"] if t["label"] == "느린팀"][0]
fast = [t for t in d["teams"] if t["label"] == "빠른팀"][0]
assert slow.get("inbox_fail") and "7초 초과" in slow["error"], slow
assert not slow.get("unreported") and not slow.get("pending"), slow  # 숫자 칸을 0 으로 채우지 않는다
assert "error" not in fast and fast.get("unreported") == 0, fast
PY
# ── 슬랙 본문(루트 글) = 사람 말만 — 오류 원문·명령어·경로·파일 이름 0 (오빠 2026-10-22 «사람이 읽지도 못하는 이걸 왜 발급하냐») ──
CELLS="$(python3 "$BIN/ft-board.py" render --sheet --text 2>/dev/null)"
TERM="$(python3 "$BIN/ft-board.py" render --term 2>/dev/null)"
SLACK="$(python3 "$BIN/ft-board.py" render --slack 2>/dev/null)"
printf '%s\n' "$CELLS" > "$T/body.txt"
has "ⓑ 슬랙 본문에 팀별 쉬운 말 한 줄(느린팀)" "$CELLS" "⚠ 느린팀 지금 확인 못 함"
has "ⓑ 빠른팀은 정상으로 그려진다" "$CELLS" "확인 중"
ERR_LINES="$(printf '%s\n%s\n%s\n' "$CELLS" "$TERM" "$SLACK" | grep -E '지금 확인 못 함|확인 불가\(쪽지함|확인 불가\(명부')"
[ -n "$ERR_LINES" ] && ok "ⓐ 실패 팀 줄을 찾았다(빈 대조 아님)" || bad "ⓐ 실패 팀 줄이 본문에 없다"
for bad_word in "Command[" "timed out" "TimeoutExpired" "ft-inbox.sh" "s-master" "/var/" ".json" "inbox.sh" "7초 초과 · 재시도"; do
  lacks "ⓐ 실패 팀 줄에 원문·명령·경로·파일 이름 0 ($bad_word)" "$ERR_LINES" "$bad_word"
done
lacks "ⓓ «미보고 0» 위장 없음" "$CELLS$TERM$SLACK" "느린팀 0"
lacks "ⓓ «0건» 으로 채우지 않는다" "$CELLS" "느린팀 · 0"
has "ⓒ 칸 글자 = «확인 불가»" "$(python3 "$BIN/ft-board.py" render --sheet 2>/dev/null)" "확인 불가(쪽지함 7초 초과)"
has "ⓐ 원문은 로그(stderr)에만 남는다" "$(cat "$T/collect.err")" "timed out after 7 seconds"

echo "fail=$fail"; [ "$fail" = 0 ]
