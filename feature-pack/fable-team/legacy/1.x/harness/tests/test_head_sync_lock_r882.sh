#!/usr/bin/env bash
# test_head_sync_lock_r882.sh — R882: ft-head-sync 동시 폭주 제거
#   ⓐ --apply = cwd 워크트리 1곳만 git 호출 ⓑ 전수 표 = --table(--apply 와 분리) ⓒ 동시 1개 잠금(r2 커널 flock · 신호 9 고아 0 · 옛 pid 글자로 막지 않음)
#   r3 ⓖ 같은 워크트리 1곳 --apply ∥ --apply --all → 하나만 씀 · ⓗ 남의 MERGE_HEAD abort 0 · ⓘ 병합 뒤 검증 실패 = ERROR rc1 · 변이 2종
#   r4 ⓝ 잠금 밖 남의 같은 base merge --no-commit → abort 0 · rc1
#   r5 ⓟ 충돌 = merge-tree 로 미리 판정 → merge 안 함 · 상태 무변경 ⓠ 깨끗한데 merge 실패(서명) → abort 0 · MERGE_HEAD 그대로 · rc1 ⓡ 깨끗 → 최신화함 · 변이 2종
#   (r5: 도구 안 merge --abort 호출 0 — r3·r4 의 «abort» 단언은 «abort 0 · 오류·사람» 으로 바뀜)
#   ⓓ ft_head_lag 쪽지에 --apply 지시 0 ⓕ 변이 2종. 임시 origin+clone+워크트리 + git 대역(호출 기록)만 · 실 워크트리 0 · press 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; SYNC="$BIN/ft-head-sync.sh"; PY="$BIN/ft_head_lag.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; KEEP=""; trap 'rm -rf "$T"; [ -n "$KEEP" ] && kill "$KEEP" 2>/dev/null' EXIT
REALGIT="$(command -v git)"; mkdir -p "$T/shim"
cat > "$T/shim/git" <<EOF
#!/usr/bin/env bash
printf '%s\t%s\n' "\$PWD" "\$*" >> "\${GITLOG:-/dev/null}"
case "\$*" in *merge-base*) [ -n "\${GITSLOW:-}" ] && sleep "\$GITSLOW";; esac
case "\$*" in *"merge --no-edit"*)   # r3 대역: merge 직전 멈춤 · 남의 MERGE_HEAD 심기 · 병합 뒤 작업 트리 더럽히기
  [ -n "\${GITMERGESLOW:-}" ] && sleep "\$GITMERGESLOW"
  [ -n "\${FOREIGN_MH:-}" ] && printf '%s\n' "\$FOREIGN_MH" > "\$("$REALGIT" -C "\$2" rev-parse --absolute-git-dir)/MERGE_HEAD"
  [ -n "\${FOREIGN_MERGE:-}" ] && "$REALGIT" -C "\$2" merge --no-commit --no-ff "\${@: -1}" >/dev/null 2>&1   # r4: 잠금 밖 남이 같은 base 로 merge --no-commit
  [ -n "\${DIRTY_AFTER:-}" ] && { "$REALGIT" "\$@"; r=\$?; echo stray > "\$2/stray.txt"; exit "\$r"; };;
esac
exec "$REALGIT" "\$@"
EOF
chmod +x "$T/shim/git"
head_of() { sha "$1" HEAD; }

# 픽스처: main 전진 뒤 M0 에서 딴 워크트리 A·B·C 전부 뒤처짐 · 미커밋 0
fixture() {  # fixture <폴더>
  mkrepo "$1"; local d
  for d in a b c; do git -C "$W" worktree add -q -b "nano/$d" "$1/wt-$d" "$M0"; git -C "$1/wt-$d" config user.name t; git -C "$1/wt-$d" config user.email t@t; echo "$d" > "$1/wt-$d/$d.txt"; cm "$1/wt-$d" "work $d"; done
  echo m1 > "$W/m.txt"; cm "$W" "main moves"; git -C "$W" push -q origin main
}
# ⓐ 판정: wt-a 안 --apply 의 git 호출에 wt-b·wt-c 가 한 번도 안 나온다 · A 만 병합
apply_scope() {  # apply_scope <스크립트> <픽스처> → rc · out · others(남의 워크트리 git 호출 수)
  local s="$1" f="$2"; : > "$f/git.log"
  out="$( ( cd "$f/wt-a" && PATH="$T/shim:$PATH" GITLOG="$f/git.log" bash "$s" --apply ) 2>&1 )"; rc=$?
  others="$(grep -cE '/wt-(b|c)' "$f/git.log")"
}
# ⓒ 판정: 표 모드 3개를 겹쳐 띄운다(git 대역이 merge-base 마다 1초) → 표를 낸 실행 수 · «이미 실행 중» 수 · rc 합
conc() {  # conc <스크립트> <픽스처>
  local s="$1" f="$2" i pids=""; rm -f "$f"/conc.*
  for i in 1 2 3; do ( cd "$f/w" && PATH="$T/shim:$PATH" GITSLOW=1 bash "$s" --table > "$f/conc.$i" 2>&1; echo $? > "$f/conc.$i.rc" ) & pids="$pids $!"; sleep 0.4; done
  wait $pids
  tables="$(grep -l '^base=' "$f"/conc.? | grep -c .)"; busy="$(grep -lE '이미 실행 중 pid [0-9]+ · 시작 [0-9]{2}:[0-9]{2}' "$f"/conc.? | grep -c .)"
  rcs="$(cat "$f"/conc.?.rc | paste -sd+ - | bc)"
}

fixture "$T/f1"; W1="$T/f1/w"
bash -n "$SYNC"; ck "bash -n head-sync" $?

# ── ⓐ --apply = cwd 워크트리 1곳만
H0b="$(head_of "$T/f1/wt-b")"; apply_scope "$SYNC" "$T/f1"
[ "$rc" = 0 ] && git -C "$T/f1/wt-a" merge-base --is-ancestor "$(sha "$W1" HEAD)" HEAD; ck "ⓐ wt-a 안 --apply rc0 · A 최신화" $?
[ "$others" = 0 ]; ck "ⓐ 남의 워크트리(wt-b·wt-c) git 호출 0 (실측 $others)" $?
[ "$(printf '%s\n' "$out" | grep -cE '^nano/(b|c) ')" = 0 ] && [ "$(head_of "$T/f1/wt-b")" = "$H0b" ]; ck "ⓐ 표에 B·C 줄 0 · B HEAD 불변" $?

# ── ⓑ 전수 표 = --table(인자 없음도 같은 표) · --apply 와 같이 못 씀
out="$( ( cd "$W1" && bash "$SYNC" --table ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"apply=0"* ]] && [ "$(printf '%s\n' "$out" | grep -cE '^nano/(a|b|c) ')" = 3 ]; ck "ⓑ --table = 전 워크트리 표(A·B·C) rc0" $?
out="$( ( cd "$T/f1/wt-a" && bash "$SYNC" --table --apply ) 2>&1 )"; rc=$?
[ "$rc" = 2 ]; ck "ⓑ --table --apply → usage rc2" $?

# ── ⓒ 동시 1개 잠금
conc "$SYNC" "$T/f1"
[ "$tables" = 1 ] && [ "$busy" = 2 ] && [ "$rcs" = 0 ]; ck "ⓒ 겹친 3개 → 표 1 · «이미 실행 중 pid N · 시작 HH:MM» 2 · rc 전부 0 (표 $tables · 대기 $busy)" $?
LK="$W1/.git/ft-head-sync-scan.flock"   # 표·전수 = 순회 키(r3)
out="$( ( cd "$W1" && bash "$SYNC" --table ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"base="* ]] && [ -z "$(lsof -t "$LK" 2>/dev/null)" ]; ck "ⓒ 끝나면 잠금 풀림(쥔 프로세스 0 · 다음 실행 정상)" $?
# r2 ⓐ 두 실행 동시: 첫 실행이 잠금 쥔 채 느리게 도는 동안 둘째 → «이미 실행 중» rc0 · 스캔 0
pair() {  # pair <스크립트> <픽스처> → rc · out(둘째) · scans(둘째의 스캔 git 호출 수)
  local s="$1" f="$2" i; : > "$f/git2.log"; rm -f "$f/w/.git/ft-head-sync-scan.flock"   # 앞 실행의 pid 글자를 지워야 «첫 실행이 잡았다» 를 기다릴 수 있다(쥔 프로세스 0 일 때만)
  ( cd "$f/w" && PATH="$T/shim:$PATH" GITSLOW=3 bash "$s" --table > "$f/first.out" 2>&1 ) & FIRST=$!
  for i in $(seq 50); do grep -q '^pid ' "$f/w/.git/ft-head-sync-scan.flock" 2>/dev/null && break; sleep 0.1; done
  out="$( ( cd "$f/w" && PATH="$T/shim:$PATH" GITLOG="$f/git2.log" bash "$s" --table ) 2>&1 )"; rc=$?
  scans="$(grep -cE '	(-C [^ ]+ )?(status|merge-base|cherry|diff)' "$f/git2.log")"
}
pair "$SYNC" "$T/f1"
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && [[ "$out" =~ 이미\ 실행\ 중\ pid\ [0-9]+\ ·\ 시작\ [0-9]{2}:[0-9]{2} ]] && [ "$scans" = 0 ]; ck "ⓐ r2 두 실행 동시 → 둘째 «이미 실행 중 pid N · 시작 HH:MM» 1줄 rc0 · 스캔 git 0 (실측 $scans)" $?
# r2 ⓑ 첫 실행을 신호 9 로 죽이면 커널이 잠금을 푼다 → 다음 실행이 회수 문구 없이 바로 잡음
killtree() { local c; for c in $(pgrep -P "$1"); do killtree "$c"; done; kill -9 "$1" 2>/dev/null; }
killtree "$FIRST"; wait "$FIRST" 2>/dev/null
out="$( ( cd "$T/f1/w" && bash "$SYNC" --table ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"base="* ]] && [[ "$out" != *"이미 실행 중"* ]] && [[ "$out" != *"회수"* ]]; ck "ⓑ r2 신호 9 로 죽은 주인 → 다음 실행이 바로 잡음(회수 문구 0 · 고아 0)" $?
# r2 ⓒ 파일에 남은 옛 pid 글자(살아 있는 pid 라도)만으로는 막지 않는다 — 막는 것은 커널 잠금뿐
printf 'pid %s · 시작 00:00\n' "$$" > "$LK"
out="$( ( cd "$W1" && bash "$SYNC" --table ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"base="* ]] && [[ "$out" != *"이미 실행 중"* ]]; ck "ⓒ r2 잠금 파일의 옛 pid 글자만으로는 막지 않음" $?
python3 -I -c 'import fcntl, sys, time
f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[1], "w").write("pid 4242 · 시작 01:02\n"); time.sleep(30)' "$LK" & KEEP=$!
for i in $(seq 50); do grep -q 'pid 4242' "$LK" && break; sleep 0.1; done
out="$( ( cd "$W1" && bash "$SYNC" --table ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] && [[ "$out" == *"이미 실행 중 pid 4242 · 시작 01:02"* ]] && grep -q 'pid 4242' "$LK"; ck "ⓒ 살아 있는 주인 → 1줄 rc0 · 남의 잠금 글자 그대로" $?
out="$( ( cd "$T/f1/wt-b" && bash "$SYNC" --apply ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | awk '$1=="nano/b"' | grep -q '최신화함'; ck "ⓒ 전수 잠금 중에도 자기 워크트리 --apply 는 돈다(잠금 범위 = 그 워크트리)" $?
kill "$KEEP" 2>/dev/null; wait "$KEEP" 2>/dev/null; KEEP=""

# ── ⓓ 쪽지 문구 — --apply 지시 0 · 자기 워크트리 스스로 · 팩 무관
out="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); from ft_head_lag import build
print(build([{"path": "/tmp/wtA", "branch": "nano/a", "n": 2, "secs": 18000}], "a" * 40))' "$BIN")"
! printf '%s\n' "$out" | grep -q -- '--apply'; ck "ⓓ 쪽지에 --apply 0" $?
[[ "$out" == *"스스로"* ]] && [[ "$out" == *"merge --no-edit $(printf 'a%.0s' $(seq 40))"* ]] && [[ "$out" == *"팩"*"무관"* ]]; ck "ⓓ 쪽지 = 자기 워크트리 스스로(merge 만 · main sha 고정) · 팩 작업 무관" $?

# ── r3 ⓖ 같은 워크트리: 1곳 --apply(merge 직전 멈춤) ∥ --apply --all → 하나만 쓰고 다른 쪽 «건너뜀» · 작업 파일 = HEAD
race() {  # race <스크립트> <픽스처> → rc · out(--all) · one(1곳 출력)
  local s="$1" f="$2" i k; k="$(git -C "$f/wt-a" rev-parse --absolute-git-dir)/ft-head-sync.flock"; rm -f "$k"
  ( cd "$f/wt-a" && PATH="$T/shim:$PATH" GITMERGESLOW=6 bash "$s" --apply > "$f/one.out" 2>&1 ) & FIRST=$!
  for i in $(seq 50); do grep -q '^pid ' "$k" 2>/dev/null && break; sleep 0.1; done
  out="$( ( cd "$f/w" && bash "$s" --apply --all --confirm 3 ) 2>&1 )"; rc=$?; wait "$FIRST"; one="$(cat "$f/one.out")"
}
fixture "$T/f3"; race "$SYNC" "$T/f3"
[ "$rc" = 0 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '건너뜀 (다른 실행 중)' && [[ "$out" == *"건너뜀 1"* ]]; ck "ⓖ r3 --all 은 1곳 실행이 쥔 wt-a 를 «건너뜀» · 끝줄 건너뜀 수 rc0" $?
printf '%s\n' "$one" | awk '$1=="nano/a"' | grep -q '최신화함' && printf '%s\n' "$out" | awk '$1=="nano/b"||$1=="nano/c"' | grep -c '최신화함' | grep -qx 2; ck "ⓖ r3 wt-a = 1곳 실행만 씀 · B·C = 전수가 씀" $?
git -C "$T/f3/wt-a" merge-base --is-ancestor "$(sha "$T/f3/w" HEAD)" HEAD && [ -z "$(git -C "$T/f3/wt-a" status --porcelain --untracked-files=all)" ] && [ ! -e "$(git -C "$T/f3/wt-a" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; ck "ⓖ r3 wt-a 작업 파일 = HEAD(미커밋 0 · MERGE_HEAD 0) · HEAD ⊇ main" $?
# ── r3 ⓗ merge 직전 남이 MERGE_HEAD 를 만들면 → abort 0 · 건너뜀(남의 것 그대로)
fixture "$T/f4"; FMH="$(sha "$T/f4/wt-b" HEAD)"
out="$( ( cd "$T/f4/wt-a" && PATH="$T/shim:$PATH" FOREIGN_MH="$FMH" bash "$SYNC" --apply ) 2>&1 )"; rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '오류·사람(merge rc=128 · MERGE_HEAD .* 남음)' && [ "$(cat "$(git -C "$T/f4/wt-a" rev-parse --absolute-git-dir)/MERGE_HEAD")" = "$FMH" ]; ck "ⓗ r3~r5 남의 MERGE_HEAD(다른 sha) → abort 0 · 그대로 둠 · 오류·사람 rc1" $?
# ── r3 ⓘ 병합은 됐는데 작업 트리가 HEAD 와 다르면 «최신화함» 0 → ERROR 1줄 rc1
out="$( ( cd "$T/f4/wt-c" && PATH="$T/shim:$PATH" DIRTY_AFTER=1 bash "$SYNC" --apply ) 2>&1 )"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"ERROR 병합 뒤 검증 실패"* ]] && ! printf '%s\n' "$out" | awk '$1=="nano/c"' | grep -q '최신화함'; ck "ⓘ r3 병합 뒤 미커밋 남음 → «최신화함» 0 · ERROR rc1" $?

# ── r4 ⓝ 잠금 밖 다른 실행이 «같은 base» 로 merge --no-commit 해 둠(검사 뒤) → 우리 merge rc=128 → abort 0 · 남의 MERGE_HEAD 그대로 · rc1 · 보류
nfix() { fixture "$1"; BS="$(sha "$1/w" HEAD)"; out="$( ( cd "$1/wt-a" && PATH="$T/shim:$PATH" FOREIGN_MERGE=1 bash "$2" --apply ) 2>&1 )"; rc=$?; MHF="$(git -C "$1/wt-a" rev-parse --absolute-git-dir)/MERGE_HEAD"; }
nfix "$T/f7" "$SYNC"
[ "$rc" = 1 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '오류·사람(merge rc=128 · MERGE_HEAD .* 남음)' && [ "$(cat "$MHF" 2>/dev/null)" = "$BS" ] && [[ "$out" == *"ERROR merge 실패(rc=128 · abort 0"* ]] && [[ "$out" != *VIOLATION* ]]; ck "ⓝ r4·r5 남의 같은 base 병합 → abort 0 · MERGE_HEAD(=base) 그대로 · 오류·사람 rc1" $?
# ── r5 ⓟ 충돌 base → merge-tree 1 → merge 안 함 · «충돌·사람» · HEAD·index·작업 파일 무변경(r4 ⓞ 자리 · abort 대신 미리 판정)
fixture "$T/f8"; echo conflict > "$T/f8/wt-a/m.txt"; cm "$T/f8/wt-a" "conflict m"; H0="$(head_of "$T/f8/wt-a")"
out="$( ( cd "$T/f8/wt-a" && bash "$SYNC" --apply ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '충돌·사람' && [ ! -e "$(git -C "$T/f8/wt-a" rev-parse --absolute-git-dir)/MERGE_HEAD" ] && [ "$(head_of "$T/f8/wt-a")" = "$H0" ] && [ "$(cat "$T/f8/wt-a/m.txt")" = conflict ] && [ -z "$(git -C "$T/f8/wt-a" status --porcelain)" ]; ck "ⓟ r5 충돌 → merge 안 함 · «충돌·사람» · MERGE_HEAD 0 · HEAD·파일·index 무변경 rc0" $?
# ── r5 ⓠ 깨끗한 base 인데 merge 가 실패(서명 실패 — git 이 index·작업 트리 반영·MERGE_HEAD 쓴 뒤 die) → abort 0 · 상태 그대로 · «오류·사람» rc1
qfix() { fixture "$1"; git -C "$1/wt-a" config commit.gpgSign true; git -C "$1/wt-a" config gpg.program /usr/bin/false; git -C "$1/wt-a" config gpg.openpgp.program /usr/bin/false
  out="$( ( cd "$1/wt-a" && bash "$2" --apply ) 2>&1 )"; rc=$?; MHF="$(git -C "$1/wt-a" rev-parse --absolute-git-dir)/MERGE_HEAD"; }
qfix "$T/fq" "$SYNC"
[ "$rc" = 1 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '오류·사람(merge rc=' && [ "$(cat "$MHF" 2>/dev/null)" = "$(sha "$T/fq/w" HEAD)" ] && [[ "$out" == *"ERROR merge 실패"*"abort 0"* ]]; ck "ⓠ r5 깨끗 + 서명 실패 → abort 0 · MERGE_HEAD 그대로 · 오류·사람 rc1" $?
# ── r5 ⓡ 깨끗 base 정상 → «최신화함» rc0
fixture "$T/fr"; out="$( ( cd "$T/fr/wt-a" && bash "$SYNC" --apply ) 2>&1 )"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '최신화함' && [ -z "$(git -C "$T/fr/wt-a" status --porcelain --untracked-files=all)" ]; ck "ⓡ r5 깨끗 → «최신화함» · 미커밋 0 rc0" $?
# ── ⓕ 변이 2종 — 단언이 실제로 잡는가
mkbin() { local d="$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-head-sync.sh"; }
fixture "$T/f2"
mkbin "$T/mut1"; sed 's/fcntl\.flock(int(sys\.argv\[1\]), fcntl\.LOCK_EX | fcntl\.LOCK_NB)/pass/' "$SYNC" > "$T/mut1/ft-head-sync.sh"
! cmp -s "$SYNC" "$T/mut1/ft-head-sync.sh"; ck "ⓕ 변이1(flock 줄 제거)이 실제로 줄을 바꿨다" $?
conc "$T/mut1/ft-head-sync.sh" "$T/f2"
[ "$tables" -ge 2 ]; ck "ⓕ 변이(flock 제거) → 겹친 실행이 표 $tables 개 = ⓒ 단언이 잡는다" $?
pair "$T/mut1/ft-head-sync.sh" "$T/f2"; killtree "$FIRST"; wait "$FIRST" 2>/dev/null
[[ "$out" != *"이미 실행 중"* ]] && [ "$scans" -gt 0 ]; ck "ⓕ 변이(flock 제거) → 둘째도 스캔 git $scans = r2 ⓐ 단언이 잡는다" $?
mkbin "$T/mut2"; sed '/R882 cwd 한정/d' "$SYNC" > "$T/mut2/ft-head-sync.sh"
! cmp -s "$SYNC" "$T/mut2/ft-head-sync.sh"; ck "ⓕ 변이2 가 실제로 줄을 바꿨다" $?
apply_scope "$T/mut2/ft-head-sync.sh" "$T/f2"
[ "$others" -gt 0 ]; ck "ⓕ 변이(cwd 제한 제거) → 남의 워크트리 git 호출 $others = ⓐ 단언이 잡는다" $?

mutate() {  # mutate <새 폴더> <옛 글자> <새 글자> — 정확히 1곳 바꾼 ft-head-sync 사본
  mkbin "$1"; python3 -I -c 'import sys; s = open(sys.argv[1], encoding="utf-8").read(); assert s.count(sys.argv[3]) == 1, "변이 대상 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))' "$SYNC" "$1/ft-head-sync.sh" "$2" "$3"; }
mutate "$T/mut3" 'p="$(gitdir "$1")/ft-head-sync.flock"' 'p="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/ft-head-sync-wr.flock"'
ck "ⓕ 변이3(전수 쓰기 잠금 = 공용 키) 만듦" $?
fixture "$T/f5"; race "$T/mut3/ft-head-sync.sh" "$T/f5"
! printf '%s\n' "$out" | awk '$1=="nano/a"' | grep -q '건너뜀'; ck "ⓕ 변이(공용 키) → --all 이 1곳 실행 중인 wt-a 를 씀 = ⓖ 단언이 잡는다" $?
mutate "$T/mut4" 'else git -C "$wt" merge-tree --write-tree HEAD "$BSHA" >/dev/null 2>"$TMP/mt.err" || trc=$?' 'else :'
ck "ⓕ 변이4(merge-tree 사전 판정 제거) 만듦" $?
fixture "$T/f9"; echo conflict > "$T/f9/wt-a/m.txt"; cm "$T/f9/wt-a" "conflict m"
out="$( ( cd "$T/f9/wt-a" && bash "$T/mut4/ft-head-sync.sh" --apply ) 2>&1 )"; rc=$?
[ -e "$(git -C "$T/f9/wt-a" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; ck "ⓕ 변이(사전 판정 제거) → 충돌 merge 를 실제로 돌려 MERGE_HEAD·충돌 파일 남김 = ⓟ 단언이 잡는다" $?
mutate "$T/mut5" 'else res="오류·사람(merge rc=' 'else git -C "$wt" merge --abort >/dev/null 2>&1; res="오류·사람(merge rc='
ck "ⓕ 변이5(abort 되살림) 만듦" $?
qfix "$T/fq2" "$T/mut5/ft-head-sync.sh"
[ ! -e "$MHF" ]; ck "ⓕ 변이(abort 되살림) → 서명 실패 병합을 abort 로 지움 = ⓠ 단언이 잡는다" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
