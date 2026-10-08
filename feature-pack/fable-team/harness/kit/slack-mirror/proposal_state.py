"""proposal_state — 제안서 발행 상태 파일 읽기·쓰기 (byz_proposal_publish 에서 분리 · 동작 변경 0).

상태 파일 {<팀>/<slug>: {root_ts, revs: {r0, r1…: {phase, at, ts}}}}. 저장 실패는 PublishError(#0 RULE — 삼키지 않는다).
"""
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from mirror_lib import save_state

KST = ZoneInfo("Asia/Seoul")


class PublishError(RuntimeError):
    pass


def read_state(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise PublishError(f"상태 파일 읽기 실패: {path} ({type(e).__name__})") from e
    if not isinstance(data, dict):
        raise PublishError(f"상태 파일 형식 오류: {path}")
    return data


def set_phase(path: Path, key: str, rev: str, phase: str, **fields: object) -> None:
    """rN 기록에 phase 와 칸을 «덧쓴다» — 앞서 저장한 md_hash·html·files 는 이 호출이 언급하지 않아도 보존된다(DA R2-A ③)."""
    try:
        st = read_state(path)
        rec = st.setdefault(key, {"revs": {}})
        old = rec.setdefault("revs", {}).get(rev, {})
        rec["revs"][rev] = {**old, "phase": phase, "at": datetime.now(KST).isoformat(timespec="seconds"), **fields}
        if rev == "r0" and fields.get("ts"):
            rec["root_ts"] = fields["ts"]
        save_state(path, st)  # type: ignore[arg-type]
    except OSError as e:
        raise PublishError(f"상태 쓰기 실패({phase}): {path} ({type(e).__name__})") from e
