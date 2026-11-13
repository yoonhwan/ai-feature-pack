"""r1416 — 다른 루트로 간 쪽지(BRIDGED · 직접 송신)도 보낸 쪽 루트 우편함 «기록»(mailbox.log.jsonl)에 영수 1줄.

실사건 = planner 가 aifp·kakao 좌석 [HIL] 에 «회신 #N» 을 보냈는데 ft-decision-count 가 «30분 넘은 팀 대기» 로 셈
  (회신 셈 answered_seqs = 보낸 쪽 루트 기록의 «from = 내 계보» 줄 · 다리는 받는 쪽 루트에만 줄을 썼다).
세계 = 임시 루트 2개(byz 꼴 = planner 명부 · kakao 꼴 = 하위 폴더 루트) + 가짜 roots.tsv + 가짜 tmux(doorbell).
환경: R1416_COMM(시험할 comm) · R1416_BIN(answered_seqs 를 부를 bin) — 셸 짝 tests/test_mbox_bridge_receipt_r1416.sh 가 변이 사본을 넣는다.
격리: 실 우편함·실 tmux·실 /tmp 상태·실 좌석 0 · HOME 도 임시.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

HERE = Path(__file__).resolve().parents[2]
COMM = Path(os.environ.get("R1416_COMM") or HERE / "comm")
BIN = Path(os.environ.get("R1416_BIN") or HERE / "bin")
PLANNER = "byz-planner-master-claude#150"
TEAMS_BYZ = "| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| planner | design/planner/ | 현역 | seats-planner.json |\n"
TEAMS_KAKAO = "| 팀 | 폴더 | 상태 | 명부 |\n|---|---|---|---|\n| kakao | design/kakao/ | 현역 | seats.json |\n"


def write(path: Path, body: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    return path


def seats(master: str, extra: list[str]) -> str:
    return json.dumps({"_master": master, **{m: {"role": "nano"} for m in [master, *extra]}}, ensure_ascii=False)


class World:
    def __init__(self, tmp: Path) -> None:
        self.tmp, self.byz, self.kakao = tmp, tmp / "byz", tmp / "kakao/.worktrees/bootstrap/kakao-planning"
        stub = tmp / "stub"
        write(stub / "tmux", "#!/bin/sh\nexit 0\n").chmod(0o755)
        for root in (self.byz, self.kakao):
            dst = root / ".fable-team/comm"
            dst.mkdir(parents=True)
            for f in COMM.iterdir():
                if f.is_file() and f.suffix in (".py", ".sh"):
                    shutil.copyfile(f, dst / f.name)
        write(self.byz / "design/TEAMS.md", TEAMS_BYZ)
        write(self.kakao / "design/TEAMS.md", TEAMS_KAKAO)
        write(self.byz / ".fable-team/seats-planner.json", seats(PLANNER, ["byz-harness-master-claude#150"]))
        write(self.kakao / ".fable-team/seats.json", seats("kakao-master#1", ["kakao-nano#0"]))
        self.tsv = write(tmp / "roots.tsv", f"byz\t{self.byz}\t현역\torigin/main\t.\t기본\n"
                         f"kakao\t{self.kakao}\t현역\tfeature/bootstrap\t.\t{tmp}/lock-kakao\n")
        (tmp / "home").mkdir()
        self.env = {**os.environ, "FT_ROOTS_TSV": str(self.tsv), "HOME": str(tmp / "home"),
                    "PATH": f"{stub}{os.pathsep}{os.environ['PATH']}"}
        for k in ("FT_MBOX_BRIDGED", "FT_MBOX_RECEIPT", "FT_MBOX_DIR", "TMUX", "TMUX_PANE"):
            self.env.pop(k, None)

    def comm(self, root: Path) -> Path:
        return root / ".fable-team/comm"

    def send(self, root: Path, to: str, frm: str, body: str, **extra: str) -> subprocess.CompletedProcess[str]:
        env = {**self.env, "FT_ROOT": str(root), "FT_MBOX_DIR": str(self.comm(root)), **extra}
        return subprocess.run(["bash", str(self.comm(root) / "mbox.sh"), "send", to, frm, body],
                              env=env, capture_output=True, text=True, timeout=30)

    def rows(self, root: Path, name: str) -> list[dict]:
        p = self.comm(root) / name
        return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.is_file() else []

    def answered(self, root: Path, seat: str) -> set[int]:
        code = f"import sys; sys.path.insert(0, {str(BIN)!r}); import ft_inbox_core as c; print(sorted(c.answered_seqs({seat!r})))"
        got = subprocess.run([sys.executable, "-c", code], env={**self.env, "FT_ROOT": str(root)},
                             capture_output=True, text=True, timeout=30)
        assert got.returncode == 0, got.stderr
        return set(json.loads(got.stdout))

    def receipts(self, root: Path) -> list[dict]:
        return [r for r in self.rows(root, "mailbox.log.jsonl") if "bridged" in r]


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


# ── B1 — 루트 A planner → 루트 B 좌석 «회신 #7» 다리 rc0 → 루트 A answered_seqs(planner) ∋ 7 · 영수 1줄(두 번 쓰기 0)
def test_b1_bridged_reply_counts_on_sender_root(w: World) -> None:
    got = w.send(w.byz, "kakao-master#1", PLANNER, "회신 #7 진행하세요")
    assert got.returncode == 0 and "BRIDGED" in got.stdout, got.stdout + got.stderr
    assert 7 in w.answered(w.byz, PLANNER)
    rec = w.receipts(w.byz)
    assert len(rec) == 1, rec
    assert rec[0]["bridged"] == "kakao" and rec[0]["to"] == "kakao-master#1" and rec[0]["from"] == PLANNER
    assert rec[0]["body"] == "회신 #7 진행하세요" and isinstance(rec[0]["remote_seq"], int) and "seq" not in rec[0]
    assert [r["seq"] for r in w.rows(w.kakao, "mailbox.jsonl")] == [rec[0]["remote_seq"]]


# ── B2 — 같은 송신 뒤 루트 A 큐 = 0 · recv/peek 새 쪽지 0(영수는 기록에만)
def test_b2_receipt_is_not_delivered(w: World) -> None:
    assert w.send(w.byz, "kakao-master#1", PLANNER, "회신 #7").returncode == 0
    assert w.rows(w.byz, "mailbox.jsonl") == []
    env = {**w.env, "FT_ROOT": str(w.byz), "FT_MBOX_DIR": str(w.comm(w.byz))}
    for seat in (PLANNER, "byz-harness-master-claude#150", "kakao-master#1"):
        for verb in ("peek", "recv"):
            got = subprocess.run(["bash", str(w.comm(w.byz) / "mbox.sh"), verb, seat], env=env,
                                 capture_output=True, text=True, timeout=30)
            assert "회신 #7" not in got.stdout + got.stderr, (verb, seat, got.stdout)


# ── B3 — 다리 송신 실패(rc≠0) → 영수 0 · 지금 오류 출구 그대로
def test_b3_bridge_failure_writes_no_receipt(w: World) -> None:
    shutil.rmtree(w.comm(w.kakao))
    got = w.send(w.byz, "kakao-master#1", PLANNER, "회신 #7")
    assert got.returncode != 0 and "판정 불가" in got.stderr, (got.returncode, got.stderr)
    assert w.receipts(w.byz) == [] and 7 not in w.answered(w.byz, PLANNER)


# ── B4 — 영수 쓰기 실패 → 다리 결과 그대로(BRIDGED) + WARN 1줄
def test_b4_receipt_write_failure_warns(w: World) -> None:
    code = (f"import sys; sys.path.insert(0, {str(w.comm(w.byz))!r}); import mbox_roots as m, mbox_receipt as r; from pathlib import Path\n"
            f"m.CANON = {str(w.comm(w.byz))!r}\n"
            "orig = r.receipt\n"
            "r.receipt = lambda comm, *a: orig(Path(m.CANON) / 'no-such-dir', *a)\n"
            f"print(m.bridge('kakao-master#1', {PLANNER!r}, '회신 #7'))\n")
    got = subprocess.run([sys.executable, "-c", code], env=w.env, capture_output=True, text=True, timeout=30)
    assert got.returncode == 0 and got.stdout.startswith("BRIDGED → kakao"), got.stdout + got.stderr
    warns = [ln for ln in got.stderr.splitlines() if ln.startswith("WARN")]
    assert len(warns) == 1 and "영수" in warns[0], got.stderr
    assert len(w.rows(w.kakao, "mailbox.jsonl")) == 1


# ── B5 — 같은 루트 안 송신(다리 0) → 지금과 같음(영수 0 · 기록 1줄은 원래 꼴)
def test_b5_same_root_send_unchanged(w: World) -> None:
    got = w.send(w.byz, "byz-harness-master-claude#150", PLANNER, "회신 #5")
    assert got.returncode == 0 and "QUEUED" in got.stdout and "BRIDGED" not in got.stdout
    log = w.rows(w.byz, "mailbox.log.jsonl")
    assert len(log) == 1 and set(log[0]) == {"seq", "ts", "to", "from", "body"}, log
    assert w.receipts(w.kakao) == [] and w.rows(w.kakao, "mailbox.log.jsonl") == []


# ── B6 — 다른 루트 우편함 «직접» 송신(FT_MBOX_DIR=그 루트 · FT_MBOX_BRIDGED=1)의 «회신 #9» → 보낸 쪽 answered_seqs ∋ 9
def test_b6_direct_foreign_mailbox_reply_counts(w: World) -> None:
    got = w.send(w.kakao, "kakao-master#1", PLANNER, "회신 #9", FT_MBOX_BRIDGED="1")
    assert got.returncode == 0 and "QUEUED" in got.stdout, got.stdout + got.stderr
    assert 9 in w.answered(w.byz, PLANNER)
    rec = w.receipts(w.byz)
    assert len(rec) == 1 and rec[0]["bridged"] == "kakao" and "seq" not in rec[0], rec
    assert w.rows(w.byz, "mailbox.jsonl") == []
