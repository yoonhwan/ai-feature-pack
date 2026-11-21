// ft-nano-repo-grep-guard (r2379 · r2413 find 갈래) — pi 좌석이 «리포 루트 재귀 grep»(나노) 과 «리포 루트 find»(좌석 전부)를 bash 로 돌리지 못하게 tool_call 문지기에서 거절하고 갈 길(ci·git ls-files·범위 경로)을 알려 준다.
//  · 거절 = 나노 꼴 좌석 ∧ 명령 토막 하나라도 (재귀 grep ∧ 루트 대상) → {block:true, reason} · 파이프 뒤 토막도 같은 판정
//  · find 거절(r2413) = FT_SEAT_NAME 있는 좌석 전부 ∧ 토막 첫 낱말 find ∧ (루트 대상 ∧ 깊이 제한 없음(-maxdepth N ≤ 3) ∧ 가지치기 없음(-prune)) · 폴더를 좁혔거나 깊이·가지치기를 준 find 는 그대로
//  · 통과 = 나노 아님·좌석 미상·bash 밖 도구(pi grep·read·ci)·재귀 아님·기준 폴더 아래 하위 폴더 대상·rg(손 0) · 판정 불가(git rc≠0·7초·나누기 실패·풀 수 없는 cd) = 통과 + NOTE 1줄(사유별 1회 · 하드 룰 20) — 확장 오류로 도구 호출을 막지 않는다
//  · 거절마다 <루트>/.fable-team/state/nano-grep-block.log 1줄(같은 좌석·같은 명령 1회 · 0644 · 하드 룰 19) · 쓰기 실패 = ERROR 1줄 · 설치 = ~/.pi/agent/extensions 복사 1개(master h) · env = FT_SEAT_NAME · FT_LIVE_ROOT · 시험 = tests/test_nano_repo_grep_guard_r2379.sh · tests/test_nano_repo_find_guard_r2413.sh
import * as fs from "node:fs";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendLoadLine, say } from "./ft-load-line.ts"; // r1537 로드 줄 · r1837 진단 1줄 출력 길
import { seatOf, realish } from "./ft-live-write-guard.ts"; // r1672 좌석·realpath 판정 재사용(그 파일 손 0)

const NANO = /(^|[-_/.])nano([-_#./]|$)/, GREPS = /^(grep|egrep|fgrep)$/, VALUED = new Set(["--include", "--exclude", "--exclude-dir"]);
const FINDS = /^find$/, FIND_PRE = new Set(["-H", "-L", "-P", "-E", "-X", "-d", "-s", "-x"]);
const SEPC = new Set(["&", "|", ";", "\n", "(", ")", "`"]), OPENS = new Set(["(", "$(", "`"]);
export const WHY = '[ft-nano-repo-grep-guard] 리포 루트 재귀 grep 금지(하드 룰 16) — ci search "<말>" <카드 §구현 범위 폴더> --max 5 · 심볼 = ci sym <이름> · 참조 = ci refs "<파일>#<이름>" · 파일 구조 = ci outline <파일>(code-intel) · 또는 grep 대상을 그 폴더로 좁힘';
export const WHY_FIND = "[ft-nano-repo-grep-guard] 리포 루트 find 금지(.worktrees·사본까지 훑음) — 추적 파일 = git ls-files '<패턴>' · 코드 = ci search · 그 밖 = 폴더를 좁힌 find <폴더> 또는 find . -maxdepth 3";
type Seg = { toks: string[]; sep: string };
type Verdict = { block: boolean; bad: string; root: string; target: string };
const NO: Verdict = { block: false, bad: "", root: "", target: "" };
const QUOTED_SPACE_BREAKS = false; // 따옴표 안 공백 = 낱말 안(경계 아님) · 변이 M18 이 뒤집는다
// 명령 나누기 — 낱말은 훑기 안에서 만든다(따옴표·역슬래시 안 공백 = 낱말 하나) · 나누기 = 따옴표 밖의 ; && || | & 줄바꿈 ( ) $( 백틱 · 리다이렉트 안 &(&> · >& · 2>&1)는 나누기 아님
export function splitCmd(cmd: string): { segs: Seg[]; bad: string } {
  const segs: Seg[] = []; let toks: string[] = [], cur = "", inTok = false, q = "", i = 0;
  const add = (s: string) => { cur += s; inTok = true; };
  const push = () => { if (inTok) toks.push(cur); cur = ""; inTok = false; };
  const end = (sep: string) => { push(); segs.push({ toks, sep }); toks = []; };
  while (i < cmd.length) {
    const c = cmd[i], nx = cmd[i + 1] ?? "";
    if (q) { if (c === "\\" && q === '"') { add(nx); i += 2; continue; } if (c === q) { q = ""; i++; continue; } if (c === " " && QUOTED_SPACE_BREAKS) { push(); i++; continue; } add(c); i++; continue; }
    if (c === "'" || c === '"') { q = c; inTok = true; i++; continue; }
    if (c === "\\") { if (nx) add(nx); i += 2; continue; }
    if (c === " " || c === "\t") { push(); i++; continue; }
    if (c === "&" && nx === ">") { add("&>"); i += 2; continue; }
    if (c === ">" && nx === "&") { add(">&"); i += 2; continue; }
    if (c === "&" && nx === "&") { end("&&"); i += 2; continue; }
    if (c === "|" && nx === "|") { end("||"); i += 2; continue; }
    if (c === "$" && nx === "(") { end("$("); i += 2; continue; }
    if (SEPC.has(c)) { end(c); i++; continue; }
    add(c); i++;
  }
  end("");
  return { segs, bad: q ? `따옴표 안 닫힘(${q})` : "" };
}
// 리다이렉트 낱말 — fd 복제(2>&1 · >&2) · 대상 붙여 씀(2>/dev/null) · 대상이 다음 낱말(>) · 대상 없음 = pure
export function redir(t: string): "fd" | "attached" | "pure" | "" {
  if (/^\d*>&\d+$/.test(t)) return "fd";
  const m = /^(?:\d+)?(&>>?|>>?|<|&>)(.*)$/.exec(t);
  if (!m) return "";
  return m[2] ? "attached" : "pure";
}
// 앞 낱말 건너뛰기 — env 대입(A=b) · timeout N · nice [-n N] · command · env
function headIndex(toks: string[]): number {
  for (let k = 0; k < toks.length; ) {
    const t = toks[k];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t)) { k++; continue; }
    if (t === "timeout" || t === "gtimeout") { k += 2; continue; }
    if (t === "nice") { k += toks[k + 1] === "-n" ? 3 : 1; continue; }
    if (t === "command" || t === "env") { k++; continue; }
    return k;
  }
  return -1;
}

// grep 인자 — 재귀(-r·-R·--recursive·-d recurse) · 경로 낱말(패턴 1개 제외 · 값 받는 옵션의 값 제외 · 리다이렉트 제외)
export function parseArgs(toks: string[], i0: number): { rec: boolean; paths: string[]; bad: string } {
  let rec = false, ef = false, i = i0; const pos: string[] = [];
  const take = (): string => { const v = toks[i] ?? ""; i++; return v; }; // 값 받는 옵션의 값 = 다음 낱말
  while (i < toks.length) {
    const t = toks[i], r = redir(t);
    i++;
    if (r === "fd" || r === "attached") continue;
    if (r === "pure") { if (!toks[i]) return { rec, paths: [], bad: `대상 없는 리다이렉트(${t})` }; i++; continue; }
    if (t.startsWith("--")) {
      const eq = t.indexOf("="), name = eq < 0 ? t : t.slice(0, eq), val = eq < 0 ? "" : t.slice(eq + 1);
      if (name === "--recursive" || name === "--dereference-recursive") { rec = true; continue; }
      if (name === "--directories") { if ((val || take()) === "recurse") rec = true; continue; }
      if (VALUED.has(name) && !val) take();
      continue;
    }
    if (t.startsWith("-") && t.length > 1) {
      for (let j = 1; j < t.length; j++) {
        const c = t[j];
        if (c === "r" || c === "R") { rec = true; continue; }
        if (!"efmABCd".includes(c)) continue;
        let val = t.slice(j + 1);
        if (val.startsWith("=")) val = val.slice(1);
        if (!val) val = take();
        if (c === "e" || c === "f") ef = true;
        if (c === "d" && val === "recurse") rec = true;
        break;
      }
      continue;
    }
    pos.push(t);
  }
  return { rec, paths: ef ? pos : pos.slice(1), bad: "" };
}

// cd 따라가기 — 인자 없음 = $HOME · `cd -`·$HOME·$PWD 밖 변수 = 판정 불가
function cdStep(toks: string[], base: string): { base?: string; bad?: string } {
  const a1 = toks[1] ?? "";
  if (!a1) return { base: realish(process.env.HOME ?? "") || base };
  if (a1 === "-") return { bad: "풀 수 없는 cd(cd -)" };
  for (const m of a1.matchAll(/\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/g)) if (m[1] !== "HOME" && m[1] !== "PWD") return { bad: `풀 수 없는 cd($${m[1]})` };
  const p = a1.startsWith("/") || a1.startsWith("~") || a1.startsWith("$") ? realish(a1) : realish(path.join(base, a1));
  return p ? { base: p } : { bad: "풀 수 없는 cd(빈 값)" };
}
// 경로 낱말 → 절대 경로(상대는 기준 폴더에 붙임 · ~/$HOME/$PWD/심링크/.. 풀이)
const abs = (w: string, base: string): string => (w.startsWith("/") || w.startsWith("~") || w.startsWith("$") ? realish(w) : realish(path.join(base, w)));
// 루트 대상 = 경로 낱말 0(grep -r 기본 = 기준 폴더) 또는 하나라도 루트 집합과 같음
function atRoot(paths: string[], base: string, roots: string[]): boolean {
  const ps = paths.length ? paths : ["."];                   // 경로 낱말 0 = grep -r 기본 = 기준 폴더
  return ps.some((w) => roots.includes(abs(w, base)));
}

// git 두 조회 — 각 7초 상한 · rc 확인(실패를 조용히 cwd 로 돌리지 않는다)
function gitOut(base: string, args: string[]): { out: string; bad: string } {
  try {
    return { out: execFileSync("git", ["-C", base, ...args], { encoding: "utf-8", timeout: 7000, stdio: ["ignore", "pipe", "ignore"] }).trim(), bad: "" };
  } catch (e) {
    const er = e as { signal?: string };
    return { out: "", bad: `git ${args.join(" ")} ${er?.signal ? "7초 넘김" : "rc≠0"}` };
  }
}

// 루트 집합 = 공용 루트(FT_LIVE_ROOT · 없으면 git-common-dir 의 부모) ∪ 워크트리 맨 위(show-toplevel) ∪ $HOME
export function rootsOf(base: string): { roots: string[]; bad: string } {
  const roots: string[] = [];
  if (process.env.FT_LIVE_ROOT) roots.push(realish(process.env.FT_LIVE_ROOT));
  else {
    const g = gitOut(base, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
    if (g.bad || !g.out) return { roots, bad: g.bad || "git rev-parse --git-common-dir 빈 출력" };
    roots.push(path.dirname(g.out));
  }
  const t = gitOut(base, ["rev-parse", "--show-toplevel"]);
  if (t.bad || !t.out) return { roots, bad: t.bad || "git rev-parse --show-toplevel 빈 출력" };
  roots.push(t.out);
  if (process.env.HOME) roots.push(realish(process.env.HOME));
  return { roots, bad: "" };
}

// 한 명령 판정 — 토막마다 기준 폴더를 따라가며 재귀 grep 을 모으고, 루트 집합은 재귀 grep 이 있을 때만 부른다
export function judge(cmd: string, base0: string): Verdict {
  const { segs, bad } = splitCmd(cmd);
  if (bad) return { ...NO, bad };
  let base = base0; const stack: string[] = [], found: { paths: string[]; base: string }[] = [], memo = new Map<string, ReturnType<typeof rootsOf>>();
  for (const s of segs) {
    if (OPENS.has(s.sep)) stack.push(base);
    if ((s.toks[0] ?? "") === "cd") {
      if (s.toks.length === 1 && (s.sep === "$(" || s.sep === "`")) return { ...NO, bad: "풀 수 없는 cd($(…))" };
      const r = cdStep(s.toks, base);
      if (r.bad) return { ...NO, bad: r.bad };
      base = r.base ?? base;
    } else {
      const k = headIndex(s.toks);
      if (k >= 0 && GREPS.test(path.basename(s.toks[k]))) {
        const a = parseArgs(s.toks, k + 1);
        if (a.bad) return { ...NO, bad: a.bad };
        if (a.rec) found.push({ paths: a.paths, base });
      }
    }
    if (s.sep === ")") base = stack.pop() ?? base0;
  }
  for (const f of found) {
    if (!memo.has(f.base)) memo.set(f.base, rootsOf(f.base));
    const rr = memo.get(f.base) as ReturnType<typeof rootsOf>;
    if (rr.bad) return { ...NO, bad: rr.bad };
    if (atRoot(f.paths, f.base, rr.roots)) return { block: true, bad: "", root: rr.roots[0] ?? f.base, target: f.paths.length ? f.paths.join(" ") : f.base };
  }
  return NO;
}

// find 인자 — 앞 옵션(-H·-L·-P·-E·-X·-d·-s·-x) 건너뛰고 경로 낱말(첫 식 낱말 «-»·«(»·«!» 앞까지 · -f <경로> = 경로) · 깊이 제한(-maxdepth N) · 가지치기(-prune)
export function parseFind(toks: string[], i0: number): { paths: string[]; depth: number; prune: boolean; bad: string } {
  const paths: string[] = []; let i = i0, depth = -1, prune = false;
  while (i < toks.length) {
    const t = toks[i];
    if (FIND_PRE.has(t)) { i++; continue; }
    if (t !== "-f") break;
    const w = toks[i + 1] ?? ""; if (!w) return { paths, depth, prune, bad: "대상 없는 -f" };
    paths.push(w); i += 2;
  }
  for (; i < toks.length; i++) {
    const t = toks[i];
    if (t.startsWith("-") || t === "(" || t === "!") break;
    paths.push(t);
  }
  for (let j = i; j < toks.length; j++) {
    if (toks[j] === "-prune") prune = true;
    if (toks[j] === "-maxdepth") { const n = Number(toks[j + 1]); depth = Number.isFinite(n) ? n : -1; j++; }
  }
  const v = paths.find((w) => /\$|`/.test(w)); // 변수·명령 치환 경로 = 판정 불가(알려진 한계 2)
  return { paths, depth, prune, bad: v ? `풀 수 없는 find 경로(${v})` : "" };
}
// find 전용 루트 대상 — 경로 낱말을 base 기준 절대 경로로 풀어 루트와 같거나 «루트의 조상» 이면 참(기존 atRoot = grep 완전 일치 전용 · 손 0)
function atFindRoot(paths: string[], base: string, roots: string[]): boolean {
  const ps = paths.length > 0 ? paths : ["."];
  return ps.some((w) => {
    const p = abs(w, base);
    if (!p) return false;
    const pre = p.endsWith(path.sep) ? p : p + path.sep;
    return roots.some((r) => r === p || r.startsWith(pre));
  });
}
// find 한 명령 판정(K1~K3) — 토막마다 기준 폴더를 따라가며 루트 대상 find 를 모으고, 루트 집합은 루트 대상 find 가 있을 때만 부른다
export function judgeFind(cmd: string, base0: string): Verdict {
  const { segs, bad } = splitCmd(cmd);
  if (bad) return { ...NO, bad };
  let base = base0; const stack: string[] = [], found: { paths: string[]; base: string }[] = [], memo = new Map<string, ReturnType<typeof rootsOf>>();
  for (const s of segs) {
    if (OPENS.has(s.sep)) stack.push(base);
    if ((s.toks[0] ?? "") === "cd") {
      if (s.toks.length === 1 && (s.sep === "$(" || s.sep === "`")) return { ...NO, bad: "풀 수 없는 cd($(…))" };
      const r = cdStep(s.toks, base);
      if (r.bad) return { ...NO, bad: r.bad };
      base = r.base ?? base;
    } else {
      const k = headIndex(s.toks);
      if (k >= 0 && FINDS.test(path.basename(s.toks[k]))) {
        const a = parseFind(s.toks, k + 1);
        if (a.bad) return { ...NO, bad: a.bad };
        if (!a.prune && !(a.depth >= 0 && a.depth <= 3)) found.push({ paths: a.paths, base });
      }
    }
    if (s.sep === ")") base = stack.pop() ?? base0;
  }
  for (const f of found) {
    if (!memo.has(f.base)) memo.set(f.base, rootsOf(f.base));
    const rr = memo.get(f.base) as ReturnType<typeof rootsOf>;
    if (rr.bad) return { ...NO, bad: rr.bad };
    if (atFindRoot(f.paths, f.base, rr.roots)) return { block: true, bad: "", root: rr.roots[0] ?? f.base, target: f.paths.length ? f.paths.join(" ") : f.base };
  }
  return NO;
}

// 거절 기록 1줄 — 같은 좌석·같은 명령은 1회만 · 쓰기 실패 = ERROR 1줄(거절은 그대로)
export function logBlock(root: string, seat: string, cmd: string): void {
  const f = path.join(root, ".fable-team", "state", "nano-grep-block.log");
  try {
    const prev = fs.existsSync(f) ? fs.readFileSync(f, "utf-8") : "";
    if (prev.split("\n").some((l) => l.includes(` ${seat} `) && l.trimEnd().endsWith(` ${cmd}`))) return;
    fs.mkdirSync(path.dirname(f), { recursive: true }); fs.appendFileSync(f, `${new Date().toISOString()} ${seat} ${cmd}\n`, { mode: 0o644 });
  } catch (e) { say(`ERROR ft-nano-repo-grep-guard: 감지 로그 실패 ${f} — ${e}`); }
}

export default function (pi: ExtensionAPI) {
  const noted = new Set<string>();
  const note = (bad: string) => { if (!noted.has(bad)) { noted.add(bad); say(`NOTE ft-nano-repo-grep-guard: 판정 불가 ${bad}`); } }; // 판정 불가 = NOTE 1줄(사유별 1회)
  pi.on("session_start", async () => { appendLoadLine(pi, "r2379", "ft-nano-repo-grep-guard.ts"); });
  pi.on("tool_call", async (event) => {
    const seat = seatOf(), findSeat = process.env.FT_SEAT_NAME ?? "";        // find 갈래 대상 = FT_SEAT_NAME 만(K1 · r1672 seatOf 의 FT_SEAT fallback 안 씀)
    if (!seat) return;                                                         // 좌석 env 없음 = 판정 0(K1·K3)
    if (String(event.toolName ?? "") !== "bash") return;                       // bash 밖(pi grep·read·ci) = 통과
    const cmd = String((event.input as Record<string, unknown> | undefined)?.command ?? "");
    if (!cmd) return;
    const isNano = NANO.test(seat);                                            // grep 갈래 대상 = 나노만(r2379 그대로)
    if (isNano) {
      let v: Verdict;
      try { v = judge(cmd, process.cwd()); } catch (e) { say(`ERROR ft-nano-repo-grep-guard: 판정 실패 — ${e}`); return; }
      if (v.bad) { note(v.bad); return; }
      if (v.block) { logBlock(v.root, seat, cmd.slice(0, 120)); return { block: true, reason: `${WHY} · 대상 ${v.target}` }; }
    }
    if (findSeat) {                                                            // find 갈래 = FT_SEAT_NAME 있는 좌석 전부(K1)
      let f: Verdict;
      try { f = judgeFind(cmd, process.cwd()); } catch (e) { say(`ERROR ft-nano-repo-grep-guard: find 판정 실패 — ${e}`); return; }
      if (f.bad) { note(f.bad); return; }
      if (f.block) { logBlock(f.root, findSeat, cmd.slice(0, 120)); return { block: true, reason: `${WHY_FIND} · 대상 ${f.target}` }; }
    }
  });
}
