#!/usr/bin/env bash
# ft-live-install-check.sh --range <A..B> | --all [--ref <ref>] [--repo <리포>] [--kit <리포 기준 키트 경로>] [--project <프로젝트 루트>] [--map <지도.tsv>]   (R245 · 병합 ≠ 끝)
#   하네스 키트(하네스 코드 루트의 kit/ · r385) 파일이 라이브 위치(FT_BIN · ~/.claude/hooks · ~/.hermes/scripts · launchd 데몬)와 같은지 «읽기만» 대조한다.
#   --range = A..B 에서 바뀐 키트 파일만(대상 집합) · 대조 blob 은 --ref(기본 origin/main) tip · B 가 ref 조상 아니면 ERROR · --all = ref 의 키트 전부. 대조는 blob hash — 지도 = <키트>/LIVE-MAP.tsv.
#   --repo·--kit 기본 = 하네스 코드 루트(FT_HARNESS_ROOT · ../HARNESS_ROOT)의 리포 · 그 리포 기준 kit/ · --project = shim 대조 루트(기본 = 리포 공용 루트).
#   출력: `OK n=<개수> skip=<개수>` 또는 `PENDING n=<개수>` + 항목 줄(DIFF·MISSING·MODE·EXEC-BIT(홈 훅 실행 비트 없음 · r491)·UNMAPPED·NOTLOADED·RESTART·STALE-COPY) + `HINT <폴더> <설치 명령>`.
#   r413: --project 루트와 그 .worktrees/* 의 .fable-team/bin 이 LIVE_BIN 없음 ∧ shim 0 ∧ 파일 ≥1 이면 `STALE-COPY <bin> files=<n>` + `HINT <bin> bash <하네스>/install.sh --apply --project <워크트리>`.
#   종료: 0 = OK · 1 = PENDING · 2 = usage · 3 = ERROR(지도·ref 못 품 — 조용한 통과 금지 · #0 RULE). 쓰기 0 · fetch 0 · 설치는 master 집행.
#   env: FT_BIN(라이브 도구 폴더) · FT_LAUNCHCTL·FT_PS(시험 주입 · 기본 launchctl·ps).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PY="$HERE/ft_live_install_check.py"
[ -f "$PY" ] || { echo "ERROR 대조 모듈 없음: $PY"; exit 3; }
[ $# -ge 1 ] || { echo "usage: $0 --range <A..B> | --all [--ref <ref>] [--repo <리포>] [--kit <키트 경로>] [--project <루트>] [--map <tsv>]" >&2; exit 2; }
python3 -I "$PY" "$@"; rc=$?
[ "$rc" -eq 2 ] && echo "usage: $0 --range <A..B> | --all [--ref <ref>] [--repo <리포>] [--kit <키트 경로>] [--project <루트>] [--map <tsv>]" >&2
exit "$rc"
