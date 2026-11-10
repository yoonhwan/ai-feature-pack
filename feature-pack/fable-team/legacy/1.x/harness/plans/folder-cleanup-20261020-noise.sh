#!/bin/bash
# 흔적만 남은 옛 작업 폴더 정리 — 카드 r576-noise-only-worktrees-archive-then-clean · master 87 발주 #123052 · 작성 byz-harness-nano-r576-noise-only-worktrees-archive-then-c#0
# 대상 = .fable-team/state/folder-cleanup-20261020.noise-only.tsv (실행 시점에 다시 읽는다 · 없는 폴더 = SKIP)
# 되는 일 = 폴더마다 재확인 → 흔적을 tar 로 보관 → 흔적 되돌리기 → `git worktree remove`(강제 옵션 없음)
# 안 되는 일 = 가지 삭제 0 · 강제 삭제 0 · 재확인 하나라도 어긋나면 그 폴더는 SKIP(다음 폴더 계속)
# 되살림 = `git worktree add <경로> <가지>` 뒤 보관 tar 의 trace.patch 를 `git apply` (deleted.txt = 지웠던 파일 목록)
# 사용: folder-cleanup-20261020-noise.sh [--dry-run] [--root <BYZ 루트>] [--list <tsv>] [--archive-dir <경로>] [--log <파일>]
set -u
ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
LIST="$ROOT/.fable-team/state/folder-cleanup-20261020.noise-only.tsv"
ARCHIVE="$ROOT/.fable-team/state/folder-cleanup-20261020-noise"
LOG=""
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift;;
    --root) ROOT="${2:-}"; shift 2;;
    --list) LIST="${2:-}"; shift 2;;
    --archive-dir) ARCHIVE="${2:-}"; shift 2;;
    --log) LOG="${2:-}"; shift 2;;
    *) echo "REJECT 알 수 없는 인자: $1"; exit 2;;
  esac
done
[ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ] || { echo "REJECT 리포 아님: $ROOT"; exit 1; }
[ -f "$LIST" ] || { echo "REJECT 목록 없음: $LIST"; exit 1; }
[ -n "$LOG" ] || LOG="$(mktemp -t folder-cleanup-noise.XXXXXX)"
: > "$LOG"
mkdir -p "$ARCHIVE" || { echo "REJECT 보관 폴더 만들기 실패: $ARCHIVE"; exit 1; }
git -C "$ROOT" fetch -q origin || { echo "REJECT fetch 실패"; exit 1; }
REMOTE="$(git -C "$ROOT" ls-remote origin 2>/dev/null | cut -f1)"
[ -n "$REMOTE" ] || { echo "REJECT ls-remote 실패"; exit 1; }
CWDS="$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
SEAT_CWDS="$(tmux list-panes -a -F '#{pane_current_path}' 2>/dev/null)"

say() { echo "$*" >> "$LOG"; }
only_trace() {   # stdin = `git status --porcelain` 줄 · 전부 « M .serena/project.yml» 또는 « D <경로>» 면 0
  local line n=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n+1))
    case "$line" in
      " M .serena/project.yml"|" D "*) : ;;
      *) return 1;;
    esac
  done
  return 0
}
skip() { say "SKIP $2 $1"; echo "SKIP [$2] $1"; skipn=$((skipn+1)); }

# 크기 큰 폴더부터 (한 번만 잰다 · 큰 공간 먼저 회수)
SIZED="$ARCHIVE/.sized.tsv"
: > "$SIZED"
while IFS= read -r wt; do
  [ -n "$wt" ] || continue
  [ -d "$wt" ] || { printf '0\t%s\n' "$wt" >> "$SIZED"; continue; }
  printf '%s\t%s\n' "$(du -sk "$wt" 2>/dev/null | awk '{print $1+0}')" "$wt" >> "$SIZED"
done < "$LIST"
SORTED="$(sort -rn "$SIZED" | cut -f2)"

removed=0; skipn=0; failn=0; tarn=0
echo "== $( [ "$DRY" = 1 ] && echo 'DRY-RUN' || echo 'RUN' ) root=$ROOT list=$LIST archive=$ARCHIVE"
for wt in $SORTED; do
  name="$(basename "$wt")"
  # ① 재확인 ⓐ 폴더 실재
  [ -d "$wt" ] || { skip "$wt" "폴더 없음"; continue; }
  # ⓑ 흔적만 ( M .serena/project.yml · D 경로) ⓒ 추적 안 된 파일 0
  STATUS="$(git -C "$wt" status --porcelain 2>/dev/null)"
  if printf '%s\n' "$STATUS" | grep -q '^?? '; then skip "$wt" "추적 안 된 파일"; continue; fi
  if ! printf '%s\n' "$STATUS" | only_trace; then skip "$wt" "흔적 아닌 변경"; continue; fi
  # ⓓ HEAD 가 원격 보관 안 (origin/* 또는 refs/backup/*)
  sha="$(git -C "$wt" rev-parse HEAD 2>/dev/null)" || { skip "$wt" "HEAD 없음"; continue; }
  if ! printf '%s\n' "$REMOTE" | grep -q -x "$sha"; then
    outside="$(git -C "$ROOT" rev-list --count "$sha" --not --remotes 2>/dev/null)"
    refs_bk="$(git -C "$ROOT" rev-list --count "$sha" --not --glob='refs/backup/*' 2>/dev/null)"
    if [ "$outside" != 0 ] && [ "$refs_bk" != 0 ]; then skip "$wt" "원격 보관 없음"; continue; fi
  fi
  # ⓔ 어떤 프로세스 cwd 도 아님 ⓕ 그 폴더를 cwd 로 둔 tmux 좌석 0
  real="$(cd "$wt" 2>/dev/null && pwd -P)"
  if printf '%s\n' "$CWDS" | grep -q -x -F -e "$wt" -e "$real"; then skip "$wt" "cwd 사용 중"; continue; fi
  if printf '%s\n' "$SEAT_CWDS" | grep -q -x -F -e "$wt" -e "$real"; then skip "$wt" "좌석 cwd"; continue; fi
  br="$(git -C "$wt" branch --show-current 2>/dev/null)"
  if [ "$DRY" = 1 ]; then say "WOULD-REMOVE $wt $br $sha"; echo "WOULD-REMOVE $wt"; removed=$((removed+1)); continue; fi
  # ② 보관 — 흔적 패치 + 삭제 목록 + 폴더 정보 + HEAD 1줄
  tarf="$ARCHIVE/$name.tar.gz"
  STAGE="$(mktemp -d)" || { skip "$wt" "보관 준비 실패"; continue; }
  { git -C "$wt" diff > "$STAGE/trace.patch"
    git -C "$wt" ls-files -d > "$STAGE/deleted.txt"
    [ -f "$wt/.worktree-info.json" ] && cp "$wt/.worktree-info.json" "$STAGE/" 
    printf 'HEAD %s\nBRANCH %s\nPATH %s\n' "$sha" "$br" "$wt" > "$STAGE/meta.txt"
  } >/dev/null 2>&1
  if ! tar -czf "$tarf" -C "$STAGE" . >/dev/null 2>&1; then
    rm -rf "$STAGE"; say "SKIP $wt 보관 실패"; echo "SKIP [보관 실패] $wt"; skipn=$((skipn+1)); continue
  fi
  rm -rf "$STAGE"
  tarn=$((tarn+1))
  # ③ 되돌리기 — 흔적을 원래대로 (그 뒤 깨끗하지 않으면 SKIP, 손 0)
  git -C "$wt" checkout -- .serena/project.yml >/dev/null 2>&1
  git -C "$wt" checkout -- . >/dev/null 2>&1
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then say "SKIP $wt 되돌리기 실패"; echo "SKIP [되돌리기 실패] $wt"; skipn=$((skipn+1)); continue; fi
  # ④ 지우기 — 강제 옵션 없음 (git 이 스스로 거절하면 FAIL 기록 후 계속)
  if git -C "$ROOT" worktree remove "$wt" >> "$LOG" 2>&1; then
    say "REMOVED $wt $br $sha tar=$tarf"; echo "REMOVED $wt"; removed=$((removed+1))
  else
    say "FAIL $wt"; echo "FAIL $wt"; failn=$((failn+1))
  fi
done
rm -f "$SIZED"
echo "RESULT removed=$removed skip=$skipn fail=$failn tar=$tarn log=$LOG"
df -h / | tail -1
[ "$failn" = 0 ] || exit 1
exit 0
