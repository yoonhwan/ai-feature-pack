#!/usr/bin/env bash
# test_r560_approval_equiv_base_and_hook.sh — r560: 판정기 기준 main = «세트가 실제로 병합한 main» + 훅 판정기 자리(LIVE_BIN)·후보 순서·이유 표시 + 범위 셈 equiv 재사용.
#   축 ⓐ~ⓘ: ⓐ main 이 한 칸 더 가도 EQUIV(base=병합한 main) ⓑ 병합 커밋이 그 밖의 변경을 담음 → NOT-EQUIV ⓒ main 아닌 가지 병합 → NOT-EQUIV
#   ⓓ 병합 2번 → base = 마지막 병합의 main 쪽 부모 ⓔ 옛 main 위 rebase → EQUIV(base=merge-base(S,main)) ⓕ 훅: 남의 세트 400개 + 자기 승인 1개(가장 옛날) → EQUIV
#   ⓖ 훅: 판정기 rc≠0·stderr 이유 · 7초 초과 이유 · 마감 21초 이유 ⓗ 훅: 도구 자리가 루트 shim 폴더여도 LIVE_BIN 판정기로 EQUIV · 라이브 판정기 없음 = 거절+이유 · 로그 읽기 1곳
#   ⓘ 범위: 원장에 이미 센 승인 A 의 EQUIV = 원장 종류 equiv · used·today 증가 0 · SCOPE-OK equiv=<A>
#   ⓚ~ⓞ DA⑥ r1: ⓚ 역행 그래프(main 이 지운 파일 부활) → NOT-EQUIV ⓛ 그 꼴 + 훅 deny ⓜ 판정기 출력 잘못된 UTF-8 = deny(예외 fail-open 0) ⓝ 옛 main 위 head 직접 main push → deny ⓞ ⓚ 꼴 세트 scope-approve = class=equiv 못 받음
# 격리: 임시 git 리포(refs/remotes/origin/main 가짜 ref) + 임시 루트/상태/훅 폴더 — 실 상태·실 gh·실 슬랙·외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"
EQP="${FT_TEST_EQUIV:-$BIN/ft_approval_equiv.py}"                                  # base 대조 = 고치기 전 판정기로 같은 시험을 돌린다
GUARD="${FT_TEST_GUARD:-$ROOT/harness/kit/fable-team/templates/hooks/autonomy-merge-guard.sh}"
SCOPE_BIN="${FT_TEST_SCOPE_BIN:-$BIN}"                                             # ⓘ = 범위 도구 사본(임시 리포 안)
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/w"; g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
put() { printf '%s\n' "$2" > "$W/$1"; g add "$1"; g commit -qm "$1"; }
git -c init.defaultBranch=main init -q "$W"; put base.txt base
g checkout -qb feat; put own.txt own1; A="$(g rev-parse HEAD)"                       # 승인 세트 A
g checkout -q main; put m1.txt m1; M1="$(g rev-parse HEAD)"; g update-ref refs/remotes/origin/main "$M1"
S1="$(g checkout -q -B s1 "$A" && g merge -q --no-edit refs/remotes/origin/main && g rev-parse HEAD)"   # S1 = A + main(M1) 병합
g checkout -q main; put m2.txt m2; M2="$(g rev-parse HEAD)"; g update-ref refs/remotes/origin/main "$M2"  # main 이 한 칸 더 전진(r560 사건)
eqv() { out="$(python3 -I "$EQP" "$W" "$1" "$2" origin main 2>&1)"; rc=$?; }

bash -n "$GUARD"; ck "bash -n autonomy-merge-guard.sh" $?
python3 -m py_compile "$EQP"; ck "py_compile ft_approval_equiv.py" $?

# ⓐ 기준 main = 세트가 병합한 main
eqv "$A" "$S1"; [ "$rc" = 0 ] && has "^EQUIV " && has "base=${M1:0:10}" && ! has "base=${M2:0:10}"; ck "ⓐ main 이 한 칸 더 갔어도 EQUIV · base=병합한 main(${M1:0:8})" $?

# ⓑ 병합 커밋이 그 밖의 변경을 담음
g checkout -q -B s2 "$A"; g merge -q --no-commit --no-ff refs/remotes/origin/main >/dev/null 2>&1; echo evil > "$W/evil.txt"; g add -A; g commit -qm evilmerge; S2="$(g rev-parse HEAD)"
eqv "$A" "$S2"; [ "$rc" = 1 ] && has "^NOT-EQUIV" && ! has "^EQUIV"; ck "ⓑ 병합 커밋이 그 밖의 변경을 담음 → NOT-EQUIV(거짓 통과 0)" $?

# ⓒ main 아닌 가지 병합
g checkout -q -B oth "$A"; put oth.txt o; g checkout -q -B s3 "$A"; g merge -q --no-edit refs/remotes/origin/main >/dev/null 2>&1; g merge -q --no-edit oth >/dev/null 2>&1; S3="$(g rev-parse HEAD)"
eqv "$A" "$S3"; [ "$rc" = 1 ] && has "^NOT-EQUIV"; ck "ⓒ main 아닌 가지 병합 → NOT-EQUIV" $?

# ⓓ 병합 2번 → 기준 = 마지막 병합의 main 쪽 부모
g checkout -q -B s4 "$A"; g merge -q --no-edit "$M1" >/dev/null 2>&1; g merge -q --no-ff --no-edit refs/remotes/origin/main >/dev/null 2>&1; S4="$(g rev-parse HEAD)"
eqv "$A" "$S4"; [ "$rc" = 0 ] && has "merges=2" && has "base=${M2:0:10}"; ck "ⓓ 병합 2번 = 마지막 병합의 main 쪽 부모(${M2:0:8}) 기준 · EQUIV" $?

# ⓔ 옛 main 위로 rebase
g checkout -q -B s5 "$M1"; g cherry-pick "$A" >/dev/null 2>&1; S5="$(g rev-parse HEAD)"
eqv "$A" "$S5"; [ "$rc" = 0 ] && has "mode=rebase" && has "base=${M1:0:10}"; ck "ⓔ 옛 main 위 rebase → EQUIV mode=rebase base=merge-base(S,main)" $?

# ===== 훅 =====
IH="$T/hooks"; mkdir -p "$IH"; cp "$ROOT/harness/kit/fable-team/templates/hooks/autonomy-"*.sh "$ROOT/harness/kit/hooks/merge_cmd.py" "$IH"/   # 설치 꼴(한 폴더)
cp "$GUARD" "$IH/autonomy-merge-guard.sh"; MG="$IH/autonomy-merge-guard.sh"
R="$T/root"; S="$T/state"; AP="$S/autonomy-merge-approved"; mkdir -p "$R/.fable-team" "$S" "$T/planner"
LIVE="$T/live"; mkdir -p "$LIVE"; cp "$BIN/ft_approval_equiv.py" "$LIVE"/
printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_BIN"
export FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$S" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_HOOK_LOG="$T/hook.log" FT_AUTONOMY_SH="$BIN/ft-autonomy.sh"
a() { "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$W"; }
runh() { out="$(printf '%s' "$(mkbash "gh pr merge 7 --squash --match-head-commit $1")" | "$BASH" "$MG" 2>"$T/err")"; rc=$?; }
denied() { [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; }
a on >/dev/null 2>&1; a approve-merge "$A" >/dev/null 2>&1
[ -f "$AP/$A" ] || { echo "FAIL 픽스처 승인 파일 없음"; fail=$((fail+1)); }

# ⓕ 남의 세트 400개(최신 mtime) + 자기 승인 1개(가장 옛날)
for i in $(seq 1 400); do f="$(printf '%040x' "$((1000 + i))")"; printf 'approve-merge %s A1 1\n' "$f" > "$AP/$f"; printf 'approve-merge %s A1 1\n' "$f" >> "$S/autonomy.log"; done
touch -t 203001010000 "$AP"/* 2>/dev/null; touch -t 202001010000 "$AP/$A"
t0=$SECONDS; runh "$S1"; dt=$((SECONDS - t0))
[ "$rc" = 0 ] && [ -z "$out" ] && grep -q "EQUIV $A -> $S1" "$T/hook.log" && [ "$dt" -le 12 ]; ck "ⓕ 남의 세트 400개(최신순) + 자기 승인(가장 옛날) → EQUIV 통과 (${dt}s)" $?

# ⓖ 판정기 rc≠0 · stderr → 이유 / 7초 초과 / 마감 21초
mkj() { printf '%s\n' "$2" > "$LIVE/ft_approval_equiv.py"; chmod +x "$LIVE/ft_approval_equiv.py"; }
mkj bad '#!/usr/bin/env python3
import sys
sys.stdout.write("NOT-EQUIV 왜 안 되냐\\n"); sys.stderr.write("깨진 판정기 stderr\\n"); sys.exit(1)'
: > "$T/hook.log"; runh "$S1"; denied && has 'rc=1' && has 'stderr=깨진 판정기 stderr'; ck "ⓖ 판정기 rc≠0 → 거절 이유에 rc=1·stderr" $?
mkj slow '#!/usr/bin/env python3
import time
time.sleep(8)'
: > "$T/hook.log"; runh "$S1"; denied && has '판정기 7초 초과'; ck "ⓖ 판정기 7초 초과 → 거절 이유에 «판정기 7초 초과»" $?
for i in $(seq 1 3); do f="$(printf '%040x' "$((2000 + i))")"; printf 'approve-merge %s A1 1\n' "$f" > "$AP/$f"; printf 'approve-merge %s A1 1\n' "$f" >> "$S/autonomy.log"; done
: > "$T/hook.log"; runh "$S1"; denied && has '마감 21초'; ck "ⓖ 마감 21초 소진 → 거절 이유에 «후보 N 중 M 대조 · 마감 21초»" $?
rm -f "$AP/"$(printf '%040x' 2001) "$AP/"$(printf '%040x' 2002) "$AP/"$(printf '%040x' 2003)

# ⓗ 도구 자리 = 루트 shim 폴더(그 안 .py = bash 대리 파일) → LIVE_BIN 판정기로 EQUIV
SHIM="$T/shimdir"; mkdir -p "$SHIM"; cp "$BIN"/ft-autonomy*.sh "$SHIM"/ 2>/dev/null; cp "$BIN"/autonomy_scope*.py "$SHIM"/ 2>/dev/null
printf '#!/usr/bin/env bash\necho "ft-root-bin-shim: ft_approval_equiv.py → LIVE_BIN" >&2\nexit 2\n' > "$SHIM/ft_approval_equiv.py"
cp "$BIN/ft_approval_equiv.py" "$LIVE/ft_approval_equiv.py"
: > "$T/hook.log"; out="$(FT_AUTONOMY_SH="$SHIM/ft-autonomy.sh" bash -c 'printf "%s" "$(cat)" | bash "$0"' "$MG" <<<"$(mkbash "gh pr merge 7 --squash --match-head-commit $S1")" 2>"$T/err")"; rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && grep -q "EQUIV $A -> $S1" "$T/hook.log"; ck "ⓗ 도구 자리가 루트 shim 폴더여도 LIVE_BIN 의 진짜 판정기로 EQUIV" $?
NB="$T/nb"; mkdir -p "$NB"; cp "$BIN"/*.sh "$BIN"/autonomy_*.py "$NB"/ 2>/dev/null; rm -f "$NB/ft_approval_equiv.py"
printf '%s\n' "$T/empty-live" > "$R/.fable-team/LIVE_BIN"; mkdir -p "$T/empty-live"
runh2() { out="$(FT_AUTONOMY_SH="$NB/ft-autonomy.sh" bash -c 'printf "%s" "$(cat)" | bash "$0"' "$MG" <<<"$(mkbash "gh pr merge 7 --squash --match-head-commit $S1")" 2>"$T/err")"; rc=$?; }
runh2; denied && has '라이브 판정기 없음'; ck "ⓗ LIVE_BIN·도구 폴더 모두 판정기 없음 → 거절 + «라이브 판정기 없음»" $?
printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_BIN"
n="$(grep -c 'open(self.logpath' "$MG")"; [ "$n" = 1 ] && ! sed -n '/for a in/,/return False/p' "$MG" | grep -q 'open(self.logpath'; ck "ⓗ autonomy.log 를 여는 자리 1곳(후보 순회 안에서 다시 읽지 않음)" $?

# ===== ⓘ 범위 셈: 이미 센 승인 A 의 EQUIV = 재승인 아님 =====
SR="$T/srepo"; git -c init.defaultBranch=main init -q "$SR"
sg() { git -C "$SR" -c user.email=t@t -c user.name=t "$@"; }
sput() { printf '%s\n' "$2" > "$SR/$1"; sg add "$1"; sg commit -qm "$1"; }
sput base.txt base; sg checkout -qb f; sput own.txt own1; SA="$(sg rev-parse HEAD)"
sg checkout -q main; sput sm1.txt m1; SM1="$(sg rev-parse HEAD)"; sg update-ref refs/remotes/origin/main "$SM1"
SS="$(sg checkout -q -B sf "$SA" && sg merge -q --no-edit refs/remotes/origin/main && sg rev-parse HEAD)"
mkdir -p "$SR/harness"; cp -R "$SCOPE_BIN" "$SR/harness/bin"
cat > "$T/stub-classify.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = check-revert ] && { echo OK; exit 0; }
echo "CLASS docs"; exit 0
EOF
cat > "$T/stub-post.sh" <<'EOF'
#!/usr/bin/env bash
echo "SLACK-TS 1800000000.000100"; exit 0
EOF
export FT_SCOPE_CLASSIFY="$T/stub-classify.sh" FT_SCOPE_SLACK_POST="$T/stub-post.sh"
rm -rf "$S"; mkdir -p "$S"
sa() { FT_ROOT="$SR" "$BASH" "$SR/harness/bin/ft-autonomy.sh" "$@"; }
sr() { out="$(sa "$@" 2>&1)"; rc=$?; }
sa on >/dev/null 2>&1; sa approve-scope --for 10h --max 5 --classes docs >/dev/null 2>&1
sr scope-approve "$SA"; [ "$rc" = 0 ] && has 'SCOPE-OK .* used=1/5'; ck "ⓘ 픽스처: A 승인 = used=1/5" $?
sr scope-approve "$SS"; [ "$rc" = 0 ] && has 'class=equiv' && has "equiv=$SA" && has 'used=1/5'; ck "ⓘ A 의 EQUIV(승인 위 main 병합만) = class=equiv · used 그대로 1/5" $?
sr scope-status; has '1/5' && has '오늘 1/'; ck "ⓘ 하루 셈도 그대로(오늘 1)" $?
tail -1 "$S/autonomy-scope/S1.ledger.tsv" 2>/dev/null | awk -F'\t' '{exit !($4=="equiv")}'; ck "ⓘ 원장 줄 종류 = equiv" $?

# ===== DA⑥ r1 (2026-10-20 HOLD 재검토) ⓚ~ⓞ =====
# ⓚ DA 그래프 꼴: main B─M1─M2(M2 가 gone.txt 삭제) · A = gone.txt 수정 · U = A↔M2 병합(삭제된 파일을 A 판으로 되살림) · S = U 에 «옛 main(M1)» 병합 = 역행 그래프
#    기준 main = merge-base(S, origin/main) = M2 이므로 merge-tree(A,M2) 의 modify/delete 충돌이 드러난다(옛 판 mx=M1 이면 되살림이 통과).
W2="$T/w2"; g2() { git -C "$W2" -c user.email=t@t -c user.name=t "$@"; }
p2() { printf '%s\n' "$2" > "$W2/$1"; g2 add "$1"; g2 commit -qm "$1"; }
git -c init.defaultBranch=main init -q "$W2"; p2 keep.txt k; p2 gone.txt gone; B2="$(g2 rev-parse HEAD)"
g2 checkout -qb feat2; printf 'own-gone\n' > "$W2/gone.txt"; g2 add gone.txt; g2 commit -qm own2; A2="$(g2 rev-parse HEAD)"
g2 checkout -q main; p2 m1.txt m1; M1B="$(g2 rev-parse HEAD)"; g2 rm -q gone.txt; g2 commit -qm "main deletes gone.txt"; M2B="$(g2 rev-parse HEAD)"
g2 update-ref refs/remotes/origin/main "$M2B"
g2 checkout -qb u "$A2"; g2 merge -q --no-commit "$M2B" >/dev/null 2>&1; printf 'own-gone\n' > "$W2/gone.txt"; g2 add gone.txt; g2 commit -qm U >/dev/null 2>&1
g2 checkout -q -B s HEAD; g2 merge -q --no-edit "$M1B" >/dev/null 2>&1; S6="$(g2 rev-parse HEAD)"
j2() { out="$(python3 -I "$EQP" "$W2" "$1" "$2" origin main 2>&1)"; rc=$?; }
j2 "$A2" "$S6"; [ "$rc" = 1 ] && has '^NOT-EQUIV'; ck "ⓚ 역행 그래프(main 이 지운 gone.txt 를 되살린 S) → NOT-EQUIV(거짓 EQUIV 0)" $?

a approve-merge "$A2" >/dev/null 2>&1; : > "$T/hook.log"
runh3() { out="$(cd "$W2" && printf '%s' "$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$W2")" | "$BASH" "$MG" 2>"$T/err")"; rc=$?; }
runh3 "gh pr merge 8 --squash --match-head-commit $S6"; denied && has '재승인 필요'; ck "ⓛ 역행 그래프 head(남의 승인 A2 만 등록) → 훅 deny" $?
: > "$T/hook.log"; runh3() { out="$(cd "$W2" && printf '%s' "$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$W2")" | "$BASH" "$MG" 2>"$T/err")"; rc=$?; }
a approve-merge "$A2" >/dev/null 2>&1; rm -f "$AP/$A"
runh3 "gh pr merge 8 --squash --match-head-commit $S6"; denied && has '재승인 필요'; ck "ⓛ 역행 그래프 세트(남의 승인만 등록) → 훅 deny" $?

mkj bad8 "#!/usr/bin/env python3
import sys
sys.stdout.buffer.write(b'EQUIV \xff\xfe broken\\n'); sys.exit(3)"
: > "$T/hook.log"; runh "$S1"; denied && has 'rc=3'; ck "ⓜ 판정기 출력이 잘못된 UTF-8 + rc3 → 훅 deny(예외로 새서 허용 0)" $?
mkj real2 "#!/usr/bin/env python3
raise RuntimeError('판정기 내부 오류')"
: > "$T/hook.log"; runh "$S1"; denied && has 'rc=1' && has 'Traceback'; ck "ⓜ 판정기 내부 예외(트레이스백) → 훅 deny + 이유에 stderr 첫 줄" $?
cp "$BIN/ft_approval_equiv.py" "$LIVE/ft_approval_equiv.py"

cd "$W2" && git checkout -q s 2>/dev/null
g checkout -q -B oldmain "$A"; echo own-old > "$W/ownold.txt"; g add -A; g commit -qm oldmain; g2 checkout -q main 2>/dev/null
runh5() { out="$(cd "$W" && printf '%s' "$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$W")" | "$BASH" "$MG" 2>"$T/err")"; rc=$?; }
a approve-merge "$A" >/dev/null 2>&1; g checkout -q s5; OLDH="$(g rev-parse HEAD)"
runh5 "git push origin HEAD:main"; denied && has 'main 이 head 의 조상이 아님'; ck "ⓝ 옛 main 위 head 직접 main push → deny" $?
g checkout -q -B s5ok refs/remotes/origin/main; echo ok > "$W/okpush.txt"; g add -A; g commit -qm okpush
a approve-merge "$(g rev-parse HEAD)" >/dev/null 2>&1; runh5 "git push origin HEAD:main"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓝ 최신 main 을 품은 승인 head 직접 push 는 통과(막지 않음)" $?

cd "$SR" && sg checkout -q -B reg "$SA" && sg merge -q --no-commit "refs/remotes/origin/main" >/dev/null 2>&1 && { printf 'own\n' > "$SR/own.txt"; sg add -A; sg commit -qm U; }; SREG="$(sg rev-parse HEAD)"
sr scope-approve "$SREG"; [ "$rc" = 0 ] && ! has 'class=equiv' && has 'used=2/5'; ck "ⓞ 역행 꼴 세트는 class=equiv 비차감을 못 받음(일반 셈 used=2/5)" $?

# ✅ 마무리 — 남의 파일 손대지 않았나(정본 미러 cmp0) + 기존 시험은 따로(ⓙ = evidence)
cmp -s "$BIN/ft_approval_equiv.py" "$ROOT/harness/kit/fable-team/bin/ft_approval_equiv.py" && cmp -s "$BIN/ft-autonomy-scope.sh" "$ROOT/harness/kit/fable-team/bin/ft-autonomy-scope.sh"; ck "ⓙ 정본 미러 cmp0(harness/bin ↔ kit)" $?
echo "fail=$fail"; [ "$fail" = 0 ]
