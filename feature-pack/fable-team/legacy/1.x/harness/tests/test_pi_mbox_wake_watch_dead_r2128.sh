#!/usr/bin/env bash
# test_pi_mbox_wake_watch_dead_r2128.sh — r2128: pi 팀장 좌석 쪽지 깨움 확장(ft-mbox-wake)의 감시가 멎어도 다시 깨운다.
#  W1 진단 줄(.beat) ①② · W2 재무장(agent_end·정상 settled·유휴 1회 타이머) ③④ · W3 바깥 복구(ft-idle-wake) ⑤⑥ · W4 반례 지킴 ⑦⑧
#  격리: 임시 루트(<케이스>/.fable-team/{comm,state}) · 합성 mailbox.jsonl · seats-*.json · 가짜 pi(sendMessage 기록) ·
#        스텁 mbox.sh(budget rc 고정 · ring · send 기록) · 가짜 tmux(send-keys 기록 · 실 tmux 0) · 가짜 HOME(확장 파일).
#  감시 멎음 재현 = 드라이버가 node:fs watch 를 대역으로 바꾼다(syncBuiltinESMExports — 제품에 시험 전용 문 0) ·
#        유휴 타이머 = 가짜 시계(FT_MBOX_WAKE_REARM_MS 값의 setTimeout 만 잡아 손으로 발화 · sleep 0).
#  기준판: R2128_EXT=<옛 ft-mbox-wake.ts> R2128_IW=<옛 ft-idle-wake.sh> R2128_MUT=0 bash <이 파일>
#  변이(사본): M1 agent_end 재무장 지움 → ③ · M2 유휴 타이머 지움 → ④ · M3 주기 타이머 → ④ · M4 .beat 비교 지움 → ⑦ ·
#        M5 IDLE 확인 지움 → ⑧a · M6 같은 seq 건너뛰기 = 모든 result → ⑤-b · M7 Escape 를 예약 앞에 → ⑧d — 변이마다 원본 대조 1회.
#  새 파일 mode 100644 — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R2128_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
IW="${R2128_IW:-$HARNESS/bin/ft-idle-wake.sh}"
MUT="${R2128_MUT:-1}"
SEAT="byz-knowledge-master-pi#107"; DESK="byz-planner-desk#3"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "기대 '$3' 실제 '$2'"; fi; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] && [ -f "$IW" ] || { echo "FAIL 대상 없음 $EXT / $IW"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r2128.XXXXXX")"; trap 'rm -rf "$T"' EXIT
t0=$(date +%s)

# ══ 확장 쪽(①~④) — 가짜 pi + fs.watch 대역 ══════════════════════════════════════════════════
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
cat > "$T/driver.mjs" <<'NODE'
import fsMod from "node:fs";
import * as path from "node:path";
import { EventEmitter } from "node:events";
import { syncBuiltinESMExports } from "node:module";
import { pathToFileURL } from "node:url";
const EXT = process.env.R2128_DRV_EXT, SEAT = process.env.R2128_SEAT, ROOT = process.env.R2128_TMP, CASES = (process.env.R2128_CASES || "1234").split("");
const REARM = 777777; let fails = 0;
const ok = (n) => console.log(`PASS ${n}`), bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const realST = globalThis.setTimeout, realCT = globalThis.clearTimeout, wait = (ms) => new Promise((r) => realST(r, ms));
const until = async (fn, ms = 800) => { const t = Date.now(); while (Date.now() - t < ms) { if (fn()) return true; await wait(10); } return fn(); };
// 가짜 시계 = 유휴 재무장 타이머(REARM ms)만 잡는다 — 다른 타이머(바운스·기동 창)는 실 타이머
const pend = new Set();
globalThis.setTimeout = (fn, ms, ...a) => { if (ms === REARM) { const h = { fn, fake: true }; pend.add(h); return h; } return realST(fn, ms, ...a); };
globalThis.clearTimeout = (h) => { if (h && h.fake) { pend.delete(h); return; } return realCT(h); };
const fire = () => { const hs = [...pend]; pend.clear(); for (const h of hs) h.fn(); return hs.length; };
// fs.watch 대역 — block 이면 사건 0(감시 멎음) · 아니면 실 감시를 그대로 잇는다 · close 는 실 Node 처럼 다음 tick 에 'close'
const realWatch = fsMod.watch, realRead = fsMod.readFileSync, W = []; let block = false, mboxPath = "", reads = 0;
fsMod.watch = (dir, cb) => { const w = new EventEmitter(); w.closed = false; const real = block ? null : realWatch(dir, (e, fn) => { if (!w.closed) cb(e, fn); });
  w.close = () => { if (w.closed) return; w.closed = true; real?.close(); process.nextTick(() => w.emit("close")); }; W.push(w); return w; };
fsMod.readFileSync = (p, ...a) => { if (p === mboxPath) reads++; return realRead(p, ...a); };
syncBuiltinESMExports();
const errs = []; console.error = (...a) => errs.push(a.join(" "));
const row = (seq, body = `[발주 #${seq}] 일`) => JSON.stringify({ seq, ts: "2026-11-16T00:00:00", to: SEAT, from: "byz-planner-desk#3", body }) + "\n";
let modv = 0;
async function load(name, blocked) {
  const dir = path.join(ROOT, name), comm = path.join(dir, ".fable-team", "comm"), state = path.join(dir, ".fable-team", "state");
  fsMod.mkdirSync(comm, { recursive: true });
  fsMod.writeFileSync(path.join(dir, ".fable-team", "seats-harness.json"), JSON.stringify({ _master: SEAT, [SEAT]: { agent: "pi" } }));
  fsMod.writeFileSync(path.join(comm, "mbox.sh"), "#!/bin/bash\nexit 0\n");
  mboxPath = path.join(comm, "mailbox.jsonl"); fsMod.writeFileSync(mboxPath, "");
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: mboxPath, FT_SEAT: SEAT, FT_MBOX_WAKE_DEBOUNCE_MS: "5", FT_MBOX_WAKE_REARM_MS: String(REARM), FT_MBOX_NOW: "1000", FT_PI_EXT_LOG: path.join(dir, "ext.log") });
  block = blocked; pend.clear(); errs.length = 0;
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, appendEntry() {},
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    sendMessage(m) { this.calls.push(m); } };
  (await import(`${pathToFileURL(EXT).href}?v=${++modv}`)).default(pi);
  const w0 = W.length; await pi.emit("session_start", {});
  await wait(300); // 기동 창 1회 재확인(debounce+250)이 지난 뒤부터 잰다
  const beatF = path.join(state, "pi-wake", `${SEAT.replace(/[^A-Za-z0-9._#-]/g, "_")}.beat`);
  const beat = () => { try { const t = realRead(beatF, "utf-8"); return { lines: t.split("\n").filter(Boolean).length, ...Object.fromEntries(t.trim().split(/\s+/).map((kv) => kv.split("="))) }; } catch { return { lines: 0 }; } };
  return { pi, mbox: mboxPath, w0, beat, mine: () => W.slice(w0) };
}
const ERR = () => errs.concat((() => { try { return realRead(process.env.FT_PI_EXT_LOG, "utf-8").split("\n"); } catch { return []; } })()).filter((l) => l.includes("ERROR ft-mbox-wake") && l.includes("감시 error"));
if (CASES.includes("1")) { // ① 기동 뒤 쪽지 1 → 깨움 1 · .beat 1줄(woke · watchers 2)
  const c = await load("c1", false);
  fsMod.appendFileSync(c.mbox, row(11));
  await until(() => c.pi.calls.length >= 1);
  const b = c.beat();
  eq("① 쪽지 1 → 깨움 1", c.pi.calls.length, 1);
  eq("① .beat 1줄 · why=woke · watchers=2 · woke>0 · event>0", `${b.lines}|${b.why}|${b.watchers}|${Number(b.woke) > 0}|${Number(b.event) > 0}`, "1|woke|2|true|true");
  await c.pi.emit("session_shutdown", {});
}
if (CASES.includes("2")) { // ② watcher 'error' → ERROR 1줄 + 그 자리 재무장 1 · 같은 이유 둘째 ERROR 0
  const c = await load("c2", false);
  const n0 = W.length, e = Object.assign(new Error("EIO"), { code: "EIO" });
  try { c.mine()[0].emit("error", e); } catch { /* 듣는 이 없음 = 기준판 */ }
  await wait(50);
  eq("② error → ERROR 1줄", ERR().length, 1);
  eq("② error → 그 자리 재무장 1(새 watcher 2 · 옛 2 닫힘)", `${W.length - n0}|${W.slice(c.w0, n0).every((w) => w.closed)}`, "2|true");
  const n1 = W.length;
  try { W[n1 - 1].emit("error", e); } catch { /* 기준판 */ }
  await wait(50);
  eq("② 같은 이유 둘째 error → ERROR 0(합 1)", ERR().length, 1);
  eq("② 둘째 error 도 재무장(새 watcher 2)", W.length - n1, 2);
  await c.pi.emit("session_shutdown", {});
}
if (CASES.includes("3")) { // ③ 감시 막힘 + 쪽지 1 → agent_end → 실제 재등록 · 그 뒤 쪽지는 감시 사건으로 깨움
  const c = await load("c3", true);
  fsMod.appendFileSync(c.mbox, row(31)); await wait(80);
  eq("③ 감시 막힘 = 쪽지 1 깨움 0", c.pi.calls.length, 0);
  const n0 = W.length; block = false; process.env.FT_MBOX_NOW = "2000";
  await c.pi.emit("agent_end", {}); await wait(50);
  eq("③ agent_end → 새 watcher 2 · 옛 것 닫힘 · close 로 재무장 0", `${W.length - n0}|${W.slice(c.w0, n0).every((w) => w.closed)}`, "2|true");
  eq("③ .beat rearm 갱신(2000)", c.beat().rearm, "2000");
  fsMod.writeFileSync(c.mbox, ""); await wait(80); // recv 가 비운 꼴 — 감시 사건 → 빈 우편함(배달 대기 해제)
  const k = c.pi.calls.length;
  fsMod.appendFileSync(c.mbox, row(32));
  await until(() => c.pi.calls.length > k);
  eq("③ 재무장 뒤 쪽지 1 → 감시 사건으로 깨움 1", c.pi.calls.length - k, 1);
  const n2 = W.length; await c.pi.emit("session_shutdown", {}); await wait(30); await c.pi.emit("agent_end", {}); fire(); await wait(30);
  eq("③ shutdown 뒤 재무장 0(close·agent_end·타이머)", W.length - n2, 0);
}
if (CASES.includes("4")) { // ④ 감시 막힘 + 유휴 진입 → 쪽지 1 → 유휴 1회 타이머 → 깨움 1 · 둘째 발화 0
  const c = await load("c4", true);
  await c.pi.emit("agent_start", {}); await c.pi.emit("agent_end", {}); await c.pi.emit("agent_settled", {});
  fsMod.appendFileSync(c.mbox, row(41)); await wait(80);
  eq("④ 감시 막힘 = 쪽지 1 깨움 0", c.pi.calls.length, 0);
  const n0 = W.length, r0 = reads, f1 = fire();
  eq("④ 유휴 타이머 1회 발화 → 재무장 1 · check 1 · 깨움 1", `${f1}|${W.length - n0}|${reads - r0}|${c.pi.calls.length}`, "1|2|1|1");
  const n1 = W.length, r1 = reads, f2 = fire();
  eq("④ 같은 유휴 둘째 = 타이머 발화 0 · 재무장 0 · check 0", `${f2}|${W.length - n1}|${reads - r1}`, "0|0|0");
  await c.pi.emit("session_shutdown", {});
}
process.exit(fails ? 1 : 0);
NODE
drv() { R2128_DRV_EXT="$1" R2128_CASES="$2" R2128_SEAT="$SEAT" R2128_TMP="$T/run-$(basename "$1" .ts)-$2" timeout 70 node "$T/driver.mjs"; }
drv "$T/ext/ft-mbox-wake.ts" 1234; drc=$?
t1=$(date +%s)

# ══ 바깥 쪽(⑤~⑧) — ft-idle-wake 확장 좌석 갈래 ════════════════════════════════════════════════
NOW="$(date +%s)"
mkdir -p "$T/stub"
cat > "$T/stub/mbox.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$BOX/calls.log"
case "$1 $2" in
  "budget reserve") [ -z "${TYPE_ON_RESERVE:-}" ] || echo "$FT_IDLE_WAKE_NOW" > "$BOX/activity"; exit "${RESERVE_RC:-0}";;
  "budget refund") exit 0;;
esac
case "$1" in
  ring) case " $* " in *" --auto "*) echo "RING $2 doorbell=ext";; *) echo "RING $2 doorbell=${RING_DB:-sent}";; esac;;
  send) echo "SENT #1";;
esac
exit 0
EOF
cat > "$T/stub/tmux.sh" <<'EOF'
#!/bin/bash
echo "$*" >> "$BOX/tmux.log"
case "$1" in
  has-session) exit 0;;
  list-clients) cat "$BOX/activity"; exit 0;;
  list-panes) echo "$SEAT_NAME|%9"; exit 0;;
  send-keys) exit 0;;
  show-environment) exit 1;;
esac
exit 0
EOF
printf '#!/bin/bash\necho "$(cat "$BOX/status") 2026-11-16T00:00:00 1000 yes jsonl"\n' > "$T/stub/status.sh"
printf 'import sys\nprint(sys.argv[2])\n' > "$T/stub/mbox.py"
mkdir -p "$T/home/.pi/agent/extensions"; : > "$T/home/.pi/agent/extensions/ft-mbox-wake.ts"
KEY="$(printf '%s' "$SEAT" | sed 's/[^A-Za-z0-9._#-]/_/g')"
box() { # <이름> <seq> <미읽음 나이초> [beat event 나이초|none] — 새 상자 · BOX 설정
  BOX="$T/box-$1"; rm -rf "$BOX"; mkdir -p "$BOX/.fable-team/comm" "$BOX/.fable-team/state/pi-wake"
  printf '{"_master":"%s","%s":{"agent":"pi"}}\n' "$SEAT" "$SEAT" > "$BOX/.fable-team/seats-knowledge.json"
  printf '{"_master":"planner-m#1","_desk":"%s","planner-m#1":{"agent":"claude"}}\n' "$DESK" > "$BOX/.fable-team/seats-planner.json"
  python3 -c 'import json,sys,time;print(json.dumps({"seq":int(sys.argv[1]),"ts":time.strftime("%Y-%m-%dT%H:%M:%S",time.localtime(int(sys.argv[2])-int(sys.argv[3]))),"to":sys.argv[4],"from":"x","body":"[발주] 일"}))' "$2" "$NOW" "$3" "$SEAT" > "$BOX/.fable-team/comm/mailbox.jsonl"
  [ "${4:-1000}" = none ] || echo "event=$((NOW - ${4:-1000})) check=$((NOW - 900)) why=empty inTurn=0 wakePending=0 watchers=2 rearm=$((NOW - 1000)) woke=0" > "$BOX/.fable-team/state/pi-wake/$KEY.beat"
  echo IDLE > "$BOX/status"; echo "$((NOW - 1000))" > "$BOX/activity"; : > "$BOX/calls.log"; : > "$BOX/tmux.log"
}
iw() { # <스크립트> [시계 오프셋초] [env…]
  local s="$1" off="${2:-0}"; shift 2 2>/dev/null || shift
  env BOX="$BOX" SEAT_NAME="$SEAT" HOME="$T/home" FT_ROOT="$BOX" FT_MBOX="$T/stub/mbox.sh" FT_MBOX_PY="$T/stub/mbox.py" FT_SEAT_STATUS="$T/stub/status.sh" \
    FT_TMUX="bash $T/stub/tmux.sh" FT_IDLE_WAKE_NOW="$((NOW + off))" FT_IDLE_SLOT_LOG="$BOX/slot.log" "$@" bash "$s" >/dev/null 2>"$BOX/err"
}
n() { local c; c="$(grep -c -- "$1" "$2" 2>/dev/null)"; printf '%s' "${c:-0}"; }
cnt() { printf 'res%s esc%s ring%s send%s' "$(n '^budget reserve' "$BOX/calls.log")" "$(n 'send-keys -t %9 Escape' "$BOX/tmux.log")" "$(n '--reserved' "$BOX/calls.log")" "$(n '^send ' "$BOX/calls.log")"; }
rec() { python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).get("result","-"))' "$BOX/.fable-team/state/idle-wake.json" "$SEAT" 2>/dev/null || echo "-"; }
wlog() { n "$SEAT seq=$1 .*복구 깨움 0" "$BOX/.fable-team/state/idle-wake.log"; }

c5()  { box 5 51 660; iw "$1"; local a; a="$(cnt) $(rec) m$(n "^send $SEAT " "$BOX/calls.log")d$(n "^send $DESK " "$BOX/calls.log")"; iw "$1" 30; echo "$a | $(cnt)"; }
c5b() { box 5b 52 200; iw "$1"; local a; a="$(cnt) $(rec)"; iw "$1" 460; echo "$a | $(cnt) $(rec)"; }
c5c() { box 5c 53 660; printf '{"%s":{"seq":53,"result":"done"}}' "$SEAT" > "$BOX/.fable-team/state/idle-wake.json"; iw "$1"; echo "$(cnt) $(rec)"; }
c5d() { box 5d 54 660; iw "$1" 0 RING_DB=quiet; echo "$(cnt) $(rec)"; }
c6()  { box 6 61 540; iw "$1"; local a; a="$(cnt)"; iw "$1" 120; echo "$a | $(cnt)"; }
c7()  { box 7 71 660 60; iw "$1"; echo "$(cnt) log$(wlog 71)"; }
c8a() { box 8a 81 660; echo WORKING > "$BOX/status"; iw "$1"; echo "$(cnt) log$(wlog 81)"; }
c8b() { box 8b 82 660; sed -i.bak 's/why=empty/why=uquiet/' "$BOX/.fable-team/state/pi-wake/$KEY.beat"; iw "$1"; echo "$(cnt) log$(wlog 82)"; }
c8c() { box 8c 83 660; echo 83 > "$BOX/.fable-team/state/pi-wake/$KEY.gated"; iw "$1"; echo "$(cnt) log$(wlog 83)"; }
c8d() { box 8d 84 660; iw "$1" 0 RESERVE_RC=3; echo "$(cnt) tmux$(n send-keys "$BOX/tmux.log") held$(ls "$BOX/.fable-team/state/doorbell-held" 2>/dev/null | wc -l | tr -d ' ') $(rec) log$(wlog 84)"; }
c8e() { box 8e 85 660; iw "$1" 0 TYPE_ON_RESERVE=1; echo "$(cnt) refund$(n '^budget refund' "$BOX/calls.log") tmux$(n send-keys "$BOX/tmux.log") log$(wlog 85)"; }
W5="res1 esc1 ring1 send2 sent m1d1 | res1 esc1 ring1 send2"; W5B="res0 esc0 ring0 send0 ext | res1 esc1 ring1 send2 sent"
W6="res0 esc0 ring0 send0 | res1 esc1 ring1 send2"; W7="res0 esc0 ring0 send0 log1"; W8A="$W7"
W8D="res1 esc0 ring0 send0 tmux0 held0 quiet log1"
eq "⑤ 11분·IDLE·.beat 앞 → reserve 1 · Escape 1 · ring --reserved 1 · 팀장 1 · desk 1 · sent · 재실행 0" "$(c5 "$IW")" "$W5"
eq "⑤-b 200초 ext 위임 기록 → 660초 = 복구 1회" "$(c5b "$IW")" "$W5B"
eq "⑤-c 옛 판 {seq,done} → 복구 1회" "$(c5c "$IW")" "res1 esc1 ring1 send2 sent"
eq "⑤-d ring 출력 quiet → 알림 0 · 기록 quiet" "$(c5d "$IW")" "res1 esc1 ring1 send0 quiet"
eq "⑥ 문턱: 9분 → 0 · 11분 → 1" "$(c6 "$IW")" "$W6"
eq "⑦ 정상 확장(.beat 사건이 미읽음 뒤) → 깨움 0 + 로그 1" "$(c7 "$IW")" "$W7"
eq "⑧a 턴 중 → 깨움 0 + 로그 1" "$(c8a "$IW")" "$W8A"
eq "⑧b .beat why=uquiet → 깨움 0 + 로그 1" "$(c8b "$IW")" "$W7"
eq "⑧c .gated ≥ seq → 깨움 0 + 로그 1" "$(c8c "$IW")" "$W7"
eq "⑧d 예산 소진(held 없음 · 예약 거절) → tmux 0 · reserve 1 · ring 0 · 알림 0 + 로그 1" "$(c8d "$IW")" "$W8D"
eq "⑧e 예약 뒤 키 입력 120초 안 → refund 1 · tmux 0 + 로그 1" "$(c8e "$IW")" "res1 esc0 ring0 send0 refund1 tmux0 log1"
t2=$(date +%s)

# ══ 변이 M1~M7(사본) — 변이 = 그 사례 FAIL · 원본 = 같은 사례 PASS ═══════════════════════════════
mut() { python3 - "$@" <<'PY'
import sys; src, dst, old, new = sys.argv[1:5]; s = open(src, encoding="utf-8").read()
if s.count(old) != 1: sys.exit(f"변이 자리 {s.count(old)}곳")
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
mx() { # <이름> <사례> <옛> <새> — 확장 변이
  mut "$T/ext/ft-mbox-wake.ts" "$T/ext/$1.ts" "$3" "$4" >/dev/null 2>&1 || { bad "$1 변이 자리 없음"; return; }
  if drv "$T/ext/$1.ts" "$2" >/dev/null 2>&1; then bad "$1 → 사례 $2 FAIL 검출"; else ok "$1 → 사례 $2 FAIL 검출"; fi
  if drv "$T/ext/ft-mbox-wake.ts" "$2" >/dev/null 2>&1; then ok "$1 대조 원본 → 사례 $2 PASS"; else bad "$1 대조 원본 → 사례 $2 PASS"; fi; }
mi() { # <이름> <사례 함수> <기대> <옛> <새> — ft-idle-wake 변이(같은 폴더에 ft_card_rest.py 사본)
  mkdir -p "$T/mi-$1"; cp "$(dirname "$IW")/ft_card_rest.py" "$T/mi-$1/" 2>/dev/null
  mut "$IW" "$T/mi-$1/ft-idle-wake.sh" "$4" "$5" >/dev/null 2>&1 || { bad "$1 변이 자리 없음"; return; }
  local m o; m="$($2 "$T/mi-$1/ft-idle-wake.sh")"; o="$($2 "$IW")"
  if [ "$m" != "$3" ]; then ok "$1 → $2 FAIL 검출($m)"; else bad "$1 → $2 FAIL 검출"; fi
  eq "$1 대조 원본 → $2 PASS" "$o" "$3"; }
if [ "$MUT" = 1 ]; then
  mx M1 3 'if (live) arm(); idleArm(); run();' 'idleArm(); run();'
  mx M2 4 'rearmT = down || !live ? null : setTimeout(' 'rearmT = null; void ('
  mx M3 4 'setTimeout(() => { rearmT = null; if (!down) { arm(); run(); } }, rearmMs)' 'setTimeout(function tick() { rearmT = setTimeout(tick, rearmMs); if (!down) { arm(); run(); } }, rearmMs)'
  mi M4 c7 "$W7" 'if max(num(b.get("event")), num(b.get("woke"))) >= NOW - age:' 'if False:'
  mi M5 c8a "$W8A" $'    if state != "IDLE":\n        return False, None' $'    if False:\n        return False, None'
  mi M6 c5b "$W5B" 'prev.get("result") in ("sent", "attempt", "unsure")' 'True'
  mi M7 c8d "$W8D" '    rc = budget("reserve", seat)' '    run([*TMUX, "send-keys", "-t", "%9", "Escape"]); rc = budget("reserve", seat)'
else echo "SKIP 변이 M1~M7 — R2128_MUT=0"; fi
t3=$(date +%s)
bash -n "$0" && ok "S bash -n rc0" || bad "S bash -n rc0"
eq "S 확장 ≤240줄(r1529 S1 과 같은 상한)" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 240 ] && echo yes || echo no)" yes
eq "S setInterval 0" "$(grep -c 'setInterval' "$EXT")" 0
echo "TIME 확장 $((t1 - t0))s · 바깥 $((t2 - t1))s · 변이 $((t3 - t2))s"
echo "---"
if [ "$drc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail driver_rc=$drc)"; exit 1
