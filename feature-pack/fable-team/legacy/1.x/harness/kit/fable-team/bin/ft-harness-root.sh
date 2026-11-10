#!/usr/bin/env bash
# ft-harness-root.sh — source 전용 (r385 · 설계 §2 루트 3분리의 «코드» 루트)
#   ft_harness_root <부른 도구 폴더> → 하네스 코드 루트(팩 `feature-pack/fable-team/harness`) 절대경로 1줄 · 못 풀면 빈 줄 + rc1.
#   순서: ①env FT_HARNESS_ROOT ②<폴더>/../HARNESS_ROOT 파일 1줄(harness/install.sh --apply 가 설치 버전 폴더에 쓴다)
#         ③<폴더>/.. 에 kit/fable-team 이 있으면(팩 harness/bin) ④<폴더>/../../.. 에 kit/fable-team 이 있으면(팩 harness/kit/fable-team/bin).
#   ft_harness_kit <하네스 루트> → "<리포 루트>\t<리포 기준 키트 bin 트리 경로>" (git ls-tree 대조 도구의 --repo·--path 기본값) · 못 풀면 rc1.
ft_harness_root() {
  local d="$1" c=""
  if [ -n "${FT_HARNESS_ROOT:-}" ]; then c="$FT_HARNESS_ROOT"
  elif [ -f "$d/../HARNESS_ROOT" ]; then c="$(sed -n '1p' "$d/../HARNESS_ROOT" | tr -d '\r')"
  elif [ -d "$d/../kit/fable-team" ]; then c="$d/.."
  elif [ -d "$d/../../../kit/fable-team" ]; then c="$d/../../.."
  fi
  [ -n "$c" ] && [ -d "$c/kit/fable-team" ] || { echo ""; return 1; }
  (cd -- "$c" && pwd -P)
}
# 데이터 루트 2종 (r385 · arch#90 109417·109422 · 새 설치본 = git 밖이라 «자기 위치» 로 루트를 못 푼다 → ~/.claude 로 조용히 풀리는 경로 0):
#   ft_data_root <도구 폴더> → 라이브 루트(옛 $HERE/../.. 묶음: 자율·대리 결정·재개·press 허가 · 상태 = <라이브 루트>/.fable-team/state)
#     ①env FT_ROOT ②cwd git 공용 루트의 .fable-team/LIVE_ROOT 1줄(절대경로 폴더) ③옛 설치 꼴(<폴더> = */.fable-team/bin)이면 <폴더>/../.. ④ERROR(stderr) rc1
#     ★state 용이다 — comm(우편함·판정기)은 이것을 쓰지 않는다(r459 · ft_comm_dir)★
#   ft_repo_root <도구 폴더> → 리포 공용 루트(옛 git -C $HERE 묶음: 자원·정지·디스크·사본·비밀 검사 · 상태 = <리포 루트>/.fable-team/state)
#     ①env 는 부르는 쪽(FT_RES_ROOT 등) ②옛 설치 꼴이면 git -C <폴더> 공용 루트(없으면 <폴더>/../..) ③cwd git 공용 루트(.fable-team/ 있을 때) ④ERROR(stderr) rc1
_ft_common_root() { local g; g="$(git ${1:+-C "$1"} rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1; [ -n "$g" ] || return 1; printf '%s\n' "${g%/.git}"; }
ft_data_root() {
  local h="$1" r v
  if [ -n "${FT_ROOT:-}" ]; then printf '%s\n' "$FT_ROOT"; return 0; fi
  if r="$(_ft_common_root)" && [ -f "$r/.fable-team/LIVE_ROOT" ]; then
    v="$(sed -n '1p' "$r/.fable-team/LIVE_ROOT" | tr -d '\r')"
    case "$v" in /*) [ -d "$v" ] && { printf '%s\n' "$v"; return 0; };; esac
    echo "ERROR LIVE_ROOT 가 절대경로 폴더가 아님: «$v» ($r/.fable-team/LIVE_ROOT)" >&2; return 1
  fi
  case "$h" in */.fable-team/bin) (cd -- "$h/../.." && pwd); return;; esac
  echo "ERROR 라이브 루트를 못 풂 — FT_ROOT 없음 · cwd($(pwd)) 가 .fable-team/LIVE_ROOT 있는 git 리포 아님 · 옛 설치 꼴 아님($h)" >&2; return 1
}
ft_repo_root() {
  local h="$1" r
  case "$h" in */.fable-team/bin) _ft_common_root "$h" || (cd -- "$h/../.." && pwd); return;; esac
  if r="$(_ft_common_root)" && [ -d "$r/.fable-team" ]; then printf '%s\n' "$r"; return 0; fi
  echo "ERROR 리포 공용 루트를 못 풂 — env 없음 · cwd($(pwd)) 가 .fable-team/ 있는 git 리포 아님 · 옛 설치 꼴 아님($h)" >&2; return 1
}
# ft_comm_dir <도구 폴더> → <공용 루트>/.fable-team/comm (r459 · 자리 규칙: 코드 = LIVE_BIN · 데이터 = 공용 루트 · 정본 = ref origin/main)
#   ①env FT_MBOX_DIR(comm 폴더 그 자체) ②env FT_ROOT ③<폴더> = */.fable-team/bin 이면 git -C <폴더> 공용 루트(없으면 <폴더>/../..) ④cwd git 공용 루트
#   LIVE_ROOT 는 읽지 않는다(옛 라이브 워크트리 comm = 판정기 없음 → 틱 발사 0 · r459) · comm 폴더 없음 = ERROR(stderr) rc1 · 도구별 env 는 부르는 쪽
ft_comm_dir() {
  local h="$1" c=""
  if [ -n "${FT_MBOX_DIR:-}" ]; then c="$FT_MBOX_DIR"
  elif [ -n "${FT_ROOT:-}" ]; then c="$FT_ROOT/.fable-team/comm"
  else
    case "$h" in */.fable-team/bin) c="$(_ft_common_root "$h" || (cd -- "$h/../.." && pwd))/.fable-team/comm";;
      *) c="$(_ft_common_root)" || { echo "ERROR comm 폴더를 못 풂 — FT_MBOX_DIR·FT_ROOT 없음 · cwd($(pwd)) 가 git 리포 아님 · 옛 설치 꼴 아님($h)" >&2; return 1; }
         c="$c/.fable-team/comm";;
    esac
  fi
  [ -d "$c" ] || { echo "ERROR comm 폴더 없음: $c (공용 루트 · LIVE_ROOT 는 보지 않는다)" >&2; return 1; }
  printf '%s\n' "$c"
}
ft_harness_kit() {
  local top
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd -- "$top" && pwd -P)"
  printf '%s\t%s\n' "$top" "${1#"$top"/}/kit/fable-team/bin"
}
