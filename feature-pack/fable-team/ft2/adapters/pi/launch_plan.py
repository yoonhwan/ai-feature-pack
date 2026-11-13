"""ft 2.0 좌석 열기의 계획 만들기 — launch.py 가 부르기만 한다(r1769 · 파일 200줄 규칙 분리).

여기 있는 것은 «바깥 호출 전에 정해지는 값» 뿐이다: 열기 argv · 좌석 env 5개 · 확인 argv·판정(r1780) · 실패 사유의 복구 2줄.
바깥 호출·의도 쓰기는 launch.py 몫이다.
"""
import os
import shlex
import shutil

DEFAULT_BASE = "origin/main"          # r1780 A1: 기본 가지 자동 판정 0(origin/HEAD 는 리포마다 다르다) · 이름 고정
HEX = frozenset("0123456789abcdef")


def seat_env(root, team, work, holder, attempt):
    """좌석 env 5개 — `-e K=V` 로 tmux 에 넘기는 값과 같다(좌석 도구가 자기를 아는 데 필요한 전부)."""
    return dict(zip(("FT2_ROOT", "FT2_TEAM", "FT2_WORK", "FT2_HOLDER", "FT2_ATTEMPT"), (root, team, work, holder, attempt)))


def pi_path(env_path):
    """pi 절대 경로 — tmux 는 부른 쪽 PATH 로 명령을 찾고 keeper(launchd) PATH 엔 ~/.local/bin 이 없다(r1892) · 못 찾음 = None."""
    found = shutil.which("pi", path=os.pathsep.join([env_path or "", os.path.expanduser("~/.local/bin")]))
    return os.path.abspath(found) if found else None


def card_row(root, team):
    """카드 루트 행(keeper_next.cards 와 같은 표 · 팀 행 > * 행) → (repo 절대 경로, ref, 카드 폴더) · 없음 = None(r1895)."""
    try:
        rows = [x.rstrip("\n").split("\t") for x in open(os.path.join(root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError):
        return None
    r = next((x for x in rows if x[0] == team), None) or next((x for x in rows if x[0] == "*"), None)
    return (os.path.abspath(os.path.join(root, r[1])), r[2], r[3].replace("*", team)) if r else None


def first_body(env, row):
    """(body_mark, 첫 본문 1줄) — pi `[messages...]` 첫 메시지 · 카드 = 표의 repo + ref:path 그대로(r1895 · 바깥 호출 0)."""
    mark = "[발주] ft2 %s %s@%s" % (env["FT2_TEAM"], env["FT2_WORK"], env["FT2_ATTEMPT"])
    return mark, "%s 좌석 %s — 카드 %s %s:%s/대기/%s.md 를 통째로 읽고 그대로 수행 · ft2_claim → ft2_start 부터 · 산출·막힘은 팀 master 에 mbox" % (mark, env["FT2_HOLDER"], *row, env["FT2_WORK"])


def plan_of(folder, tag, root, team, holder, role_argv, worktree, repo, env, body, base=DEFAULT_BASE):
    """의도·워크트리·열기 argv — `--detach`(가지 몰래 만들기 0) · git 은 `-C <repo>`(A2) · pi argv 는 역할 표 그대로(A5).
    git argv 끝 = 기준 ref 이름(r1780) — dry-run 은 이 이름 그대로 보이고, 실제 실행은 `at_sha` 로 확인한 sha 로 바꾼다."""
    path = os.path.abspath(worktree or os.path.join(root, ".fable-team", "teams", team, "worktrees", tag))
    pairs = [word for key, value in env.items() for word in ("-e", key + "=" + value)]
    pi = pi_path(os.environ.get("PATH"))
    return {"intent": os.path.join(folder, tag + ".intent"), "worktree": path,
            "git": ["git", "-C", repo, "worktree", "add", "--no-checkout", "--detach", path, base],
            # r1846: 빈 자리 → sparse(출처 = 1.x r835 ft_sparse_patterns · 남의 팀 design 제외) → checkout · 큰 리포도 25초 안
            "sparse": ["git", "-C", path, "sparse-checkout", "set", "--no-cone", "/*", "!/design/teams/*/", "/design/teams/%s/" % team],
            "checkout": ["git", "-C", path, "checkout", "-q"],
            "tmux": ["tmux", "new-session", "-d", "-s", holder, "-c", path] + pairs + [pi or "pi"] + ["--approve"] + list(role_argv) + [body],
            "pi_bin": pi, "alive": ["tmux", "has-session", "-t", "=" + holder]}   # r1892: new-session rc0 뒤 1회


def repo_check(repo):
    """대상 리포 확인 명령 1회(A2) — `--repo` 를 준 호출에서만 부른다(기본 = 지금 그대로)."""
    return ["git", "-C", repo, "rev-parse", "--show-toplevel"]


def base_check(repo, ref):
    """기준 ref 확인 1회(r1780 A2) — `--repo` 유무와 무관하게 늘 부른다 · 성공 = stdout 40자 sha · fetch 0(A5)."""
    return ["git", "-C", repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}"]


def checks(repo, base, explicit):
    """git 단계 앞 확인 목록 = (argv, 거절 사유 머리). 리포 확인은 `--repo` 때만 · 기준 ref 확인은 늘 · 기준이 마지막."""
    head = [(repo_check(repo), "대상 리포 아님(%s)" % repo)] if explicit else []
    return head + [(base_check(repo, base), "기준 ref 없음(%s)" % base)]


def checked(argv, rc, detail):
    """확인 1회 결과 → (rc, 진단 또는 sha). 기준 ref 확인은 rc0 이어도 유효 40자 sha 가 없으면 거절이다(추측 0)."""
    if "--verify" not in argv:
        return rc, detail
    sha = next((word for word in (detail or "").split() if len(word) == 40 and set(word) <= HEX), "") if rc == 0 else ""
    return (0, sha) if sha else (1, "rc %s · %s" % (rc, detail or "빈 출력"))


def at_sha(git, sha):
    """실제 실행 git argv — 끝의 ref 이름을 확인한 sha 로 바꾼다(보정1 R1 · 확인 뒤 ref 가 움직여도 자리 = 기록한 sha)."""
    return git[:-1] + [sha]


def recovery(repo, path):
    """git 단계 실패 사유에 붙는 복구 2줄 — 자동 지우기·자동 재시도 0(하드 룰 2 · A3).

    경로는 shlex.quote 로 인용한다 — 공백·따진부호가 든 repo·worktree 에서 안내를 bash 에 그대로 넘겨도
    경로가 갈라지지 않아야 한다(DA 보정 291508).
    """
    return ("복구 ⓐ git -C %s worktree remove --force --force %s (반쪽 worktree 가 남았을 때 · 사람 실행) "
            "ⓑ 같은 일 새 attempt = cli assign → deliver → launch" % (shlex.quote(repo), shlex.quote(path)))
