"""ft_team_lib — 팀 폴더 단일 출처(파이썬 쪽 · R382b). 셸 ft-team-lib.sh 와 «같은 규칙» — 시험(test_team_literal_paths.sh)이 두 구현의 출력 동치를 대조한다.

TEAMS.md «폴더» 칸(3번째 열) 3꼴을 푼다 — 도구는 `design/<팀>/` 을 글자로 박지 않고 team_root/team_in 만 부른다.
  꼴1 `design/<팀>/` · 꼴2 `design/teams/<팀>/` · 꼴3 `$FT_HARNESS_ROOT/design/<팀>/`(env 치환 · 하네스 팩 분리 뒤)
실패는 TeamPathError — 옛 `design/<팀>/` 으로 되돌아가지 않는다(#0 RULE).
env: FT_REPO_ROOT(기본 git 루트) · FT_TEAMS_MD(기본 <루트>/design/TEAMS.md · team_in 은 무시) · FT_HARNESS_ROOT(꼴3 치환값)
ref 판(r479 · 셸 ft_team_cands_ref 와 같은 규칙): team_rows_ref · team_cands_ref · team_in_ref — 명단 = `git show <ref>:design/TEAMS.md` · 폴더 = 그 루트에 실재하는 후보
쌍둥이 판(r495 · 셸 ft_team_in_ref 와 같은 규칙): team_in_ref 가 쌍둥이 둘 다 실재면 ref 트리(ls-tree -d)에 있는 쪽 + stderr `WARN TWIN-STALE` · ref 에 둘 다 = 명단 꼴 + `WARN TWIN-BOTH` · ref 에 둘 다 없음 = TeamPathError
문서 본문 ref 판(r517): team_doc_ref — ref 명단 후보의 `<ref>:<후보>/<파일>` 본문 · ref 에 없음 = None · 못 읽음 = TeamPathError(ft_decision_count 의 planner 표)
sparse 판(r486): team_root·team_in·team_in_ref 가 «tracked 인데 sparse 로 디스크에 없음» 을 SparseHidden(TeamPathError) 로 말한다 — 메시지 `SPARSE-HIDDEN <경로> …`(셸 ft_team_root 와 같은 글자) · team_cands_ref 는 «실재 여부 무관» 그대로
"""
from __future__ import annotations

import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

_FORM = re.compile(r"^(\$FT_HARNESS_ROOT/|\$\{FT_HARNESS_ROOT\}/)?design/(teams/)?[a-z0-9][a-z0-9_-]*/$")


class TeamPathError(RuntimeError):
    pass


class RefReadError(TeamPathError):
    """r839: ref 읽기 규칙 위반(못 읽음·빈 응답 2회·예산 소진·판정 불가) = rc4 — «없음/파일 없음»(TeamPathError · rc1)과 가른다."""


class SparseHidden(TeamPathError):
    """r486: 폴더가 tracked 인데 sparse 체크아웃(r444 · 나노 = 자기 팀 design 만)으로 디스크에 없다 — 일반 «없음» 실패와 가른다."""

    def __init__(self, rel: str):
        super().__init__(f"SPARSE-HIDDEN {rel} — 이 워크트리는 자기 팀 폴더만 체크아웃(r444) · 전체 사본 = ft-scratch-repo.sh <base> 에서 돌려라")
        self.rel: str = rel


def _git_out(base: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(base), *args], capture_output=True, text=True, timeout=7)


REF_BUDGET_S = 70.0   # r839 r4: ref 읽기 전체 예산(초 · 프로세스 첫 조회 기준) — 7초 룰 × 여러 조회를 감싼다(FT_REF_BUDGET_SEC 로 덮기·시험 전용)
_REF_T0: float | None = None


def _ref_remaining() -> float:
    """남은 예산(초) — 첫 조회 때 시작 시각을 잡고 예산에서 뺀다. 0 이하면 예산 소진(미종료 0)."""
    global _REF_T0
    if _REF_T0 is None:
        _REF_T0 = time.monotonic()
    try:
        budget = float(os.environ.get("FT_REF_BUDGET_SEC") or REF_BUDGET_S)
    except ValueError:
        budget = REF_BUDGET_S
    return _REF_T0 + budget - time.monotonic()


def _git_once(base: Path | str, args: list[str], lim: float) -> tuple[int, str, str]:
    """git 1회 — lim 초 상한 · 넘으면 프로세스 그룹 TERM → 0.5초 뒤 KILL(자식까지) · (rc, stdout, stderr) · rc 124 = 상한 초과 · 128 = 실행 실패."""
    try:
        p = subprocess.Popen(["git", "-C", str(base), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             stdin=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return 128, "", ""
    try:
        out, err = p.communicate(timeout=lim)
    except subprocess.TimeoutExpired:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(p.pid, sig)
            except (ProcessLookupError, PermissionError):
                pass
            if sig == signal.SIGTERM:
                try:
                    p.wait(0.5)
                except subprocess.TimeoutExpired:
                    pass
        try:
            p.communicate(timeout=2)
        except (subprocess.TimeoutExpired, ValueError):
            pass
        return 124, "", ""
    return p.returncode, (out or b"").decode("utf-8", "replace"), (err or b"").decode("utf-8", "replace")


def ref_read(base: Path | str, *args: str) -> str:
    """r839 r4 — ref 조회 공용 규칙(셸 ft-team-lib.sh ref_read 와 같은 규칙 · 시험이 두 구현을 대조):
    ① 시도당 7초 상한 ② stdout 빈 값(rc0)이면 딱 1회 재시도 ③ 그래도 빈 값 = «빈 응답 2회» TeamPathError
    ④ rc≠0 = 재시도 없이 «못 읽음» TeamPathError ⑤ 남은 예산(REF_BUDGET_S=70) 소진 = TeamPathError — 미종료 0."""
    shown = " ".join(["git", "-C", str(base), *args])
    for _attempt in (1, 2):
        left = _ref_remaining()
        if left <= 0:
            raise RefReadError(f"ERROR ref 읽기 예산 소진({REF_BUDGET_S:g}s): {shown}")
        rc, out, _err = _git_once(base, list(args), min(7.0, left))
        if rc != 0:
            raise RefReadError(f"ERROR {shown} 못 읽음: rc={rc}")
        if out.strip():
            return out
    raise RefReadError(f"ERROR 빈 응답 2회: {shown}")


def _ref_present(base: Path | str, spec: str) -> bool:
    """ref 에 그 객체가 있나 — 존재 판정은 «출력» 도 «rc 만» 도 안 믿는다(r5 ②):
    rc0 = 있음 · rc1/128 + stderr 가 «does not exist in» = 그 ref 에 그 파일 없음 · 그 밖(명령 실패·리포 아님·ref 없음·상한) = TeamPathError «판정 불가».
    (빈 답을 «없음» 으로, 명령 실패를 «파일 없음» 으로 읽는 길을 닫는다 — DA⑥ r4 반례 ②)"""
    left = _ref_remaining()
    shown = f"git -C {base} cat-file -e {spec}"
    if left <= 0:
        raise RefReadError(f"ERROR ref 읽기 예산 소진({REF_BUDGET_S:g}s): {shown}")
    rc, _out, err = _git_once(base, ["cat-file", "-e", spec], min(7.0, left))
    if rc == 0:
        return True
    if rc in (1, 128) and re.search(r"(does not exist in|exists on disk, but not in)", err):
        return False   # «없음» 은 git 이 그렇게 «말할 때» 만(실패·빈 답을 없음으로 읽지 않는다)
    raise RefReadError(f"ERROR {shown} 판정 불가: rc={rc}" + (f" {err.strip().splitlines()[0][:120]}" if err.strip() else ""))


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
    """명단 = `git show <ref>:design/TEAMS.md`(R400 r3 · r479 — 체크아웃 사본이 옛 명단이어도·없어도 무관) · 못 읽음 = TeamPathError(옛 파일 후퇴 0).
    r839 r5 ①: 이 show 도 공용 ref_read 를 거친다(빈 답 = 1회 재시도 · 빈 답 2번 = rc4 · 예산) — ref_read 밖 git 호출 0."""
    base = Path(repo) if repo else repo_root()
    try:
        body = ref_read(base, "show", f"{ref}:design/TEAMS.md")
    except RefReadError as e:   # 하드 오류(못 읽음·빈 응답 2회·예산 소진)는 rc4 로 살려 올린다
        raise RefReadError(f"ERROR 명단 ref 못 읽음({ref}:design/TEAMS.md): {base} — {e}") from e
    except TeamPathError as e:
        raise TeamPathError(f"ERROR 명단 ref 못 읽음({ref}:design/TEAMS.md): {base} — {e}") from e
    return _rows_text(body)


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


def team_doc_ref(root: Path | str, team: str, name: str, ref: str = "origin/main") -> str | None:
    """r517: 정본 문서 «읽기» 본문 = ref 판(셸 ft_team_doc_ref 의 ref 쪽 · 임시 파일 0 · 체크아웃 명단·디스크 0) — ref 명단 후보(_cands_ref · 명단 꼴 먼저)마다
    `<ref>:<후보>/<name>` 이 ref 트리에 있으면 그 본문 · 모두 없음 = None · 명단 못 읽음·팀 없음·git 실패·리포 밖 후보(꼴3) = TeamPathError(조용한 None 0).
    r839 r4: 있나는 `cat-file -e`(출력을 안 믿는다) · 본문은 공용 ref_read(빈 응답 2회 = TeamPathError)."""
    base = Path(root)
    for c in _cands_ref(base, team, ref):
        try:
            path = f"{c.relative_to(base)}/{name}"
        except ValueError:
            raise TeamPathError(f"ERROR {team} 폴더가 리포 밖({c}) — ref 문서 읽기 대상 아님") from None
        if not _ref_present(base, f"{ref}:{path}"):
            continue
        return ref_read(base, "show", f"{ref}:{path}")
    return None


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


def data_root(common: Path | str) -> str:
    """r515: 셸 ft_data_root 의 파이썬 짝(대리 도구와 같은 데이터 루트) — env FT_ROOT · 없으면 <공용 루트>/.fable-team/LIVE_ROOT 1행(절대경로 폴더 · 아니면 TeamPathError) · 파일 없으면 공용 루트."""
    live = Path(common, ".fable-team", "LIVE_ROOT")
    if os.environ.get("FT_ROOT") or not live.is_file():
        return os.environ.get("FT_ROOT") or str(common)
    v = (live.read_text(encoding="utf-8").splitlines() or [""])[0].strip()
    if not (v.startswith("/") and os.path.isdir(v)):
        raise TeamPathError(f"ERROR LIVE_ROOT 가 절대경로 폴더가 아님: «{v}» ({live})")
    return v


def planner_queue(root: Path | str) -> Path:
    """r515 — 셸 ft_planner_queue 와 같은 규칙: FT_PLANNER_DIR · ref(FT_TEAMS_REF·origin/main) 명단 꼴 planner 폴더가 루트에 실재 · 아니면 공용 루트 .fable-team/state/planner (옛 체크아웃 꼴 후퇴 0 · 못 풀면 TeamPathError)."""
    if os.environ.get("FT_PLANNER_DIR"):
        return Path(os.environ["FT_PLANNER_DIR"]) / "AUTONOMY-QUEUE.md"
    first = _cands_ref(root, "planner", os.environ.get("FT_TEAMS_REF") or "origin/main")[0]
    if first.is_dir():
        return first / "AUTONOMY-QUEUE.md"
    g = _git_out(Path(root), "rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()
    if not g:
        raise TeamPathError(f"ERROR planner 큐 자리를 못 풂 — 명단 꼴 폴더 없음({first}) · 공용 루트(git common dir) 못 읽음: {root}")
    return Path(g[:-5] if g.endswith("/.git") else g) / ".fable-team/state/planner/AUTONOMY-QUEUE.md"


def _doc_dir() -> str:
    return (os.environ.get("TMPDIR") or "/tmp").rstrip("/")


def _write_temp(prefix: str, body: str) -> Path:
    fd, p = tempfile.mkstemp(prefix=prefix, dir=_doc_dir())
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(body if body.endswith("\n") else body + "\n")
    return Path(p)


def doc_ref_only_temp(root: Path | str, team: str, name: str, ref: str | None = None) -> Path:
    """r839: 정본 문서 «ref 본문만» 을 임시 파일로(디스크 0 · 셸 ft_team_doc_ref_only 의 짝) — 없음·못 읽음 = TeamPathError 1줄."""
    r = ref or os.environ.get("FT_TEAMS_REF") or "origin/main"
    body = team_doc_ref(root, team, name, r)
    if body is None:
        raise TeamPathError(f"ERROR {team} {name} 가 {r} 에 없거나 못 읽었다(디스크 0 · 명단 {r}:design/TEAMS.md)")
    return _write_temp("ft-team-doc.", body)


def planner_queue_ref_temp(root: Path | str, ref: str | None = None, repo: str | None = None) -> Path:
    """r839: 오빠 큐(AUTONOMY-QUEUE.md) «ref 본문» 을 임시 파일로(디스크 0 · 셸 ft_planner_queue_ref 의 짝).
    실패 문구 = 기준판 바이트 그대로 1줄(`ERROR 오빠 큐 origin/main 판을 못 읽음: <ref>:<rel>` · 명단 실패는 `ERROR planner 명단(…)을 못 읽음: <루트>`) — 호출자가 덧붙이지 않는다(r5 ④)."""
    r = ref or os.environ.get("FT_TEAMS_REF") or "origin/main"
    base = Path(repo or os.environ.get("FT_LEDGER_REPO") or root)
    try:
        first = _cands_ref(root, "planner", r)[0]
    except TeamPathError:
        raise TeamPathError(f"ERROR planner 명단({r}:design/TEAMS.md)을 못 읽음: {root}") from None
    try:
        rel = str(first.relative_to(Path(root))) + "/AUTONOMY-QUEUE.md"
    except ValueError:
        rel = f"{first}/AUTONOMY-QUEUE.md"
    spec = f"{r}:{rel}"
    bad = f"ERROR 오빠 큐 origin/main 판을 못 읽음: {spec}"
    try:
        if not _ref_present(base, spec):
            raise TeamPathError(bad)
        body = ref_read(base, "show", spec)
    except RefReadError as e:
        # 기준판 바이트 유지(④): «빈 파일» 은 기준판처럼 rc1 · 예산·판정 불가·못 읽음은 rc4(⑤)
        raise (TeamPathError(bad) if "빈 응답 2회" in str(e) else RefReadError(bad)) from None
    except TeamPathError:
        raise TeamPathError(bad) from None
    return _write_temp("ft-queue-ref.", body)


def main(argv: list[str]) -> int:
    """셸 호출용 진입점(r839 r5 — 셸에 재시도·예산·문구 로직을 두지 않는다): stdout = 본문/경로, rc 그대로.
    ref-read·present 실패 = rc4(판정 불가 1줄) · doc-ref·queue-ref 실패 = rc1(기준판 문구 1줄)."""
    cmd = argv[0] if argv else ""
    try:
        if cmd == "ref-read":
            sys.stdout.write(ref_read(argv[1], *argv[2:]))
            return 0
        if cmd == "present":
            return 0 if _ref_present(argv[1], argv[2]) else 1
    except TeamPathError as e:
        print(str(e), file=sys.stderr)
        return 4
    try:
        if cmd == "doc-ref":
            print(doc_ref_only_temp(argv[1], argv[2], argv[3], argv[4] if len(argv) > 4 else None))
            return 0
        if cmd == "queue-ref":
            print(planner_queue_ref_temp(argv[1], argv[2] if len(argv) > 2 else None, argv[3] if len(argv) > 3 else None))
            return 0
    except RefReadError as e:
        print(str(e), file=sys.stderr)
        return 4
    except TeamPathError as e:
        print(str(e), file=sys.stderr)
        return 1
    print("usage: ft_team_lib.py ref-read <리포> <git 인자…> | present <리포> <ref:경로> | doc-ref <루트> <팀> <파일> [<ref>] | queue-ref <루트> [<ref>] [<리포>]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
