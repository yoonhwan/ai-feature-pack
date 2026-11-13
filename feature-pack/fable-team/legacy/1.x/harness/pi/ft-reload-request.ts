// ft-reload-request (r1531) — 설치 h 의 끝줄이 남긴 <state>/pi-wake/<좌석키>.reload 를 fs.watch 로 보고, 좌석이 쉬면 바로·
//  일하는 중이면 agent_settled 에서 `/ft-reload-runtime` 명령을 «1회» 보낸다. 그래서 tmux send-keys /reload 입력 주입이 0 이 된다.
//  ★요청 파일은 reload 전에 지운다★ — 지우기 성공 = 요청 1 · 실패 = reload 0 + ERROR 1줄(no_silent_fallback).
//  · r1540 = 거절되면 요청을 «되살린다» — pi 는 일하는 중 reload 를 거절한다(interactive-mode.js:5438 «Wait for the current response…» · docs/extensions.md:1536). 지운 뒤 거절되면 요청이 조용히 사라지므로 handler 가 reload 직전에 한 번 더 쉼을 확인하고, 일하는 중이면 파일을 다시 쓴 뒤 pending 으로 두어 다음 정상 settled 에서 1회 쓴다.
//  · 활성 판정·state·좌석키 = ft-mbox-wake.ts(r1477·r1529) 와 «같은 식»(두 벌이 다른 말을 하면 좌석이 두 길로 리로드한다).
//  · 설치 = `~/.pi/agent/extensions/ft-reload-request.ts` 복사 1개 · 첫 적용만 오빠 /reload 1회.
//  · env: FT_MBOX_ROOT · FT_MBOX_STATE_DIR · FT_SEAT · FT_RELOAD_REQUEST_DEBOUNCE_MS · 시험 = tests/test_pi_reload_request_r1531.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { execSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine } from "./ft-load-line.ts"; // r1537 — 세션 기록 «로드 <카드> <판>» 1줄(턴 0)
import { say as extSay } from "./ft-load-line.ts"; // r1837 — 진단 1줄 출력 길 · 지역 이름 say(activeSeat 인자)와 겹쳐 alias
type Ctx = { isIdle(): boolean }; // ExtensionContext 중 필요한 칸만 — 시험이 ctx 를 흉내 낼 수 있게 좁힌다
const CMD = "/ft-reload-runtime";
const keyOf = (s: string) => s.replace(/[^A-Za-z0-9._#-]/g, "_");
const fail = (m: string) => extSay(`ERROR ft-reload-request: ${m}`);
const sh = (cmd: string): string => { try { return execSync(cmd, { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; } };
const seatName = (): string => process.env.FT_SEAT || sh('tmux display-message -p "#S"');
// ★root = «git 공용 루트»★ — pi pane 의 cwd 는 워크트리일 수 있다(ft-mbox-wake.ts 와 같은 식).
const gitRoot = (): string => { const d = sh("git rev-parse --path-format=absolute --git-common-dir"); return d ? path.dirname(d) : ""; };

export default function (pi: ExtensionAPI) {
  const root = process.env.FT_MBOX_ROOT || gitRoot() || process.cwd();
  const seat = seatName();
  const state = process.env.FT_MBOX_STATE_DIR ?? path.join(root, ".fable-team", "state");
  const wakeDir = path.join(state, "pi-wake");
  const req = path.join(wakeDir, `${keyOf(seat)}.reload`);
  const debounce = Number(process.env.FT_RELOAD_REQUEST_DEBOUNCE_MS ?? 300);
  let watcher: fs.FSWatcher | null = null, timer: ReturnType<typeof setTimeout> | null = null, startup: ReturnType<typeof setTimeout> | null = null;
  let pending = false, held = false, ctxNow: Ctx | null = null, announced = "", failed = "", denied = 0;

  // ★활성 = 이벤트마다 재확인★ (ft-mbox-wake.ts activeFlag 와 «같은 칸») — _master ∧ 같은 파일 행 agent=='pi' ∨ planner _desk
  const activeFlag = (): boolean => {
    const d = path.join(root, ".fable-team"); let names: string[] = [];
    try { names = fs.readdirSync(d).filter((f) => /^seats.*\.json$/.test(f)); } catch { return false; }
    for (const f of names) {
      try { const j = JSON.parse(fs.readFileSync(path.join(d, f), "utf-8")), r = j?.[seat];
        if ((r?.agent === "pi" && j._master === seat) || (f === "seats-planner.json" && j._desk === seat)) return true; } catch { continue; } // 깨진 파일 = 그 파일 거짓
    }
    return false;
  };
  const activeSeat = (say: boolean): boolean => { // 다른 pi 좌석(나노) 자동 리로드 0 — 좌석이 스스로 제 판본을 못 바꾼다
    const mine = !!seat && activeFlag();
    if (mine) { announced = ""; return true; }
    const why = `inactive seat=${seat || "?"} — 요청 파일 그대로 · reload 0`;
    if (say && announced !== why) { extSay(`ft-reload-request: ${why}`); announced = why; }
    return false;
  };
  const hasReq = (): boolean => fs.existsSync(req);
  // ★먼저 지운다★ — 지우기 실패면 reload 0 · 파일은 그대로 둔다(다음 사건이 다시 판정)
  function take(): boolean {
    try { fs.rmSync(req); failed = ""; return true; }
    catch (e) { const m = String(e); if (m !== failed) { failed = m; fail(`요청 파일 지우기 실패 ${req} — ${m}`); } return false; } // 같은 실패 반복 = ERROR 1줄
  }
  const idleOf = (c: Ctx | null): boolean => { try { return c ? c.isIdle() : false; } catch { return false; } }; // ctx 없음 = 모른다 → 미룬다
  const idle = (): boolean => idleOf(ctxNow);
  function fire(): void { // expandPromptTemplates = 명령으로 디스패치(모델 입력 0) · 핸들러가 ctx.reload() 1회로 끝난다
    try { void pi.sendUserMessage(CMD, { expandPromptTemplates: true }); } catch (e) { fail(`sendUserMessage 실패 — ${e}`); }
  }
  // ★r1540 = 지운 요청을 거절 때 되살린다★ — take() 가 먼저 지우므로 여기서 다시 써야 요청이 안 사라진다.
  function restore(): void {
    try { fs.mkdirSync(wakeDir, { recursive: true }); fs.writeFileSync(req, "reload rejected (busy) — restored by ft-reload-request\n"); }
    catch (e) { fail(`요청 복원 실패 ${req} — ${e}`); } // 복원 실패 = 줄 1개(no_silent_fallback)
  }
  function guard(ctx: Ctx | null): boolean { // reload 직전 재확인 — 일하는 중이면 reload 0 · 요청 복원 · 다음 정상 settled 1회
    if (ctx ? idleOf(ctx) : idle()) return true; // ★핸들러 ctx 가 있으면 그가 정본★ — ctxNow(마지막 settled) 는 한 턴 뒤처질 수 있다
    restore(); pending = true;
    if (denied !== 1) { denied = 1; extSay("ft-reload-request: reload 거절(일하는 중) — 요청 복원"); } // 같은 거절 반복 = 1줄
    return false;
  }
  function check(): void {
    if (held) return; // ★중단(aborted)으로 끝난 런 뒤 = 다음 정상 settled 까지 보류★ — 시작 타이머·fs.watch·settled 가 «모두» 이 표지를 본다(DA R1)
    if (!activeSeat(false)) return; // 비활성 좌석 = 파일 그대로 · reload 0
    if (!hasReq()) { pending = false; return; } // 요청 없음 = 표지 해제
    if (!idle()) { pending = true; return; } // 일하는 중 = 그 자리 0 · 다음 agent_settled 에서 1
    if (!take()) return; // 지우기 실패 = reload 0
    pending = false;
    fire();
  }
  const run = () => { try { check(); } catch (e) { fail(`처리 실패 — ${e}`); } };
  const schedule = () => { if (!timer) timer = setTimeout(() => { timer = null; run(); }, debounce); }; // 폴더 사건 3번 = 바운스 1회

  pi.registerCommand("ft-reload-runtime", { // 핸들러 = ctx.reload() 1회가 끝 · 그 뒤 코드는 옛 판본으로 돈다(docs/extensions.md:1512)
    description: "확장·스킬·프롬프트 판본을 다시 읽는다(요청 파일 ft-reload-request 가 부른다)",
    handler: async (_args, ctx) => { if (!guard(ctx as Ctx)) return; denied = 0; await ctx.reload(); return; },
  });
  pi.on("session_start", async (_event, ctx) => {
    appendLoadLine(pi, "r1531", "ft-reload-request.ts"); // r1537 — 실림 1줄
    ctxNow = ctx as Ctx; pending = false; held = false; // 새 세션 = 이전 런의 중단 상태를 물려받지 않는다
    try { fs.mkdirSync(wakeDir, { recursive: true }); } catch { /* 이미 있음 */ }
    try { watcher = fs.watch(wakeDir, (_e, fn) => { if (fn === path.basename(req)) schedule(); }); } // ★부모 폴더 감시★ — 파일 교체에도 유지
    catch (e) { fail(`watch 실패 ${wakeDir} — ${e}`); }
    activeSeat(true);
    run(); // 꺼져 있던 동안 생긴 요청 = 시작 1회
    // ★감시 기동 창★ — fs.watch 등록 직후 사건은 유실될 수 있다(FSEvents startup). 주기 0 · 시작 1회 재확인만.
    startup = setTimeout(() => { startup = null; run(); }, debounce + 250);
  });
  pi.on("agent_settled", async (event, ctx) => {
    ctxNow = ctx as Ctx;
    if ((event as { aborted?: boolean })?.aborted) { held = true; return; } // 중단(Escape)으로 끝난 런 = 다음 정상 settled 로 미룬다
    held = false;
    if (!pending && !hasReq()) return; // 할 일 없음 = 0
    run(); // 일하는 중 미뤄 둔 요청 = 여기서 1회
  });
  // 세션 교체(reload/resume)·종료 = 감시 해제. 안 닫으면 옛 인스턴스가 같은 요청 파일에 2중으로 리로드한다.
  pi.on("session_shutdown", async () => {
    if (watcher) watcher.close(); watcher = null;
    if (timer) clearTimeout(timer); if (startup) clearTimeout(startup); timer = startup = null;
  });
}
