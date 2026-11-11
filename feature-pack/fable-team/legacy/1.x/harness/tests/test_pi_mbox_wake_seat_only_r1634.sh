#!/usr/bin/env bash
# test_pi_mbox_wake_seat_only_r1634.sh — r1634: ft-mbox-wake 는 ft 좌석일 때만 동작한다. ⓔⓔb③ = 좌석 밖(조용한 no-op) · ⓕ = 좌석 안(그대로) · ⓖ명부-only = 좌석 · 변이 1(보정 되돌림)·M3 검출 · DA HOLD R1.
#  격리: tmp 루트 4개(plain = git 밖 빈 폴더 · seat = tmp 리포 + seats-planner.json + 스텁 mbox.sh · roster · broken) · 실 우편함·실 명부·실 pi 세션 0 · tmux 는 PATH 스텁. 새 파일 mode 100644 — `bash <이 파일>`.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1634_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
SEAT="byz-x-master#1"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
eq "S1 확장 $(wc -l < "$EXT" | tr -d ' ')줄 ≤200" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes
eq "S2 좌석 판정 사용 2곳" "$(grep -c 'seatKnown()' "$EXT")" 2
bash -n "$0" && ok "S3 bash -n rc0" || bad "S3 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1634-seat.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ext" "$T/bin" "$T/bin-seat" "$T/bin-random" "$T/node_modules/@earendil-works/pi-coding-agent"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"                              # tmux 없음/밖 = display 실패
printf '#!/bin/sh\necho %s\n' "$SEAT" > "$T/bin-seat/tmux"; chmod 755 "$T/bin-seat/tmux"           # 세션명 = 명부 키
printf '#!/bin/sh\necho random-tmux\n' > "$T/bin-random/tmux"; chmod 755 "$T/bin-random/tmux"      # 세션명 = 명부에 없음
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"
sed 's/if (seatKnown() === false) return; //' "$EXT" > "$T/ext/m3.ts"  # M3 = 좌석 판정 제거
awk '{ if ($0 ~ /^  const seatKnown = /) { held = $0; next } if ($0 ~ /^export default function/ && held != "") { print held; held = "" } print }' \
  "$EXT" > "$T/ext/m1-hoist.ts"  # 변이 1 = DA HOLD R1 보정 되돌림(seatKnown 을 모듈 범위로)
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) });\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const EXT = process.env.R1634_EXT, TMP = process.env.R1634_TMP, SEAT = process.env.R1634_SEAT, MODE = process.env.R1634_MODE || "normal";
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const capture = () => { const buf = [], orig = console.error; console.error = (...a) => buf.push(a.map(String).join(" ")); return { buf, stop: () => { console.error = orig; } }; };
const errors = (buf) => buf.filter((l) => l.startsWith("ERROR ft-mbox-wake:")).length;
const bin = (d) => `${d}:${process.env.R1634_REALPATH}`; // 스텁 PATH + 실제 PATH(스텁 안에 없는 명령은 진짜 것을 쓴다)
const live = [];
async function load(env, cwd) {
  for (const p of live.splice(0)) await p.emit("session_shutdown", {}); // 앞 케이스 감시 해제(2중 감시 0)
  for (const k of ["FT_SEAT", "TMUX_PANE", "FT_MBOX_ROOT", "FT_MBOX_FILE", "FT_MBOX_STATE_DIR"]) delete process.env[k];
  if (process.env.R1634_PATH) process.env.PATH = process.env.R1634_PATH; // 케이스마다 PATH 기준을 되돌린다(앞 케이스 스텁 누수 0)
  Object.assign(process.env, env); process.chdir(cwd);
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); }, appendEntry() {}, sendMessage(m) { this.calls.push(m); } };
  live.push(pi);
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`);
  mod.default(pi);
  return pi;
}
const mk = (d) => { fs.mkdirSync(path.join(TMP, d, ".fable-team", "comm"), { recursive: true }); return path.join(TMP, d); };
const roster = (d, seq) => { // seats-planner.json(좌석 행) + 스텁 mbox.sh + 내 앞 1행
  const b = path.join(d, ".fable-team"); fs.mkdirSync(path.join(b, "state"), { recursive: true });
  fs.writeFileSync(path.join(b, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(b, "comm", "mbox.sh"), "#!/bin/bash\nexit 0\n");
  fs.writeFileSync(path.join(b, "comm", "mailbox.jsonl"), JSON.stringify({ seq, to: SEAT, from: "byz-x-da#0", body: `[발주 #${seq}] x` }) + "\n");
  return d;
};
const ENV = { PATH: process.env.R1634_PATH, FT_MBOX_WAKE_DEBOUNCE_MS: "5" };
const run = async (env, cwd, events = ["session_start"]) => { const pi = await load(env, cwd), cap = capture(); for (const e of events) await pi.emit(e, {}); cap.stop(); return { pi, cap }; };
const plain = path.join(TMP, "plain"); fs.mkdirSync(plain, { recursive: true });
if (MODE === "m3") { const d = path.join(TMP, "plain-m3"); fs.mkdirSync(d, { recursive: true }); // 변이 M3: 좌석 판정을 빼면 ERROR 줄이 다시 나온다
  eq("M3 좌석 판정 빼기 → ⓔ FAIL 검출(ERROR 줄 발생)", errors((await run(ENV, d, ["session_start", "agent_end"])).cap.buf) > 0, true);
} else {
  { const r = await run(ENV, plain, ["session_start", "agent_end"]); // ⓔ 좌석 밖 = 조용한 no-op
    eq("ⓔ ERROR 0줄 · 깨움 0 · 상태 폴더 0", `${errors(r.cap.buf)}/${r.pi.calls.length}/${fs.existsSync(path.join(plain, ".fable-team", "state", "pi-wake"))}`, "0/0/false");
    fs.mkdirSync(path.join(plain, ".fable-team", "comm"), { recursive: true });
    fs.writeFileSync(path.join(plain, ".fable-team", "comm", "mailbox.jsonl"), JSON.stringify({ seq: 1, to: SEAT, from: "byz-x-da#0", body: "[발주 #1] 늦은 우편함" }) + "\n");
    await wait(200); eq("ⓔ 감시 0(뒤에 생긴 우편함도 깨움 0)", r.pi.calls.length, 0); }
  { const r = await run({ PATH: bin(process.env.R1634_RANDBIN), TMUX_PANE: "%1" }, plain); // ⓔb tmux 안인데 명부 행 없음
    eq("ⓔb tmux 세션명이 명부에 없음 = 깨움 0 · ERROR 0줄", `${r.pi.calls.length}/${errors(r.cap.buf)}`, "0/0"); }
  { const bd = mk("broken"); fs.writeFileSync(path.join(bd, ".fable-team", "seats-planner.json"), "{broken"); // ③명부 조회 실패 = 판정 불가
    const r = await run({ PATH: bin(process.env.R1634_RANDBIN), TMUX_PANE: "%1", FT_MBOX_ROOT: bd }, bd);
    eq("③명부 조회 실패 = 판정 불가(ERROR 1줄 · 조용한 no-op 0)", `${r.pi.calls.length}/${errors(r.cap.buf)}`, "0/1"); }
  { const sd = roster(mk("seat"), 5); // ⓕ 좌석 안 = 기동 회수 1턴
    const r = await run({ ...ENV, FT_SEAT: SEAT, FT_MBOX_ROOT: sd }, sd);
    eq("ⓕ 좌석 안 기동 회수 = 턴 1", r.pi.calls.length, 1);
    fs.rmSync(path.join(sd, ".fable-team", "comm", "mailbox.jsonl"), { force: true }); }
  { const sd = path.join(TMP, "seat"); // ⓕ 좌석 안 + 우편함 없음 = 지금처럼 ERROR 1줄(조용한 0 금지)
    const r = await run({ ...ENV, FT_SEAT: SEAT, FT_MBOX_ROOT: sd }, sd);
    eq("ⓕ 좌석 안 우편함 없음 = ERROR 1줄", errors(r.cap.buf), 1); }
}
if (MODE === "roster") { const rd = roster(mk("roster"), 7); // ⓖ명부-only: FT_SEAT 없이 tmux 세션명 = 명부 키 → 좌석(DA HOLD R1 재현 경로 · 변이 1 은 여기서 ReferenceError 로 죽는다)
  const r = await run({ PATH: bin(process.env.R1634_SEATBIN), TMUX_PANE: "%1", FT_MBOX_ROOT: rd, FT_MBOX_WAKE_DEBOUNCE_MS: "5" }, rd);
  eq("ⓖ명부-only FT_SEAT 없이 명부 행 = 좌석(턴 1 · ERROR 0줄)", `${r.pi.calls.length}/${errors(r.cap.buf)}`, "1/0"); }
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

RUN="timeout 70 node $T/driver.mjs"
R1634_PATH="$T/bin:$PATH" R1634_TMP="$T" R1634_SEAT="$SEAT" R1634_EXT="$T/ext/ft-mbox-wake.ts" R1634_SEATBIN="$T/bin-seat" R1634_RANDBIN="$T/bin-random" R1634_REALPATH="$PATH" $RUN; rc=$?
R1634_PATH="$T/bin:$PATH" R1634_TMP="$T" R1634_SEAT="$SEAT" R1634_EXT="$T/ext/ft-mbox-wake.ts" R1634_SEATBIN="$T/bin-seat" R1634_RANDBIN="$T/bin-random" R1634_REALPATH="$PATH" R1634_MODE="roster" $RUN; rc1=$?
# 변이 1 = 보정 되돌림(seatKnown 모듈 범위) → ⓖ명부-only 에서 ReferenceError = 새 시험 FAIL 검출
if R1634_TMP="$T" R1634_SEAT="$SEAT" R1634_EXT="$T/ext/m1-hoist.ts" R1634_SEATBIN="$T/bin-seat" R1634_RANDBIN="$T/bin-random" R1634_REALPATH="$PATH" R1634_MODE="roster" $RUN >/dev/null 2>&1; then
  bad "변이 1 보정 되돌림 → 새 시험 FAIL 검출"; else ok "변이 1 보정 되돌림 → 새 시험 FAIL 검출(ReferenceError)"; fi
R1634_PATH="$T/bin:$PATH" R1634_TMP="$T" R1634_SEAT="$SEAT" R1634_EXT="$T/ext/m3.ts" R1634_MODE="m3" $RUN; rc2=$?
if [ "$rc" = 0 ] && [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail normal_rc=$rc roster_rc=$rc1 mutant_rc=$rc2)"; exit 1
