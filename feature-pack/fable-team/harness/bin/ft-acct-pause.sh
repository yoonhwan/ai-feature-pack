#!/usr/bin/env bash
# ft-acct-pause.sh set|clear|status — 계정 풀(provider[/모델]) 단위 «정지» 를 provider 별 항목이 든 상태 파일 1개 + 회차 진행 기록으로만 건다 (r1214 · Issue #5345 ③·⑤ · 판정 2889).
#   set --provider <P> [--model <M>] --until <ISO8601 · 지금+8시간 이하> [--release-at <ISO8601>] --reason "<10자 이상>" [--set-by <이름>]
#        provider 별 독립 항목 · 같은 provider 가 이미 있으면 REJECT(clear 뒤 set) · --model 은 정규화(base_model)해 저장 · model 없음 = 그 provider 전체.
#        유효 끝 = min(until, release_at) · round_id = <P>-<set_at>-<4자> · 정지 진입 때 그 풀의 현역 좌석마다 «[정지 예고]» 1통(도구 발신자).
#   clear [--provider <P>]   그 항목만(arg 있음) / 전부(arg 없음) 지운다. 회차 기록은 stage=cleared 로 남긴다(감사).
#   status                   판정기. 한 바퀴 1회 도는 주체 = 만료·풀림·부분 재시도.
#        없음 `pause=none` rc0 · 유효 `PAUSED <P[/M]> until_hhmm=… round=…` rc3 · 유효 끝 지남 → stage=releasing → «[재개]» 적재 →
#        doorbell 이 sent 가 아닌 좌석만 ring 1회 → 전 좌석이 끝나면 항목 삭제 + `RELEASED|EXPIRED <P[/M]>` rc0 · 손상 `ERROR pause …` rc4(정지 유지).
#   status --check [<P[/M]>] [--agent <A>] [--model <M>]   부작용 0(삭제·쪽지·ring·기록 0 · 잠금은 공유 읽기).
#        그 provider(그리고 모델이 같거나 항목 model 이 빈칸) 가 지금 정지면 rc3 `PAUSED …` 1줄 · 아니면 rc0 `OK pause=none` · 판정 불가 rc4 `ERROR pause …`.
#   파일 = <리포 루트>/.fable-team/state/ACCT_PAUSE (json 1개) · 회차 기록 = <리포 루트>/.fable-team/state/acct-pause/<round_id>.json
#          리포 루트 = ft-spawn-hold.sh 와 같은 역산(ft_repo_root) — 워크트리 어디서 불러도 같은 파일 · 일반 파일(권한 644 · 폴더·심링크 0, 하드 룰 19).
#   provider 판별 = provider-of-model.tsv(모델 정규식 → provider) → agent 기본표(claude→claude · codex→codex · pi→deepseek · cmd→deepseek) → 둘 다 없으면 «판정 불가».
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
MAX_UNTIL = 8 * 3600
FOLD_DAYS = 7
SENDER = "ft-acct-pause"
BUSY = re.compile(r"esc to interrupt|Working|Thinking|↓ [0-9,]+ tokens|\| *thinking")
UNSUBMITTED = re.compile(r"^[›❯] +[^ ]")
AGENT_DEFAULT = {"claude": "claude", "codex": "codex", "pi": "deepseek", "cmd": "deepseek"}
USAGE = ('usage: ft-acct-pause.sh set --provider <P> [--model <M>] --until <ISO8601> [--release-at <ISO8601>] '
         '--reason "<10자+>" [--set-by <이름>] | clear [--provider <P>] | '
         'status [--check [<P[/M]>] [--agent <A>] [--model <M>]]')


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


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None


def panes():
    r = run([TMUX, "list-panes", "-a", "-F", "#{session_name} #{pane_id}"])
    out = {}
    if r is None or r.returncode != 0:
        return out
    for line in r.stdout.splitlines():
        cols = line.split()
        if len(cols) >= 2:
            out[cols[0]] = cols[1]
    return out


def pane_busy(pane):
    """지금 턴 중이거나 미제출 입력이 있으면 True — 판정 불가도 True(깨우지 않는 쪽)."""
    r = run([TMUX, "capture-pane", "-t", pane, "-p"])
    if r is None or r.returncode != 0:
        return True
    tail = [ln for ln in r.stdout.splitlines() if ln.strip()][-14:]
    text = "\n".join(tail)
    return bool(BUSY.search(text)) or any(UNSUBMITTED.match(ln) for ln in tail)


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


def recipients(prov, model):
    """그 풀의 현역 좌석 — 명부 합집합 ∩ tmux 생존 ∩ provider 판별 일치(모델이 다르면 제외) · tick 유무를 함께 둔다."""
    alive = panes()
    out = []
    for seat, row in seats_live().items():
        if seat not in alive:
            continue
        p, _ = provider_of(row.get("agent") or "", row.get("model") or "")
        if p != prov:
            continue
        rm = base_model(row.get("model") or "")
        if model and rm and rm != model:
            continue
        out.append({"seat": seat, "tick": bool(row.get("tick")), "notice_at": None,
                    "resume_at": None, "woke_at": None, "last_err": ""})
    return out


def send_seat(seat, body):
    """mbox send(도구 발신자 ft-acct-pause) → (doorbell, 오류문구)."""
    r = run(["bash", str(MBOX), "send", seat, SENDER, body])
    if r is None:
        return "", "mbox 실행 실패"
    doorbell = (re.search(r"doorbell=(\w+)", r.stdout or "") or [None, ""])[1] if re.search(r"doorbell=(\w+)", r.stdout or "") else ""
    if r.returncode != 0 or "QUEUED" not in (r.stdout or ""):
        tail = (r.stdout + r.stderr).strip().splitlines()
        return doorbell, (tail[-1][:80] if tail else f"send rc={r.returncode}")
    return doorbell, ""


def ring_seat(seat):
    r = run(["bash", str(MBOX), "ring", seat])
    return r is not None and r.returncode == 0


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
    alive = panes()
    for r in rec.get("recipients") or []:
        if budget["seats"] <= 0 or time.time() >= budget["deadline"]:
            break
        seat = r.get("seat") or ""
        if not seat or (r.get("notice_at") if kind == "set" else r.get("resume_at")):
            continue
        if seat not in alive:
            r["last_err"] = "absent"
            if kind == "resume":
                r["resume_at"] = NOW
            continue
        if not r.get("tick") and pane_busy(alive[seat]):
            r["last_err"] = "busy"
            continue
        doorbell, err = send_seat(seat, body)
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
        if doorbell != "sent":
            if ring_seat(seat):
                r["woke_at"] = NOW
            else:
                r["last_err"] = "ring 실패"
    return done


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
            print(f"REJECT acct-pause set — {prov} 항목이 이미 있다(round={state[prov].get('round_id', '?')}) — clear 뒤 set")
            return 1
        rid = f"{prov}-{NOW}-{secrets.token_hex(2)}"
        entry = {"provider": prov, "model": model, "until": until, "until_iso": until_iso,
                 "release_at": rel or None, "release_at_iso": rel_iso or None, "reason": reason,
                 "set_by": set_by, "set_at": NOW, "round_id": rid}
        state[prov] = entry
        write_json(FILE, state)
        rec = {"provider": prov, "model": model, "round_id": rid, "stage": "set", "set_at": NOW,
               "until": until, "release_at": rel or None, "reason": reason, "set_by": set_by,
               "recipients": recipients(prov, model)}
        write_json(REC / f"{rid}.json", rec)
        budget = {"deadline": time.time() + BATCH_SEC, "seats": BATCH_SEATS}
        notice_pass(entry, rec, "set", budget)
        write_json(REC / f"{rid}.json", rec)
        left = sum(1 for r in rec["recipients"] if not r.get("notice_at"))
        print(f"SET pause {label(prov, model)} until={until_iso} release={rel_iso or '—'} round={rid} "
              f"recipients={len(rec['recipients'])} 남은통지={left}")
        return 0
    finally:
        release(fh)


def do_clear(prov):
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
            try:
                FILE.unlink()          # 빈 사전 파일({})은 정지 아님 — 파일을 남기지 않는다
            except FileNotFoundError:
                pass
            print("pause=none")
            return 0
        gone = [prov] if prov else list(state.keys())
        for p in gone:
            entry = state.pop(p, None)
            rid = (entry or {}).get("round_id")
            if not rid:
                continue
            try:
                rec = read_json(REC / f"{rid}.json", None)
                if isinstance(rec, dict):
                    rec["stage"] = "cleared"
                    rec["ended_at"] = NOW
                    write_json(REC / f"{rid}.json", rec)
            except Bad:
                pass
            print(f"CLEARED pause {label(p, base_model((entry or {}).get('model') or ''))} round={rid}")
        if state:
            write_json(FILE, state)
        else:
            try:
                FILE.unlink()
            except FileNotFoundError:
                pass
        return 0
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
            entry = state[prov]
            if not isinstance(entry, dict):
                raise Bad(f"항목이 사전이 아니다 provider={prov}")
            try:
                until = int(entry["until"])
                rid = entry["round_id"]
            except (KeyError, TypeError, ValueError):
                raise Bad(f"항목 손상 provider={prov}")
            rel = int(entry.get("release_at") or 0)
            end = min(until, rel) if rel else until
            rec = read_json(REC / f"{rid}.json", None)
            if not isinstance(rec, dict) or not isinstance(rec.get("recipients"), list):
                raise Bad(f"회차 기록 손상 round={rid}")
            lab = label(prov, base_model(entry.get("model") or ""))
            if NOW >= end:
                rec["stage"] = "releasing"
                write_json(REC / f"{rid}.json", rec)
                notice_pass(entry, rec, "resume", budget)
                write_json(REC / f"{rid}.json", rec)
                left = [r for r in rec["recipients"] if not r.get("resume_at")]
                if left:
                    print(f"RELEASING {lab} round={rid} 남은={len(left)}")
                    rc = 3
                    continue
                rec["stage"] = "released"
                rec["ended_at"] = NOW
                write_json(REC / f"{rid}.json", rec)
                del state[prov]
                if state:
                    write_json(FILE, state)
                else:
                    try:
                        FILE.unlink()
                    except FileNotFoundError:
                        pass
                print(f"{'EXPIRED' if NOW >= until else 'RELEASED'} {lab} round={rid}")
            else:
                # 정지 중이어도 «못 보낸 예고»는 이 호출이 이어서 보낸다(부분 실패·바쁜 좌석 복구 주체 = 판정기).
                if rec.get("stage") == "set" and any(not r.get("notice_at") for r in rec["recipients"]):
                    notice_pass(entry, rec, "set", budget)
                    write_json(REC / f"{rid}.json", rec)
                print(f"PAUSED {lab} until_hhmm={hhmm(until)} until_epoch={until} "
                      f"release_hhmm={hhmm(rel) if rel else '—'} round={rid} stage={rec.get('stage', 'set')}")
                rc = 3
        if rc == 0:
            print("pause=none")
        fold_records()
        return rc
    finally:
        release(fh)


def do_check(argv):
    want, agent, model = "", "", ""
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--check":
            i += 1
            continue
        if a in ("--agent", "--model") and i + 1 < len(argv):
            if a == "--agent":
                agent = argv[i + 1]
            else:
                model = argv[i + 1]
            i += 2
            continue
        if a.startswith("--") or want:
            print(USAGE)
            return 2
        want = a
        i += 1
    if "/" in want:
        want, model = want.split("/", 1)
    model = base_model(model)
    prov = want.strip()
    if not prov:
        prov, _ = provider_of(agent, model)
        if not prov:
            print(f"ERROR pause 판정 불가(provider) — agent={agent or '-'} model={model or '-'} 규칙표={RULE}")
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
        entry = state.get(prov)
        if not isinstance(entry, dict):
            print("OK pause=none")
            return 0
        em = base_model(entry.get("model") or "")
        if em and model and em != model:
            print("OK pause=none")
            return 0
        lab = label(prov, em or (model if not em else ""))
        print(f"PAUSED {lab} until_hhmm={hhmm(entry.get('until'))} until_epoch={int(entry.get('until') or 0)} "
              f"release_hhmm={hhmm(entry.get('release_at'))} round={entry.get('round_id', '')} stage={entry.get('stage', '') or 'set'}")
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
