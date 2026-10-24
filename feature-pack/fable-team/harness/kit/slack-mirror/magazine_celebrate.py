"""magazine_celebrate — 아침 매거진 윗부분 «끝낸 일 축하» 재료 (r867 · 오빠 10-25 «하루 성과 셀러브레이션 · eli5 · 아래에 남은 일 풀 설명»).

창 = 판 날짜 D 의 (D-1) 00:00 ~ D 08:00 KST(끝 시각 제외). 창 안에 «닫는 증거»가 생긴 일만 싣는다 —
①원장 행: 창 시작 때 원장에선 완료가 아니었는데 창 끝 때 원장에선 완료이고, 그 행에 커밋 번호가 있다
②인덱스 카드: 창 안 커밋에서 «완성» 폴더로 옮겨졌다(그 커밋 = 닫는 증거).
쉬운 풀이(eli5)는 외부 호출 — 7초 룰(묶음 2장 · 호출당 7초 + 재시도 1 · 전체 70초 · magazine_celebrate_eli5) · 실패 = ERROR 로그 + 그 칸 «쉬운 풀이 생성 실패 — 사유»(숨김 0).
git 실패는 raise(반쪽 축하 0 · #0 RULE). 카드 글의 번호 낱말·상대 날짜는 근거 표로 옮긴다(판 본문 지침 §3).
"""
import logging
import re
from datetime import datetime, timedelta
from pathlib import Path

import magazine_eli5
from magazine_brief import Brief, Done
from magazine_brief_rows import is_done, split_evidence, table_rows
from magazine_collect_detail import git, sections
from magazine_date_guard import find_relative_dates
from magazine_doc_md import Cell, Doc, parse_doc
from magazine_celebrate_eli5 import explain
from magazine_eli5_batches import Eli5Error
from magazine_guide_check import violations
from magazine_indexless import strip_tokens
from magazine_summary import run_cmd
from magazine_window import KST

LOG = logging.getLogger("magazine_doc")
CARD_GLOB = "design/*/indices/완성/*.md"
DONE_DIR = "/indices/완성/"
SHA = re.compile(r"(?<![0-9A-Za-z])(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?![0-9A-Za-z])")
TITLE = re.compile(r"^#\s+(?:인덱스:\s*)?(.+)$")


def window(day: str) -> tuple[datetime, datetime]:
    """판 날짜 D → ((D-1) 00:00, D 08:00) KST."""
    d = datetime.fromisoformat(day).replace(tzinfo=KST)
    return d - timedelta(days=1), d + timedelta(hours=8)


def span_text(start: datetime, end: datetime) -> str:
    return f"{start:%m-%d %H:%M} ~ {end:%m-%d %H:%M}"


def _bad(text: str) -> bool:
    """판 본문에 실을 수 없는 글 — 지침 §3 금지 꼴 또는 상대 날짜."""
    return bool(violations(text) or find_relative_dates(Doc("", "", [Cell("x", "x", text)], [])))


def _plain(text: str, why: list[str]) -> str:
    """번호 낱말은 걷어 근거(why)로 · 그래도 판에 못 실으면 글째 근거로 옮기고 표시만 남긴다."""
    clean, found = strip_tokens(" ".join(text.split()))
    why += found
    if clean and _bad(clean):
        why.append(clean[:60])
        return "(설명 문장은 근거 표에)"
    return clean


def _done_rows(text: str) -> dict[str, tuple[str, str]]:
    """원장 §1·§2-1·§5 에서 완료인 행 → {일: (상태 글, 근거 글)}."""
    out: dict[str, tuple[str, str]] = {}
    for cell in parse_doc(text).cells if text else []:
        archive = "완료 보관" in cell.title
        if not (archive or cell.title.startswith(("오빠가 시킨 일", "2-1."))):
            continue
        for row in table_rows(cell.body):
            task, task_why = split_evidence(row.get("시키신 일") or row.get("발주") or "")
            state = row.get("지금 상태", "")
            if task and (archive or is_done(state)):
                clean, state_why = split_evidence(state)
                out[" ".join(task.split())] = (clean, " · ".join(x for x in (task_why, state_why, row.get("닫는 증거", "")) if x))
    return out


def _ledger_at(repo: Path, ref: str, path: str, when: datetime) -> str:
    sha = git(repo, "rev-list", "-1", f"--before={when.isoformat()}", ref, "--", path).strip()
    return git(repo, "show", f"{sha}:{path}") if sha else ""


def _from_ledger(repo: Path, ref: str, path: str, start: datetime, end: datetime) -> list[Done]:
    last = end - timedelta(seconds=1)
    before, now = _done_rows(_ledger_at(repo, ref, path, start - timedelta(seconds=1))), _done_rows(_ledger_at(repo, ref, path, last))
    out = []
    for task, (state, evidence) in now.items():
        if task in before or not SHA.search(evidence):
            continue  # 창 전에 이미 끝났거나 닫는 증거(커밋 번호)가 없다
        why = [evidence]
        title, what = _plain(task, why), _plain(state, why)
        out.append(Done(f"원장:{task}", title, f"원문 — {title} · {what}", " · ".join(why), "원장 · 오빠가 시킨 일", f"{title} — {what}"))
    return out


def _card_fact(text: str, path: str, why: list[str]) -> tuple[str, str]:
    """(대신 제목, 풀이 재료). 판 제목은 쉬운 풀이의 제목 — 풀이가 실패하면 «배경» 첫 문장(60자) · 카드 이름(영문 번호 이름)은 근거 표로만."""
    head = next((m.group(1) for ln in text.split("\n")[:3] if (m := TITLE.match(ln))), Path(path).stem)
    why.append(f"카드 {head.split(' — ')[0]}")
    back, _ = strip_tokens(" ".join(next((s.body for s in sections(text) if s.head.startswith("배경")), "").split()))
    if not back:
        return "(배경 없는 카드 — 이름은 근거 표에)", head.split(" — ")[0]
    first = back.split(". ")[0]
    return _plain(first if len(first) <= 60 else first[:60] + "…", why), back[:500]


def _from_cards(repo: Path, ref: str, start: datetime, end: datetime) -> list[Done]:
    out = git(repo, "log", ref, "-M", "--diff-filter=AR", "--name-status", "--format=%x01%H%x00%cI",
              f"--since={start.isoformat()}", f"--until={end.isoformat()}", "--", CARD_GLOB)
    seen: dict[str, Done] = {}
    for chunk in out.split("\x01")[1:]:
        lines = chunk.split("\n")
        sha, at = lines[0].split("\x00")
        if not start <= datetime.fromisoformat(at) < end:
            continue  # git --since/--until 는 경계 포함·근사 — 창은 여기서 정확히 자른다
        for row in lines[1:]:
            fields = row.split("\t")
            path = fields[-1]
            if row.startswith("R") and DONE_DIR in fields[1]:
                continue  # 완성/ 안에서 이름만 바꿈 — 창 전에 이미 끝난 일(새 완성 아님 · DA⑥ r1 반례 1)
            if row.strip() and path not in seen:
                why = [f"{sha[:10]} 완성 이동"]
                title, source = _card_fact(git(repo, "show", f"{sha}:{path}"), path, why)
                seen[path] = Done(f"카드:{path}", title, f"원문 — {title}", " · ".join(why), f"{path.split('/')[1]} 팀 · 카드 완성", source)
    return list(seen.values())


def collect(repo: str, ref: str, path: str, day: str) -> tuple[str, list[Done]]:
    """(창 글, 창 안 완성 목록 — 원장 행 먼저 · 카드 다음)."""
    start, end = window(day)
    return span_text(start, end), _from_ledger(Path(repo), ref, path, start, end) + _from_cards(Path(repo), ref, start, end)


def explain_done(done: list[Done], cmd: str) -> None:
    """칸마다 쉬운 풀이를 붙인다(d.eli5 = dict | 실패 사유). 완성 0건이면 외부 호출 0."""
    if not done:
        return
    units = [{"ref": d.key, "자료": d.source} for d in done]
    try:
        result = explain(units, cmd, magazine_eli5._skill(), run_cmd)
    except Eli5Error as e:  # eli5 스킬 원문 없음
        LOG.error("쉬운 풀이 전부 실패: %s", e)
        result = {u["ref"]: "eli5 스킬 없음" for u in units}
    for d in done:
        value = result.get(d.key, "생성 실패")
        if isinstance(value, dict) and _bad(" ".join([value["title"], value["analogy"], *value["lines"]])):
            LOG.error("쉬운 풀이 생략 key=%s 사유=지침", d.key)
            value = "지침 위반 문장"
        elif isinstance(value, str):
            LOG.error("쉬운 풀이 생략 key=%s 사유=%s", d.key, value)
        d.eli5 = value


def fill(brief: Brief, repo: str, ref: str, path: str, cmd: str) -> None:
    """brief 의 축하 칸(span·done)과 근거 표를 채운다."""
    brief.span, brief.done = collect(repo, ref, path, brief.date)
    explain_done(brief.done, cmd)
    brief.evidence += [(d.evidence, d.title[:40]) for d in brief.done]
