"""r1392 — stall-scan 이 대기 카드 lint 를 «바뀐 카드만» 돌리고(카드 blob oid + lint 판 sha 캐시), 한 실행의 lint 는 판정 기한 D 의 절반에서 멈춘다.

L1 좌석 106(4 live) · 팀장 IDLE · 대기 60장 · 캐시 0 · 느린 lint(0.5s) · D=20 → 70초 안에 rc0 (못 잰 장은 «lint 미판정» 줄)
L2 L1 바로 뒤 둘째 실행 → lint 호출 = 첫 실행 미판정 장 수만 · 셋째 실행 lint 0
L3 첫 실행을 기한 넘김으로 강제(팀 t2 의 git ls-tree 지연 · D=10 · lint 1s) → rc3 + stall-scan.json lint 칸에 그때까지 잰 장 · 둘째 실행은 그 장 lint 0
L4 카드 1장 본문 바꿈(oid 바뀜) → 그 장만 lint 1회 · 나머지 0
L5 ft-index-lint.sh 내용 바뀜(lint 판 sha 바뀜) → 전부 다시 잰다
L6 캐시 at 이 6시간 넘음 → 그 장 다시 잰다
L7 lint 미판정 장은 a 후보 0 · notes 에 «a? <팀> lint 미판정 N장 — 다음 실행» 1줄 · ready 장은 지금처럼 a
R1392_BIN = 시험할 bin 폴더(기본 kit) · R1392_BASE_BIN = 기준판 bin(없으면 안 씀).
격리: 임시 리포(bare origin + 체크아웃) · 가짜 명부·tmux·mbox·seat-status·lint — 실 루트 0 · 네트워크 0 · 실 좌석 깨우기 0 · 자기 재호출 0.
낮은 우선순위(taskpolicy -b)는 sudo 가 필요해 쓰지 않고, lint 비용(고정 지연)으로 «느린 lint» 를 재현한다.
바쁜 루프 대신 sleep 을 쓰는 이유: macOS python 기동이 호출당 0.35초라 비용을 덮어(60장 = 21초) 시험 시간 상한(하드 룰 22)을 넘긴다.
예산·캐시 계약은 «걸린 시간» 만 보므로 같은 반례를 만든다.
시험 시간 상한(하드 룰 22) 때문에 live 좌석은 4(좌석 판정 자체가 좌석당 30ms × 8회 — 36 live 면 한 실행에 9~14초)으로 줄이고,
명부에는 106석을 그대로 둔다(«좌석 106 중 4 live»). 부하는 lint 비용으로 만든다.
"""
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1392_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
GIT = shutil.which("git") or "git"
GENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "LC_ALL": "C"}
CARD = "# {n}\n- 선행: 없음\n"
NCARDS = 60
LINT = """#!/bin/sh
echo "$1" >> "$FT_STUB/lint.calls"
c=$(cat "$FT_STUB/lint.cost" 2>/dev/null || echo 0)
[ "$c" = 0 ] && exit 0
sleep "$c"
exit 0
"""


def git(cwd: Path, *args: str) -> str:
    r = subprocess.run([GIT, *args], cwd=cwd, env=GENV, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, (args, r.stderr)
    return r.stdout.strip()


def put(wt: Path, label: str, files: dict[str, str]) -> None:
    base = wt / f"design/{label}/indices"
    shutil.rmtree(base, ignore_errors=True)
    for rel, text in files.items():
        _ = (base / rel).parent.mkdir(parents=True, exist_ok=True)
        _ = (base / rel).write_text(text, encoding="utf-8")


def repo(w: World, label: str, disk: dict[str, str], ref: dict[str, str]) -> Path:
    """그 팀 카드 체크아웃 = 리포 · 디스크는 C1(disk) · origin/main 은 C2(ref). 캐시 oid 는 ref 트리에서 온다."""
    wt = w.root / f".worktrees/wt-{label}"
    wt.mkdir(parents=True, exist_ok=True)
    origin = w.root / f".worktrees/origin-{label}.git"
    git(wt.parent, "init", "-q", "--bare", "-b", "main", str(origin))
    git(wt, "init", "-q", "-b", "main")
    git(wt, "remote", "add", "origin", str(origin))
    put(wt, label, disk)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--allow-empty", "-m", "c1 disk")
    put(wt, label, ref)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--allow-empty", "-m", "c2 ref")
    git(wt, "push", "-q", "origin", "main")
    return wt


def bump(w: World, label: str, files: dict[str, str]) -> None:
    """ref 를 앞으로 — 카드 본문(oid)이 바뀐 상황."""
    wt = w.root / f".worktrees/wt-{label}"
    put(wt, label, files)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--allow-empty", "-m", "c3 bump")
    git(wt, "push", "-q", "origin", "main")


def many(n: int = NCARDS, body: str = CARD) -> dict[str, str]:
    return {f"대기/c{i:02d}.md": body.format(n=f"c{i:02d}") for i in range(n)}


def roster(w: World, team: str, master: str, live: int, total: int) -> None:
    """명부 = 팀장 1 + live 만큼 실 좌석 + 나머지는 명부에만(total). 전부 IDLE(팀장 5분 · 좌석 30분)."""
    names = [f"{team}-n{i:02d}#0" for i in range(live)]
    rows: dict[str, object] = {"_master": master, "_label": team, "_cards": f"design/{team}/indices", "_cards_wt": f"wt-{team}", master: {"role": "master"}}
    rows |= {s: {"role": "nano"} for s in [*names, *(f"{team}-x{i:02d}#0" for i in range(max(total - live - 1, 0)))]}
    _ = (w.root / f".fable-team/seats-{team}.json").write_text(json.dumps(rows), encoding="utf-8")
    w.live = [master, *names]
    w._tmux()  # noqa: SLF001 — 시험 세계의 tmux 스텁을 라이브 좌석으로 다시 쓴다
    w.state(master, "IDLE", 5)
    for s in names:
        w.state(s, "IDLE", 30)


@pytest.fixture
def w(tmp_path: Path) -> World:
    world = World(tmp_path)
    lint = world.stub / "fake-lint.sh"
    _ = lint.write_text(LINT, encoding="utf-8")
    lint.chmod(0o755)
    world.env["FT_INDEX_LINT"] = str(lint)
    world.env["FT_STALL_PENALTY_AUTO"] = "0"  # 처리(페널티)는 이 카드 밖 — 시험 세계를 건드리지 않는다
    roster(world, "t1", "t1-master#1", 3, 106)  # 명부 106석 · live = 팀장 + 3(시험 시간 상한 · 부하는 lint 비용)
    repo(world, "t1", many(), many())
    return world


def cost(w: World, sec: float) -> None:
    _ = (w.stub / "lint.cost").write_text(str(sec), encoding="utf-8")


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=120)


def reset(w: World) -> None:
    (w.stub / "lint.calls").unlink(missing_ok=True)


def lints(w: World) -> list[str]:
    p = w.stub / "lint.calls"
    return [Path(x).stem for x in p.read_text(encoding="utf-8").splitlines()] if p.exists() else []


def cell(w: World) -> dict:
    p = w.root / ".fable-team/state/stall-scan.json"
    doc = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    lint = doc.get("lint")
    return lint if isinstance(lint, dict) else {}


def missed(out: str) -> int:
    m = re.search(r"lint 미판정 (\d+)장 — 다음 실행", out)
    return int(m.group(1)) if m else 0


def listed(out: str) -> int:
    m = re.search(r"대기 카드 (\d+)장\(", out)
    return int(m.group(1)) if m else 0


def test_l1_slow_lint_under_load_still_judges_in_time(w: World) -> None:
    cost(w, 0.5)  # 60장 × 0.5s = 30s > D(20) — 예산이 없으면 기한을 넘긴다
    w.env["FT_STALL_SCAN_TOTAL_S"] = "20"
    reset(w)
    r = scan(w)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "stall=" in r.stdout.splitlines()[0], r.stdout
    assert missed(r.stdout) > 0, r.stdout  # 예산에 걸린 장은 «미판정» 줄로 보인다(조용한 0 아님)
    assert len(lints(w)) <= 40, len(lints(w))  # D/2(5초) 뒤로는 lint 를 더 부르지 않는다


def test_l2_second_run_lints_only_what_was_left(w: World) -> None:
    cost(w, 0.5)
    w.env["FT_STALL_SCAN_TOTAL_S"] = "20"
    reset(w)
    first = scan(w)
    left = missed(first.stdout)
    assert left > 0, first.stdout
    cost(w, 0.05)  # 둘째 실행은 남은 장만 — 예산(30초) 안에서 끝난다
    w.env["FT_STALL_SCAN_TOTAL_S"] = "60"
    reset(w)
    second = scan(w)
    assert second.returncode == 0, second.stdout + second.stderr
    assert len(lints(w)) == left, (len(lints(w)), left)  # 첫 실행이 잰 장은 다시 안 잰다
    reset(w)
    third = scan(w)
    assert third.returncode == 0 and lints(w) == [], (third.stdout, lints(w))  # 셋째 실행 lint 0


def test_l3_timeout_keeps_what_was_already_linted(w: World, tmp_path: Path) -> None:
    w.team("t2", "t2-master#1", ["t2-nano#0"])
    w.state("t2-master#1", "IDLE", 5)
    repo(w, "t2", {"대기/t2card.md": CARD.format(n="t2card")}, {"대기/t2card.md": CARD.format(n="t2card")})
    shim = w.stub / "shim"
    git_path = shutil.which("git") or "git"
    _ = (shim / "git").write_text(f'#!/bin/sh\ncase "$PWD" in */wt-t2/*) [ "$1" = ls-tree ] && sleep 9;; esac\nexec {git_path} "$@"\n', encoding="utf-8")
    (shim / "git").chmod(0o755)
    w.env["FT_STALL_GIT_SEC"] = "20"  # git 상한이 아니라 D 가 먼저 끊는다
    cost(w, 1.0)  # 예산(D/2 = 5초) 안에서 5장 남짓만 잰다
    w.env["FT_STALL_SCAN_TOTAL_S"] = "10"
    reset(w)
    first = scan(w)
    assert first.returncode == 3, first.stdout + first.stderr
    assert "판정 기한 10 s 초과" in first.stdout, first.stdout
    saved = cell(w)
    assert len(saved) >= 1, first.stdout  # 기한을 넘겨도 그때까지 잰 장은 남는다
    shim_git = shim / "git"
    shim_git.unlink()  # 지연 제거 — 둘째 실행은 정상 속도
    cost(w, 0.05)
    w.env["FT_STALL_SCAN_TOTAL_S"] = "60"
    reset(w)
    second = scan(w)
    assert second.returncode == 0, second.stdout + second.stderr
    again = [s for s in lints(w) if s in saved]
    assert again == [], again  # 저장된 장은 다시 안 잰다
    assert len(lints(w)) == NCARDS + 1 - len(saved), (len(lints(w)), len(saved))


def test_l4_changed_card_is_linted_again_alone(w: World) -> None:
    cost(w, 0.05)
    reset(w)
    assert scan(w).returncode == 0
    cached = set(cell(w))  # 첫 실행이 기억한 장(부하로 몇 장 못 쟀을 수 있다 — 그 장은 «기억 없음» 이라 아래 비교에서 뺀다)
    assert len(cached) >= 55, len(cached)
    changed = {**many(), "대기/c07.md": "# c07\n- 선행: 없음\n\n본문 바뀜\n"}
    bump(w, "t1", changed)  # ref 의 c07 blob oid 가 바뀐다
    reset(w)
    second = scan(w)
    assert second.returncode == 0, second.stdout + second.stderr
    assert [s for s in lints(w) if s in cached] == ["c07"], lints(w)  # 기억한 장 중 바뀐 장만 다시


def test_l5_changed_lint_script_relints_all(w: World) -> None:
    cost(w, 0.05)
    reset(w)
    assert scan(w).returncode == 0
    lint = Path(w.env["FT_INDEX_LINT"])
    _ = lint.write_text(LINT + "# v2 — 판이 바뀌었다\n", encoding="utf-8")  # 동작 그대로 · 파일 내용만 바뀜
    lint.chmod(0o755)
    reset(w)
    second = scan(w)
    assert second.returncode == 0, second.stdout + second.stderr
    assert len(lints(w)) >= 55, len(lints(w))  # 판이 바뀌면 기억을 못 쓴다 — 전부 다시 잰다(캐시가 없던 기준판도 통과하는 «지키는» 계약)


def test_l6_cache_older_than_six_hours_is_rechecked(w: World) -> None:
    cost(w, 0.05)
    reset(w)
    assert scan(w).returncode == 0
    w.advance(6 * 3600 + 60)  # 캐시 at 이 6시간을 넘겼다
    reset(w)
    second = scan(w)
    assert second.returncode == 0, second.stdout + second.stderr
    assert len(lints(w)) >= 55, len(lints(w))  # 6시간 지난 판정은 다시 잰다


def test_l7_missed_cards_are_not_candidates_and_say_so(w: World) -> None:
    cost(w, 0.5)  # 0.5 × 60 = 30s > D/2(10초) → 절반 남짓만 재고 나머지는 미판정
    w.env["FT_STALL_SCAN_TOTAL_S"] = "20"
    reset(w)
    r = scan(w)
    assert r.returncode == 0, r.stdout + r.stderr
    left = missed(r.stdout)
    assert left > 0 and "a? t1 lint 미판정" in r.stdout, r.stdout  # 조용한 0 아님 — 1줄
    assert counts(r.stdout)["a"] == "1", r.stdout  # 잰 장은 지금처럼 a 후보
    assert listed(r.stdout) == NCARDS - left, (listed(r.stdout), left)  # 미판정 장은 a 후보 0
    assert NCARDS - left == len(lints(w)), (len(lints(w)), left)
