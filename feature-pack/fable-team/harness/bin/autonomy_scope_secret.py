"""autonomy_scope_secret.py — 분류기가 쓰는 «추가 줄 추출(diff 상태 기계)» 과 «비밀 판정기(ft_secret_judge) 호출 범위» (r559).

왜: 14MB 세트를 통째로 plan() 에 넣으면 판정기가 세그먼트마다 같은 글을 다시 훑어 96초가 걸린다(프로파일 = evidence/r559/03-profile-before.txt).
H1(DA⑥ r1): 본문 줄 «++ …» 을 머리로 오인하거나 따옴표 경로를 버리면 SECRET_SHAPE 가 새므로, diff 를 «상태 기계» 로 읽는다 —
  `diff --git` = 새 파일 · `@@` 뒤 = hunk 안 · hunk 안의 «+» 줄은 «+++» 여도 추가 줄 · 경로는 `-c core.quotepath=off` + C 따옴표 풀기 ·
  경로를 못 풀면 그 파일은 code(전문 plan()).
H2(DA⑥ r1): 문서는 «평범한 산문» 만 plan() 밖 — 그 파일의 «바뀐 뒤 전문»(git cat-file --batch 1회) 기준 ``` ~~~ 울타리 안 ·
  들여쓰기(4칸·탭) · 백틱 포함 · «! »·«$ »·«> » 시작 · 표 행(백틱 있을 때) 은 plan() · 전문을 못 읽으면 그 문서 추가 줄 전부 plan().
H3(DA⑥ r1): code 로 분류된 파일은 추가 줄 «전문» 을 plan() 에 넘긴다(변수 추적 보존 · 덩어리 = 파일 경계로만).
SECRET_SHAPE(키 원문 모양)는 이 상태 기계가 뽑은 «모든 추가 줄» 을 본다(줄이지 않음).
"""
import re
import subprocess

class ImportErr(Exception):
    pass

SECRET_SHAPE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{30,}|\bsk-[A-Za-z0-9_-]{20,}|\bxox[abprs]-[A-Za-z0-9-]{10,}")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def unquote(s):   # git 의 C 따옴표(`"b/…"`) 풀기 — 따옴표가 «b/ 까지» 감싼다
    if len(s) >= 2 and s.startswith('"') and s.endswith('"'):
        s = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), s[1:-1])
        s = re.sub(r"\\(.)", lambda m: {"t": "\t", "n": "\n", "r": "\r", "\\": "\\", '"': '"'}.get(m.group(1), m.group(1)), s)
    return s


def path_of(raw):   # `+++ b/<경로>` → 리포 기준 경로(따옴표면 먼저 풀기) · 못 풀면 None(= code 로 본다)
    s = unquote(raw.strip())
    return s[2:] if s.startswith("b/") else None


def parse_added(git, repo, base, sha):   # → [(경로|None, [(새 파일 줄번호, 글)…], 새 파일인가)] · 한 번의 diff(파일마다 git 호출 0)
    out = git(repo, "-c", "core.quotepath=off", "diff", "--no-color", "--no-renames", "-U0", base, sha)
    blocks, cur, newno, hunk, new = [], None, 0, False, False
    for ln in out.split("\n"):
        if ln.startswith("diff --git "):
            cur, hunk, new = None, False, False
            continue
        if not hunk and ln.startswith("--- "):
            new = ln[4:].strip() == "/dev/null"   # 새 파일 = «바뀐 뒤 전문» 이 곧 추가 줄(cat-file 생략)
            continue
        if not hunk and ln.startswith("+++ "):
            path = path_of(ln[4:])
            cur = [] if path else None
            if cur is not None:
                blocks.append((path, cur, new))
            continue
        m = HUNK.match(ln)
        if m:
            newno, hunk = int(m.group(1)), True
        elif hunk and ln.startswith("+"):
            if cur is not None:
                cur.append((newno, ln[1:]))
            newno += 1
    return blocks


def read_new(repo, sha, paths):   # git cat-file --batch → {경로: 바뀐 뒤 전문} · 못 읽은 경로는 빼다(바이트로 읽어 크기 어긋남 0)
    paths = sorted(set(paths))
    got = {}
    for k in range(0, len(paths), 400):   # 400개씩 — 한 번에 다 넣으면 git 호출 상한(7초)을 넘는다
        got.update(_batch(repo, sha, paths[k:k + 400]))
    return got


def _batch(repo, sha, paths):
    p = subprocess.run(["git", "-C", repo, "cat-file", "--batch"], capture_output=True, timeout=7,
                       input="".join("%s:%s\n" % (sha, x) for x in paths).encode())
    data, i, got = p.stdout, 0, {}
    for path in paths:
        nl = data.find(b"\n", i)
        if nl < 0:
            break
        head = data[i:nl].split(b" ")
        i = nl + 1
        if len(head) < 3 or not head[2].isdigit():
            continue
        size = int(head[2])
        got[path] = data[i:i + size].decode("utf-8", "replace")
        i += size + 1
    return got


def doc_cmds(full, items):   # 문서: plan() 에 넘길 «실행될 수 있는» 줄 — full = 바뀐 뒤 전문(없으면 전부)
    if full is None:
        return "\n".join(t for _n, t in items)
    ctx, fence = set(), ""
    for i, ln in enumerate(full.split("\n"), 1):
        s = ln.strip()
        if s.startswith("```") or s.startswith("~~~"):
            mark = s[:3]
            ctx.add(i)
            fence = "" if fence == mark else (fence or mark)
            continue
        if fence or ln.startswith(("    ", "\t")) or "`" in ln or ln.lstrip().startswith(("! ", "$ ", "> ")):
            ctx.add(i)
    return "\n".join(_promptless(t) for n, t in items if n in ctx)


def _promptless(t):   # «$ »·«! » 는 셸 프롬프트 표시 — 판정기에는 명령만 넘긴다
    head = t.lstrip()
    return head[2:] if head.startswith(("! ", "$ ")) else t


def reason(blocks, class_of, repo, sha):   # 이유 글자 꼴은 종전 그대로 · 덩어리 = 파일 경계
    text = "\n".join(t for _p, items, _n in blocks for _no, t in items)
    if SECRET_SHAPE.search(text):
        return "추가 줄에 비밀 꼴"
    try:
        import ft_secret_judge
    except SystemExit:
        raise ImportErr("ft_secret_judge 를 불러오지 못함")
    full = {p: "\n".join(t for _no, t in items) for p, items, new in blocks if new}
    full.update(read_new(repo, sha, [p for p, _i, new in blocks if p and not new and class_of(p)[0] != "code"]))
    for path, items, _new in blocks:
        if path is None or class_of(path)[0] == "code":   # 경로를 못 푼 파일은 code 로 본다
            text = "\n".join(t for _n, t in items)
        else:
            text = doc_cmds(full.get(path), items)
        found = ft_secret_judge.plan(text) if text.strip() else []
        if found:
            return "추가 줄: " + found[0][1]
    return None
