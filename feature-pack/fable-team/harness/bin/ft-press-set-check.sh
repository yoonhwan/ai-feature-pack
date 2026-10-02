#!/usr/bin/env bash
# ft-press-set-check.sh --runner <러너 파일> --worker-cwd <dir> --gateway-cwd <dir>
#   press 세트 축 (M7 범위 4 · 603 카드 «설계 확정 ①②⑤» 정의 그대로 · single_set_testing §1 규칙 1): 시험은 한 세트에서만.
#   ①러너 값 = 러너 파일이 속한 워크트리의 `git rev-parse HEAD`(40-hex) == worker·gateway cwd 워크트리 HEAD.
#   ②dirty 범위 = 세트가 실행하는 코드 경로 전부(tracked 변경) — 예외 목록 아님. design/·docs/ 는 세트 밖.
#   ⑤우회 = env PRESS_SET_MISMATCH_REASON(공백만 아님) → ERROR(stderr) + stdout «diagnostic» · exit 0. 그 회차는 판정·같은 세트 증거로 못 쓴다.
#   ③b 기동 stamp(DA⑥ 관측 A4 · M7 press-set-axis): 「현재 cwd HEAD」 만 비교하면 기동 뒤 워크트리가 새 커밋으로 바뀌어도 옛 코드로 뜬 서비스가 통과한다.
#     --worker-start·--gateway-start <epoch 초>(서비스 pid 프로세스 시작시각 · 호출자가 ps lstart 로 계산)에 그 워크트리 HEAD 였던 커밋(`git rev-parse HEAD@{<epoch>}` — reflog «기록(이벤트) 시각» 기준,
#     커밋 시각 아님: DA⑥ r2 615b26aa31) = start_head. start_head .. 현재 HEAD 의 `git diff --name-only` 를 SET_PATHS(②와 같은 상수 1곳)로 거른 결과가 1건 이상이면 REJECT ·
#     0건(design/·docs/ 문서 커밋만)이면 통과 — evid 에 start_head·current_head 둘 다 기록. stamp 인자가 없거나 숫자가 아니거나 start_head 를 reflog 에서 못 읽으면
#     (기동 시각이 reflog 최초 항목보다 앞서 git 이 경고만 내고 가장 오래된 항목을 돌려주는 경우 포함) REJECT(통과 추정 금지).
#   pid→cwd 해석(lsof)은 호출자(ft-press-gate.sh) 몫. FE stamp·/health code_sha·러너 자체 거절은 603 카드에 남긴다.
#   exit 0 = 세트 일치 · 1 = REJECT(사유 stdout) · 2 = usage. ★침묵 통과 0 — 어느 경로든 evid 한 줄 이상 출력★
set -uo pipefail
RUNNER=""; WCWD=""; GCWD=""; WSTART=""; GSTART=""
usage() { echo "usage: $0 --runner <file> --worker-cwd <dir> --gateway-cwd <dir> --worker-start <epoch> --gateway-start <epoch>" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --runner) RUNNER="${2:-}"; shift 2 2>/dev/null || usage ;;
    --worker-cwd) WCWD="${2:-}"; shift 2 2>/dev/null || usage ;;
    --gateway-cwd) GCWD="${2:-}"; shift 2 2>/dev/null || usage ;;
    --worker-start) WSTART="${2:-}"; shift 2 2>/dev/null || usage ;;
    --gateway-start) GSTART="${2:-}"; shift 2 2>/dev/null || usage ;;
    *) usage ;;
  esac
done
[ -n "$RUNNER" ] && [ -n "$WCWD" ] && [ -n "$GCWD" ] || usage
SET_PATHS=(worker gateway shared clients/web/src tests/e2e scripts/server)
problems=(); evid=""
HEADVAL=""; TOPVAL=""
_inspect() { # 이름 경로 → evid 한 줄 추가 · HEADVAL=그 워크트리 HEAD(서브셸 금지 — problems 가 사라진다)
  local name="$1" at="$2" dir top head dirty
  HEADVAL=""; TOPVAL=""
  dir="$at"; [ -d "$dir" ] || dir="$(dirname -- "$at")"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { problems+=("$name: git 워크트리 아님($at)"); return 1; }
  head="$(git -C "$top" rev-parse HEAD 2>/dev/null)" || { problems+=("$name: HEAD 조회 실패($top)"); return 1; }
  dirty="$(git -C "$top" status --porcelain -uno -- "${SET_PATHS[@]}" 2>/dev/null)" || { problems+=("$name: dirty 조회 실패($top)"); return 1; }
  evid="${evid}set: ${name} worktree=${top} head=${head} dirty=$(printf '%s' "$dirty" | grep -c .)"$'\n'
  [ -z "$dirty" ] || problems+=("$name: dirty — 세트 경로 tracked 변경 $(printf '%s' "$dirty" | grep -c .)개(예 $(printf '%s' "$dirty" | head -1 | cut -c4-)) @ $top")
  HEADVAL="$head"; TOPVAL="$top"
}
_stamp() { # 이름 기동epoch 워크트리 현재HEAD — 기동 시 HEAD..현재 HEAD 가 실행 코드 경로(SET_PATHS)를 바꿨으면 problems 추가
  local name="$1" start="$2" top="$3" cur="$4" sh changed n rrc drc
  [ -n "$top" ] || return 0
  if [[ ! "$start" =~ ^[0-9]{9,12}$ ]]; then problems+=("$name: 기동 stamp 없음/비숫자(${start:-<빈 값>}) — 서비스 시작시각(epoch)을 받지 못해 옛 코드 여부를 판정할 수 없다"); return 0; fi
  sh="$(git -C "$top" rev-parse --verify "HEAD@{$start}" 2>&1)"; rrc=$?
  if [ "$rrc" -ne 0 ] || [[ ! "$sh" =~ ^[0-9a-f]{40}$ ]]; then problems+=("$name: 기동 stamp 대조 불가 — 기동 시각 HEAD 를 reflog 에서 못 읽음(rc=$rrc · 기동 epoch $start · ${sh:0:80} · $top)"); return 0; fi
  changed="$(git -C "$top" diff --name-only "$sh" "$cur" -- "${SET_PATHS[@]}" 2>/dev/null)"; drc=$?
  if [ "$drc" -ne 0 ]; then problems+=("$name: 기동 시 HEAD ${sh:0:9} .. 현재 HEAD ${cur:0:9} diff 조회 실패 @ $top"); return 0; fi
  n="$(printf '%s' "$changed" | grep -c .)"
  evid="${evid}stamp: ${name} start=${start} start_head=${sh} current_head=${cur} set_changed=${n}"$'\n'
  [ "$n" -eq 0 ] || problems+=("$name: 기동(epoch $start) 뒤 HEAD 가 ${sh:0:9}→${cur:0:9} 로 움직여 실행 코드 경로 ${n}개 변경(예 $(printf '%s' "$changed" | head -3 | paste -sd, -)) — 옛 코드로 뜬 서비스 @ $top")
}
_inspect runner "$RUNNER"; rh="$HEADVAL"; _inspect worker "$WCWD"; wh="$HEADVAL"; _stamp worker "$WSTART" "$TOPVAL" "$HEADVAL"; _inspect gateway "$GCWD"; gh="$HEADVAL"; _stamp gateway "$GSTART" "$TOPVAL" "$HEADVAL"
[ -z "$rh" ] || [ -z "$wh" ] || [ "$rh" = "$wh" ] || problems+=("worker HEAD ${wh:0:9} != runner HEAD ${rh:0:9}")
[ -z "$rh" ] || [ -z "$gh" ] || [ "$rh" = "$gh" ] || problems+=("gateway HEAD ${gh:0:9} != runner HEAD ${rh:0:9}")
printf '%s' "$evid"
if [ "${#problems[@]}" -eq 0 ]; then echo "OK 세트 일치 — runner==worker==gateway HEAD $rh · dirty 0"; exit 0; fi
REASON="${PRESS_SET_MISMATCH_REASON:-}"
if [ -n "${REASON//[[:space:]]/}" ]; then
  echo "ERROR 세트 축 우회(PRESS_SET_MISMATCH_REASON=$REASON) — 불일치 ${#problems[@]}건: ${problems[*]}" >&2
  echo "diagnostic 세트 불일치 우회 회차 — 판정·같은 세트 증거로 사용 0 · 사유: $REASON"
  exit 0
fi
echo "REJECT 세트 축 — 서비스·러너·FE 는 같은 워크트리 같은 HEAD(dirty 0)에서만 (docs/rules/single_set_testing.md §1):"
printf '  - %s\n' "${problems[@]}"
exit 1
