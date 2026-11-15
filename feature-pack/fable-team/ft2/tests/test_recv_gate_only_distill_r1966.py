"""r1966 — recv 문턱에 걸린 좌석도 증류·승계 쪽지는 받는다(recv --only distill) · 반례 ①~⑥·③b·③c + 변이 M1~M6.
임시 루트 · 가짜 mbox(받는 쪽 = 정본 mbox.sh 복사본 · 보내는 쪽 = 기록 스크립트) · 실 세션 0 · sleep 0 · 시험 1개 70초."""
import json
import os
import shutil
import subprocess
import time

from test_pi_distill_gate import CLAUDE, GATE, NODE, SEAT, build, capture_mbox, run_gate

COMM = GATE.parents[3] / "legacy" / "1.x" / "harness" / "comm"
HOOK = GATE.parents[3] / "legacy" / "1.x" / "harness" / "kit" / "fable-team" / "templates" / "hooks" / "context-distill-gate.sh"
K, LOW = 281000, 200000  # build() 문턱 = recv 250k · 경고 300k
assert NODE, "node 없음"

def gate_root(tmp, desk="byz-p-desk#1", mtime_ago=None, reached=False):
    root = build(tmp)
    (root / ".fable-team" / "seats-planner.json").write_text(json.dumps({"_master": "byz-p-master#1", "_desk": desk}), encoding="utf-8")
    harness = json.loads((root / ".fable-team" / "seats-harness.json").read_text(encoding="utf-8"))
    (root / ".fable-team" / "seats-harness.json").write_text(json.dumps({**harness, "_arch": "byz-x-arch#2"}), encoding="utf-8")
    if mtime_ago is not None:
        mark = root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano"
        mark.write_text(f"t seat={SEAT} ctx={K} 증류 미완\n", encoding="utf-8")
        os.utime(mark, (time.time() - mtime_ago,) * 2)
    if reached:
        (root / ".fable-team" / "state" / "successor").mkdir(parents=True)
        (root / ".fable-team" / "state" / "successor" / f"{SEAT}.json").write_text("{}", encoding="utf-8")
    return root

def judge(gate, root, *cmds, k=K, mbox=None):
    return run_gate(gate, root, [{"tool": "bash", "tokens": k, "model": CLAUDE, "seat": SEAT, "command": c} for c in cmds], env={"FT_MBOX": str(mbox)} if mbox else {})

def mutant(tmp, src, old, new):
    text = src.read_text(encoding="utf-8")
    assert old in text, old
    (out := tmp / "mut" / src.name).parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text.replace(old, new, 1), encoding="utf-8")
    return out

def queue(tmp, mutate=None):  # 정본 우편함 폴더 복사본(받는 쪽) · mutate = (파일 이름, 옛 글, 새 글)
    comm = tmp / "q" / ".fable-team" / "comm"
    shutil.copytree(COMM, comm)
    (tmp / "q" / ".git").mkdir()
    if mutate:
        shutil.copy(mutant(tmp, comm / mutate[0], *mutate[1:]), comm / mutate[0])
    return comm

def put(comm, *bodies):
    rows = [json.loads(x) for x in (comm / "mailbox.jsonl").read_text(encoding="utf-8").splitlines()] if (comm / "mailbox.jsonl").exists() else []
    seq = max([r["seq"] for r in rows], default=0)
    for i, b in enumerate(bodies, seq + 1):
        rows.append({"seq": i, "ts": "t", "to": SEAT, "from": "byz-y-master#1", "body": b})
    (comm / "mailbox.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")

def recv(comm, *opt):
    p = subprocess.run(["bash", str(comm / "mbox.sh"), "recv", SEAT, *opt], capture_output=True, text=True, timeout=30, cwd=comm.parents[1],
                       env={"PATH": os.environ["PATH"], "HOME": str(comm.parents[2]), "TMPDIR": str(comm.parents[2])})
    left = [json.loads(x)["body"] for x in (comm / "mailbox.jsonl").read_text(encoding="utf-8").splitlines()] if (comm / "mailbox.jsonl").exists() else []
    return p.returncode, [ln.split(" — ", 1)[1] for ln in p.stdout.splitlines() if ln.startswith("READ [")], left

def case_1(comm):  # ① 승계 1 + 일반 1 → 승계만 소비 · ⑥ 머리처럼 보이는 본문 중간 = 통과 아님
    put(comm, "[승계 발주] 후계 열기", "일반 발주 r9", "참고 [인계] 본문 중간")
    return recv(comm, "--only", "distill")

def case_3b(comm):  # ③b [레디] 1 → 소비 · 뒤에 온 일반 발주 잔류 · 빈 큐 뒤 일반도 잔류
    put(comm, "[레디] 후계 도달")
    first = recv(comm, "--only", "distill")
    put(comm, "일반 발주 r10")
    return first, recv(comm, "--only", "distill")

def test_1_6_3b_only_distill_consumes_pass_heads_inside_claim(tmp_path):
    assert case_1(queue(tmp_path / "a")) == (0, ["[승계 발주] 후계 열기"], ["일반 발주 r9", "참고 [인계] 본문 중간"])
    first, second = case_3b(queue(tmp_path / "b"))
    assert first == (0, ["[레디] 후계 도달"], []) and second == (0, [], ["일반 발주 r10"]), (first, second)
    assert recv(queue(tmp_path / "c"), "--only", "work")[0] == 2, "다른 --only 값 = rc 2"
    assert case_1(queue(tmp_path / "m1", ("mbox.sh", 'MBOX_ONLY_HEADS="$_only"', 'MBOX_ONLY_HEADS=""')))[2] == [], "M1 --only 무시 = 전부 소비"
    assert "참고 [인계] 본문 중간" not in case_1(queue(tmp_path / "m4", ("mbox_ops.py", 'r.get("body", "").lstrip().startswith(heads))', 'any(h in r.get("body", "") for h in heads))')))[2], "M4 본문 중간 통과"
    m6 = ("mbox_ops.py", "    if heads:\n        only =", "    if heads:\n        _after = lambda g: [x for x in g if x[1].get('body', '').startswith(heads)]\n    if False:\n        only =")
    comm6 = queue(tmp_path / "m6", m6)
    ops = comm6 / "mbox_ops.py"
    ops.write_text(ops.read_text(encoding="utf-8").replace("    if not got:\n", "    got = _after(got) if heads else got\n    if not got:\n", 1), encoding="utf-8")
    assert case_3b(comm6)[1][2] == [], "M6 잠금 밖 거르기 = 일반 발주가 큐에서 사라진다"

def test_2_3_4_5_gate(tmp_path):
    mbox, log = capture_mbox(tmp_path)
    root = gate_root(tmp_path / "g")
    bare, only = f"bash {root}/.fable-team/comm/mbox.sh recv {SEAT}", f"bash {root}/.fable-team/comm/mbox.sh recv {SEAT} --only distill"
    got = judge(GATE, root, bare, only, f"{only}; {bare}", bare, mbox=mbox)
    assert [v["rule"] for v in got] == ["recv-gate", "recv-only-distill", "recv-gate", "recv-gate"] and "--only distill" in got[0]["reason"], got  # ② · 섞인 맨 recv = 막음
    crit = [ln for ln in log.read_text(encoding="utf-8").splitlines() if "[크리티컬]" in ln]
    assert [ln.split(" ")[1] for ln in crit] == ["byz-x-master#1", "byz-p-desk#1"] and f"ctx={K}" in crit[0], crit  # ④ 첫 걸림 1통씩 · 두 번째 0
    assert [v["action"] for v in judge(GATE, gate_root(tmp_path / "r", reached=True), bare)] == ["allow"], "③ 도달 파일 = 맨 recv 통과"
    assert [v["rule"] for v in judge(GATE, gate_root(tmp_path / "l"), bare, k=LOW)] == ["below-warn"], "⑤ 문턱 아래 = 지금처럼"
    assert [v["rule"] for v in judge(GATE, gate_root(tmp_path / "c"), f"{bare} # --only distill", f"{bare} #--only distill", f"{bare} '--only distill'")] == ["recv-gate"] * 3, "R1 주석·따옴표 속 --only = 실제 옵션 아님"
    m2 = mutant(tmp_path, GATE, 'if (only) return { action: "allow"', 'if (true) return { action: "allow"')
    assert judge(m2, gate_root(tmp_path / "m2"), bare)[0]["action"] == "allow", "M2"
    m3, (mbox3, log3) = mutant(tmp_path / "3", GATE, "if (!to || notified.has(`${seat}|${key}|${to}`)) return \"\";", 'if (!to) return "";'), capture_mbox(tmp_path, "_3")
    judge(m3, gate_root(tmp_path / "m3"), bare, bare, mbox=mbox3)
    assert log3.read_text(encoding="utf-8").count("[크리티컬]") == 4, "M3 중복 막기 삭제 = 두 번째 걸림도 보냄"
    m5 = mutant(tmp_path / "5", GATE, '"successor", `${seat}.json`', '"successor", `${seat}.none`')
    assert judge(m5, gate_root(tmp_path / "m5", reached=True), bare)[0]["action"] == "block", "M5"

def test_3c_one_opener_after_wait(tmp_path):
    for tag, desk, ago, want in (("d", "byz-p-desk#1", 301, ["byz-p-desk#1"]), ("a", "", 301, ["byz-x-arch#2"]), ("s", SEAT, 301, ["byz-x-arch#2"]), ("w", "byz-p-desk#1", 10, [])):
        mbox, log = capture_mbox(tmp_path, tag)
        root = gate_root(tmp_path / tag, desk=desk, mtime_ago=ago)
        judge(GATE, root, *[f"bash {root}/.fable-team/comm/mbox.sh recv {SEAT}"] * 2, mbox=mbox)
        opened = [ln.split(" ")[1] for ln in log.read_text(encoding="utf-8").splitlines() if "[개설]" in ln]
        assert opened == want and SEAT not in opened, (tag, opened)  # 한 곳만 · 걸린 좌석 자신 0 · 대기 전 0

def hook(tmp, cmd, k=K):  # claude 훅 같은 규칙 — 가짜 tmux 가 좌석 이름을 준다
    (fake := tmp / "fake").mkdir(exist_ok=True)
    (fake / "tmux").write_text(f'#!/bin/bash\necho "{SEAT}"\n', encoding="utf-8")
    (fake / "tmux").chmod(0o755)
    (tmp / "t.jsonl").write_text(json.dumps({"type": "assistant", "message": {"model": CLAUDE, "usage": {"input_tokens": k}}}), encoding="utf-8")
    p = subprocess.run(["/bin/bash", str(HOOK), "hard", "--recv-gate-at", "250000", "--block-at", "320000"], input=json.dumps({"transcript_path": str(tmp / "t.jsonl"), "cwd": str(tmp / "repo"), "tool_name": "Bash", "tool_input": {"command": cmd}}),
                       capture_output=True, text=True, timeout=30, env={"PATH": f"{fake}:{os.environ['PATH']}", "HOME": str(tmp / "home"), "TMUX_PANE": "%1"})
    return p.returncode, p.stderr

def test_claude_hook_same_rule(tmp_path):
    shutil.rmtree(build(tmp_path) / ".git")
    subprocess.run(["git", "init", "-q", str(tmp_path / "repo")], check=True, timeout=30)
    m = f"bash {tmp_path}/repo/.fable-team/comm/mbox.sh recv {SEAT}"
    rc, err = hook(tmp_path, m)
    assert rc == 2 and "--only distill" in err, err
    assert [hook(tmp_path, c)[0] for c in (f"{m} --only distill", f"{m} --only distill; {m}", f"{m} --only work", f"{m} # --only distill", f"{m} #--only distill")] == [0, 2, 2, 2, 2]  # R1 주석 속 --only = 막음
