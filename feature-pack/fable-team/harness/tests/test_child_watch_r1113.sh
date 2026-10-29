#!/usr/bin/env bash
# test_child_watch_r1113.sh — ft-child-watch.sh 반례 R9~R11 + 조회 표 + 한 명령 강제 정리 + zombie-clean R12 (r1113 · 판정 2769·2770)
#   가짜 나무 = lib/r1113_fake_tree.sh · 명부·카드·mbox = 임시 FT_ROOT · 발신 = FT_CHILD_MBOX_SH 스텁(기록만) · 실 tmux·launchd·mbox 0 · 자기 재호출 0
#   zombie-clean = 가짜 ps 스냅샷 + 가짜 launchctl · clean --dry-run(kill 0) · 대상 = ZC_SCRIPT(기본 리포 kit)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
W="${W_SCRIPT:-$BIN/ft-child-watch.sh}"; ZC="${ZC_SCRIPT:-$HERE/../kit/zombie-clean/zombie-clean.sh}"
TMP="$(mktemp -d)"; . "$HERE/lib/r1113_fake_tree.sh"; fake_init; trap fake_cleanup EXIT
pass=0; fail=0; T0=$(date +%s)
ck() { local n="$1"; shift; if "$@"; then echo "PASS $n"; pass=$((pass+1)); else echo "FAIL $n"; sed 's/^/    | /' "$TMP/last" 2>/dev/null | tail -6; fail=$((fail+1)); fi; }
R="$TMP/root"; mkdir -p "$R/.fable-team" "$TMP/cw"
export FT_ROOT="$R" FT_CHILD_STATE_DIR="$TMP/cw" FT_CHILD_WATCH_EVERY_SEC=0 FT_CHILD_MBOX_SH="$TMP/fake/mbox" FT_SEAT_QUIESCE_BIN="$BIN/ft-seat-quiesce.sh"
printf 'echo "$2|$4" >> "%s"\n' "$TMP/sent" > "$TMP/fake/mbox"; : > "$TMP/sent"
printf '# c\n## 상태\n- 2026-10-29 15:02 — 대기→진행\n- 2026-10-29 — [완료·휴식] r1113 남은 것 0\n' > "$R/card-done.md"
printf '# c\n## 상태\n- 2026-10-29 16:14 — 대기→진행 · 좌석 x\n' > "$R/card-prog.md"
cat > "$R/.fable-team/seats-harness.json" <<'EOF'
{"_master": "HM#1", "R9a": {"role": "arch"}, "R9b": {"role": "arch"}, "R10": {"role": "arch"}, "R11prog": {"role": "nano", "agent": "pi", "index": "card-prog.md"}}
EOF
echo '{"_master": "OM#1", "R11done": {"role": "nano", "agent": "pi", "index": "card-done.md"}}' > "$R/.fable-team/seats-ops.json"
w() { bash "$W" "$@" > "$TMP/last" 2>&1; echo $? > "$TMP/rc"; }
sent() { grep -c -- "$1" "$TMP/sent" | tr -d ' '; }
tree R9a 25 basedpyright; rss "$(pid_of R9a basedpyright)" 350
tree R10 5 basedpyright; rss "$(pid_of R10 basedpyright)" 1200
tree R11done 40; tree R11prog 40

r9_off() { FT_CHILD_AUTONOMY=off w; [ "$(sent 'HM#1|\[자식\] R9a 유휴 25분 · 자식 350MB · basedpyright:350 · 조치: 경보만')" = 1 ] && alive "$(pid_of R9a basedpyright)"; }
r9_once() { FT_CHILD_AUTONOMY=off w; [ "$(sent '\[자식\] R9a')" = 1 ] && grep -q 'child=0' "$TMP/last"; }
r9_on() { tree R9b 25 basedpyright; rss "$(pid_of R9b basedpyright)" 350; FT_CHILD_AUTONOMY=on w
  [ "$(sent 'HM#1|\[자식\] R9b 유휴 25분 · 자식 350MB · basedpyright:350 · 조치: QUIESCED R9b mode=done')" = 1 ] && ! alive "$(pid_of R9b basedpyright)"; }
r10() { [ "$(sent 'R10')" = 0 ] && alive "$(pid_of R10 basedpyright)"; }
r11() { [ "$(sent 'OM#1|\[유휴 나노\] R11done 유휴 40분 · 카드 - 2026-10-29 — \[완료·휴식\]')" = 1 ] && [ "$(sent 'R11prog')" = 0 ]; }
table() { w --table; grep -q '^좌석	역할	유휴분	자식MB' "$TMP/last" && grep -qE '^R10	arch	5	1200	1200	1	basedpyright:1200	-$' "$TMP/last" && [ -s "$TMP/cw/child-watch.tsv" ]; }
kill_busy() { w --kill R10; [ "$(cat "$TMP/rc")" = 1 ] && grep -q 'REJECT R10 — 쓰는 중(유휴 5분 < 20분)' "$TMP/last" && alive "$(pid_of R10 basedpyright)"; }
kill_idle() { w --kill R9a; [ "$(cat "$TMP/rc")" = 0 ] && grep -q '^QUIESCED R9a mode=done' "$TMP/last" && ! alive "$(pid_of R9a basedpyright)"; }
busy_on() { echo '{"_master": "HM#1", "R9a": {"role": "arch"}, "R9b": {"role": "arch"}, "R10": {"role": "arch"}, "R11prog": {"role": "nano", "agent": "pi", "index": "card-prog.md"}, "BZ": {"role": "arch"}, "BZ2": {"role": "arch"}}' > "$R/.fable-team/seats-harness.json"
  tree BZ 25 basedpyright busy; rss "$(pid_of BZ basedpyright)" 350; FT_CHILD_AUTONOMY=on w
  [ "$(sent 'HM#1|\[자식\] BZ 유휴 25분 .* 조치: 경보만(작업 중 신호 · 도구 셸 1개)')" = 1 ] && alive "$(pid_of BZ basedpyright)" || return 1
  w --kill BZ; [ "$(cat "$TMP/rc")" = 1 ] && grep -q 'REJECT BZ — 쓰는 중(도구 셸 1개 실행 중' "$TMP/last" && alive "$(pid_of BZ basedpyright)"; }
ck "R9 유휴 25분 ∧ 350MB → [자식] 1통 · 자율 OFF = 경보만(생존)" r9_off
ck "R9 다음 틱 0통(하루 1회)" r9_once
ck "R9 자율 ON → QUIESCED mode=done · 내림" r9_on
ck "R10 유휴 5분 ∧ 1,200MB(일하는 중) → 경보 0 · 조치 0" r10
ck "R11 pi 나노 유휴 40분 ∧ 완료·휴식 → 그 팀 master 1통 · 진행 → 0 · kill 0" r11
ck "조회 표 --table(좌석·역할·유휴·MB·top3)" table
ck "--kill 쓰는 중 좌석 REJECT rc 1 · 안 죽임" kill_busy
ck "--kill 유휴 좌석 → QUIESCED · 내림" kill_idle
ck "DA① 추가 유휴(출력 없음)+도구 셸 실행 중 → 자율 ON 이어도 경보만 · --kill REJECT · 생존" busy_on
mkdir -p "$TMP/wbin"; cp -p "$BIN/ft-harness-root.sh" "$TMP/wbin/"; sed 's/            if on and not v\["busy"\] and not dry:/            if on and not dry:/' "$W" > "$TMP/wbin/ft-child-watch.sh"; cmp -s "$W" "$TMP/wbin/ft-child-watch.sh" && echo "WARN 변이 wm 이 원본과 같음"
: > "$TMP/sent"; : > "$TMP/cw/child-watch.sent"
ck "ⓜ8 작업 중 신호 무시 → 자동 정리가 basedpyright 를 내림(busy 칸 FAIL)" eval 'tree BZ2 25 basedpyright busy; rss "$(pid_of BZ2 basedpyright)" 350; FT_CHILD_AUTONOMY=on bash "$TMP/wbin/ft-child-watch.sh" >/dev/null 2>&1; ! alive "$(pid_of BZ2 basedpyright)"'
T1=$(date +%s)

# R12 zombie-clean — 가짜 ps 스냅샷(-axwwo 만 답함) · 가짜 launchctl(91002 = launchd 관리)
Z="$TMP/zc"; mkdir -p "$Z/bin" "$Z/home"
printf '#!/usr/bin/env bash\ncase "$1" in -axwwo) cat "%s"; exit 0 ;; esac\ncase "$*" in *"ppid="*) exit 0 ;; esac\nexec /bin/ps "$@"\n' "$Z/ps.fix" > "$Z/bin/ps"
printf '#!/usr/bin/env bash\nprintf "PID\\tStatus\\tLabel\\n91002\\t0\\tcom.xclaw.crew\\n"\n' > "$Z/bin/launchctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$Z/bin/tmux"; printf '#!/usr/bin/env bash\nexit 1\n' > "$Z/bin/lsof"; chmod +x "$Z/bin/"*
printf '91001 1 ?? 50000 node /Users/x/xclaw/crew/nanoclaw/index.js\n91002 1 ?? 40000 node /Users/x/xclaw/crew/other/index.js\n' > "$Z/ps.fix"
zc() { env -u ZC_TARGET_EXTRA HOME="$Z/home" PATH="$Z/bin:$PATH" "$@" bash "$ZC" clean --dry-run 2>&1 | sed -n 's/^  \([0-9][0-9]*\) \[.*$/\1/p' | sort -n | tr '\n' ' '; }
r12_on() { local s; s="$(zc)"; echo "$s" > "$TMP/last"; [ "$s" = "91001 " ]; }
r12_off() { local s; s="$(zc ZC_TARGET_EXTRA=)"; echo "$s" > "$TMP/last"; [ -z "$s" ]; }
ck "R12 launchd 밖 xclaw node 고아 = 대상 · launchd 목록 pid 보호" r12_on
ck "R12 ZC_TARGET_EXTRA= 빈 값 → 대상 0" r12_off
echo "단계별 초: child-watch $((T1 - T0)) · zombie-clean $(( $(date +%s) - T1 ))"
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
