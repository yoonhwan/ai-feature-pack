#!/usr/bin/env bash
# ft-resource-swapwarn-lib.sh — r633: swap>FT_RES_SWAP_MAX ∧ level>=FT_SWAP_LEVEL_MIN 은 동결·REJECT 하지 않고 «닫아도 되는 유휴 좌석» 목록을 팀장에게 쪽지로(감시자 본문 줄 수 상한 ≤245 때문에 lib).
#   FT_RES_SWAP_FREEZE=1 = swap 축만 옛 동작(swap∧level2 동결·REJECT · 쪽지 0) — level 4·disk·memfree 동결은 env 와 무관하게 그대로.
#   계기: 동결 10회 중 8회가 swap∧level 2(그때 memfree 30~36% · 3~5분 뒤 저절로 해제) — 그 사이 네 팀 spawn·교대가 막힘(골 6 «메모리 세션 제한으로 안 멈춰 있게» 충돌 · arch 115).
#   재설계 r3(DA⑥ r2 HOLD · 하드 룰 14 · arch 116): ★감시자는 기록만★ — hard 동결(disk·memfree·level 4) 판정 뒤 hard 아님 ∧ swap 경고면 swapwarn_record 가
#     .fable-team/state/swap-warn-pending.json 을 tmp→mv 로 쓰고 발신 쪽(python 한 프로세스)을 «분리 실행»(nohup + os.setsid · 기다리지 않음)한다. 감시자 안에서 회수·발신을 기다리는 지점 0.
#   발신 쪽(send): 잠금 swap-warn-send.lock.d(mkdir · 살아 있는 보유자면 바로 끝 · 죽은 pid 면 회수)로 1개만 · 회수 dry-run·mbox 발신·이름 검사 각각
#     subprocess(start_new_session) + 상한 FT_RES_SWAPWARN_CALL_CAP_SEC(7초 · 하드 룰 12) + 초과 시 os.killpg(프로세스 무리 전체) + 재시도 1 · 초과·실패 = 감시 로그 ERROR 1줄 · 서명 기록 0 · pending 그대로(다음 경고 틱 재시도).
#   목록 = ft-resource-reclaim.sh --dry-run --preventive 출력의 WOULD-CLOSE 행만(승인 두 행 안 · HIL·SKIP 행 0 · 닫기 0 — 닫기는 팀장).
#     요약 줄 `PREVENTIVE reclaimed=N …` 이 없거나 N ≠ WOULD-CLOSE 행 수(dry-run 은 reclaimed = WOULD-CLOSE 수) = «회수 출력 형식 깨짐» ERROR · rc3 · 쪽지 0 — «후보 0»(WARN) 과 다른 글.
#   받는 사람 = 그 좌석 행이 있는 명부(seats*.json)들의 `_master` 값 그대로(사슬 걷기 0 — 승계는 mbox recv 의 lineage 가 이어 받는다 · `_replaced_by` 를 읽지 않는다).
#     ORPHAN = 그 명부들에서 `_master` 0개 · 서로 다른 값 2개 이상 · ft-name-lint.sh 실패 → 로그 ERROR + 하네스 명부 `_master` 앞 `[자원 경고·명부 이상]` 묶음 1통. 후보 0 팀엔 안 보냄.
#   중복 = 팀장별 서명(swap FT_RES_SWAPWARN_BAND_MIB(4096) 구간 · 좌석 목록)이 같으면 FT_RES_SWAPWARN_REPEAT_SEC(1800) 안에 다시 안 보냄(후보 0 WARN·ORPHAN 묶음도 같은 규칙) · 상태 .fable-team/state/swap-warn.json
#     없음 = 첫 실행 · 있는데 깨짐·형식 아님 = ERROR · 발신 0 · 덮어쓰기 0(사람이 보게 남김).
_SWAPWARN_PY="$(cat <<'PY'
import json, os, re, signal, subprocess, sys, time
from pathlib import Path
mode, root, stdir, logf, here = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4], Path(sys.argv[5])
mbox = sys.argv[6] if len(sys.argv) > 6 else ""
if mode == "send-bg":
    os.setsid()   # 감시자 프로세스 무리(launchd 작업)에서 떨어진다 — 감시자가 끝나도 같이 죽지 않고, 감시자는 기다리지 않는다
CAP = float(os.environ.get("FT_RES_SWAPWARN_CALL_CAP_SEC", "7"))
def log(msg):
    with open(logf, "a", encoding="utf-8") as f:
        f.write("%s\t%s\n" % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), msg))
def capped(cmd):   # 상한 + 프로세스 무리 종료 + 재시도 1 → (rc, stdout) · 124 = 상한 초과
    rc, out = 1, ""
    for _ in range(2):
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True, text=True)
        try:
            out, _ = p.communicate(timeout=CAP); rc = p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            p.communicate(); rc, out = 124, ""
        if rc == 0:
            return 0, out
    return rc, out
def why(rc):
    return "rc=%d%s" % (rc, " (상한 %g초 초과 · 프로세스 무리 종료)" % CAP if rc == 124 else "")
lock = stdir / "swap-warn-send.lock.d"
for _ in range(2):
    try:
        os.mkdir(lock); break
    except FileExistsError:
        try:
            pid = int((lock / "pid").read_text().strip())
            os.kill(pid, 0); sys.exit(0)   # 살아 있는 발신 쪽이 있다 — 1개만
        except (OSError, ValueError):
            for f in lock.glob("*"):
                f.unlink()
            lock.rmdir()
else:
    sys.exit(0)
(lock / "pid").write_text(str(os.getpid()))
def main():
    pend = stdir / "swap-warn-pending.json"
    if not pend.exists():
        return 0
    pst = pend.stat().st_mtime_ns
    try:
        pd = json.loads(pend.read_text(encoding="utf-8")); swap, level = int(pd["swap"]), int(pd["level"])
    except (OSError, ValueError, KeyError, TypeError) as e:
        log("ERROR swap 닫기 목록 pending 깨짐 %s: %s — 발신 0" % (pend, str(e)[:80])); return 4
    state, st = stdir / "swap-warn.json", {}
    if state.exists():
        try:
            st = json.loads(state.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            log("ERROR swap 닫기 목록 상태 파일 깨짐 — %s 읽기·파싱 실패: %s · 발신 0 · 파일 그대로(사람 확인)" % (state, str(e)[:80])); return 4
        if not isinstance(st, dict) or not all(isinstance(v, dict) for v in st.values()):
            log("ERROR swap 닫기 목록 상태 파일 깨짐 — %s 형식 아님(객체의 객체) · 발신 0 · 파일 그대로(사람 확인)" % state); return 4
    def mark(key, sig):
        st[key] = {"sig": sig, "ts": int(time.time())}
        tmp = state.with_name(state.name + ".tmp")
        tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8"); tmp.replace(state)
    rc, out = capped(["bash", os.environ.get("FT_RECLAIM_SH") or str(here / "ft-resource-reclaim.sh"), "--dry-run", "--preventive"])
    if rc != 0:
        log("ERROR swap 닫기 목록 회수 도구 %s — 동결 0 · 쪽지 0" % why(rc)); return 3
    lines = out.splitlines()
    would = [c[0].strip() for c in (ln.split(" | ") for ln in lines) if len(c) == 4 and c[3].startswith("WOULD-CLOSE")]
    summ = [m for m in (re.match(r"^PREVENTIVE reclaimed=(\d+) candidates=(\d+)", ln) for ln in lines) if m]
    if not summ:
        log("ERROR swap 닫기 목록 회수 출력 형식 깨짐 — 요약 줄(PREVENTIVE reclaimed=… candidates=…) 없음 · 동결 0 · 쪽지 0"); return 3
    if int(summ[-1].group(1)) != len(would):
        log("ERROR swap 닫기 목록 회수 출력 형식 깨짐 — 요약 reclaimed=%s ≠ WOULD-CLOSE 행 %d · 동결 0 · 쪽지 0" % (summ[-1].group(1), len(would))); return 3
    masters_of, harness_master = {}, None
    for f in sorted((root / ".fable-team").glob("seats*.json")):
        try:
            d = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(d, dict):
            continue
        if f.name == "seats-harness.json":
            harness_master = d.get("_master")
        for k, v in d.items():
            if not k.startswith("_") and isinstance(v, dict):
                masters_of.setdefault(k, set())
                if d.get("_master"):
                    masters_of[k].add(d["_master"])
    lint_ok = {}
    def name_ok(m):
        if m not in lint_ok:
            lint_ok[m] = capped(["bash", str(here / "ft-name-lint.sh"), m])[0] == 0
        return lint_ok[m]
    band = swap // int(os.environ.get("FT_RES_SWAPWARN_BAND_MIB", "4096")); rep = int(os.environ.get("FT_RES_SWAPWARN_REPEAT_SEC", "1800")); now = int(time.time())
    def due(key, sig):
        old = st.get(key) or {}
        return not (old.get("sig") == sig and now - int(old.get("ts", 0)) < rep)
    by, orph = {}, []
    for s in sorted(set(would)):
        ms = masters_of.get(s)
        if ms is None:
            orph.append((s, "명부에 없음"))
        elif len(ms) != 1:
            orph.append((s, "_master %s" % ("0개" if not ms else "갈림(" + ",".join(sorted(ms)) + ")")))
        else:
            m = next(iter(ms))
            if m == s or not name_ok(m):
                orph.append((s, "_master %s 이름 검사 실패" % m))
            else:
                by.setdefault(m, []).append(s)
    err = 0
    def mail(to, body):
        return capped(["bash", mbox, "send", to, "ft-resource-watch", body])[0]
    if not would and due("_none", "%d|" % band):
        log("WARN swap=%dM level=%d close-list 후보 0(닫아도 되는 유휴 좌석 없음) — 동결 0" % (swap, level)); mark("_none", "%d|" % band)
    if orph:
        sig = "%d|%s" % (band, " ".join(s for s, _ in orph))
        if due("_orphan", sig):
            for s, w in orph:
                log("ERROR swap 닫기 목록 수신자 없음 %s — %s · 보내기 0" % (s, w))
            if not harness_master:
                log("ERROR swap 닫기 목록 명부 이상 묶음 수신자 없음(seats-harness.json _master)"); err = 1
            else:
                rc = mail(harness_master, "[자원 경고·명부 이상] swap %dMiB level %d — 닫아도 되는 유휴 좌석인데 팀장을 못 정함: %s · 명부 확인" % (swap, level, " · ".join("%s(%s)" % o for o in orph)))
                if rc == 0:
                    mark("_orphan", sig)
                else:
                    log("ERROR swap 닫기 목록 명부 이상 묶음 발신 실패 to=%s %s (재시도 1 포함)" % (harness_master, why(rc))); err = 1
    sent = 0
    for m, ss in sorted(by.items()):
        sig = "%d|%s" % (band, " ".join(ss))
        if not due(m, sig):
            continue
        rc = mail(m, "[자원 경고] swap %dMiB level %d — 닫아도 되는 유휴 좌석: %s · 팀장이 닫기(nano-close 경로) · 새 spawn 은 막지 않음" % (swap, level, " ".join(ss)))
        if rc == 0:
            mark(m, sig); sent += len(ss)
        else:
            log("ERROR swap 닫기 목록 쪽지 발신 실패 to=%s %s (재시도 1 포함)" % (m, why(rc))); err = 1
    if sent:
        log("WARN swap=%dM level=%d close-list sent n=%d — 동결 0(r633 · swap 축 옛 동작 FT_RES_SWAP_FREEZE=1)" % (swap, level, sent))
    if err:
        return 3
    if pend.exists() and pend.stat().st_mtime_ns == pst:
        pend.unlink()   # 다 보냈고 그새 새 기록이 없으면 처리 끝 · 실패면 그대로 둬 다음 경고 틱이 재시도
    return 0
try:
    rc = main()
finally:
    for f in lock.glob("*"):
        f.unlink()
    lock.rmdir()
sys.exit(rc)
PY
)"

_swapwarn_args() { # 발신 쪽 인자: 루트 · 상태 폴더 · 로그 · bin · mbox (mbox 못 풀면 rc≠0)
  local mb="${FT_MBOX_SH:-}" cm
  [ -n "$mb" ] || { . "$HERE/ft-harness-root.sh" && cm="$(ft_comm_dir "$HERE")" && mb="$cm/mbox.sh"; } || return 3
  _SW_ARGS=("$RES_ROOT" "$STATE" "$LOG" "$HERE" "$mb")
}

swapwarn_record() { # $1=swap MiB $2=level $3=memfree — 감시자 tick: 기록 1개 + 발신 쪽 분리 실행(기다리지 않음) · 언제나 곧바로 돌아온다
  local p="$STATE/swap-warn-pending.json"
  printf '{"swap": %s, "level": %s, "memfree": %s, "ts": %s}\n' "$1" "$2" "${3:-0}" "$(now_epoch)" > "$p.tmp.$$" && mv -f "$p.tmp.$$" "$p" \
    || { logline "ERROR swap 닫기 목록 기록 실패 $p — 동결 0"; return 3; }
  _swapwarn_args || { logline "ERROR swap 닫기 목록 우편함 못 풂 — 동결 0 · 기록은 남음"; return 3; }
  nohup python3 -c "$_SWAPWARN_PY" send-bg "${_SW_ARGS[@]}" </dev/null >/dev/null 2>>"$LOG" &
  return 0
}

swapwarn_send_now() { # 발신 쪽을 이 셸에서 바로(시험·사람 점검용) — rc = 발신 쪽 rc(0 정상 · 3 실패 · 4 기록·상태 깨짐)
  _swapwarn_args || { logline "ERROR swap 닫기 목록 우편함 못 풂"; return 3; }
  python3 -c "$_SWAPWARN_PY" send "${_SW_ARGS[@]}"
}
