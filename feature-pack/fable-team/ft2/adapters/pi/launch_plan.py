"""ft 2.0 좌석 열기의 계획 만들기 — launch.py 가 부르기만 한다(r1769 · 파일 200줄 규칙 분리).

여기 있는 것은 «바깥 호출 전에 정해지는 값» 뿐이다: 열기 argv · 좌석 env 5개 · 실패 사유의 복구 2줄.
바깥 호출·의도 쓰기는 launch.py 몫이다.
"""
import os
import shlex


def seat_env(root, team, work, holder, attempt):
    """좌석 env 5개 — `-e K=V` 로 tmux 에 넘기는 값과 같다(좌석 도구가 자기를 아는 데 필요한 전부)."""
    return dict(zip(("FT2_ROOT", "FT2_TEAM", "FT2_WORK", "FT2_HOLDER", "FT2_ATTEMPT"), (root, team, work, holder, attempt)))


def plan_of(folder, tag, root, team, holder, role_argv, worktree, repo, env):
    """의도·워크트리·열기 argv — `--detach`(가지 몰래 만들기 0) · git 은 `-C <repo>`(A2) · pi argv 는 역할 표 그대로(A5)."""
    path = os.path.abspath(worktree or os.path.join(root, ".fable-team", "teams", team, "worktrees", tag))
    pairs = [word for key, value in env.items() for word in ("-e", key + "=" + value)]
    return {"intent": os.path.join(folder, tag + ".intent"), "worktree": path,
            "git": ["git", "-C", repo, "worktree", "add", "--detach", path],
            "tmux": ["tmux", "new-session", "-d", "-s", holder, "-c", path] + pairs + ["pi"] + list(role_argv)}


def repo_check(repo):
    """대상 리포 확인 명령 1회(A2) — `--repo` 를 준 호출에서만 부른다(기본 = 지금 그대로)."""
    return ["git", "-C", repo, "rev-parse", "--show-toplevel"]


def recovery(repo, path):
    """git 단계 실패 사유에 붙는 복구 2줄 — 자동 지우기·자동 재시도 0(하드 룰 2 · A3).

    경로는 shlex.quote 로 인용한다 — 공백·따진부호가 든 repo·worktree 에서 안내를 bash 에 그대로 넘겨도
    경로가 갈라지지 않아야 한다(DA 보정 291508).
    """
    return ("복구 ⓐ git -C %s worktree remove --force --force %s (반쪽 worktree 가 남았을 때 · 사람 실행) "
            "ⓑ 같은 일 새 attempt = cli assign → deliver → launch" % (shlex.quote(repo), shlex.quote(path)))
