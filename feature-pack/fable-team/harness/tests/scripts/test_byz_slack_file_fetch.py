"""byz_slack_file_fetch — 가짜 Slack(files.info + 다운로드)으로 저장 규칙·거부·크기 불일치·시간 상한을 시험한다(실 Slack 0)."""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pytest

KIT = Path(__file__).resolve().parents[3] / "harness" / "kit" / "slack-mirror"
SCRIPT = KIT / "byz_slack_file_fetch.py"
MIB = 1024 * 1024
sys.path.insert(0, str(KIT))
import byz_slack_file_fetch as ff  # noqa: E402


class Fake:
    def __init__(self) -> None:
        self.files: dict[str, dict] = {}  # id -> {"info": {...}, "bytes": b"..."}
        outer = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, format: str, *args: object) -> None:  # noqa: A002
                pass

            def do_GET(self) -> None:
                u = urlparse(self.path)
                if u.path.endswith("files.info"):
                    f = outer.files[parse_qs(u.query)["file"][0]]
                    raw = json.dumps({"ok": True, "file": {**f["info"], "url_private_download": f"{outer.base}/dl/{f['info']['id']}"}}).encode()
                else:
                    raw = outer.files[u.path.rsplit("/", 1)[1]]["bytes"]
                self.send_response(200)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        self.srv = HTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_port}"

    def add(self, fid: str, name: str, body: bytes, mime: str = "text/markdown", size: int | None = None) -> None:
        self.files[fid] = {"info": {"id": fid, "name": name, "mimetype": mime, "size": len(body) if size is None else size}, "bytes": body}


@pytest.fixture
def fake(tmp_path: Path):
    (tmp_path / "tok.env").write_text("YOONHWAN_BOT_TOKEN=xoxp-test\n", encoding="utf-8")
    f = Fake()
    yield f
    f.srv.shutdown()


def fetch(fake: Fake, tmp_path: Path, fid: str):
    return subprocess.run([sys.executable, str(SCRIPT), "--file-id", fid, "--root", str(tmp_path), "--token-file", str(tmp_path / "tok.env"),
                           "--api-base", fake.base], capture_output=True, text=True, timeout=60)


def saved(tmp_path: Path) -> list[Path]:
    return [p for p in (tmp_path / ".fable-team" / "state" / "desk-files").rglob("*") if p.is_file()]


def test_markdown_is_saved_under_dated_dir_with_cleaned_name(fake: Fake, tmp_path: Path):
    fake.add("F1", "메모 v1.md", "안녕 desk".encode())
    r = fetch(fake, tmp_path, "F1")
    (p,) = saved(tmp_path)
    assert r.returncode == 0 and r.stdout.startswith(f"SAVED {p} bytes=") and p.name.startswith("F1-") and p.name.endswith(".md")
    assert p.read_bytes() == "안녕 desk".encode() and "xoxp" not in r.stdout + r.stderr and "/dl/" not in r.stdout + r.stderr


def test_pdf_is_refused_with_rc3_and_terminal_hint(fake: Fake, tmp_path: Path):
    fake.add("F2", "표.pdf", b"%PDF-1.4", mime="application/pdf")
    r = fetch(fake, tmp_path, "F2")
    assert r.returncode == 3 and "터미널에서 직접 열어 주세요: 표.pdf" in r.stdout and saved(tmp_path) == []


def test_one_byte_over_one_mib_is_refused_and_exactly_one_mib_is_saved(fake: Fake, tmp_path: Path):
    fake.add("F3", "big.txt", b"a" * (MIB + 1), mime="text/plain")
    assert fetch(fake, tmp_path, "F3").returncode == 3 and saved(tmp_path) == []
    fake.add("F4", "edge.txt", b"a" * MIB, mime="text/plain")
    assert fetch(fake, tmp_path, "F4").returncode == 0 and len(saved(tmp_path)) == 1


def test_path_traversal_name_is_cleaned_and_stays_inside_the_dated_dir(fake: Fake, tmp_path: Path):
    fake.add("F5", "../../x.md", b"x")
    assert fetch(fake, tmp_path, "F5").returncode == 0
    (p,) = saved(tmp_path)
    assert "/" not in p.name and p.parent.parent == tmp_path / ".fable-team" / "state" / "desk-files"
    assert ff.safe_name("a" * 200) == "a" * 80 and ff.safe_name("\0/..") == "__.." and ff.safe_name("") == "file"


def test_byte_count_differing_from_size_field_saves_nothing(fake: Fake, tmp_path: Path):
    fake.add("F6", "lie.md", b"twelve bytes", size=5)
    r = fetch(fake, tmp_path, "F6")
    assert r.returncode == 1 and "ERROR" in r.stderr and saved(tmp_path) == []


def test_text_named_file_with_binary_content_saves_nothing(fake: Fake, tmp_path: Path):
    fake.add("F7", "fake.md", b"\x00\x01binary", mime="application/pdf")
    assert fetch(fake, tmp_path, "F7").returncode == 1 and saved(tmp_path) == []


JPEG_HEAD = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00"


def test_two_mib_jpeg_is_saved_as_image_with_nul_bytes_kept(fake: Fake, tmp_path: Path):
    body = JPEG_HEAD + b"\x00" * (2 * MIB - len(JPEG_HEAD))
    fake.add("F8", "x.jpg", body, mime="image/jpeg")
    r = fetch(fake, tmp_path, "F8")
    (p,) = saved(tmp_path)
    assert r.returncode == 0 and r.stdout.strip() == f"SAVED {p} bytes={2 * MIB} kind=image" and p.read_bytes() == body
    assert "xoxp" not in r.stdout + r.stderr and "/dl/" not in r.stdout + r.stderr


@pytest.mark.parametrize(("name", "mime", "head"), [
    ("a.png", "image/png", b"\x89PNG\r\n\x1a\n"), ("b.gif", "image/gif", b"GIF87a"), ("c.gif", "image/gif", b"GIF89a"),
    ("d.webp", "image/webp", b"RIFF\x10\x00\x00\x00WEBP"), ("photo", "image/png", b"\x89PNG\r\n\x1a\n"), ("e.JPEG", "", JPEG_HEAD)])
def test_each_image_kind_is_saved_by_extension_or_mimetype(fake: Fake, tmp_path: Path, name: str, mime: str, head: bytes):
    fake.add("F9", name, head + b"rest", mime=mime)
    r = fetch(fake, tmp_path, "F9")
    assert r.returncode == 0 and r.stdout.rstrip().endswith("kind=image") and len(saved(tmp_path)) == 1


def test_image_named_file_whose_bytes_are_an_html_error_page_saves_nothing(fake: Fake, tmp_path: Path):
    fake.add("F10", "x.png", b"<!DOCTYPE html><html>login</html>", mime="image/png")
    r = fetch(fake, tmp_path, "F10")
    assert r.returncode == 1 and "ERROR" in r.stderr and saved(tmp_path) == []
    assert "xoxp" not in r.stdout + r.stderr and "/dl/" not in r.stdout + r.stderr


def test_image_over_the_image_cap_is_refused_and_exactly_the_cap_is_saved(fake: Fake, tmp_path: Path):
    fake.add("F11", "huge.png", b"\x89PNG", mime="image/png", size=ff.IMAGE_MAX_BYTES + 1)
    r = fetch(fake, tmp_path, "F11")
    assert ff.IMAGE_MAX_BYTES == 10 * MIB and r.returncode == 3 and "터미널에서 직접 열어 주세요: huge.png" in r.stdout and saved(tmp_path) == []
    fake.add("F12", "edge.png", b"\x89PNG\r\n\x1a\n" + b"a" * (ff.IMAGE_MAX_BYTES - 8), mime="image/png")
    assert fetch(fake, tmp_path, "F12").returncode == 0 and len(saved(tmp_path)) == 1


def test_image_byte_count_differing_from_size_field_saves_nothing(fake: Fake, tmp_path: Path):
    fake.add("F13", "lie.jpg", JPEG_HEAD + b"more", mime="image/jpeg", size=5)
    assert fetch(fake, tmp_path, "F13").returncode == 1 and saved(tmp_path) == []


def test_text_output_line_says_kind_text(fake: Fake, tmp_path: Path):
    fake.add("F14", "n.txt", b"hi", mime="text/plain")
    r = fetch(fake, tmp_path, "F14")
    assert r.returncode == 0 and r.stdout.rstrip().endswith("bytes=2 kind=text")


@pytest.mark.parametrize(("name", "mime"), [("a.zip", "application/zip"), ("b.svg", "image/svg+xml"), ("c.heic", "image/heic")])
def test_other_kinds_stay_refused_with_rc3(fake: Fake, tmp_path: Path, name: str, mime: str):
    fake.add("F15", name, b"x", mime=mime)
    r = fetch(fake, tmp_path, "F15")
    assert r.returncode == 3 and f"터미널에서 직접 열어 주세요: {name}" in r.stdout and saved(tmp_path) == []


def test_deadline_for_one_mib_is_within_the_batch_ceiling():
    assert ff.deadline_s(MIB) == 10.5 and ff.deadline_s(0) <= 70 and ff.deadline_s(10**9) == 70.0


class _Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


class _Resp:
    def __init__(self, body: bytes) -> None:
        self.body = body

    def __enter__(self) -> "_Resp":
        return self

    def __exit__(self, *exc: object) -> None:
        return None

    def read(self, n: int) -> bytes:
        out, self.body = self.body[:n], self.body[n:]
        return out


def _patched(monkeypatch: pytest.MonkeyPatch, first_elapsed: float):
    clock, calls = _Clock(), []

    def fake_urlopen(req: object, timeout: float):
        calls.append(timeout)
        if len(calls) == 1:
            clock.now += first_elapsed
            raise OSError("boom")
        return _Resp(b"hello")

    monkeypatch.setattr(ff.time, "monotonic", clock)
    monkeypatch.setattr(ff.urllib.request, "urlopen", fake_urlopen)
    return calls


def test_retry_timeout_is_capped_by_the_remaining_total_deadline(monkeypatch: pytest.MonkeyPatch):
    calls = _patched(monkeypatch, first_elapsed=6.0)  # 총 마감(크기 5 B → 10.5 s) 중 6 s 를 쓰고 실패
    assert ff.download("http://x/dl", "t", 5) == b"hello"
    assert len(calls) == 2 and calls[1] <= 4.5 + 1e-9


def test_no_retry_when_the_total_deadline_is_already_spent(monkeypatch: pytest.MonkeyPatch):
    calls = _patched(monkeypatch, first_elapsed=11.0)
    with pytest.raises(ff.lib.MirrorError):
        ff.download("http://x/dl", "t", 5)
    assert len(calls) == 1
