#!/bin/bash
# ft-lib.sh — fable-team v3 스크립트 7종 공용 헬퍼 (§0-1 승인 판정·원자 규약·감사 로그·세션 파싱)
# 이 파일은 "스크립트 7종"에 포함되지 않는 구조적 보조(sourced lib)다.
# 목적: kill/distill/gzip 래퍼가 공유하는 승인 판정(§0-1), 원자 write(tmp+mv),
#       감사 append, 세션명 파싱, 신호 디렉토리 해석을 단일 소스로 유지(DRY).
# 안전: 실행 파일이 아니라 sourced — set -e를 강제하지 않는다(호출자가 결정).

# ── 경로 해석 ─────────────────────────────────────────────
# 프로젝트 루트: --root 값 우선, 없으면 상향 탐색으로 .fable-team 보유 디렉토리.
ft_resolve_root() {
  local r="$1"
  if [ -n "$r" ]; then printf '%s\n' "$r"; return 0; fi
  local d; d="$(pwd)"
  while [ "$d" != "/" ]; do
    [ -d "$d/.fable-team" ] && { printf '%s\n' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s\n' "$(pwd)"   # 폴백 — 호출자가 .fable-team 부재를 별도 처리
}

ft_dir()       { printf '%s/.fable-team\n' "$1"; }                       # <root>
ft_approvals() { printf '%s/.fable-team/approvals\n' "$1"; }             # <root>
ft_global_signals() { printf '%s/.fable-team/.signals\n' "$1"; }        # <root>
ft_pm_signals() { printf '%s/.fable-team/pm/.signals\n' "$1"; }         # <root>
# per-feature 신호 디렉토리
ft_feat_signals() { printf '%s/.fable-team/state/%s/.signals\n' "$1" "$2"; }  # <root> <slug>

# ── 세션명 파싱: ft-<slug>-<role>#N (PM=ft-pm-<proj>#N) ─────
# 결과 전역: FT_SLUG FT_ROLE FT_INC FT_BASE (FT_BASE = #N 제외한 lineage 베이스)
FT_KNOWN_ROLES="architect analyst implementer tester2 tester da2 da checker pm"
ft_parse_sess() {
  local sess="$1"
  local core="${sess#ft-}"          # ft- 프리픽스 제거
  local base inc
  case "$core" in
    *\#*) base="${core%#*}"; inc="${core##*#}";;
    *)    base="$core";      inc=0;;
  esac
  # FT_BASE는 원 세션명의 프리픽스를 보존한다(B-1). 비-ft 세션(사람이 alias로 띄운 오케)에
  # ft- 를 강제 부여하면 후계가 ft-자칭으로 게이트 면제·lineage 이중화·워커 오염된다.
  case "$sess" in
    ft-*) FT_BASE="ft-${base}";;
    *)    FT_BASE="${base}";;
  esac
  FT_INC="$inc"
  # PM은 role이 선행(ft-pm-<proj>)
  case "$base" in
    pm-*) FT_ROLE="pm"; FT_SLUG="${base#pm-}"; return 0;;
    pm)   FT_ROLE="pm"; FT_SLUG="";            return 0;;
  esac
  # 그 외: 후행 role 매칭
  local r
  for r in $FT_KNOWN_ROLES; do
    case "$base" in
      *-"$r") FT_ROLE="$r"; FT_SLUG="${base%-$r}"; return 0;;
    esac
  done
  FT_ROLE=""; FT_SLUG="$base"; return 0   # role 미상 — slug만
}

# 세션에 대응하는 신호 디렉토리(feature slug 있으면 feature, 없으면 global)
ft_signals_for_sess() {
  local root="$1" sess="$2"
  # 비-ft 세션(오케 자기증류)은 feature/pm 아님 → global signals (state/ 오염 방지, MINOR-7)
  case "$sess" in ft-*) ;; *) ft_global_signals "$root"; return 0;; esac
  ft_parse_sess "$sess"
  if [ -n "$FT_SLUG" ] && [ "$FT_ROLE" != "pm" ]; then
    ft_feat_signals "$root" "$FT_SLUG"
  elif [ "$FT_ROLE" = "pm" ]; then
    ft_pm_signals "$root"
  else
    ft_global_signals "$root"
  fi
}

# ── 원자 write (tmp + mv) ──────────────────────────────────
ft_atomic_write() {  # <target-file> <content-string>
  local target="$1"; shift
  local content="$1"
  local dir; dir="$(dirname "$target")"
  mkdir -p "$dir" 2>/dev/null || return 1
  local tmp="$dir/.tmp.$$.$RANDOM"
  printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

ft_append() {  # <file> <line>  — append-only(원자 append: 각 write는 O_APPEND)
  local f="$1"; shift
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 1
  printf '%s\n' "$1" >> "$f" 2>/dev/null
}

# 감사 로그(append-only, §0-2 L3)
ft_audit() {  # <root> <line>
  ft_append "$(ft_approvals "$1")/approvals-audit.log" "$(date +%s) $2"
}

# ── install.json 판독 ─────────────────────────────────────
# 파이썬으로 점(dot)경로 조회. 부재/오류 시 빈 문자열.
ft_ijson() {  # <root> <dot.path>  (예: approvals.standing.auto_gzip.granted)
  local root="$1" path="$2"
  python3 - "$root/.fable-team/install.json" "$path" <<'PY' 2>/dev/null
import json,sys
try:
    d=json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
cur=d
for k in sys.argv[2].split('.'):
    if isinstance(cur,dict) and k in cur: cur=cur[k]
    else: sys.exit(0)
if isinstance(cur,bool): print("true" if cur else "false")
elif isinstance(cur,(list,dict)): print(json.dumps(cur))
else: print(cur)
PY
}

# spawn_exceptions 목록에 특정 값 존재?
ft_has_exception() {  # <root> <name>
  local root="$1" name="$2" arr
  arr="$(ft_ijson "$root" approvals.spawn_exceptions)"
  case "$arr" in *"\"$name\""*) return 0;; *) return 1;; esac
}

# ── op-token 판정·소비 (§0-1 claim-by-rename) ──────────────
# 반환: 0=허가(standing 또는 토큰 claim 성공) / 3=APPROVAL_REQUIRED
# 사용: ft_check_approval <root> <op:kill|distill|gzip> <target> <op_token_path|"">
ft_check_approval() {
  local root="$1" op="$2" target="$3" token="$4" no_standing="${5:-}"
  # 1) standing 승인 (no_standing=1이면 건너뜀 — 비-ft 대상은 op-token 전용, B-1c)
  local skey granted
  case "$op" in
    kill|distill) skey="autonomous_ft_kill";;
    gzip)         skey="auto_gzip";;
    *) skey="";;
  esac
  if [ -n "$skey" ] && [ "$no_standing" != "1" ]; then
    granted="$(ft_ijson "$root" "approvals.standing.$skey.granted")"
    if [ "$granted" = "true" ]; then
      ft_audit "$root" "APPROVE-STANDING op=$op target=$target key=$skey"
      return 0
    fi
  fi
  # 2) op-token claim
  [ -z "$token" ] && return 3
  [ -f "$token" ] && [ -r "$token" ] || return 3
  local t_op t_target t_expires now
  t_op="$(sed -n 's/^op=//p' "$token" | head -1)"
  t_target="$(sed -n 's/^target=//p' "$token" | head -1)"
  t_expires="$(sed -n 's/^expires=//p' "$token" | head -1)"
  now="$(date +%s)"
  [ "$t_op" = "$op" ] || return 3
  [ "$t_target" = "$target" ] || return 3
  [ -n "$t_expires" ] && [ "$t_expires" -ge "$now" ] 2>/dev/null || return 3
  # consumed/ 보장 — 보장 실패 시 실행 중단(§0-1)
  local consumed; consumed="$(ft_approvals "$root")/consumed"
  mkdir -p "$consumed" 2>/dev/null || return 3
  # claim = mv (원자·1회성). 실패(이미 소비·경합) → exit 3
  local dest="$consumed/$(basename "$token").$now"
  mv "$token" "$dest" 2>/dev/null || return 3
  ft_audit "$root" "APPROVE-TOKEN op=$op target=$target token=$(basename "$token")"
  return 0
}

# ── 세션 CPU 합산(pane_pid 서브트리 %cpu) ──────────────────
ft_sess_cpu() {  # <sess>  → 소수 %cpu 합(문자열). 세션 없으면 빈 문자열.
  local sess="$1" pids pid cpu total="0"
  tmux has-session -t "$sess" 2>/dev/null || { printf ''; return 1; }
  pids="$(tmux list-panes -t "$sess" -F '#{pane_pid}' 2>/dev/null)"
  [ -z "$pids" ] && { printf ''; return 1; }
  # pane_pid + 전 자손
  local allpids=""
  for pid in $pids; do
    allpids="$allpids $pid $(pgrep -P "$pid" 2>/dev/null) $(pgrep -g "$pid" 2>/dev/null)"
  done
  allpids="$(printf '%s\n' $allpids | sort -u)"
  for pid in $allpids; do
    cpu="$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$cpu" ] && total="$(awk -v a="$total" -v b="$cpu" 'BEGIN{printf "%.1f", a+b}')"
  done
  printf '%s\n' "$total"
}

# 세션 pane 프로세스 살아있나(HARD GATE — agent 프로세스 확인)
ft_sess_alive() {  # <sess>
  local sess="$1" pid
  tmux has-session -t "$sess" 2>/dev/null || return 1
  pid="$(tmux list-panes -t "$sess" -F '#{pane_pid}' 2>/dev/null | head -1)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# ── swap-lock 가드 v3 (§L r5 base + r6 consume-once + r7 토큰 정확비교) ──────
# 목적: bin 세트 스왑(update.md §P-2) 중 배포 래퍼의 진입을 물리 차단(정상상태/2회차+).
# 첫 스왑(부트스트랩)은 물리 보장 아님 — quiesce-invariant가 커버(§B1). 물리 보장 주장 금지.
# 발동 = 배포 래퍼 allowlist 문맥 + 유효 락 + 20초 초과 단일 케이스. 그 외 전부 fail-open.
# 호출부: 파일 말미 `ft_swap_guard "$@"` — source 시점 호출 스크립트의 위치 파라미터를
#   함수로 전달해야 bypass consume-once가 `--run` 토큰을 판별할 수 있다(함수 내 "$@"는
#   함수 인자이므로 무인자 호출 시 빈 값 → 토큰 탐지 불가). $0는 sourced 함수 내에서도
#   호출 스크립트를 가리키므로 allowlist/bindir 판정은 무영향.
ft_swap_guard() {
  # bypass = consume-once 토큰 — 폐기 시점은 체인 종단(--run 데몬)뿐. r7: "$@" 토큰 정확
  # 비교("--runner"/"--runtime"/공백 포함 인자값 오탐 제거 — $* 부분문자열 판별 폐기).
  # 체인: 코어 →(명령 접두 env)→ --stop-if-owned / --ensure →(nohup 상속 1회)→ --run 데몬.
  # --run(체인 종단)에서만 unset → 이후 fork되는 send 자식은 미상속 → 다음 스왑에서 정상 가드.
  if [ "$FT_SWAP_BYPASS" = "1" ]; then
    _is_run=0
    for _arg in "$@"; do [ "$_arg" = "--run" ] && { _is_run=1; break; }; done
    [ "$_is_run" = 1 ] && unset FT_SWAP_BYPASS
    unset _is_run _arg
    return 0
  fi
  case "${0##*/}" in                          # H4: 명시 allowlist — 글롭(ft-*.sh) 금지(오발동 방지)
    ft-tmux-spawn.sh|ft-tmux-send.sh|ft-tmux-poll.sh|ft-tmux-kill.sh|ft-tmux-distill.sh|\
    ft-pm-watchd.sh|ft-ctx-triage.sh|ft-gzip.sh) ;;
    *) return 0;;                             # 인터랙티브 셸($0=-zsh/bash)·직접 source — fail-open
  esac
  local bindir lock ts now waited
  bindir="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || return 0
  [ -f "$bindir/ft-lib.sh" ] || return 0      # bin 문맥 아님 — fail-open
  lock="${bindir%/bin}/.swap.lock"
  [ "$lock" = "$bindir/.swap.lock" ] && return 0   # /bin 아래 아님(팩 소스 등) — fail-open
  [ -d "$lock" ] || return 0                  # 평상시: stat 1회 즉시 통과
  now="$(date +%s)"
  ts="$(sed -n '1s/^\([0-9][0-9]*\).*/\1/p' "$lock/owner" 2>/dev/null)"
  [ -n "$ts" ] || ts="$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null)"  # H3 폴백
  if [ -n "$ts" ] && [ $((now - ts)) -gt "${FT_SWAP_TTL:-600}" ]; then
    echo "ft-lib: stale swap-lock(>TTL) — 무시하고 진행(잔존 락 수동 정리 권고: $lock)" >&2
    return 0                                  # stale = fail-open(크래시 잔존 락이 brick 못 함)
  fi
  waited=0
  while [ "$waited" -lt "${FT_SWAP_WAIT:-20}" ]; do
    sleep 1; waited=$((waited+1))
    [ -d "$lock" ] || return 0                # 대기 중 해제 → 정상 진행
  done
  echo "ft-lib: bin swap in progress — retry ($lock)" >&2
  exit 7                                      # SWAP_LOCK_BUSY — allowlist 래퍼 프로세스 한정이라 exit 정당
}
ft_swap_guard "$@"
