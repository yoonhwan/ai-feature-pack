"""ft_team_lib — 팀 폴더 단일 출처(파이썬 쪽 · R382b). 셸 ft-team-lib.sh 와 «같은 규칙» — 시험(test_team_literal_paths.sh)이 두 구현의 출력 동치를 대조한다.

TEAMS.md «폴더» 칸(3번째 열) 3꼴을 푼다 — 도구는 `design/<팀>/` 을 글자로 박지 않고 team_root/team_in 만 부른다.
  꼴1 `design/<팀>/` · 꼴2 `design/teams/<팀>/` · 꼴3 `$FT_HARNESS_ROOT/design/<팀>/`(env 치환 · 하네스 팩 분리 뒤)
실패는 TeamPathError — 옛 `design/<팀>/` 으로 되돌아가지 않는다(#0 RULE).
env: FT_REPO_ROOT(기본 git 루트) · FT_TEAMS_MD(기본 <루트>/design/TEAMS.md · team_in 은 무시) · FT_HARNESS_ROOT(꼴3 치환값)
ref 판(r479 · 셸 ft_team_cands_ref 와 같은 규칙): team_rows_ref · team_cands_ref · team_in_ref — 명단 = `git show <ref>:design/TEAMS.md` · 폴더 = 그 루트에 실재하는 후보
쌍둥이 판(r495 · 셸 ft_team_in_ref 와 같은 규칙): team_in_ref 가 쌍둥이 둘 다 실재면 ref 트리(ls-tree -d)에 있는 쪽 + stderr `WARN TWIN-STALE` · ref 에 둘 다 = 명단 꼴 + `WARN TWIN-BOTH` · ref 에 둘 다 없음 = TeamPathError
sparse 판(r486): team_root·team_in·team_in_ref 가 «tracked 인데 sparse 로 디스크에 없음» 을 SparseHidden(TeamPathError) 로 말한다 — 메시지 `SPARSE-HIDDEN <경로> …`(셸 ft_team_root 와 같은 글자) · team_cands_ref 는 «실재 여부 무관» 그대로
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

_FORM = re.compile(r"^(\$FT_HARNESS_ROOT/|\$\{FT_HARNESS_ROOT\}/)?design/(teams/)?[a-z0-9][a-z0-9_-]*/$")


class TeamPathError(RuntimeError):
    pass


class SparseHidden(TeamPathError):
    """r486: 폴더가 tracked 인데 sparse 체크아웃(r444 · 나노 = 자기 팀 design 만)으로 디스크에 없다 — 일반 «없음» 실패와 가른다."""

    def __init__(self, rel: str):
        super().__init__(f"SPARSE-HIDDEN {rel} — 이 워크트리는 자기 팀 폴더만 체크아웃(r444) · 전체 사본 = ft-scratch-repo.sh <base> 에서 돌려라")
        self.rel: str = rel


def _git_out(base: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(base), *args], capture_output=True, text=True, timeout=7)


def _check_sparse(base: Path, path: Path) -> None:
    """path 가 디스크에 없고 · 루트가 sparse 이고 · 그 경로가 tracked 면 SparseHidden. 그 밖(전체 체크아웃·untracked·디스크에 있음)은 아무것도 안 한다."""
    if path.exists():
        return
    try:
        rel = str(path.relative_to(base))
    except ValueError:
        return
    if _git_out(base, "config", "--bool", "core.sparseCheckout").stdout.strip() != "true":
        return
    if _git_out(base, "ls-files", "--error-unmatch", "--", rel).returncode == 0:
        raise SparseHidden(rel)


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
    return _rows_text(md.read_text(encoding="utf-8"))


def _rows_text(text: str) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in text.splitlines():
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
    out = _rel_path(team, rel, base, alt)
    if not alt and not rel.startswith(("$FT_HARNESS_ROOT/", "${FT_HARNESS_ROOT}/")):
        _check_sparse(Path(base), out)
    return out


def _rel_path(team: str, rel: str, base: Path, alt: bool) -> Path:
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


def team_rows_ref(ref: str = "origin/main", repo: Path | str | None = None) -> dict[str, str]:
    """명단 = `git show <ref>:design/TEAMS.md`(R400 r3 · r479 — 체크아웃 사본이 옛 명단이어도·없어도 무관) · 못 읽음 = TeamPathError(옛 파일 후퇴 0)."""
    base = Path(repo) if repo else repo_root()
    try:
        out = subprocess.run(["git", "-C", str(base), "show", f"{ref}:design/TEAMS.md"],
                             capture_output=True, text=True, timeout=7)
    except (OSError, subprocess.SubprocessError) as e:
        raise TeamPathError(f"ERROR 명단 ref 못 읽음({ref}:design/TEAMS.md): {base} — {e}") from e
    if out.returncode != 0:
        raise TeamPathError(f"ERROR 명단 ref 못 읽음({ref}:design/TEAMS.md): {base}")
    return _rows_text(out.stdout)


def _cands_ref(root: Path | str, team: str, ref: str) -> list[Path]:
    """셸 ft_team_cands_ref 와 같은 규칙 — 명단 꼴 먼저 · 쌍둥이 뒤 · 꼴3 은 쌍둥이 0 (실재 여부 무관)."""
    rows = team_rows_ref(ref, root)
    if team not in rows:
        raise TeamPathError(f"ERROR {team} 은 팀 명단({ref}:design/TEAMS.md)에 없다")
    out = [_rel_path(team, rows[team], Path(root), False)]
    if not rows[team].startswith(("$FT_HARNESS_ROOT/", "${FT_HARNESS_ROOT}/")):
        out.append(_rel_path(team, rows[team], Path(root), True))
    return out


def team_cands_ref(root: Path | str, team: str, ref: str = "origin/main") -> list[Path]:
    """«명단 = ref · 폴더 = 루트»(r479): ref 명단으로 푼 후보 중 그 루트에 실재하는 폴더만(명단 꼴 먼저)."""
    return [c for c in _cands_ref(root, team, ref) if c.is_dir()]


def _behind(base: Path, ref: str) -> str:
    out = _git_out(base, "rev-list", "--count", f"HEAD..{ref}")
    return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else "?"


def _twin_pick(base: Path, team: str, ref: str, hits: list[Path], cand: str) -> Path:
    """r495: 쌍둥이 둘 다 실재 → ref 트리(ls-tree -d)에 있는 쪽 · 한쪽 = 그것 + WARN TWIN-STALE · 둘 다 = 명단 꼴(hits[0]) + WARN TWIN-BOTH · 둘 다 없음 = TeamPathError(셸 ft_team_in_ref 와 같은 글자)."""
    onref = [c for c in hits if _git_out(base, "ls-tree", "-d", ref, "--", str(c.relative_to(base))).stdout.strip()]
    if len(onref) == 1:
        stale = next(c for c in hits if c != onref[0])
        print(f"WARN TWIN-STALE {stale} (ref 에 없음 · 체크아웃 ref 뒤 {_behind(base, ref)}커밋)", file=sys.stderr)
        return onref[0]
    if len(onref) == 2:
        print(f"WARN TWIN-BOTH {hits[0]} {hits[1]} (ref 에 둘 다 · 명단 꼴 {hits[0]})", file=sys.stderr)
        return hits[0]
    raise TeamPathError(f"ERROR {team} 폴더 실재 후보 2개 — 정확히 1개여야 한다(명단 {ref}:design/TEAMS.md · 후보 {cand}) (ref 에 둘 다 없음)")


def team_in_ref(root: Path | str, team: str, ref: str = "origin/main") -> Path:
    """team_in 의 ref 판 — 실재 후보 1개 = 그것 · 쌍둥이 2개 = ref 트리로 가름(r495 · _twin_pick) · 0 = TeamPathError(사유에 후보 · 추측 0)."""
    cands = _cands_ref(root, team, ref)
    hits = [c for c in cands if c.is_dir()]
    if not hits:
        for c in cands:
            _check_sparse(Path(root), c)
    cand = " ".join(map(str, cands))
    if len(hits) == 2:
        return _twin_pick(Path(root), team, ref, hits, cand)
    if len(hits) != 1:
        raise TeamPathError(f"ERROR {team} 폴더 실재 후보 {len(hits)}개 — 정확히 1개여야 한다(명단 {ref}:design/TEAMS.md · 후보 {cand})")
    return hits[0]
