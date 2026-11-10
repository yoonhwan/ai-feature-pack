#!/usr/bin/env bash
# ft-burn·ft-plan 계약 시험 — 사례 ⓐ~ⓞ · 변이 M1~M7. 격리 HOME · 실 HOME 읽기 0 · 네트워크 0.
# 부르는 법: timeout 70 bash feature-pack/ft-plan/test/contract.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PACK="$(cd "$HERE/../.." && pwd)"
BURN="$PACK/ft-burn/bin/ft-burn"; PLAN="$PACK/ft-plan/bin/ft-plan"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; unset FT_CAP_FILE
mkdir -p "$HOME/.claude/projects/p" "$HOME/.pi/agent/sessions/s" "$T/empty"
ulimit -u $(( $(ps -U "$(id -u)" -o pid= | wc -l | tr -d ' ') + 40 )) 2>/dev/null || true  # r1041
P=0; F=0; STEP=0
step(){ echo "── $1"; STEP=$SECONDS; }
ok(){ echo "  [✓] $1 ($((SECONDS-STEP))s)"; P=$((P+1)); }
no(){ echo "  [✗] $1 — $2 ($((SECONDS-STEP))s)"; F=$((F+1)); }
chk(){ case "$2" in *"$3"*) ok "$1";; *) no "$1" "기대 문자열 없음: $3";; esac; }
nchk(){ case "$2" in *"$3"*) no "$1" "있으면 안 되는 문자열: $3";; *) ok "$1";; esac; }
mutate(){ python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
assert old in t, "변이 지점 없음: " + old
open(dst, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}

step "픽스처"
python3 - "$HOME" <<'PY'
import json, os, sys, time
H = sys.argv[1]; now = time.time()
ts = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))
def u(rd, wr, ip, ou):
    return {"input_tokens": ip, "output_tokens": ou,
            "cache_read_input_tokens": rd, "cache_creation_input_tokens": wr}
with open(os.path.join(H, ".claude/projects/p/abc12345.jsonl"), "w") as f:
    for i in range(21):        # 같은 요청 21건 = 세션 표본 조건(요청 20건 이상)
        f.write(json.dumps({"timestamp": ts(now - 3600 - (i % 2) * 1800),
                            "message": {"id": "m%d" % i, "model": "claude-opus",
                                        "usage": u(1000, 20000, 500, 300)}}) + "\n")
    f.write(json.dumps({"timestamp": ts(now - 1800),      # ⓓ usage 0 = API 오류 레코드
                        "message": {"id": "z1", "model": "claude-opus", "usage": u(0, 0, 0, 0)}}) + "\n")
with open(os.path.join(H, ".pi/agent/sessions/s/2026-11-10T00-00-00-000Z_sess1.jsonl"), "w") as f:
    for i in range(2):         # i=0 → pi-other · i=1 → 모델 미상(unknown)
        m = {"usage": {"input": 10, "output": 20, "cacheRead": 30, "cacheWrite": 40}}
        if i == 0:
            m["model"] = "deepseek-v4"
        f.write(json.dumps({"timestamp": ts(now - 600), "message": m}) + "\n")
PY
ok "픽스처 생성 (claude 22건 · pi 2건)"

step "ⓐ 표본 0"
"$BURN" --hours 0.01 --project "$T/empty" --json > "$T/a.json" 2>"$T/a.err"; rc=$?
[ $rc -eq 0 ] && ok "ⓐ ft-burn rc0" || no "ⓐ ft-burn" "rc=$rc $(tail -1 "$T/a.err")"
A="$("$PLAN" --from "$T/a.json" --capacity 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓐ ft-plan --capacity rc0" || no "ⓐ ft-plan" "rc=$rc"
chk "ⓐ 표본 0 = 미산정" "$A" "미산정"
nchk "ⓐ ZeroDivision 없음" "$A" "ZeroDivision"

step "ⓑⓒⓓⓞ ft-burn --json → burn.v1"
"$BURN" --hours 168 --project "$T/empty" --json > "$T/b.json" 2>"$T/b.err"; rc=$?
[ $rc -eq 0 ] && ok "ⓞ ft-burn --json rc0" || no "ⓞ rc" "rc=$rc $(tail -1 "$T/b.err")"
JQ="$(python3 - "$T/b.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["plan_input"]
assert d["schema"] == "burn.v1", d["schema"]
req = {"req", "usage0", "ctx_per_req", "active_hours", "cache_reuse", "w_per_session_hour", "samples"}
for k, v in d["pools"].items():
    assert req <= set(v), (k, req - set(v))
c = d["pools"]["claude"]
print("pools=%s rate=%s usage0=%s ctx=%s w=%s reuse=%.4f"
      % (",".join(sorted(d["pools"])), d["rate_claude"], c["usage0"], c["ctx_per_req"],
         c["w_total"], c["cache_reuse"]))
PY
)"; [ $? -eq 0 ] && ok "ⓞ plan_input 필드 전부 있음" || no "ⓞ 필드" "$JQ"
chk "ⓓ usage0 분리 집계" "$JQ" "usage0=1"
chk "ⓓ 모델 미상 = unknown pool" "$JQ" "pi-other,unknown"
chk "ⓓ ctx/req = usage0 제외 21500" "$JQ" "ctx=21500.0"
chk "ⓒ W = 21 × 27100" "$JQ" "w=569100"
C="$("$PLAN" --from "$T/b.json" --capacity --accounts 5x:5,ultra:5 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓑ --capacity rc0" || no "ⓑ rc" "rc=$rc"
python3 - "$C" <<'PY' && ok "ⓑ 시뮬 4행 · 캐시재사용 2종" || no "ⓑ 시뮬행" "4행 아님"
import re, sys
assert len(re.findall(r"^  (실측|낭비 -\d+%) ", sys.argv[1], re.M)) == 4
assert re.search(r"\d+% \(\d+%\)", sys.argv[1])
PY
nchk "ⓑ 없는 pool 은 행 없음" "$C" "pi-claude"
chk "ⓔ 앵커 상태 표기" "$C" "미검증"
chk "ⓔ target = 운영정책" "$C" "운영정책"
chk "ⓕ --need 스케일 표" "$("$PLAN" --from "$T/b.json" --need concurrent:40 2>&1)" "필요 주간M"
chk "ⓙ 골 모형 2행" "$C" "낮은 용량 가정"
chk "ⓝ 축 정의 1줄" "$C" "메인 골 = 전역 직렬(동시 1)"
chk "ⓝ 동시골 라벨" "$C" "동시골(용량상 가능 수)"
chk "ⓔ --wk-5x 가 출력을 바꾼다" "$("$PLAN" --from "$T/b.json" --capacity --accounts 5x:1 --wk-5x 400 2>&1)" "wk_5x=400"

step "ⓖ 기존 모드 불변"
D="$("$BURN" --hours 168 --project "$T/empty" 2>&1)"
chk "ⓖ 기존 섹션 유지" "$D" "[0] Runtime environment"
nchk "ⓖ 측정 모드에 용량 출력 없음" "$D" "[capacity]"

step "ⓛ 상수 파일 자리"
FULL="$T/proj/.fable-team/state/capacity/accounts.env"; mkdir -p "${FULL%/*}"
printf '%s\n' FT_CAP_CLAUDE_5X=5 FT_CAP_CLAUDE_ULTRA=5 FT_CAP_CODEX_PLUS=2 FT_CAP_CODEX_PRO=1 \
  FT_CAP_DEEPSEEK_KEYS=1 FT_CAP_WK_5X_LOW=124 FT_CAP_WK_ULTRA_LOW=497 FT_CAP_WK_5X=389 \
  FT_CAP_WK_ULTRA=1555 FT_CAP_SEATS_PER_TEAM=4 FT_GOAL_TEAMS=3 FT_GOAL_TEAM_HOURS=8 \
  FT_CAP_TARGET_UTIL=0.85 > "$FULL"
R="$(cd "$T/proj" && "$PLAN" --from "$T/b.json" --inventory 2>&1)"
chk "ⓛ 루트 파일을 읽는다" "$R" "상수 파일: $FULL"
chk "ⓘ 상수 완비" "$R" "상수 완비"
chk "ⓘ 크리티컬 2행" "$R" "낮은 용량 가정"
chk "ⓜ 낮은 가정 = _LOW 실값 2639" "$R" "      2639"
chk "ⓜ 높은 가정 행" "$R" "높은 용량 가정"
nchk "ⓜ 옛 라벨(낙관=작은 용량) 없음" "$R" "낙관(arch"
E="$(HOME="$T/nohome" "$PLAN" --from "$T/b.json" --inventory 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓗ 상수 없음 rc0" || no "ⓗ rc" "rc=$rc"
chk "ⓗ 0순위 문제 N건" "$E" "0순위 문제"
chk "ⓗ 산정 숫자 신뢰 금지" "$E" "신뢰하지 않는다"
grep -v "_LOW" "$FULL" > "$T/nolow.env"
K="$("$PLAN" --from "$T/b.json" --inventory --inv-file "$T/nolow.env" 2>&1)"
chk "ⓚ 하한 키도 INV_KEYS" "$K" "0순위 문제 2건"
chk "ⓚ 하한 없으면 산정 불가" "$K" "산정 불가 — _LOW 키가 상수 파일에 없다"
python3 - "$T/b.json" "$T/bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["plan_input"]["schema"] = "ctx.v1"
json.dump(d, open(sys.argv[2], "w"))
PY
OUT="$("$PLAN" --from "$T/bad.json" --inventory 2>&1)"; rc=$?
[ $rc -ne 0 ] && ok "ⓞ 잘못된 계약 rc≠0" || no "ⓞ rc" "rc=$rc"
chk "ⓞ 사유 1줄" "$OUT" "계약 불일치"

step "변이 M1~M7"
mutate "$BURN" "$T/m1" '(write or 0) * W_W5M' '(write or 0) * W_W1H'
chk "M1 가중 1.25→2.0 이면 W 가 틀어진다" "$(python3 "$T/m1" --hours 168 --project "$T/empty" --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["plan_input"]["pools"]["claude"]["w_total"])')" "884100.0"
mutate "$BURN" "$T/m2" 'ctx_per_req=(tot_in / nz) if nz else 0.0,' 'ctx_per_req=(tot_in / p["req"]) if p["req"] else 0.0,'
chk "M2 usage0 을 분모에 넣으면 ctx/req 가 틀어진다" "$(python3 "$T/m2" --hours 168 --project "$T/empty" --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["plan_input"]["pools"]["claude"]["ctx_per_req"])')" "20522.7"
mutate "$PLAN" "$T/m3" 'ANCHOR_STATUS[key]' '"ok"'
nchk "M3 상태 표기를 빼면 «미검증» 이 사라진다" "$(python3 "$T/m3" --from "$T/b.json" --capacity --accounts 5x:5 2>&1 | head -3)" "미검증"
mutate "$PLAN" "$T/m4" 'if w5 is None or wu is None:' 'if False:'
nchk "M4 상한÷3 대체가 돌아오면 «산정 불가» 가 사라진다" "$(python3 "$T/m4" --from "$T/b.json" --inventory --inv-file "$T/nolow.env" 2>&1)" "산정 불가 — _LOW 키가 상수 파일에 없다"
mutate "$PLAN" "$T/m5" 'cands = [os.path.join(root, ".fable-team/state/capacity/accounts.env"), user]' 'cands = [user]'
nchk "M5 루트 파일을 빼면 머리 경로가 달라진다" "$(cd "$T/proj" && python3 "$T/m5" --from "$T/b.json" --inventory 2>&1)" "상수 파일: $FULL"
mutate "$PLAN" "$T/m6" '("낮은 용량 가정", lo5, lou)' '("낮은 용량 가정", hi5 / 3.0, hiu / 3.0)'
nchk "M6 하한을 상한÷3 으로 되돌리면 2639 가 아니다" "$(python3 "$T/m6" --from "$T/b.json" --inventory --inv-file "$FULL" 2>&1)" "      2639"
mutate "$PLAN" "$T/m7" 'bad = ci.get("schema") != SCHEMA' 'bad = False'
if python3 "$T/m7" --from "$T/bad.json" --inventory >/dev/null 2>&1; then ok "M7 계약 가드를 빼면 rc=0 이 된다(변이 검출)"; else no "M7 계약 가드" "가드를 빼도 rc≠0 — 변이 미검출"; fi

echo ""
echo "ft-plan contract: $P passed, $F failed"
[ $F -eq 0 ]
