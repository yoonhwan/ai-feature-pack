#!/usr/bin/env bash
# ft-sets.sh [--check | --body <세트>] [팀]
#   세트 발주 원장(SETS.md) 조회·검사 — 읽기 전용 · 원격 0 (판정 359 · 설계 design/harness/DESIGN-set-dispatch-20261008.md §5)
#   (없음)  표 출력(상태 순 진행→발주→보류→닫힘→폐기) + 끝줄 「세트 진행 a · 발주 b · 보류 c · 닫힘 d」(폐기가 있을 때만 · 폐기 e 덧붙임)
#           팀을 주면 그 팀 SET-REQUESTS.md 의 요청 줄을 원장과 대조해 PENDING/REACK/MISMATCH/MISSING/STALE 로 보인다
#   --check 형식 검사(이름·상태·발주 칸 git cat-file·보호 ref·닫힘 close N/N·Issue 겹침 경고) · --body <세트> 발주 칸 sha:경로 의 본문
# 원장 = FT_SETS_FILE 하나(없으면 rc 3 — 다른 경로로 넘어가지 않는다) · 팀 요청 파일 루트 FT_SETS_TEAM_ROOT(기본 현재 디렉터리)
# git 객체 저장소 FT_SETS_REPO(기본 원장이 든 리포)   rc 0 통과 · 1 검사 실패/미전달 · 2 usage · 3 원장 없음
set -uo pipefail
usage() { echo "usage: $0 [--check | --body <세트>] [팀]" >&2; exit 2; }
MODE=list; TEAM=""; BODYSET=""
while [ $# -gt 0 ]; do case "$1" in
  --check) MODE=check;;
  --body) MODE=body; shift; BODYSET="${1:-}"; [ -n "$BODYSET" ] || usage;;
  -*) usage;;
  *) [ -z "$TEAM" ] || usage; TEAM="$1";; esac; shift; done

if [ -z "${FT_SETS_FILE:-}" ] || [ ! -f "$FT_SETS_FILE" ]; then
  echo "ERROR 원장 없음 — FT_SETS_FILE=${FT_SETS_FILE:-<미설정>} (다른 경로로 넘어가지 않는다)"; exit 3; fi
LDIR="$(dirname "$FT_SETS_FILE")"
REPO="${FT_SETS_REPO:-$(git -C "$LDIR" rev-parse --show-toplevel 2>/dev/null)}"
TEAMROOT="${FT_SETS_TEAM_ROOT:-$PWD}"

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; REPLY="${s%"${s##*[![:space:]]}"}"; }
split_row() { local raw i; C=(); IFS='|' read -ra raw <<<"$1"; for i in "${!raw[@]}"; do trim "${raw[i]}"; C[i]="$REPLY"; done; }
status_kw() { REPLY="${1%% — *}"; }
rank() { case "$1" in 진행) REPLY=0;; 발주) REPLY=1;; 보류) REPLY=2;; 닫힘) REPLY=3;; 폐기) REPLY=4;; *) REPLY=5;; esac; }

ROWS=(); HEAD_ROW=""; SEP='^\|[-: |]+$'
while IFS= read -r line; do
  [[ "$line" == \|* ]] || continue
  [[ "$line" =~ $SEP ]] && continue
  split_row "$line"
  if [ "${C[1]:-}" = 세트 ]; then HEAD_ROW="$line"; else ROWS+=("$line"); fi
done < "$FT_SETS_FILE"

row_lookup() { local r; [ ${#ROWS[@]} -gt 0 ] || return 1
  for r in "${ROWS[@]}"; do split_row "$r"; [ "${C[1]:-}" = "$1" ] && return 0; done; return 1; }

ledger_head() {
  local f sha dirty
  f="$(basename "$FT_SETS_FILE")"
  if ! git -C "$LDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "원장 $FT_SETS_FILE @ git 밖 · 미커밋 변경 알 수 없음"; return; fi
  sha="$(git -C "$LDIR" log -1 --format=%H -- "$f" 2>/dev/null | cut -c1-10)"
  dirty="$(git -C "$LDIR" status --porcelain -- "$f" 2>/dev/null)"
  echo "원장 $FT_SETS_FILE @ ${sha:-미커밋} · 미커밋 변경 $([ -n "$dirty" ] && echo 있음 || echo 없음)"
}

cmd_list() {
  local r k n0=0 n1=0 n2=0 n3=0 n4=0 out="" i
  ledger_head
  echo "$HEAD_ROW"; echo "|---|---|---|---|---|---|---|---|---|---|"
  if [ ${#ROWS[@]} -gt 0 ]; then
    for i in 0 1 2 3 4 5; do for r in "${ROWS[@]}"; do
      split_row "$r"; { [ -z "$TEAM" ] || [ "${C[2]:-}" = "$TEAM" ]; } || continue
      status_kw "${C[3]:-}"; k="$REPLY"; rank "$k"; [ "$REPLY" = "$i" ] || continue
      echo "$r"; case "$k" in 진행) n0=$((n0+1));; 발주) n1=$((n1+1));; 보류) n2=$((n2+1));; 닫힘) n3=$((n3+1));; 폐기) n4=$((n4+1));; esac
    done; done
  fi
  out="세트 진행 $n0 · 발주 $n1 · 보류 $n2 · 닫힘 $n3"; [ "$n4" -gt 0 ] && out="$out · 폐기 $n4"
  echo "$out"
  [ -z "$TEAM" ] || scan_requests
}

# 요청 줄 판정(설계 §3-b): 적용 sha 있음 → 원장 HEAD 가 그 commit 을 품었나(STALE) · 적용 - → REACK(원장 적용 id 가 같음 · 전 상태 검사보다 먼저) > MISMATCH > PENDING
scan_requests() {
  local f="$TEAMROOT/design/$TEAM/orders/SET-REQUESTS.md" id set from to ap head kw n=0 open=0
  [ -f "$f" ] || { echo "요청 파일 없음: $f"; return; }
  head="$(git -C "$LDIR" rev-parse HEAD 2>/dev/null || true)"
  while IFS=$'\t' read -r id set from to ap; do
    n=$((n+1))
    if [ "$ap" != "-" ]; then
      if ! git -C "$LDIR" cat-file -e "$ap^{commit}" 2>/dev/null || ! git -C "$LDIR" merge-base --is-ancestor "$ap" "${head:-HEAD}" 2>/dev/null; then
        echo "STALE $id $set — 적용 $ap 를 이 원장(HEAD ${head:0:10})이 아직 품지 않음(원장이 적용 commit 보다 뒤)"; open=$((open+1)); fi
      continue; fi
    open=$((open+1))
    if ! row_lookup "$set"; then echo "MISSING $id $set — 원장에 그 세트 행 없음"; continue; fi
    status_kw "${C[3]}"; kw="$REPLY"
    if [ "${C[9]}" = "$id" ]; then echo "REACK $id $set — 원장은 이미 적용(적용 id 같음) · 갱신 0 · 같은 ACK 재회신만"
    elif [ "$kw" != "$from" ]; then echo "MISMATCH $id $set — 원장 지금 ${C[3]} ≠ 전 상태 $from · 적용 0 · 불일치 회신"
    else echo "PENDING $id $set — $from → $to 원장 미반영(적용 -)"; fi
  done < <(awk -F' · ' '/^- [a-z0-9]+-s[0-9]+-[0-9][0-9] · /{ sub(/^- /,"",$1); split($3,t," → "); a=$NF; sub(/^적용 /,"",a); print $1 "\t" $2 "\t" t[1] "\t" t[2] "\t" a }' "$f")
  echo "요청 ${n}건 · 미완료 $open"
}

FAILS=0
err()  { echo "ERROR $1"; FAILS=$((FAILS+1)); }
warn() { echo "WARN $1"; }

# 발주 칸 = byz-agents@<sha>:<경로>#<앵커>. 진행 중 행은 객체·보호 ref(refs/orders/<판정>-<팀>) 둘 다, 닫힘·폐기 행은 객체 부재를 WARN 만(ref 정리는 CLOSEOUT)
check_order() {
  local n="$1" kw="$2" ord="$3" v="$4" team="$5" sha path full
  [[ "$ord" =~ ^[a-z0-9-]+@([0-9a-f]{7,40}):([^#]+)(#.+)?$ ]] || { err "$n 발주 칸 형식 아님: $ord"; return; }
  sha="${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"
  if ! git -C "$REPO" cat-file -e "$sha:$path" 2>/dev/null; then
    case "$kw" in 닫힘|폐기) warn "$n 미전달 — $sha:$path 객체 없음(닫힘·폐기 행)";; *) err "$n 미전달 — $sha:$path 객체 없음";; esac; return; fi
  case "$kw" in 닫힘|폐기) return;; esac
  full="$(git -C "$REPO" rev-parse -q --verify "refs/orders/$v-$team^{commit}" 2>/dev/null)" || full=""
  if [ -z "$full" ]; then err "$n 보호 ref refs/orders/$v-$team 없음"
  elif [[ "$full" != "$sha"* ]]; then err "$n 보호 ref refs/orders/$v-$team 가 발주 commit($sha)이 아닌 ${full:0:10} 를 가리킴"; fi
}

check_row() {
  local n="${C[1]:-}" team="${C[2]:-}" st="${C[3]:-}" iss="${C[6]:-}" v="${C[8]:-}" ap="${C[9]:-}" kw cnt tok
  [ ${#C[@]} -eq 11 ] || { err "$n 칸 수 $(( ${#C[@]} - 1 )) ≠ 10"; return; }
  [[ "$n" =~ ^[a-z0-9]+/s[0-9]+-[a-z0-9-]{3,40}$ ]] || err "이름 형식 아님: $n"
  [ "${n%%/*}" = "$team" ] || err "$n 팀 칸($team) ≠ 이름 앞부분"
  status_kw "$st"; kw="$REPLY"
  [[ "$st" =~ ^(발주|진행)$|^(보류|닫힘)\ —\ .+$|^폐기\ —\ 판정\ [0-9]+$ ]] || err "$n 상태 5종 아님: $st"
  [[ "$iss" =~ ^-$|^#[0-9]+(\ #[0-9]+)*$ ]] || err "$n Issue 칸 형식 아님: $iss"
  [[ "$v" =~ ^[0-9]+$ ]] || err "$n 판정 칸 숫자 아님: $v"
  [[ "$ap" =~ ^-$|^[a-z0-9]+-s[0-9]+-[0-9][0-9]$ ]] || err "$n 적용 id 형식 아님: $ap"
  if [ "$kw" = 닫힘 ] && [ "$iss" != "-" ]; then
    cnt="$(printf '%s\n' "$iss" | wc -w | tr -d ' ')"
    [[ "$st" == *"close $cnt/$cnt"* ]] || err "$n 닫힘인데 close $cnt/$cnt 확인 없음(일부 실패면 보류 — close 실패 #N): $st"; fi
  case " $SEEN " in *" $n "*) err "$n 행 중복(한 세트 = 한 행)";; esac; SEEN="$SEEN $n"
  for tok in $iss; do [ "$tok" = "-" ] || ISSLINES="$ISSLINES${tok#\#} $n"$'\n'; done
  check_order "$n" "$kw" "${C[7]:-}" "$v" "$team"
}

cmd_check() {
  local r; SEEN=""; ISSLINES=""
  if [ ${#ROWS[@]} -gt 0 ]; then for r in "${ROWS[@]}"; do
    split_row "$r"; { [ -z "$TEAM" ] || [ "${C[2]:-}" = "$TEAM" ]; } && check_row; done; fi
  printf '%s' "$ISSLINES" | sort -k1,1n | awk '$1==p { print "WARN Issue #" $1 " 가 두 세트에 있다: " pn " / " $2 } { p=$1; pn=$2 }'
  if [ "$FAILS" -gt 0 ]; then echo "CHECK FAIL — ERROR $FAILS건"; exit 1; fi
  echo "CHECK OK — 행 ${#ROWS[@]}"
}

cmd_body() {
  row_lookup "$BODYSET" || { echo "ERROR 세트 없음: $BODYSET"; exit 1; }
  [[ "${C[7]}" =~ ^[a-z0-9-]+@([0-9a-f]{7,40}):([^#]+)(#.+)?$ ]] || { echo "ERROR 발주 칸 형식 아님: ${C[7]}"; exit 1; }
  git -C "$REPO" show "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}" 2>/dev/null || { echo "ERROR 미전달 — ${BASH_REMATCH[1]}:${BASH_REMATCH[2]} 객체 없음"; exit 1; }
}

case "$MODE" in list) cmd_list;; check) cmd_check;; body) cmd_body;; esac
