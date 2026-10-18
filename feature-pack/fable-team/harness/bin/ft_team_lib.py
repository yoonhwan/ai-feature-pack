"""ft_team_lib — 팀 폴더 단일 출처(파이썬 쪽 · R382b). 셸 ft-team-lib.sh 와 «같은 규칙» — 시험(test_team_literal_paths.sh)이 두 구현의 출력 동치를 대조한다.

TEAMS.md «폴더» 칸(3번째 열) 3꼴을 푼다 — 도구는 `design/<팀>/` 을 글자로 박지 않고 team_root/team_in 만 부른다.
  꼴1 `design/<팀>/` · 꼴2 `design/teams/<팀>/` · 꼴3 `$FT_HARNESS_ROOT/design/<팀>/`(env 치환 · 하네스 팩 분리 뒤)
실패는 TeamPathError — 옛 `design/<팀>/` 으로 되돌아가지 않는다(#0 RULE).
env: FT_REPO_ROOT(기본 git 루트) · FT_TEAMS_MD(기본 <루트>/design/TEAMS.md · team_in 은 무시) · FT_HARNESS_ROOT(꼴3 치환값)
"""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

_FORM = re.compile(r"^(\$FT_HARNESS_ROOT/|\$\{FT_HARNESS_ROOT\}/)?design/(teams/)?[a-z0-9][a-z0-9_-]*/$")


class TeamPathError(RuntimeError):
    pass


def repo_root() -> Path:
    if env := os.environ.get("FT_REPO_ROOT"):
        return Path(env)
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=7)
    if out.returncode != 0 or not out.stdout.strip():
        raise TeamPathError("ERROR 리포 루트를 못 찾았다(FT_REPO_ROOT 또는 git 안에서 실행)")
    return Path(out.stdout.strip())


def teams_md(root: Path | None = None) -> Path:
    path = Path(os.environ["FT_TEAMS_MD"]) if os.environ.get("FT_TEAMS_MD") else (root or repo_root()) / "design" / "TEAMS.md"
    if not path.is_file():
        raise TeamPathError(f"ERROR 팀 명단 없음: {path}")
    return path


def team_rows(md: Path) -> dict[str, str]:
    """명단 → {팀: 칸 원문 경로} (3꼴 중 하나인 행만 · 같은 팀이 둘이면 첫 행)."""
    rows: dict[str, str] = {}
    for line in md.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            continue
        cells = line.split("|")
        if len(cells) < 4:
            continue
        rel = re.sub(r"[\s`]", "", cells[2])
        name = rel.rstrip("/").rsplit("/", 1)[-1]
        if _FORM.match(rel) and name not in rows:
            rows[name] = rel
    return rows


def team_names(root: Path | None = None) -> list[str]:
    return list(team_rows(teams_md(root)))


def team_rel(team: str, root: Path | None = None) -> str:
    rows = team_rows(teams_md(root))
    if team not in rows:
        raise TeamPathError(f"ERROR {team} 은 팀 명단(TEAMS.md)에 없다")
    return rows[team]


def _harness_root_from_map() -> str:
    """셸 ft-harness-root.sh ft_harness_root ②~④ 와 같은 규칙(env 는 부르는 쪽): 지도 1줄 → 팩 체크아웃 꼴. 못 풀면 ""."""
    d = Path(__file__).resolve().parent
    m = d / "../HARNESS_ROOT"
    if m.is_file():
        lines = m.read_text(encoding="utf-8").splitlines()
        c = lines[0].strip() if lines else ""
    elif (d / "../kit/fable-team").is_dir():
        c = str(d / "..")
    elif (d / "../../../kit/fable-team").is_dir():
        c = str(d / "../../..")
    else:
        c = ""
    return str(Path(c).resolve()) if c and (Path(c) / "kit/fable-team").is_dir() else ""


def team_root(team: str, root: Path | None = None, alt: bool = False) -> Path:
    """팀 폴더 절대경로. alt=True = 쌍둥이 경로(꼴1↔꼴2 · 꼴3 은 쌍둥이 없음 = TeamPathError)."""
    rel = team_rel(team, root)
    base = root or repo_root()
    if rel.startswith(("$FT_HARNESS_ROOT/", "${FT_HARNESS_ROOT}/")):
        if alt:
            raise TeamPathError(f"ERROR {team} 은 꼴3 이라 쌍둥이 경로가 없다")
        # 꼴3 순서(r386 r3): ①env FT_HARNESS_ROOT ②설치본 지도(셸 ft_harness_root 와 같은 규칙) ③TeamPathError
        hr = os.environ.get("FT_HARNESS_ROOT", "") or _harness_root_from_map()
        if not hr or not Path(hr).is_dir():
            env = os.environ.get("FT_HARNESS_ROOT") or "<없음>"
            raise TeamPathError(f"ERROR {team} 폴더가 $FT_HARNESS_ROOT 꼴인데 env 가 없거나 폴더가 아니다: {env}")
        return Path(hr.rstrip("/") + "/" + rel.split("/", 1)[1].rstrip("/"))
    if rel.startswith("design/teams/"):
        out = f"{base}/{rel.replace('design/teams/', 'design/', 1)}" if alt else f"{base}/{rel}"
    else:
        out = f"{base}/design/teams/{team}/" if alt else f"{base}/{rel}"
    return Path(out.rstrip("/"))


def team_in(root: Path | str, team: str) -> Path:
    """그 «루트(워크트리 포함)» 의 design/TEAMS.md 로 푼 팀 폴더 — FT_TEAMS_MD 는 보지 않는다(셸 ft_team_in 과 같다)."""
    saved = os.environ.pop("FT_TEAMS_MD", None)
    try:
        return team_root(team, Path(root))
    finally:
        if saved is not None:
            os.environ["FT_TEAMS_MD"] = saved
