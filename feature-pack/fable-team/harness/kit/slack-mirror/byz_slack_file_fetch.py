#!/usr/bin/env python3
"""byz_slack_file_fetch — 슬랙 파일 1개를 desk 가 읽도록 로컬에 받는다(텍스트 계열 ≤ 1 MiB · 이미지 png·jpg·gif·webp ≤ 10 MiB). 정본: DESIGN-r231-desk-slack-files-20261015.md §2·§5.

받은 내용은 미검증 입력 — 자료로만 읽는다. 토큰·url_private* 는 출력·로그·오류문에 싣지 않는다.
"""
import argparse
import datetime
import http.client
import math
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import mirror_lib as lib

MAX_BYTES = 1024 * 1024
IMAGE_MAX_BYTES = 10 * MAX_BYTES
TEXT_EXT = (".md", ".txt", ".csv", ".json", ".yaml", ".log")
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp")
IMAGE_MIME = ("image/png", "image/jpeg", "image/gif", "image/webp")
LAUNCH_S, TOTAL_CAP_S = 3.5, 70.0  # 크기 아는 배치(판정 1375): 고정비 + 7 s × ceil(크기/기준량), 재시도 포함 총 마감 70 s
NOT_TEXT_RC = 3


def deadline_s(size: int) -> float:
    return min(LAUNCH_S + lib.EXTERNAL_CALL_TIMEOUT_S * max(1, math.ceil(size / MAX_BYTES)), TOTAL_CAP_S)


def safe_name(name: object) -> str:
    return re.sub(r"[^A-Za-z0-9._-]", "_", str(name))[:80] or "file"


def kind_of(info: dict[str, object]) -> str | None:
    """text(지금 그대로) · image(png·jpg·gif·webp) · None(나머지 — 받지 않는다)."""
    name, mime = str(info.get("name", "")).lower(), str(info.get("mimetype", ""))
    if name.endswith(TEXT_EXT) or mime.startswith("text/"):
        return "text"
    if name.endswith(IMAGE_EXT) or mime in IMAGE_MIME:
        return "image"
    return None


def is_image_bytes(data: bytes) -> bool:
    return (data.startswith((b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"GIF87a", b"GIF89a"))
            or (data[:4] == b"RIFF" and data[8:12] == b"WEBP"))


def _open(req: urllib.request.Request, start: float, cap: float) -> http.client.HTTPResponse:
    """첫 바이트(응답 헤더) 전 실패만 1회 재시도 — 매 시도의 timeout 은 남은 총 마감을 넘지 않고, 남은 시간이 0이면 시도하지 않는다."""
    for attempt in range(lib.MAX_RETRIES + 1):
        remaining = cap - (time.monotonic() - start)
        if remaining <= 0:
            raise lib.MirrorError("다운로드 총 마감 초과")
        try:
            return urllib.request.urlopen(req, timeout=min(lib.EXTERNAL_CALL_TIMEOUT_S, remaining))
        except (urllib.error.URLError, OSError) as e:
            if attempt == lib.MAX_RETRIES:
                raise lib.MirrorError(f"다운로드 시작 실패: {type(e).__name__}") from e
    raise lib.MirrorError("다운로드 시작 실패")


def download(url: str, token: str, size: int, kind: str = "text") -> bytes:
    """총 마감 안에서만 읽는다 — 초과·크기 불일치·텍스트의 NUL(이진)·이미지의 머리 바이트 불일치는 raise(부분 저장 0)."""
    start, cap = time.monotonic(), deadline_s(size)
    data = b""
    with _open(urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"}), start, cap) as resp:
        while chunk := resp.read(65536):
            data += chunk
            if len(data) > size or time.monotonic() - start > cap:
                raise lib.MirrorError("다운로드가 크기 필드를 넘거나 총 마감을 넘었어요")
    if len(data) != size or (kind == "text" and b"\0" in data):
        raise lib.MirrorError(f"받은 바이트({len(data)})가 크기 필드({size})와 다르거나 텍스트가 아니에요")
    if kind == "image" and not is_image_bytes(data):
        raise lib.MirrorError("받은 바이트 머리가 png·jpg·gif·webp 가 아니에요")
    return data


def fetch(args: argparse.Namespace) -> int:
    token = lib.read_token(Path(args.token_file).expanduser())
    info = lib.api_call(args.api_base, token, "files.info", {"file": args.file_id}, get=True).get("file")
    if not isinstance(info, dict):
        raise lib.MirrorError("files.info 응답에 file 없음")
    size, kind = info.get("size"), kind_of(info)
    if kind is None or not isinstance(size, int) or size > (IMAGE_MAX_BYTES if kind == "image" else MAX_BYTES):
        print(f"터미널에서 직접 열어 주세요: {' '.join(str(info.get('name', '?')).split())}")
        return NOT_TEXT_RC
    data = download(str(info.get("url_private_download", "")), token, size, kind)
    out = Path(args.root) / ".fable-team/state/desk-files" / datetime.date.today().isoformat() / f"{safe_name(info.get('id'))}-{safe_name(info.get('name'))}"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"SAVED {out} bytes={len(data)} kind={kind}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--file-id", required=True)
    ap.add_argument("--root", default=".", help="desk 작업 루트 — 저장 위치 <root>/.fable-team/state/desk-files/")
    ap.add_argument("--token-file", default="~/.hermes/secrets/yoonhwan_bot.env")
    ap.add_argument("--api-base", default="https://slack.com/api")
    try:
        return fetch(ap.parse_args())
    except lib.MirrorError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
