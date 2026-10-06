#!/bin/bash
# fable-team context-distill-gate — 450k 절대값 컨텍스트 하드 증류 게이트
# 하네스 0.4 단위 1 (GOAL-harness-v2 축 B「최대 450k 에서 증류」· 오빠 판정 2026-09-23 「훅 hard 모드 착수」· 임계 450k 고정 — 09-14 창 80% 대체).
# 소스 정본: ai-feature-pack/feature-pack/fable-team/skill/templates/hooks/context-distill-gate.sh (이 파일은 사본).
# 토큰 소스: transcript 의 «마지막 실 usage»(input+cache_read+cache_creation) — <synthetic>·전부 0 레코드는 건너뛴다(구멍 H3).
# 세 모드 (settings.json 인자):
#   warn  (UserPromptSubmit)        : ≥ WARN_AT 면 매 턴 증류 경고 주입(additionalContext).
#   block (PreToolUse Agent|Workflow|Task): ≥ BLOCK_AT 면 신규 스폰 차단(증류·마무리 스폰은 EXEMPT).
#   hard  (PreToolUse *)            : ≥ BLOCK_AT 면 «증류 allowlist 밖 모든 도구» exit 2. 좌석의 다음 도구 호출을 막는다(구멍 H1).
# 대상: 전 좌석 기본(구멍 H2) — 면제는 OMC_GATE_EXEMPT_MODELS(정규식) 로만. TOP_MODELS 완화는 폐지.
# 임계: OMC_DISTILL_WARN_AT/BLOCK_AT 는 «settings.json hook command 인자» 로만 준다 — 좌석 셸 env 는 읽지 않는다(구멍 H4).
# FAIL-OPEN 유지(데드락 회피) 하되 실패는 exit 1 + stderr + 로그로 «보인다»(구멍 H5). 로그: ~/.claude/logs/context-distill-gate.log
# r3: DA-harness-0.4-unit1-r1 REJECT R1~R3 수정 — hard_allowed() 를 명령/경로 «조각 단위» 판정으로 재작성(SB-harness-0.4-unit1-hook-r3).
# r4: 오케 실측(orch-check.md) MISMATCH 10/30 수정 — F1~F8·B1·B2(따옴표 # · zsh/bash -c 재판정 · git -C ·
#     heredoc 제외 · 리포루트 경로 · Monitor until/while · $(/백틱 차단).
# r5: 오케 FB_CFO#15 재실측(orch-check.md 「r4 오케 재실측」) MISMATCH 3/8 수정 — STATE_RE 가 «리포루트
#     상대» 뿐 아니라 «.worktrees/<이름>/ 접두 뒤」도 받는다(실 transcript: .fable-team/state/ Write 100건+
#     전부 워크트리 절대경로, 워크트리 28개가 각자 state 를 가짐). r4 의 "워크트리 state 는 가짜 위치" 해석은
#     실측으로 반박됨 — F5·F6·F7 나머지(정규화·.. 없음·리포루트 아래)는 그대로.
# r6: ★사고 재발방지★ — 셔뱅 /bin/bash 는 macOS 기본 bash 3.2.57(GPLv3 회피, PATH bash5.3.9 와 다르다).
#     r5 글로벌 적용 직후 전 좌석 전 도구가 차단됐다(오빠 손 복구 2회) — 원인은 이 줄의 리터럴 백틱 하나가
#     '<<PYEOF' 인용 heredoc 안인데도 3.2 파서가 백틱 짝을 못 찾고 EOF 까지 통째로 삼켜버린 것
#     (line 290: unexpected EOF while looking for matching backtick). 백틱·$( 을 \x60·\x24\x28 헥스 리터럴로
#     치환해 원천에서 제거 — 파일 전체 리터럴 백틱 0. run.py 도 /bin/bash 로 시험해야 이 결함이 잡힌다
#     (PATH bash5 로 시험하면 안 잡힘 — 이번 사고의 직접 원인).
# r7: DA-harness-0.4-unit1-r2 REJECT R5~R7 + C8~C11 수정(SB-harness-0.4-unit1-hook-r7).
#     R5 허용 스크립트는 «정확 경로»(리포루트/.worktrees/<이름>/ 의 .fable-team/{bin,comm}/ · realpath 재판정 ·
#        _SP 폐지) · state/comm/.baton Write 는 .md/.json/.jsonl/.txt 한정 + realpath 가 리포 밖·.claude/·bin/ 이면 차단.
#     R6 승계 경로 허용: design/**/inbox/**/*.md · NN-HANDOFF-*.md.
#     R7 push 강제 = 결합 플래그(-uf) · --force(-with-lease) · --delete · -d · 원격 삭제 refspec(:x) · +refspec.
#     C8 구분자 단독 & · 따옴표 밖 이스케이프는 리터럴 · <( >( > >> <<< 차단(예외 2>/dev/null·2>&1·>/dev/null) ·
#        heredoc 마커는 따옴표 밖에서만.  C9 리포루트 없음 = 경로 전부 차단(cwd 폴백 폐지).
#     C10·C11 deny·exempt 로그 행에 agent_id.  모드·임계·fail-open·warn 출력은 그대로.
# r8: DA-harness-0.4-unit1-r3 REJECT R1·R2 수정(SB-harness-0.4-unit1-hook-r7 §재발주 5).
#     R1 push 판정은 «shlex 로 따옴표를 벗긴 토큰 열»에 — 원문 정규식은 '+main' · -"f" · "-d" 를 놓쳤다. 토큰별
#        ^-[A-Za-z]*f[A-Za-z]*$ · ^--force(-with-lease|-if-includes)?(=.*)?$ · --delete · -d · --mirror · --prune · ^\+ ·
#        ^: 또는 :$ (원격 삭제 refspec · HEAD:main 은 0). shlex 실패(닫히지 않은 따옴표) = 차단.
#     R2 git add|commit|status|diff|log 토큰에 ^--output(=|$) · -o 가 있으면 차단(--output 은 allowlist 밖 파일을 만든다 —
#        DA 가 git 2.52 로 실증). 단 commit 의 -o(--only) 는 커밋 규약이라 허용 · --output 만 차단.
# r9: DA-harness-0.4-unit1-r4 REJECT R3·R4·R5 수정(SB-harness-0.4-unit1-hook-r7 §재발주 6) — push 를 denylist→allowlist.
#     R3 shlex 는 셸 확장을 안 한다($'+main' · ${X:-f} · {-f,} · 백슬래시개행) → push 조각 원문에 $ { \ 있으면 차단.
#     R4 git 은 옵션 약어를 받는다(--delet · --mirro) → '-' 시작 토큰은 정확일치 집합 12개만 통과.
#     R5 --receive-pack='sh -c …' · --exec=id 임의 실행 → 같은 집합으로 자동 차단. refspec 규칙(+ · ^: · :$) 유지.
#     C3 BLOCK 안내문에 «증류 커밋은 --only -F 파일 경유» 한 줄.
set +e
MODE="${1:-warn}"; shift
WARN_AT_ARG=""; BLOCK_AT_ARG=""
while [ $# -gt 0 ]; do case "$1" in
  --warn-at) WARN_AT_ARG="$2"; shift 2;; --block-at) BLOCK_AT_ARG="$2"; shift 2;; *) shift;; esac; done
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0
LOG="$HOME/.claude/logs/context-distill-gate.log"; mkdir -p "$(dirname "$LOG")" 2>/dev/null
EXEMPT_MODELS="${OMC_GATE_EXEMPT_MODELS:-}"     # 예: 'haiku' — 비워두면 면제 없음

RESULT=$(python3 - "$INPUT" "$WARN_AT_ARG" "$BLOCK_AT_ARG" "$EXEMPT_MODELS" "$MODE" <<'PYEOF' 2>>"$LOG"
import json, sys, os, re, shlex
TAIL_CAP = 16 * 1024 * 1024
TAIL_CHUNK = 262144
WARN_DEFAULT, BLOCK_DEFAULT = 400_000, 450_000     # 450k 절대값(오빠 2026-09-23) · 경고는 50k 앞

def norm_model(m):
    if isinstance(m, dict):
        m = m.get("id") or m.get("display_name") or ""
    if not isinstance(m, str):
        return ""
    return re.sub(r"-+", "-", re.sub(r"[ .]+", "-", m.lower()))

def scan_last_real_usage(path):
    """뒤에서부터 읽어 «실 usage»(합>0, model 이 <synthetic> 아님)를 돌려준다. 구멍 H3."""
    model, usage = None, None
    with open(path, "rb") as f:
        f.seek(0, 2); pos = f.tell(); buf = b""
        while pos > 0 and len(buf) < TAIL_CAP:
            step = min(TAIL_CHUNK, pos); pos -= step
            f.seek(pos); buf = f.read(step) + buf
            lines = buf.split(b"\n")
            usable = lines if pos == 0 else lines[1:]
            for line in reversed(usable):
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                msg = obj.get("message") or {}
                u = msg.get("usage")
                m = msg.get("model") or obj.get("model")
                if not u or (isinstance(m, str) and "synthetic" in m):
                    continue
                s = sum(int(u.get(k) or 0) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
                if s <= 0:
                    continue
                return m, u, s
    return model, usage, 0

try:
    data = json.loads(sys.argv[1])
    warn_at = int(sys.argv[2]) if sys.argv[2].strip() else WARN_DEFAULT
    block_at = int(sys.argv[3]) if sys.argv[3].strip() else BLOCK_DEFAULT
    exempt_re = sys.argv[4].strip()
    mode = sys.argv[5]
except Exception as e:
    print("ERROR|input parse: %s" % e); sys.exit(0)

tpath = data.get("transcript_path", "")
if not tpath or not os.path.isfile(tpath):
    print("ERROR|transcript missing: %r" % tpath); sys.exit(0)     # 구멍 H5 — 조용한 ALLOW 금지
try:
    model, usage, ctx = scan_last_real_usage(tpath)
except Exception as e:
    print("ERROR|scan failed: %s" % e); sys.exit(0)
model = norm_model(model)
if exempt_re and model and re.search(exempt_re, model):
    print("ALLOW|%d|exempt-model|%d|%d" % (ctx // 1000, warn_at // 1000, block_at // 1000)); sys.exit(0)
if ctx <= 0:
    # r10: 첫 프롬프트(assistant 응답 0건)는 잴 컨텍스트가 없다 — 정상 ALLOW. assistant 기록이 있는데 usage 만 없으면 여전히 ERROR(H5).
    def has_assistant(path):
        with open(path, "rb") as f:
            for line in f:
                if b'"type":"assistant"' in line:
                    return True
        return False
    try:
        fresh = not has_assistant(tpath)
    except Exception:
        fresh = False
    if fresh:
        print("ALLOW|0|fresh-session|%d|%d" % (warn_at // 1000, block_at // 1000)); sys.exit(0)
    print("ERROR|no real usage record in transcript"); sys.exit(0)
k = ctx // 1000

# ── hard 모드 allowlist: 증류·마무리에 필요한 도구만 ─────────────────────────────
tool = data.get("tool_name") or ""
ti = data.get("tool_input") or {}
cwd_raw = str(data.get("cwd") or "")
agent_id = re.sub(r"[^A-Za-z0-9._-]", "_", str(data.get("agent_id") or "")) or "-"   # C10·C11: 로그 집계용('|' 금지)

def find_repo_root(cwd):
    """git common-dir 의 부모(=…/BYZ-Agents/) 를 찾는다 — 어느 워크트리 cwd 에서 시작해도 같다.
    워크트리 루트는 .git 이 «파일»(gitdir 포인터) 이라 os.path.isdir 이 걸러준다."""
    if not cwd:
        return None
    p = os.path.normpath(cwd)
    seen = set()
    while p not in seen:
        seen.add(p)
        if os.path.isdir(os.path.join(p, ".git")):
            return p
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent
    return None

REPO_ROOT = find_repo_root(cwd_raw)
REPO_REAL = os.path.realpath(REPO_ROOT) if REPO_ROOT else None

# r5: 리포루트 상대 뿐 아니라 .worktrees/<이름>/ 접두 뒤도 받는다 — 접두 그룹이 .baton 까지 걸리게 묶는다
# (오케 FB_CFO#15 실측: .fable-team/state/ Write 100건+ 전부 워크트리 절대경로, .baton 은 양쪽에 실재).
STATE_RE = re.compile(r"^(?:\.worktrees/[^/]+/)?(?:\.fable-team/(?:state|comm)/|\.baton/)")
STATE_EXT = (".md", ".json", ".jsonl", ".txt")     # R5: state/comm/.baton 에 실행 가능한 것을 쓰지 못한다
CARD_SUFFIX_RE = re.compile(r"(^|/)design/[^/]+/(?:IMPL|HANDOFF|VERDICT|PROGRESS)-[^/]*\.md$")  # F5·F7: 어느 워크트리 접두든
HANDOFF_BARE_RE = re.compile(r"(^|/)HANDOFF-[^/]*\.md$")
INBOX_RE = re.compile(r"(^|/)design/(?:[^/]+/)*inbox/(?:[^/]+/)*[^/]+\.md$")   # R6: design/**/inbox/**/*.md
NUM_HANDOFF_RE = re.compile(r"(^|/)\d+-HANDOFF-[^/]*\.md$")                    # R6: NN-HANDOFF-*.md

def absolutize(fp):
    if os.path.isabs(fp):
        return os.path.normpath(fp)
    if not cwd_raw:
        return None
    return os.path.normpath(os.path.join(cwd_raw, fp))

def rel_to_root(p, base):
    """base 기준 상대경로('/' 구분). base 없음·base 밖이면 None (C9: cwd 폴백 폐지)."""
    if not base:
        return None
    try:
        rel = os.path.relpath(p, base)
    except Exception:
        return None
    if rel == os.pardir or rel.startswith(os.pardir + os.sep):
        return None
    return rel.replace(os.sep, "/")

def path_allowed(fp, writing):
    fp = str(fp or "")
    if not fp:
        return False
    if re.search(r"(^|/)\.\.(/|$)", fp):          # 조각에 .. 가 남아 있으면 그 자체로 차단
        return False
    resolved = absolutize(fp)
    if resolved is None:
        return False
    rel = rel_to_root(resolved, REPO_ROOT)          # C9: 리포루트 없음 / 리포 밖(예: /tmp/…) = 차단
    if rel is None:
        return False
    if STATE_RE.match(rel):
        if writing:                                 # R5: Write·Edit 만 — 실행 가능한 것을 state/comm/.baton 에 쓰지 못한다
            if not rel.lower().endswith(STATE_EXT):
                return False
            real_rel = rel_to_root(os.path.realpath(resolved), REPO_REAL)   # 심링크를 타고 리포 밖·.claude/·bin/ 이면 차단
            if real_rel is None or real_rel.startswith(".claude/") or re.search(r"(^|/)bin/", real_rel):
                return False
        return True
    for rx in (CARD_SUFFIX_RE, HANDOFF_BARE_RE, INBOX_RE, NUM_HANDOFF_RE):
        if rx.search(rel):
            return True
    return False

# R5: 허용 스크립트는 이름 + «정확 경로» — 리포루트 또는 .worktrees/<이름>/ 의 .fable-team/{bin,comm}/ 직속만.
# realpath 는 같은 자리 또는 .claude/fable-team/bin/(리포루트 .fable-team/comm/mbox.sh 가 그리로 가는 심링크 —
# 실측 2026-09-23 readlink · 전 좌석의 실 mbox 경로) 만 — 실행 허용 전용이며 Write 는 STATE 규칙이 .claude/ 를 막는다.
SCRIPT_ARGS = {
    "mbox.sh": re.compile(r"^(?:send|relay|recv|peek|ring)\b"),
    "ft-mbox.sh": None,
    "ft-tmux-distill.sh": None,
    "ft-tmux-spawn.sh": None,
    "ft-role-spawn.sh": None,
    "ft-nano-spawn.sh": None,
    "ft-version.sh": None,
}
SCRIPT_CALL_RE = re.compile(r"^(?:bash\s+)?(\S+)(?:\s+(.*))?$", re.DOTALL)
SCRIPT_DIR_RE = re.compile(r"^(?:\.worktrees/[^/]+/)?\.fable-team/(?:bin|comm)/[^/]+$")
SCRIPT_REAL_RE = re.compile(r"^(?:(?:\.worktrees/[^/]+/)?\.fable-team/(?:bin|comm)|\.claude/fable-team/bin)/[^/]+$")

def script_call_allowed(frag):
    m = SCRIPT_CALL_RE.match(frag)
    if not m:
        return False
    path, args = m.group(1), (m.group(2) or "").strip()
    name = os.path.basename(path)
    if name not in SCRIPT_ARGS:
        return False
    arg_re = SCRIPT_ARGS[name]
    if arg_re and not arg_re.match(args):
        return False
    if re.search(r"(^|/)\.\.(/|$)", path):
        return False
    resolved = absolutize(path)
    if resolved is None:
        return False
    rel = rel_to_root(resolved, REPO_ROOT)
    if rel is None or not SCRIPT_DIR_RE.match(rel):
        return False
    real_rel = rel_to_root(os.path.realpath(resolved), REPO_REAL)
    if real_rel is None or not SCRIPT_REAL_RE.match(real_rel):
        return False
    return True

_GITC = r"(?:-C\s+\S+\s+)?"                        # F3: git -C <path> <sub>
_CMD_ALT = (
    r"cd\s+\S+"
    r"|(?:baton|\S*/\.baton/\S*/baton)\s+(?:save|finish)\b"
    r"|git\s+" + _GITC + r"add\b"
    r"|git\s+" + _GITC + r"commit\b"
    r"|git\s+" + _GITC + r"status\b"
    r"|git\s+" + _GITC + r"diff\b"
    r"|git\s+" + _GITC + r"log\b"
    r"|git\s+" + _GITC + r"push\b"
    r"|tmuxc\s+(?:open|save|list|distill)\b"
    r"|tmux\s+(?:capture-pane|list-\S*)\b"
    r"|sleep\b"                                    # F8
)
CMD_RE = re.compile(r"^\s*(?:" + _CMD_ALT + r")")
GIT_SUB_RE = re.compile(r"^git\s+" + _GITC + r"(add|commit|status|diff|log|push)\b")
# r9 R3~R5: push 는 ★allowlist★ — denylist 는 셸 확장($'+main'·${X:-f}·{-f,})·옵션 약어(--delet)·--receive-pack/--exec 에 끝이 없다(DA r4).
#   ①push 조각 «원문»에 $ · { · \ 가 있으면 shlex 전에 차단  ②'-' 시작 토큰은 아래 집합 정확일치만  ③refspec + 시작 · ^: · :$ 차단(HEAD:main 0).
PUSH_SHELL_RE = re.compile(r"[$\\{]")
PUSH_OPT_OK = frozenset(("-u", "--set-upstream", "-q", "--quiet", "-v", "--verbose", "--dry-run", "-n",
                         "--follow-tags", "--tags", "--all", "--porcelain"))
PUSH_REF_BAD_RE = re.compile(r"^(?:\+.*|:.*|.*:)$")
# r8 R2: git diff|log 의 --output(=|<sep>) · -o 는 allowlist 밖 파일을 만든다. commit 의 -o(--only) 는 규약이라 허용.
OUTPUT_TOK_RE = re.compile(r"^--output(?:=.*)?$")

def git_tokens_allowed(frag):
    """r8·r9: git 허용 부명령의 «따옴표를 벗긴 토큰 열» 검사. shlex 실패(닫히지 않은 따옴표) = 차단."""
    m = GIT_SUB_RE.match(frag)
    if not m:
        return True
    sub = m.group(1)
    if sub == "push" and PUSH_SHELL_RE.search(frag):        # r9 ①: 확장 문자는 토큰화 전에
        return False
    try:
        toks = shlex.split(frag, posix=True)
    except ValueError:
        return False
    for t in toks:
        if OUTPUT_TOK_RE.match(t):
            return False
        if t == "-o" and sub != "commit":
            return False
    if sub == "push":
        for t in toks[toks.index("push") + 1:] if "push" in toks else toks:
            if t.startswith("-"):
                if t not in PUSH_OPT_OK:                     # r9 ②: 목록 밖 옵션은 «전부» 차단(약어·--force*·--receive-pack·--exec 포함)
                    return False
            elif PUSH_REF_BAD_RE.match(t):                   # r9 ③
                return False
    return True
READONLY_RE = re.compile(r"^\s*(cat\b|tail\s+-\d+|head\s+-\d+|grep\b|wc\b)")
WRAP_RE = re.compile(r"^\s*(?:zsh|bash)\s+-l?c\s+(['\"])(.*)\1\s*$", re.DOTALL)   # F2
LOOP_RE = re.compile(r"^\s*(?:until|while)\s+(.+?)\s*(?:;|\n)\s*do\s+(.+?)\s*(?:;|\n)\s*done\s*;?\s*$", re.DOTALL)  # F8
HEREDOC_OP_RE = re.compile(r"(?<![<])<<(?![<])-?\s*(['\"]?)(\w+)\1")   # F4 · C8: <<< 는 heredoc 이 아니다
REDIR_OK_RE = re.compile(r"(?:2>&1|2>/dev/null|>/dev/null)(?=\s|$)")   # C8: 허용 리다이렉트는 이 셋뿐

def find_heredoc(cmd):
    """따옴표 밖의 첫 heredoc 연산자 match. C8: 따옴표 안 "<<X" 는 마커가 아니다."""
    in_sq = in_dq = False
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if in_sq:
            if c == "'":
                in_sq = False
            i += 1; continue
        if in_dq:
            if c == "\\":
                i += 2; continue
            if c == '"':
                in_dq = False
            i += 1; continue
        if c == "\\":
            i += 2; continue
        if c == "'":
            in_sq = True; i += 1; continue
        if c == '"':
            in_dq = True; i += 1; continue
        if c == "<":
            m = HEREDOC_OP_RE.match(cmd, i)
            if m:
                return m
        i += 1
    return None

def strip_heredocs(cmd):
    m = find_heredoc(cmd)
    if not m:
        return cmd
    marker = m.group(2)
    line_end = cmd.find("\n", m.end())
    if line_end == -1:
        return cmd                                  # 본문 없는 << 는 남겨 리다이렉트 검사가 차단한다
    head = cmd[:m.start()] + " " + cmd[m.end():line_end + 1]   # 연산자도 제거(본문을 뗀 heredoc 만)
    rest = cmd[line_end + 1:]
    lines = rest.split("\n")
    found_idx = None
    for idx, ln in enumerate(lines):
        if ln.strip() == marker:
            found_idx = idx
            break
    if found_idx is None:
        return head.rstrip("\n")
    remainder = "\n".join(lines[found_idx + 1:])
    result = head + remainder
    if find_heredoc(remainder):
        return strip_heredocs(result)
    return result

def split_top_level(s):
    """따옴표 밖의 ||/&&/;/|/&/개행 에서만 나눈다(F1·F2 의 전제).
    C8: 따옴표 밖 \\ 는 다음 문자를 리터럴로(따옴표 개폐로 안 읽음) · 단독 & 는 리다이렉트(2>&1·&>) 가 아닐 때만 구분자."""
    delims = ("||", "&&", ";", "|", "\n")
    out = []
    buf = []
    i, n = 0, len(s)
    in_sq = in_dq = False
    while i < n:
        c = s[i]
        if in_sq:
            buf.append(c)
            if c == "'":
                in_sq = False
            i += 1; continue
        if in_dq:
            if c == "\\" and i + 1 < n:
                buf.append(c); buf.append(s[i + 1]); i += 2; continue
            buf.append(c)
            if c == '"':
                in_dq = False
            i += 1; continue
        if c == "\\" and i + 1 < n:
            buf.append(c); buf.append(s[i + 1]); i += 2; continue
        if c == "'":
            in_sq = True; buf.append(c); i += 1; continue
        if c == '"':
            in_dq = True; buf.append(c); i += 1; continue
        hit = None
        for d in delims:
            if s.startswith(d, i):
                hit = d; break
        if hit is None and c == "&":
            prev = s[i - 1] if i > 0 else ""
            nxt = s[i + 1] if i + 1 < n else ""
            if prev not in ("<", ">") and nxt != ">":
                hit = "&"
        if hit:
            out.append("".join(buf)); buf = []
            out.append(hit)
            i += len(hit); continue
        buf.append(c); i += 1
    out.append("".join(buf))
    return out

def find_unquoted_hash(s):
    """따옴표 밖 + 직전이 공백/시작인 # 위치. 없으면 -1 (F1). C8: 따옴표 밖 \\ 는 다음 문자를 리터럴로."""
    in_sq = in_dq = False
    prev_ws = True
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_sq:
            if c == "'":
                in_sq = False
            i += 1; prev_ws = False; continue
        if in_dq:
            if c == "\\" and i + 1 < n:
                i += 2; prev_ws = False; continue
            if c == '"':
                in_dq = False
            i += 1; prev_ws = False; continue
        if c == "\\" and i + 1 < n:
            i += 2; prev_ws = False; continue
        if c == "'":
            in_sq = True; i += 1; prev_ws = False; continue
        if c == '"':
            in_dq = True; i += 1; prev_ws = False; continue
        if c == "#" and prev_ws:
            return i
        prev_ws = c in (" ", "\t")
        i += 1
    return -1

def has_bad_redirect(s):
    """C8: 따옴표 밖 <( >( > >> <<< (그리고 본문 없이 남은 <<) 는 차단. 예외 2>/dev/null · 2>&1 · >/dev/null. 단순 < 는 목록 밖."""
    in_sq = in_dq = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_sq:
            if c == "'":
                in_sq = False
            i += 1; continue
        if in_dq:
            if c == "\\":
                i += 2; continue
            if c == '"':
                in_dq = False
            i += 1; continue
        if c == "\\":
            i += 2; continue
        if c == "'":
            in_sq = True; i += 1; continue
        if c == '"':
            in_dq = True; i += 1; continue
        if c == "<":
            if s.startswith("<<", i) or s.startswith("<(", i):
                return True
            i += 1; continue
        if c == ">":
            start = i
            while start > 0 and s[start - 1].isdigit():
                start -= 1
            m = REDIR_OK_RE.match(s, start)
            if not m:
                return True
            i = m.end(); continue
        i += 1
    return False

def bash_fragments_allowed(cmd):
    cmd = str(cmd or "")
    if not cmd.strip():
        return True
    lm = LOOP_RE.match(cmd.strip())                # F8: until/while … do … done 껍데기 벗기기
    if lm:
        cmd = lm.group(1) + "\n" + lm.group(2)
    cmd = strip_heredocs(cmd)                       # F4: heredoc 본문 제외
    pieces = split_top_level(cmd)
    prev_delim = None
    for piece in pieces:
        if piece in ("||", "&&", ";", "|", "&", "\n"):
            prev_delim = piece
            continue
        idx = find_unquoted_hash(piece)              # F1: 따옴표 밖 # 만 주석
        if idx >= 0:
            frag, has_comment = piece[:idx], True
        else:
            frag, has_comment = piece, False
        frag_stripped = frag.strip()
        if frag_stripped:
            if "\x24\x28" in frag_stripped or "\x60" in frag_stripped:   # B1.B2 (r6: hex literal - bash3.2 heredoc backtick bug)
                return False
            if has_bad_redirect(frag_stripped):      # C8
                return False
            wm = WRAP_RE.match(frag_stripped)        # F2: zsh -lc/bash -c 안쪽 재판정
            if wm:
                if not bash_fragments_allowed(wm.group(2)):
                    return False
            elif prev_delim == "|" and READONLY_RE.search(frag_stripped):
                pass
            elif CMD_RE.match(frag_stripped):
                if not git_tokens_allowed(frag_stripped):   # r8 R1·R2
                    return False
            elif script_call_allowed(frag_stripped):   # R5: 정확 경로 스크립트
                pass
            else:
                return False
        if has_comment:                              # 주석 조각 = 차단(R1)
            return False
        prev_delim = None
    return True

def hard_allowed():
    if tool == "Read":   # 2026-10-05 master-claude#136: 읽기 전용 — 갇힌 좌석이 훅·스냅샷을 읽고 스스로 빠져나오게
        return True
    if tool in ("Write", "Edit"):
        return path_allowed(ti.get("file_path"), True)
    if tool in ("Bash", "Monitor"):
        return bash_fragments_allowed(ti.get("command"))
    if tool == "Skill":  # /baton:save·finish 는 Skill 경로로 온다 (2026-09-23 CFO_HARNESS_F5#0 피차단 발견)
        return bool(re.search(r"^baton:(save|finish)$", str(ti.get("skill") or "")))
    if tool in ("SendMessage", "TaskStop", "ListAgents", "ToolSearch", "ScheduleWakeup", "AskUserQuestion"):   # AskUserQuestion: 사람에게 «!» 명령을 물을 길(10-05)
        return True
    return False

BLOCK_EXEMPT = r"baton|distill|증류|checkpoint|save|DA[ _-]?final|finalize|종결|handoff|승계|snapshot"
def spawn_text(d):
    parts = []
    for key in ("prompt", "description", "command", "subagent_type", "message", "task"):
        v = ti.get(key)
        if isinstance(v, str):
            parts.append(v)
    return " ".join(parts)

if ctx >= block_at:
    if mode == "hard":
        if hard_allowed():
            print("EXEMPT|%d|hard-allowlist:%s|%d|%d|%s" % (k, tool, warn_at // 1000, block_at // 1000, agent_id))
        else:
            print("BLOCK|%d|%s|%d|%d|%s" % (k, tool, warn_at // 1000, block_at // 1000, agent_id))
    else:
        txt = spawn_text(data)
        if txt and re.search(BLOCK_EXEMPT, txt, re.I):
            print("EXEMPT|%d|spawn-exempt|%d|%d|%s" % (k, warn_at // 1000, block_at // 1000, agent_id))
        else:
            print("BLOCK|%d|%s|%d|%d|%s" % (k, tool, warn_at // 1000, block_at // 1000, agent_id))
elif ctx >= warn_at:
    print("WARN|%d|%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
else:
    print("ALLOW|%d|%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
PYEOF
)
PYRC=$?
IFS='|' read -r STATE K WHAT WARN_K BLOCK_K AGENT <<<"$RESULT"

# ── 판정기 실패 = 보이는 fail-open (exit 1 + 로그) ──────────────────────────────
if [ "$PYRC" != 0 ] || [ -z "$STATE" ] || [ "$STATE" = "ERROR" ]; then
  printf '%s error mode=%s %s\n' "$(date +%FT%T)" "$MODE" "${RESULT:-python rc=$PYRC}" >> "$LOG" 2>/dev/null
  printf '⚠️ [context-distill-gate] 판정 실패(ALLOW, fail-open): %s\n' "${RESULT:-python rc=$PYRC}" >&2
  exit 1
fi

case "$MODE" in
  hard|block)
    if [ "$STATE" = "BLOCK" ]; then
      printf '%s deny mode=%s ctx=%sk block_at=%sk tool=%s agent_id=%s\n' "$(date +%FT%T)" "$MODE" "$K" "$BLOCK_K" "$WHAT" "${AGENT:--}" >> "$LOG" 2>/dev/null
      printf '🛑 [context-distill-gate] 컨텍스트 %sk 토큰 — 증류 강제선(%sk 절대값) 돌파. 도구 «%s» 차단.\n' "$K" "$BLOCK_K" "$WHAT" >&2
      printf '허용되는 것만: 스냅샷(HANDOFF-*.md · design/**/inbox/**/*.md · .fable-team/state/**) 쓰기 · baton save · mbox send/relay · git add/commit/push · Read · AskUserQuestion · tmuxc save · ★후계 개설 = zsh -lc "tmuxc open <wt> --name <좌석> --agent claude --model <ID> --ctx 1m --effort high" 또는 .fable-team/bin/ft-role-spawn.sh★.\n' >&2
      printf '★한 줄에 허용 명령만★ — 변수 대입(f=…)·echo·ls·$()·리다이렉트(>/dev/null)를 섞으면 줄 전체가 차단된다. 명령마다 따로 호출.\n' >&2
      printf '증류 커밋은 git commit --only -F <파일> -- <경로> 로 — -m 안의 명령치환·백틱·따옴표 밖 확장은 차단된다. push 옵션은 -u/-q/-v/-n/--dry-run/--follow-tags/--tags/--all/--porcelain 만.\n' >&2
      printf '지금: ①워커 전원 수거 ②write-through·HANDOFF 최신화 ③baton save ④후계 스폰(zsh -lc "tmuxc open …" 단독 한 줄) ⑤정지 레디. 사람 입력(UserPromptSubmit)은 막지 않는다.\n' >&2
      exit 2
    fi
    if [ "$STATE" = "EXEMPT" ]; then     # C7·C10·C11: 돌파 후 허용 호출도 남긴다(집계 분모)
      printf '%s exempt mode=%s ctx=%sk block_at=%sk what=%s agent_id=%s\n' "$(date +%FT%T)" "$MODE" "$K" "$BLOCK_K" "$WHAT" "${AGENT:--}" >> "$LOG" 2>/dev/null
    fi
    exit 0 ;;
  warn)
    if [ "$STATE" = "WARN" ] || [ "$STATE" = "BLOCK" ] || [ "$STATE" = "EXEMPT" ]; then
      python3 - "$K" "$WARN_K" "$BLOCK_K" "$STATE" <<'PYEOF2' 2>/dev/null
import json, sys
k, warn_k, block_k, st = sys.argv[1:5]
if st == "WARN":
    msg = "⚠️ [context-distill-gate] 컨텍스트 %sk 토큰 — 경고선(%sk) 초과. ★새 일 수락 중지 · 지금 증류★: 스냅샷 → baton save → zsh -lc \"tmuxc open …\" 후계(한 줄 단독). %sk(절대값)에서 «증류 allowlist 밖 모든 도구»가 물리 차단된다." % (k, warn_k, block_k)
else:
    msg = "🛑 [context-distill-gate] 컨텍스트 %sk 토큰 — 강제선(%sk) 돌파 상태. 증류 도구만 허용된다. 지금 스냅샷·baton save·후계 스폰." % (k, block_k)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": msg}}))
PYEOF2
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
