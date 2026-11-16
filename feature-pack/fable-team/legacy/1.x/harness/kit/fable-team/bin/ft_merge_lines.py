#!/usr/bin/env python3
"""ft_merge_lines.py <repo> <M> <S> — 후보 S 가 «main M 이 더한 줄» 을 지우지 않는지 검사 (R230 교정 1 H2 · 교정 2 H2-1).
전제: M 은 S 의 조상(ft-merge-gate.sh 가 먼저 확인). 보호 집합 = diff -M F M 의 파일별 추가 줄 다중집합(공백뿐인 줄 제외),
F = S 의 first-parent 사슬에서 «M 의 조상인 첫 커밋». F == M(처음부터 M 위) = 보호 집합 빈 집합 = 통과.
위치·순서는 보지 않는다(개수까지 포함하면 통과). 삭제·바이너리 변경·명령 실패는 전부 deny.
r461: 다른 폴더로 옮긴 파일(git R, 또는 D 인데 S 트리에 같은 이름이 정확히 1개)은 옮긴 곳에서 줄을 센다 — 옛 경로 글자 → 새 경로 글자 1쌍 치환 허용 · 후보 0·2+ 는 삭제로 deny.
r477: 비교 «전» main 이 더한 줄에 명단(ref FT_TEAMS_REF · 기본 origin/main) 기준 팀 폴더 정규화(옛 꼴 `design/<팀>/` → 새 꼴 `design/teams/<팀>/` · 명단 꼴2 팀만 · 한 방향)를 적용해 «정규화 뒤 같은 줄 = 같은 줄»(PATHSUBST). 후보 줄은 원문 그대로 — 새 꼴을 옛 꼴로 되돌린 줄은 소실. 명단 못 읽음 = 정규화 0 + stderr WARN 1줄(옛 동작 그대로).
r1741 --replace-ok <리포 상대 경로>@<sha>#§<절>: DA 판정문(카드 리포 = FT_ROOT → 후보 리포)의 그 절 ```gate-replace 블록(첫 줄 `head <40hex>` · 다음 줄 `<경로>TAB<main 줄 원문>TAB<개수>`)에 적힌 (경로·원문) 만큼만 소실에서 뺀다. «판정:» 값이 APPROVE 로 시작하고 블록 head 가 S 이거나 S=«head 뒤 main 병합만 + 자기 변경 동일»(ft-approval-equiv)일 때만 유효 — 못 읽음·블록 없음·APPROVE 아님·head 불일치 = DENY(통과 0). 인자 없으면 옛 동작 바이트 그대로.
r2098: 소실 DENY 첫 줄 = 앞 8 항목 + «외 N 파일» + «합계 <파일> 파일 · <줄> 줄» · 둘째 줄 «다음: …» · --lost-rows = 판정 대신 블록 줄(rc 1 = 줄로 못 적는 소실 · stderr).
exit 0 = 통과 · 1 = deny(사유 stdout) · 2 = 명령 실패(사유 stdout · deny 와 같게 취급)."""
import collections
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    from ft_team_lib import team_rows_ref
except Exception:  # 옛 설치본(모듈·함수 없음) = 옛 동작 + WARN
    team_rows_ref = None


class Fail(Exception):
    pass


def git(repo, *a):
    p = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", *a], capture_output=True)
    if p.returncode != 0:
        raise Fail("git %s 실패: %s" % (" ".join(a[:3]), p.stderr.decode("utf-8", "replace").strip()[:120]))
    return p.stdout.decode("utf-8", "replace")


def is_anc(repo, a, b):
    return subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", a, b], capture_output=True).returncode == 0


def fork_point(repo, m, s):
    chain = git(repo, "rev-list", "--first-parent", s).split()
    lo, hi = 0, len(chain)  # 술어 «chain[i] 가 M 의 조상» 은 사슬 아래로 갈수록 참(단조) — 이진 탐색
    while lo < hi:
        mid = (lo + hi) // 2
        lo, hi = (lo, mid) if is_anc(repo, chain[mid], m) else (mid + 1, hi)
    if lo == len(chain):
        raise Fail("S 의 first-parent 사슬이 main 과 만나지 않음(무관 이력)")
    return chain[lo]


def added_lines(repo, f, m):
    """diff -M F M → ({경로: Counter(추가 줄)}, {바이너리 경로})."""
    adds, binary, cur = {}, set(), None
    for line in git(repo, "diff", "-M", "--unified=0", "--no-color", f, m).split("\n"):
        if line.startswith("+++ "):
            cur = None if line == "+++ /dev/null" else line[6:].split("\t")[0]
            if cur is not None:
                adds.setdefault(cur, collections.Counter())
        elif line.startswith("Binary files "):
            hit = re.search(r" and b/(.*) differ$", line)
            if hit:
                binary.add(hit.group(1))
        elif cur is not None and line.startswith("+") and line[1:].strip():
            adds[cur][line[1:].rstrip("\r")] += 1
    return adds, binary


def m_to_s(repo, m, s):
    """M → S 에서 달라진 파일: {M 쪽 경로: (상태, S 쪽 경로)}. 목록에 없는 파일 = M 과 S 가 같다."""
    tok, out, i = git(repo, "diff", "-M", "--name-status", "-z", m, s).split("\0"), {}, 0
    while i + 1 < len(tok):
        st = tok[i][0]
        if st in "RC":
            out[tok[i + 1]] = ("R", tok[i + 2]); i += 3
        else:
            out[tok[i + 1]] = (st, tok[i + 1]); i += 2
    return out


def moved_to(repo, s, path, tree):
    """r461: S 에서 사라진(D) 파일 → S 트리의 같은 이름 파일이 정확히 1개면 그 경로. 0 = 삭제 · 2+ = 모호(추측 0) → (None, 사유)."""
    if not tree:
        tree.extend(git(repo, "ls-tree", "-r", "-z", "--name-only", s).split("\0"))
    base = path.rsplit("/", 1)[-1]
    cands = [p for p in tree if p.rsplit("/", 1)[-1] == base]
    if len(cands) == 1:
        return cands[0], None
    return None, "S 가 삭제" + (" · 같은 이름 후보 %d개(추측 0)" % len(cands) if cands else "")


def _roster_hint(repo, ref):
    """명단을 «기대할 수 있는» 저장소인가 — 명시 ref · 체크아웃 TEAMS.md · ref 트리의 TEAMS.md. 아니면(합성 픽스처) WARN 0."""
    if os.environ.get("FT_TEAMS_REF") or os.path.isfile(os.path.join(repo, "design", "TEAMS.md")):
        return True
    try:
        p = subprocess.run(["git", "-C", repo, "cat-file", "-e", "%s:design/TEAMS.md" % ref], capture_output=True, timeout=7)
    except Exception:
        return True
    return p.returncode == 0


def team_table(repo):
    """r477: 명단(ref FT_TEAMS_REF · 기본 origin/main)의 꼴2 팀 → 옛 꼴 접두. 못 읽음 = None(추측 0 · 옛 동작)."""
    ref = os.environ.get("FT_TEAMS_REF") or "origin/main"
    if team_rows_ref is None:
        if _roster_hint(repo, ref):
            print("WARN 명단 ref 못 읽음 — PATHSUBST 0", file=sys.stderr)
        return None
    try:
        rows = team_rows_ref(ref, repo)
    except Exception:
        if _roster_hint(repo, ref):
            print("WARN 명단 ref 못 읽음 — PATHSUBST 0", file=sys.stderr)
        return None
    return {team: "design/%s/" % team for team, rel in rows.items() if rel.startswith("design/teams/")}


def norm(line, table):
    """r477: 본문 안 «옛 팀 폴더» 글자를 새 꼴로 — 명단 꼴2 팀만 · 한 방향(옛→새)만."""
    if table:
        for team, old in table.items():
            line = line.replace(old, "design/teams/%s/" % team)
    return line


def replace_ok(repo, spec, s):
    """r1741 A1~A3: DA 판정문 §<절> 의 ```gate-replace 블록 → ({(경로, 원문): 개수}, «경로@sha10#§절») — 리포 = FT_ROOT(카드) → 후보.
    못 읽음(카드 리포 FT_ROOT 하나 · 7초 상한)·절 없음·APPROVE 아님·블록 꼴 아님·head 불일치는 Fail(통과 0 · 게이트가 DENY … 판정 불가 로 낸다)."""
    m = re.fullmatch(r"([^@\s]+)@([0-9a-f]{7,40})#§(\S+)", spec)
    if not m: raise Fail("판정 불가 replace-ok 꼴 아님(<경로>@<sha>#§<절>): %s" % spec[:80])
    path, sha, sec = m.groups()
    root, why = os.environ.get("FT_ROOT") or "", "판정 불가 replace-ok 판정문 못 읽음 %s@%s" % (path, sha[:10])
    alt = "" if root else os.environ.get("FT_REPLACE_ROOT") or ""   # r1746 A5: FT_ROOT 빈 값 = 승인 루트(게이트가 fm_live_root 로 채움) — 그게 후보 리포 자신이면 쓰지 않는다(X1 후보 리포 폴백 0)
    if alt:
        try:
            cd = [subprocess.run(["git", "-C", d, "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, timeout=7).stdout.strip() for d in (alt, repo)]
        except subprocess.TimeoutExpired:
            raise Fail(why + " — 7초 초과")
        root = alt if cd[0] and cd[0] != cd[1] else ""
    text = None   # 판정문 리포 = 카드 리포(FT_ROOT) 하나뿐 — 후보 리포 폴백 0 · FT_ROOT 가 빈 값이면 git -C ""(=cwd 리포)를 부르지도 않는다
    if root:
        try:
            p = subprocess.run(["git", "-C", root, "-c", "core.quotepath=off", "show", "%s:%s" % (sha, path)], capture_output=True, timeout=7)
            text = p.stdout.decode("utf-8", "replace") if p.returncode == 0 else None
        except subprocess.TimeoutExpired:
            raise Fail(why + " — 7초 초과")
    if text is None: raise Fail(why)
    hit = re.search(r"(?m)^#{1,6}\s[^\n]*§\s*%s(?![0-9])[^\n]*\n(.*?)(?=^#{1,6}\s|\Z)" % re.escape(sec), text, re.S)
    if not hit: raise Fail("판정 불가 replace-ok §%s 절 없음(%s@%s)" % (sec, path, sha[:10]))
    v = re.search(r"(?m)^\s*판정:\s*(.+)$", hit.group(1))
    if not (v and v.group(1).strip().lstrip("*").startswith("APPROVE")):
        raise Fail("판정 불가 replace-ok §%s APPROVE 아님(%.40s)" % (sec, v.group(1).strip() if v else "판정: 줄 없음"))
    f = re.search(r"```gate-replace[ \t]*\nhead ([0-9a-f]{40})\n(.*?)```", hit.group(1), re.S)
    if not f: raise Fail("판정 불가 replace-ok 블록 없음 또는 첫 줄 «head <40hex>» 아님(§%s)" % sec)
    rows = [x.split("\t") for x in f.group(2).split("\n") if x.strip()]
    if not all(len(c) == 3 and c[2].strip().isdigit() and int(c[2]) >= 1 for c in rows):
        raise Fail("판정 불가 replace-ok 블록 줄 꼴 아님(경로<TAB>원문<TAB>개수)")
    if f.group(1) != s:   # A3: head == S 이거나 «head 뒤 main 병합만 + 자기 변경 동일»(ft-approval-equiv 판정 그대로) — 호출 상한 7초
        try:
            eq = subprocess.run(["bash", os.path.join(HERE, "ft-approval-equiv.sh"), f.group(1), s, "--repo", repo,
                                 "--remote", os.environ.get("FT_REPLACE_REMOTE", "origin"),
                                 "--target", os.environ.get("FT_REPLACE_TARGET", "main")], capture_output=True, timeout=7).returncode == 0
        except subprocess.TimeoutExpired:
            raise Fail("판정 불가 replace-ok head 대조 7초 초과(블록 %s · 후보 %s)" % (f.group(1)[:10], s[:10]))
        if not eq:
            raise Fail("replace-ok head ≠ 후보(블록 %s · 후보 %s · main 병합만 차이도 아님)" % (f.group(1)[:10], s[:10]))
    return {(c[0], c[1].rstrip("\r")): int(c[2]) for c in rows}, "%s@%s#§%s" % (path, sha[:10], sec)


def losses(repo, f, m, s, rok):
    """r2098: 소실 계산 1곳(DENY · --lost-rows 공용) → ([(경로, 사유, {main 줄 원문: 소실 개수})], 이동, PATHSUBST 줄, REPLACE-OK 줄, 보호 집합 파일 수)."""
    table = team_table(repo)
    adds, binary = added_lines(repo, f, m)
    changed, bad, moved, tree, pathsubst = m_to_s(repo, m, s), [], [], [], 0
    rok_n = 0
    for path in sorted(set(adds) | binary):
        if path not in changed:
            continue
        st, sp = changed[path]
        if st == "D":
            sp, why = (None, "S 가 삭제") if path in binary else moved_to(repo, s, path, tree)
            if why:
                bad.append((path, "main 이 바꾼 파일을 %s" % why, {})); continue
        if path in binary:
            bad.append((path, "바이너리가 main 의 것과 다름", {})); continue
        raw = collections.Counter(l.rstrip("\r") for l in git(repo, "show", "%s:%s" % (s, sp)).split("\n") if l.strip())
        # r477: «main 이 더한 줄» 만 팀 폴더 옛 꼴 → 새 꼴 정규화(한 방향) — 후보가 새 꼴을 옛 꼴로 되돌린 줄은 소실 그대로
        # r461: 이동이면 main 줄 속 «옛 경로» 글자를 «새 경로» 로 바꾼 줄도 같은 줄로 센다(치환은 그 1쌍만)
        rows = {}
        for l, n in adds[path].items():
            if not l.strip():
                continue
            moved_line = l.replace(path, sp)
            raw_hit = max(raw[l], raw[moved_line])
            hit = max(raw[l], raw[moved_line], raw[norm(l, table)], raw[norm(moved_line, table)])
            allow = rok.get((path, l), 0)            # A4: (경로·원문)마다 블록 개수만큼만 소실에서 뺀다
            if n - hit - allow > 0:
                rows[l] = n - hit - allow
            rok_n += min(max(0, n - hit), allow)     # 실제로 사라진 줄만 REPLACE-OK 로 센다(안 사라진 줄은 무시)
            if min(n, hit) > min(n, raw_hit):  # 정규화로만 같아진 줄 = PATHSUBST
                pathsubst += 1
        lost = sum(rows.values())
        if lost:
            bad.append((path, "main 이 더한 줄 %d 개가 S 에서 사라짐" % lost if sp == path
                        else "%s 로 이동했으나 main 이 더한 줄 %d 개 없음" % (sp, lost), rows))
        elif sp != path:
            moved.append("%s -> %s" % (path, sp))
    return bad, moved, pathsubst, rok_n, len(adds) + len(binary)


def lost_rows(repo, f, m, s):
    """r2098 P3: gate-replace 블록 줄 = «head <S 40hex>» + «경로TAB원문TAB개수» · 줄로 못 적는 소실 = stderr 1줄씩 · rc 1."""
    head = git(repo, "rev-parse", "--verify", s + "^{commit}").strip()
    out, why = ["head " + head], []
    for path, msg, rows in (losses(repo, f, m, s, {})[0] if f != m else []):
        if not rows:
            why.append("%s: %s" % (path, msg))
        for row, n in sorted(rows.items()):
            w = "원문에 TAB" if "\t" in row else "원문에 백틱 3개(```)" if "```" in row else ""
            why.append("%s: %s" % (path, w)) if w else out.append("%s\t%s\t%d" % (path, row, n))
    print("\n".join(out))
    for w in why:
        print("줄로 못 적음: " + w, file=sys.stderr)
    return 1 if why else 0


def main(repo, m, s, spec="", rows=False):
    f = fork_point(repo, m, s)
    if rows:
        return lost_rows(repo, f, m, s)
    if f == m:
        print("PASS 처음부터 main 위(F==M) — 보호 집합 빈 집합")
        return 0
    rok, rok_disp = {}, ""
    if spec:   # A2: 판정문 못 읽음·블록 없음·APPROVE 아님·head 불일치 = 통과 0(게이트가 DENY 로 낸다)
        try:
            rok, rok_disp = replace_ok(repo, spec, s)
        except Fail as e:
            print("DENY %s" % e)
            return 1
    bad, moved, pathsubst, rok_n, n_set = losses(repo, f, m, s, rok)
    if bad:
        more = " 외 %d 파일" % (len(bad) - 8) if len(bad) > 8 else ""
        print("DENY main 이 더한 줄을 지움(옛 브랜치 F=%s) — main 에서 새 브랜치로 따라: %s%s · 합계 %d 파일 · %d 줄" % (
            f[:10], "; ".join("%s: %s" % b[:2] for b in bad[:8]), more, len(bad), sum(sum(b[2].values()) for b in bad)))
        print("다음: 의도된 교체면 DA 판정문 gate-replace 블록 → 착지 명령에 --replace-ok <경로>@<sha>#§<절> · 블록 줄 = ft_merge_lines.py %s %s %s --lost-rows" % (repo, m, s))
        return 1
    show = "".join("; MOVED " + x for x in moved[:3]) + (" 외 %d" % (len(moved) - 3) if len(moved) > 3 else "")
    sub = " · PATHSUBST %d줄" % pathsubst if pathsubst else ""
    ok = " · REPLACE-OK %d줄 (%s)" % (rok_n, rok_disp) if rok_n else ""
    print("PASS 보호 집합 %d 파일 · F=%s · 이동 인정 %d%s%s%s" % (n_set, f[:10], len(moved), show, sub, ok))
    return 0


if __name__ == "__main__":
    av, spec = sys.argv[1:], ""
    rows = "--lost-rows" in av   # r2098 P3: 판정 대신 gate-replace 블록 줄
    av = [a for a in av if a != "--lost-rows"]
    if "--replace-ok" in av:
        i = av.index("--replace-ok")
        av, spec = av[:i] + av[i + 2:], av[i + 1] if i + 1 < len(av) else ""
    if len(av) != 3:
        print("usage: ft_merge_lines.py <repo> <M> <S> [--replace-ok <리포 상대 경로>@<sha>#§<절>] [--lost-rows]"); sys.exit(2)
    try:
        sys.exit(main(*av, spec, rows))
    except Fail as e:
        print("ERROR %s" % e); sys.exit(2)
