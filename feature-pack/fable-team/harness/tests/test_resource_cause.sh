#!/usr/bin/env bash
# test_resource_cause.sh — 디스크·메모리 경보 → «원인 좌석» 한 줄 (ft-resource-cause.sh) + 경보·동결 연결.
# 가짜 tmux·ps·임시 루트만 쓴다 — 실 tmux·실 du·실 좌석 0. (60분 증가분 상위 폴더 3개 + 만든 좌석 매핑)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/scripts/fable-team-bin"; KIT="$REPO/scripts/harness-install/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/R"; ST="$R/.fable-team/state"; WT="$T/wt"; S="$T/stub"; mkdir -p "$ST" "$WT/harness-foo" "$WT/other-wt" "$WT/quiet-wt" "$S"
bash -n "$BIN/ft-resource-cause.sh" && ok "bash -n ft-resource-cause.sh" || bad "bash -n"
for f in ft-resource-cause.sh ft-resource-watch.sh ft-disk-alarm.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done

# 가짜 tmux — 세션 목록 · pane(세션 cwd · pid)
cat > "$S/tmux" <<EOF
#!/bin/bash
case "\$1 \$*" in
  *list-sessions*) printf 'byz-harness-nano-foo#0\nbyz-t-owner-claude#1\nbyz-t-cwd-claude#1\nbyz-t-mem-a-claude#1\nbyz-t-mem-b-claude#1\n';;
  *pane_current_path*) printf 'byz-t-cwd-claude#1 %s/other-wt\n' "$WT";;
  *pane_pid*) printf 'byz-t-mem-a-claude#1 100\nbyz-t-mem-b-claude#1 110\n';;
esac
EOF
# 가짜 ps — pid ppid rss(KiB) comm: a 의 claude 가 2GiB(셸 100 아래 중간 프로세스 150 경유) · b 의 claude 가 1GiB · 상관없는 프로세스
cat > "$S/ps" <<'EOF'
#!/bin/bash
printf '%s\n' '200 150 2097152 claude' '150 100 5000 zsh' '210 110 1048576 claude' '300 1 9000000 mds' '220 110 300000 codex'
EOF
chmod 755 "$S/tmux" "$S/ps"

NOW="$(date +%s)"; T2="$NOW"; T1=$((NOW-3700))   # 1시간 전 스냅샷 + 지금 스냅샷
REPOP="$T/tmpbase/repo-abc12345-1700000000-9"; mkdir -p "$REPOP"
printf '%s\t%s\t%s\n' "$REPOP" byz-t-owner-claude#1 "$((NOW-4000))" > "$ST/scratch-repos.tsv"
{
  printf '%s\t%s\t%s\n' "$T1" "$REPOP" 1048576 "$T2" "$REPOP" $((1048576+5*1048576))
  printf '%s\t%s\t%s\n' "$T1" worktrees.total 10485760 "$T2" worktrees.total $((10485760+3*1048576))
  printf '%s\t%s\t%s\n' "$T1" /private/tmp/mystery 100 "$T2" /private/tmp/mystery $((100+2*1048576))
  printf '%s\t%s\t%s\n' "$T1" colima.diffdisk 100 "$T2" colima.diffdisk $((100+1048576/2))
  printf '%s\t%s\t%s\n' "$T1" worktrees.count 10 "$T2" worktrees.count 20
} > "$ST/disk-attrib.tsv"
touch "$WT/harness-foo" "$WT/other-wt"; touch -t 202001010000 "$WT/quiet-wt"   # 최근 60분: harness-foo · other-wt / quiet-wt 는 오래됨

c() { env FT_RES_ROOT="$R" FT_WORKTREES="$WT" PATH="$S:$PATH" bash "$BIN/ft-resource-cause.sh" "$@" 2>&1; }
out="$(c disk)"; rc=$?
[ "$rc" = 0 ] && ok "disk rc0" || bad "disk rc=$rc $out"
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = 0 ] && ok "한 줄(개행 0)" || bad "한 줄이 아님: $out"
has "$out" "repo-abc12345-1700000000-9 +5.0G ← byz-t-owner-claude#1" "임시 사본(repo-<sha>) → 등록된 주인 좌석"
has "$out" "worktrees.total +3.0G ← " "워크트리 합계 증가 = 최근 60분 건드린 워크트리로 풀이"
has "$out" "harness-foo→byz-harness-nano-foo#0" "워크트리 이름 → 나노 좌석 이름 매핑"
has "$out" "other-wt→byz-t-cwd-claude#1" "워크트리 → 그 안에서 도는 tmux 세션(cwd) 매핑"
hasnt "$out" "quiet-wt" "60분 안 건드린 워크트리는 제외"
has "$out" "/private/tmp/mystery +2.0G ← 주인 미상" "주인 못 찾으면 «주인 미상» (추측 0)"
hasnt "$out" "colima" "증가 상위 3개만(4위 제외)"
hasnt "$out" "worktrees.count" "개수 칸은 용량 순위에서 제외"
# 60분 전 스냅샷이 없으면 정직하게
: > "$ST/disk-attrib.tsv"; printf '%s\t%s\t%s\n' "$NOW" worktrees.total 100 > "$ST/disk-attrib.tsv"
out="$(c disk)"; has "$out" "자료 부족" "60분 전 스냅샷 없음 → «자료 부족» (추측 0)"
: > "$ST/disk-attrib.tsv"; out="$(c disk)"; has "$out" "자료 부족" "스냅샷 파일이 비어도 «자료 부족»"
rm -f "$ST/disk-attrib.tsv"; out="$(c disk)"; has "$out" "자료 부족" "스냅샷 파일 없음 → «자료 부족»"

# 메모리: claude·codex 프로세스 상위 3 → 그 프로세스 조상 pane 의 세션
out="$(c mem)"; rc=$?
[ "$rc" = 0 ] && ok "mem rc0" || bad "mem rc=$rc $out"
has "$out" "byz-t-mem-a-claude#1 2.0G" "메모리 1위 = 조상 pane 의 세션(중간 프로세스 경유)"
has "$out" "byz-t-mem-b-claude#1 1.3G" "같은 세션의 claude+codex 합산(1.0G+0.3G)"
hasnt "$out" "mds" "claude·codex 밖 프로세스는 제외"
c bogus >/dev/null 2>&1; [ "$?" = 2 ] && ok "잘못된 모드 rc2" || bad "잘못된 모드 rc"

# ── 경보·동결 연결 ──
grep -q 'ft-resource-cause.sh' "$BIN/ft-disk-alarm.sh" && ok "ft-disk-alarm 이 원인 좌석 도구를 부름" || bad "ft-disk-alarm 연결 없음"
grep -q 'ft-resource-cause.sh' "$BIN/ft-resource-watch.sh" && ok "ft-resource-watch(동결) 이 원인 좌석 도구를 부름" || bad "watch 연결 없음"
MB="$T/mbox.sh"; printf '#!/bin/bash\n[ "$1" = send ] && echo "$*" >> "%s/mbox.log"\necho QUEUED\n' "$T" > "$MB"; chmod +x "$MB"
printf '#!/bin/bash\necho "== 디스크 증가 상위 (직전 스냅샷 대비) =="\necho "  /private/tmp/zzz  +9.00G  100.0MB/min"\n' > "$T/watch-fake.sh"
printf '#!/bin/bash\n[ "$1" = disk ] && echo "ORIGIN-SEAT-LINE"\n' > "$T/cause-fake.sh"; printf '#!/bin/bash\nexit 0\n' > "$T/scratch-fake.sh"; chmod +x "$T/watch-fake.sh" "$T/cause-fake.sh" "$T/scratch-fake.sh"
echo '{"_hil_route": "byz-t-planner-claude#1"}' > "$T/seats-planner.json"; : > "$T/mbox.log"
env FT_RES_ROOT="$R" FT_DISK_FREE_GIB=20 FT_MBOX_SH="$MB" FT_SEATS_JSON="$T/seats-planner.json" FT_RES_WATCH_SH="$T/watch-fake.sh" FT_SCRATCH_REPO_SH="$T/scratch-fake.sh" FT_RESOURCE_CAUSE_SH="$T/cause-fake.sh" \
  bash "$BIN/ft-disk-alarm.sh" >/dev/null 2>&1
has "$(cat "$T/mbox.log")" "[디스크 긴급]" "디스크 긴급 쪽지 발신"
has "$(cat "$T/mbox.log")" "원인 좌석: ORIGIN-SEAT-LINE" "디스크 긴급 쪽지에 «원인 좌석» 줄"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
