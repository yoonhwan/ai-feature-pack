#!/usr/bin/env bash
# test_queue_state_r528.sh — 오빠 큐 상태 칸 = 대기·진행·보류·완료 넷 + 정지 종류 셋(어휘 정본 queue-states.tsv · 판정기 ft_queue_state.py)
#   ⓐ 4 상태 꼴 OK ⓑ 정지 종류 붙임 OK ⓒ 보류 재확인 시각 없음 → ERR(줄 번호) ⓓ 어휘 밖·빈 칸 → ERR · 끝줄 QUEUE-STATE
#   ⓔ ft-proxy-decide QUEUE 새 줄 7칸 · 끝 칸 대기 · 새 파일 머리 7칸(상태) ⓕ 옛 머리 «처리됨» 도 같은 칸 · decision-count 가 «대기» 를 열린 줄로 셈
# 격리: 임시 큐·FT_ROOT·상태 — 실 큐·실 mbox 쓰기 0 · 외부 호출 0.
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; MIR="$HERE/../../harness/kit/fable-team/bin"
QS="$BIN/ft_queue_state.py"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

for f in queue-states.tsv ft_queue_state.py ft-proxy-decide.sh ft_decision_count.py; do cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp 0: $f" $?; done
[ -f "$QS" ]; ck "판정기 파일 실재: ft_queue_state.py" $?
python3 -m py_compile "$QS" 2>/dev/null; ck "py_compile ft_queue_state.py" $?
[ "$(wc -l < "$QS" 2>/dev/null || echo 999)" -le 200 ]; ck "ft_queue_state.py ≤ 200줄" $?

mkq() {  # <파일> <머리 끝 칸 이름> <상태 칸 값…> — 7칸 표 · 한 값 = 한 행
  local f="$1" col="$2"; shift 2
  { printf '# AUTONOMY-QUEUE\n\n| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | %s |\n|---|---|---|---|---|---|---|\n' "$col"
    for v in "$@"; do printf '| A9 | 2026-10-20 09:00 | x | 질문 | 추천 | 사유 | %s |\n' "$v"; done; } > "$f"
}
L() { out="$(python3 "$QS" lint "$1" 2>&1)"; rc=$?; }
okall() { [ "$rc" = 0 ] && grep -qx "QUEUE-STATE ERR=0 OK=$1" <<<"$out"; }

# ===== ⓐ 4 상태 꼴 =====
mkq "$T/a.md" 상태 '대기' '진행 — byz-harness-nano-r528#0' '보류 — 오빠 출장 · 재확인 2026-10-21 09:00' '완료 — 판정 2470' '완료 — c9136ad1ca'
L "$T/a.md"; okall 5; ck "ⓐ 대기 · 진행—누가 · 보류—사유·재확인 · 완료—판정/sha → OK 5 rc0" $?
echo "  ⓐ 원문: $(tail -1 <<<"$out")"

# ===== ⓑ 정지 종류 붙임 =====
mkq "$T/b.md" 상태 '진행 · 구현중정지 — 시험 ⓓ 작성' '대기 · 대기중정지' '진행 · 일시정지 — 정지 파일 2189'
L "$T/b.md"; okall 3; ck "ⓑ 구현중정지·대기중정지·일시정지 → OK 3 rc0" $?

# ===== ⓒ 보류 재확인 시각 없음 / 덧말 빠짐 =====
mkq "$T/c.md" 상태 '대기' '보류 — 10-18 전팀 정지(판정 2253) 뒤 오빠 대기 아님 · 재개 때 팀별 재확인' '보류 — 재확인 2026-10-21 09:00' '보류 — 사유 · 재확인 2026-13-40 99:99'
L "$T/c.md"; { [ "$rc" = 1 ] && grep -q '^ERR 6 ' <<<"$out" && grep -q '^ERR 7 ' <<<"$out" && grep -q '^ERR 8 ' <<<"$out" && grep -qx 'QUEUE-STATE ERR=3 OK=1' <<<"$out"; }
ck "ⓒ 보류 재확인 시각 없음·사유 없음·틀린 시각 → ERR 줄 번호 6·7·8 rc1" $?
echo "  ⓒ 원문: $(grep '^ERR 6' <<<"$out")"
mkq "$T/c2.md" 상태 '진행' '완료' '완료 — 끝났음' '진행 · 일시정지 — 정지 파일' '진행 · 구현중정지' '완료 · 구현중정지 — x' '진행 · 대기중정지'
L "$T/c2.md"; { [ "$rc" = 1 ] && grep -qx 'QUEUE-STATE ERR=7 OK=0' <<<"$out"; }
ck "ⓒ 필수 덧말 빠짐(진행 누가·완료 판정/sha·hold 번호·멈춘 단계) · 안 붙는 정지 종류 → ERR 7" $?

# ===== ⓓ 어휘 밖 · 빈 칸 · 끝줄 =====
mkq "$T/d.md" 상태 '' '처리됨 — 대리 끝' '대리 끝' '판정 1994 (10-16 오빠)' '대기 · 대기중정지 · 일시정지' '대기'
L "$T/d.md"; { [ "$rc" = 1 ] && [ "$(grep -c '^ERR ' <<<"$out")" = 5 ] && [ "$(tail -1 <<<"$out")" = 'QUEUE-STATE ERR=5 OK=1' ]; }
ck "ⓓ 빈 칸·어휘 밖 문장·정지 둘 → ERR 5 · 끝줄 QUEUE-STATE ERR=5 OK=1" $?
echo "  ⓓ 원문: $(grep '^ERR 5' <<<"$out")"
printf '| 자율 | 질문 | 상태 |\n|---|---|---|\n| A9 | x |\n' > "$T/d2.md"; L "$T/d2.md"; [ "$rc" = 1 ] && grep -q '^ERR 3 ' <<<"$out"; ck "ⓓ 상태 칸보다 짧은 행 → ERR" $?
printf '| 자율 | 질문 | 사유 |\n|---|---|---|\n| A9 | x | y |\n' > "$T/d3.md"; L "$T/d3.md"; [ "$rc" = 1 ] && grep -q '^ERR 1 .*상태' <<<"$out"; ck "ⓓ 머리에 상태·처리됨 칸 없음 → ERR 1" $?
L "$T/none.md"; [ "$rc" = 2 ] && grep -q '^ERROR ' <<<"$out"; ck "ⓓ 큐 파일 없음 → ERROR rc2(조용한 0 금지)" $?
out="$(python3 "$QS" parse "$T/b.md")"; rc=$?
python3 - "$out" <<'PY'; ck "ⓓ parse JSON — 줄 번호·머리 이름별 칸·상태·정지·덧말" $?
import json, sys
rows = json.loads(sys.argv[1])
r = rows[2]
assert r["line"] == 7 and r["cells"]["질문"] == "질문" and r["cells"]["상태"].startswith("진행"), r
assert (r["state"], r["stop"], r["extra"], r["error"]) == ("진행", "일시정지", "정지 파일 2189", None), r
assert rows[1]["stop"] == "대기중정지" and rows[1]["extra"] == "", rows[1]
PY
mkq "$T/p.md" 상태 '보류 — 사유 · 재확인 2026-10-21 09:00'
out="$(python3 "$QS" parse "$T/p.md")"; python3 -c 'import json,sys;r=json.loads(sys.argv[1])[0];assert r["recheck"]=="2026-10-21 09:00",r' "$out"; ck "ⓓ parse 재확인 시각 칸" $?
{ printf '| 자율 | 질문 | 상태 | 새칸 |\n|---|---|---|---|\n| A9 | x | 대기 | 값 |\n'; } > "$T/p2.md"
out="$(python3 "$QS" parse "$T/p2.md")"; python3 -c 'import json,sys;r=json.loads(sys.argv[1])[0];assert r["cells"]["새칸"]=="값" and r["state"]=="대기",r' "$out"; ck "ⓓ 상태 뒤에 칸이 늘어도 파서 그대로(r529)" $?

# ===== ⓕ 옛 머리 «처리됨» =====
mkq "$T/f.md" 처리됨 '대기' '완료 — 판정 1994' '보류 — 10-18 전팀 정지 뒤 재확인'
L "$T/f.md"; { [ "$rc" = 1 ] && grep -qx 'QUEUE-STATE ERR=1 OK=2' <<<"$out" && grep -q '^ERR 7 ' <<<"$out"; }; ck "ⓕ 옛 머리 «처리됨» = 같은 칸으로 읽음(이름 바꾸기 0)" $?

# ===== ⓔ ft-proxy-decide 새 줄 · 새 파일 머리 =====
S="$T/state"; P="$T/planner"; mkdir -p "$S" "$P"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$P" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
printf '%s\n' '- **100** (오빠) x 착수 승인' > "$P/VERDICTS-planner-1.md"
"$BASH" "$BIN/ft-autonomy.sh" on >/dev/null 2>&1; [ "$("$BASH" "$BIN/ft-autonomy.sh" mode)" = on ]; ck "준비: 자율 ON" $?
Q="$P/AUTONOMY-QUEUE.md"
out="$("$BASH" "$BIN/ft-proxy-decide.sh" --kind card-start --card "$T/none.md" --verdict 100 --q q1 --choice c --why w --undo u 2>&1)"; rc=$?
[ "$rc" = 2 ]; ck "ⓔ 준비: QUEUE rc2" $?
head="$(grep -m1 '^| 자율' "$Q")"; row="$(grep '| q1 |' "$Q")"
[ "$head" = '| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 상태 |' ]; ck "ⓔ 새 파일 머리 7칸 · 끝 칸 «상태»" $?
echo "  ⓔ 원문: $head"; echo "  ⓔ 원문: $row"
[ "$(awk -F'|' '{print NF-2}' <<<"$row")" = 7 ] && grep -q '| 대기 |$' <<<"$row"; ck "ⓔ 새 QUEUE 줄 7칸 · 끝 칸 대기" $?
L "$Q"; okall 1; ck "ⓔ 도구가 쓴 큐 = 린트 OK" $?
mkq "$P/AUTONOMY-QUEUE.md" 처리됨 '보류 — 옛 문장'
"$BASH" "$BIN/ft-proxy-decide.sh" --kind card-start --card "$T/none.md" --verdict 100 --q q2 --choice c --why w --undo u >/dev/null 2>&1
row="$(grep '| q2 |' "$Q")"; [ "$(awk -F'|' '{print NF-2}' <<<"$row")" = 7 ] && grep -q '| 대기 |$' <<<"$row"; ck "ⓔ 옛 머리(처리됨) 큐에도 새 줄 7칸 · 대기" $?

# ===== ⓕ decision-count: «대기» = 열린 줄 · 빈 칸(옛) = 열린 줄 · 다른 상태 = 닫힘 =====
DQ="$T/dq.md"; mkq "$DQ" 상태 '대기' '대기 · 대기중정지' '진행 — x' '보류 — y · 재확인 2026-10-21 09:00' '완료 — 판정 1'
DC() { python3 - "$BIN" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ft_decision_count as d
rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in open(sys.argv[2], encoding="utf-8") if ln.startswith("|")]
rows = [r for r in rows if not all(set(c) <= set("-:") and c for c in r)]
print(d.autonomy_open((rows[1:], rows[0]))[0])
PY
}
[ "$(DC "$DQ")" = 2 ]; ck "ⓕ decision-count 머리 «상태» · 대기 2 = 열린 줄 2" $?
mkq "$DQ" 처리됨 '' '대기' '완료 — 판정 1' '보류 — 옛 문장'
[ "$(DC "$DQ")" = 2 ]; ck "ⓕ decision-count 옛 머리 «처리됨» · 빈 칸 + 대기 = 열린 줄 2" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
