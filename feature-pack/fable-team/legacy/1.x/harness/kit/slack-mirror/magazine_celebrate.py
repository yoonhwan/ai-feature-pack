"""magazine_celebrate — 아침 매거진 윗부분 «끝낸 일 축하» 재료 (r867 · 오빠 10-25 «하루 성과 셀러브레이션 · eli5 · 아래에 남은 일 풀 설명»).

창 = 판 날짜 D 의 (D-1) 00:00 ~ D 08:00 KST(끝 시각 제외). «새 완성» = 인덱스 카드 갈래 하나(r4 단순화 · DA⑥ r1~r3 반례 8건 중 5건이 원장 행 갈래) —
인덱스 카드: «완성» 폴더로 옮긴 커밋이 창 안 ∧ 옛 경로가 완성/ 밖 · 재료 = 카드 제목 + 그 커밋 sha 뿐(배경 글 옮기기 0 → 잘려 숨는 글 0)
같은 sha 는 1건으로 합친다(제목을 « · » 로 이어 숨김 0). 원장 행 완료는 이번 판 축하에 싣지 않고 머리 줄이 그렇게 밝힌다(magazine_brief.done_head)
— 원장 행 축하는 원장에 착지 sha 칸이 생긴 뒤 별 카드.
쉬운 풀이(eli5)는 외부 호출 — 7초 룰(묶음 2장 · 호출 프롬프트 전체 상한 · 호출당 7초 + 재시도 1 · 전체 70초 · magazine_celebrate_eli5) · 실패 = ERROR 로그 + 그 칸 «쉬운 풀이 생성 실패 — 사유»(숨김 0).
ref git 실패는 raise(반쪽 축하 0 · #0 RULE). 번호 낱말·상대 날짜는 근거 표로 옮긴다(판 본문 지침 §3).
"""
import logging
import re
from datetime import datetime, timedelta
from pathlib import Path

import magazine_eli5
from magazine_brief import Brief, Done
from magazine_collect_detail import done_line, fetch_refs, git, team_of
from magazine_date_guard import find_relative_dates
from magazine_doc_md import Cell, Doc
from magazine_celebrate_eli5 import explain
from magazine_eli5_batches import Eli5Error
from magazine_guide_check import violations
from magazine_indexless import strip_tokens
from magazine_summary import run_cmd
from magazine_window import KST

LOG = logging.getLogger("magazine_doc")
CARD_GLOB = "design/*/indices/완성/*.md"
DONE_DIR = "/indices/완성/"
OPS_REF = "origin/ops/main-base"  # r1009 — 하네스 카드는 이 원격 가지에서 완성된다
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


def _card_name(text: str, path: str) -> str:
    """카드 이름 — 머리 «… — 끝:»·«(설명)» 앞부분만(머리에 섮인 «— 대기 · 착수 0» 같은 상태 글은 싣지 않는다 · r1009)."""
    head = next((m.group(1) for ln in text.split("\n")[:3] if (m := TITLE.match(ln))), Path(path).stem)
    return head.split("— 끝:")[0].split(" (")[0].strip(" —")


def _done_refs(repo: Path, ref: str) -> list[str]:
    """축하 칸이 읽을 ref — 넘어온 ref + 하네스 카드가 완성되는 origin/ops/main-base.

    HEAD 는 원장 사본의 origin/main 과 같은 커밋(ft-ledger-repo-sync)이다. ops 가지를 못 받으면 MagazineError —
    상세 수집기와 같은 «반쪽 0» 규칙(삼킴 0 · DA⑥ r1 반례 2).
    """
    if ref != "HEAD" and not ref.startswith("origin/"):
        return [ref]  # 시험·수동 지정 ref 는 그대로(원격 가지가 아니다)
    if not _remote_tracked(repo):
        LOG.info("축하 칸 — 원격 추적 ref 없는 리포(%s): 넘어온 ref %s 만으로 그린다", repo, ref)
        return [ref]  # 사본이 아니다(origin 이 아예 없는 로컬 리포) — 사본이면 아래에서 ops 가지가 필수다
    fetch_refs(repo, [OPS_REF])  # 못 받으면 MagazineError — 상세 수집기와 같은 «반쪽 0»(삼킴 0)
    return [ref, OPS_REF]


def _remote_tracked(repo: Path) -> bool:
    """이 리포가 «원격 추적 가지» 를 가진 사본인가 — 사본이면 하네스 카드 가지(ops/main-base)가 필수다."""
    return bool(git(repo, "for-each-ref", "--count=1", "--format=%(refname)", "refs/remotes/").strip())


def _from_cards(repo: Path, refs: list[str], start: datetime, end: datetime) -> list[Done]:
    out: list[Done] = []
    seen: set[str] = set()  # 카드 경로 — 앞 ref 가 이긴다(두 ref 에 다른 커밋으로 있어도 1건 · 상세 수집기와 같은 규칙)
    for ref in refs:
        out += _cards_of(repo, ref, start, end, seen)
    return out


def _cards_of(repo: Path, ref: str, start: datetime, end: datetime, seen: set[str]) -> list[Done]:
    out = git(repo, "log", ref, "-M", "--diff-filter=AR", "--name-status", "--format=%x01%H%x00%cI",
              f"--since={start.isoformat()}", f"--until={end.isoformat()}", "--", CARD_GLOB)
    done: list[Done] = []
    for chunk in out.split("\x01")[1:]:
        lines = chunk.split("\n")
        sha, at = lines[0].split("\x00")
        if not start <= datetime.fromisoformat(at) < end:
            continue  # git --since/--until 는 경계 포함·근사 — 창은 여기서 정확히 자른다
        for fields in (row.split("\t") for row in lines[1:] if row.strip()):
            path = fields[-1]
            if path in seen:
                continue
            seen.add(path)
            if fields[0].startswith("R") and DONE_DIR in path:
                continue  # 완성/ 안에서 이름만 바꿈 — 창 전에 이미 끝난 일
            text = git(repo, "show", f"{sha}:{path}")
            name = _card_name(text, path)
            why = [f"{sha[:10]} 완성 이동 · 카드 {name}"]
            title = _plain(name, why) or "(카드 이름은 근거 표에)"  # 이름 속 번호 낱말(R259 등)은 근거 표로
            raw = done_line(text) or ""
            what = _plain(raw, why) if raw else ""  # 원문 줄도 같은 걸러내기(r1033) — why 를 evidence 로 잇기 «전»
            done.append(Done(f"sha:{sha}", title, what or f"원문 — {title}", " · ".join(why), f"{team_of(path)} 팀 · 카드 완성", title))
    return done


def _merge(items: list[Done]) -> list[Done]:
    """같은 닫는 증거 sha = 같은 일 1건 — 제목·원문·근거를 « · » 로 잇는다(숨김 0)."""
    by_key: dict[str, Done] = {}
    for d in items:
        if d.key not in by_key:
            by_key[d.key] = d
            continue
        m = by_key[d.key]
        m.title, m.what, m.evidence, m.source = (f"{a} · {b}" for a, b in ((m.title, d.title), (m.what, d.what), (m.evidence, d.evidence), (m.source, d.source)))
    return list(by_key.values())


def collect(repo: str, ref: str, day: str) -> tuple[str, list[Done]]:
    """(창 글, 창 안 완성 목록 — 인덱스 카드만 · 같은 sha 1건)."""
    start, end = window(day)
    return span_text(start, end), _merge(_from_cards(Path(repo), _done_refs(Path(repo), ref), start, end))


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


def fill(brief: Brief, repo: str, ref: str, cmd: str) -> None:
    """brief 의 축하 칸(span·done)과 근거 표를 채운다."""
    brief.span, brief.done = collect(repo, ref, brief.date)
    explain_done(brief.done, cmd)
    brief.evidence += [(d.evidence, d.title[:40]) for d in brief.done]
