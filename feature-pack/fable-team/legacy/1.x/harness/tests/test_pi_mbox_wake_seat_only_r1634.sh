#!/usr/bin/env bash
# test_pi_mbox_wake_seat_only_r1634.sh — r1634: ft-mbox-wake 는 ft 좌석일 때만 동작한다(ⓔ 좌석 밖 = 조용한 no-op · ⓕ 좌석 안 = 그대로 · 변이 M3 검출).
#  격리: 임시 루트 2개(plain = git 밖 빈 폴더 · seat = tmp 리포 + seats-planner.json + 스텁 mbox.sh) · 실 우편함·실 명부·실 pi 세션 0 · tmux 는 PATH 스텁(exit 1).
#  새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
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
mkdir -p "$T/ext" "$T/bin" "$T/node_modules/@earendil-works/pi-coding-agent"
printf '#!/bin/sh\nexit 1\n' > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"  # tmux 없음/밖 = display 실패(빠르게)
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"
sed 's/if (seatKnown() === false) return; //' "$EXT" > "$T/ext/m3.ts"  # M3 = 좌석 판정을 빼고 우편함 없음 분기만 남긴 사본
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) });\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"

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
const live = [];
async function load(env, cwd) {
  for (const p of live.splice(0)) await p.emit("session_shutdown", {}); // 앞 케이스 감시 해제(2중 감시 0)
  for (const k of ["FT_SEAT", "TMUX_PANE", "FT_MBOX_ROOT", "FT_MBOX_FILE", "FT_MBOX_STATE_DIR"]) delete process.env[k];
  Object.assign(process.env, env); process.chdir(cwd);
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); }, appendEntry() {}, sendMessage(m) { this.calls.push(m); } };
  live.push(pi);
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`);
  mod.default(pi);
  return pi;
}
const plain = path.join(TMP, "plain"); fs.mkdirSync(plain, { recursive: true });
const seatDir = path.join(TMP, "seat"), base = path.join(seatDir, ".fable-team"), comm = path.join(base, "comm");
fs.mkdirSync(comm, { recursive: true }); fs.mkdirSync(path.join(base, "state"), { recursive: true });
fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
fs.writeFileSync(path.join(comm, "mbox.sh"), "#!/bin/bash\nexit 0\n");
fs.writeFileSync(path.join(comm, "mailbox.jsonl"), JSON.stringify({ seq: 5, to: SEAT, from: "byz-x-da#0", body: "[발주 #5] x" }) + "\n");
const ENV = { PATH: process.env.R1634_PATH, FT_MBOX_WAKE_DEBOUNCE_MS: "5" };

if (MODE === "m3") { // 변이 M3: 좌석 판정을 빼면 ⓔ 에서 ERROR 줄이 다시 나온다
  const m3dir = path.join(TMP, "plain-m3"); fs.mkdirSync(m3dir, { recursive: true }); // 앞 케이스가 만든 우편함과 격리
  const pi = await load(ENV, m3dir);
  const cap = capture(); await pi.emit("session_start", {}); await pi.emit("agent_end", {}); cap.stop();
  eq("M3 좌석 판정 빼기 → ⓔ FAIL 검출(ERROR 줄 발생)", errors(cap.buf) > 0, true);
} else {
  { // ⓔ 좌석 밖(FT_SEAT·TMUX_PANE 없음 · git 밖 빈 폴더 · 우편함 없음) = 조용한 no-op
    const pi = await load(ENV, plain);
    const cap = capture(); await pi.emit("session_start", {}); await pi.emit("agent_end", {}); cap.stop();
    eq("ⓔ ERROR 0줄", errors(cap.buf), 0);
    eq("ⓔ 깨움 0", pi.calls.length, 0);
    eq("ⓔ 상태 폴더 0", fs.existsSync(path.join(plain, ".fable-team", "state", "pi-wake")), false);
    fs.mkdirSync(path.join(plain, ".fable-team", "comm"), { recursive: true });
    fs.writeFileSync(path.join(plain, ".fable-team", "comm", "mailbox.jsonl"), JSON.stringify({ seq: 1, to: SEAT, from: "byz-x-da#0", body: "[발주 #1] 늦은 우편함" }) + "\n");
    await wait(200);
    eq("ⓔ 감시 0(뒤에 생긴 우편함도 깨움 0)", pi.calls.length, 0);
  }
  { // ⓕ 좌석 안 = 지금 그대로(기동 회수 1턴)
    const pi = await load({ ...ENV, FT_SEAT: SEAT, FT_MBOX_ROOT: seatDir }, seatDir);
    await pi.emit("session_start", {});
    eq("ⓕ 좌석 안 기동 회수 = 턴 1", pi.calls.length, 1);
    fs.rmSync(path.join(comm, "mailbox.jsonl"), { force: true });
    const cap = capture(); await pi.emit("session_shutdown", {}); cap.stop();
  }
  { // ⓕ 좌석 안 + 우편함 없음 = 지금처럼 ERROR 1줄(좌석 안의 조용한 0 금지)
    const pi = await load({ ...ENV, FT_SEAT: SEAT, FT_MBOX_ROOT: seatDir }, seatDir);
    const cap = capture(); await pi.emit("session_start", {}); cap.stop();
    eq("ⓕ 좌석 안 우편함 없음 = ERROR 1줄", errors(cap.buf), 1);
  }
}
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R1634_PATH="$T/bin:$PATH" R1634_TMP="$T" R1634_SEAT="$SEAT" R1634_EXT="$T/ext/ft-mbox-wake.ts" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
R1634_PATH="$T/bin:$PATH" R1634_TMP="$T" R1634_SEAT="$SEAT" R1634_EXT="$T/ext/m3.ts" R1634_MODE="m3" \
  timeout 70 node "$T/driver.mjs"; rc2=$?
echo "---"
if [ "$rc" = 0 ] && [ "$rc2" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail normal_rc=$rc mutant_rc=$rc2)"; exit 1
