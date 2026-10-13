#!/usr/bin/env bash
# ft-nano-spawn.sh <indices/대기/X.md> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--raise "<사유>"] [--from <발주좌석>] [--recheck <판정문>] [--base <ref>] [--cherry-override "<사유>"] [--dry-run]
#   --raise "<사유>" = 상향 모델(claude-fable-*·*astra* · 판정 1641)을 열 때 필수 · 명부 행에 raised{reason,card,by,at,close_on} 를 남긴다(R149)
#   Seatbelt 0.3 · 나노 좌석을 «손타이핑 없이» 연다 (SEATBELT-README §3 열기).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인)
# 한 번에: ①lint ②워크트리+.venv/.env 심링크+.worktree-info.json ③tmuxc open(--agent/--model 통과, 기본 claude/opus-5.5)
#          ④remain-on-exit on + @zc_v65_active=1 ⑤seats.json 등록 ⑥인덱스 대기→진행 ⑦첫 발주(인덱스 경로 한 줄, mbox) ⑧도달 확인(jsonl)
# ★팩 ft-tmux-spawn.sh 미사용★: install.json canonical·CAPABILITY_GAP 게이트가 v65 워크트리에 없다(troubleshoot 09-06 「install.json 부재 = exit 4」) · 오빠 §0-A 「tmuxc 로 생성해서 어차피 쓰니 모델까지 지정가능」 — tmuxc 직접 호출.
set -uo pipefail
IDX="${1:-}"; shift || { echo "usage: $0 <indices/대기/X.md> [--agent A] [--model M] [--effort E] [--raise \"<사유>\"] [--from SEAT] [--base REF] [--cherry-override \"<사유>\"] [--dry-run]" >&2; exit 2; }
AGENT="claude"; MODEL=""; EFFORT="high"; FROM="${FT_SEND_FROM:-dispatch}"; DRY=0; FAST=""; TIER=""; RECHECK=""; BASE_REF=""; HAVE_CO=0; CO=""; RAISE=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; shift 2;; --raise) RAISE="${2:-}"; shift 2 2>/dev/null || shift;;
  --from) FROM="$2"; shift 2;; --recheck) RECHECK="$2"; shift 2;; --dry-run) DRY=1; shift;; --tier) TIER="$2"; shift 2;; --base) BASE_REF="$2"; shift 2;;
  --cherry-override) HAVE_CO=1; CO="${2:-}"; shift 2 2>/dev/null || shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
CO_ARGS=(); [ "$HAVE_CO" -eq 0 ] || { [ -n "${CO//[[:space:]]/}" ] || { echo "usage: --cherry-override \"<사유>\" — 사유가 비었다(사유 없는 우회 거부)" >&2; exit 2; }; CO_ARGS=(--override "$CO"); }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel)"                       # 호출 워크트리(기준 브랜치의 자리)
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
# ★팀 env 자동 로드 (카드 nano-spawn-close-team-env §1)★: FT_NANO_PREFIX 가 이미 있으면 «명시가 이긴다» — 아무것도 안 한다.
#   없으면 카드 경로 design/<팀>/indices/ 의 팀(v65 는 default)으로 $ROOT/.fable-team/bin-<팀>/<팀>-env.sh 를 source. 파일이 없으면 추측 없이 REJECT.
if [ -z "${FT_NANO_PREFIX:-}" ]; then
  _team=""; [[ "$IDX" =~ design/([a-z0-9]+)/indices/ ]] && [ "${BASH_REMATCH[1]}" != v65 ] && _team="${BASH_REMATCH[1]}"
  if [ -n "$_team" ]; then
    _tenv="$ROOT/.fable-team/bin-$_team/$_team-env.sh"
    [ -f "$_tenv" ] || { echo "REJECT 팀 env 없음: $_tenv"; exit 1; }
    . "$_tenv"
  fi
  echo "ENV team=${_team:-default} prefix=${FT_NANO_PREFIX:-ft-v65-temp-} seats=${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
fi
# ★라이브 bin 드리프트 입구 검사 (카드 live-bin-drift-check · Issue 816 ③)★: 설치 꼴(*/.fable-team/bin)에서 돌 때만 — 라이브 도구가 origin/main 키트와 다르면 열지 않는다(--dry-run 도 같다).
#   검사 스크립트가 없는 것도 드리프트(설치 누락) · 우회 스위치 없음 — 해결은 master 라이브 cp.
case "$HERE" in
  */.fable-team/bin|*/.fable-team/*/bin)
    if [ ! -f "$HERE/ft-live-bin-drift-check.sh" ]; then echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시 (ft-live-bin-drift-check.sh 설치 누락)"; exit 1; fi
    _dout="$(bash "$HERE/ft-live-bin-drift-check.sh" --bin "$HERE" --repo "$ROOT")" || { printf '%s\n' "$_dout"; echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시"; exit 1; }
    printf '%s\n' "$_dout";;
  *) echo "INFO drift-check 건너뜀 — 실행 위치가 설치 폴더 아님: $HERE";;
esac
# ★--tier checker|tester[:N] = 싼 모델 순위 (오빠 2026-09-14 확정 「zcode > cmd > luna > sonnet」 · README §5-1)★
#   N 생략 = 1순위. 한도·거부(usage_limit_reached·429·exit 10 크레딧)면 발주자가 :2 :3 :4 로 다음 순위. sonnet(4) 은 마지막.
#   zcode 슬러그는 설치마다 다르다 — FT_ZCODE_MODEL 로 준다(없으면 REJECT — 없는 모델을 지어내지 않는다).
# 2026-09-14 오빠 실측 정정 2회: 「zcode 구독 없네 제외」 → 「cmd 월제한이 18일날 풀린다.. cmd도 넘기자」 ⇒ 지금 순위 = luna > sonnet. cmd 는 FT_CMD_ENABLED=1 일 때만 1순위 복귀(월제한 해제 후 오빠가 켠다).
_cmd_on="${FT_CMD_ENABLED:-0}"
case "$TIER" in
  checker|tester|checker:1|tester:1)
    if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
    else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  checker:2|tester:2)
    if [ "$_cmd_on" = 1 ]; then AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";
    else AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5[1m]}"; EFFORT="high"; fi;;
  checker:3|tester:3)                AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5[1m]}"; EFFORT="high";;
  # impl = 구현 나노. 1순위 opus-5.5(기본값 — 오빠 2026-09-28 「나노워커 이후부터 opus5.5로 구현 · fable은 진짜 해결 안 되는 문제에만」 · fable 은 --model 명시로만), :2 luna (cmd 는 FT_CMD_ENABLED=1 일 때 :2 로 끼어듦)
  impl|impl:1) ;;
  impl:2) if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
          else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  impl:3) AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";;
  '') ;; *) echo "unknown --tier $TIER (checker|tester[:1-3] · impl[:1-3])" >&2; exit 2;;
esac
# 역할을 seats.json 에 남긴다 — 세션 상태 절·stall 대상 판정이 «checker/tester/impl» 을 가른다
ROLE="${TIER%%:*}"; ROLE="${ROLE:-nano}"
# --model 미지정(티어도 안 정함)이면 에이전트별 기본 — claude 는 FT_IMPL_MODEL, 그 밖은 모델을 지어내지 않고 정해진 것만(opencode 등은 REJECT)
if [ -z "$MODEL" ]; then case "$AGENT" in
  claude) MODEL="${FT_IMPL_MODEL:-claude-opus-5-5[1m]}";;
  codex)  MODEL="${FT_LUNA_MODEL:-gpt-6-luna}";;
  cmd)    MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}";;
  *) echo "REJECT --model 필수 (--agent $AGENT 는 기본 모델이 없다)"; exit 1;; esac
fi
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
[ -f "$IDX" ] || { echo "REJECT 인덱스 없음: $IDX"; exit 1; }
case "$IDX" in */대기/*) ;; *) echo "REJECT 대기/ 에 있는 인덱스만 연다: $IDX"; exit 1;; esac
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }
# 형제 도구는 설치 폴더에만 있다 — 원본 폴더에서 돌리면 lint 의 «파일 없음» 이 «lint 실패» 로, 첫 발주는 좌석을 연 «뒤» 에 죽는다. 열기 «전»에 거절한다(R134). --dry-run 은 송신 전(179행)에 끝나므로 send-verified 는 실전만.
for _sib in ft-index-lint.sh $([ "$DRY" = 1 ] || echo ft-send-verified.sh); do
  [ -f "$HERE/$_sib" ] || { echo "REJECT $_sib 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
done
# R149(판정 1641): 상향 모델은 사유 필수 — 해석이 끝난 실제 MODEL 로 판정하고 부작용(카드·원장·워크트리·tmux·명부) «전»에 거절한다. rc 0=상향 1=기본 그 밖=도구 고장(조용히 기본 취급 0)
python3 "$HERE/ft_raised.py" is-raised "$MODEL"; _rrc=$?
case "$_rrc" in
  0) [ -n "${RAISE//[[:space:]]/}" ] || { echo "REJECT 상향 모델($MODEL)은 --raise \"<사유>\" 필수 — 닫히면 원래 모델로(판정 1641)"; exit 1; };;
  1) ;;
  *) echo "REJECT ft_raised.py 판정 실패 rc=$_rrc ($HERE/ft_raised.py) — 부작용 0"; exit 1;;
esac

# ① lint — 누가 읽어도 착수 가능한가 (P2: planner 카드 머리 「- 템플릿: 빈 카드(나노가 채움)」 = lint ⑤⑥ 만 건너뜀 · 그 밖 팀·검사는 그대로)
_EBN=""; if [[ "$IDX" == *design/planner/indices/* ]] && awk '/^##[[:space:]]/{exit} {print}' "$IDX" | grep -q '^- 템플릿: 빈 카드(나노가 채움)'; then export FT_INDEX_ALLOW_EMPTY_BODY=1; _EBN=" ★빈 카드 템플릿: 카드 구현 범위·완료 조건 절을 네가 먼저 채우고 arch 1줄 확인 뒤 착수★"; else unset FT_INDEX_ALLOW_EMPTY_BODY; fi
bash "$HERE/ft-index-lint.sh" "$IDX" || { echo "REJECT lint 실패"; exit 1; }
# ①-0 제안서 «오빠가 본 승인» 게이트 (R77 · 판정 816 — 로직은 ft-proposal-gate.sh --card)
_pg="$(bash "$HERE/ft-proposal-gate.sh" --card "$IDX" 2>&1)" || { echo "REJECT 제안서 승인 증거 부족 — $_pg"; exit 1; }; echo "$_pg"
# ①a 머리줄 4줄(C6 · SPEC-roles P3-1) — 없으면 REJECT 가 아니라 «spawn 후보 제외» 경고(ft-nano-slots.sh 와 같은 검사 · 현행 동작 보존)
_hmiss="$(awk '/^##[[:space:]]/{exit} {print}' "$IDX" | python3 -c "
import re, sys
h = sys.stdin.read()
print(' '.join(k.replace(' ', '_') for k in ('Issue', '상태', '선행', '시험 입력') if not re.search(r'^\s*[-*]?\s*' + k + r':[ \t]*\S', h, re.M)))")"
[ -z "$_hmiss" ] || echo "WARN 후보 제외 — 카드 머리줄 없음: $_hmiss (REJECT 아님 · ft-nano-slots.sh 후보에서 빠진다): $IDX"
# ①a-2 기준값 머리줄(C20 · SPEC-github-issue-driven §12-1) — 없거나 빈칸이면 REJECT 가 아니라 «후보 제외» 경고(위 4줄 검사와 같은 방식 · 현행 동작 보존).
#   지표가 없으면 「없음 → 대체 축」 을 적어야 하며 빈칸은 안 된다(design/harness/BASELINE-TEMPLATE.md).
awk '/^##[[:space:]]/{exit} {print}' "$IDX" | grep -Eq '^[[:space:]]*[-*]?[[:space:]]*기준값:[[:space:]]*[^[:space:]]' \
  || echo "WARN 후보 제외 — 카드 머리줄 기준값 없음 또는 빈칸 (REJECT 아님 · 지표 없으면 「기준값: 없음 → 대체 축 <무엇>」 · design/harness/BASELINE-TEMPLATE.md): $IDX"

# ①b 카드 base_sha 대조 (M7 · single_set_testing §1 규칙 2 · 오빠 ORDERS 102): 09-25 카드를 10-02 코드에 재대조 없이 집행한 사고 차단.
#   카드 «## 상태» 에 `base_sha: <40-hex>` 가 없으면 첫 개설 = 현재 기준 브랜치 HEAD 를 써넣고 진행(REJECT 0).
#   있으면 재개·재spawn = base_sha..HEAD 사이에 카드 «## 구현 범위» 가 인용한 파일(경로 토큰 · `관련 파일:` 줄 포함 · 인용 0 이면 세트 경로 전체 worker/ gateway/ shared/ clients/web/src/ tests/e2e/ scripts/server/)이 바뀌었으면 REJECT.
#   통과 = `--recheck <판정문>` 이 실재하고 그 판정문이 «현재 HEAD sha»(7자 이상 접두)를 적고 있을 때만.
CUR_HEAD="$(git -C "$WT" rev-parse "${BASE_REF:-HEAD}^{commit}")" || { echo "REJECT 기준 ${BASE_REF:+ref(--base) }HEAD 조회 실패: ${BASE_REF:-HEAD}"; exit 1; }
CARD_BASE="$(grep -E '^[[:space:]-]*base_sha:[[:space:]]*[0-9a-f]{40}' "$IDX" | head -1 | grep -oE '[0-9a-f]{40}' | head -1)"
if [ -z "$CARD_BASE" ]; then
  STAMP_BASE=1
else
  STAMP_BASE=0
  _chg="$(python3 - "$IDX" "$WT" "$CARD_BASE" "$CUR_HEAD" <<'PY'
import re, subprocess, sys
card, repo, base, head = sys.argv[1:5]
txt = open(card, encoding="utf-8").read()
m = re.search(r"^##\s*구현 범위.*?(?=^##\s|\Z)", txt, re.S | re.M)
scope = m.group(0) if m else ""
cited = set(re.findall(r"[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+/?|[A-Za-z0-9_\-]+\.(?:sh|py|ts|tsx|js|json|md|yaml|yml)", scope))
for ln in txt.splitlines():
    if ln.strip().startswith("관련 파일:"):
        cited |= {t.strip() for t in re.split(r"[,\s]+", ln.split(":", 1)[1]) if t.strip()}
if not cited:
    cited = {"worker/", "gateway/", "shared/", "clients/web/src/", "tests/e2e/", "scripts/server/"}
out = subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", "diff", "--name-only", base, head], capture_output=True, text=True)
if out.returncode != 0:
    print("DIFFFAIL " + out.stderr.strip()[:120]); sys.exit(3)
hit = [p for p in out.stdout.splitlines() if any(p == c or p.startswith(c if c.endswith("/") else c + "/") or p.endswith("/" + c) for c in cited)]
if hit:
    n = subprocess.run(["git", "-C", repo, "rev-list", "--count", f"{base}..{head}"], capture_output=True, text=True).stdout.strip()
    print(f"CHANGED {n} " + " ".join(hit[:20]) + (f" … 외 {len(hit) - 20}개" if len(hit) > 20 else ""))
PY
)"; _crc=$?
  [ "$_crc" -eq 0 ] || { echo "REJECT 카드 base_sha 대조 실패(rc=$_crc): ${_chg:0:160}"; exit 1; }
  if [ -n "$_chg" ]; then
    _ok=0
    if [ -n "$RECHECK" ] && [ -f "$RECHECK" ]; then
      while read -r _t; do case "$CUR_HEAD" in "$_t"*) _ok=1; break;; esac; done < <(grep -oE '[0-9a-f]{7,40}' "$RECHECK" | sort -u)
    fi
    [ "$_ok" = 1 ] || { echo "REJECT 카드 base_sha ${CARD_BASE:0:9} 이후 feat HEAD ${CUR_HEAD:0:9} 사이에 카드가 인용한 파일이 바뀜 — 재대조 필요(arch 판정 뒤 --recheck <판정문>; 판정문에 현재 HEAD sha 를 적는다). 커밋 $(printf '%s' "$_chg" | cut -d' ' -f2)개 · 바뀐 파일: $(printf '%s' "$_chg" | cut -d' ' -f3-)"; exit 1; }
    echo "RECHECK 통과 — 판정문 $RECHECK 가 현재 HEAD ${CUR_HEAD:0:9} 를 적음(바뀐 파일: $(printf '%s' "$_chg" | cut -d' ' -f3-))"
  fi
fi

SLUG="$(basename "$IDX" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-40)"
BASE_NAME="${FT_NANO_PREFIX:-ft-v65-temp-}$SLUG"
N=0; while tmux has-session -t "=$BASE_NAME#$N" 2>/dev/null; do N=$((N+1)); done
NAME="$BASE_NAME#$N"
BRANCH="nano/$SLUG"; WTDIR="$ROOT/.worktrees/${FT_NANO_WT_PREFIX:-v65-}$SLUG"
BASE_BRANCH="${BASE_REF:-$(git -C "$WT" rev-parse --abbrev-ref HEAD)}"
# R42: --base 가 ref 가 아니고 commit(sha)이면 info 에는 «랜딩 브랜치» 를 쓴다(닫기 게이트의 비교 기준) — sha 는 base_sha 칸.
INFO_BASE="$BASE_BRANCH"
if [ -n "${BASE_REF:-}" ] && ! git -C "$ROOT" rev-parse --verify -q "refs/heads/$BASE_REF" >/dev/null \
   && ! git -C "$ROOT" rev-parse --verify -q "refs/remotes/$BASE_REF" >/dev/null \
   && git -C "$ROOT" rev-parse --verify -q "$BASE_REF^{commit}" >/dev/null; then
  INFO_BASE="${FT_NANO_FEAT:-$(git -C "$WT" rev-parse --abbrev-ref HEAD)}"
fi
IDX_ABS="$(cd "$(dirname "$IDX")" && pwd)/$(basename "$IDX")"
IDX_REL="${IDX_ABS#"$WT"/}"

# ②-0 옛 nano 브랜치 충돌 (M7 · 10-02 슬러그 충돌 5회) — 나노 닫기는 워크트리만 지우고 브랜치는 보존한다(09-25 승인).
#   워크트리 없음 ∧ 브랜치 실재 → 그 브랜치를 cherry 게이트로 판정. 반입이면 -r2, -r3 … 후보마다 브랜치가 있으면 «워크트리 유무와
#   무관하게» 같은 판정(DA⑥ 53519 H1 — 살아 있는 -rN 워크트리도 미반입이면 재사용 0). 반입 + 워크트리 있음 = 재사용 · 브랜치 없음 = 새로.
#   미반입이면 REJECT — 옛 브랜치·워크트리 삭제·덮기·재사용 0(판정은 arch). base 워크트리 재발주 재사용(아래 ②)은 그대로.
#   ①b 카드 base_sha 기록보다 «앞» 이라 REJECT 면 카드 파일도 안 건드린다.
if [ ! -d "$WTDIR" ] && git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; then
  WT_BASE="$WTDIR"; R=1
  while git -C "$ROOT" rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null; do
    # R71: --base 가 sha 면 게이트는 랜딩 브랜치(INFO_BASE · R42)와 비교 — sha 를 넘기면 게이트가 «브랜치 없음» 으로 막는다
    gate="$( [ "$HAVE_CO" -eq 0 ] || export FT_SEAT="$FROM"   # R70: 원장 seat 칸 = 발주자(서브셸 안만)
             bash "$HERE/ft-nano-cherry-gate.sh" "$INFO_BASE" "$BRANCH" --repo "$ROOT" ${CO_ARGS[@]+"${CO_ARGS[@]}"} )" \
      || { echo "REJECT 옛 브랜치 미반입 — $BRANCH (삭제·덮기·재사용 0 · 판정 arch):"; printf '%s\n' "$gate"; exit 1; }
    echo "old_branch=$BRANCH landed=yes gate=${gate%% *}"
    [ -d "$WTDIR" ] && break
    R=$((R+1)); BRANCH="nano/$SLUG-r$R"; WTDIR="$WT_BASE-r$R"
  done
fi

# tmuxc 옵션은 에이전트별로 다르다 — `--ctx` 는 claude 만, `--effort` 는 claude·cmd·codex, `--fast` 는 codex 만 (ft-role-spawn 과 같은 분기)
OPEN=(tmuxc open "$WTDIR" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && OPEN+=(--ctx 1m)
case "$AGENT" in claude|cmd|codex) OPEN+=(--effort "$EFFORT");; esac
[ "$AGENT" = codex ] && [ -n "$FAST" ] && OPEN+=(--fast "$FAST")
echo "PLAN seat=$NAME agent=$AGENT model=$MODEL${TIER:+ tier=$TIER}${FAST:+ fast=$FAST} wt=$WTDIR branch=$BRANCH base=$BASE_BRANCH index=$IDX_REL"
# R81 ⓐ 슬랙 장부 사전 확인 — 카드에 「- 슬랙:」 줄이 있으면 부작용 «전»에 check(dry-run 도 같다): rc 0·1 통과 · 3 = 장부 불명 · 그 밖·도구 없음 = REJECT
if grep -q '^- 슬랙:' "$IDX"; then _TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
  if [ -f "$_TP" ]; then if [ -x "$_TP" ]; then "$_TP" check --card "$IDX"; else python3 "$_TP" check --card "$IDX"; fi >/dev/null 2>&1; _src=$?; else _src=127; fi
  case "$_src" in 0|1) ;; 3) echo "REJECT 슬랙 장부 불명 — byz_thread_post.py repair --card $IDX (부작용 0)"; exit 1;; *) echo "REJECT 슬랙 장부 확인 실패 rc=$_src(127=도구 없음) — 부작용 0"; exit 1;; esac; fi
if [ "$DRY" = 1 ]; then "${OPEN[@]}" --dry-run; exit 0; fi
# 사건 원장 훅(PLAN-status-sheet §3-1 · 근원 ⑥): prepared 를 «먼저» — 못 쓰면 착수 거절 · 성공(⑥ 끝)에 committed · 그 밖의 종료는 abort(trap)
_SK="$(bash "$HERE/ft-sheet-events.sh" key spawn "$SLUG" "$NAME")"; _ST="$(printf '%s' "$IDX_REL" | sed -n 's#^design/\([a-z0-9]*\)/indices/.*#\1#p')"
bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' spawn "${_ST:-v65}" "$SLUG" "$NAME" "$IDX_REL" "$FROM")" >/dev/null || { echo "REJECT 사건 원장 prepared 실패 — 착수 거절(부작용 0)"; exit 1; }
trap 'bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null' EXIT
if [ "$STAMP_BASE" = 1 ]; then
  python3 - "$IDX" "$CUR_HEAD" <<'PY' || { echo "REJECT 카드 base_sha 기록 실패($IDX)"; exit 1; }
import re, sys, datetime
p, head = sys.argv[1:3]
txt = open(p, encoding="utf-8").read()
line = f"- base_sha: {head} (spawn {datetime.date.today()})\n"
m = re.search(r"^##\s*상태[^\n]*\n", txt, re.M)
txt = txt[:m.end()] + line + txt[m.end():] if m else txt.rstrip("\n") + "\n\n## 상태\n" + line
open(p, "w", encoding="utf-8").write(txt)
PY
fi

# ② 워크트리 — 이미 있으면 재사용(재발주), 없으면 기준 브랜치에서 분기
if [ ! -d "$WTDIR" ]; then
  git -C "$ROOT" worktree add "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }
  for l in .venv .env; do [ -e "$ROOT/$l" ] && ln -sfn "../../$l" "$WTDIR/$l"; done
  # base_sha(오빠 ORDERS 103 · single_set_testing §3 ①): 갈라진 시점을 남겨 ft-nano-freshness 가 «루트부터» 판정한다.
  printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"%s","purpose":"nano · %s"}\n' "$BRANCH" "$INFO_BASE" "$(git -C "$ROOT" rev-parse --short "$BASE_BRANCH")" "$(date '+%F %T')" "$IDX_REL" > "$WTDIR/.worktree-info.json"
  # ★Serena project_name 충돌 차단 (2026-09-16 사고 1 · arch#49 #17015)★
  #   워크트리 41개가 전부 project_name "BYZ-Agents" 라 «나중 활성이 이긴다» — 형제 좌석의
  #   Serena 편집 8파일이 남의 워크트리에 떨어졌다(손실 0으로 복구). 절대경로 활성도 이름
  #   충돌엔 무력하고 `get_current_config` 는 이름만 보여줘 판별이 안 된다.
  #   ⇒ 워크트리를 만드는 그 자리에서 이름을 워크트리 이름으로 박는다.
  if [ -f "$WTDIR/.serena/project.yml" ]; then
    _wtname="$(basename "$WTDIR")"
    /usr/bin/sed -i '' -E "s|^([[:space:]]*project_name:[[:space:]]*).*$|\1\"$_wtname\"|" "$WTDIR/.serena/project.yml" \
      && echo "SERENA project_name=$_wtname ($WTDIR/.serena/project.yml)" \
      || echo "WARN serena project_name 치환 실패 — 좌석에 «편집 직전 find_file 1회» 규율을 알려라"
  fi
fi

# ③ 열기 — 모델 인자에 대괄호가 있어 zsh 글롭 즉사 함정(글로벌 규칙) → 이 스크립트는 bash 라 그대로 통과
# R81 판정 847 — ③④(세션 열기·태그) 실패 = 이 실행이 연 세션만 undo 가 kill(소유권·착수 0 검사) · ⑤⑥ 실패 = kill 0 + 사람 판정
fail_rb() { echo "$1"; [ -n "${OWNED:-}" ] || { echo "롤백 불가 — 고아: $NAME (소유권 값 못 읽음)"; exit 1; }
  _o="$(FT_NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}" FT_SEATS_JSON="$SEATS" FT_ACTIVE_TAG="${FT_ACTIVE_TAG:-@zc_v65_active}" bash "$HERE/ft-nano-spawn-undo.sh" "$NAME" --owned "$OWNED" --card "$IDX")" && { printf '%s\n' "$_o"; exit 1; }; echo "롤백 실패 — 고아: $NAME ($_o)"; exit 1; }
human() { echo "REJECT $1 실패 — 세션 $NAME 떠 있음·명부 등록됨 — 사람 판정(ft-nano-spawn-undo.sh $NAME 단독 모드로 계획 생성 가능)"; exit 1; }
"${OPEN[@]}" >/dev/null 2>&1; _orc=$?
tmux has-session -t "=$NAME" 2>/dev/null || { [ "$_orc" -eq 0 ] && echo "REJECT 세션이 안 떴다: $NAME" || echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
IFS='|' read -r PANE _cr < <(tmux list-panes -a -F '#{session_name}|#{pane_id}|#{session_created}' | awk -F'|' -v s="$NAME" '$1==s{print $2"|"$3; exit}'); OWNED=""; [ -n "$PANE" ] && [ -n "$_cr" ] && OWNED="$PANE:$_cr"
[ "$_orc" -eq 0 ] || fail_rb "REJECT tmuxc open 실패 ($NAME)"

# ④ 소실 방지 두 줄 — E-190(remain-on-exit 없어 pane 통째 소실) · E-212(태그 없어 zombie-clean 이 kill)
# ★`-t "=$NAME"` 은 has-session 에만 통한다★ (실측 2026-09-14): `#` 든 이름에 set-option/display-message 는
#   `no such session`. pane_id 로 해석해 넘긴다(mbox.sh pane_of 와 같은 이유). 세션 옵션은 pane 타겟으로도 세션에 박힌다.
[ -n "$PANE" ] || fail_rb "REJECT pane 못 찾음: $NAME"   # PANE·OWNED 는 ③ 직후 읽었다(위)
tmux set-option -t "$PANE" remain-on-exit on
tmux set-option -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}" 1
[ "$(tmux show-option -qv -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}")" = 1 ] || fail_rb "REJECT 태그 확인 실패: $NAME"

# ⑤ seats.json 등록 (tick=null → 알림 울림)
python3 - "$SEATS" "$NAME" "$AGENT" "$MODEL" "$IDX_REL" "$ROLE" "$RAISE" "$FROM" <<'PY' || human "⑤ 명부 등록"
import json, sys, collections, datetime
p, name, agent, model, idx, role, raise_reason, by = sys.argv[1:9]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d[name] = collections.OrderedDict([("role",role),("agent",agent),("tick",None),("model",model),("index",idx.replace("/대기/","/진행/"))])
if raise_reason.strip():   # R149: 상향 좌석 «왜 올렸나·언제 내리나» — 카드(진행/)가 완성/ 으로 가거나 없어지면 ft-tick raised_watch 가 ▶내릴 것
    d[name]["raised"] = collections.OrderedDict([("reason",raise_reason.strip()),("card",d[name]["index"]),("by",by),("at",datetime.datetime.now().isoformat(timespec="seconds")),("close_on","card 가 완성/ 으로 가거나 없어짐 · 또는 좌석 닫기")])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY

# ⑥ 대기→진행 (호출 워크트리에서 git mv — 인덱스 폴더의 정본은 기준 브랜치)
bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME" || human "⑥ 인덱스 이동"
NEW_IDX="${IDX_REL/\/대기\//\/진행\/}"
bash "$HERE/ft-sheet-events.sh" commit "$_SK" >/dev/null || true   # 좌석 열림+명부+카드 이동까지 끝 = 착수 사건 성공 (append 실패는 stderr SHEET-EVENT-PENDING · rc 그대로)

# ⑦⑧ 첫 발주 = 인덱스 경로 한 줄 + README. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
BODY="[Seatbelt 발주] 네 인덱스: $WT/$NEW_IDX — 먼저 $WT/${FT_SEATBELT_README:-design/v65/SEATBELT-README.md} §2 부팅 5단계(첫 보고까지), 그 다음 인덱스 §구현 범위만. 커밋은 브랜치 $BRANCH, push 금지. 산출 경로를 mbox 로 $FROM 에. ★press(라이브 오디오 시험) 금지 — 나노는 쏘지 않는다(ft-press-gate ⑦ 이 tester·checker 좌석만 허가 · 오빠 10-07) · 시험은 단위·캡처·기존 로그만, press 가 필요하면 산출에 「press 필요: <무엇을 볼지>」 1줄로 적어 $FROM 에 넘긴다★ ★측정 조작 금지(오빠 절대지침) — 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)·말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거 아님 · 측정은 trusted 클릭 + 기존 e2e 러너의 실제 음성 경로만 · 격리 Redis 픽스처 시험은 별개 · 이미 썼으면 [HIL] 로 올림 (BOOT 20)★ ★Serena 는 읽기만(find_symbol·search_for_pattern) — Serena 편집 도구(replace_*·insert_*·rename_*) 금지 · 편집은 Edit 절대경로($WTDIR/…)만★(Serena 서버 1개를 전 좌석이 공유해 활성 프로젝트가 전역 — 10-02 타 워크트리 편집 4회 · 오빠 판정). ★읽기는 Read/Serena, Bash 는 실행(git·pytest·ruff·mbox)만★ — cat/sed -n/grep 으로 파일을 읽으면 전문이 컨텍스트에 쌓인다(2026-09-14 나노 16좌석 실측: Bash 100~156회 중 절반이 파일 읽기). ★증거 줄(세트: … · 시험: … rc=… · 이슈: …)은 완료 턴에 네가 인덱스 «상태» 절에 직접 쓴다($WT/$NEW_IDX 절대경로 Edit) — master 는 커밋만(판정 1125)★ 증거 줄 템플릿(그대로 복사해 <> 만 채움): 세트: <나노 HEAD 40자> · 시험: <명령 — «(N passed)» 같은 꼬리는 여기> rc=<n> · 이슈: 0 — rc= 바로 뒤는 « · 이슈:» — 괄호·설명은 rc= 앞에. ★팀 구조: 각 팀 = master(집행) + arch(설계·발주·DA 소환) + DA(반박 게이트) 상시 · 실제 작업은 전부 나노(카드 1장 = 나노 1석) · master·arch·DA 는 코드·시안·카드 증거 줄을 쓰지 않는다★${_EBN}"
sleep 8   # 에이전트 부팅. 짧으면 doorbell 이 셸에 떨어진다(noagent)
if FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; then
  echo "SPAWNED $NAME index=$NEW_IDX wt=$WTDIR"; exit 0
fi
rc=$?; echo "SPAWNED-UNVERIFIED $NAME rc=$rc — 좌석은 떴다. 도달을 사람이 확인"; exit 5
