#!/usr/bin/env bash
# r1567 골 병렬 참고 모형 시험 — 기준값 ⓐ~ⓝ · 변이 M1~M8. 고정 ctx.v1 JSON + 상수 파일 · 빈 HOME.
#   timeout 70 bash feature-pack/ctx-plan/test/goal-parallel.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PLAN="$HERE/../bin/ctx-plan"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"; unset CTX_PLAN_CAP_FILE
P=0; F=0; STEP=0
step(){ echo "── $1"; STEP=$SECONDS; }
ok(){ echo "  [✓] $1 ($((SECONDS-STEP))s)"; P=$((P+1)); }
no(){ echo "  [✗] $1 — $2 ($((SECONDS-STEP))s)"; F=$((F+1)); }
chk(){ case "$2" in *"$3"*) ok "$1";; *) no "$1" "기대 문자열 없음: $3";; esac; }
nchk(){ case "$2" in *"$3"*) no "$1" "있으면 안 되는 문자열: $3";; *) ok "$1";; esac; }
rx(){ printf '%s\n' "$2" | grep -Eq "$3" && ok "$1" || no "$1" "패턴 없음: $3"; }
mutate(){ python3 -c 'import sys;s,d,o,n=sys.argv[1:5];t=open(s).read();assert o in t,"변이 지점 없음: "+o;open(d,"w").write(t.replace(o,n,1))' "$1" "$2" "$3" "$4"; }

step "픽스처 (rate 1.2761M · 상수 19키)"
cat > "$T/b.json" <<'EOF'
{"plan_input": {"schema": "ctx.v1", "window_hours": 168, "rate_claude": 1276100,
 "pools": {"claude": {"req": 100, "usage0": 0, "ctx_per_req": 1000.0, "active_hours": 10,
  "cache_reuse": 0.9, "cache_reuse_of_input": 0.8, "w_per_session_hour": 1276100, "samples": 5}}}}
EOF
CAP="$T/a.env"
printf '%s\n' FT_CAP_CLAUDE_5X=5 FT_CAP_CLAUDE_ULTRA=5 FT_CAP_CODEX_PLUS=2 FT_CAP_CODEX_PRO=1 \
  FT_CAP_DEEPSEEK_KEYS=1 FT_CAP_WK_5X_LOW=124 FT_CAP_WK_ULTRA_LOW=497 FT_CAP_WK_5X=389 \
  FT_CAP_WK_ULTRA=1555 FT_CAP_SEATS_PER_TEAM=4 FT_GOAL_TEAMS=3 FT_GOAL_TEAM_HOURS=8 \
  FT_CAP_TARGET_UTIL=0.85 FT_GOAL_PARALLEL_MAX=3 FT_BASE_ALWAYS_TEAMS=3 FT_BASE_ISSUE_TEAMS=4 \
  FT_BASE_ISSUE_HOURS=12 FT_BASE_GOAL_TEAMS=3 FT_BASE_GOAL_HOURS=12 > "$CAP"
inv(){ python3 "${1:-$PLAN}" --from "$T/b.json" --inv-file "${2:-$CAP}" --inventory 2>&1; }
I="$(inv)"; rc=$?; [ $rc -eq 0 ] && ok "inventory rc0" || no "inventory" "rc=$rc"
C="$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --capacity --accounts 5x:5,ultra:5 2>&1)"

step "ⓐ ⓑ 축 정의 머리 · 모형 1개"
chk "ⓐ 축 정의" "$I" "골 = 최대 3개 동시(오빠 11-10) · 한 골 = 팀 3 동시 × 8시간 = 24 팀-시간 = 96 세션-시간 · 골/주 = min(가용 세션-시간 ÷ 96, 3 × 168 ÷ 8)"
for s in 1_동시투입 2_팀순차 3_골직렬 "전역 직렬"; do nchk "ⓑ 옛 모형 '$s' 0" "$I$C" "$s"; done
rx "ⓑ 앵커마다 1행(2행)" "$(printf '%s\n' "$I" | grep -cE '^  (낮은|높은) 용량 가정 +[0-9]')" '^2$'

step "ⓒ ⓓ ⓔ ⓚ 앵커 두 행"
rx "ⓒ 높은 행" "$I" '^  높은 용량 가정 +8262 +6474\.4 +38\.5 +9\.6 +3\.0\(참고 상한\) +63\.0  유휴 팀 0\.6$'
rx "ⓓ 낮은 행" "$I" '^  낮은 용량 가정 +2639 +2068\.2 +12\.3 +3\.1 +1\.0 +21\.5  부족 팀 5\.9$'
chk "ⓔ 평균 라벨" "$I" "동시골(평균)"; chk "ⓔ 골/주 ≠ 동시골×21 라벨" "$I" "동시골 × 21 와 다를 수 있다"
chk "ⓚ 딱 맞음 문구 존재(코드)" "$(cat "$PLAN")" '"딱 맞음"'
nchk "ⓚ 한 행에 유휴·부족 둘 다 0" "$(printf '%s\n' "$I" | grep '유휴 팀' | grep '부족 팀')" "팀"

step "ⓕ ⓘ 요구 계정 역산"
chk "ⓕ 머리" "$I" "상시 9팀 · 36세션 = 6048 세션-시간/주 → 사용률 적용 전 7718M → 85% 적용 9080M"
chk "ⓕ 높은" "$I" "높은 용량 가정: Ultra 환산 5.84 → 실제 6장 · 5x 환산 23.34 → 실제 24장"
chk "ⓕ 낮은" "$I" "낮은 용량 가정: Ultra 환산 18.27 → 실제 19장 · 5x 환산 73.22 → 실제 74장"
N3="$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --need goals:3 2>&1)"
chk "ⓘ goals:3 = 6048" "$N3" "6048 세션-시간/주"; chk "ⓘ goals:3 표 = ⓕ" "$N3" "Ultra 환산 5.84 → 실제 6장 · 5x 환산 23.34 → 실제 24장"
nchk "ⓘ goals:3 알림 0" "$N3" "초과"
N4="$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --need goals:4 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "ⓘ goals:4 rc0" || no "ⓘ goals:4" "rc=$rc"
chk "ⓘ goals:4 그대로 8064" "$N4" "8064 세션-시간/주"; chk "ⓘ 알림 1줄" "$N4" "참고 모형 동시 골 3 초과 · 거부 아님"

step "ⓖ ⓗ ⓝ 라벨 · 경고 문구"
for s in "낙관 " "보수 " "상한(본 측정)" "하한(arch 교정)" "거부한다" "지켜야"; do nchk "ⓖⓝ '$s' 0" "$I$C$N4" "$s"; done
rx "ⓗ 끝 줄 = 용량 경고" "$(printf '%s\n' "$I" | tail -1)" '^  용량 경고: 동시팀 계산값 초과 발주는 경고만\(값 상태 미검증 · 거부 여부 = r1566\)$'
chk "ⓝ 골 모형 머리 참고 라벨" "$I" "골 모형(참고 — 운영 규칙 아님"; chk "ⓝ 기준선 머리 참고 라벨" "$I" "기준선(참고 — 운영 규칙 아님"

step "ⓙ ⓛ ⓜ 상수 키 · 기준선"
sed 's/FT_GOAL_PARALLEL_MAX=3/FT_GOAL_PARALLEL_MAX=/' "$CAP" > "$T/nog.env"
J="$(inv "$PLAN" "$T/nog.env")"
chk "ⓙ PARALLEL_MAX 빈 값 = 0순위 문제 1건" "$J" "0순위 문제 1건"; chk "ⓙ 기본 3 채움 0 = 산정 불가" "$J" "동시 골 참고값(FT_GOAL_PARALLEL_MAX)"
chk "ⓛ n 예시값 라벨" "$I" "n 예시값"; chk "ⓛ 골 작업 몫·총팀 상한" "$I" "= 4,626h · 낮 12h 기준 총팀 상한 13.8팀"
nchk "ⓛ «순간 상한» 0" "$I" "순간 상한"
chk "ⓜ 기준선 2,856h" "$I" "기준선 세션-시간 2,856h/주"; chk "ⓜ 예산 대비 44.1%" "$I" "높은 용량 가정 예산 대비 44.1%"
sed 's/FT_BASE_ISSUE_HOURS=12/FT_BASE_ISSUE_HOURS=/' "$CAP" > "$T/nob.env"
B="$(inv "$PLAN" "$T/nob.env")"
chk "ⓜ 기준선 키 빈 값 = 0순위 문제" "$B" "0순위 문제 1건"; chk "ⓜ 기준선 산정 불가" "$B" "산정 불가 — FT_BASE_ISSUE_HOURS"

step "변이 M1~M8 (각각 기준값이 FAIL 해야 한다)"
mutate "$PLAN" "$T/m1" '골주=min(team_h / max(goal_h, 1e-9), gmax * 168.0 / max(tgh, 1e-9))' '골주=team_h / max(goal_h, 1e-9)'
chk "M1 동시 상한 빼면 골/주 67.4" "$(inv "$T/m1")" " 67.4  유휴"
mutate "$PLAN" "$T/m2" 'math.ceil(m85 / wu), m85 / w5, math.ceil(m85 / w5)' 'round(m85 / wu), m85 / w5, round(m85 / w5)'
nchk "M2 반올림이면 5x 24장이 사라진다" "$(inv "$T/m2")" "23.34 → 실제 24장"
mutate "$PLAN" "$T/m3" '    return [goal_line("낮은 용량 가정"' '    return ["  1_동시투입", "  2_팀순차", "  3_골직렬"] + [goal_line("낮은 용량 가정"'
chk "M3 옛 3행이 돌아오면 검출" "$(python3 "$T/m3" --from "$T/b.json" --inv-file "$CAP" --capacity --accounts 5x:5,ultra:5 2>&1)" "3_골직렬"
mutate "$PLAN" "$T/m4" '용량 경고: 동시팀 계산값 초과 발주는 경고만(값 상태 미검증 · 거부 여부 = r1566)' '동시팀 계산값을 넘는 발주는 거부한다'
chk "M4 거부 문구가 돌아오면 검출" "$(inv "$T/m4" | tail -1)" "거부한다"
mutate "$PLAN" "$T/m5" '            f = num(inv, key)
            if f is None:' '            f = num(inv, key, 3.0 if key == "FT_GOAL_PARALLEL_MAX" else None)
            if f is None:'
nchk "M5 기본 3 채우면 산정 불가가 사라진다" "$(inv "$T/m5" "$T/nog.env")" "동시 골 참고값(FT_GOAL_PARALLEL_MAX)"
mutate "$PLAN" "$T/m6" 'seats = v * tg * spt * 168.0' 'seats = min(v, p["goal_parallel_max"]) * tg * spt * 168.0'
nchk "M6 goals:4 를 3 으로 깎으면 8064 가 사라진다" "$(python3 "$T/m6" --from "$T/b.json" --inv-file "$CAP" --need goals:4 2>&1)" "8064 세션-시간/주"
mutate "$PLAN" "$T/m7" '    v = [num(inv, k) for k in BASE_KEYS]' '    v = [num(inv, k, 12.0) for k in BASE_KEYS]'
nchk "M7 기준선 기본값 채우면 산정 불가가 사라진다" "$(inv "$T/m7" "$T/nob.env")" "산정 불가 — FT_BASE_ISSUE_HOURS"
mutate "$PLAN" "$T/m8" 'share = m["세션시간"] - always - issue' 'share = m["세션시간"] - always'
nchk "M8 이슈 몫 빼기 생략이면 13.8 이 아니다" "$(inv "$T/m8")" "총팀 상한 13.8팀"
echo ""; echo "ctx-plan goal-parallel: $P passed, $F failed"
[ $F -eq 0 ]
