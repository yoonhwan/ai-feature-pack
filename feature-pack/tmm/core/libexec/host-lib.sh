#!/bin/bash
# host-lib.sh — 호스트 명부 1장(~/.tmm/hosts.tsv) + ssh 실행 래퍼. tmm·tmuxc 가 source 한다.
#
# ★이 파일 하나가 «호스트를 아는 유일한 자리» 다★ (설계 docs/multihost/DESIGN-tail-remote-and-light-git-20261028.md §1.4).
#   명부가 없으면 이 맥(m3) 로컬만 돈다 — 지금 동작 그대로다(되돌림 = 명부 삭제 또는 enabled=0).
#
# 명부 ~/.tmm/hosts.tsv (탭 구분 · '#' 시작 줄은 주석 · TMM_HOSTS 로 경로 변경)
#   name  kind         ssh_alias  path_prefix                          enabled  note
#   m3    local        -          -                                    1        이 맥(허브) — 접두 생략 주소의 기본값 · kind=local 은 정확히 1행
#   mini  tail-remote  mini       /opt/homebrew/bin:$HOME/.local/bin   1        byz 맥 미니
#   oci   tail-remote  oci        $HOME/.local/bin                     1        jarvis OCI
#   ※ path_prefix 는 «원격에서» 확장된다($HOME 은 원격 홈). enabled=0 이면 조회 대상에서 빠진다.
#
# 계약 (설계 §1.4 계약 보강 1~3 — 이 파일이 그 셋을 전부 소유한다)
#  ① 인자 경계: 가변 값을 ssh 명령 문자열에 절대 넣지 않는다. ssh 에 넘기는 «고정 명령» 은 `bash -s` 하나뿐이고,
#     stdin = 부트스트랩(고정) + 길이 프레임(SCRIPT_LEN/본문/ARGC/(ARG_LEN/값)*). 빈 인자·개행·끝 개행이 바이트 그대로 보존된다.
#  ② 재시도·상한: --idempotent(읽기)만 1회 재시도, --write(쓰기)는 재시도하지 않는다.
#     7초 상한에 걸린 시도 = «집행 상한 초과» → rc=98 (더 기다리지 않는다 — 하드 룰 12).
#     그 밖의 실패(연결 거부·끊김)는 재시도 뒤 rc=97 «판정 불가» 1줄. 바깥 timeout 16 은 최후 방어선(역시 rc=98).
#  ③ ControlMaster: ControlPath=~/.ssh/ft-cm/%C · 최초 수립만 호스트별 flock(/tmp/.ft-cm-lock-<host>)으로 직렬화.
#     소켓이 선 뒤의 호출은 락 없이 공유한다. PATH 는 h_remote_path 하나로만 만든다.
#
# rc 요약: 0 성공 · 97 판정 불가(불명확) · 98 집행 상한 초과 · 그 밖 = 원격 명령의 rc 그대로.
set +e

H_SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
H_TIMEOUT_BIN="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null)"
H_CALL_TIMEOUT="${H_CALL_TIMEOUT:-7}"      # 회당 7초 (하드 룰 12)
H_RUN_CAP="${H_RUN_CAP:-16}"               # 전체 상한 = 2회 시도 + 종료 여유 2초
H_CONNECT_TIMEOUT="${H_CONNECT_TIMEOUT:-5}"
H_PERSIST="${H_PERSIST:-60}"
H_RC_UNKNOWN=97
H_RC_CAP=98

# timeout 이 없는 시스템(macOS 기본)은 gtimeout, 둘 다 없으면 상한 없이 돈다(1줄 경고).
_h_timeout() {  # <secs> <cmd...>
  local s="$1"; shift
  if [ -n "$H_TIMEOUT_BIN" ]; then "$H_TIMEOUT_BIN" "$s" "$@"; return $?; fi
  printf 'host-lib: timeout 명령 없음 — 상한 없이 실행(brew install coreutils)\n' >&2
  "$@"
}

# 호스트별 로컬 락(계약 보강 3). flock 이 있으면 flock, 없으면(macOS 기본) mkdir 스핀락.
_h_with_lock() {  # <lockfile> <cmd...>
  local lock="$1"; shift
  if command -v flock >/dev/null 2>&1; then ( flock 9 || exit 97; "$@" ) 9>"$lock"; return $?; fi
  local d="$lock.d" n=0 rc owner
  while :; do
    if mkdir "$d" 2>/dev/null; then printf '%s\n' "$$" > "$d/pid"; break; fi
    owner="$(cat "$d/pid" 2>/dev/null)"
    # ★죽은 락 회수★ — 상한 초과로 죽인 프로세스의 락이 남으면 다음 호출이 20초를 버린다(실측 2026-10-28).
    if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -rf "$d" 2>/dev/null; continue; fi
    sleep 0.05; n=$((n + 1))
    [ "$n" -gt 400 ] && return 97      # 20초 — 그래도 못 잡으면 판정 불가
  done
  "$@"; rc=$?
  rm -rf "$d" 2>/dev/null
  return $rc
}

h_hosts_file() { printf '%s\n' "${TMM_HOSTS:-$HOME/.tmm/hosts.tsv}"; }

# 명부 한 행의 한 열. 없으면 빈 출력(호출자가 판단).
h_field() {  # <host> <name|kind|ssh_alias|path_prefix|enabled|note>
  local f; f="$(h_hosts_file)"
  [ -f "$f" ] || return 0
  awk -F'\t' -v h="$1" -v k="$2" '
    /^[[:space:]]*#/ || NF < 2 { next }
    $1 == h { n = 0; for (i = 1; i <= NF; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
              if (k == "name") print $1; else if (k == "kind") print $2; else if (k == "ssh_alias") print $3;
              else if (k == "path_prefix") print $4; else if (k == "enabled") print $5; else if (k == "note") print $6;
              exit }
  ' "$f"
}

# 접두 없는 주소의 기본 호스트 = kind=local 행의 이름 (없으면 m3).
h_local_name() {
  local f; f="$(h_hosts_file)" n=""
  [ -f "$f" ] && n="$(awk -F'\t' '/^[[:space:]]*#/ {next} NF<2 {next} { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 == "local") { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1; exit } }' "$f")"
  printf '%s\n' "${n:-m3}"
}

# enabled=1 인 호스트 이름 목록 (명부 순서). 명부가 없으면 로컬 이름 1개.
h_hosts_enabled() {
  local f; f="$(h_hosts_file)"
  if [ ! -f "$f" ]; then h_local_name; return 0; fi
  awk -F'\t' '/^[[:space:]]*#/ {next} NF<2 {next} { for (i = 1; i <= NF; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i); if ($5 == "1") print $1 }' "$f"
}

h_enabled() { [ "$(h_field "$1" enabled)" = 1 ]; }

# 조회 대상 호스트 목록(명부 순서). all = enabled 전부 · 이름 = enabled 일 때만(아니면 stderr 1줄 = R3 건너뛰기).
h_targets() {
  if [ "$1" = all ]; then h_hosts_enabled; return 0; fi
  if [ "$1" = "$(h_local_name)" ]; then printf '%s\n' "$1"; return 0; fi
  if [ "$(h_field "$1" enabled)" = 1 ]; then printf '%s\n' "$1"; return 0; fi
  printf 'tmm: 호스트 %s 는 명부에 없거나 enabled=0 — 건너뜀\n' "$1" >&2
  return 0
}

# 원격 PATH 접두. 명부 값이 없으면 /opt/homebrew/bin (설계 §1.2 — 비로그인 PATH 에 tmux 가 거기 있다).
h_remote_path() {
  local p; p="$(h_field "$1" path_prefix)"
  case "$p" in ""|-) p="/opt/homebrew/bin" ;; esac
  printf '%s\n' "$p"
}

# 주소 분리: "mini/byz-x#0" → "mini byz-x#0" · "byz-x#0" → "<로컬 이름> byz-x#0".
# ★정본 h_split 은 카드3(r1048)★ — 여기서는 «최소 분리» 만 한다: 첫 '/' 만 구분자, 나머지는 좌석 이름 그대로.
h_split() {
  local a="$1"
  case "$a" in
    */*) printf '%s %s\n' "${a%%/*}" "${a#*/}" ;;
    *)   printf '%s %s\n' "$(h_local_name)" "$a" ;;
  esac
}

# ★ControlPath 는 «호스트 이름 그대로»★ — 설계 원안은 %C(해시)였는데, 그러면 로컬에서 «소켓이 섰는지» 를
#  검사할 수 없어 매 호출이 락을 잡는다(실측 2026-10-28). 호스트 이름은 짧아(m3·mini·oci) 경로 길이 제한과
#  무관하므로 이름 그대로 쓴다 — 검사·락·공유가 같은 경로 하나로 맞는다.
h_control_path() { printf '%s\n' "$HOME/.ssh/ft-cm/$1"; }

# ---------- 길이 프레임 (계약 보강 1) ----------
# ★왜 부트스트랩을 «stdin» 이 아니라 ssh 원격 명령에 싣나★ — `ssh <alias> -- bash -s` 로 스크립트와 데이터를
#  같은 stdin 에 실으면, bash 가 stdin 을 덩어리로 읽어버려 뒤따르는 `read` 가 «스크립트 본문» 을 데이터로
#  집어삼킨다(격리 실측 2026-10-28: `[ __args=(): 정수 값이 필요함`). 부트스트랩은 «고정 문자열» 이므로
#  ssh 명령에 넣어도 계약(가변 값 0) 위반이 아니다. 가변 값(접두·경로·인자)은 전부 stdin 프레임으로만 간다.
#  프레임 순서: ①PLEN/접두사 ②SLEN/스크립트본문 ③ARGC ④(ARG_LEN/값)*
_H_BOOTSTRAP='
IFS= read -r __pl; __pfx="$(dd bs=1 count="${__pl:-0}" 2>/dev/null)"
IFS= read -r __sl; __sl="${__sl%$'"'"'\r'"'"'}"
__body="$(dd bs=1 count="${__sl:-0}" 2>/dev/null)"
IFS= read -r __argc
__args=()
__i=0
while [ "$__i" -lt "${__argc:-0}" ]; do
  IFS= read -r __al
  __args[${#__args[@]}]="$(dd bs=1 count="${__al:-0}" 2>/dev/null)"
  __i=$((__i+1))
done
__tf="$(mktemp "${TMPDIR:-/tmp}/ft-host.XXXXXXXX")" || exit 90
printf "%s" "$__body" > "$__tf"
chmod 700 "$__tf" 2>/dev/null
eval "export PATH=\"$__pfx:\$PATH\""
bash "$__tf" "${__args[@]}"; __rc=$?; rm -f "$__tf"; exit $__rc
'

# 프레임 스트림 생성(값만): <path_prefix> <본문파일> [args...]
_h_frames() {
  local pf="$1" f="$2"; shift 2
  local body blen i n="$#"
  body="$(cat "$f")"; body="${body%$'\n'}"    # 끝 개행 1개만 떼어 바이트 수를 정확히 센다(값 안의 개행은 보존)
  printf '%s\n' "$(printf '%s' "$pf" | wc -c | tr -d ' ')"; printf '%s' "$pf"
  blen="$(printf '%s' "$body" | wc -c | tr -d ' ')"
  printf '%s\n' "$blen"
  printf '%s' "$body"
  printf '%s\n' "$n"
  for i in "$@"; do
    printf '%s\n' "$(printf '%s' "$i" | wc -c | tr -d ' ')"
    printf '%s' "$i"
  done
}

# 락 안에서 도는 한 번의 시도 — sshc 는 호출자(_h_ssh_attempt)의 지역 배열이다(bash 동적 스코프).
_h_locked_attempt() { _h_timeout "$H_CALL_TIMEOUT" "${sshc[@]}"; }

_h_ssh_attempt() {  # <host> <alias>   stdin = 프레임 스트림
  local host="$1" alias="$2"
  local cp; cp="$(h_control_path "$host")"
  local lock="/tmp/.ft-cm-lock-$host"
  sshc=(ssh -o BatchMode=yes -o ConnectTimeout="$H_CONNECT_TIMEOUT"
            -o ControlMaster=auto -o ControlPath="$cp" -o ControlPersist="$H_PERSIST" "$alias" -- bash -c "$(printf '%q' "$_H_BOOTSTRAP")")
  if [ -S "$cp" ]; then                      # 이미 선 소켓은 락 없이 공유
    _h_timeout "$H_CALL_TIMEOUT" "${sshc[@]}"
    return $?
  fi
  mkdir -p "$(dirname "$cp")" 2>/dev/null && chmod 700 "$(dirname "$cp")" 2>/dev/null   # 사용자 전용 (설계 보강 3)
  _h_with_lock "$lock" _h_locked_attempt     # 수립은 락 안에서 — 2번째 호출은 소켓을 만나 공유한다
}

# ---------- 실제 실행 (바깥 timeout 안에서 돈다 · 재귀 없음) ----------
_h_run_impl() {  # <host> <--idempotent|--write> <bodyfile> [args...]
  local host="$1" mode="$2" body="$3"; shift 3
  local kind alias pf tries=1 attempt=1 rc tmpd stdin_f
  kind="$(h_field "$host" kind)"
  if [ -z "$kind" ] && [ "$host" = "$(h_local_name)" ]; then kind=local; fi
  if [ "$kind" = local ]; then               # 로컬 = 그대로 실행 (지금 동작 불변)
    case "$mode" in --pipe) bash "$body" "$@" ;; *) bash "$body" "$@" ;; esac
    return $?
  fi
  if [ -z "$kind" ]; then
    printf 'host-lib: unknown host "%s" — 판정 불가\n' "$host" >&2
    return $H_RC_UNKNOWN
  fi
  alias="$(h_field "$host" ssh_alias)"
  [ -n "$alias" ] && [ "$alias" != - ] || { printf 'host-lib: %s ssh_alias 없음 — 판정 불가\n' "$host" >&2; return $H_RC_UNKNOWN; }
  pf="$(h_remote_path "$host")"
  [ "$mode" = --idempotent ] && tries=2
  tmpd="${TMPDIR:-/tmp}"; stdin_f="$tmpd/ft-host-frames.$$.$RANDOM"
  _h_frames "$pf" "$body" "$@" > "$stdin_f" || { rm -f "$stdin_f"; return $H_RC_UNKNOWN; }
  while :; do
    _h_ssh_attempt "$host" "$alias" < "$stdin_f"
    rc=$?
    case "$rc" in
      0) rm -f "$stdin_f"; return 0 ;;
      124|137) rm -f "$stdin_f"; return $H_RC_CAP ;;    # 7초 상한 = 집행 상한 초과, 재시도 0
      255) : ;;                                        # ssh 자체 실패(연결 거부·끊김) — 읽기만 재시도
      *) rm -f "$stdin_f"; return $rc ;;                 # 원격 명령의 rc 는 그대로 전달
    esac
    [ "$attempt" -ge "$tries" ] && break
    attempt=$((attempt + 1))
    stdin_f="$tmpd/ft-host-frames.$$.$RANDOM"
    _h_frames "$pf" "$body" "$@" > "$stdin_f" || { rm -f "$stdin_f"; return $H_RC_UNKNOWN; }
  done
  rm -f "$stdin_f" 2>/dev/null
  printf 'host-lib: %s 판정 불가 (rc=%s)\n' "$host" "$rc" >&2
  return $H_RC_UNKNOWN
}

# ---------- 공개 API ----------
# h_run <host> <--idempotent|--write> <cmd...>  — 원격에서 cmd 를 실행한다(로컬이면 그대로).
h_run() {
  local host="$1" mode="$2"; shift 2
  local bodyd body rc
  bodyd="${TMPDIR:-/tmp}/ft-host-body.$$.$RANDOM"
  { printf 'exec "$@"\n'; } > "$bodyd"
  _h_timeout "$H_RUN_CAP" bash -c 'source "$0" >/dev/null 2>&1; _h_run_impl "$@"' "$H_SELF" "$host" "$mode" "$bodyd" "$@"
  rc=$?
  rm -f "$bodyd"
  case "$rc" in 124|137) return $H_RC_CAP ;; esac
  return $rc
}

# h_pipe <host> <스크립트파일> [args...] — 스크립트를 stdin 으로 흘려 원격 bash 가 실행(설치 불요).
h_pipe() {
  local host="$1" f="$2"; shift 2
  [ -f "$f" ] || { printf 'host-lib: 스크립트 없음 %s\n' "$f" >&2; return $H_RC_UNKNOWN; }
  local rc
  _h_timeout "$H_RUN_CAP" bash -c 'source "$0" >/dev/null 2>&1; _h_run_impl "$@"' "$H_SELF" "$host" --idempotent "$f" "$@"
  rc=$?
  case "$rc" in 124|137) return $H_RC_CAP ;; esac
  return $rc
}

# h_tmux <host> <--idempotent|--write> <tmux args...>
h_tmux() { local host="$1" mode="$2"; shift 2; h_run "$host" "$mode" tmux "$@"; }
