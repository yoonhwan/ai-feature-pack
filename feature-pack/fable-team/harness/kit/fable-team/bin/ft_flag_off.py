"""ft_flag_off.py — «기본 꺼짐 FE 플래그인데 배포 설정에 켜는 값이 없는 것» 검출기 (R239 · 오빠 «왜 플랜팀 막힌 작업에 카운팅 안 됐나»).

꺼짐 패턴 = clients/web 코드의 `process.env.NEXT_PUBLIC_X === '1'|'true'`(`(override ?? process.env.X) === '1'` 꼴 포함 · 시험 파일 제외).
켜짐 판정 = docker/web.Dockerfile 에 `ARG <X>` 줄 «그리고» .github/workflows/cd-dev.yml 에 `<X>=(1|true)` 줄. 아니면 «결정 필요 1건».
읽기는 `git grep`/`git show <ref>` 만(로컬 · 네트워크 0 · 읽기 실패 = stderr ERROR + rc 4 — 숫자 지어내기 0).
CLI: --ref <ref>(기본 origin/main) --repo <루트>  → 행당 `FLAG-OFF <플래그> <파일:줄> ARG=<있음|없음> 배포값=<없음|값>`
     --new-between <옛> <새>  → 새로 생긴 플래그만 `FLAG-OFF 새로 생김 …` (랜딩 직후 검사 · ft-merge-lib.sh fm_flag_off_new)
"""
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ft_decision_alarm import ReadError  # noqa: E402

CODE_PATHS = ["clients/web/src", "clients/web/app", "clients/web/middleware.ts"]
DOCKERFILE, CD_DEV = "docker/web.Dockerfile", ".github/workflows/cd-dev.yml"
GREP_ERE = r"process\.env\.NEXT_PUBLIC_[A-Z0-9_]+\)?[[:space:]]*===[[:space:]]*['\"](1|true)['\"]"
FLAG_RE = re.compile(r"process\.env\.(NEXT_PUBLIC_[A-Z0-9_]+)\)?\s*===\s*['\"](?:1|true)['\"]")
TEST_FILE = re.compile(r"(^|/)__tests__/|\.(test|spec)\.tsx?$")


def git(repo, timeout, *args):
    try:
        return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise ReadError(f"git {args[0]} {timeout:g}s 초과")
    except OSError as e:
        raise ReadError(f"git 실행 불가: {e}")


def per_call(timeout, deadline):
    """조회 1회의 상한 — 마감 시각(monotonic)이 있으면 min(자기 상한, 남은 시간) · 남은 시간 0 이하 = 조회 0 + 예산 초과(R303 DA⑥ H1)."""
    if deadline is None:
        return timeout
    left = deadline - time.monotonic()
    if left <= 0:
        raise ReadError("git 조회 전체 예산 초과")
    return min(timeout, left)


def first_uses(repo, ref, timeout, deadline=None):
    """{플래그: '파일:줄'} — 시험 파일 제외 · 플래그당 첫 위치."""
    p = git(repo, per_call(timeout, deadline), "grep", "-n", "-E", GREP_ERE, ref, "--", *CODE_PATHS)
    if p.returncode == 1 and not p.stderr.strip():
        return {}  # 일치 0
    if p.returncode != 0:
        raise ReadError(f"git grep {ref} rc={p.returncode} {p.stderr.strip()[:120]}")
    found = {}
    for ln in p.stdout.splitlines():
        path, num, text = ln[len(ref) + 1:].split(":", 2)
        m = FLAG_RE.search(text)
        if m and not TEST_FILE.search(path):
            found.setdefault(m.group(1), f"{path}:{num}")
    return found


def show(repo, ref, path, timeout, deadline=None):
    p = git(repo, per_call(timeout, deadline), "show", f"{ref}:{path}")
    if p.returncode != 0:
        raise ReadError(f"git show {ref}:{path} rc={p.returncode} — 배포 설정을 못 읽어 판정 불가")
    return p.stdout


def scan(repo, ref, timeout=7.0, deadline=None):
    """[{flag, loc, arg(bool), deploy(str)}] — 켜져 있지 않은(결정 필요) 플래그만."""
    uses = first_uses(repo, ref, timeout, deadline)
    if not uses:
        return []
    docker, cd = show(repo, ref, DOCKERFILE, timeout, deadline), show(repo, ref, CD_DEV, timeout, deadline)
    rows = []
    for flag, loc in sorted(uses.items()):
        arg = re.search(rf"^\s*ARG\s+{flag}\b", docker, re.M) is not None
        m = re.search(rf"^\s*{flag}=(\S+)", cd, re.M)
        deploy = m.group(1) if m else ""
        if not (arg and deploy in ("1", "true")):
            rows.append({"flag": flag, "loc": loc, "arg": arg, "deploy": deploy})
    return rows


def open_flags(rows, decided):
    """결정 기록에 없는(켬/끔 + 판정 칸 채워진 행이 없는) 플래그만."""
    return [r for r in rows if r["flag"] not in decided]


def line(r):
    return f"FLAG-OFF {r['flag']} {r['loc']} ARG={'있음' if r['arg'] else '없음'} 배포값={r['deploy'] or '없음'}"


def new_between(repo, base, tip, timeout=7.0):
    old = {r["flag"] for r in scan(repo, base, timeout)}
    return [r for r in scan(repo, tip, timeout) if r["flag"] not in old]


def main(argv):
    ref, repo, nb = "origin/main", os.getcwd(), None
    while argv:
        if argv[0] == "--ref" and len(argv) >= 2:
            ref, argv = argv[1], argv[2:]
        elif argv[0] == "--repo" and len(argv) >= 2:
            repo, argv = argv[1], argv[2:]
        elif argv[0] == "--new-between" and len(argv) >= 3:
            nb, argv = (argv[1], argv[2]), argv[3:]
        else:
            print("usage: ft_flag_off.py [--ref <ref>] [--repo <dir>] [--new-between <옛> <새>]", file=sys.stderr)
            return 2
    try:
        if nb:
            for r in new_between(repo, *nb):
                print(f"FLAG-OFF 새로 생김 {r['flag']} {r['loc']} — planner 결정 건수에 1건 올라감")
        else:
            for r in scan(repo, ref):
                print(line(r))
    except ReadError as e:
        print(f"ERROR ft_flag_off: {e}", file=sys.stderr)
        return 4
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
