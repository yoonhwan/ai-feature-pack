#!/usr/bin/env bash
# _nano_record_r1717_close_fixture.sh — r1717 ⑭·⑲·E8 ⓒⓔ 용(사례 아님 · source 전용 · 실행 비트 0): «실» ft-nano-close.sh 사본을 r1717 픽스처 세계에서 돌린다.
#   먼저 _nano_record_r1717_fixture.sh 를 source 하고 world 를 부른 뒤 closebin 1회. 꼴 = test_nano_close_landed_pr_r1011.sh(가짜 gh·tmux · 스텁 quiesce·reap · 네트워크 0).
#   closebin [<bin 폴더>] → CB = 닫기 도구 사본 폴더 · NCREAL = 그 사본을 시험 env 로 부르는 껍데기(ft_stall_scan 의 FT_NANO_CLOSE 자리에도 쓴다)
#     리포 식별자 = origin 설정값(github 꼴) · 전송은 url.<로컬>.insteadOf 로 로컬 bare 에 · NLEDGER = 나노 원장(행 수 = 닫힘 수)
#   nwt <key> → NW = 좌석 워크트리($ROOT/.worktrees/v65-<key> · 가지 nano/<key>) — 살아 있는 좌석 닫기(③)에 필요
#   cprep <좌석> = gh 응답(MERGED · head = 직전 land 의 PH)·pane 목록 준비 · CLOSE_LIVE=1 이면 그 좌석 tmux 세션이 살아 있는 꼴(kill-session 이 TMUX_LOG 에 남는다)
#   nclose <좌석> [닫기 인자…] → OUT·RC
closebin() {
  local src="${1:-$KIT}" f
  CB="$T/closebin"; NLEDGER="$T/nano-ledger.md"; NCREAL="$T/nc-real.sh"; mkdir -p "$CB" "$T/cfake" "$T/sheet/.fable-team/state"; : > "$NLEDGER"
  for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh ft-wt-sweep.sh ft-team-lib.sh \
           ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft_team_lib.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py \
           ft_board_mail.py ft-approval-equiv.sh ft_approval_equiv.py; do cp "$src/$f" "$CB/"; done
  printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$CB/ft-seat-quiesce.sh"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$CB/ft-seat-reap.sh"
  printf '#!/bin/sh\necho "slots ok"\n' > "$CB/ft-nano-slots.sh"; printf '#!/bin/sh\necho "PI-REAPED $1 left=0"\n' > "$CB/ft-opencode-reap.sh"
  cat > "$T/cfake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) printf '%s' "$FAKE_CWD";;
  has-session) exit 1;;
esac
EOF
  cat > "$T/cfake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"; cat "$FAKE_GH_JSON"
EOF
  cat > "$NCREAL" <<EOF
#!/usr/bin/env bash
cd "$ROOT" && exec env -i HOME="$HOME" PATH="$T/cfake:$PATH" LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 FT_SHEET_ROOT="$T/sheet" FT_PACK_ROOT="$PACK" \\
  FAKE_PANES="$T/panes" FAKE_CWD="\${NC_CWD:-$PACK}" TMUX_LOG="$TMUX_LOG" FAKE_GH_LOG="$T/gh.log" FAKE_GH_JSON="$T/gh.json" FT_ROOT="$ROOT" \\
  FT_NANO_PREFIX=byz-harness-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-harness.json" FT_NANO_LEDGER="$NLEDGER" FT_NANO_FEAT=main \\
  FT_INBOX_ROOT="$COMM" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$CB/ft-nano-close.sh" "\$@"
EOF
  chmod +x "$CB"/* "$T/cfake"/* "$NCREAL"
  g "$PACK" remote set-url origin https://github.com/r1717/pack.git; g "$PACK" config "url.$PREM.insteadOf" https://github.com/r1717/pack.git
  g "$ROOT" remote set-url origin https://github.com/r1717/byz.git; g "$ROOT" config "url.$CREM.insteadOf" https://github.com/r1717/byz.git
}
nwt() { NW="$ROOT/.worktrees/v65-$1"; [ -d "$NW" ] || g "$ROOT" worktree add -q "$NW" -b "nano/$1"; export NC_CWD="$NW"; }
cprep() {
  printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$Q" "$PH" > "$T/gh.json"
  if [ "${CLOSE_LIVE:-0}" = 1 ]; then printf '%s|%%1\n' "$1" > "$T/panes"; else : > "$T/panes"; fi
  touch "$ROOT/.fable-team/seats-harness.json"   # ③ 유휴 = 가짜 명부보다 새 파일 0(픽스처가 방금 만든 워크트리 파일을 «편집» 으로 세지 않게)
}
nclose() { cprep "$1"; OUT="$(bash "$NCREAL" "$@" 2>&1)"; RC=$?; }
