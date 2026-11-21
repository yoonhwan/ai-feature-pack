"""r2380 — ft-stall-scan 의 «사람 대기» 갈래: 6시간 넘은 오빠 대기를 «사람 대기 점검» 으로 세고, 줄이 풀려 지워지면 desk 에 «사람 대기 풀림» 1통.

반례 ⑥~⑲ (①~⑤ = lint 칸 · tests/test_index_lint_human_wait_r2380.sh)
 c06 ⑦ 6시간 넘은 오빠 대기 = 팀 master 에 «사람 대기 점검» 1통(thread ts 포함) · c07 6시간 안 = 0통 · c08 같은 사건 두 번째 실행 = 0통
 c09 다른 선행이 진행 카드를 가리키면(blocked) 사람 대기 0통 (blocked 가 human 을 이긴다) · c10 «확인 <시각>» 줄이 이기면 0통 · c11 확인 줄이 앞날이면 0통
 c12 점검 1통 뒤 선행 줄이 풀려 지워지면 «사람 대기 풀림» 1통 · c13 그 1통은 desk 에 가고 그 thread ts + 결과 1줄 요구
 c14 점검이 안 나간 줄(6시간 안에 풀림)은 풀림 0통 · c15 F1 트리를 못 읽은 실행은 풀림 0통 + 기록 그대로(다음 실행 풀림 1통)
 c16 F2 점검 기록은 6시간 창 뒤에도 남는다(8시간 뒤 줄 지움 = 풀림 1통) · c17 가짜 git log rc1 = 경보 0 + «판정 불가 사람 대기 <카드>» 1줄 + 다른 카드 그대로
 c18 desk 없음(명부 `_desk` 없음) = 팀 master 에 풀림 1통 + «판정 불가 desk» 1줄 · c19 ts 없는 자유 문장 선행(7시간) = 경보 0 + a 줄 글자 기준판과 같음
R2380_BIN = 시험할 bin 폴더(기본 kit) · R2380_BASE_BIN = 기준판 bin(⑲ 대조 · 없으면 기대 문장만).
임시 리포(bare origin + 체크아웃) · 가짜 좌석·tmux·mbox · 네트워크 0 · 실 좌석 깨우기 0.
"""
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import NOW, World
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2380_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
BASE_BIN = os.environ.get("R2380_BASE_BIN")
GIT = shutil.which("git") or "git"
GENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "LC_ALL": "C"}
TS = "1795016460.792199"
HUMAN = f"# h\n- 선행: 오빠 승인 대기 (master#66 #340166 · thread {TS})\n"
PLAIN = "# h\n- 선행: 없음\n"


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def git(cwd: Path, *args: str, at: float | None = None) -> str:
    env = dict(GENV)
    if at is not None:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"@{int(at)} +0000"
    r = subprocess.run([GIT, *args], cwd=cwd, env=env, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, (args, r.stderr)
    return r.stdout.strip()


def make_repo(w: World, label: str, files: dict[str, str], ages: dict[str, float] | None = None) -> Path:
    """그 팀 카드 체크아웃 = 리포 · 파일마다 커밋 1개(시각 = NOW − ages[상대경로]시간) → origin/main push.
    나이 시험은 카드 «마지막 커밋 시각» 을 쓰므로 파일마다 따로 커밋한다(한 커밋에 묶으면 나이가 같아진다)."""
    wt = w.root / f".worktrees/wt-{label}"
    origin = w.root / f"origin-{label}.git"
    git(w.root, "init", "-q", "--bare", "-b", "main", str(origin))
    git(wt, "init", "-q", "-b", "main")
    git(wt, "remote", "add", "origin", str(origin))
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--allow-empty", "-m", "c0", at=NOW - 400 * 3600)
    for rel, text in files.items():
        p = wt / f"design/{label}/indices" / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        _ = p.write_text(text, encoding="utf-8")
        git(wt, "add", "-A")
        git(wt, "commit", "-q", "-m", f"put {rel}", at=NOW - float((ages or {}).get(rel, 0.0)) * 3600)
    git(wt, "push", "-q", "origin", "main")
    return wt


def put(w: World, label: str, rel: str, text: str, hours_ago: float = 0.0) -> None:
    """카드 1장 다시 쓰고 커밋·push — 나이 = hours_ago 시간."""
    wt = w.root / f".worktrees/wt-{label}"
    p = wt / f"design/{label}/indices" / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    _ = p.write_text(text, encoding="utf-8")
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "-m", f"put {rel}", at=NOW - hours_ago * 3600)
    git(wt, "push", "-q", "origin", "main")


def desk(w: World, seat: str = "t1-desk#9") -> None:
    """그 팀 명부에 `_desk` 를 단다(풀림 1통 받을이)."""
    p = w.root / ".fable-team/seats-t1.json"
    doc = json.loads(p.read_text(encoding="utf-8"))
    doc["_desk"] = seat
    _ = p.write_text(json.dumps(doc), encoding="utf-8")


def shim_git(w: World, body: str) -> None:
    """PATH 앞 shim 의 git 을 갈아 끼운다 — «ls-tree» 나 «log» 한 갈래만 실패시키는 데 쓴다."""
    p = w.stub / "shim" / "git"
    _ = p.write_text(f'#!/bin/sh\n{body}\nexec {GIT} "$@"\n')
    p.chmod(0o755)


def scan(w: World, bin_dir: Path | str | None = None, dry: bool = False) -> subprocess.CompletedProcess[str]:
    w.state("t1-master#1", "IDLE", 5)
    args = [str(Path(bin_dir or BIN) / "ft-stall-scan.sh")] + (["--dry-run"] if dry else [])
    return subprocess.run(["bash", *args], env=w.env, capture_output=True, text=True, timeout=90)


def human(w: World, kind: str) -> list[str]:
    return [ln for ln in w.mbox_log() if kind in ln]


def test_c06_six_hours_over_alerts_master(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    r = scan(w)
    hits = human(w, "사람 대기 점검")
    assert len(hits) == 1 and hits[0].startswith("send|t1-master#1|"), (hits, r.stdout, r.stderr)
    assert TS in hits[0], hits[0]


def test_c07_under_six_hours_is_quiet(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 2})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c08_same_event_twice_is_one_message(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    _ = scan(w)
    _ = scan(w)
    assert len(human(w, "사람 대기 점검")) == 1, human(w, "사람 대기 점검")


def test_c09_blocked_prereq_beats_human_wait(w: World) -> None:
    body = f"# h\n- 선행: indices/진행/z.md\n- 선행: 오빠 승인 대기 (thread {TS})\n"
    make_repo(w, "t1", {"대기/h.md": body, "진행/z.md": "# z\n- 선행: 없음\n"}, {"대기/h.md": 7})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c10_confirm_line_wins(w: World) -> None:
    stamp = datetime.fromtimestamp(NOW - 3600).strftime("%Y-%m-%d %H:%M")  # 1시간 전에 «아직 대기» 확인
    make_repo(w, "t1", {"대기/h.md": f"# h\n- 확인: {stamp}\n" + HUMAN.split("\n", 1)[1]}, {"대기/h.md": 7})
    r = scan(w)  # 카드 커밋은 7시간 전이지만 확인 줄이 더 최근이면 나이 0(⑩)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c11_future_confirm_line_is_quiet(w: World) -> None:
    stamp = datetime.fromtimestamp(NOW + 7200).strftime("%Y-%m-%d %H:%M")  # 앞날 확인 줄 = 나이 음수(⑪)
    make_repo(w, "t1", {"대기/h.md": f"# h\n- 확인: {stamp}\n" + HUMAN.split("\n", 1)[1]}, {"대기/h.md": 7})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c12_resolved_line_sends_done_once(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, (human(w, "사람 대기 풀림"), r.stdout)
    _ = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, human(w, "사람 대기 풀림")  # 기록을 지웠으니 다시 0통


def test_c13_done_message_goes_to_desk_with_thread_ts(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    hits = human(w, "사람 대기 풀림")
    assert len(hits) == 1 and hits[0].startswith("send|t1-desk#9|"), (hits, r.stdout)
    assert TS in hits[0] and "결과 1줄" in hits[0], hits[0]


def test_c14_no_check_no_done(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 1})
    desk(w)
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert not human(w, "사람 대기 풀림"), (human(w, "사람 대기"), r.stdout)


def test_c15_unreadable_tree_keeps_record(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    shim_git(w, 'case "$PWD" in */wt-t1/*) [ "$1" = ls-tree ] && exit 1;; esac')
    r = scan(w)
    assert not human(w, "사람 대기 풀림"), (human(w, "사람 대기 풀림"), r.stdout)
    assert "판정 불가 사람 대기 t1" in r.stdout, r.stdout
    p = w.stub / "shim" / "git"
    p.unlink()  # 가짜 git 걷어내고 같은 상황(줄 지움)을 다시 — 기록이 남아 있으면 여기서 풀림 1통
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, (human(w, "사람 대기 풀림"), r.stdout)


def test_c16_record_survives_beyond_window(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    w.advance(8 * 3600)  # 점검 기록이 6시간 창보다 오래됐다 — 그래도 남아야 한다(F2)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, (human(w, "사람 대기"), r.stdout)


def test_c17_git_log_failure_is_one_line_other_card_kept(w: World) -> None:
    make_repo(w, "t1", {"대기/bad.md": HUMAN, "대기/ok.md": HUMAN}, {"대기/bad.md": 7, "대기/ok.md": 7})
    shim_git(w, 'case "$*" in *"대기/bad.md"*) case "$*" in *log*) exit 1;; esac;; esac')  # 묶음 log·카드별 log 둘 다 실패
    r = scan(w)
    hits = human(w, "사람 대기 점검")
    assert len(hits) == 1 and "ok" in hits[0], (hits, r.stdout)
    assert "판정 불가 사람 대기 bad" in r.stdout, r.stdout


def test_c18_no_desk_falls_back_to_master(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    hits = human(w, "사람 대기 풀림")
    assert len(hits) == 1 and hits[0].startswith("send|t1-master#1|"), (hits, r.stdout)
    assert "판정 불가 desk" in r.stdout, r.stdout


def test_c19_free_text_prereq_stays_unknown(w: World) -> None:
    body = "# h\n- 선행: 오빠 승인 대기 (master#66 #340166)\n"  # thread ts 없음 = K4 판정 불가(경보 0 · a 줄은 지금 그대로)
    make_repo(w, "t1", {"대기/h.md": body, "대기/ok.md": PLAIN.replace("# h", "# ok")}, {"대기/h.md": 7, "대기/ok.md": 0})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)
    line = next((ln for ln in r.stdout.splitlines() if ln.startswith("a ")), "")
    assert "선행 미판정 1장 제외" in line, r.stdout
    if BASE_BIN:
        b = scan(w, BASE_BIN)
        bline = next((ln for ln in b.stdout.splitlines() if ln.startswith("a ")), "")
        assert line == bline, (line, bline)


def test_c20_watch_drops_the_lint_switch(w: World) -> None:
    """③b K5 — 바깥 환경에 FT_LINT_HUMAN_WAIT=reject 가 있어도 정체 감시는 그 스위치를 «지우고» lint 를 부른다(카드 판정·a 줄 글자 그대로)."""
    stub = w.stub / "lint-reject.sh"
    _ = stub.write_text('#!/bin/sh\n[ "$FT_LINT_HUMAN_WAIT" = reject ] && { echo "REJECT $1"; exit 1; }\nexit 0\n')
    stub.chmod(0o755)
    w.env["FT_INDEX_LINT"] = str(stub)
    w.env["FT_LINT_HUMAN_WAIT"] = "reject"
    make_repo(w, "t1", {"대기/ok.md": PLAIN.replace("# h", "# ok")}, {"대기/ok.md": 0})
    r = scan(w)
    line = next((ln for ln in r.stdout.splitlines() if ln.startswith("a ")), "")
    assert "대기 카드 1장(ok)" in line, (line, r.stdout)
