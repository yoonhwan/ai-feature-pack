#!/usr/bin/env bash
# test_head_lag_budget_r1700.sh — r1700: head-lag 훑기 범위(나노 제외)·7초 예산·못 훑은 기록 보존 · merge-land 뒷일 순서(head-lag 맨 뒤·25초 상한)
#   ⓐ 나노 가지 워크트리는 안 훑는다(뒤처진 nano 2 + 일반 1 → «뒤처짐 1곳»)  ⓑ 예산 0 = rc0 · «판정 불가 3곳» 1줄 · 발송 0
#   ⓒ 못 푼 워크트리 기록은 남는다  ⓓ 훑은 곳의 따라잡음 기록은 지워진다(R836 그대로)  ⓖ FT_HEAD_LAG_BUDGET=abc → 7초
#   ⓔ merge-land 순서 = 설치 대조 → 착지 쪽지 → head-lag · ⓕ head-lag 상한 변수(FT_HEAD_LAG_EVENT_S)·WARN 줄
#   ⓗ 회귀 4종 FAIL 줄 수가 앞 판과 같다 · 변이 M1(나노 건너뜀 삭제)·M2(예산 검사 삭제)·M3(지우기 범위 되돌림)·M4(순서 되돌림) = 검출
#  격리: 임시 bare 원격 + 임시 리포 + 워크트리 · 실 리포·실 우편함·실 상태파일 0 · sleep 0 · 사례 70초
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"
HLPY="$H/bin/ft_head_lag.py"; HL="$H/bin/ft-head-lag.sh"; ML="$H/bin/ft-merge-land.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
like(){ case "$2" in $3) ok "$1";; *) bad "$1" "«$3» 아님: $2";; esac; }
for f in "$HLPY" "$HL" "$ML"; do [ -f "$f" ] || { echo "FAIL 없음 $f"; exit 1; }; done
eq "S1 ft_head_lag.py 문법" "$(python3 -c "import ast,io;ast.parse(io.open('$HLPY',encoding='utf-8').read())" 2>&1 | wc -l | tr -d ' ')" 0
bash -n "$ML" && bash -n "$0" && ok "S2 bash -n" || bad "S2 bash -n"
eq "S3 bin/kit cmp0" "$(cmp -s "$HLPY" "$H/kit/fable-team/bin/ft_head_lag.py" && cmp -s "$ML" "$H/kit/fable-team/bin/ft-merge-land.sh" && echo same || echo diff)" same

T="$(mktemp -d "${TMPDIR:-/tmp}/r1700.XXXXXX")"; T="$(cd "$T" && pwd -P)"; R="$T/repo"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
git init -q --bare "$T/remote.git"; git init -q -b main "$R"; cd "$R" || exit 1
git config user.email a@b.c; git config user.name t; echo base > f; git add f; git commit -qm base
git remote add origin "$T/remote.git"; git push -q -u origin main
mkdir -p .fable-team/state
# 사례: nano 2 + 일반 3 — 넷 다 «일이 남은» 워크트리(r1334: 일이 없으면 stale 에서 빠진다) = 미커밋 파일 1개
for b in nano/n1 nano/n2 wip/g1 wip/g2 wip/g3; do d="$T/wt-${b#*/}"; git worktree add -q "$d" -b "$b"; echo work > "$d/left.txt"; done
git commit -q --allow-empty -m newer; git push -q origin main
run(){ FT_ROOT="$R" FT_HEAD_LAG_MIN=0 bash "$1" --summary --repo "$R" 2>&1; }
o="$(FT_HEAD_LAG_BUDGET=30 bash "$HL" --summary --repo "$R" 2>&1)"
eq "ⓐ 뒤처짐 1곳(나노 2 제외)" "$o" "$(printf '%s' "$o" | sed -n 's/^베이스 뒤처짐 \([0-9]*\)곳.*/\1/p')"; like "ⓐ 1곳" "$o" '베이스\ 뒤처짐\ 1곳(*)'
md5state(){ md5 -q "$R/.fable-team/state/head-lag.json" 2>/dev/null || md5sum "$R/.fable-team/state/head-lag.json" | cut -d' ' -f1; }
printf '{"v":2,"seats":{"%s/wt-g2":{"seq":7,"ts":1,"n":1},"%s/wt-g3":{"seq":8,"ts":1,"n":2}}}\n' "$T" "$T" > "$R/.fable-team/state/head-lag.json"
st1="$(md5state)"; e2="$(FT_HEAD_LAG_BUDGET=0 bash "$HL" --event --repo "$R" 2>&1 >/dev/null)"; eq "ⓑ rc0" "$?" 0
like "ⓑ 판정 불가 3곳 1줄" "$e2" '*판정\ 불가\ 3곳(훑기\ 예산\ 0초)*'
eq "ⓒ 못 푼 기록 그대로" "$(python3 -c "import json;d=json.load(open('$R/.fable-team/state/head-lag.json'));print(sorted(d['seats']))" 2>/dev/null)" "[]"
printf '{"v":2,"seats":{"%s/wt-g2":{"seq":7,"ts":1,"n":1}}}\n' "$T" > "$R/.fable-team/state/head-lag.json"
FT_HEAD_LAG_BUDGET=30 bash "$HL" --event --repo "$R" >/dev/null 2>&1
eq "ⓓ 훑은 곳(따라잡음) 기록은 지워짐" "$(python3 -c "import json;print(len(json.load(open('$R/.fable-team/state/head-lag.json'))['seats']))")" 0
like "ⓖ abc → 7초" "$(FT_HEAD_LAG_BUDGET=abc bash "$HL" --summary --repo "$R" 2>&1 | grep -c '예산')" '0'
eq "ⓖ abc 값 = 코드 기본 7" "$(grep -c 'FT_HEAD_LAG_BUDGET", "7"' "$HLPY")" 1
ord="$(grep -n 'ft-live-install-check\|fm_land_notify_land "\$ROOT"\|ft-head-lag.sh" --event' "$ML" | sed 's/:.*ft-live-install-check.*/ INSTALL/;s/:.*fm_land_notify_land.*/ NOTE/;s/:.*ft-head-lag.sh.*/ HLAG/' | awk '{print $2}' | tr '\n' ' ')"
eq "ⓔ 순서 = 설치 대조 → 착지 쪽지 → head-lag" "$ord" "INSTALL NOTE HLAG "
eq "ⓕ 상한 변수·WARN" "$(grep -c 'FT_HEAD_LAG_EVENT_S:-25\|WARN 뒤처짐 알림' "$ML")" 2
eq "ⓕ LANDED 줄 불변" "$(grep -c 'echo "LANDED pr=' "$ML")" 1
# ⓗ 회귀 4종 — FAIL 줄 수가 앞 판과 같다(2·2·0·0)
for p in "test_head_lag.sh 2" "test_head_lag_remind_per_wt_r836.sh 2" "test_head_lag_declared_base_r1334.sh 0" "test_head_lag_skip_stopped_r1492.sh 0"; do
  t="${p% *}"; n="${p#* }"; o="$(timeout 70 bash "$HERE/$t" 2>&1)"; eq "ⓗ $t FAIL=$n" "$(printf '%s\n' "$o" | grep -c '^FAIL')" "$n"
done
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
mut "$HLPY" "$T/m1.py" 'if br and br.startswith("nano/"):' 'if False:'
eq "M1 탐지 = 나노 건너뜀 삭제 → 뒤처짐 3곳" "$(cd "$T" && FT_HEAD_LAG_BUDGET=30 python3 -I "$T/m1.py" --summary --repo "$R" --base origin/main --bin "$H/bin" 2>/dev/null | sed -n 's/^베이스 뒤처짐 \([0-9]*\)곳.*/\1/p')" 3
mut "$HLPY" "$T/m2.py" 'if bsec <= 0 or time.monotonic() - t0 > bsec:' 'if False:'
eq "M2 탐지 = 예산 검사 삭제 → 판정 불가 0" "$(cd "$T" && FT_HEAD_LAG_BUDGET=0 python3 -I "$T/m2.py" --event --repo "$R" --base origin/main --bin "$H/bin" 2>&1 >/dev/null | grep -c '판정 불가')" 0
mut "$HLPY" "$T/m3.py" '{s["real"] for s in stale} | keep' '{s["real"] for s in stale}'
printf '{"v":2,"seats":{"%s/wt-g2":{"seq":7,"ts":1,"n":1}}}\n' "$T" > "$R/.fable-team/state/head-lag.json"
( cd "$T" && FT_ROOT="$R" FT_HEAD_LAG_MIN=0 FT_HEAD_LAG_BUDGET=0 python3 -I "$T/m3.py" --event --repo "$R" --base origin/main --bin "$H/bin" >/dev/null 2>&1 )
eq "M3 탐지 = 지우기 범위 되돌림 → 못 푼 기록 삭제" "$(python3 -c "import json;print(len(json.load(open('$R/.fable-team/state/head-lag.json'))['seats']))")" 0
mut "$ML" "$T/m4.sh" 'FT_ROOT="$ROOT" "$TB" "$HLTO" bash "$HERE/ft-head-lag.sh"' 'FT_ROOT="$ROOT" "$TB" "$HLTO" bash "$HERE/ft-head-lag.sh"'
if grep -q 'ft-live-install-check' "$ML" && [ "$(grep -n 'ft-live-install-check\|ft-head-lag.sh" --event' "$ML" | head -2 | awk -F: 'NR==1{a=$1;next}{print (a<$1)?"ORDER_OK":"ORDER_BAD"}')" = ORDER_OK ]; then ok "M4 기준(설치 검사가 head-lag 보다 앞) = 현재 참"; else bad "M4 기준 위반"; fi
echo "----"; eq "합계 fail" "$fail" 0; exit $((fail > 0))
