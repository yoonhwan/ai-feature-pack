# block-destructive-judge.py 보조 (R115 · 판정 466 글 싱크 목록의 확장 — 오빠 값 필요).
# ① hil 싱크: ft-hil.sh 는 계획 파일을 쓰고 링크만 만든다(실행 0 · eval 0). 그 «등록» 구간만 글 싱크로 인정한다.
#   자격 = 구간이 정확히 `bash <P> --cmd <단어1>` | `bash <P> --add <단어1>` (리다이렉트 0 · 앞 대입 0 · P 는 글롭·변수 없는 절대경로)
#        + realpath(P) 가 hil-paths.txt(이 파일 옆 · 줄마다 realpath · 설치가 작성)에 있을 때.
#   목록 파일 없음·빈 파일·읽기 실패 = 자격 0 (fail-closed). 명령에 싱크 아닌 구간이 하나라도 있으면 자격 0.
#   같은 명령이 허용 hil 파일·목록 파일(별칭 symlink·hardlink 포함)에 «쓰면» 자격 0 — 쓰고 곧 실행하는 꼴 차단(DA⑥ HOLD 1).
# ② ungit: `git` 낱말 뒤 전역 옵션(-C·-c·--git-dir·--work-tree 등)을 «셸 토큰 단위로» 걷는다 — 값 안 `;` `|` `&` 에 속지 않는다(DA⑥ HOLD 2).
import os, re, shlex

LIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hil-paths.txt")
FILE_OUT = {">", ">>", ">|", "&>", "&>>", ">&", "<>"}
VAL_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--super-prefix", "--attr-source"}

def allowed():
    try: return {l.strip() for l in open(LIST, encoding="utf-8") if l.strip() and not l.startswith("#")}
    except OSError: return set()

def sink(words, redirs):
    if len(words) != 4 or redirs or words[0] != "bash" or words[2] not in ("--cmd", "--add"): return False
    p = words[1]
    if not p.startswith("/") or re.search(r"[*?\[\]{}$~`]", p) or ".." in p.split("/"): return False
    return os.path.isfile(p) and os.path.realpath(p) in allowed()

def wtargets(g):   # 구간이 «쓰는» 파일 이름들(리다이렉트 대상 · tee 인자)
    outs = [t for o, t in g["redirs"] if o in FILE_OUT and t != "/dev/null" and not (o == ">&" and re.fullmatch(r"\d+|-", t))]
    return outs + ([w for w in g["words"][1:] if not w.startswith("-")] if g["cmd"] == "tee" else [])

def hits(t, cwd, prot):   # 쓰기 대상이 보호 파일일 수 있는가 — 풀 수 없는 이름(글롭·변수·cwd 없는 상대)은 «맞다»
    if re.search(r"[*?\[\]{}$~`]", t) or (not os.path.isabs(t) and not cwd): return True
    r = os.path.realpath(os.path.join(cwd or "/", t))
    return r in prot or os.path.exists(r) and any(os.path.exists(p) and os.path.samefile(r, p) for p in prot)

def bad(segs, cwd):   # hil 싱크가 있는데 자격을 깎아야 하면 True → 명령 전체 검사
    if not any(g["hil"] for g in segs): return False
    if any(g["kind"] != "sink" for g in segs): return True
    prot = allowed() | {LIST}
    return any(hits(t, cwd, prot) for g in segs for t in wtargets(g))

def ungit(toks):   # `git` 뒤 전역 옵션 토큰을 걷은 사본 — 옵션이 아닌 첫 낱말(하위명령)부터 그대로
    out, i = [], 0
    while i < len(toks):
        out.append("git" if os.path.basename(toks[i]) == "git" else toks[i]); g = out[-1] == "git"; i += 1
        while g and i < len(toks) and toks[i].startswith("-"): i += 2 if toks[i] in VAL_OPTS else 1
    return out

def norm_all(cmd):   # 판정 불가(Inelig·파싱 실패) 경로: 원문 + «추가» 사본(원문은 그대로 PATTERN 에 간다)
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True); lex.whitespace_split = True; lex.commenters = ""
        return cmd + "\n" + " ".join(ungit(list(lex)))
    except ValueError:   # 토큰화 실패 — 보수 경로: git 뒤 옵션 구간을 글자로 접어 «파괴 하위명령 글자»가 있으면 PATTERN 이 잡게 한다
        return cmd + "\n" + re.sub(r"\bgit\s[^\n]*?\s(worktree\s+remove|branch\s+-[Dd]\b|push\b)", r"git \1", cmd)
