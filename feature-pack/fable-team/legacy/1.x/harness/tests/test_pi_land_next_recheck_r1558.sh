#!/usr/bin/env bash
# test_pi_land_next_recheck_r1558.sh — r1558: ft-land-next 의 활성 판정이 «사건마다» 인가(로드 1회 판정 아님)
#  격리: 임시 루트(가짜 seats-harness.json · 임시 install-pending 폴더) · 가짜 git(bare 원격 + clone · 스텁 git = 호출 장부) ·
#        가짜 pi(sendMessage·appendEntry 기록) · 실 원격 0 · 실 우편함 0 · 실 pi 세션 0 · 실 명부 0.
#  ⓐ 로드 때 비활성 → 명부 _master 를 이 좌석으로 → 착지 사건 = 턴 1 · 표식 1 (reload 0)
#  ⓑ 로드 때 활성 → _master 를 다른 좌석으로 → 사건 = 턴 0 · git 호출 0 · 표식 0 · log «inactive …» 1줄
#  ⓒ 활성 → 일하는 중 큐에 쌓임 → _master 교체 → agent_settled = 턴 0 · 표식 0(보낼 때 다시 판정)
#  ⓓ 활성 그대로 = 지금 동작(사건 → 턴 1 · 본문 꼴 그대로 · 표식 1)
#  ⓔ 로드 줄(r1537)은 활성·비활성 모두 1줄 그대로
#  ⓕ 비활성 = git 호출 0 · 폴더 생성 0 · 주기 타이머 0(정적 검사)
#  변이: M1 판정을 로드 1회로 되돌림 → ⓑ 검출 · M2 send 재판정 0 → ⓒ 검출 · M3 비활성인데 fetch 먼저 → ⓕ 검출
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
EXT="$HARNESS/pi/ft-land-next.ts"
SEAT="${R1558_SEAT:-byz-harness-master-pi#173}"
OTHER="${R1558_OTHER:-byz-harness-master-pi#172}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }

[ -f "$EXT" ] || { echo "FAIL 확장 없음 $EXT"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "FAIL git 없음"; exit 1; }

# ── 정적 계약 ─────────────────────────────────────────────────────────────────────────
eq "S1 확장 200줄 아래" "$([ "$(wc -l < "$EXT" | tr -d ' ')" -le 199 ] && echo yes || echo no)" yes
eq "S2 로드 시점 활성 guard 잔재 0" "$(grep -c 'if (!seat || piMasterFile' "$EXT")" 0
eq "S3 판정 자리 = session_start·scan·send 3곳" "$(grep -c 'if (!gate()) return;' "$EXT")" 3
eq "S4 piMasterFile 호출 = active() 안 1곳(사건마다)" "$(grep -c 'piMasterFile(root, seat)' "$EXT")" 1
eq "S5 주기 폴링 0(setInterval)" "$(grep -c 'setInterval' "$EXT")" 0
bash -n "$0" && ok "S6 bash -n rc0" || bad "S6 bash -n rc0"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1558-recheck.XXXXXX")"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
GC=(-c user.email=t@example.com -c user.name=t)
git init -q --bare "$T/remote.git" || { echo "FAIL 가짜 원격 생성"; exit 1; }
git -C "$T/remote.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$T/seed"
git -C "$T/seed" "${GC[@]}" commit -q --allow-empty -m landed-1
L1="$(git -C "$T/seed" rev-parse HEAD)"
git -C "$T/seed" remote add origin "$T/remote.git"
git -C "$T/seed" push -q origin main
git -C "$T/seed" "${GC[@]}" commit -q --allow-empty -m not-landed
U1="$(git -C "$T/seed" rev-parse HEAD)"
echo "seed: main=$L1 · 미착지=$U1"

cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import { pathToFileURL } from "node:url";

const EXT = process.env.R1558_EXT, TMP = process.env.R1558_TMP, BARE = process.env.R1558_BARE;
const SEAT = process.env.R1558_SEAT, OTHER = process.env.R1558_OTHER, L1 = process.env.R1558_L1, U1 = process.env.R1558_U1;
let fails = 0, modv = 0;
const t0 = Date.now();
const step = (n) => console.log(`STEP ${n} ${((Date.now() - t0) / 1000).toFixed(1)}s`);
const ok = (n) => console.log(`PASS ${n}`);
const bad = (n, d = "") => { fails++; console.log(`FAIL ${n}${d ? ` :: ${d}` : ""}`); };
const eq = (n, got, want) => (String(got) === String(want) ? ok(n) : bad(n, `기대 '${want}' 실제 '${got}'`));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// clone=false = git 실패(판정 불가) · stateDir=true = 승계 전에도 state 폴더가 있는 실제 상황
function setup(name, { clone = true, seats = null, stateDir = false } = {}) {
  const dir = path.join(TMP, `c-${name}`);
  fs.rmSync(dir, { recursive: true, force: true });
  if (clone) execFileSync("git", ["clone", "-q", BARE, dir], { stdio: ["ignore", "pipe", "pipe"] });
  else fs.mkdirSync(dir, { recursive: true });
  const base = path.join(dir, ".fable-team"), pack = clone ? dir : path.join(TMP, `pack-${name}`);
  fs.mkdirSync(base, { recursive: true });
  if (!clone) fs.mkdirSync(pack, { recursive: true }); // git 아닌 폴더 = fetch 실패
  const state = path.join(base, "state");
  if (stateDir) fs.mkdirSync(state, { recursive: true });
  const s = seats ?? { _master: SEAT, [SEAT]: { role: "master", agent: "pi" }, [OTHER]: { role: "master", agent: "pi" } };
  fs.writeFileSync(path.join(base, "seats-harness.json"), JSON.stringify(s) + "\n");
  return { dir, base, pack, state, pend: path.join(state, "install-pending"), seen: path.join(state, "pi-wake", "land-seen") };
}
const seatsOf = (c, master) => [{ _master: master, [SEAT]: { role: "master", agent: "pi" }, [OTHER]: { role: "master", agent: "pi" } }];
function useEnv(c) {
  Object.assign(process.env, {
    FT_LAND_NEXT_ROOT: c.dir, FT_LAND_NEXT_PACK: c.pack, FT_LAND_NEXT_STATE: c.state,
    FT_SEAT: SEAT, FT_LAND_NEXT_DEBOUNCE_MS: "5", FT_LAND_NEXT_FETCH_MS: "4000",
  });
  delete process.env.FT_LAND_NEXT_SEATS;
}
const put = (c, sha, text = "PENDING n=2\nDIFF x\n") => { fs.mkdirSync(c.pend, { recursive: true }); fs.writeFileSync(path.join(c.pend, `${sha}.txt`), text); };
const seenOf = (c, sha) => fs.existsSync(path.join(c.seen, sha));
const setMaster = (c, master) => fs.writeFileSync(path.join(c.base, "seats-harness.json"), JSON.stringify(seatsOf(c, master)[0]) + "\n");
function capture() { const buf = []; const orig = console.error; console.error = (...a) => buf.push(a.map(String).join(" ")); return { buf, stop: () => { console.error = orig; } }; }

// 스텁 git = 호출 장부(비활성 사건에 git 호출이 있는가 · 변이 M3 검출용)
function stubGit(name) {
  const dir = path.join(TMP, `stub-${name}`), log = path.join(TMP, `stub-${name}.log`);
  fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(log, "");
  const p = path.join(dir, "git");
  fs.writeFileSync(p, `#!/bin/bash\nprintf '%s\\n' "$*" >> "${log}"\nexit 0\n`);
  fs.chmodSync(p, 0o755); // 임시 폴더 스텁($TMP) — 저장소 파일 아님
  return { dir, calls: () => fs.readFileSync(log, "utf-8").split("\n").filter(Boolean).length };
}
function withPath(dir, fn) { const old = process.env.PATH; process.env.PATH = `${dir}:${old}`; return fn().finally(() => { process.env.PATH = old; }); }

const live = [];
async function load(ext = EXT) {
  for (const p of live.splice(0)) { p.retired = true; await p.emit("session_shutdown", {}); }
  const pi = { calls: [], retired: false, h: {}, entries: [], on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev, { isIdle: () => true }); },
    appendEntry(t, d) { this.entries.push({ t, d }); }, // r1537 로드 줄
    sendMessage(m, o) { if (!this.retired) this.calls.push({ m, o }); } };
  live.push(pi);
  const mod = await import(`${pathToFileURL(ext).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("session_start", {}); // reload 0 — 이 카드의 사건은 «승계» 이지 재로드가 아니다
  return pi;
}
const body = (pi, i = 0) => pi.calls[i]?.m?.content ?? "";
const loadLines = (pi) => pi.entries.filter((e) => e.t === "ft-load-line");

// ── ⓐ 로드 때 비활성 → _master 를 이 좌석으로 → 착지 사건 = 턴 1 · 표식 1 (reload 0) ──────────
{
  const c = setup("a", { stateDir: true, seats: { _master: OTHER, [SEAT]: { role: "master", agent: "pi" }, [OTHER]: { role: "master", agent: "pi" } } });
  useEnv(c);
  const pi = await load();
  eq("ⓐ 로드 때 비활성 = 턴 0", pi.calls.length, 0);
  eq("ⓐ 로드 때 비활성 = 감시 폴더 생성 0", fs.existsSync(c.pend), false);
  setMaster(c, SEAT); // 승계 — reload 0 · 이 인스턴스는 그대로
  put(c, L1);
  await wait(500); step("a-succession");
  if (pi.calls.length === 0) { console.log("NOTE ⓐ fs 이벤트 미도착 — settled 회수 경로로 확인"); await pi.emit("agent_settled", {}); await wait(400); }
  eq("ⓐ 승계 뒤 착지 사건 = 턴 1(reload 0)", pi.calls.length, 1);
  eq("ⓐ 본문 = 착지 확인", body(pi).includes("[착지 확인]"), true);
  eq("ⓐ 표식 1", seenOf(c, L1), true);
}

// ── ⓑ 로드 때 활성 → _master 를 다른 좌석으로 → 사건 = 턴 0 · git 0 · 표식 0 · inactive 1줄 ──
{
  const c = setup("b", { stateDir: true }); useEnv(c);
  const pi = await load();
  setMaster(c, OTHER); // 은퇴 — 이 인스턴스는 이제 남의 좌석이다
  const g = stubGit("b"), cap = capture();
  put(c, L1);
  await withPath(g.dir, async () => { await wait(500); await pi.emit("agent_settled", {}); await wait(300); });
  cap.stop(); step("b-retired");
  eq("ⓑ 은퇴 좌석 = 턴 0", pi.calls.length, 0);
  eq("ⓑ 은퇴 좌석 = git 호출 0", g.calls(), 0);
  eq("ⓑ 은퇴 좌석 = 표식 쓰기 0", seenOf(c, L1), false);
  eq("ⓑ log «inactive …» = 1줄", cap.buf.filter((l) => l.includes("inactive")).length, 1);
}

// ── ⓒ 일하는 중 큐에 쌓임 → _master 교체 → agent_settled = 턴 0 · 표식 0 ────────────────────
{
  const c = setup("c", { stateDir: true }); useEnv(c);
  const pi = await load();
  await pi.emit("agent_start", {});
  put(c, L1);
  await wait(400);
  eq("ⓒ 일하는 중 = 턴 0(큐 대기)", pi.calls.length, 0);
  setMaster(c, OTHER); // 교체 — 새 팀장이 같은 Q 를 받아야 한다(표식 0)
  await pi.emit("agent_settled", {});
  await wait(400); step("c-settled");
  eq("ⓒ 보낼 때 다시 판정 = 턴 0", pi.calls.length, 0);
  eq("ⓒ 표식 0(새 팀장 몫)", seenOf(c, L1), false);
}

// ── ⓓ 활성 그대로 = 지금 동작(사건 → 턴 1 · 본문 꼴 · 표식 1) ────────────────────────────────
{
  const c = setup("d", { stateDir: true }); useEnv(c);
  const pi = await load();
  put(c, L1);
  await wait(500); step("d-active");
  if (pi.calls.length === 0) { await pi.emit("agent_settled", {}); await wait(400); }
  eq("ⓓ 활성 = 턴 1", pi.calls.length, 1);
  eq("ⓓ 본문 꼴 그대로", body(pi), `[착지 확인] main ${L1.slice(0, 10)} · 설치 PENDING 2 · 다음 h = 설치 h 발급 요청(planner [HIL]) · 대기 파일 ${path.join(c.pend, `${L1}.txt`)}`);
  eq("ⓓ triggerTurn/followUp", `${pi.calls[0]?.o?.triggerTurn}/${pi.calls[0]?.o?.deliverAs}`, "true/followUp");
  eq("ⓓ 표식 1", seenOf(c, L1), true);
}

// ── ⓔ 로드 줄(r1537)은 활성·비활성 모두 1줄 그대로 ──────────────────────────────────────────
{
  const a = setup("e1", { stateDir: true }); useEnv(a);
  const pa = await load();
  eq("ⓔ 활성 로드 줄 1줄", loadLines(pa).length, 1);
  eq("ⓔ 활성 로드 줄 카드 = r1532", loadLines(pa)[0]?.d?.card, "r1532");
  eq("ⓔ 활성 로드 줄 모델 턴 0", `${pa.calls.length}|${/^로드 r1532 (?:[0-9a-f]{8}|판 불명)$/.test(loadLines(pa)[0]?.d?.line ?? "")}`, "0|true");
  const b = setup("e2", { stateDir: true, seats: { _master: OTHER, [SEAT]: { role: "master", agent: "pi" }, [OTHER]: { role: "master", agent: "pi" } } });
  useEnv(b);
  const cap = capture(); const pb = await load(); cap.stop();
  eq("ⓔ 비활성 로드 줄 1줄", loadLines(pb).length, 1);
  eq("ⓔ 비활성 로드 줄 카드 = r1532", loadLines(pb)[0]?.d?.card, "r1532");
  eq("ⓔ 비활성 로드 줄 모델 턴 0", pb.calls.length, 0);
}

// ── ⓕ 비활성 = git 호출 0 · 폴더 0 · 턴 0 (사건 2회) ────────────────────────────────────────
{
  const c = setup("f", { stateDir: true, seats: { _master: OTHER, [SEAT]: { role: "master", agent: "pi" }, [OTHER]: { role: "master", agent: "pi" } } });
  useEnv(c);
  const pi = await load();
  eq("ⓕ 비활성 로드 = 폴더 생성 0", fs.existsSync(c.pend), false); // 폴더는 시험이 만든다 — 확장이 만들면 r1537 ⓖ 위반
  const g = stubGit("f");
  await withPath(g.dir, async () => { put(c, L1); put(c, U1, "PENDING n=1\n"); await wait(500); await pi.emit("agent_settled", {}); await wait(300); });
  step("f-inactive");
  eq("ⓕ 비활성 사건 2회 = 턴 0", pi.calls.length, 0);
  eq("ⓕ 비활성 = git 호출 0", g.calls(), 0);
  eq("ⓕ 비활성 = 표식 0", fs.existsSync(c.seen), false);
}

// ── 변이 도우미 ───────────────────────────────────────────────────────────────────────────
function mutate(name, from, to) {
  const src = fs.readFileSync(EXT, "utf-8"), n = src.split(from).length - 1;
  eq(`MUT ${name} 지점 1개`, n, 1);
  const p = path.join(TMP, `mut-${name}.ts`);
  fs.copyFileSync(path.join(path.dirname(EXT), "ft-load-line.ts"), path.join(TMP, "ft-load-line.ts")); // 변이 사본의 상대 import
  fs.writeFileSync(p, src.replace(from, to));
  return p;
}

// ── M1 로드 1회 판정으로 되돌림 → ⓑ(은퇴 좌석 턴 0) 검출 ───────────────────────────────────
{
  const ext1 = mutate("M1", "(): boolean => !!seat && piMasterFile(root, seat) === teamFile",
    "((v: boolean) => () => v)(!!seat && piMasterFile(root, seat) === teamFile)");
  const c = setup("m1", { stateDir: true }); useEnv(c);
  const pi = await load(ext1);
  setMaster(c, OTHER);
  put(c, L1);
  await wait(500); await pi.emit("agent_settled", {}); await wait(300); step("m1");
  eq("M1 로드 1회 판정 = 은퇴 좌석이 턴을 연다(변이 검출 · 기준 0)", pi.calls.length >= 1, true);
}

// ── M2 send 재판정 0 → ⓒ(큐에 쌓인 Q 를 은퇴 좌석이 가져감) 검출 ───────────────────────────
{
  const ext2 = mutate("M2", "    if (!gate()) return; // r1558 — 보낼 때 다시 판정 — 일하는 중 쌓인 Q 를 은퇴 좌석이 가져가지 않는다(ⓒ)",
    "    if (false) return;");
  const c = setup("m2", { stateDir: true }); useEnv(c);
  const pi = await load(ext2);
  await pi.emit("agent_start", {});
  put(c, L1);
  await wait(400);
  setMaster(c, OTHER);
  await pi.emit("agent_settled", {});
  await wait(400); step("m2");
  eq("M2 재판정 0 = 은퇴 좌석이 큐를 보낸다(변이 검출 · 기준 0)", pi.calls.length >= 1, true);
}

// ── M3 비활성인데 fetch 먼저 → ⓕ(비활성 git 호출 0) 검출 ────────────────────────────────────
{
  const ext3 = mutate("M3", "    if (!gate()) return; // r1558 — 비활성(나노 · 다른 팀 _master · 은퇴 좌석) = git fetch 0 · 표식 0(ⓑ·ⓕ)",
    "    if (false) return;");
  const c = setup("m3", { stateDir: true, seats: { _master: OTHER, [SEAT]: { role: "master", agent: "pi" }, [OTHER]: { role: "master", agent: "pi" } } });
  useEnv(c);
  const pi = await load(ext3);
  const g = stubGit("m3");
  await withPath(g.dir, async () => { put(c, L1); await wait(500); });
  step("m3");
  eq("M3 비활성인데 git 을 부른다(변이 검출 · 기준 0)", g.calls() >= 1, true);
  eq("M3 그래도 턴 0(send 재판정은 남아 있다)", pi.calls.length, 0);
}

console.log("---");
if (fails === 0) { console.log("DRIVER ALL PASS"); process.exit(0); }
console.log(`DRIVER FAIL ${fails}`); process.exit(1);
NODE

R1558_EXT="$EXT" R1558_TMP="$T" R1558_SEAT="$SEAT" R1558_OTHER="$OTHER" R1558_BARE="$T/remote.git" \
R1558_L1="$L1" R1558_U1="$U1" \
  timeout 70 node "$T/driver.mjs"; rc=$?
echo "---"
if [ "$rc" = 0 ] && [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAIL (static=$fail node_rc=$rc)"; exit 1
