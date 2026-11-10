#!/usr/bin/env python3
"""_issue_card_audit_out.py — ft-issue-card-audit 의 «출력 3꼴·추천 팀·쪽지 틀» (PLAN-issue-card-audit §2-2·§2-3).

판정(입력·연결/언급/없음·실패 처리)은 _issue_card_audit.py 가 갖는다. 여기는 «글»만 만든다 — 발송 0.
"""
import json
import os
import re

GOAL_SECTION_RE = re.compile(r"^##\s*골좌표\s*$(.*?)(?=^##\s|\Z)", re.M | re.S)
MAX_TICK_NUMBERS = 5


def load_aliases(path):
    """별칭 data(team_aliases.json). 없거나 깨졌으면 ValueError 로 알린다(부르는 쪽이 판정 불가로)."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise ValueError(f"별칭 data 읽기 실패 {path} — {exc}")
    if not isinstance(data, dict):
        raise ValueError(f"별칭 data 형식 오류 {path}")
    return data


def sums(rows):
    return {
        "approved": len(rows),
        "missing": [r["number"] for r in rows if r["status"] == "없음"],
        "mentioned": sum(1 for r in rows if r["status"] == "언급만"),
        "close": [r["number"] for r in rows if r["close_candidate"]],
    }


# ── 추천 팀 (§2-2 · R8) ──
def _title_token(title):
    hit = re.match(r"\s*\[([^\]]*)\]", title or "")
    if not hit:
        return ""
    return re.split(r"[\s·…,、]+", hit.group(1).strip())[0].strip().lower()


def team_of(issue, aliases):
    """→ (팀 이름, 근거). 근거 = 라벨 team:<x> | 제목 머리 [<x>] | 없음 — planner 분류."""
    label_alias = aliases.get("labels") or {}
    title_alias = aliases.get("title_prefix") or {}
    known = {str(t).lower() for t in (aliases.get("teams") or [])}
    teams = [lab.split(":", 1)[1].strip() for lab in issue["labels"]
             if lab.startswith("team:") and lab.split(":", 1)[1].strip()]
    if teams:
        raw = teams[0]
        return label_alias.get(raw, raw), f"라벨 team:{raw}"
    token = _title_token(issue["title"])
    if token:
        team = title_alias.get(token) or (token if token in known else None)
        if team:
            return team, f"제목 머리 [{token}]"
    return aliases.get("default", "planner"), "없음 — planner 분류"


# ── 출력 3꼴 ──
def line_tick(rows):
    """한 줄 — 번호는 큰 번호부터 5개, 6건 이상이면 «+<나머지 수>» (R3)."""
    s = sums(rows)
    parts = [f"approved={s['approved']}", f"카드없음={len(s['missing'])}"]
    head = sorted(s["missing"], reverse=True)[:MAX_TICK_NUMBERS]
    if head:
        parts.append(" ".join(f"#{n}" for n in head))
        if len(s["missing"]) > MAX_TICK_NUMBERS:
            parts.append(f"+{len(s['missing']) - MAX_TICK_NUMBERS}")
    parts.append(f"언급만={s['mentioned']}")
    parts.append(f"닫기후보={len(s['close'])}")
    return "ISSUE-CARD " + " ".join(parts)


def line_table(rows, aliases):
    """이슈마다 `#N · 제목 40자 · 상태 · 카드 칸 · 추천 팀 (근거)`."""
    out = []
    for row in rows:
        bucket = "/".join(row["buckets"]) if row["buckets"] else "—"
        team, why = team_of(row, aliases)
        title = row["title"]
        if len(title) > 40:
            title = title[:39] + "…"
        out.append(f"#{row['number']} · {title} · {row['status']} · {bucket} · "
                   f"{team} ({why})")
    return "\n".join(out)


def goal_coord(repo, team, aliases):
    """쪽지 머리의 «골좌표» — 팀 GOAL 파일의 `## 골좌표` 첫 줄 → 별칭 data goals → 자리표시."""
    for cand in (f"design/{team}/GOAL-{team}.md", f"design/{team}/GOAL.md"):
        path = os.path.join(repo, cand)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        hit = GOAL_SECTION_RE.search(text)
        if hit:
            for line in hit.group(1).strip().splitlines():
                if line.strip():
                    return line.strip().strip("`")
    return (aliases.get("goals") or {}).get(team) or f"design/{team}/ (팀 master·planner 확인)"


def body_mail(rows, team, repo, aliases):
    """§2-3 쪽지 틀 — 이 팀 몫 «카드 없음» 만. 출력 전용(발송 0 · 보내는 것은 planner)."""
    mine = [r for r in rows
            if r["status"] == "없음" and team_of(r, aliases)[0] == team]
    lines = [f"[카드 등록 요청 · approved {len(mine)}건] 골좌표: "
             f"{goal_coord(repo, team, aliases)}",
             "아래 approved 이슈에 팀 카드가 없습니다. 카드 1장씩 «대기/» 에 만들고 "
             "머리에 «- Issue: #N» 을 적어 주세요."]
    for row in mine:
        lines.append(f"- #{row['number']} «{row['title']}» "
                     f"(추천 근거: {team_of(row, aliases)[1]})")
    lines.append("끝나면 회신 1줄: «등록 #N→<카드 경로>».")
    return "\n".join(lines)
