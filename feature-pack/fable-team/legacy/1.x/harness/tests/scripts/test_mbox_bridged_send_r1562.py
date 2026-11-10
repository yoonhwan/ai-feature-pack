"""r1562 — 다른 루트 좌석에 보낸 쪽지(BRIDGED)는 «보낸 쪽» mbox.sh 가 doorbell·inbox 적재·깨움 예산을 건드리지 않는다.

실사건 = master pi#172 #278479: aifp 팀장이 BYZ 좌석에 보낸 쪽지가 BYZ 큐에 바르게 들어갔는데도
보낸 쪽(aifp) mbox.sh 가 자기 경로 doorbell 을 한 번 더 쳐서, 받는 좌석이
`bash <aifp>/.fable-team/comm/mbox.sh recv <좌석>` 꼴 잘못된 발주를 10건 물었다.
받는 루트의 mbox.sh(다리 자식)가 자기 명부로 이미 판정·주입했으므로 보낸 쪽의 두 번째 주입은 필요 없다.

세계 = 임시 루트 2개(A=aifp 꼴 · B=byz 꼴) + 기계 루트 명부(roots.tsv 2행).
  B 명부: 확장 좌석 1(`b-ext#0` · seats-harness.json `_master` + agent pi + 확장 파일 존재) · 일반 좌석 1(`b-general#0`).
환경: R1562_COMM(시험할 comm 폴더 — 셸 짝 tests/test_mbox_bridged_send_r1562.sh 가 변이 사본을 넣는다).
격리: 실 우편함·실 tmux·실 /tmp 상태·실 좌석 0 — 가짜 tmux 는 send-keys 를 파일에 적고,
      가짜 ft-inbox.sh 는 «어느 루트가 적재했나» 만 파일에 적는다. HOME·TMPDIR 도 임시 폴더.
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

HERE = Path(__file__).resolve().parents[2]
COMM = Path(os.environ.get("R1562_COMM") or HERE / "comm")

FAKE_TMUX = """#!/bin/sh
printf '%s %%s\\n' "$*" >> "$FT_FAKE_TMUX_LOG" 2>/dev/null || true
case "$1" in
  list-panes)
    case "$2" in
      -a) printf 'a-nano#0|%%11\\nb-ext#0|%%33\\nb-general#0|%%22\\n'; exit 0;;
    esac
    exit 0;;            # pane_pid 조회 = 빈 값(에이전트 생존 판정은 이 시험 소관이 아니다)
esac
exit 0
"""

FAKE_INBOX = """#!/bin/sh
root="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s %s\\n' "$root" "$*" >> "$FT_FAKE_INBOX_LOG" 2>/dev/null || true
printf 'INGEST seq=%s cls=⑤ 시험\\n' "${2:-0}"
"""


def write(path: Path, body: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")
    return path


class World:
    """임시 루트 2개 + 루트 명부 1장 — 실 상태 파일은 하나도 안 건드린다."""

    def __init__(self, tmp: Path) -> None:
        self.tmp = tmp
        self.a = tmp / "aifp"          # 보낸 쪽 루트
        self.b = tmp / "byz"           # 받는 쪽 루트
        self.tmux_log = tmp / "tmux.log"
        self.inbox_log = tmp / "inbox.log"
        self.stub = tmp / "stub"
        self.stub.mkdir()
        t = self.stub / "tmux"
        write(t, FAKE_TMUX)
        t.chmod(0o755)
        # 확장 감시 파일 — ext_wake_seat 판정은 $HOME 아래 이 파일의 «존재» 까지 본다.
        self.home = tmp / "home"
        write(self.home / ".pi/agent/extensions/ft-mbox-wake.ts", "// r1562 시험용 빈 확장\n")
        (tmp / "tmpx").mkdir()
        for root in (self.a, self.b):
            self._comm(root)
            # 가짜 인박스 적재기 — inbox_ingest 는 <루트>/.fable-team/bin/ft-inbox.sh 를 부른다.
            write(root / ".fable-team/bin/ft-inbox.sh", FAKE_INBOX)
        write(self.a / ".fable-team/seats.json", json.dumps(
            {"_master": "a-master#1", "_label": "aifp",
             "a-master#1": {"role": "master", "tick": None},
             "a-nano#0": {"role": "nano", "tick": None}}, ensure_ascii=False))
        write(self.b / ".fable-team/seats-harness.json", json.dumps(
            {"_master": "b-ext#0", "_label": "harness",
             "b-ext#0": {"role": "master", "agent": "pi", "tick": None},
             "b-general#0": {"role": "nano", "tick": None}}, ensure_ascii=False))
        self.tsv = tmp / "roots.tsv"
        write(self.tsv, "# 이름\t경로\t상태\t기준ref\t사람우편함\t틱잠금접두\n"
                        f"aifp\t{self.a}\t현역\torigin/main\t.\t기본\n"
                        f"byz\t{self.b}\t현역\torigin/main\t.\t기본\n")
        self.env = {**os.environ, "FT_ROOTS_TSV": str(self.tsv), "HOME": str(self.home),
                    "TMPDIR": str(tmp / "tmpx"), "FT_FAKE_TMUX_LOG": str(self.tmux_log),
                    "FT_FAKE_INBOX_LOG": str(self.inbox_log),
                    "FT_MBOX_DOORBELL_MIN": "0",       # 시간 억제를 끈다 — 주입 여부만 본다
                    "PATH": f"{self.stub}{os.pathsep}{os.environ['PATH']}"}
        self.env.pop("FT_MBOX_BRIDGED", None)

    def _comm(self, root: Path) -> None:
        dst = root / ".fable-team/comm"
        dst.mkdir(parents=True, exist_ok=True)
        for f in COMM.iterdir():
            if f.is_file() and f.suffix in (".py", ".sh"):
                shutil.copyfile(f, dst / f.name)

    def env_for(self, root: Path, **extra: str) -> dict[str, str]:
        return {**self.env, "FT_ROOT": str(root), "FT_REPO_ROOT": str(root),
                "FT_MBOX_DIR": str(root / ".fable-team/comm"), **extra}

    def mbox(self, root: Path, *args: str, **extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(root / ".fable-team/comm/mbox.sh"), *args],
                              env=self.env_for(root, **extra), capture_output=True, text=True, timeout=60)

    def queue(self, root: Path) -> list[dict]:
        p = root / ".fable-team/comm/mailbox.jsonl"
        return [json.loads(x) for x in p.read_text(encoding="utf-8").splitlines() if x.strip()] if p.is_file() else []

    def injections(self) -> list[str]:
        """가짜 tmux 에 실제로 들어간 «주입 문자열» 만 — send-keys -l 한 줄."""
        if not self.tmux_log.is_file():
            return []
        return [x for x in self.tmux_log.read_text(encoding="utf-8").splitlines() if "recv" in x]

    def ingests(self, root: Path) -> list[str]:
        if not self.inbox_log.is_file():
            return []
        return [x for x in self.inbox_log.read_text(encoding="utf-8").splitlines() if x.startswith(str(root))]

    def budget_n(self, root: Path, seat: str) -> int:
        key = "".join(c if (c.isalnum() or c in "._#-") else "_" for c in seat)
        p = root / ".fable-team/state/wake-budget" / f"{key}.json"
        return json.loads(p.read_text(encoding="utf-8"))["n"] if p.is_file() else 0


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


# ── ⓐ 다른 루트 «확장 좌석» — B 큐 1행 · 가짜 tmux 주입 0 · 출력 BRIDGED + doorbell=bridged
def test_case_a_bridged_send_to_ext_seat_never_injects(w: World) -> None:
    got = w.mbox(w.a, "send", "b-ext#0", "a-master#1", "루트 넘는 쪽지 — 시험 본문")
    assert got.returncode == 0, got.stdout + got.stderr
    assert "BRIDGED" in got.stdout and "doorbell=bridged" in got.stdout, got.stdout
    assert "QUEUED" not in got.stdout, got.stdout
    assert w.queue(w.a) == [], "보낸 쪽 큐에 쓰면 안 된다"
    assert [r["to"] for r in w.queue(w.b)] == ["b-ext#0"], w.queue(w.b)
    assert w.queue(w.b)[0]["from"] == "a-master#1"
    assert w.injections() == [], f"주입 0 이어야 한다(B 확장 좌석 = pane 0): {w.injections()}"


# ── ⓑ 다른 루트 «일반 좌석» — 주입 1건 · 그 경로는 «B 루트» mbox.sh (A 경로 주입 0)
def test_case_b_bridged_send_to_plain_seat_injects_only_from_receiver_root(w: World) -> None:
    got = w.mbox(w.a, "send", "b-general#0", "a-master#1", "루트 넘는 쪽지 — 시험 본문")
    assert got.returncode == 0, got.stdout + got.stderr
    assert "BRIDGED" in got.stdout and "doorbell=bridged" in got.stdout, got.stdout
    inj = w.injections()
    assert len(inj) == 1, f"받는 루트 1회만 주입해야 한다: {inj}"
    assert str(w.b / ".fable-team/comm/mbox.sh") in inj[0], inj[0]
    assert str(w.a / ".fable-team/comm/mbox.sh") not in inj[0], inj[0]
    assert [r["to"] for r in w.queue(w.b)] == ["b-general#0"], w.queue(w.b)


# ── ⓒ 보낸 쪽 inbox 적재 0 · 깨움 예산 차감 0(예약했으면 되돌림) · 그 seq 는 «받는 루트 큐» 번호
def test_case_c_sender_inbox_and_wake_budget_untouched(w: World) -> None:
    got = w.mbox(w.a, "send", "b-general#0", "a-master#1", "루트 넘는 쪽지 — 시험 본문")
    assert got.returncode == 0, got.stdout + got.stderr
    bridged_seq = [t for t in got.stdout.split() if t.startswith("seq=")]
    assert bridged_seq, got.stdout
    assert [str(r["seq"]) for r in w.queue(w.b)] == [bridged_seq[0].split("=", 1)[1]], w.queue(w.b)
    assert w.ingests(w.a) == [], f"보낸 쪽 inbox 적재 0: {w.ingests(w.a)}"
    assert w.ingests(w.b), "받는 쪽은 자기 규칙대로 적재한다"
    assert w.budget_n(w.a, "b-general#0") == 0, "울린 건 받는 루트다 — 보낸 쪽 예산은 되돌려야 한다"
    held = list((w.a / ".fable-team/state/doorbell-held").glob("*")) if (w.a / ".fable-team/state/doorbell-held").is_dir() else []
    assert held == [], f"보낸 쪽에 억제분을 적으면 안 된다: {held}"
    # ⓒ-2 예약 없는 sent(--urgent) — 되돌릴 차감이 없다(보낸 쪽 장부가 줄면 안 된다 · arch#277 반례)
    for _ in range(2):
        assert "reserved" in w.mbox(w.a, "budget", "reserve", "b-general#0", "send").stdout
    got2 = w.mbox(w.a, "send", "b-general#0", "a-master#1", "루트 넘는 쪽지 — urgent", "--urgent")
    assert "doorbell=bridged" in got2.stdout, got2.stdout + got2.stderr
    assert w.budget_n(w.a, "b-general#0") == 2, "--urgent = 예산 밖 — 보낸 쪽 장부를 되돌리면 안 된다"
    # ⓒ-3 머리 [긴급] 도 예산 밖(게이트가 예약을 안 한다) — 같은 규칙
    for _ in range(2):
        assert "reserved" in w.mbox(w.a, "budget", "reserve", "b-ext#0", "send").stdout
    got3 = w.mbox(w.a, "send", "b-ext#0", "a-master#1", "[긴급] 루트 넘는 쪽지")
    assert "doorbell=bridged" in got3.stdout, got3.stdout + got3.stderr
    assert w.budget_n(w.a, "b-ext#0") == 2, "[긴급] 머리 = 예산 밖 — 장부를 되돌리면 안 된다"


# ── ⓓ 같은 루트 send = 지금 동작 그대로(큐 적재 · 주입 1회 · inbox 적재 · 예산 차감)
def test_case_d_same_root_send_is_unchanged(w: World) -> None:
    got = w.mbox(w.a, "send", "a-nano#0", "a-master#1", "같은 루트 쪽지 — 시험 본문")
    assert got.returncode == 0, got.stdout + got.stderr
    assert "QUEUED" in got.stdout and "BRIDGED" not in got.stdout, got.stdout
    assert "doorbell=bridged" not in got.stdout, got.stdout
    assert [r["to"] for r in w.queue(w.a)] == ["a-nano#0"], w.queue(w.a)
    inj = w.injections()
    assert len(inj) == 1 and str(w.a / ".fable-team/comm/mbox.sh") in inj[0], inj
    assert len(w.ingests(w.a)) == 1, w.ingests(w.a)
    assert w.budget_n(w.a, "a-nano#0") == 1, "같은 루트 = 깨움 1회 = 차감 1회 그대로"


# ── ⓔ relay 로 다른 루트에 보낼 때도 ⓐ~ⓒ 와 같다
def test_case_e_relay_to_other_root_is_also_bridged(w: World) -> None:
    src = write(w.tmp / "relay-src.md", "r1562 relay 본문\n")
    got = w.mbox(w.a, "relay", "b-general#0", "a-master#1", str(src), "전문은 파일 — 시험 본문")
    assert got.returncode == 0, got.stdout + got.stderr
    assert "BRIDGED" in got.stdout and "doorbell=bridged" in got.stdout, got.stdout
    assert w.queue(w.a) == [], w.queue(w.a)
    assert [r["to"] for r in w.queue(w.b)] == ["b-general#0"], w.queue(w.b)
    inj = w.injections()
    assert len(inj) == 1 and str(w.a / ".fable-team/comm/mbox.sh") not in inj[0], inj
    assert w.ingests(w.a) == [], w.ingests(w.a)
    assert w.budget_n(w.a, "b-general#0") == 0, "relay 도 보낸 쪽 예산은 되돌린다"


# ── ⓕ FT_MBOX_BRIDGED=1 자식 안의 send 는 지금처럼 «자기 경로» 로 판정(무한 왕복 0)
def test_case_f_child_env_does_not_rebridge(w: World) -> None:
    got = w.mbox(w.a, "send", "b-general#0", "a-master#1", "자식 안 send — 시험 본문", FT_MBOX_BRIDGED="1")
    assert got.returncode == 0, got.stdout + got.stderr
    assert "BRIDGED" not in got.stdout and "QUEUED" in got.stdout, got.stdout
    assert [r["to"] for r in w.queue(w.a)] == ["b-general#0"], w.queue(w.a)
    assert w.queue(w.b) == [], "자식은 다리를 다시 타지 않는다"
