#!/bin/bash
# ft-tmux-distill.sh — 세션 증류 = tmuxc open(#N+1) + handover token 게이트 + tmuxc kill (§1-3④)
# tmuxc distill 원자 명령은 token 게이트 없이 구세션을 kill하므로 사용하지 않는다.
# Usage: ft-tmux-distill.sh <sess> [--op-token <path>] [--model <id>] [--effort <e>] [--prompt-file <p>]
# Exit: 0 성공(핸드오버 완료) / 3 APPROVAL_REQUIRED / 5 HANDOVER_TIMEOUT / 6 CONCURRENT_LAUNCH / 1 오류
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"
SPAWN="$(dirname "$0")/ft-tmux-spawn.sh"

SESS="$1"; shift 2>/dev/null
OP_TOKEN="" MODEL="" EFFORT="" PROMPT_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --op-token) OP_TOKEN="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --effort) EFFORT="$2"; shift 2;;
    --prompt-file) PROMPT_FILE="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$SESS" ] || { echo "ft-tmux-distill: <sess> 필수" >&2; exit 1; }
ROOT="$(ft_resolve_root "")"

# ⓪ 승인 판정 (§0-1) — ft 세션: standing 또는 op-token / 비-ft(오케 자기증류): op-token 전용(B-1c)
# 비-ft는 standing(autonomous_ft_kill: "ft-* 한정")을 적용하지 않는다 — 하드룰 전파본과 정합.
case "$SESS" in
  ft-*) ft_check_approval "$ROOT" distill "$SESS" "$OP_TOKEN" ;;
  *)    ft_check_approval "$ROOT" distill "$SESS" "$OP_TOKEN" 1 ;;
esac
[ $? -eq 0 ] || { echo "ft-tmux-distill: APPROVAL_REQUIRED $SESS (비-ft는 op-token 전용)" >&2; exit 3; }

ft_parse_sess "$SESS"           # FT_BASE FT_SLUG FT_ROLE FT_INC
BASE="$FT_BASE"; OLDN="$FT_INC"
SIG="$(ft_signals_for_sess "$ROOT" "$SESS")"; mkdir -p "$SIG/archive" 2>/dev/null

# ── launch commitment 영수증: O_EXCL 원자 생성 (2-4A④·동시 기동 방어) ──
RECEIPT="$SIG/distill-launch.$SESS.pid"
( set -o noclobber; printf '%s\n' "$$" > "$RECEIPT" ) 2>/dev/null
if [ $? -ne 0 ]; then
  echo "ft-tmux-distill: CONCURRENT_LAUNCH — 영수증 선존재 $RECEIPT" >&2
  exit 6
fi
archive_receipt() { mv "$RECEIPT" "$SIG/archive/$(basename "$RECEIPT").$(date +%s)" 2>/dev/null; }

# ① 신 incarnation 번호 = 동일 {base}# 최대값+1 (failed 마킹 번호 재사용 금지)
maxn="$OLDN"
while read -r s; do
  case "$s" in "$BASE"\#*)
    n="${s##*#}"; case "$n" in ''|*[!0-9]*) ;; *) [ "$n" -gt "$maxn" ] && maxn="$n";; esac;;
  esac
done < <(tmux ls -F '#{session_name}' 2>/dev/null)
NEWN=$((maxn+1))
# failed 마킹된 번호 스킵
while [ -f "$SIG/handover.$BASE#$NEWN.failed" ]; do NEWN=$((NEWN+1)); done
NEWSESS="$BASE#$NEWN"

# 신세션 agent 판정 (da=codex, 그 외 claude) — FT_ROLE은 위 ft_parse_sess에서 설정됨
AGENT="claude"
[ "$FT_ROLE" = "da" ] && AGENT="codex"

# 신세션 모델/effort 승계 — 미지정 시 ① spawn-audit ② 라이브 argv(tmuxc model) 순.
# self-distill(사람이 zsh alias로 띄운 최상위 오케 세션)은 spawn-audit에 자기 항목이 없어
# ①이 빈 값 → ②에서 tmuxc model 로 구세션의 라이브 --model([1m] 포함)·--effort 를 회수한다.
if [ -z "$MODEL" ]; then
  MODEL="$(awk -v s="$SESS" '$2==s{m=$3} END{print m}' "$SIG/spawn-audit.log" 2>/dev/null)"
  case "$MODEL" in ""|"<tmuxc-role>") MODEL="";; esac   # 플레이스홀더는 미해결 취급
fi
if [ "$AGENT" = "claude" ] && [ -z "$MODEL" ]; then
  LIVE="$(tmuxc model "$SESS" 2>/dev/null)"
  MODEL="$(printf '%s\n' "$LIVE" | sed -n 's/^model=//p' | head -1)"
  [ -z "$EFFORT" ] && EFFORT="$(printf '%s\n' "$LIVE" | sed -n 's/^effort=//p' | head -1)"
fi
# 침묵 강등 금지(사용자 요구): claude인데 모델 미해결이면 plain 강등 대신 실패한다.
if [ "$AGENT" = "claude" ] && [ -z "$MODEL" ]; then
  echo "ft-tmux-distill: MODEL_UNRESOLVED $SESS — spawn-audit·라이브 argv 모두 실패(침묵 강등 방지)" >&2
  archive_receipt
  exit 1
fi

# M-3: 계약 프롬프트 승계 — FT_ROLE 해석 성공 + 기본 계약 파일 존재 시 자동 지정(호출자 미지정 시).
# role 미상(비-ft 오케 자기증류)이면 생략 → 후계는 handover 지시만 받음(현행 유지).
if [ -z "$PROMPT_FILE" ] && [ -n "$FT_ROLE" ]; then
  cand="$ROOT/.fable-team/prompts/$FT_ROLE.md"
  [ -f "$cand" ] && PROMPT_FILE="$cand"
fi

# ② #N+1 스폰 + handover token 명령 포함
# role 미상(비-ft 자기증류)은 --role orch → 후계 오케가 워커 마커(FT_WORKER_ROLE) 없이 부팅(B-1b)
TOKEN="$(date +%s)-$(printf '%08x' $((RANDOM*RANDOM)))"
HANDOVER="$SIG/handover.$NEWSESS.token"
INPUT="state.md·자기 산출물 Read 완료 후 $HANDOVER 에 토큰 '$TOKEN' 을 tmp 작성 후 mv(atomic)로 기록하라"
bash "$SPAWN" --root "$ROOT" --name "$NEWSESS" --agent "$AGENT" --role "${FT_ROLE:-orch}" \
  ${MODEL:+--model "$MODEL"} ${EFFORT:+--effort "$EFFORT"} \
  ${PROMPT_FILE:+--prompt-file "$PROMPT_FILE"} --input "$INPUT" >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "ft-tmux-distill: 신세션 스폰 실패 $NEWSESS" >&2
  archive_receipt; exit 1
fi

# ③ token 파일 대기(5초 간격, 총 180초) + 내용 일치 확인 — 유일한 인계 증거
match=0; waited=0
while [ "$waited" -lt 180 ]; do
  if [ -f "$HANDOVER" ] && [ "$(head -1 "$HANDOVER" 2>/dev/null)" = "$TOKEN" ]; then match=1; break; fi
  sleep 5; waited=$((waited+5))
done

if [ "$match" = "1" ]; then
  # ④ 일치: keep_last=2 — 구세션(#N)·신세션(#N+1) 보존. lineage 최고 2번호 외만 정리.
  nums="$(tmux ls -F '#{session_name}' 2>/dev/null | awk -v b="$BASE" '
    { if (index($0,b"#")==1){ n=substr($0,length(b)+2); if(n ~ /^[0-9]+$/) print n } }' | sort -rn)"
  keep1="$(printf '%s\n' $nums | sed -n '1p')"; keep2="$(printf '%s\n' $nums | sed -n '2p')"
  for n in $nums; do
    if [ "$n" != "$keep1" ] && [ "$n" != "$keep2" ]; then
      tmuxc kill "$BASE#$n" >/dev/null 2>&1
      ft_append "$SIG/spawn-audit.log" "$(date +%s) DISTILL-CLEANUP killed=$BASE#$n keep=$keep1,$keep2"
    fi
  done
  # PM 증류: distill-count 원자 갱신 + 5의 배수면 v14-due 마커 (§3-4)
  if [ "$FT_ROLE" = "pm" ]; then
    PMSIG="$(ft_pm_signals "$ROOT")"; cf="$PMSIG/distill-count"
    c="$(cat "$cf" 2>/dev/null || echo 0)"; c=$((c+1)); ft_atomic_write "$cf" "$c"
    if [ $((c % 5)) -eq 0 ]; then ft_atomic_write "$PMSIG/v14-due" "$(date +%s)"; fi
  fi
  ft_audit "$ROOT" "DISTILL-OK old=$SESS new=$NEWSESS keep=$keep1,$keep2"
  archive_receipt
  echo "DISTILLED $SESS -> $NEWSESS"
  exit 0
else
  # ⑤ timeout/불일치 실패 분기 (#14)
  ft_atomic_write "$SIG/handover.$NEWSESS.failed" "$(date +%s) token-timeout old=$SESS"
  tmux capture-pane -p -t "$NEWSESS" 2>/dev/null | tail -30 > "$SIG/$NEWSESS.disthealth.log" 2>/dev/null
  tmuxc kill "$NEWSESS" >/dev/null 2>&1                  # 신세션 정리(자기가 만든 것 한정)
  ft_audit "$ROOT" "DISTILL-FAIL old=$SESS new=$NEWSESS reason=handover-timeout"
  archive_receipt
  echo "ft-tmux-distill: HANDOVER_TIMEOUT $SESS (신세션 $NEWSESS 정리, 구세션 보존)" >&2
  exit 5
fi
