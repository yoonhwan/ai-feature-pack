#!/usr/bin/env bash
# ft-live-entry.sh — source 전용 (R201 범위 추가 · 입구 도구 6개가 HERE 정의 직후 `. "$HERE/ft-live-entry.sh" "$@"`)
#   입구 도구(spawn·close·role-spawn·successor-open·resource-gate·resource-reclaim)가 추적 사본 위치(*/harness/bin · */harness/kit/fable-team/bin)
#   (뒤처진 워크트리의 사본 = R201 사고 꼴)에서 불리면, 옛 코드로 돌지 않고 <리포 루트>/.fable-team/LIVE_BIN 의 같은 이름 도구로 exec 한다.
#   인자·stdin·rc 는 exec 라 그대로. 대상 없음·LIVE_BIN 없음/빔 → `ERROR` + rc 3 (옛 사본 실행 0 · #0 RULE).
#   단 그 워크트리 HEAD 가 origin/main 을 «품으면»(merge-base --is-ancestor rc0 = 최신 이상 = 시험 중인 브랜치) 제자리 실행 · git 판단 실패 = ERROR rc3 (r2 · arch#71).
#   로컬 origin/main 기준 — fetch 안 함(DA r1 H2 한계 · 1차 그물 = 홈 훅 tracked-bin-call-gate).
#   LIVE_BIN 값이 `/` 로 시작하지 않으면(상대 경로) ERROR rc3 — 실행 0 (r3 · DA r1 H1).
#   FT_ALLOW_TRACKED_BIN=1 이면 넘기지 않는다(시험 하네스 전용 — tests/harness/* 는 원본을 직접 불러야 한다).
#   FT_LIVE_ENTRY_DONE=1 이면 이미 한 번 넘어온 것 — 되돌아 exec 하지 않는다(무한 루프 방지).
_le_self="${BASH_SOURCE[1]:-$0}"
_le_dir="$(cd -- "$(dirname -- "$_le_self")" && pwd)"
case "$_le_dir" in
  */.fable-team/bin|*/.fable-team/*/bin|*/fable-team/live/*/bin) : ;;            # 설치 꼴(r385 버전 폴더 포함) — 아무것도 안 한다
  */harness/bin|*/harness/kit/fable-team/bin)                                   # 추적 사본(R201 사고 꼴 · r385 팩 harness/)만 — 임시 복사본 등 그 밖의 위치는 각 도구의 옛 INFO 건너뜀 경로 그대로
    if [ "${FT_ALLOW_TRACKED_BIN:-0}" != 1 ] && [ "${FT_LIVE_ENTRY_DONE:-0}" != 1 ]; then
      _le_name="${_le_self##*/}"
      _le_gc="$(git -C "$_le_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
        || { echo "ERROR ft-live-entry: $_le_name 이 설치 폴더 밖($_le_dir)이고 git 안도 아니라 LIVE_BIN 을 못 푼다"; exit 3; }
      _le_root="${_le_gc%/.git}"
      # r2(arch#71): 그 워크트리 HEAD 가 origin/main 을 «품으면»(최신 이상 = 시험 중인 브랜치) 제자리 실행 · 품지 않으면(뒤처진 사본 = R201 사고 꼴) 아래로 LIVE_BIN exec · 판단 실패 = ERROR
      git -C "$_le_dir" merge-base --is-ancestor origin/main HEAD 2>/dev/null; _le_anc=$?
      case "$_le_anc" in
        0) unset _le_self _le_dir _le_name _le_gc _le_root _le_anc; return 0;;
        1) : ;;
        *) echo "ERROR ft-live-entry: $_le_name — origin/main 이 HEAD 의 조상인지 git 이 판단 못 함(rc=$_le_anc · dir=$_le_dir) — 옛 사본인지 모르는 채로 돌리지 않는다"; exit 3;;
      esac
      _le_file="$_le_root/.fable-team/LIVE_BIN"
      _le_live=""
      [ -f "$_le_file" ] && _le_live="$(sed -n '1p' "$_le_file" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -n "$_le_live" ] || { echo "ERROR ft-live-entry: LIVE_BIN 이 없거나 비었다: $_le_file — master 가 ft-root-bin-shim.sh 로 설치해야 한다 ($_le_name 은 옛 사본이라 돌리지 않는다)"; exit 3; }
      case "$_le_live" in /*) : ;; *) echo "ERROR ft-live-entry: LIVE_BIN 이 절대경로(/ 로 시작)가 아니다: $_le_live ($_le_file) — 상대 경로는 cwd 따라 다른 도구를 가리켜 돌리지 않는다"; exit 3;; esac
      _le_target="$_le_live/$_le_name"
      [ -f "$_le_target" ] || { echo "ERROR ft-live-entry: 라이브 도구 없음: $_le_target (LIVE_BIN=$_le_live)"; exit 3; }
      [ "$_le_target" -ef "$_le_self" ] && { echo "ERROR ft-live-entry: LIVE_BIN 이 이 도구 자신을 가리킨다: $_le_target"; exit 3; }
      echo "INFO ft-live-entry: 비설치 위치($_le_dir) → 라이브 $_le_target 로 넘김" >&2
      FT_LIVE_ENTRY_DONE=1 exec bash "$_le_target" "$@"
    fi
    ;;
  *) : ;;
esac
unset _le_self _le_dir _le_name _le_gc _le_root _le_file _le_live _le_target
