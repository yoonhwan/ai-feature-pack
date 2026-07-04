#!/bin/bash
# fable-team orchestration-gate — PreToolUse 강제 게이트 (선언 아닌 물리 차단)
# 목적: 최상위 모델 오케스트레이터(fable5·opus-4-8 등)가 한 턴에 코드 파일을 3개 이상
#       직접 수정하거나 Bash로 코드파일을 우회 편집하는 것을 물리적으로 차단 → 위임 강제.
# 대상 도구: Edit | Write | NotebookEdit | Bash  (settings.json matcher로 지정)
# 판정: exit 0 = 허용 / exit 2 = deny(stderr 메시지가 모델에 피드백)
#
# ★ 안전 제1원칙 — FAIL-OPEN: 어떤 파싱 오류·환경 이상에서도 exit 0(허용).
#   훅이 세션을 brick하지 않는다(글로벌 프록시 死=전 세션 마비 교훈).
# ★ 서브에이전트 면제(제1 판별): 위임된 워커(Agent/Task/Workflow)의 tool-call은
#   훅 입력 JSON에 agent_id/agent_type 필드가 실린다. 오케스트레이터 본인 호출엔 없다.
#   서브에이전트는 메인 세션의 transcript_path·session_id를 "공유"하므로(둘 다 opus-4-8로 보임)
#   모델/세션 판별로는 워커와 오케를 구분할 수 없다 → agent_id 유무가 유일하게 신뢰 가능한 신호.
#   agent_id 있으면 워커 → 게이트 면제(워커는 무제한, 구현 워커가 여러 파일 편집 정상).
# ★ 모델 게이팅(제2 판별, 폴백): agent_id 없는(=오케) 호출만 transcript 마지막 assistant model
#   이 TOP 집합일 때 게이트. 워커 모델(opus-4-6/sonnet-5/sonnet-4-6)은 TOP 아니므로 자유.
#   → 오케스트레이터만 제한.

set +e  # 어떤 명령 실패도 스크립트를 죽이지 않음 (fail-open)

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# ── 설정 (프로젝트 rules/orchestration.md와 정합. env로 오버라이드 가능) ──
MAX_CODE_FILES="${OMC_GATE_MAX_CODE_FILES:-2}"   # 한 턴 코드파일 직접수정 허용 상한
# TOP 오케스트레이터 모델 토큰 (정규화된 문자열에 부분일치, 소문자·하이픈형). 목록 밖 = 워커 = 면제.
# opus-?4-?8 → "opus 4.8"·"opus-4-8"·"opus4-8"·"claude-opus-4-8[1m]"·"Claude Opus 4.8" 모두 매치.
TOP_MODELS="${OMC_GATE_TOP_MODELS:-fable|opus-?4-?8}"

python3 - "$INPUT" "$MAX_CODE_FILES" "$TOP_MODELS" <<'PYEOF'
import json, sys, os, re, hashlib, shlex

def allow():   # fail-open / 통과
    sys.exit(0)

def deny(msg): # PreToolUse 차단 (stderr → 위임 안내가 모델에 피드백)
    sys.stderr.write(msg + "\n")
    sys.exit(2)

TAIL_CAP = 16 * 1024 * 1024   # 마지막 레코드가 멀티MB여도 통째로 읽되 폭주 방지 상한
TAIL_CHUNK = 262144

def norm_model(m):
    # dict(id/display_name)·display string 모두 흡수 → 소문자·(공백/점→하이픈)·연속하이픈 축약
    if isinstance(m, dict):
        m = m.get("id") or m.get("display_name") or ""
    if not isinstance(m, str):
        return ""
    return re.sub(r"-+", "-", re.sub(r"[ .]+", "-", m.lower()))

def last_model(path):
    # 파일 끝에서 완전 JSONL 레코드 단위 reverse 리더 — 거대 라인도 통째로 회수(tail cap 우회 방지).
    try:
        with open(path, "rb") as f:
            f.seek(0, 2); pos = f.tell(); buf = b""
            while pos > 0 and len(buf) < TAIL_CAP:
                step = min(TAIL_CHUNK, pos); pos -= step
                f.seek(pos); buf = f.read(step) + buf
                lines = buf.split(b"\n")
                usable = lines if pos == 0 else lines[1:]  # pos>0이면 앞쪽 부분 라인 제외
                for line in reversed(usable):
                    if not line.strip():
                        continue
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    m = (obj.get("message") or {}).get("model") or obj.get("model")
                    if m:
                        return m
    except Exception:
        return ""
    return ""

try:
    raw = sys.argv[1]; max_code = int(sys.argv[2]); top_re = sys.argv[3]
    data = json.loads(raw)
except Exception:
    allow()

tool = data.get("tool_name", "")
tin  = data.get("tool_input", {}) or {}
sid  = data.get("session_id", "nosess")
tpath = data.get("transcript_path", "")

# ── 0) 서브에이전트(위임된 워커) 면제 — 제1 판별 ──
# 서브에이전트(Agent/Task/Workflow) tool-call은 메인 세션의 transcript_path·session_id를 그대로
# 공유한다(실측: 서브의 Edit도 session_id=메인, transcript_path=메인). 따라서 모델/세션 판별로는
# 워커와 오케를 구분할 수 없다(둘 다 opus-4-8로 판별됨 — 이게 워커 오차단 근본원인).
# Claude Code는 서브에이전트 호출에만 훅 입력 JSON에 agent_id/agent_type를 싣는다(오케 본인 호출엔 없음).
# → agent_id/agent_type 존재 = 위임된 워커 → 게이트 면제(워커는 무제한). 카운터 오염도 방지.
if data.get("agent_id") or data.get("agent_type"):
    allow()

# ── 1) 세션 모델 판별 (transcript 마지막 assistant message.model) ──
# 오케스트레이터(TOP) 세션만 게이트. 워커/불명 → 면제(fail-open).
model = ""
if tpath and os.path.isfile(tpath):
    model = last_model(tpath)
if not model:                 # 폴백: stdin의 model (문자열/{id,display_name} 객체)
    model = data.get("model")
model = norm_model(model)     # dict·display·[1m] 모두 정규화 → top_re(하이픈형) 매칭

# 모델 판별 실패 → 면제(fail-open). TOP 아님 → 워커 → 면제.
if not model:
    allow()
if not re.search(top_re, model):
    allow()

# ── 여기 도달 = 오케스트레이터(TOP) 세션. 게이트 발동. ──

CODE_EXT = {
    "ts","tsx","js","jsx","mjs","cjs","py","go","rs","java","rb","php","c","cc",
    "cpp","cxx","h","hpp","hh","swift","kt","kts","scala","sh","bash","zsh","lua",
    "pl","pm","r","sql","vue","svelte","cs","m","mm","dart","ex","exs","clj","erl",
}
# 확장자 없는 코드 파일(basename allowlist) — 확장자 위장/누락 회피
CODE_BASENAMES = {"dockerfile", "makefile", "rakefile", "gemfile"}
# 코드로 세지 않음: 문서·설정·데이터·상태·의존물
EXCLUDE_PATH = re.compile(
    r"(^|/)\.(fable-team|omc|claude|baton|cairn|git|worktrees|venv)/|"
    r"(^|/)(node_modules|dist|build|__pycache__)/", re.I)

def is_code_file(path):
    if not path: return False
    if EXCLUDE_PATH.search(path): return False
    base = os.path.basename(path.strip().strip('"\'')).lower()
    if base in CODE_BASENAMES: return True
    ext = base.rsplit(".", 1)[-1] if "." in base else ""
    return ext in CODE_EXT

DELEGATE = (
    "🚫 [orchestration-gate] 오케스트레이터(%s)는 한 턴에 코드 파일 %d개까지만 직접 수정합니다.\n"
    "이번이 3개째 코드 파일 변경입니다 — 물리적으로 차단합니다.\n"
    "→ 코드 구현은 서브에이전트에 위임하세요: ft-implementer(opus-4-6) / ft-tester(sonnet-5).\n"
    "  (문서·설정·상태 파일은 카운트되지 않습니다. 정말 필요하면 위임 후 진행.)"
)

# ── 2) Bash 우회 차단 — 쓰기성 연산 + 코드파일 타겟만 정밀 판정 (오탐 최소) ──
def bash_write_target(cmd):
    # shlex 토큰 기반 쓰기 대상 탐지 (P1-a 재작성).
    # shlex.split은 quoted "a > b"를 한 토큰으로 묶어 오탐 제거,
    # 실제 리다이렉트 >는 별도 토큰으로 분리돼 정탐 유지.
    # 옵션 위치 무관 -i 탐지로 sed -e '...' -i 등 우회 차단.
    # 어떤 오류에서도 None 반환 (fail-open).
    try:
        scan = re.sub(r"\[\[.*?\]\]", " ", cmd)
        scan = re.sub(r"\(\(.*?\)\)", " ", scan)
        # 명령 구분자로만 분리(| || & && ; newline). ★ `&`가 리다이렉트 일부(`>&`·`&>`)면 분리 금지:
        #   lookbehind (?<!>)로 `>&`, lookahead (?!>)로 `&>` 보호 → 세그먼트가 redirect+target을 함께 유지.
        for seg in re.split(r"\s*(?:(?<!>)\|\|?|(?<!>)&&?(?!>)|;|\n)\s*", scan):
            seg = seg.strip()
            if not seg:
                continue
            try:
                toks = shlex.split(seg)
            except ValueError:
                return None  # fail-open: 짝없는 따옴표 등 파싱 불가 → 허용
            if not toks:
                continue
            # (A) 리다이렉트: 파일에 쓰는 모든 형태 탐지 (P1-a).
            #   [fd]>  [fd]>>  [fd]>|  [fd]>&FILE  &>  &>>  → 대상이 코드파일이면 deny.
            #   제외: 2>·fd≥2(stderr+), >&N·2>&1·>&-(fd-dup·close), quoted "a>b"(shlex가 한 토큰).
            for i, t in enumerate(toks):
                m1 = re.match(r'^(\d*)(>>|>\||>&|>)(.*)$', t)   # [fd]> >> >| >&
                m2 = re.match(r'^(&>>?)(.*)$', t)               # &> &>>
                if m1:
                    fd_s, op, inline = m1.groups()
                    fd = int(fd_s) if fd_s else 1               # fd 없음 = stdout(1)
                elif m2:
                    op, inline = m2.groups(); fd = 1            # &> = stdout+stderr 파일 쓰기
                else:
                    continue
                if fd >= 2:                                     # 2>+ (stderr+) → allow
                    continue
                target = inline.strip() if inline.strip() else (toks[i+1] if i + 1 < len(toks) else None)
                if not target:
                    continue
                if re.match(r'^&?\d+$', target) or target in ('&-', '-'):  # fd-dup / close → allow
                    continue
                target = target.lstrip('&')                     # >&file → file
                if is_code_file(target):
                    return target
            # (B) in-place 편집기: sed/perl/ruby — 옵션 위치 무관 -i 탐지.
            head = os.path.basename(toks[0])
            if head in ('sed', 'perl', 'ruby'):
                has_ip = any(
                    t == '--in-place' or t.startswith('--in-place=')
                    or (t.startswith('-') and not t.startswith('--') and 'i' in t[1:])
                    for t in toks[1:] if t.startswith('-')
                )
                if has_ip:
                    for t in toks[1:]:
                        if not t.startswith('-') and is_code_file(t):
                            return t
            elif head == 'awk':
                if any(toks[j] == '-i' and j + 1 < len(toks) and toks[j + 1] == 'inplace'
                       for j in range(1, len(toks))):
                    for t in toks[1:]:
                        if not t.startswith('-') and t != 'inplace' and is_code_file(t):
                            return t
            # (C) mv/cp/install/rsync 마지막 비옵션, tee 파일, dd of=
            if head in ('mv', 'cp', 'install', 'rsync'):
                args = [t for t in toks[1:] if not t.startswith('-')]
                if args and is_code_file(args[-1]):
                    return args[-1]
            elif head == 'tee':
                for t in toks[1:]:
                    if not t.startswith('-') and is_code_file(t):
                        return t
            elif head == 'dd':
                for t in toks[1:]:
                    if t.startswith('of=') and is_code_file(t[3:]):
                        return t[3:]
        return None
    except Exception:
        return None

if tool == "Bash":
    cmd = tin.get("command", "") or ""
    hit = bash_write_target(cmd)
    if hit:
        deny("🚫 [orchestration-gate] 오케스트레이터는 Bash로 코드 파일을 직접 수정할 수 없습니다.\n"
             "감지: %s\n→ 코드 수정은 ft-implementer에 위임하세요 (redirect/sed/mv/cp/tee 우회 금지)." % hit.strip())
    allow()

# ── 3) Edit/Write/NotebookEdit — 턴당 distinct 코드파일 카운트 ──
if tool in ("Edit", "Write", "NotebookEdit"):
    path = tin.get("file_path") or tin.get("notebook_path") or ""
    if not is_code_file(path):
        allow()  # 문서·설정·상태는 무제한
    # 턴 상태: distinct 코드파일 집합 (UserPromptSubmit 훅이 리셋)
    # TMPDIR="" (빈 값)도 /tmp로 정규화 — 빈 값이면 상태 디렉터리가 cwd에 생기는 오염 방지.
    tmp = (os.environ.get("TMPDIR") or "/tmp").rstrip("/")
    d = os.path.join(tmp, "omc-orch-gate")
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        allow()
    key = hashlib.sha1(sid.encode()).hexdigest()[:16]
    fp = os.path.join(d, key + ".files")
    seen = set()
    try:
        if os.path.isfile(fp):
            seen = set(l.strip() for l in open(fp) if l.strip())
    except Exception:
        seen = set()
    real = os.path.realpath(path)
    if real in seen:
        allow()  # 같은 파일 재편집은 새 카운트 아님
    if len(seen) >= max_code:
        # 이미 상한 도달 + 새 코드파일 → 3개째 → 차단
        deny(DELEGATE % (model, max_code))
    # 상한 미만 → 기록하고 허용
    try:
        with open(fp, "a") as f:
            f.write(real + "\n")
    except Exception:
        pass
    allow()

allow()
PYEOF
GATE_RC=$?
# python이 exit 2로 deny(메시지는 python이 이미 stderr로 출력). 그 외(0/오류)는 허용(fail-open).
# ★ $(...)로 감싸지 않는다: bash 3.2(/bin/bash)는 $(...) 안의 quoted heredoc 내부 따옴표를
#   파싱하는 버그가 있어 파싱 실패→fail-open 무력화. 직접 실행으로 3.2 호환 + deny 메시지 stderr 직결.
[ "$GATE_RC" = "2" ] && exit 2
exit 0
