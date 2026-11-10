#!/bin/bash
# r403 — 라이브 bin(조상 `.fable-team` 없음)의 ft-mbox 가 우편함 루트를 ①FT_MBOX_DIR ②스크립트 조상
# ③cwd git 공용 루트의 `.fable-team/comm`(실재할 때만) ④NO_MAILBOX_ROOT rc2 순으로 찾고,
# doorbell 줄이 `FT_MBOX_DIR=<comm>` 를 실어 cwd 무관하게 같은 우편함을 연다.
# 픽스처 = 임시 git 리포 + 임시 HOME·TMPDIR + 가짜 tmux/pgrep(send-keys 로그) + 사본 bin — 실 tmux·실 우편함·홈 쓰기 0.
KIT="$(cd "$(dirname "$0")/../kit/fable-team/bin" && pwd)"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; echo "     rc=$RC out=${OUT:0:400}"; }
TO='byz-zz-nano-q#0'; FROM='byz-zz-master-claude#1'

mkdir -p "$T/live/bin" "$T/fake" "$T/home" "$T/tmp" "$T/repo/.fable-team/comm" "$T/repo/.fable-team/bin"
for f in ft-mbox.sh ft-mbox.py ft-lib.sh; do cp "$KIT/$f" "$T/live/bin/"; cp "$KIT/$f" "$T/repo/.fable-team/bin/"; done
git -C "$T/repo" init -q && git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
  && git -C "$T/repo" worktree add -q "$T/repo/.worktrees/w1" -b w1 || { echo "FAIL 픽스처 git"; exit 1; }
TLOG="$T/tmux.log"; : > "$TLOG"
cat > "$T/fake/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  has-session) exit 0 ;;
  list-panes) if [ "$2" = -a ]; then echo "$FAKE_TO|%9"; else echo "$FAKE_PID"; fi ;;
  capture-pane) : ;;
  send-keys) [ "$4" = -l ] && printf '%s\n' "$5" >> "$TLOG" ;;
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/fake/pgrep"
chmod +x "$T/fake/tmux" "$T/fake/pgrep"
# 격리 env — 실 HOME·TMPDIR·FT_* 를 끊는다.
run() {  # <cwd> <명령…>
  OUT="$(cd "$1" && shift && env -u FT_MBOX_DIR -u FT_SEATS_JSON -u FT_ROOT HOME="$T/home" TMPDIR="$T/tmp" \
    PATH="$T/fake:$PATH" TLOG="$TLOG" FAKE_TO="$TO" FAKE_PID=$$ FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    FT_MBOX_DOORBELL_MIN=0 "$@" 2>&1)"; RC=$?
}
comms() { find "$T" -type d -name comm -path '*/.fable-team/comm' | sort | tr '\n' ' '; }
COMM="$T/repo/.fable-team/comm"; BASE_COMMS="$(comms)"

# ⓐ 명시 FT_MBOX_DIR — cwd=/tmp 라도 rc0
run /tmp env FT_MBOX_DIR="$COMM" bash "$T/live/bin/ft-mbox.sh" peek X
[ "$RC" = 0 ] && ok "ⓐ 명시 FT_MBOX_DIR · cwd=/tmp rc0" || bad "ⓐ 명시 FT_MBOX_DIR · cwd=/tmp rc0"

# ⓑ cwd=워크트리 · env 없음 → 리포 루트 comm(③) · 워크트리 안 생성 0 · sh `_seats_json` 도 같은 루트(tick → quiet)
run "$T/repo/.worktrees/w1" bash "$T/live/bin/ft-mbox.sh" peek X
{ [ "$RC" = 0 ] && [ ! -e "$T/repo/.worktrees/w1/.fable-team" ]; } && ok "ⓑ cwd 워크트리 → 리포 루트 comm rc0 · 워크트리 생성 0" || bad "ⓑ cwd 워크트리 → 리포 루트 comm rc0 · 워크트리 생성 0"
echo "{\"$TO\":{\"tick\":\"t\"}}" > "$T/repo/.fable-team/seats.json"
run "$T/repo/.worktrees/w1" bash "$T/live/bin/ft-mbox.sh" send "$TO" "$FROM" "ⓑ quiet 확인"
{ [ "$RC" = 0 ] && echo "$OUT" | grep -qF "file=$COMM/mailbox.jsonl" && echo "$OUT" | grep -qF 'doorbell=quiet'; } \
  && ok "ⓑ sh·py 같은 루트(file=리포 comm · seats tick → quiet)" || bad "ⓑ sh·py 같은 루트(file=리포 comm · seats tick → quiet)"
rm -f "$T/repo/.fable-team/seats.json"
run "$T/repo/.worktrees/w1" bash "$T/live/bin/ft-mbox.sh" recv "$TO" >/dev/null

# ⓒ cwd=/tmp · env 없음 → NO_MAILBOX_ROOT rc2 · 새 comm 0
run /tmp bash "$T/live/bin/ft-mbox.sh" peek X
{ [ "$RC" = 2 ] && echo "$OUT" | grep -qF NO_MAILBOX_ROOT && echo "$OUT" | grep -qF 'comm 없음' && [ "$(comms)" = "$BASE_COMMS" ]; } \
  && ok "ⓒ cwd=/tmp → NO_MAILBOX_ROOT rc2 · 새 comm 0" || bad "ⓒ cwd=/tmp → NO_MAILBOX_ROOT rc2 · 새 comm 0"

# ⓓ send 의 doorbell 줄 = `[발주 #<seq>] FT_MBOX_DIR=<comm> bash <live>/ft-mbox.sh recv <to> — …` 글자 그대로 · /tmp 에서 실행 → READ
: > "$TLOG"
run "$T/repo/.worktrees/w1" bash "$T/live/bin/ft-mbox.sh" send "$TO" "$FROM" "ⓓ 본문" --urgent
SEQ="$(echo "$OUT" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)"
WANT="[발주 #$SEQ] FT_MBOX_DIR=$COMM bash $T/live/bin/ft-mbox.sh recv $TO — 실행하고 그 안의 지시를 즉시 착수하라"
LINE="$(head -1 "$TLOG")"
{ [ "$RC" = 0 ] && [ -n "$SEQ" ] && [ "$LINE" = "$WANT" ] && [ "${LINE%% *}" = "[발주" ]; } \
  && ok "ⓓ doorbell 줄 글자 그대로 · 머리 [발주 #N] 첫 토큰" || { bad "ⓓ doorbell 줄 글자 그대로 · 머리 [발주 #N] 첫 토큰"; echo "     line=$LINE"; echo "     want=$WANT"; }
CMD="${LINE#\[발주 #$SEQ\] }"; CMD="${CMD%% — *}"
run /tmp bash -c "$CMD"
{ [ "$RC" = 0 ] && echo "$OUT" | grep -q "^READ .*#$SEQ"; } && ok "ⓓ doorbell 줄을 cwd=/tmp 에서 실행 → READ #$SEQ" || bad "ⓓ doorbell 줄을 cwd=/tmp 에서 실행 → READ #$SEQ"

# ⓔ 옛 설치 꼴(<리포>/.fable-team/bin 사본) · cwd=/tmp · env 없음 → 조상 유도 그대로
run /tmp bash "$T/repo/.fable-team/bin/ft-mbox.sh" peek X
R1=$RC
run /tmp bash "$T/repo/.fable-team/bin/ft-mbox.sh" send "$TO" "$FROM" "ⓔ 본문"
{ [ "$R1" = 0 ] && [ "$RC" = 0 ] && echo "$OUT" | grep -qF "file=$COMM/mailbox.jsonl" && [ "$(comms)" = "$BASE_COMMS" ]; } \
  && ok "ⓔ 옛 꼴 조상 유도 불변(peek rc0 · send file=리포 comm)" || bad "ⓔ 옛 꼴 조상 유도 불변(peek rc0 · send file=리포 comm)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" = 0 ]
