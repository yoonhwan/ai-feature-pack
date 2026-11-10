"""R382b — 팀 폴더가 TEAMS.md 폴더 칸으로 풀리는 도구(ft_team_lib)의 격리 픽스처 도우미: 임시 루트에 최소 명단을 쓴다."""
from pathlib import Path

HEAD = "| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n"


def write_teams(root: Path, *teams: str, form: str = "design/{t}/") -> Path:
    """root/design/TEAMS.md — 기본 팀 = planner · harness (꼴1 · form 으로 꼴2 `design/teams/{t}/` 도 쓸 수 있다)."""
    path = Path(root) / "design" / "TEAMS.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(HEAD + "".join(f"| {t} | `{form.format(t=t)}` | x | 현역 |\n" for t in (teams or ("planner", "harness"))), encoding="utf-8")
    return path
