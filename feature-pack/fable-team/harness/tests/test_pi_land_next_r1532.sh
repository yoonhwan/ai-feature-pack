#!/usr/bin/env bash
# test_pi_land_next_r1532.sh — r1532: pi 확장 ft-land-next 단위 시험(카드 ⓐ~ⓗ + 변이 M1·M2)
#  격리: 임시 루트(가짜 seats-harness.json · 가짜 install-pending 폴더) · 가짜 git 2개(bare 원격 + clone · main 에 있음/없음) ·
#        가짜 pi(sendMessage 호출 기록 · isIdle 주입) · 실 원격 0 · 실 우편함 0 · 실 pi 세션 0.
#  ⓐ 새 파일 = 턴 1 · ⓑ 같은 Q 재기록 = 0(표식) · ⓒ Q 가 원격 main 에 없음 = 턴 1(설치 요청 문구 0) · ⓓ git 실패 = 판정 불가 · 표식 0
#  ⓔ 일하는 중 = 0 → agent_settled 에 1(한 본문) · ⓕ 비활성(나노·다른 팀 _master·claude) = 0 · ⓖ 시작 회수 = 1(한 본문) · ⓗ 40hex 아님 = 무시
#  변이: M1 표식 끔 → ⓑ 에서 2 = 검출 · M2 MERGED 확인 끔 → ⓒ 에서 설치 요청 문구 = 검출
#  R2 git fetch 는 비동기(execFile) = pi 이벤트 루프 막힘 0 — 느린 git 스텁(0.35초) 아래에서 50ms 타이머가 먼저 돈다
#  R3 판정 불가(원격 끊김) Q 는 «다음 사건» 에 다시 뜼다 — unknownDone 은 fs 사건·시작에서 비운다(카드 ⓓ)
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="$HARNESS/pi/ft-land-next.ts"
SEAT="${R1532_SEAT:-byz-harness-master-pi#171}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "FAIL git 없음"; exit 1; }

# ── 정적 계약(완료 조건) ──────────────────────────────────────────────────────────────
eq "S1 확장 200줄 아래" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 199 ] && echo yes || echo no)" yes
eq "S2 setInterval 0(주기 폴링)" "$(grep -c 'setInterval' "$EXT")" 0
eq "S3 send-keys 0(타이핑 주입)" "$(grep -c 'send-keys' "$EXT")" 0
eq "S4 ls-remote 0" "$(grep -c 'ls-remote' "$EXT")" 0
bash -n "$0" && ok "S5 bash -n rc0" || bad "S5 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1532-land.XXXXXX")"
trap 'rm -rf "$T"' EXIT
GC=(-c user.email=t@example.com -c user.name=t)
git init -q --bare "$T/remote.git" || { echo "FAIL 가짜 원격 생성"; exit 1; }
git -C "$T/remote.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$T/seed"
git -C "$T/seed" "${GC[@]}" commit -q --allow-empty -m landed-1
L1="$(git -C "$T/seed" rev-parse HEAD)"
git -C "$T/seed" remote add origin "$T/remote.git"
git -C "$T/seed" push -q origin main
git -C "$T/seed" "${GC[@]}" commit -q --allow-empty -m landed-2
L2="$(git -C "$T/seed" rev-parse HEAD)"
git -C "$T/seed" push -q origin main
git -C "$T/seed" "${GC[@]}" commit -q --allow-empty -m not-landed
U1="$(git -C "$T/seed" rev-parse HEAD)"
echo "seed: main=$L2(조상 $L1) · 미착지=$U1"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const EXT = process.env.R1532_EXT, TMP = process.env.R1532_TMP, BARE = process.env.R1532_BARE;
const SEAT = process.env.R1532_SEAT, L1 = process.env.R1532_L1, L2 = process.env.R1532_L2, U1 = process.env.R1532_U1;
let fails = 0, modv = 0;
const t0 = Date.now();
const step = (n) => console.log(`STEP ${n} ${((Date.now() - t0) / 1000).toFixed(1)}s`);
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

function setup(name, { clone = true, seats = null, seatsFile = "seats-harness.json", seat = SEAT } = {}) {
  const dir = path.join(TMP, `c-${name}`);
  fs.rmSync(dir, { recursive: true, force: true });
  if (clone) execFileSync("git", ["clone", "-q", BARE, dir], { stdio: ["ignore", "pipe", "pipe"] });
  else fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, ".fable-team"), pack = clone ? dir : path.join(TMP, `pack-${name}`);
  fs.mkdirSync(base, { recursive: true });
  if (!clone) fs.mkdirSync(pack, { recursive: true }); // git 아닌 폴더 = fetch 실패(ⓓ)
  const s = seats ?? { _master: seat, [seat]: { role: "master", agent: "pi" } };
  fs.writeFileSync(path.join(base, seatsFile), JSON.stringify(s) + "\n");
  const state = path.join(base, "state");
  return { dir, base, pack, seat, state, pend: path.join(state, "install-pending"), seen: path.join(state, "pi-wake", "land-seen") };
}
function useEnv(c) {
  Object.assign(process.env, {
    FT_LAND_NEXT_ROOT: c.dir, FT_LAND_NEXT_PACK: c.pack, FT_LAND_NEXT_STATE: c.state,
    FT_SEAT: c.seat, FT_LAND_NEXT_DEBOUNCE_MS: "5", FT_LAND_NEXT_FETCH_MS: "4000",
  });
  delete process.env.FT_LAND_NEXT_SEATS;
}
const put = (c, sha, text = "PENDING n=2\nDIFF x\n") => { fs.mkdirSync(c.pend, { recursive: true }); fs.writeFileSync(path.join(c.pend, `${sha}.txt`), text); };
const seenOf = (c, sha) => fs.existsSync(path.join(c.seen, sha));
function capture() { const buf = []; const orig = console.error; console.error = (...a) => buf.push(a.map(String).join(" ")); return { buf, stop: () => { console.error = orig; } }; }

const live = [];
async function load(ext = EXT) {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    sendMessage(m, o) { if (!this.retired) this.calls.push({ m, o }); } };
  live.push(pi);
  const mod = await import(`${pathToFileURL(ext).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {});
  return pi;
}
const body = (pi, i = 0) => pi.calls[i]?.m?.content ?? "";

// ── ⓐ 새 파일 = 턴 1 · ⓑ 같은 Q 재기록·사건 반복 = 0 ──────────────────────────────────────
{
  const c = setup("a"); useEnv(c);
  const pi = await load();
  eq("ⓐ 시작 턴 0", pi.calls.length, 0);
  put(c, L1);
  await wait(400); step("a-put");
  if (pi.calls.length === 0) { console.log("NOTE ⓐ fs 이벤트 미도착 — settled 회수 경로로 확인"); await pi.emit("agent_settled", {}); await wait(400); }
  eq("ⓐ 새 파일 = 턴 1", pi.calls.length, 1);
  eq("ⓐ 본문", body(pi), `[착지 확인] main ${L1.slice(0, 10)} · 설치 PENDING 2 · 다음 h = 설치 h 발급 요청(planner [HIL]) · 대기 파일 ${path.join(c.pend, `${L1}.txt`)}`);
  eq("ⓐ customType/display", `${pi.calls[0]?.m?.customType}/${pi.calls[0]?.m?.display}`, "ft-land-next/true");
  eq("ⓐ triggerTurn/followUp", `${pi.calls[0]?.o?.triggerTurn}/${pi.calls[0]?.o?.deliverAs}`, "true/followUp");
  eq("ⓐ 표식", seenOf(c, L1), true);
  put(c, L1, "PENDING n=2\nDIFF x\n"); // 같은 Q 다시 쓰기
  await wait(400);
  eq("ⓑ 같은 Q 재기록 = 턴 0", pi.calls.length, 1);
  fs.writeFileSync(path.join(c.pend, "notes.md"), "x\n"); // 사건 반복(다른 이름 = 확실한 dir 이벤트)
  await wait(400);
  eq("ⓑ 사건 반복 = 턴 0", pi.calls.length, 1);
  await pi.emit("agent_settled", {}); await wait(400);
  eq("ⓑ settled 뒤에도 0", pi.calls.length, 1);
}
// ── ⓒ Q 가 원격 main 에 없음 = 턴 1 · 설치 요청 문구 0 · 표식 1 ───────────────────────────
{
  const c = setup("c"); useEnv(c);
  const pi = await load();
  put(c, U1, "PENDING n=1\n");
  await wait(400); step("c-missing");
  await pi.emit("agent_settled", {}); // ★쉼 경계 재훑기 = 놓친 fs 이벤트 회수 경로(표식이 있으면 늘지 않는다)
  await wait(400);
  eq("ⓒ 턴 1(이벤트 또는 settled 회수 · 합치면 1)", pi.calls.length, 1);
  eq("ⓒ 착지 확인 불가", body(pi).includes("착지 확인 불가"), true);
  eq("ⓒ 원격 main 에 없음", body(pi).includes("원격 main 에 없음"), true);
  eq("ⓒ 설치 요청 문구 0", body(pi).includes("설치 h 발급 요청"), false);
  eq("ⓒ 표식", seenOf(c, U1), true);
}
// ── ⓓ git 실패 = 판정 불가 턴 1 · 표식 0 → 다음 사건에 다시 ───────────────────────────────
{
  const c = setup("d", { clone: false }); useEnv(c);
  const pi = await load();
  put(c, L1);
  await wait(400); step("d-gitfail");
  if (pi.calls.length === 0) { await pi.emit("agent_settled", {}); await wait(400); }
  eq("ⓓ 턴 1", pi.calls.length, 1);
  eq("ⓓ 판정 불가", body(pi).includes("판정 불가"), true);
  eq("ⓓ 사유 줄", /사유: git fetch 실패 rc=\d+/.test(body(pi)), true);
  eq("ⓓ 설치 요청 문구 0", body(pi).includes("설치 h 발급 요청"), false);
  eq("ⓓ 표식 0", fs.existsSync(c.seen) && seenOf(c, L1), false);
  put(c, L2, "PENDING n=3\n"); // 다음 사건 = 새 착지 파일
  await wait(400);
  if (pi.calls.length === 1) { await pi.emit("agent_settled", {}); await wait(400); }
  eq("ⓓ 다음 사건에 다시 = 턴 2", pi.calls.length, 2);
}
// ── ⓔ 일하는 중 = 0 → agent_settled 에 1(여러 Q 한 본문) ──────────────────────────────────
{
  const c = setup("e"); useEnv(c);
  const pi = await load();
  await pi.emit("agent_start", {});
  put(c, L2); put(c, U1);
  await wait(400); step("e-busy");
  eq("ⓔ 일하는 중 = 0", pi.calls.length, 0);
  await pi.emit("agent_settled", {}); await wait(400);
  eq("ⓔ settled = 1", pi.calls.length, 1);
  eq("ⓔ 한 본문에 2건", body(pi).split("\n").filter((l) => l.startsWith("[")).length, 2);
  eq("ⓔ 표식 2개", [L2, U1].filter((s) => seenOf(c, s)).length, 2);
}
// ── ⓕ 비활성 좌석 = 0 (나노 · 다른 팀 _master · claude 좌석) ──────────────────────────────
{
  const nano = "byz-harness-nano-x#0";
  const c = setup("f1", { seat: nano, seats: { _master: SEAT, [SEAT]: { role: "master", agent: "pi" }, [nano]: { role: "nano", agent: "pi" } } });
  useEnv(c); const cap = capture(); const pi = await load(); cap.stop();
  eq("ⓕ1 나노 = inactive 1줄", cap.buf.filter((l) => l.includes("inactive")).length, 1);
  put(c, L1); await wait(400);
  eq("ⓕ1 나노 = 턴 0", pi.calls.length, 0);

  const c2 = setup("f2", { seats: { _master: "byz-other-master-pi#1" } });
  fs.writeFileSync(path.join(c2.base, "seats-planner.json"), JSON.stringify({ _master: SEAT, [SEAT]: { agent: "pi" } }) + "\n");
  useEnv(c2); const cap2 = capture(); const pi2 = await load(); cap2.stop();
  put(c2, L1); await wait(400);
  eq("ⓕ2 다른 팀 _master = 턴 0", pi2.calls.length, 0);

  const c3 = setup("f3", { seats: { _master: SEAT, [SEAT]: { role: "master", agent: "claude" } } });
  useEnv(c3); const cap3 = capture(); const pi3 = await load(); cap3.stop();
  put(c3, L1); await wait(400);
  eq("ⓕ3 claude 좌석 = 턴 0", pi3.calls.length, 0);
}
// ── ⓖ 세션 시작 때 표식 없는 기존 파일 = 1회(한 본문) ────────────────────────────────────
{
  const c = setup("g");
  put(c, L1); put(c, L2);
  useEnv(c);
  const pi = await load(); step("g-recover");
  await wait(300); // 시작 훑기는 비동기(fetch async)
  eq("ⓖ 시작 회수 = 턴 1", pi.calls.length, 1);
  eq("ⓖ 한 본문에 2건", body(pi).split("\n").filter((l) => l.startsWith("[착지 확인]")).length, 2);
}
// ── ⓗ 40hex 아닌 이름 = 무시 · 로그 1줄 ──────────────────────────────────────────────────
{
  const c = setup("h"); useEnv(c);
  const cap = capture(); const pi = await load();
  fs.mkdirSync(c.pend, { recursive: true });
  fs.writeFileSync(path.join(c.pend, "notes.md"), "x\n");
  fs.writeFileSync(path.join(c.pend, "deadbeef.txt"), "x\n");
  fs.writeFileSync(path.join(c.pend, `${L1.toUpperCase()}.txt`), "PENDING n=1\n");
  await wait(400);
  await pi.emit("agent_settled", {}); await wait(400); // 재훑기에서도 같은 이름은 1번만 기록된다
  cap.stop(); step("h-badname");
  eq("ⓗ 턴 0", pi.calls.length, 0);
  eq("ⓗ 로그 3줄", cap.buf.filter((l) => l.includes("이름 무시")).length, 3);
}
// ── R2 git fetch 비동기 = 이벤트 루프 막힘 0 ──────────────────────────────────────────
{
  const c = setup("r2");
  put(c, L1, "PENDING n=1\n"); // ★fs 이벤트에 기대지 않는다 — 시작 훑기가 같은 경로(git fetch)를 지난다★
  useEnv(c);
  const stubDir = path.join(TMP, "slowgit");
  fs.mkdirSync(stubDir, { recursive: true });
  const stub = path.join(stubDir, "git");
  fs.writeFileSync(stub, '#!/bin/bash\ncase "$*" in *" fetch "*) sleep 0.35; exit 0 ;; *) exit 1 ;; esac\n');
  fs.chmodSync(stub, 0o755); // 임시 폴더 스텁($TMP) — 저장소 파일 아님
  const oldPath = process.env.PATH;
  process.env.PATH = `${stubDir}:${oldPath}`;
  const t1 = Date.now(), marks = {};
  const timer = setTimeout(() => { marks.timer = Date.now() - t1; }, 50);
  const pi = await load();
  const orig = pi.sendMessage.bind(pi);
  pi.sendMessage = (m, o) => { marks.send = Date.now() - t1; orig(m, o); };
  await wait(900);
  clearTimeout(timer); process.env.PATH = oldPath; step("r2-async");
  eq("R2 턴 1(느린 fetch 뒤)", pi.calls.length, 1);
  eq("R2 50ms 타이머가 fetch(350ms)보다 먼저", (marks.timer ?? 9999) < 200, true);
  eq("R2 턴은 fetch 뒤(>=250ms)", (marks.send ?? -1) >= 250, true);
}

// ── R3 판정 불가 Q 는 다음 사건에 다시 뜼다(unknownDone 비우기) ────────────────────────────
{
  const c = setup("r3", { clone: false }); // git 실패 → 판정 불가
  useEnv(c);
  const pi = await load();
  put(c, L1);
  await wait(400);
  if (pi.calls.length === 0) { await pi.emit("agent_settled", {}); await wait(400); }
  eq("R3 첫 사건 = 턴 1", pi.calls.length, 1);
  eq("R3 첫 본문 = 판정 불가", body(pi).includes("판정 불가"), true);
  eq("R3 표식 0", !seenOf(c, L1), true);
  fs.writeFileSync(path.join(c.pend, "notes.md"), "x\n"); // 다음 사건(비-40hex) — 표식 0 인 Q 를 다시 훑게 한다
  await wait(400);
  if (pi.calls.length === 1) { await pi.emit("agent_settled", {}); await wait(400); }
  eq("R3 다음 사건에 다시 = 턴 2", pi.calls.length, 2);
  eq("R3 두 번째도 같은 Q 판정 불가", body(pi, 1).includes(L1.slice(0, 10)) && body(pi, 1).includes("판정 불가"), true);
}

// ── 변이 M1 표식 끔 → ⓑ 에서 2 = 검출 ──────────────────────────────────────────────────
function mutate(name, from, to) {
  const src = fs.readFileSync(EXT, "utf-8"), n = src.split(from).length - 1;
  eq(`MUT ${name} 지점 1개`, n, 1);
  const p = path.join(TMP, `mut-${name}.ts`);
  fs.writeFileSync(p, src.replace(from, to));
  return p;
}
{
  const ext1 = mutate("M1", "const marked = (sha: string): boolean => fs.existsSync(path.join(seenDir, sha));", "const marked = (sha: string): boolean => false;");
  const c = setup("m1"); useEnv(c);
  const pi = await load(ext1);
  put(c, L1);
  await wait(400);
  await pi.emit("agent_settled", {}); await wait(400);
  await pi.emit("agent_settled", {}); await wait(400); step("m1");
  eq("M1 첫 사건 = 1 이상", pi.calls.length >= 1, true);
  eq("M1 표식 끔 = 같은 Q 를 또 보고한다(변이 검출 · 기준은 1)", pi.calls.length >= 2, true);
}
// ── 변이 M2 MERGED 확인 끔 → ⓒ 에서 설치 요청 문구 = 검출 ───────────────────────────────
{
  const ext2 = mutate("M2", 'if (it.verdict === "merged") return', "if (true) return");
  const c = setup("m2"); useEnv(c);
  const pi = await load(ext2);
  put(c, U1, "PENDING n=1\n");
  await wait(400);
  if (pi.calls.length === 0) { await pi.emit("agent_settled", {}); await wait(400); }
  step("m2");
  eq("M2 확인 끔 = ⓒ 에서 설치 요청 문구(변이 검출)", body(pi).includes("설치 h 발급 요청"), true);
}

console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R1532_EXT="$EXT" R1532_TMP="$T" R1532_SEAT="$SEAT" R1532_BARE="$T/remote.git" \
R1532_L1="$L1" R1532_L2="$L2" R1532_U1="$U1" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
