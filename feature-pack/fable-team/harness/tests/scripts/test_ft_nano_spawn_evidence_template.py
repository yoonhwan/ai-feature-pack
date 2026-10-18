"""R133 — 나노 발주문(BODY)에 증거 줄 «복사용 템플릿 1줄» 고정.
  ⓐ ft-nano-spawn.sh BODY 에 템플릿 줄이 정확히 실재(+ 키트 사본 cmp 0)
  ⓑ 템플릿의 <> 를 실제 값으로 채운 줄 → ft-nano-evidence-check.sh rc 0
  ⓒ rc= 뒤에 꼬리를 붙인 줄 → 여전히 REJECT (파서 유지)
"""

import re
from pathlib import Path

import pytest
from ft_git_helpers import BIN, git, init_repo, run_script

TEMPLATE = (
    "증거 줄 템플릿(그대로 복사해 <> 만 채움): "
    "세트: <나노 HEAD 40자> · 시험: <명령 — «(N passed)» 같은 꼬리는 여기> rc=<n> · 이슈: 0"
)
SPAWN = BIN / "ft-nano-spawn.sh"
KIT_SPAWN = BIN.parents[1] / "harness" / "kit" / "fable-team" / "bin" / "ft-nano-spawn.sh"


@pytest.fixture
def nano(tmp_path):
    return init_repo(tmp_path / "nano", "nano/x")


def _filled(nano):
    """템플릿의 <> 를 실제 값으로 채운 줄 (BODY 에서 뽑은 템플릿 기준)."""
    tpl = TEMPLATE.split(": ", 1)[1]
    head = git(nano, "rev-parse", "HEAD").strip()
    line = re.sub(r"<나노 HEAD 40자>", head, tpl)
    line = re.sub(r"<명령 — [^>]*>", "pytest x -q (3 passed)", line)
    return line.replace("<n>", "0")


def _check(tmp_path, nano, line):
    card = tmp_path / "card.md"
    card.write_text(f"# 카드\n\n## 상태\n- {line}\n")
    return run_script("ft-nano-evidence-check.sh", str(card), "--repo", str(nano))


def test_body_has_exact_template_line_and_phrase():
    text = SPAWN.read_text(encoding="utf-8")
    assert TEMPLATE in text
    assert "rc= 바로 뒤는 « · 이슈:» — 괄호·설명은 rc= 앞에" in text
    assert text.index("(판정 1125)★") < text.index(TEMPLATE) < text.index("★팀 구조")


def test_filled_template_passes_evidence_check(tmp_path, nano):
    r = _check(tmp_path, nano, _filled(nano))
    assert r.returncode == 0, r.stdout


def test_tail_after_rc_still_rejects(tmp_path, nano):
    line = _filled(nano).replace("rc=0 · 이슈", "rc=0 (3 passed) · 이슈")
    assert _check(tmp_path, nano, line).returncode == 1


def test_swapped_order_mutation_rejects(tmp_path, nano):
    line = _filled(nano).replace("rc=0 · 이슈: 0", "이슈: 0 · rc=0")
    assert _check(tmp_path, nano, line).returncode == 1


def test_kit_copy_is_byte_identical():
    if not KIT_SPAWN.exists():
        pytest.skip("kit copy absent")
    assert Path(KIT_SPAWN).read_bytes() == SPAWN.read_bytes()
