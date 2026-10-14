#!/usr/bin/env bash
# ft-resume-attempt.sh — R163(판정 1675 ②) 죽은 좌석 자동 재개의 «기록» 쪽: 살아 있는 좌석 스냅샷 · 시도 원장 · 오빠 재허용.
#   snapshot <좌석> --agent <A> --model <M>   claude 좌석의 대화 uuid·cwd·모델을 ZC_LIVE_DIR/<좌석>.json 에 tmp→mv 로 쓴다(jsonl mtime 이 바뀐 때만 · codex·cmd 는 쓰지 않음)
#   record <좌석> [uuid|jsonl]                 스냅샷이 유효하면 값 출력(rc 0) · 없으면 rc 1
#   state <좌석> <uuid>                         none|pending|ok|failed (원장 마지막 줄)
#   claim <좌석> <uuid>                         mkdir <원장>.lock 원자 선점 → `pending <epoch>` (이미 선점이면 BLOCKED rc 1)
#   settle <좌석> <uuid> ok|failed              결과를 같은 원장에 덧씀
#   sweep                                       pending 원장 정산: 지금 살아 있는 대화의 jsonl 이 epoch 뒤에 자랐으면 ok · 세션 없음(조기 종료)·FT_RESUME_SETTLE_SEC(180) 무진행이면 failed
#   allow <좌석> <uuid>                         ★오빠 `! bash /tmp/h<N>` 로만★ — failed 원장에 `.allow` 토큰 1개 + allow.log 1줄(좌석 실행은 상태 가드가 deny)
#   can-try <좌석> <uuid>                       소비 없이 fresh|allowed|blocked <상태> (rc 0 = 시도 가능)
#   consume-allow <좌석> <uuid>                 틱 전용: 토큰 줄 == allow.log 줄일 때만 mv 로 원자 소비 → lock 해제(정확히 1회 더 claim 가능)
#   rested <jsonl>                              마지막 턴에 `[완료·휴식` 쪽지가 있으면 rc 0(완료·휴식 좌석은 죽음 대상 아님)
#   원장 = FT_RESUME_STATE(기본 <루트>/.fable-team/state/seat-resume-attempts) · 스냅샷 = ZC_LIVE_DIR(기본 ~/.claude/state/seat-live) · 시계 = FT_NOW
#   allow.log 는 원장 폴더 안에 둔다(autonomy.log 에 줄을 덧붙이면 ft-autonomy.sh mode 의 «마지막 줄» 위변조 검사가 걸린다 · 좌석 쓰기 deny 는 폴더 단위로 같이 덮임).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(cd "$HERE/../.." && pwd)}"
python3 -I - "$ROOT" "$@" <<'PY'
import json, os, re, subprocess, sys, time, collections
root, args = sys.argv[1], sys.argv[2:]
env = os.environ; home = os.path.expanduser("~")
now = lambda: int(env.get("FT_NOW") or time.time())
ATT = env.get("FT_RESUME_STATE") or f"{root}/.fable-team/state/seat-resume-attempts"
LIVE = env.get("ZC_LIVE_DIR") or f"{home}/.claude/state/seat-live"
SETTLE = int(env.get("FT_RESUME_SETTLE_SEC") or 180)
def die(msg, rc=1): print(msg); sys.exit(rc)
def load(f):
    try: return json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError): return None
def sh(*a):
    try: r = subprocess.run(a, capture_output=True, text=True, timeout=7); return r.returncode, r.stdout.split()
    except (OSError, subprocess.SubprocessError): return 1, []
def atomic(path, text):
    tmp = f"{path}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f: f.write(text)
    os.replace(tmp, path)
def ledger(seat, uuid): return f"{ATT}/{seat}__{uuid}.state"
def status(seat, uuid):
    try: last = open(ledger(seat, uuid), encoding="utf-8").read().strip().splitlines()[-1].split()
    except (OSError, IndexError): return None
    return last[0], int(last[1]) if len(last) > 1 and last[1].isdigit() else 0
def append(path, line):
    with open(path, "a", encoding="utf-8") as f: f.write(line + "\n")
def find_live(seat):   # (기록|None, 이유) — ft-seat-retire.sh find_resume 와 같은 결속: pane 자식 중 세션 파일이 있는 «정확히 1개»
    rc, pp = sh("tmux", "display", "-p", "-t", "=" + seat + ":", "#{pane_pid}")
    if not pp: return None, "tmux 세션 없음"
    _, ks = sh("pgrep", "-P", pp[0]); kids = [k for k in ks if os.path.isfile(f"{home}/.claude/sessions/{k}.json")]
    if len(kids) != 1: return None, f"세션 파일 {len(kids)}개"
    s = load(f"{home}/.claude/sessions/{kids[0]}.json"); s = s if isinstance(s, dict) else {}
    if s.get("name") != seat or str(s.get("pid")) != kids[0]: return None, "세션 파일 name·pid 불일치"
    uuid, cwd = s.get("sessionId") or "", s.get("cwd") or ""
    jsonl = f"{home}/.claude/projects/{re.sub('[^A-Za-z0-9]', '-', cwd)}/{uuid}.jsonl"
    if not (uuid and cwd and os.path.isfile(jsonl)): return None, "uuid·cwd·jsonl 없음"
    return dict(pid=int(kids[0]), uuid=uuid, jsonl=jsonl, cwd=cwd), ""
def cmd_snapshot(seat, agent, model):
    if agent != "claude": print(f"SKIP {seat} agent={agent or '-'} (claude 만)"); return 0
    if not model: die(f"REJECT {seat} --model 없음", 2)
    live, why = find_live(seat)
    if not live: print(f"SKIP {seat} {why}"); return 0
    mt = int(os.path.getmtime(live["jsonl"])); p = f"{LIVE}/{seat}.json"; old = load(p)
    if isinstance(old, dict) and old.get("uuid") == live["uuid"] and old.get("jsonl_mtime") == mt and old.get("model") == model:
        print(f"UNCHANGED {seat}"); return 0
    rec = collections.OrderedDict(name=seat, engine="claude", pid=live["pid"], uuid=live["uuid"], jsonl=live["jsonl"], cwd=live["cwd"], model=model,
        at=time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now())), source="live", jsonl_mtime=mt)
    try: os.makedirs(LIVE, exist_ok=True); atomic(p, json.dumps(rec, ensure_ascii=False, indent=2) + "\n")
    except OSError as e: die(f"ERROR snapshot 쓰기 실패 {p}: {e}")
    print(f"LIVE ok {p}"); return 0
def cmd_record(seat, field):
    d = load(f"{LIVE}/{seat}.json")
    ok = isinstance(d, dict) and d.get("name") == seat and d.get("engine") == "claude" and isinstance(d.get("uuid"), str) and d["uuid"] and isinstance(d.get("jsonl"), str)
    if not ok: return 1
    print(d["jsonl"] if field == "jsonl" else d["uuid"]); return 0
def cmd_claim(seat, uuid):
    os.makedirs(ATT, exist_ok=True)
    try: os.mkdir(ledger(seat, uuid) + ".lock")
    except FileExistsError: die(f"BLOCKED {seat} {uuid} 이미 시도됨", 1)
    append(ledger(seat, uuid), f"pending {now()}"); print(f"CLAIMED {seat} {uuid}"); return 0
def cmd_settle(seat, uuid, res):
    if res not in ("ok", "failed"): die("usage: settle <좌석> <uuid> ok|failed", 2)
    if status(seat, uuid) is None: die(f"REJECT 원장 없음 {seat} {uuid}")
    append(ledger(seat, uuid), f"{res} {now()}"); print(f"SETTLED {seat} {uuid} {res}"); return 0
def cmd_sweep():
    try: names = sorted(n for n in os.listdir(ATT) if n.endswith(".state"))
    except OSError: return 0
    for n in names:
        seat, _, uuid = n[:-6].rpartition("__"); st = status(seat, uuid)
        if not st or st[0] != "pending": continue
        alive = sh("tmux", "has-session", "-t", "=" + seat)[0] == 0
        live, _ = find_live(seat) if alive else (None, "")
        grew = bool(live) and int(os.path.getmtime(live["jsonl"])) > st[1]
        res = "ok" if grew else ("failed" if (not alive or now() - st[1] >= SETTLE) else "")
        if res: cmd_settle(seat, uuid, res)
    return 0
def cmd_allow(seat, uuid):
    st = status(seat, uuid)
    if not st or st[0] != "failed": die(f"REJECT {seat} {uuid} 원장 상태가 failed 가 아니다({st[0] if st else 'none'}) — 재허용 대상 아님")
    line = f"resume-allow {seat} {uuid} {now()}"
    append(f"{ATT}/allow.log", line); atomic(ledger(seat, uuid) + ".allow", line + "\n"); print(f"ALLOWED {line}"); return 0
def token_ok(seat, uuid):   # failed 원장 ∧ 토큰 = `resume-allow <좌석> <uuid> <발급 id(epoch)>` 정확히 한 줄 ∧ 본문 좌석·uuid == 인자 ∧ allow.log 에 «그 줄 그대로» (다른 좌석·uuid 의 승인 줄을 옮겨 넣은 토큰 = 무효)
    st = status(seat, uuid)
    if not st or st[0] != "failed": return False
    try: line = open(ledger(seat, uuid) + ".allow", encoding="utf-8").read().strip(); log = open(f"{ATT}/allow.log", encoding="utf-8").read().splitlines()
    except OSError: return False
    f = line.split(" ")
    if len(f) != 4 or f[0] != "resume-allow" or f[1] != seat or f[2] != uuid or not f[3].isdigit() or " ".join(f) != line: return False
    return line in log
def cmd_can(seat, uuid):   # 소비 없이 «지금 시도할 수 있나»: fresh(원장 없음) | allowed(오빠 토큰 유효) | blocked <상태>
    st = status(seat, uuid)
    if st is None: print("fresh"); return 0
    if token_ok(seat, uuid): print("allowed"); return 0
    print(f"blocked {st[0]}"); return 1
def cmd_consume(seat, uuid):
    if not token_ok(seat, uuid): die("NONE 유효한 토큰 없음(failed 아님·토큰 없음·allow.log 줄 없음=직접 쓰기) — 소비 0", 1)
    tok = ledger(seat, uuid) + ".allow"
    try: os.rename(tok, f"{tok}.used.{now()}")
    except OSError: die("NONE 이미 소비됨", 1)
    try: os.rmdir(ledger(seat, uuid) + ".lock")
    except OSError: pass
    print(f"CONSUMED {seat} {uuid}"); return 0
def cmd_rested(jsonl):   # 마지막 턴(마지막 turn_duration 이후 또는 직전 두 turn_duration 사이)에 `[완료·휴식` 쪽지
    try:
        with open(jsonl, "rb") as f: f.seek(0, 2); n = f.tell(); f.seek(max(0, n - 1048576)); lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError: return 1
    ends = [i for i, l in enumerate(lines) if '"turn_duration"' in l]
    if not ends: return 1
    lo = (ends[-2] + 1) if len(ends) > 1 else 0
    if any('"type":"assistant"' in l or '"type":"user"' in l for l in lines[ends[-1] + 1:]): return 1   # 마지막 턴이 끝난 뒤 새 턴이 열렸다 = 쉬는 중 아님
    return 0 if any("[완료·휴식" in l for l in lines[lo:ends[-1] + 1]) else 1
a = args; c = a[0] if a else ""
opt = lambda k: (a[a.index(k) + 1] if k in a and a.index(k) + 1 < len(a) else "")
need = {"snapshot": 2, "record": 2, "state": 3, "claim": 3, "settle": 4, "allow": 3, "consume-allow": 3, "can-try": 3, "rested": 2, "sweep": 1}
if c not in need or len(a) < need[c]: die("usage: ft-resume-attempt.sh snapshot|record|state|claim|settle|sweep|allow|consume-allow|rested ...", 2)
if c == "snapshot": sys.exit(cmd_snapshot(a[1], opt("--agent"), opt("--model")))
if c == "record": sys.exit(cmd_record(a[1], a[2] if len(a) > 2 else "uuid"))
if c == "state": print((status(a[1], a[2]) or ("none",))[0]); sys.exit(0)
if c == "claim": sys.exit(cmd_claim(a[1], a[2]))
if c == "settle": sys.exit(cmd_settle(a[1], a[2], a[3]))
if c == "sweep": sys.exit(cmd_sweep())
if c == "allow": sys.exit(cmd_allow(a[1], a[2]))
if c == "can-try": sys.exit(cmd_can(a[1], a[2]))
if c == "consume-allow": sys.exit(cmd_consume(a[1], a[2]))
if c == "rested": sys.exit(cmd_rested(a[1]))
PY
