"""autonomy_scope_secret.py — 분류기가 쓰는 «추가 줄 추출(diff 상태 기계)» 과 «비밀 판정기(ft_secret_judge) 호출 범위» (r559).

왜: 14MB 세트를 통째로 plan() 에 넣으면 판정기가 세그먼트마다 같은 글을 다시 훑어 96초가 걸린다(프로파일 = evidence/r559/03-profile-before.txt).
H1(DA⑥ r1): 본문 줄 «++ …» 을 머리로 오인하거나 따옴표 경로를 버리면 SECRET_SHAPE 가 새므로, diff 를 «상태 기계» 로 읽는다 —
  `diff --git` = 새 파일 · `@@` 뒤 = hunk 안 · hunk 안의 «+» 줄은 «+++» 여도 추가 줄 · 경로는 `-c core.quotepath=off` + C 따옴표 풀기 ·
  경로를 못 풀면 그 파일은 code(전문 plan()).
H2(DA⑥ r1): 문서는 «평범한 산문» 만 plan() 밖 — 그 파일의 «바뀐 뒤 전문»(git cat-file --batch 1회) 기준 ``` ~~~ 울타리 안 ·
  들여쓰기(4칸·탭) · 백틱 포함 · «! »·«$ »·«> » 시작 · 표 행(백틱 있을 때) 은 plan() · 전문을 못 읽으면 그 문서 추가 줄 전부 plan().
H3(DA⑥ r1): code 로 분류된 파일은 추가 줄 «전문» 을 plan() 에 넘긴다(변수 추적 보존 · 덩어리 = 파일 경계로만).
SECRET_SHAPE(키 원문 모양)는 이 상태 기계가 뽑은 «모든 추가 줄» 을 본다(줄이지 않음).
H4(r909 r3 · 하드 룰 14 「추적 대신 예외를 좁힌다」): 셸 판정 밖으로 빼는 예외는 «하나» 뿐 —
  코드 확장자(.py·.ts·.js·.go·.rs …) 파일의 추가 줄에서 문자열 리터럴 «밖» 의 식별자 «set(» 를 «set_(» 로 바꾸는 것.
  자료 확장자(.json·.txt·.sql …) 제외는 없다(DA⑥ r2 반례 1 — ci/task.txt 의 printf 비밀). 문서(.md)는 셔뱅이 «없을» 때만 doc_cmds(반례 3).
  셔뱅 있는 파일은 확장자 무관 전 줄 판정. YAML 은 추가 줄만 보고 run:/script: 값·목록 항목의 명령을 뽑아 판정한다(기준판처럼 전문 블록 재검사 0 — 오탐 2).
  키 원문 모양(SECRET_SHAPE)은 종전대로 모든 추가 줄을 본다(줄이지 않음).
"""
import re
import subprocess

class ImportErr(Exception):
    pass

EDGE_CHARS = "A-Za-z0-9_"  # ★비밀 «경계» 를 정하는 글자 집합 — ft_secret_shapes.py 와 «같아야» 한다(정의 중복은 남기되 집합은 한 벌)
EDGE_L = "(?<![" + EDGE_CHARS + "])"  # r977 r4(오빠 결정 1번): «왼쪽» 경계만 한 벌 — «오른쪽» 경계는 base 와 같다(AKIA 만 `\b` · 나머지 꼴은 값 뒤 경계 없음)
# r977 r2(DA⑥ r1 반례 2): PEM 머리말은 «경계 없이»(base 그대로) — 앞에 ASCII 글자가 붙은 `note-----BEGIN …` 를 놓치면 안 된다. 나머지 4꼴만 EDGE 묶음 안.
# r977 r4: 오른쪽 경계를 base 꼴로 — 끝 밸줄·끝 하이픈 토큰(`ghs_AAAA…_`)도 base 처럼 잡힌다(DA⑥ r2 반례 ②).
SECRET_SHAPE = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----|" + EDGE_L + r"(?:AKIA[0-9A-Z]{16}\b|gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})")
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


SHELL_LANG = {"", "bash", "sh", "shell", "zsh", "console", "sh-session", "shell-session"}   # 울타리 언어 — 표시가 없으면 셸로 본다
CODE_LANG = {"python", "py", "python3", "js", "javascript", "jsx", "ts", "typescript", "tsx", "go", "rust", "rs", "ruby", "rb",
             "java", "kotlin", "kt", "c", "cpp", "c++", "cs", "csharp", "php", "swift", "scala", "lua", "dart", "perl", "pl",
             "elixir", "ex"}   # 코드 언어 울타리 — 코드 파일과 같은 규칙(식별자 set( 만 가린다 · r909 r5)


def _fence_lang(s, mark):   # ```bash → "bash" · ``` → ""
    rest = s[len(mark):].strip()
    return rest.split()[0].lower() if rest else ""


def _shield_fence(body):   # {줄 번호: 글} 코드 울타리 본문 — 문자열 리터럴 밖 식별자 set( 만 가린 글(os.system("set") 속 set 은 그대로)
    nums = [n for n, _t in body]
    out = shield_set_call("\n".join(t for _n, t in body)).split("\n")
    return dict(zip(nums, out))


def doc_cmds(full, items):   # 문서: plan() 에 넘길 «실행될 수 있는» 줄 — full = 바뀐 뒤 전문(없으면 전부)
    if full is None:
        return "\n".join(t for _n, t in items)
    ctx, fence, code, body, shield = set(), "", False, [], {}
    for i, ln in enumerate(full.split("\n"), 1):
        s = ln.strip()
        if s.startswith("```") or s.startswith("~~~"):
            mark = s[:3]
            if fence == mark:   # 닫는 울타리
                if code:
                    shield.update(_shield_fence(body))
                fence, code, body = "", False, []
            elif not fence:     # 여는 울타리 — 코드 언어면 본문에 set( 가리기
                fence, code, body = mark, _fence_lang(s, mark) in CODE_LANG, []
            ctx.add(i)
            continue
        if fence or ln.startswith(("    ", "\t")) or "`" in ln or ln.lstrip().startswith(("! ", "$ ", "> ")):
            ctx.add(i)
            if fence and code:
                body.append((i, ln))
    if fence and code:   # 닫히지 않은 울타리도 같은 규칙
        shield.update(_shield_fence(body))
    return "\n".join(_promptless(shield.get(n, t)) for n, t in items if n in ctx)


def _promptless(t):   # «$ »·«! » 는 셸 프롬프트 표시 — 판정기에는 명령만 넘긴다
    head = t.lstrip()
    return head[2:] if head.startswith(("! ", "$ ")) else t


SHELL_EXT = (".sh", ".bash", ".zsh", ".ksh", ".dash", ".command", ".bats")
YAML_EXT = (".yml", ".yaml")
# 코드 확장자 — «문자열 리터럴 안» 글만 셸 판정에 넘긴다(r1195 · 옛 H5 «식별자 set(» 가림을 흡수)
CODE_EXT = (".py", ".pyi", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".go", ".rb", ".java", ".kt", ".kts",
             ".rs", ".c", ".h", ".cc", ".cpp", ".hpp", ".cs", ".php", ".swift", ".scala", ".pl", ".lua", ".dart",
             ".ex", ".exs", ".vue", ".svelte")
SET_CALL = re.compile(r"(?<![\w$])set(?=\()")   # 식별자 «set(» — 괄호 바로 앞
YAML_RUN = re.compile(r"""^\s*(?:-\s+)?["']?(?:run|script)["']?\s*:\s*(.*)$""")
YAML_BLOCK = re.compile(r"^[|>][-+]?\s*(?:#.*)?$")
DOC_EXT = (".md", ".markdown", ".rst")   # 문서 = 종전처럼 «실행될 수 있는 줄» 만 판정(셔뱅 없을 때)


def ext_of(path):   # 경로 → 소문자 확장자(".py") · 없으면 ""
    base = path.rsplit("/", 1)[-1].lower()
    return base[base.rfind("."):] if "." in base else ""


def _in_literals(text):   # 글자마다 «문자열 리터럴 안» 인가 — 여러 줄 따옴표·백틱 추적(주석은 리터럴로 보지 않는다)
    mask, i, n, q, triple = [False] * len(text), 0, len(text), "", False
    while i < n:
        c = text[i]
        if q:
            mask[i] = True
            if triple:
                if text.startswith(q * 3, i):
                    mask[i:i + 3] = [True, True, True]
                    i += 3
                    q, triple = "", False
                    continue
                i += 1
                continue
            if c == "\\" and i + 1 < n:
                mask[i + 1] = True
                i += 2
                continue
            q = "" if c == q or c == "\n" else q   # 한 줄 따옴표는 줄 끝에서 끝난다
            i += 1
            continue
        if text.startswith('"""', i) or text.startswith("'''", i):
            q, triple = text[i], True
            mask[i:i + 3] = [True, True, True]
            i += 3
            continue
        if c in "\"'`":
            q, triple = c, False
            mask[i] = True
        i += 1
    return mask


def shield_set_call(text):   # 코드 확장자의 «식별자 set(» 만 «set_(» 로 — 문자열 리터럴 안의 set·다른 낱말은 그대로(DA⑥ 반례 1)
    mask, out, i = _in_literals(text), [], 0
    for m in SET_CALL.finditer(text):
        if mask[m.start()]:
            continue
        out.append(text[i:m.end()])
        out.append("_")
        i = m.end()
    out.append(text[i:])
    return "".join(out)


def yaml_added(items):   # yaml: «추가 줄만» — run:/script: 값과 목록 항목의 명령을 뽑아 판정(기준판 동작 유지 · 블록 재검사 0)
    out = []
    for _n, t in items:
        m = YAML_RUN.match(t)
        if m:
            s = m.group(1).strip()
            if YAML_BLOCK.match(s):
                continue            # `run: |-` 류 — 본문 줄이 따로 추가 줄로 온다
        else:
            s = t.strip()
            if s.startswith("- "):
                s = s[2:].strip()
        s = s.strip().strip("[]").strip().strip("\"'")
        if s:
            out.append(s)
    return "\n".join(out)


def shell_text(path, is_doc, items, full):   # plan() 에 넘길 글 · "" = 이 파일은 셸 판정 밖
    text = "\n".join(t for _n, t in items)
    if path is None:   # 경로를 못 풀면 전부 판정(닫힌 쪽)
        return text
    ext = ext_of(path)
    if ext in SHELL_EXT or not ext:
        return text   # 셸 확장자 · 확장자 없는 실행 스크립트
    if full and full.split("\n", 1)[0].startswith("#!"):
        return text   # 셔뱅 있는 파일 = 셸 문맥(확장자 무관 · DA⑥ r3 반례 3)
    if is_doc or ext in DOC_EXT:
        return doc_cmds(full, items)   # 문서는 «셔뱅 없는» 파일만(실행될 수 있는 줄)
    if ext in YAML_EXT:
        return yaml_added(items)       # 기준판 동작 + 추가 줄만
    if ext in CODE_EXT and full is not None:   # 코드 = «문자열 리터럴 안» 글만(r1195 · 식별자 괄호 «(env)» 는 부분 셸 아님)
        mask = _in_literals(full)
        kept = "".join(c if m or c == "\n" else " " for c, m in zip(full, mask)).split("\n")   # 줄 번호는 그대로
        return "\n".join(kept[n - 1] if 0 < n <= len(kept) else t for n, t in items)
    return text   # 그 밖 = 판정한다(닫힌 쪽)


def reason(blocks, class_of, repo, sha):   # 이유 글자 꼴은 종전 그대로 · 덩어리 = 파일 경계
    text = "\n".join(t for _p, items, _n in blocks for _no, t in items)
    if SECRET_SHAPE.search(text):
        return "추가 줄에 비밀 꼴"
    try:
        import ft_secret_judge
    except SystemExit:
        raise ImportErr("ft_secret_judge 를 불러오지 못함")
    full = {p: "\n".join(t for _no, t in items) for p, items, new in blocks if new}
    full.update(read_new(repo, sha, [p for p, _i, new in blocks if p and not new]))
    for path, items, _new in blocks:
        text = shell_text(path, path is not None and class_of(path)[0] == "docs", items, full.get(path) if path else None)
        found = ft_secret_judge.plan(text) if text.strip() else []
        if found:
            return "추가 줄: " + found[0][1]
    return None
