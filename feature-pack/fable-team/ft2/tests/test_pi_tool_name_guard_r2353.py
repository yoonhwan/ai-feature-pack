"""ft2 pi tool-name-guard 시험 (r2353 카드) — 반례 ①~⑧ · 변이 M1~M5(변이마다 원본으로 같은 사례 1회 더) · 기준판 ④ ⑥ Red.

격리 = tmp_path 사본 · 가짜 pi(등록만 기록) · 가짜 event · 실 pi 0 · 실 세션 0 · 네트워크 0.
판정 = 확장이 돌려준 값과 «원본 객체가 그대로인지»(context 는 사본만 고쳐야 한다) · 진단 1줄은 stderr 로 받는다.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GUARD = FT2 / "adapters" / "pi" / "ft-tool-name-guard.ts"
NODE = shutil.which("node")
PLACEHOLDER = "invalid_tool_name"

# #44 실사건(sessions/…963d76e8… · 메시지 261 · 313자) 꼴 — 이름 칸에 붙은 bash 명령 초안 · arguments 는 다른 짧은 명령
#  사고 경로 두 토막은 ft2 자기검사(1.x 경로 금지)에 걸려 같은 꼴의 다른 경로로 바꿨다 · 판정에 필요한 것은 «200자 넘김 ∧ 공백»
BAD313 = (
    "sed -n '50,80p' /tmp/da44-t2349.sh | cut -c1-400; echo ===; sed -n '1,30p' /tmp/da44-t2349.sh | grep -nE "
    "'seed|log\\(\\)|cat >|printf' | head; cd ~/Project/ai-feature-pack; timeout 7 git show origin/main:"
    "feature-pack/fable-team/kit/ha/ft-autonomy.sh | grep -nE 'LLM_BAD|위변조' | head -12 | cut -c1-220"
)
ARGS = {"command": "sed -n '50,80p' /tmp/da44-t2349.sh | cut -c1-400", "timeout": "10"}

DRIVER = """
import fs from "node:fs";
const mod = await import(process.env.FT_GUARD), req = JSON.parse(fs.readFileSync(0, "utf8"));
const handlers = {}, says = [];
console.error = (...a) => says.push(a.join(" "));
mod.default({ on: (name, fn) => { (handlers[name] ??= []).push(fn); } });
const steps = [];
for (const s of req.steps) {
  if (s.op === "judge") { steps.push({ judge: s.names.map((n) => mod.nameOk(n)) }); continue; }
  const isEnd = s.op === "end", key = isEnd ? "message_end" : "context";
  const event = isEnd ? { type: "message_end", message: s.message } : { type: "context", messages: s.messages };
  const held = isEnd ? s.message : s.messages, before = JSON.stringify(held);
  says.length = 0;
  let ret; for (const fn of handlers[key] ?? []) ret = await fn(event, {});
  steps.push({ ret: ret === undefined ? null : ret, mutated: JSON.stringify(held) !== before, says: [...says] });
}
process.stdout.write(JSON.stringify({ steps, hooks: Object.keys(handlers) }));
"""


def node(steps, guard=GUARD):
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"),
           "FT_GUARD": Path(guard).resolve().as_uri(), "FT_SEAT": "byz-r2353-probe#0"}
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], capture_output=True,
                          text=True, timeout=60, input=json.dumps({"steps": steps}), env=env)
    if proc.returncode != 0:
        pytest.fail(proc.stderr[-800:])
    return json.loads(proc.stdout)


def judge(*names, guard=GUARD):
    return node([{"op": "judge", "names": list(names)}], guard=guard)["steps"][0]["judge"]


def call(cid, name, args=None):
    return {"type": "toolCall", "id": cid, "name": name, "arguments": ARGS if args is None else args}


def assistant(blocks):
    return {"role": "assistant", "content": blocks, "api": "anthropic-messages",
            "provider": "cliproxy-anthropic", "model": "claude-opus-5-5", "stopReason": "toolUse"}


def result(cid, name, text="Tool not found"):
    return {"role": "toolResult", "toolCallId": cid, "toolName": name, "isError": True,
            "content": [{"type": "text", "text": text}]}


def end(message, guard=GUARD):
    return node([{"op": "end", "message": message}], guard=guard)["steps"][0]


def ctx(messages, guard=GUARD):
    return node([{"op": "context", "messages": messages}], guard=guard)["steps"][0]


def mutant(tmp_path, index, old, new):
    source = GUARD.read_text(encoding="utf-8")
    assert old in source, f"변이 자리 없음: {old[:60]}"
    folder = tmp_path / f"m{index}"
    folder.mkdir()
    path = folder / "mutant.ts"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return path


needs_node = pytest.mark.skipif(not NODE, reason="node 없음")


@needs_node
def test_a_shape_cap_200_and_letters():
    got = judge("a" * 201, "a" * 200, "bash ls", "bash_ls", "bash", "도구이름", "")
    assert got == [False, True, False, True, True, False, False], "① 201자 = 어김 · 200자 = 정상 · ③ 공백 = 어김 · 빈 이름 = 어김"


@needs_node
def test_b_128_and_unregistered_names_are_normal():
    got = judge("a" * 128, "mcp__server__tool-name_2")
    assert got == [True, True], "② 128자 정상 꼴 = 정상 · 등록 안 된 이름도 정상(K1 은 등록 여부를 안 본다 · DA#45 M5)"


@needs_node
def test_c_message_end_repairs_before_store():
    got = end(assistant([{"type": "text", "text": "앞"}, call("toolu_01RFSsXc", BAD313)]))
    assert len(BAD313) > 200 and " " in BAD313, "실사건 꼴 = 명령 글이 이름 칸에 붙은 200자 넘김"
    blocks = got["ret"]["message"]["content"]
    assert got["ret"]["message"]["role"] == "assistant", "대체 메시지는 role 이 같아야 한다"
    assert blocks[1]["name"] == PLACEHOLDER and blocks[0] == {"type": "text", "text": "앞"}, "④ 어긴 이름만 자리 이름"
    assert blocks[1]["id"] == "toolu_01RFSsXc" and blocks[1]["arguments"] == ARGS, "④ id·arguments 는 그대로"
    assert got["ret"]["message"]["model"] == "claude-opus-5-5", "다른 필드도 그대로"
    assert len(got["says"]) == 1 and PLACEHOLDER in got["says"][0], "④ 진단 1줄"


@needs_node
def test_d_only_the_bad_call_changes_in_one_message():
    got = end(assistant([{"type": "text", "text": "가"},
                         call("t-ok", "bash", {"command": "ls"}),
                         call("t-bad", BAD313),
                         {"type": "text", "text": "나"}]))
    blocks = got["ret"]["message"]["content"]
    assert [b.get("type") for b in blocks] == ["text", "toolCall", "toolCall", "text"], "⑤ 순서 그대로"
    assert [b.get("text") for b in blocks if b["type"] == "text"] == ["가", "나"], "⑤ text 그대로"
    assert blocks[1]["name"] == "bash" and blocks[1]["arguments"] == {"command": "ls"}, "⑤ 정상 bash 는 손 0"
    assert blocks[2]["name"] == PLACEHOLDER, "⑤ 어김만 자리 이름"
    assert len(got["says"]) == 1, "⑤ 진단 1줄"


@needs_node
def test_e_context_repairs_copy_and_result_pair():
    messages = [{"role": "user", "content": "x"}, assistant([call("toolu_1", BAD313)]),
                result("toolu_1", BAD313)]
    got = ctx(messages)
    out = got["ret"]["messages"]
    assert out[1]["content"][0]["name"] == PLACEHOLDER, "⑥ 사본 toolCall 자리 이름"
    assert out[2]["toolName"] == PLACEHOLDER and out[2]["toolCallId"] == "toolu_1", "⑥ 짝 toolResult 도 같은 자리 이름"
    assert out[0] == messages[0], "⑥ 관계없는 메시지 그대로"
    assert got["mutated"] is False, "⑥ 원본 객체 손 0(기록은 안 고친다)"
    assert len(got["says"]) == 1, "⑥ 진단 1줄"


@needs_node
def test_f_context_returns_nothing_when_all_names_are_fine():
    messages = [{"role": "user", "content": "x"}] + [assistant([call(f"t{i}", "bash")]) for i in range(30)]
    got = ctx(messages)
    assert got["ret"] is None and got["mutated"] is False, "⑦ 정상 30건 = 반환 없음(사본도 그대로)"
    assert got["says"] == [], "⑦ 진단 줄 0"


@needs_node
def test_g_bad_call_without_pair_changes_only_the_call():
    got = ctx([{"role": "user", "content": "x"}, assistant([call("toolu_9", "a" * 201)])])
    out = got["ret"]["messages"]
    assert out[1]["content"][0]["name"] == PLACEHOLDER and len(out) == 2, "⑧ 짝 없는 어김 toolCall 만 바뀜 · 메시지 추가 0"
    assert got["mutated"] is False, "⑧ 원본 손 0"


@needs_node
def test_h_registers_exactly_two_hooks_and_stays_short():
    got = node([{"op": "judge", "names": ["bash"]}])
    assert got["hooks"] == ["message_end", "context"], "등록 = message_end · context 2개"
    assert len(GUARD.read_text(encoding="utf-8").splitlines()) <= 200, "≤200줄"


@needs_node
def test_i_baseline_is_red_on_d_and_e(tmp_path):
    baseline = mutant(tmp_path, 0, 'return typeof name === "string" && name.length > 0 && name.length <= CAP && SHAPE.test(name);', "return true;")
    assert end(assistant([call("toolu_1", BAD313)]), guard=baseline)["ret"] is None, "기준판(가드 없음) ④ Red"
    got = ctx([{"role": "user", "content": "x"}, assistant([call("toolu_1", BAD313)]),
               result("toolu_1", BAD313)], guard=baseline)
    assert got["ret"] is None and got["mutated"] is False, "기준판 ⑥ Red"
    assert end(assistant([call("toolu_1", BAD313)]))["ret"]["message"]["content"][0]["name"] == PLACEHOLDER, "원본은 ④ PASS"
    assert ctx([{"role": "user", "content": "x"}, assistant([call("toolu_1", BAD313)]),
                result("toolu_1", BAD313)])["ret"]["messages"][2]["toolName"] == PLACEHOLDER, "원본은 ⑥ PASS"


MUTANTS = {
    "M1": ("export const CAP = 200;", "export const CAP = 400;"),
    "M2": ("name.length <= CAP && SHAPE.test(name);", "name.length <= CAP;"),
    "M3": ("    return { message: fixed.message };", "    return;"),
    "M4": ('if (msg.role === "toolResult" && !nameOk(msg.toolName)) {', 'if (false && msg.role === "toolResult" && !nameOk(msg.toolName)) {'),
    "M5": ('    const fixed = repairMessages(event?.messages);\n    if (!fixed) return;',
           '    const fixed = repairMessages(event?.messages);\n    if (!fixed) return { messages: event.messages };'),
}


@needs_node
def test_z_mutants_break_their_cases(tmp_path):
    for index, (name, (old, new)) in enumerate(MUTANTS.items()):
        bad = mutant(tmp_path, index + 1, old, new)
        if name == "M1":
            want = [False]
            assert judge("a" * 201, guard=bad) != want, "M1 상한 400 = ① 이 안 잡힌다"
            assert judge("a" * 201) == want, "원본 ①"
        elif name == "M2":
            want = [False]
            assert judge("bash ls", guard=bad) != want, "M2 길이만 = ③ 이 안 잡힌다"
            assert judge("bash ls") == want, "원본 ③"
        elif name == "M3":
            assert end(assistant([call("toolu_1", BAD313)]), guard=bad)["ret"] is None, "M3 message_end 고침 삭제 = ④ FAIL"
            assert end(assistant([call("toolu_1", BAD313)]))["ret"]["message"]["content"][0]["name"] == PLACEHOLDER, "원본 ④"
        elif name == "M4":
            got = ctx([{"role": "user", "content": "x"}, assistant([call("toolu_1", BAD313)]), result("toolu_1", BAD313)], guard=bad)
            assert got["ret"]["messages"][2]["toolName"] == BAD313, "M4 짝 고침 삭제 = ⑥ FAIL"
            got = ctx([{"role": "user", "content": "x"}, assistant([call("toolu_1", BAD313)]), result("toolu_1", BAD313)])
            assert got["ret"]["messages"][2]["toolName"] == PLACEHOLDER, "원본 ⑥"
        else:
            got = ctx([{"role": "user", "content": "x"}] + [assistant([call(f"t{i}", "bash")]) for i in range(30)], guard=bad)
            assert got["ret"] is not None, "M5 바꿀 것 0 인데 반환 = ⑦ FAIL"
            assert ctx([{"role": "user", "content": "x"}] + [assistant([call(f"t{i}", "bash")]) for i in range(30)])["ret"] is None, "원본 ⑦"
