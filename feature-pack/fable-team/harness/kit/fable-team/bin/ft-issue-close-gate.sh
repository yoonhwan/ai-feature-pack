#!/usr/bin/env bash
# ft-issue-close-gate.sh <Issue#> <닫는 코멘트 파일|""> <apply 0|1> — Tank 래퍼 close 직전 게이트 (R102 · 판정 1059·1060)
#   close-check --gate 를 돌려 7항(원인 확정)·8항(같은 증상 보류) 또는 관찰 조건이 비었거나 N·보류면 «닫지 않고 관찰 중» 으로 둔다.
#   exit 0 = 통과(래퍼가 close 계속) · 3 = 거절 · 1 = 거절 기록 쓰기 실패(fail-closed · 이슈는 열린 채) · 2 = usage/조회 실패
#   dry-run(apply=0) = 거절 문장 + «apply 면 할 쓰기» 목록만. apply=1 = ①거절된 닫는 코멘트 보존 ②관찰 시작 마커(없을 때만) ③라벨 status:observing(없을 때만) — 순서 고정.
#   r1040: 거절 사유가 «빈 칸»(7·8항 미기입)이면 ①②③ 을 하나도 쓰지 않는다 — 읽기 점검 + 안내 1줄(관찰 조건이 성립한 거절만 표식을 남긴다).
#   쓰기 1회 = timeout 7 + 재시도 1(재시도 전 token 이 이미 올라갔는지 확인 → 결과 불명 중복 방지).
#   시험 훅: FT_TANK_WRAPPER(래퍼 대체) · FT_CLOSE_CHECK_FROM_JSON(조회 대체) · FT_CLOSE_CHECK_REPO · FT_GATE_TIMEOUT_S.
set -uo pipefail
unset GH_TOKEN
N="${1:-}"; CFILE="${2:-}"; APPLY="${3:-0}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
case "$N" in ''|*[!0-9]*) echo "usage: $0 <Issue#> <닫는 코멘트 파일|\"\"> <apply 0|1>" >&2; exit 2;; esac
[ -z "$CFILE" ] || [ -f "$CFILE" ] || { echo "닫는 코멘트 파일 없음: $CFILE" >&2; exit 2; }
WRAP="${FT_TANK_WRAPPER:-$HERE/ft-gh-as-tank.sh}"; LIM="${FT_GATE_TIMEOUT_S:-7}"
TO="$(command -v timeout || command -v gtimeout)" || { echo "timeout(coreutils) 필요 — 7초 룰" >&2; exit 2; }
SRC=(); [ -z "${FT_CLOSE_CHECK_FROM_JSON:-}" ] || SRC+=(--from-json "$FT_CLOSE_CHECK_FROM_JSON")
[ -z "${FT_CLOSE_CHECK_REPO:-}" ] || SRC+=(--repo "$FT_CLOSE_CHECK_REPO")
CARGS=("$N" --gate ${SRC[@]+"${SRC[@]}"}); [ -z "$CFILE" ] || CARGS+=(--extra-comment "$CFILE")

GL="$(bash "$HERE/ft-issue-close-check.sh" "${CARGS[@]}")"; RC=$?   # 거절 문장은 check 가 stderr 로 낸다
[ $RC -eq 3 ] || exit $RC
KIND="$(sed -n 's/^GATE .*kind=\([^ ]*\).*/\1/p' <<<"$GL")"; MARKER="$(sed -n 's/^GATE .*marker=\([01]\).*/\1/p' <<<"$GL")"
LABEL="$(sed -n 's/^GATE .*label=\([01]\).*/\1/p' <<<"$GL")"; REASON="$(sed -n 's/^GATE .* reason=//p' <<<"$GL")"
case "$KIND" in proposal_unapproved|proposal_incomplete) exit 3;; esac   # R234 · 승인 전·링크 없는 제안 Issue — 관찰 상태가 아니라 «아직 닫을 수 없음» · 쓰기 0
# r1040: 7·8항이 «빈 칸» 인 거절 = 아직 안 쓴 실수(관찰 조건 성립 0) — 관찰 표식(코멘트·라벨)을 남기지 않고 거절 문장 + 점검 안내만. 진짜 관찰 조건(n_or_hold 등)만 지금처럼 쓴다.
if [ "$KIND" = blank ]; then   # r1040-mut:blank
  echo "DRY 빈 칸 거절 — 쓰기 0(관찰 표식 안 남김)"
  echo "안내: 닫기 전에 ft-issue-close-check.sh $N 을 먼저 돌려 7·8항(원인 확정·같은 증상 보류)을 점검하라 — 이 거절은 이슈에 아무것도 쓰지 않았다." >&2
  exit 3
fi

if [ "$APPLY" != 1 ]; then
  echo "DRY 거절 시 쓰기(apply 면): ${CFILE:+①거절 코멘트 보존(comment) }$([ "$MARKER" = 0 ] && echo '②관찰 시작 마커(comment) ')$([ "$LABEL" = 0 ] && echo '③라벨 status:observing(label)')"
  exit 3
fi

TOKEN="$(date -u +%Y%m%dT%H%M%SZ)-$N"
fail() { echo "REJECT close #$N — 거절 기록 쓰기 실패($1) · 이슈는 열린 채 · 같은 명령을 다시 실행하면 이어서 복구한다." >&2; exit 1; }
write_comment() { # <단계 keep|marker> <본문 파일> — 실패하면 token 이 이미 올라갔는지 확인한 뒤 1회 재시도
  local i
  for i in 1 2; do
    "$TO" "$LIM" bash "$WRAP" comment "$N" "$2" --apply >/dev/null && return 0
    bash "$HERE/ft-issue-close-check.sh" "$N" --has-token "$TOKEN-$1" ${SRC[@]+"${SRC[@]}"} && return 0
  done
  return 1
}
write_label() { local i; for i in 1 2; do "$TO" "$LIM" bash "$WRAP" label "$N" --add status:observing --apply >/dev/null && return 0; done; return 1; }

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
if [ -n "$CFILE" ]; then   # ① 거절된 닫는 코멘트 보존 — 안의 「관찰: … 재현 있음」 같은 사실이 이슈에 남는다
  { echo "[닫기 거절 · R102 · token=$TOKEN-keep]"; cat "$CFILE"; } > "$TMPD/keep.md"
  write_comment keep "$TMPD/keep.md" || fail "거절 코멘트 보존"
fi
if [ "$MARKER" = 0 ]; then   # ② 마커 = 관찰 상태의 원천(이슈 전체에 「관찰 시작:」 줄이 없을 때만)
  cat > "$TMPD/marker.md" <<EOF
관찰 시작: $(date -u +%Y-%m-%dT%H:%M:%SZ) · 사유: $REASON · token=$TOKEN-marker
닫는 조건: 오빠 폰에서 서로 다른 판(sha) 2회 재현 0
기록 칸(issues master 가 오빠 값을 받을 때마다 1줄):
관찰: 판=<40hex> · 결과=재현 0|재현 있음 · 판정=<번호>
EOF
  write_comment marker "$TMPD/marker.md" || fail "관찰 시작 마커"
fi
if [ "$LABEL" = 0 ]; then write_label || fail "라벨 status:observing"; fi   # ③ 라벨은 표시일 뿐(멱등)
echo "관찰 중으로 기록함 #$N (kind=$KIND) — 이슈는 열린 채"
exit 3
