#!/usr/bin/env bash
# test_pi_mbox_wake_self_wake_r2259.sh — r2259 ⑦: pi 확장 ft-mbox-wake mine() = recv 가 가져갈 행(O2)
#  자기 발신 «[깨움]»(to === seat 글자 그대로) = 내 행 1 · 깨움 1(발주 seq = 그 행) · 자기 [착지]·[카드 이동] = 0행 · 깨움 0
#  기준판(mine = to ∧ from !== seat) = ① 0행(Red)
#  격리: r1529 꼴 — 임시 루트 · 합성 mailbox.jsonl · 가짜 pi · 스텁 mbox.sh · pi 패키지 스텁. 실 우편함·실 pi 0 · sleep 0(폴링).
#  R2259_EXT = 다른 확장 파일(변이 M3 = 원본 mine())을 볼 때만 준다.
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R2259_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
SEAT="byz-harness-master-pi#171"
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/r2259-self.XXXXXX")"
trap 'rm -rf "$T"' EXIT

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const EXT = process.env.R2259_EXT, SEAT = process.env.R2259_SEAT, ROOT = process.env.R2259_TMP;
let modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const until = async (fn, ms = 600) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (fn()) return true; await wait(10); } return fn(); };
const row = (seq, to, from, body) => JSON.stringify({ seq, ts: "2026-11-18T00:00:00", to, from, body });

function setup(name, rows) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team");
  const comm = path.join(base, "comm"), state = path.join(base, "state");
  fs.mkdirSync(comm, { recursive: true });
  fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(comm, "mbox.sh"), ["#!/bin/bash", "exit 0", ""].join("\n"));
  fs.writeFileSync(path.join(comm, "mailbox.jsonl"), rows.map((r) => r + "\n").join(""));
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: path.join(comm, "mailbox.jsonl"),
    FT_SEAT: SEAT, FT_MBOX_WAKE_DEBOUNCE_MS: "5" });
}
const live = [];
async function load() {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    appendEntry() {}, sendMessage(m) { if (!this.retired) this.calls.push(m); } };
  live.push(pi);
  (await import(`${pathToFileURL(EXT).href}?v=${++modv}`)).default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const seqOf = (pi) => Number((String(pi.calls.at(-1)?.content ?? "").match(/^\[발주 #(\d+)\]/) ?? [])[1] ?? -1);

{ // ⑦-① 자기 «[깨움]» 1행 = 깨움 1 · 발주 seq = 그 행
  setup("w", [row(501, SEAT, SEAT, "[깨움] r3b 대기 끝")]);
  const pi = await load();
  await until(() => pi.calls.length >= 1);
  eq("⑦① 자기 [깨움] = 깨움 1", pi.calls.length, 1);
  eq("⑦① 발주 seq = 501", seqOf(pi), 501);
}
{ // ⑦-③ 자기 [착지] · [카드 이동] = 0행 · 깨움 0
  setup("n", [row(601, SEAT, SEAT, "[착지] pr=1 sha=abc"), row(602, SEAT, SEAT, "[카드 이동] r9 대기→진행")]);
  const pi = await load();
  await wait(150);
  eq("⑦③ 자기 [착지]·[카드 이동] = 깨움 0", pi.calls.length, 0);
}
for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$HARNESS/pi/ft-load-line.ts" "$T/ext/"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
cat > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs" <<'SHIM'
export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) });
SHIM
R2259_EXT="$T/ext/ft-mbox-wake.ts" R2259_SEAT="$SEAT" R2259_TMP="$T" timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (node_rc=$rc)"; exit 1
