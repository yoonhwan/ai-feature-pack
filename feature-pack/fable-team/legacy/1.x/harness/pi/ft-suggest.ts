// ft-suggest (r1525) — 에디터 자동완성 보강: ft 도구 이름 · «!» h 실행 줄(/tmp/h<N>) · mbox recv 1줄 · 자주 쓰는 지시문 문구.
//  · 정본 = 이 파일(팩 harness/pi/) · 설치 = `~/.pi/agent/extensions/ft-suggest.ts` 사본 1개(pi /reload 1회)
//  · 키 입력 때만 읽는다 — 주기 실행 0(타이머·인터벌 0) · h 폴더 읽기 1회 ≤50ms · 파일 200개 상한(넘으면 최신 200) · 표시 5개
//  · «! » 목록 = 미실행 h 만(=.ran 있는 h 제외 · 최신 번호 우선) · 값 = `bash /tmp/h<N>` · 설명 = 2행 `# ft-hil-entry plan=` 파일 이름
//  · «mbox recv» 값 = `bash <공용 루트>/.fable-team/comm/mbox.sh recv <내 좌석>` · 좌석을 못 얻으면 이 줄 0
//  · env: FT_SUGGEST_H_DIR(h 폴더 기본 /tmp) · FT_SEAT(좌석 이름 · 비면 그 줄 0) · FT_MBOX_ROOT(공용 루트) · 시험 = harness/tests/test_pi_ft_suggest_r1525.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { execSync } from "node:child_process";
import { say } from "./ft-load-line.ts"; // r1837 — 진단 1줄 출력 길(TUI = 파일 로그)
import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const TOOLS = [
  "ft-acct-quota", "ft-budget", "ft-switch-plan", "ft-waste-check", "ft-lead-eval",
  "ft-successor-open", "ft-seat-retire", "ft-thresholds.sh", "ft-card-flow.sh",
  "ft-all-stop.sh", "ft-waste-monitor.sh", "cleanup-r1425.sh",
];
const PHRASES = [
  "[닫힌 발주] ①집합 동결 ②판정 기준 ③상한 ④종료 조건 ⑤다음 수",
  "[정리] 여유 N% (남은k/300k) · 다음 수:",
  "크론 삭제 N개",
  "판정: REJECT n건",
];
const H_CAP = 200; // 파일 상한 — 넘으면 최신 200개만 본다
const H_SHOW = 5; // 목록에 올리는 미실행 h 개수
type Item = { value: string; label: string; description?: string };

const sh = (cmd: string): string => {
  try { return execSync(cmd, { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim(); } catch { return ""; }
};
const gitRoot = (): string => {
  const d = sh("git rev-parse --path-format=absolute --git-common-dir");
  return d ? path.dirname(d) : "";
};

// h 폴더 = «실행되면 h<N>.ran 을 남기는» ft-hil 진입 파일 폴더. 읽기 실패 = 제안 0 + ERROR 1줄(가짜 목록 0).
export function hItems(dir: string, cap = H_CAP, show = H_SHOW): Item[] {
  let names: string[];
  try { names = fs.readdirSync(dir); } catch (e) { say(`ERROR ft-suggest: h 폴더 읽기 실패 ${dir} — ${e}`); return []; }
  const nums: { name: string; num: number }[] = [];
  for (const name of names) {
    const m = /^h(\d+)$/.exec(name);
    if (m) nums.push({ name, num: Number(m[1]) });
  }
  nums.sort((a, b) => b.num - a.num); // ft-hil.sh 가 1씩 올린다 = 큰 번호가 최신
  const items: Item[] = [];
  for (const { name, num } of nums.slice(0, cap)) {
    if (items.length >= show) break;
    if (fs.existsSync(path.join(dir, `${name}.ran`))) continue; // 이미 실행된 h = 제안 0
    let plan = "";
    try { plan = (fs.readFileSync(path.join(dir, name), "utf-8").split("\n")[1] ?? "").replace(/^# ft-hil-entry plan=/, "").trim(); } catch { continue; }
    const cmd = `bash ${path.join(dir, `h${num}`)}`;
    items.push({ value: cmd, label: cmd, description: plan ? path.basename(plan) : "" });
  }
  return items;
}

export default function (pi: ExtensionAPI) {
  const hDir = process.env.FT_SUGGEST_H_DIR ?? "/tmp";
  const root = process.env.FT_MBOX_ROOT || gitRoot() || process.cwd();
  const seatEnv = process.env.FT_SEAT;
  const seat = seatEnv !== undefined ? seatEnv.trim() : sh('tmux display-message -p "#S"').trim();
  const mboxSh = path.join(root, ".fable-team", "comm", "mbox.sh");
  const recvItem = (): Item | null => (seat
    ? { value: `bash ${mboxSh} recv ${seat}`, label: `bash ${mboxSh} recv ${seat}`, description: "내 쪽지함 1건 읽기(mbox recv)" }
    : null);

  pi.on("session_start", async (_e, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.addAutocompleteProvider((current: any) => ({
      triggerCharacters: ["f", "[", "!"],
      async getSuggestions(lines: string[], line: number, col: number, options: any) {
        const before = (lines[line] ?? "").slice(0, col);
        const bang = before.match(/(?:^|[ \t`])(!\s?[^\s]*)$/); // «!» · «! » · «! <한 토큰>» = h 실행 줄 목록
        if (bang) {
          const items = hItems(hDir);
          const recv = recvItem();
          if (recv) items.push(recv);
          if (items.length) return { prefix: bang[1], items };
        }
        const m = before.match(/(?:^|[ \t`])((?:ft-|cleanup-)[\w.-]*)$/);
        if (m) {
          const pre = m[1];
          const items = TOOLS.filter((t) => t.startsWith(pre)).map((t) => ({
            value: t,
            label: t,
            description: "ft 하네스 도구",
          }));
          if (items.length) return { prefix: pre, items };
        }
        const p = before.match(/(?:^|[ \t`])([^\s]{1,4}[ \t]?)$/); // 짧은 토큰 = 지시문 접두(PHRASES)
        if (p) {
          const items = PHRASES.filter((t) => t.startsWith(p[1].trim())).map((t) => ({ value: t, label: t, description: "자주 쓰는 지시문" }));
          if (items.length) return { prefix: p[1], items };
        }
        return current.getSuggestions(lines, line, col, options); // 매치 없음 = 기존 동작 그대로
      },
      applyCompletion(lines: string[], line: number, col: number, item: Item, prefix: string) {
        // «!» 목록은 bash 모드를 살린다 — «! bash /tmp/h<N>» 한 줄(하드 룰 13).
        if (prefix.startsWith("!") && item.value.startsWith("bash ")) {
          const head = `${prefix.split(/\s+/, 1)[0]} `;
          const cur = lines[line] ?? "";
          const cut = col - prefix.length;
          const out = [...lines];
          out[line] = `${cur.slice(0, cut)}${head}${item.value}${cur.slice(col)}`;
          return { lines: out, cursorLine: line, cursorCol: cut + head.length + item.value.length };
        }
        return current.applyCompletion(lines, line, col, item, prefix);
      },
      shouldTriggerFileCompletion(lines: string[], line: number, col: number) {
        return current.shouldTriggerFileCompletion?.(lines, line, col) ?? true;
      },
    }));
  });
}
