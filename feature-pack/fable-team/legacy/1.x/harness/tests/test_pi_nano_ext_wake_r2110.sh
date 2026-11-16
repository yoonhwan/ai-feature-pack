#!/usr/bin/env bash
# test_pi_nano_ext_wake_r2110.sh — r2110: ft2 가 연 pi 나노 좌석(명부 밖 · 세션 env FT2_HOLDER == 좌석 이름)을 확장 ft-mbox-wake 가 깨우고, 셸 ext_wake_seat 도 같은 기준으로 «doorbell=ext» 를 낸다.
#  반례 ①~⑦(카드 동결) + 변이 M1~M7(사본에서만 · 변이마다 원본 같은 사례 1회 대조). ⑧ = 기존 시험 목록 재실행(이 파일 밖).
#  격리: tmp 루트(팀 루트 A = tmp 리포 + 명부 2개 + 스텁 mbox.sh · 작업 리포 B + worktree 1 · 명시 루트 C) · tmux·ps = PATH 스텁 · 가짜 HOME · 실 우편함·실 명부·실 pi·실 tmux 0 · sleep 0.
#  입력 바꿈: R2110_EXT(확장) · R2110_COMM(comm 폴더) · R2110_BASE_COMM(② 기준판 · 없으면 A1 줄을 뺀 사본) · R2110_MUT=0(변이 생략 · 기준판 Red 확인용). 새 파일 mode 100644 — `bash <이 파일>`.
if [ -z "${R2110_CLEAN:-}" ]; then # 나노 좌석의 실 값을 물려받지 않는다(카드 «시험 입력»)
  exec env -u FT2_HOLDER -u FT2_ROOT -u FT_MBOX_DIR -u FT_SEAT_MBOX_DIR -u FT_MBOX_ROOT -u FT_MBOX_FILE -u FT_MBOX_STATE_DIR -u FT_SEAT -u TMUX_PANE R2110_CLEAN=1 bash "$0" "$@"
fi
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R2110_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"; COMM="${R2110_COMM:-$HARNESS/comm}"; MUT="${R2110_MUT:-1}"
SEAT="byz-t-nano-rX#0"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }
[ -f "$EXT" ] && [ -f "$COMM/mbox.sh" ] || { echo "FAIL 대상 없음 $EXT / $COMM/mbox.sh"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
TO="$(command -v timeout || command -v gtimeout)" || { echo "FAIL timeout 없음(시험 70초 상한)"; exit 1; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r2110.XXXXXX")" && pwd -P)"
trap 'rm -rf "$T"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@" >/dev/null 2>&1; }

# ── 확장 쪽 재료: 가짜 pi 모듈 · tmux 스텁(세션명 = SEAT) · 루트 A/B/C ─────────────────────────────
mkdir -p "$T/ext" "$T/bin" "$T/node_modules/@earendil-works/pi-coding-agent"
printf '#!/bin/sh\necho "%s"\n' "$SEAT" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) });\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
team() { mkdir -p "$1/.fable-team/comm" "$1/.fable-team/state"; printf '#!/bin/bash\nexit 0\n' > "$1/.fable-team/comm/mbox.sh"; : > "$1/.fable-team/comm/mailbox.jsonl"; }
A="$T/A"; B="$T/B"; BWT="$T/B-wt"; C="$T/C"
mkdir -p "$A" "$B" "$C"; g -C "$A" init; g -C "$B" init; g -C "$B" commit --allow-empty -m i; g -C "$B" worktree add "$BWT"
team "$A"; team "$C"; mkdir -p "$B/.fable-team/comm"; : > "$B/.fable-team/comm/mailbox.jsonl"   # B = 빈 우편함만(명부·CLI 0)
printf '%s\n' '{"_master":"byz-t-planner#1","_desk":"byz-t-desk#1","byz-t-planner#1":{"role":"master","agent":"pi"},"byz-t-desk#1":{"role":"desk","agent":"pi"}}' > "$A/.fable-team/seats-planner.json"
printf '%s\n' '{"_master":"byz-t-hm#1","byz-t-hm#1":{"agent":"pi","team":"t"}}' > "$A/.fable-team/seats-harness.json"
[ -d "$BWT" ] && [ "$(git -C "$BWT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$B/.git" ] || { echo "FAIL 시험 재료(B worktree) 만들기 실패"; exit 1; }

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const E = process.env, EXT = E.R2110_X, SEAT = E.R2110_SEAT, A = E.R2110_A, B = E.R2110_B, BWT = E.R2110_BWT, C = E.R2110_C;
const CASES = (E.R2110_CASES || "1,3,4,5").split(",");
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (f, ms) => { const t0 = Date.now(); while (!f() && Date.now() - t0 < ms) await wait(20); };
const errs = []; console.error = (...a) => errs.push(a.map(String).join(" "));
const errors = () => errs.filter((l) => l.startsWith("ERROR ft-mbox-wake:")).length;
const live = [];
async function load(env, cwd) {
  for (const p of live.splice(0)) await p.emit("session_shutdown", {}); // 앞 사례 감시 해제(2중 감시 0)
  for (const k of ["FT_SEAT", "FT_MBOX_ROOT", "FT_MBOX_FILE", "FT_MBOX_STATE_DIR", "FT_MBOX_DIR", "FT_SEAT_MBOX_DIR", "FT2_HOLDER", "FT2_ROOT"]) delete E[k];
  Object.assign(E, { PATH: E.R2110_PATH, TMUX_PANE: "%1", FT_MBOX_WAKE_DEBOUNCE_MS: "5" }, env); process.chdir(cwd); errs.length = 0;
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); }, appendEntry() {}, sendMessage(m) { this.calls.push(m); } };
  live.push(pi);
  (await import(`${pathToFileURL(EXT).href}?v=${++modv}`)).default(pi);
  return pi;
}
const mb = (d) => path.join(d, ".fable-team", "comm", "mailbox.jsonl");
const row = (seq) => JSON.stringify({ seq, to: SEAT, from: "byz-t-da#0", body: `[발주 #${seq}] r2110` }) + "\n";
const reset = (d, text = "") => { fs.writeFileSync(mb(d), text); fs.rmSync(path.join(d, ".fable-team", "state", "pi-wake"), { recursive: true, force: true }); };
const body = (pi) => String(pi.calls[0]?.content ?? "");
const recvOf = (root) => `bash ${root}/.fable-team/comm/mbox.sh recv ${SEAT}`;

if (CASES.includes("1")) for (const [lab, h] of [["다른 이름", "byz-t-other#0"], ["없음", undefined]]) { // ① 명부 밖 · A1 거짓 = 지금과 같음(r1634 조용한 no-op)
  reset(A, row(11)); const pi = await load(h ? { FT2_HOLDER: h, FT2_ROOT: A } : { FT2_ROOT: A }, A);
  await pi.emit("session_start"); await pi.emit("agent_end"); await wait(400);
  eq(`① FT2_HOLDER ${lab} → 턴 0 · ERROR 0`, `${pi.calls.length}/${errors()}`, "0/0"); }
if (CASES.includes("3")) { reset(A); const pi = await load({ FT2_HOLDER: SEAT, FT2_ROOT: A }, A); // ③ 쉬는 나노 · 쪽지 1통 = 턴 1
  await pi.emit("session_start"); fs.appendFileSync(mb(A), row(21)); await until(() => pi.calls.length >= 1, 3000); await wait(300);
  eq("③ 쉬는 나노 pi · 쪽지 1통 → 깨움 턴 1 · ERROR 0", `${pi.calls.length}/${errors()}`, "1/0");
  eq("③ 깨움 본문 = 팀 루트 recv", body(pi).includes(recvOf(A)) && body(pi).includes("#21"), true); }
if (CASES.includes("4")) { reset(A); const pi = await load({ FT2_HOLDER: SEAT, FT2_ROOT: A }, A); // ④ 일하는 중 = 쌓지 않고 agent_end 뒤 1회
  await pi.emit("session_start"); await wait(350); await pi.emit("agent_start");
  fs.appendFileSync(mb(A), row(31)); await wait(400); eq("④ 일하는 중 쪽지 → 턴 0", pi.calls.length, 0);
  await pi.emit("agent_end"); await until(() => pi.calls.length >= 1, 3000); eq("④ agent_end 뒤 → 턴 1", pi.calls.length, 1);
  fs.appendFileSync(mb(A), row(32)); await wait(400); eq("④ 배달 대기 깨움 1개 상한(새 쪽지 → 그대로 1)", pi.calls.length, 1); }
if (CASES.includes("5") || CASES.includes("5c")) { // ⑤ 팀 루트 A ≠ 작업 리포 B(cwd = B worktree) · DA R1
  const five = async (lab, env, want) => { reset(A, row(51)); reset(B); reset(C, row(52));
    const pi = await load({ FT2_HOLDER: SEAT, FT2_ROOT: A, ...env }, BWT); await pi.emit("session_start");
    await until(() => pi.calls.length >= 1, want === "-" ? 400 : 3000); await wait(300);
    const bw = fs.existsSync(path.join(B, ".fable-team", "state", "pi-wake")), bm = fs.statSync(mb(B)).size;
    if (want === "A") eq(`⑤ ${lab} → 턴 1 · A recv #51 · B pi-wake 0 · B 우편함 쓰기 0`, `${pi.calls.length}/${body(pi).includes(recvOf(A)) && body(pi).includes("#51")}/${bw}/${bm}`, "1/true/false/0");
    if (want === "C") eq(`⑤ ${lab} → C 감시(턴 1 · C recv #52)`, `${pi.calls.length}/${body(pi).includes(recvOf(C)) && body(pi).includes("#52")}`, "1/true");
    if (want === "-") eq(`⑤ ${lab} → 지금 순서(B 감시 · 턴 0)`, `${pi.calls.length}/${bw}/${errors()}`, "0/true/0"); };
  if (CASES.includes("5")) { await five("기본", {}, "A"); await five("FT_MBOX_DIR=A 판", { FT_MBOX_DIR: path.join(A, ".fable-team", "comm") }, "A");
    await five("FT_SEAT_MBOX_DIR=A 판", { FT_SEAT_MBOX_DIR: path.join(A, ".fable-team", "comm") }, "A"); await five("FT2_ROOT=없는 폴더", { FT2_ROOT: path.join(A, "없음") }, "-"); }
  await five("FT_MBOX_ROOT=C 명시", { FT_MBOX_ROOT: C }, "C"); }
for (const p of live.splice(0)) await p.emit("session_shutdown", {});
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE
drv() { R2110_X="$1" R2110_CASES="$2" R2110_SEAT="$SEAT" R2110_A="$A" R2110_B="$B" R2110_BWT="$BWT" R2110_C="$C" R2110_PATH="$T/bin:$PATH" "$TO" 60 node "$T/driver.mjs"; }

# ── 셸 쪽 재료: 박스(comm 사본) · tmux 스텁(show-environment = FAKE_ENV_LINE/RC) · ps 스텁(pane = pi 자신) ─────
mkdir -p "$T/fakebin" "$T/home-ext/.pi/agent/extensions" "$T/home-none" "$T/seats"
: > "$T/home-ext/.pi/agent/extensions/ft-mbox-wake.ts"
cat > "$T/fakebin/tmux" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${TMUX_LOG:-/dev/null}"
case "${1:-}" in
  show-environment) [ "${FAKE_ENV_RC:-0}" = 0 ] || exit "$FAKE_ENV_RC"; [ -z "${FAKE_ENV_LINE:-}" ] || printf '%s\n' "$FAKE_ENV_LINE"; exit 0;;
  list-panes) if [ "${2:-}" = "-a" ]; then printf '%s|%%1\n' "$FAKE_SEAT"; else printf '900001\n'; fi; exit 0;;
  has-session|list-clients|send-keys) exit 0;;
  display-message) printf 'pi\n'; exit 0;;
esac
exit 1
EOF
printf '#!/bin/sh\necho "900001     1 S    pi"\n' > "$T/fakebin/ps"; chmod 755 "$T/fakebin/tmux" "$T/fakebin/ps"
printf '%s\n' '{"byz-t-planner#1":{"agent":"pi","team":"p"},"byz-t-da#0":{"agent":"codex","team":"t"}}' > "$T/seats/seats.json"
cp "$A/.fable-team/seats-planner.json" "$A/.fable-team/seats-harness.json" "$T/seats/"
shrun() { # <comm 폴더> <tmux env 줄> <rc> <HOME> <하위명령…> → "rc|출력|send-keys 수"
  local cd="$1" line="$2" rc="$3" home="$4" r out code; shift 4; r="$(mktemp -d "$T/box.XXXXXX")"   # 호출마다 새 박스(seq·예산 누수 0)
  mkdir -p "$r/.fable-team/comm" "$r/.fable-team/state" "$r/tmp"; cp -R "$cd"/. "$r/.fable-team/comm/"; : > "$r/.fable-team/comm/mailbox.jsonl"; : > "$r/tmux.log"
  out="$(PATH="$T/fakebin:$PATH" HOME="$home" FT_SEATS_JSON="$T/seats/seats.json" FT_MBOX_DIR="$r/.fable-team/comm" FT_MBOX_STATE_DIR="$r/.fable-team/state" \
    TMPDIR="$r/tmp" TMUX_LOG="$r/tmux.log" FAKE_SEAT="$SEAT" FAKE_ENV_LINE="$line" FAKE_ENV_RC="$rc" FT_PS_CMD="$T/fakebin/ps" FT_AGENT_ALIVE_TIMEOUT=2 FT_BIN="$T/nobin" \
    FT_MBOX_NOW=1700002800 FT_MBOX_WAKE_SEAT_MAX=6 FT_MBOX_WAKE_TEAM_MAX=30 FT_MBOX_RATE_N=1000 FT_MBOX_RESEND_COOLDOWN=0 \
    "$TO" 60 bash "$r/.fable-team/comm/mbox.sh" "$@" 2>/dev/null)"; code=$?; out="${out//$r/<BOX>}"
  printf '%s|%s|%s' "$code" "$(printf '%s' "$out" | tr '\n' ' ')" "$(grep -c '^send-keys' "$r/tmux.log")"
}
ring() { shrun "$1" "$2" "$3" "$4" ring "$SEAT" --auto; }
send() { shrun "$1" "$2" "$3" "$4" send "$SEAT" "byz-t-da#0" "[발주] r2110 시험"; }
cut_a1() { mkdir -p "$2"; cp -R "$1"/. "$2/"; python3 - "$2/mbox.sh" <<'PY'
import sys; p = sys.argv[1]; s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write("".join(l for l in s.splitlines(True) if '_ft2_nano_seat "$1" && return 0' not in l))
PY
}
BASE_COMM="${R2110_BASE_COMM:-}"; if [ -z "$BASE_COMM" ]; then BASE_COMM="$T/base-comm"; cut_a1 "$COMM" "$BASE_COMM"; echo "INFO ② 기준판 = A1 줄을 뺀 사본(R2110_BASE_COMM 로 실 기준판을 넘길 수 있다)"; fi

# ── 확장 ①③④⑤ ──
drv "$T/ext/ft-mbox-wake.ts" "1,3,4,5"; rx=$?
# ── 셸 ② · ⑥ · ⑦ ──
for c in "다른 이름|FT2_HOLDER=byz-t-other#0|0" "FT2_HOLDER 줄 없음||0" "지움 표시|-FT2_HOLDER|0" "tmux rc 1||1"; do
  IFS='|' read -r lab line rc <<<"$c"
  for k in ring send; do got="$($k "$COMM" "$line" "$rc" "$T/home-ext")"; want="$($k "$BASE_COMM" "$line" "$rc" "$T/home-ext")"
    eq "② $lab · $k → 출력·rc·send-keys 기준판과 같음" "$got" "$want"; done
  case "$(ring "$COMM" "$line" "$rc" "$T/home-ext")" in *doorbell=ext*) bad "② $lab · ring --auto 가 doorbell=ext";; *) ok "② $lab · ext_wake_seat 거짓(doorbell=ext 아님)";; esac
done
SAME="FT2_HOLDER=$SEAT"
eq "⑥ 나노 pi + 확장 파일 → ring --auto = doorbell=ext · send-keys 0" "$(ring "$COMM" "$SAME" 0 "$T/home-ext")" "0|RING $SEAT doorbell=ext|0"
s6="$(send "$COMM" "$SAME" 0 "$T/home-ext")"
case "$s6" in 0\|*gate=quiet*\|0) ok "⑥ send → ew=1(gate=quiet) · send-keys 0";; *) bad "⑥ send → ew=1(gate=quiet) · send-keys 0" "$s6";; esac
g7="$(ring "$COMM" "$SAME" 0 "$T/home-none")"
case "$g7" in *doorbell=ext*) bad "⑦ 확장 파일 없음 → 거짓" "$g7";; *) eq "⑦ 확장 파일 없음 → 거짓 · 기준판과 같음" "$g7" "$(ring "$BASE_COMM" "$SAME" 0 "$T/home-none")";; esac

# ── 변이 M1~M7(사본) — 변이 = 그 사례 FAIL · 원본 = 같은 사례 PASS ──
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys; src, dst, old, new = sys.argv[1:5]; s = open(src, encoding="utf-8").read()
if s.count(old) != 1: sys.exit(f"변이 자리 {s.count(old)}곳: {old}")
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
mx() { # <이름> <사례> <옛 글> <새 글> — 확장 변이
  if ! mut "$T/ext/ft-mbox-wake.ts" "$T/ext/$1.ts" "$3" "$4" >/dev/null 2>&1; then bad "$1 변이 자리 없음"; return; fi
  if drv "$T/ext/$1.ts" "$2" >/dev/null 2>&1; then bad "$1 → 사례 $2 FAIL 검출"; else ok "$1 → 사례 $2 FAIL 검출"; fi
  if drv "$T/ext/ft-mbox-wake.ts" "$2" >/dev/null 2>&1; then ok "$1 대조 원본 → 사례 $2 PASS"; else bad "$1 대조 원본 → 사례 $2 PASS"; fi; }
ms() { # <이름> <사례 함수> <HOME> <옛 글> <새 글> — 셸 변이(사례 = ⑥ 의 ring --auto 기대 doorbell=ext / ⑦ 의 기대 ext 아님)
  mkdir -p "$T/$1"; cp -R "$COMM"/. "$T/$1/"; if ! mut "$COMM/mbox.sh" "$T/$1/mbox.sh" "$4" "$5" >/dev/null 2>&1; then bad "$1 변이 자리 없음"; return; fi
  local m=no o=no; case "$(ring "$T/$1" "$SAME" 0 "$3")" in *doorbell=ext*) m=yes;; esac; case "$(ring "$COMM" "$SAME" 0 "$3")" in *doorbell=ext*) o=yes;; esac
  if [ "$2" = 6 ]; then eq "$1 → ⑥ FAIL 검출 · 대조 원본 ⑥ PASS(doorbell=ext 변이/원본)" "$m/$o" no/yes
  else eq "$1 → ⑦ FAIL 검출 · 대조 원본 ⑦ PASS(doorbell=ext 변이/원본)" "$m/$o" yes/no; fi; }
if [ "$MUT" = 1 ]; then
  mx M1 3 '=> nano || !!piMasterFile(' '=> !!piMasterFile('
  mx M2 3 'if (process.env.FT_SEAT || nano) return true;' 'if (process.env.FT_SEAT) return true;'
  mx M3 1 'nano = !!seat && process.env.FT2_HOLDER === seat' 'nano = !!seat && !!process.env.FT2_HOLDER'
  mx M6 5 'process.env.FT_MBOX_ROOT || ft2Root || gitRoot()' 'process.env.FT_MBOX_ROOT || gitRoot()'
  mx M7 5c 'process.env.FT_MBOX_ROOT || ft2Root || gitRoot()' 'ft2Root || process.env.FT_MBOX_ROOT || gitRoot()'
  ms M4 6 "$T/home-ext" $'  _ft2_nano_seat "$1" && return 0' ''
  ms M5 7 "$T/home-none" $'  [ -f "$ext" ] || return 1\n  _ft2_nano_seat "$1" && return 0' $'  _ft2_nano_seat "$1" && return 0\n  [ -f "$ext" ] || return 1'
else echo "SKIP 변이 M1~M7 — R2110_MUT=0"; fi
bash -n "$0" && ok "S bash -n rc0" || bad "S bash -n rc0"
if [ "$rx" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (driver_rc=$rx static_fail=$fail)"; exit 1
