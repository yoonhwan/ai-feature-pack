"""proposal_files — 제안서 세트(md + 쉬운 판 HTML) 만들기·붙이기 (byz_proposal_publish 보조 · 판정 357 설계 §r2-2).

원문 고정: rN 기록의 md_hash 는 첫 `posting` 저장 때 같이 기록되고, 이후 다른 원문이 같은 rN 으로 들어오면 raise(게시 0 · 캐시 채택 0).
HTML 캐시 이름에 원문 hash 가 들어가 다른 원문의 HTML 을 채택할 수 없다. 쉬운 판 실패(Eli5Error)는 rN 기록 html=omitted 로 남겨
재실행이 침묵으로 바뀌지 않게 한다(다시 원하면 다음 rN). 첨부는 magazine_attach.attach 를 그대로 쓴다(AttachError 는 삼키지 않는다).
"""
import hashlib
import logging
import os
from collections.abc import Callable
from pathlib import Path

from magazine_attach import attach
from magazine_eli5_batches import Eli5Error
from magazine_slack import Target
from proposal_state import PublishError, read_state, set_phase

LOG = logging.getLogger("byz_proposal_publish")


def md_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_pinned(key: str, rev: str, rec: dict, h: str) -> None:
    if rec.get("md_hash") and rec["md_hash"] != h:
        raise PublishError(f"{key} {rev} 은 {str(rec['md_hash'])[:8]} 원문으로 진행됨 — 바뀐 원문은 다음 rN(--revision)")


def make_html(key: str, rev: str, h: str, text: str, rec: dict, cmd: str, cache_dir: Path,
              build: Callable[[str, str, str], str]) -> tuple[Path | None, dict]:
    """(HTML 경로 또는 None, rN 기록에 넣을 html 칸). 캐시가 있으면 LLM 호출 0 · omitted 기록이 있으면 재시도 0."""
    old = rec.get("html") or {}
    if old.get("phase") == "omitted":
        return None, old
    path = cache_dir / f"{key.replace('/', '-')}-{rev}-{h[:16]}.html"
    if path.exists():
        return path, {"phase": "ready", "md_hash": h}
    try:
        page = build(text, key, cmd)
    except Eli5Error as e:
        reason = (str(e).splitlines() or [""])[0] or "원인 불명"
        LOG.error("%s %s 쉬운 판 생성 실패 — HTML 없이 md 만 발행: %s", key, rev, reason)
        return None, {"phase": "omitted", "reason": reason, "md_hash": h}
    cache_dir.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(page, encoding="utf-8")
    os.replace(tmp, path)
    return path, {"phase": "ready", "md_hash": h}


def attach_all(t: Target, thread: str, key: str, rev: str, h: str, files_in: list[tuple[str, Path | None]],
               st_path: Path, base: dict, force_file: str = "") -> None:
    """md → html 순서로 붙인다. files.<종류>.phase=done 이면 건너뜀(= 「md 완료」 와 같은 의미) · 시도 기록은 file_id 를 받자마자 저장."""
    files = dict(read_state(st_path).get(key, {}).get("revs", {}).get(rev, {}).get("files", {}))
    for kind, path in files_in:
        if path is None or files.get(kind, {}).get("phase") == "done":
            continue

        def save(a: dict, kind: str = kind) -> None:
            files[kind] = a
            set_phase(st_path, key, rev, "posted", files=files, **base)

        attach(t, thread, kind, path, f"제안서 {key} {rev} {kind.upper()} {h[:8]}",
               attempt=files.get(kind), save=save, force=force_file == kind)
        save({"phase": "done", "ts": thread})
