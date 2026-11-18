"""ft 2.0 좌석 열기의 계획 만들기 — launch.py 가 부르기만 한다(r1769 · 파일 200줄 규칙 분리).

여기 있는 것은 «바깥 호출 전에 정해지는 값» 뿐이다: 열기 argv · 좌석 env 5개 · 확인 argv·판정(r1780) · 실패 사유의 복구 2줄.
바깥 호출·의도 쓰기는 launch.py 몫이다. r1929: 내용 든 원자 예약(reserve) · 열기 pid 판정(pid_state) · 이어 열기 단계(resume_steps)도 여기 둔다.
"""
import itertools
import json
import os
import re
import shlex
import shutil
import subprocess
import time

DEFAULT_BASE = "origin/main"          # r1780 A1: 기본 가지 자동 판정 0(origin/HEAD 는 리포마다 다르다) · 이름 고정
HEX = frozenset("0123456789abcdef")
BAN = "main·ops/main-base push·병합·착지·설치·심링크·가지 삭제 0(= master·h 몫) · AGENTS.md «Landing the Plane» 은 이 좌석에 적용 0"   # r1900 금지 목록(두 길 공통)
LAND = "· 산출 = 가지 nano/<work> push + master 보고까지 · " + BAN   # r1900 첫 본문 끝 고정 1구 · r1930: 팀 DA 좌석을 못 읽을 때만 쓰는 옛 길
DIRECT = ("산출 = 가지 nano/<work> push → PR 열기(금지 목록 밖) → 팀 DA %s 에 판정 요청(5칸 = 대상 동결·판정 기준·상한·종료 조건·다음 수 · 근거 줄 = 세트 sha·PR 번호·"
          "카드 경로·시험 줄 · PR 번호 없으면 요청 아님) · 카드 상태의 HOLD 줄이 3 이면 DA 요청 0 · 팀 master 에 1줄 · 막힘 = 팀 master 에 mbox · ")   # r1930 산출은 팀장을 거치지 않는다
RECV = "쪽지 = bash %s/.fable-team/comm/mbox.sh recv %s · "   # r1933 2.0 나노 받는 길(첫 본문 1구)
CARDMAP = os.path.join(".fable-team", "teams", "%s", "runtime", "cards.tsv")   # r2030 짝 표(keeper_land.CARDMAP 과 같은 자리 · 팀장 append · 여기는 읽기만)
WAIT = re.compile(r"^(design/.+/indices)/대기/[^/]+\.md$")   # r2030 짝 표 경로 중 대기 단계(keeper_land.MAPPED 의 대기 갈래)
TEAMS = "design/TEAMS.md"   # r2082 팀 폴더 표(«팀»·«폴더» 칸) · 기준 sha tree 안 경로
UNREAD = "팀 폴더 표 못 읽음 — 제외 0"   # r2082 A2 의도 1칸
FOLDER = re.compile(r"design/(?:[A-Za-z0-9._-]+/)+")   # r2082 «폴더» 칸 꼴(glob 글자 0)
LIMIT = 12000   # r2082 A3 묶음 파일 수 상한 기본(env FT2_CHECKOUT_FILES)


def team_table(text):
    """r2082 A1·A2 — 기준 sha 의 design/TEAMS.md blob 글(None = 목록에 없음)의 첫 «팀»·«폴더» 표 → ({팀: 폴더}, 메모).
    호출 리포의 작업 트리·index·HEAD 는 읽지 않는다 · 목록에 없음 = ({}, "") · 칸을 못 읽음 = ({}, UNREAD)(열기는 막지 않는다)."""
    if text is None:
        return {}, ""
    rows = [[c.strip().strip("`") for c in x.strip().strip("|").split("|")] if x.lstrip().startswith("|") else None for x in text.splitlines()]
    at = next((i for i, r in enumerate(rows) if r and "팀" in r and "폴더" in r), None)
    if at is None:
        return {}, UNREAD
    t, f = rows[at].index("팀"), rows[at].index("폴더")
    got = {r[t]: r[f] for r in itertools.takewhile(bool, rows[at + 1:]) if len(r) > max(t, f) and FOLDER.fullmatch(r[f])}
    return (got, "") if got else ({}, UNREAD)


def with_teams(plan, team, text):
    """r2082 A1 — 남의 팀 폴더 제외 패턴을 내 팀 패턴 바로 뒤(짝 카드 폴더 앞 = 짝 카드는 그대로 포함)에 넣는다 · 내 팀이 표에 없으면 표의 모든 팀 폴더.
    기준 sha 가 정해지고 읽은 «뒤» 에만 부른다(dry-run 의 sparse 인자 = 기준판)."""
    folders, note = team_table(text)
    at = plan["sparse"].index("/design/teams/%s/" % team) + 1
    plan["sparse"][at:at] = ["!/" + folder for name, folder in folders.items() if name != team]
    plan["notes"].update({"sparse_note": note} if note else {})


def tree_read(repo, sha):
    """r2082 A3·A5 — 기준 sha 읽기 argv · 파일 목록(늘 1회) · TEAMS.md blob(목록에 있을 때만 1회)."""
    return (["git", "-C", repo, "ls-tree", "-r", "--name-only", "-z", sha],
            ["git", "-C", repo, "cat-file", "blob", "%s:%s" % (sha, TEAMS)])


def seat_env(root, team, work, holder, attempt):
    """좌석 env 5개 — `-e K=V` 로 tmux 에 넘기는 값과 같다(좌석 도구가 자기를 아는 데 필요한 전부)."""
    return dict(zip(("FT2_ROOT", "FT2_TEAM", "FT2_WORK", "FT2_HOLDER", "FT2_ATTEMPT"), (root, team, work, holder, attempt)))


def pi_path(env_path):
    """pi 절대 경로 — tmux 는 부른 쪽 PATH 로 명령을 찾고 keeper(launchd) PATH 엔 ~/.local/bin 이 없다(r1892) · 못 찾음 = None."""
    found = shutil.which("pi", path=os.pathsep.join([env_path or "", os.path.expanduser("~/.local/bin")]))
    return os.path.abspath(found) if found else None


def seat_tools():
    """좌석 도구 확장 = 이 파일 옆 ft2-seat.ts(설치본 루트 기준 · r1905) — pi 는 `-e` 로만 읽는다 · 전역 extensions 쓰기 0."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "ft2-seat.ts")


def card_row(root, team):
    """카드 루트 행(keeper_next.cards 와 같은 표 · 팀 행 > * 행) → (repo 절대 경로, ref, 카드 폴더) · 없음 = None(r1895)."""
    try:
        rows = [x.rstrip("\n").split("\t") for x in open(os.path.join(root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError):
        return None
    r = next((x for x in rows if x[0] == team), None) or next((x for x in rows if x[0] == "*"), None)
    return (os.path.abspath(os.path.join(root, r[1])), r[2], r[3].replace("*", team)) if r else None


def mapped_cards(root, team):
    """r2030 짝 표 대기 카드 {work: (repo 절대, ref, 경로)} — work 당 경로 정확히 1개 ∧ 꼴 …/indices/대기/X.md ∧ 그 indices 를 품은 카드 루트 표 행(팀 행 먼저).
    짝 표 없음 = {} · 짝 표·루트 표 판독 실패 = «짝 표 못 읽음»(부르는 쪽 = 지금 길 · keeper 는 로그 1줄)."""
    path, seen, out = os.path.join(root, CARDMAP % team), {}, {}
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh, open(os.path.join(root, ".fable-team", "state", "directive-roots.tsv"), encoding="utf-8") as rt:
            pairs, rows = [x.split("\t") for x in fh.read().splitlines() if x.strip()], [x.rstrip("\n").split("\t") for x in rt if not x.startswith("#") and len(x.split("\t")) >= 4]
    except (OSError, UnicodeError):
        return "짝 표 못 읽음"
    for x in pairs:
        seen.setdefault(x[0].strip(), []).append(x[1].strip() if len(x) == 2 else "")
    for work, paths in seen.items():
        m = WAIT.match(paths[0]) if len(paths) == 1 else None
        r = next((y for y in sorted(rows, key=lambda y: "*" in y[3]) if m and re.fullmatch(re.escape(y[3]).replace(r"\*", "[^/]+"), m.group(1))), None)
        out.update({work: (os.path.abspath(os.path.join(root, r[1])), r[2], paths[0])} if r else {})
    return out


def mapped_card(root, team, work):
    """r2030 이 work 의 짝 표 대기 카드 (repo, ref, 경로) — 짝 work 이름 또는 카드 stem(keeper 는 stem 으로 연다) · 없음·여럿·판독 실패 = None(지금 길)."""
    got = mapped_cards(root, team) if root else {}
    hits = {got[work]} if isinstance(got, dict) and work in got else {v for v in (got.values() if isinstance(got, dict) else ()) if os.path.basename(v[2]) == work + ".md"}
    return hits.pop() if len(hits) == 1 else None


def da_seat(root, team):
    """팀 명부(`<root>/.fable-team/seats-<팀>.json`)의 `_da` 좌석 이름 — 없음·빈 값·글자 아님·명부 못 읽음 = None(r1930 · 로컬 읽기뿐 · 임의 DA 0)."""
    try:
        with open(os.path.join(root, ".fable-team", "seats-%s.json" % team), encoding="utf-8") as handle:
            seat = json.load(handle).get("_da")
    except (OSError, ValueError, AttributeError, TypeError):
        return None
    return seat if isinstance(seat, str) and seat.strip() else None


def first_body(env, row, tail=None):
    """(body_mark, 첫 본문 1줄) — pi `[messages...]` 첫 메시지 · 카드 = 표의 repo + ref:path 그대로(r1895 · 바깥 호출 0).
    tail = goal-close 모듈 가운데 구 + `gc=<판> · `(r1947 · launch.py 가 읽어 넘김) · None = 내장 구 + «모듈 못 읽음» · 끝 = 코드 상수."""
    mark = "[발주] ft2 %s %s@%s" % (env["FT2_TEAM"], env["FT2_WORK"], env["FT2_ATTEMPT"])
    da = da_seat(env.get("FT2_ROOT"), env["FT2_TEAM"])   # r1930: 못 읽으면 옛 길(팀 master) + «DA 좌석 못 읽음»
    tail = tail + BAN if tail else "ft2_claim → ft2_start 부터 · 모듈 못 읽음 · " + (DIRECT % da + BAN if da else "DA 좌석 못 읽음 · 산출·막힘은 팀 master 에 mbox " + LAND)
    tail = RECV % (env.get("FT2_ROOT"), env["FT2_HOLDER"]) + tail   # r1933 나노가 큐를 읽는 법 = recv 1줄(doorbell = 트리거만)
    hit = mapped_card(env.get("FT2_ROOT"), env["FT2_TEAM"], env["FT2_WORK"])   # r2030 짝 표 대기 카드 = 그 실제 자리 · 없음 = 지금 경로
    card = "%s %s:%s" % hit if hit else "%s %s:%s/대기/%s.md" % (*row, env["FT2_WORK"])
    return mark, "%s 좌석 %s — 카드 %s 를 통째로 읽고 그대로 수행 · root = %s · work = %s · gen = ft2_claim 이 돌려준 값 · " % (
        mark, env["FT2_HOLDER"], card, env.get("FT2_ROOT"), env["FT2_WORK"]) + tail   # r1930 범위 더함: work = 접미 없는 이름(@aN 은 attempt 칸)


def plan_of(folder, tag, root, team, holder, role_argv, worktree, repo, env, body, base=DEFAULT_BASE):
    """의도·워크트리·열기 argv — `--detach`(가지 몰래 만들기 0) · git 은 `-C <repo>`(A2) · pi argv 는 역할 표 그대로(A5).
    git argv 끝 = 기준 ref 이름(r1780) — dry-run 은 이 이름 그대로 보이고, 실제 실행은 `at_sha` 로 확인한 sha 로 바꾼다."""
    path = os.path.abspath(worktree or os.path.join(root, ".fable-team", "teams", team, "worktrees", tag))
    box = os.path.join(root, ".fable-team", "comm")   # r2050 좌석 우편함 = FT2_ROOT 것 · 실재 폴더일 때만(부모 env 값 물려주기 0)
    mbox = [("FT_SEAT_MBOX_DIR", box)] if os.path.isdir(box) else []   # r2109 이름 = 스킬 mbox 래퍼만 읽음(FT_MBOX_DIR 은 모든 도구의 1순위 → 좌석 안 시험이 실 우편함에 씀)
    pairs = [word for key, value in list(env.items()) + mbox for word in ("-e", key + "=" + value)]
    pi, hit = pi_path(os.environ.get("PATH")), mapped_card(root, team, env.get("FT2_WORK", ""))   # r2030 짝 표 카드 폴더만 sparse 에 더함
    return {"intent": os.path.join(folder, tag + ".intent"), "worktree": path,
            "git": ["git", "-C", repo, "worktree", "add", "--no-checkout", "--detach", path, base],
            # r1846: 빈 자리 → sparse(출처 = 1.x r835 ft_sparse_patterns · 남의 팀 design 제외) → checkout · 큰 리포도 25초 안
            "sparse": ["git", "-C", path, "sparse-checkout", "set", "--no-cone", "/*", "!/design/teams/*/", "/design/teams/%s/" % team] + (["/%s/" % WAIT.match(hit[2]).group(1)] if hit else []),
            "notes": {},   # r2082 의도에 더할 칸(A2 · 묶음 수) · 기준 sha 읽은 뒤 채움
            "checkout": ["git", "-C", path, "checkout", "-q"],
            "tmux": ["tmux", "new-session", "-d", "-s", holder, "-c", path] + pairs + [pi or "pi"] + ["-e", seat_tools(), "--approve"] + list(role_argv) + [body],
            "mbox": "FT_SEAT_MBOX_DIR=" + box if mbox else "우편함 명시 0 — %s 없음" % box,
            "pi_bin": pi, "alive": ["tmux", "has-session", "-t", "=" + holder],   # r1892: new-session rc0 뒤 1회
            "receipt": ["tmux", "display-message", "-p", "-t", "=%s:" % holder, "#{session_id}\t#{session_created}"]}   # r2257 O1: alive rc0 뒤 1회 · 개설 영수만(살아 있음 판정 0)


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


def reserve(path, payload):
    """내용 든 원자 예약(r1929 DA 보정) — tmp 에 쓰고 fsync → os.link(tmp, 예약 경로) → tmp 지움.
    이미 있으면 EEXIST = False(원자 · 배타 · «있나 보고 쓰기» 0) · 성공한 예약 파일은 늘 pid 가 들어 있다(빈 파일 순간 0)."""
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    try:
        os.link(tmp, path)
        return True
    except FileExistsError:
        return False
    finally:
        os.unlink(tmp)


def ps_call(argv, timeout=7):
    """ps 1회(LC_ALL=C · 바깥 호출 7초) → (rc, stdout) · 실패 = (None, "")."""
    try:
        done = subprocess.run(["ps"] + argv, capture_output=True, text=True, timeout=timeout, env=dict(os.environ, LC_ALL="C"))
    except (OSError, subprocess.TimeoutExpired):
        return None, ""
    return done.returncode, done.stdout


def pid_state(pid, started, ps=ps_call):
    """열기 프로세스 → "alive"·"dead"·"unknown"(r1929) · pid 없음(옛 의도) = dead · ps(argv) → (rc, 출력).
    os.kill(pid, 0) 뒤 ps 시작 시각이 started 보다 늦으면 같은 pid 를 받은 다른 프로세스(dead) · 좀비 = dead · 판정 못 함 = unknown(닫힌 쪽)."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return "dead"
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return "dead"
    except PermissionError:
        pass
    except (OSError, OverflowError):
        return "unknown"
    rc, out = ps(["-o", "stat=,lstart=", "-p", str(pid)])
    words = (out or "").split() if rc == 0 else []
    try:
        at = time.mktime(time.strptime(" ".join(words[1:6]), "%a %b %d %H:%M:%S %Y"))
    except (ValueError, OverflowError):
        return "unknown"
    late = isinstance(started, (int, float)) and at > started + 1
    return "dead" if late or words[0].startswith("Z") else "alive"


def worktree_head(porcelain, path):
    """`git worktree list --porcelain` 출력 → 그 경로의 HEAD sha · 목록에 없음 = None(경로는 realpath 로 맞춘다)."""
    want, here = os.path.realpath(path), None
    for line in porcelain.splitlines():
        if line.startswith("worktree "):
            here = os.path.realpath(line[len("worktree "):])
        elif line.startswith("HEAD ") and here == want:
            return line[len("HEAD "):].strip()
    return None


def resume_steps(plan, sha, head, exists):
    """이어 열기 git 단계(r1929 ③) — 경로 없음·목록 없음 = git add 부터 · 경로 있음 ∧ 목록 HEAD == base_sha = sparse·checkout 만 ·
    그 밖(경로만 있음·HEAD 다름) = None(«끊긴 열기 · 자리 불일치» · 지우기 0)."""
    if not exists and head is None:
        return [("git add", at_sha(plan["git"], sha)), ("git sparse", plan["sparse"]), ("git checkout", plan["checkout"])]
    if exists and head == sha:
        return [("git sparse", plan["sparse"]), ("git checkout", plan["checkout"])]
    return None


def resume_plan(plan, repo, sha, timeout):
    """이어 열기 단계 — `git worktree list --porcelain` 1회(상한 = git 25초) → resume_steps · 목록 실패·base_sha 없음 = None."""
    try:
        done = subprocess.run(["git", "-C", repo, "worktree", "list", "--porcelain"], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if done.returncode != 0 or not sha:
        return None
    return resume_steps(plan, sha, worktree_head(done.stdout, plan["worktree"]), os.path.exists(plan["worktree"]))


def checkout_limit():
    """r2082 A3 — env FT2_CHECKOUT_FILES(양의 정수) · 그 밖 = 12000."""
    raw = os.environ.get("FT2_CHECKOUT_FILES", "")
    return int(raw) if raw.isdigit() and int(raw) > 0 else LIMIT


def unit(path):
    """묶음 단위 = 최상위 폴더(design 은 그 아래 폴더) · 최상위·design 바로 밑 파일 = ""(늘 묶음 1 맨 앞)."""
    parts = path.split("/")
    deep = 2 if parts[0] == "design" else 1
    return "/".join(parts[:deep]) if len(parts) > deep else ""


def batches(paths, skip, limit):
    """[[단위…]…] — 단위별 파일 수(skip 접두 = 남의 팀 폴더는 센다 0)를 이름 차례로 합이 limit 이하가 되게 묶는다 ·
    혼자 넘는 단위 = 혼자 1묶음(A3). 새 패턴과 파일 집합은 마지막 묶음에서 A1 패턴 그대로라, 세기는 나누는 데만 쓴다."""
    count = {}
    for path in paths:
        if not path.startswith(skip):
            count[unit(path)] = count.get(unit(path), 0) + 1
    out, size = [], limit + 1
    for name in sorted(count):
        if size + count[name] <= limit:
            out[-1].append(name)
            size += count[name]
        else:
            out.append([name])
            size = count[name]
    return out


def checkout_steps(plan, paths, limit):
    """r2082 A3 — git add 뒤 단계 · 1묶음 = 지금 그대로(sparse → checkout · A5) · n묶음 = sparse(묶음 2.. 뺀 패턴) →
    «git checkout 1/n» = checkout -q → «git checkout k/n» = sparse-checkout set(묶음 k+1.. 뺀 패턴 · n/n = A1 패턴 그대로)."""
    skip = tuple(p[2:] for p in plan["sparse"] if p.startswith("!/design/") and "*" not in p)
    groups = batches(paths, skip, limit)
    if len(groups) < 2:
        return [("git sparse", plan["sparse"]), ("git checkout", plan["checkout"])]
    n = len(groups)
    later = lambda k: ["!/%s/" % re.sub(r"([\\*?\[])", r"\\\1", u) for g in groups[k:] for u in g]  # noqa: E731
    steps = [("git sparse", plan["sparse"] + later(1)), ("git checkout 1/%d" % n, plan["checkout"])]
    return steps + [("git checkout %d/%d" % (k + 1, n), plan["sparse"] + later(k + 1)) for k in range(1, n)]


def split_steps(plan, paths):
    """r2082 A3 — (git add 뒤 단계, 의도 칸) · paths = 기준 sha 파일 목록(늘 센다 · 호출 리포 index 로 건너뛰기 0)."""
    steps = checkout_steps(plan, paths, checkout_limit())
    return steps, ({"checkout_batches": len(steps) - 1} if len(steps) > 2 else {})


def resume_split(base, batched, failed_step):
    """r2082 A4 — 이어 열기 단계 · 묶음 k(≥2)에서 끊긴 자리(경로 있음 ∧ HEAD == base_sha) = 묶음 k 부터(끝난 묶음 다시 쓰기 0) ·
    그 밖 = resume_steps 의 git add(있으면) + 묶음 단계 전부(1묶음 = resume_steps 와 같다)."""
    head, names = [s for s in base if s[0] == "git add"], [s[0] for s in batched]
    if not head and failed_step in names[2:]:
        return batched[names.index(failed_step):]
    return head + batched


def recovery(repo, path):
    """git 단계 실패 사유에 붙는 복구 2줄 — 자동 지우기·자동 재시도 0(하드 룰 2 · A3).

    경로는 shlex.quote 로 인용한다 — 공백·따진부호가 든 repo·worktree 에서 안내를 bash 에 그대로 넘겨도
    경로가 갈라지지 않아야 한다(DA 보정 291508).
    """
    return ("복구 ⓐ git -C %s worktree remove --force --force %s (반쪽 worktree 가 남았을 때 · 사람 실행) "
            "ⓑ 같은 일 새 attempt = cli assign → deliver → launch" % (shlex.quote(repo), shlex.quote(path)))
