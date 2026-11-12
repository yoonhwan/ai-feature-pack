#!/usr/bin/env bash
# ft-critical-notify.sh — 착지·닫기 거절과 되풀이 판정 불가를 desk 에 [크리티컬] 1통으로 알린다 (r1718 · 오빠 추가 지시 8 «그냥 넘기지 말고 데스크에 매번 크리티컬»)
#   알림   : ft-critical-notify.sh <도구> <대상> --event "<사건 지문>" --what "<글>" --next "<1줄>" [--where "<경로|PR|좌석>"]
#   배출   : ft-critical-notify.sh --drain                    밀린 장부에서 오래된 것부터 최대 3통(ft_stall_scan 이 회차마다 1회)
#   해결   : ft-critical-notify.sh --resolved <도구> <대상>   그 대상의 열쇠를 닫는다(로컬 파일만 · 발신 0) → 그 뒤 거절은 지문이 같아도 즉시 1통
#   감싸기 : ft-critical-notify.sh --wrap <도구> <스크립트> [인자…]   본 작업을 자식으로 «1회» 실행 · stdout 은 나오는 대로 흘리고 사본만 뜬다 · 끝난 뒤 rc 1 = 알림 · rc 0 = 해결
#   본문 = «[크리티컬] <도구> <대상> — 무엇: … · 어디: … · 다음 손: …»(700자 안) · 받는 이 = seats-planner.json `_desk` · 보내는 이 = <도구>(ft-* · # 없음)
#   발신 몫 = min(7초, FT_CRITICAL_BUDGET_S) · 재시도 0 · 반환 0 고정(--wrap 만 본 작업 rc). 발신 «앞» 에 state/critical-pending.jsonl 1줄(임시→mv) · 성공한 것만 지운다.
#   같은 열쇠(도구·대상·지문)는 FT_CRITICAL_DEDUPE_S(기본 3600 · 0 = 끔) 안에 1통 · 지나도 미해결이면 «(되풀이 n회째 · 첫 알림 #seq)» · 보낸 기록 = state/critical-sent.jsonl.
#   발신 실패(_desk 없음 · mbox rc≠0 · 시간 초과 · 남은 < 1초) = stderr WARN 1줄 · pending 그대로. FT_CRITICAL_OFF=1 = 호출 0 · 기록 0(시험·격리 실행용).
#   자리: comm = ft_comm_dir(FT_MBOX_DIR → FT_ROOT → cwd git 공용 루트) · 명부 = <comm>/.. · state = FT_CRITICAL_STATE_DIR → <comm>/../state · mbox = FT_MBOX → <comm>/mbox.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { sed -n '3,6s/^# *//p' "${BASH_SOURCE[0]:-$0}" >&2; exit 2; }
core() {   # 장부·발신·분류 = 아래 파이썬 한 곳 · 자리를 못 풀면 WARN 1줄(쓰기 0)
  local comm
  comm="$( . "$HERE/ft-harness-root.sh" 2>/dev/null && ft_comm_dir "$HERE" 2>/dev/null )" \
    || { [ "$1:${3:-}" = after:0 ] || echo "WARN ft-critical-notify: comm 폴더를 못 풂(FT_MBOX_DIR · FT_ROOT · cwd git 공용 루트) — 알림 0 · 기록 0" >&2; return 0; }   # 본 작업 rc 0(알릴 것 없음)이면 조용히
  python3 - "${FT_CRITICAL_STATE_DIR:-$(dirname -- "$comm")/state}" "$(dirname -- "$comm")" "${FT_MBOX:-$comm/mbox.sh}" "$HERE" "$@" <<'PY'
import fcntl, hashlib, json, os, re, subprocess, sys, time; sys.stderr.reconfigure(encoding="utf-8", errors="replace")
STATE, SEATS, MBOX, HERE, MODE = sys.argv[1:6]; ARGS = sys.argv[6:]
PEND, SENT = os.path.join(STATE, "critical-pending.jsonl"), os.path.join(STATE, "critical-sent.jsonl")
NOW, T0 = float(os.environ.get("FT_CRITICAL_NOW") or time.time()), time.monotonic()
try: DEDUPE, BUDGET = float(os.environ.get("FT_CRITICAL_DEDUPE_S") or 3600), min(7.0, float(os.environ.get("FT_CRITICAL_BUDGET_S") or 7))
except ValueError: DEDUPE, BUDGET = 3600.0, 7.0
PROG = re.compile(r"pane 작업 중|\(IDLE 아님\)|분 내 편집|jsonl 마지막 기록\(|미제출 입력|도구 셸 실행|미읽음 쪽지|doorbell \d+건 미전달|미커밋 (실작업물|변경|\d+줄)|실작업물 미커밋")   # A6 «진행» 사유 표(세션이 일하는 중) — 표에 없는 글 = 진행 아님(알린다)
CLOSE_NEXT = [(r"(세트:|- 착지:|증거 줄).*없", "그 나노에 정리 기록 차례(r1717 landed 명령) · 나노 없음이면 팀장"), (r"낡음|갈라짐", "원장 ref 를 맞춘 뒤 다시 닫기 — 팀 넘는 나노면 arch 판단")]
LAND_NEXT = [(r"동일승인 대조", "지금 head sha 로 다시 승인"), (r"충돌|non-FF|조상이 아님|포함하지 않음|최신화", "PR 가지를 main 위로 최신화 → 새 head sha 로 오빠께 다시 질문")]
warn = lambda m: print("WARN ft-critical-notify: " + m, file=sys.stderr)
key = lambda r: (r.get("tool"), r.get("target"), r.get("event")); sha12 = lambda s: hashlib.sha256(s.encode("utf-8")).hexdigest()[:12]

def load(p):
    try: raw = open(p, encoding="utf-8").read().split("\n")
    except OSError: return []
    rows = []
    for l in raw:
        try: r = json.loads(l)
        except ValueError: continue
        if isinstance(r, dict): rows.append(r)
    return rows

def save(p, rows):   # 임시→mv · 일반 파일(하드 룰 19)
    tmp = f"{p}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f: f.write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    os.replace(tmp, p)

class Lock:   # 로컬 파일을 고칠 때만 잡는다 — 발신 중에는 놓는다(부르는 쪽 마감 안에 pending 이 먼저 남게)
    def __enter__(self):
        os.makedirs(STATE, exist_ok=True)
        self.f = open(os.path.join(STATE, "critical.lock"), "w"); fcntl.flock(self.f, fcntl.LOCK_EX)
    def __exit__(self, *a): self.f.close()

def claimed(r):   # 다른 실행이 지금 보내는 중인 줄(그 프로세스가 살아 있고 30초 안) — 같은 줄 두 번 발신 0 · 죽은 실행의 표시는 무효(F1)
    c = r.get("claim") or {}
    try: pid, at = int(c.get("pid") or 0), float(c.get("at") or 0)
    except (TypeError, ValueError): return False
    if pid <= 0 or pid == os.getpid() or time.time() - at > 30: return False
    try: os.kill(pid, 0); return True
    except OSError: return False

def add(new):   # A2·A3 — 같은 미해결 열쇠가 DEDUPE 초 안 = 발신 0 · 아니면 발신 «앞» 에 pending 1줄
    with Lock():
        prior = [s for s in load(SENT) if key(s) == key(new) and not s.get("resolved")]
        if prior and DEDUPE > 0 and NOW - float(prior[-1].get("ts") or 0) < DEDUPE: return
        if prior: new["n"], new["first"] = int(prior[-1].get("n") or 1) + 1, prior[0].get("first")
        pend = load(PEND)
        if not any(key(p) == key(new) for p in pend): save(PEND, pend + [new])   # r1718-mut:pendfirst

def desk():
    try: v = json.load(open(os.path.join(SEATS, "seats-planner.json"), encoding="utf-8")).get("_desk")
    except (OSError, ValueError, AttributeError): v = ""
    return v.strip() if isinstance(v, str) else ""

def body(r):   # A1 — 700자 안 · 넘으면 «무엇» 뒤를 자르고 «외 <n>자»
    rep = f" (되풀이 {r['n']}회째 · 첫 알림 #{r.get('first') or '?'})" if int(r.get("n") or 1) > 1 else ""
    head, tail = f"[크리티컬] {r['tool']} {r['target']} — 무엇: ", f" · 어디: {r.get('where') or '-'} · 다음 손: {r['next']}{rep}"
    what, room = " ".join(str(r["what"]).split()), 700 - len(head) - len(tail)
    if len(what) > room: keep = max(0, room - 10); what = f"{what[:keep]} 외 {len(what) - keep}자"
    return head + what + tail

def send(to, r):   # → seq | None(실패 = WARN 1줄 · 재시도 0)
    left, who = BUDGET - (time.monotonic() - T0), f"{r['tool']} {r['target']}"
    if left < 1: warn(f"남은 시간 {max(left, 0.0):.1f}초 < 1초 — 발신 0 · pending 에 남김({who})"); return None
    try: p = subprocess.run(["bash", MBOX, "send", to, r["tool"], body(r)], capture_output=True, encoding="utf-8", errors="replace", timeout=left)
    except subprocess.TimeoutExpired: warn(f"mbox 발신 시간 초과({left:.1f}초) — pending 에 남김({who})"); return None
    except OSError as e: warn(f"mbox 실행 실패({e}) — pending 에 남김({who})"); return None
    if p.returncode != 0: warn(f"mbox 발신 실패 rc={p.returncode} — pending 에 남김({who})"); return None
    m = re.search(r"seq=(\d+)", p.stdout)
    return int(m.group(1)) if m else 0

def flush():   # A2 — 오래된 것부터 최대 3통 · 같은 열쇠 여러 줄 = 1통 · 발신에 성공한 것만 지운다(버림 0)
    with Lock():
        pend, batch = load(PEND), []
        for r in [r for r in pend if not claimed(r)]:
            if len(batch) < 3 and key(r) not in [key(b) for b in batch]: batch.append(r)
            if key(r) in [key(b) for b in batch]: r["claim"] = {"pid": os.getpid(), "at": time.time()}
        if batch: save(PEND, pend)
    if not batch: return
    to, done = desk(), []
    if not to: warn(f"seats-planner.json 에 _desk 칸 없음({SEATS}) — 발신 0 · pending 에 남김")
    for r in (batch if to else []):
        seq = send(to, r)
        if seq is None: break
        done.append({"tool": r["tool"], "target": r["target"], "event": r["event"], "ts": NOW, "seq": seq, "n": int(r.get("n") or 1), "first": r.get("first") or seq})
    with Lock():
        keep = [r for r in load(PEND) if key(r) not in [key(d) for d in done]]
        for r in keep:
            if (r.get("claim") or {}).get("pid") == os.getpid(): del r["claim"]
        save(PEND, keep)
        sent = load(SENT) + done
        while len(sent) > 200: sent.pop(next((n for n, s in enumerate(sent) if s.get("resolved")), 0))   # 200줄 넘으면 «해결» 된 앞 줄부터
        if done: save(SENT, sent)

def resolve(tool, target):   # A3 — 그 대상의 열쇠를 전부 닫는다(로컬 파일만 · 발신 0)
    if not os.path.isfile(SENT): return
    with Lock():
        sent = load(SENT); hit = [s for s in sent if (s.get("tool"), s.get("target")) == (tool, target) and not s.get("resolved")]
        for s in hit: s["resolved"] = NOW   # r1718-mut:resolved
        if hit: save(SENT, sent)

def notify(tool, target, event, what, nxt, where=""):
    add({"tool": tool, "target": target, "event": event, "what": what, "next": nxt, "where": where, "ts": NOW})
    flush()

def reasons(out):   # A5(R4) — 머리 줄 «REJECT <좌석>» 뒤 `  - ` 사유 줄 전부(이어진 들여쓴 줄 포함) · 한 줄 꼴 출구는 그 줄이 사유
    ls = out.split("\n"); i = next((n for n, l in enumerate(ls) if l.startswith("REJECT")), None)
    if i is None: return "", []
    rs = []
    for l in ls[i + 1:]:   # r1718-mut:allreasons
        if l.startswith("  - "): rs.append(l[4:])
        elif l.startswith("    ") and rs: rs[-1] += " " + l.strip()
        else: break
    return ls[i], rs or [ls[i][len("REJECT"):].strip()]

def nexts(table, texts, default):   # 사유마다 표를 찾아 겹치지 않게 잇는다
    out = []
    for t in texts:
        n = next((v for rx, v in table if re.search(rx, t)), default)
        if n not in out: out.append(n)
    return " · ".join(out)

def close_after(tool, args, out):   # A5·A5b·A6 — «진행» 사유만이면 발신 0 · 그 밖이 1개라도 있으면 진행 아닌 사유 전부
    seat = next((a for a in args if not a.startswith("--")), "")
    live = [r for r in reasons(out)[1] if not PROG.search(r)]   # r1718-mut:progfilter
    if not seat or not live: return
    idx = ""
    for f in sorted(os.listdir(SEATS)):
        try: row = json.load(open(os.path.join(SEATS, f), encoding="utf-8")).get(seat) if re.fullmatch(r"seats.*\.json", f) else None
        except (OSError, ValueError, AttributeError): row = None
        if isinstance(row, dict) and isinstance(row.get("index"), str): idx = idx or row["index"]
    rec, cause = os.path.join(HERE, "ft-nano-record.sh"), " / ".join(live)
    if tool == "ft-nano-close":   # A5b — r1717 거절 이력(없거나 실패 = WARN 1줄 · rc 불변)
        try: ok = os.path.isfile(rec) and subprocess.run(["bash", rec, "refused", "--seat", seat, "--cause", cause], capture_output=True, timeout=7).returncode == 0
        except (OSError, subprocess.TimeoutExpired): ok = False
        if not ok: warn(f"ft-nano-record.sh refused 없음·실패 — 거절 이력 0({seat})")
    stem = re.sub(r"\.md$", "", os.path.basename(idx)) or "-"
    notify(tool, seat, f"{stem}:{sha12(chr(10).join(live))}", cause, nexts(CLOSE_NEXT, live, "REJECT 원문대로"), idx or seat)

def land_after(args, out, ctx):   # A4 — rc 1 거절 전부 · 지문 = <PR head sha>:<REJECT 원문 전체 sha256 앞 12>(사유 분류는 다음 손 안내에만)
    opt = lambda k, d: next((args[n + 1] for n, a in enumerate(args[:-1]) if a == k), d)
    pr = next((a for n, a in enumerate(args) if a.isdigit() and (n == 0 or args[n - 1] not in ("--approve-sha", "--repo", "--remote", "--target"))), "?"); repo = opt("--repo", ".")
    try: url = subprocess.run(["git", "-C", repo, "remote", "get-url", opt("--remote", "origin")], capture_output=True, encoding="utf-8", errors="replace", timeout=7).stdout.strip()
    except (OSError, subprocess.TimeoutExpired): url = ""
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    slug = m.group(1) if m else re.sub(r"\.git$", "", os.path.basename(url or os.path.abspath(repo)))
    if out is None: return resolve("ft-merge-land", f"{slug} PR #{pr}")
    ls = out.split("\n"); i = next((n for n, l in enumerate(ls) if l.startswith("REJECT")), None)
    if i is None: return
    j = next((n for n in range(i, len(ls)) if ls[n].endswith("(착지 0)")), i)
    text = "\n".join(ls[i:j + 1])
    notify("ft-merge-land", f"{slug} PR #{pr}", f"{ctx or '-'}:{sha12(text)}", ls[i], nexts(LAND_NEXT, [text], "REJECT 원문대로 고친 뒤 다시 land"), f"{slug}#{pr}")   # r1718-mut:landevent

def after(tool, rc, d, args):   # --wrap 끝 — rc 1 = 알림 · rc 0 = 해결 · 그 밖(rc 2 usage·승인 없음 등) = 호출 0
    read = lambda n: open(os.path.join(d, n), encoding="utf-8", errors="replace").read() if os.path.isfile(os.path.join(d, n)) else ""
    if tool == "ft-merge-land": return land_after(args, read("out") if rc == "1" else None, read("ctx").strip())
    if rc == "0": return resolve(tool, next((a for a in args if not a.startswith("--")), ""))
    close_after(tool, args, read("out"))

try:
    if MODE == "--drain": flush()
    elif MODE == "--resolved" and len(ARGS) == 2: resolve(*ARGS)
    elif MODE == "after" and len(ARGS) >= 3: after(ARGS[0], ARGS[1], ARGS[2], ARGS[3:])
    else:
        o = {ARGS[n]: ARGS[n + 1] for n in range(1, len(ARGS) - 1, 2)}
        if len(ARGS) % 2 == 0 or MODE.startswith("--") or not {"--event", "--what", "--next"} <= set(o): sys.exit(2)
        notify(MODE, ARGS[0], o["--event"], o["--what"], o["--next"], o.get("--where", ""))
except Exception as e:   # 알림 실패는 부른 도구의 rc 를 바꾸지 않는다(하드 룰 20)
    warn(f"{type(e).__name__}: {e}")
PY
}
[ $# -ge 1 ] || usage
if [ "${FT_CRITICAL_OFF:-0}" = 1 ]; then [ "$1" = --wrap ] && [ $# -ge 3 ] && { shift 2; exec bash "$@"; }; exit 0; fi   # A9 — 호출 0 · 기록 0
if [ "$1" = --wrap ]; then   # A7 — 본 작업은 자식 1회(다시 돌리지 않는다) · rc·stdout·stderr 그대로
  [ $# -ge 3 ] || usage; TOOL="$2"; SCRIPT="$3"; shift 3
  D="$(mktemp -d "${TMPDIR:-/tmp}/ft-critical-XXXXXX" 2>/dev/null)" || { FT_CRITICAL_IN=$$ bash "$SCRIPT" "$@"; exit $?; }
  FT_CRITICAL_IN=$$ FT_CRITICAL_CTX="$D/ctx" bash "$SCRIPT" "$@" | tee "$D/out"; RC=${PIPESTATUS[0]}   # r1718-mut:stream
  case "$RC" in 0|1) core after "$TOOL" "$RC" "$D" "$@";; esac
  rm -rf "$D"; exit "$RC"
fi
core "$@"; rc=$?; [ "$rc" = 2 ] && usage; exit 0
