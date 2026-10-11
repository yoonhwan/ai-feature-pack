#!/usr/bin/env bash
# ft-issue-close-check.sh <Issue#> [--from-json <file>] [--repo <dir>] [--gate] [--extra-comment <file>] [--has-token <tok>]
#   C4 · Issue close 완료 8항 검사 (읽기 전용 — gh issue view 만 부른다 · edit/close/label 0).
#   8항 = 닫는 사건 · PR · 재현 PASS · 정리 · 기록 · 정본 · 원인 확정 · 같은 증상 보류 (design/harness/ISSUE-TRANSITIONS.md §3).
#   통과 = ①코멘트 어딘가에 6항 줄이 «값과 함께» 전부 있다 ②Closes 로 연결된 PR 이 있다(closedByPullRequestsReferences) ③7·8항(아래) 또는 관찰 조건.
#   7·8항 = `원인 확정: Y — <근거 ≥10자>` · `같은 증상 보류: 0` — 키로 «가장 마지막 줄»을 고른 뒤 그 줄만 검증한다(R102 · 판정 1059·1060).
#     관찰 중(`관찰 시작:` 마커 · 라벨 status:observing · 미완료 거절 기록)이면 7·8항 대신 «현재 구간에서 서로 다른 판 2회 재현 0» 을 요구한다.
#   --gate = 7·8항+관찰 조건만(1~6항·Closes 생략) · exit 0 통과 / 3 거절(stderr 문장 + stdout `GATE rc=3 kind=… marker=… label=… reason=…`).
#   --extra-comment = 곧 올릴 닫는 코멘트 파일을 «가장 마지막» 코멘트로 붙여 읽는다 · --has-token = 코멘트에 `token=<tok>` 있으면 exit 0 없으면 1.
#   gh view = timeout 7 + 재시도 1(env FT_GATE_TIMEOUT_S 시험 훅).
#   6항 정본 = `정본: <파일>#<절>@<랜딩 sha>`(부분 PR 은 `@S1,S2` · ff 랜딩은 `@T..S`) 또는 `정본 영향 없음: <이유 ≥10자>`.
#     `정본:` 은 S 마다 (가)S 가 랜딩 ref(env FT_LAND_REF · 기본 origin/main)의 조상 (나)S^1..S(T..S 면 그 구간)의 바뀐 파일에 <파일> 포함.
#     fetch 하지 않는다 — S 가 로컬에 없으면 MISS.
#   exit 0 = 통과 · 1 = 미비(사유 stdout) · 2 = usage 또는 조회 실패
#   --from-json = gh 호출 대신 같은 모양의 JSON 파일(시험용 · tests/fixtures/issue_close/).
#   --repo = 정본 sha 를 조회할 git 리포(기본 = 이 스크립트가 있는 리포 루트).
set -uo pipefail
unset GH_TOKEN
N="${1:-}"; shift || true
FROM_JSON=""; REPO=""; GATE=0; EXTRA=""; HAS_TOKEN=""
while [ $# -gt 0 ]; do case "$1" in
  --from-json) FROM_JSON="${2:-}"; shift 2;; --repo) REPO="${2:-}"; shift 2;; --gate) GATE=1; shift;;
  --extra-comment) EXTRA="${2:-}"; shift 2;; --has-token) HAS_TOKEN="${2:-}"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$N" in ''|*[!0-9]*) echo "usage: $0 <Issue#> [--from-json <file>] [--repo <dir>] [--gate] [--extra-comment <file>] [--has-token <tok>]" >&2; exit 2;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$REPO" ] || REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || (cd "$HERE/../.." && pwd))"
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }

if [ -n "$FROM_JSON" ]; then
  [ -f "$FROM_JSON" ] || { echo "json 없음: $FROM_JSON" >&2; exit 2; }
  JSON="$(cat "$FROM_JSON")"
else
  TO="$(command -v timeout || command -v gtimeout)" || { echo "timeout(coreutils) 필요 — 7초 룰" >&2; exit 2; }
  for TRY in 1 2; do   # 7초 + 재시도 1
    JSON="$("$TO" "${FT_GATE_TIMEOUT_S:-7}" gh issue view "$N" --json number,state,title,labels,comments,closedByPullRequestsReferences 2>&1)" && break
    [ "$TRY" = 2 ] && { echo "gh issue view $N 실패: $JSON" >&2; exit 2; }
  done
fi
if [ -n "$EXTRA" ]; then
  [ -f "$EXTRA" ] || { echo "extra 코멘트 파일 없음: $EXTRA" >&2; exit 2; }
  JSON="$(jq --rawfile b "$EXTRA" '.comments += [{body:$b}]' <<<"$JSON")"
fi
if [ -n "$HAS_TOKEN" ]; then jq -e --arg t "token=$HAS_TOKEN" '[.comments[].body | select(contains($t))] | length > 0' <<<"$JSON" >/dev/null; exit $?; fi

# ── 7·8항 · 관찰 구간 (R102 · design/harness/PLAN-r102-close-gate §1~§3) ──
KEYP='^\s*[-*]?\s*(\[[ xX]\]\s*)?'
LREF="${FT_LAND_REF:-origin/main}"
pick_last() { # <키> → «가장 마지막 키 줄»의 값 — 값이 무효여도 앞 줄로 내려가지 않는다(선택 먼저 · 검증 나중)
  jq -r --arg p "$KEYP" --arg k "$1" '[.comments[].body | split("\n")[] | select(test($p + $k + "\\s*[:：]"))] | last // empty
    | sub($p + $k + "\\s*[:：]\\s*"; "") | sub("\\s+$"; "")' <<<"$JSON"
}
EVJQ='[.comments[].body | split("\n")[]] | .[] |
  (select(test($p + "관찰 시작\\s*[:：]")) | "M\t" + ((capture("수리 랜딩=(?<s>[0-9a-fA-F]{40})") | .s | ascii_downcase) // "")),
  (select(test($p + "관찰\\s*[:：]\\s*판=[0-9a-fA-F]{40}\\s*[·,]\\s*결과=(재현 0|재현 있음)\\s*[·,]\\s*판정=[0-9]+"))
    | capture("판=(?<s>[0-9a-fA-F]{40}).*결과=(?<r>재현 0|재현 있음)") | "O\t" + (.s | ascii_downcase) + "\t" + (if .r == "재현 0" then "0" else "Y" end)),
  (select(test($p + "관찰 해제\\s*[:：]\\s*판정=[0-9]+")) | "R\t\t"),
  (select(test("^\\[닫기 거절 · R102 · token=")) | "H\t\t")'
obs_scan() { # 이벤트 줄(M 마커 · O 관찰 · R 해제 · H 거절 기록)을 순서대로 읽어 현재 구간 상태를 만든다
  local T S R valid
  FIRST=0; PEND=0; REL=0; ANY=0; REPRO=0; LASTREPRO=""; FIX=""; ALLS=" "; OK0=" "
  while IFS=$'\t' read -r T S R; do case "$T" in
    M) ANY=1
       if [ $FIRST -eq 0 ]; then valid=1   # 첫 마커 = 구간 시작
       else valid=0   # 새 구간 = 수리 랜딩 sha 가 main 조상 · 앞 마커 sha 와 다름 · 앞 수리의 후손 · 현재 구간에 재현 있음
         if [ -n "$S" ] && [ $REPRO -gt 0 ] && [[ "$ALLS" != *" $S "* ]] && git -C "$REPO" rev-parse --verify -q "$LREF^{commit}" >/dev/null \
            && git -C "$REPO" cat-file -e "$S^{commit}" 2>/dev/null && git -C "$REPO" merge-base --is-ancestor "$S" "$LREF" 2>/dev/null \
            && { [ -z "$FIX" ] || git -C "$REPO" merge-base --is-ancestor "$FIX" "$S" 2>/dev/null; }; then valid=1; fi
       fi
       [ -z "$S" ] || ALLS="$ALLS$S "
       if [ $valid -eq 1 ]; then FIRST=1; REPRO=0; OK0=" "; REL=0; PEND=0; [ -z "$S" ] || FIX="$S"; fi;;
    O) [ $FIRST -eq 1 ] || continue   # 첫 마커 앞의 관찰 줄은 구간 밖
       if [ "$R" = Y ]; then REPRO=$((REPRO+1)); LASTREPRO="${S:0:10}"; else [[ "$OK0" == *" $S "* ]] || OK0="$OK0$S "; fi;;
    R) [ $FIRST -eq 1 ] && REL=1;;
    H) PEND=1;;
  esac; done <<<"$(jq -r --arg p "$KEYP" "$EVJQ" <<<"$JSON")"
}
gate_eval() { # → G_RC(0|3) G_KIND G_MSG G_MARKER G_LABEL G_REASON
  local K7 K8 V8 W s k=0 list="" miss=""
  K7="$(jq -rn --arg v "$(pick_last '원인 확정')" 'if ($v == "") or ($v | startswith("<")) then "blank"
    elif ($v | test("^[Yy]\\s*[—–-]+\\s*\\S")) then (($v | sub("^[Yy]\\s*[—–-]+\\s*"; "")) as $r | if ($r | startswith("<")) or ($r | length) < 10 then "blank" else "Y" end)
    elif ($v | test("^[Nn]($|\\s|[—–-])")) then "N" else "blank" end')"
  V8="$(pick_last '같은 증상 보류')"
  K8="$(jq -rn --arg v "$V8" 'if ($v == "") or ($v | startswith("<")) then "blank" elif ($v | test("^0\\s*$")) then "zero" else "hold" end')"
  obs_scan
  G_MARKER=$ANY; G_LABEL=0; G_RC=3; G_KIND=""; G_MSG=""; G_REASON="마커 복구"
  jq -e '[.labels[]?.name] | index("status:observing")' <<<"$JSON" >/dev/null 2>&1 && G_LABEL=1
  W=""; [ "$K7" = blank ] && W="7항"; [ "$K8" = blank ] && W="${W:+7·}8항"
  if [ -n "$W" ]; then G_REASON="빈 칸"
  elif [ "$K7" = N ] || [ "$K8" = hold ]; then
    G_REASON=""; [ "$K7" = N ] && G_REASON="원인 확정 N"; [ "$K8" = hold ] && G_REASON="${G_REASON:+$G_REASON · }같은 증상 보류 $V8"
  fi
  if { [ $FIRST -eq 1 ] || [ $PEND -eq 1 ] || [ $G_LABEL -eq 1 ]; } && [ $REL -eq 0 ]; then   # 관찰 중
    if [ $FIRST -eq 0 ] && [ $PEND -eq 0 ]; then
      G_KIND=obs_nomarker; G_MSG="REJECT close #$N — status:observing 인데 「관찰 시작:」 줄 없음 — 복구 쓰기 재시도."
    elif [ $REPRO -gt 0 ]; then
      G_KIND=obs_repro; G_MSG="REJECT close #$N — 관찰 중 재현 있음(판 $LASTREPRO) — 수리 랜딩 뒤 「관찰 시작: … · 수리 랜딩=<40hex>」 로 새 관찰을 연다."
    else
      for s in $OK0; do if git -C "$REPO" cat-file -e "$s^{commit}" 2>/dev/null; then k=$((k+1)); list="$list${list:+,}${s:0:10}"; else miss="$miss ${s:0:10}"; fi; done
      if [ $k -ge 2 ]; then G_RC=0; G_KIND=obs_pass
      else G_KIND=obs_short; G_MSG="REJECT close #$N — 관찰 중 · 재현 0 판 $k/2 (${list:-없음}) — 서로 다른 판 $((2-k))회 더.${miss:+ 로컬에 없는 판:$miss — git fetch 후 다시.}"; fi
    fi
  elif [ -n "$W" ]; then
    G_KIND=blank; G_MSG="REJECT close #$N — 7항 「원인 확정」/8항 「같은 증상 보류」 마지막 줄이 비었거나 무효($W) → 닫지 않고 «관찰 중»(status:observing). 실수면 planner 값으로 라벨 해제 뒤 다시."
  elif [ "$K7" = N ] || [ "$K8" = hold ]; then
    G_KIND=n_or_hold; G_MSG="REJECT close #$N — 원인 확정=$K7 · 같은 증상 보류=$V8 → 닫지 않고 «관찰 중»(status:observing). 닫는 조건 = 오빠 폰에서 서로 다른 판(sha) 2회 재현 0 — 코멘트에 「관찰: 판=<40hex> · 결과=재현 0 · 판정=<번호>」 2줄(판이 서로 달라야 함)."
  else G_RC=0; G_KIND=pass; fi
}
if [ "$GATE" = 1 ]; then
  gate_eval
  [ "$G_RC" -eq 0 ] && { echo "GATE rc=0 kind=$G_KIND"; exit 0; }
  echo "$G_MSG" >&2; echo "GATE rc=3 kind=$G_KIND marker=$G_MARKER label=$G_LABEL reason=$G_REASON"; exit 3
fi

STATE="$(jq -r '.state' <<<"$JSON")"
echo "Issue #$N state=$STATE title=$(jq -r '.title' <<<"$JSON")"

MISS=0
for ITEM in "닫는 사건" "PR" "재현 PASS" "정리" "기록"; do
  # 줄 모양: [- ][[x] ]<항목>: <값>  (값은 비어 있지 않고 <...> 자리표시가 아님)
  HIT="$(jq -r --arg item "$ITEM" '[.comments[].body | split("\n")[]
    | select(test("^\\s*[-*]?\\s*(\\[[ xX]\\]\\s*)?" + $item + "\\s*[:：]\\s*[^<\\s]"))] | length' <<<"$JSON")"
  if [ "${HIT:-0}" -ge 1 ]; then echo "  OK   5항 $ITEM"; else echo "  MISS 5항 $ITEM — 코멘트에 「${ITEM}: <값>」 줄 없음"; MISS=1; fi
done

# 6항 정본 — 줄 모양은 5항과 같다. `정본\s*:` 만 잡으므로 `정본 영향 없음:` 줄은 섞이지 않는다.
canon_lines() { # <키 정규식> → 값 줄들(값 비면·`<…>` 면 제외)
  jq -r --arg k "$1" '.comments[].body | split("\n")[]
    | select(test("^\\s*[-*]?\\s*(\\[[ xX]\\]\\s*)?" + $k + "\\s*[:：]\\s*[^<\\s]"))
    | sub("^\\s*[-*]?\\s*(\\[[ xX]\\]\\s*)?" + $k + "\\s*[:：]\\s*"; "") | sub("\\s+$"; "")' <<<"$JSON"
}
canon_check_sha() { # <파일> <sha 또는 T..S> → 0 통과 · 1 MISS(사유 stdout)
  local X="$1" TOK="$2" S FROM FILES REF="${FT_LAND_REF:-origin/main}"
  case "$TOK" in -*|'') echo "  MISS 6항 정본 — sha 「${TOK}」 형식 오류"; return 1;; esac
  case "$TOK" in *..*) FROM="${TOK%%..*}"; S="${TOK##*..}";; *) S="$TOK"; FROM="$TOK^1";; esac
  if ! git -C "$REPO" cat-file -e "${S}^{commit}" 2>/dev/null; then echo "  MISS 6항 정본 $S — S 없음 — git fetch 후 다시"; return 1; fi
  if ! git -C "$REPO" rev-parse --verify -q "${REF}^{commit}" >/dev/null; then echo "  MISS 6항 정본 $S — 랜딩 ref ${REF} 없음 — git fetch 후 다시"; return 1; fi
  if ! git -C "$REPO" merge-base --is-ancestor "$S" "$REF"; then echo "  MISS 6항 정본 $S — 랜딩 안 됨 (${REF} 의 조상이 아님)"; return 1; fi
  if ! FILES="$(git -C "$REPO" diff --name-only "$FROM" "$S" 2>/dev/null)"; then echo "  MISS 6항 정본 $S — 범위 ${FROM}..${S} 를 못 읽음"; return 1; fi
  if ! grep -Fxq -- "$X" <<<"$FILES"; then echo "  MISS 6항 정본 $S — 랜딩 commit 에 정본 $X 없음 — 로컬에만 고친 것"; return 1; fi
  echo "  OK   6항 정본 $X @ $S"; return 0
}
CANON="$(canon_lines '정본')"
if [ -n "$CANON" ]; then
  while IFS= read -r V; do
    X="${V%%#*}"; REST="${V#*#}"
    if [ "$X" = "$V" ] || [ "${REST#*@}" = "$REST" ]; then echo "  MISS 6항 정본 — 「${V}」 은 <파일>#<절>@<sha> 모양이 아님"; MISS=1; continue; fi
    X="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$X")"; SHAS="${REST##*@}"
    IFS=',' read -ra TOKS <<<"$SHAS"
    for TOK in "${TOKS[@]}"; do
      TOK="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$TOK")"
      canon_check_sha "$X" "$TOK" || MISS=1
    done
  done <<<"$CANON"
else
  REASON="$(canon_lines '정본 영향 없음' | head -1)"
  RLEN="$(jq -Rn --arg r "$REASON" '$r | length')"   # 글자 수(로케일 무관 — ${#…} 는 C 로케일에서 바이트)
  if [ -z "$REASON" ]; then
    echo "  MISS 6항 정본 — 코멘트에 「정본: <파일>#<절>@<랜딩 sha>」 또는 「정본 영향 없음: <이유>」 줄 없음"; MISS=1
  elif [ "$RLEN" -ge 10 ]; then echo "  OK   6항 정본 영향 없음 (이유 ${RLEN}자)"
  else echo "  MISS 6항 정본 영향 없음 — 이유 ${RLEN}자 (<10자)"; MISS=1; fi
fi

gate_eval   # 7·8항(또는 관찰 조건) — 원인 확정 · 같은 증상 보류
if [ "$G_RC" -eq 0 ]; then echo "  OK   7·8항 원인 확정·같은 증상 보류 ($G_KIND)"; else PFX="REJECT close #$N — "; echo "  MISS 7·8항 — ${G_MSG#"$PFX"}"; MISS=1; fi

PRS="$(jq -r '[.closedByPullRequestsReferences[]?.number] | map("#"+tostring) | join(" ")' <<<"$JSON")"
if [ -n "$PRS" ]; then echo "  OK   Closes 연결 PR $PRS"; else echo "  MISS Closes 연결 PR 없음 — 랜딩 PR 본문에 「Closes #${N}」 필요"; MISS=1; fi

if [ "$MISS" -eq 0 ]; then echo "PASS #$N 완료 8항 + Closes 연결"; exit 0; fi
echo "FAIL #$N 미비 — 소유 오케에 1통(보완 또는 ft-issue-reopen.sh)"; exit 1
