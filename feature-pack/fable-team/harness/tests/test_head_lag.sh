#!/usr/bin/env bash
# test_head_lag.sh — R243: 착지 뒤 기준 헤드 자동 갱신(ft-merge-land) + 뒤처진 워크트리 → 팀 master 알림(ft-head-lag)
# 임시 origin+clone+워크트리 · 시험용 tmux 서버(-L) · 가짜 명부·mbox · gh 스텁 — 실 저장소·실 tmux·실 mbox·실 원격 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"; LAND="$BIN/ft-merge-land.sh"; LAG="$BIN/ft-head-lag.sh"; PY="$BIN/ft_head_lag.py"; PY2="$BIN/ft_head_lag_seats.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; SOCK="hl$$"; REAL_GIT="$(command -v git)"
TM() { tmux -L "$SOCK" "$@"; }
cleanup() { for s in $(TM list-sessions -F '#{session_name}' 2>/dev/null); do TM kill-session -t "$s" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
mkrepo "$T"; mkdir -p "$T/.fable-team/state" "$T/shim"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
export FT_HEAD_LAG_TMUX_ARGS="-L $SOCK" FT_HEAD_LAG_MBOX="$T/mbox" MBOX_LOG="$T/mbox.log"
BH="$T/.fable-team/state/base-head"; : > "$MBOX_LOG"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
echo "$*" >> "$STUB_LOG"
EOF
cat > "$T/mbox" <<'EOF'
#!/bin/bash
n=$(( $(wc -l < "$MBOX_LOG") + 1 )); printf '%s\t%s\t%s\n' "$2" "$3" "$(printf '%s' "$4" | tr '\n' '~')" >> "$MBOX_LOG"; echo "QUEUED seq=$((9000+n)) to=$2"
EOF
cat > "$T/shim/git" <<EOF
#!/bin/bash
for a in "\$@"; do if [ "\$a" = commit-tree ] && [ -n "\${RACE_WT:-}" ] && [ ! -e "\$RACE_MARK" ]; then : > "\$RACE_MARK"; "$REAL_GIT" -C "\$RACE_WT" commit -q --allow-empty -m race && "$REAL_GIT" -C "\$RACE_WT" push -q origin HEAD:main; fi; done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$T/gh-stub" "$T/mbox" "$T/shim/git"
omain() { sha "$ORIGIN" refs/heads/main; }
msgs() { wc -l < "$MBOX_LOG" | tr -d ' '; }
mkpr() {  # mkpr <번호> <브랜치> <시작점>
  git -C "$W" checkout -q -B "$2" "$3"; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1 work"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"feat: PR "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
lag() { out="$(bash "$LAG" "$@" --repo "$W" 2>&1)"; rc=$?; }
mainc() {  # mainc <파일> <몇 초 전> — origin main 에 커밋 1개(committer 시각 지정)
  git -C "$W" checkout -q main; echo "$1" >> "$W/m.txt"; git -C "$W" add -A
  GIT_COMMITTER_DATE="$(( $(date +%s) - $2 )) +0000" git -C "$W" commit -q -m "main $1"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
}
mkwt() {  # mkwt <이름> <브랜치> <시작점> [세션명]
  git -C "$W" worktree add -q -b "$2" "$T/$1" "$3"; [ -z "${4:-}" ] || TM new-session -d -s "$4" -c "$T/$1"
}

# ── ⓐ 착지 사건 → 기준 헤드 파일
bash -n "$LAND"; ck "bash -n land" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?
git -C "$W" fetch -q origin; M1="$(omain)"; printf '%s\n' "$M1" > "$BH"
mkpr 9 pr9 origin/main; P9="$PRSHA"; git -C "$T" clone -q "$ORIGIN" "$T/race"; git -C "$T/race" config user.name t; git -C "$T/race" config user.email t@t
apv --approve-sha "$P9"; out="$(PATH="$T/shim:$PATH" RACE_WT="$T/race" RACE_MARK="$T/race.mark" bash "$LAND" 9 --approve-sha "$P9" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(cat "$BH")" = "$M1" ]; ck "ⓐ 착지 실패(non-FF 거절) → 기준 헤드 옛 값 그대로" $?
git -C "$W" fetch -q origin; mkpr 11 pr11 origin/main; land 11 --approve-sha "$PRSHA"; L="$(omain)"
[ "$rc" = 0 ] && [ "$(cat "$BH")" = "$L" ] && [ "$(wc -l < "$BH" | tr -d ' ')" = 1 ]; ck "ⓐ 착지 성공 → 기준 헤드 파일 = 새 main sha(1줄)" $?
! ls "$T/.fable-team/state" | grep -q '^base-head\.'; ck "ⓐ 임시 파일 잔재 0(원자 교체)" $?

# ── 시나리오: 착지 L 위에 main 커밋 c1(5시간 전)·c2(2시간 전) · 워크트리 lagA(L·팀A)·lagB(c1·팀B)·lagC(c2=최신·팀B)·lagD(c1·좌석 없음)·lagR(release/x·L·팀A)
git -C "$W" checkout -q main; git -C "$W" reset -q --hard origin/main
mainc c1 18000; C1="$(sha "$W" HEAD)"; mainc c2 7200; C2="$(sha "$W" HEAD)"
echo '{"_master":"byz-teama-master-claude#1"}' > "$T/.fable-team/seats-teama.json"; echo '{"_master":"byz-teamb-master-claude#2"}' > "$T/.fable-team/seats-teamb.json"
mkwt lagA nano/lagA "$L" 'byz-teama-nano-claude#0'; mkwt lagB nano/lagB "$C1" 'byz-teamb-nano-claude#0'; mkwt lagC nano/lagC "$C2" 'byz-teamb-nano-codex#1'
mkwt lagD nano/lagD "$C1"; mkwt lagR release/x "$L" 'byz-teama-nano-claude#3'
: > "$MBOX_LOG"; rm -f "$T/.fable-team/state/head-lag.json"
lag --event
A="$(grep -c '^byz-teama-master-claude#1' "$MBOX_LOG")"; B="$(grep -c '^byz-teamb-master-claude#2' "$MBOX_LOG")"
[ "$rc" = 0 ] && [ "$(msgs)" = 2 ] && [ "$A" = 1 ] && [ "$B" = 1 ]; ck "ⓑ 뒤처진 팀 A·B master 에 각 1통(팀당 1통)" $?
grep '^byz-teama' "$MBOX_LOG" | grep -q '베이스 뒤처짐' && grep '^byz-teama' "$MBOX_LOG" | grep -q 'lagA(nano/lagA)' && grep '^byz-teama' "$MBOX_LOG" | grep -q '2커밋' && grep '^byz-teama' "$MBOX_LOG" | grep -q '5시간' && grep '^byz-teama' "$MBOX_LOG" | grep -q 'ft-head-sync.sh --apply'; ck "ⓑ 알림에 워크트리·브랜치·N커밋·N시간·명령 줄" $?
! grep -E 'lagC|lagD|lagR' "$MBOX_LOG" | grep -q '^byz-teama'; ck "ⓑ A 알림에 남의 워크트리·최신(lagC)·좌석 없는 곳(lagD)·release 브랜치(lagR) 없음" $?
grep '^byz-teamb' "$MBOX_LOG" | grep -q 'lagB' && ! grep -q 'lagD' "$MBOX_LOG"; ck "ⓑ B 알림 = lagB · 좌석 없는 lagD 알림 0" $?
# ── ⓒ 같은 main sha → 0통
lag --event; [ "$rc" = 0 ] && [ "$(msgs)" = 2 ]; ck "ⓒ 같은 main sha 재실행 → 0통" $?
lag --cron; [ "$(msgs)" = 2 ]; ck "ⓒ 안전망(--cron)도 이미 알린 건 0통" $?
# ── ⓕ 요약
lag --summary; [ "$out" = "베이스 뒤처짐 3곳(가장 오래 lagA 2커밋·5시간)" ]; ck "ⓕ --summary 1줄(좌석 없는 lagD 포함 · 최신 lagC·release 제외)" $?
# ── ⓓ 6시간 뒤 재알림 1 · 그 뒤 0
export FT_HEAD_LAG_NOW="$(( $(date +%s) + 6*3600 + 60 ))"; lag --cron
[ "$(msgs)" = 4 ]; ck "ⓓ 6시간 뒤에도 그대로 → 재알림 1(팀당)" $?
export FT_HEAD_LAG_NOW="$(( $(date +%s) + 13*3600 ))"; lag --cron; [ "$(msgs)" = 4 ]; ck "ⓓ 그 뒤 0(재촉 상한 1)" $?
unset FT_HEAD_LAG_NOW
# ── ⓔ 새 main sha → 다시 1 · 문턱(--cron 60분)
mainc c3 600; : > "$MBOX_LOG"
lag --cron; [ "$(msgs)" = 2 ] && ! grep -q 'lagC' "$MBOX_LOG"; ck "ⓔ 새 main sha → 다시 1(팀당) · 문턱 미만(lagC 10분)은 제외" $?
FT_HEAD_LAG_MIN=5 lag --cron; [ "$(msgs)" = 3 ] && tail -n1 "$MBOX_LOG" | grep -q 'lagC'; ck "ⓔ 문턱 5분이면 lagC 알림 1" $?
# ── ⓖ fetch 실패 → ERROR + rc 4 + 알림 0(지어내기 0)
rm -f "$T/.fable-team/state/head-lag.json"; n0="$(msgs)"; ORIG_URL="$(git -C "$W" remote get-url origin)"; git -C "$W" remote set-url origin "$T/nonexistent.git"
lag --event; git -C "$W" remote set-url origin "$ORIG_URL"
[ "$rc" = 4 ] && [[ "$out" == *ERROR* ]] && [ "$(msgs)" = "$n0" ]; ck "ⓖ fetch 실패 → stderr ERROR · rc 4 · 알림 0" $?
# ── ⓕ 0곳이면 빈 출력
for d in lagA lagB lagC lagD; do git -C "$T/$d" merge -q --no-edit origin/main >/dev/null 2>&1; done
lag --summary; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓕ 뒤처짐 0곳 → 빈 출력" $?
# ── 정적
bash -n "$LAG"; ck "bash -n head-lag" $?
[ "$(wc -l < "$LAG" | tr -d ' ')" -le 40 ] && [ "$(wc -l < "$PY" | tr -d ' ')" -le 150 ] && [ "$(wc -l < "$PY2" | tr -d ' ')" -le 150 ]; ck "진입 ≤ 40줄 · py 각 ≤ 150줄" $?
! cat "$LAG" "$PY" "$PY2" | grep -vE '^\s*#' | grep -qE '"(reset|rebase|push|merge|checkout|commit)"|git[^|]*(reset|rebase|push|merge)|--force'; ck "정적: head-lag 에 git reset·rebase·push·merge·force 0(읽기 전용)" $?
[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
