#!/usr/bin/env bash
# h-mini-ft-install.sh — fable-team 하네스(스킬·스크립트·에이전트 정의)를 mini 에 «추가만» 설치한다. 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   2026-10-25 · aifp-multihost-master-claude#4 · 오빠 «설치안된 패블팀부터 설치» (mini 에 ccu 팀을 세우기 위한 1단계)
#   하는 일: ① 이 맥 ~/.claude/skills/fable-team → mini ~/.claude/skills/fable-team (없을 때만 · .omc/__pycache__/*.bak* 제외)
#            ② 이 맥 ~/.claude/agents/ft-*.md → mini ~/.claude/agents/ (없는 파일만 · *.bak* 제외)
#            ③ mini 에서 ft-mbox 스모크(임시 폴더에서 send→recv · 제품 쪽지함 0 쓰기)
#   하지 않는 일: settings.json·훅·CLAUDE.md 변경 0 · 기존 파일 덮어쓰기 0 · 삭제 0 · 서버·Redis 접촉 0.
# 사용: bash /tmp/h<N>        → 설치
#       DRY=1 bash /tmp/h<N>  → 무엇을 복사할지·충돌 여부만 보고(쓰기 0)
# rc: 0 성공 · 2 전제 실패 · 3 이미 설치돼 있음(덮어쓰기 거부) · 4 복사 실패 · 5 스모크 실패
set -uo pipefail
MINI="${MINI:-mini}"; DRY="${DRY:-0}"
SRC_SKILL="$HOME/.claude/skills/fable-team"; SRC_AGENTS="$HOME/.claude/agents"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-ftinst] %s\n' "$*"; }
die() { printf '[h-ftinst] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }

[ -d "$SRC_SKILL/scripts" ] && [ -f "$SRC_SKILL/SKILL.md" ] || die 2 "원본 스킬이 없다: $SRC_SKILL"
AGENTS=(); for f in "$SRC_AGENTS"/ft-*.md; do [ -f "$f" ] && case "$f" in *.bak*) ;; *) AGENTS+=("$f");; esac; done
[ "${#AGENTS[@]}" -gt 0 ] || die 2 "원본 에이전트 정의(ft-*.md)가 없다: $SRC_AGENTS"
EXC=(--exclude '.omc' --exclude '__pycache__' --exclude '*.bak*' --exclude '.DS_Store')

STATE="$(ms 20 'echo skill=$( [ -e $HOME/.claude/skills/fable-team ] && echo EXISTS || echo absent ); n=0; for f in '"$(printf '%s ' "${AGENTS[@]##*/}")"'; do [ -e $HOME/.claude/agents/$f ] && n=$((n+1)); done; echo agents_existing=$n; echo py=$(command -v python3 >/dev/null && echo ok || echo MISSING); echo user=$(whoami)' 2>&1)" || die 2 "mini 접속 실패: ${STATE}"
printf '%s\n' "$STATE" | sed 's/^/        /'
SIZE="$(rsync -an "${EXC[@]}" --stats "$SRC_SKILL/" "$MINI:/tmp/.ft-dry-nonexistent/" 2>/dev/null | sed -n 's/^Total file size: //p' | head -1)"
say "복사 대상: 스킬 $(cd "$SRC_SKILL" && find . -type f ! -path './.omc/*' ! -name '*.bak*' ! -path '*/__pycache__/*' | wc -l | tr -d ' ')파일(${SIZE:-?}) · 에이전트 ${#AGENTS[@]}개(${AGENTS[*]##*/})"
case "$STATE" in *"skill=EXISTS"*) die 3 "mini 에 ~/.claude/skills/fable-team 이 이미 있다 — 덮어쓰지 않는다(필요하면 차이 확인 후 별도 계획)";; esac
case "$STATE" in *"py=MISSING"*) die 2 "mini 에 python3 없음";; esac

if [ "$DRY" = "1" ]; then
  say "DRY — 쓰기 0. 위 조건이면 설치 가능: ① 스킬 복사 ② 에이전트 ${#AGENTS[@]}개 복사(없는 파일만) ③ 스모크"
  exit 0
fi

say "1/3 스킬 복사"
ms 10 'mkdir -p $HOME/.claude/skills $HOME/.claude/agents' || die 4 "mini 폴더 생성 실패"
timeout 60 rsync -a -e "ssh ${SO[*]}" "${EXC[@]}" "$SRC_SKILL/" "$MINI:.claude/skills/fable-team/" || die 4 "스킬 복사 실패"
say "2/3 에이전트 정의 복사(없는 파일만)"
timeout 30 rsync -a --ignore-existing -e "ssh ${SO[*]}" "${AGENTS[@]}" "$MINI:.claude/agents/" || die 4 "에이전트 복사 실패"
say "3/3 스모크 — 임시 쪽지함에서 send→recv"
OUT="$(ms 30 'D=$(mktemp -d); export FT_MBOX_DIR=$D; M=$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh; bash $M send t-b t-a "[t-a->t-b] smoke" >/dev/null 2>&1; bash $M recv t-b 2>&1 | grep -c smoke; ls $HOME/.claude/skills/fable-team/scripts/ft-nano-spawn.sh $HOME/.claude/agents/ft-architect.md 2>&1 | wc -l; rm -rf "$D"' 2>&1)" || die 5 "스모크 실행 실패: ${OUT}"
printf '%s\n' "$OUT" | sed 's/^/        /'
echo "$OUT" | head -1 | grep -qx 1 || die 5 "쪽지 send→recv 가 mini 에서 안 돈다(위 출력 확인)"
say "완료 rc=0 — mini 에 fable-team 스킬·에이전트 정의 설치(추가만). 다음: git 클론 + ccu 팀 쪽지함·좌석(별도 계획)"
exit 0
