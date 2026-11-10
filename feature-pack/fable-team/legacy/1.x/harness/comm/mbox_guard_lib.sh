#!/bin/bash
# mbox_guard.sh 가 source 하는 공용 함수(R372 · 단독 실행 0 · DIR 은 mbox.sh 가 정한다) — 판정기 폴더 해석 하나.
# 순서 = FT_BIN → $DIR/../LIVE_BIN 파일 1행(절대경로 · 실재 폴더 — 루트 shim `.fable-team/bin/ft-*.sh` 와 같은 규약) → $DIR/../bin.
# 먼저 «해당되는» 후보 하나만 쓴다 — LIVE_BIN 이 유효하면 ../bin(옛 사본 자리)은 보지 않는다. 상대경로·빈 줄·없는 폴더인 LIVE_BIN 은 무시한다.

# _ft_live_bin <판정기 파일명> — rc 0 = 판정기 전체 경로 출력 · rc 1 = 사유 한 줄 출력(`FT_BIN=<값|빈 값> · LIVE_BIN=<경로|없음> · 폴백=<경로>`).
_ft_live_bin() {
  local name="$1" fb="${FT_BIN:-}" fall="$DIR/../bin" lb="" dir
  [ ! -r "$DIR/../LIVE_BIN" ] || lb="$(head -1 "$DIR/../LIVE_BIN" 2>/dev/null | tr -d '\r')"
  case "$lb" in /*) [ -d "$lb" ] || lb="";; *) lb="";; esac
  if [ -n "$fb" ]; then dir="$fb"; elif [ -n "$lb" ]; then dir="$lb"; else dir="$fall"; fi
  [ -f "$dir/$name" ] && { printf '%s' "$dir/$name"; return 0; }
  printf 'FT_BIN=%s · LIVE_BIN=%s · 폴백=%s (%s 없음)' "${fb:-<빈 값>}" "${lb:-없음}" "$fall" "$name"; return 1
}
