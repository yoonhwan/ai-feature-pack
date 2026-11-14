"""ft 2.0 keeper 판정 갈래 — 카드 «- 판정: HOLD» 줄이 늘면 holder 나노를 1회 깨운다 · 누적 3 = 깨움 0 + 인터뷰 길 로그 (r1931).

keeper.py 바퀴가 끝나지 않은 일마다 check 1회. 카드 = keeper_land resolver(짝 표 → 팀 폴더 · git show) · 깨움 = keeper_stall 깨움 길.
state «hold» = {"<team>|<work>": 깨운 n} · attempt·세트 sha·holder 는 키 밖(누적 유지) · 멈춤 깨움(woke)과 따로 셈.
"""
import importlib.util, os, re  # noqa: E401

HOLD = re.compile(r"^- 판정: HOLD(?=\s|$)", re.M)
WAKE = "[판정] HOLD — 카드 상태 줄을 읽고 보정 · 일 %s 누적 %d"
_S = importlib.util.spec_from_file_location("ft2_hold_projection", os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "core", "projection.py"))
projection = importlib.util.module_from_spec(_S)
_S.loader.exec_module(projection)


def holds(k, team, work):
    """카드 HOLD 줄 수(후보 카드 중 큰 값 · landing 과 같은 고르기) · 못 읽음 = 사유 문자열."""
    cards = k.cardmap(team)
    mapped = cards.get(work) if isinstance(cards, dict) else None
    if mapped:
        cards = "짝 표 같은 work %d줄" % len(mapped) if len(mapped) > 1 else k.mapped_cards(team, mapped[0])
    elif isinstance(cards, dict):
        cards = k.cards(team)
    if isinstance(cards, str):
        return cards
    exact, counts = work + ".md" in {os.path.basename(p) for _, p in cards}, []
    for ref, path in cards:
        base = os.path.basename(path)
        if mapped or (base == work + ".md" if exact else base.startswith(work + "-") and base.endswith(".md")):
            rc, body, _ = k.git(k.root, "show", "%s:%s" % (ref, path))
            if rc != 0:
                return "git show %s rc %s" % (path, rc)
            counts.append(len(HOLD.findall(body)))
    return max(counts) if counts else "카드 후보 0"


def check(k, team, work, attempt, rows):
    """n 이 늘었고 n ≤ 2 → 깨움 1회 · n ≥ 3 → 깨움 0 + HELD 1회 · 카드·holder·pane 못 읽음 = 판정 불가 1줄."""
    n, key = holds(k, team, work), "%s|%s" % (team, work)
    if isinstance(n, str):
        return k.log("판정 불가", team, "%s HOLD 판독 %s — 깨움 0" % (work, n))
    seen = k.state.setdefault("hold", {}).get(key, 0)
    if n <= seen:
        return None
    if n >= 3:
        k.state["hold"][key] = n
        return None if seen >= 3 else k.log("HELD", team, "%s HOLD 누적 %d — 인터뷰 길(하드 룰 14)" % (work, n))
    holder = k.read_json(os.path.join(projection.runtime_path(k.root, team), "launch", "%s@%s.intent" % (work, attempt))).get("FT2_HOLDER")
    alive = k.probe(holder) if holder else "holder 없음"
    if alive != "alive":
        return k.log("판정 불가", team, "%s HOLD %d holder %s %s — 깨움 0" % (work, n, holder, alive))
    if k.stall.guard(team, work, holder, rows):
        k.state["hold"][key] = n
        k.stall.wake(team, work, holder, key + "@hold", n, WAKE, "hold_")
