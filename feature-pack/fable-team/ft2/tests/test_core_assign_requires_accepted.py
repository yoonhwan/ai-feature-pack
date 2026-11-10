"""ft2 코어 — 접수 영수 없는 배정 = 접수 거부 (r1616 · 조건 12 «코어 전체 연결» 둘째 칸).

ⓐ 지금 판(r1616 이전)은 submit 없이도 assign 이 «접수 성공» 이다 — r1607 ⓓ 루프 29회가 그 길로 실행권·완료까지
갔다. ⓑ 접수 없는 assign = «접수 거부» · written False · journal·state 바이트 불변. ⓒ 접수(work=W1) 뒤 W1 =
«접수 성공» 그대로 · 다른 work(W2) = 거부. ⓓ 거부된 work 의 deliver·claim 은 지금 판 동작 그대로(바꾸지 않음).
변이 M1 = accept 대조를 빼면 ⓑ 가 빨강(거부가 사라진다). 격리 tmp_path · sleep 0 · 시험 1파일.
"""
import importlib.util
import os
from pathlib import Path

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(FT2, "core")
TEAM, EV = "harness", ("v1", "v2")
OK, HOLD, REFUSED = "접수 성공", "완료 유보", "접수 거부"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_rcv_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


intake, dispatch = _load("intake"), _load("dispatch")
Dispatch = dispatch.Dispatch


def _node(root, cls=None):
    return (cls or Dispatch)(str(root), TEAM)


def _accept(root, work):
    """접수 1줄 — 영수에 work 를 남긴다(`intake.submit(command, body, work)`)."""
    return intake.Intake(str(root), TEAM).submit("c-" + work, "본문", work)


def _bytes(node):
    """state·journal 바이트 — «쓰기 0» 을 바이트로 대조한다(ⓑ)."""
    return tuple(Path(path).read_bytes() if os.path.exists(path) else b""
                 for path in (node.rs.state_path, node.rs.journal_path))


def test_b_assign_without_accept_is_refused(tmp_path):
    """ⓑ 접수 영수 없는 assign = 접수 거부 · written False · 바이트 불변."""
    node = _node(tmp_path)
    before = _bytes(node)
    grant = node.assign("W1", "h1", evidence=EV)
    assert (grant.result, grant.written, grant.stage) == (REFUSED, False, "reject")
    assert grant.reason == "영수-없음"
    assert _bytes(node) == before                        # journal·state 둘 다 그대로


def test_c_accepted_work_ok_other_refused(tmp_path):
    """ⓒ 접수한 W1 은 지금처럼 «접수 성공» · 접수 없는 W2 는 거부."""
    assert _accept(tmp_path, "W1").written
    node = _node(tmp_path)
    assert node.assign("W1", "h1", evidence=EV).result == OK
    assert node.assign("W2", "h2", evidence=EV).result == REFUSED


def test_d_refused_work_deliver_claim_unchanged(tmp_path):
    """ⓓ 접수 거부된 work 의 deliver·claim = 지금 판 그대로(이 카드는 배정 입구만 본다)."""
    node = _node(tmp_path)
    assert node.assign("W3", "h1", evidence=EV).result == REFUSED
    deliver = node.deliver("W3")
    assert (deliver.result, deliver.written, deliver.stage) == (HOLD, False, "no-intent")
    claim = node.ex.claim("W3", "h1")
    assert (claim.result, claim.written, claim.gen) == (OK, True, 1)
    assert _bytes(node) != tuple(b"" for _ in range(2))                     # claim 은 쓴다(관측 1줄)


class _NoAcceptCheck(Dispatch):
    """변이 M1 — accept 대조만 뺀다(다른 입구·계약 낱말 그대로)."""

    def _accepted(self, records, work):
        return True


def test_m1_accept_check_removed_is_red(tmp_path):
    """M1 accept 대조를 빼면 ⓑ 가 빨강 — 거부가 사라지고 배정이 성립한다."""
    mutant = _node(tmp_path / "m", _NoAcceptCheck)
    grant = mutant.assign("W1", "h1", evidence=EV)
    assert (grant.result, grant.written) == (OK, True)
