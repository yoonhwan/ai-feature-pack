#!/usr/bin/env bash
# test_inbox_mark_still_open.sh — r593: mark 가 «표시했음» 만 찍어 닫힌 줄로 오해되던 것 → 표시 뒤 그 줄의 닫힘 술어를 다시 읽어
#   보고 의무 급 미닫힘 = «STILL-OPEN seq=… cls=… — report <seq> 또는 회신 쪽지» 1줄 · 닫힘 = «CLOSED seq=…» 1줄.
#   닫힘 술어(obligation_closed)·급(MUST_REPORT)·세기(ft-decision-count) 변경 0.
# 전부 mktemp 임시 FT_ROOT(가짜 큐·가짜 우편함) · 실 인박스·실 mbox·Haiku/tmux 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
INBOX="$REPO/harness/bin/ft-inbox.sh"
CORE="$REPO/harness/bin/ft_inbox_core.py"
DEC="$REPO/harness/bin/ft-decision-count.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/root"; mkdir -p "$FT_ROOT/.fable-team/state/inbox" "$FT_ROOT/.fable-team/comm/bodies"
unset FT_SEAT TMUX_PANE
Q="$FT_ROOT/.fable-team/state/inbox"; BD="$FT_ROOT/.fable-team/comm/bodies"
M=planner-x; ME="$M#9"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

seed() {  # <seq:cls>… — 줄마다 mark 없음 · reported=false · 본문 첫 줄 = [결정] 질문 꼴
  python3 - "$BD" "$Q/$M.jsonl" "$@" <<'PY'
import json, sys
bd, q, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = []
for spec in specs:
    seq, cls = spec.split(":")
    bp = f"{bd}/{seq}.txt"
    open(bp, "w", encoding="utf-8").write(f"[a->planner-x#9] [결정] {seq} 처리할까?\n")
    rows.append({"seq": int(seq), "ts": "2026-10-21T02:00:00", "from": "chatbot-x", "cls": cls, "prio": 1,
                 "group": f"g{seq}", "body_path": bp, "mark": None, "reported": False, "via": "rule"})
with open(q, "w", encoding="utf-8") as f:
    f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
PY
}

# ⓐ 보고 의무 급(③) 1줄 mark 처리 → STILL-OPEN 안내 1줄 (고치기 전 판 = 이 줄 0)
seed 124233:③
OUT="$(bash "$INBOX" mark 124233 처리 "대리 결정 ②" --seat "$ME" 2>&1)"; rc=$?
eq "ⓐ mark rc" "$rc" "0"
if grep -qx "STILL-OPEN seq=124233 cls=③ — report 124233 또는 회신 쪽지" <<<"$OUT"; then
  ok "ⓐ STILL-OPEN 원문 1줄"
else
  bad "ⓐ STILL-OPEN 줄 (출력: $(tr '\n' '|' <<<"$OUT"))"
fi
grep -qx "MARKED seq=124233 file=.*" <<<"$OUT" && ok "ⓐ MARKED 줄 그대로" || bad "ⓐ MARKED 줄"
grep -q "CLOSED seq=124233" <<<"$OUT" && bad "ⓐ CLOSED 오출력" || ok "ⓐ CLOSED 오출력 0"

# ⓑ 보고 의무 밖 급(⑤) mark → CLOSED 1줄 · STILL-OPEN 안내 0
seed 124234:⑤
OUT="$(bash "$INBOX" mark 124234 처리 "정리" --seat "$ME" 2>&1)"; rc=$?
eq "ⓑ mark rc" "$rc" "0"
grep -qx "CLOSED seq=124234" <<<"$OUT" && ok "ⓑ CLOSED 1줄" || bad "ⓑ CLOSED 줄 (출력: $(tr '\n' '|' <<<"$OUT"))"
grep -q "STILL-OPEN" <<<"$OUT" && bad "ⓑ STILL-OPEN 오출력" || ok "ⓑ STILL-OPEN 안내 0"

# ⓒ mark 뒤 report → ft-decision-count 첫 줄 숫자 −1 (표식 질문 1줄)
seed 124235:③
printf '{"_master": "planner-x#9", "_cards_wt": "none"}\n' > "$FT_ROOT/.fable-team/seats-planner.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil-stub.sh"; chmod +x "$T/hil-stub.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/tmux-stub.sh"; chmod +x "$T/tmux-stub.sh"
git init -q "$T/flag"; git -C "$T/flag" -c user.name=t -c user.email=t@t commit -q --allow-empty -m e
count() {
  env FT_ROOT="$FT_ROOT" FT_DECISION_NOW=2026-10-21T03:00:00 FT_DECISION_HIL="$T/hil-stub.sh" FT_DECISION_TMUX="$T/tmux-stub.sh" \
      FT_DECISION_MBOX="$T/hil-stub.sh" FT_DECISION_MERGE_QUEUE="$T/MQ-none.md" FT_DECISION_AUTONOMY_QUEUE="$T/AQ-none.md" \
      FT_DECISION_FLAG_DECISIONS="$T/FD-none.md" FT_FLAG_OFF_REPO="$T/flag" FT_FLAG_OFF_REF=HEAD \
      HIL_DIR="$T/hil" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" bash "$DEC" 2>&1 | head -1
}
bash "$INBOX" mark 124235 처리 "대리 결정" --seat "$ME" >/dev/null 2>&1
BEFORE="$(count)"; eq "ⓒ 전 = 결정 인터뷰 1건" "$(cut -d' ' -f1-3 <<<"$BEFORE")" "결정 인터뷰 1건"
bash "$INBOX" report 124235 --seat "$ME" >/dev/null 2>&1; rc=$?
eq "ⓒ report rc" "$rc" "0"
AFTER="$(count)"; eq "ⓒ 후 = 결정 인터뷰 0건" "$(cut -d' ' -f1-3 <<<"$AFTER")" "결정 인터뷰 0건"
echo "   ⓒ 원문: 전 «${BEFORE}» · 후 «${AFTER}»"

# ⓓ 닫힘 술어 함수 바이트 불변 (origin/main 판 ft_inbox_core.py 의 obligation_closed 와 비교)
BASE="$(git -C "$REPO" show origin/main:feature-pack/fable-team/harness/bin/ft_inbox_core.py 2>/dev/null)"
if [ -z "$BASE" ]; then bad "ⓓ origin/main 판 못 읽음"; else
  python3 - "$CORE" "$BASE" <<'PY'
import re, sys
def fn(src):
    m = re.search(r"^def obligation_closed\(.*?(?=^\S)", src, re.S | re.M)
    return m.group() if m else ""
new, base = fn(open(sys.argv[1], encoding="utf-8").read()), fn(sys.argv[2])
print("PASS ⓓ obligation_closed 바이트 불변" if new and new == base else "FAIL ⓓ obligation_closed 변경됨")
sys.exit(0 if new and new == base else 1)
PY
  [ $? = 0 ] || fail=$((fail+1))
fi

echo "SUMMARY fail=$fail"
[ "$fail" = 0 ]
