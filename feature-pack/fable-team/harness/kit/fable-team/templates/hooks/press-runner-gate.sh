#!/bin/bash
# fable-team press-runner-gate — PreToolUse:Bash (R106c · 오빠 R15 「poller 없는 press 하는 tester+checker 세션은 없어야한다」· R4)
# 왜: ft-press-gate.sh(⑥ 기준선·⑦ 좌석 역할)는 tester 가 스스로 부를 때만 걸려 나노·master 의 러너 직접 실행을 못 막는다.
# 적용: «실행 꼴 양성 일치»만 — 래퍼(nohup·timeout N·caffeinate·uv run)를 벗긴 조각이 `python* [옵션] realtime_multi_e2e.py`·`python* -m …realtime_multi_e2e`·러너 직접 실행이면 ft-press-gate.sh 를 같은 env 로 돌려 rc≠0 → deny(쪽지·grep·pytest·pgrep 등은 allow). 인라인 `FT_PRESS_CARD=… python3 …` 대입은 전달. 게이트 = env FT_PRESS_GATE_BIN > <리포 루트>/.fable-team/bin/ft-press-gate.sh.
# ★게이트 부재·실행 실패·시간초과 = deny(fail-closed) · stdin 파싱 불가 = 허용+로그(sibling 관례) · 게이트 PASS 는 허가·BTS 골격을 발급하니 훅이 대신 부르는 회차에 수동으로 또 부르지 않는다(⑧) · 설치는 master 몫★
set +e; INPUT=$(cat 2>/dev/null); [ -n "$INPUT" ] || exit 0; export INPUT
python3 - <<'PYEOF'
import json, os, re, shlex, subprocess, sys, time
LOG = os.environ.get("FT_PRESS_RUNNER_GATE_LOG") or os.path.expanduser("~/.claude/logs/press-runner-gate.log")
RUNNER, SHELLS, WRAP = "realtime_multi_e2e.py", {"bash", "sh", "zsh"}, {"nohup", "time", "exec", "command", "nice", "caffeinate", "timeout", "uv", "run"}
PY = re.compile(r"python[\d.]*")
ASSIGN = re.compile(r"^([A-Za-z_]\w*)=(.*)$", re.S)
def note(msg):
    try: os.makedirs(os.path.dirname(LOG), exist_ok=True); open(LOG, "a", encoding="utf-8").write(time.strftime("%Y-%m-%dT%H:%M:%S") + f" press-runner-gate: {msg}\n")
    except OSError: pass
GUIDE = " · press 는 tester·checker 좌석이 FT_PRESS_CARD=<카드> 로만(R15·R4)"
def split(cmd):  # 따옴표 밖 ; | & 줄바꿈 기준 조각
    segs, q = [""], None
    for c in cmd:
        if q: q = None if c == q else q
        elif c in "'\"": q = c
        elif c in ";|&\n": segs.append(""); continue
        segs[-1] += c
    return [s for s in segs if s.strip()]
def is_run(w):  # 실행 꼴 양성 일치 — 옵션 문법은 파싱하지 않고 첫 python* 단어 뒤를 왼쪽부터 읽는다
    h = os.path.basename(w[0])
    if h == RUNNER: return True
    if h not in WRAP and not PY.fullmatch(h): return False
    a = w[next((i for i, x in enumerate(w) if PY.fullmatch(os.path.basename(x))), 0) + 1:]
    for j, x in enumerate(a):
        if x == "-c": return False
        if x == "-m": return j + 1 < len(a) and a[j + 1].split(".")[-1] == RUNNER[:-3]
        if x.endswith(".py"): return os.path.basename(x) == RUNNER
    return False
def walk(cmd, depth=0):  # → (러너 «실행» 조각 있음, 인라인 대입 {이름: 값})
    run, env = False, {}
    for seg in split(cmd):
        try: w = shlex.split(seg)
        except ValueError: w = seg.split()
        while w and (w[0] in ("export", "env") or ASSIGN.match(w[0])):
            m = ASSIGN.match(w.pop(0))
            if m and (m.group(1).startswith(("FT_PRESS_", "BYZ_PRESS_")) or m.group(1) == "FT_NANO_FEAT"): env[m.group(1)] = m.group(2)  # FT_NANO_FEAT = 게이트 ① 기준 줄기(없으면 게이트 기본 feat/v6-realtime-live) — v65 #183593
        if not w: continue
        head = os.path.basename(w[0])
        flag = [i for i, x in enumerate(w) if i and re.fullmatch(r"-\w*c\w*", x) and i + 1 < len(w)]
        if head in SHELLS and flag and depth < 3:  # bash -lc '…' 안쪽을 다시 본다
            r, e = walk(w[flag[0] + 1], depth + 1)
            run, env = run or r, {**env, **e}
        elif is_run(w): run = True
    return run, env
def deny(why):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": why}}, ensure_ascii=False)); sys.exit(0)
try: data = json.loads(os.environ["INPUT"]); data.get("tool_name")
except (ValueError, AttributeError) as e: note(f"stdin JSON 파싱 불가({e}) — 허용(fail-open)"); sys.exit(0)
run, inline = walk(str((data.get("tool_input") or {}).get("command") or ""))
if data.get("tool_name") not in (None, "Bash") or not run: sys.exit(0)
cwd = data.get("cwd") or os.getcwd()
git = lambda *a: subprocess.run(["git", "-C", cwd, *a], capture_output=True, text=True).stdout.strip()
top = git("rev-parse", "--show-toplevel") or cwd
gate = os.environ.get("FT_PRESS_GATE_BIN") or os.path.join(top, ".fable-team/bin/ft-press-gate.sh")
def install_hint():  # r494: 새 워크트리 bin 없음 = 설치본 shim --init 1줄 · LIVE_BIN = 공용 루트 .fable-team/LIVE_BIN 1줄(못 읽으면 글자 <LIVE_BIN>)
    gd, lb = git("rev-parse", "--path-format=absolute", "--git-common-dir"), ""
    try: lb = open(os.path.join(os.path.dirname(gd) if os.path.basename(gd) == ".git" else gd, ".fable-team/LIVE_BIN"), encoding="utf-8").readline().strip() if gd else ""
    except OSError: pass
    lb = lb or "<LIVE_BIN>"
    return f" · 설치(master) = bash {lb}/ft-root-bin-shim.sh --root {top} --live {lb} --init"
if not os.access(gate, os.X_OK): deny(f"press 러너 실행인데 게이트가 없다({gate}) — fail-closed(R106c)" + GUIDE + install_hint())
try: r = subprocess.run([gate], env={**os.environ, **inline}, capture_output=True, text=True, timeout=60)
except (OSError, subprocess.TimeoutExpired) as e: deny(f"ft-press-gate 실행 실패({e}) — fail-closed(R106c)")
if r.returncode != 0:
    xs = " / ".join(l.strip() for l in r.stdout.splitlines() if "✗" in l)[:600]
    deny(f"ft-press-gate 막힘(rc={r.returncode}): {xs}" + GUIDE)
PYEOF
exit 0
