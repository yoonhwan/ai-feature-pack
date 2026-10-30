#!/usr/bin/env python3
"""ft_doc_exempt_moves.py — ft_doc_exempt.py 의 «진행→완성 카드 이동» 한 꼴 판정 (r1175 · 카드 r1175-doc-exempt-index-move-done-commit)

왜: 팀 master 가 ft-index-move 로 카드를 진행/ 에서 완성/ 으로 옮긴 PR 은 indices(제외 폴더)의 D+A 라 매번 사람 승인 h 를 기다렸다
    (이슈팀 기획 §5-1 ⑥ · arch#182 «ft-index-move 가 만든 이동 커밋 한정 면제»). ft-index-move 가 만드는 꼴과 «정확히» 같은 변경만 연다.
꼴(전부 참일 때만 그 짝을 행 목록에서 뺀다):
  ① 같은 팀 design/teams/<팀>/indices/진행/<이름>.md 삭제(D) + design/teams/<팀>/indices/완성/<이름>.md 추가(A) — 이름 같음
  ② 새 판 = 옛 판 줄 전부가 같은 순서로 남고 새 줄은 끝에만 덧붙음 · 바뀌어도 되는 줄 = 머리(첫 `## ` 앞)의 첫 «- 상태:» 줄 1개 → «- 상태: 완성…»
     (ft-index-move.sh 의 끝 기록 덧붙임 + r1009 머리 상태 줄 교체와 같은 꼴)
  ③ 덧붙은 줄 중 «- … — 진행→완성 · … · DA <경로>[#§N]» 이 정확히 1개 · <경로> 가 head 트리에 있고 그 절(#§N 없으면 파일 전체)에
     «닫힘»|«CLOSE» 가 있음(ft-index-move.sh 의 이동 게이트와 같은 절 규칙 · §5 가 §57 에 안 걸림)
  짝이 있는데 ②③ 이 틀리면 면제 아님(사유 반환) · 짝이 없는 D·A 는 그대로 두어 본 판정기의 지금 규칙(D 거절 · indices 제외)이 본다.
알려진 한계: ft-index-move 의 다른 게이트(리서치 닫힘·DA 보류·정본 줄)는 다시 돌리지 않는다 — 꼴과 판정문 «닫힘» 만 본다.
"""

import re

from ft_doc_exempt_paths import TEAMS_PREFIX, TEAM_RX, shape_problem

FROM_DIR, TO_DIR = "진행", "완성"
STATE = "- 상태:"
LOG_RX = re.compile(r"^- .+ — 진행→완성 · (?:.+ · )?DA (\S+)$")


def _card(path):
    """design/teams/<팀>/indices/<상태>/<이름>.md 이면 (팀, 상태, 이름) · 아니면 None."""
    if shape_problem(path) or not path.startswith(TEAMS_PREFIX):
        return None
    segs = path[len(TEAMS_PREFIX):].split("/")
    if len(segs) != 4 or segs[1] != "indices" or not segs[3].endswith(".md") or not TEAM_RX.match(segs[0]):
        return None
    return segs[0], segs[2], segs[3]


def _lines(data):
    """bytes → 줄 목록(끝 줄바꿈 1개는 줄로 세지 않는다) · NUL·UTF-8 아님 = None."""
    if data is None or b"\0" in data:
        return None
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    ln = text.split("\n")
    return ln[:-1] if ln and ln[-1] == "" else ln


def appended_lines(old, new):
    """② 꼴 대조 — (덧붙은 줄 목록, 사유)."""
    if len(new) <= len(old):
        return None, "덧붙은 줄 없음"
    head_end = next((i for i, ln in enumerate(old) if ln.startswith("## ")), len(old))
    state_at = next((i for i in range(head_end) if old[i].startswith(STATE)), -1)
    for i, ln in enumerate(old):
        if new[i] == ln or (i == state_at and new[i].startswith(STATE + " 완성")):
            continue
        return None, "%d번째 줄이 바뀜" % (i + 1)
    return new[len(old):], ""


def _header_hit(line, sec):
    """ft-index-move.sh 절 규칙 — `## ` 헤더 안 sec 포함 · sec 에 § 가 있으면 바로 뒤가 숫자가 아닐 때만(§5 ≠ §57)."""
    rest = line
    while True:
        i = rest.find(sec)
        if i < 0:
            return False
        nxt = rest[i + len(sec):i + len(sec) + 1]
        if "§" not in sec or not (nxt.isascii() and nxt.isdigit()):
            return True
        rest = rest[i + len(sec):]


def verdict_closed(da, read_head):
    """③ 판정문 재확인 — 사유(빈 값 = 통과). read_head(path) → bytes|None (head 트리)."""
    path, _, sec = da.partition("#")
    if shape_problem(path):
        return "판정문 경로 모양 틀림: %s" % da
    text = _lines(read_head(path))
    if text is None:
        return "판정문이 head 트리에 없음: %s" % path
    if sec:
        on, body = False, []
        for ln in text:
            if ln.startswith("## "):
                on = _header_hit(ln, sec)
            if on:
                body.append(ln)
        if not body:
            return "판정문 %s 에 절 «%s» 없음" % (path, sec)
        text = body
    if not any("닫힘" in ln or "CLOSE" in ln for ln in text):
        return "판정문 %s %s 에 «닫힘»/«CLOSE» 없음" % (path, sec)
    return ""


def index_move_pair(rows, read_blob, base, head):
    """rows = [(상태, 경로)] · read_blob(rev, path) → bytes|None.
    반환 (남은 rows, [(팀, 완성 경로)], 사유) — 사유가 있으면 짝이 있으나 이동 꼴 아님(면제 0)."""
    gone = {}
    for st, p in rows:
        c = _card(p)
        if st == "D" and c and c[1] == FROM_DIR:
            gone[(c[0], c[2])] = p
    used, moved = set(), []
    for st, p in rows:
        c = _card(p)
        if st != "A" or not c or c[1] != TO_DIR or (c[0], c[2]) not in gone:
            continue
        src = gone[(c[0], c[2])]
        old, new = _lines(read_blob(base, src)), _lines(read_blob(head, p))
        if old is None or new is None:
            return rows, [], "이동 꼴 아님(카드를 못 읽음·UTF-8 아님): %s" % p
        tail, why = appended_lines(old, new)
        logs = [m.group(1) for m in map(LOG_RX.match, tail or []) if m]
        if not why and len(logs) != 1:
            why = "덧붙은 «진행→완성 · DA» 기록 줄 %d개(1개여야)" % len(logs)
        why = why or verdict_closed(logs[0], lambda q: read_blob(head, q))
        if why:
            return rows, [], "추가·수정 아닌 변경(D): %s — 이동 꼴 아님: %s" % (src, why)
        used.update((src, p))
        moved.append((c[0], p))
    return [(st, p) for st, p in rows if p not in used], moved, ""
