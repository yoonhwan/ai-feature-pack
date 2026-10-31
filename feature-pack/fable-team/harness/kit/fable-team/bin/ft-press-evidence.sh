#!/usr/bin/env bash
# ft-press-evidence.sh pack|check|debt … — r1230 press 증거 묶음(판정 2946 · 오빠 slack 1793416496 «테스트 bts poller 없이는 배포없다»)
#   pack <세트 sha> --run <run_id> --poller <poller_dom.jsonl> --table <4자 표 .md> --turbopack <get_errors 원문 파일> [--repo <dir>] [--remote origin]
#        → 같은 칸 검사 통과 뒤 묶음 커밋 1개(부모 = 세트 · 트리 = poller_dom.jsonl·table.md·turbopack.txt·meta.txt) → git push <remote> refs/press/<세트>-<run_id>
#          4자 표(.md)는 run_id 머리 1줄(«run_id: <id>») + | 축 | 사실 | 시간 | 네 축(아키텍처 문서·코드·로그·화면) · poller 줄 = axis·epoch_ms 필수 · run_id 칸 있는 줄 1줄 이상
#   check --repo <dir> --main <M> --head <S> --landing <Q> --pr <N> [--title <PR 제목>] [--body <PR 본문>] [--root <원장 루트>] [--remote origin]
#        → ft-merge-land 가 부른다 · BYZ 리포 ∧ 배포 경로(cd-dev.yml paths-filter) 변경이면 묶음 필수 · 정확 역변경만 면제 + 빚(refs/press-debt) · 빚 상환(refs/press-debt-paid)
#   debt [--repo <dir>] [--remote origin] [--main <rev>] → 미상환 빚 목록
#   판정 = press_evidence_verify.py(BYZ scripts/ci 사본과 바이트 같음) · 착지·묶음 = press_evidence_land.py · rc 0 통과 · 1 거절 · 2 사용법
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PY="$HERE/press_evidence_land.py"
usage() { sed -n '2,9p' "$HERE/ft-press-evidence.sh" >&2; exit 2; }
[ $# -ge 1 ] || usage
V="$1"; shift
case "$V" in
  pack)
    [ $# -ge 1 ] && [ "${1#-}" = "$1" ] || usage
    SET="$1"; shift
    SEAT="${FT_SEAT:-}"; [ -n "$SEAT" ] || { [ -z "${TMUX:-}" ] || SEAT="$(tmux display-message -p '#S' 2>/dev/null)"; }
    exec python3 "$PY" pack --set "$SET" --seat "${SEAT:-unknown}" "$@";;
  check) exec python3 "$PY" land "$@";;
  debt) exec python3 "$PY" debt "$@";;
  *) usage;;
esac
