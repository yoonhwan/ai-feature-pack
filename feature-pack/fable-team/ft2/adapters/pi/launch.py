#!/usr/bin/env python3
"""ft 2.0 호출자 좌석 열기 — 배정·전달된 일 1개를 워크트리 + pi 좌석으로 «한 번만» 연다 (r1765).

코어는 일을 기록할 뿐 좌석을 열지 않는다(`close_next`·`reopen` 의 «spawn·tmux = 호출자»). 그 호출자가 이 명령이다.
① journal·state 읽기만(잠금·쓰기 0)으로 «최신 dispatch»(holder · attempt)를 찾고 그 attempt 가 전달되지 않았으면 열지 않는다
② 열기 의도를 내용 든 원자 예약(link · pid 든 claiming · r1929)으로 «한 번만» 만들어 두 번째 호출을 0 으로 만든다 ③ 의도가 잡히면 git 3호출(worktree add --no-checkout --detach → sparse-checkout set → checkout · r1846) →
`tmux new-session` 1회(-e K=V 5개 · 이미 뜬 서버의 새 pane 에도 env 가 간다). 실행권(claim·start)은 좌석 몫 ·
상한은 두 값이다(r1769): git·로컬 하네스 25초 · tmux(바깥 호출) 7초 · `--repo` 를 주면 그 리포에서 worktree 를 만든다 ·
실패는 의도 줄에 단계 + rc2 «복구 필요»(자동 재시도 0) + 복구 2줄 · 결과 낱말은 계약 8낱말 밖 0 · 부르는 법:
    python3 adapters/pi/launch.py --root R --team T --work W [--worktree 경로] [--repo 경로] [--role 역할] [--base ref] [--dry-run | --resume]
--resume(r1929) = 끊긴 열기(opening ∧ 열기 pid 죽음)를 같은 자리에서 attempt 당 1회 잇는다(.resume 예약 성공한 실행자만).
"""
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(os.path.dirname(HERE))
GIT_TIMEOUT, TMUX_TIMEOUT, USAGE = 25, 7, 64
OK, REFUSED, CORRUPT = "접수 성공", "접수 거부", "복구 필요"
FIELDS, REQUIRED = ("root", "team", "work", "worktree", "repo", "role", "base"), ("root", "team", "work")
STAMP = "%Y-%m-%dT%H:%M:%S"
NOHOOK = dict(os.environ, GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.hooksPath", GIT_CONFIG_VALUE_0=os.devnull)   # r1967 ② checkout hook 끔(= -c core.hooksPath · argv 그대로)


class Usage(Exception):
    """인자·값이 틀렸다 = rc 64 · 쓰기 0."""


def _load(rel, alias):
    spec = importlib.util.spec_from_file_location(alias, os.path.join(FT2, rel))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


projection, journal, record = (_load(os.path.join("core", name + ".py"), "ft2_launch_" + name)
                               for name in ("projection", "journal", "record"))
models = _load(os.path.join("tools", "models.py"), "ft2_launch_models")
planner = _load(os.path.join("adapters", "pi", "launch_plan.py"), "ft2_launch_plan")
goal_close = _load(os.path.join("tools", "goal_close.py"), "ft2_launch_goal_close")   # r1947: 첫 본문 가운데 구 = 모듈 판
cleaner = _load(os.path.join("adapters", "pi", "launch_cleanup.py"), "ft2_launch_cleanup")   # r1967 ③ 반쪽 치우기


def parse(argv):
    """`--이름 값` + `--dry-run` → 인자 dict. 모르는 이름·값 빠짐 = Usage(쓰기 «전»)."""
    given = {"dry": "--dry-run" in argv, "resume": "--resume" in argv}
    rest = [token for token in argv if token not in ("--dry-run", "--resume")]
    while rest:
        name, rest = rest[0][2:], rest[1:]
        if not name or name not in FIELDS or not rest:
            raise Usage("인자 꼴: --이름 값 (받은 것 %r)" % ("--" + name,))
        given[name], rest = rest[0], rest[1:]
    missing = [name for name in REQUIRED if not given.get(name)]
    if missing:
        raise Usage("값 빠짐: " + ",".join("--" + name for name in missing))
    return given


def seat(root, team, work):
    """최신 dispatch 줄 → (holder, attempt, 사유) — 그 attempt 가 전달 «되지 않았으면» 열지 않는다(A1 · DA R1).
    투영의 `deliveries` 는 «과거 전달 목록» 이라 최신 배정의 전달 여부가 아니다 — journal 줄로 확인한다."""
    runtime = projection.runtime_path(root, team)
    if not os.path.isdir(runtime):
        return None, None, "runtime 없음 = 배정·전달 없음(바깥 호출 0)"
    node = journal.Journal(runtime, rec=record)
    records = node.records()
    state = record.recover_state(node.state(), records)
    latest = [rec for rec in records if rec.get("kind") == "dispatch" and rec.get("work") == work]
    if not latest:
        return None, None, "배정 없음 — 열지 않는다(바깥 호출 0)"
    attempt = latest[-1].get("attempt")
    if attempt not in list((state.get("deliveries") or {}).get(work) or []):
        return None, None, "최신 dispatch(%s) 미전달 — 열지 않는다(바깥 호출 0)" % attempt
    return latest[-1].get("holder"), attempt, ""


def call(cmd, cwd, env, timeout):
    """바깥 호출 1회 — 상한은 부르는 쪽이 정한다(git 25초 · tmux 7초 · 하드 룰 12). (rc, 진단 1줄) · 넘치거나 실행 실패 = rc None."""
    try:
        done = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, str(exc).splitlines()[0][:200]
    return done.returncode, (done.stderr or done.stdout).strip()[:200]


def write_intent(path, payload):
    """의도 줄 1개 = JSON 1줄. 같은 자리를 다시 쓰면 «마지막 상태» 만 남는다 · tmp → replace(빈 의도 판독 0 · r1929)."""
    with open(path + ".w", "w", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
    os.replace(path + ".w", path)


def read_intent(path):
    """의도 1줄 — 못 읽으면 {} (다른 호출이 만드는 중일 수 있다 · 추측 0)."""
    try:
        return json.loads(open(path, encoding="utf-8").read())
    except (OSError, ValueError):
        return {}


def failed(plan, env, step, detail, repo, extra=None, note=""):
    """실패 = 의도 줄에 단계 1개 — 그 줄이 있으면 다시 불러도 바깥 호출 0 · 사유에 복구 2줄(A3) · r1967 치움 = 복구 줄 대신 치움 1구."""
    write_intent(plan["intent"], dict(env, state="failed", step=step, reason=detail, repo=repo, at=time.strftime(STAMP), **(extra or {})))
    reason = "%s 실패: %s — 자동 재시도 0" % (step, detail or "진단 없음")
    if step.startswith("git"):
        reason += " · " + (note if (extra or {}).get("slot_returned") else note + " · " * bool(note) + planner.recovery(repo, plan["worktree"]))
    return dict(result=CORRUPT, opened=False, intent=plan["intent"], step=step, reason=reason), 2


def already(got, plan):
    """같은 일의 두 번째 호출 — 쓰기 0 · tmux 0. 열린 의도 = «이미 열림» · 실패 의도 = «복구 필요»."""
    if got.get("state") == "opened":
        return dict(result=OK, opened=False, intent=plan["intent"], worktree=got.get("worktree"), reason="이미 열림 — 같은 일은 한 번만 연다"), 0
    if got.get("state") == "failed":
        return dict(result=CORRUPT, opened=False, intent=plan["intent"], step=got.get("step"), reason="의도에 남은 실패(%s): %s — 자동 재시도 0" % (got.get("step"), got.get("reason"))), 2
    return dict(result=CORRUPT, opened=False, intent=plan["intent"], reason="의도가 있으나 상태 불명 — 열림 여부는 사람이 확인한다"), 2


def open_seat(given):
    """(결과 dict, rc). 순서 = 최신 dispatch·전달 → 역할 → (dry-run) → 의도 1번 → git 3호출 → tmux 1회."""
    root, team, work = os.path.abspath(given["root"]), given["team"], given["work"]
    role = given.get("role") or "session"
    holder, attempt, why = seat(root, team, work)
    if holder is None:
        return dict(result=REFUSED, work=work, reason=why), 1
    item = models.role(role)
    if item is None:
        return dict(result=CORRUPT, work=work, role=role, reason="불명(역할 %s — role-defaults.tsv 행 없음 · 대신 0)" % role), 2
    repo = os.path.abspath(given.get("repo") or root)
    base = given.get("base") or planner.DEFAULT_BASE      # r1780 A1: 기준 ref 이름(원문 보존)
    env = planner.seat_env(root, team, work, holder, attempt)
    folder, tag = os.path.join(projection.runtime_path(root, team), "launch"), "%s@%s" % (work, attempt)
    row = planner.card_row(root, team)               # r1895: 첫 본문 카드 경로 · 표 행 없음 = 거절(바깥 호출 0)
    if row is None:
        return dict(result=REFUSED, work=work, reason="카드 루트 표 행 없음 — 바깥 호출 0"), 1
    tail = goal_close.phrase(root, team, "nano", "first_body_tail", {"da": planner.da_seat(root, team)})   # r1947: 같은 프로세스 1회 · 파일 읽기뿐 · None = 내장 구
    mark, body = planner.first_body(env, row, tail)
    plan = planner.plan_of(folder, tag, root, team, holder, item["argv"], given.get("worktree"), repo, env, body, base)
    if given.get("dry"):
        return dict(result=OK, dry_run=True, work=work, attempt=attempt, holder=holder, role=item["role"], repo=repo, base=base,
                    model=item["model"], effort=item["effort"], timeouts={"git": GIT_TIMEOUT, "tmux": TMUX_TIMEOUT},
                    paths=plan, argv={key: plan[key] for key in ("git", "sparse", "checkout", "tmux")}, env=env), 0
    os.makedirs(os.path.dirname(plan["intent"]), exist_ok=True)
    own = dict(pid=os.getpid(), started=time.time())   # r1929: 열기 pid · 시각(keeper 가 죽음을 판정)
    if given.get("resume"):
        return resume(plan, env, repo, dict(own, kind="resume"), (item, base, mark))
    if not planner.reserve(plan["intent"], dict(env, state="claiming", kind="open", **own)):   # link 예약이 유일한 판정(M3)
        return already(read_intent(plan["intent"]), plan)
    if plan["pi_bin"] is None:                    # r1892: 못 찾으면 git·tmux 부르기 전 실패 의도(다시 불러도 바깥 호출 0)
        return failed(plan, env, "pi 없음", "PATH·~/.local/bin 에 pi 없음", repo)
    if not os.path.isfile(planner.seat_tools()):  # r1905: 좌석 도구 없으면 git·tmux 전 실패(조용한 생략 0)
        return failed(plan, env, "좌석 도구 없음", "판정 불가 좌석 도구 없음 %s" % planner.seat_tools(), repo)
    for argv, label in planner.checks(repo, base, given.get("repo")):   # A2: 리포(--repo 때만)·기준 ref(늘 · r1780) 확인 — 실패면 아무것도 열지 않는다
        rc, detail = planner.checked(argv, *call(argv, repo, None, GIT_TIMEOUT))
        if rc != 0:
            os.unlink(plan["intent"])         # 거절 = 의도 0(방금 만든 표식만 지운다)
            return dict(result=REFUSED, work=work, repo=repo, base=base,
                        reason="%s: %s — 바깥 호출 0" % (label, detail or "진단 없음")), 1
    sha = detail                                # 마지막 확인 = 기준 ref → 40자 sha(실제 argv 끝 · 의도 base_sha)
    write_intent(plan["intent"], dict(env, state="opening", role=item["role"], repo=repo, base=base, base_sha=sha, body_mark=mark, at=time.strftime(STAMP), **own))
    os.makedirs(os.path.dirname(plan["worktree"]), exist_ok=True)
    steps = (("git add", planner.at_sha(plan["git"], sha)), ("git sparse", plan["sparse"]), ("git checkout", plan["checkout"]))
    return finish(plan, env, steps, repo, sha, (item, base, mark))


def resume(plan, env, repo, own, keep):
    """r1929 ③ 이어 열기 — 첫 동작 = .resume 예약(attempt 당 1개 = 횟수 그 자체) · EEXIST = 부작용 0 rc1 · 예약 뒤 실패 = failed(.resume 남김)."""
    if not planner.reserve(plan["intent"] + ".resume", own):
        return dict(result=REFUSED, intent=plan["intent"], reason="이미 복구 예약 — 이어 열기는 attempt 당 1회 · 부작용 0"), 1
    got = read_intent(plan["intent"])
    if got.get("state") != "opening":
        return already(got, plan)
    if planner.pid_state(got.get("pid"), got.get("started")) != "dead":
        return dict(result=REFUSED, intent=plan["intent"], reason="열기 pid 살아 있음·판정 불가 — 이어 열기 0"), 1
    steps = planner.resume_plan(plan, repo, got.get("base_sha"), GIT_TIMEOUT)
    if steps is None:
        return failed(plan, env, "끊긴 열기 · 자리 불일치", "worktree 목록·HEAD ≠ base_sha %s" % got.get("base_sha"), repo)
    return finish(plan, env, steps, repo, got["base_sha"], keep)


def finish(plan, env, steps, repo, sha, keep):
    """git 단계 → tmux 1회 → 살아 있음 1회 → opened (처음 열기·이어 열기 공통 · 상한 그대로)."""
    item, base, mark = keep
    made = {}
    for step, argv in steps:
        new = step == "git add" and not os.path.lexists(plan["worktree"])   # r1967 ⓐ 생성 영수 = add 직전 경로 부재 ∧ add rc0
        rc, detail = call(argv, repo, NOHOOK if step == "git checkout" else None, GIT_TIMEOUT)   # r1846: 호출마다 25초 · 실패 = 그 단계 이름 · 뒤 호출 0
        if rc != 0:
            return failed(plan, env, step, detail, repo, *cleaner.sweep(plan, repo, sha, made, GIT_TIMEOUT, TMUX_TIMEOUT))   # r1967 ③ 이번 호출이 만든 반쪽만
        if new:
            made = dict(add_ok=True, path_new=True)
            write_intent(plan["intent"], dict(read_intent(plan["intent"]), **made))
    rc, detail = call(plan["tmux"], None, dict(os.environ, **env), TMUX_TIMEOUT)
    if rc != 0:
        return failed(plan, env, "tmux", detail, repo)
    rc, detail = call(plan["alive"], None, dict(os.environ, **env), TMUX_TIMEOUT)   # r1892: 살아 있음 1회
    if rc != 0:
        return failed(plan, env, "tmux 즉시 종료", "세션 없음 — pi 실행 실패(PATH·인증) 의심 · %s" % (detail or "진단 없음"), repo)
    write_intent(plan["intent"], dict(env, state="opened", role=item["role"], worktree=plan["worktree"], base=base, base_sha=sha, body_mark=mark, at=time.strftime(STAMP)))
    hook = os.path.join(repo, ".git", "hooks", "post-checkout")   # r1967 ② cairn reconcile = 열기 «뒤» 1회 · 따로 25초 · 실패해도 열기 결과 그대로
    ran = "rc %s" % call([hook, "0" * 40, sha, "1"], plan["worktree"], None, GIT_TIMEOUT)[0] if os.access(hook, os.X_OK) else "hook 없음"
    return dict(result=OK, opened=True, work=env["FT2_WORK"], attempt=env["FT2_ATTEMPT"], holder=env["FT2_HOLDER"],
                worktree=plan["worktree"], intent=plan["intent"], reconcile=ran), 0


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
