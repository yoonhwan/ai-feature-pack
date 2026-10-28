#!/usr/bin/env bash
# ft-scratchpad-census.sh — r1080: 세션 scratchpad 의 git 사본을 «죽은 세션 · 깨끗 · 24h» 판정 표로 남긴다. 기본은 삭제 0.
#   찾기: <루트=FT_SP_ROOT 기본 /private/tmp/claude-$UID>/*/*/scratchpad/* 중 `.git`(폴더=clone · 파일=linked)이 바로 있는 폴더. 중첩 사본은 바깥 것 하나로 센다.
#   세션 판정: 폴더 경로의 세션 uuid 가 `ps -axo command` 의 `--session-id <uuid>` 에 있으면 live · 없으면 dead. ps 실패·0줄 = «판정 불가» rc2 · 표 0.
#   점유: `lsof -a -d cwd -Fn` 1회 · 실패·0줄 = «판정 불가» rc2. 사본 폴더 또는 그 아래가 cwd 면 held.
#   사본별 판정: idle = 사본 아래 최근 쓰기(find -mmin · 1440분 문턱 · .git 은 뺀다 — 우리 git status 가 .git/index mtime 을 갱신해 스스로 «최근쓰기» 로 보이는 것 방지) · dirty = git status --porcelain 줄 수 · unique = HEAD 를 담은 ref 0개(`git for-each-ref --contains HEAD`) · 크기 = du -sk(7초 넘으면 «?»)
#   판정 칸: DEAD-SAFE(dead ∧ held 0 ∧ idle ≥1440 ∧ dirty 0 ∧ unique 0) · DEAD-KEEP(사유) · LIVE · UNKNOWN(판정 불가)
#   출력: 표 .fable-team/state/scratchpad-census.tsv (tmp+mv 통째 교체 · 일반 파일) · stdout 요약 1줄. 회차 상한 FT_SP_BUDGET_SEC(기본 60) — 외부 호출 앞마다 남은 예산을 보고 상한을 줄이고, 넘으면 커서로 넘긴다(«부분 k/N»).
#   ★삭제 스위치(기본 끔)★ .fable-team/state/scratchpad-sweep.enabled 가 있을 때만 DEAD-SAFE 를 지운다: 지우기 직전 같은 사본 재판정 → 로그(경로·HEAD·remote·MB) 먼저 → clone = 폴더 삭제 · linked = 원 저장소에서 그 경로 하나만 worktree remove(prune 0).
#   env(시험용): FT_RES_ROOT · FT_SP_ROOT · FT_SP_STATE · FT_SP_BUDGET_SEC · FT_SP_PS_OUT(파일|읽기 실패면 판정 불가) · FT_SP_LSOF_OUT · FT_SP_GIT
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 4
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "ERROR 리포 루트를 못 찾음(FT_RES_ROOT)" >&2; exit 4; }
STATE="${FT_SP_STATE:-$ROOT/.fable-team/state}"
mkdir -p "$STATE" 2>/dev/null || { echo "ERROR 상태 폴더 생성 실패: $STATE" >&2; exit 4; }
OUT="$STATE/scratchpad-census.tsv"; CUR="$STATE/scratchpad-census.cursor"
SLOG="$STATE/scratchpad-sweep.log"; SWITCH="$STATE/scratchpad-sweep.enabled"
SPROOT="${FT_SP_ROOT:-/private/tmp/claude-$UID}"
BUDGET="${FT_SP_BUDGET_SEC:-60}"
GITBIN="${FT_SP_GIT:-git}"
DEADLINE=$(( $(date +%s) + BUDGET ))
left() { local r=$(( DEADLINE - $(date +%s) )); [ "$r" -gt 0 ] && echo "$r" || echo 0; }
cap() { local r; r="$(left)"; [ "$r" -gt 0 ] || return 1; [ "$r" -gt 7 ] && echo 7 || echo "$r"; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

PS_SNAP=""; LS_SNAP=""
snapshot_ps() { PS_SNAP=""; if [ -n "${FT_SP_PS_OUT:-}" ]; then [ -r "$FT_SP_PS_OUT" ] || return 1; PS_SNAP="$(cat "$FT_SP_PS_OUT")"
  else local c; c="$(cap)" || return 1; PS_SNAP="$(timeout "$c" ps -axo command 2>/dev/null)" || return 1; fi
  [ -n "$PS_SNAP" ]; }
snapshot_lsof() { LS_SNAP=""; if [ -n "${FT_SP_LSOF_OUT:-}" ]; then [ -r "$FT_SP_LSOF_OUT" ] || return 1; LS_SNAP="$(cat "$FT_SP_LSOF_OUT")"
  else local c; c="$(cap)" || return 1; LS_SNAP="$(timeout "$c" lsof -a -d cwd -Fn 2>/dev/null)" || return 1; fi
  [ -n "$LS_SNAP" ]; }
git_c() { local d="$1"; shift; local c; c="$(cap)" || return 1; timeout "$c" "$GITBIN" -C "$d" "$@" 2>/dev/null; }
idle_of() { # "<b" 또는 ">=1440" — find 실패·시간 초과면 rc1
  local d="$1" c o; c="$(cap)" || return 1
  o="$(timeout "$c" find "$d" -name .git -prune -o -mmin -1440 -print -quit 2>/dev/null)" || return 1
  if [ -z "$o" ]; then echo ">=1440"; return 0; fi
  local b; for b in 15 30 60 180 360 720; do c="$(cap)" || return 1
    [ -n "$(timeout "$c" find "$d" -name .git -prune -o -mmin -"$b" -print -quit 2>/dev/null)" ] && { echo "<$b"; return 0; }; done
  echo "<1440"; }
size_of() { local d="$1" c sk; c="$(cap)" || { echo "?"; return 0; }
  sk="$(timeout "$c" du -sk "$d" 2>/dev/null | awk 'NR==1{print $1}')"
  case "$sk" in ''|*[!0-9]*) echo "?";; *) awk -v k="$sk" 'BEGIN{printf "%.1f", k/1024}';; esac; }
held_of() { local p="$1" ln; while IFS= read -r ln; do case "$ln" in n*) ln="${ln#n}"
    [ "$ln" = "$p" ] && return 0; case "$ln" in "$p"/*) return 0;; esac;; esac; done <<<"$LS_SNAP"; return 1; }
uuid_of() { basename "$(dirname "$(dirname "$1")")"; }
repo_of() { # linked 사본의 원 저장소 루트 — 못 찾으면 빈 값
  local p="$1" c; c="$(git_c "$p" rev-parse --git-common-dir)" || return 1
  case "$c" in '') return 1;; /*) :;; *) c="$p/$c";; esac
  case "$c" in */.git) printf '%s' "${c%/.git}";; *) printf '%s' "$c";; esac; }

V_PATH=""; V_KIND=""; V_UUID=""; V_VERDICT=""; V_REASON=""; V_IDLE="-"; V_MB="?"; V_HEAD="-"; V_REMOTE="-"; V_REPO=""
judge() { local p="$1" idle dirty uniq n="0"
  V_PATH="$p"; V_UUID="$(uuid_of "$p")"; V_REASON=""; V_IDLE="-"; V_MB="?"; V_HEAD="-"; V_REMOTE="-"; V_REPO=""
  V_KIND=clone; [ -f "$p/.git" ] && V_KIND=linked
  if grep -q -e "--session-id $V_UUID" <<<"$PS_SNAP"; then V_VERDICT=LIVE; V_REASON="세션 살아 있음"; return 0; fi
  if held_of "$p"; then V_VERDICT=DEAD-KEEP; V_REASON="cwd사용중"; return 0; fi
  V_IDLE="$(idle_of "$p")" || { V_VERDICT=UNKNOWN; V_REASON="판정 불가(idle)"; return 0; }
  dirty="$(git_c "$p" status --porcelain)" || { V_VERDICT=UNKNOWN; V_REASON="판정 불가(git status)"; return 0; }
  n="$(grep -c . <<<"$dirty")"
  uniq="$(git_c "$p" for-each-ref --contains HEAD --format='%(refname)' refs/heads refs/remotes)" || { V_VERDICT=UNKNOWN; V_REASON="판정 불가(git for-each-ref)"; return 0; }
  V_HEAD="$(git_c "$p" rev-parse --short=8 HEAD)" || V_HEAD="-"
  V_REMOTE="$(git_c "$p" config --get remote.origin.url)"; [ -n "$V_REMOTE" ] || V_REMOTE="-"
  V_MB="$(size_of "$p")"
  if [ "$V_IDLE" != ">=1440" ]; then V_VERDICT=DEAD-KEEP; V_REASON="최근쓰기"
  elif [ "$n" != 0 ]; then V_VERDICT=DEAD-KEEP; V_REASON="미커밋$n"
  elif [ -z "$uniq" ]; then V_VERDICT=DEAD-KEEP; V_REASON="유일커밋"
  elif [ "$V_KIND" = linked ]; then V_REPO="$(repo_of "$p")" || V_REPO=""
    if [ -z "$V_REPO" ]; then V_VERDICT=DEAD-KEEP; V_REASON="원 저장소 없음"; else V_VERDICT=DEAD-SAFE; fi
  else V_VERDICT=DEAD-SAFE; fi
  return 0; }
recheck() { # 지우기 직전 같은 사본을 처음과 «같은 규칙»으로 다시 판정 — DEAD-SAFE 일 때만 0
  snapshot_ps || return 1; snapshot_lsof || return 1; judge "$1"; [ "$V_VERDICT" = DEAD-SAFE ]; }
delete_one() { # 0 = 지움 · 1 = 거절(로그 1줄). 로그를 먼저 쓰고 지운다.
  local p="$1" kind="$2" repo="$3" c
  recheck "$p" || { printf '%s\t%s\t재판정 거절\n' "$(iso)" "$p" >> "$SLOG"; return 1; }
  printf '%s\t%s\tHEAD=%s\tremote=%s\tMB=%s\n' "$(iso)" "$p" "${V_HEAD}" "${V_REMOTE}" "${V_MB}" >> "$SLOG"
  c="$(cap || echo 7)"
  if [ "$kind" = linked ]; then timeout "$c" "$GITBIN" -C "$repo" worktree remove "$p" >/dev/null 2>&1
  else rm -rf -- "$p"; fi
  [ -e "$p" ] && return 1
  return 0; }

# ── 사본 목록(중첩 제외 = scratchpad 바로 아래만) ──
fresh=""; for d in "$SPROOT"/*/*/scratchpad/*/; do [ -d "$d" ] || continue; [ -e "${d%/}/.git" ] || continue; fresh="$fresh${d%/}"$'\n'; done
TOTAL="$(printf '%s' "$fresh" | grep -c .)"
work="$fresh"
if [ -s "$CUR" ]; then work=""; while IFS= read -r l; do [ -n "$l" ] && [ -d "$l" ] && work="$work$l"$'\n'; done < "$CUR"
  while IFS= read -r l; do [ -n "$l" ] && ! grep -qxF -- "$l" <<<"$work" && work="$work$l"$'\n'; done <<<"$fresh"; fi
TMP="$OUT.tmp.$$"; : > "$TMP"
judged=0; rest=""; safe=0; keeps=0; lives=0; unks=0; dels=0; mbsum=0
if [ "$(left)" -gt 0 ]; then   # 남은 예산 0 이면 외부 호출 0 — 아래 루프가 전부 커서로 넘긴다
  if ! snapshot_ps; then echo "[scratchpad 사본] 판정 불가 — ps 실패 또는 0줄 (표 0 · 삭제 0)" >&2
    echo "판정 불가: ps 실패 또는 0줄"; rm -f "$TMP"; exit 2; fi
  if ! snapshot_lsof; then echo "[scratchpad 사본] 판정 불가 — lsof 실패 또는 0줄 (표 0 · 삭제 0)" >&2
    echo "판정 불가: lsof 실패 또는 0줄"; rm -f "$TMP"; exit 2; fi
fi
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ "$(left)" -le 0 ]; then rest="$rest$p"$'\n'; continue; fi
  judge "$p"; judged=$((judged+1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$V_VERDICT" "$V_KIND" "$V_MB" "$V_IDLE" "$V_UUID" "$V_PATH" \
    "${V_REASON:--}" "$V_HEAD" "$V_REMOTE" >> "$TMP"
  case "$V_VERDICT" in
    DEAD-SAFE) safe=$((safe+1)); mbsum="$(awk -v a="$mbsum" -v b="$V_MB" 'BEGIN{print a+b}')"
      if [ -e "$SWITCH" ]; then delete_one "$V_PATH" "$V_KIND" "$V_REPO" && dels=$((dels+1)); fi;;
    DEAD-KEEP) keeps=$((keeps+1));; LIVE) lives=$((lives+1));; *) unks=$((unks+1));;
  esac
done <<<"$work"
if ! mv -f "$TMP" "$OUT" 2>/dev/null; then cp -f "$TMP" "$OUT"; fi; rm -f "$TMP"
if [ -n "$rest" ]; then printf '%s' "$rest" > "$CUR"; else rm -f "$CUR"; fi
gib="$(awk -v m="$mbsum" 'BEGIN{printf "%.2f", m/1024}')"
part=""; [ -z "$rest" ] || part=" · 부분 $judged/$TOTAL"
printf '[scratchpad 사본] DEAD-SAFE %s개 %sGiB · DEAD-KEEP %s · LIVE %s · UNKNOWN %s · 삭제 %s%s\n' \
  "$safe" "$gib" "$keeps" "$lives" "$unks" "$dels" "$part"
exit 0
