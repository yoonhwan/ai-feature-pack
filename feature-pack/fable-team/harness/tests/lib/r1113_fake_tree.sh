#!/usr/bin/env bash
# r1113_fake_tree.sh — source 전용. 가짜 좌석 나무(실 프로세스 = `sleep` 스텁 · argv0 이름만 바꿈) + 가짜 tmux·launchctl·ps 필터.
#   실 tmux·실 LSP·실 크롬·실 launchd 0 · 신호는 이 파일이 띄운 스텁에만 닿는다(ps 필터 = 띄운 pid 만 보임).
#   쓰는 쪽: TMP(빈 임시 폴더) 를 정한 뒤 source → fake_init → tree <좌석> <유휴분> <스펙…> · 끝에 fake_cleanup(trap).
#   스펙: <이름> = `exec -a <이름> sleep 300` · trap:<이름> = TERM 무시 · busy = 도구 셸(bash -c 루프) · spawner = TERM 받으면 새 자식 r1113-newkid 를 띄우고 끝남
#         nest:<부모>:<자식> = 부모 밑 자식 1개(자식 pid 는 FAKE_KEEP_RE 로 보임) · orphan <이름> = ppid 1(부모 셸이 곧 끝남)
fake_init() {
  mkdir -p "$TMP/fake" "$TMP/state" "$TMP/permits"
  : > "$TMP/pids"; : > "$TMP/panes"; : > "$TMP/launchd"; : > "$TMP/rss"
  cat > "$TMP/fake/tmux" <<'EOF'
case "$1" in list-panes) cat "$FAKE_PANES"; exit 0;; esac
echo "fake tmux: $*" >&2; exit 1
EOF
  cat > "$TMP/fake/launchctl" <<'EOF'
echo "PID	Status	Label"; awk '{print $1"\t0\tcom.fake."$1}' "$FAKE_LAUNCHD"
EOF
  cat > "$TMP/fake/ps" <<'EOF'
/bin/ps "$@" | awk -v re="$FAKE_KEEP_RE" 'NR==FNR { k[$1] = 1; next } ($1 in k) || (re != "" && $0 ~ re)' "$FAKE_PIDS" -
EOF
  cat > "$TMP/fake/agent.sh" <<'EOF'
out="$1"; shift
for spec in "$@"; do
  case "$spec" in
    trap:*) bash -c 'trap "" TERM; exec -a "$0" sleep 300' "${spec#trap:}" & ;;
    busy) bash -c 'while :; do sleep 1; done' & ;;
    spawner) bash -c 'trap "bash -c \"exec -a r1113-newkid sleep 300\" & exit 0" TERM; while :; do sleep 0.2; done' & ;;
    nest:*) x="${spec#nest:}"; bash -c 'bash -c "exec -a \"\$0\" sleep 300" "$1" & exec -a "$0" sleep 300' "${x%%:*}" "${x#*:}" & spec="${x%%:*}" ;;
    *) bash -c 'exec -a "$0" sleep 300' "$spec" & ;;
  esac
  echo "$! ${spec#trap:}" >> "$out"
done
exec -a claude sleep 300
EOF
  export FT_TMUX="$TMP/fake/tmux" FT_LAUNCHCTL="$TMP/fake/launchctl" FT_PS="$TMP/fake/ps"
  export FAKE_PANES="$TMP/panes" FAKE_LAUNCHD="$TMP/launchd" FAKE_PIDS="$TMP/pids"
  export FT_QUIESCE_RSS_TSV="$TMP/rss" FT_QUIESCE_STATE_DIR="$TMP/state" FT_PERMIT_DIR="$TMP/permits"
  export FT_QUIESCE_WAIT_SEC=2 FT_PRESS_RUNNER_RE='^r1113-no-press-runner$' FAKE_KEEP_RE='r1113-(newkid|lchild)'
}
# tree <좌석> <유휴분> <스펙…> — 띄운 pid 는 $TMP/tree-<좌석>.pids (`pid 이름`) · 에이전트 pid = 첫 줄 «root»
tree() {
  local seat="$1" idle="$2" f="$TMP/tree-${1//[^A-Za-z0-9_-]/_}.pids" i n; shift 2
  : > "$f"; bash "$TMP/fake/agent.sh" "$f" "$@" & local root=$!
  n=$#; for i in $(seq 1 50); do [ "$(wc -l < "$f" | tr -d ' ')" -ge "$n" ] && break; sleep 0.1; done
  echo "$root root" >> "$f"; cut -d' ' -f1 "$f" >> "$TMP/pids"
  printf '%s\t%s\t%s\n' "$seat" "$root" "$(( $(date +%s) - idle * 60 ))" >> "$TMP/panes"
  for i in $(seq 1 30); do /bin/ps -o command= -p "$root" 2>/dev/null | grep -q '^claude' && break; sleep 0.1; done
}
orphan() {   # orphan <이름> — ppid 1 스텁 1개 · pid 는 $TMP/orphan.pid
  ( bash -c 'exec -a "$0" sleep 300' "$1" & echo $! > "$TMP/orphan.pid" ); local p; p="$(cat "$TMP/orphan.pid")"; echo "$p" >> "$TMP/pids"
  for i in $(seq 1 30); do [ "$(/bin/ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && break; sleep 0.1; done
}
pid_of() { awk -v n="$2" '{ p = $1; $1 = ""; sub(/^ /, ""); if ($0 == n) { print p; exit } }' "$TMP/tree-${1//[^A-Za-z0-9_-]/_}.pids"; }   # pid_of <좌석> <이름(공백 포함 그대로)>
alive() { local st; st="$(/bin/ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; [ -n "$st" ] && [ "${st#Z}" = "$st" ]; }   # Z(좀비) = 죽음
rss() { echo -e "$1\t$2" >> "$TMP/rss"; }
kid() { /bin/ps -axo pid=,command= | awk -v n="$1" '$2 == n { print $1 }'; }   # kid <이름> — FAKE_KEEP_RE 로 띄운 자식 pid(들)
fake_cleanup() { { cat "$TMP/pids"; kid r1113-newkid; kid r1113-lchild; } 2>/dev/null | xargs kill -9 2>/dev/null; rm -rf "$TMP"; }
