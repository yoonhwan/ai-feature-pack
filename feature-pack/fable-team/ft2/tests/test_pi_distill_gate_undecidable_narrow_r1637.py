"""ft2 pi distill-gate r1637 시험 — 좌석 안 판정 불가 = recv 만 막음(ⓐ) · 읽기 전용 통과(ⓑ) · 그 밖 통과+기록(ⓒ) · 턴 주입 0(ⓓ) · ctx 읽은 경로 그대로(ⓔ) · 변이 M1~M3.
node 로 judge()·확장 훅을 직접 부른다 · 픽스처 = tmp_path 뿐(실 좌석·실 우편함 0) · sleep 0."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GATE = FT2 / "adapters" / "pi" / "distill-gate.ts"
NODE = shutil.which("node") or pytest.skip("node 없음", allow_module_level=True)
CLAUDE, SEAT, S = "claude-sonnet-5-5", "byz-x-nano#0", {"reason": "startup", "entries": []}
DRIVER = """
import fs from "node:fs"; const mod = await import(process.env.FT_GATE), req = JSON.parse(fs.readFileSync(0, "utf8"));
if (req.op === "judge") process.stdout.write(JSON.stringify(req.cases.map((c) => mod.judge({ ...c, cwd: req.cwd, env: req.env }))));
else {
  const err = [], orig = console.error; console.error = (...a) => err.push(a.map(String).join(" "));
  const pi = { h: {}, on(e, f) { (this.h[e] ??= []).push(f); } }; mod.default(pi); await pi.h.session_start[0]({ reason: "resume" }, {});
  const out = [];
  for (const c of req.cases) { const ctx = { cwd: req.cwd, model: { id: c.model ?? "claude-sonnet-5-5" }, getContextUsage: () => (c.tokens ? { tokens: c.tokens } : null), sessionManager: { getEntries: () => [] } };
    out.push((c.tool === "session" ? await pi.h.session_start[0]({ reason: c.reason }, {}) : c.tool === "turn" ? await pi.h.before_agent_start[0]({}, ctx) : await pi.h.tool_call[0]({ toolName: c.tool, input: c.input ?? {} }, ctx)) ?? null); }
  console.error = orig; process.stdout.write(JSON.stringify({ results: out, stderr: err }));
}"""

def run(gate, root, cases, env, op="judge", home=None):
    e = {"PATH": os.environ["PATH"], "HOME": str(home or root), "FT_GATE": gate.resolve().as_uri(), **(env if op == "ext" else {})}
    p = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], check=False, capture_output=True, text=True, timeout=60, env=e, input=json.dumps({"op": op, "cwd": str(root), "env": env, "cases": cases}))
    assert p.returncode == 0, p.stderr[-800:]
    return json.loads(p.stdout)

def build(tmp):
    root = tmp / "repo"
    for d in (".git", ".fable-team/comm", ".fable-team/state"):
        (root / d).mkdir(parents=True, exist_ok=True)
    (root / ".fable-team" / "thresholds.env").write_text("FT_DISTILL_WARN=300000\nFT_DISTILL_BLOCK=320000\nFT_DISTILL_RECV=250000\n", encoding="utf-8")
    (root / ".fable-team" / "seats-harness.json").write_text(json.dumps({"_master": "byz-x-master#1", SEAT: {"role": "nano"}}), encoding="utf-8")
    (tmp / "mbox.sh").write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{tmp}/mbox.log"\n', encoding="utf-8")
    return root, {"FT_SEAT": SEAT, "FT_MBOX": str(tmp / "mbox.sh")}

def reasons(tmp, gate=GATE):
    out = []  # 판정 불가 4사유 = (이름, gate, root, env, 사례 덮어쓰기, home)
    for name in ("모델 불명", "문턱 못 읽음", "좌석 이름 못 읽음", "ctx usage 없음"):
        d = tmp / name.replace(" ", "_")  # 경로 공백 0(실 좌석 경로와 같은 꼴)
        root, env = build(d)
        g, over, home = gate, {"tokens": 330000, "model": CLAUDE, "seat": SEAT, "session": S}, d / "home"
        if name == "모델 불명": over["model"] = ""
        if name == "문턱 못 읽음":
            (root / ".fable-team" / "thresholds.env").write_text("", encoding="utf-8")
            g = d / "bare" / "distill-gate.ts"  # 옆 샘플 없음 = 문턱 못 읽음
            g.parent.mkdir()
            shutil.copy(gate, g)
        if name == "좌석 이름 못 읽음": over["seat"] = ""
        if name == "ctx usage 없음": over["tokens"], env["FT_DISTILL_FAILOPEN_MAX"] = None, "1"  # 연속 N(=1) 도달
        out.append((name, g, root, env, over, home))
    return out

MB = "bash {r}/.fable-team/comm/mbox.sh"
RO = [("read", {}), ("grep", {}), ("find", {}), ("ls", {}), ("ask_user", {})] + [("bash", {"command": c}) for c in ("ls", "find . -name x", "grep -n a f", "echo $TMUX_PANE", "tmux capture-pane -p -t x", MB + " peek " + SEAT)]
PASS = [("write", {"path": "src/a.ts"}), ("edit", {"path": "src/a.ts"}), ("bash", {"command": "tmux send-keys -t x hi Enter"}), ("bash", {"command": "git commit -m x"}), ("bash", {"command": "ls > out.txt"}), ("bash", {"command": "find . -delete"})]

def judge_all(tmp, rows, gate=GATE):
    for name, g, root, env, over, home in reasons(tmp, gate):
        got = run(g, root, [{"tool": t, **over, **{k: (v.format(r=root) if isinstance(v, str) else v) for k, v in r.items()}} for t, r in rows], env, home=home)
        yield name, root, got

def test_a_recv_blocked_in_each_reason_and_team_lead_once(tmp_path):
    for name, root, got in judge_all(tmp_path, [("bash", {"command": MB + " recv " + SEAT})] * 2):
        assert [(v["action"], v["rule"]) for v in got] == [("block", "undecidable-recv")] * 2 and name in got[0]["reason"], (name, got)
        log = tmp_path / name.replace(" ", "_") / "mbox.log"
        sent = log.read_text(encoding="utf-8").count("send ") if log.exists() else 0
        assert sent == (0 if name == "좌석 이름 못 읽음" else 1), (name, sent)  # 좌석 불명 = 팀장 불명 = send 0(지금 notifyTeam 그대로)

def test_b_readonly_always_pass(tmp_path):
    for name, _, got in judge_all(tmp_path, RO):
        assert {(v["action"], v["rule"]) for v in got} == {("allow", "undecidable-readonly")}, (name, got)

def test_c_others_pass_and_logged(tmp_path):
    for name, _, got in judge_all(tmp_path, PASS):
        assert {(v["action"], v["rule"]) for v in got} == {("allow", "undecidable-pass")}, (name, got)
    root, env = build(tmp_path / "ext")
    got = run(GATE, root, [{"tool": "bash", "input": {"command": "tmux send-keys -t x hi"}}], env, op="ext")
    assert got["results"] == [None] and len(got["stderr"]) == 1 and got["stderr"][0].startswith("ft2 distill-gate: undecidable-pass "), got

def ext_turns(gate, tmp):
    root, env = build(tmp)
    recv = MB.format(r=root) + " recv " + SEAT
    return run(gate, root, [{"tool": "turn"}, {"tool": "bash", "input": {"command": "ls"}}, {"tool": "ask_user"}, {"tool": "turn"}, {"tool": "bash", "input": {"command": recv}},
                            {"tool": "turn", "tokens": 305000}, {"tool": "turn", "tokens": 305000}], env, op="ext")

def test_d_no_turn_injection_warn_once(tmp_path):
    r = (got := ext_turns(GATE, tmp_path))["results"]
    assert r[:4] == [None] * 4 and r[4]["block"] is True and "recv" in r[4]["reason"], r  # 턴 주입 0 · ls·ask_user 통과 · recv 1회 막힘
    assert r[5]["message"]["content"].startswith("⚠️") and r[6] is None, r  # warn-line 은 세션당 1회
    assert sum(ln.startswith("ft2 distill-gate: turn undecidable") for ln in got["stderr"]) == 2, got["stderr"]  # 판정 불가 턴 = stderr 1줄씩
    root, env, w = *build(tmp_path / "s"), {"tool": "turn", "tokens": 305000}  # DA HOLD #305492 반례1 — 새 세션 첫 경고는 다시 1회
    r = run(GATE, root, [w, w, {"tool": "session", "reason": "new"}, w, w], env, op="ext")["results"]
    assert [bool(x and x.get("message")) for x in r] == [True, False, False, True, False], r

def test_e_ctx_read_paths_unchanged(tmp_path):
    root, env = build(tmp_path)
    c = lambda t, k, **r: {"tool": t, "tokens": k, "model": CLAUDE, "seat": SEAT, **r}
    got = run(GATE, root, [c("bash", 260000, command=MB.format(r=root) + " recv me"), c("bash", 330000, command="rm -rf x"), c("bash", 1000, command="ls"), c("bash", 999999, command="rm -rf x", model="gpt-6-sol")], env)
    assert [v["rule"] for v in got] == ["recv-gate", "block-gate", "below-warn", "model-out-of-scope"], got
    assert run(GATE, root, [{"tool": "bash", "tokens": None, "model": CLAUDE, "command": "ls"}], {})[0]["rule"] == "not-seat"

def mutant(tmp, name, old, new):
    src = GATE.read_text(encoding="utf-8")
    assert src.count(old) == 1, name
    p = tmp / name / "distill-gate.ts"
    p.parent.mkdir(parents=True)
    p.write_text(src.replace(old, new), encoding="utf-8")
    shutil.copy(GATE.parent / "thresholds.env.sample", p.parent)
    return p

def test_m_mutants_detected(tmp_path):
    m1 = mutant(tmp_path, "M1", "return readOnly(input) ?", "return false ?")
    assert any(v["rule"] != "undecidable-readonly" for _, _, got in judge_all(tmp_path / "1", RO, m1) for v in got), "M1 readOnly 늘 거짓 → ⓑ FAIL"
    m2 = mutant(tmp_path, "M2", 'if (input.tool === "bash" && isRecv(input.command)) return { action: "block", rule: "undecidable-recv"', 'if (false) return { action: "block", rule: "undecidable-recv"')
    assert any(v["action"] != "block" for _, _, got in judge_all(tmp_path / "2", [("bash", {"command": MB + " recv " + SEAT})], m2) for v in got), "M2 recv 차단 빼기 → ⓐ FAIL"
    m3 = mutant(tmp_path, "M3", 'if (v.action === "warn" && !warned)', 'if (v.action !== "allow" || /^undecidable/.test(v.rule))')
    assert ext_turns(m3, tmp_path / "3")["results"][0] is not None, "M3 턴 주입 되살리기 → ⓓ FAIL"
