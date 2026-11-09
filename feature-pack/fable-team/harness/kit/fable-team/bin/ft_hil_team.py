#!/usr/bin/env python3
"""ft_hil_team.py — h<N> 의 팀 읽기(r1538 · `ft_hil_pending.py --team` 의 본체).

h 기록에는 팀 칸이 없다(등록 꼴 그대로 · r1538 범위 밖). 팀을 알 길 둘:
  계획 머리 `# ft-hil-request seat=<좌석…>`(r1117 · 최대 3) — 계획 파일 경로는 h 의 `# ft-hil-entry plan=` 줄이 가리킨다
  `<h>.notify` 의 `seat=<좌석>`(r718)
좌석 이름 → 팀 = `byz-<팀>-…` · `aifp-<팀>-…`. 그 밖 꼴 = 표식 없음(팀을 못 읽는다 · 부르는 쪽이 «전 팀에 셈» 으로 처리)
읽기 실패·파일 없음 = 그 출처만 0(다른 출처는 살린다) · 예외 0 · 쓰기 0.
"""
import re

PLAN, REQ, NOTI = b"# ft-hil-entry plan=", b"# ft-hil-request seat=", b"seat="
TEAM = re.compile(r"(?:byz|aifp)-([a-z0-9]+)", re.ASCII)


def val(path, mark):  # mark 뒤 1줄 값을 공백으로 나눈다 · 파일 없음·표식 없음 = []
    try:
        with open(path, "rb") as f:
            return next((ln[len(mark):].decode("utf-8", "replace").split() for ln in f.read().split(b"\n") if ln.startswith(mark)), [])
    except OSError:
        return []


def teams_of(hpath):  # h 의 팀 집합 = 계획 머리 요청 좌석 ∪ notify 좌석의 팀 · 표식 0 = 빈 집합
    seats = val((val(hpath, PLAN) or [""])[0], REQ) + val(hpath + ".notify", NOTI)
    return {m.group(1) for m in map(TEAM.match, seats) if m}


def picked(d, rows, team):  # (남길 행, 팀 표식 없는 h 이름들) — 표식 없는 h 는 지금처럼 전 팀에 센다
    keep, bare = [], []
    for r in rows:
        t = teams_of("%s/h%s" % (d, r[0]))
        if not t:
            bare.append(r[0])
        if not t or team in t:
            keep.append(r)
    return keep, bare
