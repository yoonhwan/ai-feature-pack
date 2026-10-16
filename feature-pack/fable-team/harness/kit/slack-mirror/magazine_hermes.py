"""magazine_hermes — 칸·팀 한 묶음씩 Haiku 프록시(cliproxy Messages)에 «쉬운 한 문단»을 시킨다 (R117 r2 · 오빠 판정 1433 · 하드 룰 12).

에르메스 CLI·세션 DB 경로 0 — mirror_summary._fetch 직접 호출(MODEL 재사용). 시도 상한 = EXTERNAL_CALL_TIMEOUT_S 7초(가산 0) · 재시도 1회(시간 초과·연결 실패만) · 동시 3 · 단계 마감 120초(늦은 결과는 버림).
요청 body(최종 직렬화 UTF-8) ≤ 1,800B(토큰 ≥ 1바이트 + 프록시 고정 ~134토큰 → 입력 ≤ 1,934 토큰 «호출 전» 보장) · max_tokens ≤ 400(이 호출용) · 응답 usage 의 input + cache_creation + cache_read «합계» > 2,000 또는 stop_reason == max_tokens 면 그 칸 실패.
길이 재시도 0 — 하드 룰 12(재시도는 첫 출력 전 실패만 · 답을 받은 뒤 검증 탈락은 재호출하지 않는다).
실패·검증 탈락은 칸 단위 Easy(error=사유) + ERROR 로그 — 본문(원문)은 호출자가 그대로 싣는다(무음 폴백 0).
"""
import http.client
import json
import logging
import re
from concurrent.futures import Future, ThreadPoolExecutor, wait
from dataclasses import dataclass

from magazine_doc_md import Cell
from mirror_lib import EXTERNAL_CALL_TIMEOUT_S, MAX_RETRIES
from mirror_summary import DEFAULT_URL, MODEL, SummaryError, _fetch

LOG = logging.getLogger("magazine_hermes")
BODY_CAP_B = 1800
MAX_TOKENS = 400
INPUT_TOKENS_CAP = 2000
ANSWER_CAP = 200
STAGE_DEADLINE_S = 70.0  # 판정 666·1375 — 총 마감 천장 70초(매거진 판은 이 호출을 안 쓰고 뉴스 쪽이 쓴다)
WORKERS = 3
INSTRUCTION = (
    "아래는 «{title}» 칸의 원문이에요. 항목을 하나하나 나열하지 말고 전체 흐름만, 초등학생도 알아듣는 쉬운 말로 100자 안쪽 한두 문장으로 설명해 주세요(길면 안 돼요). "
    "원문에 없는 내용은 쓰지 말고, 주어를 지어내지 마세요. 개수를 세지 말고 숫자를 지어내지 마세요. 번호(#숫자)·해시·파일 경로·영어 약어는 쓰지 마세요. "
    "설명 한 문단만 출력하세요.\n\n"
)
_NOISE = re.compile(r"[|\-: ]+")
_BAD = re.compile(r"#\d+|(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])|[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+")


class EasyError(RuntimeError):
    pass


@dataclass(frozen=True)
class Easy:
    text: str | None
    error: str | None


def build_prompt(cell: Cell, cap: int = BODY_CAP_B) -> str:
    """요청 입력만 자른다(본문은 안 자름) — 줄 단위로 앞에서부터 채우므로 머리 «지금 상태» 줄이 먼저 들어간다."""
    head = INSTRUCTION.format(title=cell.title)
    room = cap - len(head.encode("utf-8"))
    kept: list[str] = []
    used = 0
    for ln in cell.body.splitlines():
        if not ln.strip() or _NOISE.fullmatch(ln):
            continue
        size = len(ln.encode("utf-8")) + 1
        if used + size > room:
            if not kept:
                kept.append(ln.encode("utf-8")[:room].decode("utf-8", errors="ignore"))
            break
        kept.append(ln)
        used += size
    return head + "\n".join(kept)


def _serialize(prompt: str) -> bytes:
    return json.dumps({"model": MODEL, "max_tokens": MAX_TOKENS, "thinking": {"type": "disabled"},
                       "messages": [{"role": "user", "content": prompt}]}, ensure_ascii=False).encode("utf-8")


def build_body(cell: Cell) -> bytes:
    """최종 직렬화 body ≤ BODY_CAP_B — 줄 경계에 닿을 때까지 cap 을 (초과분, 최소 1B)씩 내린다. 머리 지시문 아래로 내려가면 실패."""
    floor = len(INSTRUCTION.format(title=cell.title).encode("utf-8"))
    cap = BODY_CAP_B
    while cap > floor:
        body = _serialize(build_prompt(cell, cap))
        if len(body) <= BODY_CAP_B:
            return body
        cap -= max(1, len(body) - BODY_CAP_B)
    raise EasyError(f"요청 body 를 {BODY_CAP_B}B 안으로 못 줄임")


def check(answer: str) -> str:
    text = " ".join(answer.split())
    if not text:
        raise EasyError("빈 답")
    if len(text) > ANSWER_CAP:
        raise EasyError(f"{len(text)}자 — {ANSWER_CAP}자 초과")
    if _BAD.search(text):
        raise EasyError("번호·해시·경로가 섞인 답")
    return text


def _parse(raw: bytes) -> str:
    try:
        data = json.loads(raw)
    except ValueError as e:
        raise EasyError("응답 해석 실패") from e
    blocks = data.get("content") if isinstance(data, dict) else None
    if not isinstance(blocks, list):
        raise EasyError("응답 해석 실패")
    if data.get("stop_reason") == "max_tokens":
        raise EasyError(f"max_tokens {MAX_TOKENS} 에서 잘림")
    usage = data.get("usage") or {}
    used = sum(v for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens") if isinstance(v := usage.get(k), int))
    if used > INPUT_TOKENS_CAP:
        raise EasyError(f"입력 {used} 토큰 — {INPUT_TOKENS_CAP} 초과")
    return check("".join(b["text"] for b in blocks if isinstance(b, dict) and b.get("type") == "text" and isinstance(b.get("text"), str)))


def easy_one(cell: Cell, url: str = DEFAULT_URL, attempt_timeout: float = EXTERNAL_CALL_TIMEOUT_S) -> str:
    body = build_body(cell)
    for _ in range(MAX_RETRIES + 1):
        try:
            return _parse(_fetch(url, body, attempt_timeout))
        except (TimeoutError, ConnectionError):
            continue  # 첫 출력 전 실패만 재시도 — HTTP 오류·검증 탈락은 같은 결과라 즉시 실패
        except (OSError, http.client.HTTPException, SummaryError) as e:
            raise EasyError(f"프록시 호출 실패: {type(e).__name__}: {e}") from e
    raise EasyError(f"시간 초과 — {attempt_timeout:g}초 × {MAX_RETRIES + 1}회")


def easy_all(
    cells: list[Cell], url: str = DEFAULT_URL, *,
    workers: int = WORKERS, deadline: float = STAGE_DEADLINE_S, attempt_timeout: float = EXTERNAL_CALL_TIMEOUT_S,
) -> dict[str, Easy]:
    pool = ThreadPoolExecutor(max_workers=workers)
    futs = {pool.submit(easy_one, c, url, attempt_timeout): c for c in cells}
    done, _late = wait(futs, timeout=deadline)
    pool.shutdown(wait=False, cancel_futures=True)  # 마감 뒤 늦게 오는 결과는 읽지 않는다
    return {c.key: _result(f, c) if f in done else _failed(c, f"단계 마감 {deadline:g}초 넘김 — 늦은 결과는 버림") for f, c in futs.items()}


def _result(fut: Future[str], cell: Cell) -> Easy:
    try:
        return Easy(fut.result(), None)
    except EasyError as e:
        return _failed(cell, str(e))


def _failed(cell: Cell, reason: str) -> Easy:
    LOG.error("쉬운 요약 실패 %s(%s): %s", cell.key, cell.title, reason)
    return Easy(None, reason)
