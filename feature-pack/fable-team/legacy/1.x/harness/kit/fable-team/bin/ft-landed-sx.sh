#!/usr/bin/env bash
# ft-landed-sx.sh — r1713: «카드 세트 S ⊂ 끝줄 head X» 같은 산출 판정 한 곳(r1084 3칸 · ft-nano-close.sh _lp_sx_gate 와 ft-nano-close-due.sh 가 같이 부른다 · 두 벌 0).
#   usage: ft-landed-sx.sh <repo> <S 40hex> <X 40hex> [<main ref> (기본 refs/remotes/origin/main)]
#   통과 = ⓐ S 가 X 의 조상 ⓑ S..X 첫 부모 줄에 «main 병합 아닌 일반 커밋» 0 ⓒ merge-base(<main ref>) 대비 «자기 변경» patch-id S = X(둘 다 비어 있지 않음)
#   반환값: 0 = 통과(stdout «SX-OK merges=<S..X 첫 부모 main 병합 수>») · 1 = 조건 거짓(출력 0) · 2 = 판정 불가(stderr 1줄 «판정 불가 <단계> rc=<n>: <git 출력 첫 줄>»)
#     단계 = ancestor · revlist · mb-set · mb-head · pid-set · pid-head · merges · usage — rc 124 = 시간 초과(하드 룰 12 · 20: 실패·초과로 통과 0)
#   env FT_LANDED_SX_CAP = git 호출마다 상한 초(기본 7) · 넘으면 그 묶음(새 세션) 전부 KILL · 읽기만(refs·워크트리 쓰기 0)
set -uo pipefail
exec python3 - "$@" <<'PY'
import os, signal, subprocess, sys

def fail(step, rc, out=""):
    first = (out.split("\n") or [""])[0] if out else ""
    print(f"판정 불가 {step} rc={rc}: {first}", file=sys.stderr); sys.exit(2)

a = sys.argv[1:]
if len(a) not in (3, 4) or not all(a[:3]): fail("usage", 2, "ft-landed-sx.sh <repo> <S> <X> [<main ref>]")
repo, s, x = a[0], a[1], a[2]
ref = a[3] if len(a) == 4 and a[3] else "refs/remotes/origin/main"
try: cap = max(0.5, float(os.environ.get("FT_LANDED_SX_CAP") or 7))
except ValueError: cap = 7.0

def call(cmd):   # → (rc, stdout+stderr 를 꼬리 개행 뗀 값) · 시간 초과 = 124 · 실행 불가 = 127
    try: p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
    except OSError as e: return 127, str(e)
    try: out, _ = p.communicate(timeout=cap)
    except subprocess.TimeoutExpired:
        try: os.killpg(p.pid, signal.SIGKILL)
        except OSError: pass
        p.communicate(); return 124, ""
    return p.returncode, out.rstrip("\n")

git = lambda *r: call(["git", "-C", repo, *r])
pid = lambda base, tip: call(["bash", "-c", 'set -o pipefail; git -C "$1" diff "$2" "$3" | git patch-id --stable', "_", repo, base, tip])

rc, out = git("merge-base", "--is-ancestor", s, x)   # ⓐ rc 1 = «아니오» = 거짓
if rc == 1: sys.exit(1)
if rc != 0: fail("ancestor", rc, out)
rc, out = git("rev-list", "--first-parent", "--no-merges", f"{s}..{x}")   # ⓑ 0줄 = main 병합뿐
if rc != 0: fail("revlist", rc, out)
if out: sys.exit(1)
rc, mb1 = git("merge-base", s, ref)   # ⓒ 자기 변경 = merge-base 대비 diff 의 patch-id
if rc != 0 or not mb1: fail("mb-set", rc, mb1)
rc, mb2 = git("merge-base", x, ref)
if rc != 0 or not mb2: fail("mb-head", rc, mb2)
rc, p1 = pid(mb1, s)
if rc != 0: fail("pid-set", rc, p1)
rc, p2 = pid(mb2, x)
if rc != 0: fail("pid-head", rc, p2)
first = lambda t: next((l.split()[0] for l in t.split("\n") if l.split()), "")
p1, p2 = first(p1), first(p2)
if not p1 or not p2 or p1 != p2: sys.exit(1)
rc, n = git("rev-list", "--first-parent", "--merges", "--count", f"{s}..{x}")   # 통과 문구의 «main 병합 <n>개»
if rc != 0 or not n[:1].isdigit(): fail("merges", rc, n)
print(f"SX-OK merges={n}")
PY
