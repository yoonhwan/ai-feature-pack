#!/usr/bin/env bash
# test_waste_measure_pi_r1471.sh — r1471 계약: ft_waste_measure.py 가 pi 세션 형식(type=message · message.role ·
#   message.usage.{cacheRead,cacheWrite,cacheWrite1h} · responseId · toolCall)을 claude 형식과 «같은 단위»로 읽는다.
#   T1 같은 대화를 두 형식으로 적으면 숫자·rc 동일 · T2 pi 단독 매핑(턴3·요청4·toolResult 배제) · T3 responseId 없음 = 미상 id rc1
#   T4 형식 미상 → FORMAT unknown 1줄 + rc2(E 줄 0) · T5 claude 출력 바이트 동일(FORMAT 머리 1줄만 추가) + 기존 r1462 시험 rc0.
#   합성 jsonl 만 쓴다(실 세션 파일 0 · 홈 쓰기 0) · sleep 0 · 외부 호출 0 · 70초 안.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
M="$HERE/../bin/ft_waste_measure.py"
R1462="$HERE/test_waste_measure_r1462.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
[ -f "$M" ] || { echo "FAIL ft_waste_measure.py 없음: $M"; echo "FAILED 1"; exit 1; }
python3 -m py_compile "$M" >/dev/null 2>&1 && ok "py_compile" || bad "py_compile"

# 같은 대화 1개를 두 형식으로 적는다 — 턴 3 · 요청 4 · 도구 Bash,Read · usage 동일 · 끊김 1회(25,000)
mkdir -p "$T/claude" "$T/pi"   # 두 형식의 파일 이름을 같게 둔다(출력 file= 값이 같아야 숫자만 비교된다)
python3 - "$T/claude/session.jsonl" "$T/pi/session.jsonl" <<'PY'
import json, sys
CONV = [
    ("u",  "2026-11-08T01:00:00.000Z", "부팅 보고"),
    ("a",  "2026-11-08T01:00:01.000Z", dict(rid="msg_A", read=1000, cc5=1000, cc1=4000, out=150, tools=["Bash"])),
    ("tr", "2026-11-08T01:00:02.000Z", None),
    ("a",  "2026-11-08T01:00:31.000Z", dict(rid="msg_B", read=2000, cc5=0, cc1=25000, out=120, tools=["Bash", "Read"])),
    ("tr", "2026-11-08T01:00:32.000Z", None),
    ("a",  "2026-11-08T01:00:33.000Z", dict(rid="msg_C", read=3000, cc5=0, cc1=0, out=90, tools=["Read"])),
    ("tr", "2026-11-08T01:00:34.000Z", None),
    ("u",  "2026-11-08T01:05:00.000Z", "[desk 틱 · byz-planner-desk-claude#121] 승계 본문 6항"),
    ("a",  "2026-11-08T01:05:01.000Z", dict(rid="msg_D", read=4000, cc5=0, cc1=0, out=60, tools=["Bash"])),
    ("tr", "2026-11-08T01:05:02.000Z", None),
    ("u",  "2026-11-08T01:10:00.000Z", "다음 작업"),
]
def claude_rows():
    rows = []
    for kind, ts, p in CONV:
        if kind == "u":
            rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": p}})
        elif kind == "tr":
            rows.append({"type": "user", "timestamp": ts, "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}})
        else:
            blocks = [{"type": "tool_use", "name": n} for n in p["tools"]] or [{"type": "thinking"}]
            for b in blocks:   # claude 는 응답이 블록마다 행으로 갈라진다
                rows.append({"type": "assistant", "timestamp": ts, "message": {
                    "id": p["rid"], "usage": {
                        "input_tokens": 2, "output_tokens": p["out"],
                        "cache_read_input_tokens": p["read"],
                        "cache_creation_input_tokens": p["cc5"] + p["cc1"],
                        "cache_creation": {"ephemeral_5m_input_tokens": p["cc5"],
                                           "ephemeral_1h_input_tokens": p["cc1"]}},
                    "content": [b]}})
    return rows
def pi_rows():
    rows = []
    for kind, ts, p in CONV:
        if kind == "u":
            rows.append({"type": "message", "id": "u_" + ts, "parentId": None, "timestamp": ts,
                         "message": {"role": "user", "content": [{"type": "text", "text": p}],
                                     "timestamp": 1794120000000}})
        elif kind == "tr":
            rows.append({"type": "message", "id": "r_" + ts, "parentId": None, "timestamp": ts,
                         "message": {"role": "toolResult", "toolCallId": "call_1", "toolName": "bash",
                                     "content": [{"type": "text", "text": "ok"}]}})
        else:
            content = [{"type": "text", "text": "…"}]
            content += [{"type": "toolCall", "id": "call_%s_%d" % (p["rid"], i), "name": n, "arguments": {}}
                        for i, n in enumerate(p["tools"])]
            rows.append({"type": "message", "id": "x_" + p["rid"], "parentId": None, "timestamp": ts,
                         "message": {"role": "assistant", "content": content, "api": "openai-completions",
                                     "provider": "opengateway", "model": "deepseek/deepseek-v4.1-flash-ultrafast",
                                     "responseId": "og-" + p["rid"], "stopReason": "toolUse",
                                     "usage": {"input": 2, "output": p["out"], "reasoning": 1,
                                               "cacheRead": p["read"], "cacheWrite": p["cc5"] + p["cc1"],
                                               "cacheWrite1h": p["cc1"], "totalTokens": 0,
                                               "cost": {"total": 0}}}})
    return rows
for path, rows in ((sys.argv[1], claude_rows()), (sys.argv[2], pi_rows())):
    open(path, "w").write("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
PY

# ── T1 — 같은 대화를 두 형식으로 적으면 같은 숫자·같은 rc (FORMAT 머리 줄만 다르다)
o_c="$(python3 "$M" "$T/claude/session.jsonl" 2>&1)"; rc_c=$?
o_p="$(python3 "$M" "$T/pi/session.jsonl" 2>&1)"; rc_p=$?
body_c="$(printf '%s\n' "$o_c" | grep -v '^FORMAT ')"
body_p="$(printf '%s\n' "$o_p" | grep -v '^FORMAT ')"
[ "$body_c" = "$body_p" ] && ok "T1 두 형식 숫자 동일(E1·E2·E3·BREAK·5m/1h)" \
  || bad "T1 두 형식 불일치: $(printf '%s\n' "$body_c" | diff - <(printf '%s\n' "$body_p") | tr '\n' '/')"
[ "$rc_c" -eq "$rc_p" ] && ok "T1 rc 동일(rc=$rc_c)" || bad "T1 rc 다름 claude=$rc_c pi=$rc_p"
printf '%s\n' "$o_p" | grep -q '^FORMAT pi rows=' && ok "T1 pi 머리 줄 FORMAT pi" || bad "T1 FORMAT: $(printf '%s\n' "$o_p" | head -1)"

# ── T2 — pi 단독: 턴 3 · 요청 4(responseId 고유) · toolResult 행은 턴·요청 어디에도 0
printf '%s\n' "$o_p" | grep -q '^TURNS turns=3 requests=4 orphans=0$' \
  && ok "T2 턴 3 · 요청 4 · toolResult 는 턴 아님" || bad "T2 TURNS: $(printf '%s\n' "$o_p" | grep '^TURNS' | head -1)"
printf '%s\n' "$o_p" | grep -q '^E1 value=1.33 기준=2 PASS ticks=1' && ok "T2 E1 턴 분해" \
  || bad "T2 E1: $(printf '%s\n' "$o_p" | grep '^E1' | head -1)"
printf '%s\n' "$o_p" | grep -q '^E2 value=2500 기준=60000 PASS' && ok "T2 E2 = cacheRead 합/요청" \
  || bad "T2 E2: $(printf '%s\n' "$o_p" | grep '^E2' | head -1)"
printf '%s\n' "$o_p" | grep -q '^E3 value=1.00 기준=1 PASS ticks=1 tick_tools=1' && ok "T2 E3 = 틱 턴 toolCall 수" \
  || bad "T2 E3: $(printf '%s\n' "$o_p" | grep '^E3' | head -1)"
printf '%s\n' "$o_p" | grep -q '^BREAK count=1 write=25000$' && ok "T2 끊김 규칙 claude 와 같다" \
  || bad "T2 BREAK: $(printf '%s\n' "$o_p" | grep '^BREAK' | head -1)"
printf '%s\n' "$o_p" | grep -q '^CACHE 새입력5m=1000 1h=29000 출력=420 도구=5$' \
  && ok "T2 cacheWrite→5m/1h 분리(cacheWrite−cacheWrite1h)" || bad "T2 CACHE: $(printf '%s\n' "$o_p" | grep '^CACHE' | head -1)"
[ "$rc_p" -eq 0 ] && ok "T2 기준 안 넘으면 rc0" || bad "T2 rc=$rc_p"

# ── T3 — pi assistant 행에 responseId 없음 1건: 요청으로 세되 «미상 id» → E2 판정 불가 rc1 (0 치환 0)
python3 - "$T/t3.jsonl" <<'PY'
import json, sys
def u(ts, text):
    return {"type": "message", "timestamp": ts, "message": {"role": "user", "content": [{"type": "text", "text": text}]}}
def a(ts, usage, tools, rid=None):
    m = {"role": "assistant", "content": [{"type": "toolCall", "id": "c1", "name": n, "arguments": {}} for n in tools],
         "usage": usage}
    if rid is not None:
        m["responseId"] = rid
    return {"type": "message", "timestamp": ts, "message": m}
U = lambda read, cc1: {"input": 2, "output": 10, "cacheRead": read, "cacheWrite": cc1, "cacheWrite1h": cc1,
                       "totalTokens": 0, "cost": {"total": 0}}
rows = [u("2026-11-08T07:00:00.000Z", "턴"),
        a("2026-11-08T07:00:01.000Z", U(1000, 0), ["Bash"], rid="og-1"),
        a("2026-11-08T07:00:02.000Z", U(2000, 500), ["Read"])]   # responseId 없음
open(sys.argv[1], "w").write("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t3.jsonl" 2>&1)"; rc=$?
printf '%s\n' "$out" | grep -q '^TURNS turns=1 requests=2' && ok "T3 id 없는 행도 요청으로 센다" \
  || bad "T3 TURNS: $(printf '%s\n' "$out" | grep '^TURNS' | head -1)"
printf '%s\n' "$out" | grep -q '미상id=1' && ok "T3 «미상id=1» 표기" || bad "T3 미상id 표기 없음: $(printf '%s\n' "$out" | grep '^E2' | head -1)"
printf '%s\n' "$out" | grep -q '^FAIL E2 ' && ok "T3 E2 판정 불가 FAIL 줄" || bad "T3 FAIL E2 없음: $(printf '%s\n' "$out" | grep '^FAIL' | tr '\n' '/')"
[ "$rc" -eq 1 ] && ok "T3 rc1(조용한 0 금지)" || bad "T3 rc=$rc"

# ── T4 — 형식 미상: session·model_change 만 있는 파일 → FORMAT unknown 1줄 + rc2 + E 줄 0
python3 - "$T/t4.jsonl" <<'PY'
import json, sys
rows = [{"type": "session", "version": 3, "id": "s1", "timestamp": "2026-11-08T08:00:00.000Z", "cwd": "/tmp"},
        {"type": "model_change", "id": "m1", "timestamp": "2026-11-08T08:00:01.000Z",
         "provider": "opengateway", "modelId": "deepseek/deepseek-v4.1-flash-ultrafast"}]
open(sys.argv[1], "w").write("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n")
PY
out="$(python3 "$M" "$T/t4.jsonl" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "T4 형식 미상 rc2" || bad "T4 rc=$rc (턴 0 을 «낭비 0» 으로 읽히게 두면 안 된다)"
[ "$out" = "FORMAT unknown claude=0 pi=0" ] && ok "T4 FORMAT unknown 1줄" || bad "T4 출력: $(printf '%s\n' "$out" | tr '\n' '/')"
printf '%s\n' "$out" | grep -q '^E[123] ' && bad "T4 E 줄이 나왔다" || ok "T4 E 줄 0"

# ── T5 — claude 경로 바이트 동일(FORMAT 머리 1줄만 추가) + 기존 r1462 시험 rc0
cat > "$T/golden.txt" <<'GOLD'
WASTE r1462 file=session.jsonl since=-
TURNS turns=3 requests=4 orphans=0
E1 value=1.33 기준=2 PASS ticks=1 tick_avg=1.00 others_avg=1.50 tick_max=1
E2 value=2500 기준=60000 PASS 미상=0
E3 value=1.00 기준=1 PASS ticks=1 tick_tools=1
BREAK count=1 write=25000
CACHE 새입력5m=1000 1h=29000 출력=420 도구=5
GOLD
[ "$(printf '%s\n' "$o_c" | sed -n '1p')" = "FORMAT claude rows=12" ] && ok "T5 claude 머리 줄 FORMAT claude rows=12" \
  || bad "T5 FORMAT: $(printf '%s\n' "$o_c" | head -1)"
[ "$(printf '%s\n' "$o_c" | sed -n '2,$p')" = "$(cat "$T/golden.txt")" ] && ok "T5 claude 출력 나머지 줄 바이트 동일" \
  || bad "T5 claude 출력 변동: $(printf '%s\n' "$o_c" | sed -n '2,$p' | diff - "$T/golden.txt" | tr '\n' '/')"
if [ -f "$R1462" ]; then
  bash "$R1462" >/dev/null 2>&1 && ok "T5 기존 test_waste_measure_r1462 rc0" || bad "T5 기존 r1462 시험 rc≠0"
else
  bad "T5 기존 시험 없음: $R1462"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
