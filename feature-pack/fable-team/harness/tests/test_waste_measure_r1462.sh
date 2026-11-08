#!/usr/bin/env bash
# test_waste_measure_r1462.sh — ft_waste_measure.py(r1462) 계약: T4 요청 dedup·턴 집계·--since · T5 prefix 끊김 · T6 기준 초과 rc1.
#   합성 jsonl 만 쓴다(실 세션·실 우편함·홈 쓰기 0) · 고정 sleep 0 · 외부 호출 0 · 70초 안.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
M="$HERE/../bin/ft_waste_measure.py"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$M" ] || { echo "FAIL ft_waste_measure.py 없음: $M"; echo "FAILED 1"; exit 1; }
python3 -m py_compile "$M" >/dev/null 2>&1 && ok "py_compile" || bad "py_compile"

# T4 — 요청 1개가 content 블록마다 행으로 갈라진 합성본(같은 message.id · 같은 usage)
python3 - "$T/t4.jsonl" <<'PY'
import json, sys
rows = []
def u(ts, text):
    rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}})
def tr(ts):
    rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}})
def a(ts, mid, read, cc5, cc1, blocks, out=100):
    rows.append({"type": "assistant", "timestamp": ts, "message": {"id": mid, "usage": {
        "input_tokens": 2, "output_tokens": out, "cache_read_input_tokens": read,
        "cache_creation_input_tokens": cc5 + cc1,
        "cache_creation": {"ephemeral_5m_input_tokens": cc5, "ephemeral_1h_input_tokens": cc1}},
        "content": blocks}})
u("2026-11-08T01:00:00.000Z", "부팅 보고")
a("2026-11-08T01:00:01.000Z", "msg_A", 1000, 1000, 4000, [{"type": "thinking"}, {"type": "tool_use", "name": "Bash"}])
tr("2026-11-08T01:00:02.000Z")
a("2026-11-08T01:00:03.000Z", "msg_B", 2000, 0, 100, [{"type": "tool_use", "name": "Bash"}, {"type": "tool_use", "name": "Read"}])
tr("2026-11-08T01:00:04.000Z")
a("2026-11-08T01:00:05.000Z", "msg_C", 3000, 0, 0, [{"type": "thinking"}])
u("2026-11-08T01:05:00.000Z", "[desk 틱 · byz-planner-desk-claude#121] 승계 본문 6항")
a("2026-11-08T01:05:01.000Z", "msg_D", 4000, 0, 0, [{"type": "tool_use", "name": "Bash"}])
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t4.jsonl" 2>&1)"; rc=$?
echo "$out" | grep -q '^TURNS turns=2 requests=4 orphans=0$' && ok "T4 턴 2 · 요청 4(message.id dedup)" || bad "T4 dedup: $(echo "$out" | grep '^TURNS' | head -1)"
echo "$out" | grep -q '^E1 value=2.00 기준=2 PASS' && ok "T4 E1 = 요청/턴 = 2.00" || bad "T4 E1: $(echo "$out" | grep '^E1' | head -1)"
echo "$out" | grep -q 'tick_avg=1.00 others_avg=3.00' && ok "T4 E1 턴 종류 분해(틱 1.00 · 그 외 3.00)" || bad "T4 E1 분해: $(echo "$out" | grep '^E1' | head -1)"
echo "$out" | grep -q '^E2 value=2500 기준=60000 PASS' && ok "T4 E2 = 10,000/4 = 2500" || bad "T4 E2: $(echo "$out" | grep '^E2' | head -1)"
echo "$out" | grep -q '^E3 value=1.00 기준=1 PASS' && ok "T4 E3 = 틱턴 도구 1" || bad "T4 E3: $(echo "$out" | grep '^E3' | head -1)"
echo "$out" | grep -q '새입력5m=1000 1h=4100' && ok "T4 새 입력 5m/1h 분리(1000/4100)" || bad "T4 5m/1h: $(echo "$out" | grep '^CACHE' | head -1)"
[ "$rc" -eq 0 ] && ok "T4 기준 안 넘으면 rc0" || bad "T4 rc=$rc"
out="$(python3 "$M" "$T/t4.jsonl" --since 2026-11-08T01:04:00Z 2>&1)"; rc=$?
echo "$out" | grep -q '^TURNS turns=1 requests=1 orphans=0$' && ok "T4 --since 뒤 턴 1 · 요청 1" || bad "T4 --since: $(echo "$out" | grep '^TURNS' | head -1)"
python3 "$M" "$T/t4.jsonl" --since nope >/dev/null 2>&1; [ $? -eq 2 ] && ok "T4 --since 형식 오류 rc2" || bad "T4 --since 오류 rc≠2"

# T5 — prefix 끊김 = 앞 요청과 120초 안 ∧ creation > 2만 ∧ read > 0 (첫 요청 제외)
python3 - "$T/t5.jsonl" <<'PY'
import json, sys
rows = []
def a(ts, mid, read, cc):
    rows.append({"type": "assistant", "timestamp": ts, "message": {"id": mid, "usage": {
        "input_tokens": 2, "output_tokens": 10, "cache_read_input_tokens": read,
        "cache_creation_input_tokens": cc,
        "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": cc}},
        "content": [{"type": "tool_use", "name": "Bash"}]}})
rows.append({"type": "user", "timestamp": "2026-11-08T02:00:00.000Z", "message": {"role": "user", "content": "깨우는 턴"}})
a("2026-11-08T02:00:01.000Z", "msg_1", 5000, 60000)   # 첫 요청 — creation>2만 이어도 제외
a("2026-11-08T02:00:31.000Z", "msg_2", 5000, 25000)   # 30초 뒤 · 2.5만 · read>0 → 끊김 1
a("2026-11-08T02:00:46.000Z", "msg_3", 6000, 5000)    # 15초 뒤지만 creation 5천 → 아님
a("2026-11-08T02:07:00.000Z", "msg_4", 7000, 50000)   # 374초 뒤 → 아님
a("2026-11-08T02:07:10.000Z", "msg_5", 0, 30000)      # 10초 뒤지만 read 0 → 아님
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t5.jsonl" 2>&1)"
echo "$out" | grep -q '^BREAK count=1 write=25000$' && ok "T5 끊김 1회 · 재작성 25,000" || bad "T5 끊김: $(echo "$out" | grep '^BREAK' | head -1)"

# T6 — 기준값(E1 2 · E2 60000 · E3 1)을 넘으면 rc1 + 넘은 항목 줄
python3 - "$T/t6.jsonl" <<'PY'
import json, sys
rows = []
def u(ts, text):
    rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}})
def a(ts, mid, read, blocks):
    rows.append({"type": "assistant", "timestamp": ts, "message": {"id": mid, "usage": {
        "input_tokens": 2, "output_tokens": 10, "cache_read_input_tokens": read,
        "cache_creation_input_tokens": 0,
        "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}},
        "content": blocks}})
u("2026-11-08T03:00:00.000Z", "턴1")
for i in range(3):
    a("2026-11-08T03:00:0%d.000Z" % (i + 1), "msg_a%d" % i, 70000, [{"type": "tool_use", "name": "Bash"}])
u("2026-11-08T03:10:00.000Z", "[desk 틱 · 좌석] 6항")
for i in range(3):
    a("2026-11-08T03:10:0%d.000Z" % (i + 1), "msg_b%d" % i, 70000, [{"type": "tool_use", "name": "Bash"}])
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t6.jsonl" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "T6 기준 초과 rc1" || bad "T6 rc=$rc"
echo "$out" | grep -q '^FAIL E1 ' && echo "$out" | grep -q '^FAIL E2 ' && echo "$out" | grep -q '^FAIL E3 ' \
  && ok "T6 넘은 항목 3줄(E1·E2·E3)" || bad "T6 FAIL 줄: $(echo "$out" | grep '^FAIL' | tr '\n' '/')"
# T8(반례①-a) — 틱 도구 [2,0]: 평균 1.00 은 PASS 로 숨지만 «틱별 최대» 2 는 기준 초과다
python3 - "$T/t8.jsonl" <<'PY'
import json, sys
rows = []
def u(ts, text):
    rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}})
def a(ts, mid, read, tools):
    rows.append({"type": "assistant", "timestamp": ts, "message": {"id": mid, "usage": {
        "input_tokens": 2, "output_tokens": 10, "cache_read_input_tokens": read,
        "cache_creation_input_tokens": 0,
        "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}},
        "content": [{"type": "tool_use", "name": t} for t in tools]}})
u("2026-11-08T04:00:00.000Z", "[desk 틱 · a] 6항")
a("2026-11-08T04:00:01.000Z", "msg_t1", 1000, ["Bash", "Bash"])
u("2026-11-08T04:10:00.000Z", "[desk 틱 · b] 6항")
a("2026-11-08T04:10:01.000Z", "msg_t2", 1000, [])
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t8.jsonl" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "T8 틱 최대 2 → rc1" || bad "T8 rc=$rc (평균으로 가려짐)"
echo "$out" | grep -q '^E3 value=2.00 기준=1 FAIL' && ok "T8 E3 = 틱별 최대 2.00 FAIL" || bad "T8 E3: $(echo "$out" | grep '^E3' | head -1)"
echo "$out" | grep -q 'tick_tools=2,0' && ok "T8 틱별 값 노출(2,0)" || bad "T8 틱별 값 없음"

# T9(반례①-b) — usage 없는 요청을 0 으로 치환하지 않는다(«미상» 표기 → 판정 불가 rc1)
python3 - "$T/t9.jsonl" <<'PY'
import json, sys
rows = [{"type": "user", "timestamp": "2026-11-08T05:00:00.000Z", "message": {"role": "user", "content": "턴"}},
        {"type": "assistant", "timestamp": "2026-11-08T05:00:01.000Z", "message": {"id": "msg_nu", "content": [{"type": "tool_use", "name": "Bash"}]}}]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t9.jsonl" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "T9 usage 없음 → rc1(조용한 0 금지)" || bad "T9 rc=$rc"
echo "$out" | grep -q '미상=1' && ok "T9 «미상=1» 표기" || bad "T9 미상 표기 없음: $(echo "$out" | grep '^E2' | head -1)"
echo "$out" | grep -q '^FAIL E2 ' && ok "T9 E2 판정 불가 FAIL 줄" || bad "T9 FAIL E2 없음"

# T9b(반례①-c) — 틱 요청 3 + 일반 1: E1 평균 2.00 은 PASS 지만 틱 턴 3 요청은 초과다
python3 - "$T/t9b.jsonl" <<'PY'
import json, sys
rows = []
def u(ts, text):
    rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}})
def a(ts, mid):
    rows.append({"type": "assistant", "timestamp": ts, "message": {"id": mid, "usage": {
        "input_tokens": 2, "output_tokens": 10, "cache_read_input_tokens": 100,
        "cache_creation_input_tokens": 0,
        "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 0}},
        "content": [{"type": "tool_use", "name": "Bash"}]}})
u("2026-11-08T06:00:00.000Z", "[desk 틱 · a] 6항")
for i in range(3):
    a("2026-11-08T06:00:0%d.000Z" % (i + 1), "msg_t%d" % i)
u("2026-11-08T06:10:00.000Z", "보통 턴")
a("2026-11-08T06:10:01.000Z", "msg_n0")
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t9b.jsonl" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "T9b 틱 3요청 → rc1" || bad "T9b rc=$rc (평균으로 가려짐)"
echo "$out" | grep -q 'tick_max=3' && ok "T9b «tick_max=3» 노출" || bad "T9b tick_max 없음: $(echo "$out" | grep '^E1' | head -1)"
echo "$out" | grep -q '^FAIL E1 ' && ok "T9b E1 FAIL 줄" || bad "T9b FAIL E1 없음"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
