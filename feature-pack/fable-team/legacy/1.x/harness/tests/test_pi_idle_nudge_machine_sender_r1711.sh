#!/usr/bin/env bash
# test_pi_idle_nudge_machine_sender_r1711.sh — r1711: ft-idle-nudge 지문 last 칸이 기계 발신(from «ft-*») 쪽지를 세지 않는다.
#   ① 지문 n=2 + ft-stall-scan [멈춤] 1통 → settled 2회 = 턴 0 · [긴급] 0 (기준판 = 턴 1 → [긴급] 1)
#   ② ft-desk-reply-wake 쪽지 → ① 과 같음 ③ [멈춤]→[정리]→settled×2 3회 반복 → [긴급] 누적 0 (기준판 = 3)
#   ④ 다른 좌석(planner) 쪽지 → 지문 리셋 · 턴 1 ⑤ 우편함 읽기 실패 → 판정 불가 1줄 · 턴 0 · [긴급] 0
#   변이 W1(거르기 삭제 → ①③ FAIL) · W2(모든 발신 거름 → ④ FAIL) · 변이마다 원본 같은 사례 1회 대조 · 회귀 idle-nudge 3파일 rc
# 임시 루트·가짜 tmux(PATH)·가짜 bin shim 만 · 실 우편함·실 tmux 0 · sleep 0 · 사례마다 node 프로세스 1개
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1711_EXT:-$HARNESS/pi/ft-idle-nudge.ts}"
RBASE="4a6560f47e17a47cac9d93b33c8d051b70eedd67"   # 기준판 = 고침 직전 팩 origin/main 고정 40hex
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
T0=$SECONDS; st(){ echo "단계 $1 $((SECONDS-T0))초"; T0=$SECONDS; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r1711-ms.XXXXXX")"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/path" "$T/node_modules/@earendil-works/pi-coding-agent"
# ── shim(판정 입력) — 골 열림 · 진행 0 · h 0 · peek = 우편함 to=좌석 미읽음 · send = 우편함 append ─────
printf '#!/bin/bash\necho "★팀별 완성 진행 (abcdef0123)★"\necho "| feature | — | 1 | 일 |"\necho "★/팀별 완성 진행★"\n' > "$T/bin/ft-goal-table.sh"
printf '#!/bin/bash\necho "카드 대기 0 · 진행 0(좌석 0) · 착지됐는데 진행 0"\n' > "$T/bin/ft-card-flow.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/bin/ft-hil.sh"
cat > "$T/bin/mbox.sh" <<'SH'
D="${FT_MBOX_DIR:-$(cd "$(dirname "$0")" && pwd)}"
case "$1" in
  peek) python3 - "$D/mailbox.jsonl" "$2" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print("pending=%d scanned=1 lineage=0" % len([r for r in rows if r.get("to") == sys.argv[2] and r.get("from") != sys.argv[2]]))
PY
  ;;
  send) python3 - "$D/mailbox.jsonl" "$2" "$3" "$4" <<'PY'
import json, sys
f, to, frm, body = sys.argv[1:5]
rows = [json.loads(l) for l in open(f) if l.strip()]
seq = max([r["seq"] for r in rows] + [290000]) + 1
open(f, "a").write(json.dumps({"seq": seq, "ts": "2026-11-12T00:00:00", "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")
print("QUEUED seq=%d to=%s" % (seq, to))
PY
  ;;
  *) exit 2;;
esac
SH
chmod +x "$T/bin"/*.sh
printf '#!/bin/sh\necho "no server running on /tmp/x" >&2; exit 1\n' > "$T/path/tmux"; chmod +x "$T/path/tmux"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
printf '{"type":"module"}\n' > "$T/package.json"
cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const EXT = process.env.R1711_EXT, ROOT = process.env.R1711_TMP, CASE = process.argv[2];
const SEAT = "byz-feature-master-pi#70", PLANNER = "byz-planner-master-pi#266";
let fails = 0;
const eq = (n, got, want) => { if (String(got) === String(want)) console.log(`PASS ${n}`); else { fails++; console.log(`FAIL ${n} :: 기대 '${want}' 실제 '${got}'`); } };
const row = (seq, to, from, body) => JSON.stringify({ seq, ts: "2026-11-11T23:07:46", to, from, body }) + "\n";
const base = path.join(ROOT, ".fable-team"), comm = path.join(base, "comm"), state = path.join(base, "state");
for (const d of [path.join(base, "bin"), path.join(comm, "receipts"), path.join(state, "pi-wake")]) fs.mkdirSync(d, { recursive: true });
for (const n of ["ft-goal-table.sh", "ft-card-flow.sh", "ft-hil.sh"]) fs.copyFileSync(path.join(ROOT, "bin", n), path.join(base, "bin", n));
fs.copyFileSync(path.join(ROOT, "bin", "mbox.sh"), path.join(comm, "mbox.sh"));
fs.writeFileSync(path.join(base, "seats-feature.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
fs.writeFileSync(path.join(base, "seats-planner.json"), JSON.stringify({ _master: PLANNER }) + "\n");
const mb = path.join(comm, "mailbox.jsonl"), rc = path.join(comm, "receipts", `${SEAT}.jsonl`);
const idle = path.join(state, "pi-wake", `${SEAT}.idle`);
fs.writeFileSync(mb, ""); fs.writeFileSync(rc, row(287175, SEAT, PLANNER, "[결정] 다음 없음 확인"));
fs.writeFileSync(idle, JSON.stringify({ fp: "0|0|287175", n: 2 }) + "\n");   // 실사건 지문 꼴(n=2 = [긴급] 이미 1통)
Object.assign(process.env, { FT_MBOX_ROOT: ROOT, FT_MBOX_STATE_DIR: state, FT_MBOX_FILE: mb, FT_SEAT: SEAT });
const errs = []; console.error = (...a) => { errs.push(a.join(" ")); };
const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, sendMessage(m, o) { this.calls.push({ m, o }); } };
(await import(pathToFileURL(EXT).href)).default(pi);
const settle = async () => { for (const f of pi.h.agent_settled ?? []) await f({ aborted: false }); };
const urg = () => fs.readFileSync(mb, "utf-8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l)).filter((r) => String(r.body).startsWith("[긴급]")).length;
const recv = (seq, from, body) => fs.appendFileSync(rc, row(seq, SEAT, from, body));            // 읽은 쪽지 = 영수
const sent = (seq, body) => fs.appendFileSync(mb, row(seq, PLANNER, SEAT, body));                  // 팀장 자기 발신(승격 안 된 [정리])
if (CASE === "1" || CASE === "2") {
  recv(287200, CASE === "1" ? "ft-stall-scan" : "ft-desk-reply-wake", "[멈춤] feature 20분 무활동");
  await settle(); await settle();
  eq(`${CASE === "1" ? "①" : "②"} 기계 발신 → 턴 0`, pi.calls.length, 0);
  eq(`${CASE === "1" ? "①" : "②"} 기계 발신 → [긴급] 0`, urg(), 0);
}
if (CASE === "3") {
  for (const k of [0, 1, 2]) { recv(288000 + k * 10, "ft-stall-scan", "[멈춤] feature 20분 무활동"); sent(288001 + k * 10, "[정리] 다음 없음 · 쉼"); await settle(); await settle(); }
  eq("③ [멈춤] 3회 반복 → [긴급] 누적 0", urg(), 0);
}
if (CASE === "4") {
  recv(287300, PLANNER, "[발주] 다음 일 검토");
  await settle();
  eq("④ 좌석 발신 → 지문 리셋 · 턴 1", pi.calls.length, 1);
  eq("④ 지문 last = 287300", JSON.parse(fs.readFileSync(idle, "utf-8")).fp, "0|0|287300");
}
if (CASE === "5") {
  recv(287200, "ft-stall-scan", "[멈춤] feature 20분 무활동"); fs.rmSync(mb);                       // 우편함 없음 = 읽기 실패
  await settle(); await settle();
  eq("⑤ 읽기 실패 → 턴 0", pi.calls.length, 0);
  eq("⑤ «판정 불가» 1줄 이상", errs.some((e) => e.includes("판정 불가")), true);
  eq("⑤ [긴급] 0(우편함 새로 안 생김 · 발신 시도 0)", fs.existsSync(mb) || errs.some((e) => e.includes("[긴급]")), false);
}
if (process.env.R1711_DEBUG) console.log("ERRS " + JSON.stringify(errs));
console.log(`FAILED ${fails}`); process.exit(fails ? 1 : 0);
NODE
# drv <확장 파일> <사례> — 사례마다 새 루트 · 확장은 형제(ft-mbox-wake·ft-load-line)와 같은 폴더 사본
RUNN=0
passed() { grep -qx 'FAILED 0' <<<"$1"; }; failed() { grep -qE '^FAILED [1-9]' <<<"$1"; }   # 크래시 = 둘 다 아님
mkext() { local d="$T/ext-$1"; mkdir -p "$d"; cp "$HARNESS/pi/ft-mbox-wake.ts" "$HARNESS/pi/ft-load-line.ts" "$d/"; printf '{"type":"module"}\n' > "$d/package.json"; cat > "$d/ft-idle-nudge.ts"; printf '%s\n' "$d/ft-idle-nudge.ts"; }
drv() { local r; [ -n "${R1711_DEBUG:-}" ] && echo "drv $*" >&2; RUNN=$((RUNN+1)); r="$T/run$RUNN"; mkdir -p "$r"; cp -R "$T/bin" "$r/"; ( cd "$T" && R1711_EXT="$1" R1711_TMP="$r" PATH="$T/path:$PATH" timeout 60 node "$T/driver.mjs" "$2" 2>&1 ); }
mut() { python3 - "$EXT" "$1" "$2" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old, new = sys.argv[2:4]
assert s.count(old) == 1, "변이 대상 1곳 아님: " + old
sys.stdout.write(s.replace(old, new, 1))
PY
}
NEW="$(mkext new < "$EXT")"
# ── 기준판(Red) — ①②③ FAIL · ④⑤ PASS ───────────────────────────────────────────────
OLD="$(git -C "$HARNESS" show "$RBASE:feature-pack/fable-team/legacy/1.x/harness/pi/ft-idle-nudge.ts" 2>/dev/null | mkext old)"
[ -s "$OLD" ] || { echo "FAIL 기준판 $RBASE 읽기 실패(판정 불가)"; exit 1; }
for c in 1 2 3; do r="$(drv "$OLD" $c)"; failed "$r" && ok "기준판 사례 $c FAIL(Red)" || bad "기준판 사례 $c 가 통과 — Red 아님"; done
for c in 4 5; do r="$(drv "$OLD" $c)"; passed "$r" && ok "기준판 사례 $c PASS(앞 판과 같음)" || bad "기준판 사례 $c — 앞 판과 다름" "$(grep -m1 -E '^FAIL|Error' <<<"$r")"; done
st 기준판
# ── 고친 판 ①~⑤ ──────────────────────────────────────────────────────────────────
for c in 1 2 3 4 5; do r="$(drv "$NEW" $c)"; echo "$r" | grep -E '^(PASS|FAIL|ERRS) ' | sed 's/^/  /'; passed "$r" && ok "고친 판 사례 $c" || bad "고친 판 사례 $c" "$(grep -m1 -E '^FAIL|Error' <<<"$r")"; done
st 고친판
# ── 변이(하나씩 독립) + 원본 대조 ─────────────────────────────────────────────────────
W1="$(mut ' && !String(r.from ?? "").startsWith("ft-")' '' | mkext w1)"
W2="$(mut 'const others = (r: { from?: unknown }) =>' 'const others = (r: { from?: unknown }) => false &&' | mkext w2)"
for c in 1 3; do r="$(drv "$W1" $c)"; failed "$r" && ok "W1 거르기 삭제 → 사례 $c FAIL(검출)" || bad "W1 사례 $c 검출 실패"
  r="$(drv "$NEW" $c)"; passed "$r" && ok "W1 대조 원본 사례 $c PASS" || bad "W1 대조 원본 사례 $c"; done
r="$(drv "$W2" 4)"; failed "$r" && ok "W2 모든 발신 거름 → 사례 4 FAIL(검출)" || bad "W2 사례 4 검출 실패"
r="$(drv "$NEW" 4)"; passed "$r" && ok "W2 대조 원본 사례 4 PASS" || bad "W2 대조 원본 사례 4"
st 변이
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
