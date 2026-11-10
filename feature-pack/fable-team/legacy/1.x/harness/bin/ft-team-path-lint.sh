#!/usr/bin/env bash
# ft-team-path-lint.sh [<bin 폴더>]   (R382 · 착지 게이트 1줄)
#   ① 팀 경로 조립 하드코딩 0 — 폴더 안 *.sh·*.py 에 «design/ 바로 뒤에 셸 변수가 붙는 조립»이 있으면 ERR(팀 폴더는 ft_team_root 만 푼다 · ft-team-lib.sh 가 단일 출처).
#   ② 전환 끝나면 쌍둥이 후보 제거 요구 — TEAMS.md 폴더 칸에 옛 꼴1(design/<팀>/)이 0 인데 ft_index_twin 호출이 남은 도구가 있으면 ERR.
#      꼴1 이 남아 있으면 «전환 중» INFO 한 줄(통과).
#   env: FT_REPO_ROOT(기본 git 루트 · ②의 TEAMS.md 위치). 출력 끝줄 `OK …` 또는 `ERR …` · exit 0 = OK · 1 = ERR · 2 = usage
# --md <팀 폴더|파일.md> (r447): 카드·문서(*.md) 본문 전부(주석·코드 블록 포함)에서 옛 꼴 `design/<팀>/` 글자 —
#   명단 새 꼴(design/teams/<팀>/) 팀 = ERR `<파일>:<줄>: …` · 명단 옛 꼴(전환 중) 팀 = INFO(통과) · 꼴3 팀 = 대상 아님. 명단 = 대상이 든 리포의 design/TEAMS.md(FT_REPO_ROOT·FT_TEAMS_MD 가 이긴다)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft-team-lib.sh" ] || { echo "ERR ft-team-lib.sh 없음: $HERE"; exit 1; }
. "$HERE/ft-team-lib.sh"
md_lint() { local tgt="$1" d rows new old f out n=0 nf=0 tot=0 info=""
  d="$(cd -- "$([ -d "$tgt" ] && echo "$tgt" || dirname -- "$tgt")" && pwd -P)" || { echo "ERR 대상 폴더를 못 연다: $tgt"; return 1; }
  rows="$(FT_REPO_ROOT="${FT_REPO_ROOT:-$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)}" _ft_team_rows)" || { echo "ERR 팀 명단을 못 읽었다 — md 검사 불가: $tgt"; return 1; }
  new="$(printf '%s\n' "$rows" | awk -F'\t' '$2 ~ /^design\/teams\//{print $1}' | paste -sd'|' -)"
  old="$(printf '%s\n' "$rows" | awk -F'\t' '$2 ~ /^design\// && $2 !~ /^design\/teams\//{print $1}' | paste -sd'|' -)"
  while IFS= read -r f; do [ -n "$f" ] || continue; tot=$((tot+1))
    if [ -n "$new" ] && out="$(grep -nE "(^|[^A-Za-z0-9_])design/($new)/" -- "$f")"; then
      printf '%s\n' "$out" | cut -c1-160 | sed "s|^|ERR $f:|"; n=$((n+$(printf '%s\n' "$out" | grep -c .))); nf=$((nf+1)); fi
    [ -n "$old" ] && grep -qE "(^|[^A-Za-z0-9_])design/($old)/" -- "$f" && info="$info ${f#"$d"/}"
  done < <(if [ -d "$tgt" ]; then find "$tgt" -type f -name '*.md' | LC_ALL=C sort; else printf '%s\n' "$tgt"; fi)
  [ -z "$info" ] || echo "INFO 전환 중 팀(명단 옛 꼴: $old) 옛 꼴 글자 파일(통과):$info"
  [ "$n" = 0 ] || { echo "ERR 카드·문서 옛 경로 글자 ${n}줄(${nf}파일) — design/teams/<팀>/ 로 고친다(명단 새 꼴 팀: $new)"; return 1; }
  echo "OK md 옛 경로 글자 0 (검사 ${tot}파일)"; }
if [ "${1:-}" = --md ]; then [ $# = 2 ] && [ -e "$2" ] || { echo "usage: $0 --md <팀 폴더|파일.md>" >&2; exit 2; }; md_lint "$2"; exit $?; fi
DIR="${1:-$HERE}"; [ $# -le 1 ] && [ -d "$DIR" ] || { echo "usage: $0 [<bin 폴더>] | --md <팀 폴더|파일.md>" >&2; exit 2; }
PAT='design/\$'"\\{?[A-Za-z_]+\\}?/"
bad="$(cd "$DIR" && grep -nE "$PAT" -- *.sh *.py 2>/dev/null | cut -c1-160)"
[ -z "$bad" ] || { printf '%s\n' "$bad"; echo "ERR 팀 경로 조립 하드코딩 $(printf '%s\n' "$bad" | grep -c .)곳 — ft_team_root 로 바꾼다"; exit 1; }
teams="$(ft_team_names 2>/dev/null)" || teams=""
if [ -z "$teams" ]; then echo "OK 하드코딩 0 (②③ TEAMS.md 를 못 읽어 전환·리터럴 검사 생략)"; exit 0; fi
# ③ 리터럴 팀 이름 경로 0 (R382b) — `design/(teams/)?<팀>/` 글자 · 파이썬 쪼갠 꼴 `"design" / "<팀>"` · 팀 목록은 TEAMS.md 에서 동적 생성 · `#` 주석 줄은 제외.
#    범위 밖 대기 목록(PENDING) = 이 단위가 고치지 않은 «리터럴 남은» 파일 — 매 실행 INFO 로 이름을 찍고, 목록 밖 파일에 리터럴이 있으면 ERR · 목록 파일이 깨끗해지면 «목록에서 제거» INFO(목록이 줄기만 한다 · 팀 명단 의존이라 ERR 아님).
PENDING="${FT_TEAM_LITERAL_PENDING-}"   # R383: 대기 목록 비움(2차 19파일 변환 끝) — 시험·후속 단위가 env 로 다시 주입할 수 있다
alt="$(printf '%s\n' "$teams" | paste -sd'|' -)"
LIT="design/(teams/)?($alt)([^A-Za-z0-9_-]|\$)"   # 팀 이름 뒤가 슬래시·따옴표·줄 끝이면 리터럴(slash 없는 joined 꼴 포함 · 이름 뒤에 영숫자가 이어지는 접두는 제외)
Q="[\"']"
PYLIT="${Q}design${Q}[[:space:]]*/[[:space:]]*(${Q}teams${Q}[[:space:]]*/[[:space:]]*)?${Q}($alt)${Q}"
hits="$(cd "$DIR" && grep -nE -e "$LIT" -e "$PYLIT" -- *.sh *.py 2>/dev/null | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
badf=""; pendf=""
for f in $(printf '%s\n' "$hits" | cut -d: -f1 | sort -u); do
  case " $PENDING " in *" $f "*) pendf="$pendf $f";; *) badf="$badf $f";; esac
done
if [ -n "$badf" ]; then
  for f in $badf; do printf '%s\n' "$hits" | grep -E "^$f:" | cut -c1-160; done
  echo "ERR 리터럴 팀 이름 경로 $(echo $badf | wc -w | tr -d ' ')개 파일 — ft_team_root(셸)·ft_team_lib.team_in(파이썬)으로 바꾼다:$badf"; exit 1
fi
if [ -n "$pendf" ]; then echo "INFO 리터럴 대기(범위 밖 · 후속 카드) $(echo $pendf | wc -w | tr -d ' ')개:$pendf"; else echo "INFO 리터럴 대기 0"; fi
clean=""; for f in $PENDING; do [ -f "$DIR/$f" ] && case " $pendf " in *" $f "*) ;; *) clean="$clean $f";; esac; done
[ -z "$clean" ] || echo "INFO 대기 목록에서 제거할 파일(리터럴 0 — 이 팀 명단 기준):$clean"
old="$(ft_team_rels 2>/dev/null | grep -E '^design/' | grep -vc '^design/teams/')"
if [ "$old" -gt 0 ]; then echo "OK 하드코딩 0 · 전환 중(옛 꼴 팀 ${old}개 — 쌍둥이 후보 유지)"; exit 0; fi
twins="$(cd "$DIR" && grep -lE 'ft_index_twin' -- *.sh *.py 2>/dev/null | grep -vx 'ft-team-lib.sh' | grep -vx 'ft-team-path-lint.sh' | tr '\n' ' ')"
[ -z "$twins" ] || { echo "ERR 전환 끝났는데 쌍둥이 후보가 남았다 — 제거: $twins"; exit 1; }
echo "OK 하드코딩 0 · 전환 끝 · 쌍둥이 후보 0"
