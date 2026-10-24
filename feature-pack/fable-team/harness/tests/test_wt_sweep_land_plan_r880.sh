#!/usr/bin/env bash
# test_wt_sweep_land_plan_r880.sh — 카드 r880: 착지용 사본(.worktrees/land-*)이 착지 뒤 영원히 남던 것의 «닫는 사건».
#   ⓑ착지 sha 가 main 조상 + 미커밋 0 + 주인 좌석 0 인 land 사본만 → 계획 파일 1개(.sh.hil) · 삭제 실행 0 · [HIL] 은 목록 바뀐 때만
#   ⓒ미커밋·미착지·좌석 살아 있음·잠김 = 목록 밖(이유 1줄) · 좌석을 못 읽으면 목록 0
#   ⓕ계획 실행(= 오빠 h) 순간 다시 잰다 — HEAD 바뀜·새 미커밋 = skip · 통과한 것만 git worktree remove
# 임시 git 리포 + 임시 워크트리 + 가짜 tmux·lsof·du 만 — 실 리포·워크트리·tmux·mbox 0 · 외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${WT_TEST_SRC:-$HERE/../../harness/kit/fable-team/bin}"   # 고치기 전·변이 코드로 돌릴 때만 덮어쓴다
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
isd() { [ -d "$1" ] && echo yes || echo no; }
sent_is_sig() { [ -s "$1.sent" ] && [ "$(cat "$1.sent")" = "$(cat "$1.sig" 2>/dev/null)" ] && echo yes || echo no; }

mkdir -p "$T/bin" "$T/fake" "$T/state"
cp "$SRC/ft-wt-sweep.sh" "$T/bin/"; bash -n "$T/bin/ft-wt-sweep.sh" && ok "bash -n" || bad "bash -n"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_TMUX_ERR:-}" ] && { echo "${FAKE_TMUX_ERR_TEXT:-permission denied}"; exit 1; }
if [ -n "${FAKE_TMUX_CNT:-}" ]; then   # 몇 번째 호출부터 «새 좌석» 이 보이는지 — 재검사 시점을 재는 대역(r880 고침 1)
  c="$(cat "$FAKE_TMUX_CNT" 2>/dev/null || echo 0)"; c=$((c+1)); echo "$c" > "$FAKE_TMUX_CNT"
  [ "$c" -ge "${FAKE_TMUX_AT:-999}" ] && { echo "$FAKE_LATE_PANE"; exit 0; }
fi
[ -s "$FAKE_PANES" ] && { cat "$FAKE_PANES"; exit 0; }
echo "no server running on /tmp/fake"; exit 1
EOF
printf '#!/usr/bin/env bash\necho p1; sed "s/^/n/" "$FAKE_CWDS"\n' > "$T/fake/lsof"
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\n" 1000 "$2"\n' > "$T/fake/du"
chmod +x "$T/fake/"*; : > "$T/panes"; echo /usr > "$T/cwds"

REPO="$T/repo"; mkdir -p "$REPO"
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
GIT init -q -b main; echo a > "$REPO/a"; GIT add a; GIT commit -q -m c1; C1="$(GIT rev-parse HEAD)"
echo b > "$REPO/a"; GIT commit -q -am c2; C2="$(GIT rev-parse HEAD)"
GIT update-ref refs/remotes/origin/main "$C2"
GIT branch side "$C1"; GIT -c core.hooksPath=/dev/null checkout -q side; echo s > "$REPO/s"; GIT add s; GIT commit -q -m side; GIT checkout -q main
W="$REPO/.worktrees"
for n in land-done land-done2 land-done3 land-dirty land-alive land-locked nano-x; do GIT worktree add -q --detach "$W/$n" "$C2"; done
GIT worktree add -q --detach "$W/land-unlanded" side
echo junk > "$W/land-dirty/junk"
echo "$W/land-alive/sub" > "$T/cwds"
GIT worktree lock "$W/land-locked"
NWT() { GIT worktree list --porcelain | grep -c '^worktree '; }
N0="$(NWT)"

lp() { ( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_WT_CLEAN_DIR="$T/state/wt-clean" FT_WT_SCAN_ROOT="$REPO" \
  FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN="$T/fake/lsof" FT_DU_BIN="$T/fake/du" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" "$@" \
  bash "$T/bin/ft-wt-sweep.sh" --land-plan 2>&1 ); }
PLAN="$T/state/wt-clean/land-copies.sh.hil"

echo "== ⓑ 착지 끝난 land 사본만 계획 1개 · 삭제 0"
o="$(lp)"; rc=$?
chk "ⓑ rc 0" "$rc" 0
has "$o" "LAND-PLAN 3곳 3000KB" "ⓑ 대상 3곳(land-done·2·3) · 크기 합"
has "$o" "LAND land-done sha=${C2:0:12} kb=1000" "ⓑ 목록 줄 = 이름·착지 sha·크기"
chk "ⓑ 계획 파일 1개" "$(ls "$T/state/wt-clean" | grep -c 'land-copies.sh.hil$')" 1
chk "ⓑ 계획의 land_rm 줄 = 3" "$(grep -c '^land_rm ' "$PLAN")" 3
has "$o" "[HIL] seat=byz-harness-wt-land 착지 끝난 land 사본 3곳" "ⓑ 첫 목록 = [HIL] 1줄"
chk "ⓑ 삭제 호출 0 — 워크트리 수 그대로" "$(NWT)" "$N0"
chk "ⓑ 삭제 호출 0 — land-done 폴더 그대로" "$(isd "$W/land-done")" yes
hasnt "$o" "nano-x" "ⓑ land-* 아닌 사본은 대상 밖"
# r880 고침 4(DA r1 반례 4): «바뀐 때만» 의 근거는 목록 비교가 아니라 «보냄 표지»(.sent = 실제로 나간 목록 해시)다.
cp "$PLAN.sig" "$PLAN.sent"; o="$(lp)"; hasnt "$o" "[HIL]" "ⓑ 목록이 같고 보냄 표지 있으면 [HIL] 0(바뀐 때만)"
rm -f "$PLAN.sent"; o="$(lp)"; has "$o" "[HIL]" "ⓑ 보냄 표지 없으면 같은 목록도 재발송(ⓓ)"

echo "== ⓒ 목록 밖 — 이유 1줄"
for n in land-dirty land-alive land-locked land-unlanded; do hasnt "$(grep '^land_rm ' "$PLAN")" "$W/$n " "ⓒ $n 계획 밖"; done
has "$o" "KEEP land-dirty — 미커밋 1줄" "ⓒ 미커밋 이유"
has "$o" "KEEP land-unlanded — 미착지" "ⓒ 미착지 이유"
has "$o" "KEEP land-alive — 좌석·프로세스 살아 있음" "ⓒ 좌석 살아 있음 이유(cwd)"
has "$o" "KEEP land-locked — 잠김" "ⓒ 잠김 이유"
echo "$W/land-done3" > "$T/panes"; o="$(lp)"
has "$o" "KEEP land-done3 — 좌석·프로세스 살아 있음" "ⓒ tmux pane 이 안에 = 목록 밖"
has "$o" "[HIL]" "ⓒ 목록이 바뀌면 [HIL] 다시 1줄"
: > "$T/panes"
mv "$PLAN" "$T/plan.keep"; o="$(lp FAKE_TMUX_ERR=1)"; rc=$?
chk "ⓒ 좌석 못 읽음 → rc 1" "$rc" 1
has "$o" "ERROR land 목록 건너뜀 — tmux 목록 실패" "ⓒ 좌석 못 읽음 → 이유"
chk "ⓒ 좌석 못 읽음 → 계획 0" "$([ -e "$PLAN" ] && echo yes || echo no)" no

echo "== ⓕ 계획 실행 순간 다시 잰다(= 오빠 h)"
o="$(lp)"; chk "ⓕ 다시 만든 계획 = 3곳" "$(grep -c '^land_rm ' "$PLAN")" 3
echo late > "$W/land-done2/late"                                   # 만든 뒤 생긴 미커밋
git -C "$W/land-done3" checkout -q --detach "$C1"                     # 만든 뒤 HEAD 바뀜(여전히 main 조상)
r="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" bash "$PLAN" 2>&1 )"; rc=$?
chk "ⓕ 계획 rc 0" "$rc" 0
has "$r" "removed $W/land-done" "ⓕ 검사 통과 = git worktree remove"
chk "ⓕ land-done 지워짐" "$(isd "$W/land-done")" no
has "$r" "skip $W/land-done2 — 미커밋 1줄" "ⓕ 만든 뒤 미커밋 = skip"
has "$r" "skip $W/land-done3 — HEAD 바뀜" "ⓕ 만든 뒤 HEAD 바뀜 = skip(낡은 목록으로 지우기 0)"
chk "ⓕ land-done2 남음" "$(isd "$W/land-done2")" yes
chk "ⓕ land-done3 남음" "$(isd "$W/land-done3")" yes
for n in land-dirty land-alive land-locked land-unlanded nano-x; do chk "ⓕ $n 남음" "$(isd "$W/$n")" yes; done
r="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" FAKE_TMUX_ERR=1 bash "$PLAN" 2>&1 )"; rc=$?
chk "ⓕ 실행 때 좌석 못 읽음 → 중단 rc 1" "$rc" 1
has "$r" "중단 — tmux 목록 실패(rc=1)(지우기 0)" "ⓕ 중단 이유"

echo "== ⓐ 재설계 r3-1: 사본마다 직전에 좌석 목록을 새로 읽는다(처리 중 열린 좌석 skip)"
land_reset() {   # ⓕ 가 남긴 얼룩(land-done2 미커밋 · land-done/done3 삭제·HEAD 이동)을 대상 3곳 깨끗한 상태로 되돌린다
  rm -f "$W/land-done2/late"
  for n in land-done land-done3; do
    if [ -d "$W/$n" ]; then git -C "$W/$n" checkout -q --detach "$C2"; else GIT worktree add -q --detach "$W/$n" "$C2"; fi
  done
}
land_reset
rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/cnt"; : > "$T/panes"
o="$(lp FAKE_TMUX_CNT="$T/cnt" FAKE_TMUX_AT=3 FAKE_LATE_PANE="$W/land-done2")"; rc=$?
chk "ⓐ rc 0" "$rc" 0
has "$o" "LAND-PLAN 2곳 2000KB" "ⓐ 앞 사본을 처리하는 사이 열린 좌석은 계획 밖(3→2곳)"
hasnt "$(grep '^land_rm ' "$PLAN")" "$W/land-done2 " "ⓐ B(land-done2) land_rm 줄 없음"
has "$o" "KEEP land-done2 — 좌석·프로세스 살아 있음" "ⓐ B KEEP 이유 1줄"
has "$o" "LAND land-done3 sha=" "ⓐ 뒤 사본은 새 목록으로 재판단"
rm -f "$T/cnt2"; o="$(lp)"; chk "ⓐ 다시 3곳 계획" "$(grep -c '^land_rm ' "$PLAN")" 3
r="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" \
  FAKE_TMUX_CNT="$T/cnt2" FAKE_TMUX_AT=2 FAKE_LATE_PANE="$W/land-done2" bash "$PLAN" 2>&1 )"; rc=$?
chk "ⓐ 계획 실행 rc 0" "$rc" 0
has "$r" "removed $W/land-done" "ⓐ 계획 첫 사본 = 지움"
has "$r" "skip $W/land-done2 — 좌석·프로세스 살아 있음" "ⓐ 실행 중 열린 좌석 = 지우기 직전 skip"
chk "ⓐ land-done2 남음" "$(isd "$W/land-done2")" yes
chk "ⓐ land-done 지워짐" "$(isd "$W/land-done")" no

cat > "$T/fake/ft-hil" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_HIL_LOG"; echo "! bash /tmp/h77"
EOF
chmod +x "$T/fake/ft-hil"

cat > "$T/fake/mbox.sh" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_MBOX_FAIL:-0}" = 1 ] && exit 1
printf '%s\n' "$*" >> "$FAKE_MBOX_LOG"
EOF
chmod +x "$T/fake/mbox.sh"
mkdir -p "$REPO/.fable-team"
printf '{"_master":"m#1","m#1":{"role":"master"}}\n' > "$REPO/.fable-team/seats.json"
printf '{"_master":"m#1","m#1":{"role":"master"}}\n' > "$REPO/.fable-team/seats-harness.json"
lrun() { ( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_ROOT="$REPO" FT_WT_CLEAN_DIR="$T/state/wt-clean" FT_WT_SCAN_ROOT="$REPO" \
  FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN="$T/fake/lsof" FT_DU_BIN="$T/fake/du" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" \
  FT_MBOX_SH="$T/fake/mbox.sh" FT_WT_ARCHIVE=0 FT_HIL_BIN="$T/fake/ft-hil" FAKE_HIL_LOG="$T/hil.log" FAKE_MBOX_LOG="$T/mbox.log" "$@" \
  bash "$T/bin/ft-wt-sweep.sh" --launchd 2>&1 ); }

# ⓐ 계획 실행에서 land-done·land-done3 이 지워졌다 — ⓑ 부터는 대상 3곳을 다시 채운다
land_reset
chk "ⓑ 준비: 대상 3곳 복구" "$(isd "$W/land-done"):$(isd "$W/land-done2"):$(isd "$W/land-done3")" yes:yes:yes

echo "== ⓑ 재설계 r3-1: tmux 오류 글자를 «좌석 0» 으로 읽지 않는다"
mv "$PLAN" "$T/plan.keep2" 2>/dev/null; rm -f "$PLAN.sig" "$PLAN.sent"
o="$(lp FAKE_TMUX_ERR=1 FAKE_TMUX_ERR_TEXT='error connecting to /tmp/tmux-501/default (Permission denied)')"; rc=$?
chk "ⓑ tmux 연결 오류 → rc 1" "$rc" 1
has "$o" "ERROR land 목록 건너뜀 — tmux 목록 실패(rc=1)" "ⓑ 중단 + ERROR"
has "$o" "error connecting to /tmp/tmux-501/default (Permission denied)" "ⓑ 오류 글자 그대로"
chk "ⓑ 계획 0" "$([ -e "$PLAN" ] && echo yes || echo no)" no

# 대상 3곳 목록으로 되돌린다(ⓐ 실행에서 land-done 이 지워졌으므로 다시 만든다)
o="$(lp)"; chk "ⓑ 준비: 계획 3곳" "$(grep -c '^land_rm ' "$PLAN")" 3

echo "== ⓒ 재설계 r3-1: 계획을 ft-hil 에 등록하고 ! bash /tmp/h<N> 한 줄을 알림에 싣는다"
: > "$T/hil.log"; rm -f "$PLAN.sent"; : > "$T/panes"
o="$(lp FT_HIL_BIN="$T/fake/ft-hil" FAKE_HIL_LOG="$T/hil.log")"
chk "ⓒ 등록기 대역 호출 1회" "$(grep -c . "$T/hil.log")" 1
has "$(cat "$T/hil.log")" "--add $PLAN" "ⓒ 등록 대상 = 계획 파일"
has "$o" "! bash /tmp/h77" "ⓒ 알림 줄에 h 진입점 한 줄"
chk "ⓒ 알림은 1줄" "$(printf '%s\n' "$o" | grep -c '^\[HIL\] seat=byz-harness-wt-land')" 1

# 등록기 자체가 실패해도 계획·알림은 남는다(경로로 후퇴)
o="$(lp FT_HIL_BIN="$T/fake/없는-hil")"
has "$o" "스크립트 $PLAN" "ⓒ 등록기 실패 = 경로 안내로 후퇴"

# ⓓ 준비: 대상 3곳을 깨끗한 상태로 다시 채운다
land_reset
rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/mbox.log" "$T/hil.log"

echo "== ⓓ 재설계 r3-1: «보냄» 표지는 알림이 실제로 나간 뒤에만 · 표지 없으면 같은 목록도 재발송"
o="$(lrun)"
chk "ⓓ 알림 성공 → .sent = 보낸 목록 해시" "$(sent_is_sig "$PLAN")" yes
chk "ⓓ mbox 로 1회 나감" "$(grep -c . "$T/mbox.log")" 1
has "$(cat "$T/mbox.log")" "! bash /tmp/h77" "ⓓ 나간 알림에 h 진입점"
o="$(lrun)"
chk "ⓓ 표지 있음 = 재발송 0" "$(grep -c . "$T/mbox.log")" 1
rm -f "$PLAN.sent"; o="$(lrun)"
chk "ⓓ 표지 없으면 같은 목록도 재발송" "$(grep -c . "$T/mbox.log")" 2
rm -f "$PLAN.sent" "$T/mbox.log"; o="$(lrun FAKE_MBOX_FAIL=1)"
chk "ⓓ 알림 실패 = 표지 0" "$([ -e "$PLAN.sent" ] && echo yes || echo no)" no
o="$(lrun)"
chk "ⓓ 실패 뒤 다음 pass 재발송" "$(grep -c . "$T/mbox.log")" 1
chk "ⓓ 재발송 성공 뒤 표지" "$(sent_is_sig "$PLAN")" yes
chk "ⓓ 삭제 호출 0 — land-done 살아 있음" "$(isd "$W/land-done")" yes

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
