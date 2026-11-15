#!/usr/bin/env bash
# test_child_watch_launchd_env_r1795.sh — r1795: launchd 꼴(env -i · TMUX 없음 · LC_ALL=C) child-watch 가 좌석·자율을 제대로 읽는다 (카드 반례 ①~④ · 변이 M1~M4)
#   가짜 나무 = lib/r1113_fake_tree.sh(sleep 스텁) · 가짜 tmux = TMUX 없음 ∧ LC_ALL=C ∧ -u 없음 → 탭을 `_` 로(tmux 3.6a 실측 꼴) · FAKE_TMUX_BROKEN=1 → -u 여도 `_`
#   임시 A(범위 없음) · A/.fable-team/LIVE_ROOT → 임시 B(범위 S1 켜짐) · 모든 실행 = --dry-run(kill·발신 0) · 실 tmux·launchd·mbox·리포 state 0 · sleep 0
#   CW_BIN = 시험할 bin 폴더(기본 ../bin · 기준판 Red 확인용)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN0="$(cd -- "${CW_BIN:-$HERE/../bin}" && pwd)"
TMP="$(mktemp -d)"; . "$HERE/lib/r1113_fake_tree.sh"; fake_init; trap fake_cleanup EXIT
pass=0; fail=0; T0=$(date +%s)
ck() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; sed 's/^/    | /' "$TMP/last" 2>/dev/null | tail -4; fail=$((fail+1)); fi; }
cat > "$TMP/fake/tmux-lc" <<'EOF'
u=0; [ "${1:-}" = -u ] && { u=1; shift; }
case "$1" in list-panes)
  if [ -n "${FAKE_TMUX_BROKEN:-}" ] || { [ "$u" = 0 ] && [ -z "${TMUX:-}" ] && [ "${LC_ALL:-}" = C ]; }; then tr '\t' '_' < "$FAKE_PANES"; else cat "$FAKE_PANES"; fi; exit 0;; esac
echo "fake tmux: $*" >&2; exit 1
EOF
A0="$TMP/a0"; A1="$TMP/a1"; B="$TMP/b"; mkdir -p "$A0/.fable-team" "$A1/.fable-team" "$B/.fable-team/state" "$TMP/cw"
printf '%s\n' "$B" > "$A1/.fable-team/LIVE_ROOT"
NOW=$(date +%s); printf '%s\ton\tA1\napprove-scope S1 A1 %s until=%s max=30 daily=10 classes=docs\n' "$NOW" "$NOW" $((NOW + 86400)) > "$B/.fable-team/state/autonomy.log"
printf '{"mode":"on","since":%s,"event":"A1","until":null}\n' "$NOW" > "$B/.fable-team/state/autonomy.json"
: > "$TMP/sent"; printf 'echo "$2|$4" >> "%s"\n' "$TMP/sent" > "$TMP/fake/mbox"
tree S1 25; tree S2 5
lw() {  # <bin> <FT_ROOT> [VAR=값…] — launchd 꼴: env -i · TMUX 없음 · LANG 없음 · --dry-run
  local b="$1" r="$2"; shift 2
  env -i HOME="$TMP" PATH="$PATH" FT_ROOT="$r" FT_TMUX="$TMP/fake/tmux-lc" FT_PS="$FT_PS" FT_LAUNCHCTL="$FT_LAUNCHCTL" \
    FAKE_PANES="$FAKE_PANES" FAKE_PIDS="$FAKE_PIDS" FAKE_LAUNCHD="$FAKE_LAUNCHD" FAKE_KEEP_RE="$FAKE_KEEP_RE" FT_QUIESCE_RSS_TSV="$FT_QUIESCE_RSS_TSV" \
    FT_QUIESCE_STATE_DIR="$FT_QUIESCE_STATE_DIR" FT_PERMIT_DIR="$FT_PERMIT_DIR" FT_CHILD_STATE_DIR="$TMP/cw" FT_CHILD_MBOX_SH="$TMP/fake/mbox" \
    FT_SEAT_QUIESCE_BIN="$b/ft-seat-quiesce.sh" "$@" bash "$b/ft-child-watch.sh" --dry-run > "$TMP/last" 2>&1; echo $? > "$TMP/rc"; }
rc() { [ "$(cat "$TMP/rc")" = "$1" ]; }
summ() { tail -1 "$TMP/last" | grep -qxF "$1"; }
c1() { lw "$1" "$A0"; rc 0 && summ "child-watch seats=2 child=0 nano=0 orphans=0 quiesced=0 dry-run autonomy=off"; }
c2() { lw "$1" "$A0" FAKE_TMUX_BROKEN=1; rc 20 && [ "$(grep -c . "$TMP/last")" = 1 ] && grep -q '^CHILD-WATCH-UNKNOWN 판정 불가 — .*tmux 출력 칸 나눔 실패' "$TMP/last" && [ ! -s "$TMP/sent" ]; }
c3() { lw "$1" "$A1"; rc 0 && summ "child-watch seats=2 child=0 nano=0 orphans=0 quiesced=0 dry-run autonomy=on" || return 1
  lw "$1" "$A0"; rc 0 && summ "child-watch seats=2 child=0 nano=0 orphans=0 quiesced=0 dry-run autonomy=off"; }
c4() { lw "$1" "$A1" FT_CHILD_AUTONOMY=off; rc 0 && tail -1 "$TMP/last" | grep -q ' dry-run autonomy=off$' || return 1   # 좌석 칸은 ① 몫 — 여기는 자율 칸만
  lw "$1" "$A0" FT_CHILD_AUTONOMY=on; rc 0 && tail -1 "$TMP/last" | grep -q ' dry-run autonomy=on$'; }
ck "① launchd 꼴(TMUX 없음 · LC_ALL=C) 좌석 2 → seats=2" c1 "$BIN0"
ck "② -u 여도 3칸 아님 → CHILD-WATCH-UNKNOWN rc20 · 1줄 · 발신 0" c2 "$BIN0"
ck "③ A/LIVE_ROOT=B(S1 켜짐) → autonomy=on · LIVE_ROOT 없음 → off" c3 "$BIN0"
ck "④ FT_CHILD_AUTONOMY=off|on 이 LIVE_ROOT 보다 먼저" c4 "$BIN0"
T1=$(date +%s)
mutant() {  # <이름> <파일> <sed> → 사본 bin 폴더 경로(사본 = 원본이면 rc1)
  local m="$TMP/mut-$1"; cp -R "$BIN0" "$m" && sed "$3" "$BIN0/$2" > "$m/$2"; cmp -s "$BIN0/$2" "$m/$2" && return 1; echo "$m"; }
mutv() {  # <변이> <파일> <sed> <사례> — 변이 = 그 사례 FAIL · 원본 = 같은 사례 PASS(1회 더)
  local m; m="$(mutant "$1" "$2" "$3")" || { echo "    | 변이 $1 사본 = 원본"; return 1; }
  "$4" "$m" && { echo "    | 변이 $1 이 $4 를 통과"; return 1; }; "$4" "$BIN0"; }
ck "M1 -u 뺌 → ① FAIL · 원본 ① PASS" mutv M1 ft-seat-quiesce.sh 's/\["-u", "list-panes"/["list-panes"/' c1
ck "M2 칸 실패를 좌석 0 으로 → ② FAIL · 원본 ② PASS" mutv M2 ft-seat-quiesce.sh 's/if any(len(f) != 3 for f in rows): raise/if 0: raise/' c2
ck "M3 LIVE_ROOT 무시 → ③ FAIL · 원본 ③ PASS" mutv M3 ft-child-watch.sh 's/env\["FT_ROOT"\] = live/pass/' c3
ck "M4 LIVE_ROOT 가 시험 길보다 먼저 → ④ FAIL · 원본 ④ PASS" mutv M4 ft-child-watch.sh 's/    if v in ("on", "off"): return v == "on"/    if v in ("on", "off") and not os.path.isfile(os.path.join(E.get("FT_ROOT") or "", ".fable-team\/LIVE_ROOT")): return v == "on"/' c4
echo "단계별 초: 사례 $((T1 - T0)) · 변이 $(( $(date +%s) - T1 ))"
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
