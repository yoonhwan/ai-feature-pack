#!/usr/bin/env bash
# test_live_install.sh — R215: ft-live-install.sh (키트 ref → 라이브 bin 설치 · 백업 · 재검사 · main 조상만).
# mktemp 만 쓴다(bare 원격 + 클론 + 설치 꼴 <x>/.fable-team/bin) — 실제 리포·라이브 bin·launchd 0.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CEILING_DIRECTORIES
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
TOOLS="$HERE/../../scripts/fable-team-bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
h() { git hash-object --no-filters "$1"; }
G() { git -c user.email=t@t -c user.name=t "$@"; }

bash -n "$SRC/ft-live-install.sh" && ok "bash -n ft-live-install.sh" || bad "bash -n ft-live-install.sh"

# ── 키트 꼴 원격: a.sh(755) · b.sh(644) · c.py(644) · drift-check ──
KP="scripts/harness-install/fable-team/bin"
mkrepo() {   # mkrepo <이름> <a.sh 내용>  → $T/<이름>.git(bare) · $T/<이름>(클론)
  local n="$1" seed="$T/$1-seed"
  git init -q --bare -b main "$T/$n.git"; git init -q -b main "$seed"; mkdir -p "$seed/$KP"
  printf '%s\n' "$2" > "$seed/$KP/a.sh"; chmod 755 "$seed/$KP/a.sh"
  printf 'data b\n' > "$seed/$KP/b.sh"; chmod 644 "$seed/$KP/b.sh"
  printf 'print("c")\n' > "$seed/$KP/c.py"; chmod 644 "$seed/$KP/c.py"
  cp -p "$TOOLS/ft-live-bin-drift-check.sh" "$seed/$KP/"
  git -C "$seed" add -A && G -C "$seed" commit -q -m kit
  git -C "$seed" remote add origin "$T/$n.git" && git -C "$seed" push -q origin main
  git clone -q "$T/$n.git" "$T/$n" 2>/dev/null
}
mkrepo good 'echo a'
CLONE="$T/good"; LIVE="$T/.fable-team/bin"; STATE="$T/.fable-team/state"
fresh_live() { rm -rf "$T/.fable-team"; mkdir -p "$LIVE"; for f in "$CLONE/$KP"/*; do cp -p "$f" "$LIVE/"; done; }
INST() { bash "${INSTALLER:-$TOOLS/ft-live-install.sh}" "$@"; }
CHK() { bash "$TOOLS/ft-live-bin-drift-check.sh" --bin "$LIVE" --repo "$CLONE" --ref "${1:-origin/main}"; }
untouched_a() { [ "$(h "$LIVE/a.sh")" = "$A0" ]; }

# ⓐ 일치 → OK 이미 일치 · 쓰기 0
fresh_live; out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓐ 일치"; has "$out" "OK 이미 일치" "ⓐ OK 이미 일치 줄"
[ ! -e "$STATE" ] && ok "ⓐ 쓰기 0(state 폴더 없음)" || bad "ⓐ 일치인데 state 폴더가 생김"

# ⓑ DIFF 1·MISSING 1·MODE 1 → 3개 설치 · 재검사 OK · tar 에 기존 2개(MISSING 은 기존 파일 없음)
mutate_b() { fresh_live; echo "# x" >> "$LIVE/a.sh"; rm "$LIVE/b.sh"; chmod 755 "$LIVE/c.py"; }
scenario_b() {   # → $out $rc $secs $bak
  mutate_b; local t0=$SECONDS
  out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?; secs=$((SECONDS - t0))
  bak="$(printf '%s\n' "$out" | sed -n 's/.* bak=//p')"
}
scenario_b
rc_is "$rc" 0 "ⓑ 3개 설치"; has "$out" "INSTALLED n=3 ref=" "ⓑ INSTALLED n=3"
CHK >/dev/null; rc_is "$?" 0 "ⓑ 재검사 OK"
[ -x "$LIVE/c.py" ] && bad "ⓑ MODE 원복 실패(c.py 실행 비트 남음)" || ok "ⓑ MODE 원복(c.py 644)"
if [ -f "$bak" ]; then
  names="$(tar -tf "$bak" | sort | tr '\n' ' ')"
  [ "$names" = "a.sh c.py " ] && ok "ⓑ tar 안에 기존 2개(a.sh c.py)" || bad "ⓑ tar 내용 «$names» 기대 «a.sh c.py »"
else bad "ⓑ 백업 tar 없음: «$bak»"; fi
[ "$secs" -le 5 ] && ok "ⓚ 1회 ${secs}s ≤ 5s" || bad "ⓚ 1회 ${secs}s > 5s"

# ⓒ EXTRA 보존
fresh_live; echo "# x" >> "$LIVE/a.sh"; echo keep > "$LIVE/extra.sh"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓒ EXTRA 있어도 설치"; has "$out" "KEEP-EXTRA extra.sh" "ⓒ KEEP-EXTRA 줄"; has "$out" "INSTALLED" "ⓒ INSTALLED"
[ -f "$LIVE/extra.sh" ] && ok "ⓒ EXTRA 파일 보존" || bad "ⓒ EXTRA 파일이 지워짐"

# ⓓ ref 가 main 조상이 아님 → REJECT · 쓰기 0
git -C "$CLONE" checkout -q -b side; echo "# side" >> "$CLONE/$KP/a.sh"; G -C "$CLONE" commit -q -am side
SIDE="$(git -C "$CLONE" rev-parse HEAD)"; git -C "$CLONE" checkout -q main
fresh_live; echo "# x" >> "$LIVE/a.sh"; A0="$(h "$LIVE/a.sh")"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref "$SIDE" 2>&1)"; rc=$?
rc_is "$rc" 1 "ⓓ 조상 아님"; has "$out" "REJECT" "ⓓ REJECT 줄"
untouched_a && ok "ⓓ 쓰기 0(a.sh 그대로)" || bad "ⓓ a.sh 가 바뀜"
[ ! -e "$STATE" ] && ok "ⓓ 백업도 안 만듦" || bad "ⓓ state 폴더가 생김"

# ⓔ 백업 폴더를 못 만듦 → rc 3 · 쓰기 0
fresh_live; echo "# x" >> "$LIVE/a.sh"; A0="$(h "$LIVE/a.sh")"; touch "$STATE"   # state 가 «파일» 이라 mkdir -p 실패
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 3 "ⓔ 백업 불가"; has "$out" "ERROR" "ⓔ ERROR 줄(조용한 통과 아님)"
untouched_a && ok "ⓔ 쓰기 0" || bad "ⓔ a.sh 가 바뀜"

# ⓕ blob 이 bash -n 실패 → 라이브 bin 전부 그대로 · rc 3 · tmp 0
mkrepo broken 'if then'
scenario_f() {   # → $out $rc  (INSTALLER 가 주어지면 변이본)
  fresh_live; echo "# x" >> "$LIVE/a.sh"; rm "$LIVE/b.sh"; A0="$(h "$LIVE/a.sh")"
  out="$(INST --bin "$LIVE" --repo "$T/broken" --ref origin/main 2>&1)"; rc=$?
}
scenario_f
rc_is "$rc" 3 "ⓕ bash -n 실패"; has "$out" "bash -n 실패" "ⓕ 사유 줄"
untouched_a && ok "ⓕ a.sh 원복(그대로)" || bad "ⓕ a.sh 가 바뀜"
[ ! -e "$LIVE/b.sh" ] && ok "ⓕ 다른 파일도 쓰기 0(b.sh 안 생김)" || bad "ⓕ b.sh 가 생김(부분 설치)"
[ -z "$(ls -A "$LIVE" | grep 'tmp-li')" ] && ok "ⓕ tmp 잔여 0" || bad "ⓕ tmp 가 남음"

# ⓖ --dry-run → 표만 · 쓰기 0
fresh_live; echo "# x" >> "$LIVE/a.sh"; A0="$(h "$LIVE/a.sh")"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main --dry-run 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓖ dry-run"; has "$out" "WOULD DIFF a.sh" "ⓖ 설치 대상 표"; has "$out" "DRY-RUN n=1" "ⓖ DRY-RUN 줄"
untouched_a && ok "ⓖ 쓰기 0" || bad "ⓖ a.sh 가 바뀜"
[ ! -e "$STATE" ] && ok "ⓖ 백업도 안 만듦" || bad "ⓖ state 폴더가 생김"

# ⓗ 죽은 pid 가 쥔 잠금 + 그 pid 의 tmp 가 남은 상태(크래시) 뒤 재실행 → 회수 · 정상 설치 · 죽은 pid tmp 청소 · 산 pid 의 tmp 는 그대로
( : ) & DEAD=$!; wait "$DEAD"
fresh_live; echo "# x" >> "$LIVE/a.sh"; mkdir -p "$STATE/live-install/lock.d"; printf '%s\n%s\n' "$DEAD" "$(date +%s)" > "$STATE/live-install/lock.d/owner"
echo junk > "$LIVE/.a.sh.tmp-li.$DEAD"; echo live > "$LIVE/.zz.sh.tmp-li.$$"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓗ 죽은 pid 잠금 회수 후 정상 설치"; has "$out" "INSTALLED" "ⓗ INSTALLED"
[ ! -e "$LIVE/.a.sh.tmp-li.$DEAD" ] && ok "ⓗ 죽은 pid 의 tmp 청소" || bad "ⓗ 죽은 pid 의 tmp 가 남음"
[ -e "$LIVE/.zz.sh.tmp-li.$$" ] && ok "ⓗ 산 pid 의 tmp 는 건드리지 않음(자기 tmp 만 청소)" || bad "ⓗ 남의 tmp 를 지움"
[ ! -e "$STATE/live-install/lock.d" ] && ok "ⓗ 끝나면 잠금 해제" || bad "ⓗ 잠금이 남음"
rm -f "$LIVE/.zz.sh.tmp-li.$$"

# ⓛ H1 — 내용과 모드가 «동시에» 다른 파일(DIFF+MODE) 정상 설치 · 건수는 고유 파일 수
fresh_live; echo "# x" >> "$LIVE/a.sh"; chmod 644 "$LIVE/a.sh"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓛ DIFF+MODE 동시 파일 설치"; has "$out" "INSTALLED n=1 ref=" "ⓛ 건수 = 고유 파일 1"
[ -x "$LIVE/a.sh" ] && [ "$(h "$LIVE/a.sh")" = "$(h "$CLONE/$KP/a.sh")" ] && ok "ⓛ a.sh 내용·실행 비트 키트와 같음" || bad "ⓛ a.sh 가 키트와 다름"
fresh_live; echo "# x" >> "$LIVE/a.sh"; chmod 644 "$LIVE/a.sh"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main --dry-run 2>&1)"; has "$out" "WOULD DIFF+MODE a.sh" "ⓛ dry-run 은 사유를 합쳐 한 줄"

# ⓜ H2 — mv 를 가짜로 바꿔 «실제 중단»: mv 실패 / k개 반영 뒤 TERM / KILL(트랩 불가)
mkdir -p "$T/stub"
cat > "$T/stub/mv" <<'EOS'
#!/bin/bash
n=$(cat "$STUBCOUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$STUBCOUNT"
case "$STUBMODE" in fail) [ "$n" != 2 ] || exit 1;; esac
/bin/mv "$@"
case "$STUBMODE" in term) [ "$n" != 2 ] || kill -TERM "$PPID";; kill) [ "$n" != 2 ] || kill -KILL "$PPID";; esac
exit 0
EOS
chmod 755 "$T/stub/mv"
mutate_m() {   # a.sh DIFF · b.sh MISSING · c.py DIFF → mv 순서 a.sh, b.sh, c.py
  fresh_live; echo "# x" >> "$LIVE/a.sh"; rm "$LIVE/b.sh"; echo "# y" >> "$LIVE/c.py"; rm -f "$T/count"
  A0="$(h "$LIVE/a.sh")"; C0="$(h "$LIVE/c.py")"
}
unchanged_m() { [ "$(h "$LIVE/a.sh")" = "$A0" ] && [ ! -e "$LIVE/b.sh" ] && [ "$(h "$LIVE/c.py")" = "$C0" ] && [ -z "$(ls -A "$LIVE" | grep 'tmp-li')" ]; }
MANS() { ls "$STATE"/live-install/*.manifest 2>/dev/null | head -1; }

mutate_m; out="$(STUBMODE=fail STUBCOUNT="$T/count" PATH="$T/stub:$PATH" INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 3 "ⓜ mv 실패"; has "$out" "mv 실패: b.sh" "ⓜ 오류 줄에 파일명(변수 안 덮임)"; has "$out" "RESTORED n=3" "ⓜ RESTORED 줄"
unchanged_m && ok "ⓜ mv 실패 → 설치 전 상태로 원복(없던 b.sh 없음 · tmp 0)" || bad "ⓜ mv 실패 뒤 원복 안 됨"
[ -e "$(MANS).done" ] && ok "ⓜ 원복 뒤 manifest.done" || bad "ⓜ manifest.done 없음"

mutate_m; rm -rf "$STATE"; out="$(STUBMODE=term STUBCOUNT="$T/count" PATH="$T/stub:$PATH" INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 143 "ⓜ 2개 반영 뒤 TERM"; has "$out" "RESTORED n=3" "ⓜ TERM → RESTORED 줄"
unchanged_m && ok "ⓜ TERM → 원복(새로 생긴 b.sh 삭제 · tmp 0)" || bad "ⓜ TERM 뒤 원복 안 됨"

mutate_m; rm -rf "$STATE"; out="$(STUBMODE=kill STUBCOUNT="$T/count" PATH="$T/stub:$PATH" INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 137 "ⓜ KILL(트랩 불가)"; M="$(MANS)"
{ [ -f "$M" ] && [ ! -e "$M.done" ] && [ -e "$LIVE/b.sh" ]; } && ok "ⓜ KILL → 미완 manifest 남음 · 반쯤 설치됨" || bad "ⓜ KILL 상태 이상"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 1 "ⓜ 미완 manifest → 다음 실행 거절"; has "$out" "REJECT 이전 설치 미완 — --restore" "ⓜ REJECT 안내"
[ -e "$LIVE/b.sh" ] && ok "ⓜ 거절은 쓰기 0(반쯤 상태 그대로)" || bad "ⓜ 거절인데 상태가 바뀜"
out="$(INST --restore "$M" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓜ --restore"; has "$out" "RESTORED n=3" "ⓜ --restore RESTORED 줄"
unchanged_m && ok "ⓜ --restore → 새 파일 제거까지 원복 · tmp 0" || bad "ⓜ --restore 뒤 원복 안 됨"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?; rc_is "$rc" 0 "ⓜ 복원 뒤 정상 설치 재개"; has "$out" "INSTALLED n=3" "ⓜ INSTALLED n=3"
mutate_m; INST --bin "$LIVE" --repo "$CLONE" --ref origin/main >/dev/null 2>&1; M="$(MANS)"
rm -f "${M%.manifest}"; out="$(INST --restore "$M" 2>&1)"; rc=$?   # 복원 실패 모사: 백업 tar 를 지운 뒤 --restore
rc_is "$rc" 1 "ⓜ 백업 tar 없음 → RESTORE-FAIL"; has "$out" "RESTORE-FAIL" "ⓜ RESTORE-FAIL 줄(원복 단정 안 함)"

# ⓝ 동시 설치 — 잠금: 산 pid 가 쥔 잠금 앞에서 두 번째 실행은 5초 기다린 뒤 REJECT(쓰기 0 · 남의 잠금은 안 지움)
fresh_live; echo "# x" >> "$LIVE/a.sh"; A0="$(h "$LIVE/a.sh")"; mkdir -p "$STATE/live-install/lock.d"
printf '%s\n%s\n' "$$" "$(date +%s)" > "$STATE/live-install/lock.d/owner"
out="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rc=$?
rc_is "$rc" 1 "ⓝ 잠금 보유 중 두 번째 실행"; has "$out" "REJECT 다른 설치 진행 중 pid=$$" "ⓝ REJECT 줄(보유자 pid)"
untouched_a && ok "ⓝ 쓰기 0" || bad "ⓝ a.sh 가 바뀜"
[ -d "$STATE/live-install/lock.d" ] && ok "ⓝ 남의 잠금은 그대로" || bad "ⓝ 남의 잠금을 지움"
# A 가 스테이징 중(tmp 만들고 chmod 에서) manifest 만들기 전에 멈춘 사이 B 진입 — 잠금이 있으면 B 거절, A 는 정상 완료
mkdir -p "$T/stub2"
cat > "$T/stub2/chmod" <<'EOS'
#!/bin/bash
if [ -n "${STALL_FLAG:-}" ] && [ ! -e "$STALL_FLAG" ]; then
  : > "$STALL_FLAG"; for _ in $(seq 1 150); do [ -e "$STALL_DONE" ] && break; sleep 0.2; done
fi
exec /bin/chmod "$@"
EOS
chmod 755 "$T/stub2/chmod"
conc() {   # → outA rcA outB rcB
  fresh_live; echo "# x" >> "$LIVE/a.sh"; rm -f "$T/af" "$T/ad" "$T/A.out" "$T/A.rc"
  ( STALL_FLAG="$T/af" STALL_DONE="$T/ad" PATH="$T/stub2:$PATH" INST --bin "$LIVE" --repo "$CLONE" --ref origin/main > "$T/A.out" 2>&1; echo $? > "$T/A.rc" ) &
  local apid=$!; for _ in $(seq 1 50); do [ -e "$T/af" ] && break; sleep 0.2; done
  outB="$(INST --bin "$LIVE" --repo "$CLONE" --ref origin/main 2>&1)"; rcB=$?
  : > "$T/ad"; wait "$apid"; rcA="$(cat "$T/A.rc")"; outA="$(cat "$T/A.out")"
}
conc
rc_is "$rcB" 1 "ⓝ A 스테이징 뒤 정지 중 B 진입 → 거절"; has "$outB" "다른 설치 진행 중" "ⓝ B REJECT 줄"
rc_is "$rcA" 0 "ⓝ A 는 정상 완료"; has "$outA" "INSTALLED" "ⓝ A INSTALLED"
[ "$(h "$LIVE/a.sh")" = "$(h "$CLONE/$KP/a.sh")" ] && ok "ⓝ 최종 a.sh = 키트" || bad "ⓝ 최종 a.sh 가 키트와 다름"

# ⓘ 키트 두 사본 cmp 0
cmp "$TOOLS/ft-live-install.sh" "$SRC/ft-live-install.sh" && ok "ⓘ 키트 사본 cmp 0" || bad "ⓘ 키트 사본 불일치"

# ⓙ 변이: 백업 단계 삭제본 → ⓑ tar 단언 실패 · 문법 검사 삭제본 → ⓕ 실패
mkdir -p "$T/mut"; cp "$TOOLS/ft-live-bin-drift-check.sh" "$T/mut/"
grep -v 'tar -cf "\$bak"' "$TOOLS/ft-live-install.sh" > "$T/mut/no-backup.sh"
sed -e '/\*\.sh) bash -n/d' "$TOOLS/ft-live-install.sh" > "$T/mut/no-syntax.sh"
INSTALLER="$T/mut/no-backup.sh"; scenario_b
{ [ -f "$bak" ] && [ "$(tar -tf "$bak" | sort | tr '\n' ' ')" = "a.sh c.py " ]; } 2>/dev/null && bad "ⓙ 백업 삭제 변이가 ⓑ 에서 검출 안 됨" || ok "ⓙ 백업 삭제 변이 → ⓑ tar 단언 실패 검출"
INSTALLER="$T/mut/no-syntax.sh"; scenario_f
[ "$rc" = 3 ] && bad "ⓙ 문법 검사 삭제 변이가 ⓕ 에서 검출 안 됨" || ok "ⓙ 문법 검사 삭제 변이 → ⓕ 실패 검출 (rc=$rc)"
sed -e 's/^lock_acquire "\$SD"/:/' "$TOOLS/ft-live-install.sh" > "$T/mut/no-lock.sh"
INSTALLER="$T/mut/no-lock.sh"; conc
[ "$rcB" = 1 ] && bad "ⓙ 잠금 제거 변이가 ⓝ 에서 검출 안 됨" || ok "ⓙ 잠금 제거 변이 → ⓝ 동시 반례 검출 (B rc=$rcB)"
unset INSTALLER

echo "fail=$fail"; [ "$fail" = 0 ]
