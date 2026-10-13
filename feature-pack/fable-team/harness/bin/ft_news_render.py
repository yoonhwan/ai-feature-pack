"""ft_news_render — 뉴스 초안 두 장(DRAFT · ISSUES) 글 만들기 (R118a). 번호·sha·경로·좌석 이름·영어 약어 0 — scrub 이 마지막 문턱이다."""
import hashlib
import re
from datetime import datetime

TEAM_NAMES = {"v65": "실시간 통역", "cfo": "결제 팀", "feature": "신기능", "graphics": "디자인", "harness": "하네스",
              "issues": "이슈 관리", "loom": "RAG", "ops": "운영툴", "planner": "기획", "ccu": "부하 시험"}  # 팀 약어 → 쉬운 이름 표(상수 1곳)
_ABBR = re.compile(r"(?<![A-Za-z0-9])(" + "|".join(TEAM_NAMES) + r")(?![A-Za-z0-9])", re.I)
RANK = ("확인 안 됨", "전달됨", "대기", "진행", "일부 완료", "완료")  # 뒤로 갈수록 앞선 단계
_PAREN = re.compile(r"\s*[(（][^)）]*(?:#\d|판정\s*\d|[0-9a-f]{7,40}|\.md)[^)）]*[)）]")
_TOKENS = re.compile(r"#\d+|판정\s*\d+(?:[~,·]\d+)*|\bR\d{2,}[a-z]?\b|(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])|\S+/\S+|\S+\.md\b")
_SLUG = re.compile(r"^[A-Za-z0-9][\w.-]*\s*(?:—\s*|\(\s*(?:\w+ 팀 · )?)")  # 카드 파일 이름 머리말 — 사람 말이 아니다
_OPEN = re.compile(r"\s*[(（][^)）]*$")  # 80자에서 잘려 닫히지 않은 괄호 꼬리
TOP_ISSUES, TEAM_ITEMS, SHORT_CAP = 5, 2, 48


def easy_names(text: str) -> str:
    """Haiku 에 보내기 «전» 팀 약어를 쉬운 이름으로 바꾼다(CFO → 결제 팀)."""
    return _ABBR.sub(lambda m: TEAM_NAMES[m[1].lower()], text)


def state_rank(state: str) -> int:
    return next((k for k in range(len(RANK) - 1, -1, -1) if state.startswith(RANK[k])), 0)


def team_name(team: dict) -> str:
    return TEAM_NAMES.get(team["key"], f"{team['label']} 팀")


def scrub(text: str) -> str:
    text = _OPEN.sub("", _TOKENS.sub("", _PAREN.sub("", _SLUG.sub("", text.strip()))))
    return re.sub(r"\s+", " ", text).strip(" ·—-:,")


def short(text: str) -> str:
    text = scrub(text)
    return text if len(text) <= SHORT_CAP else text[:SHORT_CAP].rstrip(" ·—-,") + "…"


def title_id(title: str) -> str:
    return "t" + hashlib.sha1(title.encode("utf-8")).hexdigest()[:10]


def title_text(easy: dict, title: str) -> str:
    """팀 목록의 카드 제목 — 쉬운 문장(영어·번호 게이트 통과)이 있으면 그것, 없으면 짧은 원문 + 실패 사유(무음 삭제 0)."""
    return say(easy, title_id(title), title)


def say(easy: dict, key: str, original: str) -> str:
    """쉬운 문장이 있으면 그것, 실패면 원문 제목(번호 제거) + 사유."""
    got = easy.get(key)
    if got and got.text:
        return got.text
    return f"{short(original)} (쉬운 문장 실패: {got.failure if got else '요청 안 됨'})"


def issue_text(issue: dict) -> str:
    return f"{issue['team']}: {issue['title']} — {'; '.join(issue['reasons'])}"


def _cell(text: str) -> str:
    return text.replace("|", "/").replace("\n", " ")


def _requests_table(requests: list[dict], easy: dict) -> list[str]:
    merged: dict[str, str] = {}  # 같은 문장은 1줄 — 상태는 가장 앞선 단계
    for r in requests:
        text = _cell(say(easy, "r%d" % r["n"], r["quote"]))
        if text not in merged or state_rank(r["state"]) > state_rank(merged[text]):
            merged[text] = r["state"]
    rows = ["| 시키신 일 | 지금 상태 |", "|---|---|"] + [f"| {t} | {_cell(st)} |" for t, st in merged.items()]
    return rows if requests else ["(이번 창에 새로 시키신 일이 없어요)"]


def _by_team(teams: list[dict], pick, easy: dict) -> list[str]:
    out = [f"- **{team_name(t)}**: {line}" for t in teams if (line := pick(t, easy))]
    return out or ["- (없음)"]


def _progress(t: dict, easy: dict) -> str:
    items = list(t["progress"].values())
    if not items:
        return ""
    idle = sum(1 for p in items if not p["seats"])
    names = " · ".join(title_text(easy, p["title"]) for p in items[:TEAM_ITEMS])
    return f"{names} (진행 {len(items)}장{f', 맡은 세션 없는 것 {idle}장' if idle else ''})"


def _todo(t: dict, easy: dict) -> str:
    queue = " · ".join(title_text(easy, q["title"]) for q in t["queue"][:TEAM_ITEMS])
    ask = f"오빠가 정할 것 {len(t['oppa_todo'])}건" if t["oppa_todo"] else ""
    return " / ".join(x for x in (queue, ask) if x)


def _done(t: dict, easy: dict) -> str:
    d = t["done_today"]
    return f"{title_text(easy, d['last'])} 외 {d['n'] - 1}건" if d["n"] else ""


def _team_zones(teams: list[dict], easy: dict) -> list[str]:
    """확인 정본 꼴 — 팀마다 `### 쉬운 이름` 구역(R117 parse_doc 이 팀 경계로 읽는다) + 지금 상태 1줄 · 진행 · 할 일."""
    out: list[str] = []
    for t in teams:
        c, lead = t["counts"], (t["leads"][0]["state"] if t["leads"] else "확인 불가")
        out += [f"### {team_name(t)}", f"지금 상태: {scrub(lead)} · 완성 {c['완성']}장 · 진행 {c['진행']}장 · 대기 {c['대기']}장",
                f"- 진행: {_progress(t, easy) or '없음'}", f"- 할 일: {_todo(t, easy) or '없음'}", ""]
    return out


def render_draft(now: datetime, requests: list[dict], collect: dict, issues: list[dict], easy: dict) -> str:
    teams = collect["teams"]
    probs = list(dict.fromkeys(f"- {say(easy, 'p%d' % k, issue_text(i))}" for k, i in enumerate(issues[:TOP_ISSUES])))
    parts = [f"# 뉴스 초안 — {now:%Y-%m-%d %H:%M}", "", "## 1. 시키신 일 — 지금 상태", *_requests_table(requests, easy), "",
             "## 2. 완료한 일", *_by_team(teams, _done, easy), "", "## 3. 진행 중", *_by_team(teams, _progress, easy), "",
             "## 4. 할 일", *_by_team(teams, _todo, easy), "", "## 5. 드러난 문제", *(probs or ["- (없음)"]), "", "## 6. 팀별 상태와 할 일", *_team_zones(teams, easy)]
    return "\n".join(parts)


def render_issues(now: datetime, issues: list[dict], top_n: int, easy: dict) -> str:
    lines = [f"# 이슈 정리 리포트 — {now:%Y-%m-%d %H:%M}", ""]
    rows = dict.fromkeys(f"{say(easy, 'p%d' % k, issue_text(i))} — {i['team']} · 복잡도 {i['score']}" for k, i in enumerate(issues[:top_n]))
    lines += [f"{k + 1}. {row}" for k, row in enumerate(rows)]
    rest = len(issues) - top_n
    lines += ["", f"나머지 {max(rest, 0)}개는 이 판에서 줄였어요."]
    return "\n".join(lines) + "\n"
