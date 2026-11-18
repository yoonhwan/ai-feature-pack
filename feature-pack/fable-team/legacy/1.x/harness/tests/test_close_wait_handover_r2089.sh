#!/usr/bin/env bash
# test_close_wait_handover_r2089.sh — r2089 C1~C5: 후계 개설 직후(도달 파일 나이 ≤ 창) «[인계] 없음 · 세션 살아 있음» = WAIT rc 4 · [크리티컬] 0 · 창 밖 = stall-scan 승계 감시 1통.
#   반례 ①~⑥ (카드 r2089-close-handover-missing-open-window) + 변이 M1~M5(사본 · 같은 사례 원본 1회 대조) + bin↔kit cmp.
#   격리: 정본 comm 사본 + 임시 명부·우편함 + tmux·reap 스텁 + 가짜 [크리티컬] mbox · 실 명부·실 큐·실 tmux 0 · sleep 0 · 시계 = FT_NOW.
#   R2089_BIN = 시험할 bin(기준판 = 팩 origin/main 사본 → ① Red) · R2089_BASE_REF = ④ 기준판(기본 origin/main · fetch 0) · 인자 = 사례 이름.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CRITICAL_OFF FT_CRITICAL_STATE_DIR FT_ROOT FT_NOW FT_HANDOVER_READY_WAIT_S; do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TRK="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"; SRC="$REPO/harness/comm"; BIN="${R2089_BIN:-$TRK}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
O='byz-zz-arch-pi#1'; N='byz-zz-arch-pi#2'; M='byz-zz-master-pi#1'; DESK='byz-planner-desk-pi#9'; NOW="$(date +%s)"
mkdir -p "$T/mstub" "$T/cstub"; printf '#!/bin/sh\nexit 1\n' > "$T/mstub/tmux"
cat > "$T/cstub/tmux" <<'EOF'
#!/bin/sh
n="${3#=}"; n="${n%:}"
case "$1" in has-session) grep -qxF "$n" "$TS/alive";; list-sessions) cat "$TS/alive";; display-message) echo 0;; show-options) ;;
  kill-session) echo "$n" >> "$TS/kills"; grep -vxF "$n" "$TS/alive" > "$TS/a2"; mv "$TS/a2" "$TS/alive";; *) exit 1;; esac
EOF
printf '#!/bin/sh\necho "reap $1 found=0 left=0"\n' > "$T/cstub/reap.sh"
printf '#!/bin/sh\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$TS/crit.log"; echo "QUEUED seq=9 to=$2"\n' > "$T/cstub/mbox.sh"
chmod +x "$T"/mstub/* "$T"/cstub/*
cat > "$T/reach.py" <<'PY'
import json, os, sys, time
p, n, k, now = sys.argv[1:5]; os.makedirs(os.path.dirname(p), exist_ok=True)
at = lambda d: time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(float(now) - d))
row = {"successor": n, "seq": 5, "reached_at": at(-60 if k == "future" else 0 if k in ("broken", "noat") else float(k) if k != "none" else 0)}
if k == "noat": row.pop("reached_at")
if k != "none": open(p, "w").write("{oops" if k == "broken" else json.dumps(row) + "\n")
PY
new_env() {   # 격리 루트 1개 · [HIL] 1통 받음 · 명부 = 승계 표기(retire 뒤) · [인계] 0
  E="$(cd "$(mktemp -d "$T/env.XXXXXX")" && pwd -P)"; C="$E/.fable-team/comm"; TS="$E/ts"; export TS
  mkdir -p "$C" "$TS"; git -C "$E" init -q; cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"
  printf '{}\n' > "$E/.fable-team/seats.json"; printf '{"_master":"p#1","_desk":"%s"}\n' "$DESK" > "$E/.fable-team/seats-planner.json"
  printf '{"_master":"%s","%s":{"role":"master"},"%s":{"role":"stop-ready","agent":"pi","_replaced_by":"%s"},"%s":{"role":"arch","agent":"pi","_replaces":["%s"]}}\n' "$M" "$M" "$O" "$N" "$N" "$O" > "$E/.fable-team/seats-zz.json"
  printf '{"seq": 1, "ts": "2026-11-11T00:00:00", "to": "%s", "from": "slack-oppa", "body": "[HIL] q1"}\n' "$O" > "$C/mailbox.jsonl"; : > "$TS/crit.log"; printf '%s\n%s\n' "$O" "$N" > "$TS/alive"
  sh_ recv "$O"; [ -n "${1:-}" ] && python3 "$T/reach.py" "$E/.fable-team/state/successor/$O.json" "$N" "$1" "$NOW"; return 0
}
xenv() { ( unset FT_PLANNER_HEAD_MODE; export FT_SEATS_JSON="$E/.fable-team/seats.json" FT_MBOX_DIR="$C" FT_MBOX_STATE_DIR="$E/.fable-team/state" FT_MBOX_RATE_N=999 \
  FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py"; "$@" ); }
sh_() { OUT="$(cd "$E" && PATH="$T/mstub:$PATH" xenv timeout 20 bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
close() {   # close <bin> <FT_NOW> [더 인자] — 실 ft-seat-close(자기 --wrap → ft-critical-notify) 1회
  local b="$1" t="$2"; shift 2
  OUT="$(cd "$E" && PATH="$T/cstub:$PATH" FT_NOW="$t" FT_MBOX="$T/cstub/mbox.sh" FT_SEAT_REAP_BIN="$T/cstub/reap.sh" ZC_RESUME_DIR="$E/resume" \
    xenv timeout 30 bash "$b/ft-seat-close.sh" "$O" --reason "retire -> $N" --seats "$E/.fable-team/seats-zz.json" "$@" 2>/dev/null)"; RC=$?; }
ncrit() { grep -c '\[크리티컬\]' "$TS/crit.log"; }
nstate() { cat "$E/.fable-team/state/critical-pending.jsonl" "$E/.fable-team/state/critical-sent.jsonl" 2>/dev/null | grep -c .; }
REJ="REJECT $O [인계] 없음 · 세션 살아 있음 — handover 먼저 또는 --verdict(명부 쓰기 0 · kill 0)"
c1() {   # ① 도달 60초 전 → WAIT rc 4 · 명부 불변 · kill 0 · [크리티컬] 0
  local b="${1:-$BIN}"; new_env 60; cp "$E/.fable-team/seats-zz.json" "$T/r.before"; close "$b" "$NOW"
  [ "$RC" = 4 ] && [ "${OUT%%$'\n'*}" = "WAIT $O 후계 $N [인계] 기다림(60초 · 창 600초) — bash mbox.sh handover $O $N (명부 쓰기 0 · kill 0)" ] || { echo "  rc=$RC $OUT"; return 1; }
  cmp -s "$T/r.before" "$E/.fable-team/seats-zz.json" && [ ! -s "$TS/kills" ] && [ "$(ncrit)/$(nstate)" = 0/0 ] || { echo "  부수효과 crit=$(ncrit) state=$(nstate)"; return 1; }
}
c2() {   # ② 도달 601초 전 → REJECT rc 1 · [크리티컬] 1
  local b="${1:-$BIN}"; new_env 601; close "$b" "$NOW"
  [ "$RC" = 1 ] && [ "${OUT%%$'\n'*}" = "$REJ" ] && [ "$(ncrit)" = 1 ] || { echo "  rc=$RC crit=$(ncrit) $OUT"; return 1; }
}
c3() {   # ③ 도달 파일 없음 / JSON 깨짐 / reached_at 없음 / 미래 → ② 와 같은 REJECT rc 1
  local b="${1:-$BIN}" k
  for k in none broken noat future; do new_env "$k"; close "$b" "$NOW"; [ "$RC" = 1 ] && [ "${OUT%%$'\n'*}" = "$REJ" ] && [ "$(ncrit)" = 1 ] || { echo "  $k rc=$RC $OUT"; return 1; }; done
}
four() {   # four <bin> <갈래> → "rc|첫 줄"(숫자 가림) · 도달 60초 전(새 갈래가 끼어들 자리)
  new_env 60; local t="$NOW" a=()
  case "$2" in verdict) a=(--verdict 1);; dead) printf '%s\n' "$N" > "$TS/alive";; ready) sh_ handover "$O" "$N"; t=$((NOW + 60));; esac
  close "$1" "$t" ${a[@]+"${a[@]}"}; printf '%s|%s' "$RC" "$(printf '%s\n' "$OUT" | head -1 | sed -E 's/#[0-9]+/#N/g; s/[0-9]+초 ·/N초 ·/')"
}
c4() {   # ④ --verdict / 세션 없음(dead-seat) / [인계] 뒤 [레디] 없음(r2080 WAIT) → 기준판과 같은 rc · 첫 줄
  local base="$T/base" k a z
  [ -d "$base" ] || { mkdir -p "$base" && git -C "$TRK" archive "${R2089_BASE_REF:-origin/main}" . | tar -x -C "$base"; } || { echo "  기준판 bin 못 뜸 — 판정 불가"; return 1; }
  for k in verdict dead ready; do a="$(four "$BIN" "$k")"; z="$(four "$base" "$k")"; [ "$a" = "$z" ] || { echo "  $k 지금=[$a] 기준판=[$z]"; return 1; }; echo "  $k = 기준판 [${a:0:80}]"; done
}
cat > "$T/c56.py" <<'PY'
import json, shutil, subprocess, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from _stall_world import World, counts, NOW
BIN, SRC, TMP, LINT, REACH, want = Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), sys.argv[5], sys.argv[6], sys.argv[7]
O, N = "byz-t1-arch-pi#1", "byz-t1-arch-pi#2"
def setup(name, o=None, live=True, handover=False, reach="601"):
    w = World(TMP / name); c = w.root / ".fable-team/comm"
    for f in [*SRC.glob("mbox*.py"), *SRC.glob("mbox*.sh"), SRC / "bang_command_check.py"]: shutil.copy(f, c / f.name)
    (c / "mailbox.jsonl").write_text(json.dumps({"seq": 1, "ts": "2026-11-11T00:00:00", "to": O, "from": "slack-oppa", "body": "[HIL] q1"}) + "\n")
    p = w.root / ".fable-team/seats-planner.json"; d = json.loads(p.read_text()); d["_desk"] = "desk#9"; p.write_text(json.dumps(d))
    (w.root / ".fable-team/seats.json").write_text("{}"); w.live += [O, N] if live else [N]; w._tmux()
    for s in ("planner#1", "t1-master#1", "t1-nano#0", O, N): w.state(s, "WORKING", 0.1)
    w.env.update(FT_SEATS_JSON=str(w.root / ".fable-team/seats.json"), FT_MBOX_STATE_DIR=str(w.root / ".fable-team/state"), FT_MBOX_RATE_N="999",
                 FT_MBOX_FANOUT_WINDOW="0", FT_NAME_LINT=LINT, FT_MBOX_PY=str(c / "mbox.py"), FT_STALL_PENALTY_AUTO="0")
    mb = lambda *a: subprocess.run(["bash", str(c / "mbox.sh"), *a], env=w.env, cwd=w.root, capture_output=True, timeout=20)
    mb("recv", O); mb("handover", O, N) if handover else mb("mark", O, "1", "처리함")
    p = w.root / ".fable-team/seats-t1.json"; d = json.loads(p.read_text())
    d[O] = o or {"role": "stop-ready", "agent": "pi", "_replaced_by": N}; d[N] = {"role": "arch", "agent": "pi", "_replaces": [O]}; p.write_text(json.dumps(d))
    subprocess.run([sys.executable, REACH, str(w.root / f".fable-team/state/successor/{O}.json"), N, reach, str(NOW)], check=True)
    return w
def scan(w):
    r = subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr[-400:]
    sent = w.root / ".fable-team/state/critical-sent.jsonl"
    return counts(r.stdout)["w"], [l for l in w.mbox_log() if "[크리티컬]" in l], sent.read_text() if sent.exists() else "", r.stdout
if want in ("5", "5a"):   # ⑤ 60초 전 = 0 · w=0
    w, cr, _, out = scan(setup("in", reach="60")); assert w == "0" and not cr, out
if want in ("5", "5b"):   # ⑤ 601초 전 = 1통(구·후계·지문 handover-missing) · w=1 · 한 번 더 = 합 1 / 도달 파일 없음 = 1
    x = setup("out"); w, cr, sent, out = scan(x)
    assert w == "1" and len(cr) == 1 and O in cr[0] and N in cr[0] and "handover-missing" in sent, (out, cr, sent)
    assert len(scan(x)[1]) == 1
    w, cr, _, out = scan(setup("none", reach="none")); assert w == "1" and len(cr) == 1, out
if want == "6":   # ⑥ [인계] 있음 · [레디] 없음 601초 = ready-missing 1통 / 세션 없음 · nano · _closed = 0
    x = setup("rdy", handover=True); x.set_now(NOW + 601); w, cr, sent, out = scan(x)
    assert w == "1" and len(cr) == 1 and "ready-missing" in sent and "handover-missing" not in sent, (out, sent)
    for k, kw in (("dead", dict(live=False)), ("nano", dict(o={"role": "nano", "agent": "pi", "_replaced_by": N})),
                  ("cl", dict(o={"role": "stop-ready", "agent": "pi", "_replaced_by": N, "_closed": {"at": "x"}}))):
        w, cr, _, out = scan(setup(k, **kw)); assert w == "0" and not cr, (k, out)
PY
py() { python3 "$T/c56.py" "$HERE/scripts" "$1" "$SRC" "$(mktemp -d "$T/w.XXXXXX")" "$REPO/harness/bin/ft-name-lint.sh" "$T/reach.py" "$2" 2>&1 | tail -3 | sed 's/^/  /'; return "${PIPESTATUS[0]}"; }
c5() { py "${1:-$BIN}" "${2:-5}"; }; c6() { py "${1:-$BIN}" 6; }
s0=$SECONDS; run() { local c="$1"; shift; if "$c" "$@"; then ok "사례 $c"; else bad "사례 $c"; fi; }
if [ $# -gt 0 ]; then for c in "$@"; do run "$c"; done; echo "FAIL=$fail"; [ "$fail" = 0 ]; exit $?; fi
for c in c1 c2 c3 c4 c5 c6; do run "$c"; done; echo "단계 사례 $((SECONDS-s0))초"; s0=$SECONDS
[ -z "${R2089_BIN:-}" ] || { echo "FAIL=$fail"; [ "$fail" = 0 ]; exit $?; }
MB="$T/mbin"; cp -Rp "$TRK" "$MB"
mutate() {  # $1 이름 $2 파일 $3 원문 $4 바꿀 글 $5 사례 [$6 갈래] — 사본 FAIL ∧ 원본 PASS
  python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p, encoding="utf-8").read(); assert s.count(a) == 1, s.count(a); open(p, "w", encoding="utf-8").write(s.replace(a, b))' "$MB/$2" "$3" "$4" || { bad "변이 $1 — 자리 못 찾음"; return; }
  "$5" "$MB" ${6:-} >/dev/null 2>&1 && bad "변이 $1 → $5 ${6:-} 살아남음" || ok "변이 $1 → $5 ${6:-} FAIL"
  "$5" "$BIN" ${6:-} >/dev/null 2>&1 && ok "변이 $1 대조 원본 $5 ${6:-} PASS" || bad "변이 $1 대조 원본 $5 FAIL"; cp -p "$TRK/$2" "$MB/$2"
}
mutate "M1 창 비교 지움(항상 WAIT)" ft-seat-close.sh 'and 0 <= a <= s' 'and True' c2
mutate "M2 도달 파일 없음 = WAIT" ft-seat-close.sh 'except (OSError, ValueError, KeyError, TypeError): sys.exit(1)' 'except (OSError, ValueError, KeyError, TypeError): print("WAIT x"); sys.exit(0)' c3
mutate "M3 닫기 rc 4 → 1" ft-seat-close.sh '&& finish 4 "$w"' '&& finish 1 "$w"' c1
mutate "M4 승계 감시 새 갈래 지움" ft_stall_scan.py 'elif first.startswith(f"REJECT {old} [인계] 없음")' 'elif False' c5 5b
mutate "M5 승계 감시 창 안도 알림" ft_stall_scan.py 'if a is None or not 0 <= a <= s:' 'if True:' c5 5a
echo "단계 변이 $((SECONDS-s0))초"
for f in ft-seat-close.sh ft_stall_scan.py; do cmp -s "$TRK/$f" "$KIT/$f" && ok "짝 사본 $f" || bad "짝 사본 $f"; done
echo "FAIL=$fail"; [ "$fail" = 0 ]
