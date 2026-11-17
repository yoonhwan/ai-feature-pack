"""r2178 — ft2 좌석 도구 4개 = executionMode "sequential" · 한 턴에 묶여도 원문 순서로 하나씩 돈다.

① 등록 표면(도구마다) · ②③④ 실제 pi 러너(pi-agent-core runAgentLoop + 가짜 stream 함수 · 모델 호출 0)에서
도구 execute 를 감싼 «시작 · 끝» 기록으로 순서를 본다(BUSY 횟수는 판정에 쓰지 않는다) · 실행 단독 결과 전체는
기준판(= 칸 지운 사본)과 1:1 같다. 가짜 pi · 래퍼 · 격리 루트 = test_pi_seat_adapter.py 그대로.
러너 = PI_AGENT_CORE(agent-loop.js) > ~/.pi/agent/install/current-version 판 · 없으면 ②③④ skip(카드 알려진 한계 5).
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_pi_seat_adapter as S  # noqa: E402  같은 가짜 pi·래퍼·격리 루트

budget = S.budget
FIX = 'executionMode: "sequential" as const,'
MUTANTS = {"M1": (FIX, ""), "M2": (FIX, 'executionMode: name === "ft2_effect" ? undefined : "sequential" as const,'),
           "M3": (FIX, 'executionMode: "parallel" as const,')}


def core_path():
    if os.environ.get("PI_AGENT_CORE"):
        return Path(os.environ["PI_AGENT_CORE"])
    pi = Path.home() / ".pi" / "agent" / "install"
    try:
        ver = (pi / "current-version").read_text(encoding="utf-8").split()[0]
    except (OSError, IndexError):
        return None
    return pi / "releases" / ver / "node_modules" / "@earendil-works" / "pi-agent-core" / "dist" / "agent-loop.js"


CORE = core_path()
need_runner = pytest.mark.skipif(not (S.NODE and CORE and CORE.is_file()), reason=f"pi 러너 없음: {CORE}")
RUNNER = """
import fs from "node:fs";
const req = JSON.parse(fs.readFileSync(0, "utf8"));
const mod = await import(process.env.FT2_ADAPTER), { runAgentLoop } = await import(process.env.PI_CORE_URL);
const got = new Map(); mod.default({ registerTool: (t) => got.set(t.name, t), on: () => 0 });
const stub = (name, wait) => ({ name, label: name, description: name, parameters: { type: "object", properties: {} },
  async execute() { if (wait) await new Promise((r) => setImmediate(r)); return { content: [{ type: "text", text: name }], details: {} }; } });
const usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
const msg = (content, stopReason) => ({ role: "assistant", content, stopReason, usage, api: "fake", provider: "fake", model: "fake", timestamp: 0 });
const out = [];
for (const round of req.rounds) {
  const log = [], list = [...got.values(), stub("push", false), stub("A", true), stub("B", false)];
  const tools = list.map((t) => ({ ...t, async execute(id, p, s, u) { log.push("시작 " + t.name); const r = await t.execute(id, p, s, u, { cwd: p.root }); log.push("끝 " + t.name); return r; } }));
  const turns = [msg(round.calls.map((c, i) => ({ type: "toolCall", id: "c" + i, name: c.tool, arguments: c.params })), "toolUse"), msg([{ type: "text", text: "끝" }], "stop")];
  const streamFn = async () => { const m = turns.shift(); return { async *[Symbol.asyncIterator]() { yield { type: "done", reason: m.stopReason, message: m }; }, result: async () => m }; };
  const msgs = await runAgentLoop([{ role: "user", content: "go", timestamp: 0 }], { systemPrompt: "", messages: [], tools },
    { model: { provider: "fake", id: "fake", api: "fake" }, convertToLlm: (m) => m }, () => {}, undefined, streamFn);
  out.push({ log, results: msgs.filter((m) => m.role === "toolResult").map((m) => ({ tool: m.toolName, text: m.content[0].text, isError: m.isError === true })) });
}
process.stdout.write(JSON.stringify(out));
"""
DRIVER = S.DRIVER.replace("hasExecute:", "executionMode: t.executionMode, hasExecute:").replace(
    "out.push({ tool: c.tool, text: r.content[0].text, isError: r.isError === true, details: r.details })", "out.push(r)")


def node(tmp_path, adapter, script, payload, extra=None):
    env = {"PATH": os.environ["PATH"], "HOME": str(tmp_path), **S.seat(tmp_path, adapter)["env"], **(extra or {})}
    if CORE:
        env["PI_CORE_URL"] = CORE.resolve().as_uri()
    proc = subprocess.run([S.NODE, "--input-type=module", "-e", script], input=json.dumps(payload), capture_output=True,
                          text=True, timeout=60, env=env)
    assert proc.returncode == 0, proc.stderr[-800:]
    return json.loads(proc.stdout)


def modes(tmp_path, adapter=None):
    return {t["name"]: t.get("executionMode") for t in node(tmp_path, adapter, DRIVER, {"op": "register"})["tools"]}


def batch(tmp_path, adapter, tools, rounds):
    """회차마다 새 임시 루트(start 까지 끝냄) · 한 턴 = tools 원문 순서."""
    plan = []
    for i in range(rounds):
        S.prepare(root := tmp_path / f"r{i}", S.STARTED)
        plan.append({"calls": [{"tool": n, "params": S.params(n, root) if n.startswith("ft2_") else {}} for n in tools]})
    return node(tmp_path, adapter, RUNNER, {"rounds": plan})


def in_order(row, names):
    return row["log"] == [w + " " + n for n in names for w in ("시작", "끝")]


def accepted_in_order(row):
    docs = [json.loads(r["text"]) for r in row["results"] if r["tool"].startswith("ft2_")]
    return (not [r for r in row["results"] if r["isError"]] and [d["result"] for d in docs] == ["접수 성공"] * len(docs)
            and [d["revision"] for d in docs] == sorted(d["revision"] for d in docs))


def case2(tmp_path, adapter=None, rounds=5):
    rows = batch(tmp_path, adapter, ("ft2_effect", "push", "ft2_result"), rounds)
    return all(in_order(r, ("ft2_effect", "push", "ft2_result")) and accepted_in_order(r) for r in rows), rows


def case3(tmp_path, adapter=None, rounds=5):
    rows = batch(tmp_path, adapter, ("ft2_effect", "ft2_result"), rounds)
    return all(in_order(r, ("ft2_effect", "ft2_result")) and accepted_in_order(r) for r in rows), rows


def test_1_every_tool_is_sequential(tmp_path):
    assert modes(tmp_path) == {n: "sequential" for n in S.TOOLS}


@need_runner
def test_2_effect_push_result_run_in_written_order(tmp_path):
    ok, rows = case2(tmp_path)
    assert ok, rows


@need_runner
def test_3_effect_result_alone_run_in_order(tmp_path):
    ok, rows = case3(tmp_path)
    assert ok, rows


@need_runner
def test_4_batch_without_ft2_stays_parallel(tmp_path):
    (row,) = batch(tmp_path, None, ("A", "B"), 1)
    assert row["log"].index("시작 B") < row["log"].index("끝 A"), row


def test_single_success_result_equals_base(tmp_path):
    """구현 확인칸 ① — 도구 4개 각각 성공한 단독 호출의 결과 객체 전체(content · isError · details) = 기준판."""
    base = S.mutant(tmp_path, MUTANTS["M1"])
    seen = {}
    for label, adapter in (("base", base), ("new", None)):
        S.prepare(root := tmp_path / label, S.BASE)
        cases = [{"tool": n, "params": S.params(n, root)} for n in S.TOOLS]
        rows = node(tmp_path, adapter, DRIVER, {"op": "run", "cwd": str(root), "cases": cases}, {"FT_NOW": S.NOW})
        seen[label] = json.loads(json.dumps(rows).replace(str(root), "<root>"))
    assert [r.get("isError") for r in seen["new"]] == [None] * 4, seen["new"]
    assert seen["new"] == seen["base"]


def test_mutants_break_their_cases_and_original_does_not(tmp_path):
    for name, pair in MUTANTS.items():
        (box := tmp_path / name).mkdir()
        bad = S.mutant(box, pair)
        assert modes(box, bad) != {n: "sequential" for n in S.TOOLS} and modes(box) == {n: "sequential" for n in S.TOOLS}, name
        if name == "M2" or not CORE or not CORE.is_file():
            continue  # M2 = ① 만 깬다(② 는 result 쪽 칸으로 통과할 수 있다 · 카드 변이 줄)
        assert case2(box / "m2", bad, 1)[0] is False and case2(box / "o2", None, 1)[0] is True, name
        assert case3(box / "m3", bad, 1)[0] is False and case3(box / "o3", None, 1)[0] is True, name
