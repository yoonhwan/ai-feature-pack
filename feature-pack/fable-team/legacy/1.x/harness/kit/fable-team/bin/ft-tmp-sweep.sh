#!/usr/bin/env bash
# ft-tmp-sweep.sh — /private/tmp 바로 아래의 지난 손 사본(git worktree·clone 을 품은 폴더)을 하루 1회 지운다 (r2073 · 오빠 승인 Slack 1794751400.613599).
#   A1 대상 = BASE 바로 아래 폴더(심링크 아님) ∧ 내 소유 ∧ 안쪽 깊이 3 안에 `.git`(파일 = worktree · 폴더 = clone) 1개 이상 ∧ ft-scratch-repo 등록부에 없는 경로 · 그 밖 = 손 0 · 목록 0
#   A2 남김 = mtime 48시간 안(young) · 어떤 프로세스 cwd 가 그 폴더나 그 아래(cwd) · 안쪽 리포 `git status --porcelain` 1줄↑(dirty)
#            · worktree `git rev-list -n 1 HEAD --not --remotes` 1줄 · clone `git rev-list -n 1 --all --not --remotes` 1줄(unpushed)
#            · git rc≠0·7초 넘김 = 그 폴더 «판정 불가» · lsof 실패(rc≠0·0줄) = 그 실행 전체 삭제 0 «판정 불가 lsof» rc 3
#   A3 첫 1회 = 목록만(표식 state/tmp-sweep.armed) · 그 뒤 삭제 + 원 리포마다 `git worktree prune` 1회 · 한 실행 총 FT_TMP_SWEEP_BUDGET(70)초 · 넘으면 deferred
#      끝 줄 1줄 → state/tmp-sweep.log(지운 폴더는 줄마다) · removed≥1 또는 판정 불가≥1 이면 planner 쪽지 1통
#   A4 지우기 전에 폴더 최상위의 1MiB 안 일반 파일을 state/tmp-sweep-keep/<이름>/ 로 복사 · 복사 실패 = 그 폴더 삭제 0 «판정 불가»
#   A6 쪽지 몫 = 8초(총 상한 < 16 이면 절반) · 훑기 예산 = 총 상한 − 쪽지 몫 · 항목 보기 전에 훑기 예산이 끝나면 그 자리에서 끝 → 이름을 state/tmp-sweep.cursor 에
#      다음 실행은 cursor 항목부터 · 목록 끝 = cursor 지움 · 표식은 목록 끝까지 간 실행에서만 · deferred = 훑지 못한 바로 아래 항목 수
#   env: FT_TMP_SWEEP_BASE(기본 /private/tmp) · FT_RES_ROOT · FT_LSOF_BIN · FT_GIT_BIN · FT_TMP_SWEEP_BUDGET · FT_TMP_SWEEP_AGE_MIN(2880)
#        FT_MBOX_SH · FT_TMP_SWEEP_TO(없으면 FT_SEATS_JSON/seats-planner.json `_hil_route`)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
BASE="${FT_TMP_SWEEP_BASE:-/private/tmp}"; BASE="${BASE%/}"
LSOF="${FT_LSOF_BIN:-lsof}"; GIT="${FT_GIT_BIN:-git}"
BUDGET="${FT_TMP_SWEEP_BUDGET:-70}"; AGE="${FT_TMP_SWEEP_AGE_MIN:-2880}"
NOTE=8; [ "$BUDGET" -ge 16 ] || NOTE=$((BUDGET / 2))   # A6 쪽지 몫
SCAN=$((BUDGET - NOTE))
STATE="$ROOT/.fable-team/state"; LOG="$STATE/tmp-sweep.log"; ARMED="$STATE/tmp-sweep.armed"; CURSOR="$STATE/tmp-sweep.cursor"
KEEP="$STATE/tmp-sweep-keep"; REG="$STATE/scratch-repos.tsv"
mkdir -p "$STATE" || { echo "판정 불가 상태 폴더 생성 실패: $STATE"; exit 4; }
SECONDS=0

logline() { printf '%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$LOG"; }
left() { echo $((SCAN - SECONDS)); }   # 훑기 예산 남은 초(판정·보관·삭제·prune)
cap() { # cap <초> 명령… — 초를 넘기면 SIGALRM 으로 끊는다(rc 142)
  local t="$1"; shift; perl -e 'my $t = shift; alarm $t; exec @ARGV or exit 127' "$t" "$@"
}
bcap() { # bcap <최대 초> 명령… — 남은 총 예산과 최대 초 중 작은 쪽으로 끊는다 · 예산 0 이면 호출 0 rc 124 (R1)
  local l m="$1"; shift; l=$(left); [ "$l" -ge 1 ] || return 124; [ "$l" -le "$m" ] || l="$m"
  cap "$l" "$@"
}
gcap() { bcap 7 "$GIT" "$@"; }   # 남은 예산 안에서 git 1회(최대 7초)
notify() {
  local to="${FT_TMP_SWEEP_TO:-}" mbox="${FT_MBOX_SH:-}"
  [ -n "$to" ] || to="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_hil_route",""))' "${FT_SEATS_JSON:-$ROOT/.fable-team/seats-planner.json}" 2>/dev/null)"
  [ -n "$mbox" ] || { . "$HERE/ft-harness-root.sh" 2>/dev/null && mbox="$(ft_comm_dir "$HERE")/mbox.sh"; }
  if [ -z "$to" ] || [ -z "$mbox" ]; then logline "ERROR 쪽지 수신자·우편함 불명 — 1통 못 보냄"; return 0; fi
  local l=$((BUDGET - SECONDS)); [ "$l" -le 7 ] || l=7   # 쪽지만 총 상한 기준(A6)
  if [ "$l" -lt 1 ]; then logline "ERROR 쪽지 미전달 rc=124 to=$to(총 상한 끝)"; return 0; fi
  cap "$l" bash "$mbox" send "$to" ft-tmp-sweep "$1" >/dev/null 2>>"$LOG" || logline "ERROR 쪽지 미전달 rc=$? to=$to(총 상한·7초)"
}
registered() { # 등록부 첫 칸과 정확히 같은 경로(글자 그대로 또는 실제 경로)
  [ -f "$REG" ] || return 1
  awk -F'\t' -v a="$1" -v b="$2" '$1==a || $1==b {f=1} END{exit !f}' "$REG"
}
repos_of() { find "$1" -mindepth 1 -maxdepth 3 -name .git -prune -print 2>/dev/null; }

# cwd 조회 = 실행당 1회 — 실패면 아무것도 지우지 않는다
CWDS="$(cap 7 "$LSOF" -Fn -d cwd 2>/dev/null)"; lrc=$?
CWDS="$(sed -n 's/^n//p' <<<"$CWDS")"
if [ "$lrc" != 0 ] || [ -z "$CWDS" ]; then
  line="tmp-sweep 판정 불가 lsof rc=$lrc — 이번 실행 삭제 0"
  echo "$line"; logline "$line"; notify "[임시 사본 정리] $line"; exit 3
fi
held() { # held <경로> <실제 경로>
  awk -v a="$1" -v b="$2" 'index($0, a)==1 && (length($0)==length(a) || substr($0, length(a)+1, 1)=="/") {f=1}
    index($0, b)==1 && (length($0)==length(b) || substr($0, length(b)+1, 1)=="/") {f=1} END{exit !f}' <<<"$CWDS"
}

# judge <폴더> → 0 지움 · 1 남김(WHY) · 2 판정 불가(WHY) · 3 예산 끝(deferred) — 지울 때 원 리포 git-common-dir 를 COMMONS 에
judge() {
  local d="$1" g r o rc
  WHY=""; COMMONS=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    r="${g%/.git}"
    [ "$(left)" -ge 1 ] || return 3
    o="$(gcap -C "$r" status --porcelain 2>/dev/null)"; rc=$?
    [ "$rc" = 0 ] || { [ "$(left)" -ge 1 ] || return 3; WHY="판정 불가 git status rc=$rc $r"; return 2; }
    [ -z "$o" ] || { WHY="dirty $r"; return 1; }
    if [ -d "$g" ]; then
      o="$(gcap -C "$r" rev-list -n 1 --all --not --remotes 2>/dev/null)"; rc=$?
    else
      o="$(gcap -C "$r" rev-list -n 1 HEAD --not --remotes 2>/dev/null)"; rc=$?
    fi
    [ "$rc" = 0 ] || { [ "$(left)" -ge 1 ] || return 3; WHY="판정 불가 git rev-list rc=$rc $r"; return 2; }
    [ -z "$o" ] || { WHY="unpushed $r"; return 1; }
    if [ -f "$g" ]; then
      o="$(gcap -C "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$o" ] && COMMONS="$COMMONS$o"$'\n'
    fi
  done <<<"$(repos_of "$d")"
  return 0
}
keep_files() { # 최상위 1MiB 안 일반 파일 → KEEP/<이름>/ (rc≠0 = 실패)
  local d="$1" dst; dst="$KEEP/${1##*/}"
  mkdir -p "$dst" || return 1
  find "$d" -mindepth 1 -maxdepth 1 -type f -size -1024k -print0 | xargs -0 -I{} cp -p {} "$dst/"
}
freek() { df -Pk "$BASE" 2>/dev/null | awk 'NR==2{print $4+0}'; }

ARM=0; [ -f "$ARMED" ] && ARM=1
removed=0 young=0 cwd=0 dirty=0 unp=0 unk=0 deferred=0 listed=0 PRUNE=""
f0=$(freek)
LIST=(); for e in "$BASE"/* "$BASE"/.[!.]*; do [ -e "$e" ] || [ -L "$e" ] || continue; LIST+=("$e"); done
N=${#LIST[@]}; START=0; CUT=""
if [ -f "$CURSOR" ]; then
  cn="$(head -n 1 "$CURSOR" 2>/dev/null)"
  case "$cn" in
    ''|*/*) logline "cursor 읽기 실패 — 처음부터";;
    *) for k in "${!LIST[@]}"; do if [ "${LIST[$k]}" = "$BASE/$cn" ]; then
         START=$k   # A6 cursor 부터
         break; fi; done;;
  esac
fi
for ((i = START; i < N; i++)); do
  d="${LIST[$i]}"
  if [ "$(left)" -lt 1 ]; then CUT=$i
    break   # A6 끊긴 자리
  fi
  [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ] || continue
  n="$(basename "$d")"; [ "$d" = "$BASE/$n" ] || continue
  real="$(cd "$d" 2>/dev/null && pwd -P)" || real="$d"
  registered "$d" "$real" && continue
  [ -n "$(repos_of "$d")" ] || continue
  if [ -n "$(find "$d" -maxdepth 0 -mmin -"$AGE" 2>/dev/null)" ]; then young=$((young+1)); logline "남김 young $d"; continue; fi
  if held "$d" "$real"; then cwd=$((cwd+1)); logline "남김 cwd $d"; continue; fi
  judge "$d"; jr=$?
  case "$jr" in
    3) CUT=$i; break;;
    2) unk=$((unk+1)); logline "남김 $WHY ($d)"; continue;;
    1) case "$WHY" in dirty*) dirty=$((dirty+1));; *) unp=$((unp+1));; esac; logline "남김 $WHY ($d)"; continue;;
  esac
  if [ "$ARM" = 0 ]; then listed=$((listed+1)); echo "목록 지움 대상 $d"; logline "목록 지움 대상 $d"; continue; fi
  if [ "$(left)" -lt 1 ]; then CUT=$i; logline "삭제 미룸 예산 끝 $d(다음 실행)"; break; fi
  keep_files "$d" || { unk=$((unk+1)); logline "남김 판정 불가 판정문 보관 실패 ($d)"; continue; }
  bcap 60 rm -rf "$d"
  if [ -e "$d" ]; then CUT=$i; logline "삭제 미완 $d(다음 실행)"; break; fi
  removed=$((removed+1)); PRUNE="$PRUNE$COMMONS"; logline "삭제 $d"
done
if [ -n "$CUT" ]; then
  deferred=$((N - CUT)); cn="${LIST[$CUT]##*/}"
  printf '%s\n' "$cn" > "$CURSOR"   # A6 cursor 쓰기
  logline "예산 끝 — $cn 부터 다음 실행"
else
  rm -f "$CURSOR"
fi
while IFS= read -r c; do
  [ -n "$c" ] || continue
  if [ "$(left)" -lt 1 ]; then logline "WARN worktree prune 생략 예산 끝 $c(지운 폴더 항목만 남음 · 다음 prune 이 지움)"; continue; fi
  gcap --git-dir="$c" worktree prune 2>/dev/null || logline "WARN worktree prune 실패 $c"
done <<<"$(sort -u <<<"$PRUNE")"
f1=$(freek); freed=$(awk -v a="${f0:-0}" -v b="${f1:-0}" 'BEGIN{x=(b-a)/1048576; if (x<0) x=0; printf "%.1f", x}')
kept=$((young+cwd+dirty+unp+unk))
line="tmp-sweep removed=$removed freed=$freed kept=$kept(young $young · cwd $cwd · dirty $dirty · unpushed $unp · 판정 불가 $unk) deferred=$deferred"
[ "$ARM" = 1 ] || { line="$line · 첫 1회 목록만 대상=$listed"; [ -n "$CUT" ] || : > "$ARMED"; }
echo "$line"; logline "$line"
[ "$removed" -lt 1 ] && [ "$unk" -lt 1 ] || notify "[임시 사본 정리] $line"
exit 0
