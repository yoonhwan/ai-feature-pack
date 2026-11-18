"""r2019 — recv 문턱 알림([크리티컬]·[개설])의 보내는 이 = 도구 이름 ft-distill-gate → desk 경로 판정기 통과 · 발신 실패 = 걸린 좌석 stderr 1줄(같은 열쇠 1회).
T1~T4 + 변이 M1·M2 · 임시 루트 · 가짜 mbox(인자 기록) · 실제 ft_desk_route_gate.py(tmp 명부) · 실 우편함·실 좌석 0 · sleep 0."""
import json
import os
import subprocess

from test_pi_distill_gate import CLAUDE, DRIVER, GATE, NODE, SEAT
from test_recv_gate_only_distill_r1966 import K, gate_root, mutant

ROUTE = GATE.parents[3] / "legacy" / "1.x" / "harness" / "bin" / "ft_desk_route_gate.py"
DESK, MASTER, TOOL = "byz-p-desk#1", "byz-x-master#1", "ft-distill-gate"
assert NODE, "node 없음"

def fake_mbox(tmp, fail_to=""):  # 인자 기록 · fail_to 앞이면 REJECT rc3(우편함 판정기 꼴)
    log = tmp / "mbox.log"
    (sh := tmp / "mbox-fake.sh").write_text(f'#!/bin/bash\nprintf "%s\\n" "$*" >> "{log}"\n[ "$2" = "{fail_to}" ] && {{ echo "REJECT desk 에는 planner 가 보내요"; exit 3; }}\nexit 0\n', encoding="utf-8")
    return sh, log

def run(gate, root, mbox, n=1, mtime_ago=None):  # 맨 recv n 번 · stderr 도 돌려준다
    cases = [{"tool": "bash", "tokens": K, "model": CLAUDE, "seat": SEAT, "command": f"bash {root}/.fable-team/comm/mbox.sh recv {SEAT}"}] * n
    p = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], capture_output=True, text=True, timeout=60, input=json.dumps({"op": "judge", "cwd": str(root), "env": {"FT_MBOX": str(mbox)}, "cases": cases}),
                       env={"PATH": os.environ["PATH"], "FT_GATE": gate.resolve().as_uri(), "HOME": str(root.parent)})
    assert p.returncode == 0, p.stderr[-800:]
    return json.loads(p.stdout), p.stderr

def sent(log):  # [(to, from, body)]
    return [tuple(ln.split(" ", 3)[1:]) for ln in log.read_text(encoding="utf-8").splitlines()] if log.exists() else []

def route(root, tmp, to, frm, body):  # 실제 판정기 · tmp 명부
    (bf := tmp / "body.txt").write_text(body, encoding="utf-8")
    p = subprocess.run(["python3", str(ROUTE), "--to", to, "--from", frm, "--body-file", str(bf), "--seats-dir", str(root / ".fable-team"), "--comm", str(root / ".fable-team" / "comm")],
                       capture_output=True, text=True, timeout=30, env={"PATH": os.environ["PATH"], "FT_ROOTS_TSV": str(tmp / "none.tsv")})
    return p.returncode, p.stdout.strip()

def crit_route(tmp, gate):  # T1 몸통 — desk 앞 [크리티컬] 을 판정기에 통과시킨다
    root, (mbox, log) = gate_root(tmp / "r"), fake_mbox(tmp)
    run(gate, root, mbox)
    crit = [s for s in sent(log) if s[2].startswith("[크리티컬]")]
    desk = [s for s in crit if s[0] == DESK]
    assert len(desk) == 1, crit
    return crit, route(root, tmp, *desk[0])

def test_t1_t2_crit_from_tool_passes_desk_route(tmp_path):
    crit, rv = crit_route(tmp_path, GATE)
    assert sorted(s[0] for s in crit) == sorted([MASTER, DESK]) and all(s[1] == TOOL for s in crit), crit  # T1·T2 두 곳 모두 같은 from
    assert all(SEAT in s[2].split(" — ")[0] for s in crit), crit  # 본문 첫머리 = 걸린 좌석 이름 그대로
    assert rv == (0, "OK"), rv  # T1 판정기 통과

def test_m1_from_seat_rejected(tmp_path):
    m1 = mutant(tmp_path, GATE, '"send", to, "ft-distill-gate", body', '"send", to, seat, body')
    _, rv = crit_route(tmp_path, m1)
    assert rv[0] == 3 and rv[1].startswith("REJECT"), rv  # M1 from = 좌석 → 판정기 REJECT

def test_t3_open_same_from(tmp_path):
    root, (mbox, log) = gate_root(tmp_path / "r", mtime_ago=301), fake_mbox(tmp_path)
    run(GATE, root, mbox)
    opened = [s for s in sent(log) if s[2].startswith("[개설]")]
    assert opened and all(s[0] == DESK and s[1] == TOOL for s in opened), opened
    assert route(root, tmp_path, *opened[0]) == (0, "OK")

def fail_lines(tmp, gate):
    root, (mbox, _) = gate_root(tmp / "r"), fake_mbox(tmp, fail_to=DESK)
    got, err = run(gate, root, mbox, n=2)
    return got, [ln for ln in err.splitlines() if "알림 실패" in ln]

def test_t4_send_fail_one_line(tmp_path):
    got, lines = fail_lines(tmp_path, GATE)
    assert len(lines) == 1 and DESK in lines[0] and "REJECT" in lines[0] and "rc=3" in lines[0], lines  # 같은 열쇠 두 번째 = 0
    assert "알림 실패" in got[0]["reason"] and "알림 실패" not in got[1]["reason"], got

def test_m2_no_fail_line(tmp_path):
    m2 = mutant(tmp_path, GATE, 'console.error(`ft2 distill-gate: ${m}`); ', "")
    assert fail_lines(tmp_path, m2)[1] == [], "M2 실패 알림 삭제 = T4 FAIL"
