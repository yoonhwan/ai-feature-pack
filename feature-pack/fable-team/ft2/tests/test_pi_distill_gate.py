"""ft2 pi distill-gate 시험 — 사례 ⓐ~ⓙ + 변이 M1~M6 (r1553 카드 · arch#274 보정 1). extension 은 TypeScript 라 node 로 불러 «판정»만 받는다.
ⓘ = 실제 claude 훅(context-distill-gate.sh)을 가짜 transcript 로 돌려 같은 입력의 allow/deny 대조 · mbox handover·ready·close-check 3개는 «의도된 차이»(훅 deny · 게이트 allow) · 격리 픽스처 = tmp_path 뿐."""
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
BIN = "." + "fable-team" + "/bin"  # 1.x 경로 문자열이라 조각으로 조립한다(legacy_guard 자기검사)
CLAUDE, SEAT = "claude-sonnet-5-5", "byz-x-nano#0"
DRIVER = """
import fs from "node:fs"; const mod = await import(process.env.FT_GATE), req = JSON.parse(fs.readFileSync(0, "utf8"));
const out = req.op === "thresholds" ? mod.thresholds(req.env, req.cwd) : req.cases.map((c) => { try { return mod.judge({ ...c, cwd: req.cwd, env: req.env }); } catch (e) { return { action: "throw", rule: "error", reason: String(e) }; } }); process.stdout.write(JSON.stringify(out));"""

def run_gate(gate, root, cases, env=None, op="judge", home=None):
    proc = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], capture_output=True, text=True, timeout=60, input=json.dumps({"op": op, "cwd": str(root), "env": env or {}, "cases": cases}),
                          env={"PATH": os.environ["PATH"], "FT_GATE": gate.resolve().as_uri(), "HOME": str(home or root.parent)})
    if proc.returncode != 0:
        pytest.fail(proc.stderr[-800:])
    return json.loads(proc.stdout)

def build(tmp):
    root = tmp / "repo"
    for d in (".git", BIN, ".fable-team/comm", ".fable-team/state", ".fable-team/state/pi-distill-pending", "design/harness/inbox/arch"):
        (root / d).mkdir(parents=True, exist_ok=True)
    for name in ("mbox.sh", "ft-mbox.sh", "ft-successor-open.sh"):
        (root / (".fable-team/comm" if name == "ft-mbox.sh" else BIN) / name).write_text("#!/bin/bash\n", encoding="utf-8")
    (root / ".fable-team" / "thresholds.env").write_text("FT_DISTILL_WARN=300000\nFT_DISTILL_BLOCK=320000\nFT_DISTILL_RECV=250000\n", encoding="utf-8")
    for name, data in (("seats-aa.json", {"_master": "byz-aa-master#1", "byz-aa-master#1": {"role": "master"}, "byz-aa-nano#0": {"role": "nano"}}),
                       ("seats-harness.json", {"_master": "byz-x-master#1", "byz-x-master#1": {"role": "master"}, "byz-x-master#0": {"role": "master", "_replaced_by": "byz-x-master#1"}, SEAT: {"role": "nano"}})):
        (root / ".fable-team" / name).write_text(json.dumps(data), encoding="utf-8")
    (root / "design" / "harness" / "HANDOFF-a.md").write_text("x\n", encoding="utf-8")
    return root

def capture_mbox(tmp, tag=""):
    (tmp / f"mbox-capture{tag}.sh").write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{tmp}/mbox{tag}.log"\n', encoding="utf-8")
    return tmp / f"mbox-capture{tag}.sh", tmp / f"mbox{tag}.log"

def cases(*items):
    return [{"tool": t, "tokens": k, "model": CLAUDE, "seat": SEAT, **rest} for t, k, rest in items]

def bash(*cmds, k=330000):
    return cases(*[("bash", k, {"command": c}) for c in cmds])

def test_a_thresholds_priority_and_no_numbers(tmp_path):
    root, home = build(tmp_path), tmp_path / "home"
    (home / ".claude" / "fable-team").mkdir(parents=True)
    (home / ".claude" / "fable-team" / "thresholds.env").write_text("FT_DISTILL_WARN=1111\nFT_DISTILL_BLOCK=2222\nFT_DISTILL_RECV=3333\n", encoding="utf-8")
    assert run_gate(GATE, root, [], op="thresholds", home=home) == {"warn": 300000, "block": 320000, "recv": 250000}
    (root / ".fable-team" / "thresholds.env").write_text("FT_DISTILL_BLOCK=320000\n", encoding="utf-8")
    assert run_gate(GATE, root, [], env={"FT_DISTILL_RECV": "4444"}, op="thresholds", home=home) == {"warn": 1111, "block": 320000, "recv": 4444}, "env > 루트 파일 > 사용자 파일"
    assert not re.findall(r"\b\d{5,}\b", GATE.read_text(encoding="utf-8")), "extension 안에 문턱 숫자를 두지 않는다"

def test_b_warn_line_blocks_nothing(tmp_path):
    got = run_gate(GATE, build(tmp_path), bash("rm -rf x", "echo hi", k=305000))
    assert [v["action"] for v in got] == ["warn", "warn"] and "경고선" in got[0]["reason"], got

def test_c_block_allowlist(tmp_path):
    root = build(tmp_path)
    got = run_gate(GATE, root, cases(("read", 330000, {"path": "/etc/passwd"}), ("write", 330000, {"path": str(root / "design/harness/HANDOFF-a.md")}), ("bash", 330000, {"command": "git status"}))
                   + cases(("bash", 330000, {"command": "git commit --only -F /tmp/m -- a.txt"}), ("write", 330000, {"path": "/tmp/out.md"}), ("grep", 330000, {})) + bash("rm -rf build", "echo hi"))
    assert [v["action"] for v in got] == ["allow"] * 4 + ["block"] * 4, got

def test_d_recv_gate(tmp_path):
    root = build(tmp_path)
    base = f"bash {root}/{BIN}/mbox.sh"
    got = run_gate(GATE, root, bash(*[base + s for s in (" recv me", " peek me", ' send a b "hi"', " relay a b /tmp/f", " handover a b", " ready a b", " close-check a")], k=260000)
                   + bash(f'bash "{root}/{BIN}/mbox.sh" recv me', k=260000))  # 따옴표 친 정상 경로도 새 recv 차단(DA R4)
    assert [v["action"] for v in got] == ["block"] + ["allow"] * 6 + ["block"] and {v["rule"] for v in got[:1] + got[7:]} == {"recv-gate"}, got

def test_e_undecidable_blocks_and_notifies_once(tmp_path):
    root = build(tmp_path)
    mbox, log = capture_mbox(tmp_path)
    same = cases(("bash", None, {"command": "ls"}), ("read", 0, {}), ("bash", None, {"command": "ls"}))
    assert [v["action"] for v in run_gate(GATE, root, same, env={"FT_MBOX": str(mbox)})] == ["block"] * 3
    assert log.read_text(encoding="utf-8").strip().splitlines() == [f"send byz-x-master#1 {SEAT} [긴급] 증류 판정 불가 {SEAT} ctx usage 없음"], "같은 좌석·같은 이유 1통"
    other = run_gate(GATE, root, [{"tool": "read", "tokens": 300000, "model": CLAUDE, "seat": ""}], env={"FT_MBOX": str(mbox)})
    assert other[0]["action"] == "block" and "좌석 이름 못 읽음" in other[0]["reason"], other  # 좌석 불명 = 팀장 불명 = send 0
    (root / ".fable-team" / "thresholds.env").write_text("", encoding="utf-8")
    assert run_gate(GATE, root, [], op="thresholds", home=tmp_path / "nohome") == {"warn": 250000, "block": 300000, "recv": 250000}, "r1860: 파일 없음 = ft2 샘플 값"
    bare = tmp_path / "bare" / "distill-gate.ts"  # 옆 샘플·설치본 없음 = 판정 불가
    bare.parent.mkdir()
    shutil.copy(GATE, bare)
    assert (nofile := run_gate(bare, root, cases(("read", 330000, {})), env={"FT_MBOX": str(mbox)}, home=tmp_path / "nohome"))[0]["action"] == "block" and "문턱 못 읽음" in nofile[0]["reason"], nofile
    assert len(log.read_text(encoding="utf-8").strip().splitlines()) == 2, "이유가 다르면 다른 1통(좌석 불명은 팀장 불명 = send 0)"

def test_e2_master_is_the_roster_that_holds_the_seat(tmp_path):
    root, mbox, log = build(tmp_path), *capture_mbox(tmp_path, "_m")
    assert run_gate(GATE, root, cases(("read", 0, {})), env={"FT_MBOX": str(mbox)})[0]["action"] == "block"
    assert log.read_text(encoding="utf-8").split(" ")[1] == "byz-x-master#1", "정렬상 앞선 seats-aa 의 byz-aa-master#1 이 아니다"
    other = tmp_path / "other" / ".fable-team" / "comm"
    other.mkdir(parents=True)
    (other.parent / "seats.json").write_text(json.dumps({"_master": "byz-other-master#9", SEAT: {"role": "nano"}}), encoding="utf-8")
    moved = other / "mbox.sh"
    moved.write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{tmp_path}/mbox-other.log"\n', encoding="utf-8")
    run_gate(GATE, root, cases(("read", 0, {})), env={"FT_MBOX": str(moved)})
    assert (tmp_path / "mbox-other.log").read_text(encoding="utf-8").split(" ")[1] == "byz-other-master#9", "찾는 곳 = FT_MBOX 의 .fable-team"
    assert (absent := run_gate(GATE, root, [{"tool": "read", "tokens": 0, "model": CLAUDE, "seat": "byz-zz-nano#0"}], env={"FT_MBOX": str(moved)}))[0]["action"] == "block" and "팀장 불명" in absent[0]["reason"], absent
    assert (tmp_path / "mbox-other.log").read_text(encoding="utf-8").count("byz-other-master#9") == 1, "팀장 불명이면 send 0"

def test_f_known_non_claude_pass_unknown_model_blocks(tmp_path):
    root, mbox, log = build(tmp_path), *capture_mbox(tmp_path, "_f")
    got = run_gate(GATE, root, [{"tool": "bash", "tokens": 999999, "model": m, "seat": SEAT, "command": "rm -rf x"} for m in ("gpt-6-sol", "gemini-3-pro", "deepseek-v4-pro")])
    assert [v["action"] for v in got] == ["allow"] * 3 and {v["rule"] for v in got} == {"model-out-of-scope"}, got
    unknown = run_gate(GATE, root, [{"tool": "bash", "tokens": 330000, "model": "", "seat": SEAT, "command": "echo work"}], env={"FT_MBOX": str(mbox)})
    assert unknown[0]["action"] == "block" and "모델 불명" in unknown[0]["reason"] and log.read_text(encoding="utf-8").count("모델 불명") == 1, "모델 불명 = 판정 불가 + 팀장 1줄(DA R1)"

def test_g_pending_file_written_once(tmp_path):
    root = build(tmp_path)
    got = run_gate(GATE, root, bash("git status", k=305000) + bash("rm -rf x", k=330000) + bash("rm -rf y", k=400000))
    assert [v["action"] for v in got] == ["warn", "block", "block"], got
    state = root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano"
    assert "ctx=330000" in state.read_text(encoding="utf-8"), "차단과 같이 미완 표식이 먼저 생긴다"
    assert [v["action"] for v in run_gate(GATE, root, bash("rm -rf z", k=500000))] == ["block"] and state.read_text(encoding="utf-8").endswith("ctx=330000 증류 미완\n"), "이미 있으면 덮어쓰지 않는다(DA 반례 4)"
    assert run_gate(GATE, build(tmp_path / "r6"), cases(("read", 330000, {"path": "README.md"})))[0]["action"] == "allow" and (tmp_path / "r6/repo/.fable-team/state/pi-distill-pending/byz-x-nano").exists(), "허용 통과여도 ≥차단선이면 표식"

def test_h_pending_blocks_new_work_allows_successor(tmp_path):
    root = build(tmp_path)
    (root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano").write_text("old\n", encoding="utf-8")
    base = f"bash {root}/.fable-team"
    got = run_gate(GATE, root, bash(base + "/bin/mbox.sh recv me", k=260000) + cases(("write", 330000, {"path": str(root / "design/harness/HANDOFF-b.md")}))
                   + bash(base + "/bin/ft-successor-open.sh old wt --name new", base + "/comm/mbox.sh handover old new"))
    assert [v["action"] for v in got] == ["block", "allow", "allow", "allow"], got

PARITY = [("Read", "read", "design/harness/HANDOFF-a.md"), ("Write", "write", "design/harness/HANDOFF-a.md"), ("Edit", "edit", "design/harness/VERDICT-da.md"), ("Write", "write", "design/harness/inbox/arch/01-a.md"),
          ("Write", "write", ".fable-team/state/successor/x.json"), ("Write", "write", ".fable-team/state/x.sh"), ("Write", "write", "/tmp/out.md"), ("Write", "write", "src/a.ts")]
PARITY_CMD = ["git status", "git add -A", "git commit --only -F /tmp/m -- a.txt", "git push origin nano/x", "git push --force origin x", "git log --oneline -5",
              "git reset --hard HEAD", "git checkout -b task", "git branch -D task", "rm -rf build", "echo hi", "bash {r}/{b}/mbox.sh send a b \"hi\"", "bash {r}/{b}/ft-successor-open.sh a b",
              "tmux capture-pane -p", "tmuxc save", "baton save", "pgrep -x pi", "cd {r} && git status"]  # 승계용 비git 명령(git 판정을 git 조각에만 — DA R5 직접 회귀)
DIVERGE = ["handover a b", "ready a b", "close-check byz-x-nano"]  # 의도된 차이(카드 ⓓ·ⓗ) — claude 훅은 막고(SCRIPT_ARGS 5개) pi 게이트는 통과

def hook_verdict(hook, root, home, tool, tool_input):
    usage = {"input_tokens": 1000, "cache_read_input_tokens": 320000, "cache_creation_input_tokens": 9000}
    (root / "transcript.jsonl").write_text(json.dumps({"type": "assistant", "message": {"model": CLAUDE, "usage": usage}}), encoding="utf-8")
    proc = subprocess.run(["bash", str(hook), "hard", "--warn-at", "300000", "--block-at", "320000", "--recv-gate-at", "250000"], timeout=60, capture_output=True, text=True,
                          input=json.dumps({"transcript_path": str(root / "transcript.jsonl"), "tool_name": tool, "tool_input": tool_input, "cwd": str(root)}), env={"PATH": os.environ["PATH"], "HOME": str(home)})
    assert proc.returncode in (0, 2), proc.stderr[-500:]
    return proc.returncode == 0

def test_i_allowlist_matches_claude_hook(tmp_path):
    HOOK.is_file() or pytest.skip(f"claude 훅 없음 — {HOOK}")
    root, home, mine, theirs = build(tmp_path), tmp_path / "home", [], []  # home 은 사용자 단(段) 격리용(HOME)
    for tool, pi_tool, value in PARITY:
        theirs.append(hook_verdict(HOOK, root, home, tool, {"file_path": (path := value if value.startswith("/") else str(root / value))}))
        mine.append((pi_tool, {"path": path}))
    for cmd in PARITY_CMD:
        theirs.append(hook_verdict(HOOK, root, home, "Bash", {"command": (text := cmd.format(r=root, b=BIN))}))
        mine.append(("bash", {"command": text}))
    got = run_gate(GATE, root, [{"tool": t, "tokens": 330000, "model": CLAUDE, "seat": SEAT, **rest} for t, rest in mine])
    assert 0 < sum(theirs) < len(theirs), "훅 판정이 한 쪽으로 쏠리면 대조가 무의미하다"
    assert [v["action"] != "block" for v in got] == theirs, "허용 입력이 claude 훅과 어긋난다"
    diff = [f"bash {root}/.fable-team/comm/mbox.sh {c}" for c in DIVERGE]
    assert [hook_verdict(HOOK, root, home, "Bash", {"command": c}) for c in diff] == [False] * 3 and [v["action"] for v in run_gate(GATE, root, bash(*diff))] == ["allow"] * 3, "훅은 막고 pi 게이트는 통과시킨다(의도된 차이)"

def test_j_closing_event_is_successor_seat(tmp_path):
    root = build(tmp_path)
    state = root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano"
    recv = f"bash {root}/.fable-team/comm/mbox.sh recv me"
    run_gate(GATE, root, bash("rm -rf x", k=330000))
    low = run_gate(GATE, root, bash(recv, k=120000))
    assert state.exists() and [v["action"] for v in low] == ["block"], "같은 좌석은 압축으로 120k 가 돼도 표식 유지 + recv 차단"
    assert "seat=byz-x-nano#0" in state.read_text(encoding="utf-8"), "표식 본문에 좌석 전체 이름(#N)"
    succ = run_gate(GATE, root, cases(("bash", 120000, {"seat": "byz-x-nano#1", "command": recv})))
    assert not state.exists() and [v["action"] for v in succ] == ["allow"], "후계 좌석(#N+1)의 첫 판정이 표식을 닫는다"
    state.write_text("2026-01-01T00:00:00Z 옛 형식 ctx=999 증류 미완\n", encoding="utf-8")
    old = run_gate(GATE, root, bash(recv, k=120000))
    assert state.exists() and "옛 파일" in old[0]["reason"], "본문 없는 옛 파일 = 유지 + reason 1줄"

MUTANTS = {"M1_판정불가를_통과로": ('action: "block", rule: "undecidable"', 'action: "allow", rule: "undecidable"'),
           "M2_팀장알림_빼기": ('const bad = notifyTeam(input, env, seat || "unknown", root, why);', 'const bad = "";'),
           "M3_허용목록에서_handover_빼기": ('"ring", "handover", ', '"ring", '), "M4_gpt도_판정": ("if (!/claude/i.test(model)) return", "if (!model) return"),
           "M5_상태파일_덮어쓰기": ('{ flag: "wx" }', '{ flag: "w" }'), "M7_좌석이름_대조_빼기": ('k < lines.warn && stored && stored !== seat && stored.replace(/#\\d+$/, "") === seat.replace(/#\\d+$/, "")', 'k < lines.warn'),  # 좌석 이름 대조를 빼면 같은 좌석의 표식도 닫힌다
           "M6_첫_master_행으로": ('k === seat || k.replace(/#\\d+$/, "") === base', 'true'), "M8_기본값_줄_빼기": ('env.FT_MBOX || (builtin && fs.existsSync(builtin) ? builtin : "")', 'env.FT_MBOX || ""')}  # M8 은 test_k 가 잡는다

def mutant(tmp_path, name):
    old, new = MUTANTS[name]
    source = GATE.read_text(encoding="utf-8")
    assert old in source, name
    path = tmp_path / f"{name}.ts"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return path

def test_m_mutants_break_their_cases(tmp_path):
    root, state = build(tmp_path), None
    state = root / ".fable-team" / "state" / "pi-distill-pending" / "byz-x-nano"
    for name in (n for n in MUTANTS if not n.startswith("M8")):  # M8 은 test_k 가 잡는다
        m, kind = mutant(tmp_path, name), name[1]
        if kind in "12":  # M1 판정 불가를 통과로 · M2 팀장 1줄 빼기
            mbox, log = capture_mbox(tmp_path, name[:2])
            got = run_gate(m, root, cases(("read", 0, {})), env={"FT_MBOX": str(mbox)})
            assert (got[0]["action"] != "block") if kind == "1" else (not log.exists()), name
        elif kind == "3":  # M3 handover 를 빼면 ⓘ 의 «의도된 차이» 행이 깨진다(정상 allow · 훅 deny)
            cmd = f"bash {root}/.fable-team/comm/mbox.sh handover a b"
            assert [v["action"] for v in run_gate(GATE, root, bash(cmd))] == ["allow"] and run_gate(m, root, bash(cmd))[0]["action"] == "block", name
        elif kind == "4":  # M4 gpt 모델도 판정
            assert run_gate(m, root, [{"tool": "bash", "tokens": 999999, "model": "gpt-6-sol", "seat": SEAT, "command": "rm -rf x"}])[0]["action"] == "block", name
        elif kind == "6":  # M6 팀장을 «첫 master 행» 으로 되돌리면 test_e2 가 깨진다
            mbox, log = capture_mbox(tmp_path, "_M6")
            run_gate(m, root, cases(("read", 0, {})), env={"FT_MBOX": str(mbox)})
            assert log.read_text(encoding="utf-8").startswith("send byz-aa-master#1 "), name
        elif kind == "7":  # M7 좌석 이름 대조를 빼면 같은 좌석의 표식도 닫힌다
            run_gate(m, root, bash("rm -rf x", k=330000) + bash("git status", k=120000))
            assert not state.exists(), name
        else:  # M5 상태 파일 덮어쓰기
            run_gate(m, root, bash("rm -rf x", k=330000) + bash("rm -rf y", k=400000))
            assert "ctx=400000" in state.read_text(encoding="utf-8"), name

def test_k_team_lead_mbox_defaults_to_repo_root(tmp_path):
    root = build(tmp_path)
    (root / ".fable-team" / "comm" / "mbox.sh").write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{tmp_path}/mbox-def.log"\n', encoding="utf-8")
    assert run_gate(GATE, root, cases(("read", 0, {})))[0]["action"] == "block" and (tmp_path / "mbox-def.log").read_text(encoding="utf-8").startswith("send byz-x-master#1 "), "FT_MBOX 없이도 <루트>/.fable-team/comm/mbox.sh 로 1회"
    run_gate(mutant(tmp_path, "M8_기본값_줄_빼기"), root, cases(("read", 0, {})))
    assert (tmp_path / "mbox-def.log").read_text(encoding="utf-8").count("send ") == 1, "변이: 기본값 줄을 빼면 알림 0"

def test_legacy_guard_clean():
    assert (p := subprocess.run([sys.executable, str(FT2 / "tools" / "legacy_guard.py"), str(FT2)], capture_output=True, text=True, timeout=60)).returncode == 0, p.stdout + p.stderr

# ── r1565: «ctx usage 없음» 3갈래(ⓐ~ⓚ) — 새 대화 판정은 session 입력으로만 받는다(안 주면 지금 동작) ──────────
S = {"reason": "startup", "entries": []}  # ⓙ 새 대화

def gate(root, rows, env=None, **kw): return run_gate(GATE, root, [{"tool": t, "tokens": k, "model": CLAUDE, "seat": SEAT, "session": kw.get("session", S), **r} for t, k, r in rows], env=env)

def one(root, tool, k, session=None, **rest): return gate(root, [(tool, k, rest)], session=session or S)[0]

def test_n_first_verdict_streak_and_allowlist(tmp_path):
    root, mbox, log = build(tmp_path), *capture_mbox(tmp_path, "_n")
    got = gate(root, [("bash", None, {"command": "ls"}), ("bash", None, {"command": "ls"}), ("bash", None, {"command": "rm -rf x"}), ("read", None, {"path": "/etc/passwd"}), ("bash", 1000, {"command": "ls"}), ("bash", None, {"command": "ls"})], env={"FT_MBOX": str(mbox)})
    assert [v["action"] for v in got] == ["allow", "allow", "block", "allow", "allow", "block"], got  # ⓐ 첫 판정 · ⓑ 연속 3 = 허용 목록(밖 막음·안 통과) · ⓓ 읽으면 연속 0 · ⓔ 읽은 뒤의 null = 통과 0
    assert [v["rule"] for v in got] == ["undecidable-first", "undecidable-pass", "undecidable-allowlist", "undecidable-allowlist", "below-warn", "undecidable-allowlist"], got
    assert log.read_text(encoding="utf-8").strip().splitlines() == [f"send byz-x-master#1 {SEAT} [긴급] 증류 판정 불가 {SEAT} ctx usage 없음"], "ⓒ 같은 좌석·같은 이유 세션당 1통(첫 판정 알림 0)"
    assert [v["rule"] for v in gate(root, [("bash", 0, {"command": "ls"}), ("bash", None, {"command": "ls"})])] == ["undecidable-first", "undecidable-pass"], "ⓘ tokens=0 은 «읽음» 이 아니다"
    assert [v["rule"] for v in gate(root, [("bash", None, {"command": "ls"}), ("bash", None, {"command": "ls"})], env={"FT_DISTILL_FAILOPEN_MAX": "2"})] == ["undecidable-first", "undecidable-allowlist"], "ⓑ r1554 와 같은 키(env) 로 상한을 바꿀 수 있다"
    assert one(root, "bash", 330000, command="ls")["rule"] == "block-gate" and (root / ".fable-team/state/pi-distill-pending/byz-x-nano").exists(), "회귀① 판정 가능 호출은 그대로(차단선 + 표식)"
    assert [v["rule"] for v in gate(root, [("bash", 1000, {"command": "ls"}), ("bash", None, {"command": f"bash {root}/.fable-team/comm/mbox.sh recv me"})])] == ["below-warn", "recv-gate"], "회귀② 압축 뒤 null + 표식 = recv 차단"
    assert [v["action"] for v in gate(root, [("bash", 1000, {"command": "ls"}), ("bash", None, {"command": "rm -rf build"})])] == ["allow", "block"], "회귀③ 읽은 뒤 null 은 통과 0(허용 목록 밖 막음)"

def test_o_initial_exception_only_for_new_conversation(tmp_path):
    root = build(tmp_path)
    for reason, entries in (("startup", []), ("new", [])):
        assert one(root, "read", None, {"reason": reason, "entries": entries})["rule"] == "undecidable-first", reason
    for reason, entries in (("resume", []), ("reload", []), ("fork", []), ("startup", None), (None, []), ("startup", [{"type": "message", "message": {"role": "assistant"}}]), ("new", [{"type": "compaction"}])):
        assert one(root, "read", None, {"reason": reason, "entries": entries})["action"] == "block", reason  # ⓙ 초기 예외 0 = 지금 동작
    state = root / ".fable-team/state/pi-distill-pending/byz-x-nano"
    state.write_text("2026-01-01T00:00:00Z seat=byz-x-nano#0 ctx=9 증류 미완\n", encoding="utf-8")
    assert one(root, "read", None, {"reason": "startup", "entries": []})["action"] == "block" and state.exists(), "ⓙ 표식 있으면 초기 예외 0 · ⓔ usage 없음 판정은 표식을 지우지 않는다"
    assert one(root, "read", 999999, session={"reason": "startup", "entries": []}, model="")["action"] == "block", "ⓕ 모델 불명은 새 대화여도 그대로 막는다"
    r1 = build(tmp_path / "r1")  # 표식 폴더도 없다 = DA R1 의 «fresh»
    shutil.rmtree(r1 / ".fable-team" / "state" / "pi-distill-pending")
    assert [v["action"] for v in run_gate(GATE, r1, [{"tool": t, "tokens": k, "model": CLAUDE, "seat": "", "session": S} for t, k in (("read", None), ("read", 0), ("turn", None))])] == ["block"] * 3, "DA R1 ⓕ 좌석 불명이 usage 초기 예외(ⓐⓗ)보다 먼저 — 좌석 없는 새 세션은 통과 0"

def test_p_turn_start_silent_only_before_any_usage(tmp_path):
    root, mbox, log = build(tmp_path), *capture_mbox(tmp_path, "_p")
    got = gate(root, [("turn", None, {}), ("read", None, {}), ("turn", 1000, {}), ("turn", None, {})], env={"FT_MBOX": str(mbox)})
    assert [v["action"] for v in got] == ["allow", "allow", "allow", "block"], got
    assert [v["rule"] for v in got[:2]] == ["undecidable-turn", "undecidable-first"], "ⓗ 주입 0 · ⓚ 턴 시작이 첫 판정 예외를 소모하지 않는다"
    assert log.read_text(encoding="utf-8").strip().splitlines() == [f"send byz-x-master#1 {SEAT} [긴급] 증류 판정 불가 {SEAT} ctx usage 없음"], "ⓗ 턴 시작 usage 없음 = 알림 0 · 읽은 뒤의 null 만 지금 동작(막음+1줄)"

def test_r_successor_first_turn_ignores_previous_generation_marker(tmp_path):
    root, mbox, log = build(tmp_path), *capture_mbox(tmp_path, "_r")
    state = root / ".fable-team/state/pi-distill-pending/byz-x-nano"
    state.write_text("2026-01-01T00:00:00Z seat=byz-x-nano#9 ctx=9 증류 미완\n", encoding="utf-8")  # 직전 세대(#9) 표식
    got = gate(root, [("turn", None, {}), ("read", None, {})], env={"FT_MBOX": str(mbox)})
    assert [v["rule"] for v in got] == ["undecidable-turn", "undecidable-first"], got  # ⓜ 승계 첫 턴 = 주입 0 · 알림 0 · 연속 횟수 불변
    assert not log.exists() or log.read_text(encoding="utf-8").strip() == "", "ⓛ 직전 세대 표식으로 [긴급] 0"
    assert state.exists() and one(root, "read", 1000)["rule"] == "below-warn" and not state.exists(), "ⓜ 이 좌석 첫 양수 판정 = 표식 닫힘(지금 동작)"
    self_root, self_mbox, self_log = build(tmp_path / "s"), *capture_mbox(tmp_path, "_r2")  # 자기 좌석(#0) 표식 = 지금 동작 유지
    (self_root / ".fable-team/state/pi-distill-pending/byz-x-nano").write_text("seat=byz-x-nano#0 ctx=9 증류 미완\n", encoding="utf-8")
    assert gate(self_root, [("turn", None, {})], env={"FT_MBOX": str(self_mbox)})[0]["action"] == "block" and self_log.read_text(encoding="utf-8").count("send ") == 1, "ⓛⓜ 자기 좌석 표식 = 주입 + 1통 유지"
    old = build(tmp_path / "o")  # 좌석 이름 없는 옛 표식 = 지금처럼 초기 예외 0
    (old / ".fable-team/state/pi-distill-pending/byz-x-nano").write_text("2026-01-01T00:00:00Z ctx=9 증류 미완\n", encoding="utf-8")
    assert one(old, "read", None)["action"] == "block", "ⓛ 이름 없는 옛 표식·읽기 실패 = 초기 예외 0"

MUT1565 = {"M1": ("if (!seen && n < max) return { action: \"allow\",", "if (!seen && n < max) return { action: \"block\","),
           "M2": ("!seen && n < max", "!seen"), "M3": ("ok = toolAllowed(input, root)", "ok = false"),
           "M4": ("!seen && n < max", "n === 1"),  # M4 = 읽은 뒤의 null 을 «첫 판정» 처럼 통과시킨다
           "M5": ("if (turn && !seen && fresh) return", "if (false) return"),
           "M6": ("if (turn && !seen && fresh) return", "if (turn) return"),
           "M7": ("if (k > 0) { seenUsage.set(key, true); misses.delete(key); }", "if (input.tokens !== null && input.tokens !== undefined) { seenUsage.set(key, true); misses.delete(key); }"),
           "M8": ("NEW.has(reason) && ", ""),
           "M9": ("if (turn && !seen && fresh) return", "if (turn && !seen && fresh && seenUsage.set(key, true)) return"),
           "M10": ("!seen && n < max", "n < max")}  # M10 = 읽은 뒤의 null 을 다시 «통과» 로 되돌린다
MUT1565["M11"] = ('!seat ? "좌석 이름 못 읽음(TMUX_PANE·FT_SEAT)" : !k ? "ctx usage 없음"', '!k ? "ctx usage 없음" : !seat ? "좌석 이름 못 읽음(TMUX_PANE·FT_SEAT)"')  # M11 = 좌석 불명 판정을 usage 예외 뒤로 되돌린다(DA R1)
MUT1565["M12"] = ("&& (stored === seat || !stored), fresh", "&& true, fresh")  # M12 = 표식 판정을 베이스 존재로 되돌린다(ⓛⓜ FAIL)
MUT1565["M13"] = ("(stored === seat || !stored), fresh", "false, fresh")  # M13 = 자기 좌석 이름 표식도 무시한다(ⓛⓜ FAIL)

def mut1565(tmp_path, name):
    old, new = MUT1565[name]
    source = GATE.read_text(encoding="utf-8")
    assert old in source, name
    path = tmp_path / f"{name}.ts"
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return path

def test_q_mutants_r1565(tmp_path):
    root = build(tmp_path)
    for name in MUT1565:
        m, kind = mut1565(tmp_path, name), "10" if name == "M10" else "11" if name == "M11" else "12" if name == "M12" else "13" if name == "M13" else name[1]
        if kind == "1":  # ⓐ 첫 판정 통과를 빼면 첫 호출이 막힌다
            assert run_gate(m, root, [{"tool": "bash", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}])[0]["action"] == "block", name
        elif kind == "10":  # M10 읽은 뒤의 null 이 통과하면 허용 목록 밖 도구가 열린다
            assert [v["action"] for v in run_gate(m, root, [{"tool": "bash", "tokens": 1000, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}, {"tool": "bash", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S, "command": "rm -rf build"}])][-1] == "allow", name
        elif kind == "2":  # ⓑ 연속 N 을 무한으로 두면 3회째도 통과한다
            assert [v["action"] for v in run_gate(m, root, [{"tool": "bash", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}] * 3)] == ["allow"] * 3, name
        elif kind == "3":  # ⓑ 허용 목록을 무시하면 증류 도구도 막힌다
            assert [v["action"] for v in run_gate(m, root, [{"tool": "read", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S, "path": "/etc/passwd"}] * 3)] == ["allow", "allow", "block"], name
        elif kind == "4":  # ⓔ 읽은 뒤의 null 을 첫 판정으로 취급한다
            assert [v["rule"] for v in run_gate(m, root, [{"tool": "bash", "tokens": 1000, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}, {"tool": "bash", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}])][-1] == "undecidable-first", name
        elif kind == "5":  # ⓗ 턴 시작 무주입을 빼면 첫 턴에 메시지가 주입된다
            assert run_gate(m, root, [{"tool": "turn", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S}])[0]["rule"] != "undecidable-turn", name
        elif kind == "6":  # ⓗ 를 읽은 뒤의 null 에도 적용하면 지금 동작(막음)이 사라진다
            assert [v["action"] for v in run_gate(m, root, [{"tool": "bash", "tokens": 1000, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}, {"tool": "turn", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S}])][-1] == "allow", name
        elif kind == "7":  # ⓘ tokens=0 을 «읽음» 으로 세면 첫 판정 통과가 사라진다
            assert run_gate(m, root, [{"tool": "bash", "tokens": 0, "model": CLAUDE, "seat": SEAT, "session": S, "command": "ls"}])[0]["rule"] != "undecidable-first", name
        elif kind == "8":  # ⓙ resume 세션에도 초기 예외를 주면 막히지 않는다
            assert run_gate(m, root, [{"tool": "read", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": {"reason": "resume", "entries": []}}])[0]["rule"] == "undecidable-first", name
        elif kind == "11":  # M11 좌석 불명을 usage 예외 뒤로 되돌리면 좌석 없는 새 세션이 통과한다(DA R1)
            norow = build(tmp_path / "n11")
            shutil.rmtree(norow / ".fable-team" / "state" / "pi-distill-pending")
            assert run_gate(m, norow, [{"tool": "read", "tokens": None, "model": CLAUDE, "seat": "", "session": S}])[0]["action"] != "block", name
        elif kind == "12":  # M12 베이스 존재로 되돌리면 승계 첫 턴이 거짓 경보(직전 세대 표식)
            base12 = build(tmp_path / "n12")
            (base12 / ".fable-team/state/pi-distill-pending/byz-x-nano").write_text("seat=byz-x-nano#9 ctx=9\n", encoding="utf-8")
            assert run_gate(m, base12, [{"tool": "turn", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S}])[0]["action"] == "block", name
        elif kind == "13":  # M13 자기 좌석 표식도 무시하면 증류 중 좌석이 초기 예외를 받는다
            base13 = build(tmp_path / "n13")
            (base13 / ".fable-team/state/pi-distill-pending/byz-x-nano").write_text("seat=byz-x-nano#0 ctx=9\n", encoding="utf-8")
            assert run_gate(m, base13, [{"tool": "turn", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S}])[0]["action"] == "allow", name
        else:  # M9 ⓚ 턴 시작이 «읽음» 을 소모하면 첫 tool_call 이 «첫 판정» 이 아니다
            assert [v["rule"] for v in run_gate(m, root, [{"tool": "turn", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S}, {"tool": "read", "tokens": None, "model": CLAUDE, "seat": SEAT, "session": S}])] == ["undecidable-turn", "undecidable-allowlist"], name
