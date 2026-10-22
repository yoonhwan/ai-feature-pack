#!/usr/bin/env python3
"""ft_doc_exempt.py — «문서 전용 PR» 예외 판정 한 곳 (R725 · 카드 r725-doc-only-pr-lands-without-approve-h)

왜: 자율 OFF 에서도 main 에 들어가는 모든 PR 이 오빠 승인 파일을 요구해, planner 팀장 교대 인계서처럼
    .md 만 바꾸는 PR 도 오빠께 실행 요청이 갔다(오빠 2026-10-22 13:3x 「이건 그냥 할 수 있는 건데」).
    ⇒ «한 팀 폴더 안의 .md 추가·수정만» 인 PR 을 기계로 판정해 승인 h 없이 착지시킨다.
    범위(2026-10-22 master #140107 확정 · R741 확대) = 모든 팀 폴더 design/teams/<팀>/ 아래 .md — 2576(이슈팀 표) 포함.
    R741: «직속» 만이 아니라 «하위 폴더»(증거·날짜 폴더 등)까지. 단 도구가 판정 입력으로 읽는 폴더(indices·inbox·keys)와
    점 폴더는 제외 — 그 목록·조각 검사는 ft_doc_exempt_paths.py 한 곳(카드 r741-doc-exempt-team-subfolders).
    이전 판(planner 직속 HANDOFF-*/CLOSEOUT-*.md 만)은 폐기.

사용: ft_doc_exempt.py --mode <doc-exempt|md-files> --head <40hex> [--base <40hex>] [--repo <dir>]
        [--root <dir>] [--seat <좌석>] [--remote origin] [--target main]
  doc-exempt (기본) — 전부 참일 때만 면제:
    ⓪ 부른 좌석 = «실제» 좌석 — TMUX_PANE 의 세션명(ft-press-gate.sh `_seat_name` 과 같은 규칙)으로 구한다.
       자기 신고(FT_SEAT·--seat)와 다르면 판정 불가(rc2). 시험용 덮어쓰기 = FT_DOC_EXEMPT_SELFTEST=1 1곳(press-gate 와 같은 꼴)
       ∧ 명부 루트 = 대상 리포 공용 루트(git common dir 의 상위) 또는 그 `.fable-team/LIVE_ROOT` 1행 «뿐» —
       --root/FT_ROOT 가 다르면 rc2(DA⑥ r1 질문 4: 가짜 명부로 _master 를 바꿔 넣는 길)
    ① 부른 좌석 = 그 폴더 «팀 master»(명부 seats-<팀>.json `_master`) 또는 planner `_master` «정확 일치»
       ∧ 이름 lint PASS(ft-name-lint.sh 1곳)
    ② base(--base · 없으면 fetch 로 얻은 최신 <remote>/<target>) 가 head 의 조상
    ③ merge-base(base,head)..head 최종 트리 diff 의 모든 경로가 «한» 팀 폴더 design/teams/<팀>/ 아래(하위 폴더 허용 ·
       indices·inbox·keys·baselines·점 폴더 제외 = ft_doc_exempt_paths.EXCLUDE_DIRS) ∧ 이름이 *.md 이고 정본·승인근거·판정 입력
       이름(ft_doc_exempt_paths.CANON·EXCLUDE_NAMES · key(NFKC+casefold) 비교 · 어느 깊이에서든) 아님
       ∧ ★하위 폴더는 «추가(A)» 만★ — 수정·삭제·이름바꾸기(M/D/R)는 직속만(오빠 결정 2026-10-22 · 선택지 1)
    ④ 추가(A)·수정(M)만 — 삭제·이름바꿈·복사 0(--no-renames · --find-copies=0)
    ⑤ 모드 100644 만(링크·실행비트·gitlink 0) · 바이너리 0 — numstat rc≠0 = rc2 · 바이너리 판정은 git diff 속성이 아니라
       head 의 blob 내용(NUL 바이트·UTF-8 아님)으로 본다(DA⑥ r1 질문 3: 속성 강제·numstat 실패로 바이너리가 통과하던 자리)
    ⑥ 경로 정규화로 범위를 넓히지 않음(대소문자 그대로 · NFC 아님·제어문자 0)
  md-files — diff 의 모든 경로가 *.md 인가(ft-proxy-decide docs-push 의 «design/x.py 구멍» 막기 · 판정 1125 계열)

출력: 첫 줄 `DOC-EXEMPT <head> files=<N> team=<팀> by=<좌석>`(좌석 = 실제 호출 좌석) | `DOC-FILES <head> files=<N>`  (rc 0)
      `NOT <사유>` (rc 1 · 판정했고 예외 아님) · `NOT <사유>` (rc 2 · 판정 불가 — 호출자는 «면제 0»)
환경: FT_DOC_EXEMPT=0 → 예외 꺼짐(rc 2 NOT) · FT_SEAT(자기 신고 좌석 — 실제 좌석과 같아야) · FT_ROOT(명부 루트 — 출처 검증)
      FT_DOC_EXEMPT_SELFTEST=1 + FT_DOC_EXEMPT_SEAT=<좌석> = 시험에서만 좌석 덮어쓰기 — ★그 판정 성공은 rc3★(«시험 판정 — 착지에 못 쓴다» · ft-press-gate 자체시험과 같은 꼴)
      실경로(ft-merge-lib·ft-merge-land)는 판정기를 부를 때 이 두 env 를 `env -u` 로 지운다 — 호출자가 export 해도 착지에 못 쓴다
      FT_DOC_EXEMPT_CALL_S(외부 호출 한 시도 상한 · 기본 7) — 총 마감은 호출자 몫(카드 ⓗ)
"""
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # R741: 같은 폴더 모듈(경로 조각 판정) — 설치본도 키트 트리 참조
import ft_doc_exempt_paths as paths   # noqa: E402  (제외 폴더·CANON·경로 모양 = 한 곳 · 본 판정기 줄 수 상한)

SHA = re.compile(r"^[0-9a-f]{40}$")
PLANNER = "planner"
GOOD_MODE = "100644"
CALL_S = 7


def notx(msg, rc=1):
    print("NOT " + msg.replace("\n", " ")[:400])
    sys.exit(rc)


def git(repo, *args, timeout=20):
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr.decode("utf-8", "replace").strip()


def bounded(cmd, secs=CALL_S, retries=1):
    """외부 호출 한 시도 secs 초 + 재시도 retries — 초과·실패면 False(늦은 성공 채택 0)."""
    for _ in range(retries + 1):
        try:
            p = subprocess.run(cmd, capture_output=True, timeout=secs)
        except subprocess.TimeoutExpired:
            continue
        if p.returncode == 0:
            return True
    return False


def repo_dir(arg):
    d = arg or os.environ.get("FT_REPO") or os.getcwd()
    rc, out, _ = git(d, "rev-parse", "--show-toplevel")
    if rc != 0 or not out.strip():
        notx("git 리포를 못 찾음: %s" % d, 2)
    return out.decode().strip()


def roster_master(root, team, required=True):
    """명부 seats-<팀>.json `_master` 한 값 — 없음·깨짐 = (required 면)판정 불가 (추측 0) · 아니면 빈 값."""
    p = os.path.join(root, ".fable-team", "seats-%s.json" % team)
    try:
        with open(p, encoding="utf-8") as f:
            m = (json.load(f) or {}).get("_master") or ""
    except (OSError, ValueError) as e:
        if required:
            notx("%s 명부를 못 읽음(%s): %s" % (team, type(e).__name__, p), 2)
        return ""
    if not m and required:
        notx("%s 명부에 _master 없음: %s" % (team, p), 2)
    return m.strip()


def name_lint(seat):
    """이름 lint = 같은 폴더 ft-name-lint.sh(1곳) — 없으면 판정 불가(면제 0)."""
    lint = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ft-name-lint.sh")
    if not os.path.isfile(lint):
        notx("이름 lint 도구 없음: %s" % lint, 2)
    try:
        p = subprocess.run(["bash", lint, seat], capture_output=True, timeout=CALL_S)
    except subprocess.TimeoutExpired:
        notx("이름 lint 시간 초과", 2)
    if p.returncode != 0:
        notx("좌석 이름 lint 실패: %s" % (p.stdout or p.stderr).decode("utf-8", "replace").strip(), 2)


def resolve_base(repo, base, remote, target):
    if base:
        if not SHA.match(base):
            notx("--base 형식 틀림(40hex): %s" % base, 2)
        return base
    ref = "refs/remotes/%s/%s" % (remote, target)
    if not bounded(["git", "-C", repo, "fetch", "--quiet", remote, target]):
        notx("최신 %s/%s fetch 실패·%d초 초과" % (remote, target, CALL_S), 2)
    rc, out, err = git(repo, "rev-parse", "--verify", "-q", ref + "^{commit}")
    if rc != 0 or not out.strip():
        notx("base(%s) 해석 실패: %s" % (ref, err), 2)
    return out.decode().strip()


def actual_seat(declared):
    """⓪ 실제 호출 좌석 — TMUX_PANE 의 세션명(ft-press-gate.sh `_seat_name` 과 같은 규칙).
    덮어쓰기는 FT_DOC_EXEMPT_SELFTEST=1 일 때만(시험 1곳). 못 구하면 판정 불가(면제 0) · 자기 신고와 다르면 판정 불가."""
    real = ""
    if os.environ.get("FT_DOC_EXEMPT_SELFTEST") == "1":
        real = (os.environ.get("FT_DOC_EXEMPT_SEAT") or declared or "").strip()
    else:
        pane = os.environ.get("TMUX_PANE") or ""
        if pane:
            try:
                p = subprocess.run(["tmux", "display-message", "-p", "-t", pane, "#{session_name}"], capture_output=True, timeout=CALL_S)
                if p.returncode == 0:
                    real = p.stdout.decode("utf-8", "replace").strip()
            except (OSError, subprocess.SubprocessError):
                real = ""
    if not real:
        notx("좌석 해석 실패(TMUX_PANE 의 세션명을 못 구함) — 면제 0", 2)
    if declared and declared != real:
        notx("자기 신고 좌석(%s) ≠ 실제 좌석(%s) — 면제 0" % (declared, real), 2)
    return real


def verified_root(repo, roota):
    """명부 루트 출처 검증 — 대상 리포 공용 루트(git common dir 의 상위) 또는 그 `.fable-team/LIVE_ROOT` 1행 «뿐».
    --root/FT_ROOT 가 그와 다르면 판정 불가(면제 0) — 가짜 명부에 자기 이름을 _master 로 넣는 길을 닫는다."""
    rc, out, err = git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if rc != 0 or not out.strip():
        notx("대상 리포 공용 루트를 못 풂: %s" % err, 2)
    common = os.path.dirname(out.decode().strip())
    allowed = {os.path.realpath(common)}
    try:
        with open(os.path.join(common, ".fable-team", "LIVE_ROOT"), encoding="utf-8") as f:
            v = f.readline().strip()
        if v and os.path.isabs(v) and os.path.isdir(v):
            allowed.add(os.path.realpath(v))
    except OSError:
        pass
    root = roota or os.environ.get("FT_ROOT") or common
    if os.path.realpath(root) not in allowed:
        notx("명부 루트(%s)가 대상 리포 공용 루트(%s)도 그 .fable-team/LIVE_ROOT 도 아님 — 면제 0" % (root, common), 2)
    return root


def blob_bad(repo, head, path):
    """⑤ 바이너리 0 — git diff 속성(--numstat)이 아니라 head 의 blob «내용» 으로 본다.
    NUL 바이트 있음 = 거절 · UTF-8 로 못 읽음 = 거절(DA⑥ r1 질문 3: 속성 강제로 바이너리가 통과하던 자리)."""
    rc, out, err = git(repo, "cat-file", "blob", "%s:%s" % (head, path))
    if rc != 0:
        notx("blob 을 못 읽음(%s): %s — 면제 0" % (path, err), 2)
    if b"\0" in out:
        return "바이너리(NUL 바이트): %s" % path
    try:
        out.decode("utf-8")
    except UnicodeDecodeError:
        return "UTF-8 아님: %s" % path
    return ""


def diff_paths(repo, base, head):
    """(status, path) 목록 — 이름바꿈·복사 판정 0(--no-renames · --find-copies=0) · numstat rc≠0 = 판정 불가."""
    rc, out, err = git(repo, "diff", "--name-status", "-z", "--no-renames", "--find-copies=0", base, head)
    if rc != 0:
        notx("diff 실패: %s" % err, 2)
    tok = out.decode("utf-8", "surrogateescape").split("\0")
    pairs = [(tok[i], tok[i + 1]) for i in range(0, len(tok) - 1, 2) if tok[i]]
    rc, _num, err = git(repo, "diff", "--numstat", "-z", "--no-renames", "--find-copies=0", base, head)
    if rc != 0:
        notx("numstat 실패(%s) — 바이너리 판정 불가 · 면제 0" % err, 2)
    return pairs


def main(argv):
    mode, head, base, repoa, roota, seat, remote, target = "doc-exempt", "", "", "", "", "", "origin", "main"
    i = 0
    while i < len(argv):
        a = argv[i]
        if i + 1 >= len(argv) and a.startswith("--"):
            notx("값 없는 인자: %s" % a, 2)
        if a == "--mode":
            mode = argv[i + 1]
        elif a == "--head":
            head = argv[i + 1]
        elif a == "--base":
            base = argv[i + 1]
        elif a == "--repo":
            repoa = argv[i + 1]
        elif a == "--root":
            roota = argv[i + 1]
        elif a == "--seat":
            seat = argv[i + 1]
        elif a == "--remote":
            remote = argv[i + 1]
        elif a == "--target":
            target = argv[i + 1]
        else:
            notx("알 수 없는 인자: %s" % a, 2)
        i += 2
    if mode not in ("doc-exempt", "md-files"):
        notx("--mode 은 doc-exempt|md-files: %s" % mode, 2)
    if os.environ.get("FT_DOC_EXEMPT", "1") == "0":
        notx("FT_DOC_EXEMPT=0 — 예외 꺼짐", 2)
    if not SHA.match(head or ""):
        notx("--head 형식 틀림(40hex): %s" % head, 2)
    repo = repo_dir(repoa)
    root = ""
    if mode == "doc-exempt":
        root = verified_root(repo, roota)   # 명부 루트 출처 검증 — md-files 는 명부를 안 읽으므로 대상 아님
        seat = actual_seat(seat or os.environ.get("FT_SEAT") or "")
        planner = roster_master(root, PLANNER)
        name_lint(seat)
    b = resolve_base(repo, base, remote, target)
    rc, out, _ = git(repo, "merge-base", b, head)
    mb = out.decode().strip() if rc == 0 else ""
    if not mb or mb != b:
        notx("base(%s) 가 head(%s) 의 조상이 아님" % (b[:10], head[:10]), 1)
    pairs = diff_paths(repo, mb, head)
    if not pairs:
        notx("바뀐 경로 0 — 면제 아님")
    if mode == "md-files":
        for _st, p in pairs:
            if not p.endswith(".md"):
                notx("문서(.md) 아닌 파일: %s" % p)
        print("DOC-FILES %s files=%d" % (head, len(pairs)))
        return 0
    teams = set()
    for st, p in pairs:
        if st not in ("A", "M"):
            notx("추가·수정 아닌 변경(%s): %s" % (st, p))
        team, why = paths.team_of(p, st)
        if why:
            notx(why)
        why = blob_bad(repo, head, p)
        if why:
            notx(why)
        teams.add(team)
    if len(teams) != 1:
        notx("한 PR 한 팀 폴더가 아님: %s" % ", ".join(sorted(teams)))
    team = teams.pop()
    tm = roster_master(root, team, required=False)   # 착지 좌석 = 그 폴더 팀 master 또는 planner (master #140107)
    if not tm and team != PLANNER:
        notx("%s 명부에 _master 없음 — 그 팀 master 는 착지 불가 · planner 좌석만" % team, 2)
    if seat not in (planner, tm):
        notx("부른 좌석(%s)이 %s 팀 master(%s)도 planner(%s)도 아님" % (seat, team, tm or "없음", planner), 2)
    for _st, p in pairs:
        rc, out, _ = git(repo, "ls-tree", "-z", head, "--", p)
        rec = out.decode("utf-8", "surrogateescape").split("\0")[0]
        mode_s = rec.split(" ")[0] if rec else ""
        if mode_s != GOOD_MODE:
            notx("모드 %s 는 100644 아님: %s" % (mode_s or "없음", p))
    print("DOC-EXEMPT %s files=%d team=%s by=%s" % (head, len(pairs), team, seat))
    if os.environ.get("FT_DOC_EXEMPT_SELFTEST") == "1":   # 시험 판정은 «착지 근거»가 아니다 — 성공도 rc3(ft-press-gate 자체시험과 같은 꼴)
        print("SELFTEST 시험 판정 — 착지에 못 쓴다(FT_DOC_EXEMPT_SELFTEST=1 · 실경로는 env -u 로 지운다)", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except subprocess.SubprocessError as e:
        notx("git 호출 실패(%s) — 면제 0" % type(e).__name__, 2)
