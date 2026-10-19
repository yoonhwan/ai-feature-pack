#!/usr/bin/env bash
# ft-scratch-repo.sh — 시험·검토용 «저장소 사본»을 통째 복사 대신 등록형 git worktree(--detach)로 만든다 (R246).
#   ft-scratch-repo.sh <sha|ref> [--repo <저장소>]   사본 생성 → 경로 1줄 출력 · 등록 `.fable-team/state/scratch-repos.tsv`(경로·주인·시각)
#   ft-scratch-repo.sh --done <경로>                 등록된 사본만 worktree 제거 + 등록 줄 삭제 (등록 밖 경로는 거부)
#   ft-scratch-repo.sh --report [--summary]          «주인 없는 사본» 크기 목록 — 삭제 0. --summary = `주인 없는 임시 사본 N개 N.N GiB` 한 줄(0개면 출력 없음)
#   ft-scratch-repo.sh --sweep                       주인 없는 사본 정리(판정 1920): 첫 1회 = 목록 보고만(실삭제 0, 표식 scratch-sweep.armed) · 그 뒤부터 자동 삭제 · 지울 게 없으면 출력 0
#     r444: tmux 목록을 못 읽으면 stdout `ERROR tmux unreadable …` 1줄(호출자 ft-disk-alarm 이 planner 로) + 삭제 0 · 지운 뒤 로그 `swept=N owner-dead=N tmp=N`
#   ft-scratch-repo.sh --judged <경로>               «판정 끝난» 사본이면 rc 0 · 아니면 1 · 등록 사본 아님/없는 경로 2 — 사본 HEAD 가 main 에 착지했거나, 그 sha 앞 8자가 main 의 design/ 문서에 적혔고 그 문서 커밋이 AGE 분 지났을 때(삭제 0 · r-disk-drop-worktree-scratch-census)
#   같은 주인의 «등록 사본» 이 3개를 넘게 살아 있으면 새로 만들 때 stderr WARN + 가장 오래된 «판정 끝난» 사본 경로(삭제는 좌석 손 — `--done <경로>`). env FT_SCRATCH_MAIN(판정 기준 ref · 기본 origin/main 있으면 그것 없으면 main)
#   «주인 없는 사본» = 등록 사본 중 주인 세션이 tmux 에 없는 것 «즉시»(r444 · 나이 문턱 0 · tmux 목록 실패면 이 판정 생략) + TMPDIR `tmp.*` 중 FT_SCRATCH_AGE_MIN(1440분) 지나고 내 소유이며 어떤 프로세스의 cwd 도 아닌 것
#   같은 sha·같은 주인의 등록 사본이 디스크에 있으면 새로 만들지 않고 그 경로를 다시 준다(r444).
#   env: FT_RES_ROOT · FT_SCRATCH_DIR(사본 부모, 기본 $TMPDIR) · FT_SCRATCH_OWNER(주인, 기본 현재 tmux 세션)
#        FT_TMUX_BIN(기본 PATH → /opt/homebrew/bin → /usr/local/bin — launchd PATH 엔 homebrew 가 없다 · r444) · FT_TMUX_SOCKET(있으면 -S) · FT_TMUX_TMPDIR(있으면 TMUX_TMPDIR)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
STATE="$ROOT/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; ARMED="$STATE/scratch-sweep.armed"; SLOG="$STATE/scratch-sweep.log"; AGE="${FT_SCRATCH_AGE_MIN:-1440}"
TMO=""; command -v gtimeout >/dev/null 2>&1 && TMO="gtimeout 7"; [ -n "$TMO" ] || { command -v timeout >/dev/null 2>&1 && TMO="timeout 7"; }
die() { echo "ERROR $1" >&2; exit "${2:-1}"; }
TMUX_BIN="${FT_TMUX_BIN:-$(command -v tmux 2>/dev/null)}"
for _t in /opt/homebrew/bin/tmux /usr/local/bin/tmux; do [ -n "$TMUX_BIN" ] || { [ -x "$_t" ] && TMUX_BIN="$_t"; }; done
[ -z "${FT_TMUX_TMPDIR:-}" ] || export TMUX_TMPDIR="$FT_TMUX_TMPDIR"
tmux_sessions() { [ -n "$TMUX_BIN" ] || return 127; "$TMUX_BIN" ${FT_TMUX_SOCKET:+-S "$FT_TMUX_SOCKET"} list-sessions -F '#{session_name}' 2>/dev/null; }
mkdir -p "$STATE" 2>/dev/null || die "상태 폴더 생성 실패: $STATE" 4
gib() { awk -v k="$1" 'BEGIN{ if (k ~ /^[0-9]+$/) printf "%.2f", k/1048576; else printf "?" }'; }
kb()  { $TMO du -sk "$1" 2>/dev/null | awk '{print $1}'; }
drop_reg() { grep -v "^$1	" "$TSV" > "$TSV.tmp.$$"; mv "$TSV.tmp.$$" "$TSV"; }
rm_copy() { git -C "$1" worktree remove --force "$1" 2>/dev/null || rm -r -f "$1" || return 1; }   # 등록 사본·24h 지난 내 tmp.* 만 호출된다(판정 1920)
registered() { # <경로> → 0 = 등록부에 있음(실경로로 대조 — git 은 /private/var 로, 등록부는 $TMPDIR 의 /var 로 적는다)
  local want p rest; want="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  while IFS="$(printf '\t')" read -r p rest; do [ -d "$p" ] && [ "$(cd "$p" && pwd -P)" = "$want" ] && return 0; done < <(cat "$TSV" 2>/dev/null)
  return 1
}
judged() { # <경로> → 0 = 판정 끝남(착지됐거나 판정문에 적히고 AGE 분 지남)
  local sha h8 m ct
  sha="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || return 1; h8="${sha:0:8}"
  m="${FT_SCRATCH_MAIN:-}"; [ -n "$m" ] || { git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1 && m=origin/main || m=main; }
  git -C "$ROOT" merge-base --is-ancestor "$sha" "$m" 2>/dev/null && return 0
  ct="$(git -C "$ROOT" log "$m" --format=%ct -S"$h8" -n1 -- design 2>/dev/null)"
  [ -n "$ct" ] && [ $(( $(date +%s) - ct )) -ge $((AGE*60)) ]
}
warn_many() { # <주인> — 등록 사본(디스크에 있는 것) > 3 이면 WARN + 가장 오래된 «판정 끝난» 사본
  local o="$1" n=0 p ow t oldest=""
  while IFS="$(printf '\t')" read -r p ow t; do
    [ "$ow" = "$o" ] && [ -d "$p" ] || continue
    n=$((n+1)); [ -n "$oldest" ] || { judged "$p" && oldest="$p"; }
  done < <(cat "$TSV" 2>/dev/null)
  [ "$n" -gt 3 ] || return 0
  echo "WARN 주인 $o 의 등록 사본이 ${n}개 — 가장 오래된 «판정 끝난» 사본: ${oldest:-없음(판정 끝난 사본 0)}${oldest:+ (삭제는 좌석 손: ft-scratch-repo.sh --done $oldest)}" >&2
}
orphans() { # → ORPH = "kb<TAB>경로<TAB>reg|tmp<TAB>사유" 줄들 · N · K
  local SESS p o t d TD cwds; ORPH=""; N=0; K=0; TMUX_OK=1
  add() { ORPH="$ORPH$1	$2	$3	$4
"; N=$((N+1)); case "$1" in ''|*[!0-9]*) ;; *) K=$((K+$1));; esac; }
  # 등록 사본: tmux 목록을 못 읽으면(rc≠0) «세션 0» 으로 세지 않고 이 판정 전체를 건너뛴다(#0 RULE) · 주인 없음 = 즉시(r444 · 나이 문턱 0 — 주인이 죽으면 쓸 사람이 없다)
  if SESS="$(tmux_sessions)"; then
    while IFS="$(printf '\t')" read -r p o t; do
      [ -n "$p" ] && [ -d "$p" ] || continue
      printf '%s\n' "$SESS" | grep -qx -- "$o" || add "$(kb "$p")" "$p" reg "등록 사본 · 주인 $o 없음"
    done < <(cat "$TSV" 2>/dev/null)
  else TMUX_OK=0; echo "ERROR tmux 목록 실패 — 등록 사본 판정 생략 (tmux=${TMUX_BIN:-없음})" >&2; fi
  TD="${TMPDIR:-/tmp}"; TD="${TD%/}"; cwds="$(lsof -w -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  for d in $(find "$TD" -maxdepth 1 -type d -name 'tmp.*' -user "$(id -un)" -mmin +"$AGE" 2>/dev/null); do
    grep -q "^$d" <<<"$cwds" || add "$(kb "$d")" "$d" tmp "TMPDIR tmp.* ${AGE}분 지남"
  done
}

case "${1:-}" in
  --done)
    P="${2:-}"; [ -n "$P" ] && grep -q "^$P	" "$TSV" 2>/dev/null || die "등록된 사본이 아님: ${P:-<없음>}" 2
    rm_copy "$P" || die "제거 실패: $P" 4; drop_reg "$P"; echo "DONE $P";;
  --judged)
    P="${2:-}"; [ -n "$P" ] && [ -d "$P" ] && registered "$P" || die "등록된 사본이 아님: ${P:-<없음>}" 2
    judged "$P"; exit $?;;
  --report)
    orphans
    if [ "${2:-}" = --summary ]; then [ "$N" = 0 ] || printf '주인 없는 임시 사본 %s개 %s GiB\n' "$N" "$(gib "$K")"
    else printf '%s' "$ORPH" | awk -F'\t' '$1!=""{printf "%s\t%s\t%s\n", sprintf("%.2f", $1/1048576), $2, $4}'; fi;;
  --sweep)
    orphans
    # r444: launchd 에서 tmux 를 못 읽으면 «생략» 으로 조용히 끝내지 않는다 — stdout 1줄(호출자가 planner 쪽지로) + 삭제 0(tmp.* 포함)
    if [ "$TMUX_OK" = 0 ]; then printf '%s ERROR tmux unreadable — 삭제 0 (tmux=%s)\n' "$(date +%F)" "${TMUX_BIN:-없음}" >> "$SLOG"
      echo "ERROR tmux unreadable — 임시 사본 정리 생략·삭제 0 (tmux=${TMUX_BIN:-없음} · FT_TMUX_BIN/FT_TMUX_SOCKET 확인)"; exit 0; fi
    [ "$N" != 0 ] || exit 0
    if [ ! -f "$ARMED" ]; then date +%s > "$ARMED"; printf '%s [목록 보고 · 실삭제 0] %s개 %s GiB\n%s' "$(date +%F)" "$N" "$(gib "$K")" "$ORPH" >> "$SLOG"
      printf '[임시 사본 목록 보고 · 실삭제 0 · 다음 정리부터 자동] 주인 없는 사본 %s개 %s GiB: %s\n' "$N" "$(gib "$K")" "$(printf '%s' "$ORPH" | awk -F'\t' 'NR<=3{printf "%s%s", (NR>1?", ":""), $2}')"; exit 0; fi
    DEL=0; DK=0; DREG=0
    while IFS="$(printf '\t')" read -r k p ty why; do
      [ -n "$p" ] || continue
      if rm_copy "$p"; then DEL=$((DEL+1)); case "$k" in ''|*[!0-9]*) ;; *) DK=$((DK+k));; esac; [ "$ty" != reg ] || { drop_reg "$p"; DREG=$((DREG+1)); }; printf '%s 삭제 %s (%s)\n' "$(date +%F)" "$p" "$why" >> "$SLOG"
      else echo "ERROR 삭제 실패: $p" >&2; fi
    done <<EOF
$ORPH
EOF
    printf '%s swept=%s owner-dead=%s tmp=%s\n' "$(date +%F)" "$DEL" "$DREG" "$((DEL-DREG))" >> "$SLOG"
    [ "$DEL" = 0 ] || printf '[임시 사본 자동 삭제] 주인 없는 사본 %s개 %s GiB 삭제(되살릴 수 있는 사본만) — 목록: .fable-team/state/scratch-sweep.log\n' "$DEL" "$(gib "$DK")";;
  -*|"") die "usage: ft-scratch-repo.sh <sha|ref> [--repo <저장소>] | --done <경로> | --judged <경로> | --report [--summary] | --sweep" 2;;
  *)
    REF="$1"; shift; SRC="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ "${1:-}" != --repo ] || { SRC="${2:-}"; shift 2; }
    [ -n "$SRC" ] || die "저장소를 못 찾음(--repo 필요)" 2
    SHA="$(git -C "$SRC" rev-parse --verify -q "$REF^{commit}")" || die "ref 를 못 찾음: $REF" 2
    OWNER="${FT_SCRATCH_OWNER:-$(tmux display-message -p '#S' 2>/dev/null || echo -)}"
    case "$OWNER" in ''|-) die "주인 세션을 모른다(tmux 밖 · FT_SCRATCH_OWNER 없음) — 주인 모르는 사본은 만들지 않는다" 2;; esac
    while IFS="$(printf '\t')" read -r p ow t; do   # r444: 같은 sha·같은 주인 사본이 살아 있으면 재사용(사본 0 추가)
      [ "$ow" = "$OWNER" ] && [ -d "$p" ] && [ "$(git -C "$p" rev-parse HEAD 2>/dev/null)" = "$SHA" ] && { echo "$p"; exit 0; }
    done < <(cat "$TSV" 2>/dev/null)
    BASE="${FT_SCRATCH_DIR:-${TMPDIR:-/tmp}}"; mkdir -p "$BASE"
    DEST="${BASE%/}/repo-$(printf '%.8s' "$SHA")-$(date +%s)-$$"
    git -C "$SRC" worktree add -q --detach "$DEST" "$SHA" >/dev/null || die "worktree add 실패: $DEST" 4
    printf '%s\t%s\t%s\n' "$DEST" "$OWNER" "$(date +%s)" >> "$TSV"; warn_many "$OWNER"; echo "$DEST";;
esac
