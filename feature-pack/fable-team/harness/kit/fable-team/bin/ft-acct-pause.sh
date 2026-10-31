#!/usr/bin/env bash
# ft-acct-pause.sh set|clear|status — 계정 풀(provider[/모델]) 단위 «정지» 를 provider 별 항목이 든 상태 파일 1개 + 회차 진행 기록으로만 건다 (r1214 · Issue #5345 ③·⑤ · 판정 2889).
#   set --provider <P> [--model <M>] --until <ISO8601 · 지금+8시간 이하> [--release-at <ISO8601>] --reason "<10자 이상>" [--set-by <이름>]
#        provider 별 독립 항목 · 같은 provider 가 이미 있으면 REJECT(clear 뒤 set) · --model 은 정규화(base_model)해 저장 · model 없음 = 그 provider 전체.
#        유효 끝 = min(until, release_at) · round_id = <P>-<set_at>-<4자> · 정지 진입 때 그 풀의 현역 좌석마다 «[정지 예고]» 1통(도구 발신자).
#   clear [--provider <P>]   그 항목만(arg 있음) / 전부(arg 없음) 푼다 — ★status 의 «재개 절차» 를 그대로 탄다★(재개 쪽지 → 유휴 확인 뒤 quiet 좌석 ring → 전 좌석 완료 뒤 항목 삭제).
#        아직 못 깨운 좌석이 있으면 항목을 남기고 `RELEASING … 남은=N` 만 내고 다음 status 호출이 이어받는다(조기 삭제 = 재개 유실 0).
#   status                   판정기. 한 바퀴 1회 도는 주체 = 만료·풀림·부분 재시도.
#        없음 `pause=none` rc0 · 유효 `PAUSED <P[/M]> until_hhmm=… round=…` rc3 · 유효 끝(min(until, release_at)) 지남 → stage=releasing →
#        «[재개]» 적재 → 유휴 확인을 지난 좌석만 ring 1회 → 전 좌석이 끝나면 항목 삭제 + `RELEASED|EXPIRED <P[/M]>` rc0 · 손상 `ERROR pause …` rc4(정지 유지).
#   status --check [<P[/M]>] [--agent <A>] [--model <M>] [--seat <좌석>]   부작용 0(삭제·쪽지·ring·기록 0 · 잠금은 공유 읽기).
#        그 provider(그리고 모델이 같거나 항목 model 이 빈칸) 가 «지금 유효한 정지» 면 rc3 `PAUSED …` 1줄 · 아니면 rc0 `OK pause=none`(★만료 포함 — 유효 끝이 지났으면 정지 아님★).
#        손상 판정은 status 와 «같은» 깊이(항목 null·until/round_id 이상·회차 기록 json 깨짐) → rc4 `ERROR pause …`(fail-closed).
#        --seat 는 명부 행에서 agent/model 을 읽고, 명부 model 이 빈칸이면 그 pane 의 argv `--model` 을 읽어 정규화 뒤 비교한다.
#   파일 = <리포 루트>/.fable-team/state/ACCT_PAUSE (json 1개) · 회차 기록 = <리포 루트>/.fable-team/state/acct-pause/<round_id>.json
#          리포 루트 = ft-spawn-hold.sh 와 같은 역산(ft_repo_root) — 워크트리 어디서 불러도 같은 파일 · 일반 파일(권한 644 · 폴더·심링크 0, 하드 룰 19).
#   provider 판별 = provider-of-model.tsv(모델 정규식 → provider) → agent 기본표(claude→claude · codex→codex · pi→deepseek · cmd→deepseek) → 둘 다 없으면 «판정 불가».
#   ★배치(하드 룰 12)★: 한 status 호출의 좌석 처리 = FT_ACCT_BATCH_SEC(기본 7초) 안 · 외부 호출(send·ring) timeout = «남은 배치 시간»(최대 30초) — 느린 mbox 하나가 바퀴를 잡아먹지 않는다.
#        좌석 수 상한 = FT_ACCT_BATCH_SEATS(기본 20) — 넘는 좌석은 다음 호출(틱 다음 바퀴)이 이어받는다.
#   env(시험): FT_ACCT_ROOT FT_ACCT_NOW FT_ACCT_MBOX FT_ACCT_RULES FT_ACCT_TMUX FT_ACCT_LOCK_WAIT FT_ACCT_BATCH_SEC FT_ACCT_BATCH_SEATS FT_ACCT_AGENT_PROVIDER
#   ★측정·조작 금지(오빠 절대지침)★: 이 도구는 좌석을 kill 하지 않고 pane 에 입력하지 않는다 — 문은 «발사 0» 뿐이다(하드 룰 2·7).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$HERE/ft-harness-root.sh" ] || { echo "ERROR pause ft-harness-root.sh 없음: $HERE" >&2; exit 4; }
. "$HERE/ft-harness-root.sh"
ROOT="${FT_ACCT_ROOT:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(ft_repo_root "$HERE")" || { echo "ERROR pause 리포 공용 루트를 못 풂 — FT_ACCT_ROOT 로 지정하라 ($HERE)" >&2; exit 4; }
fi
MBOX="${FT_ACCT_MBOX:-}"
if [ -z "$MBOX" ]; then
  _CM="$(ft_comm_dir "$HERE" 2>/dev/null)" || _CM=""
  [ -n "$_CM" ] && MBOX="$_CM/mbox.sh"
fi
[ -n "$MBOX" ] || MBOX="$ROOT/.fable-team/comm/mbox.sh"
python3 - "$ROOT" "$HERE" "$MBOX" "$@" <<'PY'
import datetime
import fcntl
import json
import os
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path

ROOT, HERE, MBOX = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
ARGS = sys.argv[4:]
STATE = ROOT / ".fable-team" / "state"
FILE = STATE / "ACCT_PAUSE"
REC = STATE / "acct-pause"
LOCKF = REC / "lock"
RULE = Path(os.environ.get("FT_ACCT_RULES") or (HERE / "provider-of-model.tsv"))
TMUX = os.environ.get("FT_ACCT_TMUX", "tmux")
NOW = int(os.environ.get("FT_ACCT_NOW") or time.time())
LOCK_WAIT = float(os.environ.get("FT_ACCT_LOCK_WAIT") or 7)
BATCH_SEC = float(os.environ.get("FT_ACCT_BATCH_SEC") or 7)
BATCH_SEATS = int(os.environ.get("FT_ACCT_BATCH_SEATS") or 20)
CALL_MAX = float(os.environ.get("FT_ACCT_CALL_MAX") or 30)   # 한 외부 호출 상한(배치 남은 시간이 더 작으면 그쪽)
MAX_UNTIL = 8 * 3600
FOLD_DAYS = 7
SENDER = "ft-acct-pause"
BUSY = re.compile(r"esc to interrupt|Working|Thinking|↓ [0-9,]+ tokens|\| *thinking|Crunched|Crunching")
UNSUBMITTED = re.compile(r"^[›❯] +[^ ]")
AGENT_DEFAULT = {"claude": "claude", "codex": "codex", "pi": "deepseek", "cmd": "deepseek"}
USAGE = ('usage: ft-acct-pause.sh set --provider <P> [--model <M>] --until <ISO8601> [--release-at <ISO8601>] '
         '--reason "<10자+>" [--set-by <이름>] | clear [--provider <P>] | '
         'status [--check [<P[/M]>] [--agent <A>] [--model <M>] [--seat <좌석>]]')


class Bad(Exception):
    """파일·기록 손상 — 판정 불가(정지 유지 · rc4)."""


def hhmm(ep):
    return time.strftime("%H:%M", time.localtime(int(ep))) if ep else "—"


def base_model(model):
    """`claude-fable-5-1[1m]` → `claude-fable-5-1` (창 꼬리 떼고 비교 · ft_api_outage_util.base_model 과 같은 규칙)."""
    return re.sub(r"\[[^\]]*\]$", "", (model or "").strip())


def label(prov, model):
    return f"{prov}/{model}" if model else f"{prov}/*"


def rules():
    try:
        txt = RULE.read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for line in txt.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cols = line.split("\t") if "\t" in line else line.split()
        if len(cols) >= 2:
            out.append((cols[0].strip(), cols[1].strip()))
    return out


def agent_map():
    m = dict(AGENT_DEFAULT)
    for part in re.split(r"[,\s]+", os.environ.get("FT_ACCT_AGENT_PROVIDER", "")):
        if "=" in part:
            k, v = part.split("=", 1)
            if k.strip():
                m[k.strip()] = v.strip()
    return m


def provider_of(agent, model):
    """모델 정규식표 → agent 기본표 → ('', 'unknown')."""
    bm = base_model(model)
    if bm:
        for pat, prov in rules():
            try:
                if re.search(pat, bm):
                    return prov, "rule"
            except re.error:
                continue
    a = (agent or "").strip()
    table = agent_map()
    if a and table.get(a):
        return table[a], "agent"
    return "", "unknown"


def iso_epoch(text):
    try:
        d = datetime.datetime.fromisoformat((text or "").replace("Z", "+00:00"))
    except ValueError:
        return 0
    if d.tzinfo is None:
        d = d.astimezone()
    return int(d.timestamp())


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (ValueError, OSError) as exc:
        raise Bad(f"{path.name} 읽기 실패({exc.__class__.__name__}) — {path}")


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    tmp.write_text(json.dumps(obj, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def acquire(shared):
    """flock — 대기 ≤ LOCK_WAIT. 반환 = 파일핸들 · None = 잠금 파일 없음(공유 읽기, 부작용 0) · False = 못 잡음."""
    if shared and not LOCKF.exists():
        return None
    if not shared:
        try:
            REC.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise Bad(f"상태 폴더 생성 실패 — {exc}")
    try:
        fh = open(LOCKF, "a+")
    except OSError as exc:
        raise Bad(f"잠금 파일 열기 실패 — {exc}")
    mode = fcntl.LOCK_SH if shared else fcntl.LOCK_EX
    deadline = time.time() + LOCK_WAIT
    while True:
        try:
            fcntl.flock(fh, mode | fcntl.LOCK_NB)
            return fh
        except OSError:
            if time.time() >= deadline:
                fh.close()
                return False
            time.sleep(0.05)


def release(fh):
    if fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_UN)
        finally:
            fh.close()


def run(cmd, timeout=CALL_MAX):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=max(0.2, timeout))
    except subprocess.TimeoutExpired:
        return None
    except (OSError, subprocess.SubprocessError):
        return None


def panes(budget=None):
    """좌석 pane 목록. 배치 남은 시간이 없으면 «조회 생략»(None) — 부르는 쪽이 그 좌석을 다음 호출로 넘긴다(⑧).
    tmux 자체가 실패(rc≠0)하면 {} — «좌석 없음» 과 «조회 못 함» 을 가른다."""
    left = None
    if budget is not None:
        left = budget["deadline"] - time.time()
        if left <= 0.2:
            return None
    r = run([TMUX, "list-panes", "-a", "-F", "#{session_name} #{pane_id}"], timeout=min(7.0, left) if left else 7.0)
    if r is None:
        return None
    out = {}
    if r.returncode != 0:
        return out
    for line in r.stdout.splitlines():
        cols = line.split()
        if len(cols) >= 2:
            out[cols[0]] = cols[1]
    return out


def pane_busy(pane, budget=None):
    """지금 턴 중이거나 미제출 입력이 있으면 True · 판정 불가도 True(깨우지 않는 쪽).
    배치 남은 시간이 없으면 None(조회 생략) — 부르는 쪽이 그 좌석을 다음 호출로 넘긴다(⑧)."""
    left = None
    if budget is not None:
        left = budget["deadline"] - time.time()
        if left <= 0.2:
            return None
    r = run([TMUX, "capture-pane", "-t", pane, "-p"], timeout=min(7.0, left) if left else 7.0)
    if r is None:
        return None if budget is not None else True
    if r.returncode != 0:
        return True
    tail = [ln for ln in r.stdout.splitlines() if ln.strip()][-14:]
    text = "\n".join(tail)
    return bool(BUSY.search(text)) or any(UNSUBMITTED.match(ln) for ln in tail)


def pane_argv_model(pane):
    """그 pane 의 에이전트 argv 에서 `--model <id>` 를 읽어 정규화한다(명부 model 이 빈칸일 때 · ⑤)."""
    r = run([TMUX, "display-message", "-t", pane, "-p", "#{pane_pid}"], timeout=7)  # 한 번짜리 조회(좌석당 1회 · ⑤)
    pid = (r.stdout or "").strip() if r is not None and r.returncode == 0 else ""
    if not pid.isdigit():
        return ""
    p = run(["ps", "-o", "args=", "-p", pid], timeout=7)
    args = (p.stdout or "").strip() if p is not None and p.returncode == 0 else ""
    m = re.search(r"--model[= ]+([^\s]+)", args)
    return base_model(m.group(1)) if m else ""


def seats_live():
    """seats*.json 합집합 — 이름 중복 제거 · `_` 키·_replaced_by·stop-ready 제외(현역 후보)."""
    live = {}
    try:
        files = sorted((ROOT / ".fable-team").glob("seats*.json"))
    except OSError:
        return live
    seen = set()
    for f in files:
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if not isinstance(d, dict):
            continue
        for k, v in d.items():
            if not isinstance(k, str) or k.startswith("_") or not isinstance(v, dict) or k in seen:
                continue
            seen.add(k)
            if v.get("_replaced_by") or v.get("role") == "stop-ready":
                continue
            live[k] = v
    return live


def seat_provider(seat, row, alive):
    """좌석의 (provider, model) — 명부 model 이 빈칸이면 pane argv 를 읽는다(⑤)."""
    model = base_model(row.get("model") or "")
    if not model and seat in alive:
        model = pane_argv_model(alive[seat])
    prov, _ = provider_of(row.get("agent") or "", model)
    return prov, model


def recipients(prov, model, budget=None):
    """그 풀의 현역 좌석 — 명부 합집합 ∩ tmux 생존 ∩ provider 판별 일치(모델이 다르면 제외) · tick 유무를 함께 둔다."""
    alive = panes(budget)
    if alive is None:
        return []
    out = []
    for seat, row in seats_live().items():
        if seat not in alive:
            continue
        p, rm = seat_provider(seat, row, alive)
        if p != prov:
            continue
        if model and rm and rm != model:
            continue
        out.append({"seat": seat, "tick": bool(row.get("tick")), "notice_at": None,
                    "resume_at": None, "woke_at": None, "no_ring": False, "last_err": ""})
    return out


def send_seat(seat, body, budget):
    """mbox send(도구 발신자 ft-acct-pause) → (doorbell, 오류문구). timeout = 남은 배치 시간(⑧)."""
    left = budget["deadline"] - time.time()
    if left <= 0.2:
        return "", "배치 시간 초과"
    r = run(["bash", str(MBOX), "send", seat, SENDER, body], timeout=min(CALL_MAX, left))
    if r is None:
        return "", "mbox 실행 실패·시간 초과"
    doorbell = (re.search(r"doorbell=(\w+)", r.stdout or "") or [None, ""])[1]
    if r.returncode != 0 or "QUEUED" not in (r.stdout or ""):
        tail = (r.stdout + r.stderr).strip().splitlines()
        return doorbell or "", (tail[-1][:80] if tail else f"send rc={r.returncode}")
    return doorbell or "", ""


def ring_seat(seat, budget):
    left = budget["deadline"] - time.time()
    if left <= 0.2:
        return False
    r = run(["bash", str(MBOX), "ring", seat], timeout=min(CALL_MAX, left))
    return r is not None and r.returncode == 0


def ring_if_idle(r, budget):
    """재개 ring 은 «모든» 좌석(틱 좌석 포함)이 유휴일 때만 — 바쁘면 다음 호출이 재시도(④)."""
    seat = r.get("seat") or ""
    alive = panes(budget)
    if alive is None:
        r["last_err"] = "조회 시간 초과"
        return False
    if seat not in alive:
        r["no_ring"] = True
        r["last_err"] = "absent"
        return False
    busy = pane_busy(alive[seat], budget)
    if busy is None:
        r["last_err"] = "조회 시간 초과"
        return False
    if busy:
        r["last_err"] = "busy"
        return False
    if not ring_seat(seat, budget):
        r["last_err"] = "ring 실패"
        return False
    r["woke_at"] = NOW
    r["last_err"] = ""
    return True


def rec_done(rec):
    """재개 완료 = 모든 좌석이 적재됐고(resume_at), 깨울 좌석은 다 깨웠다(woke_at 또는 no_ring)."""
    rs = rec.get("recipients") or []
    return all(x.get("resume_at") and (x.get("woke_at") or x.get("no_ring")) for x in rs)


def notice_pass(entry, rec, kind, budget):
    """kind=set|resume · 좌석마다 통지(유휴 확인) → 기록. 이번 호출에서 처리한 수를 돌려준다(배치 상한)."""
    prov = entry.get("provider", "")
    model = base_model(entry.get("model") or "")
    lab = label(prov, model)
    rel = entry.get("release_at") or 0
    when = hhmm(rel) if rel else hhmm(entry.get("until") or 0)
    if kind == "set":
        body = (f"[정지 예고] {lab} 한도 — 풀림 {when} · 지금 턴을 끝내고 WIP 커밋 · 새 발주·DA·spawn 0 · 재개는 [재개] 쪽지")
    else:
        body = f"[재개] {lab} 풀림 {when} · 중단한 턴부터"
    done = 0
    for r in rec.get("recipients") or []:
        if budget["seats"] <= 0 or time.time() >= budget["deadline"]:
            break
        if not isinstance(r, dict):
            raise Bad(f"회차 기록 좌석 항목 손상 round={rec.get('round_id')}")
        seat = r.get("seat") or ""
        if not seat:
            continue
        if kind == "set":
            if r.get("notice_at"):
                continue
        elif r.get("resume_at"):
            if not (r.get("woke_at") or r.get("no_ring")):
                if ring_if_idle(r, budget):
                    done += 1
            continue
        joined = panes(budget)
        if joined is None:                       # ⑧ 조회 자체를 건너뛴다 — 남은 좌석은 다음 호출
            break
        if seat not in joined:
            r["resume_at" if kind == "resume" else "notice_at"] = NOW
            r["no_ring"] = True
            r["last_err"] = "absent"
            continue
        if not r.get("tick"):
            busy = pane_busy(joined[seat], budget)
            if busy is None:
                r["last_err"] = "조회 시간 초과"
                break
            if busy:
                r["last_err"] = "busy"
                continue
        doorbell, err = send_seat(seat, body, budget)
        budget["seats"] -= 1
        done += 1
        if err:
            r["last_err"] = err
            continue
        r["last_err"] = ""
        if kind == "set":
            r["notice_at"] = NOW
            continue
        r["resume_at"] = NOW
        if doorbell == "sent":
            r["no_ring"] = True          # doorbell 이 이미 pane 에 들어갔다 — ring 0(이중 깨움 0)
        else:
            ring_if_idle(r, budget)
    return done


def release_pass(entry, rec, budget, final_stage):
    """재개 절차 한 번 — 부르는 쪽이 단계·저장·삭제를 정한다. 반환 = 전 좌석 완료인가."""
    rec["stage"] = "releasing"
    write_json(REC / f"{rec.get('round_id')}.json", rec)
    notice_pass(entry, rec, "resume", budget)
    write_json(REC / f"{rec.get('round_id')}.json", rec)
    if not rec_done(rec):
        return False
    rec["stage"] = final_stage
    rec["ended_at"] = NOW
    write_json(REC / f"{rec.get('round_id')}.json", rec)
    return True


def fold_records():
    """released/cleared 이고 7일 지난 회차 기록만 접는다 — 미완료 기록은 나이와 무관하게 유지."""
    try:
        files = sorted(REC.glob("*.json"))
    except OSError:
        return
    for f in files:
        try:
            rec = json.loads(f.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        if not isinstance(rec, dict) or rec.get("stage") not in ("released", "cleared"):
            continue
        when = int(rec.get("ended_at") or rec.get("set_at") or 0)
        if when and NOW - when > FOLD_DAYS * 86400:
            try:
                f.unlink()
            except OSError:
                pass


def err(msg):
    print(f"ERROR pause {msg}")
    return 4


def drop_file_if_empty(state):
    if state:
        write_json(FILE, state)
        return
    try:
        FILE.unlink()
    except FileNotFoundError:
        pass


def load_entry(state, prov):
    """항목 + 회차 기록 검증(status·check 공통 깊이) — 손상이면 Bad."""
    if prov not in state:
        return None, None
    entry = state[prov]
    if not isinstance(entry, dict):
        raise Bad(f"항목이 사전이 아니다 provider={prov}")
    try:
        until = int(entry["until"])
        rid = entry["round_id"]
    except (KeyError, TypeError, ValueError):
        raise Bad(f"항목 손상 provider={prov}")
    rec = read_json(REC / f"{rid}.json", None)
    if not isinstance(rec, dict) or not isinstance(rec.get("recipients"), list):
        raise Bad(f"회차 기록 손상 round={rid}")
    return entry, rec


def endpoint(entry):
    until = int(entry["until"])
    rel = int(entry.get("release_at") or 0)
    return (min(until, rel) if rel else until), until, rel


def do_set(opts):
    prov = (opts.get("provider") or "").strip()
    if not prov or "/" in prov:
        print("REJECT acct-pause set — --provider 는 풀 이름 하나(예: claude) · 받은 값: «%s»" % prov)
        return 1
    model = base_model(opts.get("model") or "")
    until_iso = (opts.get("until") or "").strip()
    until = iso_epoch(until_iso)
    if not until:
        print("REJECT acct-pause set — --until 은 ISO8601 (예: 2026-10-31T12:00:00+09:00)")
        return 1
    if until <= NOW:
        print("REJECT acct-pause set — --until 이 이미 지났다")
        return 1
    if until > NOW + MAX_UNTIL:
        print("REJECT acct-pause set — --until 은 지금+8시간 이하(기한 없는 정지 금지)")
        return 1
    rel_iso = (opts.get("release_at") or "").strip()
    rel = iso_epoch(rel_iso) if rel_iso else 0
    if rel_iso and not rel:
        print("REJECT acct-pause set — --release-at 은 ISO8601")
        return 1
    reason = (opts.get("reason") or "").strip()
    if len(reason) < 10:
        print("REJECT acct-pause set — --reason 은 10자 이상")
        return 1
    set_by = (opts.get("set_by") or os.environ.get("FT_ACCT_SET_BY") or "unknown").strip()
    fh = acquire(False)
    if fh is False:
        return err("판정 불가 잠금 — 다른 status 가 잠금 중")
    try:
        state = read_json(FILE, {})
        if not isinstance(state, dict):
            raise Bad("ACCT_PAUSE 최상위가 사전이 아니다")
        if prov in state:
            print(f"REJECT acct-pause set — {prov} 항목이 이미 있다(round={(state.get(prov) or {}).get('round_id', '?')}) — clear 뒤 set")
            return 1
        rid = f"{prov}-{NOW}-{secrets.token_hex(2)}"
        entry = {"provider": prov, "model": model, "until": until, "until_iso": until_iso,
                 "release_at": rel or None, "release_at_iso": rel_iso or None, "reason": reason,
                 "set_by": set_by, "set_at": NOW, "round_id": rid}
        state[prov] = entry
        write_json(FILE, state)
        budget = {"deadline": time.time() + BATCH_SEC, "seats": BATCH_SEATS}
        rec = {"provider": prov, "model": model, "round_id": rid, "stage": "set", "set_at": NOW,
               "until": until, "release_at": rel or None, "reason": reason, "set_by": set_by,
               "recipients": recipients(prov, model, budget)}
        write_json(REC / f"{rid}.json", rec)
        if not rec["recipients"]:
            print("WARN 좌석 목록 조회 시간 초과 또는 대상 0 — 예고 0(상태는 걸었다)")
        notice_pass(entry, rec, "set", budget)
        write_json(REC / f"{rid}.json", rec)
        left = sum(1 for r in rec["recipients"] if not r.get("notice_at"))
        print(f"SET pause {label(prov, model)} until={until_iso} release={rel_iso or '—'} round={rid} "
              f"recipients={len(rec['recipients'])} 남은통지={left}")
        return 0
    finally:
        release(fh)


def do_clear(prov):
    """clear 도 «재개 절차» 를 탄다 — 쪽지·ring·기록이 끝나야 삭제(① · 조기 삭제 = 재개 유실)."""
    fh = acquire(False)
    if fh is False:
        return err("판정 불가 잠금 — 다른 status 가 잠금 중")
    try:
        state = read_json(FILE, {})
        if not isinstance(state, dict):
            raise Bad("ACCT_PAUSE 최상위가 사전이 아니다")
        prov = (prov or "").strip()
        if prov and prov not in state:
            print("pause=none")
            return 0
        if not state:
            drop_file_if_empty({})
            print("pause=none")
            return 0
        gone = [prov] if prov else list(state.keys())
        budget = {"deadline": time.time() + BATCH_SEC, "seats": BATCH_SEATS}
        rc = 0
        for p in gone:
            entry, rec = load_entry(state, p)
            if entry is None:
                continue
            lab = label(p, base_model(entry.get("model") or ""))
            rid = entry.get("round_id")
            if release_pass(entry, rec, budget, "cleared"):
                state.pop(p, None)
                print(f"CLEARED pause {lab} round={rid}")
            else:
                left = sum(1 for r in rec["recipients"] if not (r.get("resume_at") and (r.get("woke_at") or r.get("no_ring"))))
                print(f"RELEASING {lab} round={rid} 남은={left}")
                rc = 0
        drop_file_if_empty(state)
        return rc
    finally:
        release(fh)


def do_status():
    fh = acquire(False)
    if fh is False:
        return err("판정 불가 잠금 — 다른 status 가 잠금 중")
    try:
        state = read_json(FILE, {})
        if not isinstance(state, dict):
            raise Bad("ACCT_PAUSE 최상위가 사전이 아니다")
        rc = 0
        budget = {"deadline": time.time() + BATCH_SEC, "seats": BATCH_SEATS}
        for prov in list(state.keys()):
            entry, rec = load_entry(state, prov)
            if entry is None:
                continue
            until = int(entry["until"])
            rid = entry["round_id"]
            end, _until, rel = endpoint(entry)
            lab = label(prov, base_model(entry.get("model") or ""))
            if rec.get("stage") == "releasing" or NOW >= end:
                if release_pass(entry, rec, budget, "released"):
                    state.pop(prov, None)
                    print(f"{'EXPIRED' if NOW >= until else 'RELEASED'} {lab} round={rid}")
                else:
                    left = sum(1 for r in rec["recipients"] if not (r.get("resume_at") and (r.get("woke_at") or r.get("no_ring"))))
                    print(f"RELEASING {lab} round={rid} 남은={left}")
                    rc = 3
            else:
                # 정지 중이어도 «못 보낸 예고»는 이 호출이 이어서 보낸다(부분 실패·바쁜 좌석 복구 주체 = 판정기).
                if rec.get("stage") == "set" and any(not r.get("notice_at") for r in rec["recipients"]):
                    notice_pass(entry, rec, "set", budget)
                    write_json(REC / f"{rid}.json", rec)
                print(f"PAUSED {lab} until_hhmm={hhmm(until)} until_epoch={until} "
                      f"release_hhmm={hhmm(rel) if rel else '—'} round={rid} stage={rec.get('stage', 'set')}")
                rc = 3
        drop_file_if_empty(state)
        if rc == 0:
            print("pause=none")
        fold_records()
        return rc
    finally:
        release(fh)


def do_check(argv):
    want = agent = model = seat = ""
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--check":
            i += 1
            continue
        if a in ("--agent", "--model", "--seat") and i + 1 < len(argv):
            if a == "--agent":
                agent = argv[i + 1]
            elif a == "--model":
                model = argv[i + 1]
            else:
                seat = argv[i + 1]
            i += 2
            continue
        if a.startswith("--") or want:
            print(USAGE)
            return 2
        want = a
        i += 1
    if seat and not want:
        row = seats_live().get(seat) or {}
        agent = agent or (row.get("agent") or "")
        model = model or base_model(row.get("model") or "")
        if not model:                       # ⑤ 명부 model 빈칸 → pane argv `--model`
            joined = panes()
            if seat in joined:
                model = pane_argv_model(joined[seat])
    if "/" in want and not model:
        want, model = want.split("/", 1)
    model = base_model(model)
    prov = want.strip()
    if not prov:
        prov, _ = provider_of(agent, model)
        if not prov:
            print(f"ERROR pause 판정 불가(provider) — agent={agent or '-'} model={model or '-'} seat={seat or '-'} 규칙표={RULE}")
            return 4
    try:
        fh = acquire(True)
    except Bad as exc:
        return err(str(exc))
    if fh is False:
        return err("판정 불가 잠금 — 다른 status 가 잠금 중")
    try:
        state = read_json(FILE, {})
        if not isinstance(state, dict):
            raise Bad("ACCT_PAUSE 최상위가 사전이 아니다")
        entry, rec = load_entry(state, prov)      # ③ status 와 같은 손상 판정(rc4)
        if entry is None:
            print("OK pause=none")
            return 0
        em = base_model(entry.get("model") or "")
        if em and model and em != model:
            print("OK pause=none")
            return 0
        end, until, rel = endpoint(entry)
        if NOW >= end:                            # ② 유효 끝(만료·풀림 시각) 지남 = 정지 아님(부작용 0)
            print("OK pause=none")
            return 0
        lab = label(prov, em or model)
        print(f"PAUSED {lab} until_hhmm={hhmm(until)} until_epoch={until} "
              f"release_hhmm={hhmm(rel) if rel else '—'} round={entry.get('round_id', '')} stage={rec.get('stage', '') or 'set'}")
        return 3
    except Bad as exc:
        return err(str(exc))
    finally:
        release(fh)


def main():
    if not ARGS:
        print(USAGE, file=sys.stderr)
        return 2
    cmd, rest = ARGS[0], ARGS[1:]
    try:
        if cmd == "status":
            if "--check" in rest:
                return do_check(rest)
            if rest:
                print(USAGE, file=sys.stderr)
                return 2
            return do_status()
        if cmd == "clear":
            prov = ""
            i = 0
            while i < len(rest):
                if rest[i] == "--provider" and i + 1 < len(rest):
                    prov = rest[i + 1]
                    i += 2
                    continue
                print(USAGE, file=sys.stderr)
                return 2
            return do_clear(prov)
        if cmd == "set":
            opts = {}
            i = 0
            keys = {"--provider": "provider", "--model": "model", "--until": "until",
                    "--release-at": "release_at", "--reason": "reason", "--set-by": "set_by"}
            while i < len(rest):
                if rest[i] in keys and i + 1 < len(rest):
                    opts[keys[rest[i]]] = rest[i + 1]
                    i += 2
                    continue
                print(USAGE, file=sys.stderr)
                return 2
            return do_set(opts)
        print(USAGE, file=sys.stderr)
        return 2
    except Bad as exc:
        return err(str(exc))


if __name__ == "__main__":
    sys.exit(main())
PY
