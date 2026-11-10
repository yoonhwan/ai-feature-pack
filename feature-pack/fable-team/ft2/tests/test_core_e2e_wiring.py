"""ft2 코어 전체 연결 끝-끝 시험 (r1607 · 조건 12 «코어 전체 연결» 첫 칸).

부품 7장(intake·dispatch·execution·lifecycle·journal·projection·record)을 `core/cli.py` 동사만으로 잇는다 — 접수 1건이
배정·전달·claim·착수·효과·결과·완료를 지나 투영에 «닫힘» 으로 서고, crash 뒤 recover 로 같은 결과에 닿는다. 상태를
바꾸는 호출은 전부 CLI 동사 하나(라이브러리 직접 호출 0)이고, 투영만 읽기 전용 관측 1곳(투영 동사는 r1610)이다.

ⓐ 8줄 rc·낱말 = 계약값 + 닫힘 1행 · ⓑ holder 경합 하나만 성공 · ⓕ 완료 뒤 재배정·착수 · ⓒ kill 뒤 recover 재개 · ⓓ 회전·reclaim
뒤에도 닫힌 행 그대로 · M1(complete 제거)·M2(recover 제거)·M3(closed={}) 변이 3/3 빨강 · sleep 0 · 격리 tmp·팀 1개.
"""
import json
import os
import subprocess
import sys

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI = os.path.join(FT2, "core", "cli.py")
TEAM, NOW = "harness", "2026-11-11T01:00:00"
OK, HOLD, RECOVERED = "접수 성공", "완료 유보", "회수 결과"
STEPS = "submit assign deliver claim start effect result complete".split()
ENV = dict(os.environ, FT_NOW=NOW)


def _cli(root, *args):
    """CLI 1회 = 동사 1개. stdout 은 JSON 1줄, rc 는 계약값(낱말 → cli.RC) 그대로."""
    done = subprocess.run([sys.executable, CLI] + list(args) + ["--root", str(root), "--team", TEAM],
                          cwd=FT2, env=ENV, capture_output=True, text=True, timeout=25)
    assert "Traceback" not in done.stderr, done.stderr
    assert done.stdout.count("\n") == 1, done.stdout
    return json.loads(done.stdout), done.returncode


def _kill(root, *args):
    """작업자 자식 = `python3 core/cli.py` 1회, 결과 확정 «전» SIGKILL. 자식이 rc 를 낸 «뒤» 죽이므로
    죽는 프로세스는 살아 있고(이미 끝난 프로세스 kill 0), 종료는 signal 이다."""
    code = '"$@" >/dev/null 2>&1; echo "rc=$?"; read _wait'
    proc = subprocess.Popen(["/bin/sh", "-c", code, "sh", sys.executable, CLI] + list(args)
                            + ["--root", str(root), "--team", TEAM],
                            cwd=FT2, env=ENV, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    try:
        assert proc.stdout.readline().strip() == "rc=0"
    finally:
        proc.kill()
        proc.wait(timeout=25)
    assert proc.returncode < 0, proc.returncode              # 실제 kill = signal 종료


def _journal(root):
    """runtime 의 journal 줄 전부(활성 + 닫힌 segment) — «기록 1번» 을 센다."""
    folder, out = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", TEAM, "runtime"), []
    for name in sorted(n for n in os.listdir(folder) if n.startswith("journal") and n.endswith(".jsonl")):
        out += [json.loads(line) for line in open(os.path.join(folder, name), encoding="utf-8") if line.strip()]
    return out


def _project(root):
    """투영 1개 = 읽기 전용 관측. 코어가 노출한 입구(`projection.project`) 하나만 subprocess 로 부른다."""
    code = ("import json,sys; sys.path.insert(0, %r); import projection; print("
            "json.dumps(projection.project(%r, %r)['works'], ensure_ascii=False))" % (os.path.dirname(CLI), str(root), TEAM))
    done = subprocess.run([sys.executable, "-c", code], cwd=FT2, capture_output=True, text=True, timeout=25)
    assert "Traceback" not in done.stderr, done.stderr
    return json.loads(done.stdout)


_word = lambda pair: (pair[0].get("result"), pair[1])    # CLI 반환 (JSON, rc) → (낱말, rc)  # noqa: E731

def _life(root, work, submit=True, holder="h1"):
    """ⓐ 사슬 1회 — (step, 낱말, rc) 목록. 세대는 claim 이 돌려준 값을 쓴다(assign 뒤 claim 은 +1)."""
    got = [("submit",) + _word(_cli(root, "submit", "--command", "c-" + work, "--body", "본문-" + work,
                                 "--work", work))] \
        if submit else []                      # 접수 상한 8 — 회전 반복에서는 첫 1건만 접수한다
    got += [("assign",) + _word(_cli(root, "assign", "--work", work, "--holder", holder,
                                     "--evidence", "v1,v2")),
            ("deliver",) + _word(_cli(root, "deliver", "--work", work))]
    claim, rc = _cli(root, "claim", "--work", work, "--holder", holder)
    gen, got = str(claim["gen"]), got + [("claim",) + _word((claim, rc))]
    for step, extra in (("start", ()), ("effect", ("--effect", "e-" + work)), ("result", ())):
        got += [(step,) + _word(_cli(root, step, "--work", work, "--holder", holder, "--gen", gen, *extra))]
    return got + [("complete",) + _word(_cli(root, "complete", "--work", work))]


def test_a_submit_to_closed_projection(tmp_path):
    """ⓐ 8줄이 계약값(접수 성공 ×8 · rc 0)으로 지나가고, 투영에 그 일이 «닫힘» 1행으로 선다."""
    root = tmp_path / "happy"
    assert _life(root, "W1") == [(step, OK, 0) for step in STEPS]               # ⓐ 8줄 = 계약값
    row = _project(root)["W1"]
    assert (row["done"], row["owner"], row["uncertain"]) == (True, None, False)   # 닫힘 = 완료 + 실행권 반환
    assert row["deliveries"] == ["a1"] and row["gen"] == 2
    # ⓕ 완료 뒤 다음 배정 — 투영 owner 칸이 빈(가용) 같은 holder 가 두 번째 일을 배정→claim→착수한다
    _cli(root, "submit", "--command", "c-W2", "--body", "본문-W2", "--work", "W2")
    assert _cli(root, "assign", "--work", "W2", "--holder", "h1", "--evidence", "v1,v2")[0]["result"] == OK
    gen2 = str(_cli(root, "claim", "--work", "W2", "--holder", "h1")[0]["gen"])
    assert _cli(root, "start", "--work", "W2", "--holder", "h1", "--gen", gen2)[0]["result"] == OK
    assert _cli(root, "reclaim")[0]["result"] == RECOVERED


def test_b_two_holders_one_execution_right(tmp_path):
    """ⓑ h1 이 착수한 일에 h2 가 claim — 하나만 성공하고, 진 쪽 effect 는 거절 낱말에 쓰기 0."""
    root = tmp_path / "race"
    _cli(root, "submit", "--command", "c-W1", "--body", "본문-W1", "--work", "W1")
    _cli(root, "assign", "--work", "W1", "--holder", "h1", "--evidence", "v1,v2")
    _cli(root, "deliver", "--work", "W1")
    gen = _cli(root, "claim", "--work", "W1", "--holder", "h1")[0]["gen"]
    assert _cli(root, "start", "--work", "W1", "--holder", "h1", "--gen", str(gen))[0]["result"] == OK
    assert _cli(root, "effect", "--work", "W1", "--holder", "h1", "--gen", str(gen),
                "--effect", "e1")[0]["result"] == OK
    lost, rc = _cli(root, "claim", "--work", "W1", "--holder", "h2")            # 하나만 성공
    assert (lost["result"], rc, lost["stage"], lost["written"]) == (HOLD, 1, "uncertain", True)
    late, rc = _cli(root, "effect", "--work", "W1", "--holder", "h2", "--gen", str(lost["gen"]),
                    "--effect", "e2")                                          # 진 쪽 = 거절 낱말
    assert (late["result"], rc, late["written"]) == (HOLD, 1, False)
    effects = [rec for rec in _journal(root) if rec["kind"] == "effect"]
    assert [rec["holder"] for rec in effects] == ["h1"] and len(effects) == 1  # 이중 실행 0
    row = _project(root)["W1"]
    assert (row["owner"]["holder"], row["uncertain"], row["done"]) == ("h1", True, False)


def test_c_crash_resume_keeps_single_effect(tmp_path):
    """ⓒ 배정 뒤 전달 전 kill → recover 가 같은 attempt 전달(무유실) · 효과 뒤 result 전 kill → 완료로 재개.
    kill = cli 자식이 자기 rc 를 낸 «뒤» sh 래퍼를 죽이는 «동사 사이 중단» 모형이다 — 쓰기 도중 crash 는
    계약 replay(contracts/core case 06·07) 몫이라 여기서 흉내내지 않는다."""
    root = tmp_path / "crash"
    _cli(root, "submit", "--command", "c-W1", "--body", "본문-W1", "--work", "W1")
    _kill(root, "assign", "--work", "W1", "--holder", "h1", "--evidence", "v1,v2")
    recovered, rc = _cli(root, "recover")                     # M2 = 이 줄을 빼면 전달 기록이 사라진다
    assert (recovered["result"], rc, recovered["delivered"]) == (OK, 0, ["a1"])
    gen = str(_cli(root, "claim", "--work", "W1", "--holder", "h1")[0]["gen"])
    _cli(root, "start", "--work", "W1", "--holder", "h1", "--gen", gen)
    _kill(root, "effect", "--work", "W1", "--holder", "h1", "--gen", gen, "--effect", "e1")
    assert _cli(root, "recover")[0]["delivered"] == []        # 재전달 0 (이미 전달된 attempt)
    assert _cli(root, "result", "--work", "W1", "--holder", "h1", "--gen", gen)[0]["result"] == OK
    assert _cli(root, "complete", "--work", "W1")[0]["result"] == OK
    row = _project(root)["W1"]
    assert (row["done"], row["owner"], row["deliveries"]) == (True, None, ["a1"])
    assert len([rec for rec in _journal(root) if rec["kind"] == "effect"]) == 1   # 중복 효과 0

def test_d_segment_rotation_keeps_projection(tmp_path):
    """ⓓ segment 회전이 일어나도 먼저 닫힌 work 의 투영 행이 그대로 · reclaim 뒤에도 그대로."""
    root = tmp_path / "rotate"
    assert _life(root, "W000") == [(step, OK, 0) for step in STEPS]   # 첫 사슬 8동사 = 계약값
    row = _project(root)["W000"]
    assert (row["done"], row["owner"], row["uncertain"]) == (True, None, False)   # 회전 전 닫힘
    closed = {"W000": row}                        # M3 = 이 칸을 {} 로 비우면 빨강
    for index in range(1, 30):                    # 실측 20 work 부근에서 회전한다
        assert all(step[1:] == (OK, 0) for step in _life(root, "work-%03d-" % index + "x" * 70, submit=False))
    runtime = os.path.join(os.path.abspath(str(root)), ".fable-team", "teams", TEAM, "runtime")
    segments = [n for n in os.listdir(runtime) if n.startswith("journal.") and n != "journal.jsonl"]
    assert segments, "회전 0 = 시험 입력이 segment cap 에 못 닿았다"          # 회전 ≥ 1
    after = _project(root)
    assert closed and {name: after[name] for name in closed} == closed      # 회전이 결과를 안 바꾼다
    assert _cli(root, "reclaim")[0]["result"] == RECOVERED
    assert closed and {name: _project(root)[name] for name in closed} == closed   # 회수 뒤에도 같다
