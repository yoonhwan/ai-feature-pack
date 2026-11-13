#!/usr/bin/env bash
# test_thresholds_one_source_r1860.sh — 교대 문턱 «파일 없을 때 기본값» = 설치본 templates/thresholds.env.sample 한 곳(r1860).
#   네 도구(ft-thresholds.sh · claude 훅 · ft-resume-gate.sh · pi distill-gate.ts thresholds())가 같은 값을 쓰는지 대조한다.
#   반례 ① 홈 파일 → 330/350/280/200 ② 홈·루트 파일 없음 → 샘플 250/300/250/150 ③ 샘플을 260/310/240/160 으로 → 네 도구 그 값
#   ④ 샘플도 없음 → ft-thresholds rc3 · pi null · 훅 판정 불가 1줄 · 리줌 UNKNOWN rc3.
#   r1: pi 샘플 = ft2 adapters/pi/thresholds.env.sample(env FT_DISTILL_SAMPLE > 어댑터 옆 > ~/.claude/fable-team/ft2/versions/<CURRENT>/adapters/pi/)
#   ⑤ 1.x kit 샘플과 ft2 사본 cmp 0 ⑥ ft2 legacy_guard 위반 0.
#   임시 HOME·임시 설치본 사본만 · 실 홈·장부 쓰기 0 · sleep 0. 변이용 override: KIT=<kit/fable-team 사본> PI_GATE=<distill-gate.ts 사본> FT2_SAMPLE=<ft2 샘플 사본>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${KIT:-$HERE/../kit/fable-team}"
FT2="$(cd -- "$HERE/../../../../ft2" && pwd)"
PI_GATE="${PI_GATE:-$FT2/adapters/pi/distill-gate.ts}"; FT2_SAMPLE="${FT2_SAMPLE:-$FT2/adapters/pi/thresholds.env.sample}"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
I="$T/inst"; R="$T/rep"; H="$T/home"; FAKE="$T/fakebin"
P="$T/pi"; mkdir -p "$I/bin" "$I/templates/hooks" "$R/.git" "$R/.fable-team" "$H" "$FAKE" "$P"
cp "$KIT/bin/ft-thresholds.sh" "$KIT/bin/ft-resume-gate.sh" "$I/bin/"
cp "$KIT/templates/hooks/context-distill-gate.sh" "$I/templates/hooks/"
cp "$KIT/templates/thresholds.env.sample" "$I/templates/"
cp "$PI_GATE" "$P/distill-gate.ts"; cp "$FT2_SAMPLE" "$P/" 2>/dev/null   # pi 어댑터 사본 + 옆 샘플
printf '#!/usr/bin/env bash\ncase "$1" in display) echo "byz-t-x-claude#1";; esac; exit 0\n' > "$FAKE/tmux"; chmod +x "$FAKE/tmux"
unset FT_DISTILL_WARN FT_DISTILL_BLOCK FT_DISTILL_RECV FT_RESUME_MAX FT_DISTILL_NEWWORK FT_THRESHOLDS OMC_FT_BIN FT_DISTILL_THRESHOLDS FT_DISTILL_SAMPLE
run(){ env HOME="$H" PATH="$FAKE:$PATH" TMUX_PANE=%1 "$@"; }
tj(){ printf '{"type":"assistant","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1" > "$T/t.jsonl"; }
hj(){ python3 -c 'import json,sys;print(json.dumps({"transcript_path":sys.argv[1],"cwd":sys.argv[2],"tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$T/t.jsonl" "$R" "$1"; }

# vals → "WARN BLOCK RECV RESUME" 를 도구마다 한 줄씩(ft · hook · resume · pi)
ft_vals(){ run bash "$I/bin/ft-thresholds.sh" --export 2>/dev/null | python3 -c 'import sys,re;d=dict(re.findall(r"(FT_\w+)=(\d+)",sys.stdin.read()));print(*[int(d.get(k,0))//1000 for k in ("FT_DISTILL_WARN","FT_DISTILL_BLOCK","FT_DISTILL_RECV","FT_RESUME_MAX")])'; }
hook_recv(){ tj "$1"; hj "bash $R/.fable-team/comm/mbox.sh recv x" | run bash "$I/templates/hooks/context-distill-gate.sh" hard >/dev/null 2>&1; echo $?; }
hook_vals(){ # hook_vals <warn> <recv 후보> · warn/block = 경고 문구의 두 숫자 · recv = 후보 V 에서 막고(rc2) V-1 토큰에서 통과(rc0)할 때만 V
  local w b r="?"
  tj "$(( $1 * 1000 + 5000 ))"; hj "ls" | run bash "$I/templates/hooks/context-distill-gate.sh" warn 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' > "$T/hw" 2>/dev/null
  w="$(grep -o '경고선([0-9]*k)' "$T/hw" | tr -dc 0-9)"; b="$(grep -o '[0-9]*k(절대값)' "$T/hw" | tr -dc 0-9)"
  [ "$(hook_recv "$(( $2 * 1000 ))")" = 2 ] && [ "$(hook_recv "$(( $2 * 1000 - 1 ))")" = 0 ] && r="$2"
  echo "${w:-?} ${b:-?} $r"; }
resume_val(){ tj 999999999; run bash "$I/bin/ft-resume-gate.sh" "$T/t.jsonl" 2>&1 | sed -n 's/.*max=\([0-9,]*\).*/\1/p' | tr -d , | python3 -c 'import sys;s=sys.stdin.read().strip();print(int(s)//1000 if s else "?")'; }
pi_vals(){ HOME="$H" node --no-warnings --input-type=module -e 'const m=await import(process.argv[1]);const s=process.env.FT_DISTILL_SAMPLE;const t=m.thresholds(s?{FT_DISTILL_SAMPLE:s}:{},process.argv[2]);console.log(t?`${t.warn/1000} ${t.block/1000} ${t.recv/1000}`:"null")' "$(python3 -c 'import pathlib,sys;print(pathlib.Path(sys.argv[1]).resolve().as_uri())' "$P/distill-gate.ts")" "$R" 2>&1; }
check(){ # check <이름> <warn> <block> <recv> <resume>
  local f h r p; f="$(ft_vals)"; h="$(hook_vals "$2" "$4")"; r="$(resume_val)"; p="$(pi_vals)"
  [ "$f" = "$2 $3 $4 $5" ] && ok "$1 ft-thresholds $f" || bad "$1 ft-thresholds 기대 $2 $3 $4 $5 실제 $f"
  [ "$h" = "$2 $3 $4" ] && ok "$1 훅 $h" || bad "$1 훅 기대 $2 $3 $4 실제 $h"
  [ "$r" = "$5" ] && ok "$1 리줌 $r" || bad "$1 리줌 기대 $5 실제 $r"
  [ "$p" = "$2 $3 $4" ] && ok "$1 pi $p" || bad "$1 pi 기대 $2 $3 $4 실제 $p"; }

mkdir -p "$H/.claude/fable-team"
printf 'FT_DISTILL_WARN=330000\nFT_DISTILL_BLOCK=350000\nFT_DISTILL_RECV=280000\nFT_RESUME_MAX=200000\n' > "$H/.claude/fable-team/thresholds.env"
check "① 홈 파일" 330 350 280 200
rm -f "$H/.claude/fable-team/thresholds.env"
check "② 파일 없음 → 샘플" 250 300 250 150
printf 'FT_DISTILL_WARN=260000\nFT_DISTILL_BLOCK=310000\nFT_DISTILL_RECV=240000\nFT_DISTILL_NEWWORK=310000\nFT_RESUME_MAX=160000\n' > "$I/templates/thresholds.env.sample"; cp "$I/templates/thresholds.env.sample" "$P/thresholds.env.sample"
check "③ 샘플 260/310/240/160" 260 310 240 160

printf 'FT_DISTILL_WARN=270000\nFT_DISTILL_BLOCK=320000\nFT_DISTILL_RECV=260000\n' > "$T/e.sample"
[ "$(FT_DISTILL_SAMPLE="$T/e.sample" pi_vals)" = "270 320 260" ] && ok "③ pi env FT_DISTILL_SAMPLE 우선" || bad "③ pi env 샘플 $(FT_DISTILL_SAMPLE="$T/e.sample" pi_vals)"
rm -f "$I/templates/thresholds.env.sample" "$P/thresholds.env.sample"
V="$H/.claude/fable-team/ft2"; mkdir -p "$V/versions/9.9.9/adapters/pi"; echo 9.9.9 > "$V/CURRENT"; cp "$T/e.sample" "$V/versions/9.9.9/adapters/pi/thresholds.env.sample"
[ "$(pi_vals)" = "270 320 260" ] && ok "④ pi 설치본 versions/<CURRENT> 샘플" || bad "④ pi 설치본 샘플 $(pi_vals)"
rm -rf "$V"
run bash "$I/bin/ft-thresholds.sh" --show > "$T/o4" 2>&1; rc=$?
[ $rc -eq 3 ] && ok "④ 샘플 없음 ft-thresholds rc3" || bad "④ ft-thresholds rc=$rc $(head -c 160 "$T/o4")"
[ "$(pi_vals)" = null ] && ok "④ pi null(판정 불가)" || bad "④ pi $(pi_vals)"
tj 270000; hj "ls" | run bash "$I/templates/hooks/context-distill-gate.sh" warn > "$T/h4" 2>"$T/e4"; rc=$?
{ [ $rc -eq 1 ] && [ "$(grep -c '판정 실패' "$T/e4")" = 1 ]; } && ok "④ 훅 판정 불가 1줄 rc1" || bad "④ 훅 rc=$rc err=$(head -c 200 "$T/e4")"
tj 999999999; run bash "$I/bin/ft-resume-gate.sh" "$T/t.jsonl" > "$T/r4" 2>&1; rc=$?
{ [ $rc -eq 3 ] && grep -q UNKNOWN "$T/r4"; } && ok "④ 리줌 UNKNOWN rc3" || bad "④ 리줌 rc=$rc $(cat "$T/r4")"

cmp -s "$KIT/templates/thresholds.env.sample" "$FT2_SAMPLE" && ok "⑤ 1.x kit 샘플 = ft2 사본(cmp 0)" || bad "⑤ 두 샘플 다름/없음: $FT2_SAMPLE"
sed '3s/=.*/=1/' "$KIT/templates/thresholds.env.sample" > "$T/diff.sample"; ! cmp -s "$KIT/templates/thresholds.env.sample" "$T/diff.sample" && ok "⑤ 한 줄 다른 사본 → cmp 가 잡음" || bad "⑤ cmp 자기검사"
python3 "$FT2/tools/legacy_guard.py" "$FT2" > "$T/g6" 2>&1 && ok "⑥ ft2 legacy_guard 위반 0" || bad "⑥ legacy_guard $(head -c 200 "$T/g6")"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
