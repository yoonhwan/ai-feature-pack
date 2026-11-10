"""ft-board ① 완성 트리 렌더 — collect() dict 의 team["axes"] 만 읽는다(재조회 0).

기본 = 축마다 `완성(누적) n(최근: 제목)` 한 줄로 접고 🔄⏳·경보 줄만 행 상한 안에서. `--full` = 접기·상한 해제(✅ 펼침).
"""
import ft_board_env as env

AXIS_CAP = 5
GLYPH = {"완성": "✅", "진행": "🔄", "대기": "⏳", "중복": "⚠", "카드 없음": "❌"}


def _seat_note(team: dict, idx: str) -> str:
    seats = team["progress"].get(idx, {}).get("seats", [])
    return "  ← " + (" · ".join(f"{s['name']} {s['state']}" for s in seats) if seats else "좌석 없음")


def _entry_line(e: dict, team: dict, full: bool) -> str:
    pad = "  " * (e["d"] + 1 if full else 1)
    if e["k"] != "card":
        return f"{pad}{e['text']}"
    st = e["state"]
    note = {"진행": _seat_note(team, e["idx"]), "카드 없음": " ⚠카드 없음",
            "중복": f" ⚠폴더 중복({','.join(e['folders'])})"}.get(st, "")
    return f"{pad}{GLYPH[st]} {e['text']}{note}"


def _shown(e: dict) -> bool:
    if e["k"] == "dup":
        return True
    if e["k"] == "head":
        return "(카드 미연결)" in e["text"]
    return e["state"] != "완성"


def axis_lines(ax: dict, team: dict, full: bool) -> list[str]:
    c = ax["counts"]
    recent = f"(최근: {ax['recent']})" if ax["recent"] else ""
    warn = f" · ⚠중복 {c['중복']}" if c["중복"] else ""
    out = [f"■ {ax['title']}", f"  ✅ 완성(누적) {c['완성']}{recent} · 🔄 진행 {c['진행']} · ⏳ 대기 {c['대기']}{warn}"]
    ents = ax["entries"] if full else [e for e in ax["entries"] if _shown(e)]
    lines = [_entry_line(e, team, full) for e in ents]
    if not full and len(lines) > AXIS_CAP:
        lines = lines[:AXIS_CAP] + [f"  … 외 {len(lines) - AXIS_CAP}"]
    return out + lines


def tree_lines(d: dict, full: bool) -> list[str]:
    out = []
    for t in d["teams"]:
        if t.get("error"):  # 명부 수집 실패 = 이 팀 칸 «확인 불가»(축·카드 수 없음 · 원문 0 · r677)
            out.append(f"{t['label']} — 확인 불가({env.plain_error(t)})")
            continue
        if not t["cards_dir"]:
            out.append(f"{t['label']} — 카드 폴더 미지정")
            continue
        out.append(f"{t['label']}" + ("" if t["tree"] else " — 완성 트리 미지정(전부 축 미연결로 보임)"))
        for ax in t["axes"]:
            out += axis_lines(ax, t, full)
    return out
