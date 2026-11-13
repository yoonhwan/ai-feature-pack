// ft-land-next (r1532) — 착지 1개 = «다음 h(설치) 안내» 1회. ft-merge-land 가 착지 뒤 남기는 <state>/install-pending/<Q>.txt 를 fs.watch 로 듣는다.
//  · 활성 = seats-harness.json `_master` 이고 «같은 파일» 그 행 agent=='pi' (r1530 piMasterFile 식 · 이 카드 기준 HEAD 에는 r1530 미착지라 같은 식 복사)
//    r1558 — 그 판정은 «사건마다» 다시 한다(로드 1회 금지). 은퇴 좌석은 착지마다 턴 0 · 승계 전에 뜬 좌석은 reload 없이 활성
//  · 새 40hex 파일마다 사건 1회: 리포(BYZ 루트 · 팩)에서 git fetch origin main → Q 가 origin/main 의 조상인가 (주기 폴링 0 · 상시 조회 0 · fetch 는 비동기 = 이벤트 루프 막힘 0)
//  · 확인 뒤 sendMessage(triggerTurn, followUp) 1회 · 쉬면 바로 · 일하면 다음 agent_settled 에 모아 1회(여러 Q = 한 본문)
//  · 표식 <state>/pi-wake/land-seen/<Q> 는 턴 요청 «뒤» · 판정 불가(git 실패)면 표식 0 = 다음 사건에 다시
//  · 설치 h 발급 자체는 좌석의 일(planner [HIL]) — 이 확장은 h 를 만들지 않는다
//  · env: FT_LAND_NEXT_ROOT · FT_LAND_NEXT_PACK · FT_LAND_NEXT_STATE · FT_LAND_NEXT_SEATS · FT_LAND_NEXT_DEBOUNCE_MS · FT_LAND_NEXT_FETCH_MS
//  · 시험 = harness/tests/test_pi_land_next_r1532.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { execFile, execFileSync, execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine } from "./ft-load-line.ts"; // r1537 — 세션 기록 «로드 <카드> <판>» 1줄(턴 0)
import { say } from "./ft-load-line.ts"; // r1837 — 진단 1줄 출력 길(TUI = 파일 로그)

type Verdict = "merged" | "missing" | "unknown";
export type Item = { sha: string; file: string; pending: number; verdict: Verdict; reason: string };

const sh = (cmd: string): string => { try { return execSync(cmd, { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "pipe"] }).trim(); } catch { return ""; } };
const log = (m: string) => say(`ft-land-next: ${m}`);
const fail = (m: string) => say(`ERROR ft-land-next: ${m}`);
export const seatName = (): string => process.env.FT_SEAT || sh('tmux display-message -p "#S"');
// root = «git 공용 루트» — pi pane 의 cwd 는 워크트리일 수 있다(ft-mbox-wake r1530 과 같은 식).
const gitRoot = (): string => { const d = sh("git rev-parse --path-format=absolute --git-common-dir"); return d ? path.dirname(d) : ""; };

// 팀장 pi 판정(piMasterFile 식) = seats*.json 하나의 _master 이고 «같은 파일» 그 행 agent=='pi' → 그 파일 이름(없으면 "") · 깨진 파일 = 그 파일 거짓
export function piMasterFile(root: string, seat: string): string {
  const d = path.join(root, ".fable-team"); let names: string[] = []; try { names = fs.readdirSync(d).filter((f) => /^seats.*\.json$/.test(f)).sort(); } catch { return ""; }
  for (const f of names) { try { const j = JSON.parse(fs.readFileSync(path.join(d, f), "utf-8")), r = j?.[seat]; if (r?.agent === "pi" && j._master === seat) return f; } catch { continue; } }
  return "";
}

// ft-live-install-check 출력 첫 줄 «PENDING n=2» → 2 (없으면 0)
export function pendingCount(file: string): number {
  try { const m = /PENDING\s+n=(\d+)/.exec(fs.readFileSync(file, "utf-8").split("\n")[0] ?? ""); return m ? Number(m[1]) : 0; } catch { return 0; }
}

// 감시 폴더 → 40hex(.txt) 파일만 · mtime 내림차순 · 나머지 이름은 bad(로그 1줄용)
export function landScan(dir: string): { ok: { sha: string; file: string }[]; bad: string[] } {
  let names: string[] = []; try { names = fs.readdirSync(dir); } catch { return { ok: [], bad: [] }; }
  const ok: { sha: string; file: string; mt: number }[] = [], bad: string[] = [];
  for (const n of names) {
    const m = /^([0-9a-f]{40})(?:\.txt)?$/.exec(n), file = path.join(dir, n);
    if (!m) { bad.push(n); continue; }
    try { ok.push({ sha: m[1], file, mt: fs.statSync(file).mtimeMs }); } catch { continue; }
  }
  return { ok: ok.sort((a, b) => b.mt - a.mt).map(({ sha, file }) => ({ sha, file })), bad };
}

// 본문 1줄 — 기준값(카드 ⓐ·ⓒ·ⓓ) 그대로
export function bodyOf(it: Item): string {
  const q = it.sha.slice(0, 10), tail = `대기 파일 ${it.file}`;
  if (it.verdict === "merged") return `[착지 확인] main ${q} · 설치 PENDING ${it.pending} · 다음 h = 설치 h 발급 요청(planner [HIL]) · ${tail}`;
  if (it.verdict === "missing") return `[착지 확인 불가] ${q} · 원격 main 에 없음 · ${tail}`;
  return `[판정 불가] ${q} · 사유: ${it.reason} · ${tail}`;
}

const git = (args: string[], ms: number): number => {
  try { execFileSync("git", args, { encoding: "utf-8", timeout: ms, stdio: ["ignore", "pipe", "pipe"] }); return 0; }
  catch (e: any) { return typeof e?.status === "number" ? e.status : 1; }
};
// 하드 룰 12 — 1회 + 재시도 1 · 시간 초과 = rc≠0(판정 불가)
// ★R2: fetch 는 비동기 execFile★ — 동기 execFileSync 는 최대 fetchMs×2 동안 pi 이벤트 루프를 막는다(arch 반례 2)
const gitAsync = (args: string[], ms: number): Promise<number> => new Promise((resolve) => {
  execFile("git", args, { encoding: "utf-8", timeout: ms }, (e: any) => resolve(e ? (typeof e.code === "number" ? e.code : 1) : 0));
});
const fetchMain = async (repo: string, ms: number): Promise<number> => { let rc = await gitAsync(["-C", repo, "fetch", "--quiet", "origin", "main"], ms); if (rc !== 0) rc = await gitAsync(["-C", repo, "fetch", "--quiet", "origin", "main"], ms); return rc; };
const isAncestor = (repo: string, sha: string): boolean => git(["-C", repo, "merge-base", "--is-ancestor", sha, "origin/main"], 7000) === 0;

export default function (pi: ExtensionAPI) {
  // r1537 — 로드 줄은 «이 확장이 실렸다» 만 말한다 ⇒ ★활성 guard «앞»에서 등록★(비활성 좌석도 1줄 · 기능은 그대로 비활성)
  pi.on("session_start", async () => { appendLoadLine(pi, "r1532", "ft-land-next.ts"); });
  const root = process.env.FT_LAND_NEXT_ROOT || gitRoot() || process.cwd();
  const seat = seatName(), teamFile = process.env.FT_LAND_NEXT_SEATS || "seats-harness.json";
  const state = process.env.FT_LAND_NEXT_STATE || path.join(root, ".fable-team", "state");
  const dir = path.join(state, "install-pending"), seenDir = path.join(state, "pi-wake", "land-seen");
  // r1558 — 활성 판정 = «사건마다» 다시 본다(로드 1회 아님 · ft-mbox-wake r1529 activeSeat 와 같은 칸). 좌석 이름(seat)만 로드 때 읽는다(tmux 세션명은 안 바뀐다)
  const active = (): boolean => !!seat && piMasterFile(root, seat) === teamFile;
  let said = ""; // 같은 비활성 사유 반복 = log 0(사건이 몰려도 1줄) · 활성이 되면 비워 다시 1줄 쓸 수 있게
  const ensure = (): void => { try { fs.mkdirSync(dir, { recursive: true }); fs.mkdirSync(seenDir, { recursive: true }); } catch { /* 이미 있음 */ } };
  const onChange = (): void => { unknownDone.clear(); schedule(); };
  // 감시는 «폴더를 만들지 않는다» — 비활성 좌석이 감시 폴더를 만들면 r1537 ⓖ 위반. 폴더가 없으면 부모(state)를 지켜보다가 생기면 갈아탄다(감시 1개 유지 · 사건 중복 0)
  function arm(): void {
    const p = fs.existsSync(dir) ? dir : fs.existsSync(state) ? state : "";
    if (!p || watchPath === p) return;
    try { watcher?.close(); watcher = fs.watch(p, onChange); watchPath = p; } catch (e) { fail(`watch 실패 ${p} — ${e}`); }
  }
  function gate(): boolean { // 비활성 = 턴 0 · git fetch 0 · 표식 0 (r1558 ⓑ·ⓒ·ⓕ) — 핸들러는 늘 등록하고 «사건마다» 여기서 판정한다
    if (active()) { said = ""; ensure(); arm(); return true; }
    const why = `inactive seat=${seat || "?"} team=${teamFile}`;
    if (said !== why) { said = why; log(why); }
    arm(); // 승계 전에 뜬 좌석도 다음 착지 사건을 받도록 감시만 걸어 둔다(폴더 생성 0 · 턴 0)
    return false;
  }
  const repos = [...new Set([root, process.env.FT_LAND_NEXT_PACK || "/Users/yoonhwan/Project/ai-feature-pack"])];
  const debounce = Number(process.env.FT_LAND_NEXT_DEBOUNCE_MS ?? 300), fetchMs = Number(process.env.FT_LAND_NEXT_FETCH_MS ?? 25000);
  const bad = new Set<string>(), unknownDone = new Set<string>(); // unknownDone = settle 재훑기에서만 억제(fs 사건·세션 시작에서 비운다 · R3)
  let timer: ReturnType<typeof setTimeout> | null = null, busy = false, queue: Item[] = [];
  let watcher: fs.FSWatcher | null = null, watchPath = ""; // r1558 — 감시 1개(폴더 또는 부모 state) · 한 번에 하나만

  const marked = (sha: string): boolean => fs.existsSync(path.join(seenDir, sha)); // ★표식 — 같은 Q 재사건 0 (M1 변이 지점)
  const stamp = (sha: string) => { try { fs.mkdirSync(seenDir, { recursive: true }); fs.writeFileSync(path.join(seenDir, sha), `${new Date().toISOString()}\n`); } catch (e) { fail(`표식 쓰기 실패 ${sha} — ${e}`); } };
  function send(items: Item[]) {
    if (!items.length) return;
    if (!gate()) return; // r1558 — 보낼 때 다시 판정 — 일하는 중 쌓인 Q 를 은퇴 좌석이 가져가지 않는다(ⓒ)
    try { pi.sendMessage({ customType: "ft-land-next", content: items.map(bodyOf).join("\n"), display: true }, { triggerTurn: true, deliverAs: "followUp" }); }
    catch (e) { return fail(`sendMessage 실패 — ${e}`); } // 턴 0 → 표식도 0 = 다음 사건에 다시
    for (const it of items) { if (it.verdict === "unknown") unknownDone.add(it.sha); else stamp(it.sha); } // 판정 불가 = 표식 0(단 같은 세션 재보고는 1회)
  }
  const flush = () => { const q = queue; queue = []; send(q); }; // ⓔ settled 에 모아 1회

  function judge(sha: string, file: string, fetched: { repo: string; rc: number }[]): Item {
    const pending = pendingCount(file);
    if (fetched.some((f) => f.rc === 0 && isAncestor(f.repo, sha))) return { sha, file, pending, verdict: "merged", reason: "" };
    const f0 = fetched.find((f) => f.rc !== 0);
    if (f0) return { sha, file, pending, verdict: "unknown", reason: `git fetch 실패 rc=${f0.rc} (${f0.repo})` }; // ⓓ 표식 0
    return { sha, file, pending, verdict: "missing", reason: "" }; // ⓒ
  }
  async function scan(): Promise<void> {
    if (!gate()) return; // r1558 — 비활성(나노 · 다른 팀 _master · 은퇴 좌석) = git fetch 0 · 표식 0(ⓑ·ⓕ)
    const { ok, bad: wrong } = landScan(dir);
    for (const n of wrong) if (!n.startsWith(".") && !bad.has(n)) { bad.add(n); log(`이름 무시(40hex 아님) ${n}`); } // ⓗ
    const fresh = ok.filter(({ sha }) => !marked(sha) && !unknownDone.has(sha) && !queue.some((q) => q.sha === sha));
    if (!fresh.length) return;
    const fetched = await Promise.all(repos.map(async (repo) => ({ repo, rc: await fetchMain(repo, fetchMs) }))); // 사건 1회 · 리포당 1회 · 비동기
    const items = fresh.map(({ sha, file }) => judge(sha, file, fetched));
    if (busy) { queue.push(...items); log(`일하는 중 — settled 에 ${items.length}건`); return; }
    send(items);
  }
  let scanning = false, again = false;
  async function run(): Promise<void> {
    if (scanning) { again = true; return; } // 비동기 fetch 동안 또 들어온 사건 = 끝난 뒤 1회 더
    scanning = true;
    try { await scan(); } catch (e) { fail(`감시 처리 실패 — ${e}`); } finally { scanning = false; }
    if (again) { again = false; void run(); }
  }
  const schedule = () => { if (!timer) timer = setTimeout(() => { timer = null; void run(); }, debounce); };

  pi.on("session_start", async () => {
    unknownDone.clear(); // R3 — 새 세션은 판정 불가 Q 도 다시 본다
    if (!gate()) return; // 비활성 = 폴더·턴 0(r1537 ⓖ) · 감시만 부모(state)에 걸어 승계 사건을 기다린다(r1558 ⓐ)
    void run(); // ⓖ 시작 회수 = 표식 없는 기존 파일 1회(한 본문)
  });
  pi.on("agent_start", async () => { busy = true; });
  pi.on("agent_settled", async () => { busy = false; flush(); void run(); }); // 쉼 경계 1회 더 훑기 = fs.watch 가 놓친 사건 회수(표식 있는 파일은 git 호출 0)
  pi.on("session_shutdown", async () => { watcher?.close(); watcher = null; watchPath = ""; if (timer) clearTimeout(timer); timer = null; });
}
