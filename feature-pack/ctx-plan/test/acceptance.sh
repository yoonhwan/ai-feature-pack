#!/usr/bin/env bash
# r1564 수용 기준 시험 (arch#279 표 1~8 · 느슨한 연결 + 설치 가드). 각 행 = 검사 + 변이.
# 격리 HOME 만(실 HOME·네트워크 0).  timeout 70 bash feature-pack/ctx-plan/test/acceptance.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PACK="$(cd "$HERE/../.." && pwd)"
BURN="$PACK/ctx-burn/bin/ctx-burn"; PLAN="$PACK/ctx-plan/bin/ctx-plan"
WCHK="$PACK/fable-team/skill/scripts/ft-waste-check.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; unset FT_CAP_FILE CTX_PLAN_CAP_FILE
mkdir -p "$HOME/.claude/projects/h" "$T/empty" "$T/bin"
ulimit -u $(( $(ps -U "$(id -u)" -o pid= | wc -l | tr -d ' ') + 40 )) 2>/dev/null || true  # r1041
P=0; F=0; STEP=0
step(){ echo "── $1"; STEP=$SECONDS; }
ok(){ echo "  [✓] $1 ($((SECONDS-STEP))s)"; P=$((P+1)); }
no(){ echo "  [✗] $1 — $2 ($((SECONDS-STEP))s)"; F=$((F+1)); }
chk(){ case "$2" in *"$3"*) ok "$1";; *) no "$1" "기대 문자열 없음: $3";; esac; }
nchk(){ case "$2" in *"$3"*) no "$1" "있으면 안 되는 문자열: $3";; *) ok "$1";; esac; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "기대 $3 · 실제 $2"; }
mutate(){ python3 -c 'import sys;s,d,o,n=sys.argv[1:5];t=open(s).read();assert o in t,"변이 지점 없음: "+o;open(d,"w").write(t.replace(o,n,1))' "$1" "$2" "$3" "$4"; }

step "픽스처 (계약 JSON + 상수 + ctx-burn 픽스처 로그)"
CAP="$T/accounts.env"
printf '%s\n' FT_CAP_CLAUDE_5X=1 FT_CAP_CLAUDE_ULTRA=0 FT_CAP_WK_5X_LOW=124 FT_CAP_WK_ULTRA_LOW=497 \
  FT_CAP_WK_5X=389 FT_CAP_WK_ULTRA=1555 FT_CAP_CODEX_PLUS=2 FT_CAP_CODEX_PRO=1 \
  FT_CAP_DEEPSEEK_KEYS=1 FT_CAP_SEATS_PER_TEAM=4 FT_GOAL_TEAMS=3 FT_GOAL_TEAM_HOURS=8 \
  FT_CAP_TARGET_UTIL=0.85 > "$CAP"
python3 - "$HOME" "$T" <<'PY'
import json, os, sys, time
H, T = sys.argv[1], sys.argv[2]; now = time.time()
ts = lambda t: time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))
u = {"input_tokens": 500, "output_tokens": 300, "cache_read_input_tokens": 20000,
     "cache_creation_input_tokens": 5000}
rows = [{"timestamp": ts(now - 900 - i * 90),
         "message": {"id": "x%d" % i, "model": "claude-opus", "usage": u}} for i in range(21)]
open(os.path.join(H, ".claude/projects/h/a.jsonl"), "w").write(
    "\n".join(json.dumps(r) for r in rows) + "\n")
PY
CTX="$(HOME="$T/home" "$BURN" --hours 168 --project "$T/empty" --json 2>/dev/null)"
printf '%s' "$CTX" > "$T/b.json"
chk "픽스처: 계약 schema" "$CTX" '"schema": "ctx.v1"'

step "1행 느슨함 — bin·install.sh 에 하네스·홈 경로 문자열 0"
for f in "$PLAN" "$PACK/ctx-plan/install.sh"; do
  eq "1: $(basename "$f") 에 .fable-team/~/.claude 0건" "$(grep -c '\.fable-team\|~/.claude\|/\.claude/' "$f")" "0"
done
cp "$PLAN" "$T/back.py"                       # 변이: 상위 탐색 되살리기
python3 - "$T/back.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
t = t.replace('def inv_path(a):',
              'def _walk():\n    d = os.getcwd()\n    while True:\n'
              '        c = os.path.join(d, ".fable-team/state/capacity/accounts.env")\n'
              '        if os.path.isfile(c):\n            return c\n'
              '        if os.path.dirname(d) == d:\n            return ""\n        d = os.path.dirname(d)\n\n\ndef inv_path(a):')
t = t.replace('    return a.inv_file or os.environ.get("CTX_PLAN_CAP_FILE", "")',
              '    return a.inv_file or os.environ.get("CTX_PLAN_CAP_FILE", "") or _walk()')
open(p, "w").write(t)
PY
eq "1 변이: 탐색을 되살리면 문자열이 생긴다" "$(grep -c '\.fable-team' "$T/back.py")" "1"

step "2행 느슨함 — 상수 파일 경로는 --inv-file · CTX_PLAN_CAP_FILE 둘뿐"
mkdir -p "$T/cwd/.fable-team/state/capacity"; cp "$CAP" "$T/cwd/.fable-team/state/capacity/accounts.env"
OUT="$(cd "$T/cwd" && "$PLAN" --from "$T/b.json" --inventory 2>&1)"; rc=$?
eq "2: cwd/.fable-team 파일은 읽지 않는다 (rc3)" "$rc" "3"
chk "2: 가드 1줄" "$OUT" "상수 파일 없음"
eq "2: 표·계산 출력 0" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "1"
chk "2: --inv-file 로 주면 읽는다" "$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --inventory 2>&1)" "상수 파일: $CAP"
chk "2: env 로 주면 읽는다" "$(CTX_PLAN_CAP_FILE="$CAP" "$PLAN" --from "$T/b.json" --inventory 2>&1)" "상수 파일: $CAP"
python3 - "$T/back.py" "$T/m2.py" <<'PY'
import sys
t = open(sys.argv[1]).read()
t = t.replace('    return a.inv_file or os.environ.get("CTX_PLAN_CAP_FILE", "") or _walk()',
              '    return a.inv_file or os.environ.get("CTX_PLAN_CAP_FILE", "") or os.path.expanduser("~/.claude/fable-team/state/capacity/accounts.env")')
open(sys.argv[2], "w").write(t)
PY
mkdir -p "$HOME/.claude/fable-team/state/capacity"; cp "$CAP" "$HOME/.claude/fable-team/state/capacity/accounts.env"
eq "2 변이: 홈 후보를 되살리면 그 파일을 읽어 rc0" "$(python3 "$T/m2.py" --from "$T/b.json" --inventory >/dev/null 2>&1; echo $?)" "0"
rm -f "$HOME/.claude/fable-team/state/capacity/accounts.env"

step "3행 느슨함 — 입력은 ctx.v1 JSON 하나 · ctx-burn 실행 0"
eq "3: bin 에 subprocess 0" "$(grep -c 'subprocess' "$PLAN")" "0"
OUT="$("$PLAN" --from "$T/b.json" --inv-file "$CAP" --inventory 2>&1)"; rc=$?
eq "3: 정상 계약 rc0" "$rc" "0"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["plan_input"]["schema"]="burn.v1";json.dump(d,open(sys.argv[2],"w"))' "$T/b.json" "$T/bad.json"
OUT="$("$PLAN" --from "$T/bad.json" --inv-file "$CAP" --inventory 2>&1)"; rc=$?
eq "3: schema≠ctx.v1 → rc2" "$rc" "2"
eq "3: 사유 1줄" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "1"
chk "3: 사유 문구" "$OUT" "계약 불일치"
mutate "$PLAN" "$T/m3.py" 'bad = ci.get("schema") != SCHEMA' 'bad = False'
eq "3 변이: 검사를 빼면 rc0" "$(python3 "$T/m3.py" --from "$T/bad.json" --inv-file "$CAP" --inventory >/dev/null 2>&1; echo $?)" "0"

step "4·5행 하네스 — 설치된 ctx-burn 만 · 미설치면 skip rc0"
SYS="/usr/bin:/bin:$HOME/../..//opt/homebrew/bin"                    # python3 는 있고 ctx-burn 은 없는 PATH
SYS="/usr/bin:/bin:$(dirname "$(command -v python3)")"
cp "$BURN" "$T/bin/ctx-burn"                                          # PATH 에 «설치된» ctx-burn
CK="$HOME/Project/ai-feature-pack/feature-pack/ctx-burn/bin/ctx-burn"  # 체크아웃 자리에도 실행본을 둔다(R5)
mkdir -p "${CK%/*}"; cp "$BURN" "$CK"; chmod 755 "$CK"
OUT="$(cd "$T/empty" && PATH="$SYS" "$WCHK" --hours 1 2>&1)"; rc=$?
eq "5: 미설치 PATH → rc0" "$rc" "0"
chk "5: skip 1줄(느슨한 연결)" "$OUT" "WASTE skip (ctx-burn 미설치 — 느슨한 연결)"
eq "4: 체크아웃에 실행본이 있어도 부르지 않는다(1줄)" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "1"
OUT="$(cd "$T/empty" && PATH="$T/bin:$SYS" "$WCHK" --hours 1 2>&1)"; rc=$?
eq "4: PATH 설치본이면 실행된다" "$rc" "0"
chk "4: 실행 결과가 나온다(skip 아님)" "$(printf '%s' "$OUT" | grep -c 'WASTE \(ok\|warn\|critical\)')" "1"
mutate "$WCHK" "$T/w4.sh" 'CW="$(command -v ctx-burn 2>/dev/null || true)"' 'CW="$(command -v ctx-burn 2>/dev/null || echo "$HOME/Project/ai-feature-pack/feature-pack/ctx-burn/bin/ctx-burn")"'
M4="$(cd "$T/empty" && PATH="$SYS" bash "$T/w4.sh" --hours 1 2>&1)"
eq "4 원본: 체크아웃 실행본 호출 0회(skip)" "$(printf '%s' "$M4" | grep -c 'WASTE skip')" "0"
chk "4 변이: 체크아웃 후보를 되살리면 실제로 부른다" "$(printf '%s' "$M4" | grep -c 'WASTE \(ok\|warn\|critical\)')" "1"
step "6행 가드 — 상수 파일 없으면 rc3 + 1줄 · 표 0"
OUT="$(HOME="$T/nohome" "$PLAN" --from "$T/b.json" --capacity 2>&1)"; rc=$?
eq "6: 빈 HOME·인자 없음 → rc3" "$rc" "3"
eq "6: 1줄만" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "1"
chk "6: 안내 문구" "$OUT" "ctx-plan: 상수 파일 없음 — --inv-file 또는 CTX_PLAN_CAP_FILE (install.sh 참고)"
for m in --capacity --need\ concurrent:1 --scales\ 1.0 --inventory; do
  eq "6: $m 도 표 0" "$(HOME="$T/nohome" "$PLAN" --from "$T/b.json" $m 2>&1 | wc -l | tr -d ' ')" "1"
done
mutate "$PLAN" "$T/m6.py" 'if not (path and os.path.isfile(path)):' 'if False:'
eq "6 변이: 가드를 빼면 기본값으로 계산해 rc0" "$(HOME="$T/nohome" python3 "$T/m6.py" --from "$T/b.json" --capacity 2>&1 >/dev/null; echo $?)" "0"

step "7행 가드 유지 — 키는 있고 값이 빈 파일 = 0순위 문제(기본값 대체 0)"
sed 's/=.*/=/' "$CAP" > "$T/blank.env"
OUT="$("$PLAN" --from "$T/b.json" --inv-file "$T/blank.env" --inventory 2>&1)"; rc=$?
eq "7: rc0" "$rc" "0"
chk "7: 0순위 문제 13건" "$OUT" "0순위 문제 13건"
chk "7: 기본값 대체 없음(산정 불가)" "$("$PLAN" --from "$T/b.json" --inv-file "$T/blank.env" --capacity --accounts 5x:1 2>&1)" "기본값 대체 0"

step "R4 (기준7) 빈 값 = 산정 불가 — 예외 0 · 0 대체 금지"
sed 's/FT_CAP_TARGET_UTIL=0.85/FT_CAP_TARGET_UTIL=/' "$CAP" > "$T/notarget.env"
O="$(HOME="$T/home" "$PLAN" --from "$T/b.json" --inv-file "$T/notarget.env" --capacity --accounts 5x:5 2>&1)"; rc=$?
eq "R4a: TARGET_UTIL 빈 값 → rc0(예외 0)" "$rc" "0"
chk "R4a: 정원 산정 불가" "$O" "정원 산정 불가 — 목표 사용률(FT_CAP_TARGET_UTIL)"
chk "R4a: 골 모형 산정 불가" "$O" "골 모형 산정 불가"; nchk "R4a: TypeError 없음" "$O" "TypeError"
sed 's/FT_CAP_WK_5X=389/FT_CAP_WK_5X=/' "$CAP" > "$T/nowk.env"
O="$(HOME="$T/home" "$PLAN" --from "$T/b.json" --inv-file "$T/nowk.env" --capacity --accounts 5x:5 2>&1)"; rc=$?
eq "R4b: WK_5X 빈 값 → rc0(예외 0)" "$rc" "0"; chk "R4b: 산정 불가 문구" "$O" "산정 불가 — 주간 5x M(FT_CAP_WK_5X)"
sed 's/FT_CAP_CLAUDE_5X=1/FT_CAP_CLAUDE_5X=/' "$CAP" > "$T/no5x.env"
O="$(HOME="$T/home" "$PLAN" --from "$T/b.json" --inv-file "$T/no5x.env" --inventory 2>&1)"; rc=$?
eq "R4c: CLAUDE_5X 빈 값 → rc0" "$rc" "0"; chk "R4c: 구독 상수 산정 불가" "$O" "구독 상수: 산정 불가 — FT_CAP_CLAUDE_5X"
nchk "R4c: 0장으로 대체하지 않는다" "$O" "5x 0 + Ultra"
mutate "$PLAN" "$T/m9.py" 'gone = missing(p, GOAL_NEED)' 'gone = []'
nchk "R4 변이1(골 경로 가드 제거): 산정 불가가 사라진다" "$(python3 "$T/m9.py" --from "$T/b.json" --inv-file "$T/notarget.env" --capacity --accounts 5x:5 2>&1)" "골 모형 산정 불가"
mutate "$PLAN" "$T/m10.py" 'num(inv, "FT_CAP_CLAUDE_5X"), num(inv, "FT_CAP_CLAUDE_ULTRA")' 'num(inv, "FT_CAP_CLAUDE_5X", 0.0), num(inv, "FT_CAP_CLAUDE_ULTRA", 0.0)'
nchk "R4 변이2(0 대체 복원): 산정 불가가 사라진다" "$(python3 "$T/m10.py" --from "$T/b.json" --inv-file "$T/no5x.env" --inventory 2>&1)" "구독 상수: 산정 불가"

step "8행 경계 — ctx-burn 측정 원천은 HOME 주입으로 격리"
eq "8: 격리 HOME 픽스처만 집계(claude 21요청)" "$(printf '%s' "$CTX" | python3 -c 'import json,sys;print(json.load(sys.stdin)["plan_input"]["pools"]["claude"]["req"])')" "21"
nchk "8: 실 HOME 세션 경로 없음" "$(grep -c 'Users/yoonhwan/.claude/projects' "$T/b.json")" "1"
echo ""; echo "ctx-plan acceptance: $P passed, $F failed"
[ $F -eq 0 ]
