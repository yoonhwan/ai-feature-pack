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
if [ -n "${FAKE_TMUX_CNT:-}" ]; then   # 몇 번째 호출부터 «새 좌석»·«오류» 가 보이는지 — 재검사 시점을 재는 대역(r880 고침 1·7)
  c="$(cat "$FAKE_TMUX_CNT" 2>/dev/null || echo 0)"; c=$((c+1)); echo "$c" > "$FAKE_TMUX_CNT"
  [ "$c" -ge "${FAKE_TMUX_ERR_AT:-999999}" ] && { echo "${FAKE_TMUX_ERR_TEXT:-Permission denied}"; exit 1; }
  [ "${FAKE_TMUX_ERR_EVEN:-0}" = 1 ] && [ $(( c % 2 )) -eq 0 ] && { echo "${FAKE_TMUX_ERR_TEXT:-Permission denied}"; exit 1; }
  [ "$c" -ge "${FAKE_TMUX_AT:-999}" ] && { echo "$FAKE_LATE_PANE"; exit 0; }
fi
[ -n "${FAKE_TMUX_SLEEP:-}" ] && sleep "$FAKE_TMUX_SLEEP"   # 느린 tmux(고침 6)
[ -n "${FAKE_TMUX_NS_SLEEP:-}" ] && { echo "no server running on /tmp/fake"; sleep "$FAKE_TMUX_NS_SLEEP"; exit 1; }
[ -s "$FAKE_PANES" ] && { cat "$FAKE_PANES"; exit 0; }
exit 0   # 서버는 있고 pane 0 = 정상 rc0 빈 출력(문구 면제 0 이라 rc≠0 은 실패다)
EOF
printf '#!/usr/bin/env bash\nif [ -n "${FAKE_LSOF_RC_AT:-}" ]; then c="$(cat "$FAKE_LSOF_CNT" 2>/dev/null || echo 0)"; c=$((c+1)); echo "$c" > "$FAKE_LSOF_CNT"; [ "$c" -ge "$FAKE_LSOF_RC_AT" ] && { echo p1; exit 1; }; fi\necho p1; sed "s/^/n/" "$FAKE_CWDS"\n[ "${FAKE_LSOF_RC:-0}" = 0 ] || exit "${FAKE_LSOF_RC}"\n' > "$T/fake/lsof"
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

# 사람 승인 진입점(ft-hil)·알림(mbox) 대역 — 기본값으로 물려 준다(등록 실패는 계약 ⑥ 위반이라 시험마다 override)
cat > "$T/fake/ft-hil" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_HIL_TEXT:-}" ] && echo "$FAKE_HIL_TEXT"
[ "${FAKE_HIL_FAIL:-0}" = 1 ] && exit 9
[ "${FAKE_HIL_RC:-0}" != 0 ] && exit "${FAKE_HIL_RC}"
printf '%s\n' "$*" >> "$FAKE_HIL_LOG"; echo "! bash /tmp/h77"
EOF
cat > "$T/fake/mbox.sh" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_MBOX_FAIL:-0}" = 1 ] && exit 1
printf '%s\n' "$*" >> "$FAKE_MBOX_LOG"
EOF
REALPY="$(command -v python3)"   # realpath 실패 주입용 대역(정상일 때는 진짜 python3)
cat > "$T/fake/python3" <<PYEOF
#!/usr/bin/env bash
if [ -n "\${FAKE_PY_FAIL_AT:-}" ]; then
  c="\$(cat "\$FAKE_PY_CNT" 2>/dev/null || echo 0)"; c=\$((c+1)); echo "\$c" > "\$FAKE_PY_CNT"
  [ "\$c" -ge "\$FAKE_PY_FAIL_AT" ] && { echo "python3 실패"; exit 1; }
fi
[ "\${FAKE_PY_FAIL:-0}" = 1 ] && { echo "python3 실패"; exit 1; }
exec "$REALPY" "\$@"
PYEOF
chmod +x "$T/fake/ft-hil" "$T/fake/mbox.sh" "$T/fake/python3"; : > "$T/hil.log"; : > "$T/mbox.log"
lp() { ( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_WT_CLEAN_DIR="$T/state/wt-clean" FT_WT_SCAN_ROOT="$REPO" \
  FT_TMUX_BIN="$T/fake/tmux" FT_LSOF_BIN="$T/fake/lsof" FT_DU_BIN="$T/fake/du" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" \
  FT_HIL_BIN="$T/fake/ft-hil" FAKE_HIL_LOG="$T/hil.log" "$@" \
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
has "$o" "ERROR land 목록 건너뜀 — tmux pane 실패(rc=1)" "ⓒ 좌석 못 읽음 → 이유"
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
has "$r" "중단 — tmux pane 실패(rc=1)(지우기 0)" "ⓕ 중단 이유"

echo "== ⓐ 재설계 r3-1: 사본마다 직전에 좌석 목록을 새로 읽는다(처리 중 열린 좌석 skip)"
land_reset() {   # 앞선 칸이 남긴 얼룩(미커밋·삭제·HEAD 이동)을 대상 3곳 깨끗한 상태로 되돌린다
  rm -f "$W/land-done2/late"
  for n in land-done land-done2 land-done3; do
    if [ -d "$W/$n" ]; then git -C "$W/$n" checkout -q --detach "$C2" 2>/dev/null; else GIT worktree add -q --detach "$W/$n" "$C2"; fi
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
has "$o" "ERROR land 목록 건너뜀 — tmux pane 실패(rc=1)" "ⓑ 중단 + ERROR"
hasnt "$o" "^LAND land-done" "ⓑ 실패 출력은 쓰지 않는다(성공일 때만)"
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

# 계약 ⑥(DA r2 ⑥): 등록기 실패는 «보냈다» 가 아니다 — rc≠0 · 알림 0 · 표지 0 · 다음 pass 가 등록부터 다시
rm -f "$PLAN.sent"; : > "$T/hil.log"
o="$(lp FAKE_HIL_FAIL=1)"; rc=$?
chk "ⓒ 등록 실패 → rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
has "$o" "ERROR ft-hil 등록 실패" "ⓒ 등록 실패 → ERROR 1줄"
hasnt "$o" "! bash /tmp/h" "ⓒ 등록 실패 → 알림 0"
chk "ⓒ 등록 실패 → 보냄 표지 0" "$([ -e "$PLAN.sent" ] && echo yes || echo no)" no
chk "ⓒ 등록 실패여도 계획 파일은 남음" "$([ -f "$PLAN" ] && echo yes || echo no)" yes
rm -f "$PLAN.sent"; o="$(lp)"
chk "ⓒ 다음 pass 가 등록 재시도" "$(grep -c . "$T/hil.log")" 1
has "$o" "! bash /tmp/h77" "ⓒ 재시도 성공 → h 진입점"

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

echo "== ⓔ① DA r2 ①: tmux 가 준 심링크 경로도 «진짜 경로» 로 맞춰 비교한다"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
rm -f "$W/alias"; ln -s "$W/land-done" "$W/alias"
echo "$W/alias" > "$T/panes"; o="$(lp)"
has "$o" "KEEP land-done — 좌석·프로세스 살아 있음" "ⓔ① 별칭으로 열린 사본 = 목록 밖"
hasnt "$(grep '^land_rm ' "$PLAN")" "$W/land-done " "ⓔ① land_rm 줄 없음"
chk "ⓔ① 남은 대상 2곳" "$(grep -c '^land_rm ' "$PLAN")" 2
: > "$T/panes"; rm -f "$W/alias"

echo "== ⓔ③ DA r2 ③: 계획에 mtime 을 박고, 낡은 계획은 실행하지 않는다"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
o="$(lp)"; chk "ⓔ③ 계획 3곳" "$(grep -c '^land_rm ' "$PLAN")" 3
chk "ⓔ③ 계획 줄에 mtime(소수 초) 3번째 인자" "$(grep -cE '^land_rm .+ [0-9]+(\.[0-9]+)?  # [0-9]+ KB$' "$PLAN")" 3
sig0="$(cat "$PLAN.sig")"; cp "$PLAN" "$T/stale.hil"         # ① 낡을 계획을 먼저 떠 둔다
sleep 1.1; touch "$W/land-done"                                    # mtime 만 바꾼다(HEAD·내용 그대로)
o2="$(lp)"; chk "ⓔ③ mtime 이 바뀌면 재생성 해시도 달라짐" "$([ "$(cat "$PLAN.sig")" != "$sig0" ] && echo yes || echo no)" yes
r="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" bash "$T/stale.hil" 2>&1 )"; rc=$?
chk "ⓔ③ 낡은 계획 실행 rc 0" "$rc" 0
has "$r" "skip $W/land-done — mtime 바뀜" "ⓔ③ 낡은 계획은 지우지 않고 skip(이유 = mtime)"
chk "ⓔ③ land-done 남음(낡은 목록으로 지우기 0)" "$(isd "$W/land-done")" yes
rm -f "$T/stale.hil"

echo "== ⓔ④ DA r2 ④: 목록을 채우는 두 번째 호출의 실패도 검사한다(짝수 호출 실패 = 판정 불가)"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/cnt3"
o="$(lp FAKE_TMUX_CNT="$T/cnt3" FAKE_TMUX_ERR_EVEN=1 FAKE_TMUX_ERR_TEXT='Permission denied')"; rc=$?
chk "ⓔ④ 실패한 사본이 있으면 rc 1" "$rc" 1
has "$o" "판정 불가 land-" "ⓔ④ 실패 사본은 «판정 불가» 로그(ERROR 접두 0)"
has "$o" "ERROR land 판정 불가 " "ⓔ④ ERROR 는 요약 1줄"
chk "ⓔ④ ERROR 줄 수 = 1" "$(printf '%s\n' "$o" | grep -c '^ERROR')" 1
chk "ⓔ④ 판정 불가 사본은 계획에 없음" "$(printf '%s\n' "$o" | sed -n 's/^판정 불가 \(land-[^:]*\):.*/\1/p' | while read -r nm; do grep -q "^land_rm .*\b$nm\b" "$PLAN" && echo BAD; done | grep -c BAD)" 0
chk "ⓔ④ 판정 불가 사본 남음" "$(printf '%s\n' "$o" | sed -n 's/^판정 불가 \(land-[^:]*\):.*/\1/p' | while read -r nm; do isd "$W/$nm"; done | grep -c no)" 0

echo "== ⓔ⑤ DA r2 ⑤: tmux·lsof 호출에 시간 상한(기본 7초)"
chk "ⓔ⑤ 기본 상한 = 7초" "$(grep -c 'FT_WT_LIVE_SEC:-7' "$T/bin/ft-wt-sweep.sh")" 1
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
t0="$(date +%s)"; o="$(lp FAKE_TMUX_SLEEP=10 FT_WT_LIVE_SEC=2)"; rc=$?; el=$(( $(date +%s) - t0 ))
chk "ⓔ⑤ 느린 tmux → rc 1" "$rc" 1
has "$o" "ERROR land 목록 건너뜀 — tmux pane 실패(rc=124)" "ⓔ⑤ 시간 초과 = 못 읽음(좌석 0 아님)"
chk "ⓔ⑤ 상한에서 끊김(${el}s ≤ 6s · 주입 10s)" "$([ "$el" -le 6 ] && echo yes || echo no)" yes
# 계약 ⑥(h 등록 실패 rc≠0 · 재시도)은 위 ⓒ 칸이 닫는다.

echo "== ⓐ DA r3 ①: 경로는 바이트 그대로 — 뒤 공백·수직탭 들어간 별칭이 가리키는 사본은 «사용 중»"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
SP=" " ; VT="$(printf '\013')"
rm -f "$W/alias$SP" "$W/al${VT}ias"
ln -s "$W/land-done" "$W/alias$SP"; ln -s "$W/land-done2" "$W/al${VT}ias"
printf '%s\n%s\n' "$W/alias$SP" "$W/al${VT}ias" > "$T/panes"; o="$(lp)"
has "$o" "KEEP land-done — 좌석·프로세스 살아 있음" "ⓐ 뒤 공백 별칭 = 사용 중"
has "$o" "KEEP land-done2 — 좌석·프로세스 살아 있음" "ⓐ 수직탭 별칭 = 사용 중"
chk "ⓐ 남은 대상 1곳" "$(grep -c '^land_rm ' "$PLAN")" 1
: > "$T/panes"; rm -f "$W/alias$SP" "$W/al${VT}ias"

echo "== ⓑ DA r3 ④: lsof 가 부분 출력을 내고 rc≠0 이면 중단(계획 0)"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
o="$(lp FAKE_LSOF_RC=1)"; rc=$?
chk "ⓑ rc 1" "$rc" 1
has "$o" "ERROR land 목록 건너뜀 — lsof cwd 실패(rc=1)" "ⓑ 출력이 있어도 실패 = 중단"
chk "ⓑ 계획 0" "$([ -e "$PLAN" ] && echo yes || echo no)" no

echo "== ⓒ DA r3 ④: «no server running» 도 면제 0 — 지연이면 시간 초과 실패"
chk "ⓒ 시간 상한 기본 = 7초" "$(grep -c 'FT_WT_LIVE_SEC:-7' "$T/bin/ft-wt-sweep.sh")" 1
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
t0="$(date +%s)"; o="$(lp FAKE_TMUX_NS_SLEEP=10 FT_WT_RUN_SEC=2)"; rc=$?; el=$(( $(date +%s) - t0 ))
chk "ⓒ 시간 초과 → rc 1" "$rc" 1
has "$o" "ERROR land 목록 건너뜀 — tmux pane 실패(rc=124)" "ⓒ 문구로 면제하지 않는다"
chk "ⓒ 계획 0" "$([ -e "$PLAN" ] && echo yes || echo no)" no
chk "ⓒ 상한에서 끊김(${el}s ≤ 6s · 주입 10s)" "$([ "$el" -le 6 ] && echo yes || echo no)" yes

echo "== ⓓ DA r3 ⑤: 등록 rc≠0 에 오류 문구가 있어도 «성공» 이 아니다"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/hil.log"
o="$(lp FAKE_HIL_RC=9 FAKE_HIL_TEXT='번호 충돌: h77 사용 중')"; rc=$?
chk "ⓓ rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
has "$o" "ERROR ft-hil 등록 실패" "ⓓ rc≠0 = 등록 실패"
chk "ⓓ .sent 0" "$([ -e "$PLAN.sent" ] && echo yes || echo no)" no
hasnt "$o" "! bash /tmp/h" "ⓓ 알림 0"
rm -f "$PLAN.sent"; o="$(lp)"
chk "ⓓ 다음 실행이 등록 재시도" "$(grep -c . "$T/hil.log")" 1

echo "== ⓔ DA r3 미종결 ⑥: --launchd 가 land-plan 의 rc 를 그대로 반영"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/hil.log" "$T/mbox.log"
o="$(lrun FAKE_HIL_RC=17)"; rc=$?
chk "ⓔ 등록 실패면 --launchd rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
chk "ⓔ 표지 0" "$([ -e "$PLAN.sent" ] && echo yes || echo no)" no
rm -f "$PLAN.sent"; o="$(lrun)"; rc=$?
chk "ⓔ 정상이면 --launchd rc 0" "$rc" 0
chk "ⓔ 정상이면 표지 생김" "$(sent_is_sig "$PLAN")" yes

echo "== ⓕ DA r4 ①: 표지 해시가 같아 알림을 생략해도 «판정 불가» 가 있으면 최종 rc≠0 (--launchd 도)"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/cntF"
o="$(lrun FAKE_TMUX_CNT="$T/cntF" FAKE_TMUX_ERR_AT=6)"; rc=$?
chk "ⓕ 1회차(조회 실패 포함) rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
chk "ⓕ 1회차 계획 = 확정분 2곳" "$(grep -c '^land_rm ' "$PLAN")" 2
chk "ⓕ 1회차에 표지 생김" "$(sent_is_sig "$PLAN")" yes
rm -f "$T/cntF"
o="$(lrun FAKE_TMUX_CNT="$T/cntF" FAKE_TMUX_ERR_AT=6)"; rc=$?
has "$o" "LAND-NOTIFY 보냄 표지 있음" "ⓕ 2회차는 알림 생략 경로"
chk "ⓕ 표지 일치여도 rc≠0(--launchd 기록)" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
chk "ⓕ 2회차 ERROR 1줄" "$(printf '%s\n' "$o" | grep -c '^ERROR')" 1

echo "== ⓖ DA r4 ②: 한 건 실패에 ERROR 는 1줄(사본별 줄은 «판정 불가» 로그)"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/cntG"
o="$(lp FAKE_TMUX_CNT="$T/cntG" FAKE_TMUX_ERR_AT=6)"; rc=$?
chk "ⓖ rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
chk "ⓖ ERROR 줄 수 = 1" "$(printf '%s\n' "$o" | grep -c '^ERROR')" 1
has "$o" "판정 불가 land-" "ⓖ 사본별 줄은 ERROR 접두 0"
has "$o" "ERROR land 판정 불가 2곳" "ⓖ ERROR = 요약 1줄"

echo "== ⓗ 전수: 조회 자리마다 실패 → rc≠0 · ERROR 1줄 · (표지 있는/없는 경우)"
chk "ⓗ run7 호출 자리 = 4" "$(grep -c 'run7 "' "$T/bin/ft-wt-sweep.sh")" 4
hsite() {   # hsite <이름> — 자리별 실패 주입. per-copy 자리(tmux3·tmux4)는 표지 있는 경우까지 잰다.
  local nm="$1" cnt="$T/cnt_$1" o rc o2 rc2
  case "$nm" in
    tmux1) set -- FAKE_TMUX_CNT="$cnt" FAKE_TMUX_ERR_AT=1 ;;
    tmux3) set -- FAKE_TMUX_CNT="$cnt" FAKE_TMUX_ERR_AT=6 ;;   # 6·7번째 조회 = land-done3·land-unlanded
    tmux4) set -- FAKE_TMUX_CNT="$cnt" FAKE_TMUX_ERR_AT=5 ;;   # 5번째부터 = 확정 대상까지 실패
    lsof)  set -- FAKE_LSOF_RC=1 ;;
    realpath) set -- FAKE_PY_FAIL=1 ;;
    hil)   set -- FAKE_HIL_RC=9 ;;
  esac
  land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$cnt"
  o="$(lp "$@")"; rc=$?
  chk "ⓗ$nm 표지 없음 → rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
  chk "ⓗ$nm 표지 없음 → ERROR 1줄" "$(printf '%s\n' "$o" | grep -c '^ERROR')" 1
  case "$nm" in tmux3|tmux4) ;; *) return 0 ;; esac   # 시작 조회 실패·등록 실패는 계획이 없어 «표지 있음» 경우가 성립하지 않는다
  rm -f "$cnt" "$PLAN.sent"
  o="$(lrun "$@")"; rc=$?
  chk "ⓗ$nm 표지 만든 1회차 rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
  chk "ⓗ$nm 표지 생김" "$(sent_is_sig "$PLAN")" yes
  rm -f "$cnt"
  o2="$(lrun "$@")"; rc2=$?
  chk "ⓗ$nm 표지 있음 → rc≠0" "$([ "$rc2" -ne 0 ] && echo yes || echo no)" yes
  chk "ⓗ$nm 표지 있음 → ERROR 1줄" "$(printf '%s\n' "$o2" | grep -c '^ERROR')" 1
}
for site in tmux1 tmux3 tmux4 lsof realpath hil; do hsite "$site"; done

echo "== ⓘ DA r5 ①: 같은 초 안의 mtime 변경도 «바뀜» — 계획 해시·실행 재검사 둘 다"
land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent"
o="$(lp)"; sig0="$(cat "$PLAN.sig")"
chk "ⓘ 계획 3곳" "$(grep -c '^land_rm ' "$PLAN")" 3
sec="$(perl -MTime::HiRes=stat -e 'print int((Time::HiRes::stat($ARGV[0]))[9])' "$W/land-done")"
perl -MTime::HiRes=utime -e 'utime $ARGV[1], $ARGV[1], $ARGV[0]' "$W/land-done" "$sec"   # 같은 초 · 소수부만 .0 으로
chk "ⓘ 초는 그대로" "$(stat -f %m "$W/land-done")" "$sec"
r="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" bash "$PLAN" 2>&1 )"; rc=$?
chk "ⓘ 낡은 계획 실행 rc 0" "$rc" 0
has "$r" "skip $W/land-done — mtime 바뀜" "ⓘ 같은 초 안 변경도 skip(삭제 대역 호출 0)"
chk "ⓘ land-done 남음" "$(isd "$W/land-done")" yes
o="$(lp)"; chk "ⓘ 재생성 해시가 달라짐" "$([ "$(cat "$PLAN.sig")" != "$sig0" ] && echo yes || echo no)" yes

echo "== ⓙ DA r5 ②: 계획 «실행» 단계의 조회 실패 = 그 사본 skip · ERROR 1줄 · 최종 rc≠0"
jcase() {   # jcase <tmux|lsof|realpath> — 실행 단계에서만 실패(2~3번째 조회)
  local nm="$1" r rc ev
  case "$nm" in
    tmux)     ev="FAKE_TMUX_CNT=$T/cntJ_$1 FAKE_TMUX_ERR_AT=3" ;;
    lsof)     ev="FAKE_LSOF_CNT=$T/cntJ_$1 FAKE_LSOF_RC_AT=3" ;;
    realpath) ev="FAKE_PY_CNT=$T/cntJ_$1 FAKE_PY_FAIL_AT=3" ;;
  esac
  land_reset; rm -f "$PLAN" "$PLAN.sig" "$PLAN.sent" "$T/cntJ_$1"; o="$(lp)"
  r="$( cd "$T" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWDS="$T/cwds" $ev bash "$PLAN" 2>&1 )"; rc=$?
  chk "ⓙ$nm 실행 최종 rc≠0" "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
  chk "ⓙ$nm ERROR 1줄" "$(printf '%s\n' "$r" | grep -c '^ERROR')" 1
  has "$r" "removed $W/land-done" "ⓙ$nm 실패 전 사본은 정상 삭제"
  has "$r" "skip $W/land-done2 — 좌석 목록 못 읽음" "ⓙ$nm 실패한 사본은 지우지 않음"
  chk "ⓙ$nm land-done2 남음" "$(isd "$W/land-done2")" yes
  has "$r" "ERROR 판정 불가 " "ⓙ$nm ERROR = 마지막 요약 1줄"
}
for j in tmux lsof realpath; do jcase "$j"; done

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
