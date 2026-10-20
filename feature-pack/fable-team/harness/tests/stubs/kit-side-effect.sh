#!/usr/bin/env bash
# kit-side-effect.sh — 부작용 도구(reap·tmux·은퇴) 자리의 시험 스텁 (r536 · tests/lib/kit_bin_copy.sh 가 그 이름으로 덮는다).
# 실제 프로세스·tmux·명부 손 0 · 호출 1줄을 KIT_STUB_LOG(기본 = 스텁이 놓인 폴더/.stub-calls.log)에 남기고 `left=0 rc=0` · exit 0.
here="$(cd -- "$(dirname -- "$0")" && pwd)"
printf '%s %s\n' "$(basename -- "$0")" "$*" >> "${KIT_STUB_LOG:-$here/.stub-calls.log}"
echo "$(basename -- "$0") stub left=0 rc=0"
exit 0
