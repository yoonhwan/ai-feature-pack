"""mirror_inbound._rows 파싱 캐시 (r624) — 파일이 안 바뀌면 다시 읽지 않고, 바뀌거나 회전하면 새 내용을 본다. 임시 comm 폴더만(실 슬랙·mbox 0)."""
import json
import os
import sys
from pathlib import Path

import pytest

KIT = Path(__file__).resolve().parents[2] / "kit" / "slack-mirror"
sys.path.insert(0, str(KIT))
import mirror_inbound as mi  # noqa: E402

TO = "byz-desk-claude#1"
NAMES = ("mailbox.jsonl", "mailbox.log.jsonl", "mailbox.log.jsonl.1")


def _row(tok: str, to: str = TO) -> str:
    return json.dumps({"from": mi.FROM, "to": to, "body": f"[{mi.FROM}->{to}] 글\n({tok})"}, ensure_ascii=False)


def _write(p: Path, *toks: str) -> None:
    p.write_text("".join(_row(t) + "\n" for t in toks), encoding="utf-8")


@pytest.fixture
def comm(tmp_path: Path) -> Path:
    getattr(mi, "_ROWS_CACHE", {}).clear()
    for i, name in enumerate(NAMES):
        _write(tmp_path / name, f"slack:1.{i}a:{TO}", f"slack:1.{i}b:{TO}")
    return tmp_path


@pytest.fixture
def reads(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    seen: list[str] = []
    real = Path.read_text

    def counting(self: Path, *a, **k):
        seen.append(self.name)
        return real(self, *a, **k)

    monkeypatch.setattr(Path, "read_text", counting)
    return seen


def test_a_same_files_read_once_each(comm: Path, reads: list[str]):
    """ⓐ 같은 파일로 marker_seen 10번 — 파일 읽기는 파일당 1번(옛 판 = 30번)."""
    for _ in range(10):
        assert mi.marker_seen(comm, "slack:9.9:none", TO) is False
    assert sorted(reads) == sorted(NAMES), f"읽기 {len(reads)}번: {reads}"


def test_a2_hit_returns_same_answers(comm: Path, reads: list[str]):
    """ⓐ' 캐시로 답한 판정이 처음 판정과 같다 — marker_seen·queue_has·queue_len."""
    first = (mi.marker_seen(comm, f"slack:1.2b:{TO}", TO), mi.queue_has(comm, f"slack:1.0a:{TO}", TO), mi.queue_len(comm, TO))
    again = (mi.marker_seen(comm, f"slack:1.2b:{TO}", TO), mi.queue_has(comm, f"slack:1.0a:{TO}", TO), mi.queue_len(comm, TO))
    assert first == again == (True, True, 2)
    assert mi.queue_has(comm, f"slack:1.1a:{TO}", TO) is False  # 사본 로그의 흔적은 큐가 아니다
    assert sorted(reads) == sorted(NAMES)


def test_b_appended_line_is_seen(comm: Path, reads: list[str]):
    """ⓑ 줄 덧붙임(mtime·크기 바뀜) → 다음 호출이 새 토큰을 찾는다(낡은 값 0)."""
    tok = f"slack:2.0:{TO}"
    assert mi.marker_seen(comm, tok, TO) is False
    with (comm / "mailbox.log.jsonl").open("a", encoding="utf-8") as f:
        f.write(_row(tok) + "\n")
    assert mi.marker_seen(comm, tok, TO) is True
    assert reads.count("mailbox.log.jsonl") == 2 and reads.count("mailbox.jsonl") == 1


def test_b2_same_size_rewrite_is_seen(comm: Path):
    """ⓑ' 크기가 같은 다시 쓰기라도 mtime 이 바뀌면 새 내용을 본다."""
    q = comm / "mailbox.jsonl"
    assert mi.queue_has(comm, f"slack:1.0a:{TO}", TO) is True
    st = q.stat()
    _write(q, f"slack:1.0x:{TO}", f"slack:1.0y:{TO}")  # 토큰 길이 같음 = 크기 같음
    assert q.stat().st_size == st.st_size
    os.utime(q, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000))
    assert mi.queue_has(comm, f"slack:1.0a:{TO}", TO) is False
    assert mi.queue_has(comm, f"slack:1.0x:{TO}", TO) is True


def test_c_rotation_both_names_fresh(comm: Path):
    """ⓒ 회전(mailbox.log.jsonl → .1 · 새 빈 파일) → 두 이름 모두 새 내용 · 없어진 파일은 건너뛴다."""
    old_log, old_one = f"slack:1.1a:{TO}", f"slack:1.2a:{TO}"
    assert mi.marker_seen(comm, old_log, TO) and mi.marker_seen(comm, old_one, TO)
    (comm / "mailbox.log.jsonl").replace(comm / "mailbox.log.jsonl.1")
    (comm / "mailbox.log.jsonl").write_text("", encoding="utf-8")
    assert mi.marker_seen(comm, old_log, TO) is True  # 이제 .1 에 있다
    assert mi.marker_seen(comm, old_one, TO) is False  # 옛 .1 은 덮였다
    new = f"slack:3.0:{TO}"
    with (comm / "mailbox.log.jsonl").open("a", encoding="utf-8") as f:
        f.write(_row(new) + "\n")
    assert mi.marker_seen(comm, new, TO) is True
    (comm / "mailbox.log.jsonl.1").unlink()
    assert mi.marker_seen(comm, old_log, TO) is False  # 없는 파일 = 건너뜀(오류 0)
    assert mi.marker_seen(comm, new, TO) is True
