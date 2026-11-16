// ft-tool-result-cap (r2083) — pi 좌석의 도구 결과 1건이 상한(기본 6,000바이트 ≈ 2k 토큰)을 넘으면 전문은 파일로, 창에는 머리·표시 줄·꼬리만.
//  · 상한 = env FT_TOOL_RESULT_CAP_BYTES(양의 정수 · 0 = 끔 · 숫자 아님 = 기본 + say 1줄) · 폴더 = FT_TOOL_RESULT_DIR || <OS 임시>/ft-tool-result
//  · 전문 = <폴더>/<pid>/<안전 글자 id>-<id sha256 앞 16>.txt 일반 파일 — `call/a`·`call_a`·`call/A` 가 서로 다른 이름(대소문자 무시 FS 포함)
//  · 그대로(반환 없음): 상한 이하 · text 아닌 조각 · 좌석 아님(FT_SEAT 없음 + tmux 세션 이름이 `#<숫자>` 로 안 끝남 · session_start 1회 판정)
//    · 상한 0 · 상한 < 표시 줄 최대 바이트 M(say 1줄) · 전문 쓰기 실패(say 1줄 · 하드 룰 20)
//  · 훅은 content 만 돌려준다(details·isError·usage 손 0) · 메시지 주입 0 · 등록 = tool_result · session_start
//  · 시험 = harness/tests/test_pi_tool_result_cap_r2083.sh · 설치 = ~/.pi/agent/extensions 복사 1개(master h)
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { say } from "./ft-load-line.ts"; // r1837 — 진단 1줄 출력 길(TUI = 파일 로그)

export const DEFAULT_CAP = 6000;
type Part = { type: string; text?: string };
const bytes = (s: string): number => Buffer.byteLength(s, "utf-8");

export const marker = (n: number, a: number, b: number, file: string): string =>
  `[결과 상한] 전문 ${n}바이트 중 머리 ${a} · 꼬리 ${b} 만 실음 · 전문 = ${file} · 더 볼 때는 줄 범위로 읽는다`;
// 표시 줄 최대 바이트 M = 머리·꼬리 자리에 N 을 넣은 글 + 줄바꿈 2
export const markerMax = (n: number, file: string): number => bytes(marker(n, n, n, file)) + 2;

// 이름 = `[A-Za-z0-9_-]` 밖 글자 → `_` + `-` + 원래 id(UTF-8) sha256 앞 16자리
export function fileName(id: string): string {
  const safe = id.replace(/[^A-Za-z0-9_-]/g, "_"), hash = createHash("sha256").update(Buffer.from(id, "utf-8")).digest("hex").slice(0, 16);
  return `${safe}-${hash}`;
}

const cont = (buf: Buffer, i: number): boolean => i > 0 && i < buf.length && (buf[i] & 0xc0) === 0x80;
// 머리 = 앞 max 바이트 안 · 글자 중간 0 · 창 안에 줄바꿈이 있으면 그 줄 끝에서 끊음(줄바꿈 제외)
function headOf(buf: Buffer, max: number): string {
  let end = Math.min(max, buf.length);
  while (cont(buf, end)) end--;
  if (end <= 0) return "";
  if (buf[end] !== 0x0a) { const nl = buf.lastIndexOf(0x0a, end - 1); if (nl >= 0) end = nl; }
  return buf.subarray(0, end).toString("utf-8");
}
// 꼬리 = 뒤 max 바이트 안 · 글자 중간 0 · 창 안에 줄바꿈이 있으면 다음 줄 처음부터
function tailOf(buf: Buffer, max: number): string {
  let start = Math.max(buf.length - max, 0);
  while (cont(buf, start)) start++;
  if (start >= buf.length) return "";
  if (start > 0 && buf[start - 1] !== 0x0a) { const nl = buf.indexOf(0x0a, start); if (nl >= 0 && nl < buf.length - 1) start = nl + 1; }
  return buf.subarray(start).toString("utf-8");
}

// 판정·자르기 1곳 — {} = 그대로 · {say} = 그대로 + 1줄 · {content} = 바꾼 결과(바이트 합 ≤ 상한)
export function capContent(content: Part[], id: string, cap: number, dir: string): { content?: Part[]; say?: string } {
  if (!(cap > 0) || !Array.isArray(content) || content.length === 0) return {};
  if (content.some((p) => p?.type !== "text" || typeof p.text !== "string")) return {};
  const full = content.map((p) => p.text as string).join(""), n = bytes(full);
  if (!(n > cap)) return {};
  const file = path.join(dir, String(process.pid), `${fileName(String(id ?? ""))}.txt`), m = markerMax(n, file);
  if (cap < m) return { say: `결과 상한 판정 불가 — 상한 ${cap}바이트 < 표시 줄 ${m}바이트` };
  try { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, full, "utf-8"); }
  catch (e) { return { say: `결과 상한 판정 불가 — 전문 쓰기 실패 ${file} ${String(e).split("\n")[0]}` }; }
  const buf = Buffer.from(full, "utf-8"), room = cap - m, half = Math.floor(room / 2);
  const head = headOf(buf, half), tail = tailOf(buf, room - half);
  return { content: [{ type: "text", text: `${head}\n${marker(n, bytes(head), bytes(tail), file)}\n${tail}` }] };
}

// 상한 값 — 없음·빈칸 = 기본 · 숫자(0 포함) = 그 값 · 그 밖 = 기본 + bad
export function capOf(raw: string | undefined): { cap: number; bad: boolean } {
  if (raw === undefined || raw === "") return { cap: DEFAULT_CAP, bad: false };
  return /^\d+$/.test(raw.trim()) ? { cap: Number(raw.trim()), bad: false } : { cap: DEFAULT_CAP, bad: true };
}

// 좌석 = FT_SEAT 있음 ∨ (tmux 안 ∧ 세션 이름이 `#<숫자>` 로 끝남) · tmux 조회 실패 = 좌석 아님 + say 1줄
export function isSeat(): boolean {
  if (process.env.FT_SEAT) return true;
  if (!process.env.TMUX) return false;
  try { return /#\d+$/.test(execFileSync("tmux", ["display-message", "-p", "#S"], { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim()); }
  catch (e) { say(`결과 상한 좌석 판정 불가 — tmux ${String(e).split("\n")[0]}`); return false; }
}

export default function (pi: ExtensionAPI): void {
  let seat = false, warned = false;
  pi.on("session_start", async () => { seat = isSeat(); });
  pi.on("tool_result", async (event) => {
    try {
      if (!seat) return;
      const raw = process.env.FT_TOOL_RESULT_CAP_BYTES, { cap, bad } = capOf(raw);
      if (bad && !warned) { warned = true; say(`결과 상한 값 '${raw}' 숫자 아님 — 기본 ${DEFAULT_CAP}바이트로 동작`); }
      const dir = process.env.FT_TOOL_RESULT_DIR || path.join(os.tmpdir(), "ft-tool-result");
      const r = capContent(event.content as Part[], event.toolCallId, cap, dir);
      if (r.say) say(r.say);
      return r.content ? { content: r.content } : undefined;
    } catch (e) { say(`결과 상한 판정 불가 — ${String(e).split("\n")[0]}`); return undefined; }
  });
}
