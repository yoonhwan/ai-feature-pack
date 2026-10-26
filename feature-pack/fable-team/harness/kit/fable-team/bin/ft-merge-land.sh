#!/usr/bin/env bash
# ft-merge-land.sh <PR번호> --approve-sha <40hex> [--repo <dir>] [--remote origin] [--target main]   (R230 교정 2 H1 · 오빠 판정 1875 «로컬 착지 강제»)
#   main 병합 = 이 도구뿐(gh pr merge·ft-gh-as-tank.sh pr merge 는 훅이 막는다). 검사한 트리 == 실제로 main 에 놓이는 트리 — 틈은 git 서버의 non-FF 거절이 닫는다.
#   ① 오빠 승인 값(--approve-sha = 승인한 PR head sha · 없으면 실행 0 · 지금 head 가 다르면 «A 뒤 main 병합만 + 자기 변경 동일» 일 때만 ft-approval-equiv 로 통과 — R247 판정 1917) ② PR OPEN·base main·head sha 결속 ③ PR head fetch(pull/N/head) ④ ft-merge-gate(main 포함·줄 계약)
#   ⑤ Q = commit-tree <S^{tree}> -p <M>(squash 1커밋 · 메시지 = PR 제목·본문 + PR #N) · --ff(R392) = 승인 sha == PR head ∧ main 이 head 의 조상일 때만 Q=S(commit-tree 0 · 전송 객체 0 · 커밋 수 보존) ⑥ git push origin Q:refs/heads/main (force 0 · non-FF = 착지 0)
#   ⑦ PR 에 착지 sha 코멘트 + 닫기. 7초 룰: gh·fetch 각 7 s + 재시도 1 · push 는 크기 비례 PB=min(F + 7 s × ceil(객체수/U0), 70 s)(fm_push_bound · R354) · 실제 상한 AB=min(PB, 남은 시간)(남은 11 s·PB 70 이면 11 s 한 번 · timeout 이면 재시도 0) · 재시도 1 은 «서버 응답 전 연결 실패» 뿐(timeout·reset·remote 출력 = 불명 → ls-remote 1회로 착지됨/착지 0/불명 판정) · 총 마감 70 s.
#   ★모든 모드(ON·OFF·tamper·상태 못 읽음)에서 승인 파일(autonomy-merge-approved/<sha> + autonomy.log 한 줄)이 필요★(R336 · autonomy-merge-guard 와 같은 결속). 승인 파일 폴더 = ft-autonomy.sh state-dir(R253). 성공 줄에 approve-file=<승인 epoch>.
#   exit 0 = 착지+정리 · 1 = REJECT(착지 0) · 2 = usage·승인 없음 · 3 = 착지 성공 · PR 코멘트/닫기 실패(수동). FT_GH/FT_GH_WRITE = 시험 주입.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"; . "$HERE/ft-evidence-lib.sh" && [ -n "${FT_EVIDENCE_RX:-}" ] || { echo "REJECT 증거 로그 판정식 없음($HERE/ft-evidence-lib.sh) — 실행 0"; exit 2; }   # r449: pre-commit·ft-evidence-untrack 과 같은 함수
PR=""; AP=""; REPO=""; REMOTE="origin"; TARGET="main"; FF=""; T0=$SECONDS
GH_R="${FT_GH:-gh}"; GH_W="${FT_GH_WRITE:-$HERE/ft-gh-as-tank.sh}"
usage() { echo "usage: $0 <PR번호> --approve-sha <40hex> [--ff] [--repo <dir>] [--remote origin] [--target main]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --approve-sha) [ $# -ge 2 ] || usage; AP="$2"; shift 2;;
  --ff) FF=1; shift;;
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --remote) [ $# -ge 2 ] || usage; REMOTE="$2"; shift 2;;
  --target) [ $# -ge 2 ] || usage; TARGET="$2"; shift 2;;
  -*) usage;; *) [ -z "$PR" ] || usage; PR="$1"; shift;; esac; done
printf '%s' "$PR" | grep -Eq '^[0-9]+$' || usage
[ -z "$AP" ] || printf '%s' "$AP" | grep -Eq '^[0-9a-f]{40}$' || { echo "REJECT 오빠 병합 승인 값(--approve-sha <PR head 40hex>) 없음 — 실행 0"; exit 2; }   # R725: 빈 값 = 문서 전용 판정 경로(아래 ft_doc_exempt.py)
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "REJECT repo 를 찾을 수 없음"; exit 1; }
G() { git -C "$REPO" "$@"; }
rej() { echo "REJECT $* (착지 0)"; exit 1; }
CTX="$(fm_land_ctx "$REPO" "$REMOTE" "${FT_ROOT:-}")" || rej "대상 리포 remote URL 해석 실패(fetch·push URL 이 같은 github owner/name 이어야) — 어느 리포 PR 인지 몰라 착지 0"   # r648: 승인 루트(BYZ) ≠ 대상 리포
IFS='|' read -r ROOT CROSS SLUG BH RROOT <<<"$CTX"; STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"
pushsave() { local f; mkdir -p -- "$STATE/push-out" 2>/dev/null && f="$STATE/push-out/push-$PR-$(date +%Y%m%dT%H%M%S)-$$.log" && printf '%s\n' "$POUT" >"$f" 2>/dev/null && printf '%s' "$f"; }   # r595: push 출력 전문을 상태 폴더에 남긴다 — 경로 출력, 쓰기 실패면 rc≠0(삼키기 0)
pushwhy() { local f; f="$(pushsave)" || f=""; printf '사유 %s · 마지막 줄 %s · 전문=%s' "$(printf '%s\n' "$POUT" | grep -E '^(remote:|PUSH_DENIED|! \[)' | head -n 3 | cut -c1-200 | tr '\n' '|' | sed 's/|$//;s/|/ · /g')" "$(printf '%s' "$POUT" | tail -n1)" "${f:-저장 실패}"; }   # r595: 거부 사유 줄(앞 3개) + 마지막 줄 + 전문 파일 경로
LIM="${FT_LAND_TOTAL_S:-70}"; { [ "$LIM" -le 70 ] && [ "$LIM" -ge 1 ]; } 2>/dev/null || LIM=70   # 총 마감 — 시험 주입은 줄이기만 가능(70 s 초과 불가)
deadline() { [ $((SECONDS - T0)) -lt "$LIM" ] || rej "총 마감 $LIM s 초과"; }

AUT="$HERE/ft-autonomy.sh"   # R336: 모든 모드(on·off·tamper·불명)에서 오빠 승인 파일 + log 한 줄 필요 — OFF 에서 master 가 sha 만 적어 착지하던 틈을 닫는다
AST="$(bash "$AUT" state-dir 2>/dev/null)"   # r648: 승인 폴더 = 이 정식 리졸버 하나뿐(공용 루트를 직접 쓰는 길 0)
[ -n "$AST" ] || AST="$(cd "${FT_ROOT:-$ROOT}" 2>/dev/null && bash "$AUT" state-dir 2>/dev/null)"   # 팩 cwd 등에서 해석 실패할 때만 부른 리포 안에서 재시도(LIVE_ROOT 그대로 작동)
[ -n "$AST" ] || { echo "REJECT 자율 상태 폴더 해석 실패 — 실행 0"; exit 2; }
[ -z "$AP" ] || { AF="$AST/autonomy-merge-approved/$AP"   # R725: 승인 값을 준 경우만 승인 파일을 본다(빈 값 = doc-exempt 판정이 가른다)
[ "$(wc -l < "$AF" 2>/dev/null | tr -d ' ')" = 1 ] && grep -q "^approve-merge $AP " "$AF" && grep -qxF "$(head -n1 "$AF")" "$AST/autonomy.log" 2>/dev/null \
  || { echo "REJECT 오빠 승인 파일 없음 — 승인 h 한 줄 먼저(approve-merge $AP 승인 파일·로그 한 줄 없음) — 실행 0"; exit 2; }
AFE="$(awk '{print $4}' "$AF")"; AFV="$(awk '{print $3}' "$AF")"; }   # 승인 epoch — merge-gate.log 에 «누가 언제 승인했나» 를 남긴다

JSON="$(fm_t7 "$GH_R" pr view "$PR" ${SLUG:+-R "$SLUG"} --json headRefOid,headRefName,title,body,state,baseRefName)" || rej "gh pr view $PR 실패(7 s + 재시도 1)"; deadline
pf() { printf '%s' "$JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1"; }
[ "$(pf state)" = OPEN ] || rej "PR #$PR 가 OPEN 아님($(pf state))"
[ "$(pf baseRefName)" = "$TARGET" ] || rej "PR #$PR base 가 $TARGET 아님($(pf baseRefName))"
HEADSHA="$(pf headRefOid)"   # head != 승인 sha 는 게이트 뒤 ft-approval-equiv 가 가른다(R247 판정 1917 — A 뒤 main 병합만 했고 자기 변경이 같으면 같은 승인)
fm_t7 git -c gc.auto=0 -C "$REPO" fetch --quiet "$REMOTE" "pull/$PR/head" || rej "PR head fetch 실패"; deadline
S="$(G rev-parse --verify -q FETCH_HEAD^{commit})" && [ "$S" = "$HEADSHA" ] || rej "fetch 한 head($S) != PR head($HEADSHA)"; DNY="$(bash "$HERE/ft-merge-deny.sh" "$S" --branch "$(pf headRefName)" --repo "$REPO")" || rej "${DNY:-착지 금지 목록 검사 실패(사유 0)}"   # r755: 착지 금지 가지 목록(ft-merge-deny.txt) — 목록 없음·꼴 오류·금지 가지 = 착지 0(fail-closed)

GOUT="$(bash "$HERE/ft-merge-gate.sh" "$S" --repo "$REPO" --remote "$REMOTE" --target "$TARGET" --base-head-file "$BH")" || rej "게이트: ${GOUT#DENY }"; deadline
EQ=""   # R247: 게이트가 main 을 fetch 한 «뒤»(equiv 는 로컬 git 만) — 통과면 나머지 게이트·착지는 S 기준 그대로. 못 판단(rc3)도 REJECT.
[ -z "$FF" ] || [ "$HEADSHA" = "$AP" ] || rej "ff 는 승인 sha == PR head 만(승인 ${AP:0:10} · head ${HEADSHA:0:10}) — 동일승인 대조 경로는 --ff 없이"   # R392: ff 는 equiv 경로 0
if [ -n "$AP" ] && [ "$HEADSHA" != "$AP" ]; then
  EQ="$("$(fm_timeout_bin)" 30 bash "$HERE/ft-approval-equiv.sh" "$AP" "$S" --repo "$REPO" --remote "$REMOTE" --target "$TARGET" 2>&1)" \
    || rej "PR head($HEADSHA) != 승인 sha($AP) — 승인 뒤 head 가 움직였고 동일승인 대조(병합·rebase 두 경로)도 실패:${EQ:-timeout 도구 없음 또는 30 s 초과}"; deadline
  echo "$EQ"
fi
EQM="$(printf '%s' "$EQ" | sed -n 's/.* mode=\([a-z]*\) overlap=\([0-9]*\).*/equiv=\1 overlap=\2/p')"   # R281: merge-gate.log·PR 코멘트에 «어느 경로로 같은 승인이 됐나»
M="$(G rev-parse --verify -q "refs/remotes/$REMOTE/$TARGET^{commit}")" || rej "main 확인 실패"; [ -n "$AP" ] || { DOCX="$(fm_doc_exempt "$AST" "$REPO" "$ROOT" "$M" "$S")" || rej "승인 파일 없음 · $DOCX"; }   # R725: 승인 값이 없을 때만 문서 전용 예외(실패 = 면제 0)
[ ! -f "$HERE/ft-team-lib.sh" ] || OLDP="$(. "$HERE/ft-team-lib.sh" && ft_old_form_added "$REPO" "$M" "$S")" || rej "$OLDP"   # r447: 명단 새 꼴 팀의 옛 꼴 위치에 새 파일 = 착지 0
EVL="$(G diff --name-only -z --no-renames --diff-filter=AM "$M...$S" -- design | tr '\0' '\n' | ft_evidence_filter)"   # r449: 가지가 더하거나 고친 design/ 증거 로그 = 착지 0(pre-commit 을 우회한 커밋도 여기서 선다)
[ -z "$EVL" ] || rej "증거 로그 $(printf '%s\n' "$EVL" | grep -c .) — git rm --cached 뒤 다시: $(printf '%s\n' "$EVL" | head -n 10 | tr '\n' ' ')"
if [ -n "$FF" ]; then   # R392: 가지가 이미 원격에 있으면 squash Q 의 트리·블롭 전부를 다시 보낸다(have 가 edge 아님 · #1927 675 MB) — ref 만 S 로 전진
  G merge-base --is-ancestor "$M" "$S" || rej "main($M) 이 head 의 조상이 아님 — ff 불가 · --ff 빼고 squash 또는 최신화"
  Q="$S"; PBO="0 $(fm_push_calc 0)"
else
MSG="$(printf '%s\n\n%s\n\nPR #%s (head %s)' "$(pf title)" "$(pf body)" "$PR" "$S")"
Q="$(G commit-tree "$S^{tree}" -p "$M" -m "$MSG")" || rej "commit-tree 실패"
[ "$(G rev-parse "$Q^{tree}")" = "$(G rev-parse "$S^{tree}")" ] && G merge-base --is-ancestor "$M" "$S" || rej "착지 후보 tree != 검사 tree 이거나 검사한 head 가 착지 부모 main($M)을 품지 않음 — 검사 뒤 main 이 움직였다(다시 최신화)"   # R247 DA⑥ HOLD2-①: 부모 M 이 S 의 조상이어야 «검사한 트리 == main 위에 놓이는 트리»(M ⊂ Q 는 항상 참이라 무의미했음)
PBO="$(fm_push_bound "$REPO" "$M" "$Q")"
fi
[ ! -f "$HERE/ft-bg-loop-lint.sh" ] || BLO="$(bash "$HERE/ft-bg-loop-lint.sh" --range "$M..$S" --repo "$REPO")" || rej "$(printf '%s' "$BLO" | head -3 | tr '\n' ' ')"   # r448: 가지가 추가·수정한 design/·tests/e2e/ *.sh 의 while+sleep+>> 루프가 ft-bg-loop.sh 래퍼 밖 = 착지 0

TB="$(fm_timeout_bin)" || rej "timeout 도구 없음"
PN="${PBO% *}"; PB="${PBO#* }"; PV="$(fm_push_calc '?' 2>/dev/null)"   # R354: PB = 크기 비례로 «계산한 최대 시도 시간» · AB = 그 시도에 실제로 건 상한 min(PB, 남은 시간) · PV = 최소 1단위(F+7)
LANDVIA=""
for i in 1 2; do
  deadline; REM=$((LIM - (SECONDS - T0))); NEED="$PV"; [ "$i" -eq 1 ] || NEED="$PB"   # R247 DA⑥ HOLD2-② 를 AB 기준으로 재정의: 1차는 남은 시간 ≥ 1단위(F+7)면 AB=min(PB,남은 시간) 으로 시작 · 재시도는 남은 시간 ≥ PB — 총 마감 70 s 불변. 한계: 남은 11 s · PB 70 이면 11 s 한 번만 시도 · timeout 이면 재시도 0(다음 틱)
  [ "$REM" -ge "$NEED" ] || rej "총 마감 $LIM s 안에 push 를 끝낼 수 없음(남은 ${REM}s < push 상한 ${NEED}s — 재시도 0 · 다음 틱)"
  AB=$((PB < REM ? PB : REM)); PS=$SECONDS
  POUT="$("$TB" "$AB" git -C "$REPO" push "$REMOTE" "$Q:refs/heads/$TARGET" 2>&1)"; PRC=$?
  [ "$PRC" -eq 0 ] && break
  printf '%s' "$POUT" | grep -qE 'rejected|non-fast-forward|fetch first|stale info' && rej "서버가 non-FF 로 거절 — 검사 뒤 main 이 움직였다(트리 어긋남 방지 · 다시 최신화): $(pushwhy)"
  # R354 DA⑥ H1: 재시도 = «서버 응답 전» 이 보이는 실패뿐(remote 출력 0 + 연결 실패 문자열 + timeout 아님). timeout·reset·remote 출력이 있는 실패는 «불명» — 자동 재시도 0, 원격 ref 를 1회 읽어 가른다
  RESP=0; printf '%s' "$POUT" | grep -qE '^remote:|^To ' && RESP=1
  if [ "$i" -eq 1 ] && [ "$PRC" -ne 124 ] && [ "$PRC" -ne 143 ] && [ "$RESP" = 0 ] && printf '%s' "$POUT" | grep -qiE 'could not resolve host|connection (timed out|refused)|ssh: connect to host|network is unreachable'; then continue; fi
  { [ "$PRC" -eq 124 ] || [ "$PRC" -eq 143 ] || [ "$RESP" = 1 ] || printf '%s' "$POUT" | grep -qiE 'connection (reset|closed)|hung up unexpectedly|early eof'; } \
    || rej "push 실패(rc=$PRC · 재시도 조건 = 서버 응답 전 연결 실패 1회뿐): $(pushwhy)"
  LSO="$("$TB" 7 git -C "$REPO" ls-remote "$REMOTE" "refs/heads/$TARGET" 2>&1)"; lrc=$?; LSV="${LSO%%[[:space:]]*}"   # 실패 경로 진단 1회(읽기 전용 · 7 s)
  if [ "$lrc" -eq 0 ] && [ "$LSV" = "$Q" ]; then LANDVIA="ls-remote"; break
  elif [ "$lrc" -eq 0 ] && [ "$LSV" = "$M" ]; then rej "착지 0 확정(원격 $TARGET = $M) · push 응답 불명(rc=$PRC) · 재시도 0 — 총 마감 안에 끝내지 못함 · 다음 틱에 다시"
  else rej "원격 상태 불명 · 손 확인 필요(push rc=$PRC · ls-remote rc=$lrc 값=${LSO:0:80})"; fi
done
mkdir -p "$STATE" && printf '%s repo=%s main=%s head=%s method=ft-merge-land%s tree=%s landed=%s pr=%s approve=%s%s approve-file=%s%s%s%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$(basename "${SLUG:-$ROOT}")" "$M" "$S" "${FF:+-ff}" "$(G rev-parse "$S^{tree}")" "$Q" "$PR" "$AP" "${EQM:+ $EQM}" "${AFE:-}" "${LANDVIA:+ push-confirmed=ls-remote}" "${DOCX:+ $DOCX}" "$([ "${AFV:-}" != D1 ] || printf ' standing=D1')" >>"$STATE/merge-gate.log"   # r947: 상시 승인 착지만 끝에 standing=D1
echo "LANDED pr=$PR sha=$Q main_before=$M head=$S tree=$(G rev-parse "$Q^{tree}")${FF:+ mode=ff}"
echo "push ok objects=$PN bound=$PB attempt=$AB took=$((SECONDS - PS))s${LANDVIA:+ confirmed=ls-remote(응답 후 timeout)}"   # R354: 착지마다 1줄 — bound=계산 최대 · attempt=실제 상한 · took=마지막 시도 소요 · 3건 모이면 기준량 U0 갱신 근거
SN="$(awk -v ap="$AP" '$1=="scope-use" && $3==ap && $2 ~ /^S[0-9]+$/ {s=$2} END{print s}' "$STATE/autonomy.log" 2>/dev/null)"   # R298(DA⑥ H3): 그 승인 sha 의 «마지막 scope-use S<n>» 한 원장만 — 줄 없으면 0
DL=""; [ "${AFV:-}" != D1 ] || DL="$AST/autonomy-standing/D1.ledger.tsv"; for LF in "$STATE/autonomy-scope/${SN:-none}.ledger.tsv" ${DL:+"$DL"}; do   # r947: 승인 줄 이벤트 D1(상시 승인) = D1 원장도 같은 칸(6·7)에 · R298: 그 원장의 «착지 sha 칸이 빈 행»(승인 sha == AP)에 Q·되돌림 명령 기록 — 실패해도 착지 rc 불변
  [ -f "$LF" ] || continue
  awk -F'\t' -v OFS='\t' -v ap="$AP" -v q="$Q" '$2==ap && $6=="" {$6=q; $7="git revert --no-edit " q; n++} {print} END{exit n?0:3}' "$LF" 2>/dev/null > "$LF.$$"; arc=$?
  if [ "$arc" -eq 0 ]; then mv -f "$LF.$$" "$LF" 2>/dev/null || { rm -f "$LF.$$"; echo "WARN 대리 승인 원장 기록 실패($LF) — 착지는 성공 · 손으로: git revert --no-edit $Q"; }
  else rm -f "$LF.$$"; [ "$arc" -eq 3 ] || echo "WARN 대리 승인 원장 기록 실패($LF) — 착지는 성공 · 손으로: git revert --no-edit $Q"; fi
done
fm_flag_off_new "$REPO" "$M" "$Q"   # R239: 이 착지가 새로 만든 «꺼진 플래그 = 결정 1건» 을 출력만(착지 rc 불변)
# R243: 착지 성공 «뒤»에만 기준 헤드를 Q 로 원자 교체(옛 값이 Q 의 조상일 때만 전진) + 뒤처진 팀 알림(실패해도 착지 rc 불변)
OLD="$(head -n1 "$BH" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$OLD" ] || G merge-base --is-ancestor "$OLD" "$Q" 2>/dev/null; then
  { mkdir -p "$(dirname "$BH")" && printf '%s\n' "$Q" > "$BH.$$" && mv -f "$BH.$$" "$BH"; } || echo "WARN 기준 헤드 갱신 실패($BH) — 손으로 기록"
fi
FT_ROOT="$ROOT" bash "$HERE/ft-head-lag.sh" --event --repo "$REPO" --base "$REMOTE/$TARGET" || echo "WARN ft-head-lag --event 실패(rc=$?) — 착지는 성공"
# R245 병합 ≠ 끝: 착지 «뒤»에 키트→라이브 설치 대조 — 출력·기록만(판정 0). 어긋남·오류·시간 초과여도 착지 rc·LANDED 줄 불변. 대기 기록 = state/install-pending/<Q>.txt
ITO="${FT_INSTALL_CHECK_TIMEOUT:-7}"; IOUT="$("$TB" "$ITO" bash "${FT_INSTALL_CHECK:-$HERE/ft-live-install-check.sh}" --range "$M..$Q" --ref "$Q" --repo "$REPO" 2>&1)"; irc=$?
if [ "$irc" -eq 124 ] || [ "$irc" -eq 143 ]; then echo "INSTALL-PENDING 설치 검사 ${ITO}초 초과 — 손으로: ft-live-install-check.sh --range $M..$Q"; IOUT="INSTALL-PENDING 검사 시간 초과"
else printf '%s\n' "$IOUT" | sed 's/^/INSTALL /'; fi
[ "$irc" -eq 0 ] || { mkdir -p "$ROOT/.fable-team/state/install-pending" && printf '%s\n' "$IOUT" > "$ROOT/.fable-team/state/install-pending/$Q.txt"; } || echo "WARN install-pending 기록 실패"
CB="$(mktemp)"; trap 'rm -f "$CB"' EXIT   # R261: ft-gh-as-tank.sh 는 하이픈 동사 + 본문 «파일» + --apply(없으면 dry-run) · pr-close --comment 한 번이 코멘트+닫기
printf '%s\n' "착지 sha $Q (ft-merge-land · 검사 트리 == 착지 트리 · 판정 1875)${EQ:+ · 동일승인 대조 EQUIV (${AP:0:10}→${S:0:10} · 판정 1917${EQM:+ · $EQM})}" > "$CB"
fm_t7 ${SLUG:+env FT_ISSUE_REPO="$SLUG"} "$GH_W" pr-close "$PR" --comment "$CB" --apply \
  || { echo "WARN 착지는 성공 — PR #$PR 코멘트/닫기 실패: 손으로 처리(착지 sha $Q)"; exit 3; }
