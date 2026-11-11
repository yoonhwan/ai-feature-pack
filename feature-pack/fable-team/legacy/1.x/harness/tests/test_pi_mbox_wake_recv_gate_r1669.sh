#!/usr/bin/env bash
# test_pi_mbox_wake_recv_gate_r1669.sh — r1669: 증류 게이트에 걸린 pi 좌석은 같은 미읽음에 깨움 1회 뒤 억제하고 팀장에게 1통을 보낸다.
#  사례 ⓐ(억제) ⓑ(팀장 1통) ⓒ(새 쪽지 1회 더) ⓓ(후계 보호) ⓔ(표식 사라지면 풀림) ⓕ(표식 없으면 지금 그대로) ⓑ-2(send 실패 = 오류 1줄 · 억제 유지) · 변이 M1(agent_end 에서 .gated 삭제 → ⓐ FAIL) M2(표식 seat 비교 삭제 → ⓓ FAIL).
#  격리: tmp 루트만(실 우편함·실 명부·실 pi 세션·tmux 0) · 가짜 mbox.sh(send 기록) · 고정 sleep 0 · node 1회. 새 파일 mode 100644 — `bash <이 파일>`.
#  돌리기: ulimit -u "$(( $(ps -u "$(id -u)" | wc -l) + 300 ))"; timeout 70 bash harness/tests/test_pi_mbox_wake_recv_gate_r1669.sh
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1669_EXT:-$HARNESS/pi/ft-mbox-wake.ts}"
SEAT="byz-x-desk#2"; MASTER="byz-x-master#0"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
eq "S1 확장 $(wc -l < "$EXT" | tr -d ' ')줄 ≤240" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 240 ] && echo yes || echo no)" yes # r1669 +25줄
eq "S2 표식 seat 비교 존재" "$(grep -c 'if (owner !== seat) return false;' "$EXT")" 1
bash -n "$0" && ok "S3 bash -n rc0" || bad "S3 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1669-gate.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/"
sed 's/wakePending = false; writeSeq(null);/wakePending = false; writeSeq(null); try { fs.rmSync(gated, { force: true }); } catch {}/' "$EXT" > "$T/ext/m1.ts" # M1 = agent_end 에서 .gated 도 지움
sed 's/if (owner !== seat) return false;/if (false) return false;/' "$EXT" > "$T/ext/m2.ts"                                            # M2 = 표식 seat 비교 삭제
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0, cancelled: false, truncated: false }) });\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const EXT = process.env.R1669_EXT, TMP = process.env.R1669_TMP, SEAT = process.env.R1669_SEAT, MASTER = process.env.R1669_MASTER, MODE = process.env.R1669_MODE || "all";
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const capture = () => { const b = [], o = console.error; console.error = (...a) => b.push(a.map(String).join(" ")); return { b, stop: () => { console.error = o; } }; };
const errors = (b) => b.filter((l) => l.startsWith("ERROR ft-mbox-wake:")).length;
const key = SEAT.replace(/[^A-Za-z0-9._#-]/g, "_"), base = SEAT.replace(/#\d+$/, "");
const live = [];
const mk = (n) => { const r = path.join(TMP, n), ft = path.join(r, ".fable-team");
  fs.mkdirSync(path.join(ft, "comm"), { recursive: true }); fs.mkdirSync(path.join(ft, "state", "pi-distill-pending"), { recursive: true });
  fs.writeFileSync(path.join(ft, "seats-planner.json"), JSON.stringify({ _master: MASTER, _desk: SEAT, [SEAT]: { role: "desk", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(ft, "comm", "mbox.sh"), '#!/bin/bash\nif [ "$1" = "send" ]; then echo "$2|$3|$4" >> "$R1669_SENDLOG"; [ -n "$R1669_FAILSEND" ] && exit 1; fi\nexit 0\n');
  return r; };
const box = (r, seqs) => fs.writeFileSync(path.join(r, ".fable-team", "comm", "mailbox.jsonl"), seqs.map((s) => JSON.stringify({ seq: s, to: SEAT, from: "byz-x-da#0", body: `[발주 #${s}] x` })).join("\n") + "\n");
const add = (r, s) => fs.appendFileSync(path.join(r, ".fable-team", "comm", "mailbox.jsonl"), JSON.stringify({ seq: s, to: SEAT, from: "byz-x-da#0", body: `[발주 #${s}] x` }) + "\n");
const mark = (r, seat) => fs.writeFileSync(path.join(r, ".fable-team", "state", "pi-distill-pending", base), `2026-11-11T00:00:00Z seat=${seat} ctx=999 증류 미완\n`);
const gone = (r) => fs.rmSync(path.join(r, ".fable-team", "state", "pi-distill-pending", base), { force: true });
const gatedOf = (r) => { try { return fs.readFileSync(path.join(r, ".fable-team", "state", "pi-wake", `${key}.gated`), "utf-8").trim(); } catch { return ""; } };
const sent = (r) => { try { return fs.readFileSync(path.join(r, "send.log"), "utf-8").trim().split("\n").filter(Boolean); } catch { return []; } };
async function load(root, extra = {}) {
  for (const p of live.splice(0)) await p.emit("session_shutdown", {});
  for (const k of ["FT_SEAT", "TMUX_PANE", "FT_MBOX_ROOT", "FT_MBOX_FILE", "FT_MBOX_STATE_DIR", "R1669_FAILSEND"]) delete process.env[k];
  Object.assign(process.env, { FT_SEAT: SEAT, FT_MBOX_ROOT: root, FT_MBOX_WAKE_DEBOUNCE_MS: "5", R1669_SENDLOG: path.join(root, "send.log"), ...extra });
  process.chdir(root);
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); }, appendEntry() {}, sendMessage(m) { this.calls.push(m); } };
  live.push(pi);
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`); mod.default(pi);
  return pi;
}
const A = async (root, events, extra = {}) => { const pi = await load(root, extra), cap = capture(); for (const e of events) await pi.emit(e); cap.stop(); return { pi, cap }; };
if (MODE === "a" || MODE === "all") { // ⓐⓑ 억제 + 팀장 1통 · M1 검출
  const r = mk("a"); mark(r, SEAT); box(r, [5]);
  const { pi, cap } = await A(r, ["session_start"]);
  eq("ⓐ 첫 미읽음 = 깨움 1", pi.calls.length, 1);
  eq("ⓐ .gated = 5", gatedOf(r), "5");
  const s = sent(r);
  eq("ⓑ 팀장 1통(to=_master · [멈춤] · #5)", `${s.length}/${s[0]?.split("|")[0]}/${/\[멈춤\]/.test(s[0] ?? "")}/${/#5/.test(s[0] ?? "")}`, `1/${MASTER}/true/true`);
  eq("ⓑ 문구 = recv 막힘 · 미읽음 1 · 후계 필요", `${/recv 막힘\(증류 게이트\)/.test(s[0] ?? "")}/${/미읽음 1/.test(s[0] ?? "")}/${/후계 필요/.test(s[0] ?? "")}`, "true/true/true");
  for (let i = 0; i < 3; i++) await pi.emit("agent_end");
  eq("ⓐ agent_end 3회 = 깨움 0 · .gated 유지 5", `${pi.calls.length}/${gatedOf(r)}`, "1/5");
  eq("ⓐⓑ 같은 표식 = 팀장 알림 0 · ERROR 0", `${sent(r).length}/${errors(cap.b)}`, "1/0");
  add(r, 7); await pi.emit("agent_end");
  eq("ⓒ 새 쪽지 = 깨움 1회 더 · .gated 7 · 알림 0", `${pi.calls.length}/${gatedOf(r)}/${sent(r).length}`, "2/7/1");
  await pi.emit("agent_end");
  eq("ⓒⓐ 새 미읽음도 1회 뒤 억제", pi.calls.length, 2);
  gone(r); await pi.emit("agent_end");
  eq("ⓔ 표식 사라짐 = 풀림(같은 seq 라도 깨움)", `${pi.calls.length}/${gatedOf(r)}`, "3/");
}
if (MODE === "d" || MODE === "all") { // ⓓ 후계 보호 · M2 검출
  const r = mk("d"); mark(r, `${base}#1`); box(r, [5]);
  const { pi } = await A(r, ["session_start"]);
  for (let i = 0; i < 2; i++) await pi.emit("agent_end");
  eq("ⓓ 후계(#1) 표식 = 억제 0(깨움 3 · .gated 0 · 알림 0)", `${pi.calls.length}/${gatedOf(r)}/${sent(r).length}`, "3//0");
}
if (MODE === "all") {
  { const r = mk("f"); box(r, [5]); // ⓕ 표식 없는 좌석 = 지금 동작
    const { pi, cap } = await A(r, ["session_start", "agent_end"]);
    eq("ⓕ 표식 없음 = 회귀 0(깨움 2 · .gated 0 · 알림 0 · ERROR 0)", `${pi.calls.length}/${gatedOf(r)}/${sent(r).length}/${errors(cap.b)}`, "2//0/0"); }
  { const r = mk("g"); mark(r, SEAT); box(r, [5]); // ⓑ-2 send 실패
    const { pi, cap } = await A(r, ["session_start"], { R1669_FAILSEND: "1" });
    const e1 = errors(cap.b);
    for (let i = 0; i < 2; i++) await pi.emit("agent_end");
    eq("ⓑ-2 send 실패 = ERROR 1줄 · 억제 유지(깨움 1 · 시도 1)", `${e1}/${pi.calls.length}/${sent(r).length}`, "1/1/1"); }
}
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

RUN="timeout 70 node $T/driver.mjs"
run() { R1669_TMP="$T" R1669_SEAT="$SEAT" R1669_MASTER="$MASTER" "$@" $RUN; }
run env R1669_EXT="$T/ext/ft-mbox-wake.ts" R1669_MODE=all; rc=$?
if run env R1669_EXT="$T/ext/m1.ts" R1669_MODE=a >/dev/null 2>&1; then bad "변이 M1 agent_end 에서 .gated 삭제 → ⓐ FAIL 검출"; else ok "변이 M1 agent_end 에서 .gated 삭제 → ⓐ FAIL 검출"; fi
if run env R1669_EXT="$T/ext/m2.ts" R1669_MODE=d >/dev/null 2>&1; then bad "변이 M2 표식 seat 비교 삭제 → ⓓ FAIL 검출"; else ok "변이 M2 표식 seat 비교 삭제 → ⓓ FAIL 검출"; fi
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (normal_rc=$rc static=$fail)"; exit 1
