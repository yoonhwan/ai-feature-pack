#!/usr/bin/env bash
# test_mbox_lineage_short_r1854.sh — recv·peek 머리 줄 계보 칸 줄이기(r1854): 이름 ≤3 = 그대로 · 4개 이상 = <N>:<새>..<옛>.
# 합류 목록(names)은 손 0 — 옛 이름 큐는 그대로 읽는다. 정본 mbox*.py 를 임시 폴더에 복사해 돈다(실 큐·설치 쓰기 0 · sleep 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; FX="$REPO/tests/fixtures/mbox_guard"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
P=byz-planner-master-claude; ME=byz-planner-arch-pi#200; O=byz-planner-old

new_env() {   # new_env <variant|long> [변이함수] — long = 서로 다른 역할 옛 이름 124개 체인(가장 새 = old124 → ME)
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/seats"; cp "$SRC"/mbox*.py "$C/"; : > "$Q"
  if [ "$1" = long ]; then echo '{}' > "$ENVROOT/seats/seats.json"
    python3 - "$ENVROOT/seats/seats-planner.json" "$ME" "$O" <<'PY'
import json, sys
f, me, o = sys.argv[1:]; d = {me: {"role": "arch", "tick": None}}
for i in range(1, 125): d["%s%d-claude#1" % (o, i)] = {"role": "stop-ready", "tick": None, "_replaced_by": me if i == 124 else "%s%d-claude#1" % (o, i + 1)}
json.dump(d, open(f, "w"))
PY
  else cp "$FX/$1"/seats*.json "$ENVROOT/seats/"; fi
  if [ -n "${2:-}" ]; then "$2"; fi
}
row() { printf '{"seq": %s, "ts": "2026-11-13T00:00:00", "to": "%s", "from": "x#1", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
mbox() { FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" python3 "$C/mbox.py" "$@" >"$ENVROOT/out" 2>"$ENVROOT/err"; }
head_len() { grep -m1 "$1" "$ENVROOT/out" | awk '{print length($0)}'; }

# M1 줄인 글을 합류 목록에도 씀 · M2 문턱 3 대신 0(늘 줄임)
mut_m1() { sed -i '' 's/names, joined = _lineage(me)$/names, joined = _lineage(me); names = [me] + joined.split(",")/' "$C/mbox_ops.py"; }
mut_m2() { sed -i '' 's/len(old) > 3/len(old) > 0/' "$C/mbox_ops.py"; grep -q 'len(old) > 0' "$C/mbox_ops.py"; }

LONG="lineage=124:${O}124-claude#1..${O}1-claude#1"
chk_1() {   # ① 124개 recv → 머리 줄 = 124:<새>..<옛> · ≤300자 · READ 3(옛 이름 큐 2개 + 내 것)
  new_env long "${1:-}"; row 1 "${O}1-claude#1" oldest; row 2 "${O}124-claude#1" newest; row 3 "$ME" mine
  mbox recv "$ME"; grep -q "^SCANNED .* $LONG\$" "$ENVROOT/out" && [ "$(head_len '^SCANNED')" -le 300 ] \
    && [ "$(grep -c '^READ \[' "$ENVROOT/out")" = 3 ]
}
chk_2() {   # ② 계보 2개(3단 체인) → lineage=#2,#1 그대로
  new_env lineage3 "${1:-}"; row 1 "$P#1" a1; mbox recv "$P#3"; grep -q "lineage=$P#2,$P#1\$" "$ENVROOT/out"
}
chk_3() {   # ③ peek 도 ① 꼴 · 소비 0
  new_env long; row 1 "${O}1-claude#1" oldest; mbox peek "$ME"
  grep -q "^pending=1 .* $LONG\$" "$ENVROOT/out" && [ "$(head_len '^pending=')" -le 300 ] && [ "$(wc -l < "$Q" | tr -d ' ')" = 1 ]
}
chk_1 && ok "① 124개 recv 머리 줄 124:<새>..<옛> · ≤300자 · READ 3" || bad "① recv :: $(head -c 300 "$ENVROOT/out")"
chk_2 && ok "② 계보 2개 lineage=#2,#1 그대로" || bad "② :: $(head -c 300 "$ENVROOT/out")"
chk_3 && ok "③ peek 124:<새>..<옛> · ≤300자 · 소비 0" || bad "③ peek :: $(head -c 300 "$ENVROOT/out")"
chk_1 mut_m1 && bad "M1 합류 목록 줄이기가 ① 에 안 잡힘" || ok "M1 합류 목록 줄이기 → ① FAIL 확인"
chk_2 mut_m2 && bad "M2 문턱 0 이 ② 에 안 잡힘" || ok "M2 문턱 0 → ② FAIL 확인"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAIL $fail"; exit 1; }
