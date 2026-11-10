#!/usr/bin/env bash
# ctx-burn·ctx-plan 계약 시험 — 사례 ⓐ~ⓞ · 변이 M1~M8 · 회귀 R1(단위)·R2(모형 상수 한 해석).
# 격리 HOME 만(실 HOME·네트워크 0).  timeout 70 bash feature-pack/ctx-plan/test/contract.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PACK="$(cd "$HERE/../.." && pwd)"
BURN="$PACK/ctx-burn/bin/ctx-burn"; PLAN="$PACK/ctx-plan/bin/ctx-plan"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; unset FT_CAP_FILE CTX_PLAN_CAP_FILE
mkdir -p "$HOME/.claude/projects/p" "$HOME/.pi/agent/sessions/s" "$T/empty"
ulimit -u $(( $(ps -U "$(id -u)" -o pid= | wc -l | tr -d ' ') + 40 )) 2>/dev/null || true  # r1041
P=0; F=0; STEP=0
step(){ echo "── $1"; STEP=$SECONDS; }
ok(){ echo "  [✓] $1 ($((SECONDS-STEP))s)"; P=$((P+1)); }
no(){ echo "  [✗] $1 — $2 ($((SECONDS-STEP))s)"; F=$((F+1)); }
chk(){ case "$2" in *"$3"*) ok "$1";; *) no "$1" "기대 문자열 없음: $3";; esac; }
nchk(){ case "$2" in *"$3"*) no "$1" "있으면 안 되는 문자열: $3";; *) ok "$1";; esac; }
mutate(){ python3 -c 'import sys;s,d,o,n=sys.argv[1:5];t=open(s).read();assert o in t,"변이 지점 없음: "+o;open(d,"w").write(t.replace(o,n,1))' "$1" "$2" "$3" "$4"; }

step "픽스처"
CAP="$T/accounts.env"                     # 상수 파일 — 자리는 부르는 쪽이 정한다(수용 기준 #2)
printf '%s\n' FT_CAP_CLAUDE_5X=5 FT_CAP_CLAUDE_ULTRA=5 FT_CAP_CODEX_PLUS=2 FT_CAP_CODEX_PRO=1 \
  FT_CAP_DEEPSEEK_KEYS=1 FT_CAP_WK_5X_LOW=124 FT_CAP_WK_ULTRA_LOW=497 FT_CAP_WK_5X=389 \
  FT_CAP_WK_ULTRA=1555 FT_CAP_SEATS_PER_TEAM=4 FT_GOAL_TEAMS=3 FT_GOAL_TEAM_HOURS=8 \
  FT_CAP_TARGET_UTIL=0.85 > "$CAP"
python3 - "$HOME" <<'PY'
import json, os, sys, time
H = sys.argv[1]; now = time.time()
ts = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))
u = lambda rd, wr, ip, ou: {"input_tokens": ip, "output_tokens": ou,
                            "cache_read_input_tokens": rd, "cache_creation_input_tokens": wr}
msg = lambda i, uu, model="claude-opus": {"id": i, "model": model, "usage": uu}
with open(os.path.join(H, ".claude/projects/p/abc12345.jsonl"), "w") as f:
    for i in range(21):   # 같은 요청 21건 = 세션 표본 조건(요청 20건 이상)
        f.write(json.dumps({"timestamp": ts(now - 3600 - (i % 2) * 1800),
                            "message": msg("m%d" % i, u(1000, 20000, 500, 300))}) + "\n")
    f.write(json.dumps({"timestamp": ts(now - 1800),   # ⓓ usage 0 = API 오류 레코드
                        "message": msg("z1", u(0, 0, 0, 0))}) + "\n")
with open(os.path.join(H, ".pi/agent/sessions/s/2026-11-10T00-00-00-000Z_sess1.jsonl"), "w") as f:
    pi = {"input": 10, "output": 20, "cacheRead": 30, "cacheWrite": 40}
    f.write(json.dumps({"timestamp": ts(now - 600), "message": {"model": "deepseek-v4", "usage": pi}}) + "\n")
    f.write(json.dumps({"timestamp": ts(now - 600), "message": {"usage": pi}}) + "\n")   # 모델 미상
PY
ok "픽스처 생성 (claude 22건 · pi 2건 · 상수 13키)"

step "ⓐ 표본 0"
"$BURN" --hours 0.01 --project "$T/empty" --json > "$T/a.json" 2>"$T/a.err"; rc=$?
[ $rc -eq 0 ] && ok "ⓐ ctx-burn rc0" || no "ⓐ ctx-burn" "rc=$rc $(tail -1 "$T/a.err")"
A="$("$PLAN" --from "$T/a.json" --inv-file "$CAP" --capacity 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓐ ctx-plan --capacity rc0" || no "ⓐ ctx-plan" "rc=$rc"
chk "ⓐ 표본 0 = 미산정" "$A" "미산정"; nchk "ⓐ ZeroDivision 없음" "$A" "ZeroDivision"

step "ⓑⓒⓓⓞ ctx-burn --json → ctx.v1"
"$BURN" --hours 168 --project "$T/empty" --json > "$T/b.json" 2>"$T/b.err"; rc=$?
[ $rc -eq 0 ] && ok "ⓞ --json rc0" || no "ⓞ rc" "rc=$rc $(tail -1 "$T/b.err")"
JQ="$(python3 - "$T/b.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["plan_input"]
assert d["schema"] == "ctx.v1", d["schema"]
need = {"req", "usage0", "ctx_per_req", "active_hours", "cache_reuse", "w_per_session_hour", "samples"}
assert all(need <= set(v) for v in d["pools"].values()), "필드 누락"
c = d["pools"]["claude"]
print("pools=%s rate=%s usage0=%s ctx=%s w=%s units=%s"
      % (",".join(sorted(d["pools"])), d["rate_claude"], c["usage0"], c["ctx_per_req"],
         c["w_total"], d["units"]["rate_claude"]))
PY
)"; [ $? -eq 0 ] && ok "ⓞ plan_input 필드 전부 있음" || no "ⓞ 필드" "$JQ"
chk "ⓓ usage0 분리 집계" "$JQ" "usage0=1"; chk "ⓓ 모델 미상 = unknown pool" "$JQ" "pi-other,unknown"
chk "ⓒ ctx/req = usage0 제외 21500" "$JQ" "ctx=21500.0"; chk "ⓒ W = 21 × 27100" "$JQ" "w=569100"
chk "R1 단위 선언 (가중토큰/세션-시간)" "$JQ" "units=weighted_tokens_per_session_hour"
C="$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --capacity --accounts 5x:5,ultra:5 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓑ --capacity rc0" || no "ⓑ rc" "rc=$rc"
python3 -c 'import re,sys;t=sys.argv[1];assert len(re.findall(r"^  (실측|낭비 -\d+%) ",t,re.M))==4;assert re.search(r"\d+% \(\d+%\)",t)' "$C" && ok "ⓑ 시뮬 4행 · 캐시재사용 2종" || no "ⓑ 시뮬행" "4행 아님"
nchk "ⓑ 없는 pool 은 행 없음" "$C" "pi-claude"
chk "ⓔ 앵커 상태 표기" "$C" "미검증"; chk "ⓔ target = 운영정책" "$C" "운영정책"; chk "ⓕ --need 스케일 표" "$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --need concurrent:40 2>&1)" "필요 주간M"
chk "ⓙ 골 모형 2행" "$C" "낮은 용량 가정"
chk "ⓝ 축 정의 1줄" "$C" "메인 골 = 전역 직렬(동시 1)"
chk "ⓝ 동시골 라벨" "$C" "동시골(용량상 가능 수)"; chk "ⓝ 참고 라벨(오빠 #278942)" "$C" "참고 — 운영 규칙 아님"
chk "ⓔ --wk-5x 가 출력을 바꾼다" "$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --capacity --accounts 5x:1 --wk-5x 400 2>&1)" "wk_5x=400"

step "ⓖ 기존 모드 불변"
D="$("$BURN" --hours 168 --project "$T/empty" 2>&1)"
chk "ⓖ 기존 섹션 유지" "$D" "[0] Runtime environment"; nchk "ⓖ 용량 출력 없음" "$D" "[capacity]"

step "ⓛⓘⓜⓚ 상수 파일 · 0순위"
R="$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --inventory 2>&1)"
chk "ⓛ --inv-file 경로를 머리에 찍는다" "$R" "상수 파일: $CAP"; chk "ⓘ 상수 완비" "$R" "상수 완비"
chk "ⓘ 크리티컬 2행" "$R" "낮은 용량 가정"; chk "ⓜ 낮은 가정 = _LOW 실값 2639" "$R" "      2639"; chk "ⓜ 높은 가정 행" "$R" "높은 용량 가정"
nchk "ⓜ 옛 라벨 없음" "$R" "낙관(arch"
chk "상한 초과 = 알림 전용(판정 4142 ⑥)" "$R" "상한 초과 = 알림 전용 · 거부·축소 0"; nchk "발주 거부 문구 없음" "$R" "발주는 거부한다"
chk "ⓛ env 경로도 받는다" "$(CTX_PLAN_CAP_FILE="$CAP" "$PLAN" --from "$T/b.json" --inventory 2>&1)" "상수 파일: $CAP"
sed 's/=.*/=/' "$CAP" > "$T/blank.env"                          # 키는 있고 값이 빈 파일
B="$("$PLAN" --from "$T/b.json" --inv-file "$T/blank.env" --inventory 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓗ 빈 값 파일 rc0" || no "ⓗ rc" "rc=$rc"; chk "ⓗ 0순위 문제 N건" "$B" "0순위 문제 13건"; chk "ⓗ 숫자 신뢰 금지" "$B" "신뢰하지 않는다"
grep -v "_LOW" "$CAP" > "$T/nolow.env"
K="$("$PLAN" --from "$T/b.json" --inv-file "$T/nolow.env" --inventory 2>&1)"
chk "ⓚ 하한 키도 INV_KEYS" "$K" "0순위 문제 2건"; chk "ⓚ 하한 없으면 산정 불가" "$K" "산정 불가 — FT_CAP_WK_5X_LOW·FT_CAP_WK_ULTRA_LOW 가 상수 파일에 없다"

step "R2 모형 상수 한 해석"; sed -e 's/FT_CAP_SEATS_PER_TEAM=4/FT_CAP_SEATS_PER_TEAM=2/' -e 's/FT_GOAL_TEAMS=3/FT_GOAL_TEAMS=2/' \
    -e 's/FT_GOAL_TEAM_HOURS=8/FT_GOAL_TEAM_HOURS=4/' "$CAP" > "$T/model.env"
M="$("$PLAN" --from "$T/b.json" --inv-file "$T/model.env" --capacity --accounts 5x:5 2>&1)"
chk "R2 머리도 2석·2팀·4h (기본값 4/3/8 아님)" "$M" "세션/팀 2석 · 팀/골 2 · 팀-시간/골 4h"
chk "R2 골 모형도 4h" "$M" "골1 = 팀 2 동시 × 4h = 8 팀-시간"; chk "R2 목표 사용률 = 파일 값" "$M" "목표 사용률 0.85"

step "R1 단위 회귀 (rate 1,000,000 토큰/h = 1.00M)"
H2="$T/h2"; mkdir -p "$H2/.claude/projects/q"
python3 - "$H2" <<'PY'
import json, os, sys, time
H = sys.argv[1]; t = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(time.time() - 600))
u = {"input_tokens": 50000, "output_tokens": 0, "cache_read_input_tokens": 0,
     "cache_creation_input_tokens": 0}
rows = [{"timestamp": t, "message": {"id": "r%d" % i, "model": "claude-opus", "usage": u}}
        for i in range(20)]
open(os.path.join(H, ".claude/projects/q/rate1m.jsonl"), "w").write(
    "\n".join(json.dumps(r) for r in rows) + "\n")
PY
HOME="$H2" "$BURN" --hours 168 --project "$T/empty" --json > "$T/rate.json" 2>/dev/null
chk "R1 픽스처 rate = 1000000" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["plan_input"]["rate_claude"])' "$T/rate.json")" "1000000"
sed -e 's/FT_CAP_CLAUDE_5X=5/FT_CAP_CLAUDE_5X=1/' -e 's/FT_CAP_CLAUDE_ULTRA=5/FT_CAP_CLAUDE_ULTRA=0/' \
    -e 's/FT_CAP_WK_5X=389/FT_CAP_WK_5X=1000/' -e 's/FT_CAP_WK_5X_LOW=124/FT_CAP_WK_5X_LOW=1000/' \
    -e 's/FT_CAP_TARGET_UTIL=0.85/FT_CAP_TARGET_UTIL=1.0/' "$CAP" > "$T/rate.env"
python3 -c 'import re,sys
t=sys.argv[1]
assert re.search(r"^  실측\s+1000\s+1000\s+25\.0 ",t,re.M),"순산: "+t[:200]
assert re.search(r"^  실측\s+168\s+1\s+1$",sys.argv[2],re.M),"역산: "+sys.argv[2][:200]' \
  "$("$PLAN" --from "$T/rate.json" --inv-file "$T/rate.env" --capacity --accounts 5x:1 2>&1)" \
  "$("$PLAN" --from "$T/rate.json" --inv-file "$T/rate.env" --need concurrent:1 2>&1)" \
  && ok "R1 순산 1000M→1000h·25.0 · 역산 concurrent:1→168M" || no "R1 단위" "100만 배 오류"

step "ⓞ 계약 검사"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["plan_input"]["schema"]="burn.v1";json.dump(d,open(sys.argv[2],"w"))' "$T/b.json" "$T/bad.json"
O="$("$PLAN" --from "$T/bad.json" --inv-file "$CAP" --inventory 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "ⓞ 잘못된 계약 rc2" || no "ⓞ rc" "rc=$rc (기대 2)"
chk "ⓞ 사유 1줄" "$O" "계약 불일치"
step "변이 M1~M8"
mutate "$BURN" "$T/m1" '(write or 0) * W_W5M' '(write or 0) * W_W1H'
chk "M1 가중 1.25→2.0 이면 W 가 틀어진다" "$(python3 "$T/m1" --hours 168 --project "$T/empty" --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["plan_input"]["pools"]["claude"]["w_total"])')" "884100.0"
mutate "$BURN" "$T/m2" 'ctx_per_req=(tot_in / nz) if nz else 0.0,' 'ctx_per_req=(tot_in / p["req"]) if p["req"] else 0.0,'
chk "M2 usage0 을 분모에 넣으면 ctx/req 가 틀어진다" "$(python3 "$T/m2" --hours 168 --project "$T/empty" --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["plan_input"]["pools"]["claude"]["ctx_per_req"])')" "20522.7"
mutate "$PLAN" "$T/m3" 'ANCHOR_STATUS[key]' '"ok"'
nchk "M3 상태 표기를 빼면 앵커 행에서 «미검증» 이 사라진다" "$(python3 "$T/m3" --from "$T/b.json" --inv-file "$CAP" --capacity --accounts 5x:5 2>&1 | grep '앵커(상태 표기 필수)')" "미검증"
mutate "$PLAN" "$T/m4" 'if w5 is None or wu is None:' 'if False:'
nchk "M4 상한÷3 대체가 돌아오면 «산정 불가» 가 사라진다" "$(python3 "$T/m4" --from "$T/b.json" --inv-file "$T/nolow.env" --inventory 2>&1)" "산정 불가 — _LOW 키가 상수 파일에 없다"
mutate "$PLAN" "$T/m6" '("낮은 용량 가정", low5, lowu)' '("낮은 용량 가정", p["wk_5x"] / 3.0, p["wk_ultra"] / 3.0)'
nchk "M6 하한을 상한÷3 으로 되돌리면 2639 가 아니다" "$(python3 "$T/m6" --from "$T/b.json" --inv-file "$CAP" --inventory 2>&1)" "      2639"
mutate "$PLAN" "$T/m7" 'bad = ci.get("schema") != SCHEMA' 'bad = False'
python3 "$T/m7" --from "$T/bad.json" --inv-file "$CAP" --inventory >/dev/null 2>&1 && ok "M7 계약 가드를 빼면 rc=0 이 된다(변이 검출)" || no "M7 계약 가드" "가드를 빼도 rc≠0"
mutate "$PLAN" "$T/m8" '상한 초과 = 알림 전용 · 거부·축소 0' '상한을 넘는 발주는 거부한다'
nchk "M8 «거부» 문구가 돌아오면 알림 전용이 사라진다" "$(python3 "$T/m8" --from "$T/b.json" --inv-file "$CAP" --inventory 2>&1 | grep "상한 초과")" "알림 전용 · 거부·축소 0"
echo ""; echo "ctx-plan contract: $P passed, $F failed"
[ $F -eq 0 ]
