#!/usr/bin/env bash
# test_successor_open_watch_r1957.sh — r1957: 승계 발주 본문 «열린 칸 감시: » 1줄(ft-successor-open 검사·조립) + team-boot B2 본문.
#   ① 감시 줄 → 발주 본문 = 기억 로드 줄 바로 다음 · 본문 4행~ 에 다시 없음 ② «없음» 통과 · 같은 자리 ③ 줄 없음 REJECT rc1 · send 0
#   ④ 2줄 ⑤ 161자 ⑥ 빈 값 → REJECT(160자 = 통과) · ⑪ B2 CLOSEOUT 절 0 → «없음(새 생명 · CLOSEOUT <sha> 기준 …)» · ⑫ 절 2행 → 두 항목 모두 · ⑫b 합친 줄 161자↑ → B2 rc≠0 STOP
#   변이(사본에서만): M1 검사 무시 → ③ · M2 조립 위치 본문 끝 → ① · M3 4행~ 빼기 삭제 → ① · M4 길이 상한 삭제 → ⑤
# 격리: r1692 시험과 같은 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 앞 스텁) + 임시 리포 · team-boot 의 FT_SUCCESSOR_OPEN = 실제 개설 도구를 같은 스텁으로 부르는 감싸개 · 실 세션 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SO="$REPO/harness/kit/fable-team/bin/ft-successor-open.sh"
F="$T/fakebin"; lg="$T/calls.log"; R="$T/repo"; OLD="byz-t-old-claude#1"; NEW="byz-t-new-claude#2"
mkdir -p "$F" "$R"; git -C "$R" init -q; mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$F/$1"; chmod +x "$F/$1"; }
mkstub tmux 'case "$1" in has-session) [ -f "$OPENED" ] && exit 0; exit 1;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; : > "$OPENED"; exit 0'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; printf "%s" "$2" > "$SENT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit 0'
mkstub mbox 'exit 0'; : > "$F/mbox_doorbell.sh"; mkstub reach 'exit 0'; . "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T/sensors" ok; RES="$FT_RES_ROOT"; SENSORS="$T/sensors/fake-sensors"
mkdir -p "$RES/design" "$R/.fable-team" "$T/live"
printf '# TEAMS\n\n| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | byz-t-master-claude | 현역 |\n' > "$RES/design/TEAMS.md"
printf '{"%s":{"role":"master","model":"m"},"%s":{"role":"master","model":"m"}}\n' "$OLD" "$NEW" > "$RES/.fable-team/seats-t.json"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| t | byz-t-master-claude | — |\n' > "$T/teamset.md"
printf '<!-- S17-BOOT-BEGIN -->\n목적 0 = 진행 카드를 완성하고 닫는다.\n<!-- S17-BOOT-END -->\n' > "$T/gov.md"
printf '%s\n' "$T/live" > "$R/.fable-team/LIVE_ROOT"; SOENV=(HOME="$T/home" PANE_CWD="$T/pane" PATH="$F:$PATH" LOG="$lg" OPENED="$T/opened" SENT="$T/sent.txt" SENSORS="$SENSORS" FT_RES_ROOT="$RES"
  FT_TEAMSET_MD="$T/teamset.md" FT_GOV_MD="$T/gov.md" FT_SO_POLL=0 FT_SO_WAIT_MAX=3 FT_SEND_VERIFIED="$F/send" FT_MBOX_SH="$F/mbox" FT_REACH_CHECK="$F/reach")
so_run() {  # so_run <개설도구> — 본문 = $T/b.txt
  rm -f "$lg" "$T/opened" "$T/sent.txt"; rm -rf "$R/.fable-team/state"; : > "$lg"
  env "${SOENV[@]}" bash "$1" "$OLD" "$R" --name "$NEW" --agent claude --model m --body-file "$T/b.txt" > "$T/out" 2>&1; RC=$?
}
body() { printf '골 1\n골 2\n골 3\n본문 4행\n'; [ $# -gt 0 ] && printf '%s\n' "$@"; printf '본문 끝\n'; }
after() { grep -A1 '^좌석 기억(1회 로드)=' "$T/sent.txt" | sed -n 2p; }   # 기억 로드 줄 바로 다음 줄
W1='열린 칸 감시: ⑬ 실사건 관측(cfo D2 ④) · 경보 stall 20분'; W0='열린 칸 감시: 없음'
ckpass() {  # ckpass <이름> <감시 줄> [도구]
  body "$2" > "$T/b.txt"; so_run "${3:-$SO}"
  { [ "$RC" = 0 ] && [ "$(after)" = "$2" ] && [ "$(grep -cxF -- "$2" "$T/sent.txt")" = 1 ]; } \
    && ok "$1 통과 · 기억 로드 다음 줄 · 1번만" || bad "$1" "rc=$RC after=$(after 2>/dev/null) out=$(cat "$T/out")"
}
ckrej() {  # ckrej <이름> [도구] — 본문 = $T/b.txt
  so_run "${2:-$SO}"
  { [ "$RC" = 1 ] && grep -q '열린 칸 감시 줄 필요' "$T/out" && ! grep -q '^send' "$lg" && ! grep -q '^tmuxc' "$lg"; } \
    && ok "$1 REJECT rc1 · 열기·send 0" || bad "$1" "rc=$RC log=$(tr '\n' ' ' < "$lg") out=$(cat "$T/out")"
}
ckpass ① "$W1"; ckpass ② "$W0"; body > "$T/b.txt"; ckrej ③; body "$W0" "$W1" > "$T/b.txt"; ckrej ④
L159="열린 칸 감시: $(printf 'x%.0s' $(seq 1 150))"; body "${L159}xx" > "$T/b.txt"; ckrej "⑤ 161자"; ckpass "⑤' 160자" "${L159}x"   # 머리 9자 + 150 + 1·2
body '열린 칸 감시: ' > "$T/b.txt"; ckrej ⑥
# ── ⑪·⑫ team-boot B2 본문 → 실제 개설 도구 검사(감싸개)
{ echo '#!/usr/bin/env bash'; printf 'cd %q; rm -rf %q %q %q\n' "$PWD" "$T/opened" "$T/sent.txt" "$R/.fable-team/state"   # cwd = 시험 cwd(git 밖 · so_run 과 같은 자리)
  printf 'while [ $# -gt 0 ]; do [ "$1" = --body-file ] && cp "$2" %q; shift; done\nexec env' "$T/b.txt"
  printf ' %q' "${SOENV[@]}" bash "$SO" "$OLD" "$R" --name "$NEW" --agent claude --model m --body-file "$T/b.txt"; echo; } > "$T/so_wrap.sh"
B="$T/boot"; mkdir -p "$B/design/teams/t1/indices/진행" "$B/.fable-team/comm" "$B/.worktrees/wtt1" "$T/la"; git -C "$B" init -q -b main
printf '{"_master":"byz-t1-master-claude#4","_cards":"design/teams/t1/indices","_cards_wt":"wtt1","byz-t1-master-claude#4":{"role":"master","agent":"claude","model":"m"}}\n' > "$B/.fable-team/seats-t1.json"
echo '{"_master":"byz-planner-master-pi#245"}' > "$B/.fable-team/seats-planner.json"; mkstub ok0 'exit 0'; mkstub tls '[ "$1" = ls ] || exit 0'
boot() {  # boot <절 줄…> — CLOSEOUT 커밋 → B2 1회(본문 = $T/b.txt)
  rm -rf "$B/.fable-team/state"; { printf '# CLOSEOUT\n\n## 골 원문\n\n골 1\n골 2\n골 3\n\n'; [ $# -gt 0 ] && printf '## 열린 칸 감시\n\n' && printf -- '- %s\n' "$@"; } > "$B/design/teams/t1/CLOSEOUT-t1-20261114.md"
  git -C "$B" add -A; git -C "$B" -c user.name=t -c user.email=t@t commit -qm c --allow-empty; git -C "$B" update-ref refs/remotes/origin/main HEAD
  BOUT="$(cd "$B" && FT_REPO_ROOT="$B" FT_SUCCESSOR_OPEN="$T/so_wrap.sh" FT_MBOX_SH="$F/ok0" FT_NANO_SPAWN="$F/ok0" FT_ALL_STOP="$F/ok0" FT_TMUX="$F/tls" \
    FT_LAUNCHAGENTS="$T/la" FT_BOOT_ME='byz-t1-nano-boot#0' FT_BOOT_REPORT_TO='byz-planner-master-pi#245' bash "$REPO/harness/bin/ft-team-boot.sh" t1 2>&1)"; BRC=$?
}
boot; SHA="$(git -C "$B" rev-parse main:design/teams/t1/CLOSEOUT-t1-20261114.md | cut -c1-10)"
{ printf '%s' "$BOUT" | grep -q 'B2 .* rc=0' && [ "$(after)" = "열린 칸 감시: 없음(새 생명 · CLOSEOUT $SHA 기준 · 재개 카드 0장 = B3)" ]; } \
  && ok "⑪ B2 절 0 → «없음(새 생명 · CLOSEOUT $SHA …)» · 실제 검사 통과" || bad "⑪" "brc=$BRC after=$(after 2>/dev/null) out=$BOUT"
boot '결제 골 칸 관측 · 다음 틱' '음성 경보 관측 · 20분'
{ printf '%s' "$BOUT" | grep -q 'B2 .* rc=0' && [ "$(after)" = '열린 칸 감시: 결제 골 칸 관측 · 다음 틱 · 음성 경보 관측 · 20분' ]; } \
  && ok "⑫ B2 절 2행 → 두 항목 모두 한 줄 · 실제 검사 통과" || bad "⑫" "brc=$BRC after=$(after 2>/dev/null) out=$BOUT"
boot "$(printf 'a%.0s' $(seq 1 80))" "$(printf 'b%.0s' $(seq 1 80))"
{ [ "$BRC" != 0 ] && printf '%s' "$BOUT" | grep -q '팀장 미도달' && printf '%s' "$BOUT" | grep -q '열린 칸 감시 줄 필요' && [ ! -s "$T/sent.txt" ]; } \
  && ok "⑫b B2 합친 줄 161자↑ → REJECT · B2 STOP rc=$BRC · 송신 0" || bad "⑫b" "brc=$BRC out=$BOUT"
# ── 변이 M1~M4 (사본에서만)
mut() {  # mut <이름> <python 치환식 old> <new> → 사본 경로 $MX/ft-successor-open.sh
  MX="$T/mx-$1"; mkdir -p "$MX"; cp -R "$(dirname -- "$SO")/." "$MX/"
  python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); s=p.read_text(); assert sys.argv[2] in s, sys.argv[2]; p.write_text(s.replace(sys.argv[2], sys.argv[3], 1))' "$MX/ft-successor-open.sh" "$2" "$3" || bad "$1 치환 자리 없음" "$2"
}
expect_fail() { local before=$fail; "$@" > "$T/mout"; [ "$fail" -gt "$before" ] && { fail=$before; ok "${M} 잡힘($(grep -m1 -o '^FAIL [^ ]*' "$T/mout"))"; } || bad "$M 안 잡힘" "$(cat "$T/mout")"; }
M=M1; mut M1 ')" || { printf '"'%s\n'"' "$WATCH"; exit 1; }' ')" || true'; body > "$T/b.txt"; expect_fail ckrej ③ "$MX/ft-successor-open.sh"
M=M2; mut M2 "printf '%s\n' \"\$WATCH\"; sed" 'sed'; python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); s=p.read_text(); p.write_text(s.replace("\"$BODY\"; } )\"  # r1391", "\"$BODY\"; printf \"%s\\n\" \"$WATCH\"; } )\"  # r1391", 1))' "$MX/ft-successor-open.sh"; expect_fail ckpass ① "$W1" "$MX/ft-successor-open.sh"
M=M3; mut M3 '|열린 칸 감시: )/d' ')/d'; expect_fail ckpass ① "$W1" "$MX/ft-successor-open.sh"
M=M4; mut M4 ' or len(w[0]) > 160' ''; body "${L159}xx" > "$T/b.txt"; expect_fail ckrej "⑤ 161자" "$MX/ft-successor-open.sh"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
