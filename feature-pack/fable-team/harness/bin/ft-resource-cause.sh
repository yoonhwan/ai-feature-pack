#!/usr/bin/env bash
# ft-resource-cause.sh disk|mem — 디스크·메모리 경보·동결 때 «누가 만들었나» 한 줄 (R320 추가 범위 · 오빠 «원인 좌석 자동 표시»).
#   disk : 최근 60분 증가분 상위 폴더 3개(disk-attrib.tsv · 직전이 아니라 1시간 전 스냅샷 대비) + 만든 좌석.
#          주인 풀이 = 임시 사본(repo-<sha>·scratch-repos.tsv 등록 주인) · 경로 아래에서 도는 tmux 세션(cwd) · 워크트리 이름 `<팀>-<슬러그>` → 나노 좌석 `byz-<팀>-nano-<슬러그>#0`.
#          워크트리 합계(worktrees.total)가 오른 경우 = 최근 60분 안 건드린 워크트리 상위 3개를 같은 규칙으로 풀이. 못 찾으면 «주인 미상» — 추측하지 않는다.
#   mem  : claude·codex 프로세스 RSS 상위 3 좌석(조상 pane 의 tmux 세션별 합산).
#   출력 = 한 줄(개행 0) · 자료가 없으면 «자료 부족» 한 줄 · rc0 (잘못된 모드 rc2). 읽기 전용 — du·삭제·kill 0 (du 는 감시자가 7초 상한으로 이미 쌓은 표만 읽는다).
#   env(시험): FT_RES_ROOT FT_WORKTREES
set -uo pipefail
MODE="${1:-}"; case "$MODE" in disk|mem) ;; *) echo "usage: $0 disk|mem" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
STATE="$ROOT/.fable-team/state"; TSV="$STATE/disk-attrib.tsv"; REG="$STATE/scratch-repos.tsv"
WORKTREES="${FT_WORKTREES:-$ROOT/.worktrees}"

seat_of_path() {   # $1=절대경로 → 좌석명(없으면 빈 값)
  local p="$1" b s
  b="$(basename "$p")"
  s="$(awk -F'\t' -v p="$p" -v b="$b" 'index(p,$1)==1 || $1 ~ ("/" b "$") {print $2; exit}' "$REG" 2>/dev/null)"
  [ -z "$s" ] && s="$(tmux list-panes -a -F '#{session_name} #{pane_current_path}' 2>/dev/null | awk -v p="$p" 'index($2,p)==1{print $1; exit}')"
  [ -z "$s" ] && s="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | awk -v b="$b" '{ if (match($0, /^byz-[a-z0-9]+-nano-/)) { t=$0; sub(/^byz-/,"",t); team=t; sub(/-nano-.*/,"",team); slug=t; sub(/^[a-z0-9]+-nano-/,"",slug); sub(/#[0-9]+$/,"",slug); if (team "-" slug == b) { print $0; exit } } }')"
  printf '%s' "$s"
}

disk_line() {
  [ -s "$TSV" ] || { echo "자료 부족(disk-attrib.tsv 없음)"; return; }
  local rows name kb owner out="" d dirs
  rows="$(awk -F'\t' '
    { ts[NR]=$1+0; if ($1+0>t2) t2=$1+0; r[NR]=$0 }
    END { for (i=1;i<=NR;i++) if (ts[i]<=t2-3600 && ts[i]>t1) t1=ts[i]
      if (t1==0 || t1==t2) exit
      for (i=1;i<=NR;i++) { split(r[i],f,"\t"); if (f[3] !~ /^[0-9]+$/ || f[2] ~ /\.(count|recent2h|free)$/) continue
        if (f[1]+0==t1) a[f[2]]=f[3]; if (f[1]+0==t2) b[f[2]]=f[3] }
      for (k in b) { d=b[k]-(a[k]+0); if (d>0) printf "%d\t%s\n", d, k } }' "$TSV" | sort -rn | head -3)"
  [ -n "$rows" ] || { echo "자료 부족(60분 전 스냅샷 없음 또는 증가 0)"; return; }
  while IFS="$(printf '\t')" read -r kb name; do
    case "$name" in
      worktrees.total)
        dirs="$(find "$WORKTREES" -mindepth 1 -maxdepth 1 -type d -mmin -60 2>/dev/null | while read -r d; do printf '%s %s\n' "$(stat -f %m "$d" 2>/dev/null)" "$d"; done | sort -rn | head -3 | cut -d' ' -f2-)"
        owner=""
        while read -r d; do [ -n "$d" ] || continue; s="$(seat_of_path "$d")"; owner="$owner${owner:+, }$(basename "$d")${s:+→$s}"; [ -n "$s" ] || owner="$owner(좌석 미상)"; done <<EOF
$dirs
EOF
        [ -n "$owner" ] || owner="최근 60분 건드린 워크트리 없음";;
      /*) owner="$(seat_of_path "$name")"; [ -n "$owner" ] || owner="주인 미상";;
      *)  owner="시스템 폴더(좌석 무관)";;
    esac
    out="$out${out:+; }$name +$(awk -v k="$kb" 'BEGIN{printf "%.1f", k/1048576}')G ← $owner"
  done <<EOF
$rows
EOF
  echo "$out"
}

mem_line() {
  local panes ps_out out
  panes="$(tmux list-panes -a -F '#{session_name} #{pane_pid}' 2>/dev/null)"; ps_out="$(ps -axo pid=,ppid=,rss=,comm= 2>/dev/null)"
  [ -n "$panes" ] && [ -n "$ps_out" ] || { echo "자료 부족(tmux·ps 읽기 실패)"; return; }
  out="$(printf '%s\n---\n%s\n' "$panes" "$ps_out" | awk '
    /^---$/ { sec=1; next }
    sec==0 { pane[$2]=$1; next }
    { pp[$1]=$2; rss[$1]=$3; comm[$1]=$4 }
    END { for (p in pp) { c=comm[p]; sub(/.*\//,"",c); if (c!="claude" && c!="codex") continue
        q=p; n=0; while (q!="" && q+0>1 && n<40) { if (q in pane) { sum[pane[q]]+=rss[p]; break } q=pp[q]; n++ } }
      for (s in sum) printf "%d\t%s\n", sum[s], s }' | sort -rn | head -3 | awk -F'\t' '{printf "%s%s %.1fG", (NR>1?"; ":""), $2, $1/1048576}')"
  [ -n "$out" ] && echo "$out" || echo "자료 부족(claude·codex 프로세스를 좌석에 못 묶음)"
}

case "$MODE" in disk) disk_line;; mem) mem_line;; esac
exit 0
