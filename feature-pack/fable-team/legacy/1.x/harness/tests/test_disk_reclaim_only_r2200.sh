#!/usr/bin/env bash
# test_disk_reclaim_only_r2200.sh — r2200 ft-disk-reclaim.sh plan 경로 접두 거르기(FT_RECLAIM_ONLY) 반례 ②~⑥(① = r2107 · r2196 · r2199 시험 재실행).
# 입력은 mktemp 안: 가짜 뿌리(tmp · cache) · 임시 리포 1개(가짜 origin) · 가짜 lsof · tmux · du(호출 경로 기록). 실 리포 · tmux · gh 0 · sleep 0.
# 기준 = 같은 도구의 ONLY 없는 candidates.tsv 전체 목록 · FT_DISK_RECLAIM_BASE_DIR(기준판 bin 사본)가 있으면 ⑥ 을 그 판과 바이트 대조.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_DISK_RECLAIM_DIR:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; TOOL="$BIN/ft-disk-reclaim.sh"
W="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$W"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }
[ -f "$TOOL" ] || { echo "FAIL 도구 없음: $TOOL"; exit 1; }
T0=$SECONDS

FK="$W/fake"; mkdir -p "$FK/bin"
printf '#!/bin/bash\necho p1; exit 0\n' > "$FK/bin/lsof"; printf '#!/bin/bash\nexit 0\n' > "$FK/bin/tmux"
printf '#!/bin/bash\necho "${@: -1}" >> "%s"\nexec /usr/bin/du "$@"\n' "$FK/du.log" > "$FK/bin/du"
chmod +x "$FK/bin/"*
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$W/gitconfig"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
TR="$W/tmp"; CR="$W/cache"; mkdir -p "$TR/ab" "$TR/abc" "$TR/x1" "$CR/c1" "$W/A" "$W/B" "$W/C" "$W/Ax"
echo x > "$TR/ab/i"; echo x > "$TR/abc/i"; echo x > "$TR/x1/i"; echo x > "$CR/c1/i"
OLD="$(date -v-8d +%Y%m%d%H%M)"; for p in "$TR/ab" "$TR/abc" "$TR/x1"; do find "$p" -depth -exec touch -h -t "$OLD" {} +; done
export PATH="$FK/bin:$PATH" FT_RECLAIM_GH=/bin/false FT_RECLAIM_TMP_ROOT="$TR" FT_RECLAIM_CACHE_ROOT="$CR" FT_RECLAIM_INFO="" FT_RECLAIM_DF_PATH=/

git init -q --bare "$W/oR" && git clone -q "$W/oR" "$W/rR" 2>/dev/null && echo f > "$W/rR/f" && git -C "$W/rR" add f \
  && git -C "$W/rR" commit -qm c1 && git -C "$W/rR" push -q origin main; R="$W/rR"
for d in A/a1 A/a2 A/adirty B/b1 C/c1 Ax/x1; do git -C "$R" worktree add -q --detach "$W/$d" main 2>/dev/null; done
git -C "$R" worktree add -q --detach "$TR/wtT" main 2>/dev/null; echo y >> "$W/A/adirty/f"
for i in "$R"/.git/worktrees/*; do touch -t "$OLD" "$i/index"; done
ln -s "$W/A" "$W/lnA"; export FT_RECLAIM_REPOS="$R"
T1=$SECONDS

plan() { rm -f "$FK/du.log"; FT_RECLAIM_ONLY="$1" bash "$TOOL" plan "$W/$2" > /dev/null 2>&1; echo $?; }   # <ONLY> <산출 폴더>
unset FT_RECLAIM_ONLY; bash "$TOOL" plan "$W/full" > /dev/null 2>&1; FULL="$W/full/candidates.tsv"
pick() { awk -F'\t' -v ps="$1" 'BEGIN{n=split(ps,a,":")} {for(i=1;i<=n;i++) if($3==a[i] || index($3, a[i]"/")==1){print; next}}' "$FULL"; }   # 전체 목록에서 접두 아래 줄
cnt() { awk -F'\t' -v k="$2" -v p="$3" '$1==k && ($3==p || index($3, p"/")==1)' "$W/$1/candidates.tsv" | wc -l | tr -d ' '; }   # <산출> <종류> <접두>
chk "기준 전체 목록 = worktree 6 · hold 2(주 · adirty) · tmp 3 · cache 1" \
  "$(cut -f1 "$FULL" | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}')" "cache=1 hold=2 tmp=3 worktree=6 "

# ② ONLY = 리포 밖 폴더 A
rc="$(plan "$W/A" o2)"
chk "② rc 0 · A 아래 worktree 2 · hold adirty · B · C · Ax 줄 0 · tmp · cache 0" \
  "$rc|$(cnt o2 worktree "$W/A")|$(cnt o2 hold "$W/A/adirty")|$(cnt o2 worktree "$W/B")$(cnt o2 worktree "$W/C")$(cnt o2 worktree "$W/Ax")|$(cnt o2 tmp "$TR")$(cnt o2 cache "$CR")" "0|2|1|000|00"
chk "② 나온 줄 = 전체 목록의 A 아래 줄(같은 바이트 · 같은 순서)" "$(cmp -s <(pick "$W/A") "$W/o2/candidates.tsv" && echo same)" "same"
chk "② 접두 밖 du 0" "$(grep -cv -e "^$W/A/" "$FK/du.log" 2>/dev/null || true)" "0"
rc="$(plan "$W/lnA" o2l)"
chk "② 심링크 접두 = 실경로로 풂 → A 와 같은 바이트" "$rc|$(cmp -s "$W/o2/candidates.tsv" "$W/o2l/candidates.tsv" && echo same)" "0|same"
rc="$(plan "$R" o2m)"
chk "② ONLY = 주 worktree → hold 주 worktree(전체 목록 i==0)" "$rc|$(cut -f1,3,4 "$W/o2m/candidates.tsv")" "0|hold	$R	주 worktree"

# ③ ONLY = A:B
rc="$(plan "$W/A:$W/B" o3)"
chk "③ rc 0 · 나온 줄 = 전체 목록의 A · B 아래 줄(같은 바이트 · 같은 순서)" "$rc|$(cmp -s <(pick "$W/A:$W/B") "$W/o3/candidates.tsv" && echo same)|$(cnt o3 worktree "$W/B")" "0|same|1"

# ④ ONLY = tmp 뿌리
rc="$(plan "$TR" o4)"
chk "④ rc 0 · tmp 3 · cache 0 · worktree = tmp 아래 wtT 만" \
  "$rc|$(cnt o4 tmp "$TR")|$(cnt o4 cache "$CR")|$(awk -F'\t' '$1=="worktree"{print $3}' "$W/o4/candidates.tsv")" "0|3|0|$TR/wtT"
chk "④ 나온 줄 = 전체 목록의 tmp 뿌리 아래 줄" "$(cmp -s <(pick "$TR") "$W/o4/candidates.tsv" && echo same)" "same"

# ⑤ 낱말 경계
rc="$(plan "$TR/ab" o5)"
chk "⑤ ONLY = …/ab → ab 1줄 · abc 0" "$rc|$(cut -f1,3 "$W/o5/candidates.tsv")" "0|tmp	$TR/ab"
rc="$(plan "$W/A" o5b)"
chk "⑤ ONLY = …/A → …/Ax 0" "$rc|$(cnt o5b worktree "$W/Ax")$(cnt o5b hold "$W/Ax")" "0|00"

# ⑥ 없음 · 빈 값 → 전체 목록과 같은 바이트
rc="$(plan "" o6)"
chk "⑥ ONLY 빈 값 = 전체 목록 같은 바이트" "$rc|$(cmp -s "$FULL" "$W/o6/candidates.tsv" && echo same)" "0|same"
if [ -n "${FT_DISK_RECLAIM_BASE_DIR:-}" ]; then
  bash "$FT_DISK_RECLAIM_BASE_DIR/ft-disk-reclaim.sh" plan "$W/base" > /dev/null 2>&1
  chk "⑥ ONLY 없음 = 기준판 candidates.tsv 같은 바이트" "$(cmp -s "$FULL" "$W/base/candidates.tsv" && echo same)" "same"
fi
for f in ft-disk-reclaim.sh _disk_reclaim_apply.py; do   # P1 · 사전 DA ⓔ
  chk "P1 $f < 200줄 · bin = kit 같은 바이트" "$([ "$(wc -l < "$BIN/$f")" -lt 200 ] && echo y)|$(cmp -s "$BIN/$f" "$KIT/$f" && echo same)" "y|same"; done
T2=$SECONDS
echo "TIME 준비=$((T1-T0))s ②~⑥=$((T2-T1))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL count=$fail"
exit $(( fail > 0 ))
