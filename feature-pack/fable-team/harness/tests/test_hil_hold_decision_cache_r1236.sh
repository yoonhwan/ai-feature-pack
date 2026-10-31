#!/usr/bin/env bash
# test_hil_hold_decision_cache_r1236.sh — r1236(Issue #5465) ①보류 h 표식(--hold/--unhold/--held) ②ft-decision-count 머리 캐시.
# 반례 R1~R8(카드 동결) + 변이 1(캐시 무시 → R5 열린 본문 500 = FAIL 이어야 함).
#   R1 h3 중 1 보류 → --each 2줄 · --held 1줄(사유)   R2 보류 뒤 해제 → --each 3줄 · --held 0줄   R3 없는 h 보류 → rc2 1줄 · 표식 0
#   R4 뉴스 칸: 미실행 1 + 보류 1 → «1개(…) · 보류 1(h…)»   R5 본문 500·캐시 490 → 열린 본문 10 · 결과 같음
#   R6 캐시 없음 → 500 열고 캐시 생성 · 다음 0   R7 캐시 한 줄 깨짐 → 그 seq 만 엶 · 결과 같음   R8 본문 없는 쪽지 1 → «본문 없음» 그대로 · 캐시 0
# 격리: 임시 HIL_DIR·임시 FT_ROOT·임시 본문 — 실 /tmp/h*·실 쪽지 0 · 자기 재호출 0(real_state_guard 재실행만) · 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX_PANE
export PYTHONDONTWRITEBYTECODE=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
PY="$(command -v python3)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

for f in ft-hil.sh ft_hil_pending.py ft_decision_kind.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 미러 cmp 0: $f" || bad "키트 미러 달라짐: $f"; done
[ "$(wc -l < "$BIN/ft-hil.sh")" -le 200 ] && ok "ft-hil.sh ≤ 200줄" || bad "ft-hil.sh 200줄 초과"

# ── R1~R3 보류 표식 ───────────────────────────────────────────────────────
H="$T/hil"; mkdir -p "$H"
for n in 1 2 3; do printf '#!/usr/bin/env bash\n# ft-hil-entry plan=/tmp/plan%s\n' "$n" > "$H/h$n"; done
hil() { env -i HOME="$T" PATH="/usr/bin:/bin" HIL_DIR="$H" HIL_CLIP=0 bash "$KIT/ft-hil.sh" "$@"; }
eq "R1 보류 전 --each 3줄" "$(hil --pending --each | wc -l | tr -d ' ')" 3
hil --hold h2 --why "ccu 닫기 먼저" >/dev/null 2>&1; eq "R1 --hold rc0" "$?" 0
eq "R1 --each 2줄(h1 h3)" "$(hil --pending --each | cut -d' ' -f1 | tr '\n' ' ')" "h1 h3 "
eq "R1 --held 1줄(사유 포함)" "$(hil --pending --held | sed 's/^h2 [0-9]* //')" "ccu 닫기 먼저"
eq "R1 --held 줄 수" "$(hil --pending --held | wc -l | tr -d ' ')" 1
eq "R1 요약 1줄 = 2개 · 보류 1개" "$(hil --pending | sed 's/ · 가장 오래된 [0-9]*분//')" "미실행 h 2개 · 보류 1개"
eq "R1 --each --held = 미실행 2줄 + held 1줄" "$(hil --pending --each --held | cut -d' ' -f1 | tr '\n' ' ')" "h1 h3 held "
[ -f "$H/h2.held" ] && [ ! -L "$H/h2.held" ] && ok "R1 표식 = 일반 파일" || bad "R1 표식이 일반 파일이 아니다"
hil --unhold h2 >/dev/null 2>&1; eq "R2 --unhold rc0" "$?" 0
eq "R2 --each 3줄" "$(hil --pending --each | wc -l | tr -d ' ')" 3
eq "R2 --held 0줄" "$(hil --pending --held | wc -l | tr -d ' ')" 0
eq "R2 표식 파일 줄 수(hold·unhold 이어 쓰기)" "$(wc -l < "$H/h2.held" | tr -d ' ')" 2
E="$(hil --hold h99 --why x 2>&1 >/dev/null)"; rc=$?
eq "R3 없는 h → rc2" "$rc" 2
eq "R3 stderr 1줄" "$(printf '%s\n' "$E" | grep -c .)" 1
[ ! -e "$H/h99.held" ] && ok "R3 표식 파일 0" || bad "R3 표식 파일이 생겼다"

# ── R4 뉴스 칸 ────────────────────────────────────────────────────────────
cat > "$T/cell.py" <<'PYC'
import sys
from datetime import datetime
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import ft_news_desk_oppa as o
print(o._hil(Path(sys.argv[2]), datetime.now()))
PYC
cell() { ( export HIL_DIR="$H" HIL_CLIP=0 FT_DESK_HIL="$KIT/ft-hil.sh"; "$PY" "$T/cell.py" "$KIT" "$T" ); }   # 하위 셸 — env 명령·비밀 조회 0
hil --hold h2 --why r4 >/dev/null 2>&1
CELL1="$(cell)"
eq "R4 뉴스 칸 = 2개(h1·h3) · 보류 1(h2)" "$(sed 's/ · 가장 오래된 [0-9]*분//' <<<"$CELL1")" "2개(h1·h3) · 보류 1(h2)"
hil --unhold h2 >/dev/null 2>&1; hil --hold h1 --why a >/dev/null 2>&1; hil --hold h2 --why b >/dev/null 2>&1; hil --hold h3 --why c >/dev/null 2>&1
CELL2="$(cell)"
eq "R4 전부 보류 = 0개 · 보류 3(h1·h2·h3)" "$CELL2" "0개 · 보류 3(h1·h2·h3)"

# ── R5~R8 머리 캐시 ───────────────────────────────────────────────────────
R="$T/root"; B="$R/.fable-team/comm/bodies"; mkdir -p "$B" "$R/.fable-team/state/inbox"
CACHE="$R/.fable-team/state/ft-decision-heads.tsv"
cat > "$T/probe.py" <<'PY'
import builtins, json, os, sys
bindir, root, bodies = sys.argv[1], sys.argv[2], sys.argv[3]
os.environ["FT_ROOT"] = root
sys.path.insert(0, bindir)
from datetime import datetime
import ft_decision_kind as k
rows = [json.loads(x) for x in open(f"{root}/rows.jsonl", encoding="utf-8")]
opened = []
real = builtins.open
def watch(f, *a, **kw):
    if isinstance(f, str) and f.startswith(bodies + "/"):
        opened.append(f)
    return real(f, *a, **kw)
builtins.open = watch
got = k.open_rows(rows, set(), datetime.fromisoformat("2026-10-31T18:00:00"))
builtins.open = real
print(len(opened), " ".join(f"{x['seq']}:{kind}" for x, kind, _ in got))
PY
mkrows() {  # <개수> <본문 없는 seq(없으면 0)> — 본문: 홀수 = 질문 · 짝수 = 통보
  python3 - "$R" "$B" "$1" "${2:-0}" <<'PY'
import json, sys
R, B, n, miss = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
rows = []
for s in range(1, n + 1):
    if s != miss:
        head = "[결정] 값 필요? ①예 ②아니오" if s % 2 else "[완료] 끝"
        open(f"{B}/{s}.txt", "w", encoding="utf-8").write(f"[byz-a#1->byz-b#1] {head}\n본문 {s}\n")
    rows.append({"seq": s, "ts": "2026-10-31T17:55:00", "from": "byz-a#1", "cls": "②", "prio": 2.0, "group": f"g{s}",
                 "body_path": f"{B}/{s}.txt", "mark": None, "reported": False})
open(f"{R}/rows.jsonl", "w", encoding="utf-8").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PY
}
probe() { python3 "$T/probe.py" "${1:-$KIT}" "$R" "$B" 2>"$T/perr"; }

mkrows 500; rm -f "$CACHE"
BASE="$(probe)"; BASE_OPEN="${BASE%% *}"; BASE_RES="${BASE#* }"
eq "R6 캐시 없음 → 본문 500 개 열림" "$BASE_OPEN" 500
eq "R6 캐시 파일 생성(500줄)" "$(wc -l < "$CACHE" | tr -d ' ')" 500
eq "R6 다음 실행 open 0" "$(probe | cut -d' ' -f1)" 0
eq "R6 다음 실행 결과 같음" "$(probe | cut -d' ' -f2-)" "$BASE_RES"
[ -f "$CACHE" ] && [ ! -L "$CACHE" ] && ok "R6 캐시 = 일반 파일" || bad "R6 캐시가 일반 파일이 아니다"

head -n 490 "$CACHE" > "$T/c490" && cp "$T/c490" "$CACHE"      # R5: 앞 490 만 적중
OUT5="$(probe)"
eq "R5 열린 본문 = 10" "${OUT5%% *}" 10
eq "R5 결과 = 캐시 없을 때와 같음" "${OUT5#* }" "$BASE_RES"
eq "R5 캐시가 500줄로 다시 참" "$(wc -l < "$CACHE" | tr -d ' ')" 500

sed -i.bak '7s/.*/깨진줄-탭-없음/' "$CACHE"; rm -f "$CACHE.bak"    # R7: 7번 줄(seq 7)만 깨뜨림
OUT7="$(probe)"
eq "R7 깨진 줄의 seq 만 본문을 엶(open 1)" "${OUT7%% *}" 1
eq "R7 결과 같음" "${OUT7#* }" "$BASE_RES"
printf '999' >> "$CACHE"                                         # 개행 없이 끊긴 마지막 줄 + 새 줄 이어 쓰기가 붙지 않아야 함
OUT7b="$(probe)"; [ "${OUT7b#* }" = "$BASE_RES" ] && ok "R7 끊긴 마지막 줄이 있어도 결과 같음" || bad "R7 끊긴 마지막 줄에서 결과 달라짐"

mkrows 6 4; rm -f "$CACHE"; rm -f "$B/4.txt"                      # R8: seq 4 본문 없음
OUT8="$(probe)"
eq "R8 본문 없는 쪽지 = «본문 없음» 1건" "$(grep -c '4:본문 없음' <<<"$OUT8")" 1
grep -q $'^4\t' "$CACHE" && bad "R8 본문 없는 seq 가 캐시에 들어갔다" || ok "R8 캐시에 안 들어감"
eq "R8 다음 실행도 같은 결과(캐시 때문에 값이 바뀌지 않는다)" "$(probe | cut -d' ' -f2-)" "${OUT8#* }"
grep -q '^WARN ft-decision-count: 쪽지 본문 없음 1건' "$T/perr" && ok "R8 본문 없음 WARN 1줄 그대로" || bad "R8 WARN 없음"

# ── 변이: 캐시를 무시하면 R5 가 open 500 이어야 한다 ─────────────────────
MUT="$T/mut"; mkdir -p "$MUT"; cp "$KIT"/*.py "$MUT/"
sed -i.bak 's/first = cache.get(str(x\["seq"\]))/first = None/' "$MUT/ft_decision_kind.py"; rm -f "$MUT/ft_decision_kind.py.bak"
cmp -s "$MUT/ft_decision_kind.py" "$KIT/ft_decision_kind.py" && bad "변이가 적용되지 않았다"
mkrows 500; rm -f "$CACHE"; probe >/dev/null; head -n 490 "$CACHE" > "$T/c490" && cp "$T/c490" "$CACHE"
OUTM="$(probe "$MUT")"
[ "${OUTM%% *}" = 500 ] && ok "변이(캐시 무시) → R5 open 500 = FAIL 확인" || bad "변이가 R5 에서 안 잡혔다(open ${OUTM%% *})"

echo "== 실패 $fail =="
[ "$fail" = 0 ]
