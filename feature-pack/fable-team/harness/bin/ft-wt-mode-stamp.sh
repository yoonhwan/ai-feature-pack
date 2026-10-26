#!/usr/bin/env bash
# ft-wt-mode-stamp.sh [--root <루트>] [--apply | --unmarked] — r835 설치 때 1회: 기존 팀 워크트리(<루트>/.worktrees/*)에 표식을 먼저 찍는다
#   왜: post-checkout(r835)은 «표식 없는» 팀 워크트리를 처음 보는 checkout 에 sparse 로 정한다 — 기존 풀 워크트리가
#       다음 checkout 에 갑자기 sparse 로 바뀌지 않게, 훅 설치 «전» 에 지금 상태를 표식으로 남긴다.
#   표식 = <워크트리 gitdir>/ft-wt-mode · 값 = 이미 sparse(core.sparseCheckout=true) → `sparse` · 아니면 `legacy-full`
#   기본 = --dry-run(목록만 · 쓰기 0) · --apply = 표식 파일 1개씩 쓰기(체크아웃 변경 0 · 되돌림 = 그 파일 삭제) · --apply 는 master 손
#   대상 밖: 표식 있는 것(그대로) · 디스크에 없는 워크트리 · .worktrees 밖 · design/teams/ 없는 리포(= SKIP · 팩 꼴)
#   출력: 줄마다 `DRY|STAMP <경로> <값>` · `HAS <경로> <값>` · 끝줄 `TOTAL worktrees=<n> new=<n> has=<n> err=<n> mode=dry|apply`
#   r843 r4: 표식 «있음» = -e 또는 -L(끊긴 심링크 포함) · 있으면 읽어 정상 값(sparse · legacy-full · full <사유 10자+>)일 때만 그대로
#     못 읽음·값 아님·심링크·폴더 = 경로마다 `ERROR 표식 자리 이상: <표식> — <이유> · <워크트리>` 줄 + 끝 rc 1 (--apply 는 이런 자리에 쓰기 0)
#   --apply 는 «없음(ENOENT)» 에만 쓴다 · 쓰기 뒤 다시 읽어 값 대조 — 다르면 `ERROR 표식 쓰기 실패: <표식>` · 끝 rc 1
#   --unmarked 도 읽기 실패(표식 자리·design/teams)를 묻지 않는다 — 경로마다 ERROR 줄 + 끝 rc 1
#   --unmarked = 탐지만(쓰기 0 · 지우기 0): 표식 없음 ∧ sparse 꺼짐 ∧ design/teams/ 아래 폴더 2개 이상(남의 팀 폴더 있음)
#     → 줄마다 `UNMARKED <경로> teams=<n> kib=<n>` · 끝줄 `TOTAL … unmarked=<n> mode=unmarked` — reset·read-tree 처럼 훅을 안 거치는 길(ft-disk-alarm 하루 1회)
set -uo pipefail
ROOT="" APPLY=0 err=0 UNM=0 unm=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 || { echo "REJECT --root 값 없음"; exit 1; };;
    --apply) APPLY=1; shift;;
    --dry-run) APPLY=0; shift;;
    --unmarked) UNM=1; shift;;
    *) echo "REJECT 모르는 인자: $1 — ft-wt-mode-stamp.sh [--root <루트>] [--apply | --unmarked]"; exit 1;;
  esac
done
[ "$APPLY$UNM" != 11 ] || { echo "REJECT --apply 와 --unmarked 는 같이 못 씀"; exit 1; }
if [ -z "$ROOT" ]; then
  GCD="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "REJECT git 리포 안에서 실행하거나 --root"; exit 1; }
  ROOT="$(cd "$GCD/.." && pwd -P)"
else
  ROOT="$(cd "$ROOT" 2>/dev/null && pwd -P)" || { echo "REJECT 루트 폴더 없음"; exit 1; }
fi
[ -d "$ROOT/design/teams" ] || { echo "SKIP $ROOT — design/teams/ 없음(팩 꼴 · post-checkout r835 대상 아님)"; exit 0; }
n=0 new=0 has=0
while IFS= read -r line; do
  case "$line" in "worktree "*) ;; *) continue;; esac
  w="${line#worktree }"
  case "$w" in "$ROOT"/.worktrees/*) ;; *) continue;; esac
  [ -d "$w" ] || continue
  n=$((n+1))
  gd="$(git -C "$w" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || { echo "WARN gitdir 못 읽음: $w"; continue; }
  mark="$gd/ft-wt-mode"
  cur=""; slot=absent; why=""
  if [ -L "$mark" ]; then slot=bad; why="심링크 표식 자리"
  elif [ -d "$mark" ]; then slot=bad; why="폴더(일반 파일 아님)"
  elif [ -e "$mark" ]; then
    if [ -f "$mark" ] && [ -r "$mark" ] && cur="$(head -n 1 "$mark" 2>/dev/null)"; then
      case "$cur" in
        sparse|legacy-full) slot=ok;;
        "full "*) if [ "$(python3 -c 'import sys; print(len(sys.argv[1].strip()))' "${cur#full }" 2>/dev/null || echo 0)" -ge 10 ]; then slot=ok; else slot=bad; why="full 사유 10자 미만"; fi;;
        *) slot=bad; why="정상 값 아님(sparse · legacy-full · full <사유 10자+> 아님)";;
      esac
    else slot=bad; why="못 읽음"; fi
  fi
  if [ "$slot" = bad ]; then err=$((err+1)); echo "ERROR 표식 자리 이상: $mark — $why · $w"; continue; fi
  if [ "$slot" = ok ]; then has=$((has+1)); [ "$UNM" = 1 ] || echo "HAS $w $cur"; continue; fi
  if [ "$(git -C "$w" config --bool core.sparseCheckout 2>/dev/null)" = true ]; then v=sparse; else v=legacy-full; fi
  if [ "$UNM" = 1 ]; then
    [ "$v" = legacy-full ] || continue
    if [ ! -r "$w/design/teams" ] || [ ! -x "$w/design/teams" ]; then
      err=$((err+1)); echo "ERROR 팀 폴더 못 읽음: $w/design/teams — 남의 팀 폴더 수를 못 셈"; continue
    fi
    tn="$(find "$w/design/teams" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    [ "$tn" -ge 2 ] || continue
    unm=$((unm+1)); echo "UNMARKED $w teams=$tn kib=$(du -sk "$w" 2>/dev/null | cut -f1)"; continue
  fi
  new=$((new+1))
  if [ "$APPLY" = 1 ]; then
    if echo "$v" > "$mark" && [ "$(cat "$mark" 2>/dev/null)" = "$v" ]; then echo "STAMP $w $v"
    else err=$((err+1)); echo "ERROR 표식 쓰기 실패: $mark — «${v}» 쓰고 다시 읽은 값이 다름 · $w"; fi
  else
    echo "DRY $w $v"
  fi
done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null)
if [ "$UNM" = 1 ]; then
  echo "TOTAL worktrees=$n has=$has unmarked=$unm mode=unmarked"
  if [ "$err" -ne 0 ]; then echo "ERROR 표식·읽기 실패 $err곳 — 위 ERROR 줄" >&2; exit 1; fi
  exit 0
fi
echo "TOTAL worktrees=$n new=$new has=$has err=$err mode=$([ "$APPLY" = 1 ] && echo apply || echo dry)"
[ "$err" = 0 ]
