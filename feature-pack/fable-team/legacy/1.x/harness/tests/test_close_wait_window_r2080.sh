#!/usr/bin/env bash
# test_close_wait_window_r2080.sh — r2080 B1~B4: 승계 창 안 «후계 [레디] 없음» = WAIT rc 4(close-check) → ft-seat-close WAIT rc 4 · [크리티컬] 0.
#   반례 ⑥~⑩ (카드 r2080-succession-tick-field-close-alarm-window) + 변이 M5~M10(사본 · 같은 사례 원본 1회 대조) + bin↔kit cmp.
#   격리: 정본 comm 사본 + 임시 명부·우편함 + tmux·reap 스텁 + 가짜 [크리티컬] mbox(FT_MBOX) · 실 명부·실 큐·실 tmux 0 · sleep 0.
#   시계 = FT_NOW(= [인계] ts + 초) · R2080_COMM·R2080_BIN = 시험할 comm·bin(기준판 = 팩 origin/main 사본 → ⑥ ⑦ Red) · 인자 = 사례 이름.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CRITICAL_OFF FT_CRITICAL_STATE_DIR FT_ROOT FT_NOW FT_HANDOVER_READY_WAIT_S; do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TRK="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
SRC="${R2080_COMM:-$REPO/harness/comm}"; BIN="${R2080_BIN:-$TRK}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
O='byz-zz-arch-pi#1'; N='byz-zz-arch-pi#2'; X='byz-zz-arch-pi#3'; M='byz-zz-master-pi#1'; DESK='byz-planner-desk-pi#9'
mkdir -p "$T/mstub" "$T/cstub"
printf '#!/bin/sh\nexit 1\n' > "$T/mstub/tmux"   # 우편함 쪽 = r1600 꼴(doorbell 0)
cat > "$T/cstub/tmux" <<'EOF'
#!/bin/sh
echo "$*" >> "$TS/tmux.calls"
n="${3#=}"; n="${n%:}"
case "$1" in
  has-session) grep -qxF "$n" "$TS/alive";;
  list-sessions) cat "$TS/alive";;
  display-message) echo 0;;
  show-options) ;;
  kill-session) echo "$n" >> "$TS/kills"; grep -vxF "$n" "$TS/alive" > "$TS/a2"; mv "$TS/a2" "$TS/alive";;
  *) exit 1;;
esac
EOF
printf '#!/bin/sh\necho "reap $1 found=0 left=0"\n' > "$T/cstub/reap.sh"
cat > "$T/cstub/mbox.sh" <<'EOF'
#!/bin/sh
printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$TS/crit.log"; echo "QUEUED seq=9$(wc -l < "$TS/crit.log" | tr -d ' ') to=$2"
EOF
chmod +x "$T"/mstub/* "$T"/cstub/*

roster() {   # roster <retired 0|1>
  python3 - "$E/.fable-team/seats-zz.json" "$1" "$O" "$N" "$M" <<'PY'
import json, sys
p, r, o, n, m = sys.argv[1], sys.argv[2] == "1", *sys.argv[3:6]
d = {"_master": m, m: {"role": "master"}, o: {"role": "arch", "agent": "pi"}, n: {"role": "arch", "agent": "pi", "_replaces": [o]}}
if r: d[o] = {"role": "stop-ready", "agent": "pi", "_replaced_by": n}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [comm 원본] — 격리 루트 1개
  E="$(cd "$(mktemp -d "$T/env.XXXXXX")" && pwd -P)"; C="$E/.fable-team/comm"; Q="$C/mailbox.jsonl"; TS="$E/ts"; export TS
  mkdir -p "$C" "$E/.fable-team/state" "$TS"; git -C "$E" init -q
  cp "${1:-$SRC}"/mbox*.py "${1:-$SRC}"/mbox*.sh "${1:-$SRC}"/bang_command_check.py "$C/"
  printf '{}\n' > "$E/.fable-team/seats.json"; printf '{"_master":"byz-planner-master-pi#1","_desk":"%s"}\n' "$DESK" > "$E/.fable-team/seats-planner.json"
  roster 0; : > "$Q"; : > "$TS/crit.log"; printf '%s\n%s\n%s\n' "$O" "$N" "$X" > "$TS/alive"
}
xenv() { ( unset FT_PLANNER_HEAD_MODE
  export FT_SEATS_JSON="$E/.fable-team/seats.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$E/.fable-team/state"
  export FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py"
  "$@" ); }
sh_() { OUT="$(cd "$E" && PATH="$T/mstub:$PATH" xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
cc() { OUT="$(cd "$E" && PATH="$T/mstub:$PATH" FT_NOW="$(at "$1")" xenv timeout 20 python3 "$C/mbox.py" close-check "$O" 2>&1)"; RC=$?; }   # cc <[인계] 뒤 초>
ccnow() { OUT="$(cd "$E" && PATH="$T/mstub:$PATH" FT_NOW="$(date +%s)" xenv timeout 20 python3 "$C/mbox.py" close-check "$O" 2>&1)"; RC=$?; }   # 시계 = 지금(ts 를 고친 사례)
close() {   # close <bin> <[인계] 뒤 초> — 실 ft-seat-close(자기 --wrap → ft-critical-notify) 1회
  OUT="$(cd "$E" && PATH="$T/cstub:$PATH" FT_NOW="$(at "$2")" FT_MBOX="$T/cstub/mbox.sh" FT_SEAT_REAP_BIN="$T/cstub/reap.sh" ZC_RESUME_DIR="$E/resume" \
    xenv timeout 30 bash "$1/ft-seat-close.sh" "$O" --reason "retire -> $N" --seats "$E/.fable-team/seats-zz.json" 2>/dev/null)"; RC=$?; }
seqof() { printf '%s\n' "$OUT" | sed -n 's/^QUEUED seq=\([0-9]*\).*/\1/p' | head -1; }
at() { python3 - "$C/mailbox.log.jsonl" "$HS" "$1" <<'PY'
import json, sys, time
p, hs, d = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
r = next(json.loads(l) for l in open(p, encoding="utf-8") if json.loads(l).get("seq") == hs)
print(time.mktime(time.strptime(r["ts"][:19], "%Y-%m-%dT%H:%M:%S")) + d)
PY
}
setup() {   # setup [comm 원본] — 옛 [인계] 1통 · retire 표기 · 후계 recv 까지([레디] 0 · HS = [인계] seq)
  new_env "${1:-}"; printf '{"seq": 1, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "[HIL] q1"}\n' "$O" >> "$Q"
  sh_ recv "$O"; sh_ handover "$O" "$N"; HS="$(seqof)"; [ -n "$HS" ] || return 1
  roster 1; sh_ recv "$N"
}
edit_ts() {   # edit_ts drop|future — [인계] 줄의 ts 칸을 지우거나 미래(+1일)로
  python3 - "$C/mailbox.log.jsonl" "$HS" "$1" <<'PY'
import json, sys, time
p, hs, how = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = [json.loads(l) for l in open(p, encoding="utf-8")]
for r in rows:
    if r.get("seq") == hs:
        if how == "drop": r.pop("ts")
        else: r["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() + 86400))
open(p, "w", encoding="utf-8").writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)
PY
}
ncrit() { grep -c '\[크리티컬\]' "$TS/crit.log"; }
nstate() { cat "$E/.fable-team/state/critical-pending.jsonl" "$E/.fable-team/state/critical-sent.jsonl" 2>/dev/null | grep -c .; }

c6() {   # ⑥ 60초 → WAIT rc 4 · 601초 → REJECT rc 3 · ts 없음 · 미래 ts → REJECT rc 3
  setup || return 2
  cc 60; [ "$RC" = 4 ] && [[ "${OUT%%$'\n'*}" == "WAIT $O [인계] #$HS 뒤 후계 [레디] 기다림(60초 · 창 600초) — 후계가 bash mbox.sh ready $N $O" ]] || { echo "  60초 rc=$RC $OUT"; return 1; }
  cc 601; [ "$RC" = 3 ] && [[ "$OUT" == "REJECT $O [인계] #$HS 뒤 후계 [레디] 없음"* ]] || { echo "  601초 rc=$RC $OUT"; return 1; }
  edit_ts future; ccnow; [ "$RC" = 3 ] && [[ "$OUT" == REJECT*"후계 [레디] 없음"* ]] || { echo "  미래 rc=$RC $OUT"; return 1; }
  edit_ts drop; ccnow
  [ "$RC" = 3 ] && [[ "$OUT" == REJECT*"후계 [레디] 없음"* ]] || { echo "  ts 없음 rc=$RC $OUT"; return 1; }
}
c7() {   # ⑦ ft-seat-close(--wrap 경유) 60초 → rc 4 · 명부 바이트 같음 · kill 0 · [크리티컬] 기록 0 / 601초 → rc 1 · [크리티컬] 1통
  local b="${1:-$BIN}"; setup || return 2
  cp "$E/.fable-team/seats-zz.json" "$T/r.before"
  close "$b" 60; [ "$RC" = 4 ] && [[ "$OUT" == "WAIT $O [인계] #$HS 뒤 후계 [레디] 기다림(60초 · 창 600초)"*"(명부 쓰기 0 · kill 0)" ]] || { echo "  60초 rc=$RC $OUT"; return 1; }
  cmp -s "$T/r.before" "$E/.fable-team/seats-zz.json" && [ ! -s "$TS/kills" ] && [ "$(ncrit)/$(nstate)" = 0/0 ] || { echo "  60초 부수효과 kills=$(cat "$TS/kills" 2>/dev/null) crit=$(ncrit) state=$(nstate)"; return 1; }
  close "$b" 601; [ "$RC" = 1 ] && [ "$(ncrit)" = 1 ] && grep -q "\[크리티컬\] ft-seat-close $O — 무엇: .*후계 \[레디\] 없음" "$TS/crit.log" || { echo "  601초 rc=$RC crit=$(ncrit) $OUT"; return 1; }
}
c8() {   # ⑧ 누락 0 — WAIT 뒤 창 지남 = [크리티컬] 1통 / WAIT 뒤 [레디] = CLOSED-SESSION rc 0 / retire 끝 닫기 WAIT = rc 0 · WAIT 줄
  local b="${1:-$BIN}"; setup || return 2
  close "$b" 60; [ "$RC" = 4 ] && [ "$(ncrit)" = 0 ] || { echo "  ⓐ 60초 rc=$RC"; return 1; }
  close "$b" 661; [ "$RC" = 1 ] && [ "$(ncrit)" = 1 ] || { echo "  ⓐ 661초 rc=$RC crit=$(ncrit)"; return 1; }
  setup || return 2
  close "$b" 60; [ "$RC" = 4 ] || { echo "  ⓑ 60초 rc=$RC"; return 1; }
  sh_ ready "$N" "$O"; [ "$RC" = 0 ] || { echo "  ⓑ ready rc=$RC $OUT"; return 1; }
  close "$b" 120; [ "$RC" = 0 ] && [[ "$OUT" == *"CLOSED-SESSION $O "* ]] && grep -qxF "$O" "$TS/kills" && [ "$(ncrit)" = 0 ] || { echo "  ⓑ [레디] 뒤 rc=$RC $OUT"; return 1; }
  setup || return 2
  local line; line="$(grep -E '^"\$\{FT_TMUX:-tmux\}" has-session -t "=\$OLD"' "$b/ft-seat-retire.sh")"; [ -n "$line" ] || { echo "  ⓒ retire 끝 줄 못 찾음"; return 1; }
  OUT="$(cd "$E" && PATH="$T/cstub:$PATH" FT_NOW="$(at 60)" FT_MBOX="$T/cstub/mbox.sh" FT_SEAT_REAP_BIN="$T/cstub/reap.sh" FT_TMUX="$T/cstub/tmux" \
    FT_SEAT_CLOSE_BIN="$b/ft-seat-close.sh" OLD="$O" NEW="$N" ARG="$E/.fable-team/seats-zz.json" xenv bash -c "$line" 2>/dev/null)"; RC=$?
  [ "$RC" = 0 ] && [[ "$OUT" == *"WAIT $O [인계] #$HS"* ]] && [ "$(ncrit)" = 0 ] || { echo "  ⓒ retire 끝 rc=$RC $OUT"; return 1; }
}
cat > "$T/c10.py" <<'PY'
import json, os, shutil, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from _stall_world import World, counts
BIN, SRC, TMP, LINT, CSTUB = Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), sys.argv[5], Path(sys.argv[6])
O, N = "byz-t1-arch-pi#1", "byz-t1-arch-pi#2"   # 팀 글자 t1 = seats-t1.json(mbox_teamfile)


def world(name):
    w = World(TMP / name)
    c = w.root / ".fable-team/comm"
    for f in [*SRC.glob("mbox*.py"), *SRC.glob("mbox*.sh"), SRC / "bang_command_check.py"]:
        shutil.copy(f, c / f.name)
    (c / "mailbox.jsonl").touch()
    row(w, {"role": "arch", "agent": "pi"})
    pp = w.root / ".fable-team/seats-planner.json"
    dp = json.loads(pp.read_text()); dp["_desk"] = "desk#9"; pp.write_text(json.dumps(dp))
    (w.root / ".fable-team/seats.json").write_text("{}")
    w.live += [O, N]; w._tmux()
    for s in ("planner#1", "t1-master#1", "t1-nano#0", O, N):
        w.state(s, "WORKING", 0.1)
    w.env.update(FT_SEATS_JSON=str(w.root / ".fable-team/seats.json"), FT_MBOX_STATE_DIR=str(w.root / ".fable-team/state"), FT_MBOX_RATE_N="999",
                 FT_MBOX_FANOUT_WINDOW="0", FT_NAME_LINT=LINT, FT_MBOX_PY=str(c / "mbox.py"), FT_STALL_PENALTY_AUTO="0")
    return w


def row(w, o):
    p = w.root / ".fable-team/seats-t1.json"
    d = json.loads(p.read_text()); d[O] = o; d[N] = {"role": "arch", "agent": "pi", "_replaces": [O]}
    p.write_text(json.dumps(d))


def mbox(w, *a):
    r = subprocess.run(["bash", str(w.root / ".fable-team/comm/mbox.sh"), *a], env=w.env, cwd=w.root, capture_output=True, text=True, timeout=20)
    return r.stdout + r.stderr


def setup(name, o=None):
    w = world(name)
    with open(w.root / ".fable-team/comm/mailbox.jsonl", "a") as f:
        f.write(json.dumps({"seq": 1, "ts": "2026-11-11T00:00:00", "to": O, "from": "slack-oppa", "body": "[HIL] q1"}) + "\n")
    mbox(w, "recv", O)
    out = mbox(w, "handover", O, N)
    hs = int(next(l for l in out.splitlines() if l.startswith("QUEUED seq=")).split()[1][4:])
    row(w, o or {"role": "stop-ready", "agent": "pi", "_replaced_by": N})
    mbox(w, "recv", N)
    r = next(json.loads(l) for l in open(w.root / ".fable-team/comm/mailbox.log.jsonl") if json.loads(l).get("seq") == hs)
    return w, hs, time.mktime(time.strptime(r["ts"][:19], "%Y-%m-%dT%H:%M:%S"))


def scan(w, at):
    w.set_now(at)
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr[-400:]
    return r


def crit(w):
    return [l for l in w.mbox_log() if "[크리티컬]" in l]


def close(w, at):
    ts = w.root / "ts"; ts.mkdir(exist_ok=True); (ts / "alive").write_text(f"{O}\n{N}\nbyz-t1-arch-pi#3\n"); (ts / "crit.log").touch()
    env = {**w.env, "FT_NOW": str(at), "PATH": f"{CSTUB}{os.pathsep}{w.env['PATH']}", "TS": str(ts), "FT_MBOX": str(CSTUB / "mbox.sh"),
           "FT_SEAT_REAP_BIN": str(CSTUB / "reap.sh"), "ZC_RESUME_DIR": str(w.root / "resume")}
    r = subprocess.run(["bash", str(BIN / "ft-seat-close.sh"), O, "--reason", f"retire -> {N}", "--seats", str(w.root / ".fable-team/seats-t1.json")],
                       env=env, cwd=w.root, capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout


def c10a():  # 60 → 0 · w=0 / 601 → [크리티컬] 1 · w 줄 · w=1 / 1200 → 합 1
    w, hs, t0 = setup("a")
    c = close(w, t0 + 60)
    assert c[0] == 4, c
    r = scan(w, t0 + 60)
    assert counts(r.stdout)["w"] == "0" and not crit(w), (r.stdout, w.mbox_log())
    u0 = int(counts(r.stdout)["u"])
    r = scan(w, t0 + 601)
    sent = (w.root / ".fable-team/state/critical-sent.jsonl").read_text().splitlines()
    assert counts(r.stdout)["w"] == "1" and f"w {O} {N} #{hs}" in r.stdout.splitlines() and len(crit(w)) == 1 and len(sent) == 1, (r.stdout, w.mbox_log())
    assert O in crit(w)[0] and f"#{hs}" in crit(w)[0], crit(w)
    scan(w, t0 + 1200)
    assert len(crit(w)) == 1, w.mbox_log()
    return u0


def c10b():  # [레디] 뒤 → 0 · w=0 · 그 뒤 닫기 CLOSED-SESSION rc 0
    w, hs, t0 = setup("b")
    assert close(w, t0 + 60)[0] == 4
    mbox(w, "ready", N, O)
    r = scan(w, t0 + 700)
    assert counts(r.stdout)["w"] == "0" and not crit(w), (r.stdout, w.mbox_log())
    rc, out = close(w, t0 + 700)
    assert rc == 0 and f"CLOSED-SESSION {O} " in out, (rc, out)


def c10c():  # 세션 없음 / nano / _closed → 0
    for name, o, live in (("nolive", None, False), ("nano", {"role": "nano", "agent": "pi", "_replaced_by": N}, True),
                          ("closed", {"role": "stop-ready", "agent": "pi", "_replaced_by": N, "_closed": {"at": "x"}}, True)):
        w, hs, t0 = setup(name, o)
        if not live:
            w.live.remove(O); w._tmux()
        r = scan(w, t0 + 601)
        assert counts(r.stdout)["w"] == "0" and not crit(w), (name, r.stdout, w.mbox_log())


def c10d(u0):  # close-check 스텁 rc 2 · 빈 출력 → 0 · u +1 · 노트 / 미표시 쪽지 REJECT → 0
    for name, body in (("rc2", "exit 2"), ("empty", "exit 0")):
        w, hs, t0 = setup(name)
        stub = w.root / "cc.py"; stub.write_text(f"import sys\nsys.{body.replace(' ', '(')})\n")
        w.env["FT_MBOX_PY"] = str(stub)
        r = scan(w, t0 + 601)
        assert not crit(w) and int(counts(r.stdout)["u"]) == u0 + 1 and "승계 감시 판정 불가" in r.stdout, (name, u0, r.stdout)


def c10u():  # 창 뒤 REJECT 사유 = 미표시 쪽지 → 0
    w, hs, t0 = setup("unmarked")
    with open(w.root / f".fable-team/comm/receipts/{O}.jsonl", "a") as f:
        f.write(json.dumps({"seq": 77, "from": "slack-oppa", "ts": "2026-11-11T00:00:01", "body": "[HIL] q2", "body_full": ""}) + "\n")
    r = scan(w, t0 + 601)
    assert counts(r.stdout)["w"] == "0" and not crit(w), (r.stdout, w.mbox_log())


want = sys.argv[7:] or ["a", "b", "c", "d", "u"]
u0 = c10a() if "a" in want or "d" in want else 0
for k in ("b", "c", "u"):
    if k in want:
        globals()["c10" + k]()
if "d" in want:
    c10d(u0)
PY
c10() {   # c10 [bin] [갈래 a|b|c|d|u …] — ⑩ 승계 감시(B5) · 닫기는 60초 1회(WAIT) · 그 뒤 stall-scan 만 · [인계] ts 기준 시계
  local b="${1:-$BIN}"; shift || true
  python3 "$T/c10.py" "$HERE/scripts" "$b" "$SRC" "$(mktemp -d "$T/w10.XXXXXX")" "$REPO/harness/bin/ft-name-lint.sh" "$T/cstub" "$@" 2>&1 | tail -4 | sed 's/^/  /'
  return "${PIPESTATUS[0]}"
}
nine() {   # nine <comm 원본> <갈래> → "rc|첫 줄" (60초 · 창 안)
  setup "$1" >/dev/null || { echo "setup 실패"; return; }
  case "$2" in
    unmarked) printf '{"seq": 77, "from": "slack-oppa", "ts": "2026-11-11T00:00:01", "body": "[HIL] q2", "body_full": ""}\n' >> "$C/receipts/$O.jsonl";;   # recv 영수 1줄 · 표시 0
    form) python3 -c 'import json,sys,time; print(json.dumps({"seq": int(sys.argv[3]) + 50, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "to": sys.argv[2], "from": sys.argv[1], "body": "[인계] 손으로 쓴 인계 — 항목은 대화로"}, ensure_ascii=False))' "$O" "$N" "$HS" >> "$C/mailbox.log.jsonl";;   # 손으로 쓴 [인계](기계 머리 0)
    nogot) sh_ send "$O" "$N" "[레디] $O <- $N · [인계] #$HS 받음 · 항목 1";;
    held) mkdir -p "$E/.fable-team/state/doorbell-held"; printf 'held x\nseq=7\n' > "$E/.fable-team/state/doorbell-held/$O";;
  esac
  cc 60; printf '%s|%s' "$RC" "$(printf '%s\n' "$OUT" | sed "s/#[0-9][0-9]*/#N/g" | head -1)"
}
c9() {   # ⑨ 창 안(60초) 미표시 / 형식 불명 / «받음» 없는 항목 / 억제 doorbell → 기준판과 같은 REJECT 줄 · rc 3
  if [ -z "${R2080_BASE_COMM:-}" ]; then   # 기준판 = R2080_BASE_REF(기본 origin/main · fetch 0)의 comm 사본
    local pre; pre="$(git -C "$SRC" rev-parse --show-prefix 2>/dev/null)" && mkdir -p "$T/base" && git -C "$SRC" archive "${R2080_BASE_REF:-origin/main}" . | tar -x -C "$T/base" \
      || { echo "  기준판 comm 못 뜸(${R2080_BASE_REF:-origin/main}:$pre) — 판정 불가"; return 1; }
    R2080_BASE_COMM="$T/base"
  fi
  local k a z
  for k in unmarked form nogot held; do
    a="$(nine "$SRC" "$k")"; z="$(nine "$R2080_BASE_COMM" "$k")"
    [ "$a" = "$z" ] && [[ "$a" == "3|REJECT "* ]] || { echo "  $k 지금=[$a] 기준판=[$z]"; return 1; }
    echo "  $k = 기준판 [${a:0:90}]"
  done
}

s0=$SECONDS
run() { local c="$1"; shift; if "$c" "$@"; then ok "사례 $c"; else bad "사례 $c"; fi; }
if [ $# -gt 0 ]; then for c in "$@"; do run "$c"; done; echo "FAIL=$fail"; [ "$fail" = 0 ]; exit $?; fi
for c in c6 c7 c8 c9 c10; do run "$c"; done
echo "단계 사례 $((SECONDS-s0))초"; s0=$SECONDS
[ -z "${R2080_COMM:-}${R2080_BIN:-}" ] || { echo "FAIL=$fail"; [ "$fail" = 0 ]; exit $?; }

MC="$T/mcomm"; MB="$T/mbin"; cp -Rp "$SRC" "$MC"; cp -Rp "$TRK" "$MB"
mutate() {  # $1 이름 $2 사본 폴더 $3 파일 $4 원문 $5 바꿀 글 $6 사례 — 사본 FAIL ∧ 원본 PASS
  python3 - "$2/$3" "$4" "$5" <<'PY' || { bad "변이 $1 — 자리 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  if [ "$2" = "$MC" ]; then ( SRC="$MC"; "$6" ) >/dev/null 2>&1; else "$6" "$MB" ${7:-} >/dev/null 2>&1; fi; [ $? -ne 0 ] && ok "변이 $1 → $6 ${7:-} FAIL" || bad "변이 $1 → $6 살아남음"
  "$6" "$BIN" ${7:-} >/dev/null 2>&1 && ok "변이 $1 대조 원본 $6 ${7:-} PASS" || bad "변이 $1 대조 원본 $6 FAIL"
  cp -p "$SRC/$3" "$MC/$3" 2>/dev/null; cp -p "$TRK/$3" "$MB/$3" 2>/dev/null
}
mutate "M5 창 비교 지움(항상 WAIT)" "$MC" mbox_handover.py '    return (int(age), s) if 0 <= age < s else None' '    return (int(age), s)' c6
mutate "M6 닫기 rc 4 → 1" "$MB" ft-seat-close.sh '[ $? != 4 ] || finish 4 ' '[ $? != 4 ] || finish 1 ' c7
mutate "M8 승계 중 구 좌석 고르기 지움" "$MB" ft_stall_scan.py 'v["_replaced_by"] and not v.get("_closed")' 'v["_replaced_by"] and False and not v.get("_closed")' c10 a
mutate "M9 WAIT 도 알림" "$MB" ft_stall_scan.py 'hit = first.startswith("REJECT ") and " 뒤 후계 [레디] 없음" in first' 'hit = first.startswith(("REJECT ", "WAIT ")) and " 뒤 후계 [레디] " in first' c10 a
mutate "M10 다른 REJECT 도 알림" "$MB" ft_stall_scan.py 'hit = first.startswith("REJECT ") and " 뒤 후계 [레디] 없음" in first' 'hit = first.startswith("REJECT ")' c10 u
mutate "M7 ts 없음 = WAIT" "$MC" mbox_handover.py '        return None   # ts 없음·꼴 틀림' '        return 0, s   # ts 없음·꼴 틀림' c6
echo "단계 변이 $((SECONDS-s0))초"

for f in ft-seat-close.sh ft_stall_scan.py; do cmp -s "$TRK/$f" "$KIT/$f" && ok "짝 사본 $f" || bad "짝 사본 $f"; done
echo "FAIL=$fail"; [ "$fail" = 0 ]
