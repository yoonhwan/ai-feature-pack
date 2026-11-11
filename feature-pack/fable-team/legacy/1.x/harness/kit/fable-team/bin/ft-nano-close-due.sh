#!/usr/bin/env bash
# ft-nano-close-due.sh — r1360: «닫기 차례» 나노 좌석을 매번 사실에서 다시 계산해 1줄씩 낸다(읽기 전용 · 장부·알림·잠금 0 · 좌석을 닫는 길 0).
#   usage: ft-nano-close-due.sh [--team <팀>|--all] [--summary] [--why]      (기본 --all)
#   닫기 차례 = 아래 다섯을 «모두» 만족하는 나노 좌석(살아 있는 tmux 세션 · 명부 현역 role=nano · 옛 번호·_replaced_by·stop-ready 뺌):
#     ⓐ 완료 근거 = 그 좌석 카드 «## 상태» 절의 마지막 `세트: <40hex>` 가 지금 HEAD (A12·A14 판정 4096 — 리서치(이름 `-research#N`)·미착수(세트 줄 0)·
#        재개(마지막 `재개(--reopen)` 줄 뒤에 세트 줄 0)는 HEAD 조상 여부가 아니라 «이 근거 칸» 으로 가른다 · 카드 자리 = 명부 `_cards_wt` 체크아웃 아래 행의 `index`)
#     ⓑ HEAD 가 origin/main 의 조상(ff) ∨ origin/main 커밋 «끝줄» 이 정확히 «PR #<N> (head <HEAD 40hex>)»(squash · nano-close _lp_landed_gate 와 같은 꼴)
#     ⓒ `git status --porcelain` 0줄 ⓓ `ft-seat-status.sh turn <좌석>` STATE = IDLE · 워크트리 = 그 세션 pane 의 «지금» cwd(명부 cwd 칸에 기대지 않음)
#   출력: «닫기 차례 <좌석> 팀=<팀> 가지=<가지|detached> landed=<ff|squash> main=<짧은 sha> — bash ft-nano-close.sh <좌석> --landed-pr <N|-> --result <산출> --recv <seq>»
#         조회 실패(tmux·git·fetch·seat-status·카드 읽기 rc≠0 · 시간 상한) = «판정 불가 <좌석> <명령> rc=<n>» 1줄(목록에 안 넣음 · 하드 룰 20) · --why = «제외 <좌석> <사유>» 줄도 낸다
#         --summary = «닫기 차례 <팀>=<n> …» 1줄 · 판정 불가가 있는 팀은 «<팀>=<n>+판정불가<m>» 로 써서 정상 0석으로 안 보이게 한다(A23)
#   반환값(A23): 0 = 모든 좌석을 판정함 · 3 = 판정 불가 1건 이상(--summary 에도 같음) · 2 = usage
#   시간(A17): 좌석당 바깥 호출 4개(squash 확인 때 5) · 호출마다 7초 · 좌석마다 7초 상한(fetch 는 리포당 1회·7초+재시도 1) · 전체 FT_CLOSE_DUE_BUDGET 초(기본 70) 넘으면
#     남은 좌석 «판정 불가 <좌석> 시간 상한» 1줄씩 · 다음 --all 실행은 지난 회차 미조회 좌석부터(순서 이어받기 파일 1개 = <루트>/.fable-team/state/close-due-cursor.txt · 일반 파일 · 임시→mv).
#   env: FT_ROOT|FT_REPO_ROOT(루트) · FT_CLOSE_DUE_BUDGET · FT_CLOSE_DUE_SEAT_STATUS(좌석 상태 도구 경로 · 시험용) · FT_CLOSE_DUE_CLOCK_STEP(시험용 가짜 시계: 좌석 1개당 N초)
#   r1670 승인 갈래: `--approve-gate <좌석>` = 승인 갈래만 «다시» 계산한다(ft-nano-close.sh --approved 가 부른다 · env 무관). 조건 = 카드 «DA 판정:» 경로의 판정문 첫 `판정:` 값이 APPROVE(r1664 값 규칙) ∧ 그 판정문의 «승인 sha: <40hex>» 줄이 지금 HEAD 와 정확히 같음(본문 언급만으로는 승인 0 · DA astra #284785 ①) ∧ 마지막 «인수:» sha = HEAD ∧ 세트·인수 줄 «뒤» 에 HOLD·보정 요청·재개(--reopen) 0 ∧ HEAD 가 origin 원격 가지에 있음(remote-tracking ref).
#     출력 `APPROVE-OK <좌석> set=<HEAD> verdict=<경로>` rc 0 · 거짓 = `APPROVE-REJECT <좌석> <사유>` rc 1 · 조회 실패 = `판정 불가 …` rc 3 · usage 2.
#   env FT_NANO_AUTO_CLOSE=1 일 때만 «승인 갈래» 를 닫기 차례 목록에 넣는다(기본 0 = 지금 출력 그대로 · r1670 ⓔ) · ⓕ 닫기 금지(도구 셸 실행 · pane 작업 중 · 미제출 입력)는 AUTO=1 목록과 `--approve-gate` 직접 재계산 **둘 다**에 건다(DA astra #284785 ②)(시험 스텁 FT_CLOSE_DUE_QUIET: 첫 줄 `OK` 또는 `BUSY <사유>`).
#   바꾸는 것 0: 명부·refs/heads·워크트리·tmux 그대로(remote-tracking origin/main 만 fetch 로 움직인다) · 순서 파일 외 쓰기 0.
set -uo pipefail
FT_CLOSE_DUE_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; export FT_CLOSE_DUE_HERE
exec python3 - "$@" <<'PY'
import json, os, re, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, os.environ["FT_CLOSE_DUE_HERE"])
from ft_team_lib import rosters, repo_root, TeamPathError

HERE = os.environ["FT_CLOSE_DUE_HERE"]
args = sys.argv[1:]
team_only, summary, why, gate, i = None, False, False, "", 0
USAGE = "usage: ft-nano-close-due.sh [--team <팀>|--all] [--summary] [--why] | --approve-gate <좌석>"
while i < len(args):
    a = args[i]
    if a == "--all": team_only = None
    elif a == "--summary": summary = True
    elif a == "--why": why = True
    elif a == "--approve-gate" and i + 1 < len(args): gate = args[i + 1]; i += 1
    elif a == "--team" and i + 1 < len(args): team_only = args[i + 1]; i += 1
    else: print(USAGE, file=sys.stderr); sys.exit(2)
    i += 1
if gate and (summary or why or team_only): print(USAGE, file=sys.stderr); sys.exit(2)
AUTO = os.environ.get("FT_NANO_AUTO_CLOSE") == "1"   # r1670 — 승인 갈래·ⓕ 닫기 금지를 목록에 넣는다(기본 0 = 지금 출력 그대로)
GATE = bool(gate)
try: BUDGET = float(os.environ.get("FT_CLOSE_DUE_BUDGET") or 70)
except ValueError: BUDGET = 70.0
STEP = os.environ.get("FT_CLOSE_DUE_CLOCK_STEP")
_fake = [0.0]
def now():   # 전체 예산 시계 — 시험은 좌석 1개당 STEP 초씩 가는 가짜 시계(고정 sleep 0)
    if STEP:
        _fake[0] += float(STEP); return _fake[0]
    return time.monotonic()
SEAT_STATUS = os.environ.get("FT_CLOSE_DUE_SEAT_STATUS") or HERE + "/ft-seat-status.sh"
env = {**os.environ, "LC_ALL": "C"}
lines, unk, exc = [], {}, []   # 출력 줄 · 팀별 판정 불가 수 · 제외 줄


def run(cmd, cap=7.0):   # → (rc, stdout, 이유) · 시간 초과·실행 불가 = rc None
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=max(0.5, cap), env=env)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired: return None, "", "시간 초과"
    except OSError as e: return None, "", str(e)


class Unjudged(Exception): pass


def need(cmd, cap, what, ok=(0,)):
    rc, out, err = run(cmd, cap)
    if rc is None or rc not in ok: raise Unjudged(f"{what} rc={'-' if rc is None else rc}")
    return rc, out


try: root = Path(os.environ.get("FT_ROOT") or os.environ.get("FT_REPO_ROOT") or repo_root())
except (TeamPathError, subprocess.SubprocessError, OSError) as e:
    print(f"판정 불가 루트 {str(e)[:120]} rc=1"); sys.exit(3)
try: rows = rosters(root)
except (TeamPathError, OSError) as e:
    print(f"판정 불가 팀 명단 {str(e)[:120]} rc=1"); sys.exit(3)
cursor_f = Path(os.environ.get("FT_CLOSE_DUE_CURSOR") or root / ".fable-team" / "state" / "close-due-cursor.txt")
counts = {}
cands = []   # (팀, 좌석, 행, 카드 자리)
for r in rows:
    t = r["team"]
    if team_only and t != team_only: continue
    counts[t] = 0
    if r["doc"] is None:
        lines.append(f"판정 불가 팀={t} 명부 {r['diag']} rc=1"); unk[t] = unk.get(t, 0) + 1; continue
    doc = r["doc"]
    nanos = {k: v for k, v in doc.items() if not k.startswith("_") and isinstance(v, dict) and v.get("role") == "nano" and not v.get("_replaced_by")}
    top = {}   # 같은 이름 줄기의 가장 큰 번호만(옛 번호 뺌)
    for k in nanos:
        b, _, n = k.rpartition("#")
        if n.isdigit() and int(n) > top.get(b, -1): top[b] = int(n)
    wt = doc.get("_cards_wt")
    for k, v in sorted(nanos.items()):
        b, _, n = k.rpartition("#")
        if n.isdigit() and int(n) < top.get(b, -1): continue
        cands.append((t, k, v, [root / ".worktrees" / wt if wt else root, root]))
if team_only and team_only not in counts:
    lines.append(f"판정 불가 팀={team_only} 명단 밖 rc=1"); counts[team_only] = 0; unk[team_only] = 1
rc_t, live_out, live_err = run(["tmux", "list-sessions", "-F", "#{session_name}"])
if rc_t is None or (rc_t != 0 and "no server running" not in live_err): live = None
else: live = set(live_out.split("\n")) if rc_t == 0 else set()
if cands and live is None:
    for t, k, _, _ in cands: lines.append(f"판정 불가 {k} tmux list-sessions rc={rc_t if rc_t is not None else '-'}"); unk[t] = unk.get(t, 0) + 1
    cands = []
cands = [c for c in cands if c[1] in live]
if team_only is None and cursor_f.is_file():   # A17 이어받기 — 지난 회차 첫 미조회 좌석부터
    try: cur = cursor_f.read_text(encoding="utf-8").strip()
    except OSError: cur = ""
    names = [c[1] for c in cands]
    if cur in names: j = names.index(cur); cands = cands[j:] + cands[:j]
fetched = {}   # 리포(.git 위치) → None(성공) | 이유


def repo_key(cwd):   # 프로세스 0 — cwd 에서 위로 올라가며 .git(파일=워크트리 · 폴더) 을 찾아 공용 git 폴더를 키로
    p = Path(cwd)
    for d in [p, *p.parents]:
        g = d / ".git"
        if g.is_dir(): return str(g), str(d)
        if g.is_file():
            m = re.match(r"gitdir:\s*(.+)", g.read_text(encoding="utf-8").strip())
            if m:
                gd = Path(m.group(1)) if os.path.isabs(m.group(1)) else d / m.group(1)
                cd = gd.parent.parent if gd.parent.name == "worktrees" else gd
                return str(cd), str(d)
    return None, None


def fetch_once(key, top):
    if key not in fetched:
        why_ = None
        for _ in range(2):   # 7초 + 재시도 1
            rc, _o, _e = run(["git", "-C", top, "fetch", "-q", "--no-write-fetch-head", "origin", "+refs/heads/main:refs/remotes/origin/main"])
            why_ = None if rc == 0 else f"git fetch origin main rc={'-' if rc is None else rc}"
            if why_ is None: break
        fetched[key] = why_
    if fetched[key]: raise Unjudged(fetched[key])


CARD_REFS = {}


def card_ref(team):   # r1649: ft_card_ref 와 같은 규칙 — env(FT_CARD_REF) → 카드 루트 표(state/directive-roots.tsv) 팀·«*» 행 → origin/main · fetch 7초+재시도 1
    if team not in CARD_REFS:
        ref, why = (os.environ.get("FT_CARD_REF") or "").strip(), ""
        if not ref:
            try: tab = [l.split("\t") for l in (root / ".fable-team/state/directive-roots.tsv").read_text(encoding="utf-8").split("\n")]
            except OSError: tab = []
            hit = [c for c in tab if len(c) > 2 and c[0] == team] or [c for c in tab if len(c) > 2 and c[0] == "*"]
            ref = (hit[0][2].strip() if hit else "") or "origin/main"
        if "/" in ref and run(["git", "-C", str(root), "rev-parse", "--git-dir"])[0] == 0:   # 리포 아닌 루트 = ref 없음(그때는 지금처럼 워크트리 후보)
            rem, br = ref.split("/", 1)
            for _ in range(2):   # 7초 + 재시도 1
                rc, _o, _e = run(["git", "-C", str(root), "fetch", "-q", "--no-write-fetch-head", rem, f"+refs/heads/{br}:refs/remotes/{ref}"])
                why = "" if rc == 0 else f"카드 ref fetch 실패 {ref} rc={'-' if rc is None else rc}"
                if not why: break
        CARD_REFS[team] = (ref, why)
    ref, why = CARD_REFS[team]
    if why: raise Unjudged(why)   # r1649-mut:reffetch — 둘째 실패면 그 좌석은 판정 불가: 낡은 워크트리 카드로 «완료 근거» 를 만들지 않는다
    return ref


def card_text(card_dirs, idx, team):   # r1649: 카드 본문 — ref 판 먼저, 없으면 지금 후보(워크트리)
    cm = re.match(r"^(?:.*/)?(design/(?:teams/[^/]+|[^/]+)/indices)/[^/]+/([^/]+)$", idx or "")   # r1649-mut:cardref
    if cm:   # ref(FT_CARD_REF → 카드 루트 표 → origin/main) 의 진행·완성·대기 판부터 — 뒤처진 카드 워크트리에서 «카드 파일 없음» 0
        ref = card_ref(team)
        for stage in ("진행", "완성", "대기"):
            rc, out, _e = run(["git", "-C", str(root), "show", f"{ref}:{cm.group(1)}/{stage}/{cm.group(2)}"])
            if rc == 0: return out
    for d in card_dirs:
        f = d / idx
        if f.is_file():
            try: return f.read_text(encoding="utf-8")
            except (OSError, UnicodeError): raise Unjudged("카드 읽기 rc=1")
    return None


def basis(card_dirs, idx, team=""):   # 카드 «## 상태» 절 → (마지막 세트 sha|None, 사유, 절 줄들)
    if not idx: return None, "카드 index 칸 없음(근거 0)", []
    raw = card_text(card_dirs, idx, team)
    if raw is None: return None, "카드 파일 없음(근거 0)", []
    txt = raw.split("\n")
    st = next((n for n, l in enumerate(txt) if l.startswith("## 상태")), None)
    if st is None: return None, "카드 상태 절 없음(근거 0)", []
    sec = []
    for l in txt[st + 1:]:
        if l.startswith("## "): break
        sec.append(l)
    sets = [(n, m.group(1)) for n, l in enumerate(sec) for m in [re.search(r"세트:\s*([0-9a-f]{40})", l)] if m]
    reop = [n for n, l in enumerate(sec) if "재개(--reopen)" in l]
    if not sets: return None, "세트 줄 없음(미착수·리서치)", sec
    if reop and reop[-1] > sets[-1][0]: return None, "재개 뒤 세트 줄 없음(A12)", sec
    return sets[-1][1], "", sec


# ── r1670 승인 갈래 — 카드의 DA 판정·인수 줄과 판정문으로 «착지 없이» 닫을 수 있는지 본다 ─────────────────
SET_RE = re.compile(r"세트:\s*([0-9a-f]{40})")
ACC_RE = re.compile(r"인수:\s*([0-9a-f]{40})")
DA_LINE = re.compile(r"DA\s*판정\s*[:：]\s*(\S+)")
VERDICT_LINE = re.compile(r"^\s*(?:#+[^:：]*|[-*]\s*)?판정\s*[:：]\s*(.*)$")
APPROVE_VAL = re.compile(r"^APPROVE(?![A-Za-z])(?:\s*(?:—|–|-|\()(?:.*))?$")   # r1664 값 규칙: APPROVE · «APPROVE — …» · «APPROVE (…)»
APPROVE_SHA = re.compile(r"^\s*(?:[-*]\s*)?승인\s*sha\s*[:：]\s*([0-9a-f]{40})\s*$")   # 판정문의 «명시 승인 SHA» 줄 — 본문의 sha 언급은 승인 근거가 아니다(DA astra #284785 ①)
POST_BAD = re.compile(r"HOLD|보정\s*요청|재개\s*\(--reopen\)")   # 세트·인수 줄 «뒤» 에 있으면 승인 효력 0


def approve_ok(sec, head, root):   # 승인 갈래(ⓑ) → (True, 판정문 경로) | (False, 사유) · 조회 실패 = Unjudged
    da = next((m.group(1) for l in sec for m in [DA_LINE.search(l)] if m), "")
    if not da: return False, "카드에 «DA 판정:» 줄 없음"
    vp = da.split("#§")[0].strip()
    p = Path(vp) if os.path.isabs(vp) else Path(root) / vp
    try: vt = p.read_text(encoding="utf-8")
    except (OSError, UnicodeError): raise Unjudged(f"DA 판정문 읽기 rc=1 ({vp})")
    m = next((m for l in vt.split("\n") for m in [VERDICT_LINE.match(l)] if m), None)
    if m is None: return False, "DA 판정문에 «판정:» 줄 없음"
    val = m.group(1).strip().strip("*`_ ")
    if not APPROVE_VAL.match(val): return False, f"DA 판정 값이 APPROVE 아님(«{val[:40]}»)"
    shas = {m.group(1) for l in vt.split("\n") for m in [APPROVE_SHA.match(l)] if m}
    if len(shas) != 1: return False, f"DA 판정문의 «승인 sha:» 줄이 {len(shas)}개(정확히 1개여야 한다)"
    if shas.pop() != head: return False, f"DA 판정문의 승인 sha ≠ HEAD {head[:9]}(본문 언급만으로는 승인 0)"
    acc = [n for n, l in enumerate(sec) if ACC_RE.search(l)]
    if not acc: return False, "카드에 «인수:» 줄 없음"
    a_sha = ACC_RE.search(sec[acc[-1]]).group(1)
    if a_sha != head: return False, f"인수 {a_sha[:9]} ≠ HEAD {head[:9]}"
    sets = [n for n, l in enumerate(sec) if SET_RE.search(l)]
    after = sec[max(acc[-1], sets[-1]) + 1:]
    badl = next((l for l in after if POST_BAD.search(l)), "")
    if badl: return False, f"인수 뒤 «{badl.strip()[:40]}» 줄 — 닫지 않는다"
    return True, str(p)


def on_remote(cwd, br, head, cap):   # HEAD 가 origin 원격 가지에 있음(remote-tracking ref · 추가 fetch 0)
    if br in (None, "(detached)"): return False
    _, tip = need(["git", "-C", cwd, "rev-parse", "--verify", "refs/remotes/origin/" + br + "^{commit}"], cap(), "git rev-parse origin 가지", ok=(0, 128))
    tip = tip.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", tip): return False
    rc, _ = need(["git", "-C", cwd, "merge-base", "--is-ancestor", head, tip], cap(), "git merge-base", ok=(0, 1))
    return rc == 0


def last_sent(seat):   # 좌석의 마지막 발신 seq + 본문 파일 — ② recv·① result 값(읽기만 · 큰 파일은 끝 4MB)
    best, body = 0, ""
    for p in (root / ".fable-team" / "comm" / "mailbox.jsonl", root / ".fable-team" / "comm" / "mailbox.log.jsonl"):
        try:
            with open(p, "rb") as fh:
                off = max(0, fh.seek(0, os.SEEK_END) - (4 << 20)); fh.seek(off); raw = fh.read()
        except OSError: continue
        for line in raw.decode("utf-8", "replace").splitlines()[1 if off else 0:]:
            try: r = json.loads(line); seq = int(r.get("seq") or 0)
            except (ValueError, TypeError, AttributeError): continue
            if r.get("from") != seat or seq <= best: continue
            best = seq; body = str(r.get("body") or "")
    f = root / ".fable-team" / "comm" / "bodies" / f"{best}.txt"
    return best, (str(f) if best and f.is_file() else "")


SHELL_EXE = {"zsh", "bash", "sh", "fish"}
BUSY_RE = re.compile(r"esc to interrupt|Working|Thinking|Crunched|Crunching")   # ft-acct-pause.sh 와 같은 꼴
DRAFT_RE = re.compile(r"^[›❯] +[^ ]")   # ft-acct-pause.sh UNSUBMITTED 와 같은 꼴


def quiet(k, cap):   # ⓕ 닫기 금지 → (True, "") | (False, 사유) · 조회 실패 = Unjudged
    stub = (os.environ.get("FT_CLOSE_DUE_QUIET") or "").strip()
    if stub:
        rc, out, _e = run(["bash", stub, k], cap())
        if rc != 0: raise Unjudged(f"조용함 조회 rc={'-' if rc is None else rc}")
        first = (out.strip().split("\n") or [""])[0]
        return (True, "") if first.startswith("OK") else (False, (first[4:].strip() or "조용하지 않음")[:40])
    _, out = need(["tmux", "list-panes", "-t", "=" + k + ":", "-F", "#{pane_pid}"], cap(), "tmux list-panes")
    pid = (out.split() or [""])[0]
    if not pid.isdigit(): raise Unjudged("tmux pane_pid rc=1")
    _, pso = need(["ps", "-A", "-o", "pid=,ppid=,args="], cap(), "ps")
    kids, seen, todo = {}, set(), [int(pid)]
    for ln in pso.splitlines():
        a = ln.split(None, 2)
        if len(a) == 3 and a[0].isdigit() and a[1].isdigit(): kids.setdefault(int(a[1]), []).append((int(a[0]), a[2]))
    while todo:
        for c, cmd in kids.get(todo.pop(), []):
            if c in seen: continue
            seen.add(c); todo.append(c)
            toks = cmd.split()
            if toks and os.path.basename(toks[0]).lstrip("-") in SHELL_EXE and " -c " in " " + cmd + " ": return False, "도구 셸 실행"
    _, pane = need(["tmux", "capture-pane", "-p", "-t", "=" + k + ":"], cap(), "tmux capture-pane")
    tail = [l for l in pane.splitlines() if l.strip()][-14:]
    if any(DRAFT_RE.match(l) for l in tail): return False, "미제출 입력"
    if any(BUSY_RE.search(l) for l in tail): return False, "pane 작업 중"
    return True, ""


def judge(t, k, row, card_dirs):   # → 줄 | None(제외 · exc 에 사유) · 조회 실패 = Unjudged
    seat_t0 = time.monotonic()
    cap = lambda: 7.0 - (time.monotonic() - seat_t0)
    def chk():
        if cap() <= 0: raise Unjudged("좌석 7초 상한 rc=-")
    if "-research#" in k: exc.append(f"제외 {k} 리서치 좌석(자기 근거 칸 = --research 닫기)"); return None
    sha_card, why_, sec = basis(card_dirs, row.get("index") or "", t)
    if sha_card is None: exc.append(f"제외 {k} {why_}"); return None
    _, out = need(["tmux", "display-message", "-p", "-t", "=" + k + ":", "#{pane_current_path}"], cap(), "tmux display-message")
    cwd = out.strip()
    if not cwd or not os.path.isdir(cwd): raise Unjudged("tmux pane cwd rc=1")
    chk()
    _, out = need(["git", "-C", cwd, "status", "--porcelain=v2", "--branch"], cap(), "git status")
    head = br = None; dirty = 0
    for l in out.split("\n"):
        if l.startswith("# branch.oid "): head = l.split()[2]
        elif l.startswith("# branch.head "): br = l.split(" ", 2)[2]
        elif l and not l.startswith("#") and not l.rstrip().endswith((".serena/project.yml", ".serena/")): dirty += 1   # r1670 ⓕ: 잡음(.serena/project.yml · 폴더로 접힌 .serena/)은 미커밋으로 안 센다
    if not head or not re.fullmatch(r"[0-9a-f]{40}", head): raise Unjudged("git status HEAD rc=1")
    if dirty: exc.append(f"제외 {k} 미커밋 {dirty}줄"); return None
    if sha_card != head: exc.append(f"제외 {k} 세트 {sha_card[:9]} ≠ HEAD {head[:9]}"); return None
    if AUTO or GATE:   # ⓕ 닫기 금지 — 목록(AUTO=1)과 직접 재계산(GATE) 공통 · 둘 다 아닐 때만 지금 그대로
        ok_q, why_q = quiet(k, cap)
        if not ok_q: exc.append(f"제외 {k} {why_q}"); return None
        chk()
    key, top = repo_key(cwd)
    if key is None: raise Unjudged("git 리포 찾기 rc=1")
    fetch_once(key, top)
    chk()
    rc, _ = need(["git", "-C", cwd, "merge-base", "--is-ancestor", head, "refs/remotes/origin/main"], cap(), "git merge-base", ok=(0, 1))
    landed, main_sha, pr = ("ff", None, "-") if rc == 0 else (None, None, "-")
    if rc == 0:
        _, o2 = need(["git", "-C", cwd, "rev-parse", "--short=9", "refs/remotes/origin/main"], cap(), "git rev-parse"); main_sha = o2.strip()
    else:
        chk()
        _, o2 = need(["git", "-C", cwd, "log", "-n", "20", "--fixed-strings", f"--grep=(head {head})", "--format=%h%x1f%B%x1e", "refs/remotes/origin/main"], cap(), "git log")
        for rec in o2.split("\x1e"):
            h, _, body = rec.strip("\n").partition("\x1f")
            ls = [x for x in body.split("\n") if x.strip()]
            if ls and ls[-1].startswith("main 자동 병합"): ls = ls[:-1]   # r1169 docam 꼬리 1줄
            m = re.fullmatch(r"PR #(\d+) \(head " + head + r"\)", ls[-1].strip()) if ls else None
            if m: landed, main_sha, pr = "squash", h, m.group(1); break
        if landed is None and (AUTO or GATE):   # r1670 승인 갈래 — 착지 없이 DA APPROVE·인수·원격 보존이 다 서면 닫기 차례
            chk(); _, _so = need([SEAT_STATUS, "turn", k], cap(), "ft-seat-status turn"); _st = (_so.split() or [""])[0]
            if _st != "IDLE": exc.append(f"제외 {k} 상태 {_st or '-'} (IDLE 아님)"); return None   # ⓑ·ⓕ: 승인 갈래도 «지금 IDLE» 일 때만
            ok_a, info = approve_ok(sec, head, str(root))
            if ok_a: chk(); ok_a, info = (True, info) if on_remote(cwd, br, head, cap) else (False, "HEAD 가 origin 원격 가지에 없음")
            seq, body = 0, ""
            if ok_a:
                seq, body = last_sent(k)
                if not body: ok_a, info = False, "좌석 보고 본문 없음(①·② 값 0)"
            if ok_a:
                chk(); _, msha = need(["git", "-C", cwd, "rev-parse", "--short=9", "refs/remotes/origin/main"], cap(), "git rev-parse")
                return (f"닫기 차례 {k} 팀={t} 갈래=승인 set={head} main={msha.strip()}"
                        f" — bash ft-nano-close.sh {k} --approved {info} --result {body} --recv {seq}")
            exc.append(f"제외 {k} {info}"); return None
        if landed is None: exc.append(f"제외 {k} main 에 산출 없음(ff 0 · squash 끝줄 0)"); return None
    chk()
    _, out = need([SEAT_STATUS, "turn", k], cap(), "ft-seat-status turn")
    st = (out.split() or [""])[0]
    if st != "IDLE": exc.append(f"제외 {k} 상태 {st or '-'} (IDLE 아님)"); return None
    return (f"닫기 차례 {k} 팀={t} 가지={'detached' if br in (None, '(detached)') else br} landed={landed} main={main_sha}"
            f" — bash ft-nano-close.sh {k} --landed-pr {pr} --result <산출> --recv <seq>")


def gate_mode(seat):   # --approve-gate — 승인 갈래를 «지금 사실» 로 다시 계산(목록 판정과 같은 judge 한 곳 · 추측 0)
    for r in rows:
        doc = r["doc"]
        if not isinstance(doc, dict) or seat not in doc: continue
        wt = doc.get("_cards_wt")
        exc.clear(); lines.clear()
        try: ln = judge(r["team"], seat, doc[seat], [root / ".worktrees" / wt if wt else root, root])
        except Unjudged as e: print(f"판정 불가 {seat} {e}"); return 3
        if ln and "갈래=승인" in ln:
            m = re.search(r"--approved (\S+)", ln); vp = m.group(1) if m else ""
            want = (os.environ.get("FT_APPROVE_VERDICT") or "").strip()
            if want and os.path.realpath(want) != os.path.realpath(vp):
                print(f"APPROVE-REJECT {seat} --approved 경로가 카드 «DA 판정:» 경로와 다름(«{want}» ≠ «{vp}»)"); return 1
            sh = re.search(r"set=([0-9a-f]{40})", ln)
            print(f"APPROVE-OK {seat} set={sh.group(1) if sh else '-'} verdict={vp}"); return 0
        pre = f"제외 {seat} "
        why_ = (exc[-1][len(pre):] if exc[-1].startswith(pre) else exc[-1]) if exc else (ln or "승인 갈래 아님")
        print(f"APPROVE-REJECT {seat} {why_}"); return 1
    print(f"APPROVE-REJECT {seat} 명부에 없음"); return 1


if gate: sys.exit(gate_mode(gate))   # 승인 갈래 단독 길 — 아래 목록 순회 안 돈다
t0 = now(); cut = None
for n, (t, k, row, cdirs) in enumerate(cands):
    if cut is None and now() - t0 > BUDGET: cut = k
    if cut is not None:
        lines.append(f"판정 불가 {k} 시간 상한 rc=-"); unk[t] = unk.get(t, 0) + 1; continue
    try: ln = judge(t, k, row, cdirs)
    except Unjudged as e: lines.append(f"판정 불가 {k} {e}"); unk[t] = unk.get(t, 0) + 1; continue
    if ln: lines.append(ln); counts[t] += 1
if team_only is None:   # 순서 파일 — 시간 상한에 걸렸을 때만 «첫 미조회 좌석» 을 적고 다 돌았으면 비운다(없으면 만들지 않는다)
    want = cut if cut is not None else ("" if cursor_f.is_file() else None)
    if want is not None:
        tmp = cursor_f.with_name(cursor_f.name + ".tmp-" + str(os.getpid()))
        try: cursor_f.parent.mkdir(parents=True, exist_ok=True); tmp.write_text(want + "\n", encoding="utf-8"); os.replace(tmp, cursor_f)
        except OSError as e: lines.append(f"판정 불가 순서파일 쓰기 {str(e)[:80]} rc=1"); unk["-"] = unk.get("-", 0) + 1
if summary:
    print("닫기 차례 " + " ".join(f"{t}={c}" + (f"+판정불가{unk[t]}" if unk.get(t) else "") for t, c in sorted(counts.items())) + (f" · 판정불가 순서파일={unk['-']}" if unk.get("-") else ""))
else:
    for ln in lines + (exc if why else []): print(ln)
sys.exit(3 if any(unk.values()) else 0)
PY
