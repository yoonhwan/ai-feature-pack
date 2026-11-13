// ft-load-line (r1537) — 확장이 «이 세션에 실렸다» 를 세션 기록(jsonl)에 «로드 <카드> <판>» 1줄로 남긴다. 모델 턴 0 · 주기 0.
//  · 쓰는 길 = pi.appendEntry(customType, data) 하나 — 세션 jsonl 에 type:"custom" 레코드 1줄 · LLM 컨텍스트 미포함 · 턴 0
//    (근거 = pi docs/extensions.md:1681 pi.appendEntry · docs/session-format.md:169 · dist/core/extensions/types.d.ts:1295).
//    메시지 주입(send*)은 쓰지 않는다 — triggerTurn 없이라도 «컨텍스트에 들어가는» 메시지라 이 카드의 계약(턴 0 · 컨텍스트 0) 밖이다.
//  · 판 = 설치본 파일 내용 sha256 앞 8자 — 설치가 «cp 1개» 라 판 문자열이 따로 없고, 내용 지문이 «새 판이 실렸나» 를 그대로 답한다.
//    못 읽으면 «판 불명»(빈칸 0) · 설치 폴더 = 이 파일의 폴더(설치본이면 ~/.pi/agent/extensions) · env FT_PI_EXT_DIR 이 이긴다.
//  · 기록 실패 = say() 1줄(no_silent_fallback · r1837) · 확장 본 기능 등록은 계속 — 로드 줄이 확장을 죽이지 않는다.
//  · 시험 = harness/tests/test_pi_ext_load_line_r1537.sh
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

export const LOAD_TYPE = "ft-load-line";
export const UNKNOWN = "판 불명";
type AppendOnly = { appendEntry<T = unknown>(customType: string, data?: T): void };

// 이 파일이 놓인 폴더 = 설치 폴더(설치본 ~/.pi/agent/extensions · 시험 = 팩 harness/pi)
export function installDir(): string {
  try { return path.dirname(fileURLToPath(import.meta.url)); } catch { return ""; }
}

// 판 = 파일 내용 sha256 앞 8자 · 읽기 실패(없음·권한) = «판 불명»
export function versionOf(dir: string, file: string): string {
  if (!dir) return UNKNOWN;
  try { return createHash("sha256").update(fs.readFileSync(path.join(dir, file))).digest("hex").slice(0, 8); } catch { return UNKNOWN; }
}

// 세션 기록 1줄 — session_start 마다 1회(reload 도 session_start 1회 = 1줄) · throw 해도 확장은 계속
export function appendLoadLine(pi: AppendOnly, card: string, file: string): void {
  const version = versionOf(process.env.FT_PI_EXT_DIR || installDir(), file), line = `로드 ${card} ${version}`;
  try { pi.appendEntry(LOAD_TYPE, { card, version, file, line }); }
  catch (e) { say(`ERROR ft-load-line: 세션 기록 실패 ${line} (${file}) — ${e}`); }
}

// r1837 — 확장 진단 1줄의 출력 길. TUI(stderr=터미널)면 화면 위에 찍혀 입력창 경계선을 덮는다 → 파일 로그 1줄 · 터미널 0.
//  그 밖(시험·print·json·파이프) = 종전 console.error 1회. 로그 = FT_PI_EXT_LOG || ~/.pi/agent/logs/ft-ext.log · 좌석 = FT_SEAT || TMUX_PANE || ?
//  쓰기 실패 = 터미널 0 · 프로세스 첫 실패 1회만 tmpdir/ft-ext-<uid>.log · 둘 다 실패 = 버림. 시험 = tests/test_pi_ext_say_r1837.sh
let tmpTried = false;
export function say(line: string): void {
  if (process.stderr.isTTY !== true) { console.error(line); return; }
  const seat = process.env.FT_SEAT || process.env.TMUX_PANE || "?", row = `${new Date().toISOString()} ${seat} ${line}\n`;
  const file = process.env.FT_PI_EXT_LOG || path.join(os.homedir(), ".pi", "agent", "logs", "ft-ext.log");
  try { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.appendFileSync(file, row); return; } catch { /* 아래 tmpdir 1회 */ }
  if (tmpTried) return;
  tmpTried = true;
  try { fs.appendFileSync(path.join(os.tmpdir(), `ft-ext-${process.getuid?.() ?? "u"}.log`), row); } catch { /* 둘 다 실패 = 버림(S3) */ }
}

// ★이 파일도 «확장 파일» 이다★ — pi 는 설치 폴더의 .ts 를 «전부» 확장으로 로드하고 default factory 가 없으면
//  `Extension does not export a valid factory function` 로 그 파일을 실패로 남긴다(docs/extensions.md:46 · loader.js:534).
//  그래서 하는 일 0 의 factory 를 둔다 — 로드돼도 핸들러·기록·명령 0(기록은 확장 4개가 appendLoadLine 으로 낸다).
export default function (): void {}
