#!/usr/bin/env bash
# test_pi_ext_load_line_r1537.sh — r1537: pi 확장 4개가 session_start 에 «로드 <카드> <판>» 1줄을 세션 기록(jsonl)에 남긴다(모델 턴 0).
#  격리: 확장 모듈을 가짜 pi(on·appendEntry 기록 스텁)로 불러 session_start 만 발화 · 실 pi 0 · 실 우편함 0 · 실 세션 0 · sleep 0(마이크로태스크만).
#  사례: ⓐ 4확장 각각 session_start 1회 → 기록 정확히 1회 · 본문 «로드 <카드> <판>»(빈칸 0)
#        ⓑ 기록 호출이 모델 턴 0(triggerTurn 없음 · sendMessage/sendUserMessage 호출 0)
#        ⓒ session_start 2회(reload) → 2줄(회마다 1줄 · 같은 카드)
#        ⓓ 기록 호출이 throw → ERROR 1줄 · 확장 session_start 나머지는 계속(감시 폴더 생성 = 증거)
#        ⓔ 조기 return 경로(우편함 없음)에서도 기록은 남는다 = 기존 동작 변화 0
#  변이: M1 ft-idle-nudge 의 로드 줄 뺌 = ⓐ FAIL · M2 appendEntry → sendMessage(triggerTurn:true) = ⓑ FAIL
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
PI="${R1537_PI_DIR:-$HARNESS/pi}"
HELPER="$PI/ft-load-line.ts"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$HELPER" ] || { echo "FAIL 헬퍼 없음 $HELPER"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
eq "S1 헬퍼 = appendEntry 만(sendMessage 0)" "$(grep -c 'sendMessage' "$HELPER")" 0
eq "S2 헬퍼 = 주기 0(setInterval 0)" "$(grep -c 'setInterval' "$HELPER")" 0
for f in ft-mbox-wake ft-idle-nudge ft-reload-request ft-land-next; do
  [ -f "$PI/$f.ts" ] || { bad "S3 확장 없음 $f.ts"; continue; }
  eq "S3 $f.ts ≤200줄" "$([ "$(wc -l < "$PI/$f.ts" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes
  eq "S4 $f.ts 로드 줄 호출 1회" "$(grep -c 'appendLoadLine(pi, ' "$PI/$f.ts")" 1
  eq "S5 $f.ts 로드 줄 import 1회" "$(grep -c 'import { appendLoadLine } from "./ft-load-line.ts";' "$PI/$f.ts")" 1
done
bash -n "$0" && ok "S6 bash -n rc0" || bad "S6 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1537-loadline.XXXXXX")"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/base/.fable-team/comm" "$T/base/.fable-team/state" "$T/fixture"
: > "$T/base/.fable-team/comm/mailbox.jsonl"
printf '%s\n' '{"_master":"byz-r1537-probe#0","byz-r1537-probe#0":{"role":"master","agent":"pi"}}' > "$T/base/.fable-team/seats-harness.json"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const PI = process.env.R1537_PI_DIR, T = process.env.R1537_TMP;
const EXT = [
  { file: "ft-mbox-wake.ts", card: "r1529" },
  { file: "ft-idle-nudge.ts", card: "r1530" },
  { file: "ft-reload-request.ts", card: "r1531" },
  { file: "ft-land-next.ts", card: "r1532" },
];
let fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const errs = [];
const origErr = console.error;
console.error = (...a) => { errs.push(a.join(" ")); };

let modv = 0;
function fake() {
  const pi = { h: {}, entries: [], sends: [], cmds: {}, throwOn: false,
    on(e, f) { (this.h[e] ??= []).push(f); },
    appendEntry(t, d) { if (this.throwOn) throw new Error("boom"); this.entries.push({ t, d }); },
    sendMessage(...a) { this.sends.push(["sendMessage", ...a]); },
    sendUserMessage(...a) { this.sends.push(["sendUserMessage", ...a]); },
    registerCommand(n, o) { this.cmds[`/${n.replace(/^\//, "")}`] = o; },
    async emit(e) { for (const f of this.h[e] ?? []) await f({}, { isIdle: () => true, reload: () => new Promise(() => {}) }); },
  };
  return pi;
}
async function load(ext, opts = {}) {
  const pi = fake(); pi.throwOn = !!opts.throwOn; errs.length = 0;
  const mod = await import(`${pathToFileURL(path.join(PI, ext.file)).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start");
  if (opts.reload) await pi.emit("session_start");
  return pi;
}
const lines = (pi) => pi.entries.filter((e) => e.t === "ft-load-line");
const shape = (line) => /^로드 r15\d\d (?:[0-9a-f]{8}|판 불명)$/.test(line);

for (const ext of EXT) { // ⓐ ⓑ ⓒ
  const pi = await load(ext, { reload: true });
  const got = lines(pi);
  eq(`ⓐ ${ext.file} 기록 2회(≠1회면 reload 마다 1줄 위반)`, got.length, 2);
  eq(`ⓐ ${ext.file} 카드 = ${ext.card}`, got[0]?.d?.card, ext.card);
  eq(`ⓐ ${ext.file} 본문 꼴 «로드 <카드> <판>»`, shape(got[0]?.d?.line ?? ""), true);
  eq(`ⓐ ${ext.file} 판 빈칸 0`, `${got[0]?.d?.version ? "yes" : "no"}|${got[0]?.d?.file}`, `yes|${ext.file}`);
  eq(`ⓐ ${ext.file} 파일 이름 = 기록의 file`, got[0]?.d?.file, ext.file);
  eq(`ⓒ ${ext.file} 회마다 1줄(같은 카드 2줄)`, `${got[1]?.d?.line}`.startsWith(`로드 ${ext.card} `), true);
  eq(`ⓑ ${ext.file} 모델 턴 0(sendMessage/sendUserMessage 0)`, pi.sends.length, 0);
}

{ // ⓓ 기록 throw = ERROR 1줄 · 확장 나머지 계속
  const ext = EXT[3], pi = await load(ext, { throwOn: true });
  eq("ⓓ 기록 throw = ERROR 1줄", errs.filter((l) => l.startsWith("ERROR ft-load-line")).length, 1);
  eq("ⓓ 기록 throw = 기록 0", lines(pi).length, 0);
  eq("ⓓ 확장 계속 = ft-land-next 감시 폴더 생성", fs.existsSync(path.join(process.env.FT_LAND_NEXT_STATE, "install-pending")), true);
  const rr = await load(EXT[2], { throwOn: true });
  eq("ⓓ 확장 계속 = ft-reload-request 명령 등록", !!rr.cmds["/ft-reload-runtime"], true);
}
{ // ⓔ 조기 return(우편함 없음) 경로에서도 기록은 남는다 · 기존 ERROR 는 그대로 1줄
  process.env.FT_MBOX_FILE = path.join(T, "nope", "mailbox.jsonl");
  const pi = await load(EXT[0]);
  eq("ⓔ 우편함 없음 = 기록 1줄", lines(pi).length, 1);
  eq("ⓔ 기존 동작 그대로 = ERROR ft-mbox-wake 1줄", errs.filter((l) => l.startsWith("ERROR ft-mbox-wake")).length, 1);
}
console.error = origErr;
process.exit(fails ? 1 : 0);
NODE

# 좌석 = 격리 팀의 pi 팀장(4확장 «활성» 경로) — 조기 return·비활성 분기 없이 session_start 전건을 지난다
# 설치본 흉내 = 사본 5개(확장 4 + 헬퍼)를 나란히 + pi 패키지 스텁 → 헬퍼가 «제 폴더» 로 판을 찾는 길을 그대로 시험한다.
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$PI"/ft-{load-line,mbox-wake,idle-nudge,reload-request,land-next}.ts "$T/ext/"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
eq "S7 시험 사본 = 원본 바이트 일치" "$(cd "$PI" && cmp -s ft-load-line.ts "$T/ext/ft-load-line.ts" && echo yes)" yes

export R1537_PI_DIR="$T/ext" R1537_TMP="$T" FT_SEAT="byz-r1537-probe#0"
export FT_MBOX_ROOT="$T/base" FT_MBOX_FILE="$T/base/.fable-team/comm/mailbox.jsonl" FT_MBOX_STATE_DIR="$T/base/.fable-team/state"
export FT_LAND_NEXT_ROOT="$T/base" FT_LAND_NEXT_STATE="$T/base/.fable-team/state" FT_LAND_NEXT_PACK="$T/base" FT_LAND_NEXT_FETCH_MS=2000
cd "$T" || exit 1
timeout 70 node "$T/driver.mjs"; rc=$?
[ "$rc" -eq 0 ] && ok "N1 driver rc0(사례 ⓐ~ⓔ 전건)" || bad "N1 driver rc=$rc"

if [ "$fail" -eq 0 ]; then echo "OK r1537 (static+node pass)"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
