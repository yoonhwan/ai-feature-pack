#!/usr/bin/env bash
# test_pi_idle_nudge_r1530.sh — r1530: pi 확장 ft-idle-nudge (팀장 pi 좌석 쉼 데드락 → agent_settled 1회 턴)
#  격리: 임시 루트(<케이스>/.fable-team/{bin,comm,state} · 가짜 seats-*.json · 가짜 카드판 fake/indices/{대기,진행} ·
#        가짜 h 대기 목록 fake/hil · 가짜 골 표 fake/teams · 가짜 우편함 comm/mailbox.jsonl + receipts) ·
#        스텁 shim(ft-goal-table.sh·ft-card-flow.sh·ft-hil.sh · mbox.sh peek/send = 임시 우편함) · 가짜 pi(sendMessage 셈 · agent_settled 직접 발화).
#        실 pi 0 · 실 우편함 쓰기 0 · sleep 0.
#  사례: ⓐ 쉼 = 턴 1 ⓑ 같은 지문 2회째 = 턴 0 + desk [긴급] 1 ⓒ 3회째 이후 0 ⓓ 진행 1 = 0·지문 무변화 ⓔ h 1 = 0 ⓕ 미읽음 1 = 0
#        ⓖ 자기 발신 행 = 지문 무변화 ⓗ 남의 새 쪽지 seq = 다시 1회 ⓘ 읽기 실패 = 판정 불가·턴 0·[긴급] 0·지문 무변화
#        ⓙ 나노·_desk·claude _master = 0 ⓚ aborted = 0 · ⓛ 팀 골 행 없음 = 0 · ⓜ 활성 판정 = ft-mbox-wake piMasterFile 공유
#  변이: M1 지문 비교 끔 → ⓑ 턴 2 · M2 지문에 자기 발신 seq 포함 → ⓖ 턴 2 · M3 읽기 실패를 0 으로 → ⓘ 턴 1
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다. 자기 호출 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="${R1530_EXT:-$HARNESS/pi/ft-idle-nudge.ts}"
WAKE="$(dirname "$EXT")/ft-mbox-wake.ts"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 없음"; exit 1; }
[ -f "$EXT" ] && [ -f "$WAKE" ] || { echo "FAIL 확장 없음 $EXT / $WAKE"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
n="$(wc -l < "$EXT" | tr -d ' ')"
eq "S1 확장 ${n}줄 < 200" "$([ "$n" -lt 200 ] && echo yes || echo no)" yes
CODE="$(grep -v '^[[:space:]]*//' "$EXT")"   # 머리 주석 줄은 빼고 코드 줄만 본다
eq "S2 사건 = pi.on 2개(session_start 로드 줄 r1537 + agent_settled)" "$(grep -c 'pi.on(' <<<"$CODE")$(grep -c 'pi.on("agent_settled"' <<<"$CODE")" 21
eq "S3 주기·타이머·send-keys 0" "$(grep -cE 'setInterval|setTimeout|send-keys|fs\.watch' <<<"$CODE")" 0
eq "S4 활성 판정 = ft-mbox-wake piMasterFile import(복사본 0)" "$(grep -c 'import { piMasterFile } from "./ft-mbox-wake.ts"' "$EXT")$(grep -c 'readdirSync' "$EXT")" 10
eq "S5 [긴급] 본문 백틱·\$( 0" "$(grep '\[긴급\] \${seat}' "$EXT" | grep -cE '\\`|\$\(')" 0
bash -n "$0" && ok "S6 bash -n rc0" || bad "S6 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1530-idle.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# ── 스텁 shim: 가짜 데이터(<케이스>/fake) 를 읽는다 · <이름>.fail 표식 = 읽기 실패 ─────────────
mkdir -p "$T/stub"
cat > "$T/stub/ft-goal-table.sh" <<'SH'
F="$(cd "$(dirname "$0")/../.." && pwd)/fake"
[ -e "$F/goal.fail" ] && { echo "ERROR 원장 못 읽음" >&2; exit 1; }
[ -e "$F/goal.bad" ] && { echo "WARN 표 없음" >&2; exit 0; }   # 꼴 불일치 = 마커 없는 빈 출력 rc0
echo "★팀별 완성 진행 (abcdef0123)★"; echo "| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |"; echo "|---|---|---|---|"
while IFS= read -r t; do [ -n "$t" ] && echo "| $t | — | 1 | 일 |"; done < "$F/teams"
echo "★/팀별 완성 진행★"
SH
cat > "$T/stub/ft-card-flow.sh" <<'SH'
F="$(cd "$(dirname "$0")/../.." && pwd)/fake"
[ -e "$F/card.fail" ] && { echo "카드 숫자 확인 불가(카드 폴더) — $2"; exit 3; }
w=$(ls "$F/indices/대기" 2>/dev/null | grep -c '\.md$'); p=$(ls "$F/indices/진행" 2>/dev/null | grep -c '\.md$')
echo "카드 대기 $w · 진행 $p(좌석 0) · 착지됐는데 진행 0"
SH
cat > "$T/stub/ft-hil.sh" <<'SH'
F="$(cd "$(dirname "$0")/../.." && pwd)/fake"
[ -e "$F/hil.fail" ] && { echo "ERROR ft-hil --pending 읽기 실패" >&2; exit 3; }
[ "$1 $2" = "--pending --each" ] || exit 2
[ $# -eq 2 ] || { [ "$3" = "--team" ] && [ -n "${4:-}" ]; } || exit 2   # r1538: --team <팀> 인자도 받는다(필터는 이 스텁 밖)
cat "$F/hil" 2>/dev/null; exit 0
SH
cat > "$T/stub/mbox.sh" <<'SH'
D="${FT_MBOX_DIR:-$(cd "$(dirname "$0")" && pwd)}"
case "$1" in
  peek) python3 - "$D/mailbox.jsonl" "$2" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
mine = [r for r in rows if r.get("to") == sys.argv[2] and r.get("from") != sys.argv[2]]
print("pending=%d scanned=1 lineage=0" % len(mine))
PY
  ;;
  send) python3 - "$D/mailbox.jsonl" "$2" "$3" "$4" <<'PY'
import json, sys
f, to, frm, body = sys.argv[1:5]
rows = [json.loads(l) for l in open(f) if l.strip()]
seq = max([r["seq"] for r in rows] + [1000]) + 1
open(f, "a").write(json.dumps({"seq": seq, "ts": "2026-11-09T00:00:00", "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")
print("QUEUED seq=%d to=%s" % (seq, to))
PY
  ;;
  *) exit 2;;
esac
SH

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const EXT = process.env.R1530_EXT, ROOT = process.env.R1530_TMP, STUB = process.env.R1530_STUB;
const SEAT = "byz-harness-master-pi#171", DESK = "byz-planner-desk-pi#9", OTHER = "byz-harness-nano-other#7";
let EXTv = EXT, modv = 0, fails = 0;
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const keyOf = (s) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const errs = []; const origErr = console.error; console.error = (...a) => { errs.push(a.join(" ")); };
const row = (seq, to, from, body) => JSON.stringify({ seq, ts: "2026-11-09T00:00:00", to, from, body });
const append = (f, ...rows) => fs.appendFileSync(f, rows.map((r) => r + "\n").join(""));
const read = (f) => { try { return fs.readFileSync(f, "utf-8"); } catch { return "<없음>"; } };

function setup(name, { seat = SEAT, rosters } = {}) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team"), fake = path.join(dir, "fake");
  for (const d of [path.join(base, "bin"), path.join(base, "comm", "receipts"), path.join(base, "state"), path.join(fake, "indices", "대기"), path.join(fake, "indices", "진행")]) fs.mkdirSync(d, { recursive: true });
  for (const n of ["ft-goal-table.sh", "ft-card-flow.sh", "ft-hil.sh"]) fs.copyFileSync(path.join(STUB, n), path.join(base, "bin", n));
  fs.copyFileSync(path.join(STUB, "mbox.sh"), path.join(base, "comm", "mbox.sh"));
  const r = rosters ?? { "seats-harness.json": { _master: SEAT, [SEAT]: { role: "master", agent: "pi" } } };
  r["seats-planner.json"] ??= { _master: "byz-planner-master-pi#244", _desk: DESK, [DESK]: { agent: "pi" } };
  for (const [f, j] of Object.entries(r)) fs.writeFileSync(path.join(base, f), JSON.stringify(j) + "\n");
  fs.writeFileSync(path.join(fake, "teams"), "planner\nharness\nv65\n");
  fs.writeFileSync(path.join(fake, "hil"), "");
  const mbox = path.join(base, "comm", "mailbox.jsonl"); fs.writeFileSync(mbox, "");
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: path.join(base, "state"), FT_MBOX_FILE: mbox, FT_SEAT: seat });
  return { dir, fake, mbox, receipts: path.join(base, "comm", "receipts", `${seat}.jsonl`),
    idle: path.join(base, "state", "pi-wake", `${keyOf(seat)}.idle`) };
}
async function load() {
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    sendMessage(m, o) { this.calls.push({ m, o }); } };
  const mod = await import(`${pathToFileURL(EXTv).href}?v=${++modv}`);
  mod.default(pi);
  pi.settle = (aborted = false) => pi.emit("agent_settled", { aborted });
  return pi;
}
const urgents = (c) => read(c.mbox).split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l)).filter((r) => r.to === DESK && r.body.startsWith("[긴급]")).length;

// ── ⓐ 쉼 = 턴 1 · ⓑ 2회째 = 턴 0 + [긴급] 1 · ⓒ 3·4회째 = 0 · 지문 파일 3회째에서 멈춤 ────────────
{
  const c = setup("abc"), pi = await load();
  await pi.settle();
  eq("ⓐ 쉼 settled = sendMessage 1", pi.calls.length, 1);
  eq("ⓐ triggerTurn·followUp", `${pi.calls[0]?.o?.triggerTurn}/${pi.calls[0]?.o?.deliverAs}`, "true/followUp");
  eq("ⓐ 본문 «다음 발주 또는 막힌 이유 1줄»", (pi.calls[0]?.m?.content ?? "").includes("다음 발주 또는 막힌 이유 1줄"), true);
  eq("ⓐ [긴급] 0", urgents(c), 0);
  await pi.settle();
  eq("ⓑ 같은 지문 2회째 = sendMessage 0(총 1)", pi.calls.length, 1);
  eq("ⓑ desk [긴급] 1통(임시 우편함 행 1)", urgents(c), 1);
  await pi.settle(); const s3 = read(c.idle); await pi.settle();
  eq("ⓒ 3·4회째 = sendMessage 0(총 1)", pi.calls.length, 1);
  eq("ⓒ 3·4회째 = [긴급] 추가 0", urgents(c), 1);
  eq("ⓒ 지문 파일 3회째 뒤 무변화", read(c.idle), s3);
}
// ── ⓓ 진행 1 = 0 · 지문 무변화 → 0 이 되면 1 ──────────────────────────────────────────
{
  const c = setup("d"), pi = await load();
  fs.writeFileSync(path.join(c.fake, "indices", "진행", "r1.md"), "x");
  await pi.settle();
  eq("ⓓ 진행 1 = sendMessage 0", pi.calls.length, 0);
  eq("ⓓ 지문 파일 무변화(없음)", fs.existsSync(c.idle), false);
  fs.rmSync(path.join(c.fake, "indices", "진행", "r1.md")); await pi.settle();
  eq("ⓓ 진행 0 으로 = sendMessage 1", pi.calls.length, 1);
}
// ── ⓔ 대기 h 1 = 0 · ⓕ 미읽음 1(남이 보낸 행) = 0 ──────────────────────────────────────
{
  const c = setup("e"), pi = await load();
  fs.writeFileSync(path.join(c.fake, "hil"), "h8001 12\n");
  await pi.settle();
  eq("ⓔ 대기 h 1 = sendMessage 0", pi.calls.length, 0);
  eq("ⓔ 지문 파일 없음", fs.existsSync(c.idle), false);
  const c2 = setup("f"), pi2 = await load();
  append(c2.mbox, row(700, SEAT, OTHER, "[발주 #700] 남의 쪽지"));
  await pi2.settle();
  eq("ⓕ 미읽음 1 = sendMessage 0", pi2.calls.length, 0);
  eq("ⓕ 지문 파일 없음", fs.existsSync(c2.idle), false);
}
// ── ⓖ nudge 턴에서 자기 쪽지(desk 앞 + 자기 앞 알림) → 지문 무변화 → 2회째 = [긴급] · 턴 0 ────────
{
  const c = setup("g"), pi = await load();
  append(c.receipts, row(650, SEAT, OTHER, "[발주 #650] 받은 것"));
  await pi.settle();
  eq("ⓖ 1회째 = sendMessage 1", pi.calls.length, 1);
  append(c.mbox, row(1201, DESK, SEAT, "[회신] 막힌 이유 — 오빠 결정 대기"), row(1202, SEAT, SEAT, "[카드 이동] 자기 알림"));
  await pi.settle();
  eq("ⓖ 자기 발신 뒤 2회째 = sendMessage 0(총 1)", pi.calls.length, 1);
  eq("ⓖ 2회째 = [긴급] 1", urgents(c), 1);
}
// ── ⓗ 남이 보낸 새 쪽지 seq(받은 영수) → 지문 바뀜 → 다시 1회 ───────────────────────────────
{
  const c = setup("h"), pi = await load();
  await pi.settle(); await pi.settle();
  eq("ⓗ 전제 1회 + [긴급]", `${pi.calls.length}/${urgents(c)}`, "1/1");
  append(c.receipts, row(900, SEAT, OTHER, "[발주 #900] recv 한 새 쪽지"));
  await pi.settle();
  eq("ⓗ 새 seq = sendMessage 1 더(총 2)", pi.calls.length, 2);
  await pi.settle();
  eq("ⓗ 새 지문 2회째 = [긴급] 1 더(총 2)", `${pi.calls.length}/${urgents(c)}`, "2/2");
}
// ── ⓘ 읽기 실패(골 표 rc1 · 골 표 꼴 불일치 · 카드판 rc3 · h rc3 · 지문 파일 손상) = 판정 불가 1줄 · 턴 0 · [긴급] 0 · 지문 무변화 ──
for (const [k, why] of [["goal.fail", "골 표"], ["goal.bad", "골 표"], ["card.fail", "카드판"], ["hil.fail", "대기 h"]]) {
  const c = setup(`i-${k}`), pi = await load();
  await pi.settle(); await pi.settle(); // 1회째 턴 + 2회째 [긴급] 뒤 지문 n=2
  const before = read(c.idle), u0 = urgents(c);
  fs.writeFileSync(path.join(c.fake, k), "1"); errs.length = 0;
  await pi.settle();
  eq(`ⓘ ${k} = sendMessage 0 추가(총 1)`, pi.calls.length, 1);
  eq(`ⓘ ${k} = [긴급] 추가 0`, urgents(c), u0);
  eq(`ⓘ ${k} = 지문 무변화`, read(c.idle), before);
  eq(`ⓘ ${k} = stderr «판정 불가 — ${why}» 1줄`, errs.filter((e) => e.includes(`판정 불가 — ${why}`)).length, 1);
}
{
  const c = setup("i-fresh"), pi = await load(); // 지문 없는 첫 settled 에서 실패 = 턴 0 (M3 대상)
  fs.writeFileSync(path.join(c.fake, "card.fail"), "1");
  await pi.settle();
  eq("ⓘ 첫 settled 카드판 실패 = sendMessage 0", pi.calls.length, 0);
  eq("ⓘ 첫 settled 카드판 실패 = 지문 파일 없음", fs.existsSync(c.idle), false);
  const c2 = setup("i-idle"), pi2 = await load();
  fs.mkdirSync(path.dirname(c2.idle), { recursive: true }); fs.writeFileSync(c2.idle, "{깨짐");
  await pi2.settle();
  eq("ⓘ 지문 파일 손상 = sendMessage 0 · 파일 무변화", `${pi2.calls.length}/${read(c2.idle)}`, "0/{깨짐");
}
// ── ⓙ 비활성: pi 나노 · _desk · claude _master = 0 ───────────────────────────────────────
for (const [name, seat, rosters] of [
  ["j-nano", "byz-harness-nano-x#0", { "seats-harness.json": { _master: SEAT, [SEAT]: { agent: "pi" }, "byz-harness-nano-x#0": { role: "nano", agent: "pi" } } }],
  ["j-desk", DESK, undefined],
  ["j-claude", "byz-harness-master-claude#170", { "seats-harness.json": { _master: "byz-harness-master-claude#170", "byz-harness-master-claude#170": { agent: "claude" } } }],
]) {
  const c = setup(name, { seat, rosters }), pi = await load();
  await pi.settle();
  eq(`ⓙ ${name} = sendMessage 0 · 지문 파일 없음`, `${pi.calls.length}/${fs.existsSync(c.idle)}`, "0/false");
}
// ── ⓚ event.aborted=true(Escape) = 0 · ⓛ 팀 골 행 없음 = 0 · ⓜ seats.json _master = 팀 v65 ─────────
{
  const c = setup("k"), pi = await load();
  await pi.settle(true);
  eq("ⓚ aborted = sendMessage 0 · 지문 파일 없음", `${pi.calls.length}/${fs.existsSync(c.idle)}`, "0/false");
  const c2 = setup("l"), pi2 = await load();
  fs.writeFileSync(path.join(c2.fake, "teams"), "planner\nv65\n");
  await pi2.settle();
  eq("ⓛ 골 표에 팀 행 없음 = sendMessage 0", pi2.calls.length, 0);
  const s = "byz-v65-master-pi#3", c3 = setup("m", { seat: s, rosters: { "seats.json": { _master: s, [s]: { agent: "pi" } } } }), pi3 = await load();
  await pi3.settle();
  eq("ⓜ seats.json 팀장 = 팀 v65 로 판정 · 턴 1", `${pi3.calls.length}/${(pi3.calls[0]?.m?.content ?? "").includes("v65 골 열림")}`, "1/true");
}
// ── ⓜ 활성 판정 공유: 같은 입력표에서 piMasterFile(팀장 pi 만 · _desk 0) ─────────────────────────
{
  const { piMasterFile } = await import(`${pathToFileURL(path.join(path.dirname(EXT), "ft-mbox-wake.ts")).href}?v=${++modv}`);
  const c = setup("share", { rosters: { "seats-harness.json": { _master: SEAT, [SEAT]: { agent: "pi" } }, "seats-ccu.json": { _master: "byz-ccu-master-claude#1", "byz-ccu-master-claude#1": { agent: "claude" } } } });
  const got = [SEAT, DESK, "byz-ccu-master-claude#1", "nobody#0"].map((s) => piMasterFile(c.dir, s) || "-").join(",");
  eq("ⓜ piMasterFile 입력표(팀장 pi · desk · claude 팀장 · 없음)", got, "seats-harness.json,-,-,-");
}

// ── 변이 ───────────────────────────────────────────────────────────────────────────
function mutate(name, from, to) {
  const src = fs.readFileSync(EXT, "utf-8"), out = src.replace(from, to);
  if (out === src) { bad(`변이 ${name} 치환 미적용(줄 못 찾음)`); return null; }
  const p = path.join(path.dirname(EXT), `mut-${name}.ts`); fs.writeFileSync(p, out); return p;
}
{ // M1 지문 비교 끔 → ⓑ sendMessage 2
  const m = mutate("M1", "prev.fp === fp ? prev.n + 1 : 1", "1");
  if (m) { EXTv = m; setup("M1"); const pi = await load(); await pi.settle(); await pi.settle();
    eq("변이 M1 → ⓑ sendMessage 2 = FAIL 검출", pi.calls.length, 2); EXTv = EXT; }
}
{ // M2 지문에 자기 발신 seq 포함 → ⓖ 턴 2
  const m = mutate("M2", 'String(r.from ?? "") !== seat', "true");
  if (m) { EXTv = m; const c = setup("M2"); const pi = await load(); await pi.settle();
    append(c.mbox, row(1201, DESK, SEAT, "[회신] 막힌 이유"), row(1202, SEAT, SEAT, "[카드 이동] 자기 알림")); await pi.settle();
    eq("변이 M2 → ⓖ sendMessage 2 = FAIL 검출", pi.calls.length, 2); EXTv = EXT; }
}
{ // M3 읽기 실패를 0 으로 → ⓘ 턴 1
  const m = mutate("M3", "c.rc === 0 ? progOf(c.out) : null", "(progOf(c.out) ?? 0)");
  if (m) { EXTv = m; const c = setup("M3"); fs.writeFileSync(path.join(c.fake, "card.fail"), "1"); const pi = await load(); await pi.settle();
    eq("변이 M3 → ⓘ sendMessage 1 = FAIL 검출", pi.calls.length, 1); EXTv = EXT; }
}

console.error = origErr;
console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

# 확장 둘(ft-idle-nudge 가 ./ft-mbox-wake.ts 를 import) 을 사본 폴더에 나란히 + pi 패키지 스텁.
mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
cp "$EXT" "$T/ext/ft-idle-nudge.ts"; cp "$WAKE" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/" # r1537 공용 헬퍼
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' \
  > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
cmp -s "$EXT" "$T/ext/ft-idle-nudge.ts" && cmp -s "$WAKE" "$T/ext/ft-mbox-wake.ts" && ok "S7 시험 사본 = 원본 바이트 일치" || bad "S7 시험 사본 = 원본 바이트 일치"

R1530_EXT="$T/ext/ft-idle-nudge.ts" R1530_TMP="$T" R1530_STUB="$T/stub" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
