#!/usr/bin/env bash
# test_pi_ft_suggest_r1525.sh — r1525: pi 확장 ft-suggest 단위 시험 (S1~S4 정적 + a~e 기준값)
#  격리: 임시 폴더만 — 가짜 h 폴더(FT_SUGGEST_H_DIR) · 가짜 공용 루트(.fable-team/comm/mbox.sh 자리) · 가짜 current 제공자(호출 기록)
#        · 실 pi 세션 0 · 실 /tmp/h 0 · 실 우편함 0. sleep·setTimeout 대기 0(확장이 동기 읽기라 대기가 필요 없다).
#  (a) «! » = 미실행 h 5개(최신 5 · .ran 제외 · 값 «bash <h폴더>/h<N>» · 설명 = 2행 plan= 파일 이름)
#  (a2) 파일 200개 상한(넘으면 최신 200만) · (b) «mbox recv <내 좌석>» 1줄 / 좌석 못 얻으면 0
#  (c) «판정» = PHRASES 실제 반환(current 로 넘기지 않음) · (d) h 폴더 읽기 1회 ≤50ms · 주기 실행 0
#  (e) 매치 없음 = current.getSuggestions 1회(기존 동작 보존) · (f) applyCompletion = «!» 유지(bash 모드)
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1525_EXT:-$HARNESS/pi/ft-suggest.ts}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }

# ── 정적 계약 ────────────────────────────────────────────────────────────────
LINES="$(wc -l < "$EXT" | tr -d ' ')"
eq "S1 확장 ${LINES}줄 ≤120" "$([ "$LINES" -le 120 ] && echo yes || echo no)" yes
eq "S2 setInterval 0" "$(grep -c 'setInterval' "$EXT")" 0
eq "S3 setTimeout 0" "$(grep -c 'setTimeout' "$EXT")" 0
bash -n "$0" && ok "S4 bash -n rc0" || bad "S4 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1525-suggest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-suggest.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/" # r1837 공용 출력 헬퍼 say()
cmp -s "$EXT" "$T/ext/ft-suggest.ts" && ok "S5 시험 사본 = 원본 바이트 일치" || bad "S5 시험 사본 = 원본 바이트 일치"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export {};\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
import { performance } from "node:perf_hooks";

const EXT = process.env.R1525_EXT, ROOT = process.env.R1525_TMP;
let fails = 0, modv = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));

// h 진입 파일 3행 = ft-hil.sh 꼴(1행 shebang · 2행 표식 · 3행 셸). plan= 없으면 설명 빈 값.
const hfile = (dir, n, plan = `/x/h-plan-${n}.sh`) => {
  fs.writeFileSync(path.join(dir, `h${n}`), `#!/usr/bin/env bash\n${plan ? `# ft-hil-entry plan=${plan}\n` : "# 설명 없음\n"}P=/x/plan.sh; M=${dir}/h${n}\n`);
};
function hdir(name, nums, ran = [], plan = (n) => `/x/h-plan-${n}.sh`) {
  const dir = path.join(ROOT, name);
  fs.mkdirSync(dir, { recursive: true });
  for (const n of nums) hfile(dir, n, plan(n));
  for (const n of ran) fs.writeFileSync(path.join(dir, `h${n}.ran`), "1700000000\n");
  return dir;
}

async function load(env) {
  for (const k of Object.keys(env)) { if (env[k] === undefined) delete process.env[k]; else process.env[k] = env[k]; }
  const mod = await import(`${pathToFileURL(EXT).href}?v=${++modv}`);
  const calls = [];
  const current = {
    getSuggestions: async (...a) => { calls.push(a); return { prefix: "", items: [{ value: "FILE", label: "FILE" }] }; },
    applyCompletion: (lines, line, col) => ({ lines: [...lines], cursorLine: line, cursorCol: col }),
    shouldTriggerFileCompletion: () => true,
  };
  let provider = null;
  const pi = { on: (ev, fn) => { pi[ev] = fn; }, sendMessage: () => {} };
  mod.default(pi);
  const ctx = { hasUI: true, ui: { addAutocompleteProvider: (f) => { provider = f(current); } } };
  await pi.session_start({}, ctx);
  if (!provider) throw new Error("addAutocompleteProvider 미등록");
  const suggest = (line, col = line.length) => provider.getSuggestions([line], 0, col, {});
  return { provider, suggest, calls };
}

// ── (a) «! » = 미실행 h 5개 · 최신 우선 · .ran 제외 · 값/설명 ─────────────────────────
{
  const dir = hdir("a", [1, 2, 3, 4, 5, 6, 7], [2, 5]);
  const s = await load({ FT_SUGGEST_H_DIR: dir, FT_SEAT: "" });
  const r = await s.suggest("! ");
  eq("a1 «! » = 항목 5개(좌석 없음 = recv 줄 0)", r?.items?.length, 5);
  eq("a1 prefix = «! »", r?.prefix, "! ");
  eq("a2 최신 우선 = h7,h6,h4,h3,h1", r?.items?.map((i) => i.value).join("|"),
    [7, 6, 4, 3, 1].map((n) => `bash ${dir}/h${n}`).join("|"));
  eq("a3 .ran 있는 h2 는 목록에 없다", r?.items?.some((i) => i.value.endsWith("/h2")), false);
  eq("a4 설명 = 2행 plan= 파일 이름", r?.items?.[0]?.description, "h-plan-7.sh");
  eq("a5 값 = «bash <h폴더>/h<N>»(«!» 없는 순수 명령)", r?.items?.[0]?.value, `bash ${dir}/h7`);
  const r2 = await s.suggest("!");
  eq("a6 «!» 만 입력해도 같은 목록", r2?.items?.length, 5);
  const r3 = await s.suggest("! b");
  eq("a7 «! b» = 같은 목록(접두 필터 아님)", r3?.items?.length, 5);
  const r4 = await s.suggest("! bash /tmp/h7"); // 두 번째 공백 뒤 = h 목록 아님
  eq("a8 실제 명령을 친 뒤 = h 목록 0", r4?.items?.[0]?.value, "FILE");
}
// ── (a2) 파일 200개 상한 — 최신 200 만 본다 ───────────────────────────────────────────
{
  const nums = Array.from({ length: 210 }, (_, i) => i + 1);
  const ran = Array.from({ length: 200 }, (_, i) => i + 1); // 옛 200개는 전부 실행됨
  const dir = hdir("a2", nums, ran);
  const s = await load({ FT_SUGGEST_H_DIR: dir, FT_SEAT: "" });
  const r = await s.suggest("! ");
  eq("a9 파일 210개 · 최신 200만 = 미실행 h210~h206", r?.items?.map((i) => path.basename(i.value)).join("|"), "h210|h209|h208|h207|h206");
}
// ── (b) mbox recv 1줄 = 내 좌석 · 좌석 못 얻으면 0 ────────────────────────────────────
{
  const dir = hdir("b", [1, 2], []);
  const root = path.join(ROOT, "b-root");
  fs.mkdirSync(path.join(root, ".fable-team", "comm"), { recursive: true });
  const SEAT = "byz-harness-nano-r1525-pi-ft-suggest-autocomplete-h-list#0";
  const s = await load({ FT_SUGGEST_H_DIR: dir, FT_SEAT: SEAT, FT_MBOX_ROOT: root });
  const r = await s.suggest("! ");
  eq("b1 마지막 1줄 = mbox recv 내 좌석", r?.items?.at(-1)?.value, `bash ${root}/.fable-team/comm/mbox.sh recv ${SEAT}`);
  eq("b2 h 2개 + recv 1개 = 3", r?.items?.length, 3);
  const s2 = await load({ FT_SUGGEST_H_DIR: dir, FT_SEAT: "" });
  const r2 = await s2.suggest("! ");
  eq("b3 좌석 못 얻으면 recv 줄 0", r2?.items?.filter((i) => i.value.includes("mbox.sh")).length, 0);
}
// ── (c) «판정» = PHRASES 실제 반환(current 로 넘기지 않음) ─────────────────────────────
{
  const s = await load({ FT_SUGGEST_H_DIR: path.join(ROOT, "a"), FT_SEAT: "" });
  const r = await s.suggest("판정");
  eq("c1 «판정» = «판정: REJECT n건»", r?.items?.map((i) => i.value).join("|"), "판정: REJECT n건");
  eq("c2 current 호출 0(직접 반환)", s.calls.length, 0);
  eq("c3 prefix = «판정»", r?.prefix, "판정");
  const r2 = await s.suggest("크론");
  eq("c4 «크론» = «크론 삭제 N개»", r2?.items?.map((i) => i.value).join("|"), "크론 삭제 N개");
}
// ── (d) h 폴더 읽기 1회 ≤50ms · 주기 실행 0(타이머 없음 = 대기 없이 즉시) ───────────────
{
  const dir = hdir("d", Array.from({ length: 200 }, (_, i) => i + 1), []);
  const s = await load({ FT_SUGGEST_H_DIR: dir, FT_SEAT: "" });
  const t0 = performance.now();
  const r = await s.suggest("! ");
  const ms = performance.now() - t0;
  eq("d1 파일 200개 읽기 1회 ≤50ms", ms <= 50, true);
  console.log(`# d1 실측 ${ms.toFixed(1)}ms`);
  eq("d2 목록 5개", r?.items?.length, 5);
}
// ── (e) 매치 없음 = current.getSuggestions 1회 ───────────────────────────────────────
{
  const s = await load({ FT_SUGGEST_H_DIR: path.join(ROOT, "a"), FT_SEAT: "" });
  const r = await s.suggest("그냥 문장");
  eq("e1 매치 없음 = current 1회 호출", s.calls.length, 1);
  eq("e2 current 결과 그대로", r?.items?.[0]?.value, "FILE");
  const r2 = await s.suggest("! "); // h 목록이 있으면 current 0
  const before = s.calls.length;
  eq("e3 h 목록이 있으면 current 0", before, 1);
  ok(`e4 h 목록 반환(${r2?.items?.length}개)`);
}
// ── (f) applyCompletion = «!» 유지(bash 모드 · 하드 룰 13) ────────────────────────────
{
  const dir = hdir("f", [7], []);
  const s = await load({ FT_SUGGEST_H_DIR: dir, FT_SEAT: "" });
  const r = await s.suggest("! ");
  const out = s.provider.applyCompletion(["! "], 0, 2, r.items[0], r.prefix);
  eq("f1 «! » 적용 = «! bash <h폴더>/h7»", out.lines[0], `! bash ${dir}/h7`);
  eq("f2 커서 = 줄 끝", out.cursorCol, out.lines[0].length);
  const out2 = s.provider.applyCompletion(["abc ! b"], 0, 7, r.items[0], "! b");
  eq("f3 문장 중간 «! b» = 접두 보존", out2.lines[0], `abc ! bash ${dir}/h7`);
}

console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R1525_EXT="$T/ext/ft-suggest.ts" R1525_TMP="$T" timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
