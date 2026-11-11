"""ft2 코어 — 접수 영수 없는 실행권(claim) = 접수 거부 (r1632 · 실사건 r1629 checker ⓞ1).

ⓐ submit 없이 claim W9 = «접수 거부» · written False · 이유 1줄 · runtime 바이트 불변(쓰기 0).
ⓑ submit(work=W9) 뒤 claim W9 = «접수 성공» gen1(지금과 같다).
ⓒ 영수 있는 W9 에 claim → start → (구 실행자 종료 가정) claim --rotation = 새 세대 성공(r1612 그대로).
ⓓ claim 과 assign 이 «같은 함수» 로 판정한다(execution.accepted 한 곳 · dispatch._accepted 는 위임).
ⓔ 회귀 = ft2 시험 전부 통과 · claim 을 submit 없이 부르던 기존 시험 줄은 «접수 1줄» 을 앞에 두었다
   (분류표: test_core_execution 17건 · test_core_dispatch 3건 · test_core_journal_cap 4건 · r1616 카드 ⓓ 1건).
변이 M1 = claim 의 영수 대조를 빼면 ⓐ 가 빨강 · M2 = 영수 확인을 rotation 에서도 거부로 만들면 ⓒ 가 빨강.
격리 tmp root(--root 자리) · sleep 0 · 시험 1파일.
"""
import importlib.util
import os
from pathlib import Path

FT2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(FT2, "core")
TEAM = "t1"
OK, REFUSED = "접수 성공", "접수 거부"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_r1632_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


execution, dispatch = _load("execution"), _load("dispatch")


def _ex(root, cls=None):
    return (cls or execution.Execution)(str(root), TEAM)


def _accept(root, *works):
    """접수 1줄 — accept 줄에 work 를 남긴다(`intake.submit(command, body, work)`)."""
    entry = execution.intake.Intake(str(root), TEAM)
    for work in works:
        assert entry.submit("c-" + work, "본문", work).written
    return root


def _snap(node):
    """state·journal·bodies 스냅샷 — «쓰기 0» 을 바이트로 대조한다(ⓐ)."""
    return tuple(Path(path).read_bytes() if os.path.exists(path) else b""
                 for path in (node.rs.state_path, node.rs.journal_path)) + \
        tuple(sorted(os.listdir(node.rs.bodies)))


def test_a_claim_without_receipt_is_refused(tmp_path):
    """ⓐ 접수 영수 없는 claim = 접수 거부 · written False · runtime 바이트 불변."""
    node = _ex(tmp_path / "t")
    before = _snap(node)
    grant = node.claim("W9", "h1")
    assert (grant.result, grant.written, grant.gen) == (REFUSED, False, None)
    assert grant.reason == "접수 영수 없음 · intake.submit 먼저"          # 이유 1줄
    assert _snap(node) == before                                          # journal·state·bodies 그대로


def test_b_claim_with_receipt_is_unchanged(tmp_path):
    """ⓑ 접수한 W9 은 지금처럼 «접수 성공» gen1."""
    _accept(tmp_path / "t", "W9")
    grant = _ex(tmp_path / "t").claim("W9", "h1")
    assert (grant.result, grant.written, grant.gen) == (OK, True, 1)


def test_c_rotation_with_receipt_is_unchanged(tmp_path):
    """ⓒ 영수 있는 W9 = claim → start → rotation 새 세대(r1612 복구 그대로)."""
    root = tmp_path / "t"
    node = _ex(_accept(root, "W9"))
    first = node.claim("W9", "h1")
    assert node.start("W9", "h1", first.gen).result == OK
    rotated = node.claim("W9", "h2", rotation=True)          # 구 실행자 종료·권한 회수 확인
    assert (rotated.result, rotated.gen) == (OK, 2)


def test_d_one_judgment_shared_with_assign(tmp_path):
    """ⓓ 접수 영수 판정은 한 곳 — 배정과 실행권이 같은 함수를 본다(판정 문구 2벌 0)."""
    root = _accept(tmp_path / "t", "W9")
    node = dispatch.Dispatch(str(root), TEAM)
    state_records = node.ex._state_records()[1]
    assert (execution.accepted(state_records, "W9"), node._accepted(state_records, "W9")) == (True, True)
    assert execution.accepted(state_records, "W8") is False
    assert _ex(root).claim("W9", "h1").result == OK                       # 실행권 입구도 같은 판정
    source = Path(dispatch.__file__).read_text(encoding="utf-8")
    assert 'rec["kind"] == "accept"' not in source                        # 판정 본문 사본 0


class _RotationRefuse(execution.Execution):
    """변이 M2 — 영수 확인을 rotation 에서도 «거부» 로 만든다(영수 있는데 거부)."""

    def claim(self, work, holder, rotation=False, confirm_by=None):
        if rotation:
            return execution.Grant(REFUSED, work, holder=holder, reason="접수 영수 없음 · intake.submit 먼저")
        return super().claim(work, holder, rotation, confirm_by)


def test_m1_accept_check_removed_is_red(tmp_path, monkeypatch):
    """M1 claim 의 영수 대조를 빼면 ⓐ 가 빨강 — 거부가 사라지고 실행권이 선다."""
    monkeypatch.setattr(execution, "accepted", lambda records, work: True)
    grant = _ex(tmp_path / "m1").claim("W9", "h1")
    assert (grant.result, grant.written) == (OK, True)


def test_m2_rotation_refusal_is_red(tmp_path):
    """M2 rotation 을 영수 없음으로 거부하면 ⓒ 가 빨강 — 영수 있는데 새 세대가 안 선다."""
    root = tmp_path / "m2"
    node = _ex(_accept(root, "W9"), cls=_RotationRefuse)
    assert (node.claim("W9", "h1").result, node.claim("W9", "h2", rotation=True).result) == (OK, REFUSED)
