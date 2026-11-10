#!/usr/bin/env bash
# test_hil_pending_team_r1538.sh — r1538: `ft-hil.sh --pending --team <팀>` = h 의 «그 팀» 만 센다.
#  팀 읽기 = 계획 머리 `# ft-hil-request seat=<좌석…>` ∪ `<h>.notify` 의 `seat=` 좌석 이름(`byz-<팀>-…` · `aifp-<팀>-…`)
#  사례: ⓐ --team ops · ops h 1 + cfo h 1 → ops 줄 1  ⓑ 요청 머리 없음 + notify seat=byz-cfo-… → cfo 로 셈(ops 0)
#        ⓒ 요청 머리·notify 둘 다 없음 → 모든 팀에 셈 + stderr «팀 표식 없음 h<N> — 전 팀에 셈(기존 동작)» 1줄
#        ⓓ 요청 좌석 3개가 다른 팀 → 그 셋 모두에 셈  ⓔ --team 없는 호출 = base(고정 sha) 와 바이트 같음 · stderr 0
#        ⓕ aifp-<팀>-… → <팀> · 그 밖 꼴 좌석 = 표식 없음과 같게(ⓒ)  ⓖ ft-idle-nudge: 다른 팀 h 1 = 턴 1 · 그 팀 h 1 = 턴 0
#        ⓗ R1 반례: 계획 «공백 경로» = 경로는 줄 전체 · 좌석 칸만 split(공백 경로 요청 팀 유지 · notify 다른 팀도 셈)
#        ⓘ R1 반례: 공백 경로 + notify 없음 → 표식 없음으로 새지 않는다(전 팀 오분류 0)
#  변이: M1 --team 거르기 끔 → ⓐ FAIL(2줄) · M2 표식 없는 h 를 빼버림 → ⓒ FAIL(0줄) · M3 ft-idle-nudge 가 --team 을 안 넘김 → ⓖ FAIL(턴 0)
#        M4 경로를 공백으로 자름(R1 이전 꼴) → ⓗ·ⓘ FAIL(요청 팀 유실 · 전 팀 오분류)
#  격리: 임시 HIL_DIR 만(실 /tmp/h* 0 · 실 우편함 0) · FT_HIL_NOW 로 분 경계 고정 · sleep 0 · 외부 호출 0(env -i).
# 새 파일 mode 100644 — `bash <이 파일>` 로 부른다. 자기 호출 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HARNESS="$(cd -- "$HERE/.." && pwd)"
SRC="${R1538_BIN:-$HARNESS/kit/fable-team/bin}"
EXT="$HARNESS/pi/ft-idle-nudge.ts"
PACK="$(cd -- "$HARNESS/../../.." && pwd)"
fail=0; t0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (기대 '$3' 실제 '$2')"; fi; }
step() { echo "== $1 ($((SECONDS - t0))s)"; }

command -v python3 >/dev/null 2>&1 || { echo "FAIL python3 없음"; exit 1; }
[ -f "$SRC/ft-hil.sh" ] && [ -f "$SRC/ft_hil_pending.py" ] && [ -f "$SRC/ft_hil_team.py" ] && [ -f "$EXT" ] \
  || { echo "FAIL 산출 없음: $SRC / $EXT"; exit 1; }

T="$(mktemp -d "${TMPDIR:-/tmp}/r1538-team.XXXXXX")"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/base" "$T/fx"
NOW="$(date +%s)"

# ── base(고정 sha 17784fa49bcefbc641816047eceafd6fa08bd80a) — ⓔ 바이트 비교 기준(r1132 고정 기준판 ──
BASE_SHA=17784fa49bcefbc641816047eceafd6fa08bd80a
for f in ft-hil.sh ft_hil_pending.py ft_latest_write.py; do
  git -C "$PACK" show "$BASE_SHA:feature-pack/fable-team/harness/bin/$f" > "$T/base/$f" 2>"$T/base.err" \
    || { bad "base 추출 실패 $f ($(head -c 120 "$T/base.err"))"; }
done
[ -s "$T/base/ft_hil_pending.py" ] && ok "base = 고정 sha ${BASE_SHA:0:12} 3파일 추출" || bad "base 추출 실패"

run() {  # <BIN 폴더> <HIL_DIR> <인자…> → $T/out · $T/err · $T/rc
  local b="$1" d="$2"; shift 2
  env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$d" HIL_CLIP=0 FT_HIL_NOW="$NOW" \
    bash "$b/ft-hil.sh" "$@" >"$T/out" 2>"$T/err"; echo "$?" >"$T/rc"
}
out() { tr '\n' '|' <"$T/out"; }

# ── 픽스처: <케이스 폴더> — h 는 «2분 전» 미실행 · 계획 머리/notify 만 다르게 ────────────────
fx() {  # fx <케이스> <n>:<쉼표 좌석들 | ->[ :<notify 좌석 | ->][ :sp] — sp = 계획 파일을 «공백 있는 폴더·이름» 에 둔다(R1 반례)
  python3 - "$T/fx" "$NOW" "$@" <<'PY'
import os, sys
root, now, specs = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
case = os.path.join(root, specs[0]); os.makedirs(case, exist_ok=True)
for spec in specs[1:]:
    parts = spec.split(":"); n = parts[0]
    seats = [] if parts[1] == "-" else parts[1].split(",")
    sp = parts[3:] == ["sp"]
    plan = os.path.join(case, "plan dir", "ops plan %s.sh" % n) if sp else os.path.join(case, "plan-%s.sh" % n)
    os.makedirs(os.path.dirname(plan), exist_ok=True)
    open(plan, "w").write("#!/usr/bin/env bash\n" + ("# ft-hil-request seat=%s\n" % " ".join(seats) if seats else "") + "echo hi\n")
    p = os.path.join(case, "h%s" % n)
    open(p, "w").write("#!/usr/bin/env bash\n# ft-hil-entry plan=%s\nP=x; M=y\n" % plan)
    os.utime(p, (now - 120, now - 120))
    if len(parts) > 2 and parts[2] != "-":
        open(p + ".notify", "w").write("seat=%s\ncomm=/tmp/x\n" % parts[2])
PY
}
fx a 101:byz-ops-lead-claude#3 102:byz-cfo-lead-claude#4
fx b 103:-:byz-cfo-desk-claude#9
fx c 104:-
fx d 105:byz-ops-x#1,byz-cfo-y#2,byz-airag-z#3
fx e 101:byz-ops-lead-claude#3 102:byz-cfo-lead-claude#4 103:-:byz-cfo-desk-claude#9 104:- \
     105:byz-ops-x#1,byz-cfo-y#2,byz-airag-z#3 106:aifp-airag-nano#4 107:planner#3 108:byz-ops-x#1:byz-airag-nano#4
fx f 106:aifp-airag-nano#4 107:planner#3
fx h 120:byz-ops-lead-claude#3:byz-cfo-desk-claude#9:sp
fx i 121:byz-ops-lead-claude#3:-:sp

step "ⓐ 그 팀 h 만(ops h 1 + cfo h 1)"
run "$SRC" "$T/fx/a" --pending --each
eq "ⓐ --team 없음 = 2줄" "$(out)" "h101 2|h102 2|"
run "$SRC" "$T/fx/a" --pending --each --team ops
eq "ⓐ --team ops = ops 1줄" "$(out)" "h101 2|"
eq "ⓐ --team ops stderr 0" "$(wc -c <"$T/err" | tr -d ' ')" 0
eq "ⓐ --team ops rc0" "$(cat "$T/rc")" 0
run "$SRC" "$T/fx/a" --pending --each --team cfo
eq "ⓐ --team cfo = cfo 1줄" "$(out)" "h102 2|"
run "$SRC" "$T/fx/a" --pending --each --team harness
eq "ⓐ --team harness = 0줄" "$(out)" ""
run "$SRC" "$T/fx/a" --pending --team ops
eq "ⓐ 요약도 거른다(미실행 h 1개)" "$(out)" "미실행 h 1개 · 가장 오래된 2분|"

step "ⓑ 요청 머리 없음 + notify seat= → notify 좌석 팀"
run "$SRC" "$T/fx/b" --pending --each --team cfo
eq "ⓑ cfo 로 셈" "$(out)" "h103 2|"
run "$SRC" "$T/fx/b" --pending --each --team ops
eq "ⓑ ops 에는 0" "$(out)" ""
eq "ⓑ 표식 있는 h 는 stderr 0" "$(wc -c <"$T/err" | tr -d ' ')" 0

step "ⓒ 표식 없는 h = 모든 팀에 셈 + 근거 1줄"
for tm in ops harness cfo; do
  run "$SRC" "$T/fx/c" --pending --each --team "$tm"
  eq "ⓒ --team $tm = h104 셈" "$(out)" "h104 2|"
  eq "ⓒ --team $tm stderr 1줄" "$(cat "$T/err")" "팀 표식 없음 h104 — 전 팀에 셈(기존 동작)"
  eq "ⓒ --team $tm rc0" "$(cat "$T/rc")" 0
done

step "ⓓ 요청 좌석 3개(다른 팀) = 그 셋 모두에 셈"
for tm in ops cfo airag; do
  run "$SRC" "$T/fx/d" --pending --each --team "$tm"
  eq "ⓓ --team $tm = h105" "$(out)" "h105 2|"
done
run "$SRC" "$T/fx/d" --pending --each --team harness
eq "ⓓ --team harness = 0줄" "$(out)" ""

step "ⓔ --team 없는 호출 = base 와 바이트 같음"
for a in "" --each --held; do
  run "$SRC" "$T/fx/e" --pending $a; cp "$T/out" "$T/new.out"; cp "$T/err" "$T/new.err"; cp "$T/rc" "$T/new.rc"
  run "$T/base" "$T/fx/e" --pending $a
  if cmp -s "$T/new.out" "$T/out" && cmp -s "$T/new.rc" "$T/rc" && [ ! -s "$T/new.err" ]; then
    ok "ⓔ --pending ${a:-(요약)} = base 바이트 같음($(wc -l <"$T/out" | tr -d ' ')줄)"
  else
    bad "ⓔ --pending ${a:-(요약)} 다름" "rc 새=$(cat "$T/new.rc") base=$(cat "$T/rc") err=$(head -c 160 "$T/new.err")"
  fi
done
run "$T/base" "$T/fx/e" --pending --each; cp "$T/out" "$T/base.out"
run "$SRC" "$T/fx/e" --pending --each --team harness; cp "$T/out" "$T/team.out"
eq "ⓔ 거른 판은 base 와 다르다(전제: 다른 팀 h 가 있다)" "$([ "$(cat "$T/base.out")" != "$(cat "$T/team.out")" ] && echo yes || echo no)" yes

step "ⓕ aifp-<팀>-… = <팀> · 그 밖 꼴 좌석 = 표식 없음"
run "$SRC" "$T/fx/f" --pending --each --team airag
eq "ⓕ --team airag = aifp 좌석 h106 + 표식 없는 h107" "$(out)" "h106 2|h107 2|"
eq "ⓕ stderr = h107 만" "$(cat "$T/err")" "팀 표식 없음 h107 — 전 팀에 셈(기존 동작)"
run "$SRC" "$T/fx/f" --pending --each --team harness
eq "ⓕ --team harness = 표식 없는 h107 만" "$(out)" "h107 2|"

step "ⓗ R1 반례 1 — 계획 «공백 경로» + notify 다른 팀"
run "$SRC" "$T/fx/h" --pending --each
printf '%s' "$(head -2 "$T/fx/h/h120" | tail -1)" | grep -q 'plan dir/ops plan 120.sh' \
  && ok "ⓗ 전제: h120 의 plan 줄에 공백 경로가 있다" || bad "ⓗ 전제 실패(공백 경로 픽스처)"
run "$SRC" "$T/fx/h" --pending --each --team ops
eq "ⓗ --team ops = 공백 경로 요청 좌석(ops) 으로 셈" "$(out)" "h120 2|"
eq "ⓗ --team ops stderr 0(표식 있음)" "$(wc -c <"$T/err" | tr -d ' ')" 0
run "$SRC" "$T/fx/h" --pending --each --team cfo
eq "ⓗ --team cfo = notify 좌석(cfo) 으로도 셈" "$(out)" "h120 2|"
run "$SRC" "$T/fx/h" --pending --each --team harness
eq "ⓗ --team harness = 0줄(전 팀 오분류 0)" "$(out)" ""
eq "ⓗ --team harness stderr 0" "$(wc -c <"$T/err" | tr -d ' ')" 0

step "ⓘ R1 반례 2 — 공백 경로 + notify 없음 = 전 팀 오분류 0"
run "$SRC" "$T/fx/i" --pending --each --team ops
eq "ⓘ --team ops = h121" "$(out)" "h121 2|"
run "$SRC" "$T/fx/i" --pending --each --team harness
eq "ⓘ --team harness = 0줄(표식 없음으로 새지 않는다)" "$(out)" ""
eq "ⓘ --team harness stderr «팀 표식 없음» 0" "$(wc -c <"$T/err" | tr -d ' ')" 0

step "ⓖ ft-idle-nudge 가 그 팀 h 로 판정"
if command -v node >/dev/null 2>&1; then
  WAKE="$(dirname "$EXT")/ft-mbox-wake.ts"
  mkdir -p "$T/stub"
  cat > "$T/stub/ft-goal-table.sh" <<'SH'
F="$(cd "$(dirname "$0")/../.." && pwd)/fake"
echo "★팀별 완성 진행 (abcdef0123)★"; echo "| 팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것 |"; echo "|---|---|---|---|"
echo "| harness | — | 1 | 일 |"; echo "| ops | — | 1 | 일 |"
echo "★/팀별 완성 진행★"
SH
  cat > "$T/stub/ft-card-flow.sh" <<'SH'
echo "카드 대기 0 · 진행 0(좌석 0) · 착지됐는데 진행 0"
SH
  cat > "$T/stub/ft-hil.sh" <<'SH'
F="$(cd "$(dirname "$0")/../.." && pwd)/fake"
[ "$1 $2" = "--pending --each" ] || exit 2
if [ "${3:-}" = "--team" ]; then [ -n "${4:-}" ] || exit 2; awk -v t="$4" '$3 == t { print $1, $2 }' "$F/hil"; else awk '{ print $1, $2 }' "$F/hil"; fi
SH
  cat > "$T/stub/mbox.sh" <<'SH'
D="${FT_MBOX_DIR:-$(cd "$(dirname "$0")" && pwd)}"
[ "$1" = peek ] || exit 2
echo "pending=0 scanned=1 lineage=0"
SH
  cat > "$T/driver.mjs" <<'NODE'
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
const EXT = process.env.R1538_EXT, ROOT = process.env.R1538_TMP, STUB = process.env.R1538_STUB;
const SEAT = "byz-harness-master-pi#171";
let modv = 0, fails = 0;
const eq = (n, got, want) => (String(got) === String(want) ? console.log(`PASS ${n}`) : (fails++, console.log(`FAIL ${n} :: 기대 '${want}' 실제 '${got}'`)));
function setup(name, hil) {
  const dir = path.join(ROOT, name), base = path.join(dir, ".fable-team"), fake = path.join(dir, "fake");
  for (const d of [path.join(base, "bin"), path.join(base, "comm"), path.join(base, "state"), path.join(fake, "indices", "대기"), path.join(fake, "indices", "진행")]) fs.mkdirSync(d, { recursive: true });
  for (const n of ["ft-goal-table.sh", "ft-card-flow.sh", "ft-hil.sh"]) fs.copyFileSync(path.join(STUB, n), path.join(base, "bin", n));
  fs.copyFileSync(path.join(STUB, "mbox.sh"), path.join(base, "comm", "mbox.sh"));
  fs.writeFileSync(path.join(base, "seats-harness.json"), JSON.stringify({ _master: SEAT, [SEAT]: { role: "master", agent: "pi" } }) + "\n");
  fs.writeFileSync(path.join(fake, "hil"), hil);
  const mbox = path.join(base, "comm", "mailbox.jsonl"); fs.writeFileSync(mbox, "");
  Object.assign(process.env, { FT_MBOX_ROOT: dir, FT_MBOX_STATE_DIR: path.join(base, "state"), FT_MBOX_FILE: mbox, FT_SEAT: SEAT });
  return dir;
}
async function load(ext) {
  const pi = { calls: [], h: {}, on(e, f) { (this.h[e] ??= []).push(f); },
    async emit(e, ev = {}) { for (const f of this.h[e] ?? []) await f(ev); },
    sendMessage(m, o) { this.calls.push({ m, o }); } };
  const mod = await import(`${pathToFileURL(ext).href}?v=${++modv}`);
  mod.default(pi);
  await pi.emit("agent_settled", { aborted: false });
  return pi;
}
setup("ops-only", "h9001 12 ops\n");
eq("ⓖ 다른 팀(ops) h 1 · 그 팀 h 0 = 턴 1", (await load(EXT)).calls.length, 1);
setup("own-team", "h9002 12 harness\n");
eq("ⓖ 그 팀(harness) h 1 = 턴 0", (await load(EXT)).calls.length, 0);
setup("none", "");
eq("ⓖ h 0 = 턴 1(전제)", (await load(EXT)).calls.length, 1);
// 변이 M3 — --team 을 안 넘기면 다른 팀 h 가 그 팀 h 로 새어 턴 0
const src = fs.readFileSync(EXT, "utf-8");
const mut = src.replace(', "--team", team', "");
if (mut === src) { fails++; console.log("FAIL 변이 M3 치환 미적용"); }
else {
  const p = path.join(path.dirname(EXT), "mut-M3.ts"); fs.writeFileSync(p, mut);
  setup("m3", "h9001 12 ops\n");
  eq("변이 M3 → ⓖ 턴 0 = FAIL 검출", (await load(p)).calls.length, 0);
}
console.log("---");
console.log(fails === 0 ? "DRIVER ALL PASS" : `DRIVER FAIL ${fails}`);
process.exit(fails === 0 ? 0 : 1);
NODE
  # 확장 둘(ft-idle-nudge → ./ft-mbox-wake.ts) + pi 패키지 스텁
  mkdir -p "$T/ext" "$T/node_modules/@earendil-works/pi-coding-agent"
  cp "$EXT" "$T/ext/ft-idle-nudge.ts"; cp "$WAKE" "$T/ext/ft-mbox-wake.ts"; cp "$(dirname "$EXT")/ft-load-line.ts" "$T/ext/" # r1537 공용 헬퍼(확장이 import)
  printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' \
    > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
  echo 'export const createLocalBashOperations = () => ({ exec: async () => ({ output: "", exitCode: 0 }) });' \
    > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
  R1538_EXT="$T/ext/ft-idle-nudge.ts" R1538_TMP="$T" R1538_STUB="$T/stub" \
    timeout 70 node "$T/driver.mjs"; rc=$?
  eq "ⓖ 확장 시험 rc0" "$rc" 0
else
  bad "ⓖ node 없음 — 확장 시험 못 함"
fi

step "변이 M1(--team 거르기 끔) · M2(표식 없는 h 를 뺌)"
mut() {  # <이름> <치환 전> <치환 후> → $T/mut-<이름> 폴더
  local n="$1" dir="$T/mut-$1"
  mkdir -p "$dir"; cp "$SRC"/ft-hil.sh "$SRC"/ft_hil_pending.py "$SRC"/ft_hil_team.py "$SRC"/ft_latest_write.py "$dir"/
  python3 - "$dir/ft_hil_team.py" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if a not in s: print("MISS", file=sys.stderr); sys.exit(3)
open(p, "w").write(s.replace(a, b, 1))
PY
  echo "$dir"
}
if d="$(mut M1 "if not t or team in t:" "if True:" 2>/dev/null)"; then
  run "$d" "$T/fx/a" --pending --each --team ops
  eq "변이 M1 → ⓐ 2줄(거르기 꺼짐) = FAIL 검출" "$(out)" "h101 2|h102 2|"
else bad "변이 M1 치환 미적용"; fi
if d="$(mut M2 "if not t or team in t:" "if t and team in t:" 2>/dev/null)"; then
  run "$d" "$T/fx/c" --pending --each --team ops
  eq "변이 M2 → ⓒ 0줄(표식 없는 h 사라짐) = FAIL 검출" "$(out)" ""
else bad "변이 M2 치환 미적용"; fi
if d="$(mut M4 'seats(rest(hpath, PLAN) or "", REQ)' 'seats((seats(hpath, PLAN) or [""])[0], REQ)' 2>/dev/null)"; then  # 경로를 공백으로 자르던 R1 이전 꼴
  run "$d" "$T/fx/h" --pending --each --team ops
  eq "변이 M4 → ⓗ ops 0줄(경로가 잘려 요청 팀 유실) = FAIL 검출" "$(out)" ""
  run "$d" "$T/fx/i" --pending --each --team ops
  eq "변이 M4 → ⓘ «팀 표식 없음» stderr 가 샌다 = FAIL 검출" "$(cat "$T/err")" "팀 표식 없음 h121 — 전 팀에 셈(기존 동작)"
  run "$d" "$T/fx/i" --pending --each --team harness
  eq "변이 M4 → ⓘ harness 1줄(전 팀 오분류) = FAIL 검출" "$(out)" "h121 2|"
else bad "변이 M4 치환 미적용"; fi

# 접합(산출 정합) — bin 과 kit 같은 바이트
for f in ft_hil_pending.py ft_hil_team.py ft-hil.sh; do
  cmp -s "$HARNESS/bin/$f" "$HARNESS/kit/fable-team/bin/$f" && ok "접합 $f bin=kit" || bad "접합 $f bin≠kit"
done

step "결과: FAIL $fail · 총 $((SECONDS - t0))s"
[ "$fail" = 0 ]
