#!/usr/bin/env bash
# ft-cards-wt-sync.sh <루트> <상태 폴더> — r2117: 명부 _cards_wt worktree(카드 원천)를 origin/<가지> 로 따라간다. ft-tick.sh step cards_wt_sync 가 부른다.
#   A1 리포당 fetch 1회(7초 + 재시도 1) · tracked 수정 0 · 앞 0 · 뒤 >0 이면 merge --ff-only --no-overwrite-ignore 1회(7초) · 성공 = 줄 0.
#   A2 못 따라가면 «판정 불가 카드 원천 <팀> <worktree> 뒤 N · 앞 M · 수정 K · <사유> — 정렬 h» 1줄 — (팀 · worktree)마다 사유가 바뀔 때만
#      (기억 = <상태 폴더>/cards-wt-sync/<팀>@<worktree> · 재기동해도 남음) · 따라가면(뒤 0) 기억을 지운다.
#   A3 worktree 에 reset · checkout · stash · clean · 지우기 0. fetch · git 실패 = «판정 불가» 줄 + rc 1(한 함수 = note 가 끝냄).
# 명부 = <루트>/.fable-team/seats.json(팀 v65) · seats-<팀>.json · worktree = <루트>/.worktrees/<_cards_wt>.
set -uo pipefail
ROOT="${1:?usage: ft-cards-wt-sync.sh <루트> <상태 폴더>}"; MEM="${2:?usage: ft-cards-wt-sync.sh <루트> <상태 폴더>}/cards-wt-sync"
SEC="${FT_CARDS_WT_GIT_SEC:-7}"
RC=0; FETCHED=""   # FETCHED = «<git 공용 폴더>=<rc>» 줄 모음(리포당 fetch 1회 · bash 3.2 = 연관 배열 0)
# g <worktree> <git 인자…> — 7초 상한(perl alarm · 그룹째 TERM · 초과 rc 124) · 물려받은 GIT_* 지움 · autostash 0
g() {
  local d="$1"; shift
  perl -e 'setpgrp(0,0); $SIG{ALRM}=sub{ local $SIG{TERM}="IGNORE"; kill "TERM", -$$; exit 124 }; alarm shift; my $r=system(@ARGV); exit(($r>>8) || (($r&127) ? 128+($r&127) : 0));' \
    "$SEC" env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR LC_ALL=C git -c merge.autoStash=false -C "$d" "$@"
}
# note <팀> <worktree 이름> <뒤> <앞> <수정> <사유> — 사유가 기억과 다를 때만 1줄 + 기억 갱신
note() {
  local f="$MEM/$1@${2//\//%}" old=""
  [ -f "$f" ] && old="$(cat "$f" 2>/dev/null)"
  [ "$old" = "$6" ] && return 0
  echo "판정 불가 카드 원천 $1 .worktrees/$2 뒤 $3 · 앞 $4 · 수정 $5 · $6 — 정렬 h"
  if mkdir -p "$MEM" 2>/dev/null && printf '%s' "$6" > "$f.tmp.$$" 2>/dev/null && mv -f "$f.tmp.$$" "$f" 2>/dev/null; then :
  else rm -f "$f.tmp.$$" 2>/dev/null; echo "판정 불가 카드 원천 $1 .worktrees/$2 기억 쓰기 실패 $f — 다음 바퀴에 같은 줄이 다시 나온다"; RC=1; fi
}
forget() { rm -f "$MEM/$1@${2//\//%}" 2>/dev/null; }
# fetch_once <worktree> — 리포당 1번(7초 + 재시도 1) · rc 를 기억해 같은 리포의 다음 worktree 는 다시 부르지 않는다
fetch_once() {
  local key line rc
  key="$(g "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  line="$(printf '%s\n' "$FETCHED" | grep -F -x -m1 -e "$key=0" -e "$key=1")" && { [ "${line##*=}" = 0 ]; return; }
  g "$1" fetch -q origin >/dev/null 2>&1 || g "$1" fetch -q origin >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && FETCHED="$FETCHED$key=0"$'\n' || FETCHED="$FETCHED$key=1"$'\n'
  return "$rc"
}
# sync_one <팀> <_cards_wt> — A1 · A2 · A3
sync_one() {
  local team="$1" name="$2" wt="$ROOT/.worktrees/$2" br n m k counts rc
  [ -d "$wt" ] && [ -e "$wt/.git" ] || { note "$team" "$name" "?" "?" "?" "worktree 없음"; return; }
  br="$(g "$wt" symbolic-ref -q --short HEAD 2>/dev/null)" || { note "$team" "$name" "?" "?" "?" "가지 없음(HEAD 분리 또는 git 실패)"; return; }
  fetch_once "$wt" || { note "$team" "$name" "?" "?" "?" "fetch 실패 origin"; RC=1; return; }
  g "$wt" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null 2>&1 || { note "$team" "$name" "?" "?" "?" "원격 가지 없음 origin/$br"; return; }
  counts="$(g "$wt" rev-list --left-right --count "HEAD...refs/remotes/origin/$br" 2>/dev/null)" || { note "$team" "$name" "?" "?" "?" "git 실패 rev-list"; RC=1; return; }
  m="${counts%%[[:space:]]*}"; n="${counts##*[[:space:]]}"
  k="$(g "$wt" status --porcelain --untracked-files=no 2>/dev/null)" || { note "$team" "$name" "$n" "$m" "?" "git 실패 status"; RC=1; return; }
  k="$(printf '%s' "$k" | grep -c .)"
  [ "$n" -gt 0 ] || { forget "$team" "$name"; return; }
  if [ "$k" = 0 ] && [ "$m" = 0 ]; then
    g "$wt" merge -q --ff-only --no-overwrite-ignore --no-autostash "refs/remotes/origin/$br" >/dev/null 2>&1; rc=$?
    [ "$rc" = 0 ] && { forget "$team" "$name"; return; }
    note "$team" "$name" "$n" "$m" "$k" "ff 실패"; return
  fi
  local why=""
  [ "$m" = 0 ] || why="앞 커밋 있음"
  [ "$k" = 0 ] || why="${why:+$why · }tracked 수정 있음"
  note "$team" "$name" "$n" "$m" "$k" "$why"
}

list="$(python3 - "$ROOT/.fable-team" <<'PY'
import json, sys
from pathlib import Path
d = Path(sys.argv[1])
for p in sorted([d / "seats.json", *d.glob("seats-*.json")]):
    if not p.is_file():
        continue
    team = "v65" if p.stem == "seats" else p.stem.removeprefix("seats-")
    try:
        doc = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        print(f"{team}\t!")
        continue
    wt = doc.get("_cards_wt") if isinstance(doc, dict) else None
    if isinstance(wt, str) and wt.strip() and "\t" not in wt and "\n" not in wt:
        print(f"{team}\t{wt.strip()}")
PY
)" || { echo "판정 불가 카드 원천 명부 읽기 실패 $ROOT/.fable-team"; exit 1; }
while IFS=$'\t' read -r team name; do
  [ -n "$team" ] || continue
  if [ "$name" = "!" ]; then note "$team" "-" "?" "?" "?" "명부 JSON 실패"; continue; fi
  sync_one "$team" "$name"
done <<< "$list"
exit "$RC"
