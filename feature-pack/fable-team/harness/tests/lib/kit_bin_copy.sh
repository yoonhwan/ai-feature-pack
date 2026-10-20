#!/usr/bin/env bash
# kit_bin_copy.sh <임시 bin> — 시험용 «키트 bin 통째 복사» 도우미 (r536 · r516 묶음 ⑥ 임시 bin 짝 누락).
# 키트 kit/fable-team/bin 의 일반 파일 전부(설치 install.sh --apply 와 같은 집합)를 <임시 bin> 에 cp -p 한 뒤,
#   부작용 도구(프로세스 회수·tmux 조작·좌석 은퇴)를 tests/stubs/kit-side-effect.sh 로 덮는다 — 실제 kill·tmux·reap 0.
# 스텁 호출은 KIT_STUB_LOG(기본 <임시 bin>/.stub-calls.log)에 «<도구 이름> <인자>» 1줄 · 출력 `left=0 rc=0` · exit 0.
# 출력 1줄: `KIT-BIN-COPY files=<N> stubbed=<이름,…>` · 키트·임시 bin 없으면 stderr 1줄 + exit 1.
set -uo pipefail
LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$LIB/../../kit/fable-team/bin"; STUB="$LIB/../stubs/kit-side-effect.sh"
DST="${1:?usage: kit_bin_copy.sh <임시 bin>}"
[ -d "$KIT" ] && [ -f "$STUB" ] || { echo "kit_bin_copy: 키트 bin 또는 스텁 없음($KIT · $STUB)" >&2; exit 1; }
mkdir -p "$DST" || { echo "kit_bin_copy: 임시 bin 못 만듦($DST)" >&2; exit 1; }
SIDE_EFFECT="ft-seat-reap.sh ft-opencode-reap.sh ft-leak-reap.sh ft-docker-test-reap.sh ft-seat-retire.sh ft-tmux-kill.sh ft-tmux-spawn.sh ft-tmux-send.sh ft-tmux-distill.sh"
n=0
for f in "$KIT"/*; do
  [ -f "$f" ] || continue
  cp -p "$f" "$DST/" || { echo "kit_bin_copy: 복사 실패 $f" >&2; exit 1; }
  n=$((n + 1))
done
stubbed=""
for s in $SIDE_EFFECT; do
  [ -e "$DST/$s" ] || continue
  cp "$STUB" "$DST/$s" && chmod +x "$DST/$s" || { echo "kit_bin_copy: 스텁 덮기 실패 $s" >&2; exit 1; }
  stubbed="${stubbed:+$stubbed,}$s"
done
echo "KIT-BIN-COPY files=$n stubbed=$stubbed"
