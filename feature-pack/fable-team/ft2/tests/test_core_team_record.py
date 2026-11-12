"""ft2 팀 기록 1파일 시험 (카드 r1723-ft20-team-record-file · 계획 PLAN-ft20-team-record-file-20261112).

| 사례 | given 1줄 | 기대 |
|---|---|---|
| T1 왕복(카드 ①) | 칸 전부 채워 write(expect=0) | 접수 성공 · read 값·칸 순서 같음 · 기록 판 1 |
| T2 빈 칸(카드 ②) | 한 칸 빈 값 | 접수 거부 · 파일 bytes 그대로 |
| T3 다른 팀 | seat=byz-planner-master-pi#1 로 harness 기록 write | 접수 거부 · 쓰기 0 |
| T4 낡은 판 | 판 2 인데 expect=1 | 완료 유보 RETRY · 쓰기 0 |
| T5 가리키기(카드 ④) | ASSIGN 경로 없음 · 본문 줄 / «없음» | 거부 / 통과 |
| T6 읽기 무변화 | writer.lock 점유 중 read | 성공 · mtime·bytes 불변 |
| T7 crash(카드 ③) | on_step 이 rename 직전 예외 | 옛 기록 bytes 그대로 · read 결과 불변 |
| T8 두 벌 0 | 가리킨 ASSIGN.md 에 표식 줄 | 기록에 표식 0 · 4KB 이하 |
| T9 잠금 점유 | writer.lock 점유 중 write | BUSY · 쓰기 0 |
| T10 CLI(카드 ⑤) | record-write·record-read 성공·거부·인자 오류 | rc 0·1·64 · JSON 1줄 |

시험 입력 = 격리 tmp 루트 · FT_NOW 고정 시계 · sleep 0 · 파일 1개 70초 안 · 실 .fable-team 0.
변이(하위 클래스 사본 · 하나씩): M1 팀 접두 검사 삭제 → T3 · M2 expect 대조 삭제 → T4 ·
M3 rename 대신 직접 덮어쓰기 → T7 · M4 빈 칸 검사 삭제 → T2. 재진입 표지 = 없음(자기 파일 재호출 0).
"""
import fcntl
import importlib.util
import json
import os
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.join(os.path.dirname(HERE), "core")
CLI = os.path.join(CORE, "cli.py")
TEAM, SEAT, NOW = "harness", "byz-harness-master-pi#209", "2026-11-12T10:00:00"
OK, REFUSED, HOLD, BUSY, CORRUPT = "접수 성공", "접수 거부", "완료 유보", "BUSY", "복구 필요"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_test_tr_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tr = _load("team_record")


def _fields(**over):
    out = {name: "0" for name in tr.FIELDS}
    out.update({"골좌표": "4 — 하네스 운영 정리", "마지막 결정": "r1715 착지", "ASSIGN": "없음",
                "STATE": "없음", "HANDOFF": "없음(인계서 0)", "LESSONS": "없음"})
    out.update(over)
    return out


def _node(root, cls=None, **kw):
    return (cls or tr.TeamRecord)(str(root), TEAM, clock=lambda: NOW, **kw)


def _bytes(node):
    with open(node.path, "rb") as handle:
        return handle.read()


def _hold_lock(root):
    runtime = os.path.join(str(root), ".fable-team", "teams", TEAM, "runtime")
    os.makedirs(runtime, exist_ok=True)
    handle = open(os.path.join(runtime, "writer.lock"), "a+")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    return handle


def _written(root, cls=None):
    node = _node(root, cls)
    assert node.write(SEAT, 0, _fields()).result == OK
    return node


def test_t1_roundtrip_keeps_values_and_order(tmp_path):
    node = _node(tmp_path)
    out = node.write(SEAT, 0, _fields())
    assert (out.result, out.revision, out.written) == (OK, 1, True)
    got = node.read()
    assert (got.result, got.revision) == (OK, 1)
    assert list(got.fields) == list(tr.FIELDS) and got.fields == _fields()
    assert node.path == os.path.join(str(tmp_path), ".fable-team", "teams", TEAM, "TEAM-RECORD.md")


def test_t2_empty_field_refused_and_file_unchanged(tmp_path):
    node = _written(tmp_path)
    before = _bytes(node)
    for bad in ({"열린 일": ""}, {"열린 일": "   "}):
        out = node.write(SEAT, 1, _fields(**bad))
        assert (out.result, out.written) == (REFUSED, False)
    assert node.write(SEAT, 1, {k: v for k, v in _fields().items() if k != "미커밋"}).result == REFUSED
    assert _bytes(node) == before


def test_t3_other_team_seat_refused(tmp_path):
    node = _node(tmp_path)
    out = node.write("byz-planner-master-pi#1", 0, _fields())
    assert (out.result, out.written) == (REFUSED, False)
    assert not os.path.exists(node.path)


def test_t4_stale_expect_holds_retry(tmp_path):
    node = _written(tmp_path)
    assert node.write(SEAT, 1, _fields(**{"열린 일": "r1726"})).revision == 2
    before = _bytes(node)
    out = node.write(SEAT, 1, _fields(**{"열린 일": "낡은 판"}))
    assert (out.result, out.status, out.revision, out.written) == (HOLD, "RETRY", 2, False)
    assert _bytes(node) == before


def test_t5_pointer_path_must_exist_or_none(tmp_path):
    node = _node(tmp_path)
    assign = tmp_path / "ASSIGN.md"
    for bad in (str(tmp_path / "없는-ASSIGN.md"), "## 배정표\n- r1707 → 나노"):
        out = node.write(SEAT, 0, _fields(ASSIGN=bad))
        assert (out.result, out.written) == (REFUSED, False)
    assert not os.path.exists(node.path)
    assign.write_text("# 배정표\n", encoding="utf-8")
    assert node.write(SEAT, 0, _fields(ASSIGN=str(assign))).result == OK
    assert node.write(SEAT, 1, _fields(ASSIGN="없음")).result == OK


def test_t6_read_under_lock_changes_nothing(tmp_path):
    node = _written(tmp_path)
    before, mtime = _bytes(node), os.stat(node.path).st_mtime_ns
    handle = _hold_lock(tmp_path)
    try:
        got = _node(tmp_path).read()
    finally:
        handle.close()
    assert (got.result, got.revision, got.written) == (OK, 1, False)
    assert _bytes(node) == before and os.stat(node.path).st_mtime_ns == mtime


class _Crash(RuntimeError):
    pass


def _crash_before_rename(step):
    if step == "before_rename":
        raise _Crash(step)


def test_t7_crash_before_rename_keeps_old_record(tmp_path, cls=None):
    node = _written(tmp_path, cls)
    before, first = _bytes(node), node.read()
    crash = _node(tmp_path, cls, on_step=_crash_before_rename)
    with pytest.raises(_Crash):
        crash.write(SEAT, 1, _fields(**{"열린 일": "반쯤 쓴 기록"}))
    assert _bytes(node) == before and _node(tmp_path).read() == first


def test_t8_pointer_not_copied_and_small(tmp_path):
    assign = tmp_path / "ASSIGN.md"
    assign.write_text("# 배정표\n- 표식-ASSIGN-본문-7f3a\n", encoding="utf-8")
    node = _node(tmp_path)
    assert node.write(SEAT, 0, _fields(ASSIGN=str(assign))).result == OK
    text = _bytes(node)
    assert "표식-ASSIGN-본문-7f3a".encode() not in text and len(text) <= 4096


def test_t9_write_under_lock_is_busy(tmp_path):
    node = _node(tmp_path)
    handle = _hold_lock(tmp_path)
    try:
        out = node.write(SEAT, 0, _fields())
    finally:
        handle.close()
    assert (out.result, out.written) == (BUSY, False) and not os.path.exists(node.path)


def test_read_missing_and_corrupt(tmp_path):
    got = _node(tmp_path).read()
    assert got.result == REFUSED and "판정 불가 기록 없음" in got.reason
    node = _written(tmp_path)
    with open(node.path, "a", encoding="utf-8") as handle:
        handle.write("자유 문단\n")
    assert node.read().result == CORRUPT
    assert node.write(SEAT, 1, _fields()).result == CORRUPT


def _cli(*argv):
    proc = subprocess.run([sys.executable, CLI, *argv], capture_output=True, text=True, timeout=30,
                          env=dict(os.environ, FT_NOW=NOW))
    lines = proc.stdout.splitlines()
    assert len(lines) == 1, proc.stdout + proc.stderr
    return proc.returncode, json.loads(lines[0])


def test_t10_cli_write_read_refuse_usage(tmp_path):
    root, good, bad = str(tmp_path), tmp_path / "f.json", tmp_path / "bad.json"
    good.write_text(json.dumps(_fields(), ensure_ascii=False), encoding="utf-8")
    bad.write_text(json.dumps(_fields(**{"열린 일": ""}), ensure_ascii=False), encoding="utf-8")
    base = ["--root", root, "--team", TEAM]
    rc, out = _cli("record-read", *base)
    assert rc == 1 and out["result"] == REFUSED and "판정 불가 기록 없음" in out["reason"]
    rc, out = _cli("record-write", *base, "--seat", SEAT, "--expect", "0", "--fields_file", str(good))
    assert (rc, out["result"], out["revision"]) == (0, OK, 1)
    rc, out = _cli("record-read", *base)
    assert (rc, out["result"], out["fields"]) == (0, OK, _fields())
    rc, out = _cli("record-write", *base, "--seat", SEAT, "--expect", "1", "--fields_file", str(bad))
    assert (rc, out["result"]) == (1, REFUSED)
    for argv in (("--seat", SEAT, "--expect", "1"), ("--seat", SEAT, "--expect", "x", "--fields_file", str(good)),
                 ("--seat", SEAT, "--expect", "1", "--fields_file", str(tmp_path / "없음.json"))):
        assert _cli("record-write", *base, *argv)[0] == 64


class _M1(tr.TeamRecord):
    def _seat_ok(self, seat):
        return True


class _M2(tr.TeamRecord):
    def _stale(self, expect, revision):
        return False


class _M3(tr.TeamRecord):
    def _commit(self, tmp, text):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(text[: len(text) // 2])
            handle.flush()
            self.on_step("before_rename")
            handle.write(text[len(text) // 2:])


class _M4(tr.TeamRecord):
    def _empty(self, value):
        return False


def test_mutants_break_their_case(tmp_path):
    assert _node(tmp_path / "m1", _M1).write("byz-planner-master-pi#1", 0, _fields()).result == OK  # T3
    node = _written(tmp_path / "m2", _M2)
    node.write(SEAT, 1, _fields())
    assert node.write(SEAT, 1, _fields()).result == OK                                          # T4
    with pytest.raises(AssertionError):
        test_t7_crash_before_rename_keeps_old_record(tmp_path / "m3", _M3)                        # T7
    node = _written(tmp_path / "m4", _M4)
    assert node.write(SEAT, 1, _fields(**{"열린 일": ""})).result == OK                          # T2
