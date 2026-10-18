#!/usr/bin/env python3
"""ft_merge_lines.py <repo> <M> <S> — 후보 S 가 «main M 이 더한 줄» 을 지우지 않는지 검사 (R230 교정 1 H2 · 교정 2 H2-1).
전제: M 은 S 의 조상(ft-merge-gate.sh 가 먼저 확인). 보호 집합 = diff -M F M 의 파일별 추가 줄 다중집합(공백뿐인 줄 제외),
F = S 의 first-parent 사슬에서 «M 의 조상인 첫 커밋». F == M(처음부터 M 위) = 보호 집합 빈 집합 = 통과.
위치·순서는 보지 않는다(개수까지 포함하면 통과). 삭제·바이너리 변경·명령 실패는 전부 deny.
exit 0 = 통과 · 1 = deny(사유 stdout) · 2 = 명령 실패(사유 stdout · deny 와 같게 취급)."""
import collections
import re
import subprocess
import sys


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


def main(repo, m, s):
    f = fork_point(repo, m, s)
    if f == m:
        print("PASS 처음부터 main 위(F==M) — 보호 집합 빈 집합")
        return 0
    adds, binary = added_lines(repo, f, m)
    changed, bad = m_to_s(repo, m, s), []
    for path in sorted(set(adds) | binary):
        if path not in changed:
            continue
        st, sp = changed[path]
        if st == "D":
            bad.append("%s: main 이 바꾼 파일을 S 가 삭제" % path); continue
        if path in binary:
            bad.append("%s: 바이너리가 main 의 것과 다름" % path); continue
        have = collections.Counter(l.rstrip("\r") for l in git(repo, "show", "%s:%s" % (s, sp)).split("\n") if l.strip())
        lost = sum(max(0, n - have[l]) for l, n in adds[path].items() if l.strip())
        if lost:
            bad.append("%s: main 이 더한 줄 %d 개가 S 에서 사라짐" % (path, lost))
    if bad:
        print("DENY main 이 더한 줄을 지움(옛 브랜치 F=%s) — main 에서 새 브랜치로 따라: %s" % (f[:10], "; ".join(bad[:8])))
        return 1
    print("PASS 보호 집합 %d 파일 · F=%s" % (len(adds) + len(binary), f[:10]))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("usage: ft_merge_lines.py <repo> <M> <S>"); sys.exit(2)
    try:
        sys.exit(main(*sys.argv[1:]))
    except Fail as e:
        print("ERROR %s" % e); sys.exit(2)
