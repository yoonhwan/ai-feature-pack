// ft2 pi 좌석 어댑터 (r1610 · 조건 14 «Pi 실행» 첫 칸) — pi 확장 도구 4개가 코어 cli 동사를 그대로 부른다.
// ① 도구 1개 = 동사 1개 = `python3 <ft2>/core/cli.py <동사> --이름 값 …` 1회. 그 밖의 호출 0.
// ② 도구 결과 = cli stdout 의 JSON 1줄 «그대로» · rc≠0 = isError(성공으로 감싸지 않는다).
// ③ 필수 인자 빠짐 = cli 를 부르기 «전» 에 오류(쓰기 0 · 루트 파일 변화 0).
// ④ 상주 프로세스·주기 폴링·이벤트 훅 0 — 이 파일은 registerTool 만 한다(타이머·이벤트 훅·상주 자식 없음).
// ⑤ 외부 호출 1회 상한 7초(하드 룰 12) — 넘으면 SIGKILL 로 끝낸다(SIGTERM 무시 자식도 7초에 반환).
import { execFile } from "node:child_process";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

export const TIMEOUT_MS = 7000;
export interface VerbSpec { verb: string; required: string[]; optional: string[] }
/** 도구 1개 = 동사 1개. required 가 비면 쓰기를 시작하지 않는다(ⓒ). */
export const VERBS: Record<string, VerbSpec> = {
  ft2_claim: { verb: "claim", required: ["work", "holder"], optional: ["rotation", "confirm_by"] },
  ft2_start: { verb: "start", required: ["work", "holder", "gen"], optional: [] },
  ft2_effect: { verb: "effect", required: ["work", "holder", "gen", "effect"], optional: [] },
  ft2_result: { verb: "result", required: ["work", "holder", "gen"], optional: ["word"] },
};
const STR = { type: "string" } as const;
const WHERE = { root: STR, team: STR };
export const PARAMETERS: Record<string, unknown> = {
  ft2_claim: { type: "object", additionalProperties: false, required: ["work", "holder"],
    properties: { ...WHERE, work: STR, holder: STR, rotation: { type: "boolean" }, confirm_by: STR } },
  ft2_start: { type: "object", additionalProperties: false, required: ["work", "holder", "gen"],
    properties: { ...WHERE, work: STR, holder: STR, gen: { type: "integer" } } },
  ft2_effect: { type: "object", additionalProperties: false, required: ["work", "holder", "gen", "effect"],
    properties: { ...WHERE, work: STR, holder: STR, gen: { type: "integer" }, effect: STR } },
  ft2_result: { type: "object", additionalProperties: false, required: ["work", "holder", "gen"],
    properties: { ...WHERE, work: STR, holder: STR, gen: { type: "integer" }, word: STR } },
};
const LABELS: Record<string, string> = {
  ft2_claim: "ft2 claim — 실행권 받기", ft2_start: "ft2 start — 착수 기록",
  ft2_effect: "ft2 effect — 효과 의도 내구화", ft2_result: "ft2 result — 결과 확정",
};

/** cli 경로 — FT2_CLI(설치본·시험) > 어댑터 옆 ../../core/cli.py > <루트>/feature-pack/fable-team/ft2/core/cli.py. */
export function cliPath(root: string): string {
  if (process.env.FT2_CLI) return process.env.FT2_CLI;
  try { return fileURLToPath(new URL("../../core/cli.py", import.meta.url)); } catch { /* jiti = 아래 폴백 */ }
  return path.join(root, "feature-pack", "fable-team", "ft2", "core", "cli.py");
}
const python = (): string => process.env.FT2_PYTHON || "python3";
/** 빠진 필수 인자 이름들(쉼표) — 빈 문자열·null 도 «빠짐» 이다. */
const missing = (spec: VerbSpec, params: any): string =>
  spec.required.filter((n) => params?.[n] === undefined || params?.[n] === null || params?.[n] === "").join(",");
/** 도구 인자 → cli argv. 토큰 1개 = 인자 1개(쉘 없음) · true/false 는 1/0. */
export function argv(spec: VerbSpec, params: any, root: string, team: string): string[] {
  const out = [cliPath(root), spec.verb, "--root", root, "--team", team];
  for (const name of spec.required.concat(spec.optional)) {
    const value = params[name];
    if (value === undefined || value === null || value === "") continue;
    out.push("--" + name, typeof value === "boolean" ? (value ? "1" : "0") : String(value));
  }
  return out;
}
export interface CliRun { rc: number; stdout: string; stderr: string; timedOut: boolean; error: string }
/** cli 1회 실행 — 상주 0 · 상한 7초를 넘으면 SIGKILL 로 «반드시» 끝낸다(SIGTERM 무시 자식도 7초에 반환 · DA R1). */
export function runCli(list: string[], signal?: AbortSignal): Promise<CliRun> {
  return new Promise((resolve) => {
    execFile(python(), list, { timeout: TIMEOUT_MS, killSignal: "SIGKILL", encoding: "utf8", maxBuffer: 1 << 20, signal }, (error: any, stdout, stderr) => {
      const timedOut = !!error && error.name !== "AbortError" && error.signal === "SIGKILL" && typeof error.code !== "number";
      resolve({ rc: typeof error?.code === "number" ? error.code : error ? 124 : 0,
        stdout: String(stdout ?? ""), stderr: String(stderr ?? ""), timedOut,
        error: error ? String(error.message ?? error).split("\n")[0].trim() : "" });  // ENOENT 같은 실행 실패의 진단 1줄
    });
  });
}
const detailsOf = (verb: string, run: CliRun, command: string[]) => ({ verb, rc: run.rc, timedOut: run.timedOut, command, error: run.error });
const fail = (text: string, verb = "") => ({ content: [{ type: "text" as const, text }],
  details: { verb, rc: 0, timedOut: false, command: [] as string[], error: "" }, isError: true });
function tool(name: string, spec: VerbSpec, description: string) {
  return {
    name, label: LABELS[name], description, promptSnippet: description, parameters: PARAMETERS[name],
    async execute(_toolCallId: string, params: any, signal?: AbortSignal, _onUpdate?: any, ctx?: any) {
      const bad = missing(spec, params);
      if (bad) return fail(`인자 빠짐: ${bad} — cli 호출 0 · 쓰기 0`, spec.verb);
      const root = String(params?.root ?? ctx?.cwd ?? process.cwd());
      const team = String(params?.team ?? process.env.FT2_TEAM ?? "");
      if (!team) return fail("팀 이름 없음 — 인자 team 또는 FT2_TEAM 을 정한다 · cli 호출 0 · 쓰기 0", spec.verb);
      const command = argv(spec, params, root, team);
      const run = await runCli(command, signal);
      const text = run.stdout.trim() || run.stderr.trim() || run.error || "(출력 없음)";
      if (run.rc !== 0) return { content: [{ type: "text" as const, text }], details: detailsOf(spec.verb, run, command), isError: true };
      return { content: [{ type: "text" as const, text }], details: detailsOf(spec.verb, run, command) };
    },
  };
}
export default function ft2Seat(pi: any): void {
  pi.registerTool(tool("ft2_claim", VERBS.ft2_claim, "ft2 작업의 실행권(세대)을 받는다 — 코어 claim 1회 · 결과는 cli JSON 그대로."));
  pi.registerTool(tool("ft2_start", VERBS.ft2_start, "ft2 작업 착수를 기록한다 — 코어 start 1회 · 결과는 cli JSON 그대로."));
  pi.registerTool(tool("ft2_effect", VERBS.ft2_effect, "ft2 효과 의도를 먼저 내구화한다 — 코어 effect 1회 · 결과는 cli JSON 그대로."));
  pi.registerTool(tool("ft2_result", VERBS.ft2_result, "ft2 작업 결과를 확정한다 — 코어 result 1회 · 결과는 cli JSON 그대로."));
}
