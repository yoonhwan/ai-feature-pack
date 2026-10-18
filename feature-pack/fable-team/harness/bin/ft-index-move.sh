#!/usr/bin/env bash
# ft-index-move.sh <indices/<from>/X.md> <대기|진행|완성> [--da <판정문경로#§N>] [--seat <좌석명>] [--landed <sha>]
#   Seatbelt 0.3 · 인덱스 상태 = 폴더. «닫힘» 글자를 손으로 쓸 자리를 없앤다.
#   exit 0 = 이동 · 1 = REJECT · 2 = usage
# 규칙:
#   대기→진행 : lint 통과 + --seat 필수(누가 들고 가는지). §상태 에 한 줄 append.
#   진행→완성 : --da 필수. 판정문 파일이 실재하고 그 §N 절(§N 정확 일치)에 「닫힘」 또는 「CLOSE」 + 카드 이름이 있어야 한다.
#               정본 갱신 카드는 --landed <S|T..S> 필수(랜딩 commit 사실 검사 — ft-index-move-canon.sh).
#               정본 줄 세 꼴 중 하나: 「정본 갱신: docs/architect/….md §절」 · 「정본화: <경로>[, …]」(허용 뿌리 4곳 · R318a) · 「정본 영향 없음: <이유>」.
#               하네스 카드는 `- 설치: 있음|없음` 필수 · 있음 = 라이브 설치 대조 OK + `- 실사건:` 증거(ft-index-move-install.sh · R245).
#               (DA 가 안 쓴 「닫힘」은 없다 — pm·master 가 대신 쓸 길을 두지 않는다.)
#   기타 방향 : 되돌리기(진행→대기 등)는 --seat 로 사유만 남기고 허용.
#   슬랙(판정 405) : 카드에 `- 슬랙:` 줄이 있으면 이동 «전»에 대기→진행=착수 답글 · 진행→완성=결과 답글 확인/발송.
#               도구 = env FT_THREAD_POST(기본 ~/.hermes/scripts/byz_thread_post.py) · 실패·장부 불명·도구 없음 = REJECT(이동 0 · 폴백 0).
set -uo pipefail
SRC="${1:-}"; DST="${2:-}"; shift 2 2>/dev/null || { echo "usage: $0 <index.md> <대기|진행|완성> [--da <file#§N>] [--seat <name>] [--landed <sha>]" >&2; exit 2; }
DA=""; SEAT=""; LANDED=""
while [ $# -gt 0 ]; do case "$1" in --da) DA="$2"; shift 2;; --seat) SEAT="$2"; shift 2;; --landed) LANDED="$2"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$DST" in 대기|진행|완성) ;; *) echo "REJECT dst 는 대기|진행|완성" >&2; exit 2;; esac
[ -f "$SRC" ] || { echo "REJECT 없음: $SRC"; exit 1; }
SRC="$(cd -- "$(dirname -- "$SRC")" && pwd)/$(basename -- "$SRC")"   # 절대경로 — 상대경로면 아래 git -C ls-files 추적 판정이 untracked 로 떨어져 mv 가 된다(DA r1 R5)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
IDX_ROOT="$(cd "$(dirname "$SRC")/.." && pwd)"
FROM="$(basename "$(dirname "$SRC")")"
[ "$FROM" != "$DST" ] || { echo "REJECT 이미 $DST 에 있다"; exit 1; }
if [ "$DST" = 진행 ]; then
  [ -f "$HERE/ft-index-lint.sh" ] || { echo "REJECT ft-index-lint.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  bash "$HERE/ft-index-lint.sh" "$SRC" || { echo "REJECT lint 실패 — 위 사유"; exit 1; }
  [ -n "$SEAT" ] || { echo "REJECT 대기→진행 은 --seat <좌석명> 필수"; exit 1; }
fi
if [ "$DST" = 완성 ]; then
  [ -n "$DA" ] || { echo "REJECT 진행→완성 은 --da <판정문#§N> 필수 — DA 판정 없이 닫지 않는다"; exit 1; }
  DAF="${DA%%#*}"; SEC="${DA#*#}"
  [ -f "$DAF" ] || { echo "REJECT DA 판정문 없음: $DAF"; exit 1; }
  # §N 절 = `## ` 헤더 안 §N 정확 일치(뒤가 숫자가 아님 — §5 가 §57 에 안 걸림, R37) · § 없는 절 이름은 포함 비교
  body="$(awk -v s="$SEC" 'index($0,"## ")==1{f=0; r=$0; while((i=index(r,s))>0){n=substr(r,i+length(s),1); if(index(s,"§")==0||n!~/[0-9]/){f=1;break}; r=substr(r,i+length(s))} if(f){print;next}} f' "$DAF")"
  [ -n "$body" ] || { echo "REJECT $DAF 에 절 «${SEC}» 없음"; exit 1; }
  printf '%s' "$body" | grep -qE '닫힘|CLOSE' || { echo "REJECT $DAF $SEC 에 「닫힘」/「CLOSE」 없음 — DA 가 닫지 않았다"; exit 1; }
  # R387 판정 2282 부모 완성 게이트 — ①리서치 좌석마다 `- 리서치 닫힘:` 줄(opencode = left=0 · Fable = kill rc=0) + tmux 에 그 세션 0 ②DA 보류 사건 ≥ 2 인데 유효한 재설계 해제 0 이면 완성 이동 거절(판정기 하나 = ft_da_hold_gate.py)
  while IFS= read -r _rs; do _rseat="${_rs%% *}"; [ -n "$_rseat" ] || continue
    grep -F -- "- 리서치 닫힘: $_rseat " "$SRC" | grep -qE 'left=0|kill rc=0' || { echo "REJECT 리서치 좌석 열림 $_rseat — 카드에 «- 리서치 닫힘: $_rseat <시각> left=0|kill rc=0» 줄 없음(ft-nano-close 출력 복붙 · 이동 0)"; exit 1; }
    ! tmux has-session -t "=$_rseat" 2>/dev/null || { echo "REJECT 리서치 좌석 열림 $_rseat — tmux 세션이 아직 있다(이동 0)"; exit 1; }
  done < <(sed -n 's/^- 리서치: \([^ ]*\) base=.*$/\1/p' "$SRC")
  [ -f "$HERE/ft_da_hold_gate.py" ] || { echo "REJECT ft_da_hold_gate.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _hg="$(python3 "$HERE/ft_da_hold_gate.py" "$SRC" --closing 2>&1)" || { echo "REJECT DA 보류 2회 — 상위 master·planner 의 «[재설계 해제 <카드>.md]» 쪽지 + 카드 «- 재설계 해제: #seq» 줄 없이 완성 이동 못 한다(이동 0): ${_hg%%$'\n'*}"; exit 1; }
  CARDID="$(basename "$SRC" .md)"
  printf '%s' "$body" | grep -Fq -- "$CARDID" || { echo "REJECT $DA 은 $CARDID 를 닫은 절이 아니다(절에 카드 이름 없음) — 그 판정 절에 「대상 카드: ${CARDID}」 줄을 넣고 다시. 이동 0"; exit 1; }
  # 정본 게이트 + 랜딩 commit 사실 검사(ft-index-move-canon.sh · 판정 440 r2 §6-1) — 이동 «전»에 검사한다.
  WT="$(git -C "$IDX_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$IDX_ROOT")"
  CANON_RES="$(printf '%s\n' "$body" | bash "$HERE/ft-index-move-canon.sh" "$SRC" "$WT" "$LANDED")"
  CANON_KIND="$(printf '%s' "$CANON_RES" | cut -f1)"; CANON_NOTE="$(printf '%s' "$CANON_RES" | cut -f2-)"
  case "$CANON_KIND" in
    OK) ;;
    REJECT) echo "REJECT 정본 게이트 — $CANON_NOTE (이동 0 · 카드에 줄을 쓰고 다시 이동)"; exit 1;;
    *) echo "REJECT 정본 게이트 검사 실행 실패 — 이동 0"; exit 1;;
  esac
  # r106b — 규칙 줄 검사: 규칙은 «읽히는 곳(상시 로드 지침)» + «막는 곳(훅·게이트)» 이 실재해야 닫는다(R83→R106 재발 차단).
  RUSE="쓰는 법: 「- 규칙: 지침=<상시 로드 파일>[:줄] · 강제=<훅·게이트 파일>」 또는 「- 규칙: 없음 — <사유 10자 이상>」 (구분자 = 공백 em dash 공백)"
  RLINE="$(grep -m1 '^- 규칙:' "$SRC")"
  [ -n "$RLINE" ] || { echo "REJECT 카드에 「- 규칙:」 줄 없음 — $RUSE (이동 0)"; exit 1; }
  RNONE='^- 규칙: 없음 — (.+)$'; RPATH='^- 규칙: 지침=([^[:space:]]+) · 강제=([^[:space:]]+)$'   # 정확한 두 형식만 — 접두 «없음» 면제 없음
  if [[ "$RLINE" =~ $RNONE ]]; then
    [ "$(python3 -c 'import sys; print(len(sys.argv[1]))' "${BASH_REMATCH[1]}")" -ge 10 ] || { echo "REJECT 「- 규칙:」 줄 형식 틀림 — 「없음 — 사유」 사유가 10자 미만 — $RUSE (이동 0)"; exit 1; }
  elif [[ "$RLINE" =~ $RPATH ]]; then
    RG="${BASH_REMATCH[1]%%:[0-9]*}"; RF="${BASH_REMATCH[2]}"; RG="${RG/#\~/$HOME}"; RF="${RF/#\~/$HOME}"
    case "$RG" in /*) ;; *) RG="$WT/$RG";; esac; case "$RF" in /*) ;; *) RF="$WT/$RF";; esac
    [ -f "$RG" ] || { echo "REJECT 「- 규칙:」 지침 경로 실재 0 — $RUSE (이동 0)"; exit 1; }
    [ -f "$RF" ] || { echo "REJECT 「- 규칙:」 강제(훅·게이트) 경로 실재 0 — $RUSE (이동 0)"; exit 1; }
    case "$RG" in *..*) RG="";; "$HOME/.claude/CLAUDE.md"|"$WT/CLAUDE.md"|"$WT/.claude/rules/"*.md|"$HOME/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md"|"$HOME/.claude/skills/fable-team/references/main-team-governance.md") ;; *) RG="";; esac
    [ -n "$RG" ] || { echo "REJECT 「- 규칙:」 지침이 상시 로드 파일 5종 밖 — 전역·프로젝트 CLAUDE.md · .claude/rules/*.md · COMM-GUIDE-BOOT · main-team-governance 중 하나 (이동 0)"; exit 1; }
  else
    echo "REJECT 「- 규칙:」 줄 형식 틀림 — $RUSE (이동 0)"; exit 1
  fi
  # R245 병합 ≠ 끝 — 하네스 카드 설치 게이트(ft-index-move-install.sh · 설치: 있음 = 라이브 cmp0 + 실사건 증거). 다른 팀 indices 는 게이트 안에서 통과.
  bash "$HERE/ft-index-move-install.sh" "$SRC" ${LANDED:+--landed "$LANDED"} || exit 1
fi
# 슬랙 단위 스레드(판정 405 §4) — «게시 대상» = 카드의 `- 슬랙:` 줄 유무(장부 아님). 이동 «전»에 끝낸다: 실패면 이동 0.
if { [ "$FROM" = 대기 ] && [ "$DST" = 진행 ]; } || { [ "$FROM" = 진행 ] && [ "$DST" = 완성 ]; }; then
  if grep -q '^- 슬랙:' "$SRC"; then
    TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
    [ -f "$TP" ] || { echo "REJECT 카드에 「- 슬랙:」 줄이 있는데 발행 도구가 없다: $TP (FT_THREAD_POST) — 이동 0"; exit 1; }
    tp() { if [ -x "$TP" ]; then "$TP" "$@"; else python3 "$TP" "$@"; fi; }
    S_ISSUE="$(sed -n 's/^- Issue:[[:space:]]*//p' "$SRC" | head -1 | awk '{print $1}')"; S_ISSUE="${S_ISSUE:-없음}"
    S_SEAT="${SEAT:-없음}"; S_CANON=없음
    case "${CANON_NOTE:-}" in 정본\ docs/architect/*) S_CANON="$WT/$(printf '%s' "$CANON_NOTE" | awk '{print $2}')";; esac
    S_BLK=(--issue "$S_ISSUE" --seat "$S_SEAT" --canon "$S_CANON" --resume-script "$HERE/ft-resume-cmd.sh")
    if [ "$DST" = 진행 ]; then
      out="$(tp progress --card "$SRC" --text "착수 — ${SEAT:-좌석 미지정}" --next "구현·완료 조건 확인" "${S_BLK[@]}" 2>&1)" \
        || { echo "REJECT 슬랙 착수 답글 실패 — 이동 0: $out"; exit 1; }
    else
      tp check --card "$SRC" >/dev/null 2>&1; rc=$?
      case "$rc" in
        0) ;;
        1) out="$(tp result --card "$SRC" --verdict "$DA" ${LANDED:+--landed "${LANDED##*..}"} --next "없음" "${S_BLK[@]}" 2>&1)" \
             || { echo "REJECT 슬랙 결과 답글 실패 — 이동 0: $out"; exit 1; };;
        3) echo "REJECT 장부 복구 필요 — byz_thread_post.py repair --card $SRC (이동 0)"; exit 1;;
        *) echo "REJECT 슬랙 장부 확인 실패 rc=$rc — 이동 0"; exit 1;;
      esac
    fi
  fi
fi
# R63 ㉡ — 카드가 인용한 증거·시험 경로의 측정 조작 흔적(임의 Redis 쓰기·말풍선 DOM 주입)을 «보이게» 한다. 출력만 — 이동 종료코드·REJECT 불변.
if [ "$FROM" = 진행 ] && [ "$DST" = 완성 ]; then
  SCAN_PATHS=(); while IFS= read -r p; do
    case "$p" in *ft-evidence-inject-scan.sh|tests/harness/test_evidence_inject_scan.sh|tests/harness/test_block_destructive_inject.sh) continue;; esac  # 패턴 글자를 정의·시험하는 파일 — 늘 SUSPECT
    { [ -f "$WT/$p" ] || { [ -d "$WT/$p" ] && [[ "$p" =~ ^design/.+/evidence/[^/]+/?$ ]]; }; } && SCAN_PATHS+=("$WT/$p")  # 파일은 그대로 · 폴더는 증거 폴더 «하나»만
  done < <(grep -oE '[A-Za-z0-9_./-]+' "$SRC" | grep -E '^design/.*/evidence/|^tests/|\.(py|sh)$' | sort -u)
  if [ "${#SCAN_PATHS[@]}" -gt 0 ]; then bash "$HERE/ft-evidence-inject-scan.sh" "${SCAN_PATHS[@]}" || echo "ERROR inject-scan rc=$?" >&2; fi
fi
mkdir -p "$IDX_ROOT/$DST"
NEW="$IDX_ROOT/$DST/$(basename "$SRC")"
TRACKED=0; git -C "$IDX_ROOT" ls-files --error-unmatch "$SRC" >/dev/null 2>&1 && TRACKED=1
if [ "$TRACKED" = 1 ]; then git mv "$SRC" "$NEW"; else mv "$SRC" "$NEW"; fi || { echo "REJECT 이동 실패: $SRC → $NEW"; exit 1; }
if [ "$DST" = 완성 ]; then
  # 하네스 0.5 행 3 — «완성 이동»이 원장 close 의 유일한 기록자. 원장 없는 완성은 없다(#0 RULE).
  #   트랙 = FT_TRACK(기본 default · 카드가 design/v65/indices 아래면 v65) · $ROOT/STATE_DIR 은 ft-index-gate.sh 와 같은 규약.
  ROOT="$(git -C "$IDX_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  STATE_DIR="${FT_INDEX_STATE_DIR:-$ROOT/.fable-team/state}"
  TRACK="${FT_TRACK:-}"
  if [ -z "$TRACK" ]; then   # R383: v65 카드 판정 = 팀 폴더 명단(ft_team_has · 쌍둥이 둘 다) · 명단을 못 읽으면(rc2) default 로 후퇴하지 않고 REJECT
    . "$HERE/ft-team-lib.sh" || { echo "REJECT ft-team-lib.sh 를 못 읽었다: $HERE"; exit 1; }
    FT_REPO_ROOT="$(git -C "$IDX_ROOT" rev-parse --show-toplevel 2>/dev/null)" ft_team_has v65 "$IDX_ROOT/" indices/; _hrc=$?   # 명단은 카드가 있는 워크트리의 것(워크트리마다 이동 상태가 다르다)
    case "$_hrc" in 0) TRACK=v65;; 1) TRACK=default;; *) echo "REJECT v65 팀 폴더를 못 풀었다(design/TEAMS.md) — 트랙을 못 정한다: FT_TRACK 을 주거나 명단을 고친다"; exit 1;; esac
  fi
  LEDGER="$STATE_DIR/index-ledger.$TRACK.jsonl"
  ID="$(basename "$SRC" .md)"
  row="{\"ts\":\"$(date '+%Y-%m-%dT%H:%M:%S%z')\",\"ev\":\"close\",\"id\":\"$ID\",\"da\":\"$DA\",\"seat\":\"${SEAT:--}\",\"via\":\"index-move\"}"
  if ! printf '%s\n' "$row" >> "$LEDGER" 2>/dev/null; then
    # 되돌리기도 실패할 수 있다(DA r1 R1) — 성공 문구는 되돌리기가 «실제로» 성공했을 때만.
    if { [ "$TRACKED" = 1 ] && git mv "$NEW" "$SRC"; } || { [ "$TRACKED" != 1 ] && mv "$NEW" "$SRC"; }; then
      echo "REJECT 원장에 못 썼다: $LEDGER — 이동을 되돌렸다"; exit 1
    fi
    echo "REJECT 원장에 못 썼다: $LEDGER" >&2
    echo "★되돌리기 실패 — 카드 ${NEW} · 원장 0 · 복구: git mv ${NEW} ${SRC}★" >&2; exit 3
  fi
fi
printf -- '- %s — %s→%s%s%s\n' "$(date '+%Y-%m-%d %H:%M')" "$FROM" "$DST" "${SEAT:+ · 좌석 $SEAT}" "${DA:+ · DA $DA}" >> "$NEW"
printf 'MOVED %s→%s %s\n' "$FROM" "$DST" "$NEW"
if [ "$DST" = 완성 ]; then
  # 정본 갱신 신호 — 수신자 = 명부(env FT_SEATS_JSON 우선) 최상위 `_arch`(팀 현역 arch). 키 없음·빈 값 = 쪽지 0 + INFO 1줄.
  #   게이트 아님: 발신이 실패해도 이동은 이미 끝났고 exit 0 이다(경고 1줄만). 회복 경로 = CANON-DEBT 미반영 행.
  #   「정본 영향 없음:」 카드는 arch 가 할 일이 없으므로 쪽지 0 + INFO 1줄(R41) — 정본 쪽지는 정본을 고칠 때만 간다.
  case "${CANON_NOTE:-}" in
    정본\ 영향\ 없음:*) echo "INFO 정본 쪽지 생략 — 정본 영향 없음 카드"; exit 0 ;;
  esac
  SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
  ARCH="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("_arch",""); print(v if isinstance(v,str) else "")' "$SEATS" 2>/dev/null)"
  if [ -z "$ARCH" ]; then
    echo "INFO 정본 쪽지 생략 — 명부에 _arch 없음"
  elif ! bash "${FT_MBOX:-$ROOT/.fable-team/comm/mbox.sh}" send "$ARCH" "${SEAT:-ft-index-move}" "[정본 갱신 요청] ${NEW#"$ROOT"/} · DA $DA · ${CANON_NOTE:-}" >/dev/null 2>&1; then
    echo "WARN 정본 갱신 요청 발신 실패 → $ARCH (이동은 완료 · CANON-DEBT 에 «미반영» 행을 손으로 추가)"
  else
    echo "NOTIFIED 정본 갱신 요청 → $ARCH"
  fi
fi
