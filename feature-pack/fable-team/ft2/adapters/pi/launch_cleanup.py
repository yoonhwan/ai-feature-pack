"""ft 2.0 좌석 열기 반쪽 치우기 (r1967 ③) — launch.py 가 git 단계 실패 뒤 1회 부른다(파일 200줄 규칙 분리).

치우는 것 = «이번 호출이 만든» 워크트리와 그 index.lock 뿐이다. 조건(master 고정 계약)이 하나라도 아니면 치우기 0(사람 복구 · 보존):
ⓐ 생성 영수 = 같은 호출이 add 직전 경로 부재 ∧ add rc0 (add_ok·path_new) ⓑ HEAD detached ∧ HEAD == base_sha(자기 커밋 0) ∧ tmux 0
ⓒ `git status --porcelain --ignored --untracked-files=all` 줄 전부 «D »(??·!!·수정 1줄도 0) ⓓ 판독 실패·시간 초과 = 0.
가지 삭제 0(launch 는 --detach) · 자동 재시도 0 · 칸 반환 기록(slot_returned) = remove rc0 ∧ 경로 부재 확인 뒤에만.
"""
import os
import subprocess


def run(argv, cwd=None, timeout=25):
    """바깥 호출 1회 → (rc, stdout 전체) · 넘침·실행 실패 = (None, "")(판독 실패 = 치우기 0)."""
    try:
        done = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None, ""
    return done.returncode, done.stdout


def why_keep(path, sha, alive, receipt, git_s, tmux_s):
    """(보존 사유 · status 원문) — 사유가 빈 문자열일 때만 치운다."""
    if not (receipt.get("add_ok") and receipt.get("path_new")):
        return "생성 영수 없음", ""
    if run(["git", "-C", path, "symbolic-ref", "-q", "HEAD"], timeout=git_s)[0] != 1:
        return "HEAD detached 아님·판독 실패", ""
    rc, head = run(["git", "-C", path, "rev-parse", "HEAD"], timeout=git_s)
    if rc != 0 or head.strip() != sha:
        return "자기 커밋 있음·판독 실패", ""
    if run(alive, timeout=tmux_s)[0] != 1:
        return "tmux 있음·판독 실패", ""
    rc, status = run(["git", "-C", path, "status", "--porcelain", "--ignored", "--untracked-files=all"], timeout=git_s)
    if rc != 0:
        return "status 판독 실패", ""
    if any(not line.startswith("D  ") for line in status.splitlines()):
        return "checkout 중간 꼴 밖 줄(??·!!·수정)", status
    return "", status


def index_lock(path):
    """워크트리 .git 파일의 gitdir → 그 index.lock 경로 · 못 읽음·worktrees 밖 = None."""
    try:
        head = open(os.path.join(path, ".git"), encoding="utf-8").read().strip()
    except (OSError, UnicodeError):
        return None
    gitdir = head[len("gitdir: "):] if head.startswith("gitdir: ") else ""
    return os.path.join(gitdir, "index.lock") if os.sep + "worktrees" + os.sep in gitdir else None


def sweep(plan, repo, sha, receipt, git_s=25, tmux_s=7):
    """(의도에 더할 칸 = 생성 영수 + 치우기 결과, 사유 1구) — 실패 의도에도 영수가 남는다."""
    extra, note = clear(plan, repo, sha, receipt, git_s, tmux_s)
    return dict(receipt, **extra), note


def clear(plan, repo, sha, receipt, git_s, tmux_s):
    """경로 없음 = ({}, "")(지금 그대로) · 치움 = status 보존본(<work>@<a>.cleanup.txt) 뒤 remove."""
    path = plan["worktree"]
    if not os.path.isdir(path):
        return {}, ""
    keep, status = why_keep(path, sha, plan["alive"], receipt, git_s, tmux_s)
    if keep:
        return {"cleanup": "보존 · " + keep}, "반쪽 보존(%s)" % keep
    note = plan["intent"][:-len(".intent")] + ".cleanup.txt"
    with open(note, "w", encoding="utf-8") as handle:
        handle.write(status)
    lock = index_lock(path)
    if lock and os.path.isfile(lock):
        os.unlink(lock)
    rc = run(["git", "-C", repo, "worktree", "remove", "--force", path], timeout=git_s)[0]
    if rc != 0 or os.path.lexists(path):
        return {"cleanup": "정리 실패 · 복구 필요(remove rc %s)" % rc}, "정리 실패 · 복구 필요(remove rc %s)" % rc
    return {"cleanup": "치움", "slot_returned": True, "cleanup_note": note}, "반쪽 치움 · 칸 반환(%s)" % os.path.basename(note)
