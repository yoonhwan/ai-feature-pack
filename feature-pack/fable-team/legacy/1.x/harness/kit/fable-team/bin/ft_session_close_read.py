#!/usr/bin/env python3
"""ft_session_close_read.py <원장> <since 또는 ""> <세션 또는 ""> — r2101 `ft-session-close-ledger.sh read` 의 본체(카드 S5).

차례 ⓐ fail 줄마다 호출 pid · 세션 이름 · 도구가 같은 tool 줄 가운데 원장에서 바로 앞의 것 1개를 «kill 실패» 로 돌린다(없으면 깨진 줄)
ⓑ hook 줄을 원장 순서대로: 세션 id · 이름이 같고 시각이 hook 앞 60초 ~ 뒤 5초 안이며 아직 짝 없는 tool 줄 중 가장 가까운 것(같으면 뒤 줄)
ⓑ' 짝 줄 = «<시각> <세션> 후보 ← <도구> · <좌석> · <사유>»(후보일 뿐 확정 아님)
ⓒ 짝 없는 tool 줄 = «hook 줄 없음(<도구>)»(id «-» 면 «· id 없음») · 끝 줄 «닫힘 N · 후보 a · 도구 줄 없음 b · hook 줄 없음 c · kill 실패 f · 깨진 줄 d»
원장 한 줄 = 탭 8칸 «시각 · 종류 · 세션 · 도구 · 좌석 · 사유 · 세션 id · 호출 pid»
"""
import datetime as D
import sys

KINDS = ("hook", "tool", "fail")


def when(s):
    try:
        w = D.datetime.fromisoformat(s)
    except ValueError:
        return None
    return w.astimezone().replace(tzinfo=None) if w.tzinfo else w


def load(path, lo, sess):
    """→ (rows, broken) · rows = [(원장 순번, 시각, 칸들)] · 거르기(--since · --session) 뒤"""
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except FileNotFoundError:
        return [], 0
    rows, broken = [], 0
    for n, ln in enumerate(lines):
        if not ln.strip():
            continue
        c = ln.split("\t")
        w = when(c[0]) if len(c) == 8 else None
        if w is None or c[1] not in KINDS:
            broken += 1
            continue
        if (lo and w < lo) or (sess and c[2] != sess):
            continue
        rows.append((n, w, c))
    return rows, broken


def mark_failed(rows):
    """ⓐ → (kill 실패로 돌린 tool 줄 번호 집합, 앞 tool 줄 없는 fail 줄 수)"""
    failed, broken = set(), 0
    for k, (_, _, c) in enumerate(rows):
        if c[1] != "fail":
            continue
        prev = [j for j in range(k) if j not in failed and rows[j][2][1] == "tool" and rows[j][2][2] == c[2]
                and rows[j][2][3] == c[3] and rows[j][2][7] == c[7]]
        if prev:
            failed.add(prev[-1])
        else:
            broken += 1
    return failed, broken


def pair(rows, failed):
    """ⓑ → ({hook 줄 번호: tool 줄 번호}, 짝 지은 tool 줄 번호 집합)"""
    pairs, used = {}, set()
    for k, (_, hw, h) in enumerate(rows):
        if h[1] != "hook":
            continue
        best = None
        for j, (_, tw, t) in enumerate(rows):
            if t[1] != "tool" or j in used or j in failed or t[6] == "-" or t[6] != h[6] or t[2] != h[2]:
                continue
            d = (tw - hw).total_seconds()
            if -60 <= d <= 5 and (best is None or abs(d) <= best[0]):
                best = (abs(d), j)
        if best:
            pairs[k] = best[1]
            used.add(best[1])
    return pairs, used


def render(rows, failed, pairs, used):
    out = []
    for k, (n, w, c) in enumerate(rows):
        head = f"{c[0]} {c[2]} ← "
        if c[1] == "hook":
            t = rows[pairs[k]][2] if k in pairs else None   # 짝 = 닫은 주체의 «후보»(확정 아님 · 카드 S5)
            out.append((w, n, f"{c[0]} {c[2]} 후보 ← {t[3]} · {t[4]} · {t[5]}" if t else head + "도구 줄 없음"))
        elif c[1] == "tool" and k in failed:
            out.append((w, n, head + f"kill 실패({c[3]})"))
        elif c[1] == "tool" and k not in used:
            out.append((w, n, head + (f"hook 줄 없음({c[3]} · id 없음)" if c[6] == "-" else f"hook 줄 없음({c[3]})")))
    return [s for _, _, s in sorted(out, key=lambda x: (x[0], x[1]))]


def main(path, since, sess):
    lo = when(since) if since else None
    if since and lo is None:
        print(f"판정 불가 --since 시각 꼴 아님: {since}")
        return 2
    try:
        rows, broken = load(path, lo, sess)
    except OSError as e:
        print(f"판정 불가 원장 읽기 실패 {path}: {e.strerror}")
        return 1
    failed, nofail = mark_failed(rows)
    pairs, used = pair(rows, failed)
    for s in render(rows, failed, pairs, used):
        print(s)
    hooks = sum(1 for _, _, c in rows if c[1] == "hook")
    tools = sum(1 for _, _, c in rows if c[1] == "tool")
    print(f"닫힘 {hooks} · 후보 {len(pairs)} · 도구 줄 없음 {hooks - len(pairs)} · hook 줄 없음 {tools - len(used) - len(failed)}"
          f" · kill 실패 {len(failed)} · 깨진 줄 {broken + nofail}")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:4]))
