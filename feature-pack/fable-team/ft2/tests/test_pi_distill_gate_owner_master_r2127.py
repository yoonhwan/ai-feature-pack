"""r2127 — recv 문턱 [크리티컬] 받는 이 = {harness _master · desk · 걸린 좌석의 주인 팀장} 집합 · 주인 판정 불가(행 없음 · _master 빈 값 · JSON 깨짐 · 자기 자신) = 지금 두 곳만 + «주인 팀장 알림 판정 불가 — <이유>» 1줄(좌석 1회).
반례 ①~⑥·⑥-b + 변이 M1~M4(사본 · 원본 대조) · 임시 루트 · input.notify 가짜(받는 이·본문 기록) · 실 우편함·실 tmux·실 명부 0 · sleep 0."""
import json
import os
import subprocess

from test_pi_distill_gate import CLAUDE, GATE, NODE
from test_recv_gate_only_distill_r1966 import K, gate_root, mutant

HARNESS, DESK, LECTURE = "byz-x-master#1", "byz-p-desk#1", "byz-lecture-master-pi#9"
NANO, L121, HARCH = "byz-lecture-nano-x#0", "byz-lecture-nano-l121-distill-owner#0", "byz-harness-arch-pi#9"
GHOST, EMPTY = "byz-ghost-nano-y#0", "byz-empty-nano-z#0"
NOTE = "주인 팀장 알림 판정 불가 — "
DRIVER = """
import fs from "node:fs"; const mod = await import(process.env.FT_GATE), req = JSON.parse(fs.readFileSync(0, "utf8")), sent = [];
const out = req.cases.map((c) => mod.judge({ ...c, cwd: req.cwd, env: req.env, notify: (to, body) => { sent.push([to, body]); return true; } }));
process.stdout.write(JSON.stringify({ out, sent }));"""
assert NODE, "node 없음"

def root_with(tmp, broken=False):
    root = gate_root(tmp / "r")
    fable = root / ".fable-team"
    harness = json.loads((fable / "seats-harness.json").read_text(encoding="utf-8"))
    (fable / "seats-harness.json").write_text(json.dumps({**harness, HARCH: {"role": "arch"}}), encoding="utf-8")
    rosters = {"seats-lecture.json": {"_master": LECTURE, LECTURE: {"role": "master"}, NANO: {"role": "nano"}, L121: {"role": "nano", "source": "ft2-launch"}},
               "seats-ghost.json": {"_master": "byz-ghost-master#1"},  # M4 덫 — _master 만 · 대상 좌석 행 없음
               "seats-empty.json": {"_master": "", EMPTY: {"role": "nano"}}}
    for name, data in rosters.items():
        (fable / name).write_text(json.dumps(data), encoding="utf-8")
    if broken:
        (fable / "seats-broken.json").write_text("{", encoding="utf-8")
    return root

def run(gate, root, seat, n=1):  # 맨 recv n 번 · ({결과}, [(받는 이, 본문)])
    cases = [{"tool": "bash", "tokens": K, "model": CLAUDE, "seat": seat, "command": f"bash {root}/.fable-team/comm/mbox.sh recv {seat}"}] * n
    p = subprocess.run([NODE, "--input-type=module", "-e", DRIVER], capture_output=True, text=True, timeout=60, input=json.dumps({"cwd": str(root), "env": {}, "cases": cases}),
                       env={"PATH": os.environ["PATH"], "FT_GATE": gate.resolve().as_uri(), "HOME": str(root.parent)})
    assert p.returncode == 0, p.stderr[-800:]
    got = json.loads(p.stdout)
    return got["out"], [tuple(s) for s in got["sent"]]

def crit_to(sent):
    return sorted(to for to, body in sent if body.startswith("[크리티컬]"))

def notes(out):
    return [ln for v in out for ln in v["reason"].split(" · ") if ln.startswith(NOTE)]

def owner_case(tmp, gate, seat):  # ①·② 몸통
    out, sent = run(gate, root_with(tmp), seat)
    assert all(v["rule"] == "recv-gate" for v in out), out
    return crit_to(sent), out, sent

def test_1_lecture_seat_owner_master_one(tmp_path):
    to, out, sent = owner_case(tmp_path, GATE, NANO)
    assert to == sorted([HARNESS, DESK, LECTURE]), sent  # ① 각 1통
    assert len({body for _, body in sent}) == 1 and NANO in sent[0][1], sent  # 같은 본문
    assert notes(out) == [], out

def test_2_ft2_launch_seat_owner_master(tmp_path):
    to, _, sent = owner_case(tmp_path, GATE, L121)
    assert to.count(LECTURE) == 1 and to == sorted([HARNESS, DESK, LECTURE]), sent  # ② 2.0 행 = 명부 행이 정본

def test_3_harness_seat_two(tmp_path):
    to, out, sent = owner_case(tmp_path, GATE, HARCH)
    assert to == sorted([HARNESS, DESK]), sent  # ③ 주인 = harness master → 합 2통
    assert notes(out) == [], out

def test_4_same_seat_twice_second_zero(tmp_path):
    once, twice = (crit_to(run(GATE, root_with(tmp_path / str(n)), NANO, n=n)[1]) for n in (1, 2))
    assert once and twice == once, (once, twice)  # ④ 둘째 판 send 0

def undecided(tmp, gate, seat, broken=False):
    out, sent = run(gate, root_with(tmp, broken), seat, n=2)
    return crit_to(sent), notes(out)

def test_5_master_itself(tmp_path):
    to, ns = undecided(tmp_path, GATE, LECTURE)
    assert to == sorted([HARNESS, DESK]), to  # ⑤ 자기에게 0통
    assert ns == [NOTE + "걸린 좌석 자신"], ns  # 좌석 1회

def test_6_no_row_and_empty_master(tmp_path):
    to, ns = undecided(tmp_path / "a", GATE, GHOST)
    assert to == sorted([HARNESS, DESK]) and "byz-ghost-master#1" not in to, to  # ⑥ 이름 «ghost» 짐작 send 0
    assert ns == [NOTE + "명부 행 없음"], ns
    to, ns = undecided(tmp_path / "b", GATE, EMPTY)
    assert to == sorted([HARNESS, DESK]) and ns == [NOTE + "_master 빈 값"], (to, ns)

def test_6b_broken_roster(tmp_path):
    to, ns = undecided(tmp_path, GATE, GHOST, broken=True)
    assert to == sorted([HARNESS, DESK]), to  # ⑥-b 기존 2통 그대로(진단 열쇠 ≠ crit 열쇠)
    assert ns == [NOTE + "명부 JSON 판독 실패"], ns

# 변이 — 사본에서만 · 같은 사례를 원본으로 1회 더 돌려 반대 결과를 대조한다
OWNER_SET = "[...new Set([hm, desk, owner])]"
GUARD = 'if (!to || notified.has(`${seat}|${key}|${to}`)) return "";'
SELF = 'm === seat ? ["", "걸린 좌석 자신"] : '
NO_ROW = 'return ["", broken ? "명부 JSON 판독 실패" : "명부 행 없음"];'
GUESS = ('return [String((files.map((f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); } catch { return {}; } })'
         '.find((_, i) => base.includes(files[i].replace(/^seats-|\\.json$/g, ""))) ?? {})._master ?? ""), ""];')

def test_m1_owner_send_removed(tmp_path):
    m1 = mutant(tmp_path, GATE, OWNER_SET, "[hm, desk]")
    for seat in (NANO, L121):
        assert LECTURE not in owner_case(tmp_path / f"m{seat}", m1, seat)[0]  # M1 → ①② FAIL
        assert LECTURE in owner_case(tmp_path / f"o{seat}", GATE, seat)[0]  # 원본 = 통과

def test_m2_list_and_guard_removed(tmp_path):
    m2 = mutant(tmp_path, mutant(tmp_path, GATE, OWNER_SET, "[hm, desk, owner]"), GUARD, 'if (!to) return "";')
    assert owner_case(tmp_path / "m", m2, HARCH)[0].count(HARNESS) == 2  # M2 → ③ FAIL(중복 1통 더)
    assert owner_case(tmp_path / "o", GATE, HARCH)[0].count(HARNESS) == 1

def test_m3_self_filter_removed(tmp_path):
    m3 = mutant(tmp_path, GATE, SELF, "")
    assert LECTURE in undecided(tmp_path / "m", m3, LECTURE)[0]  # M3 → ⑤ FAIL(자기에게 1통)
    assert LECTURE not in undecided(tmp_path / "o", GATE, LECTURE)[0]

def test_m4_name_guess(tmp_path):
    m4 = mutant(tmp_path, GATE, NO_ROW, GUESS)
    assert "byz-ghost-master#1" in undecided(tmp_path / "m", m4, GHOST)[0]  # M4 → ⑥ FAIL(짐작 오발신 1통)
    assert "byz-ghost-master#1" not in undecided(tmp_path / "o", GATE, GHOST)[0]
