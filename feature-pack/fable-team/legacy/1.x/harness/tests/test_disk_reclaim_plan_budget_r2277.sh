#!/usr/bin/env bash
# test_disk_reclaim_plan_budget_r2277.sh — r2277 ft-disk-reclaim.sh plan 반례 ①~⑥: ONLY 면 info 도 그 경로만(C1) · plan 시간 예산 «부분» 목록(C2).
# 입력은 mktemp 안: 가짜 뿌리(tmp · cache) · 임시 리포 1개(가짜 origin) · PATH 앞 가짜 du · git · lsof · tmux.
#   느린 대역 = 가짜가 env 로 켬(DU_SLOW = ONLY 밖 du 30초 · LSOF_SLEEP · GIT_MB_SLEEP = merge-base 마다 초) · 실 리포 · tmux · gh 0.
# FT_DISK_RECLAIM_BASE_DIR(기준판 bin 사본)가 있으면 ③ 을 그 판과 바이트 대조.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_DISK_RECLAIM_DIR:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; TOOL="$BIN/ft-disk-reclaim.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$W"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
[ -f "$TOOL" ] || { echo "FAIL 도구 없음: $TOOL"; exit 1; }
T0=$SECONDS

FK="$W/fake"; mkdir -p "$FK/bin"; RG="$(command -v git)"
cat > "$FK/bin/du" <<'EOF'
#!/bin/bash
p="${@: -1}"; o="${FT_RECLAIM_ONLY:-}"
if [ -n "${DU_SLOW:-}" ] && [ "$p" != "$o" ] && [ "${p#"$o"/}" = "$p" ]; then exec sleep 30; fi
exec /usr/bin/du "$@"
EOF
cat > "$FK/bin/lsof" <<'EOF'
#!/bin/bash
[ -n "${LSOF_FAIL:-}" ] && exit 1
[ -n "${LSOF_SLEEP:-}" ] && sleep "$LSOF_SLEEP"
echo p1; exit 0
EOF
printf '#!/bin/bash\n[ -n "${GIT_MB_SLEEP:-}" ] && [ "${3:-}" = merge-base ] && sleep "$GIT_MB_SLEEP"\nexec "%s" "$@"\n' "$RG" > "$FK/bin/git"
printf '#!/bin/bash\nexit 0\n' > "$FK/bin/tmux"
chmod +x "$FK/bin/"*
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
TR="$W/tmp"; CR="$W/cache"; mkdir -p "$TR/ab" "$TR/x1" "$CR/c1" "$W/band" "$W/inf"
echo x > "$TR/ab/i"; echo x > "$TR/x1/i"; echo x > "$CR/c1/i"
OLD="$(date -v-8d +%Y%m%d%H%M)"; for p in "$TR/ab" "$TR/x1"; do find "$p" -depth -exec touch -h -t "$OLD" {} +; done
export PATH="$FK/bin:$PATH" FT_RECLAIM_GH=/bin/false FT_RECLAIM_TMP_ROOT="$TR" FT_RECLAIM_CACHE_ROOT="$CR" FT_RECLAIM_DF_PATH=/
unset FT_RECLAIM_INFO FT_RECLAIM_ONLY FT_RECLAIM_PLAN_SEC

git init -q --bare "$W/oR" && git clone -q "$W/oR" "$W/rR" 2>/dev/null && echo f > "$W/rR/f" && git -C "$W/rR" add f \
  && git -C "$W/rR" commit -qm c1 && git -C "$W/rR" push -q origin main; R="$W/rR"
for i in $(seq -w 1 30); do git -C "$R" worktree add -q --detach "$W/band/w$i" main 2>/dev/null; done
git -C "$R" worktree add -q --detach "$W/small" main 2>/dev/null
for i in "$R"/.git/worktrees/*; do touch -t "$OLD" "$i/index"; done
export FT_RECLAIM_REPOS="$R"
T1=$SECONDS

# run <timeout> <산출 폴더> [env …] → «rc 초» · stdout = $W/<폴더>.out
run() { local t="$1" o="$2"; shift 2; local s; s=$(date +%s)
  env "$@" timeout "$t" bash "$TOOL" plan "$W/$o" > "$W/$o.out" 2> "$W/$o.err"; echo "$? $(( $(date +%s) - s ))"; }
cnt() { awk -F'\t' -v k="$2" '$1==k' "$W/$1/candidates.tsv" 2>/dev/null | wc -l | tr -d ' '; }

# ① ONLY = 대역 1폴더 · info 기본(FT_RECLAIM_INFO 없음) · ONLY 밖 du = 30초 → info 는 ONLY 만 · 5초 안 rc 0
read -r rc sec <<< "$(run 10 o1 DU_SLOW=1 FT_RECLAIM_ONLY="$TR/ab")"
chk "① rc 0 · 5초 안" "$rc|$([ "$sec" -le 5 ] && echo y)" "0|y"
chk "① info 줄 = ONLY 경로 1줄" "$(awk -F'\t' '$1=="info"{print $3"|"$4}' "$W/o1/candidates.tsv" 2>/dev/null)" "$TR/ab|info"
chk "① tmp ab 1줄" "$(cnt o1 tmp)" "1"
T2=$SECONDS

# ② lsof 10초 · 대역 worktree 30 · merge-base 마다 3초 · PLAN_SEC=20 → 20초대 rc 0 · 훑은 것만 · 끝 줄 «부분 n/30»
read -r rc sec <<< "$(run 35 o2 LSOF_SLEEP=10 GIT_MB_SLEEP=3 FT_RECLAIM_PLAN_SEC=20 FT_RECLAIM_INFO= FT_RECLAIM_ONLY="$W/band")"
F2="$W/o2/candidates.tsv"; n=$(( $(cnt o2 worktree) + $(cnt o2 hold) ))
chk "② rc 0 · 20초대(20~28)" "$rc|$([ "$sec" -ge 19 ] && [ "$sec" -le 28 ] && echo y)" "0|y"
chk "② 훑은 수 1~29 · 끝 줄 «부분 n/30»" "$([ "$n" -ge 1 ] && [ "$n" -lt 30 ] && echo y)|$(tail -n 1 "$F2" 2>/dev/null)" \
  "y|info	-	-	부분 $n/30 · 다음 = ONLY 좁힘"
chk "② stdout «PLAN … 부분 n/30»" "$(grep -c "^PLAN $F2 .* 부분 $n/30\$" "$W/o2.out")" "1"
chk "② «부분» 줄 1 · 나머지 줄 = 대역 worktree" "$(grep -c '부분' "$F2" 2>/dev/null)|$(grep -v '부분' "$F2" 2>/dev/null | cut -f3 | grep -cv "^$W/band/w")" "1|0"
T3=$SECONDS

# ③ 예산 안 작은 사례 → «부분» 줄 0 · 기준판과 바이트 같음
read -r rc sec <<< "$(run 30 o3 FT_RECLAIM_INFO="$W/inf")"
chk "③ rc 0 · «부분» 0" "$rc|$(grep -c '부분' "$W/o3/candidates.tsv")|$(grep -c '부분' "$W/o3.out")" "0|0|0"
if [ -n "${FT_DISK_RECLAIM_BASE_DIR:-}" ]; then
  FT_RECLAIM_INFO="$W/inf" bash "$FT_DISK_RECLAIM_BASE_DIR/ft-disk-reclaim.sh" plan "$W/base" > /dev/null 2>&1
  chk "③ 기준판 candidates.tsv 같은 바이트" "$(cmp -s "$W/o3/candidates.tsv" "$W/base/candidates.tsv" && echo same)" "same"
fi
T4=$SECONDS

# ④ lsof 실패 → «판정 불가 lsof» rc 3 · 목록 0
read -r rc sec <<< "$(run 30 o4 LSOF_FAIL=1)"
chk "④ rc 3 · stderr · 목록 0" "$rc|$(cat "$W/o4.err")|$([ -e "$W/o4/candidates.tsv" ] && echo y || echo n)" "3|판정 불가 lsof|n"

# ⑤ 줄 수 ≤ 200 · bin = kit
for f in ft-disk-reclaim.sh _disk_reclaim_plan.py; do
  chk "⑤ $f ≤ 200줄 · bin = kit" "$([ -f "$BIN/$f" ] && [ "$(wc -l < "$BIN/$f")" -le 200 ] && echo y)|$(cmp -s "$BIN/$f" "$KIT/$f" && echo same)" "y|same"; done

# ⑥ FT_RECLAIM_INFO 를 주면 ONLY 와 상관없이 그 값
read -r rc sec <<< "$(run 30 o6 FT_RECLAIM_ONLY="$TR/ab" FT_RECLAIM_INFO="$W/inf")"
chk "⑥ rc 0 · info 줄 = FT_RECLAIM_INFO" "$rc|$(awk -F'\t' '$1=="info"{print $3}' "$W/o6/candidates.tsv")" "0|$W/inf"
T5=$SECONDS
echo "TIME 준비=$((T1-T0))s ①=$((T2-T1))s ②=$((T3-T2))s ③=$((T4-T3))s ④~⑥=$((T5-T4))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit $(( fail > 0 ))
