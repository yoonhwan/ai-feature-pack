#!/usr/bin/env bash
# test_wt_census_r1688.sh — r1688: ft-wt-census.sh 의 칸별 판정·읽기 전용·h 안전·7초 상한·출력 꼴.
#   ⓐ 칸마다 판정(정리 가능 · 미커밋 · stash · 미착지 · squash 착지 · reflog 만 · cwd 점유 · 설정 경로 · git 실패)
#   ⓑ 도구는 읽기만(전후 worktree list·refs·stash·HEAD·status 동일) · ⓒ h 는 «정리 가능» 만 · 재판정으로 건너뜀 · --force/가지 삭제 0
#   ⓓ 한 줄 상한 초과 = 그 줄만 판정 불가(전체 계속) · ⓔ TSV 11칸 + 요약 1줄 · 변이 M1(⑤ 검사 삭제)·M2(h 재판정 삭제)·M3(git 실패를 정리 가능으로) = 검출
#  격리: 임시 bare 원격 + 임시 리포 + 사례별 워크트리 · 실 리포·실 tmux·실 라이브 쓰기 0 · sleep 은 M2 대기용 1회뿐 · 사례 70초
# 새 파일 mode 100644(실행 비트 0) — `bash <이 파일>` 로 부른다.
set -uo pipefail
# 스스로 70초 상한을 건다(멈춤 재발 방지) — 이미 안쪽이면 그대로 진행
if [ "${R1688_INNER:-0}" != 1 ] && command -v timeout >/dev/null 2>&1; then R1688_INNER=1 exec timeout 70 bash "$0" "$@"; fi
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; H="$(cd -- "$HERE/.." && pwd)"; TOOL="$H/bin/ft-wt-census.sh"
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "기대 '$3' 실제 '$2'"; }
like(){ case "$2" in $3) ok "$1";; *) bad "$1" "«$3» 아님: $2";; esac; }
[ -f "$TOOL" ] || { echo "FAIL 도구 없음 $TOOL"; exit 1; }
eq "S1 도구 ≤150줄" "$([ "$(wc -l < "$TOOL" | tr -d ' ')" -le 150 ] && echo yes || echo no)" yes
eq "S2 도구 100644" "$(stat -f %Lp "$TOOL")" 644
bash -n "$TOOL" && bash -n "$0" && ok "S3 bash -n" || bad "S3 bash -n"

T="$(mktemp -d "${TMPDIR:-/tmp}/r1688.XXXXXX")"; T="$(cd "$T" && pwd -P)"; R="$T/repo"; BUSY=""; B6=""; T0=$(date +%s)
st(){ [ "${FT_R1688_TIME:-0}" = 1 ] && echo "단계 $1 $(( $(date +%s) - T0 ))초" >&2; return 0; }
trap '[ -n "$BUSY" ] && kill "$BUSY" 2>/dev/null; [ -n "$B6" ] && kill "$B6" 2>/dev/null; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT INT TERM
export HOME="$T/home"; mkdir -p "$HOME"   # LaunchAgents glob 이 실 홈을 안 보게
git init -q --bare "$T/remote.git"; git init -q -b main "$R"; cd "$R" || exit 1
git config user.email a@b.c; git config user.name t; echo base > f.txt; git add f.txt; git commit -qm base
git remote add origin "$T/remote.git"; git push -q -u origin main
export FT_WT_CENSUS_TMUX=0 FT_WT_CENSUS_CONFIG="$R/.fable-team/seats.json"
mkdir -p "$R/.fable-team"; printf '{"cfg":"%s"}\n' "$T/wt-cfg" > "$R/.fable-team/seats.json"
git worktree add -q "$T/wt-clean" -b nano/clean
git worktree add -q "$T/wt-dirty" -b nano/dirty; echo d >> "$T/wt-dirty/f.txt"
git worktree add -q "$T/wt-stash" -b nano/stashbr; ( cd "$T/wt-stash" && echo s > s.txt && git add s.txt && git stash -q )
git worktree add -q "$T/wt-unland" -b nano/unland; ( cd "$T/wt-unland" && echo x > x.txt && git add x.txt && git commit -qm unland )
git worktree add -q "$T/wt-reflog" -b nano/reflog; ( cd "$T/wt-reflog" && echo r > r.txt && git add r.txt && git commit -qm tmp && git reset -q --hard HEAD~1 )
git worktree add -q "$T/wt-squash" -b nano/squash
( cd "$T/wt-squash" && echo q > q.txt && git add q.txt && git commit -qm sq ); git merge --squash -q nano/squash >/dev/null 2>&1 && git commit -qm "squash nano/squash" && git push -q origin main
git worktree add -q "$T/wt-cfg" -b nano/cfg
git worktree add -q "$T/wt-busy" -b nano/busy
perl -e 'chdir(shift) or die; open(my $f, ">", shift) or die; close $f; select(undef,undef,undef,60)' "$T/wt-busy" "$T/busy.ready" & BUSY=$!
for _i in $(seq 1 2000); do [ -e "$T/busy.ready" ] && break; done
git worktree add -q "$T/wt-broken" -b nano/broken; rm -f "$T/wt-broken/.git"
snap(){ { git -C "$R" worktree list --porcelain; git -C "$R" for-each-ref --format='%(refname) %(objectname)'; git -C "$R" stash list; for w in "$@" ; do echo "$w $(git -C "$w" rev-parse HEAD 2>/dev/null) $(git -C "$w" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"; done; } 2>&1; }
CASES=("$T/wt-clean" "$T/wt-dirty" "$T/wt-stash" "$T/wt-unland" "$T/wt-reflog" "$T/wt-squash" "$T/wt-cfg" "$T/wt-busy" "$T/wt-broken")
st 픽스처; B4="$(snap "${CASES[@]}")"
out="$(cd "$T" && bash "$TOOL" --repo "$R" 2>/dev/null)"; rc=$?
eq "ⓐ 실행 rc0" "$rc" 0
v(){ printf '%s\n' "$out" | awk -F'\t' -v p="$1" '$1==p{print $NF}'; }
eq "A1 정리 가능(착지)" "$(v "$T/wt-clean")" "정리 가능"
eq "A2 미커밋" "$(v "$T/wt-dirty")" "KEEP:①"
eq "A3 그 가지 stash" "$(v "$T/wt-stash")" "KEEP:①"
eq "A4 미착지" "$(v "$T/wt-unland")" "KEEP:②"
eq "A5 squash 착지" "$(v "$T/wt-squash")" "정리 가능"
eq "A6 reflog 만 닿는 커밋" "$(v "$T/wt-reflog")" "KEEP:④"
eq "A7 cwd 점유" "$(v "$T/wt-busy")" "KEEP:⑤"
eq "A8 설정이 가리킴" "$(v "$T/wt-cfg")" "KEEP:⑥"
like "A9 git 실패 = 판정 불가" "$(v "$T/wt-broken")" '판정\ 불가:*'
st ⓐⓑⓔ; eq "ⓑ 읽기만(전후 스냅샷 동일)" "$(snap "${CASES[@]}")" "$B4"
eq "ⓔ TSV 11칸" "$(printf '%s\n' "$out" | sed '$d' | awk -F'\t' 'NF!=11{n++}END{print n+0}')" 0
like "ⓔ 요약 1줄" "$(printf '%s\n' "$out" | tail -1)" '요약\ 정리\ 가능\ [0-9]*\ ·\ KEEP\ [0-9]*\(*\)*\ ·\ 판정\ 불가\ [0-9]*\(총\ [0-9]*줄\)'
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();a,b=sys.argv[3],sys.argv[4]
assert a in s, "패턴 없음: "+a
open(sys.argv[2],"w").write(s.replace(a,b,1))' "$1" "$2" "$3" "$4"; }
cat > "$T/slowgit" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do if [ "\$a" = "$T/wt-unland" ] && [ ! -e "$T/slow.once" ]; then touch "$T/slow.once"; sleep 2; fi; done
exec git "\$@"
EOF
chmod +x "$T/slowgit"
# ── 보정(arch#301 #285823): patch-id 집합 실행당 1회 · stash push -m · 바탕 수백 커밋에서 줄당 7초 ──
cat > "$T/loggit" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/gitcalls.log"
exec git "\$@"
EOF
chmod +x "$T/loggit"; : > "$T/gitcalls.log"
( cd "$T" && FT_WT_CENSUS_GIT="$T/loggit" bash "$TOOL" --repo "$R" >/dev/null 2>&1 )
eq "P1 git cherry 호출 0(줄마다 재계산 금지)" "$(grep -c ' cherry ' "$T/gitcalls.log")" 0
git worktree add -q "$T/wt-stashmsg" -b nano/stashmsg; ( cd "$T/wt-stashmsg" && echo m > m.txt && git add m.txt && git stash push -q -m "메시지 stash" )
eq "P3 stash push -m = KEEP:①" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$T/wt-stashmsg" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:①"
P="$T/perf"; git init -q --bare "$T/perf.git"; git init -q -b main "$P"
( cd "$P" && git config user.email a@b.c && git config user.name t && for i in $(seq 1 300); do echo "l$i" >> f; git add f; git commit -qm "c$i"; done
  git remote add origin "$T/perf.git"; git push -q -u origin main; git worktree add -q "$T/wt-perf" -b nano/perf12
  ( cd "$T/wt-perf" && echo p > p.txt && git add p.txt && git commit -qm "perf work" ); git cherry-pick nano/perf12 >/dev/null 2>&1; git push -q origin main )
ms(){ perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }
t1=$(ms); pv="$(cd "$T" && bash "$TOOL" --repo "$P" --only "$T/wt-perf" 2>/dev/null | awk -F'\t' '{print $NF}')"; t2=$(ms)
eq "P4 줄당 7초 안(바탕 300커밋)" "$([ $((t2-t1)) -lt 7000 ] && echo yes || echo "no($((t2-t1))ms)")" yes
# ── arch#301 r2: ③ 은 줄마다 실 sha 로 · cwd 목록은 실행당 1회 ──
git -C "$R" push -q origin nano/clean
o3="$(cd "$T" && bash "$TOOL" --repo "$R" 2>/dev/null)"
eq "P6 원격 있는 줄 ③=1(clean)" "$(printf '%s\n' "$o3" | awk -F'\t' -v p="$T/wt-clean" '$1==p{print $6}')" 1
eq "P6 원격 없는 줄 ③=0(unland)" "$(printf '%s\n' "$o3" | awk -F'\t' -v p="$T/wt-unland" '$1==p{print $6}')" 0
mkdir -p "$T/bin"; cat > "$T/bin/lsof" <<EOF
#!/usr/bin/env bash
echo x >> "$T/lsof.log"
exec /usr/sbin/lsof "\$@"
EOF
chmod +x "$T/bin/lsof"; : > "$T/lsof.log"
( cd "$T" && PATH="$T/bin:$PATH" bash "$TOOL" --repo "$R" >/dev/null 2>&1 )
eq "P7 lsof 실행당 1회(줄마다 부르지 않음)" "$(wc -l < "$T/lsof.log" | tr -d ' ')" 1
eq "P5 패치 동일 = 착지 판정(patch-id 경로)" "$pv" "정리 가능"
( cd "$P" && git worktree add -q "$T/wt-perf60" -b nano/perf60 && ( cd "$T/wt-perf60" && for i in $(seq 1 60); do echo "q$i" >> q; git add q; git commit -qm "q$i"; done ) )
t1=$(ms); v60="$(cd "$T" && bash "$TOOL" --repo "$P" --only "$T/wt-perf60" 2>/dev/null | awk -F'\t' '{print $NF}')"; t2=$(ms)
eq "P2 큰 갈래(60커밋) 줄도 7초 안 · KEEP:②" "$([ $((t2-t1)) -lt 7000 ] && echo yes || echo "no($((t2-t1))ms)")/$(case "$v60" in KEEP:②) echo KEEP;; *) echo "$v60";; esac)" "yes/KEEP"
o2="$(cd "$T" && FT_WT_CENSUS_GIT="$T/slowgit" FT_WT_CENSUS_ROW_TIMEOUT=1 bash "$TOOL" --repo "$R" 2>/dev/null)"
like "ⓓ 상한 초과 = 그 줄만 판정 불가" "$(printf '%s\n' "$o2" | awk -F'\t' -v p="$T/wt-unland" '$1==p{print $NF}')" '판정\ 불가:*초과'
eq "ⓓ 전체는 계속(다른 줄 그대로)" "$(printf '%s\n' "$o2" | awk -F'\t' -v p="$T/wt-cfg" '$1==p{print $NF}')" "KEEP:⑥"
st ⓓ; mut "$TOOL" "$T/m1.sh" 'busy "$preal" && d5=1' ':'
eq "M1 탐지 = ⑤ 삭제 → 점유 칸이 정리 가능" "$(cd "$T" && bash "$T/m1.sh" --repo "$R" --only "$T/wt-busy" 2>/dev/null | awk -F'\t' '{print $NF}')" "정리 가능"
mut "$TOOL" "$T/m3.sh" 'v="판정 불가:git 실패"' 'v="정리 가능"'
eq "M3 탐지 = git 실패를 정리 가능으로" "$(cd "$T" && bash "$T/m3.sh" --repo "$R" --only "$T/wt-broken" 2>/dev/null | awk -F'\t' '{print $NF}')" "정리 가능"
mut "$TOOL" "$T/m2.sh" 'elif [ "$(bash "$CENSUS" --only "$target" --repo "$ROOT" 2>/dev/null | awk -F"\t" "{print \$NF}")" != "정리 가능" ]; then sk_change=$((sk_change+1)); ' ''
( cd "$T" && bash "$T/m2.sh" --repo "$R" --h "$T/h2.sh" >/dev/null 2>&1 )
eq "M2 탐지 = h 재판정 삭제(재판정 호출 0줄)" "$(grep -c 'bash "$CENSUS" --only' "$T/h2.sh")" 0
st 변이; H1="$T/h1.sh"; ( cd "$T" && bash "$TOOL" --repo "$R" --h "$H1" >/dev/null 2>&1 )
eq "ⓒ h 대상 = 정리 가능 2줄" "$(grep -c '^target=' "$H1")" 2
eq "ⓒ h 에 --force·가지 삭제 0" "$(grep -v '^#' "$H1" | grep -cE '\-\-force|remove -f|branch -D|update-ref -d')" 0
echo late > "$T/wt-squash/late.txt"
hs="$(bash "$H1" 2>&1)"
eq "ⓒ 재판정으로 건너뜀" "$(printf '%s' "$hs" | grep -c '재판정 바뀜 1')" 1
eq "ⓒ 지움 1" "$(printf '%s' "$hs" | grep -c '지움 1')" 1
[ -d "$T/wt-squash" ] && ok "ⓒ 바뀐 줄은 남는다" || bad "ⓒ 바뀐 줄이 지워졌다"
eq "ⓒ 가지 삭제 0" "$(git -C "$R" branch | grep -c 'nano/')" 10
# ── DA r4 반례 R1~R6(#286094 · 기대 전부 KEEP · 미확인 = KEEP) ──
git worktree add -q "$T/wt-r1a" -b nano/r1a; ( cd "$T/wt-r1a" && git update-index --assume-unchanged f.txt && echo user >> f.txt )
eq "R1a assume-unchanged 숨은 변경" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$T/wt-r1a" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:①"
git worktree add -q "$T/wt-r1b" -b nano/r1b; ( cd "$T/wt-r1b" && git update-index --skip-worktree f.txt && echo user >> f.txt )
eq "R1b skip-worktree 숨은 변경" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$T/wt-r1b" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:①"
git worktree add -q --detach "$T/wt-r2"; ( cd "$T/wt-r2" && echo d > d.txt && git add d.txt && git stash push -q -m "detached user work" )
eq "R2 detached worktree 의 stash" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$T/wt-r2" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:①"
git worktree add -q "$T/wt-r3" -b nano/r3; printf '{"p":"%s"}\n' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]).strip(chr(34)))' "$T/wt-r3")" > "$T/r3.json"
eq "R3 JSON escape 설정 경로" "$(cd "$T" && FT_WT_CENSUS_CONFIG="$T/r3.json" bash "$TOOL" --repo "$R" --only "$T/wt-r3" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:⑥"
git worktree add -q "$T/wt-r4" -b nano/r4; ( cd "$T/wt-r4" && for i in $(seq 1 210); do git commit -q --allow-empty -m "e$i"; done; echo u > uniq.txt; git add uniq.txt; git commit -qm uniq; git reset -q --hard HEAD~211 )
eq "R4 reflog 상한 초과 = 미확인 KEEP:④" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$T/wt-r4" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:④"
eq "R4 정렬·50컷 없음" "$(grep -c 'reflog show HEAD --format=%H 2>/dev/null | sort' "$TOOL")" 0
git worktree add -q "$T/wt-r5" -b nano/r5; ( cd "$T/wt-r5" && echo m > merge-only.txt && git add merge-only.txt && git commit -qm one && git checkout -q -b r5b HEAD~1 && echo b > b.txt && git add b.txt && git commit -qm two && git checkout -q nano/r5 && git merge -q --no-ff r5b -m merge && echo m2 > merge-only2.txt && git add merge-only2.txt && git commit -q --amend --no-edit )
like "R5 merge commit 전용 변경 = KEEP(② 포함)" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$T/wt-r5" 2>/dev/null | awk -F'\t' '{print $NF}')" 'KEEP:*②*' 
A6="/tmp/r1688-alias.$$"; mkdir -p "$A6"; git -C "$R" worktree add -q "$A6" -b nano/r6 2>/dev/null
perl -e 'chdir(shift) or die; open(my $f, ">", shift) or die; close $f; select(undef,undef,undef,60)' "$A6" "$T/r6.ready" & B6=$!
for _i in $(seq 1 2000); do [ -e "$T/r6.ready" ] && break; done
eq "R6 /tmp 별칭 입력도 점유 인식" "$(cd "$T" && bash "$TOOL" --repo "$R" --only "$A6" 2>/dev/null | awk -F'\t' '{print $NF}')" "KEEP:⑤"
kill "$B6" 2>/dev/null; wait "$B6" 2>/dev/null; B6=""; git -C "$R" worktree remove --force "$A6" 2>/dev/null; rm -rf "$A6"
st ⓒ; kill "$BUSY" 2>/dev/null; wait "$BUSY" 2>/dev/null; BUSY=""
eq "프로세스 0(점유 프로세스 정리)" "$(pgrep -f "wt-busy" 2>/dev/null | wc -l | tr -d ' ')" 0
echo "----"; eq "합계 fail" "$fail" 0; exit $((fail > 0))
