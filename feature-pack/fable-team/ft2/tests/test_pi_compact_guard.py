"""ft2 pi compact-guard 시험 (r1552 카드) — 사례 ⓐ~ⓗ · ⓘ payload 재추산 · 변이 M1~M5 · 차단 기제 2. 차단 기제 = 설치본 실물 대조. ① throw 는 pi 가 삼킨다(runner try/catch) ② onPayload 안의 abort 는 provider 요청 0(가짜 fetch 계수 · 대조군 1). 격리 = tmp_path · 가짜 ctx · 가짜 payload · 가짜 fetch."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GUARD = FT2 / "adapters" / "pi" / "compact-guard.ts"
BUDGET = FT2 / "adapters" / "pi" / "compact_guard_budget.json"
NODE = shutil.which("node")
SEAT, OPUS, BASE = "byz-x-nano#0", "claude-opus-5-5", "byz-x-nano"  # opus = W 1,000,000 · O 64,000 · G 36,000 → C 900,000
DRIVER = """
import fs from "node:fs";
const mod = await import(process.env.FT_GUARD), req = JSON.parse(fs.readFileSync(0, "utf8"));
const table = mod.loadBudget(req.budget);
if (req.mode === "wiring") {
  const calls = [], handlers = {};
  mod.default({ on: (name, fn) => { (handlers[name] ??= []).push(fn); } });
  const ctx = { model: { id: req.model }, cwd: req.root, getContextUsage: () => ({ tokens: req.tokens }),
    abort: () => calls.push("abort"), compact: () => calls.push("compact"), ui: { notify: (m) => calls.push("notify:" + m.slice(0, 30)) } };
  handlers.session_start[0]({}, ctx);
  if (req.compacting) handlers.session_before_compact[0]({}, ctx);
  const payload = { messages: [{ role: "user", content: "x" }], ...(req.bytes ? { blob: "x".repeat(req.bytes) } : {}) };
  const out = handlers.before_provider_request[0]({ type: "before_provider_request", payload }, ctx);
  process.stdout.write(JSON.stringify({ calls, untouched: out === undefined }));
} else {
  const guard = mod.createGuard({ table, root: req.root, seat: req.seat }), out = [];
  for (const op of req.ops) out.push(op.op === "request" ? guard.request({ tokens: op.tokens, model: op.model, payload: op.bytes ? { blob: "x".repeat(op.bytes) } : undefined })
    : op.op === "limit" ? mod.limitFor(table, op.model) : (op.op === "beforeCompact" ? guard.beforeCompact() : guard.compactDone(), null));
  process.stdout.write(JSON.stringify({ out, file: guard.file() }));
}
"""
SWALLOW = """
const { ExtensionRunner } = await import(process.env.PI_MODULES + "/@earendil-works/pi-coding-agent/dist/core/extensions/runner.js");
const runtime = { isActive: () => true, mcpServers: { list: () => [], setChangeListener: () => {} }, pendingProviderRegistrations: [], pendingNativeProviderRegistrations: [], pendingVirtualModelRegistrations: [], flagValues: new Map() };
const handler = async () => { throw new Error("ft2 compact-guard: ctx 초과"); };
const runner = new ExtensionRunner([{ path: "/tmp/fake-guard.ts", handlers: new Map([["before_provider_request", [handler]]]) }], runtime, "/tmp", {}, {});
const errors = []; runner.onError((e) => errors.push(e.event));
const payload = { messages: [{ role: "user", content: "x" }] }, out = await runner.emitBeforeProviderRequest(payload);
process.stdout.write(JSON.stringify({ same: out === payload, errors }));
"""
ABORT = """
const { stream } = await import(process.env.PI_MODULES + "/@earendil-works/pi-ai/dist/api/openai-completions.js");
const model = { provider: "fake", id: "fake-1", api: "openai-completions", baseUrl: "http://127.0.0.1:9/v1", contextWindow: 1000000, maxTokens: 1000, input: ["text"] };
const context = { messages: [{ role: "user", content: "hi" }] };
async function run(abortInPayload) {
  let fetches = 0; const ac = new AbortController();
  const response = stream(model, context, { apiKey: "k", signal: ac.signal, maxRetries: 0, fetch: async () => { fetches++; throw new Error("no-network"); },
    onPayload: async (payload) => { if (abortInPayload) ac.abort(); return payload; } });
  const stopReason = (await response.result()).stopReason; // 계수는 await 뒤에 읽는다(객체 리터럴은 앞에서 평가된다)
  return { fetches, stopReason };
}
process.stdout.write(JSON.stringify({ control: await run(false), aborted: await run(true) }));
"""
MODULES = next(iter(sorted((Path.home() / ".pi/agent/install/releases").glob("*/node_modules"))), None)
needs_pi = pytest.mark.skipif(not (MODULES and (MODULES / "@earendil-works").is_dir()), reason="pi 설치본 없음")  # 설치본 없으면 기제 2건 skip


def node(code, inputs=None, extra=None):
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp"), "PI_MODULES": str(MODULES), **(extra or {})}
    proc = subprocess.run([NODE, "--input-type=module", "-e", code], capture_output=True, text=True, timeout=60, input=inputs, env=env)
    if proc.returncode != 0: pytest.fail(proc.stderr[-800:])
    return json.loads(proc.stdout)


def run(root, ops=(), mode="ops", guard=GUARD, budget=BUDGET, **extra):
    body = {"mode": mode, "root": str(root), "seat": SEAT, "budget": str(budget), "ops": list(ops), **extra}
    return node(DRIVER, json.dumps(body), {"FT_GUARD": guard.resolve().as_uri(), "FT_COMPACT_GUARD_BUDGET": str(budget), "FT_SEAT": SEAT, "HOME": str(Path(root).parent)})


def build(tmp):
    root = tmp / "repo"
    for d in (".git", ".fable-team/state/pi-compact-pending", ".fable-team/state/pi-distill-pending"): (root / d).mkdir(parents=True, exist_ok=True)
    return root


def marks(root, kind="pi-compact-pending"): return sorted(p.name for p in (root / ".fable-team" / "state" / kind).iterdir())


def body_of(root): return (root / ".fable-team/state/pi-compact-pending" / BASE).read_text(encoding="utf-8")


def req(tokens, model=OPUS): return {"op": "request", "tokens": tokens, "model": model}


def test_a_budget_table_real_numbers_and_unknown_model_is_refused(tmp_path):
    root = build(tmp_path)
    out = run(root, [{"op": "limit", "model": OPUS}, {"op": "limit", "model": "no-such-model"}, {"op": "limit", "model": "deepseek/deepseek-v4.1-flash-ultrafast"}, req(None)])["out"]
    assert out[0] == {"w": 1000000, "o": 64000, "g": 36000, "c": 900000} and out[0]["c"] >= 350000, "정상 증류선 350k ≤ C"
    assert out[1] is None and out[2]["c"] == 898464, "표에 없는 모델 = 판정 불가(추정 0)"
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps({"models": {OPUS: {"w": 1000000, "o": 64000, "g": 36000, "c": 123}}}), encoding="utf-8")
    assert run(root, [{"op": "limit", "model": OPUS}], budget=bad)["out"][0] is None, "표의 c 가 계산과 어긋나면 판정 불가"
    assert run(root, [req(10, "no-such-model")])["out"][0]["rule"] == "no-budget", "모델 예산 없음 = 요청 거절"
    assert out[3]["action"] == "block" and out[3]["rule"] == "no-usage", "ctx 추산도 payload 도 없음 = 요청 거절(막기 0 으로 열지 않는다)"


def test_b_over_limit_writes_mark_first_and_never_twice(tmp_path):
    root = build(tmp_path)
    got = run(root, [req(900001)])["out"][0]
    assert got["action"] == "compact" and marks(root) == [BASE], "상태 파일 먼저 + 압축 1회"
    first = body_of(root)  # 덮어쓰기 판정용 사본
    again = run(root, [req(950000)])["out"][0]
    assert again["action"] == "block" and again["rule"] == "over-limit" and body_of(root) == first, "압축 직렬 1회 · 재추산 전 초과 요청 0 · 덮어쓰기 0(ⓕ)"


def test_c_close_event_deletes_only_own_mark(tmp_path):
    root = build(tmp_path)
    (root / ".fable-team/state/pi-distill-pending" / BASE).write_text("x seat=byz-x-nano#0 증류 미완\n", encoding="utf-8")
    out = run(root, [req(900001), {"op": "beforeCompact"}, {"op": "compactDone"}, req(800000)])["out"]
    assert out[0]["action"] == "compact" and out[3]["rule"] == "below-limit" and marks(root) == [], "닫는 사건 = 자기 파일만(ⓗ)"
    assert marks(root, "pi-distill-pending") == [BASE], "r1553 표식은 그대로(ⓖ)"


def test_d_compaction_failure_keeps_history_and_blocks_next_request(tmp_path):
    root = build(tmp_path)
    out = run(root, [req(900001), {"op": "beforeCompact"}, {"op": "compactDone"}, req(900002)])["out"]
    assert out[3]["action"] == "block" and out[3]["rule"] == "over-limit" and marks(root) == [BASE], "압축 실패·부족해도 다음 초과 요청 0 · 성공 이벤트로 통과 0"


def test_e_summary_request_over_window_is_refused(tmp_path):
    root = build(tmp_path)
    out = run(root, [req(900001), {"op": "beforeCompact"}, req(1000001), req(950000)])["out"]
    assert out[2]["action"] == "block" and out[2]["rule"] == "summary-window", "요약 요청도 같은 관문(ⓔ)"
    assert out[3]["action"] == "allow" and out[3]["rule"] == "summary-within", "창 안 요약 요청은 보낸다"
    assert marks(root) == [BASE], "요약 허용으로 자기 표식을 지우지 않는다(DA R2 · ⓕ)"
    assert run(root, [req(950000)])["out"][0]["rule"] == "over-limit", "압축 실패 뒤 950000 = compact 재시도 0(ⓗ · 직렬 1회)"


def test_f_pi_distill_mark_alone_never_blocks(tmp_path):
    root = build(tmp_path)
    (root / ".fable-team/state/pi-distill-pending" / BASE).write_text("x seat=byz-x-nano#0 증류 미완\n", encoding="utf-8")
    got = run(root, [req(800000)])["out"][0]
    assert got["action"] == "allow" and marks(root) == [], "r1553 표식만으로 막으면 승계 턴까지 막힌다(ⓖ)"  # 막기 0


def test_k_null_tokens_are_re_estimated_from_payload_bytes(tmp_path):
    root = build(tmp_path)
    big = run(root, [req(950000), {"op": "beforeCompact"}, {"op": "compactDone"}, {**req(None), "bytes": 2760000}])["out"]
    assert big[0]["action"] == "compact" and big[3]["rule"] == "over-limit" and marks(root) == [BASE], "압축 뒤 ctx 추산이 비어도 payload 920k 꼴이면 요청 0 · 파일 유지"
    fresh = run(build(tmp_path / "b"), [{**req(None), "bytes": 2760000}])["out"][0]
    assert fresh["rule"] == "over-limit-compact" and "ctx=920" in body_of(tmp_path / "b" / "repo"), "첫 상태 파일에는 payload 재추산 값이 적힌다"
    small = run(root, [{**req(None), "bytes": 299000}])["out"][0]
    assert small["action"] == "allow" and small["rule"] == "below-limit" and marks(root) == [], "작은 payload = ≤ C → 자기 파일만 지우고 통과"


def test_h_wiring_aborts_after_mark_and_leaves_payload_untouched(tmp_path):
    root = build(tmp_path)
    hot = run(root, mode="wiring", tokens=900001, model=OPUS)
    assert hot["untouched"] and hot["calls"][-2:] == ["compact", "abort"] and hot["calls"][0].startswith("notify:"), hot
    assert marks(root) == [BASE], "거절 1줄 + 상태 파일 + 요청 0(abort)"  # 폭주 방지: 파일 1개 유지
    assert run(root, mode="wiring", tokens=800000, model=OPUS)["calls"] == [], "임계 아래 = 아무것도 하지 않는다"


MUTANTS = {  # 카드 변이 M1~M5 — 각 변이는 자기 사례를 깬다
    "M1": ("const d = decide(opts.table, { ...input, summary, mark, tried: tried || mark });", 'const d: Decision = tried && !summary ? { action: "allow", rule: "compact-event", reason: "압축 이벤트 = 통과" } : decide(opts.table, { ...input, summary, mark, tried: tried || mark });'),
    "M2": ('if (!budget) return { action: "block"', 'if (!budget) return { action: "allow"'),
    "M3": ('{ flag: "wx" }', '{ flag: "w" }'),
    "M4": ("if (input.summary) return tokens > budget.w", 'if (input.summary) return { action: "allow", rule: "summary-within", budget, reason: "통과" }; if (false) return tokens > budget.w'),
    "M5": ('if (tokens === null) return { action: "block", rule: "no-usage"', 'if (tokens === null) return { action: "allow", rule: "no-usage"'),
}


def test_m_mutants_break_their_cases(tmp_path):
    for index, (name, (old, new)) in enumerate(MUTANTS.items()):
        source = GUARD.read_text(encoding="utf-8")
        assert old in source, name
        (tmp_path / str(index)).mkdir()
        mutant = tmp_path / str(index) / "mutant.ts"
        mutant.write_text(source.replace(old, new, 1), encoding="utf-8")
        root = build(tmp_path / str(index) / "work")
        if name == "M1":
            out = run(root, [req(900001), {"op": "beforeCompact"}, {"op": "compactDone"}, req(900002)], guard=mutant)["out"]
            assert out[3]["action"] == "allow", "M1 변이 = 압축 이벤트만으로 통과(사례 ⓓ 가 잡는다)"
        elif name == "M2":
            assert run(root, [req(10, "no-such-model")], guard=mutant)["out"][0]["action"] == "allow", "M2 변이 = 기본값 통과"
        elif name == "M5":
            assert run(root, [req(None)], guard=mutant)["out"][0]["action"] == "allow", "M5 변이 = null 통과(사례 ⓐ 의 payload 없음 칸이 잡는다)"
        elif name == "M3":
            run(root, [req(900001)], guard=mutant)
            run(root, [req(950000)], guard=mutant)
            assert "ctx=950000" in body_of(root), "M3 변이 = 상태 파일 덮어쓰기(사례 ⓕ 가 잡는다)"
        else:
            assert run(root, [req(900001), {"op": "beforeCompact"}, req(1000001)], guard=mutant)["out"][2]["action"] == "allow", "M4 변이 = 요약 요청 관문 밖(ⓔ)"


@needs_pi
def test_i_throw_is_swallowed_by_pi():
    got = node(SWALLOW)
    assert got["same"] is True and got["errors"] == ["before_provider_request"], "throw 는 payload 를 못 바꾼다 = 요청은 그대로 나가고, pi 는 오류 이벤트만 남긴다"


@needs_pi
def test_j_abort_inside_payload_hook_makes_zero_requests():
    got = node(ABORT)
    assert got["control"]["fetches"] == 1, "대조군: abort 없으면 요청 1회"
    assert got["aborted"]["fetches"] == 0 and got["aborted"]["stopReason"] == "aborted", "abort = provider 요청 0회(관문의 차단 기제)"
