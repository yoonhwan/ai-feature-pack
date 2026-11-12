#!/usr/bin/env python3
"""ft 2.0 호출자 좌석 열기 — 배정·전달된 일 1개를 워크트리 + pi 좌석으로 «한 번만» 연다 (r1765).

코어는 일을 기록할 뿐 좌석을 열지 않는다(`close_next`·`reopen` 의 «spawn·tmux = 호출자»). 그 호출자가 이 명령이다.
① 투영 읽기만(잠금·쓰기 0)으로 최신 dispatch(holder · attempt)를 찾는다 ② 열기 의도를 O_EXCL 로 «한 번만» 만들어
두 번째 호출을 0 으로 만든다 ③ 의도가 잡히면 `git worktree add` 1회 → `tmux new-session` 1회(env 5개).
실행권(claim·start)은 좌석 몫이라 쓰지 않는다. 바깥 호출 7초 · 실패는 의도 줄에 단계로 남기고 rc2 «복구 필요»
(자동 재시도 0 · 세션 종료 0). 결과 낱말은 계약 8낱말 밖으로 나가지 않는다.
    python3 adapters/pi/launch.py --root R --team T --work W [--worktree 경로] [--role 역할] [--dry-run]
"""
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
TIMEOUT, USAGE = 7, 64
OK, REFUSED, CORRUPT = "접수 성공", "접수 거부", "복구 필요"
FIELDS, REQUIRED = ("root", "team", "work", "worktree", "role"), ("root", "team", "work")
STAMP = "%Y-%m-%dT%H:%M:%S"


class Usage(Exception):
    """인자·값이 틀렸다 = rc 64 · 쓰기 0."""


def _load(rel, alias):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(FT2, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection = _load(os.path.join("core", "projection.py"), "ft2_launch_projection")
models = _load(os.path.join("tools", "models.py"), "ft2_launch_models")


def parse(argv):
    """`--이름 값` + `--dry-run` → 인자 dict. 모르는 이름·값 빠짐 = Usage(쓰기 «전»)."""
    given, index = {}, 0
    while index < len(argv):
        token = argv[index]
        if token == "--dry-run":
            given["dry"], index = True, index + 1
        elif token.startswith("--") and token[2:] in FIELDS and index + 1 < len(argv):
            given[token[2:]], index = argv[index + 1], index + 2
        else:
            raise Usage("인자 꼴: --이름 값 (받은 것 %r)" % (token,))
    missing = [name for name in REQUIRED if not given.get(name)]
    if missing:
        raise Usage("값 빠짐: " + ",".join("--" + name for name in missing))
    return given


def seat(projected, work):
    """투영 1행 → (holder, attempt). 배정도 전달도 없으면 (None, None) — 열지 않는다(A1)."""
    row = dict((projected.get("works") or {}).get(work) or {})
    holder, deliveries = (row.get("owner") or {}).get("holder"), list(row.get("deliveries") or [])
    return (holder, deliveries[-1]) if holder and deliveries else (None, None)


def plan_of(root, team, work, attempt, holder, role_argv, worktree):
    """의도·워크트리·열기 argv. 런타임 자리는 코어와 같은 한 곳 · pi argv 는 역할 표 그대로(A5)."""
    folder, tag = os.path.join(projection.runtime_path(root, team), "launch"), "%s@%s" % (work, attempt)
    path = os.path.abspath(worktree or os.path.join(root, ".fable-team", "teams", team, "worktrees", tag))
    return {"intent": os.path.join(folder, tag + ".intent"), "worktree": path,
            "git": ["git", "worktree", "add", path],
            "tmux": ["tmux", "new-session", "-d", "-s", holder, "-c", path, "pi"] + list(role_argv)}


def seat_env(root, team, work, holder, attempt):
    """좌석 env 5개 — 좌석 도구(`ft2_claim` 등)가 자기를 아는 데 필요한 전부."""
    return {"FT2_ROOT": root, "FT2_TEAM": team, "FT2_WORK": work, "FT2_HOLDER": holder,
            "FT2_ATTEMPT": attempt}


def call(cmd, cwd, env):
    """바깥 호출 1회 — 상한 7초(하드 룰 12). (rc, 진단 1줄) · 넘치거나 실행 실패 = rc None."""
    try:
        done = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc).splitlines()[0][:200]
    return done.returncode, (done.stderr or done.stdout).strip()[:200]


def write_intent(path, payload):
    """의도 줄 1개 = JSON 1줄. 같은 자리를 다시 쓰면 «마지막 상태» 만 남는다."""
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def read_intent(path):
    """의도 1줄 — 못 읽으면 {} (다른 호출이 만드는 중일 수 있다 · 추측 0)."""
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def claimed(intent):
    """의도 1번 — O_EXCL 이 유일한 판정이다(«있나 보고 쓰기» 는 두 번 열린다 · M3)."""
    try:
        os.close(os.open(intent, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644))
    except FileExistsError:
        return False
    return True


def failed(plan, env, step, detail):
    """실패 = 의도 줄에 단계 1개 — 그 줄이 있으면 다시 불러도 바깥 호출 0(자동 재시도 0)."""
    write_intent(plan["intent"], dict(env, state="failed", step=step, reason=detail, at=time.strftime(STAMP)))
    return dict(result=CORRUPT, opened=False, intent=plan["intent"], step=step,
                reason="%s 실패: %s — 자동 재시도 0" % (step, detail or "진단 없음")), 2


def already(got, plan):
    """같은 일의 두 번째 호출 — 쓰기 0 · tmux 0. 열린 의도 = «이미 열림» · 실패 의도 = «복구 필요»."""
    if got.get("state") == "opened":
        return dict(result=OK, opened=False, intent=plan["intent"], worktree=got.get("worktree"),
                    reason="이미 열림 — 같은 일은 한 번만 연다"), 0
    if got.get("state") == "failed":
        return dict(result=CORRUPT, opened=False, intent=plan["intent"], step=got.get("step"),
                    reason="의도에 남은 실패(%s): %s — 자동 재시도 0" % (got.get("step"), got.get("reason"))), 2
    return dict(result=CORRUPT, opened=False, intent=plan["intent"],
                reason="의도가 있으나 상태 불명 — 열림 여부는 사람이 확인한다"), 2


def open_seat(given):
    """(결과 dict, rc). 순서 = 투영 → 배정·전달 → 역할 → (dry-run) → 의도 1번 → git 1회 → tmux 1회."""
    root, team, work = os.path.abspath(given["root"]), given["team"], given["work"]
    role = given.get("role") or "session"
    projected = projection.project(root, team)
    if projected.get("result") != OK:
        return dict(result=CORRUPT, work=work, reason=projected.get("reason") or "투영 판독 불가"), 2
    holder, attempt = seat(projected, work)
    if holder is None:
        return dict(result=REFUSED, work=work, reason="배정·전달 없음 — 열지 않는다(바깥 호출 0)"), 1
    item = models.role(role)
    if item is None:
        return dict(result=CORRUPT, work=work, role=role,
                    reason="불명(역할 %s — role-defaults.tsv 행 없음 · 다른 역할로 대신 0)" % role), 2
    plan = plan_of(root, team, work, attempt, holder, item["argv"], given.get("worktree"))
    env = seat_env(root, team, work, holder, attempt)
    if given.get("dry"):
        return dict(result=OK, dry_run=True, work=work, attempt=attempt, holder=holder, role=item["role"],
                    model=item["model"], effort=item["effort"], paths=plan,
                    argv={"git": plan["git"], "tmux": plan["tmux"]}, env=env), 0
    os.makedirs(os.path.dirname(plan["intent"]), exist_ok=True)
    if not claimed(plan["intent"]):
        return already(read_intent(plan["intent"]), plan)
    write_intent(plan["intent"], dict(env, state="opening", at=time.strftime(STAMP)))
    os.makedirs(os.path.dirname(plan["worktree"]), exist_ok=True)
    rc, detail = call(plan["git"], root, None)
    if rc != 0:
        return failed(plan, env, "git", detail)
    rc, detail = call(plan["tmux"], None, dict(os.environ, **env))
    if rc != 0:
        return failed(plan, env, "tmux", detail)
    write_intent(plan["intent"], dict(env, state="opened", worktree=plan["worktree"], at=time.strftime(STAMP)))
    return dict(result=OK, opened=True, work=work, attempt=attempt, holder=holder,
                worktree=plan["worktree"], intent=plan["intent"]), 0


def main(argv):
    try:
        out, rc = open_seat(parse(argv))
    except Usage as exc:
        out, rc = {"result": "사용법", "reason": str(exc)}, USAGE
    except (OSError, ValueError) as exc:      # 역할 표 손상·경로 오류 — 숨기지 않는다(추측 0)
        out, rc = {"result": CORRUPT, "reason": str(exc)}, 2
    sys.stdout.write(json.dumps(out, ensure_ascii=False, sort_keys=True) + "\n")
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
