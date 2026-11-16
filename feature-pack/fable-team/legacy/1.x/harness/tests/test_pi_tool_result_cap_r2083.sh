#!/usr/bin/env bash
# test_pi_tool_result_cap_r2083.sh — r2083: pi 좌석의 도구 결과 1건이 상한(기본 6,000바이트)을 넘으면 전문은 파일로, 창에는 머리·표시 줄·꼬리만.
#  격리: 확장을 가짜 pi(on 기록 스텁)로 불러 session_start → tool_result 를 직접 부른다 · 실 pi 0 · 실 세션 0 · 실 /tmp/ft-tool-result 0
#        (넘친 글 폴더 = 임시 폴더 FT_TOOL_RESULT_DIR) · tmux = PATH 앞 가짜 스크립트 · sleep 0.
#  사례: ① 넘는 결과(P1) ② 그대로(P2) ③ 불변(P4) ④ 다시 읽기(P4) — 카드 반례 집합 그대로.
#  변이(사본에서만 · 변이마다 원본 같은 칸 PASS 대조): M1 상한 비교 지움 · M2 전문 쓰기 지움 · M3 바이트→글자 수
#        M4 좌석 판정 지움 · M5 `>`→`>=` · M6 「상한 < M → 그대로」 지움 · M7 이름에서 hash 뺌.
#  기준판(확장 없음) = ① FAIL(Red). 새 파일 mode 100644 — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PI="${R2083_PI_DIR:-$(cd -- "$HERE/.." && pwd)/pi}"
EXT="$PI/ft-tool-result-cap.ts"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL ① 확장 없음 $EXT (기준판 = Red)"; exit 1; }

# ── ③ 정적 계약 ──────────────────────────────────────────────────────────────────────
eq "③ 소스 send 호출 0" "$(grep -c 'send' "$EXT")" 0
eq "③ on( 등록 = tool_result · session_start 2개" "$(grep -o 'pi\.on("[a-z_]*"' "$EXT" | sort | tr '\n' ' ')" 'pi.on("session_start" pi.on("tool_result" '
eq "③ ≤200줄" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 200 ] && echo yes || echo no)" yes

T="$(mktemp -d "${TMPDIR:-/tmp}/r2083-cap.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/ext"
printf '#!/bin/sh\necho "$R2083_TMUX_NAME"\n' > "$T/bin/tmux"; chmod +x "$T/bin/tmux"
cp "$PI/ft-load-line.ts" "$PI/ft-tool-result-cap.ts" "$T/ext/"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
const EXTF = process.env.R2083_EXT, T = process.env.R2083_TMP, ONLY = (process.env.R2083_ONLY || "").split(",").filter(Boolean);
let fails = 0, modv = 0, dirv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const says = []; console.error = (...a) => { says.push(a.join(" ")); };
const B = (s) => Buffer.byteLength(s, "utf-8");
const MK = /\[결과 상한\] 전문 (\d+)바이트 중 머리 (\d+) · 꼬리 (\d+) 만 실음 · 전문 = (.+?) · 더 볼 때는 줄 범위로 읽는다/g;
const name = (id) => `${id.replace(/[^A-Za-z0-9_-]/g, "_")}-${createHash("sha256").update(Buffer.from(id, "utf-8")).digest("hex").slice(0, 16)}`;
const fileOf = (dir, id) => path.join(dir, String(process.pid), `${name(id)}.txt`);
const M = (n, file) => B(`[결과 상한] 전문 ${n}바이트 중 머리 ${n} · 꼬리 ${n} 만 실음 · 전문 = ${file} · 더 볼 때는 줄 범위로 읽는다`) + 2;
const newDir = () => path.join(T, `out${++dirv}`);
const files = (dir) => { try { return fs.readdirSync(dir, { recursive: true }).filter((f) => fs.statSync(path.join(dir, f)).isFile()).length; } catch { return 0; } };
const ascii = (n) => { const rows = []; for (let i = 0; rows.join("\n").length < n; i++) rows.push(`row-${String(i).padStart(5, "0")}-${"x".repeat(38)}`); return rows.join("\n").slice(0, n); };
const hangul = (n) => "가나다라마바사아자차".repeat(Math.ceil(n / 30)).slice(0, Math.floor(n / 3)) + "ab".slice(0, n % 3);

// 확장 1개를 새로 불러 session_start → tool_result 1회(또는 여러 회) · env 는 사례마다 통째로 정함
async function run({ env = {}, calls }) {
  for (const k of ["FT_SEAT", "TMUX", "FT_TOOL_RESULT_CAP_BYTES", "R2083_TMUX_NAME"]) delete process.env[k];
  Object.assign(process.env, { FT_SEAT: "byz-r2083-probe#0" }, env);
  for (const [k, v] of Object.entries(env)) if (v === null) delete process.env[k];
  const h = {}, pi = { on(e, f) { (h[e] ??= []).push(f); } };
  const mod = await import(`${pathToFileURL(EXTF).href}?v=${++modv}`);
  mod.default(pi); says.length = 0;
  for (const f of h.session_start ?? []) await f({}, {});
  const rets = [];
  for (const c of calls) {
    const ev = { toolName: "bash", toolCallId: c.id ?? "call-1", input: {}, content: c.content, details: { keep: 1 }, isError: !!c.isError };
    let r; for (const f of h.tool_result ?? []) r = await f(ev, {});
    rets.push(r);
  }
  return { rets, says: [...says] };
}
const txt = (s) => [{ type: "text", text: s }];
const outText = (r) => (r && Array.isArray(r.content) && r.content.length === 1 && r.content[0].type === "text" ? r.content[0].text : null);
const marks = (s) => [...(s ?? "").matchAll(MK)];
const sameFile = (p, s) => { try { return fs.readFileSync(p).equals(Buffer.from(s, "utf-8")); } catch { return false; } };
const want = (g) => ONLY.length === 0 || ONLY.includes(g);

let fullA = null, fullAFile = null;
if (want("P1")) {
  { const dir = newDir(), s = ascii(20000), r = (await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: txt(s) }] })).rets[0], o = outText(r), m = marks(o);
    eq("①a ASCII 여러 줄 길이 20000", B(s), 20000);
    eq("①a 돌려준 text ≤ 6000", o !== null && B(o) <= 6000, true);
    eq("①a 원문 첫 줄로 시작", !!o?.startsWith(s.slice(0, s.indexOf("\n"))), true);
    eq("①a 원문 끝 줄로 끝남", !!o?.endsWith(s.slice(s.lastIndexOf("\n") + 1)), true);
    eq("①a 표시 줄 1개 · N = 20000", `${m.length}|${m[0]?.[1]}`, "1|20000");
    eq("①a 경로 = <폴더>/<pid>/<이름>.txt", m[0]?.[4], fileOf(dir, "call-1"));
    eq("①a 전문 파일 cmp 0", sameFile(m[0]?.[4], s), true);
    eq("①a 전문 파일 = 일반 파일", !!m[0] && fs.lstatSync(m[0][4]).isFile(), true);
    fullA = s; fullAFile = m[0]?.[4]; }
  { const dir = newDir(), s = hangul(20000), o = outText((await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: txt(s) }] })).rets[0]);
    eq("①b 한글 길이 20000", B(s), 20000);
    eq("①b 한글 ≤ 6000바이트", o !== null && B(o) <= 6000, true);
    eq("①b 깨진 글자(U+FFFD) 0", o !== null && !o.includes("\uFFFD"), true);
    eq("①b 전문 cmp 0", sameFile(marks(o)[0]?.[4], s), true); }
  { const dir = newDir(), s = "a".repeat(20000), o = outText((await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: txt(s) }] })).rets[0]);
    eq("①c 줄바꿈 없는 한 줄 ≤ 6000 · 표시 줄 1", `${o !== null && B(o) <= 6000}|${marks(o).length}`, "true|1"); }
  { const dir = newDir(), p = [ascii(7000), hangul(7000), "z".repeat(6000)], r = (await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: p.map(txt).flat() }] })).rets[0], o = outText(r);
    eq("①d 조각 3개 → 조각 1개", r?.content?.length, 1);
    eq("①d 파일 = 세 조각을 이은 것", sameFile(marks(o)[0]?.[4], p.join("")), true); }
  { const dir = newDir(), id = "a/b\tc\nd", o = outText((await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ id, content: txt(ascii(20000)) }] })).rets[0]);
    const f = path.join(dir, String(process.pid)), names = fs.existsSync(f) ? fs.readdirSync(f) : [];
    eq("①e id 의 / · 탭 · 줄바꿈 → 이름에 0", `${names.length}|${names.some((x) => /[/\t\n]/.test(x))}`, "1|false"); }
  { const dir = newDir(), o = outText((await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_TOOL_RESULT_CAP_BYTES: "3000" }, calls: [{ content: txt(ascii(20000)) }] })).rets[0]);
    eq("①f 상한 3000 → ≤ 3000", o !== null && B(o) <= 3000, true); }
  for (const [tag, a, b] of [["①g 이름 충돌", "call/a", "call_a"], ["①h 대소문자", "call/A", "call/a"]]) {
    const dir = newDir(), A = ascii(20000), Bt = hangul(20000), { rets } = await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ id: a, content: txt(A) }, { id: b, content: txt(Bt) }] });
    const pa = marks(outText(rets[0]))[0]?.[4], pb = marks(outText(rets[1]))[0]?.[4];
    eq(`${tag} 경로 2개 다름(소문자 비교)`, !!pa && !!pb && pa.toLowerCase() !== pb.toLowerCase(), true);
    eq(`${tag} 둘째 뒤 첫 파일 cmp A 0`, sameFile(pa, A), true);
    eq(`${tag} 둘째 파일 cmp B 0`, sameFile(pb, Bt), true);
  }
  { const dir = newDir(), m = M(20000, fileOf(dir, "edge")), s = ascii(20000), o = outText((await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_TOOL_RESULT_CAP_BYTES: String(m) }, calls: [{ id: "edge", content: txt(s) }] })).rets[0]), k = marks(o);
    eq("①i 최소 경계 상한 = M → ≤ M", o !== null && B(o) <= m, true);
    eq("①i 표시 줄 1 · 머리 0 · 꼬리 0", `${k.length}|${k[0]?.[2]}|${k[0]?.[3]}`, "1|0|0");
    eq("①i 파일 cmp 0", sameFile(k[0]?.[4], s), true); }
}
if (want("P2")) {
  for (const n of [5999, 6000]) {
    const dir = newDir(), r = (await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: txt(ascii(n)) }] })).rets[0];
    eq(`② ${n}바이트 → 반환 없음 · 파일 0`, `${r === undefined}|${files(dir)}`, "true|0");
  }
  { const dir = newDir(), o = outText((await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: txt(ascii(6001)) }] })).rets[0]);
    eq("② 6001바이트 → 잘림", `${o !== null && B(o) <= 6000}|${marks(o).length}`, "true|1"); }
  { const dir = newDir(), r = (await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: [...txt(ascii(20000)), { type: "image", data: "AAAA", mimeType: "image/png" }] }] })).rets[0];
    eq("② image 조각 낌 → 반환 없음 · 파일 0", `${r === undefined}|${files(dir)}`, "true|0"); }
  for (const [tag, nm, wantCut] of [["② 좌석 아님(FT_SEAT 없음 + tmux 이름 work) → 반환 없음", "work", false], ["② 대조 tmux 이름 byz-x#3 → 잘림", "byz-x#3", true]]) {
    const dir = newDir(), r = (await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_SEAT: null, TMUX: "/tmp/fake,1,0", R2083_TMUX_NAME: nm }, calls: [{ content: txt(ascii(20000)) }] })).rets[0];
    eq(tag, `${r !== undefined}|${files(dir) > 0}`, `${wantCut}|${wantCut}`);
  }
  { const dir = newDir(), r = (await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_SEAT: null, TMUX: null }, calls: [{ content: txt(ascii(20000)) }] })).rets[0];
    eq("② tmux 밖 · FT_SEAT 없음 → 반환 없음", `${r === undefined}|${files(dir)}`, "true|0"); }
  { const dir = newDir(), r = (await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_TOOL_RESULT_CAP_BYTES: "0" }, calls: [{ content: txt(ascii(20000)) }] })).rets[0];
    eq("② 값 0 → 반환 없음 · 파일 0", `${r === undefined}|${files(dir)}`, "true|0"); }
  { const dir = newDir(), x = await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_TOOL_RESULT_CAP_BYTES: "abc" }, calls: [{ content: txt(ascii(20000)) }] }), o = outText(x.rets[0]);
    eq("② 값 abc → 6000 으로 동작", `${o !== null && B(o) <= 6000 && B(o) > 3000}|${marks(o).length}`, "true|1");
    eq("② 값 abc → say 1줄", x.says.length, 1); }
  const small = async (tag, cap, dir) => {
    const x = await run({ env: { FT_TOOL_RESULT_DIR: dir, FT_TOOL_RESULT_CAP_BYTES: String(cap) }, calls: [{ id: "edge", content: txt(ascii(20000)) }] });
    eq(`${tag} → 반환 없음 · 파일 0`, `${x.rets[0] === undefined}|${files(dir)}`, "true|0");
    eq(`${tag} → say «결과 상한 판정 불가» 1줄`, `${x.says.length}|${x.says.filter((l) => l.includes("결과 상한 판정 불가")).length}`, "1|1");
  };
  await small("② 작은 상한 값 1", 1, newDir());
  { const dir = newDir(); await small("② 상한 = M − 1", M(20000, fileOf(dir, "edge")) - 1, dir); }
  { const long = path.join(T, ...Array.from({ length: 5 }, (_, i) => `${i}`.repeat(60))), short = newDir();
    eq("② 긴 폴더 경로 > 250바이트 · 그 M > 300 · 짧은 폴더 M ≤ 300(전제)", `${B(long) > 250}|${M(20000, fileOf(long, "edge")) > 300}|${M(20000, fileOf(short, "edge")) <= 300}`, "true|true|true");
    await small("② 값 300 + 긴 폴더", 300, long);
    const o = outText((await run({ env: { FT_TOOL_RESULT_DIR: short, FT_TOOL_RESULT_CAP_BYTES: "300" }, calls: [{ id: "edge", content: txt(ascii(20000)) }] })).rets[0]);
    eq("② 대조 값 300 + 짧은 폴더 → ≤ 300 잘림", `${o !== null && B(o) <= 300}|${marks(o).length}`, "true|1"); }
}
if (want("P4")) {
  { const dir = newDir(), { rets } = await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ content: txt(ascii(20000)) }, { content: txt(ascii(20000)), isError: true }] });
    eq("③ 반환 키 = content 뿐", Object.keys(rets[0] ?? {}).join(","), "content");
    eq("③ isError true 도 잘림 · 키 = content 뿐(isError 손 0)", `${marks(outText(rets[1])).length}|${Object.keys(rets[1] ?? {}).join(",")}`, "1|content"); }
  { const dir = newDir(), s = fullA ?? ascii(20000), f0 = fullAFile ?? (() => { const p = path.join(T, "full.txt"); fs.writeFileSync(p, s); return p; })();
    const whole = fs.readFileSync(f0, "utf-8"), { rets } = await run({ env: { FT_TOOL_RESULT_DIR: dir }, calls: [{ id: "re-1", content: txt(Buffer.from(whole).subarray(4000, 6000).toString("utf-8")) }, { id: "re-2", content: txt(whole) }] });
    eq("④ 전문 파일 2000바이트 구간 → 반환 없음", rets[0] === undefined, true);
    eq("④ 전문 파일 전체 → 다시 잘림(N = 20000)", `${marks(outText(rets[1])).length}|${marks(outText(rets[1]))[0]?.[1]}`, "1|20000"); }
}
process.exit(fails ? 1 : 0);
NODE

export PATH="$T/bin:$PATH" R2083_TMP="$T" FT_PI_EXT_LOG="$T/ext.log"
drive() { R2083_EXT="$1" R2083_ONLY="${2:-}" timeout 70 node "$T/driver.mjs" 2>>"$T/node.err"; }
s0=$SECONDS
out="$(drive "$T/ext/ft-tool-result-cap.ts")"; rc=$?
echo "$out"
[ "$rc" -eq 0 ] && ok "N1 driver rc0(①~④)" || bad "N1 driver rc=$rc" "$(tail -3 "$T/node.err")"
echo "TIME 원본 $((SECONDS - s0))초"

# ── 변이(사본) — 바꿀 자리 정확히 1곳 · 변이 FAIL 칸 + 원본 같은 칸 PASS ───────────────────
mutate() { # $1 이름 $2 군 $3 기대 FAIL 칸 접두 $4 찾을 글 $5 바꿀 글
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$PI/ft-load-line.ts" "$d/"
  M_FIND="$4" M_REPL="$5" node -e 'const fs=require("fs"),[s,o]=process.argv.slice(1),src=fs.readFileSync(s,"utf-8"),f=process.env.M_FIND;if(src.split(f).length-1!==1){console.log("NOPOINT");process.exit(0)}fs.writeFileSync(o,src.replace(f,()=>process.env.M_REPL))' "$PI/ft-tool-result-cap.ts" "$d/ft-tool-result-cap.ts" | grep -q NOPOINT && { bad "$1 변이 지점 1개"; return; }
  local mo; mo="$(drive "$d/ft-tool-result-cap.ts" "$2")"
  if grep -q "^FAIL $3" <<<"$mo"; then ok "$1 변이 = $3 FAIL"; else bad "$1 변이 = $3 FAIL" "검출 0"; fi
  if grep -q "^PASS $3" <<<"$out" && ! grep -q "^FAIL $3" <<<"$out"; then ok "$1 원본 대조 = $3 PASS"; else bad "$1 원본 대조 = $3 PASS"; fi
}
s1=$SECONDS
mutate M1 P1 "①a 돌려준" 'if (!(n > cap)) return {};' 'return {};'
mutate M2 P1 "①a 전문 파일 cmp" 'fs.writeFileSync(file, full, "utf-8"); ' ''
mutate M3 P1 "①b 한글 ≤" 'const bytes = (s: string): number => Buffer.byteLength(s, "utf-8");' 'const bytes = (s: string): number => s.length;'
mutate M4 P2 "② 좌석 아님" 'if (!seat) return;' ''
mutate M5 P2 "② 6000바이트" 'if (!(n > cap)) return {};' 'if (!(n >= cap)) return {};'
mutate M6 P2 "② 작은 상한 값 1" 'if (cap < m) return { say: ' 'if (false) return { say: '
mutate M7 P1 "①h 대소문자 경로" 'return `${safe}-${hash}`;' 'return `${safe}`;'
echo "TIME 변이 $((SECONDS - s1))초"

if [ "$fail" -eq 0 ]; then echo "OK r2083 (static+node+mutants pass)"; exit 0; fi
echo "FAIL r2083 ($fail)"; exit 1
