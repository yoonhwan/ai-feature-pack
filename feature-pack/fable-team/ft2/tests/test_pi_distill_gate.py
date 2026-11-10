"""ft2 pi distill-gate 시험 — 사례 ⓐ~ⓙ + 변이 M1~M5 (r1553 카드).

extension 은 TypeScript 다. pytest 는 node 로 그것을 불러 «판정»만 받는다(격리 픽스처 = tmp_path).
ⓘ 만 실제 claude 훅(context-distill-gate.sh)을 가짜 transcript 로 돌려 같은 20 입력의 allow/deny 를 대조한다.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
GATE = FT2 / "adapters" / "pi" / "distill-gate.ts"
HOOK = Path(os.environ.get("FT_CLAUDE_HOOK", Path.home() / ".claude" / "hooks" / "context-distill-gate.sh"))
NODE = shutil.which("node")
BIN = "." + "fable-team" + "/bin"   # 1.x 경로 문자열이라 조각으로 조립한다(legacy_guard 자기검사)
TH = "FT_DISTILL_WARN=300000\nFT_DISTILL_BLOCK=320000\nFT_DISTILL_RECV=250000\n"
CLAUDE, SEAT = "claude-sonnet-5-5", "byz-x-nano#0"
DRIVER = """
import fs from "node:fs";
const mod = await import(process.env.FT_GATE), req = JSON.parse(fs.readFileSync(0, "utf8"));
const out = req.op === "thresholds" ? mod.thresholds(req.env, req.cwd) : req.cases.map((c) => {
  try { return mod.judge({ ...c, cwd: req.cwd, env: req.env }); } catch (e) { return { action: "throw", rule: "error", reason: String(e) }; } });
process.stdout.write(JSON.stringify(out));
"""

def run_gate(gate, root, cases, env=None, op="judge", home=None):
    """확장을 node 로 불러 판정만 받는다 — home 을 주면 사용자 thresholds.env 단(段)을 격리한다."""
    child = {"PATH": os.environ["PATH"], "FT_GATE": gate.resolve().as_uri(), "HOME": str(home or root.parent)}
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], input=json.dumps({"op": op, "cwd": str(root), "env": env or {}, "cases": cases}),
                          capture_output=True, text=True, timeout=60, env=child)
    assert proc.returncode == 0, proc.stderr[-800:]
    return json.loads(proc.stdout)

def build(tmp):
    """격리 리포 루트 — .git 폴더 · thresholds · seats 명부 · mbox/승계 스크립트 자리."""
    root = tmp / "repo"
    for d in (".git", BIN, ".fable-team/comm", ".fable-team/state", "design/harness/inbox/arch"):
        (root / d).mkdir(parents=True, exist_ok=True)
    for name in ("mbox.sh", "ft-mbox.sh", "ft-successor-open.sh"):
        (root / (".fable-team/comm" if name == "ft-mbox.sh" else BIN) / name).write_text("#!/bin/bash\n", encoding="utf-8")
    (root / ".fable-team" / "thresholds.env").write_text(TH, encoding="utf-8")
    (root / ".fable-team" / "seats-harness.json").write_text(json.dumps({"byz-x-master#1": {"role": "master"},
        "byz-x-master#0": {"role": "master", "_replaced_by": "byz-x-master#1"}, "byz-x-nano#0": {"role": "nano"}}), encoding="utf-8")
    (root / "design" / "harness" / "HANDOFF-a.md").write_text("x\n", encoding="utf-8")
    return root

def capture_mbox(tmp, tag=""):
    """알림 실측용 mbox — 확장이 `bash <FT_MBOX> send …` 로 부르므로 실행 비트가 필요 없다."""
    script = tmp / f"mbox-capture{tag}.sh"
    script.write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{tmp}/mbox{tag}.log"\n', encoding="utf-8")
    return script, tmp / f"mbox{tag}.log"

def cases(*items):
    return [{"tool": t, "tokens": k, "model": CLAUDE, "seat": SEAT, **rest} for t, k, rest in items]

def bash(*cmds, k=330000):
    return cases(*[("bash", k, {"command": c}) for c in cmds])

def actions(got):
    return [v["action"] for v in got]

def test_a_thresholds_priority_and_no_numbers(tmp_path):
    root, home = build(tmp_path), tmp_path / "home"
    (home / ".claude" / "fable-team").mkdir(parents=True)
    (home / ".claude" / "fable-team" / "thresholds.env").write_text("FT_DISTILL_WARN=1111\nFT_DISTILL_BLOCK=2222\nFT_DISTILL_RECV=3333\n", encoding="utf-8")
    assert run_gate(GATE, root, [], op="thresholds", home=home) == {"warn": 300000, "block": 320000, "recv": 250000}
    (root / ".fable-team" / "thresholds.env").write_text("FT_DISTILL_BLOCK=320000\n", encoding="utf-8")
    assert run_gate(GATE, root, [], env={"FT_DISTILL_RECV": "4444"}, op="thresholds", home=home) == {"warn": 1111, "block": 320000, "recv": 4444}
    assert not re.findall(r"\b\d{5,}\b", GATE.read_text(encoding="utf-8")), "extension 안에 문턱 숫자를 두지 않는다"

def test_b_warn_line_blocks_nothing(tmp_path):
    got = run_gate(GATE, build(tmp_path), bash("rm -rf x", "echo hi", k=305000))
    assert actions(got) == ["warn", "warn"] and "경고선" in got[0]["reason"], got

def test_c_block_allowlist(tmp_path):
    root = build(tmp_path)
    got = run_gate(GATE, root, cases(("read", 330000, {"path": "/etc/passwd"}),
        ("write", 330000, {"path": str(root / "design/harness/HANDOFF-a.md")}), ("bash", 330000, {"command": "git status"}),
        ("bash", 330000, {"command": "git commit --only -F /tmp/m -- a.txt"})) + bash("rm -rf build", "echo hi") +
        cases(("write", 330000, {"path": "/tmp/out.md"}), ("grep", 330000, {})))
    assert actions(got) == ["allow"] * 4 + ["block"] * 4, got

def test_d_recv_gate(tmp_path):
    root, base = build(tmp_path), None
    base = f"bash {root}/{BIN}/mbox.sh"
    got = run_gate(GATE, root, bash(*[base + s for s in (" recv me", " peek me", ' send a b "hi"', " relay a b /tmp/f",
                                                       " handover a b", " ready a b", " close-check a")], k=260000))
    assert actions(got) == ["block"] + ["allow"] * 6 and got[0]["rule"] == "recv-gate", got

def test_e_undecidable_blocks_and_notifies_once(tmp_path):
    root = build(tmp_path)
    mbox, log = capture_mbox(tmp_path)
    same = cases(("bash", None, {"command": "ls"}), ("read", 0, {}), ("bash", None, {"command": "ls"}))
    assert actions(run_gate(GATE, root, same, env={"FT_MBOX": str(mbox)})) == ["block"] * 3
    lines = log.read_text(encoding="utf-8").strip().splitlines()
    assert lines == [f"send byz-x-master#1 {SEAT} [긴급] 증류 판정 불가 {SEAT} ctx usage 없음"], "같은 좌석·같은 이유 1통"
    other = run_gate(GATE, root, [{"tool": "read", "tokens": 300000, "model": CLAUDE, "seat": ""}], env={"FT_MBOX": str(mbox)})
    assert other[0]["action"] == "block" and "좌석 이름 못 읽음" in other[0]["reason"], other
    assert len(log.read_text(encoding="utf-8").strip().splitlines()) == 2, "이유가 다르면 다른 1통"
    (root / ".fable-team" / "thresholds.env").write_text("", encoding="utf-8")
    nofile = run_gate(GATE, root, cases(("read", 330000, {})), env={"FT_MBOX": str(mbox)}, home=tmp_path / "nohome")
    assert nofile[0]["action"] == "block" and "문턱 못 읽음" in nofile[0]["reason"], nofile

def test_f_non_claude_models_pass(tmp_path):
    got = run_gate(GATE, build(tmp_path), [{"tool": "bash", "tokens": 999999, "model": m, "seat": SEAT, "command": "rm -rf x"}
                                           for m in ("opengateway/gpt-6-sol", "gemini-3-pro", "deepseek/deepseek-v4-pro", "")])
    assert actions(got) == ["allow"] * 4 and {v["rule"] for v in got} == {"model-out-of-scope"}, got

def test_g_pending_file_written_once(tmp_path):
    root = build(tmp_path)
    got = run_gate(GATE, root, bash("git status", k=305000) + bash("rm -rf x", k=330000) + bash("rm -rf y", k=400000))
    assert actions(got) == ["warn", "block", "block"], got
    state = root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano"
    assert state.is_file() and "ctx=330000" in state.read_text(encoding="utf-8"), "차단과 같이 미완 표식이 먼저 생긴다"
    before = state.read_text(encoding="utf-8")
    run_gate(GATE, root, bash("rm -rf z", k=500000))
    assert state.read_text(encoding="utf-8") == before, "이미 있으면 덮어쓰지 않는다(DA 반례 4)"

def test_h_pending_blocks_new_work_allows_successor(tmp_path):
    root, base = build(tmp_path), ""
    state = root / ".fable-team" / "state" / "pi-distill-pending"
    state.mkdir(parents=True)
    (state / "byz-x-nano").write_text("old\n", encoding="utf-8")
    base = f"bash {root}/.fable-team"
    got = run_gate(GATE, root, bash(base + "/bin/mbox.sh recv me", k=260000) +
                   bash(base + "/bin/ft-successor-open.sh old wt --name new", base + "/comm/ft-mbox.sh handover old new") +
                   cases(("write", 330000, {"path": str(root / "design/harness/HANDOFF-b.md")})))
    assert actions(got) == ["block", "allow", "allow", "allow"], got

PARITY = [("Read", "read", "design/harness/HANDOFF-a.md"), ("Read", "read", "/etc/passwd"), ("Write", "write", "design/harness/HANDOFF-a.md"),
          ("Write", "write", "design/harness/inbox/arch/01-a.md"), ("Write", "write", ".fable-team/state/successor/x.json"),
          ("Write", "write", ".fable-team/state/x.sh"), ("Write", "write", "/tmp/out.md"), ("Write", "write", "src/a.ts"),
          ("Edit", "edit", "design/harness/VERDICT-da.md")]
PARITY_CMD = ["git status", "git add -A", "git commit --only -F /tmp/m -- a.txt", "git push origin nano/x", "git push --force origin x",
              "git log --oneline -5", "rm -rf build", "echo hi", "bash {r}/{b}/mbox.sh send a b \"hi\"",
              "bash {r}/{b}/ft-successor-open.sh a b", "bash {r}/.fable-team/comm/ft-mbox.sh handover a b"]

def hook_verdict(hook, root, home, tool, tool_input):
    (root / "transcript.jsonl").write_text(json.dumps({"type": "assistant", "message": {"model": CLAUDE, "usage": {
        "input_tokens": 1000, "cache_read_input_tokens": 320000, "cache_creation_input_tokens": 9000}}}) + "\n", encoding="utf-8")
    payload = {"transcript_path": str(root / "transcript.jsonl"), "tool_name": tool, "tool_input": tool_input, "cwd": str(root)}
    proc = subprocess.run(["bash", str(hook), "hard", "--warn-at", "300000", "--block-at", "320000", "--recv-gate-at", "250000"],
                          input=json.dumps(payload), capture_output=True, text=True, timeout=60, env={"PATH": os.environ["PATH"], "HOME": str(home)})
    assert proc.returncode in (0, 2), proc.stderr[-500:]
    return proc.returncode == 0

def test_i_allowlist_matches_claude_hook(tmp_path):
    if not HOOK.is_file():
        pytest.skip(f"claude 훅 없음 — {HOOK}")
    root, home, mine, theirs = build(tmp_path), tmp_path / "home", [], []
    home.mkdir(exist_ok=True)
    for tool, pi_tool, value in PARITY:
        path = str(root / value) if not value.startswith("/") else value
        theirs.append(hook_verdict(HOOK, root, home, tool, {"file_path": path}))
        mine.append((pi_tool, {"path": path}))
    for cmd in PARITY_CMD:
        text = cmd.format(r=root, b=BIN)
        theirs.append(hook_verdict(HOOK, root, home, "Bash", {"command": text}))
        mine.append(("bash", {"command": text}))
    got = run_gate(GATE, root, [{"tool": t, "tokens": 330000, "model": CLAUDE, "seat": SEAT, **rest} for t, rest in mine])
    assert sorted(theirs) == [False, False, False, False, False, False, True, True, True, True, True, True, True, True, True, True, True, True, True, True], "훅 판정이 한 쪽으로 쏠리면 대조가 무의미하다"
    assert [v["action"] != "block" for v in got] == theirs, [(PARITY + [("Bash", "", c) for c in PARITY_CMD])[i] for i in range(len(theirs)) if got[i]["action"] == ("block" if theirs[i] else "allow")]

def test_j_successor_clears_pending(tmp_path):
    root = build(tmp_path)
    state = root / ".fable-team" / "state" / "pi-distill-pending"
    state.mkdir(parents=True)
    (state / "byz-x-nano").write_text("old\n", encoding="utf-8")
    assert actions(run_gate(GATE, root, bash("git status", k=120000))) == ["allow"] and not (state / "byz-x-nano").exists()

MUTANTS = {"M1_판정불가를_통과로": ('action: "block", rule: "undecidable"', 'action: "allow", rule: "undecidable"'),
           "M2_팀장알림_빼기": ('const bad = notifyTeam(input, env, seat || "unknown", root, why);', 'const bad = "";'),
           "M3_허용목록에서_handover_빼기": ('"ring", "handover", ', '"ring", '),
           "M4_gpt도_판정": ("if (!/claude/i.test(model)) return", "if (!model) return"),
           "M5_상태파일_덮어쓰기": ('    if (fs.existsSync(p)) return "";\n    fs.mkdirSync(path.dirname(p), { recursive: true });\n    fs.writeFileSync(p, `${new Date().toISOString()} ${seat} ctx=${tokens} 증류 미완\\n`, { flag: "wx" });',
                                 '    fs.mkdirSync(path.dirname(p), { recursive: true });\n    fs.writeFileSync(p, `${new Date().toISOString()} ${seat} ctx=${tokens} 증류 미완\\n`);')}

def mutant(tmp_path, name):
    old, new = MUTANTS[name]
    source = GATE.read_text(encoding="utf-8")
    assert old in source, name
    path = tmp_path / f"{name}.ts"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return path

def test_m_mutants_break_their_cases(tmp_path):
    root, home = build(tmp_path), tmp_path / "home"
    home.mkdir(exist_ok=True)
    for name in MUTANTS:
        m = mutant(tmp_path, name)
        if name[1] in "12":   # M1 판정 불가를 통과로 · M2 팀장 1줄 빼기
            mbox, log = capture_mbox(tmp_path, name[:2])
            got = run_gate(m, root, cases(("read", 0, {})), env={"FT_MBOX": str(mbox)})
            assert (got[0]["action"] != "block") if name[1] == "1" else (not log.exists()), name
        elif name[1] == "3":   # M3 허용 목록에서 handover 빼기 → 훅은 허용, 변이본은 차단 = ⓘ 가 깨진다
            cmd = f"bash {root}/.fable-team/comm/ft-mbox.sh handover a b"
            assert run_gate(m, root, bash(cmd))[0]["action"] == "block", name
            assert hook_verdict(HOOK, root, home, "Bash", {"command": cmd}), name
        elif name[1] == "4":   # M4 gpt 모델도 판정
            assert actions(run_gate(m, root, [{"tool": "bash", "tokens": 999999, "model": "gpt-6-sol", "seat": SEAT, "command": "rm -rf x"}])) == ["block"], name
        else:                  # M5 상태 파일 덮어쓰기
            run_gate(m, root, bash("rm -rf x", k=330000))
            state = root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano"
            run_gate(m, root, bash("rm -rf y", k=400000))
            assert "ctx=400000" in state.read_text(encoding="utf-8"), name

def test_legacy_guard_clean():
    proc = subprocess.run([sys.executable, str(FT2 / "tools" / "legacy_guard.py"), str(FT2)], capture_output=True, text=True, timeout=60)
    assert proc.returncode == 0, proc.stdout + proc.stderr
