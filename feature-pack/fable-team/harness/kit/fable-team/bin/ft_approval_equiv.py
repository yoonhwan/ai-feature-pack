#!/usr/bin/env python3
"""ft_approval_equiv.py <repo> <A> <S> <remote> <target> — R247 판정 1917 동일승인 대조 (읽기 전용 · 로컬 git 만 · 네트워크 0).
A = 오빠가 승인한 PR head, S = 지금 PR head. 아래 넷이 «전부 참» 일 때만 EQUIV (거짓 거절 = 재승인 1번으로 안전 · 거짓 통과 0).
 1 A 가 S 의 조상  2 A..S 는 main 병합 커밋뿐(main 밖 일반 커밋 0 · 병합마다 첫 부모 = 승인 줄기, 나머지 부모 = main 의 조상)
 3 자기 변경 동일: diff(merge-base(A,main), A) 와 diff(merge-base(S,main), S) 의 «파일별 순서 있는 +/- 줄» 이 같음(문맥·hunk 줄 번호 무시)
 4 S 트리 == merge-tree(A, main) 의 깨끗한 병합 트리 — 3 이 못 잡는 «같은 줄을 다른 위치로 옮긴» 병합 커밋을 막는다(객체만 쓰고 ref·작업트리 0)
exit 0 = EQUIV · 1 = NOT-EQUIV(사유 stdout) · 3 = ERROR(판단 불가 = 통과 0)"""
import subprocess
import sys


class Fail(Exception):
    pass


class No(Exception):
    pass


def run(repo, *a, ok=(0,)):
    try:
        p = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", *a], capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise Fail("git %s 실행 실패: %s" % (a[0], e))
    if p.returncode not in ok:
        raise Fail("git %s 실패(rc=%d): %s" % (" ".join(a[:2]), p.returncode, p.stderr.decode("utf-8", "replace").strip()[:100]))
    return p


def out(repo, *a):
    return run(repo, *a).stdout.decode("latin-1")


def resolve(repo, x):
    p = run(repo, "rev-parse", "--verify", "-q", x + "^{commit}", ok=(0, 1))
    return p.stdout.decode().strip() if p.returncode == 0 else None


def anc(repo, a, b, shallow):
    rc = run(repo, "merge-base", "--is-ancestor", a, b, ok=(0, 1)).returncode
    if rc == 1 and shallow:
        raise Fail("shallow 저장소 — 조상 판정 불가")
    return rc == 0


def norm(repo, base, tip):
    """base→tip diff 를 {'diff --git 줄': [모드·경로 머리 줄 + 순서 있는 +/- 줄 (+ 바이너리는 새 blob)]} 로 정규화."""
    recs, key, hunk, new = {}, None, False, ""
    args = ("diff", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", "--full-index", "--unified=0", base, tip)
    for ln in out(repo, *args).split("\n"):
        if hunk and ln[:1] in ("+", "-", "\\"):
            recs[key].append(ln)
        elif ln.startswith("diff --git "):
            key, hunk = ln, False
            recs[key] = []
        elif ln.startswith("@@"):
            hunk = True
        elif ln.startswith("index "):
            new = ln.split()[1].split("..")[1]
        elif ln.startswith("Binary files "):
            recs[key].append("BIN " + new)
        elif ln:
            recs[key].append(ln)
    return recs


def check(repo, a, s, remote, target):
    shallow = out(repo, "rev-parse", "--is-shallow-repository").strip() == "true"
    m = resolve(repo, "refs/remotes/%s/%s" % (remote, target))
    sc = resolve(repo, s)
    if not m or not sc:
        raise Fail("main(%s/%s) 또는 PR head 를 확인할 수 없음" % (remote, target))
    ac = resolve(repo, a)
    if not ac:
        raise No("승인 sha %s 가 이 저장소에 없음(force-push 로 사라짐)" % a[:10])
    if ac == sc:
        return "EQUIV approve=%s head=%s merges=0 files=0" % (ac, sc)
    if not anc(repo, ac, sc, shallow):
        raise No("승인 sha %s 가 PR head %s 의 조상이 아님(rebase·force-push)" % (ac[:10], sc[:10]))
    extra = out(repo, "rev-list", "--no-merges", sc, "^" + ac, "^" + m).split()
    if extra:
        raise No("승인 뒤 main 이 아닌 일반 커밋 %d 개(%s…)" % (len(extra), extra[0][:10]))
    merges = [r.split() for r in out(repo, "rev-list", "--merges", "--parents", sc, "^" + ac, "^" + m).split("\n") if r]
    if not merges:
        raise No("승인 뒤 main 병합 커밋이 없음 — 같은 승인으로 볼 근거 없음")
    trunk = set(out(repo, "rev-list", sc, "^" + ac, "^" + m).split()) | {ac}
    for c, first, *rest in merges:
        if first not in trunk or not rest or not all(anc(repo, p, m, shallow) for p in rest):
            raise No("병합 %s 가 «승인 줄기 + main» 병합이 아님(다른 브랜치·거꾸로 병합)" % c[:10])
    da = norm(repo, out(repo, "merge-base", ac, m).strip(), ac)
    ds = norm(repo, out(repo, "merge-base", sc, m).strip(), sc)
    if da != ds:
        diff = sorted(k.split(" b/")[-1] for k in set(da) | set(ds) if da.get(k) != ds.get(k))
        raise No("자기 변경이 승인 때와 다름(main 대비 diff 불일치: %s)" % ", ".join(diff[:3]))
    p = run(repo, "merge-tree", "--write-tree", "--no-messages", ac, m, ok=(0, 1))
    if p.returncode == 1:
        raise No("승인 세트와 main 이 깨끗이 병합되지 않음(충돌) — 충돌 해소는 새 세트")
    if p.stdout.decode().split()[0] != out(repo, "rev-parse", sc + "^{tree}").strip():
        raise No("S 트리가 «승인 세트 + main 의 깨끗한 병합»과 다름(병합 커밋이 그 밖의 변경을 담음)")
    return "EQUIV approve=%s head=%s merges=%d files=%d" % (ac, sc, len(merges), len(da))


if __name__ == "__main__":
    if len(sys.argv) != 6:
        print("usage: ft_approval_equiv.py <repo> <A> <S> <remote> <target>")
        sys.exit(2)
    try:
        print(check(*sys.argv[1:]))
    except No as e:
        print("NOT-EQUIV %s" % e)
        sys.exit(1)
    except Exception as e:
        print("ERROR %s" % e)
        sys.exit(3)
