// ft2 pi 도구 이름 관문 (r2353) — API 이름 꼴(200자 · 글자 [A-Za-z0-9_-])을 어긴 tool_use 이름이 기록에 1건 남아도 그 좌석이 매 턴 400 으로 굳지 않는다.
//  · K1 판정 한 곳 = nameOk() — 1자 이상 ∧ 200자 이하 ∧ 글자 꼴. 도구 등록 여부는 안 본다(등록 안 된 정상 이름도 정상 · DA#45 M5).
//  · K2 저장 전 고침 = message_end 가 확정 메시지를 바꿔 돌려준다(role 같음) → 실행·toolResult 짝·저장이 모두 자리 이름.
//  · K3 보내기 전 고침 = context 가 요청 사본에서 같은 고침(기록 손 0) · 바꿀 것 0 이면 반환 없음(M5) · 원본 객체 손 0.
//  · 자리 이름 = invalid_tool_name 고정 — id·arguments·순서·text·다른 필드는 손 0 · 고칠 때마다 진단 1줄.
//  · 시험 = ft2/tests/test_pi_tool_name_guard_r2353.py · 설치 = ~/.pi/agent/extensions 복사 1개(master h · cp+cmp0)
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const CAP = 200;
export const PLACEHOLDER = "invalid_tool_name";
const SHAPE = /^[A-Za-z0-9_-]+$/;

/** K1 — 이름 꼴 판정 한 곳. 등록 여부·모델·좌석은 안 본다. */
export function nameOk(name: unknown): boolean {
  return typeof name === "string" && name.length > 0 && name.length <= CAP && SHAPE.test(name);
}

export interface Repair { message: Record<string, unknown>; names: string[] }

/** 메시지 1건의 어긴 이름을 자리 이름으로. 바꿀 것 0 = null(원본 그대로 돌려주지 않는다). */
export function repairMessage(message: unknown): Repair | null {
  if (!message || typeof message !== "object") return null;
  const msg = message as Record<string, unknown>;
  if (msg.role === "assistant" && Array.isArray(msg.content)) {
    const names: string[] = [];
    const content = msg.content.map((block: unknown) => {
      const b = (block ?? {}) as Record<string, unknown>;
      if (b.type !== "toolCall" || nameOk(b.name)) return block;
      names.push(String(b.name));
      return { ...b, name: PLACEHOLDER };
    });
    return names.length ? { message: { ...msg, content }, names } : null;
  }
  if (msg.role === "toolResult" && !nameOk(msg.toolName)) {
    return { message: { ...msg, toolName: PLACEHOLDER }, names: [String(msg.toolName)] };
  }
  return null;
}

/** 요청 사본 1벌 — 어긴 이름이 하나도 없으면 null(호출자는 반환하지 않는다). */
export function repairMessages(messages: unknown): { messages: unknown[]; names: string[] } | null {
  if (!Array.isArray(messages)) return null;
  const names: string[] = [];
  const out = messages.map((m) => {
    const r = repairMessage(m);
    if (!r) return m;
    names.push(...r.names);
    return r.message;
  });
  return names.length ? { messages: out, names } : null;
}

/** 진단 1줄 — TTY 면 파일(FT_GUARD_LOG || ~/.pi/agent/logs/ft-ext.log), 아니면 stderr. 기록 실패 = 버림(요청은 그대로 간다). */
export function say1(line: string): void {
  const row = `${new Date().toISOString()} ${process.env.FT_SEAT ?? "?"} ${line}`;
  if (process.stderr.isTTY !== true) { console.error(row); return; }
  const file = process.env.FT_GUARD_LOG ?? path.join(os.homedir(), ".pi", "agent", "logs", "ft-ext.log");
  try { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.appendFileSync(file, `${row}\n`); } catch { /* 버림 */ }
}

/** 한 줄에 원래 이름 앞부분만 — 그 이름이 313자여도 줄은 1줄이다. */
export function note(hook: string, names: string[]): string {
  const head = names[0].replace(/\s+/g, " ").slice(0, 60);
  return `[도구 이름] ${hook} 이름 꼴 어김 ${names.length}건 → ${PLACEHOLDER} · 원래 «${head}»(${names[0].length}자)`;
}

export default function (pi: ExtensionAPI) {
  pi.on("message_end", (event: { message?: unknown }) => {
    const fixed = repairMessage(event?.message);
    if (!fixed) return;
    say1(note("message_end", fixed.names));
    return { message: fixed.message };
  });
  pi.on("context", (event: { messages?: unknown }) => {
    const fixed = repairMessages(event?.messages);
    if (!fixed) return;
    say1(note("context", fixed.names));
    return { messages: fixed.messages };
  });
}
