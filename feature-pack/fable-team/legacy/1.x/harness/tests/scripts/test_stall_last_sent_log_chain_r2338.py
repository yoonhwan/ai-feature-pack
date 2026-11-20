"""r2338 — ft_stall_scan._last_sent: 마지막 보낸 글을 보낸 글 로그 «사슬 전체»(mailbox.log.jsonl → .1 → .2 → .3)에서 찾는다.

① log 앞자리(뒤 남 글 4MB 넘음) ② .1 에만 ③ .3 에만 ④ log 옛 글 · 큐에 더 큰 seq ⑤ log 끝 4MB 안
⑥ 어디에도 없음 ⑦ .1 없음 · .2 있음 ⑧ 1MB 조각 경계에 걸친 줄 ⑨ 깨진 줄 섞임 ⑩ 20MB 사슬 · 맞음 0 = 1초 안
⑪ log 안 같은 좌석 2통(앞 [다음 없음] · 뒤 다른 글) = 뒤(큰 seq) 글.
⑫ 마지막 진짜 [다음 없음](seq N) 뒤에 같은 from 의 bridged 거울 줄(seq 0 · 다른 본문) → [다음 없음] 본문(G2 = 맞음은 seq>0 줄만).
M1 4MB 창 되돌림 → ① FAIL · M2 회전 사본 안 봄 → ② FAIL · M3 조각 이어 붙이기 지움 → ⑧ FAIL
M4 큐 안 봄 → ④ FAIL · M5 첫 맞음 대신 앞(옛) 맞음 → ⑪ FAIL · M6 seq>0 거름 지움 → ⑫ FAIL
(변이는 R2338_BIN 사본으로 · 원본 대조 1회)
R2338_BIN = 시험할 bin 폴더(기본 kit · 변이 사본을 넣어 위 FAIL 을 본다).
격리 = 임시 comm 폴더만(실 우편함 0) · sleep 0 · 시험 1개 70초 안.
"""
import json
import os
import sys
import time
from pathlib import Path

import pytest

from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2338_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
MB = 1 << 20
BIG = 4 * MB
ME = "t1-master#1"
NAMES = {ME}
OTHER = "t1-nano#0"


def _import_scan(bin_dir: Path = BIN):
    if str(bin_dir) not in sys.path:
        sys.path.insert(0, str(bin_dir))
    sys.modules.pop("ft_stall_scan", None)
    import ft_stall_scan as m  # noqa: PLC0415 — 사본 bin 을 그때그때 import(변이 시험)

    return m


def last_sent(comm: Path, bin_dir: Path = BIN) -> str:
    return _import_scan(bin_dir)._last_sent(comm, NAMES)


def row(seq: int, frm: str = OTHER, body: str = "남 글") -> str:
    return json.dumps({"seq": seq, "from": frm, "to": "x", "body": body}, ensure_ascii=False)


def pad(path: Path, size: int = 0, n: int = 0, seq0: int = 900000) -> int:
    """남 글 덧줄 — size 바이트를 넘길 때까지(n>0 이면 n 줄) 덧붙인다. 쓴 바이트."""
    wrote, i = 0, 0
    with path.open("a", encoding="utf-8") as fh:
        while i < n or wrote < size:
            s = row(seq0 + i) + "\n"
            fh.write(s)
            wrote += len(s.encode("utf-8"))
            i += 1
    return wrote


def log(comm: Path, rows: list[str], suffix: str = "") -> Path:
    p = comm / f"mailbox.log.jsonl{suffix}"
    p.write_text("".join(s + "\n" for s in rows), encoding="utf-8")
    return p


@pytest.fixture
def comm(tmp_path: Path) -> Path:
    d = tmp_path / "comm"
    d.mkdir()
    return d


def test_log_head_behind_four_mb(comm: Path) -> None:
    """① 마지막 보낸 글이 log 앞자리 · 뒤에 남 글 4MB 넘음 → 그 본문(기준판 = 4MB 창 = '' → Red)."""
    pad(log(comm, [row(500, ME, "[다음 없음] 오래 전 글")]), size=BIG + MB)
    assert last_sent(comm) == "[다음 없음] 오래 전 글"


@pytest.mark.parametrize("suffix", [".1", ".2", ".3"], ids=["② .1 에만", "⑦ .2 에만(.1 없음)", "③ .3 에만"])
def test_rotated_copy_only(comm: Path, suffix: str) -> None:
    """②③⑦ 보낸 글이 회전 사본에만 있어도 그 본문 — 없는 자리는 건너뛴다(⑦)."""
    log(comm, [row(900000)])
    log(comm, [row(501, ME, f"[다음 없음] 회전 {suffix} 글")], suffix)
    assert last_sent(comm) == f"[다음 없음] 회전 {suffix} 글"


def test_queue_newer_seq_wins(comm: Path) -> None:
    """④ log 에 옛 글 · 큐(mailbox.jsonl)에 더 큰 seq → 큐 본문."""
    log(comm, [row(500, ME, "[다음 없음] 로그 옛 글")])
    (comm / "mailbox.jsonl").write_text(row(800, ME, "[다음 없음] 큐 새 글") + "\n", encoding="utf-8")
    assert last_sent(comm) == "[다음 없음] 큐 새 글"


def test_within_tail_unchanged(comm: Path) -> None:
    """⑤ log 끝 4MB 안 → 지금과 같은 본문(회귀)."""
    pad(log(comm, [row(500, ME, "[다음 없음] 방금 글")]), n=3)
    assert last_sent(comm) == "[다음 없음] 방금 글"


def test_nowhere_is_empty(comm: Path) -> None:
    """⑥ 어디에도 없음 → ''(«판단 못 함»)."""
    pad(log(comm, [row(500, OTHER, "남의 글")]), n=3)
    (comm / "mailbox.jsonl").write_text(row(900001, OTHER) + "\n", encoding="utf-8")
    assert last_sent(comm) == ""


def test_line_across_chunk_boundary(comm: Path) -> None:
    """⑧ 맞는 줄이 1MB 조각 경계에 걸침 → 바른 본문(조각 이어 붙이기)."""
    body = "[다음 없음] 경계 " + "가" * 1500
    target = row(500, ME, body) + "\n"
    p = comm / "mailbox.log.jsonl"
    with p.open("w", encoding="utf-8") as fh:
        fh.write(row(1) + "\n")
        fh.write(target)
        tail, i = 0, 0
        while tail < MB - len(target.encode("utf-8")) // 2:  # 경계(size-1MB)가 target 안에 오게
            s = row(900000 + i) + "\n"
            fh.write(s)
            tail += len(s.encode("utf-8"))
            i += 1
    assert last_sent(comm) == body


def test_broken_line_skipped(comm: Path) -> None:
    """⑨ 깨진 줄(JSON 아님) 섞임 → 건너뛰고 앞 줄에서 찾음."""
    p = log(comm, [row(500, ME, "[다음 없음] 깨진 줄 뒤 글")])
    with p.open("a", encoding="utf-8") as fh:
        fh.write('{"seq": 700, "from": "t1-master#1", "bo\n')
        fh.write("\x01깨진 줄\n")
    pad(p, size=BIG + MB)
    assert last_sent(comm) == "[다음 없음] 깨진 줄 뒤 글"


def test_chain_20mb_no_hit_under_1s(comm: Path) -> None:
    """⑩ 사슬 20MB · 맞음 0 → '' · 1초 안(외부 호출 0)."""
    for suffix in ("", ".1", ".2", ".3"):
        pad(log(comm, [row(1)], suffix), size=5 * MB)
    m = _import_scan()
    t0 = time.perf_counter()
    got = m._last_sent(comm, NAMES)
    took = time.perf_counter() - t0
    assert got == ""
    assert took < 1.0, f"{took:.2f}s"


def test_two_sent_same_seat_takes_newer(comm: Path) -> None:
    """⑪ log 안 같은 좌석 글 2통 → 뒤(큰 seq) 글 본문."""
    pad(log(comm, [row(500, ME, "[다음 없음] 앞 글"), row(700, ME, "일하는 중 글")]), n=2)
    assert last_sent(comm) == "일하는 중 글"


def test_mirror_row_seq_zero_skipped(comm: Path) -> None:
    """⑫ 마지막 진짜 글이 seq N [다음 없음] · 그 뒤 같은 좌석 bridged 거울 줄(seq 0) → [다음 없음] 본문."""
    pad(log(comm, [row(500, ME, "[다음 없음] 쉼"), row(0, ME, "[거울] 옛 글")]), n=2)
    assert last_sent(comm) == "[다음 없음] 쉼"
