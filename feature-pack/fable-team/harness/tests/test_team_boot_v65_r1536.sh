#!/usr/bin/env bash
# test_team_boot_v65_r1536.sh — ft-team-boot.sh r1536: ⓐ v65 명부 = seats.json(v65 이름은 옛 이름) · ⓑ 둘 다 없음 = 기존 «명부 없음» 멈춤 · ⓒ 다른 팀 그대로
#   ⓓ B4 = plist 파일 유무 아니라 launchctl 로드 여부(미로드 = 미등재(파일만)) · ⓔ 로드 = 등재(로드) · ⓕ launchctl 자체 실패 = «판정 불가» 1줄(멈추지 않음) · ⓖ plan 기본 자리 = 데이터 루트
#   격리: 임시 리포(design/teams/<팀>CLOSEOUT · seats*.json · .worktrees/wt) + 가짜 successor-open·nano·mbox·tmux·all-stop·launchctl — 실 세션·실 우편함·실 명부·실 launchd·press 0.
#   변이: M1 v65 분기 끔 → ⓐ FAIL · M2 B4 를 파일 유무로 되돌림 → ⓓ FAIL · M3 STATE 기본을 $ROOT 로 되돌림 → ⓖ FAIL
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -u   # pipefail 안 쓴다 — `cmd | grep -q` 의 SIGPIPE(141) 거짓 FAIL 방지
export LC_ALL=C
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
fail=0; out=""; rc=0; npass=0
ok()  { npass=$((npass+1)); }
bad() { echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); }
ck()  { if [ "$2" = 0 ]; then ok; else bad "$1"; fi; }
has() { printf '%s' "$out" | grep -qF -- "$1"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ---------- 가짜 도구 ----------
FAKE="$T/fake"; mkdir -p "$FAKE" "$T/la"
cat > "$FAKE/so.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/so.log"
while [ $# -gt 0 ]; do case "$1" in --name) echo "$2" >> "$FT_REC/live.txt"; shift 2;; *) shift;; esac; done
echo "DONE"; exit 0
EOF
cat > "$FAKE/nano.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/nano.log"; echo "SPAWNED"; exit 0
EOF
cat > "$FAKE/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/mbox.log"; echo "QUEUED seq=5150 to=$2 pending=0"; exit "${MBOX_RC:-0}"
EOF
cat > "$FAKE/tmux.sh" <<'EOF'
#!/usr/bin/env bash
[ "$1" = ls ] || exit 0; cat "$FT_REC/live.txt" 2>/dev/null; exit 0
EOF
cat > "$FAKE/allstop.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$FAKE/launchctl.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FT_REC/launchctl.log"
[ "${LAUNCHCTL_RC:-0}" = 0 ] && exit 0
echo "${LAUNCHCTL_ERR:-launchctl: error rc=$LAUNCHCTL_RC}" >&2; exit "$LAUNCHCTL_RC"
EOF
chmod +x "$FAKE"/*.sh
REC="$T/rec"; mkdir -p "$REC"; : > "$REC/live.txt"
export FT_REC="$REC" FT_LAUNCHAGENTS="$T/la" FT_LAUNCHCTL="$FAKE/launchctl.sh" FT_BOOT_ME='byz-harness-nano-r1536#0' FT_BOOT_REPORT_TO='byz-planner-master-pi#245'
export FT_MBOX_SH="$FAKE/mbox.sh" FT_NANO_SPAWN="$FAKE/nano.sh" FT_ALL_STOP="$FAKE/allstop.sh" FT_TMUX="$FAKE/tmux.sh" FT_SUCCESSOR_OPEN="$FAKE/so.sh"
unset FT_BOOT_STATE FT_SEATS_JSON FT_BOOT_WT LAUNCHCTL_RC 2>/dev/null || true
g() { git -C "$1" add -A >/dev/null 2>&1; git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
closeout() {  # <루트> <팀> <제목>
  local d="$1/design/teams/$2"; mkdir -p "$d"
  { echo "# CLOSEOUT 테스트 $3"; echo; echo "## 골 원문"; echo; echo "골 첫 줄 $3"; echo "골 둘째 줄"; echo "골 셋째 줄"; echo
    echo "## 4. 다시 여는 법"; echo; echo "- 새 세션 → 이 CLOSEOUT → 카드"; } > "$d/CLOSEOUT-$2-20261109.md"
}
mkfix() {  # <루트> <팀> <명부 파일 이름> <master 키> — 명부 1장 + CLOSEOUT + 워크트리
  local r="$1" t="$2" s="$3" m="$4"
  mkdir -p "$r/design/teams/$t/indices/진행" "$r/.fable-team/comm" "$r/.worktrees/wt$t"
  git -C "$r" init -q -b main >/dev/null 2>&1
  printf '{"_name":"T","_master":"%s","_cards":"design/teams/%s/indices","_cards_wt":"wt%s",\n "%s":{"role":"master","agent":"claude","model":"claude-sonnet-5-5[1m]"}}\n' \
    "$m" "$t" "$t" "$m" > "$r/.fable-team/$s"
  echo '{"_master":"byz-planner-master-pi#245"}' > "$r/.fable-team/seats-planner.json"
  closeout "$r" "$t" "$t"
  printf 'k\n' > "$r/design/teams/$t/keep.md"
  g "$r" init; git -C "$r" update-ref refs/remotes/origin/main HEAD
}
run() {  # <루트> <팀> [env…] — out·rc 갱신(세션 자리·기록 초기화 · plan 지우기)
  local r="$1" t="$2"; shift 2
  : > "$REC/live.txt"; : > "$REC/so.log"; : > "$REC/mbox.log"; : > "$REC/launchctl.log"
  rm -rf "$r/.fable-team/state/team-boot" "$r/state/team-boot"
  out="$(cd "$r" && env FT_REPO_ROOT="$r" "$@" bash "$BIN/ft-team-boot.sh" "$t" 2>&1)"; rc=$?
}
cnt() { local n=0; [ -f "$REC/$1" ] && n="$(grep -c . "$REC/$1" 2>/dev/null)"; echo "${n:-0}"; }
plans() { ls -1 "$1/.fable-team/state/team-boot/"$2-*.plan 2>/dev/null | head -1; }

# ---------- ⓐ v65 = seats.json (seats-v65.json 없음) → «명부 없음» 0 ----------
R="$T/r1"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
run "$R" v65
ck "ⓐ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has '명부 없음' && bad "ⓐ v65 명부 없음으로 멈추면 안 된다" || ok
grep -qF -- "byz-v65-master-claude#7 $R/.worktrees/wtv65 --name byz-v65-master-claude#8" "$REC/so.log" && ok || bad "ⓐ seats.json 의 _master · 이름 #8"
grep -q 'closeout=design/teams/v65/CLOSEOUT-v65-20261109.md' "$(plans "$R" v65)" && ok || bad "ⓐ plan 정본 = design/teams/v65"

# ---------- ⓑ v65 · seats-v65.json·seats.json 둘 다 없음 — 기존 «명부 없음» 멈춤 그대로 ----------
R="$T/r2"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
rm -f "$R/.fable-team/seats.json"; g "$R" no-seats
run "$R" v65
ck "ⓑ 멈춤 rc1" "$([ "$rc" = 1 ] && echo 0 || echo 1)"
has '멈춤 명부 없음' && printf '%s' "$out" | grep -qF 'seats-v65.json' && ok || bad "ⓑ 멈춤 문면(seats-v65.json)"
[ "$(cnt so.log)" = 0 ] && ok || bad "ⓑ spawn 0"

# ---------- ⓒ 다른 팀(ops) = seats-ops.json 그대로(동작 변화 0) ----------
R="$T/r3"; mkfix "$R" ops seats-ops.json 'byz-ops-master-claude#2'
run "$R" ops
ck "ⓒ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF -- "--name byz-ops-master-claude#3 --agent claude" "$REC/so.log" && ok || bad "ⓒ ops = seats-ops.json 그대로"
has '명부 없음' && bad "ⓒ ops 명부 없음 0" || ok

# ---------- ⓓ plist 파일만 있고 launchctl 미로드 → «미등재(파일만)» (등재 아님) ----------
R="$T/r4"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
: > "$T/la/com.byz.ft-tick-v65.plist"
run "$R" v65 LAUNCHCTL_RC=113 LAUNCHCTL_ERR='Could not find service "com.byz.ft-tick-v65" in domain for user gui: 501'
ck "ⓓ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B4 launchd=미등재(파일만)' && ok || bad "ⓓ 파일 있음 + 미로드 = 미등재(파일만)"
has '등재(로드)' && bad "ⓓ 미로드를 «등재» 로 읽으면 안 된다" || ok
has '부팅 직후 잔존' && bad "ⓓ 미로드는 잔존 아님" || ok
[ "$(cnt launchctl.log)" = 2 ] && ok || bad "ⓓ launchctl 1회 7초 + 재시도 1(실제 호출 $(cnt launchctl.log)회)"
grep -q '^b4=done launchd=미등재(파일만)' "$(plans "$R" v65)" && ok || bad "ⓓ plan b4 칸 = 미등재(파일만)"

# ---------- ⓔ launchctl 로드 rc0 → «등재(로드)» ----------
R="$T/r5"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
run "$R" v65 LAUNCHCTL_RC=0
ck "ⓔ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B4 launchd=등재(로드)' && ok || bad "ⓔ 로드 = 등재(로드)"
has '부팅 직후 잔존 등재(로드)' && ok || bad "ⓔ 로드 = 잔존 1줄"
[ "$(cnt launchctl.log)" = 1 ] && ok || bad "ⓔ 로드면 재시도 0"

# ---------- ⓕ launchctl 자체 실패(시간 초과 rc=124 · 명령 없음) = «판정 불가» 1줄 · 멈추지 않음 ----------
R="$T/r6"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
run "$R" v65 LAUNCHCTL_RC=124
ck "ⓕ rc0(멈추지 않음)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B4 launchd=판정불가(rc=124)' && ok || bad "ⓕ 시간 초과 = 판정 불가(rc≠0 칸)"
[ "$(cnt mbox.log)" = 1 ] && ok || bad "ⓕ 판정 불가여도 B5 보고 1통"
run "$R" v65 FT_LAUNCHCTL="$T/fake/no-such-launchctl"
ck "ⓕ 명령 없음 rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B4 launchd=판정불가(명령없음)' && ok || bad "ⓕ 명령 없음 = 판정 불가(하드 룰 20)"

# ---------- ⓖ plan 기본 자리 = 데이터 루트 $DROOT/.fable-team/state/team-boot ----------
R="$T/r7"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
run "$R" v65
ck "ⓖ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
[ -n "$(plans "$R" v65)" ] && ok || bad "ⓖ plan 자리 = 데이터 루트/.fable-team/state/team-boot"
[ -e "$R/state/team-boot" ] && bad "ⓖ 옛 자리($ROOT/state/team-boot)에 plan 0" || ok
run "$R" v65 FT_BOOT_STATE="$T/explicit"
[ "$(ls -1 "$T/explicit"/*.plan 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ] && ok || bad "ⓖ FT_BOOT_STATE 가 있으면 그 값 우선"

# ---------- ⓗ R1(DA) 명부 공존 = seats-v65.json 우선 · 후계 번호 = 두 파일 최대 #N+1 ----------
R="$T/r8"; mkfix "$R" v65 seats-v65.json 'byz-v65-master-claude#2'   # 새 이름(#2) < 옛 이름(#9) — 번호는 두 파일 최대
printf '{"_master":"byz-v65-master-pi#9",\n "byz-v65-master-pi#9":{"role":"master","agent":"pi","model":"m"}}\n' > "$R/.fable-team/seats.json"
g "$R" both-seats
run "$R" v65
ck "ⓗ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
grep -qF -- "--name byz-v65-master-claude#10 --agent claude" "$REC/so.log" && ok || bad "ⓗ 공존 = seats-v65.json 우선(_master #2) · 후계 = 두 파일 최대 #N+1(#10)"
has '명부 없음' && bad "ⓗ 공존인데 명부 없음 0" || ok

# ---------- ⓘ R2(DA) launchctl rc≠0(로드 없음 외 오류) = «판정 불가» — 거짓 미등재 0 ----------
R="$T/r9"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
run "$R" v65 LAUNCHCTL_RC=5 LAUNCHCTL_ERR='Bootstrap failed: 5: Input/output error'
ck "ⓘ rc0" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B4 launchd=판정불가(rc=5)' && ok || bad "ⓘ I/O 오류 rc=5 = 판정 불가(거짓 미등재 0)"
has '미등재(파일만)' && bad "ⓘ 로드 없음 아닌 오류를 «미등재(파일만)» 로 내리면 안 된다" || ok

# ---------- ⓙ R3(DA) 새 기본 STATE 에 plan 이 없고 옛 자리에 있으면 옛 plan 으로 재개(이동 0) ----------
R="$T/r10"; mkfix "$R" v65 seats.json 'byz-v65-master-claude#7'
: > "$REC/live.txt"; : > "$REC/so.log"; : > "$REC/mbox.log"; rm -rf "$R/state/team-boot" "$R/.fable-team/state/team-boot"
out="$(cd "$R" && env FT_REPO_ROOT="$R" FT_BOOT_STATE="$R/state/team-boot" MBOX_RC=1 bash "$BIN/ft-team-boot.sh" v65 2>&1)"; rc=$?   # 1회차: 옛 기본 자리에 B5 실패 plan + 생존 좌석
ck "ⓙ 1회차 보고 미도달 rc5" "$([ "$rc" = 5 ] && echo 0 || echo 1)"
: > "$REC/so.log"; : > "$REC/mbox.log"
out="$(cd "$R" && env FT_REPO_ROOT="$R" bash "$BIN/ft-team-boot.sh" v65 2>&1)"; rc=$?   # 2회차: 새 기본 자리(비어 있음) — 옛 plan 재개
ck "ⓙ 2회차 rc0(이미 부팅됨 0)" "$([ "$rc" = 0 ] && echo 0 || echo 1)"
has 'B1 옛 자리 plan 재개' && ok || bad "ⓙ 옛 자리 plan 1줄"
has 'B5 to=' && ok || bad "ⓙ B5 만 재개"
[ "$(cnt so.log)" = 0 ] && ok || bad "ⓙ 2회차 spawn 0(plan 에 b2=done)"
grep -q '^status=완료' "$(ls -1 "$R/state/team-boot/"v65-*.plan | head -1)" && ok || bad "ⓙ 옛 plan 파일이 완료로 바뀜(이동 0)"

# ---------- 변이 3종 — 각각 해당 사례를 FAIL 시켜야 한다(변이 흡수 0) ----------
mut() {  # <이름> <파일> <sed 식> <루트> <팀> [env…] — 변이 사본으로 다시 돌린다
  local n="$1" f="$2" e="$3" r="$4" t="$5"; shift 5
  local d="$T/mut-$n"; mkdir -p "$d"; cp "$BIN/ft-team-boot.sh" "$BIN/ft-team-seats-lib.sh" "$d/"
  sed -i '' "$e" "$d/$f"
  if cmp -s "$BIN/$f" "$d/$f"; then rc=99; bad "변이 $n 미적용(sed 0)"; return 1; fi
  : > "$REC/live.txt"; : > "$REC/so.log"; : > "$REC/mbox.log"; : > "$REC/launchctl.log"
  rm -rf "$r/.fable-team/state/team-boot" "$r/state/team-boot"
  out="$(cd "$r" && env FT_REPO_ROOT="$r" "$@" bash "$d/ft-team-boot.sh" "$t" 2>&1)"; rc=$?
}
mut M1 ft-team-seats-lib.sh 's|"$TEAM" = v65|"$TEAM" = xv65|' "$T/r1" v65
printf '%s' "$out" | grep -qF '멈춤 명부 없음' && ok || bad "M1 v65 분기를 끄면 ⓐ 가 FAIL 해야 한다"
mut M2 ft-team-boot.sh 's|tick_launchd_loaded "$TEAM"; ld="$LD_CELL"|LD_CELL=미등재; [ -e "$plist" ] \&\& LD_CELL="등재(파일만)"; ld="$LD_CELL"|' "$T/r4" v65 LAUNCHCTL_RC=1
printf '%s' "$out" | grep -qF 'launchd=등재(파일만)' && ok || bad "M2 파일 유무로 되돌리면 ⓓ 가 FAIL 해야 한다(변이 흡수)"
mut M3 ft-team-boot.sh 's|STATE="${FT_BOOT_STATE:-$DROOT/.fable-team/state/team-boot}"|STATE="${FT_BOOT_STATE:-$ROOT/state/team-boot}"|' "$T/r7" v65
[ -e "$T/r7/state/team-boot" ] && ok || bad "M3 STATE 기본을 ROOT 로 되돌리면 ⓖ 가 FAIL 해야 한다(변이 흡수)"
mut_n="$(ls -1d "$T"/mut-M1 "$T"/mut-M2 "$T"/mut-M3 2>/dev/null | wc -l | tr -d ' ')"

# ---------- 정적 — kit 사본 같은 내용 · 새 시험 실행 비트 0 ----------
cmp -s "$BIN/ft-team-boot.sh" "$BIN/../kit/fable-team/bin/ft-team-boot.sh" && ok || bad "정적: kit 사본 ft-team-boot.sh diff 0"
cmp -s "$BIN/ft-team-seats-lib.sh" "$BIN/../kit/fable-team/bin/ft-team-seats-lib.sh" && ok || bad "정적: kit 사본 ft-team-seats-lib.sh diff 0"
[ -x "$HERE/test_team_boot_v65_r1536.sh" ] && bad "정적: 새 시험 실행 비트 0(r1305 · bash 로 부른다)" || ok

echo "----"
if [ "$fail" = 0 ]; then echo "ALL PASS ($npass) · 변이적용 $mut_n/3"; exit 0; fi
echo "FAILED $fail"; exit 1
