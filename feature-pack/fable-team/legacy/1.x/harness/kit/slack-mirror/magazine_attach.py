"""magazine_attach — 파일 첨부 멱등 (설계 §6 · DA HOLD-F1). 정상 발행(r0)과 재첨부(rN)가 같은 규칙을 쓴다.

원격 표식 = 파일 제목(`아침 매거진 D 풀 디테일 rK` · `… 쉬운 판 rK` «정확 일치» — 옛 제목 `… PDF rK` · `… HTML rK` 도 같은 표식, 판정 609 r2-1). 업로드 «전» 순서:
  ① 스레드 봇 글에 그 제목(새 또는 옛)의 파일이 있으면 채택(업로드 0)
  ② 없는데 이전 시도 기록(files.<종류> phase=sharing, 같은 스레드)이 있으면 «불명» — AttachError(새 file_id 0 · complete 재호출 0)
  ③ 아니면 file_id 를 받자마자(바이트 전송·complete 전) 시도 기록 → 전송 → 공유
기록 저장이 실패하면 콜백이 raise → 원격 전송 0. 공유가 «확실히 안 된» 실패(바이트 전송 실패 · complete ok=false 거절)는 기록을
failed 로 바꿔 다음 실행이 새로 시도하게 한다 — 응답 유실 같은 «결과 불명» 은 sharing 이 남아 ②로 막힌다.
사람이 채널을 본 뒤 `--force-file <pdf|html>` 로만 ②를 건너뛴다.
"""
import logging
from collections.abc import Callable
from pathlib import Path

from magazine_slack import Target, has_file_title, upload_file

LOG = logging.getLogger("byz_morning_magazine")
CONTENT_TYPES = {".pdf": "application/pdf", ".html": "text/html", ".md": "text/markdown"}  # 확장자로 — 쉬운 판(kind html)도 이제 PDF 파일
TITLE_KIND = {"pdf": "풀 디테일", "html": "쉬운 판", "md": "상세 부록"}


class AttachError(RuntimeError):
    pass


def file_title(date: str, kind: str, rev: str) -> str:
    return f"아침 매거진 {date} {TITLE_KIND[kind]} {rev}"


def legacy_title(date: str, kind: str, rev: str) -> str:
    """옛 제목 — 옛 판 실행이 남긴 첨부·상태를 새 판이 이어받을 때만 표식으로 인정한다."""
    return f"아침 매거진 {date} {kind.upper()} {rev}"


def attach(
    t: Target, root_ts: str, kind: str, path: Path, title: str, *,
    attempt: dict[str, str] | None, save: Callable[[dict[str, str]], None], force: bool = False, legacy: str | None = None,
) -> bool:
    """True = 이번에 올림 · False = 이미 붙어 있어 채택(업로드 0). attempt = 상태 파일의 이 종류 시도 기록(없으면 None)."""
    if has_file_title(t, root_ts, title) or (legacy and has_file_title(t, root_ts, legacy)):
        LOG.info("%s 첨부 표식 채택 (업로드 0)", title)
        return False
    if attempt and attempt.get("phase") == "sharing" and attempt.get("ts") == root_ts and not force:
        raise AttachError(f"불명: {title} 첨부 확인 필요 — 앞 실행이 공유를 시도했는데 스레드에 표식이 없음. 채널을 보고 --force-file {kind}")
    seen: dict[str, str] = {}

    def started(fid: str) -> None:
        seen["id"] = fid
        save({"file_id": fid, "phase": "sharing", "ts": root_ts})

    if path.suffix.lower() not in CONTENT_TYPES:
        raise AttachError(f"지원하지 않는 첨부 확장자: {path.name}")
    upload_file(t, root_ts, path, title, CONTENT_TYPES[path.suffix.lower()], on_file_id=started,
                on_not_shared=lambda: save({"file_id": seen["id"], "phase": "failed", "ts": root_ts}))
    return True
