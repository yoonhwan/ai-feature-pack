#!/usr/bin/env bash
# ft-live-install-check.sh --range <A..B> | --all [--ref <ref>] [--repo <리포>] [--map <지도.tsv>]   (R245 · 병합 ≠ 끝)
#   하네스 키트(scripts/harness-install/) 파일이 라이브 위치(FT_BIN · ~/.claude/hooks · ~/.hermes/scripts · launchd 데몬)와 같은지 «읽기만» 대조한다.
#   --range = A..B 에서 바뀐 키트 파일만 · --all = ref(기본 origin/main) 의 키트 전부. 대조는 blob hash — 지도 = scripts/harness-install/LIVE-MAP.tsv.
#   출력: `OK n=<개수> skip=<개수>` 또는 `PENDING n=<개수>` + 항목 줄(DIFF·MISSING·MODE·UNMAPPED·NOTLOADED·RESTART) + `HINT <폴더> <설치 명령>`.
#   종료: 0 = OK · 1 = PENDING · 2 = usage · 3 = ERROR(지도·ref 못 품 — 조용한 통과 금지 · #0 RULE). 쓰기 0 · fetch 0 · 설치는 master 집행.
#   env: FT_BIN(라이브 도구 폴더) · FT_LAUNCHCTL·FT_PS(시험 주입 · 기본 launchctl·ps).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PY="$HERE/ft_live_install_check.py"
[ -f "$PY" ] || { echo "ERROR 대조 모듈 없음: $PY"; exit 3; }
[ $# -ge 1 ] || { echo "usage: $0 --range <A..B> | --all [--ref <ref>] [--repo <리포>] [--map <tsv>]" >&2; exit 2; }
python3 -I "$PY" "$@"; rc=$?
[ "$rc" -eq 2 ] && echo "usage: $0 --range <A..B> | --all [--ref <ref>] [--repo <리포>] [--map <tsv>]" >&2
exit "$rc"
