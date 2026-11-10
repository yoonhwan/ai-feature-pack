#!/usr/bin/env bash
# ft-nano-superseded-check.sh <카드> --superseded-by <대체 카드 경로> --base <디렉터리> [--base <디렉터리> ...] [--team-root <루트>]
#   --team-root (R177): 대체 카드가 «다른 팀» 것이면 그 팀(design/<팀>/)의 원장 워크트리를 <루트>/.fable-team/bin-<팀>/<팀>-env.sh 의 `export FT_NANO_LEDGER_WT=` 줄에서 글자로 읽어(source·eval 0) 검사 base 에만 하나 더한다. 못 찾으면 추가 0 = 기존 REJECT 그대로.
#   ft-nano-close.sh --superseded-by 의 ⑥ 대체 검사 (R171): 다른 카드로 «대체된» 나노는 세트를 랜딩하지 않아 rc=0 증거 줄이 없다 — 그 줄 대신 아래 셋을 요구한다.
#     ⓐ 카드 «## 상태» 의 맨 끝 줄 = `대체됨: <대체 카드 경로> · 사유: <비지 않은 글>` (경로는 --superseded-by 값과 같아야 한다)
#     ⓑ 대체 카드 경로가 design/<팀>/indices/{대기,진행,완성,완료}/*.md 또는 design/teams/<팀>/indices/{대기,진행,완성,완료}/*.md 꼴(R679: 팀 폴더 트리 · «완성» 폴더 · «완료» 는 옛 이름 호환)이고 --base 디렉터리 중 하나 아래 파일로 실재한다
#     ⓒ 대체 카드가 이 카드 자신이 아니다
#   값 추론 금지 — 하나라도 아니면 REJECT(사유 stdout). exit 0 = 통과 · 1 = REJECT · 2 = usage
set -uo pipefail
USAGE="usage: $0 <카드> --superseded-by <대체 카드 경로> --base <디렉터리> [--base <디렉터리> ...] [--team-root <루트>]"
CARD="${1:-}"; shift 2>/dev/null || { echo "$USAGE" >&2; exit 2; }
SUP=""; BASES=(); TEAM_ROOT=""
while [ $# -gt 0 ]; do case "$1" in
  --superseded-by) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; SUP="$2"; shift 2;;
  --team-root) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; TEAM_ROOT="$2"; shift 2;;
  --base) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; BASES+=("$2"); shift 2;;
  *) echo "$USAGE" >&2; exit 2;; esac; done
[ -n "$CARD" ] && [ -n "$SUP" ] && [ "${#BASES[@]}" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }
[ -f "$CARD" ] || { echo "REJECT 대체됨 — 카드 없음: $CARD"; exit 1; }
FORMAT='카드 «## 상태» 맨 끝 줄: 대체됨: <대체 카드 경로> · 사유: <글>'

# ⓐ 상태 절 맨 끝 줄 (## 상태 헤딩 뒤 ~ 다음 ## 헤딩 전의 마지막 비지 않은 줄)
last="$(awk '/^## 상태[[:space:]]*$/{inb=1; last=""; next} /^## /{inb=0} inb && NF{last=$0} END{print last}' "$CARD")"
[ -n "$last" ] || { echo "REJECT 대체됨 — 카드 «## 상태» 에 줄이 없다. 형식: $FORMAT ($CARD)"; exit 1; }
re='^대체됨:[[:space:]]*([^[:space:]]+)[[:space:]]+·[[:space:]]+사유:(.*)$'
[[ "$last" =~ $re ]] || { echo "REJECT 대체됨 — 상태 절 맨 끝 줄이 «대체됨:» 줄이 아니다. 형식: $FORMAT · 받은 줄: ${last:0:160}"; exit 1; }
line_path="${BASH_REMATCH[1]}"; reason="${BASH_REMATCH[2]}"
[[ "$reason" =~ [^[:space:]] ]] || { echo "REJECT 대체됨 — 사유가 비어 있다(사유 없는 대체 거부). 형식: $FORMAT"; exit 1; }
[ "$line_path" = "$SUP" ] || { echo "REJECT 대체됨 — 줄의 경로($line_path)가 --superseded-by($SUP)와 다르다"; exit 1; }

# ⓑ 경로 꼴 + 실재
case "$SUP" in *..*) echo "REJECT 대체됨 — 대체 카드 경로에 «..» 불가: $SUP"; exit 1;; esac
CARD_FORM='^design/(teams/)?[^/]+/indices/(대기|진행|완성|완료)/[^/]+\.md$'   # R679: 팀 폴더 꼴(design/teams/<팀>/) · 실제 폴더 «완성» · «완료» 는 옛 이름 호환
[[ "$SUP" =~ $CARD_FORM ]] \
  || { echo "REJECT 대체됨 — 대체 카드는 design/<팀>/indices/{대기,진행,완성,완료}/*.md 또는 design/teams/<팀>/indices/{대기,진행,완성,완료}/*.md 여야 한다: $SUP"; exit 1; }
if [ -n "$TEAM_ROOT" ]; then  # R177: 대체 카드 팀의 원장 워크트리를 base 끝에 1개 더한다(없는 팀·env 없음·값 이상 = 추가 0)
  team="${SUP#design/}"; team="${team%%/*}"; tw=""; tenv="$TEAM_ROOT/.fable-team/bin-$team/$team-env.sh"
  if [ "$team" = v65 ]; then tw="$TEAM_ROOT/.worktrees/v6-realtime-live"
  elif [[ "$team" =~ ^[A-Za-z0-9_-]+$ ]] && [ -f "$tenv" ]; then
    tw="$(sed -n '/^export FT_NANO_LEDGER_WT=/{s///p;q;}' "$tenv")"
    case "$tw" in  # 값 전체 판정: 따옴표는 «쌍»일 때만 벗기고, $_GR_ROOT 는 맨 앞 + 바로 뒤가 / 또는 끝일 때만 루트로 치환, 그 뒤 $·백틱·따옴표가 남으면 추가 0
      \"*\") tw="${tw#\"}"; tw="${tw%\"}";;
      \'*\') tw="${tw#\'}"; tw="${tw%\'}";; esac
    case "$tw" in
      '${_GR_ROOT}'|'${_GR_ROOT}/'*) tw=$TEAM_ROOT${tw#'${_GR_ROOT}'};;
      '$_GR_ROOT'|'$_GR_ROOT/'*) tw=$TEAM_ROOT${tw#'$_GR_ROOT'};; esac
    case "$tw" in *'$'*|*'`'*|*'"'*|*"'"*) tw="";; esac
  fi
  [ -n "$tw" ] && [ -d "$tw" ] && BASES+=("$tw")
fi
found=""; outside=""
canon() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null; }
for b in "${BASES[@]}"; do
  [ -f "$b/$SUP" ] || continue
  # 심링크(파일·상위 폴더 전부)를 해석한 실제 위치가 그 base 아래이고, base 기준 상대경로가 같은 꼴이어야 한다 — 이름만 허용 꼴인 심링크로 base 밖을 가리키는 우회 차단(DA⑥ r171 H1). 해석 실패 = REJECT(통과 간주 0).
  cf="$(canon "$b/$SUP")"; cb="$(canon "$b")"
  [ -n "$cf" ] && [ -n "$cb" ] || { echo "REJECT 대체됨 — 대체 카드 실제 위치 해석 실패: $SUP (base $b)"; exit 1; }
  rel="${cf#"$cb"/}"
  if [ "$rel" != "$cf" ] && [[ "$rel" =~ $CARD_FORM ]]; then found="$b/$SUP"; break; fi
  outside="$cf"
done
[ -n "$found" ] || { [ -z "$outside" ] || { echo "REJECT 대체됨 — 대체 카드 실제 위치가 허용 범위 밖: $SUP → $outside"; exit 1; }; echo "REJECT 대체됨 — 대체 카드 파일이 없다: $SUP (찾은 곳: ${BASES[*]})"; exit 1; }

# ⓒ 자기 자신 아님 (같은 파일: 경로 문자열이 달라도 -ef 로 본다)
[ ! "$found" -ef "$CARD" ] || { echo "REJECT 대체됨 — 대체 카드가 이 카드 자신이다: $SUP"; exit 1; }

echo "OK 대체됨 — 대체 카드 $SUP · 사유: ${reason# }"
exit 0
