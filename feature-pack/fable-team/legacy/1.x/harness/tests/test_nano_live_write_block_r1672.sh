#!/usr/bin/env bash
# test_nano_live_write_block_r1672.sh — r1672: 나노 좌석은 라이브 자리(LIVE_BIN 판 폴더·live/ · 루트 .fable-team/bin* · comm 원장 · ~/.pi/agent/extensions)에 직접 쓰지 못한다.
#   ⓐ pi 나노(write·edit·bash)의 라이브 쓰기 거절 · ⓑ realpath(심링크·..·~) 우회 0 · ⓒ claude worker-guard 같은 칸 · ⓓ 발주문 고정 문단
#   ⓔ 나노 아님·팩/임시 쓰기·라이브 읽기·mbox.sh 호출 통과 · ⓕ LIVE_BIN 못 읽음 = NOTE 1줄 + 나머지 칸 판정 · ⓗ 감지 로그 1줄(같은 좌석·같은 대상 1회)
#   ⓖ 회귀(install.json deny 유지·fail-open·pi 확장 로드 1줄) · 변이 M1~M4(사본에서만) = 계약이 실제로 잡히나
#  격리: tmp HOME·tmp 루트·tmp live 판 폴더 · 실 라이브·실 확장 쓰기 0 · press 0 · sleep 0 · 사례 < 10초
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
GUARD="$H/pi/ft-live-write-guard.ts"; SPAWN="$H/bin/ft-nano-spawn.sh"; WG="$H/kit/fable-team/templates/hooks/ft-worker-guard.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
has(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "«$3» 없음";; esac; }
command -v node >/dev/null 2>&1 || { echo "FAIL node 없음"; exit 1; }
for f in "$GUARD" "$SPAWN" "$WG"; do [ -f "$f" ] || { echo "FAIL 없음 $f"; exit 1; }; done

# ── 정적 계약 ──
eq "S1 guard.ts ≤110줄" "$([ "$(wc -l < "$GUARD" | tr -d ' ')" -le 110 ] && echo yes || echo no)" yes
eq "S2 spawn r1672 주석 1줄" "$(grep -c '^# r1672:' "$SPAWN")" 1
eq "S3 spawn 문단 1회" "$(grep -c '카드 «설치:»·«켜기» 줄 = master 몫' "$SPAWN")" 1
eq "S4 worker-guard 두 사본 같은 글자" "$(diff -q "$WG" "$H/../skill/templates/hooks/ft-worker-guard.sh" >/dev/null 2>&1 && echo same || echo diff)" same
bash -n "$SPAWN" && bash -n "$WG" && bash -n "$0" && ok "S5 bash -n 3종" || bad "S5 bash -n"
[ "$(stat -f %Lp "$0")" = 644 ] && ok "S6 시험 파일 100644" || bad "S6 시험 파일 모드"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1672.XXXXXX")"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; R="$T/root"; R2="$T/root2"; L="$HOME/.claude/fable-team/live/1.1.292/bin"; X="$T/ext"
mkdir -p "$L" "$R/.fable-team/comm/bodies" "$R/.fable-team/bin" "$R2/.fable-team/bin" "$HOME/.pi/agent/extensions" "$T/pack"
printf '%s\n' "$L" > "$R/.fable-team/LIVE_BIN"; : > "$L/ft-x.sh"; ln -s "$HOME/.claude/fable-team/live" "$T/link"; ln -s "$L" "$T/alias"
cp "$GUARD" "$X.ts"; cp "$H/pi/ft-load-line.ts" "$T/"
mkdir -p "$T/node_modules/@earendil-works/pi-coding-agent"
printf '{"name":"@earendil-works/pi-coding-agent","type":"module","main":"index.mjs","exports":"./index.mjs"}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/package.json"
printf 'export default function(){}\n' > "$T/node_modules/@earendil-works/pi-coding-agent/index.mjs"
cat > "$T/driver.mjs" <<'NODE'
import { pathToFileURL } from "node:url";
const m = await import(pathToFileURL(process.env.EXT).href), h = {};
m.default({ on: (n, f) => { h[n] = f; }, appendEntry: (t, d) => { globalThis.__e = d; } });
await h.session_start();
console.log(`CASE loadline ${globalThis.__e?.card === "r1672" && globalThis.__e?.line ? "OK" : "NO"}`);
const R = process.env.FT_LIVE_ROOT, L = `${process.env.HOME}/.claude/fable-team/live/1.1.292/bin`;
const cases = [
  ["a-write", "write", { path: `${L}/ft-x.sh` }], ["a-edit", "edit", { path: `${L}/ft-x.sh`, edits: [] }],
  ["a-bash-cp", "bash", { command: `cp pack/a.ts ${L}/ft-x.sh` }],
  ["b-symlink", "write", { path: `${process.env.T}/link/1.1.292/bin/ft-x.sh` }],
  ["b-dotdot", "write", { path: `${L}/../1.1.292/bin/ft-x.sh` }],
  ["b-tilde", "write", { path: "~/.claude/fable-team/live/1.1.292/bin/ft-x.sh" }],
  ["r1-nospace", "bash", { command: `echo text>${L}/ft-x.sh` }],
  ["r1-livebin", "bash", { command: 'cp a.ts "$LIVE_BIN/ft-x.sh"' }],
  ["r1-home", "bash", { command: 'cp a.ts "$HOME/.pi/agent/extensions/ft-x.ts"' }],
  ["r2-alias", "write", { path: `${process.env.T}/alias/../bin/ft-x.sh` }],
  ["c-bin", "write", { path: `${R}/.fable-team/bin/ft-x.sh` }],
  ["c-comm", "bash", { command: `echo x >> ${R}/.fable-team/comm/mailbox.jsonl` }],
  ["c-ext", "write", { path: `${process.env.HOME}/.pi/agent/extensions/ft-x.ts` }],
  ["e-pack", "write", { path: "/tmp/pack/a.ts" }], ["e-bash", "bash", { command: "ls -la /tmp/pack > /tmp/o.txt" }],
  ["e-read", "bash", { command: `cat ${L}/ft-x.sh | head -3` }],
  ["e-mbox", "bash", { command: `bash ${R}/.fable-team/comm/mbox.sh send a b c` }],
];
for (const [n, t, i] of cases) console.log(`CASE ${n} ${(await h.tool_call({ toolName: t, input: i }))?.block ? "BLOCK" : "PASS"}`);
NODE
drive(){ EXT="$1" FT_LIVE_ROOT="$2" FT_SEAT_NAME="${3:-byz-harness-nano-r1672-x#0}" LIVE_BIN="$L" T="$T" node "$T/driver.mjs" 2>"$T/err"; }
one(){ printf '%s\n' "$1" | awk -v c="$2" '$1=="CASE"&&$2==c{print $3}'; }
expect(){ eq "$2" "$(one "$1" "$2")" "$3"; }
pairs(){ local o="$1"; shift; for p in "$@"; do expect "$o" "${p% *}" "${p#* }"; done; }

# ── ⓐⓑⓒⓔⓗ : 나노 좌석 ──
out="$(drive "$X.ts" "$R")"
pairs "$out" "a-write BLOCK" "a-edit BLOCK" "a-bash-cp BLOCK" "b-symlink BLOCK" "b-dotdot BLOCK" "b-tilde BLOCK" \
  "r1-nospace BLOCK" "r1-livebin BLOCK" "r1-home BLOCK" "r2-alias BLOCK" \
  "c-bin BLOCK" "c-comm BLOCK" "c-ext BLOCK" "e-pack PASS" "e-bash PASS" "e-read PASS" "e-mbox PASS"
eq "loadline" "$(one "$out" loadline)" OK
LOG="$R/.fable-team/state/live-write-block.log"
eq "H1 감지 로그 = 같은 좌석·같은 대상 1줄" "$(grep -c 'live/1.1.292/bin/ft-x.sh' "$LOG")" 1
eq "H2 로그 = 일반 파일 644" "$(stat -f %Lp "$LOG")" 644
drive "$X.ts" "$R" >/dev/null; eq "H3 두 번째 실행 = 로그 증가 0" "$(grep -c 'live/1.1.292/bin/ft-x.sh' "$LOG")" 1
pairs "$(drive "$X.ts" "$R" "byz-harness-master-pi#196")" "a-write PASS" "a-bash-cp PASS" "c-bin PASS" "c-comm PASS" "c-ext PASS"
# ── ⓕ LIVE_BIN 못 읽음 = NOTE 1줄 + 나머지 칸 판정 ──
out="$(drive "$X.ts" "$R2")"; expect "$out" c-bin BLOCK; expect "$out" a-write PASS
has "F1 NOTE 1줄" "$(cat "$T/err")" "NOTE ft-live-write-guard"; has "F2 판정 불가 문구" "$(cat "$T/err")" "판 폴더 칸 판정 불가"
# ── ⓒ claude worker-guard 칸 · ⓖ 회귀 ──
wg(){ printf '%s' "$1" | FT_WORKER_ROLE=implementer FT_LIVE_ROOT="$R" FT_SEAT_NAME=byz-harness-nano-worker#0 bash "$WG" >/dev/null 2>&1; echo $?; }
eq "C1 Write 라이브 = deny" "$(wg "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$L/ft-x.sh\"}}")" 2
eq "C2 Bash cp 라이브 = deny" "$(wg "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cp a.sh $L/ft-x.sh\"}}")" 2
eq "C3 Bash 읽기 라이브 = 통과" "$(wg "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat $L/ft-x.sh\"}}")" 0
eq "C4 팩 코드 쓰기 = 통과" "$(wg '{"tool_name":"Write","tool_input":{"file_path":"/tmp/pack/a.ts"}}')" 0
eq "G1 install.json deny 유지" "$(wg '{"tool_name":"Write","tool_input":{"file_path":"/x/install.json"}}')" 2
eq "G2 FT_WORKER_ROLE 없음 = 통과(fail-open)" "$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$L/ft-x.sh" | bash "$WG" >/dev/null 2>&1; echo $?)" 0
# ── ⓒ worker R3·R4 (DA 반례 그대로) ──
for c in "ln -s s $L/r3f" "rsync s $L/r3f" "echo t>$L/r3f" "cp a $L/r3f" "sed -i '' s/a/b/ $L/r3f" "sed -i -e s/a/b/ $L/r3f"; do
  eq "R3 데몬 deny :: $c" "$(wg "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$c\"}}")" 2
done
eq "R3 라이브 원본 → /tmp cp = 허용" "$(wg "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cp $L/ft-x.sh /tmp/copy\"}}")" 0
eq "R4 worker 거절 1줄" "$(grep -c "$L/r3f" "$LOG")" 1
# ── ⓓ 발주문 고정 문단(정의·본문·dry-run 출력) ──
eval "$(grep -m1 '^_LWX=' "$SPAWN")"
has "D1 설치 = master 몫" "$_LWX" "«설치:»·«켜기» 줄 = master 몫(나노 지시 아님)"
has "D2 산출 보고 1줄" "$_LWX" "«설치 h 필요» 1줄만"
eq "D3 BODY 에 문단 1회" "$(grep -c '^BODY=.*\${_LWX}' "$SPAWN")" 1
eq "D4 dry-run 출력 줄" "$(grep -c '^echo "BODY+\${_LWX}"' "$SPAWN")" 1
# ── 변이 M1~M4 (사본에서만) ──
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
hit(){ local o g; o="$(drive "$1" "$R" "${3:-byz-harness-nano-r1672-x#0}")"; g="$(one "$o" "$2")"; [ "$g" = "$4" ]; }
mut "$X.ts" "$T/m1.ts" ': tool === "bash" ? bashTargets(String(input.command ?? "")) : []' ': []'
hit "$T/m1.ts" a-bash-cp "" PASS && ok "M1 탐지 = bash 대상 판정 삭제 → cp 통과" || bad "M1 미탐지"
mut "$X.ts" "$T/m2.ts" 'const p = realish(t), hit' 'const p = t, hit'
hit "$T/m2.ts" b-symlink "" PASS && ok "M2 탐지 = realpath 삭제 → 심링크 우회 통과" || bad "M2 미탐지"
mut "$X.ts" "$T/m3.ts" 'if (!seat || !NANO.test(seat)) return;' 'if (!seat) return;'
hit "$T/m3.ts" a-write "byz-harness-master-pi#196" BLOCK && ok "M3 탐지 = 나노 꼴 검사 삭제 → master 차단" || bad "M3 미탐지"
python3 -c 'import sys,re;a,b=sys.argv[1:];s=open(a).read();t=re.sub(r"(?m)^(BODY=.*?)\$\{_LWX\}", r"\1", s, count=1);assert t != s, "BODY 줄에 ${_LWX} 없음";open(b,"w").write(t)' "$SPAWN" "$T/m4.sh"
eq "M4 탐지 = 고정 문단 삭제" "$(grep -c '\${_LWX}' "$T/m4.sh")" 1
mut "$WG" "$T/m5.sh" 'if base == "sed":' 'if base == "sed_off":'
wgm(){ printf '%s' "$1" | FT_WORKER_ROLE=implementer FT_LIVE_ROOT="$R" FT_SEAT_NAME=byz-harness-nano-worker#0 bash "$T/m5.sh" >/dev/null 2>&1; echo $?; }
eq "M5 탐지 = sed -i 분기 제거 → 거절 안 됨" "$(wgm "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i '' s/a/b/ $L/r3f\"}}")" 0

echo "----"; eq "합계 fail" "$fail" 0; exit $((fail > 0))
