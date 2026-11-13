#!/usr/bin/env bash
# test_pi_ext_say_r1837.sh — r1837: pi 확장 진단 글이 TUI 화면(stderr=터미널)에 찍히지 않는다 → 파일 로그 1줄 · non-TTY 는 종전 console.error.
#  격리: 확장 사본($T/ext) · 가짜 pi · process.stderr.isTTY 주입 · FT_PI_EXT_LOG·TMPDIR = 임시 · 가짜 tmux(PATH) · 실 pi·실 tmux·실 우편함 0 · sleep 0.
#  사례: ① TTY · reload-request 비활성 = 터미널 0 · 로그 +1줄(<ISO> <좌석> …) ② TTY · idle-nudge 판정 불가 = 터미널 0 · 로그 +1줄
#        ③ non-TTY = console.error 1 · 로그 0 ④ TTY · 로그 폴더 읽기 전용 = 터미널 0 · tmpdir 로그 +1 · 예외 0 · 등록 계속
#        ⑤ 정적 console.* = ft-load-line say() 본문 1곳 ⑨ land-next sh() 정상 = 부모 stderr 0B · 반환 stdout
#        ⑩ sh() 실패(git 밖·tmux 실패) = 부모 stderr 0B · 반환 "" ⑪ 정적 execSync·execFileSync 마다 stdio 셋째 칸 pipe|ignore
#  변이(사본): M1 isTTY 무시 → ①② · M2 reload-request:46 교체 빼기 → ①⑤ · M3 non-TTY 도 파일 → ③ · M4 쓰기 실패 때 console.error → ④
#              M5 좌석 칸 빼기 → ① · M6 land-next sh() stdio 생략 → ⑩⑪
# 새 파일 mode 100644 — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_SEAT FT_PI_EXT_LOG; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PI="${R1837_PI_DIR:-$(cd -- "$HERE/.." && pwd)/pi}"
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/r1837-say.XXXXXX")"; T="$(cd "$T" && pwd -P)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent" "$T/nogit" "$T/bin-ok" "$T/bin-bad"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
git init -q "$T/repo"
printf '#!/bin/sh\necho seat-ok\n' > "$T/bin-ok/tmux"; printf '#!/bin/sh\necho "no server running on /tmp/x" >&2; exit 1\n' > "$T/bin-bad/tmux"; chmod +x "$T"/bin-*/tmux

cat > "$T/drv.mjs" <<'NODE'
import * as fs from "node:fs"; import * as path from "node:path"; import { pathToFileURL } from "node:url";
const [CASE, DIR, ROOT] = process.argv.slice(2), SEAT = "byz-harness-master-pi#171", OTHER = "byz-harness-nano-x#0";
const out = (ok, n, d = "") => console.log(`${ok ? "PASS" : "FAIL"} ${n}${d ? ` :: ${d}` : ""}`);
const LOG = path.join(ROOT, `${CASE}-log`, "ext.log"), TMPLOG = path.join(process.env.TMPDIR, `ft-ext-${process.getuid()}.log`);
const lines = (f) => { try { return fs.readFileSync(f, "utf-8").split("\n").filter(Boolean); } catch { return []; } };
const tty = CASE !== "c3";
if (tty) Object.defineProperty(process.stderr, "isTTY", { value: true, configurable: true });
let term = 0, cerr = []; // ⑨⑩: execSync 은 stdio 생략 시 자식 stderr 를 process.stderr.write 로 되쓴다 → 그 길은 가로채지 않고 fd2 파일 바이트로 잰다
if (!CASE.startsWith("c9") && CASE !== "c10") process.stderr.write = () => { term++; return true; };
console.error = (...a) => { cerr.push(a.join(" ")); };
function root(name, seats, bin = {}) {
  const d = path.join(ROOT, `${CASE}-${name}`), b = path.join(d, ".fable-team");
  fs.mkdirSync(path.join(b, "bin"), { recursive: true }); fs.mkdirSync(path.dirname(LOG), { recursive: true });
  for (const [f, j] of Object.entries(seats)) fs.writeFileSync(path.join(b, f), JSON.stringify(j));
  for (const [f, s] of Object.entries(bin)) fs.writeFileSync(path.join(b, "bin", f), s);
  Object.assign(process.env, { FT_MBOX_ROOT: d, FT_MBOX_STATE_DIR: path.join(b, "state"), FT_SEAT: SEAT, FT_PI_EXT_LOG: LOG, FT_RELOAD_REQUEST_DEBOUNCE_MS: "100000" });
  return d;
}
async function load(file) {
  const pi = { h: {}, on(e, f) { (this.h[e] ??= []).push(f); }, registerCommand() {}, appendEntry() {}, sendMessage() {}, sendUserMessage() {},
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true, reload: async () => {} }); } };
  (await import(pathToFileURL(path.join(DIR, file)).href)).default(pi); return pi;
}
const NANO = { "seats-planner.json": { _master: OTHER, [OTHER]: { agent: "pi" }, [SEAT]: { role: "nano", agent: "pi" } } };
const ISO = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z /;
if (CASE === "c1" || CASE === "c3") {
  root("r", NANO); const pi = await load("ft-reload-request.ts"); await pi.emit("session_start"); const L = lines(LOG);
  if (CASE === "c1") {
    out(term === 0 && cerr.length === 0, "① TTY 비활성 = 터미널 0", `stderr.write ${term} · console.error ${cerr.length}`);
    out(L.length === 1 && ISO.test(L[0]) && L[0].includes(` ${SEAT} ft-reload-request: inactive seat=${SEAT}`), "① 로그 1줄 = <ISO> <좌석> ft-reload-request: inactive seat=…", L.join(" | "));
  } else out(cerr.length === 1 && cerr[0].startsWith("ft-reload-request: inactive seat=") && L.length === 0, "③ non-TTY = console.error 1 · 로그 0", `console.error ${cerr.length} · 로그 ${L.length}`);
}
if (CASE === "c2") {
  root("n", { "seats-harness.json": { _master: SEAT, [SEAT]: { agent: "pi" } } }, { "ft-goal-table.sh": "echo boom >&2; exit 1\n" });
  const pi = await load("ft-idle-nudge.ts"); await pi.emit("agent_settled", {}); const L = lines(LOG);
  out(term === 0 && cerr.length === 0, "② TTY 판정 불가 = 터미널 0", `stderr.write ${term} · console.error ${cerr.length}`);
  out(L.length === 1 && ISO.test(L[0]) && L[0].includes(` ${SEAT} ft-idle-nudge: 판정 불가 — `), "② 로그 1줄 = ft-idle-nudge: 판정 불가 — …", L.join(" | "));
}
if (CASE === "c4") {
  root("r", NANO); fs.chmodSync(path.dirname(LOG), 0o500); let thrown = "", pi;
  try { pi = await load("ft-reload-request.ts"); await pi.emit("session_start"); } catch (e) { thrown = String(e); }
  const L = lines(TMPLOG);
  out(term === 0 && cerr.length === 0 && !thrown, "④ 읽기 전용 = 터미널 0 · 예외 0", `stderr.write ${term} · console.error ${cerr.length} · ${thrown}`);
  out(L.length === 1 && L[0].includes("ft-reload-request: inactive seat=") && (pi?.h.agent_settled ?? []).length === 1, "④ tmpdir 로그 +1 · 등록 계속", L.join(" | "));
}
if (CASE === "c9" || CASE === "c10") { // 부모 stderr = fd2 파일(bash 가 바이트를 센다) · console.error 는 위에서 가로챔
  const mod = await import(pathToFileURL(path.join(DIR, "ft-land-next.ts")).href); const pi = { on() {}, sendMessage() {} };
  Object.assign(process.env, { FT_PI_EXT_LOG: LOG }); fs.mkdirSync(path.dirname(LOG), { recursive: true });
  process.env.FT_SEAT = SEAT; mod.default(pi); delete process.env.FT_SEAT; const s = mod.seatName();
  out(s === (CASE === "c9" ? "seat-ok" : ""), `${CASE === "c9" ? "⑨" : "⑩"} sh() 반환 = ${CASE === "c9" ? "stdout" : "빈칸"}`, `'${s}'`);
}
process.exit(0);
NODE

cat > "$T/static.mjs" <<'NODE'
import * as fs from "node:fs"; import * as path from "node:path";
const DIR = process.argv[2], hits = [], bad = [];
for (const f of fs.readdirSync(DIR).filter((x) => x.endsWith(".ts")).sort()) {
  const ls = fs.readFileSync(path.join(DIR, f), "utf-8").split("\n").map((l) => (/^\s*\/\//.test(l) ? "" : l)), src = ls.join("\n");
  const a = ls.findIndex((l) => l.startsWith("export function say(")), b = ls.findIndex((l, i) => i > a && l === "}");
  ls.forEach((l, i) => { if (/console\.(error|log|warn)\b/.test(l)) hits.push(`${f}:${i + 1}${a >= 0 && i > a && i < b ? "(say)" : ""}`); });
  for (const m of src.matchAll(/\b(execSync|execFileSync)\(/g)) {
    let i = m.index + m[0].length, depth = 1, q = "";
    for (; i < src.length && depth; i++) { const c = src[i]; if (q) { if (c === "\\") i++; else if (c === q) q = ""; } else if (`'"\``.includes(c)) q = c; else if (c === "(") depth++; else if (c === ")") depth--; }
    if (!/stdio:\s*\[\s*[^,\]]+,\s*[^,\]]+,\s*"(pipe|ignore)"\s*\]/.test(src.slice(m.index, i))) bad.push(`${f}:${src.slice(0, m.index).split("\n").length}`);
  }
}
console.log(`${hits.length === 1 && hits[0].startsWith("ft-load-line.ts:") && hits[0].endsWith("(say)") ? "PASS" : "FAIL"} ⑤ console.* = say() 본문 1곳 :: ${hits.join(" ")}`);
console.log(`${bad.length === 0 ? "PASS" : "FAIL"} ⑪ execSync·execFileSync stdio 셋째 칸 pipe|ignore :: 위반 ${bad.length} ${bad.join(" ")}`);
NODE

run_all() { # $1 = 확장 폴더 → PASS/FAIL 줄
  local d="$1" c k cwd b n tag; tag="$(basename "$d")"; node "$T/static.mjs" "$d"
  for c in c1 c2 c3 c4; do mkdir -p "$T/w-$tag-$c/tmp"
    (cd "$T/nogit" && TMPDIR="$T/w-$tag-$c/tmp" timeout 70 node "$T/drv.mjs" "$c" "$d" "$T/w-$tag-$c") || echo "FAIL $c 드라이버 rc=$?"; done
  for c in c9:repo:ok c10:nogit:bad; do IFS=: read -r k cwd b <<<"$c"; mkdir -p "$T/w-$tag-$k/tmp"
    (cd "$T/$cwd" && PATH="$T/bin-$b:$PATH" TMPDIR="$T/w-$tag-$k/tmp" timeout 70 node "$T/drv.mjs" "$k" "$d" "$T/w-$tag-$k" 2>"$T/w-$tag-$k/err") || echo "FAIL $k 드라이버 rc=$?"
    n="$(wc -c < "$T/w-$tag-$k/err" | tr -d ' ')"; [ "$n" = 0 ] && echo "PASS $k 부모 stderr 0B" || echo "FAIL $k 부모 stderr ${n}B :: $(head -c 120 "$T/w-$tag-$k/err")"; done
}
fail=0; mkdir -p "$T/ext"; cp "$PI"/*.ts "$T/ext/"
OUT="$(run_all "$T/ext")"; echo "$OUT"; fail=$(grep -c '^FAIL' <<<"$OUT")

mutant() { # $1 이름 · $2 파일 · $3 perl 치환 · $4.. 잡혀야 할 사례
  local n="$1" f="$2" s="$3"; shift 3; mkdir -p "$T/$n"; cp "$T/ext"/*.ts "$T/$n/"
  perl -0pi -e "$s" "$T/$n/$f"; if cmp -s "$T/ext/$f" "$T/$n/$f"; then echo "FAIL 변이 $n 치환 미적용"; fail=$((fail+1)); return; fi
  local o; o="$(run_all "$T/$n")"
  for k in "$@"; do grep -q "^FAIL $k" <<<"$o" && echo "PASS 변이 $n → $k FAIL 검출" || { echo "FAIL 변이 $n → $k 못 잡음"; fail=$((fail+1)); }; done
}
mutant M1 ft-load-line.ts 's/if \(process\.stderr\.isTTY !== true\) //' ① ②
mutant M2 ft-reload-request.ts 's/extSay\(`ft-reload-request: \$\{why\}`\)/console.error(`ft-reload-request: \${why}`)/' ① ⑤
mutant M3 ft-load-line.ts 's/process\.stderr\.isTTY !== true/false/' ③
mutant M4 ft-load-line.ts 's|catch \{ /\* 아래 tmpdir 1회 \*/ \}|catch { console.error(line); return; }|' ④
mutant M5 ft-load-line.ts 's/\$\{seat\} \$\{line\}/\${line}/' ①
mutant M6 ft-land-next.ts 's/timeout: 7000, stdio: \["ignore", "pipe", "pipe"\] \}\)\.trim\(\); \} catch \{ return ""; \} \};\nconst log/timeout: 7000 }).trim(); } catch { return ""; } };\nconst log/' c10 ⑪
echo "---"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }; echo "FAIL $fail"; exit 1
