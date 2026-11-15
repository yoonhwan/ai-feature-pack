"""r1957 — 자동 교대 본문 «열린 칸 감시: » 1줄 ⑦~⑩·⑫ + 변이 M5~M7 · test_model_swap.Fx 그대로 · 새 본문은 실제 ft-successor-open.sh 감시 검사(PYWATCH 블록)에 넣는다."""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import test_model_swap as tms
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)
from test_model_swap import ARCH, BIN, N, Fx, _err, _limit

SO = BIN / "ft-successor-open.sh"
UNK = "열린 칸 감시: 미상(앞 본문·인계서에 절 없음 · 후계 = 인계서·recv 로 확인)"


def _fx(tmp: Path, watch: str | None, handoff: list[str] | None = None) -> Fx:
    fx = Fx(tmp)
    hf = tmp / "HANDOFF.md"
    if handoff is not None:
        _ = hf.write_text("# 인계서\n\n## 열린 칸 감시\n\n" + "".join(f"- {h}\n" for h in handoff) + "\n## 일하는 방식\n\n- x\n", encoding="utf-8")
    _ = (fx.ft / "comm" / "bodies" / "9001.txt").write_text("\n".join([*tms.GOAL, "본문 4행", *([watch] if watch else []), f"인계서: {hf}"]) + "\n", encoding="utf-8")
    fx.add(ARCH, _err("e1", N - 240, _limit()))
    return fx


def _check(body: str) -> int:  # 실제 개설 도구의 감시 검사 블록 그대로 실행
    src = SO.read_text(encoding="utf-8").split("<<'PYWATCH'\n", 1)[1].split("\nPYWATCH\n", 1)[0]
    return subprocess.run([sys.executable, "-c", src, body], capture_output=True, text=True, timeout=10).returncode


def _swapped(fx: Fx) -> list[str]:
    body = Path(fx.args()[13])
    out = [ln for ln in body.read_text(encoding="utf-8").splitlines() if ln.startswith("열린 칸 감시: ")]
    assert _check(str(body)) == 0, body.read_text(encoding="utf-8")
    return out


@pytest.mark.parametrize("watch", ["열린 칸 감시: ⑬ cfo D2 ④ 관측", "열린 칸 감시: 없음"])
def test_7_8_original_watch_line_kept_verbatim(tmp_path, watch):  # ⑦ ⑧
    fx = _fx(tmp_path, watch)
    assert fx.run().returncode == 0 and _swapped(fx) == [watch]
    assert not any("감시 미상" in m[2] for m in fx.mail())


@pytest.mark.parametrize("items", [["r1955 나노 → 구현 DA"], ["결제 골 칸 관측", "음성 경보 관측"]])
def test_9_12_handoff_section_all_items(tmp_path, items):  # ⑨ ⑫ 원 본문 줄 0 → 인계서 절 항목 전부
    fx = _fx(tmp_path, None, items)
    assert fx.run().returncode == 0 and _swapped(fx) == ["열린 칸 감시: " + " · ".join(items)]


def test_9b_no_section_is_unknown_not_none(tmp_path):  # ⑨b
    fx = _fx(tmp_path, None)
    assert fx.run().returncode == 0 and _swapped(fx) == [UNK]
    assert (mail := fx.mail()) and all(m[2].endswith("· 감시 미상") for m in mail)


@pytest.mark.parametrize("case", ["body", "handoff"])
def test_10_12b_too_long_is_hil_without_record(tmp_path, case):  # ⑩ ⑫b — save()·열기 0 · 다음 회차 다시 시도
    fx = _fx(tmp_path, "열린 칸 감시: " + "x" * 152, None) if case == "body" else _fx(tmp_path, None, ["a" * 80, "b" * 80])
    for now in (N, N + 60):
        r = fx.run(now)
        assert r.returncode == 0 and f"HIL {ARCH} 열린 칸 감시 줄 생성 실패" in r.stdout and "NOOP" not in r.stdout, r.stdout
    st = json.loads((fx.ft / "state" / "model-swap" / "state.json").read_text(encoding="utf-8"))
    assert "e1" not in st.get("swapped", []) and "byz-x-arch-claude" not in st.get("last", {})
    assert not fx.argv.exists() and not any(m[2].startswith("[자동 교대]") for m in fx.mail())


MUTS = {  # 이름: (파일, 원문, 바꿀 글, 잡는 시험)
    "M5": ("ft_api_outage_util.py", "watch[0] if len(watch) == 1 else None", '"열린 칸 감시: 없음"', lambda t: test_7_8_original_watch_line_kept_verbatim(t, "열린 칸 감시: ⑬ cfo D2 ④ 관측")),
    "M6": ("ft_model_swap.py", "        if len(watch) > 160", '        self.st["swapped"] = [*self.st["swapped"], cut.uuid]\n        self.st["last"][base] = self.now\n        self.save()\n        if len(watch) > 160', lambda t: test_10_12b_too_long_is_hil_without_record(t, "body")),
    "M7": ("ft_model_swap.py", f'"{UNK}"', '"열린 칸 감시: 없음"', test_9b_no_section_is_unknown_not_none),
}


@pytest.mark.parametrize("name", sorted(MUTS))
def test_mutations_are_caught(tmp_path, monkeypatch, name):
    f, old, new, probe = MUTS[name]
    (mx := tmp_path / "mx").mkdir()
    for n in ("ft_model_swap.py", "ft_model_swap_account.py", "ft_api_outage.py", "ft_api_outage_util.py", "model-fallback.tsv"):
        _ = shutil.copy(BIN / n, mx / n)
    s = (mx / f).read_text(encoding="utf-8")
    assert old in s, (name, old)
    _ = (mx / f).write_text(s.replace(old, new, 1), encoding="utf-8")
    monkeypatch.setattr(tms, "SWAP", mx / "ft_model_swap.py")
    (run := tmp_path / "run").mkdir()
    with pytest.raises(AssertionError):
        probe(run)
