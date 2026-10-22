#!/bin/bash
# ft-idle-slot-fill — 대기 카드가 있는데 «빈 석을 아무도 안 채우는» 팀을 채운다 (r667 · 원인 표 design/harness/CAUSE-idle-teams-and-stale-goal-table-20261021.md 행 1-1~1-5)
#   왜: ft-nano-slots 는 «출력만» · ft-idle-wake 는 «안 읽은 쪽지 있는 좌석» 만 깨운다 → planner 승인·[착지 차례]를 기다리는 팀장은 빈 석을 쥔 채 멈춘다(끝 = «카드 다 끝남 → 대기» 하나).
#   1단계(쪽지): 팀장 IDLE ≥ FT_IDLE_SLOT_SEC(600) ∧ 그 팀 나노 < 한도 ∧ 후보 ≥1 → 팀장에 «[빈 석] 후보 N · 카드 이름 · 착지 차례 대기 = 그 PR 만 대기, 다른 카드는 띄움» 1통(mbox send = 도어벨 포함 · ring 중복 0)
#   2단계(자동 spawn): 쪽지 뒤 FT_IDLE_SLOT_AUTO_SEC(900) 지나도 팀장 IDLE ∧ 같은 후보 집합 → 맨 위 1장을 그 팀 env 서브셸에서 ft-nano-spawn.sh --from <팀장> 로 띄우고(«비동기» — 결과는 다음 틱에 회수해 쪽지) · 한 틱 1장 · 실패면 spawn 원문 쪽지(조용한 실패 0)
#   ★2단계는 «기본 꺼짐»(범위 축소 · master 139846 · 재설계 = 새 카드 r721)★ — 켜려면 FT_IDLE_SLOT_AUTO=1 을 «명시»해야 하고 그때 로그에 «ERROR … r721 전까지 미검증» 1줄이 남는다. 1단계(쪽지)는 기본으로 돈다.
#   팀장 = 그 팀 명부(`seats-<팀>.json` · v65 = `seats.json`)의 `_master` 한 명 — 이름 형식(byz-<팀>-master-<에이전트>#N)·라이브(tmux)·현역을 대조하고, 어긋나면 그 팀 0.
#   0 조건: 전팀 정지(ft-all-stop.sh check rc≠0) · RESOURCE_FREEZE 표식 · 오빠가 그 화면에서 치는 중(client_activity · 송신·spawn 직전 재확인) · 팀 env 파일 없음 · FT_IDLE_SLOT_AUTO≠1(2단계만 끔 · 기본값 = 꺼짐) · 후보 계산 실패·명부 못 읽음 = 0 + 로그 1줄
#   DA⑥ r1 처방(G1~G8): G1 카드당 1회는 spawn «전» 선점(claimed) · 상태 파일 없음/손상 = 0 + 로그(첫 실행 표식 `idle-slot.seen`) — 재spawn 0 · G2 쪽지 억제는 (팀, 후보 집합)별 마지막 «성공» 송신 시각 맵 · G3 송신 rc≠0 이면 note_at 저장 0 · 자동 spawn 0(fail-closed · 다음 틱 재시도) · G4 송신·spawn 직전 client_activity 재확인 · G5 후보 계산도 그 팀 env 서브셸(부모 FT_INDEX_DIR 제거) + 반환 team·index_dir·카드 소속 대조 · G6 팀장 = 명부 `_master` 대조 · G7 spawn 비동기 + 한 실행 총 마감 FT_IDLE_SLOT_BUDGET_SEC(70)초
#   억제: 같은 (팀, 후보 집합) 쪽지 FT_IDLE_SLOT_NOTE_SEC(1800) 1회 · 자동 spawn 은 카드당 1회(재시도 = 사람). 상태 = state/idle-slot.json
#   환경: FT_ROOT · FT_MBOX · FT_SEAT_STATUS · FT_TMUX · FT_SEATS_JSON(v65 명부) · FT_IDLE_WAKE_NOW(시험 시계) · FT_IDLE_SLOT_LOG · FT_IDLE_SLOT_BUDGET_SEC. 실패는 로그만 — 깨우기(ring)를 되돌리지 않는다.
set +e
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${FT_ROOT:-}" ]; then
  FT_ROOT="$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE")"   # r385b: 옛 설치 꼴 · cwd 리포 공용 루트
  [ -n "$FT_ROOT" ] || { echo "ft-idle-slot-fill: 루트를 못 찾음" >&2; exit 1; }
fi
export FT_ROOT HERE
python3 - <<'PYEOF'
import datetime as dt, fcntl, hashlib, json, os, re, shlex, subprocess, sys, time

ROOT, HERE = os.environ["FT_ROOT"], os.environ["HERE"]
FTD = os.path.join(ROOT, ".fable-team")
COMM, STATE_DIR = os.path.join(FTD, "comm"), os.path.join(FTD, "state")
STATE = os.path.join(STATE_DIR, "idle-slot.json")
MARK = os.path.join(STATE_DIR, "idle-slot.seen")   # G1: «첫 실행 표식» — 상태 파일이 «사라진» 것과 «처음»을 가른다
LOG = os.environ.get("FT_IDLE_SLOT_LOG") or os.path.join(STATE_DIR, "idle-slot.log")
MBOX = os.environ.get("FT_MBOX") or os.path.join(COMM, "mbox.sh")
STATUS = os.environ.get("FT_SEAT_STATUS") or os.path.join(HERE, "ft-seat-status.sh")
SPAWN = os.environ.get("FT_NANO_SPAWN_SH") or os.path.join(HERE, "ft-nano-spawn.sh")
SLOTS = os.environ.get("FT_NANO_SLOTS_SH") or os.path.join(HERE, "ft-nano-slots.sh")
ALLSTOP = os.environ.get("FT_ALL_STOP_SH") or os.path.join(HERE, "ft-all-stop.sh")
SEATS = os.environ.get("FT_SEATS_JSON") or os.path.join(FTD, "seats.json")   # v65 명부(팀 명부 = seats-<팀>.json)
TMUX = shlex.split(os.environ.get("FT_TMUX") or "tmux")
CLIENT_SEC, SLOT_SEC, AUTO_SEC, NOTE_SEC, BUDGET_SEC, SPAWN_MAX = (int(os.environ.get(k) or d) for k, d in (
    ("FT_IDLE_CLIENT_SEC", 120), ("FT_IDLE_SLOT_SEC", 600), ("FT_IDLE_SLOT_AUTO_SEC", 900),
    ("FT_IDLE_SLOT_NOTE_SEC", 1800), ("FT_IDLE_SLOT_BUDGET_SEC", 70), ("FT_IDLE_SLOT_SPAWN_MAX_SEC", 1800)))
AUTO_ON = os.environ.get("FT_IDLE_SLOT_AUTO") == "1"   # ★기본 꺼짐(r667 범위 축소 · 2단계 재설계 = r721) — 켜기는 명시 1 뿐이다
NOW = float(os.environ.get("FT_IDLE_WAKE_NOW") or time.time())
END = time.monotonic() + BUDGET_SEC   # G7: 한 실행 총 마감 — 남은 시간보다 긴 조회는 하지 않는다
DEAD = ("stop-ready", "stopped", "stop")

def log(msg):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(NOW)) + f" ft-idle-slot-fill: {msg}\n")

def left():
    return END - time.monotonic()

class _R:   # 조회 실패·시간 초과를 «값»으로 — 한 번의 느린 호출이 회차 전체를 죽이지 않는다
    returncode, stdout, stderr = 1, "", ""

def run(argv, t=30):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=max(1.0, min(t, left())))
    except (subprocess.SubprocessError, OSError):
        return _R()

def roster_path(team):
    return SEATS if team == "v65" else os.path.join(FTD, f"seats-{team}.json")

def team_env(team):
    return os.path.join(FTD, f"bin-{team}", f"{team}-env.sh")

def load_state():
    """상태 JSON — 없음 = {}(첫 실행 표식) · 표식이 있는데 없어짐 / 손상 = None(이번 회차 0 · 덮어쓰지 않는다)."""
    try:
        with open(STATE, encoding="utf-8") as f:
            d = json.load(f)
        os.makedirs(STATE_DIR, exist_ok=True)
        open(MARK, "a").close()
        return d if isinstance(d, dict) else None
    except FileNotFoundError:
        if os.path.exists(MARK):
            log(f"ERROR 상태 파일 사라짐({STATE}) — 첫 실행 표식은 있는데 파일이 없다: 이번 회차 0")
            return None
        os.makedirs(STATE_DIR, exist_ok=True)
        open(MARK, "a").close()
        return {}
    except (OSError, ValueError) as e:
        log(f"ERROR 상태 파일 손상/읽기 실패({STATE}) {type(e).__name__} — 이번 회차 0")
        return None

def save_state(d):
    os.makedirs(STATE_DIR, exist_ok=True)
    open(MARK, "a").close()
    with open(STATE + ".tmp", "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False)
    os.replace(STATE + ".tmp", STATE)

def live_leads():
    """{팀: 팀장} — G6: 그 팀 명부 `_master` 한 명을 이름 형식·라이브(tmux)·현역으로 대조. 어긋나면 그 팀 0."""
    try:
        files = os.listdir(FTD)
    except OSError as e:
        log(f"ERROR {FTD} 를 못 읽음 {type(e).__name__} — 쪽지·spawn 0")
        return {}
    teams = (["v65"] if "seats.json" in files else []) + sorted(
        f[6:-5] for f in files if f.startswith("seats-") and f.endswith(".json") and len(f) > 11)
    out = {}
    for team in teams:
        p = roster_path(team)
        try:
            with open(p, encoding="utf-8") as f:
                ros = json.load(f)
            assert isinstance(ros, dict)
        except (OSError, ValueError, AssertionError) as e:
            log(f"ERROR {team} 명부를 못 읽음({p}) {type(e).__name__} — 이 팀 0")
            continue
        m = ros.get("_master")
        if not isinstance(m, str) or not m:
            log(f"{team} 명부 _master 없음({os.path.basename(p)}) — 이 팀 0")
            continue
        if not re.fullmatch(rf"byz-{re.escape(team)}-master-[a-z0-9]+#\d+", m):
            log(f"{team} 명부 _master {m} 형식 위반(byz-{team}-master-<에이전트>#N) — 이 팀 0")
            continue
        row = ros.get(m)
        if isinstance(row, dict) and (row.get("_replaced_by") or row.get("role") in DEAD):
            log(f"{team} 명부 _master {m} 현역 아님 — 이 팀 0")
            continue
        if run([*TMUX, "has-session", "-t", f"={m}"], 15).returncode != 0:
            log(f"{team} 명부 _master {m} 라이브 아님(tmux 세션 없음) — 이 팀 0")
            continue
        out[team] = m
    return out

def idle_seconds(seat):
    """(IDLE 인가, 턴 끝에서 지금까지 초) — 조회 실패·모름 = (False, 0)."""
    p = run(["bash", STATUS, "turn", seat], 20)
    f = p.stdout.split()
    if p.returncode != 0 or not f or f[0] != "IDLE": return False, 0
    try:
        return True, int(NOW - dt.datetime.fromisoformat(f[1].replace("Z", "+00:00")).timestamp())
    except (IndexError, ValueError):
        return True, 0

def typing_now(seat):
    """(최근 키 있나, 사유) — 조회 실패는 True(모름 = 안 띄운다 · 오빠 입력 절단 0)."""
    if run([*TMUX, "has-session", "-t", f"={seat}"], 15).returncode != 0: return True, "tmux 세션 없음"
    c = run([*TMUX, "list-clients", "-t", f"={seat}", "-F", "#{client_activity}"], 15)
    if c.returncode != 0: return True, f"tmux list-clients 실패 rc={c.returncode}"
    return any(NOW - int(a) <= CLIENT_SEC for a in c.stdout.split()), None

def census(team, tenv):
    """(셈 dict, 사유) — G5: 후보 계산 «도» 그 팀 env 서브셸 · 부모 FT_INDEX_DIR 은 지운다(다른 팀 카드 0) · 반환값 팀·폴더·카드 소속 대조."""
    env = {k: v for k, v in os.environ.items() if k != "FT_INDEX_DIR"}
    env["FT_NANO_PREFIX"], env["FT_SEATS_JSON"] = f"byz-{team}-nano-", roster_path(team)
    inner = ["bash", SLOTS, "--json"]
    cmd = ["bash", "-c", '. "$1" || exit 9; shift; exec "$@"', "envload", tenv, *inner] if tenv else inner
    try:
        p = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, timeout=max(1.0, min(60, left() - 2)))
    except (subprocess.SubprocessError, OSError) as e:
        return None, f"후보 계산 예외 {type(e).__name__}"
    if p.returncode != 0:
        return None, f"후보 계산 실패 rc={p.returncode} " + ((p.stderr or p.stdout).strip().splitlines() or [""])[0][:160]
    try:
        c = json.loads(p.stdout.strip() or "{}")
        assert isinstance(c, dict)
    except (ValueError, AssertionError):
        return None, "후보 계산 출력이 JSON 이 아니다"
    idx, cands = str(c.get("index_dir") or ""), c.get("candidates") or []
    if c.get("team") != team: return None, f"후보 계산 팀 불일치({c.get('team')} ≠ {team})"
    if f"/{team}/" not in idx.rstrip("/") + "/": return None, f"후보 계산 폴더가 그 팀 것이 아니다({idx})"
    if any(not str(x).startswith(idx.rstrip("/") + "/") for x in cands): return None, f"후보 카드가 그 팀 폴더({idx}) 밖이다"
    return c, None

def launch_spawn(team, lead, card, tenv):
    """G7: spawn 을 «비동기»로 띄운다(부모는 안 기다린다 · 결과는 다음 틱 회수). 반환 = pending dict."""
    out = os.path.join(STATE_DIR, "idle-slot-spawn-" + re.sub(r"[^A-Za-z0-9_.-]+", "_", lead) + ".log")
    wrap = ('out="$1"; tenv="$2"; shift 2; rc=0; if [ -n "$tenv" ] && [ -f "$tenv" ]; then . "$tenv" || rc=9; fi; '
            '"$@" >"$out" 2>&1 || rc=$?; echo "RC=$rc" >>"$out"')
    cmd = ["bash", "-c", wrap, "spawnwrap", out, tenv if os.path.exists(tenv) else "", "bash", SPAWN, card, "--from", lead]
    try:
        with open(out, "w", encoding="utf-8") as f:
            f.write("")
        p = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             stdin=subprocess.DEVNULL, start_new_session=True)
    except (subprocess.SubprocessError, OSError) as e:
        return {"card": card, "at": NOW, "out": out, "err": f"spawn 기동 예외 {type(e).__name__}"}
    return {"card": card, "pid": p.pid, "at": NOW, "out": out}

def reap(team, lead, ts):
    """다음 틱 회수 — 지난 틱 spawn 결과를 쪽지로. 아직 도는 중이면 그대로 둔다(다음 틱). 반환 = 상태 바뀌었나."""
    pd = ts.get("pending")
    if not isinstance(pd, dict): return False
    card = os.path.basename(str(pd.get("card") or "?"))
    txt = ""
    try:
        with open(pd.get("out") or "", encoding="utf-8", errors="replace") as f:
            txt = f.read()
    except OSError:
        pass
    lines = [l for l in txt.splitlines() if l.strip()]
    rc = next((l[3:].strip() for l in reversed(lines) if l.startswith("RC=")), None)
    if rc is None and not pd.get("err") and NOW - float(pd.get("at") or NOW) < SPAWN_MAX:
        return False   # 아직 돈다
    body = [l for l in lines if not l.startswith("RC=")]   # 꼴: spawn 출력 … + 회수 표식 RC=<n>
    if pd.get("err"):
        note = f"[자동 spawn 실패] {card} — 원문: {pd['err']}"
    elif rc == "0":
        note = f"[자동 spawn] {card} → {(body or ['rc=0'])[-1][:200]}"
    else:
        note = f"[자동 spawn 실패] {card} — 원문: {(body or ['출력 없음'])[-1][:200]}"
    ts.pop("pending", None)
    rc2 = send(lead, note)
    log(f"{team} 자동 spawn 결과 쪽지 {card} rc={rc2} (spawn rc={rc})")
    return True

def send(seat, body):
    r = run(["bash", MBOX, "send", seat, "ft-idle-slot-fill", body], 30)
    log(f"쪽지 → {seat} rc={r.returncode} seq={(r.stdout.split() or [''])[0][:40]}")
    return r.returncode

def fill():
    if AUTO_ON:
        log("ERROR 자동 spawn 은 r721 전까지 미검증 — FT_IDLE_SLOT_AUTO=1 로 켜져 있다(2단계 = 새 카드 r721)")
    if os.path.exists(os.path.join(STATE_DIR, "RESOURCE_FREEZE")):
        return log("자원 동결 표식(RESOURCE_FREEZE) — 쪽지·spawn 0")
    if not os.path.exists(ALLSTOP):
        return log("ft-all-stop.sh 없음 — 정지 여부를 못 봐 쪽지·spawn 0(부작용 0 쪽)")
    if run([ALLSTOP, "check"], 20).returncode != 0:
        return log("전팀 정지(ft-all-stop.sh check rc≠0) — 쪽지·spawn 0")
    st = load_state()
    if st is None: return
    spawned = False
    for team, lead in sorted(live_leads().items()):
        if left() <= 3:
            log(f"예산 {BUDGET_SEC}초 소진 — {team} 부터 이번 회차 0")
            break
        ts = st.setdefault("teams", {}).setdefault(team, {})
        if reap(team, lead, ts):
            save_state(st)
        ok, sec = idle_seconds(lead)
        if not ok or sec < SLOT_SEC: continue
        typing, why = typing_now(lead)
        if typing:
            log(f"{team} {lead} 오빠 입력 중/모름({why or 'client_activity'}) — 0")
            continue
        tenv = team_env(team)
        if team != "v65" and not os.path.exists(tenv):
            log(f"{team} 팀 env 없음({tenv}) — 0")
            continue
        c, err = census(team, tenv)
        if err:
            log(f"{team} {err} — 0")
            continue
        cands, empty = c.get("candidates") or [], int(c.get("empty") or 0)
        if empty <= 0 or not cands: continue
        names = [os.path.basename(x) for x in cands]
        sig = hashlib.sha1("|".join(names).encode()).hexdigest()[:12]
        notes = ts.setdefault("notes", {})     # G2: (팀, 후보 집합)별 마지막 «성공» 송신 시각
        claimed = ts.setdefault("claimed", {}) # G1: 카드당 1회 — spawn «전» 선점
        at = notes.get(sig)
        if AUTO_ON and not spawned and at is not None and NOW - float(at) >= AUTO_SEC and names[0] not in claimed:
            if typing_now(lead)[0]:            # G4: spawn 직전 재확인
                log(f"{team} {lead} spawn 직전 입력 감지 — spawn 0(다음 틱)")
                save_state(st)
                continue
            claimed[names[0]] = NOW
            ts["pending"] = launch_spawn(team, lead, cands[0], tenv)
            save_state(st)
            spawned = True                     # 한 틱 1장
            log(f"{team} 자동 spawn 기동 {names[0]} pid={ts['pending'].get('pid')} (비동기 · 결과는 다음 틱)")
            continue
        if at is not None and NOW - float(at) < NOTE_SEC: continue   # 같은 (팀, 후보 집합) 쪽지 30분 1회
        if typing_now(lead)[0]:                # G4: 송신 직전 재확인
            log(f"{team} {lead} 송신 직전 입력 감지 — 쪽지 0(다음 틱)")
            continue
        tail = (f"{AUTO_SEC}초 뒤에도 이대로면 장치가 맨 위 1장을 직접 띄운다." if AUTO_ON else
                f"{AUTO_SEC}초 뒤에도 이대로여도 자동 spawn 은 꺼져 있다(FT_IDLE_SLOT_AUTO=0 · 기본 꺼짐 · 2단계 = r721).")
        rc = send(lead, f"[빈 석] {team} 후보 {len(cands)}장 · 빈 석 {empty} (점유 {c.get('occupied')}/{c.get('max')}) — "
                        f"{' · '.join(names[:5])}\n착지 차례 대기 = 그 PR 만 대기, 다른 카드는 띄움 — 다음 한 줄: "
                        f"bash .fable-team/bin/ft-nano-spawn.sh {cands[0]}\n{tail}")
        if rc == 0:
            notes[sig] = NOW                   # G3: 송신 rc0 일 때만 — 실패면 다음 틱 재시도(자동 spawn 0)
            save_state(st)
        else:
            log(f"{team} 쪽지 실패 rc={rc} — 다음 틱 재시도(자동 spawn 0)")

os.makedirs(STATE_DIR, exist_ok=True)
lock = open(os.path.join(STATE_DIR, "idle-slot-fill.lock"), "w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(0)   # 다른 실행이 돌고 있다
try:
    fill()
except Exception as e:   # 이 장치의 실패가 깨우기(ring)를 되돌리지 않는다 — 로그만
    log(f"ERROR 예외 {type(e).__name__}: {e} — 이번 회차 0")
PYEOF
