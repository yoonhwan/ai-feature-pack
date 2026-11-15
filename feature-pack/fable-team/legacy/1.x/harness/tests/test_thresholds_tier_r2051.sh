#!/usr/bin/env bash
# test_thresholds_tier_r2051.sh — 증류 문턱을 모델 창 티어별 세트로 읽는다(r2051 · 오빠 1번 확정).
#   키 꼴: FT_DISTILL_TIER_<T>_MATCH=부분문자열[,…] · FT_DISTILL_{WARN,BLOCK,RECV}_<T>=정수 · 매칭 0 = 지금 키 3값.
#   대상 = ft-thresholds.sh(--get/--export/--show --model) · claude 훅(context-distill-gate.sh). pi 게이트 = ft2/tests/test_pi_distill_gate_tier_r2051.py.
#   반례 ①~⑥ + ⑦ 사본·샘플 cmp. 임시 HOME·임시 설치본 사본만 · 실 홈·장부 쓰기 0 · sleep 0.
#   변이용 override: KIT=<kit/fable-team 사본>.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${KIT:-$HERE/../kit/fable-team}"
SKILL="$HERE/../../skill"; FT2="$(cd -- "$HERE/../../../../ft2" && pwd)"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/rep"; I="$R/.fable-team/live"; H="$T/home"; FAKE="$T/fakebin"; UF="$H/.claude/fable-team/thresholds.env"
mkdir -p "$I/bin" "$I/templates/hooks" "$R/.git" "$R/.fable-team" "$H/.claude/fable-team" "$FAKE"
cp "$KIT/bin/ft-thresholds.sh" "$I/bin/"; cp "$KIT/templates/hooks/context-distill-gate.sh" "$I/templates/hooks/"
cp "$KIT/templates/thresholds.env.sample" "$I/templates/"
printf '#!/usr/bin/env bash\ncase "$1" in display) echo "byz-t-x-claude#1";; esac; exit 0\n' > "$FAKE/tmux"; chmod +x "$FAKE/tmux"
unset FT_DISTILL_WARN FT_DISTILL_BLOCK FT_DISTILL_RECV FT_RESUME_MAX FT_DISTILL_NEWWORK FT_THRESHOLDS OMC_FT_BIN FT_DISTILL_THRESHOLDS FT_DISTILL_SAMPLE
run(){ env HOME="$H" PATH="$FAKE:$PATH" TMUX_PANE=%1 "$@"; }
FTS(){ run bash "$I/bin/ft-thresholds.sh" "$@"; }
BASE='FT_DISTILL_WARN=330000\nFT_DISTILL_BLOCK=350000\nFT_DISTILL_RECV=280000\nFT_RESUME_MAX=200000\n'
T200='FT_DISTILL_TIER_200K_MATCH=haiku\nFT_DISTILL_RECV_200K=120000\nFT_DISTILL_WARN_200K=140000\nFT_DISTILL_BLOCK_200K=150000\n'
ft_vals(){ echo "$(FTS --get FT_DISTILL_RECV --model "$1" 2>/dev/null) $(FTS --get FT_DISTILL_WARN --model "$1" 2>/dev/null) $(FTS --get FT_DISTILL_BLOCK --model "$1" 2>/dev/null)"; }
tj(){ # tj <토큰> <모델(빈 값 = model 칸 없음)>
  if [ -n "$2" ]; then printf '{"type":"assistant","message":{"model":"%s","usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$2" "$1"
  else printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1"; fi > "$T/t.jsonl"; }
hj(){ python3 -c 'import json,sys;print(json.dumps({"transcript_path":sys.argv[1],"cwd":sys.argv[2],"tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$T/t.jsonl" "$R" "$1"; }
HOOK(){ hj "$2" | run /bin/bash "$I/templates/hooks/context-distill-gate.sh" "$1"; }
hook_recv(){ tj "$1" "$2"; HOOK hard "bash $R/.fable-team/comm/mbox.sh recv x" >/dev/null 2>&1; echo $?; }
hook_vals(){ # hook_vals <모델> <warn 후보> <recv 후보> → "RECV WARN BLOCK"(토큰 원값) · warn/block = 경고 문구 숫자 · recv = V 에서 막고 V-1 에서 통과할 때만 V
  local w b r="?"
  tj "$(( $2 + 5000 ))" "$1"; HOOK warn ls 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' > "$T/hw" 2>/dev/null
  w="$(grep -o '경고선([0-9]*k)' "$T/hw" | tr -dc 0-9)"; b="$(grep -o '[0-9]*k(절대값)' "$T/hw" | tr -dc 0-9)"
  [ "$(hook_recv "$3" "$1")" = 2 ] && [ "$(hook_recv "$(( $3 - 1 ))" "$1")" = 0 ] && r="$3"
  echo "$r ${w:-?}000 ${b:-?}000"; }
eq(){ [ "$2" = "$3" ] && ok "$1 = $3" || bad "$1 기대 $3 실제 $2"; }

printf "$BASE$T200" > "$UF"
# ① 200K 4줄 · haiku → 120000·140000·150000
eq "① ft --get --model claude-haiku-4-5" "$(ft_vals claude-haiku-4-5)" "120000 140000 150000"
eq "① ft --export --model" "$(FTS --export --model claude-haiku-4-5 2>/dev/null | grep -o 'FT_DISTILL_[A-Z]*=[0-9]*' | sed -n '1,3p' | tr '\n' ' ')" "FT_DISTILL_WARN=140000 FT_DISTILL_BLOCK=150000 FT_DISTILL_RECV=120000 "
eq "① 훅 haiku" "$(hook_vals claude-haiku-4-5 140000 120000)" "120000 140000 150000"
FTS --show > "$T/show" 2>&1
{ grep -q '200K' "$T/show" && grep -q 'haiku' "$T/show" && grep -q 'FT_DISTILL_RECV *280000' "$T/show" && grep -q 'FT_DISTILL_BLOCK *350000' "$T/show"; } \
  && ok "① --show 200K 행 + 기준 행 280000·350000" || bad "① --show $(cat "$T/show")"
# ② opus · gpt → 기준판 그대로
for m in claude-opus-5-5 gpt-6-sol; do eq "② ft $m" "$(ft_vals $m)" "280000 330000 350000"; eq "② 훅 $m" "$(hook_vals $m 330000 280000)" "280000 330000 350000"; done
eq "② ft --model 없음" "$(FTS --get FT_DISTILL_RECV) $(FTS --get FT_DISTILL_WARN) $(FTS --get FT_DISTILL_BLOCK)" "280000 330000 350000"
# ③ 매칭 두 티어 → 파일 앞 티어
printf "$BASE$T200"'FT_DISTILL_TIER_400K_MATCH=haiku-4\nFT_DISTILL_RECV_400K=200000\nFT_DISTILL_WARN_400K=210000\nFT_DISTILL_BLOCK_400K=220000\n' > "$UF"
eq "③ 200K 앞 · haiku" "$(ft_vals claude-haiku-4-5)" "120000 140000 150000"
eq "③ 훅 200K 앞" "$(hook_vals claude-haiku-4-5 140000 120000)" "120000 140000 150000"
printf "$BASE"'FT_DISTILL_TIER_400K_MATCH=haiku-4\nFT_DISTILL_RECV_400K=200000\nFT_DISTILL_WARN_400K=210000\nFT_DISTILL_BLOCK_400K=220000\n'"$T200" > "$UF"
eq "③′ 400K 앞 · haiku" "$(ft_vals claude-haiku-4-5)" "200000 210000 220000"
# ④ 불완전 티어 → 기본 세트 + 1줄 · --set 순서 위반 REJECT rc2 · 바이트 같음
printf "$BASE"'FT_DISTILL_TIER_200K_MATCH=haiku\nFT_DISTILL_RECV_200K=120000\n' > "$UF"
v="$(FTS --get FT_DISTILL_RECV --model claude-haiku-4-5 2>"$T/e4")"
eq "④ 불완전 → 기본 RECV" "$v" "280000"
[ "$(grep -c '티어 200K 불완전 — 기본 세트' "$T/e4")" = 1 ] && ok "④ «티어 200K 불완전» 1줄" || bad "④ stderr=$(cat "$T/e4")"
eq "④ 훅 불완전 → 기본" "$(hook_vals claude-haiku-4-5 330000 280000)" "280000 330000 350000"
printf "$BASE$T200" > "$UF"; cp "$UF" "$T/before"
FTS --set FT_DISTILL_BLOCK_200K=100000 --file "$UF" >"$T/o4" 2>&1; rc=$?
{ [ $rc -eq 2 ] && grep -q REJECT "$T/o4" && cmp -s "$UF" "$T/before"; } && ok "④ --set BLOCK_200K=100000 REJECT rc2 · 바이트 같음" || bad "④ --set rc=$rc $(cat "$T/o4")"
FTS --set FT_DISTILL_BLOCK_200K=160000 --file "$UF" >/dev/null 2>&1 && grep -q '^FT_DISTILL_BLOCK_200K=160000$' "$UF" && ok "④ --set 정상 티어 값은 씀" || bad "④ --set 정상 $(cat "$UF")"
printf "$BASE$T200" > "$UF"
# ⑤ env 지금 키 명시 = 티어보다 우선
eq "⑤ env RECV=50000 · haiku" "$(FT_DISTILL_RECV=50000 ft_vals claude-haiku-4-5)" "50000 140000 150000"
eq "⑤ 훅 env RECV=50000" "$(FT_DISTILL_RECV=50000 hook_vals claude-haiku-4-5 140000 50000)" "50000 140000 150000"
# ⑥ 모델 빈 값 = 티어 없을 때와 같은 출력·rc
eq "⑥ ft --model ''" "$(ft_vals '')" "280000 330000 350000"
tj 335000 ""; HOOK warn ls >"$T/h6a" 2>"$T/e6a"; ra=$?
printf "$BASE" > "$UF"; HOOK warn ls >"$T/h6b" 2>"$T/e6b"; rb=$?
{ [ $ra = $rb ] && cmp -s "$T/h6a" "$T/h6b" && cmp -s "$T/e6a" "$T/e6b" && [ -s "$T/h6a" ]; } && ok "⑥ 훅 모델 빈 값 = 티어 없는 파일과 같음(rc=$ra)" || bad "⑥ 훅 rc $ra/$rb $(cat "$T/h6a") | $(cat "$T/h6b")"
# ⑦ 사본·샘플
L="$HERE/.."
cmp -s "$L/kit/fable-team/bin/ft-thresholds.sh" "$SKILL/scripts/ft-thresholds.sh" && ok "⑦ ft-thresholds kit=skill cmp0" || bad "⑦ ft-thresholds 사본 다름"
cmp -s "$L/kit/fable-team/templates/hooks/context-distill-gate.sh" "$SKILL/templates/hooks/context-distill-gate.sh" && ok "⑦ 훅 kit=skill cmp0" || bad "⑦ 훅 사본 다름"
S1="$L/kit/fable-team/templates/thresholds.env.sample"
{ cmp -s "$S1" "$SKILL/templates/thresholds.env.sample" && cmp -s "$S1" "$FT2/adapters/pi/thresholds.env.sample"; } && ok "⑦ 샘플 3벌 cmp0" || bad "⑦ 샘플 3벌 다름"
{ grep -q '^FT_DISTILL_TIER_200K_MATCH=haiku$' "$S1" && grep -q '^FT_DISTILL_RECV_200K=120000$' "$S1" && grep -q '^FT_DISTILL_WARN_200K=140000$' "$S1" && grep -q '^FT_DISTILL_BLOCK_200K=150000$' "$S1" \
  && grep -q '^FT_DISTILL_WARN=250000$' "$S1" && grep -q '^FT_DISTILL_BLOCK=300000$' "$S1" && grep -q '^FT_DISTILL_RECV=250000$' "$S1"; } \
  && ok "⑦ 샘플 200K 4줄 · 지금 키 값 그대로" || bad "⑦ 샘플 줄"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
