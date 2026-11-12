#!/usr/bin/env bash
# test_scope_equiv_lazy_fetch_r1783.sh — r1783: 승인 대조가 partial clone 에서 원격 lazy fetch 를 부르지 않고(존재 확인만 GIT_NO_LAZY_FETCH=1),
#   범위 원장에서 «지금 리포와 같은 리포» sha 만 대조 후보로 넣는다.
#   ① partial clone · 없는 승인 sha → ERROR 문구 그대로 · GIT_TRACE 에 upload-pack·fetch 줄 0
#   ② 새 partial clone(blob 없음) · EQUIV·NOT-EQUIV 꼴 → 출력 바이트 그대로(diff 는 blob 을 받아 와야 한다 = env 를 run 전체에 넣으면 FAIL)
#   ③ 원장 byz 2 + repo=pack 2 · scope-approve --repo byz → 대조 호출 = byz 2개(최신순)
#   ④ 같은 원장 · --repo pack → 대조 호출 = pack 2개(최신순)
#   ⑤ ev 칸에 repo 없는 옛 줄 → byz 로 센다(③ 의 byz 후보 둘 중 하나는 ev 빈칸 · 하나는 equiv= 만)
# 격리: 임시 bare(원격 역할) + --filter=blob:none 클론(file://) · 임시 상태·루트 · 대조 도구 = 임시 bin 사본의 기록 stub — 실 상태·실 리포 config·외부 호출 0 · sleep 0.
# 변이·기준판 대조: FT_TEST_BIN=<다른 bin 폴더> 로 같은 시험을 돌린다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_NO_LAZY_FETCH GIT_TRACE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_BIN:-$HERE/../bin}"
fail=0; rc=0; out=""; t_start=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ===== 임시 원격(bare) + 작업 리포 =====
OR="$T/remote.git"; W="$T/w"
git init -q --bare -b main "$OR"; git -C "$OR" config uploadpack.allowFilter true
git -c init.defaultBranch=main init -q "$W"
g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
put() { printf '%s\n' "$2" > "$W/$1"; g add "$1"; g commit -qm "$1"; }
put base.txt base; g checkout -qb feat; put own.txt own1; A="$(g rev-parse HEAD)"
g checkout -q main; put m1.txt m1; M1="$(g rev-parse HEAD)"
S1="$(g checkout -q -B s1 "$A" && g merge -q --no-edit main && g rev-parse HEAD)"                       # EQUIV 꼴 = A + main 병합
g checkout -q -B s2 "$A"; g merge -q --no-commit --no-ff main >/dev/null 2>&1; echo evil > "$W/evil.txt"; g add -A; g commit -qm evilmerge; S2="$(g rev-parse HEAD)"   # NOT-EQUIV 꼴
g push -q "file://$OR" main feat s1 s2 2>/dev/null
MISS="0123456789abcdef0123456789abcdef01234567"
pclone() { git clone -q --no-checkout --filter=blob:none "file://$OR" "$1" 2>/dev/null; }
EQ() { out="$(cd "$T" && GIT_TRACE="$T/trace.$1" "$BASH" "$BIN/ft-approval-equiv.sh" "$3" "$4" --repo "$2" 2>&1)"; rc=$?; }
lazy() { grep -cE 'upload-pack|git fetch|built-in: git fetch|run_command: .*fetch' "$T/trace.$1" 2>/dev/null; }
t1=$SECONDS

# ① 없는 승인 sha → ERROR 그대로 · 원격 호출 0
C1="$T/c1"; pclone "$C1"
[ "$(git -C "$C1" config --get remote.origin.promisor)" = true ]; ck "픽스처: blob:none partial clone(promisor=true)" $?
EQ 1 "$C1" "$MISS" "$S1"
[ "$rc" = 3 ] && [ "$out" = "ERROR 승인 sha ${MISS:0:10} 객체가 이 저장소에 없음(네트워크 0 — 대조 불가·재승인)" ]; ck "① 없는 sha → ERROR 문구 그대로 rc3" $?
n="$(lazy 1)"; [ "${n:-x}" = 0 ]; ck "① GIT_TRACE upload-pack·fetch 줄 0 (받은 값: ${n:-없음})" $?
t2=$SECONDS

# ② 새 partial clone(blob 없음) · 있는 sha 두 꼴 → 출력 바이트 그대로
C2="$T/c2"; pclone "$C2"
EQ 2a "$C2" "$A" "$S1"
[ "$rc" = 0 ] && [ "$out" = "EQUIV approve=$A head=$S1 merges=1 files=1 mode=merge overlap=0 base=${M1:0:10}" ]; ck "② EQUIV 꼴 바이트 그대로(blob 은 diff 가 받아 온다)" $?
EQ 2b "$C2" "$A" "$S2"
[ "$rc" = 1 ] && [ "$out" = "NOT-EQUIV 자기 변경이 승인 때와 다름(main 대비 diff 불일치: evil.txt)" ]; ck "② NOT-EQUIV 꼴 바이트 그대로" $?
t3=$SECONDS

# ===== ③~⑤ 범위 원장 후보 =====
SB="$T/h/bin"; mkdir -p "$T/h"; cp -R "$BIN" "$SB"; cp -R "$HERE/../kit/fable-team/templates" "$T/h/templates"   # tpl_file = <bin>/../templates
cat > "$SB/ft-approval-equiv.sh" <<EOF
#!/usr/bin/env bash
printf '%s %s %s\n' "\$1" "\$2" "\$4" >> "$T/equiv.log"
echo "NOT-EQUIV stub"; exit 1
EOF
export FT_ROOT="$T/byz" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_GOAL_TABLE=0
S="$T/state"; mkdir -p "$T/byz/.fable-team" "$S" "$T/planner"
printf '#!/usr/bin/env bash\n[ "$1" = check-revert ] && { echo OK; exit 0; }\necho "CLASS docs"\n' > "$T/cls.sh"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/post.sh"
: > "$T/tbl.tsv"
export FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh" FT_SCOPE_PACK_TABLE="$T/tbl.tsv" FT_SCOPE_DDL_RECORDS="$T/tbl.tsv"
P="$T/pack"; git init -q -b main "$P"; mkdir -p "$P/feature-pack/fable-team/harness/kit/fable-team"
export FT_HARNESS_ROOT="$P/feature-pack/fable-team/harness"
T0=1800000000
a() { FT_NOW="$T0" "$BASH" "$SB/ft-autonomy.sh" "$@"; }
sha() { printf '%040x' "$1"; }
B1="$(sha 11)"; B2="$(sha 12)"; K1="$(sha 21)"; K2="$(sha 22)"
a on --for 12h >/dev/null 2>&1
grep -q ' repos=byz,pack ' "$S/autonomy.log"; ck "픽스처: 범위 승인 S1 repos=byz,pack" $?
L="$S/autonomy-scope/S1.ledger.tsv"; mkdir -p "$S/autonomy-scope"
{ printf '%s\t%s\t\tdocs\t\t\t\n' 1 "$B1"                               # 옛 줄(ev 빈칸) = byz
  printf '%s\t%s\t\tdocs\trepo=pack\t\t\n' 2 "$K1"
  printf '%s\t%s\t\tequiv\tequiv=%s\t\t\n' 3 "$B2" "$B1"                # repo 없는 ev = byz
  printf '%s\t%s\t\tdocs\trepo=pack learned=k1\t\t\n' 4 "$K2"; } > "$L"
calls() { awk '{print $1}' "$T/equiv.log" 2>/dev/null | paste -sd, -; }

: > "$T/equiv.log"; out="$(a scope-approve "$(sha 31)" 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q "^SCOPE-OK $(sha 31) class=docs " <<<"$out"; ck "③ scope-approve --repo byz(생략) SCOPE-OK" $?
c="$(calls)"; [ "$c" = "$B2,$B1" ]; ck "③⑤ byz 대조 = byz 2개(최신순 · 옛 줄 = byz) (받은 값: ${c:-없음})" $?
: > "$T/equiv.log"; out="$(a scope-approve "$(sha 32)" --repo pack 2>&1)"; rc=$?
[ "$rc" = 0 ] && grep -q "^SCOPE-OK $(sha 32) class=docs .* repo=pack$" <<<"$out"; ck "④ scope-approve --repo pack SCOPE-OK" $?
c="$(calls)"; [ "$c" = "$K2,$K1" ]; ck "④ pack 대조 = pack 2개(최신순) (받은 값: ${c:-없음})" $?
t4=$SECONDS

cmp -s "$BIN/ft_approval_equiv.py" "$BIN/../kit/fable-team/bin/ft_approval_equiv.py" && cmp -s "$BIN/ft-autonomy-scope.sh" "$BIN/../kit/fable-team/bin/ft-autonomy-scope.sh" || [ -n "${FT_TEST_BIN:-}" ]
ck "정본 미러 cmp0(bin ↔ kit)" $?
echo "단계별 초: 픽스처 $((t1 - t_start)) · ① $((t2 - t1)) · ② $((t3 - t2)) · ③④⑤ $((t4 - t3)) · 전체 $((SECONDS - t_start))"
echo "fail=$fail"; [ "$fail" = 0 ]
