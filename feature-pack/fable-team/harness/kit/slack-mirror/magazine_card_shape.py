"""magazine_card_shape — 완성 카드 «형식 미달» 판정·보고 (판정 602).

기본(환경변수 없음)은 지금처럼 빠진 절 하나에도 MagazineError. 명시 opt-in `MAGAZINE_MALFORMED_CARDS=report` 일 때만 그 카드를
units 에서 빼 `detail["malformed"]` 로 드러낸다 — NO SILENT FALLBACK 예외 3요건: ①opt-in ②stderr ERROR 줄 ③매거진 본문·뿌리 글·부록 경고.
카드 내용을 추정하거나 채우지 않는다(경로·빠진 절 이름만).
"""
import os
import sys

from magazine_window import MagazineError

MODE_ENV = "MAGAZINE_MALFORMED_CARDS"
PARTS = ("제목", "상태", "배경", "골좌표")  # 검사 순서 = 기존 raise 순서(제목 → 상태 → 배경 → 골좌표)


def report_mode() -> bool:
    """환경변수 없음 = False(raise 그대로) · `report` = True · 그 밖의 값(빈 문자열·오타)은 raise."""
    value = os.environ.get(MODE_ENV)
    if value is None:
        return False
    if value != "report":
        raise MagazineError(f"{MODE_ENV}={value!r} — 알 수 없는 값이에요(report 만 쓸 수 있어요)")
    return True


def missing_parts(title: str | None, heads: list[str]) -> list[str]:
    """빠진 항목 이름(PARTS 순서). heads = 카드의 `## ` 절 머리들."""
    return [p for p in PARTS if (title is None if p == "제목" else not any(h.startswith(p) for h in heads))]


def error_for(part: str, path: str) -> MagazineError:
    if part == "제목":
        return MagazineError(f"카드 제목(`# …`)이 없어요: {path}")
    return MagazineError(f"카드에 `## {part}` 절이 없어요: {path}")


def report_line(path: str, missing: list[str]) -> None:
    print(f"ERROR magazine: 형식 미달 카드 {path} (빠진 절: {', '.join(missing)})", file=sys.stderr)


def warning_line(malformed: list[dict[str, object]]) -> str | None:
    """첫 화면·뿌리 글 공용 1줄 — 형식 미달 0장이면 None(출력 바이트 불변)."""
    if not malformed:
        return None
    return f"⚠ 형식 미달 카드 {len(malformed)}장: " + " · ".join(str(m["path"]) for m in malformed)
