#!/usr/bin/env bash
# test_head_skip_list.sh — R249: «뒤처짐» 제외 목록 = 데이터 파일 1개(ft-head-skip.txt) · ft-head-lag 와 ft-head-sync 가 같은 파일을 읽는다
# 도구 폴더를 임시 폴더로 복사해 시험한다(파일 1줄 바꾸기·삭제가 실 파일에 닿지 않게) · 임시 origin+clone+워크트리 · 시험용 tmux 서버(-L) · 가짜 명부·mbox
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC_BIN="$HERE/../../harness/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; SOCK="hs$$"
TM() { tmux -L "$SOCK" "$@"; }
cleanup() { for s in $(TM list-sessions -F '#{session_name}' 2>/dev/null); do TM kill-session -t "$s" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
mkrepo "$T"; mkdir -p "$T/.fable-team/state"; cp -R "$SRC_BIN" "$T/bin"
BIN="$T/bin"; LAG="$BIN/ft-head-lag.sh"; SYNC="$BIN/ft-head-sync.sh"; SKIPF="$BIN/ft-head-skip.txt"
export FT_ROOT="$T" FT_HEAD_LAG_TMUX_ARGS="-L $SOCK" FT_HEAD_LAG_MBOX="$T/mbox" MBOX_LOG="$T/mbox.log"; : > "$MBOX_LOG"
cat > "$T/mbox" <<'EOF'
#!/bin/bash
n=$(( $(wc -l < "$MBOX_LOG") + 1 )); printf '%s\t%s\t%s\n' "$2" "$3" "$(printf '%s' "$4" | tr '\n' '~')" >> "$MBOX_LOG"; echo "QUEUED seq=$((9000+n)) to=$2"
EOF
chmod +x "$T/mbox"; echo '{"_master":"byz-teama-master-claude#1"}' > "$T/.fable-team/seats-teama.json"
DOCS="feat/feature-main docs/cfo-main docs/ops-main-r2 ops/main-base feat/ops-main feat/issue-manager"
i=0; for b in $DOCS nano/gen; do   # 줄기마다 워크트리 1개 + 팀 A 좌석 1개 — 전부 M0 에 머무름(main 은 아래서 전진)
  i=$((i+1)); git -C "$W" worktree add -q -b "$b" "$T/wt$i" "$M0"; TM new-session -d -s "byz-teama-nano-claude#$i" -c "$T/wt$i"
done
echo c1 >> "$W/m.txt"; cm "$W" "main c1"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
lag() { rm -f "$T/.fable-team/state/head-lag.json"; : > "$MBOX_LOG"; out="$(bash "$LAG" --event --repo "$W" 2>&1)"; rc=$?; }
sync_tab() { out="$(bash "$SYNC" --repo "$W" 2>&1)"; rc=$?; }
alerted() { grep -c "($1)" "$MBOX_LOG"; }   # 알림 본문에 «(브랜치)» 가 몇 번 나왔나
synced() { printf '%s\n' "$out" | awk -v b="$1" '$1==b' | grep -c .; }

# ── ⓐ 목록 줄기 6개: 알림 0 · 동기화 표에 안 나옴(제외) / ⓑ 일반 nano 줄기: 알림 1 · 표에 나옴
lag; n=0; for b in $DOCS; do n=$((n+$(alerted "$b"))); done
[ "$rc" = 0 ] && [ "$n" = 0 ]; ck "ⓐ 문서 줄기 6개 뒤처짐 → ft_head_lag 알림 0" $?
[ "$(alerted nano/gen)" = 1 ] && [ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 1 ]; ck "ⓑ 일반 nano 줄기 뒤처짐 → 알림 1(팀당 1통)" $?
sync_tab; n=0; for b in $DOCS; do n=$((n+$(synced "$b"))); done
[ "$rc" = 0 ] && [ "$n" = 0 ]; ck "ⓐ 문서 줄기 6개 → ft-head-sync 표에서 제외" $?
[ "$(synced nano/gen)" = 1 ]; ck "ⓑ nano/gen → ft-head-sync 표에 있음" $?
# ── ⓒ 환경변수 FT_HEAD_SYNC_SKIP 이 파일보다 우선
FT_HEAD_SYNC_SKIP='^nano/gen$'; export FT_HEAD_SYNC_SKIP
lag; [ "$rc" = 0 ] && [ "$(alerted nano/gen)" = 0 ] && [ "$(alerted feat/feature-main)" = 1 ]; ck "ⓒ 환경변수 값이 파일 대신 — ft_head_lag" $?
sync_tab; [ "$(synced nano/gen)" = 0 ] && [ "$(synced feat/feature-main)" = 1 ]; ck "ⓒ 환경변수 값이 파일 대신 — ft-head-sync" $?
unset FT_HEAD_SYNC_SKIP
# ── ⓔ 두 도구가 같은 파일: 1줄 빼면 둘 다 바뀐다
grep -vx 'feat/feature-main' "$SKIPF" > "$SKIPF.new" && mv "$SKIPF.new" "$SKIPF"
lag; [ "$(alerted feat/feature-main)" = 1 ] && [ "$(alerted docs/cfo-main)" = 0 ]; ck "ⓔ 파일에서 1줄 삭제 → ft_head_lag 가 그 줄기만 알림" $?
sync_tab; [ "$(synced feat/feature-main)" = 1 ] && [ "$(synced docs/cfo-main)" = 0 ]; ck "ⓔ 같은 파일 → ft-head-sync 도 그 줄기만 표에 나옴" $?
cp "$SRC_BIN/ft-head-skip.txt" "$SKIPF"
# ── ⓓ 파일 없음·빈 파일·주석뿐 → ERROR + rc≠0 + 알림 0(조용히 기본값으로 넘어가지 않는다 · #0 RULE)
for mode in missing empty comments; do
  case "$mode" in missing) rm -f "$SKIPF";; empty) : > "$SKIPF";; comments) printf '# 주석뿐\n\n' > "$SKIPF";; esac
  lag; [ "$rc" != 0 ] && [[ "$out" == *ERROR* ]] && [ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 0 ]; ck "ⓓ $mode → ft_head_lag ERROR rc≠0 알림 0" $?
  sync_tab; [ "$rc" != 0 ] && [[ "$out" == *ERROR* ]]; ck "ⓓ $mode → ft-head-sync ERROR rc≠0" $?
done
cp "$SRC_BIN/ft-head-skip.txt" "$SKIPF"
# ── r549: 공용 라이브 뿌리 feat/v6-realtime-live = «병합하지 않는 줄기»(남의 staged·수정 1526개 · 메모리 10-18) → 두 도구 모두 제외
#    ⓕ 그 브랜치만 알림 0 ⓖ 같은 파일이라 ft-head-sync 표에서도 0 ⓗ 다른 기능 브랜치는 그대로 대상(제외가 넓어지지 않음)
T2="$T/t2"; mkrepo "$T2"; mkdir -p "$T2/.fable-team/state"
git -C "$W" worktree add -q -b feat/v6-realtime-live "$T2/wt-v6" "$M0"; TM new-session -d -s 'byz-teama-nano-claude#9' -c "$T2/wt-v6"
echo c1 >> "$W/m.txt"; cm "$W" "main c1"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
lag; [ "$rc" = 0 ] && [ "$(alerted feat/v6-realtime-live)" = 0 ]; ck "ⓕ feat/v6-realtime-live 뒤처짐 → ft_head_lag 알림 0(공용 라이브 뿌리 제외)" $?
sync_tab; [ "$(synced feat/v6-realtime-live)" = 0 ]; ck "ⓖ feat/v6-realtime-live → ft-head-sync 표에서 제외(같은 파일 1줄)" $?
git -C "$W" worktree add -q -b nano/r549fn "$T2/wt-n549" "$M0"; TM new-session -d -s 'byz-teama-nano-claude#10' -c "$T2/wt-n549"
lag; n="$(alerted nano/r549fn)"; sync_tab; m="$(synced nano/r549fn)"
[ "$n" = 1 ] && [ "$m" = 1 ]; ck "ⓗ 다른 기능 브랜치 nano/r549fn → 알림 1 · 표 1(제외 안 넓어짐 · 앵커 ^(…)$)" $?
# ── 정적: 기본값 4개(main·master·release·deploy) 보존 · 하드코딩 정규식 2곳 삭제 · 키트 사본 일치
n=0; for k in 'main' 'master' 'release/.*' 'deploy/.*'; do grep -qxF "$k" "$SRC_BIN/ft-head-skip.txt" || n=1; done; [ "$n" = 0 ]; ck "정적: 기본값 4개 줄 보존" $?
! grep -qE 'release/\.\*' "$SRC_BIN/ft_head_lag.py" "$SRC_BIN/ft-head-sync.sh"; ck "정적: 하드코딩 기본 정규식 2곳 삭제" $?
cmp -s "$SRC_BIN/ft-head-skip.txt" "$HERE/../../harness/kit/fable-team/bin/ft-head-skip.txt"; ck "정적: 키트 사본 ft-head-skip.txt 일치" $?
[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
