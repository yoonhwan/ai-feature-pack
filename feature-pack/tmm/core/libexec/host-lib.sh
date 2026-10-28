#!/bin/bash
# host-lib.sh — 호스트 명부 1장(~/.tmm/hosts.tsv) 과 «호스트 좌표» 함수들. tmm·tmuxc 가 source 한다.
# 실행 래퍼(ssh·프레임·재시도)는 옆 파일 host-run.sh 가 맡는다 — 이 파일은 «명부 해석» 만 한다.
# 이 파일 하나가 «호스트를 아는 유일한 자리» 다(설계 docs/multihost/DESIGN-tail-remote-and-light-git-20261028.md §1.4).
# 명부가 없으면 이 맥(m3) 로컬만 돈다 — 지금 동작 그대로다(되돌림 = 명부 삭제 또는 enabled=0).
#
# 명부 ~/.tmm/hosts.tsv (탭 구분 · '#' 시작 줄은 주석 · TMM_HOSTS 로 경로 변경)
#   name  kind         ssh_alias  path_prefix                          enabled  note
#   m3    local        -          -                                    1        이 맥(허브) — 접두 생략 주소의 기본값 · kind=local 은 정확히 1행
#   mini  tail-remote  mini       /opt/homebrew/bin:$HOME/.local/bin   1        byz 맥 미니
#   oci   tail-remote  oci        $HOME/.local/bin                     1        jarvis OCI
#   ※ path_prefix 는 «원격에서» 확장된다($HOME 은 원격 홈). enabled=0 이면 조회 대상에서 빠진다.
#
# rc 요약(래퍼): 0 성공 · 97 판정 불가 · 98 집행 상한 초과 · 그 밖 = 원격 명령의 rc 그대로.
set +e

H_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H_CALL_TIMEOUT="${H_CALL_TIMEOUT:-7}"      # 회당 7초 (하드 룰 12)
H_RUN_CAP="${H_RUN_CAP:-16}"               # 전체 상한 = 2회 시도 + 종료 여유 2초
H_CONNECT_TIMEOUT="${H_CONNECT_TIMEOUT:-5}"
H_PERSIST="${H_PERSIST:-60}"

h_hosts_file() { printf '%s\n' "${TMM_HOSTS:-$HOME/.tmm/hosts.tsv}"; }

# 명부 한 행의 한 열. 없으면 빈 출력(호출자가 판단).
h_field() {  # <host> <name|kind|ssh_alias|path_prefix|enabled|note>
  local f; f="$(h_hosts_file)"
  [ -f "$f" ] || return 0
  awk -F'\t' -v h="$1" -v k="$2" '
    /^[[:space:]]*#/ || NF < 2 { next }
    $1 == h { for (i = 1; i <= NF; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
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
  case "$1" in
    */*) printf '%s %s\n' "${1%%/*}" "${1#*/}" ;;
    *)   printf '%s %s\n' "$(h_local_name)" "$1" ;;
  esac
}

# ★ControlPath 는 «호스트 이름 그대로»★ — 설계 원안은 %C(해시)였는데, 그러면 로컬에서 «소켓이 섰는지» 를
#  검사할 수 없어 매 호출이 락을 잡는다(실측 2026-10-28). 호스트 이름은 짧아(m3·mini·oci) 경로 길이 제한과
#  무관하므로 이름 그대로 쓴다 — 검사·락·공유가 같은 경로 하나로 맞는다.
h_control_dir() { printf '%s\n' "${H_LOCK_DIR:-$HOME/.ssh/ft-cm}"; }
h_control_path() { printf '%s\n' "$(h_control_dir)/$1"; }

# ★락도 «HOME 안»★ — /tmp 고정 경로는 호스트 이름이 같으면 다른 프로세스·다른 시험·다른 HOME 끼리
#  서로를 막는다(arch 반송 r1 실측: 시험 4칸 동시 실행에서 b 가 /tmp 락을 16초 쥐어 a·c·d 가 rc98).
h_lock_path() { printf '%s\n' "$(h_control_dir)/lock-$1"; }

. "$H_LIB_DIR/host-run.sh"
