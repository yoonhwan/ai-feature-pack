#!/usr/bin/env bash
# test_nano_close_after_approve_driver_r1670.sh — r1670 닫기 집행(ⓓ) + 주기 실행(ⓔ) + 회귀(ⓖ) + 변이 M2.
#   ⓓ ft-nano-close.sh --approved <판정문> = ⑤ cherry·⑥ 착지 증거 면제 · 그 자리에서 승인 갈래를 «다시» 계산 · 브랜치·워크트리 삭제 0 · 원장 approved=1 set=<HEAD> · 출력 CLOSED <좌석> approved=1
#   ⓔ ft_stall_scan.py — FT_NANO_AUTO_CLOSE=1 일 때만 close-due 의 «갈래=승인» 줄마다 1회 · 회차 상한 = 줄 수 · 같은 좌석 실패는 같은 HEAD 동안 재시도 0 · 꺼짐 = 지금 출력 그대로
#   본문 ⓔ = tests/scripts/test_nano_auto_close_r1670.py(단위: Scan.auto_close) · 변이 M2 = 그 시험이 잡는다
#   ⓐⓑⓒⓕ + 변이 M1·M3 = 짝 파일 test_nano_close_after_approve_r1670.sh (카드 «시험 ≤120줄» — 사례별 2파일)
#   임시 리포·가짜 tmux·스텁만 쓴다 — 실 명부·tmux·gh·네트워크·실 좌석 0 · sleep 0 · 사례 70초 안
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
ulimit -u 2000 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }
eq()   { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got=[$1] want=[$2])"; fi; }

echo "== 짝 cmp · bash -n · Python 구문"
for f in ft-nano-close.sh ft-nano-close-due.sh ft-nano-accept.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"
  bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"
  /bin/bash -n "$BIN/$f" && ok "/bin/bash 3.2 -n $f" || bad "/bin/bash 3.2 -n $f"
done
cmp -s "$BIN/ft_stall_scan.py" "$KIT/ft_stall_scan.py" && ok "cmp bin == kit ft_stall_scan.py" || bad "cmp 다름 ft_stall_scan.py"
python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$BIN/ft_stall_scan.py" && ok "ft_stall_scan.py 구문" || bad "ft_stall_scan.py 구문"

echo "== ⓔ 주기 실행(단위) + 변이 M2"
( cd "$HERE" && R1670_BIN="$KIT" timeout 70 python3.11 -m pytest -q -p no:cacheprovider scripts/test_nano_auto_close_r1670.py > "$T/py.log" 2>&1 )
ck=$?; [ "$ck" -eq 0 ] && ok "ⓔ $(grep -Eo '[0-9]+ passed' "$T/py.log" | tail -1)" || { bad "ⓔ pytest rc=$ck"; sed -n '1,40p' "$T/py.log"; }

echo "== ⓓ 닫기 집행 — ft-nano-close.sh --approved"
SEAT='byz-harness-nano-ok#0'; REPO="$T/repo"; NW="$REPO/.worktrees/v65-ok"
mkdir -p "$REPO/.fable-team/comm/bodies" "$REPO/design/teams/harness/indices/진행" "$REPO/design/harness" "$T/bin" "$T/fake" "$T/sheet/.fable-team/state"; COMM="$REPO/.fable-team/comm"
git -C "$REPO" init -q -b main; git -C "$REPO" commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$NW" -b nano/ok
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
echo x > "$NW/x"; git -C "$NW" add x; git -C "$NW" commit -q -m work; H="$(git -C "$NW" rev-parse HEAD)"
git -C "$REPO" remote add origin "$REPO"
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse main)"
git -C "$REPO" update-ref refs/remotes/origin/nano/ok "$H"   # 원격 보존(로컬 전송 · 네트워크 0)
cp "$BIN/ft-nano-close.sh" "$BIN/ft-nano-close-due.sh" "$BIN/ft-nano-accept.sh" "$BIN/ft-nano-evidence-check.sh" "$BIN/ft-nano-cherry-gate.sh" \
   "$BIN/ft-wt-sweep.sh" "$BIN/ft-team-lib.sh" "$BIN/ft-card-target-lib.sh" "$BIN/ft_git_capped.py" "$BIN/ft_teamset.py" "$BIN/ft_team_lib.py" \
   "$BIN/ft-sheet-events.sh" "$BIN/ft_sheet_events.py" "$BIN/ft_sheet_confirm.py" "$BIN/ft_sheet_key.py" "$BIN/ft_board_env.py" "$BIN/ft_board_mail.py" "$T/bin/"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "slots ok"\n' > "$T/bin/ft-nano-slots.sh"
printf '#!/bin/sh\n[ "$1" = turn ] && { echo "IDLE - - - jsonl"; exit 0; }\nexit 1\n' > "$T/bin/ft-seat-status.sh"
printf '#!/bin/sh\necho "${FAKE_QUIET:-OK}"\n' > "$T/bin/quiet"   # 닫기 금지(ⓕ) 스텁 — BUSY <사유> 로 재현   # 승인 갈래 재계산용 좌석 상태 스텁
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) cat "$FAKE_PANES";;
  display-message) cat "$FAKE_CWD";;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
  *) exit 9;;
esac
EOF
chmod +x "$T/bin/"*.sh "$T/bin/"*.py "$T/fake/tmux" 2>/dev/null
printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s' "$NW" > "$T/cwdseat"
printf '산출\n' > "$T/result.md"; printf '산출 보고\n' > "$COMM/bodies/3.txt"
printf '{"seq": 3, "from": "%s", "to": "byz-harness-master-pi#196", "body": "산출 보고"}\n' "$SEAT" > "$COMM/mailbox.jsonl"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | m | 현역 |\n' > "$REPO/design/TEAMS.md"
setup() {  # 카드·판정문·명부·원장·스텁 로그를 «정상(승인 갈래 참)» 으로 리셋
  : > "$T/log"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  printf '{"%s": {"role": "nano", "agent": "claude", "index": "design/teams/harness/indices/진행/ok.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-harness.json"
  printf '단계별 초: 1\n\n# 승인 갈래 판정\n\n## §1 판정: APPROVE\n\n승인 sha: %s\n' "$H" > "$REPO/design/harness/DA-ok.md"
  printf '# 인덱스: ok\n## 상태\n- 세트: %s\n- DA 판정: %s/design/harness/DA-ok.md#§1\n- 인수: %s · 남은 일: 검증=arch · 쓴 이: m\n' \
    "$H" "$REPO" "$H" > "$REPO/design/teams/harness/indices/진행/ok.md"
}
close() { ( cd "$REPO" && env -i HOME="$HOME" PATH="$T/fake:$PATH" FT_SHEET_ROOT="$T/sheet" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwdseat" FAKE_LOG="$T/log" FT_PACK_ROOT="$T/pack" FAKE_QUIET="${FAKE_QUIET:-OK}" \
  FT_CLOSE_DUE_QUIET="$T/bin/quiet" \
  FT_SEATS_JSON="$REPO/.fable-team/seats-harness.json" FT_NANO_PREFIX=byz-harness-nano- FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$COMM" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 FT_ROOT="$REPO" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 3 "$@" 2>&1 ); }
untouched() {  # 닫기 0 확인 — 명부·원장·브랜치·워크트리·kill 그대로
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-harness.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$T/ledger.md" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
  git -C "$REPO" rev-parse --verify -q refs/heads/nano/ok >/dev/null && ok "  └ 브랜치 그대로" || bad "$1: 브랜치 삭제"
  [ -d "$NW" ] && ok "  └ 워크트리 그대로" || bad "$1: 워크트리 삭제"
  [ ! -s "$T/log" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
}

setup; OUT="$(close --approved "$REPO/design/harness/DA-ok.md")"; RC=$?
[ "$RC" -eq 0 ] && ok "ⓓ rc=0" || { bad "ⓓ rc=$RC (전문 ↓)"; printf '%s\n' "$OUT" | tail -25; }
has "$OUT" "INFO ⑤ cherry 건너뜀 — 승인 갈래" "ⓓ ⑤ cherry = 가지 비교 0(INFO)"
has "$OUT" "APPROVE-OK $SEAT set=$H" "ⓓ ⑥ 자리 = 승인 갈래 재계산(APPROVE-OK)"
has "$OUT" "CLOSED $SEAT approved=1 set=$H" "ⓓ 출력 = CLOSED <좌석> approved=1 set=<HEAD>"
has "$(cat "$T/ledger.md")" "approved=1 set=$H" "ⓓ 원장 행 = approved=1 set=<HEAD>"
has "$(cat "$T/ledger.md")" "mode=approved" "ⓓ 원장 wt= 칸 = mode=approved(계획 0)"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-harness.json" >/dev/null && ok "ⓓ 명부 CLOSED" || bad "ⓓ 명부에 남음"
git -C "$REPO" rev-parse --verify -q refs/heads/nano/ok >/dev/null && ok "ⓓ 브랜치 보존(삭제 0)" || bad "ⓓ 브랜치 삭제됨"
[ -d "$NW" ] && ok "ⓓ 워크트리 보존(삭제 0)" || bad "ⓓ 워크트리 삭제됨"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "ⓓ 정리 계획 0(착지 전 산출 보존)" || bad "ⓓ 정리 계획 생김"

setup; printf '단계별 초: 1\n\n## §1 판정: HOLD\n\n승인 sha: %s\n' "$H" > "$REPO/design/harness/DA-ok.md"
OUT="$(close --approved "$REPO/design/harness/DA-ok.md")"; RC=$?
eq "$RC" "1" "ⓓ 판정 HOLD → rc=1(REJECT)"
has "$OUT" "DA 판정 값이 APPROVE 아님" "ⓓ 사유 = 게이트가 낸 APPROVE-REJECT(값 APPROVE 아님)"
untouched "ⓓ HOLD"

setup; FAKE_QUIET="BUSY 도구 셸 실행" OUT="$(close --approved "$REPO/design/harness/DA-ok.md")"; RC=$?   # ② AUTO=0 직접 재계산도 닫기 금지
[ "$RC" -eq 1 ] && has "$OUT" "도구 셸 실행" "② 직접 재계산(AUTO=0)도 도구 셸이면 거절" || bad "② BUSY rc=$RC ← ${OUT:0:400}"
untouched "② BUSY"
setup; OUT="$(close --approved "$T/없는판정문.md")"; RC=$?
[ "$RC" -eq 1 ] && has "$OUT" "--approved 판정문 없음" "ⓓ 없는 판정문 → REJECT" || bad "ⓓ 없는 판정문 rc=$RC"
untouched "ⓓ 없는 판정문"
setup; OUT="$(close --approved "$REPO/design/harness/DA-ok.md" --landed-pr 9)"; RC=$?
[ "$RC" -eq 2 ] && has "$OUT" "동시에 못 쓴다" "ⓓ --landed-pr 과 동시 = usage 2" || bad "ⓓ 모드 충돌 rc=$RC ← ${OUT:0:200}"
untouched "ⓓ 모드 충돌"

echo "== ⓖ 회귀 — 기본(env 0) 경로는 지금 그대로"
setup; OUT="$(close --result "$T/result.md" --recv 3)"; RC=$?   # --approved 없음 · ⑤ cherry 게이트가 실제로 돈다
has "$OUT" "REJECT $SEAT" "ⓖ 인자 없이 = 기존 경로(승인 갈래 0 · cherry 게이트가 막는다)"
hasnt "$OUT" "approved=1" "ⓖ 옛 경로에 approved 꼬리 0"
untouched "ⓖ 옛 경로"

echo "== 결과: FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || exit 1
