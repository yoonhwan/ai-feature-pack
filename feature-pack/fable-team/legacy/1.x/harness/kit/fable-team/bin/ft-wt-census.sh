#!/usr/bin/env bash
# ft-wt-census.sh [--only <경로>] [--h <출력파일>] [--repo <경로>] (r1688) — 실행 = `bash ft-wt-census.sh …`(모드 100644) — 쌓인 워크트리를 «읽기만» 해서 줄마다 «정리 가능 / KEEP + 사유 / 판정 불가» 를 내는 표(TSV)와, 표의 «정리 가능» 줄만 담는 h 생성기.
#   실행 위치 = 리포 안(워크트리 무관). 지우기·가지·refs·stash 손대기 0. 실행(run)은 만들어진 h 를 사람이 승인한 뒤에만.
#   판정 칸(워크트리 1개 = 1줄): ①미커밋·그 가지의 stash ②착지(origin/main·origin/ops/main-base 의 조상 ∨ patch-id(`git cherry` +0) ∨ squash tree)
#     ③원격 가지가 HEAD 를 담음 ④reflog 만 닿는 커밋(가지·원격이 안 닿음) ⑤살아 있는 tmux pane·프로세스 cwd 가 그 안 ⑥설정(*.json·LaunchAgents plist)이 가리키는 경로
#   판정 = 정리 가능(①0 ∧ ②참 ∧ ④0 ∧ ⑤0 ∧ ⑥0 · ③은 ②참이면 무관) · KEEP:<걸린 번호> · 판정 불가(git 실패·한 줄 상한 초과 · 하드 룰 20 «정리 가능으로 치지 않는다»)
#   출력 = TSV(11칸: 경로·가지·HEAD·①·②·③·④·⑤·⑥·마지막커밋·판정) + 요약 1줄. --only 는 그 줄만(요약 0).
#   h = «정리 가능» 줄마다 실행 직전 같은 도구로 그 줄만 다시 재서 정리 가능이면 `git worktree remove <경로>`(--force 0 · -f 0 · 가지·refs·stash 0) → 끝 요약 «지움 N · 건너뜀 M(사유별)»
#   손잡이(시험): FT_WT_CENSUS_ROW_TIMEOUT(기본 7초) · FT_WT_CENSUS_BASES · FT_WT_CENSUS_GIT · FT_WT_CENSUS_TMUX(1) · FT_WT_CENSUS_CONFIG(설정 파일 목록 덮어쓰기) · FT_WT_GIT_SEC(git 1회 상한)
set -uo pipefail
SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename -- "${BASH_SOURCE[0]:-$0}")"
GIT="${FT_WT_CENSUS_GIT:-git}"; ROW_MAX="${FT_WT_CENSUS_ROW_TIMEOUT:-7}"; GIT_SEC="${FT_WT_GIT_SEC:-7}"
BASES="${FT_WT_CENSUS_BASES:-origin/main origin/ops/main-base}"; TMUX_ON="${FT_WT_CENSUS_TMUX:-1}"; CFG="${FT_WT_CENSUS_CONFIG:-}"
ONLY=""; H_OUT=""; REPO=""
while [ $# -gt 0 ]; do case "$1" in --only) ONLY="${2:-}"; shift 2;; --h) H_OUT="${2:-}"; shift 2;; --repo) REPO="${2:-}"; shift 2;; -h|--help) sed -n '2,10p' "$0"; exit 0;; *) echo "usage: $0 [--only <경로>] [--h <출력파일>] [--repo <경로>]" >&2; exit 2;; esac; done
# 물려받은 GIT_* 를 지운다(다른 리포 상태를 읽지 않게) · LC_ALL=C
GIT_CLEAN=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS LC_ALL=C)
# cap <초> <명령…> — 상한 초과 = rc 124(그룹째 TERM · r-wt-sweep 과 같은 꼴)
cap() { perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' "$@"; }
git7() { cap "$GIT_SEC" "${GIT_CLEAN[@]}" "$GIT" -C "$1" "${@:2}"; }   # 워크트리 경로 기준
g7()   { cap "$GIT_SEC" "${GIT_CLEAN[@]}" "$GIT" "$@"; }           # 리포(cwd) 기준
GR() { if [ -n "$REPO" ]; then git7 "$REPO" "$@"; else g7 "$@"; fi; }
ROOT="$(GR rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] || { echo "판정 불가: git 리포가 아니다" >&2; exit 1; }

# ② 착지 — 조상 ∨ patch-id ∨ squash tree (r1676 대조기 3신호)
landed() {  # $1=경로
  local p="$1" b tree
  for b in $BASES; do
    GR rev-parse -q --verify "$b^{commit}" >/dev/null 2>&1 || continue
    git7 "$p" merge-base --is-ancestor HEAD "$b" 2>/dev/null && return 0
    git7 "$p" cherry "$b" HEAD >/tmp/.wtc.$$ 2>/dev/null || { rm -f /tmp/.wtc.$$; return 2; }
    grep -q '^+' /tmp/.wtc.$$ || { rm -f /tmp/.wtc.$$; return 0; }
    rm -f /tmp/.wtc.$$
    tree="$(git7 "$p" rev-parse 'HEAD^{tree}' 2>/dev/null)" || return 2
    [ -n "$tree" ] && git7 "$p" log -n 80 --format=%T "$b" 2>/dev/null | grep -qxF "$tree" && return 0
  done
  return 1
}
# ④ reflog 만 닿는 커밋(가지·원격이 안 닿는 것) — 있으면 KEEP
reflog_only() {  # HEAD reflog 의 커밋 중 가지·원격이 안 닿는 것(최근 50개만 본다)
  local shas n
  shas="$(git7 "$1" reflog show HEAD --format=%H 2>/dev/null | sort -u | head -50)" || return 2
  [ -n "$shas" ] || return 1
  n="$(git7 "$1" rev-list --count $shas --not --branches --remotes 2>/dev/null)" || return 2
  [ "${n:-0}" -gt 0 ] 2>/dev/null && return 0; return 1
}
# ⑤ 점유 — tmux pane cwd · 살아 있는 프로세스 cwd 가 그 안
prefixed() { local x; while IFS= read -r x; do case "$x" in "$1"|"$1"/*) return 0;; esac; done <<<"$2"; return 1; }
busy() {   # lsof 는 일부 프로세스를 못 읽어도 출력은 정상인데 rc≠0 이다(pipefail 에 기대지 않는다)
  local c=""
  if [ "$TMUX_ON" = 1 ] && command -v tmux >/dev/null 2>&1; then
    c="$(cap "$GIT_SEC" tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null)"; prefixed "$1" "$c" && return 0; fi
  command -v lsof >/dev/null 2>&1 || return 1
  c="$(cap "$GIT_SEC" lsof -w -d cwd -F n 2>/dev/null | sed -n 's/^n//p')"; prefixed "$1" "$c"
}
# ⑥ 설정이 가리키는 경로(r1111)
cfg_hit() {
  local f files=()
  if [ -n "$CFG" ]; then for f in $CFG; do files+=("$f"); done; else files=("$ROOT"/.fable-team/*.json "$HOME"/Library/LaunchAgents/com.byz.*.plist); fi
  for f in "${files[@]}"; do [ -f "$f" ] || continue; cap "$GIT_SEC" grep -qF -- "$1" "$f" && return 0; done
  return 1
}
judge() {  # $1=경로 $2=가지(빈값=detached) $3=HEAD 짧은 sha → TSV 1줄
  local p="$1" br="${2:-detached}" head="$3" d1=0 d2=0 d3=0 d4=0 d5=0 d6=0 f=0 o rc t0 el last="-" v r=""
  t0=$(date +%s)
  [ -d "$p" ] || { printf '%s\t%s\t%s\t-\t-\t-\t-\t-\t-\t-\t판정 불가:경로 없음\n' "$p" "$br" "$head"; return; }
  o="$(git7 "$p" status --porcelain 2>/dev/null)"; rc=$?; [ "$rc" = 0 ] || f=1; [ -z "$o" ] || d1=1
  if [ -z "$o" ] && [ "$br" != detached ]; then o="$(git7 "$p" stash list --format=%gs 2>/dev/null)"; rc=$?; [ "$rc" = 0 ] || f=1
    if [ -n "$o" ] && grep -q "on ${br}[: ]" <<<"$o"; then d1=1; fi; fi
  landed "$p"; rc=$?; [ "$rc" = 2 ] && f=1; [ "$rc" = 0 ] && d2=1
  o="$(git7 "$p" branch -r --contains HEAD 2>/dev/null)"; rc=$?; [ "$rc" = 0 ] || f=1; [ -z "$o" ] || d3=1
  reflog_only "$p"; rc=$?; [ "$rc" = 2 ] && f=1; [ "$rc" = 0 ] && d4=1
  busy "$p" && d5=1
  cfg_hit "$p" && d6=1
  last="$(git7 "$p" log -1 --format=%cI 2>/dev/null)"; [ -n "$last" ] || { f=1; last="-"; }
  el=$(( $(date +%s) - t0 )); [ "$el" -le "$ROW_MAX" ] || { f=2; }
  if [ "$f" = 1 ]; then v="판정 불가:git 실패"; elif [ "$f" = 2 ]; then v="판정 불가:한 줄 ${ROW_MAX}초 초과"
  elif [ "$d1" = 0 ] && [ "$d2" = 1 ] && [ "$d4" = 0 ] && [ "$d5" = 0 ] && [ "$d6" = 0 ]; then v="정리 가능"
  else [ "$d1" = 1 ] && r="${r}①"; [ "$d2" = 0 ] && r="${r}②"; [ "$d4" = 1 ] && r="${r}④"; [ "$d5" = 1 ] && r="${r}⑤"; [ "$d6" = 1 ] && r="${r}⑥"; v="KEEP:$r"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "$br" "$head" "$d1" "$d2" "$d3" "$d4" "$d5" "$d6" "$last" "$v"
}
rows() {
  if [ -n "$ONLY" ]; then
    local h b; h="$(git7 "$ONLY" rev-parse HEAD 2>/dev/null)"; b="$(git7 "$ONLY" rev-parse --abbrev-ref HEAD 2>/dev/null)"; [ "$b" = HEAD ] && b=""
    judge "$ONLY" "$b" "${h:0:12}"; return
  fi
  local p="" head="" br=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) [ -n "$p" ] && judge "$p" "$br" "$head"; p="${line#worktree }"; head=""; br="";;
      HEAD\ *) head="${line#HEAD }";;
      branch\ *) br="${line#branch refs/heads/}";;
    esac
  done < <(GR worktree list --porcelain 2>/dev/null; echo)
  [ -n "$p" ] && judge "$p" "$br" "$head"
}
OUT="$(rows)"
printf '%s\n' "$OUT"
if [ -n "$H_OUT" ]; then
  {
    echo '#!/usr/bin/env bash'
    echo '# ft-wt-census h (r1688) — «정리 가능» 줄만 지운다(bash <이 파일>). 실행 직전 그 줄만 다시 재서 바뀌었으면 건너뛴다.'
    echo '# --force 0 · -f 0 · 가지·refs·stash 손대기 0 · 생성기: '"$SELF"
    echo 'set -uo pipefail'
    printf 'CENSUS=%q\nROOT=%q\nGIT=%q\n' "$SELF" "$ROOT" "$GIT"
    echo 'ok=0; sk_none=0; sk_change=0; sk_fail=0'
    printf '%s\n' "$OUT" | awk -F'\t' '$NF=="정리 가능"{print $1}' | while IFS= read -r p; do
      printf 'target=%q\n' "$p"
      printf '%s\n' 'if [ ! -d "$target" ]; then sk_none=$((sk_none+1)); elif [ "$(bash "$CENSUS" --only "$target" --repo "$ROOT" 2>/dev/null | awk -F"\t" "{print \$NF}")" != "정리 가능" ]; then sk_change=$((sk_change+1)); elif "$GIT" -C "$ROOT" worktree remove "$target" 2>/dev/null; then ok=$((ok+1)); else sk_fail=$((sk_fail+1)); fi'
    done
    echo 'echo "요약 지움 ${ok} · 건너뜀 $((sk_none+sk_change+sk_fail))(없음 ${sk_none} · 재판정 바뀜 ${sk_change} · remove 실패 ${sk_fail})"'
  } > "$H_OUT"
fi
[ -n "$ONLY" ] && exit 0
# 요약 1줄 — 사유별 KEEP 수(사유 순서 고정 · awk substr 은 다바이트를 바이트로 잘라 쓸 수 없다)
c=0; k=0; u=0; n=0; why=""; cnt=(0 0 0 0 0); marks=(① ② ④ ⑤ ⑥)
while IFS= read -r line; do
  [ -n "$line" ] || continue; n=$((n+1)); v="${line##*$'\t'}"
  case "$v" in
    "정리 가능") c=$((c+1));;
    KEEP:*) k=$((k+1)); r="${v#KEEP:}"
      for i in 0 1 2 3 4; do case "$r" in *"${marks[$i]}"*) cnt[$i]=$(( cnt[$i] + 1 ));; esac; done;;
    *) u=$((u+1));;
  esac
done <<<"$OUT"
for i in 0 1 2 3 4; do [ "${cnt[$i]}" = 0 ] || why="$why ${marks[$i]}:${cnt[$i]}"; done
printf '요약 정리 가능 %d · KEEP %d%s · 판정 불가 %d (총 %d줄)\n' "$c" "$k" "$([ "$k" = 0 ] || echo "(${why# })")" "$u" "$n"
