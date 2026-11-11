"""ft2 pi distill-gate r1634 시험 — ft 좌석이 아니면 아무것도 하지 않는다(ⓐⓑ) · 좌석 안 동작은 그대로(ⓒⓓ) · 변이 M1·M2 검출.
extension 은 TypeScript 라 node 로 불러 «판정»만 받는다. 픽스처 = tmp_path 뿐 — 실 tmux 0(PATH 스텁) · 실 명부 0 · 실 우편함 0."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GATE = FT2 / "adapters" / "pi" / "distill-gate.ts"
NODE = shutil.which("node")
CLAUDE, SEAT = "claude-sonnet-5-5", "byz-x-nano#0"
DRIVER = """
import fs from "node:fs"; const mod = await import(process.env.FT_GATE), req = JSON.parse(fs.readFileSync(0, "utf8"));
if (req.op === "judge") process.stdout.write(JSON.stringify(req.cases.map((c) => { try { return mod.judge({ ...c, cwd: req.cwd, env: req.env }); } catch (e) { return { action: "throw", rule: "error", reason: String(e) }; } })));
else {
  const err = [], orig = console.error; console.error = (...a) => err.push(a.map(String).join(" "));  // 확장이 내는 stderr 를 모은다
  const pi = { h: {}, on(e, f) { (this.h[e] ??= []).push(f); } }; mod.default(pi);
  await pi.h.session_start[0]({ reason: "startup" }, {});
  const ctx = { cwd: req.cwd, model: { id: "claude-sonnet-5-5" }, getContextUsage: () => null, sessionManager: { getEntries: () => [] } }, out = [];
  for (const c of req.cases) out.push((await pi.h.tool_call[0]({ toolName: c.tool, input: c.input ?? {} }, ctx)) ?? null);
  console.error = orig; process.stdout.write(JSON.stringify({ results: out, stderr: err }));
}"""


def run(gate, cwd, cases, op="judge", env=None):
    e = {"PATH": os.environ["PATH"], "HOME": str(cwd), "FT_GATE": gate.resolve().as_uri()}
    e.update(env or {})
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], capture_output=True, text=True, timeout=60, env=e,
                          input=json.dumps({"op": op, "cwd": str(cwd), "env": env or {}, "cases": cases}))
    if proc.returncode != 0:
        pytest.fail(proc.stderr[-800:])
    return json.loads(proc.stdout)


def build(tmp):
    root = tmp / "repo"
    for d in (".git", ".fable-team/comm", ".fable-team/state", "design/harness/inbox/arch"):
        (root / d).mkdir(parents=True, exist_ok=True)
    (root / ".fable-team" / "thresholds.env").write_text("FT_DISTILL_WARN=300000\nFT_DISTILL_BLOCK=320000\nFT_DISTILL_RECV=250000\n", encoding="utf-8")
    (root / ".fable-team" / "seats-harness.json").write_text(json.dumps({"_master": "byz-x-master#1", "byz-x-master#1": {"role": "master"}, SEAT: {"role": "nano"}}), encoding="utf-8")
    plain = tmp / "plain"  # git 밖 빈 폴더 = «cwd ~ 일반 pi» 대역
    plain.mkdir()
    return root, plain


def capture(tmp):
    p = tmp / "mbox-capture.sh"
    p.write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{tmp}/mbox.log"\n', encoding="utf-8")
    return p, tmp / "mbox.log"


def stub_path(tmp, name):
    d = tmp / "bin"
    d.mkdir(exist_ok=True)
    p = d / "tmux"
    p.write_text(f"#!/bin/sh\necho {name}\n", encoding="utf-8")
    p.chmod(0o755)
    return f"{d}:{os.environ['PATH']}"


def tools(*names):
    return [{"tool": n, "tokens": None, "model": CLAUDE, "input": {"command": "ls"} if n == "bash" else {}} for n in names]


def test_a_outside_seat_no_tool_blocked_nothing_written(tmp_path):
    root, plain = build(tmp_path)
    mbox, log = capture(tmp_path)
    got = run(GATE, plain, tools("bash", "read", "write", "edit"), op="ext", env={"FT_MBOX": str(mbox)})
    assert got["results"] == [None] * 4 and got["stderr"] == [], got  # 전부 통과 · 에러 줄 0
    assert not log.exists(), "좌석 밖 = 팀장 알림 0"
    assert not (plain / ".fable-team").exists(), "좌석 밖 = 표식·상태 폴더 쓰기 0"


def test_b_tmux_session_without_roster_row_is_not_a_seat(tmp_path):
    root, _ = build(tmp_path)
    got = run(GATE, root, tools("bash", "read", "write"), env={"TMUX_PANE": "%1", "PATH": stub_path(tmp_path, "random-tmux-1")})
    assert [v["action"] for v in got] == ["allow"] * 3 and {v["rule"] for v in got} == {"not-seat"}, got


def test_c_inside_seat_judging_unchanged(tmp_path):
    root, _ = build(tmp_path)
    got = run(GATE, root, [{"tool": "bash", "tokens": None, "model": CLAUDE, "seat": SEAT, "command": "ls"},
                           {"tool": "bash", "tokens": 305000, "model": CLAUDE, "seat": SEAT, "command": "echo hi"}], env={"FT_SEAT": SEAT})
    assert [v["rule"] for v in got] == ["undecidable", "warn-line"], got


def test_d_inside_seat_fail_closed_kept(tmp_path):
    root, _ = build(tmp_path)
    got = run(GATE, root, [{"tool": "bash", "tokens": 330000, "model": "", "seat": SEAT, "command": "ls"}], env={"FT_SEAT": SEAT})
    assert got[0]["action"] == "block" and "모델 불명" in got[0]["reason"], got


def mutant(tmp_path, name, old, new):
    source = GATE.read_text(encoding="utf-8")
    assert old in source, name
    path = tmp_path / f"{name}.ts"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return path


def test_m_mutants_break_their_cases(tmp_path):
    root, plain = build(tmp_path)
    m1 = mutant(tmp_path, "M1", "if (seatVerdict(env, root, seat, input.seat !== undefined) === false)", "if (false)")  # 좌석 판정 빼기
    got = run(m1, plain, tools("bash"), op="ext")
    assert got["results"] != [None] and got["stderr"], "M1 좌석 판정 빼기 → ⓐ FAIL 검출"
    m2 = mutant(tmp_path, "M2", "if (!seat) return env.TMUX_PANE || declared ? null : false;", "if (env.TMUX_PANE) return true; if (!seat) return declared ? null : false;")  # TMUX_PANE 있으면 좌석
    got = run(m2, root, tools("bash"), env={"TMUX_PANE": "%1", "PATH": stub_path(tmp_path, "random-tmux-1")})
    assert got[0]["action"] != "allow", "M2 «TMUX_PANE 있으면 좌석» → ⓑ FAIL 검출"
