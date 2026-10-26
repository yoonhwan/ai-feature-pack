#!/bin/bash
# fable-team autonomy-state-guard — PreToolUse:Bash|Write|Edit|NotebookEdit (r-autonomy-hooks 훅② · 판정 1322·1355 · DESIGN-autonomy-proxy-decision r3 §1)
# 왜: 좌석이 자율 모드를 스스로 켜고 끄거나 상태 파일을 고치면 모드 전체가 무의미하다. ON/OFF 는 오빠 `!` 한 줄(ft-hil.sh 계획 파일)로만.
# 막는 것(모드 ON/OFF 무관 · BYZ 리포 안): `autonomy.json`·`autonomy.log`(+`.tmp`)·`autonomy-merge-ok/`·`autonomy-merge-approved/`·`autonomy-scope/`·`autonomy-digest/`·`seat-resume-attempts/` 경로를 «쓰는» 호출,
#   `ft-autonomy.sh on|off|approve-merge|approve-scope|approve-standing(r947)|forget-kind`·`ft-queue-digest.sh issue`·`ft-resume-attempt.sh allow` 실행(판정 1675 · 뒤 두 도구는 r163·r165 가 만든다).
#   r466 5c: 인자에 오빠 진입 파일(`/tmp/h<N>`·$HIL_DIR/h<N>)·계획 파일(`*.sh.hil`)이 있으면 그 본문(진입 파일의 `plan=` 이 가리키는 계획 파일까지 1단)에 같은 판정 —
#     단 approve-merge 는 자율 ON(ft-autonomy.sh mode = on)이면 허용 + 로그 `hN-approve seat=<tmux 세션|unknown> file=<경로>`(자율 중 병합 승인 = desk 실행) · OFF·못 읽음 = deny · on|off|forget-kind|approve-scope = 늘 deny · 파일 못 읽음 = 허용 + 로그.
#   r947 r2: 실행 판정은 `bash|sh` 직접 호출뿐 아니라 `source`·`.` 경유도 같은 파일이면 같다(DA 반례 1).
#   Write/Edit/NotebookEdit 는 file_path·notebook_path. Bash 는 «양성 일치»만: 리다이렉트 `>`/`>>`/`>|` 대상 · tee · cp(마지막 인자=대상) · mv/rm/ln/install/touch/truncate 인자 · dd of= · sed/perl -i.
#   r626: `ALL_STOP.json`·`ALL_STOP.released-*` 쓰기(누구든) · `ft-all-stop.sh`/`ft_all_stop.py` on|off 실행(어느 꼴이든 · planner 명부 `_master` 좌석만 예외 · hN 본문도 같다) ·
#     `all-stop.log`(원장 · DA⑥ r2) 쓰기 · `.fable-team`·`.fable-team/state` 폴더 자체 mv·rm · 인터프리터 코드 안 ALL_STOP 쓰기·지우기·옮기기(heredoc 포함) — 사유 문구는 r626 것. 변수 간접·glob 은 위협 모델 밖(카드 DA⑥ r1).
#   읽기 목록 밖을 전부 막는 방향은 오탐 폭발(r106c 실측)이라 금지 — cat·jq·grep·tail·ft-autonomy.sh status|mode|event·따옴표 안 글자·heredoc 본문은 allow.
# 한계(설계 §1): bypass 좌석의 적대적 우회(python -c 로 쓰기 등)까지는 못 막는다 — 그건 ft-autonomy.sh 의 위변조 표시가 잡는다.
# ★FAIL-OPEN★: 파싱 불가 = 허용 + 로그(FT_AUTONOMY_HOOK_LOG · 기본 ~/.claude/logs/autonomy-hooks.log). 외부 호출 0 — 로컬 git rev-parse 뿐.
# ★설치(~/.claude/hooks/ 복사 · settings.json PreToolUse 등록)는 이 파일 범위 밖 — 설치 카드★
# ★r546★ env -S 분해는 공용 모듈 merge_cmd.env_split 하나 — 같은 폴더의 merge_cmd.py 가 없으면 rc2(막음). 사본 0.
set +e
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0
export INPUT ASG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$ASG_DIR/merge_cmd.py" ] || { echo "REJECT autonomy-state-guard: merge_cmd 없음 — 같은 폴더 공용 모듈(r546)이 필요하다: $ASG_DIR/merge_cmd.py" >&2; exit 2; }
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys, time

sys.path.insert(0, os.environ["ASG_DIR"])
from merge_cmd import env_split  # r546: 사본 삭제 전 이 훅 안에 있던 그 함수(글자 그대로 옮겼다)

LOG = os.environ.get("FT_AUTONOMY_HOOK_LOG") or os.path.expanduser("~/.claude/logs/autonomy-hooks.log")
PROT = re.compile(r"(^|/)(autonomy\.(json|log)(\.tmp)?|(autonomy-merge-ok|autonomy-merge-approved|autonomy-scope|autonomy-standing|autonomy-digest|seat-resume-attempts)(/|$))")
DENY_EXEC = {"ft-autonomy.sh": ("on", "off", "approve-merge", "approve-scope", "approve-standing", "forget-kind"), "ft-queue-digest.sh": ("issue",), "ft-resume-attempt.sh": ("allow",)}  # 뒤 두 도구는 r163·r165 가 만든다 — 이름만 먼저 막는다
HFILE = re.compile(r"(^|/)h[0-9]+$|\.sh\.hil$")
WRAP = {"sudo", "env", "command", "exec", "nohup", "time", "timeout", "nice"}
SHELLS = {"bash", "sh", "zsh", "dash"}
SOURCE = {"source", "."}   # r947 r2(DA 반례 1): source·. 경유도 «같은 파일을 실행»이다 — 대상 파일이 프로그램 자리로 올라온다
VALOPTS = {"-u", "-C", "-S", "-P", "-k", "-s", "-n"}  # 값을 하나 더 먹는 래퍼 옵션(env -u NAME · timeout -k N · nice -n N)
ANY_ARG = {"tee", "touch", "rm", "truncate", "ln", "install", "shred", "unlink", "mv"}
REASON = ("자율 모드 상태 파일(autonomy.json·autonomy.log)·병합 승인(autonomy-merge-approved/·옛 autonomy-merge-ok/)·범위 승인 폴더(autonomy-scope/)·묶음 발급(autonomy-digest/)·재개 원장(seat-resume-attempts/) 쓰기와 "
          "ft-autonomy.sh on|off|approve-merge|approve-scope · ft-queue-digest.sh issue · ft-resume-attempt.sh allow 는 오빠 `!` 한 줄만 — 좌석 경로 0(판정 1322·1675·2055). "
          "읽기(cat·jq·tail·ft-autonomy.sh status)와 좌석 도구 scope-approve·scope-stop·scope-status 는 허용.")
AS_PROT = re.compile(r"(^|/)(ALL_STOP\.(json(\.tmp)?$|released-)|all-stop\.log$)")   # r626 전팀 정지 상태 파일 — 쓰기는 planner 도 0(도구로만)
AS_REASON = ("전팀 정지 스위치(ft-all-stop.sh·ft_all_stop.py on|off)는 오빠 `!` 한 줄 또는 planner 팀장(명부 seats-planner.json `_master` 좌석)만 — 좌석 경로 0(r626). "
             "ALL_STOP.json·ALL_STOP.released-* 직접 쓰기·지우기·옮기기(파이썬 코드 포함)와 상태 폴더 mv·rm 은 planner 도 0(도구로만). status·check·읽기는 허용.")
AS_EXE = re.compile(r"^ft[-_]all[-_]stop(\.sh|\.py)?$")   # r626 DA⑥ r1 Q2: 실행 꼴 무관(bash·sh·python3·직접 경로) — 이름 글자로 잡는다
AS_DIR = re.compile(r"(^|/)\.fable-team(/state)?/?$")   # 상태 폴더 자체 mv·rm
AS_PYW = re.compile(r"\b(python3?|perl|ruby|node)\b")
AS_PYOP = re.compile(r"\.unlink\(|os\.(remove|unlink|rename|replace)\(|shutil\.|\.rename\(|\.replace\(|open\([^)]*['\"][wax+]|write_(text|bytes)\(|rmtree")
AS_HIT, ROOT = [], [""]


def note(msg):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" autonomy-state-guard: {msg}\n")
    except OSError:
        pass


def byz_root(cwd):
    root = os.environ.get("FT_ROOT")
    if not root:
        p = subprocess.run(["git", "-C", cwd or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd(), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=5)
        root = os.path.dirname(p.stdout.strip()) if p.returncode == 0 and p.stdout.strip() else ""
    return root if root and os.path.isdir(os.path.join(root, ".fable-team")) else ""


def autonomy_mode(root):   # r466: ft-autonomy.sh mode — FT_AUTONOMY_SH → 루트 shim → $FT_HARNESS_ROOT/bin · 못 읽으면 ""
    hr = os.environ.get("FT_HARNESS_ROOT") or ""
    cands = [os.environ.get("FT_AUTONOMY_SH") or "", os.path.join(root, ".fable-team/bin/ft-autonomy.sh"), hr and os.path.join(hr, "bin/ft-autonomy.sh")]
    sh = next((c for c in cands if c and os.path.isfile(c)), None)
    try:
        p = subprocess.run(["bash", sh, "mode"], capture_output=True, text=True, timeout=5) if sh else None
    except (OSError, subprocess.SubprocessError):
        p = None
    m = p.stdout.strip() if p is not None and p.returncode == 0 else ""
    return m if m in ("on", "off", "tamper") else ""


def hil_text(path):   # 진입 파일·계획 파일 본문(진입 파일이면 plan= 이 가리키는 계획 파일까지 1단) → (계획 경로, 본문) · 못 읽음 = None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read(65536)
        m = re.search(r"^# ft-hil-entry plan=(\S+)", text, re.M)
        if m:
            path = m.group(1)
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read(65536)
        return path, text
    except OSError as e:
        note(f"hN 파일 못 읽음 {path}: {type(e).__name__} — 허용(fail-open)")
        return None


def seat_name():
    if not os.environ.get("TMUX"):
        return "unknown"
    try:
        p = subprocess.run(["tmux", "display-message", "-p", "#S"], capture_output=True, text=True, timeout=2)
        return p.stdout.strip() or "unknown"
    except (OSError, subprocess.SubprocessError):
        return "unknown"


def strip_heredocs(cmd):
    out, delim = [], None
    for line in cmd.split("\n"):
        if delim is not None:
            delim = None if line.strip() == delim else delim
            continue
        out.append(line)
        m = re.search(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1", line)
        delim = m.group(2) if m else None
    return "\n".join(out)


def simple_commands(cmd):
    """명령 문자열 → [(단어들, 리다이렉트 대상들)] — 따옴표 안·heredoc 본문은 글자일 뿐 명령이 아니다."""
    lex = shlex.shlex(strip_heredocs(cmd), posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace, lex.whitespace_split, lex.commenters = " \t\r", True, ""
    segs, words, reds, redir = [], [], [], None  # redir: None | "out"(다음 토큰 = 쓰기 대상) | "in"(다음 토큰 = 입력/heredoc 구분자 — 건너뜀)
    for t in lex:
        if redir:
            reds += [t] if redir == "out" else []
            redir = None
        elif t and set(t) <= set(";&|()\n"):
            segs.append((words, reds)); words, reds = [], []
        elif t and set(t) <= set("<>&|"):
            redir = "out" if ">" in t else "in" if "<" in t else None
        else:
            words.append(t)
    return segs + [(words, reds)]


def resolve(words):
    """환경 대입·래퍼·셸 인터프리터를 벗겨 (프로그램 basename, 인자들) — `bash -c 'x'` 는 ('-c', [x])."""
    w = list(words)
    while w:
        b = os.path.basename(w[0])
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]):
            w.pop(0)
        elif b in WRAP:
            w.pop(0)
            while w and (w[0].startswith("-") or re.match(r"^([A-Za-z_][A-Za-z0-9_]*=|[0-9.]+$)", w[0])):
                split = env_split(b, w)
                if split is not None:  # 첫 낱말이 실행 프로그램 — 맨 위 루프가 다시 벗긴다(bash -c 일 때만 -c 문자열을 셸 코드로 재검사)
                    w = split
                    break
                del w[:2 if w[0] in VALOPTS else 1]
        elif b in SOURCE and len(w) > 1:
            w = w[1:]   # r947 r2: `source <파일> <하위명령>` · `. <파일> <하위명령>` = 그 파일 실행과 같은 판정
        elif b in SHELLS:
            w.pop(0)
            while w and w[0].startswith("-") and not re.fullmatch(r"-[a-zA-Z]*c[a-zA-Z]*", w[0]):
                w.pop(0)
            if w and w[0].startswith("-"):
                return "-c", w[1:2]
        else:
            return b, w[1:]
    return "", []


def prot(t):   # 보호 경로인가 — 전팀 정지 파일이면 사유를 r626 으로
    if AS_PROT.search(t):
        AS_HIT.append(t)
        return True
    return bool(PROT.search(t))


def planner_seat():   # r626: 지금 좌석이 planner 명부 `_master` 인가(tmux 세션 이름 · 못 읽음 = 아님)
    try:
        with open(os.path.join(ROOT[0], ".fable-team/seats-planner.json"), encoding="utf-8") as f:
            m = json.load(f).get("_master") or ""
    except (OSError, ValueError):
        return False
    return bool(m) and seat_name() == m


def violates(cmd, depth=0, merge_ok=False, merges=None):   # merge_ok = 계획 파일 안 approve-merge 허용(자율 ON) · merges = 허용한 approve-merge 를 모은다
    if ("ALL_STOP" in cmd or "all-stop.log" in cmd) and AS_PYW.search(cmd) and AS_PYOP.search(cmd):   # r626: 인터프리터 코드 안 ALL_STOP 쓰기·지우기·옮기기(heredoc 본문 포함 · 누구든)
        AS_HIT.append("py")
        return True
    for words, reds in simple_commands(cmd):
        if any(prot(t) for t in reds):
            return True
        prog, args = resolve(words)
        if prog == "-c" and depth < 3 and args and violates(args[0], depth + 1, merge_ok, merges):
            return True
        plain = [a for a in args if not a.startswith("-")]
        if prog == "ft-autonomy.sh" and plain[:1] == ["approve-merge"] and merge_ok and merges is not None:
            merges.append(" ".join(plain[:2]))
        elif plain[:1] and plain[0] in DENY_EXEC.get(prog, ()):
            return True
        exe = [i for i, a in enumerate([prog] + args) if AS_EXE.match(os.path.basename(a))]
        if exe:
            after = [a for a in ([prog] + args)[exe[0] + 1:] if not a.startswith("-")]
            if after[:1] in (["on"], ["off"], ["init"]) and not planner_seat():   # r4: init(설치 전용)도 좌석 직접 실행 0
                AS_HIT.append(prog)
                return True
        if prog in ("mv", "rm", "rmdir") and any(AS_DIR.search(a) for a in plain):
            AS_HIT.append(prog)
            return True
        if prog in ANY_ARG and any(prot(a) for a in plain):
            return True
        if prog == "cp" and plain and prot(plain[-1]):
            return True
        if prog == "dd" and any(a.startswith("of=") and prot(a[3:]) for a in args):
            return True
        if prog in ("sed", "perl") and any(re.match(r"^-[A-Za-z]*i", a) for a in args) and any(prot(a) for a in plain):
            return True
    return False


def hil_files(cmd):   # 명령 낱말 중 진입 파일(h<N>)·계획 파일(*.sh.hil) 경로
    return [w for words, _ in simple_commands(cmd) for w in words if HFILE.search(w) and not w.startswith("-")]


def hil_violates(cmd, root):   # r466 5c → (막음 여부, 사유 꼬리)
    mode = None
    for path in hil_files(cmd):
        got = hil_text(path)
        if got is None:
            continue
        plan, text = got
        if mode is None:
            mode = autonomy_mode(root) if re.search(r"ft-autonomy\.sh", text) else ""
        merges = []
        if violates(text, merge_ok=(mode == "on"), merges=merges):
            return True, f" — 진입 파일 {path} 의 계획({plan}) 안 명령도 같다(r466 · 자율 {mode or '못 읽음'})"
        for m in merges:
            note(f"hN-approve seat={seat_name()} file={path} plan={plan} {m}")
    return False, ""


try:
    d = json.loads(os.environ["INPUT"])
    ti = d.get("tool_input") or {}
    tool = d.get("tool_name")
    root = byz_root(d.get("cwd")) if tool in ("Bash", "Write", "Edit", "NotebookEdit") else ""
    if not root:
        sys.exit(0)
    ROOT[0] = root
    hit, tail = (violates(ti.get("command") or ""), "") if tool == "Bash" else (prot(str(ti.get("file_path") or ti.get("notebook_path") or "")), "")
    if tool == "Bash" and not hit:
        hit, tail = hil_violates(ti.get("command") or "", root)
except (ValueError, OSError, AttributeError, subprocess.SubprocessError) as e:
    note(f"{type(e).__name__} {e} — 허용(fail-open)")
    sys.exit(0)
if hit:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": (AS_REASON if AS_HIT else REASON) + tail}}, ensure_ascii=False))
PYEOF
exit $?  # r546: 종전 `exit 0` 은 모듈 없음·모듈 오류까지 삼켰다 — 이제 rc2(막음)가 전달된다
