"""thread_ledger — 스레드 장부 ~/.hermes/state/byz_threads.json 읽기·쓰기 (설계 §3).

키 = «불변 단위 ID» `<팀>/<카드 파일 이름(.md 뺀 것)>` (카드가 대기/진행/완성을 옮겨도 안 바뀐다) · 매거진 = `magazine/<날짜>`.
값 = {channel, root_ts, kind(unit|report), card_path, progress:[ts…], results:[ts…]}.
장부 파일 없음·JSON 손상·저장 실패 = raise(빈 장부로 흡수 0). 빈 장부는 `init` 으로만 만든다.
"""
import json
from pathlib import Path

from mirror_lib import MirrorError, save_state

DEFAULT = Path.home() / ".hermes/state/byz_threads.json"
KINDS = ("unit", "report")


class LedgerError(MirrorError):
    pass


def init(path: Path) -> bool:
    """빈 장부를 만든다. 이미 있으면 건드리지 않고 False."""
    if path.exists():
        return False
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        save_state(path, {})
    except OSError as e:
        raise LedgerError(f"장부 생성 실패: {path} ({type(e).__name__})") from e
    return True


def load(path: Path) -> dict[str, dict]:
    if not path.exists():
        raise LedgerError(f"장부 없음: {path} — `byz_thread_post.py --init` 로만 만든다")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise LedgerError(f"장부 읽기 실패(손상): {path} ({type(e).__name__})") from e
    if not isinstance(data, dict) or not all(isinstance(v, dict) for v in data.values()):
        raise LedgerError(f"장부 형식 오류: {path}")
    return data


def _write(path: Path, data: dict[str, dict]) -> None:
    try:
        save_state(path, data)  # type: ignore[arg-type]
    except OSError as e:
        raise LedgerError(f"장부 쓰기 실패: {path} ({type(e).__name__})") from e


def get(path: Path, key: str) -> dict | None:
    return load(path).get(key)


def create(path: Path, key: str, *, channel: str, root_ts: str, kind: str, card_path: str) -> dict:
    if kind not in KINDS:
        raise LedgerError(f"kind 는 {KINDS} 중 하나: {kind}")
    data = load(path)
    if key in data:
        raise LedgerError(f"장부에 이미 있다: {key} (root_ts={data[key].get('root_ts')})")
    data[key] = {"channel": channel, "root_ts": root_ts, "kind": kind, "card_path": card_path, "progress": [], "results": []}
    _write(path, data)
    return data[key]


def ensure_report(path: Path, key: str, *, channel: str, root_ts: str, replace: bool = False) -> None:
    """매거진 뿌리 글(kind=report) — 장부에 없으면 만들고, 있는데 root_ts 가 다르면 raise.
    replace=True(사람이 --force 로 «새 뿌리 글» 을 명시한 경우만) 면 root_ts 를 새 값으로 바꾼다."""
    data = load(path)
    rec = data.get(key)
    if rec is None:
        create(path, key, channel=channel, root_ts=root_ts, kind="report", card_path="없음")
    elif rec.get("root_ts") != root_ts and replace:
        rec["root_ts"], rec["channel"] = root_ts, channel
        _write(path, data)
    elif rec.get("root_ts") != root_ts:
        raise LedgerError(f"장부 root_ts({rec.get('root_ts')}) ≠ 이번 root_ts({root_ts}): {key} — 사람이 확인한다")


def drop(path: Path, key: str) -> bool:
    """장부에서 그 키를 뻈다 — 지운 글 번호를 남기지 않는다(r1004 되읽기 가드가 지운 뒤 다음 갱신이 새 글을 만들게). 없는 키 = False(조용한 성공 0)."""
    data = load(path)
    if key not in data:
        return False
    del data[key]
    _write(path, data)
    return True


def set_field(path: Path, key: str, name: str, value: str | None) -> None:
    """한 칸 기록(value=None 이면 지움) — 보드 `reply_pending` 용."""
    data = load(path)
    if key not in data:
        raise LedgerError(f"장부에 키 없음: {key} — repair 필요")
    if value is None:
        data[key].pop(name, None)
    else:
        data[key][name] = value
    _write(path, data)


def update(path: Path, key: str, *, card_path: str | None = None, progress: str | None = None, result: str | None = None) -> dict:
    data = load(path)
    if key not in data:
        raise LedgerError(f"장부에 키 없음: {key} — repair 필요")
    rec = data[key]
    if card_path:
        rec["card_path"] = card_path
    if progress:
        rec.setdefault("progress", []).append(progress)
    if result and result not in rec.setdefault("results", []):
        rec["results"].append(result)
    _write(path, data)
    return rec
