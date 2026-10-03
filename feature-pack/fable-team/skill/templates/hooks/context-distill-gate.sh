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
import json, sys, os, re
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
    print("ERROR|no real usage record in transcript"); sys.exit(0)
k = ctx // 1000

# ── hard 모드 allowlist: 증류·마무리에 필요한 도구만 ─────────────────────────────
tool = data.get("tool_name") or ""
ti = data.get("tool_input") or {}
cwd_raw = str(data.get("cwd") or "")

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

# r5: 리포루트 상대 뿐 아니라 .worktrees/<이름>/ 접두 뒤도 받는다 — 접두 그룹이 .baton 까지 걸리게 묶는다
# (오케 FB_CFO#15 실측: .fable-team/state/ Write 100건+ 전부 워크트리 절대경로, .baton 은 양쪽에 실재).
STATE_RE = re.compile(r"^(?:\.worktrees/[^/]+/)?(?:\.fable-team/(?:state|comm)/|\.baton/)")
CARD_SUFFIX_RE = re.compile(r"(^|/)design/[^/]+/(?:IMPL|HANDOFF|VERDICT|PROGRESS)-[^/]*\.md$")  # F5·F7: 어느 워크트리 접두든
HANDOFF_BARE_RE = re.compile(r"(^|/)HANDOFF-[^/]*\.md$")

def path_allowed(fp):
    fp = str(fp or "")
    if not fp:
        return False
    if re.search(r"(^|/)\.\.(/|$)", fp):          # 조각에 .. 가 남아 있으면 그 자체로 차단
        return False
    if os.path.isabs(fp):
        resolved = os.path.normpath(fp)
    else:
        resolved = os.path.normpath(os.path.join(cwd_raw, fp)) if cwd_raw else os.path.normpath(fp)
    root = REPO_ROOT or (os.path.normpath(cwd_raw) if cwd_raw else None)
    if root:
        try:
            rel = os.path.relpath(resolved, root)
        except Exception:
            return False
        if rel == os.pardir or rel.startswith(os.pardir + os.sep):   # 리포 루트 밖(예: /tmp/…) = 차단
            return False
    else:
        rel = resolved
    rel = rel.replace(os.sep, "/")
    if STATE_RE.match(rel):
        return True
    if CARD_SUFFIX_RE.search(rel):
        return True
    if HANDOFF_BARE_RE.search(rel):
        return True
    return False

_SP = r"(?:bash\s+)?\S*/?"
_GITC = r"(?:-C\s+\S+\s+)?"                        # F3: git -C <path> <sub>
_CMD_ALT = (
    r"cd\s+\S+"
    r"|" + _SP + r"mbox\.sh\s+(?:send|relay|recv|peek|ring)\b"
    r"|" + _SP + r"ft-mbox\.sh\b"
    r"|" + _SP + r"baton\s+(?:save|finish)\b"
    r"|git\s+" + _GITC + r"add\b"
    r"|git\s+" + _GITC + r"commit\b"
    r"|git\s+" + _GITC + r"status\b"
    r"|git\s+" + _GITC + r"diff\b"
    r"|git\s+" + _GITC + r"log\b"
    r"|git\s+" + _GITC + r"push\b"
    r"|" + _SP + r"ft-tmux-distill\.sh\b"
    r"|" + _SP + r"ft-(?:tmux|role|nano)-spawn\.sh\b"
    r"|tmuxc\s+(?:open|save|list|distill)\b"
    r"|tmux\s+(?:capture-pane|list-\S*)\b"
    r"|" + _SP + r"ft-version\.sh\b"
    r"|sleep\b"                                    # F8
)
CMD_RE = re.compile(r"^\s*(?:" + _CMD_ALT + r")")
PUSH_RE = re.compile(r"^git\s+" + _GITC + r"push\b")
PUSH_FORCE_RE = re.compile(r"(--force\b|(?:^|\s)-f\b|\s\+\S)")
READONLY_RE = re.compile(r"^\s*(cat\b|tail\s+-\d+|head\s+-\d+|grep\b|wc\b)")
WRAP_RE = re.compile(r"^\s*(?:zsh|bash)\s+-l?c\s+(['\"])(.*)\1\s*$", re.DOTALL)   # F2
LOOP_RE = re.compile(r"^\s*(?:until|while)\s+(.+?)\s*(?:;|\n)\s*do\s+(.+?)\s*(?:;|\n)\s*done\s*;?\s*$", re.DOTALL)  # F8
HEREDOC_RE = re.compile(r"<<-?\s*(['\"]?)(\w+)\1")   # F4

def strip_heredocs(cmd):
    m = HEREDOC_RE.search(cmd)
    if not m:
        return cmd
    marker = m.group(2)
    line_end = cmd.find("\n", m.end())
    if line_end == -1:
        return cmd
    head = cmd[:line_end + 1]
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
    if HEREDOC_RE.search(remainder):
        return strip_heredocs(result)
    return result

def split_top_level(s):
    """따옴표 밖의 &&/||/;/|/개행 에서만 나눈다(F1·F2 의 전제)."""
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
        if c == "'":
            in_sq = True; buf.append(c); i += 1; continue
        if c == '"':
            in_dq = True; buf.append(c); i += 1; continue
        hit = None
        for d in delims:
            if s.startswith(d, i):
                hit = d; break
        if hit:
            out.append("".join(buf)); buf = []
            out.append(hit)
            i += len(hit); continue
        buf.append(c); i += 1
    out.append("".join(buf))
    return out

def find_unquoted_hash(s):
    """따옴표 밖 + 직전이 공백/시작인 # 위치. 없으면 -1 (F1)."""
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
        if c == "'":
            in_sq = True; i += 1; prev_ws = False; continue
        if c == '"':
            in_dq = True; i += 1; prev_ws = False; continue
        if c == "#" and prev_ws:
            return i
        prev_ws = c in (" ", "\t")
        i += 1
    return -1

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
        if piece in ("||", "&&", ";", "|", "\n"):
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
            wm = WRAP_RE.match(frag_stripped)        # F2: zsh -lc/bash -c 안쪽 재판정
            if wm:
                if not bash_fragments_allowed(wm.group(2)):
                    return False
            elif prev_delim == "|" and READONLY_RE.search(frag_stripped):
                pass
            elif CMD_RE.match(frag_stripped):
                if PUSH_RE.match(frag_stripped) and PUSH_FORCE_RE.search(frag_stripped):
                    return False
            else:
                return False
        if has_comment:                              # 주석 조각 = 차단(R1)
            return False
        prev_delim = None
    return True

def hard_allowed():
    if tool in ("Read", "Write", "Edit"):
        return path_allowed(ti.get("file_path"))
    if tool in ("Bash", "Monitor"):
        return bash_fragments_allowed(ti.get("command"))
    if tool == "Skill":  # /baton:save·finish 는 Skill 경로로 온다 (2026-09-23 CFO_HARNESS_F5#0 피차단 발견)
        return bool(re.search(r"^baton:(save|finish)$", str(ti.get("skill") or "")))
    if tool in ("SendMessage", "TaskStop", "ListAgents", "ToolSearch", "ScheduleWakeup"):
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
            print("EXEMPT|%d|hard-allowlist:%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
        else:
            print("BLOCK|%d|%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
    else:
        txt = spawn_text(data)
        if txt and re.search(BLOCK_EXEMPT, txt, re.I):
            print("EXEMPT|%d|spawn-exempt|%d|%d" % (k, warn_at // 1000, block_at // 1000))
        else:
            print("BLOCK|%d|%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
elif ctx >= warn_at:
    print("WARN|%d|%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
else:
    print("ALLOW|%d|%s|%d|%d" % (k, tool, warn_at // 1000, block_at // 1000))
PYEOF
)
PYRC=$?
IFS='|' read -r STATE K WHAT WARN_K BLOCK_K <<<"$RESULT"

# ── 판정기 실패 = 보이는 fail-open (exit 1 + 로그) ──────────────────────────────
if [ "$PYRC" != 0 ] || [ -z "$STATE" ] || [ "$STATE" = "ERROR" ]; then
  printf '%s error mode=%s %s\n' "$(date +%FT%T)" "$MODE" "${RESULT:-python rc=$PYRC}" >> "$LOG" 2>/dev/null
  printf '⚠️ [context-distill-gate] 판정 실패(ALLOW, fail-open): %s\n' "${RESULT:-python rc=$PYRC}" >&2
  exit 1
fi

case "$MODE" in
  hard|block)
    if [ "$STATE" = "BLOCK" ]; then
      printf '%s deny mode=%s ctx=%sk block_at=%sk tool=%s\n' "$(date +%FT%T)" "$MODE" "$K" "$BLOCK_K" "$WHAT" >> "$LOG" 2>/dev/null
      printf '🛑 [context-distill-gate] 컨텍스트 %sk 토큰 — 증류 강제선(%sk 절대값) 돌파. 도구 «%s» 차단.\n' "$K" "$BLOCK_K" "$WHAT" >&2
      printf '허용되는 것만: 스냅샷(HANDOFF-*.md · .fable-team/state/**) 쓰기 · baton save · mbox send/relay · git add/commit/push · ft-tmux-distill.sh · tmuxc save.\n' >&2
      printf '지금: ①워커 전원 수거 ②write-through·HANDOFF 최신화 ③baton save ④후계 스폰(ft-tmux-distill.sh) ⑤정지 레디. 사람 입력(UserPromptSubmit)은 막지 않는다.\n' >&2
      exit 2
    fi
    exit 0 ;;
  warn)
    if [ "$STATE" = "WARN" ] || [ "$STATE" = "BLOCK" ] || [ "$STATE" = "EXEMPT" ]; then
      python3 - "$K" "$WARN_K" "$BLOCK_K" "$STATE" <<'PYEOF2' 2>/dev/null
import json, sys
k, warn_k, block_k, st = sys.argv[1:5]
if st == "WARN":
    msg = "⚠️ [context-distill-gate] 컨텍스트 %sk 토큰 — 경고선(%sk) 초과. 다음 단계 경계에서 증류: write-through → baton save → 후계 스폰. %sk(절대값)에서 «증류 allowlist 밖 모든 도구»가 물리 차단된다." % (k, warn_k, block_k)
else:
    msg = "🛑 [context-distill-gate] 컨텍스트 %sk 토큰 — 강제선(%sk) 돌파 상태. 증류 도구만 허용된다. 지금 스냅샷·baton save·후계 스폰." % (k, block_k)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": msg}}))
PYEOF2
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
