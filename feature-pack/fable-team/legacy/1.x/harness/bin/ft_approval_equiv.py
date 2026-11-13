#!/usr/bin/env python3
"""ft_approval_equiv.py <repo> <A> <S> <remote> <target> — R247 판정 1917 동일승인 대조 (읽기 전용 · 로컬 git 만 · 네트워크 0).
A = 오빠가 승인한 PR head, S = 지금 PR head. 아래 넷이 «전부 참» 일 때만 EQUIV (거짓 거절 = 재승인 1번으로 안전 · 거짓 통과 0).
 1 A 가 S 의 조상  2 A..S 는 main 병합 커밋뿐(main 밖 일반 커밋 0 · 병합마다 첫 부모 = 승인 줄기, 나머지 부모 = main 의 조상)
 3 자기 변경 동일: diff(merge-base(A,main), A) 와 diff(merge-base(S,main), S) 의 «파일별 순서 있는 +/- 줄» 이 같음(문맥·hunk 줄 번호 무시)
 4 S 트리 == merge-tree(A, mx) 의 깨끗한 병합 트리 — 3 이 못 잡는 «같은 줄을 다른 위치로 옮긴» 병합 커밋을 막는다(객체만 쓰고 ref·작업트리 0)
 ★r560 기준 main★ mx = merge-base(S, origin/main) = «세트가 이미 품은 가장 새 main». 병합 커밋들의 main 쪽 부모는 전부 mx 의 조상이어야 하고(아니면 «main 부모 역행» = NOT-EQUIV), mx 는 merge-base(A,main) 의 자손이어야 한다(승인 이후 main). 옛 규칙은 «지금 origin/main» 과 비교해 main 이 한 칸만 더 가도 NOT-EQUIV 였다(같은 세트 재승인 폭주 · 판정 1917 의 뜻 = 세트가 병합한 main 기준). ★DA⑥ r1★ «마지막 병합의 main 쪽 부모» 만 쓰면 뒤 병합이 더 옛 main 을 병합한 그래프에서 main 이 지운 파일 부활이 EQUIV 로 샌다 — merge-base 가 그 구멍을 닫는다.
 ★R281(rebase)★ A 가 S 의 조상이 아니면 위 1·2 대신: (a) mx = merge-base(S, main) 가 승인 이후 main(merge-base(A,main) 의 자손) (b) merge-base(A,main) 존재 (c) 3 과 같되 A 쪽 base = merge-base(A,main) · S 쪽 base = mx (d) merge-tree(A, mx) 와 같음 → `mode=rebase` (옛 main 위 rebase 도 EQUIV — 착지 단계 ft-merge-land 의 «main ⊂ S» 가 옛 main 착지를 막는다)
출력 끝 칸: mode=merge|rebase · overlap=<n>(main 이 바꾼 파일 ∩ 자기 변경 파일 — 막지 않는 표지) · base=<mx 10자>)
exit 0 = EQUIV · 1 = NOT-EQUIV(사유 stdout) · 3 = ERROR(판단 불가·승인 객체 로컬에 없음 = 통과 0)
r1815 여러 후보: ft_approval_equiv.py --many <repo> <S> <remote> <target> < 후보(줄마다 A 40hex) → 후보마다 «<A> + 단건 출력» · 첫 EQUIV 에서 멈춤 · rc 0 = EQUIV 있음 · 1 = 없음 · 2 = 입력 오류
  한 실행 공유 값(S·main 에만 기대는 git 호출 · share=True)은 1회만 · 존재 확인 = cat-file --batch-check 1프로세스(GIT_NO_LAZY_FETCH=1) · 후보별 조상·diff·merge-tree 는 공유 0"""
import os
import re
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor


class Fail(Exception):
    pass


class No(Exception):
    pass


MEMO = None   # r1815 --many: {git 인자: 결과} — share=True 호출(S·main 만 기대는 값)만 · 단건 = None(지금 그대로)
RES = {}      # r1815 --many: {rev: commit sha|None} — cat-file --batch-check 1회로 미리 채움(r1880: worker 시작 전 · 뒤로는 읽기만)
LOCK = threading.Lock()   # r1880: MEMO get/set 잠금(같은 키 두 번 계산은 허용 · 값 같음)


def run(repo, *a, ok=(0,), env=None, share=False):
    with LOCK:
        p = MEMO.get(a) if share and MEMO is not None else None
    if p is None:
        try:
            p = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", *a], capture_output=True, timeout=30, env=env)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise Fail("git %s 실행 실패: %s" % (a[0], e))
        if share and MEMO is not None:
            with LOCK:
                MEMO[a] = p
    if p.returncode not in ok:
        raise Fail("git %s 실패(rc=%d): %s" % (" ".join(a[:2]), p.returncode, p.stderr.decode("utf-8", "replace").strip()[:100]))
    return p


def out(repo, *a, share=False):
    return run(repo, *a, share=share).stdout.decode("latin-1")


def resolve(repo, x):
    if MEMO is not None and x in RES:
        return RES[x]
    p = run(repo, "rev-parse", "--verify", "-q", x + "^{commit}", ok=(0, 1), env=dict(os.environ, GIT_NO_LAZY_FETCH="1"))  # r1783: 존재 확인만 원격 lazy fetch 0(diff·merge-base 는 blob 필요 — env 0)
    return p.stdout.decode().strip() if p.returncode == 0 else None


def anc(repo, a, b, shallow):
    rc = run(repo, "merge-base", "--is-ancestor", a, b, ok=(0, 1)).returncode
    if rc == 1 and shallow:
        raise Fail("shallow 저장소 — 조상 판정 불가")
    return rc == 0


def norm(repo, base, tip, share=False):
    """base→tip diff 를 {'diff --git 줄': [모드·경로 머리 줄 + 순서 있는 +/- 줄 (+ 바이너리는 새 blob)]} 로 정규화."""
    recs, key, hunk, new = {}, None, False, ""
    args = ("diff", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", "--full-index", "--unified=0", base, tip)
    for ln in out(repo, *args, share=share).split("\n"):
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
    shallow = out(repo, "rev-parse", "--is-shallow-repository", share=True).strip() == "true"
    m = resolve(repo, "refs/remotes/%s/%s" % (remote, target))
    sc = resolve(repo, s)
    if not m or not sc:
        raise Fail("main(%s/%s) 또는 PR head 를 확인할 수 없음" % (remote, target))
    ac = resolve(repo, a)
    if not ac:
        raise Fail("승인 sha %s 객체가 이 저장소에 없음(네트워크 0 — 대조 불가·재승인)" % a[:10])
    if ac == sc:
        return "EQUIV approve=%s head=%s merges=0 files=0 mode=merge overlap=0 base=%s" % (ac, sc, ac[:10])
    if not anc(repo, ac, sc, shallow):
        return rebased(repo, ac, sc, m, shallow)
    extra = out(repo, "rev-list", "--no-merges", sc, "^" + ac, "^" + m).split()
    if extra:
        raise No("승인 뒤 main 이 아닌 일반 커밋 %d 개(%s…)" % (len(extra), extra[0][:10]))
    merges = [r.split() for r in out(repo, "rev-list", "--merges", "--topo-order", "--parents", sc, "^" + ac, "^" + m).split("\n") if r]
    if not merges:
        raise No("승인 뒤 main 병합 커밋이 없음 — 같은 승인으로 볼 근거 없음")
    trunk = set(out(repo, "rev-list", sc, "^" + ac, "^" + m).split()) | {ac}
    for c, first, *rest in merges:
        if first not in trunk or not rest or not all(anc(repo, p, m, shallow) for p in rest):
            raise No("병합 %s 가 «승인 줄기 + main» 병합이 아님(다른 브랜치·거꾸로 병합)" % c[:10])
    mx = out(repo, "merge-base", sc, m, share=True).strip()   # r560 DA⑥: «S 가 이미 품은 가장 새 main» (뒤 병합이 옛 main 을 병합해도 여기서 드러난다)
    if not mx or not anc(repo, out(repo, "merge-base", ac, m).strip(), mx, shallow):
        raise No("세트가 품은 main(%s)이 승인 이후 main 이 아님 — 기준 삼을 수 없음" % (mx[:10] or "없음"))
    if [p for c, first, *rest in merges for p in (rest or [mx]) if not anc(repo, p, mx, shallow)]:
        raise No("병합 커밋의 main 쪽 부모가 기준 main(%s)보다 앞섬(역행 그래프) — 같은 승인으로 볼 수 없음" % mx[:10])
    mb = out(repo, "merge-base", ac, mx).strip()
    da = norm(repo, mb, ac)
    ds = norm(repo, out(repo, "merge-base", sc, mx, share=True).strip(), sc, share=True)
    if da != ds:
        diff = sorted(k.split(" b/")[-1] for k in set(da) | set(ds) if da.get(k) != ds.get(k))
        raise No("자기 변경이 승인 때와 다름(main 대비 diff 불일치: %s)" % ", ".join(diff[:3]))
    p = run(repo, "merge-tree", "--write-tree", "--no-messages", ac, mx, ok=(0, 1))
    if p.returncode == 1:
        raise No("승인 세트와 main 이 깨끗이 병합되지 않음(충돌) — 충돌 해소는 새 세트")
    if p.stdout.decode().split()[0] != out(repo, "rev-parse", sc + "^{tree}", share=True).strip():
        raise No("S 트리가 «승인 세트 + main 의 깨끗한 병합»과 다름(병합 커밋이 그 밖의 변경을 담음)")
    return "EQUIV approve=%s head=%s merges=%d files=%d mode=merge overlap=%d base=%s%s" % (ac, sc, len(merges), len(da), overlap(repo, da, mb, mx), mx[:10], ov_names(repo, da, mb, mx))


def ov_names(repo, da, mb, m):
    """겹친 파일 이름(최대 3 · 겹침 있을 때만 EQUIV 줄 끝에 « names=a,b») — r1275 단계 4: 재질문 사유를 사람이 읽게. 계산·판정 변경 0."""
    mine = {k.split(" b/")[-1] for k in da}
    hit = sorted(mine & set(out(repo, "diff", "--name-only", "--no-renames", mb, m).split("\n")))
    return " names=" + ",".join(hit[:3]) if hit else ""


def overlap(repo, da, mb, m):
    """main 이 base(mb)→main 사이에 바꾼 파일 ∩ PR 이 바꾼 파일 수 — 막지 않는 표지(같은 파일이면 의미가 base 에 따라 달라질 수 있음)."""
    mine = {k.split(" b/")[-1] for k in da}
    return len(mine & set(out(repo, "diff", "--name-only", "--no-renames", mb, m).split("\n")))


def rebased(repo, ac, sc, m, shallow):
    """R281 rebase 동일 + r560 기준 main: A ⊄ S 이면 (a) mx = merge-base(S, main) 이 승인 이후 main(merge-base(A,main) 의 자손) (b) merge-base(A,main) 존재 (c) 자기 변경 동일 (d) merge-tree(A, mx) 깨끗 ∧ == S 트리.
    r560: 옛 (a) «지금 main ⊂ S» 폐기 — main 이 한 칸 더 가면 같은 세트가 NOT-EQUIV 가 됐다. 옛 main 위 head 는 착지 단계(ft-merge-land 의 «main ⊂ S»)가 막는다."""
    p = run(repo, "merge-base", sc, m, ok=(0, 1), share=True)
    if p.returncode == 1:
        raise No("승인 sha %s 가 PR head %s 의 조상이 아니고 PR head 와 main 의 공통 조상도 없음" % (ac[:10], sc[:10]))
    mx = p.stdout.decode().strip()
    p = run(repo, "merge-base", ac, m, ok=(0, 1))
    if p.returncode == 1:
        raise No("승인 세트와 main 의 공통 조상이 없음")
    mb = p.stdout.decode().strip()
    if not mx or not anc(repo, mb, mx, shallow):
        raise No("PR head 가 올라탄 main(%s)이 승인 이후 main 이 아님 — rebase 동일로 볼 수 없음" % (mx[:10] or "없음"))
    da, ds = norm(repo, mb, ac), norm(repo, mx, sc, share=True)
    if da != ds:
        diff = sorted(k.split(" b/")[-1] for k in set(da) | set(ds) if da.get(k) != ds.get(k))
        raise No("rebase 한 자기 변경이 승인 때와 다름(main 대비 diff 불일치: %s)" % ", ".join(diff[:3]))
    p = run(repo, "merge-tree", "--write-tree", "--no-messages", ac, mx, ok=(0, 1))
    if p.returncode == 1:
        raise No("승인 세트와 main 이 깨끗이 병합되지 않음(충돌) — 충돌 해소는 새 세트")
    if p.stdout.decode().split()[0] != out(repo, "rev-parse", sc + "^{tree}", share=True).strip():
        raise No("S 트리가 «승인 세트 + 지금 main 의 깨끗한 병합»과 다름(rebase 중 손 편집)")
    return "EQUIV approve=%s head=%s merges=0 files=%d mode=rebase overlap=%d base=%s%s" % (ac, sc, len(da), overlap(repo, da, mb, mx), mx[:10], ov_names(repo, da, mb, mx))


def many(repo, s, remote, target, cands):
    """r1815 A1·A2: 후보 순서대로 단건 판정 · 줄 = «<A> » + 단건 출력 바이트 · 첫 EQUIV 에서 멈춤."""
    global MEMO
    MEMO = {}
    revs = ["refs/remotes/%s/%s" % (remote, target), s] + cands
    try:
        p = subprocess.run(["git", "-C", repo, "cat-file", "--batch-check"], input="".join(x + "^{commit}\n" for x in revs).encode(),
                           capture_output=True, timeout=30, env=dict(os.environ, GIT_NO_LAZY_FETCH="1"))
        got = [g.split() for g in p.stdout.decode("latin-1").split("\n")]
        RES.update((x, g[0] if len(g) == 3 else None) for x, g in zip(revs, got) if p.returncode == 0 and len(got) > len(revs))
    except (OSError, subprocess.TimeoutExpired):
        pass   # 미리 채우기 실패 = 단건 resolve 그대로(판정 같음)
    # r1880: 후보 4개씩 동시(git = 하위 프로세스) · 출력은 후보 순서대로 · 첫 EQUIV 줄 뒤 0 → 대기 future 취소(실행 중 git 은 끝까지 기다림)
    with ThreadPoolExecutor(max_workers=4) as ex:
        for f in [ex.submit(one, repo, a, s, remote, target) for a in cands]:
            rc, line = f.result()
            print(line, flush=True)
            if rc == 0:
                ex.shutdown(wait=False, cancel_futures=True)
                return 0
    return 1


def one(repo, a, s, remote, target):
    try:
        return 0, "%s %s" % (a, check(repo, a, s, remote, target))
    except No as e:
        return 1, "%s NOT-EQUIV %s" % (a, e)
    except Exception as e:
        return 1, "%s ERROR %s" % (a, e)


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "--many":
        c = [x for x in sys.stdin.read().split("\n") if x]
        sys.exit(many(*sys.argv[2:], c) if c and all(re.fullmatch("[0-9a-f]{40}", x) for x in c) else 2)
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
