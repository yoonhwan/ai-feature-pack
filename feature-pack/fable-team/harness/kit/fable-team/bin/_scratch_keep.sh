#!/usr/bin/env bash
# _scratch_keep.sh — r1090 «더러운 사본 보관» 구현 한 곳 (ft-scratch-repo.sh 가 source 로만 쓴다 · 새 «도구» 아님 · 진입 명령 그대로)
#   부르는 쪽이 이미 정한 것: KEEPDIR(보관 폴더) · KEEP_MAX_MB · cap/bounded/remtmo/gq/isnum(ft-scratch-repo.sh 상단)
#     · 지우는 길 함수는 `$(…)` 대신 cap 을 쓴다(r897 r10.5) — 이 파일도 delete_copy 안에서만 불린다
#   keep_copy <사본 물리경로> <주인|-> <branch|detached|-> <판정 때 센 status 줄 수>
#     → 0 = 보관 확인 완료(그때만 지운다) · 3 = 거절(KEEP_WHY 에 사유 · 보관 폴더는 남긴다)
#   보관 파일 4개 = 일반 파일(하드 룰 19): meta.txt · status.txt · diff.patch · untracked.tar
# keeptmo — «추적 안 한 파일 묶기(tar 1회)» 는 쪼갤 수 없는 한 배치다(한 파일로 떨어져야 보관이 성립 · 중간에 끊긴 tar 는 증거가 아니다)
#   ⇒ 하드 룰 12 의 «쪼갤 수 없는 배치» 예외로 상한 = min(남은 회차 예산, 70초) · 남은 예산이 모자라면 그 사본은 거절되고 다음 회차가 다시 잰다(삭제 0)
#   실측(2026-10-29 · 부하 60): 4864 파일 tar 1회 21초 — 7초 기본 상한으로는 통과할 수 없다.
keeptmo() { # → 보관 묶기 명령 상한(초) 1..70 · 마감 없으면 7
  local t=7 now
  if [ "$RBUD" != 0 ]; then cap now date +%s && isnum "$now" && t=$(( RBUD - now )); fi
  [ "$t" -gt 70 ] && t=70
  [ "$t" -gt 0 ] || t=1
  printf '%s\n' "$t"
}
keep_copy() { # <사본> <주인|-> <branch|detached|-> <판정 줄 수> → 0 보관 확인 완료 · 3 거절}
  local P="$1" own="$2" how="$3" want="$4"
  local kd r head now brf stn ntar nunt ndif dsz sz lim f s why
  KEEP_WHY=""; KEEP_DIR_USED=""
  lim=$(( KEEP_MAX_MB * 1048576 ))
  kd="$KEEPDIR/${own}/${P##*/}"
  cap now date +%s && isnum "$now" || { KEEP_WHY="보관 실패 — 시계 못 읽음"; return 3; }
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  cap head bounded "$r" git -C "$P" rev-parse HEAD 2>/dev/null || { KEEP_WHY="보관 실패 — HEAD 못 읽음"; return 3; }
  brf="$how"
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  cap f bounded "$r" git -C "$P" symbolic-ref --short HEAD 2>/dev/null && [ -n "$f" ] && brf="branch:$f"
  [ -d "$kd" ] && [ -L "$kd" ] && { KEEP_WHY="보관 폴더가 심링크($kd)"; return 3; }
  mkdir -p -- "$kd" 2>/dev/null && [ -d "$kd" ] || { KEEP_WHY="보관 폴더 못 만듦 $kd"; return 3; }
  # ① status.txt — 보관 판정과 같은 눈금(추적 안 한 파일을 폴더로 접지 않는다: --untracked-files=all)
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  bounded "$r" git -C "$P" status --porcelain --untracked-files=all > "$kd/status.txt" 2>/dev/null \
    || { KEEP_WHY="보관 실패 — status 못 읽음"; return 3; }
  # ② diff.patch — 추적 파일 변경(바이너리 포함)
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  bounded "$r" git -C "$P" diff HEAD --binary > "$kd/diff.patch" 2>/dev/null \
    || { KEEP_WHY="보관 실패 — diff 못 읽음"; return 3; }
  # ③ untracked.tar — 추적 안 한 파일 묶음(-z 이름 · 공백 안전)
  cap r keeptmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  bounded "$r" bash -c 'set -o pipefail; git -C "$1" ls-files --others --exclude-standard -z | tar -C "$1" -cf "$2" --null -T -' _ "$P" "$kd/untracked.tar" >/dev/null 2>&1 \
    || { KEEP_WHY="보관 실패 — 추적 안 한 파일 묶기 실패"; return 3; }
  stn=$(awk 'END{print NR+0}' "$kd/status.txt" 2>/dev/null) || stn=x
  # ④ meta.txt — 경로·주인·HEAD·가지|detached·status 줄 수·보관 시각
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$P" "$own" "$head" "$brf" "$stn" "$now" > "$kd/meta.txt" 2>/dev/null \
    || { KEEP_WHY="보관 실패 — meta 못 씀"; return 3; }
  # ⑤ 상한(사본 1개) — 넘으면 거절(삭제 0)
  sz=0
  for f in meta.txt status.txt diff.patch untracked.tar; do
    [ -f "$kd/$f" ] || continue
    cap s bounded 7 stat -f %z "$kd/$f" 2>/dev/null && isnum "$s" && sz=$(( sz + s ))
  done
  [ "$sz" -le "$lim" ] || { KEEP_WHY="보관 상한 초과(${sz}B > ${lim}B · FT_SCRATCH_KEEP_MAX_MB=${KEEP_MAX_MB})"; return 3; }
  # ⑥ 저장한 것을 «다시 읽어» 확인 — 하나라도 아니면 거절(그 사본은 지우지 않는다)
  why=""
  [ "$stn" = "$want" ] || why="보관 확인 실패 — status 줄 수 ${stn} ≠ 판정 ${want}"
  nunt=$(awk '/^\?\? /{n++} END{print n+0}' "$kd/status.txt" 2>/dev/null) || nunt=x
  [ -n "$why" ] || { ntar=$(tar -tf "$kd/untracked.tar" 2>/dev/null | awk 'END{print NR+0}') || ntar=x; [ "$ntar" = "$nunt" ] || why="보관 확인 실패 — tar 항목 ${ntar} ≠ 추적 안 한 파일 ${nunt}"; }
  ndif=$(awk '!/^\?\? /{n++} END{print n+0}' "$kd/status.txt" 2>/dev/null) || ndif=x
  dsz=0; cap dsz bounded 7 stat -f %z "$kd/diff.patch" 2>/dev/null || dsz=0
  [ -n "$why" ] || { [ "$dsz" -gt 0 ] || [ "$ndif" = 0 ] || why="보관 확인 실패 — diff.patch 가 비었는데 바뀐 추적 파일 ${ndif}줄"; }
  [ -n "$why" ] || { cap r remtmo; [ "$r" -gt 0 ] || why="보관 확인 실패 — 예산 소진"; }
  [ -n "$why" ] || { cap s bounded "$r" git -C "$P" rev-parse HEAD 2>/dev/null || s=; [ "$s" = "$head" ] || why="보관 확인 실패 — HEAD 가 바뀜"; }
  [ -z "$why" ] || { KEEP_WHY="$why · 보관 폴더 $kd"; return 3; }
  KEEP_DIR_USED="$kd"
  return 0
}
