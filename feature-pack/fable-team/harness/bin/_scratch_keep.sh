#!/usr/bin/env bash
# _scratch_keep.sh — r1090 «더러운 사본 보관» 구현 한 곳 (ft-scratch-repo.sh 가 source 로만 쓴다 · 새 «도구» 아님 · 진입 명령 그대로)
#   부르는 쪽이 이미 정한 것: KEEPDIR(보관 폴더) · KEEP_MAX_MB · cap/bounded/remtmo/gq/isnum(ft-scratch-repo.sh 상단)
#     · 지우는 길 함수는 `$(…)` 대신 cap 을 쓴다(r897 r10.5) — 이 파일도 delete_copy 안에서만 불린다
#   keep_copy <사본 물리경로> <주인|-> <detached|branch> <판정 때 센 status 줄 수>
#     → 0 = 보관 확인 완료(그때만 지운다) · 3 = 거절(KEEP_WHY 에 사유 · 보관 폴더는 남긴다)
#   보관 파일 4개 = 일반 파일(하드 룰 19): meta.txt · status.txt · diff.patch · untracked.tar
#   meta.txt 4번째 칸 «가지» = 「detached」 또는 가지 이름 — DA② r1090: detached 사본을 «-» 로 적지 않는다
#   계약④ HEAD 대조 = 메모리에 든 값이 아니라 «저장한 meta.txt 를 다시 읽어» 지금 HEAD 와 맞춘다(DA② r1090)
# keeptmo <추적 안 한 파일 수> — «추적 안 한 파일 묶기(tar 1회)» 는 쪼갤 수 없는 한 배치다(한 파일로 떨어져야 보관이 성립 · 중간에 끊긴 tar 는 증거가 아니다)
#   ⇒ 하드 룰 12 의 «쪼갤 수 없는 배치» 예외로 상한 = min(5초 + 7초×ceil(파일 수/1000), 남은 회차 예산, 70초)
#   실측(2026-10-29 · 부하 60): 4864 파일 tar 1회 21초 — 상한 40초 안. 남은 예산이 모자라면 그 사본은 거절되고 다음 회차가 다시 잰다(삭제 0)
keeptmo() { # <파일 수> → tar 1회 상한(초) 1..70 · 마감 없으면 5초+7초×ceil(n/1000)
  local n="${1:-0}" t u now
  case "$n" in ''|*[!0-9]*) n=0;; esac
  t=$(( 5 + 7 * ( (n + 999) / 1000 ) ))
  [ "$t" -gt 70 ] && t=70
  if [ "$RBUD" != 0 ]; then
    cap now date +%s && isnum "$now" && { u=$(( RBUD - now )); [ "$u" -ge "$t" ] || t="$u"; }
  fi
  [ "$t" -gt 0 ] || t=1
  printf '%s\n' "$t"
}
keep_copy() { # <사본> <주인|-> <detached|branch> <판정 줄 수> → 0 보관 확인 완료 · 3 거절
  local P="$1" own="$2" how="$3" want="$4"
  local kd r head now brf stn nunt ntar ndif dsz sz lim f s mh why
  KEEP_WHY=""; KEEP_DIR_USED=""
  lim=$(( KEEP_MAX_MB * 1048576 ))
  kd="$KEEPDIR/${own}/${P##*/}"
  cap now date +%s && isnum "$now" || { KEEP_WHY="보관 실패 — 시계 못 읽음"; return 3; }
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  cap head bounded "$r" git -C "$P" rev-parse HEAD 2>/dev/null || { KEEP_WHY="보관 실패 — HEAD 못 읽음"; return 3; }
  brf="$how"
  if [ "$how" != detached ]; then   # 가지 사본 = 지금 가지 이름 · 못 읽으면 «branch-?»(«detached» 로 적지 않는다)
    brf="branch-?"
    cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
    cap f bounded "$r" git -C "$P" symbolic-ref --short HEAD 2>/dev/null && [ -n "$f" ] && brf="$f"
  fi
  [ -d "$kd" ] && [ -L "$kd" ] && { KEEP_WHY="보관 폴더가 심링크($kd)"; return 3; }
  mkdir -p -- "$kd" 2>/dev/null && [ -d "$kd" ] || { KEEP_WHY="보관 폴더 못 만듦 $kd"; return 3; }
  # ① status.txt — 보관 판정과 같은 눈금(추적 안 한 파일을 폴더로 접지 않는다: --untracked-files=all)
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  bounded "$r" git -C "$P" status --porcelain --untracked-files=all > "$kd/status.txt" 2>/dev/null \
    || { KEEP_WHY="보관 실패 — status 못 읽음"; return 3; }
  cap stn awk 'END{print NR+0}' "$kd/status.txt" 2>/dev/null || stn=x
  cap nunt awk '/^\?\? /{n++} END{print n+0}' "$kd/status.txt" 2>/dev/null || nunt=x
  # ② diff.patch — 추적 파일 변경(바이너리 포함)
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  bounded "$r" git -C "$P" diff HEAD --binary > "$kd/diff.patch" 2>/dev/null \
    || { KEEP_WHY="보관 실패 — diff 못 읽음"; return 3; }
  # ③ untracked.tar — 추적 안 한 파일 묶음(-z 이름 · 공백 안전) · 상한 = min(5초+7초×ceil(파일수/1000), 남은 예산, 70초)
  cap r keeptmo "$nunt"; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  bounded "$r" bash -c 'set -o pipefail; git -C "$1" ls-files --others --exclude-standard -z | tar -C "$1" -cf "$2" --null -T -' _ "$P" "$kd/untracked.tar" >/dev/null 2>&1 \
    || { KEEP_WHY="보관 실패 — 추적 안 한 파일 묶기 실패"; return 3; }
  # ④ meta.txt — 경로·주인·HEAD·가지|detached·status 줄 수·보관 시각
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$P" "$own" "$head" "$brf" "$stn" "$now" > "$kd/meta.txt" 2>/dev/null \
    || { KEEP_WHY="보관 실패 — meta 못 씀"; return 3; }
  # ⑤ 상한(사본 1개) — 넘으면 거절(삭제 0) · stat 도 남은 예산 상한(고정 7초 0)
  cap r remtmo; [ "$r" -gt 0 ] || { KEEP_WHY="보관 실패 — 예산 소진"; return 3; }
  sz=0
  for f in meta.txt status.txt diff.patch untracked.tar; do
    [ -f "$kd/$f" ] || continue
    cap s bounded "$r" stat -f %z "$kd/$f" 2>/dev/null || { KEEP_WHY="보관 실패 — 크기 못 읽음(예산·stat)"; return 3; }
    isnum "$s" || { KEEP_WHY="보관 실패 — 크기 숫자 아님"; return 3; }
    sz=$(( sz + s ))
  done
  [ "$sz" -le "$lim" ] || { KEEP_WHY="보관 상한 초과(${sz}B > ${lim}B · FT_SCRATCH_KEEP_MAX_MB=${KEEP_MAX_MB})"; return 3; }
  # ⑥ 저장한 것을 «다시 읽어» 확인 — 하나라도 아니면 거절(그 사본은 지우지 않는다)
  why=""
  [ "$stn" = "$want" ] || why="보관 확인 실패 — status 줄 수 ${stn} ≠ 판정 ${want}"
  [ -n "$why" ] || { cap r keeptmo "$nunt"; [ "$r" -gt 0 ] || why="보관 확인 실패 — 예산 소진"; }
  [ -n "$why" ] || { cap ntar bounded "$r" bash -c 'set -o pipefail; tar -tf "$1" 2>/dev/null | awk "END{print NR+0}"' _ "$kd/untracked.tar" || ntar=; [ "$ntar" = "$nunt" ] || why="보관 확인 실패 — tar 항목 ${ntar:-?} ≠ 추적 안 한 파일 ${nunt}"; }
  ndif=$(awk '!/^\?\? /{n++} END{print n+0}' "$kd/status.txt" 2>/dev/null) || ndif=x
  cap r remtmo; [ -n "$why" ] || [ "$r" -gt 0 ] || why="보관 확인 실패 — 예산 소진"
  dsz=0
  [ -n "$why" ] || { cap dsz bounded "$r" stat -f %z "$kd/diff.patch" 2>/dev/null || dsz=0; [ "$dsz" -gt 0 ] || [ "$ndif" = 0 ] || why="보관 확인 실패 — diff.patch 가 비었는데 바뀐 추적 파일 ${ndif}줄"; }
  # ④′ HEAD = «저장한 meta.txt 를 다시 읽어» 지금 HEAD 와 대조(메모리 $head 재사용 0 · DA② r1090)
  [ -n "$why" ] || { cap mh awk -F'\t' 'NR==1{print $3; exit}' "$kd/meta.txt" 2>/dev/null; case "$mh" in ''|*[!0-9a-f]*) why="보관 확인 실패 — meta HEAD 못 읽음";; esac; }
  [ -n "$why" ] || { cap r remtmo; [ "$r" -gt 0 ] || why="보관 확인 실패 — 예산 소진"; }
  [ -n "$why" ] || { cap s bounded "$r" git -C "$P" rev-parse HEAD 2>/dev/null || s=; [ "$s" = "$mh" ] || why="보관 확인 실패 — HEAD 가 바뀜(meta ${mh} ≠ 지금 ${s:-?})"; }
  [ -z "$why" ] || { KEEP_WHY="$why · 보관 폴더 $kd"; return 3; }
  KEEP_DIR_USED="$kd"
  return 0
}
