"""R134 — 원본 폴더(scripts/fable-team-bin/)에서 도구 1개만 돌릴 때 형제 도구 없음을 «런타임 bin 에서 실행하라» 로 명시 거절한다.

대상 4개: ft-successor-open · ft-nano-spawn · ft-index-move · mbox-v2. 선례: ft-role-spawn.sh 69행.
시험은 임시 폴더에 도구 1개만 복사(형제 없음) / 형제까지 복사(형제 있음 — rc 1 스텁)해 돌린다.
실제 tmux·mbox 송신·좌석 열기 0 — tmuxc 는 PATH 앞 가짜(호출 기록)로 막고, 거절 뒤 부작용(파일 생성·tmuxc 호출) 0 을 확인한다.
"""

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest
from ft_git_helpers import copy_py_helpers

REPO =Path(__file__).resolve().parents[3]
SRC = REPO / "harness" / "bin"
KIT = REPO / "harness" / "kit" / "fable-team" / "bin"
HINT = "런타임 .fable-team/bin/ 에서 실행하라"
GIT_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY")


def _nano_siblings(script_text: str) -> list[str]:
    """ft-nano-spawn.sh 의 `for _sib in …` 줄(형제 목록 정본)에서 쉘 형제 이름을 읽는다 — 목록이 늘어도 표본이 따라간다(R345)."""
    line = next((ln for ln in script_text.splitlines() if "for _sib in " in ln), "")
    names = re.findall(r"ft-[\w-]+\.sh", line)
    assert names, "ft-nano-spawn.sh 에서 `for _sib in` 형제 목록을 못 읽었다 — 표본 0 으로 조용히 통과하지 않는다"
    return names


def _env(fakebin: Path) -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if k not in GIT_VARS and not k.startswith("FT_")}
    env["PATH"] = f"{fakebin}:{env['PATH']}"
    env["FT_TEAMSET"] = "0"  # R351: 위 FT_* 제거가 꺼 둔 값을 다시 — 표(origin/main)는 이 시험 주제가 아님
    return env


def _snapshot(*roots: Path) -> list[str]:
    return sorted(str(p) for r in roots for p in r.rglob("*"))


def _stub(path: Path, rc: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"#!/usr/bin/env bash\nexit {rc}\n", encoding="utf-8")
    path.chmod(0o755)


@pytest.fixture
def fakebin(tmp_path: Path) -> Path:
    """PATH 앞에 둘 가짜 tmuxc — 호출되면 calls.log 에 남기고 rc 1."""
    d = tmp_path / "fakebin"
    d.mkdir()
    log = tmp_path / "calls.log"
    tmuxc = d / "tmuxc"
    tmuxc.write_text(f'#!/usr/bin/env bash\necho "tmuxc $*" >> "{log}"\nexit 1\n', encoding="utf-8")
    tmuxc.chmod(0o755)
    return d


def _calls(tmp_path: Path) -> str:
    log = tmp_path / "calls.log"
    return log.read_text(encoding="utf-8") if log.exists() else ""


def _run(cmd: list[str], cwd: Path, env: dict[str, str]) -> "subprocess.CompletedProcess[str]":
    return subprocess.run(
        cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30
    )


# --- 도구별 준비: (복사할 도구, 형제 이름 목록, 인자·작업 폴더 만들기) ---


def _successor_args(tmp_path: Path, bindir: Path) -> tuple[list[str], Path]:
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True, env=_env(tmp_path / "fakebin"))
    body = tmp_path / "body.txt"
    body.write_text("골1\n골2\n골3\n본문\n", encoding="utf-8")
    args = [
        "bash",
        str(bindir / "ft-successor-open.sh"),
        "old#1",
        str(repo),
        "--name",
        "new#2",
        "--agent",
        "claude",
        "--model",
        "m",
        "--body-file",
        str(body),
    ]
    return args, tmp_path


def _nano_args(tmp_path: Path, bindir: Path) -> tuple[list[str], Path]:
    idx = tmp_path / "indices" / "대기" / "x.md"
    idx.parent.mkdir(parents=True)
    idx.write_text("# 인덱스: x\n", encoding="utf-8")
    seats = tmp_path / "seats.json"
    seats.write_text("{}", encoding="utf-8")
    cwd = tmp_path / "cwd"
    cwd.mkdir()
    return ["bash", str(bindir / "ft-nano-spawn.sh"), str(idx)], cwd


def _move_args(tmp_path: Path, bindir: Path) -> tuple[list[str], Path]:
    card = tmp_path / "indices" / "대기" / "x.md"
    card.parent.mkdir(parents=True)
    card.write_text("# 인덱스: x\n", encoding="utf-8")
    return ["bash", str(bindir / "ft-index-move.sh"), str(card), "진행", "--seat", "s#0"], tmp_path


def _mbox_args(tmp_path: Path, bindir: Path) -> tuple[list[str], Path]:
    return ["bash", str(bindir / "mbox-v2.sh"), "peek", "x"], tmp_path


# 도구 → (인자 만들기, 필수 형제 {이름: rc 1 스텁이 막아 줄 뒤 단계 문구}, 형제 있음일 때 기대하는 기존 문구)
CASES = {
    "ft-successor-open.sh": (
        _successor_args,
        ["ft-send-verified.sh", "ft-reach-check.sh"],
        "REJECT tmuxc open 실패",
    ),
    "ft-nano-spawn.sh": (
        _nano_args,
        _nano_siblings((SRC / "ft-nano-spawn.sh").read_text(encoding="utf-8")),
        "REJECT lint 실패",
    ),
    "ft-index-move.sh": (_move_args, ["ft-index-lint.sh"], "REJECT lint 실패"),
    "mbox-v2.sh": (_mbox_args, ["mbox.py"], ""),
}


GATED = ("ft-successor-open.sh", "ft-nano-spawn.sh")  # 맨 앞에서 자원 문지기를 부르는 도구(ft-role-spawn 은 아래 별도 시험)


def _prepare(
    tmp_path: Path, tool: str, with_siblings: bool
) -> tuple[list[str], Path, dict[str, str], Path]:
    make_args, siblings, _ = CASES[tool]
    bindir = tmp_path / "bin"
    bindir.mkdir()
    shutil.copy(SRC / tool, bindir / tool)
    if tool in GATED:
        _stub(bindir / "ft-resource-gate.sh", 0)  # 가짜 문지기 — 실제 머신 자원에 기대지 않는다
        copy_py_helpers(bindir)  # 문지기 다음 단계 순수 판정 도우미 전부(R149 ft_raised · 팀셋 ft_teamset·ft_spawn_queue …)
    if with_siblings:
        for s in siblings:
            _stub(bindir / s, 1)
    args, cwd = make_args(tmp_path, bindir)
    if with_siblings and tool == "ft-successor-open.sh":
        _stub(tmp_path / "repo" / ".fable-team" / "comm" / "mbox.sh", 0)  # R343: mbox 는 대상 리포 것
    env = _env(tmp_path / "fakebin")
    if tool == "ft-nano-spawn.sh":
        env["FT_SEATS_JSON"] = str(tmp_path / "seats.json")
    return args, cwd, env, bindir


@pytest.mark.parametrize("tool", CASES)
def test_sibling_missing_rejects_with_hint(tmp_path: Path, fakebin: Path, tool: str) -> None:
    args, cwd, env, bindir = _prepare(tmp_path, tool, with_siblings=False)
    before = _snapshot(tmp_path / "bin", cwd)
    r = _run(args, cwd, env)
    out = r.stdout + r.stderr
    assert r.returncode != 0, out
    assert "REJECT" in out and "없음:" in out and HINT in out, out
    assert _snapshot(tmp_path / "bin", cwd) == before, "거절 뒤 새 파일이 생겼다"
    assert _calls(tmp_path) == "", "거절 전에 tmuxc 가 불렸다"


@pytest.mark.parametrize(
    "tool,sibling", [(t, s) for t, (_, sibs, _) in CASES.items() for s in sibs]
)
def test_each_missing_sibling_is_named(
    tmp_path: Path, fakebin: Path, tool: str, sibling: str
) -> None:
    """형제가 여럿인 도구는 빠진 형제 이름을 정확히 말한다(하나만 빠진 경우)."""
    args, cwd, env, bindir = _prepare(tmp_path, tool, with_siblings=True)
    (bindir / sibling).unlink()
    r = _run(args, cwd, env)
    out = r.stdout + r.stderr
    assert r.returncode != 0, out
    assert f"REJECT {sibling} 없음:" in out and HINT in out, out
    assert _calls(tmp_path) == "", "거절 전에 tmuxc 가 불렸다"


@pytest.mark.parametrize("tool", CASES)
def test_siblings_present_keeps_existing_path(tmp_path: Path, fakebin: Path, tool: str) -> None:
    args, cwd, env, _ = _prepare(tmp_path, tool, with_siblings=True)
    (tmp_path / "bin" / "mbox.py").write_text(
        'import sys\nprint("STUB", *sys.argv[1:])\n', encoding="utf-8"
    ) if tool == "mbox-v2.sh" else None
    r = _run(args, cwd, env)
    out = r.stdout + r.stderr
    assert HINT not in out, out
    expected = CASES[tool][2]
    if expected:
        assert expected in out, out
    else:
        assert r.returncode == 0 and r.stdout.strip() == "STUB peek x", (r.stdout, r.stderr)


def test_nano_sibling_list_follows_script_source() -> None:
    """변이 표본 — 스크립트 형제 목록에 더미 하나를 더하면 표본에도 들어온다(고정 표본 아님)."""
    text = (SRC / "ft-nano-spawn.sh").read_text(encoding="utf-8")
    real = _nano_siblings(text)
    mutated = _nano_siblings(text.replace("for _sib in ", "for _sib in ft-dummy-sib.sh ", 1))
    assert "ft-dummy-sib.sh" in mutated and set(real) <= set(mutated) and "ft-dummy-sib.sh" not in real


@pytest.mark.parametrize("helper", ["ft_teamset.py", "ft_spawn_queue.py"])
def test_nano_spawn_missing_teamset_helper_rejects_before_side_effects(
    tmp_path: Path, fakebin: Path, helper: str
) -> None:
    """ft-nano-spawn.sh:61 — 팀셋 도우미 하나만 없는 설치본은 열기 전 안내 REJECT, 부작용 0."""
    args, cwd, env, bindir = _prepare(tmp_path, "ft-nano-spawn.sh", with_siblings=True)
    (bindir / helper).unlink()
    env.pop("FT_TEAMSET")  # 이 시험의 주제가 팀셋 칸 자체 — 끄지 않는다(R351)
    before = _snapshot(bindir, cwd)
    r = _run(args, cwd, env)
    out = r.stdout + r.stderr
    assert r.returncode == 1, (r.returncode, out)
    assert "REJECT ft_teamset.py·ft_spawn_queue.py 없음:" in out and HINT in out, out
    assert _snapshot(bindir, cwd) == before, "거절 뒤 새 파일이 생겼다"
    assert _calls(tmp_path) == "", "거절 전에 tmuxc 가 불렸다"


def test_successor_open_env_override_is_checked(tmp_path: Path, fakebin: Path) -> None:
    """env 로 바꾼 최종 경로가 없으면 기본 형제가 있어도 거절한다."""
    args, cwd, env, _ = _prepare(tmp_path, "ft-successor-open.sh", with_siblings=True)
    env["FT_SEND_VERIFIED"] = str(tmp_path / "nowhere" / "send.sh")
    r = _run(args, cwd, env)
    out = r.stdout + r.stderr
    assert r.returncode != 0 and "REJECT send.sh 없음:" in out and HINT in out, out
    assert _calls(tmp_path) == ""


def test_nano_spawn_dry_run_does_not_need_send_verified(tmp_path: Path, fakebin: Path) -> None:
    """--dry-run 은 송신 전에 끝난다 — send-verified 만 없는 설치본에서 거절하지 않는다."""
    args, cwd, env, bindir = _prepare(tmp_path, "ft-nano-spawn.sh", with_siblings=True)
    (bindir / "ft-send-verified.sh").unlink()
    r = _run([*args, "--dry-run"], cwd, env)
    out = r.stdout + r.stderr
    assert HINT not in out and "REJECT lint 실패" in out, out


@pytest.mark.parametrize("tool", ["ft-successor-open.sh", "ft-nano-spawn.sh", "ft-role-spawn.sh"])
def test_missing_resource_gate_rejects_before_side_effects(
    tmp_path: Path, fakebin: Path, tool: str
) -> None:
    """R182 — 문지기만 없는 설치본: rc 127(No such file) 이 아니라 안내 REJECT rc 1, 부작용 전."""
    if tool == "ft-role-spawn.sh":
        bindir = tmp_path / "bin"
        bindir.mkdir()
        shutil.copy(SRC / tool, bindir / tool)
        args, cwd = ["bash", str(bindir / tool), "master"], tmp_path
    else:
        args, cwd, _, bindir = _prepare(tmp_path, tool, with_siblings=True)
        (bindir / "ft-resource-gate.sh").unlink()
    env = _env(fakebin)
    before = _snapshot(bindir, cwd)
    r = _run(args, cwd, env)
    out = r.stdout + r.stderr
    assert r.returncode == 1, (r.returncode, out)
    assert "REJECT ft-resource-gate.sh 없음:" in out and HINT in out, out
    assert _snapshot(bindir, cwd) == before, "거절 뒤 새 파일이 생겼다"
    assert _calls(tmp_path) == "", "거절 전에 tmuxc 가 불렸다"


@pytest.mark.parametrize("tool", [*CASES, "ft-role-spawn.sh", "ft-tick.sh"])
def test_kit_copy_is_byte_identical(tool: str) -> None:
    assert (SRC / tool).read_bytes() == (KIT / tool).read_bytes(), f"키트 사본 drift: {tool}"
