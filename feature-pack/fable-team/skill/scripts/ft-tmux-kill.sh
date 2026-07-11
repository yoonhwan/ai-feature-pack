#!/bin/bash
# ft-tmux-kill.sh — ft-* 세션 graceful kill = tmuxc kill 검증 래퍼 (§1-3⑤)
# Usage: ft-tmux-kill.sh <sess>|--feature <slug> [--op-token <path>]
# Exit: 0 성공 / 1 비-ft 세션 거부(하드룰 방어) / 3 APPROVAL_REQUIRED(keep_last 범위 포함)
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"

TARGET="" FEATURE="" OP_TOKEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --feature) FEATURE="$2"; shift 2;;
    --op-token) OP_TOKEN="$2"; shift 2;;
    *) TARGET="$1"; shift;;
  esac
done
ROOT="$(ft_resolve_root "")"

# ── ① 가드: ft- prefix 아니면 무조건 거부(승인·토큰 무관하게 선행) ──
guard_ft() {  # <name>
  case "$1" in ft-*) return 0;; *) echo "ft-tmux-kill: 비-ft 세션 거부(하드룰 방어): $1" >&2; exit 1;; esac
}

# lineage 최근 2세대(top-2 incarnation) 여부 — standing 자율 kill 범위 밖(§0-1 keep_last=2)
in_recent2() {  # <sess>  → 0=최근2(범위밖) 1=아님
  ft_parse_sess "$1"; local base="$FT_BASE" me="$FT_INC"
  local nums; nums="$(tmux ls -F '#{session_name}' 2>/dev/null | awk -v b="$base" '
    { if (index($0,b"#")==1){ n=substr($0,length(b)+2); if(n ~ /^[0-9]+$/) print n } }' | sort -rn)"
  local k1 k2; k1="$(printf '%s\n' $nums | sed -n '1p')"; k2="$(printf '%s\n' $nums | sed -n '2p')"
  [ "$me" = "$k1" ] || [ "$me" = "$k2" ]
}

do_kill() {  # <sess>
  local sess="$1"
  # PM kill 시 watchd 동반 정리(3-3④ — 양성 일치 시에만 kill)
  ft_parse_sess "$sess"
  if [ "$FT_ROLE" = "pm" ]; then
    bash "$(dirname "$0")/ft-pm-watchd.sh" --root "$ROOT" --stop-if-owned >/dev/null 2>&1
  fi
  tmuxc kill "$sess" >/dev/null 2>&1
  ft_audit "$ROOT" "KILL $sess"
}

if [ -n "$FEATURE" ]; then
  # feature teardown(stage6 CLOSE) — 승인 판정 후 ft-<slug>-* 전부 정리(명시 종료라 keep_last 미적용)
  ft_check_approval "$ROOT" kill "feature:$FEATURE" "$OP_TOKEN"
  [ $? -eq 0 ] || { echo "ft-tmux-kill: APPROVAL_REQUIRED feature=$FEATURE" >&2; exit 3; }
  killed=0
  while read -r s; do
    case "$s" in ft-"$FEATURE"-*) do_kill "$s"; killed=$((killed+1));; esac
  done < <(tmux ls -F '#{session_name}' 2>/dev/null)
  echo "KILLED feature=$FEATURE count=$killed"
  exit 0
fi

[ -n "$TARGET" ] || { echo "ft-tmux-kill: <sess> 또는 --feature <slug> 필수" >&2; exit 1; }
guard_ft "$TARGET"                        # ① 하드룰 가드(승인보다 선행)

# ⓪ 승인 판정
if [ -n "$OP_TOKEN" ]; then
  # 단발 토큰 = 대상 명시 승인 → keep_last 미적용(사용자가 이 대상 직접 허가)
  ft_check_approval "$ROOT" kill "$TARGET" "$OP_TOKEN"
  [ $? -eq 0 ] || { echo "ft-tmux-kill: APPROVAL_REQUIRED $TARGET" >&2; exit 3; }
else
  # standing 자율 경로 → keep_last=2 범위 밖만 허용
  granted="$(ft_ijson "$ROOT" approvals.standing.autonomous_ft_kill.granted)"
  [ "$granted" = "true" ] || { echo "ft-tmux-kill: APPROVAL_REQUIRED $TARGET" >&2; exit 3; }
  if in_recent2 "$TARGET"; then
    echo "ft-tmux-kill: 최근 2세대 보존(keep_last=2) — 자율 kill 범위 밖: $TARGET" >&2
    exit 3
  fi
fi

do_kill "$TARGET"
echo "KILLED $TARGET"
exit 0
