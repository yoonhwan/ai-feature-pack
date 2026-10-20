"""file_guard — 슬랙 첨부 파일 게시 «전» 검사 (R231a · 설계 DESIGN-r231-desk-slack-files §0·§1).

글 게시 «전» 붙일 파일 전부를 post_guard 로 본다(파일 이름 + 내용). 하나라도 걸리면 PostGuardError → 글·파일 모두 게시 0.
종류·내용 판정은 «실제 대상»(심링크 해석 뒤) 기준이다. 사람 채널(`human` 또는 명부·env 채널)은 별칭·대상 둘 다 텍스트 계열만 허용한다.
비사람 채널은 대상이 텍스트 계열이면 내용을 검사하고, 그 밖(보드 PDF 등)은 실재만 본다.
검사한 바이트를 `Checked.data` 로 돌려준다 — 업로드는 원래 경로를 다시 열지 않고 그 바이트만 쓴다(검사~전송 사이 교체 차단). 오류 문구에 내용 인용 0.
"""
import mimetypes
from dataclasses import dataclass
from pathlib import Path

from post_guard import PostGuardError, check, human_channels

TEXT_SUFFIXES = {".md", ".txt", ".csv", ".json", ".yaml", ".yml", ".log"}
# 확장자로 정하는 내용 형식(magazine_attach 와 같은 꼴) — `mimetypes.guess_type` 표가 파이썬 판마다 달라
# (3.11 은 `.md` 를 모름 → application/octet-stream) 같은 파일이 다른 형식으로 올라가는 것을 막는다.
CONTENT_TYPES = {
    ".md": "text/markdown",
    ".html": "text/html",
    ".pdf": "application/pdf",
    ".txt": "text/plain",
    ".json": "application/json",
}
MAX_BYTES = 1 << 20


@dataclass(frozen=True)
class Checked:
    name: str
    data: bytes
    content_type: str


def _reject(name: str, why: str) -> None:
    raise PostGuardError(f"첨부 거부(file_guard) — {name}: {why} · 게시 0")


def _content_type(name: str) -> str:
    """표에 있는 확장자는 표 값 · 없으면 지금처럼 추측하고, 추측도 없으면 octet-stream."""
    return CONTENT_TYPES.get(Path(name).suffix.lower()) or mimetypes.guess_type(name)[0] or "application/octet-stream"


def _decode(data: bytes, name: str) -> str:
    if len(data) > MAX_BYTES:
        _reject(name, "1 MiB 초과")
    if b"\x00" in data:
        _reject(name, "NUL 바이트(UTF-16 등 텍스트 아님) — 내용 검사 불가")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        _reject(name, "UTF-8 아님 — 내용 검사 불가")
    return ""


def check_files(paths: list[str], channel: str, *, human: bool = False) -> list[Checked]:
    """파일마다 실재·종류·크기·인코딩·post_guard. 첫 거부에서 PostGuardError. 통과 시 검사한 바이트 목록."""
    strict = human or channel in human_channels()
    out: list[Checked] = []
    for i, f in enumerate(paths, 1):
        p = Path(f)
        try:
            real = p.resolve(strict=True)
        except (OSError, RuntimeError):
            _reject(f"{i}번째 파일", "실재하는 파일이 아님")
        try:
            check(f"{p.name}\n{real.name}", channel, human=human)
        except PostGuardError as e:  # 이름 자체가 비밀일 수 있어 문구에는 순번만
            _reject(f"{i}번째 파일 이름", str(e))
        if not real.is_file():
            _reject(p.name, "일반 파일이 아님")
        real_text = real.suffix.lower() in TEXT_SUFFIXES
        if strict and not (real_text and p.suffix.lower() in TEXT_SUFFIXES):
            _reject(p.name, "내용 검사 불가 종류(사람 채널은 별칭·대상 모두 .md .txt .csv .json .yaml .yml .log 만)")
        data = real.read_bytes()
        if real_text:
            body = _decode(data, p.name)
            try:
                check(f"{p.name}\n{real.name}\n{body}", channel, human=human)
            except PostGuardError as e:
                _reject(p.name, str(e))
        out.append(Checked(p.name, data, _content_type(p.name)))
    return out
