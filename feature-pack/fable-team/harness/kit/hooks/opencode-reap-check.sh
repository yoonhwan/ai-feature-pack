#!/usr/bin/env bash
# opencode-reap-check.sh — PostToolUse(Bash) 훅 (r286 · 판정 2035): 명령이 opencode 를 «실행» 했으면, 끝난 뒤 부모 잃은 opencode
#   (ppid 1 · 내 uid · 시작 FT_OC_HOOK_WINDOW_S 초 이내 · 기본 660 = Bash 상한 600 + 여유) 를 찾아 모델에게 알린다 — kill 0(회수는 ft-opencode-reap.sh 한 곳).
#   글자로만 든 opencode(echo·grep 인자·따옴표 안·heredoc 본문)는 대상 아님 · 고아 없으면 출력 0.
#   고아가 있으면 pid 파일 <FT_OC_STATE_DIR(기본 ~/.claude/state/opencode)>/orphans-<epoch>-<pid>.pids 를 쓰고 회수 명령 1줄을 additionalContext 로.
#   내부 오류 = stderr 1줄 + rc 1(조용한 통과 0 — PostToolUse 는 도구를 막지 못한다).
PY=$(cat <<'EOF'
import json, os, re, shlex, subprocess, sys, time
OC = {"opencode", ".opencode", "opencode-ai"}; SH = {"bash", "sh", "zsh", "node", "bun", "env"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
SKIP = {"command", "builtin", "exec", "nohup", "time", "if", "then", "elif", "else", "while", "until", "do", "!", "{", "}", "sudo", "env", "xargs", "caffeinate"}
def runs_oc(cmd, depth=0):   # opencode 가 «명령 자리»에 있는가 — 따옴표·heredoc 안 글자는 명령이 아니다 · bash -c 안은 재귀(상한 3)
    cmd = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\s*(?=\n|$)", "", cmd, flags=re.S).replace("\n", " ; ")
    try:
        lx = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()"); lx.whitespace_split = True; toks = list(lx)
    except ValueError: toks = cmd.split()
    start, i = True, 0
    while i < len(toks):
        tk = toks[i]; i += 1
        if tk and set(tk) <= set(";&|()"): start = True; continue
        if not start: continue
        if ASSIGN.match(tk) or tk in SKIP or tk.startswith("-"): continue
        if tk in ("timeout", "gtimeout"):
            while i < len(toks) and toks[i].startswith("-"): i += 1
            i += 1; continue
        b = os.path.basename(tk)
        if b in OC: return True
        if b in ("bash", "sh", "zsh") and depth < 3:
            while i < len(toks) and toks[i].startswith("-"):
                if re.fullmatch(r"-[a-z]*c", toks[i]) and i + 1 < len(toks) and runs_oc(toks[i + 1], depth + 1): return True
                i += 1
        start = False
    return False
def secs(et):   # [[dd-]hh:]mm:ss
    d, _, hms = et.rpartition("-"); p = [int(x) for x in hms.split(":")]
    while len(p) < 3: p.insert(0, 0)
    return int(d or 0) * 86400 + p[0] * 3600 + p[1] * 60 + p[2]
def is_oc(c):
    w = c.split()[:2]; b = os.path.basename(w[0]) if w else ""
    return b in OC or (b in SH and len(w) > 1 and os.path.basename(w[1]) in OC)
try:
    d = json.load(sys.stdin)
    cmd = (d.get("tool_input") or {}).get("command") or ""
    if d.get("tool_name") != "Bash" or "opencode" not in cmd or not runs_oc(cmd): sys.exit(0)
    win = int(os.environ.get("FT_OC_HOOK_WINDOW_S", "660"))
    out = subprocess.run(["ps", "-axww", "-o", "pid=,ppid=,uid=,etime=,lstart=,command="], capture_output=True, text=True, timeout=7, env={**os.environ, "LC_ALL": "C"}, check=True).stdout
    orph = []
    for f in (l.split(None, 9) for l in out.splitlines()):
        if len(f) >= 10 and f[1] == "1" and int(f[2]) == os.getuid() and is_oc(f[9]) and secs(f[3]) <= win: orph.append((f[0], " ".join(f[4:9]), f[9]))
    if not orph: sys.exit(0)
    st = os.environ.get("FT_OC_STATE_DIR") or os.path.expanduser("~/.claude/state/opencode"); os.makedirs(st, exist_ok=True)
    pf = os.path.join(st, f"orphans-{int(time.time())}-{os.getpid()}.pids")
    open(pf, "w", encoding="utf-8").write("# since 0\n" + "".join(f"{p}\t{l}\torphan\n" for p, l, _ in orph))
    bin_ = os.environ.get("FT_BIN") or "<FT_BIN>"
    msg = (f"[opencode-reap-check] opencode 고아 {len(orph)}개 남음(부모 잃음 · pid {' '.join(p for p, _, _ in orph)}) — opencode 는 쓰면 매번 완전히 닫는다(판정 2035): "
           f"bash {bin_}/ft-opencode-reap.sh --pid-file {pf} --apply  → 끝 줄 left=0 확인")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}, ensure_ascii=False))
except SystemExit: raise
except Exception as e:
    print(f"opencode-reap-check: ERROR {type(e).__name__}: {e}", file=sys.stderr); sys.exit(1)
EOF
)
exec python3 -c "$PY"
