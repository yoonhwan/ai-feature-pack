#!/usr/bin/env bash
# ft-nano-spawn.sh <indices/대기/X.md> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--raise "<사유>"] [--from <발주좌석>] [--recheck <판정문>] [--base <ref>] [--cherry-override "<사유>"] [--research] [--dry-run]
#   --research = 리서치 나노(판정 2282 · R387 · 설계 §3·§7) — «진행/ 부모 카드»(DA 보류가 쌓인 카드)를 옮기지 않고 같은 카드에 읽기 전용 조사 좌석을 연다: 좌석 이름 꼬리 `-research` · 발주 본문에 고정 문단(산출 = RESEARCH 파일 1개 · 코드 0) · 카드에 `- 리서치: <좌석> base=<sha> 허용=…` · opencode 는 ft-opencode-reap.sh(r286) 없으면 REJECT
#   --raise "<사유>" = 상향 모델(claude-fable-*·*astra* · 판정 1641)을 열 때 필수 · 명부 행에 raised{reason,card,by,at,close_on} 를 남긴다(R149)
#   Seatbelt 0.3 · 나노 좌석을 «손타이핑 없이» 연다 (SEATBELT-README §3 열기).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인) · 7 = 팀셋 나노 상한 — 좌석 0 · 순번 큐(QUEUED · r-teamset-standard)
# 한 번에: ①lint ②워크트리+.venv/.env·clients/web/node_modules 심링크+.worktree-info.json ③tmuxc open(--agent/--model 통과, 기본 claude/sonnet-5.5 — r286)
#          ④remain-on-exit on + @zc_v65_active=1 ⑤seats.json 등록 ⑥인덱스 대기→진행 ⑦첫 발주(인덱스 경로 한 줄, mbox) ⑧도달 확인(jsonl)
# ★팩 ft-tmux-spawn.sh 미사용★: install.json canonical·CAPABILITY_GAP 게이트가 v65 워크트리에 없다(troubleshoot 09-06 「install.json 부재 = exit 4」) · 오빠 §0-A 「tmuxc 로 생성해서 어차피 쓰니 모델까지 지정가능」 — tmuxc 직접 호출.
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec
IDX="${1:-}"; shift || { echo "usage: $0 <indices/대기/X.md> [--agent A] [--model M] [--effort E] [--raise \"<사유>\"] [--from SEAT] [--base REF] [--cherry-override \"<사유>\"] [--dry-run]" >&2; exit 2; }
AGENT="claude"; MODEL=""; EFFORT="high"; FROM="${FT_SEND_FROM:-dispatch}"; RESEARCH=0; DRY=0; FAST=""; TIER=""; RECHECK=""; BASE_REF=""; HAVE_CO=0; CO=""; RAISE=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; shift 2;; --raise) RAISE="${2:-}"; shift 2 2>/dev/null || shift;;
  --from) FROM="$2"; shift 2;; --recheck) RECHECK="$2"; shift 2;; --dry-run) DRY=1; shift;; --research) RESEARCH=1; shift;; --tier) TIER="$2"; shift 2;; --base) BASE_REF="$2"; shift 2;;
  --cherry-override) HAVE_CO=1; CO="${2:-}"; shift 2 2>/dev/null || shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
CO_ARGS=(); [ "$HAVE_CO" -eq 0 ] || { [ -n "${CO//[[:space:]]/}" ] || { echo "usage: --cherry-override \"<사유>\" — 사유가 비었다(사유 없는 우회 거부)" >&2; exit 2; }; CO_ARGS=(--override "$CO"); }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# ★spawn 정지 파일 (R320 · 판정 2166)★: 정지는 기한·해제 조건이 있는 SPAWN_HOLD 파일 하나로만 걸린다 — 문장·쪽지로 받은 정지는 효력 0. 출력 `hold=none` = 정지 아님. 없는 도구는 설치 누락(라이브 드리프트 검사가 잡는다).
if [ -f "$HERE/ft-spawn-hold.sh" ]; then
  _hold="$(bash "$HERE/ft-spawn-hold.sh" status 2>&1)"; _hrc=$?
  [ "$_hrc" = 0 ] || { printf '%s\n' "$_hold"; exit "$_hrc"; }
  printf '%s\n' "$_hold"
fi
# ★자원 게이트 (Res-1014)★: 디스크·스왑·메모리·에이전트 수가 한계를 넘으면 열지 않는다(부작용 전). 우회 플래그 없음 — 조정은 env 문턱만.
[ -f "$HERE/ft-resource-gate.sh" ] || { echo "REJECT ft-resource-gate.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
_rgout="$(bash "$HERE/ft-resource-gate.sh" check 2>&1)"; _rgrc=$?
# R198(판정 1767): 에이전트 수로 막혔을 때만 — 기존 표준승인 범위 안의 유휴·완료 좌석을 자동 정리한 뒤 문지기 재검(FT_RECLAIM=0 으로 끔)
if [ "$_rgrc" != 0 ] && [ "${FT_RECLAIM:-1}" != 0 ] && [ -f "$HERE/ft-resource-reclaim.sh" ]; then
  _rgout="$(bash "$HERE/ft-resource-reclaim.sh" --on-reject "$_rgout" --gate "$HERE/ft-resource-gate.sh" 2>&1)"; _rgrc=$?
  [ "$_rgrc" = 0 ] && printf '%s\n' "$_rgout" >&2
fi
[ "$_rgrc" != 0 ] && { printf '%s\n' "$_rgout"; exit "$_rgrc"; }
WT="$(git rev-parse --show-toplevel)"                       # 호출 워크트리(기준 브랜치의 자리)
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
# ★페널티 게이트 (R320b · 오빠 판정 2170)★: 전 세션 정지(PENALTY_STOP 파일) 중이면 재개 전 팀은 열지 않는다(부작용 전 · successor 는 대상 아님). 우회 플래그 없음 — 풀기는 ft-penalty.sh resume <팀>. 파일이 있는데 판정기가 없으면 REJECT(조용한 통과 0).
if [ -f "$ROOT/.fable-team/state/PENALTY_STOP" ]; then
  [ -f "$HERE/ft-penalty.sh" ] || { echo "REJECT 전 세션 정지 중인데 ft-penalty.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _ptm=""; [[ "$IDX" =~ design/(teams/)?([a-z0-9]+)/indices/ ]] && _ptm="${BASH_REMATCH[2]}"   # R382: design/teams/<팀>/ 꼴도 팀 이름으로 읽는다
  _pout="$(FT_ROOT="$ROOT" bash "$HERE/ft-penalty.sh" check "$_ptm" 2>&1)"; _prc=$?
  [ "$_prc" != 0 ] && { printf '%s\n' "$_pout"; exit "$_prc"; }
fi
# ★팀 env 자동 로드 (카드 nano-spawn-close-team-env §1)★: FT_NANO_PREFIX 가 이미 있으면 «명시가 이긴다» — 아무것도 안 한다.
#   없으면 카드 경로 design/<팀>/indices/ 의 팀(v65 는 default)으로 $ROOT/.fable-team/bin-<팀>/<팀>-env.sh 를 source. 파일이 없으면 추측 없이 REJECT.
if [ -z "${FT_NANO_PREFIX:-}" ]; then
  _team=""; [[ "$IDX" =~ design/(teams/)?([a-z0-9]+)/indices/ ]] && [ "${BASH_REMATCH[2]}" != v65 ] && _team="${BASH_REMATCH[2]}"
  if [ -n "$_team" ]; then
    _tenv="$ROOT/.fable-team/bin-$_team/$_team-env.sh"
    [ -f "$_tenv" ] || { echo "REJECT 팀 env 없음: $_tenv"; exit 1; }
    . "$_tenv"
  fi
  echo "ENV team=${_team:-default} prefix=${FT_NANO_PREFIX:-ft-v65-temp-} seats=${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
fi
# ★좌석 상한 (R252 · 판정 1949)★: 팀 env 에 FT_TEAM_SEAT_CAP·FT_GROUP_SEAT_CAP 가 있는 팀(위성)만 — 부작용 0 지점(워크트리·세션·명부 «전»)에서 센다. env 가 없는 팀은 검사 0.
if [ -n "${FT_TEAM_SEAT_CAP:-}${FT_GROUP_SEAT_CAP:-}" ]; then
  [ -f "$HERE/ft_seat_cap.py" ] || { echo "REJECT ft_seat_cap.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _cap="$(python3 "$HERE/ft_seat_cap.py" --root "$ROOT")" || { printf '%s\n' "$_cap"; exit 1; }
fi
# ★팀셋 나노 상한 (r-teamset-standard · 판정 2170)★: design/TEAMSET.md 표의 팀 상한 — 부작용 0 지점. 넘으면 «전 팀 정지» 대신 그 팀 끝난 나노 회수 1회(--team 필수) → 그래도 넘으면 순번 큐(QUEUED · rc 7). FT_TEAMSET=0 으로 끔.
if [ "${FT_TEAMSET:-1}" != 0 ]; then
  [ -f "$HERE/ft_teamset.py" ] && [ -f "$HERE/ft_spawn_queue.py" ] || { echo "REJECT ft_teamset.py·ft_spawn_queue.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
  _tsp="${FT_NANO_PREFIX:-ft-v65-temp-}"; _tsmd="${FT_TEAMSET_MD:-gitref:origin/main:design/TEAMSET.md}"   # R351: 표 정본 = $ROOT 의 origin/main · 못 읽으면 REJECT(조용한 통과 0)
  _tso="$(python3 "$HERE/ft_teamset.py" cap --root "$ROOT" --md "$_tsmd" --prefix "$_tsp" 2>&1)"; _tsrc=$?
  _tst="$(printf '%s' "$_tso" | awk '{print $2}')"
  if [ "$_tsrc" = 4 ] && [ "$DRY" != 1 ]; then
    bash "${FT_RECLAIM_SH:-$HERE/ft-resource-reclaim.sh}" --caller "$FROM" --need 1 --team "$_tst" >&2
    _tso="$(python3 "$HERE/ft_teamset.py" cap --root "$ROOT" --md "$_tsmd" --prefix "$_tsp" 2>&1)"; _tsrc=$?
  fi
  printf '%s\n' "$_tso"
  case "$_tsrc" in
    0) ;;
    4) [ "$DRY" = 1 ] || python3 "$HERE/ft_spawn_queue.py" add --root "$ROOT" --prefix "$_tsp" --card "$IDX" --from "$FROM"; exit 7;;
    *) echo "REJECT 팀셋 표 판정 실패(rc=$_tsrc) — 부작용 0"; exit 1;;
  esac
fi
# ★라이브 bin 드리프트 입구 검사 (카드 live-bin-drift-check · Issue 816 ③)★: 설치 꼴(*/.fable-team/bin)에서 돌 때만 — 라이브 도구가 origin/main 키트와 다르면 열지 않는다(--dry-run 도 같다).
#   검사 스크립트가 없는 것도 드리프트(설치 누락) · 우회 스위치 없음 — 해결은 master 라이브 cp.
case "$HERE" in
  */.fable-team/bin|*/.fable-team/*/bin|*/fable-team/live/*/bin)   # r385: 버전 폴더 설치 꼴 포함 · 키트 리포 = 하네스 코드 루트(--repo 생략)
    if [ ! -f "$HERE/ft-live-bin-drift-check.sh" ]; then echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시 (ft-live-bin-drift-check.sh 설치 누락)"; exit 1; fi
    _dout="$(bash "$HERE/ft-live-bin-drift-check.sh" --bin "$HERE")" || { printf '%s\n' "$_dout"; echo "REJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시"; exit 1; }
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
    else AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5-5[1m]}"; EFFORT="high"; fi;;
  checker:3|tester:3)                AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5-5[1m]}"; EFFORT="high";;
  # impl = 구현 나노. 1순위 sonnet-5.5(기본값 — r286 오빠 하네스 뉴스 «Sonnet 5.5 가 Opus·sol 보다 처리 능력 우위» · 옛 09-28 opus5.5 · fable 은 --model 명시로만), :2 luna (cmd 는 FT_CMD_ENABLED=1 일 때 :2 로 끼어듦)
  impl|impl:1) ;;
  # search = opencode 나노(r286 · DeepSeek V4.1 Flash Free 1M 무료) — 대용량 로그·코드 분석·정본화 서치 «읽고 모으기» 전용 · 닫기 = ft-nano-close(opencode left=0 확인)
  search) AGENT="opencode"; MODEL="${FT_OC_MODEL:-opencode/deepseek-v4.1-flash-free}";;
  impl:2) if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
          else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on"; fi;;
  impl:3) AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-6-luna}"; EFFORT="high"; FAST="on";;
  '') ;; *) echo "unknown --tier $TIER (checker|tester[:1-3] · impl[:1-3] · search)" >&2; exit 2;;
esac
# 역할을 seats.json 에 남긴다 — 세션 상태 절·stall 대상 판정이 «checker/tester/impl» 을 가른다
ROLE="${TIER%%:*}"; ROLE="${ROLE:-nano}"
# --model 미지정(티어도 안 정함)이면 에이전트별 기본 — claude 는 FT_IMPL_MODEL, 그 밖은 모델을 지어내지 않고 정해진 것만(표에 없는 에이전트는 REJECT)
if [ -z "$MODEL" ]; then case "$AGENT" in
  claude) MODEL="${FT_IMPL_MODEL:-claude-sonnet-5-5[1m]}";;
  codex)  MODEL="${FT_LUNA_MODEL:-gpt-6-luna}";;
  cmd)    MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}";;
  opencode) MODEL="${FT_OC_MODEL:-opencode/deepseek-v4.1-flash-free}";;   # r286
  *) echo "REJECT --model 필수 (--agent $AGENT 는 기본 모델이 없다)"; exit 1;; esac
fi
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
if [ ! -f "$IDX" ] && [ -f "$HERE/ft-team-lib.sh" ]; then . "$HERE/ft-team-lib.sh"; _tw="$(ft_index_twin "$IDX")" && [ -f "$_tw" ] && { echo "INFO 인덱스 쌍둥이 경로로 해석: $IDX → $_tw (R382 전환 기간 역호환)"; IDX="$_tw"; }; fi
[ -f "$IDX" ] || { echo "REJECT 인덱스 없음: $IDX"; exit 1; }
[ ! -f "$HERE/ft-team-lib.sh" ] || ( . "$HERE/ft-team-lib.sh" && ft_card_location_ok "$IDX" ) || exit 1   # r447: 명단 새 꼴 팀 카드가 옛 꼴 폴더(쌍둥이 해석 포함)면 REJECT
if [ "$RESEARCH" = 1 ]; then case "$IDX" in */진행/*) ;; *) echo "REJECT --research 는 진행/ 에 있는 부모 카드(DA 보류가 쌓인 카드)만 — 카드는 옮기지 않는다: $IDX"; exit 1;; esac
else case "$IDX" in */대기/*) ;; *) echo "REJECT 대기/ 에 있는 인덱스만 연다: $IDX"; exit 1;; esac; fi
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }
# 형제 도구는 설치 폴더에만 있다 — 원본 폴더에서 돌리면 lint 의 «파일 없음» 이 «lint 실패» 로, 첫 발주는 좌석을 연 «뒤» 에 죽는다. 열기 «전»에 거절한다(R134). --dry-run 은 송신 전(179행)에 끝나므로 send-verified 는 실전만.
for _sib in ft-index-lint.sh $([ "$DRY" = 1 ] || echo ft-send-verified.sh ft-agent-ready.sh); do
  [ -f "$HERE/$_sib" ] || { echo "REJECT $_sib 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
done
# R149(판정 1641): 상향 모델은 사유 필수 — 해석이 끝난 실제 MODEL 로 판정하고 부작용(카드·원장·워크트리·tmux·명부) «전»에 거절한다. rc 0=상향 1=기본 그 밖=도구 고장(조용히 기본 취급 0)
python3 "$HERE/ft_raised.py" is-raised "$MODEL"; _rrc=$?
case "$_rrc" in
  0) [ -n "${RAISE//[[:space:]]/}" ] || { echo "REJECT 상향 모델($MODEL)은 --raise \"<사유>\" 필수 — 닫히면 원래 모델로(판정 1641)"; exit 1; };;
  1) ;;
  *) echo "REJECT ft_raised.py 판정 실패 rc=$_rrc ($HERE/ft_raised.py) — 부작용 0"; exit 1;;
esac

# R387 --research: opencode 리서치 좌석은 «쓰고 바로 닫기»(메모리 버그 · r286 reap)가 전제 — 회수 도구가 없으면 부작용 «전» REJECT. Fable 등 다른 에이전트는 통과.
[ "$RESEARCH" != 1 ] || [ "$AGENT" != opencode ] || [ -f "$HERE/ft-opencode-reap.sh" ] || { echo "REJECT --research --agent opencode 는 ft-opencode-reap.sh(r286) 미설치 — 닫을 때 프로세스를 못 회수한다: $HERE · Fable(--agent claude --model claude-fable-5-1[1m])로 열거나 r286 설치 뒤"; exit 1; }

# ① lint — 누가 읽어도 착수 가능한가 (P2: planner 카드 머리 「- 템플릿: 빈 카드(나노가 채움)」 = lint ⑤⑥ 만 건너뜀 · 그 밖 팀·검사는 그대로)
[ -f "$HERE/ft-team-lib.sh" ] || { echo "REJECT ft-team-lib.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
. "$HERE/ft-team-lib.sh"   # R383: planner 카드 판정·SEATBELT 경로를 팀 폴더 명단으로 푼다(팀 이름 글자 0)
_EBN=""; if ft_team_has_ref "$WT" planner "$IDX" indices/ && awk '/^##[[:space:]]/{exit} {print}' "$IDX" | grep -q '^- 템플릿: 빈 카드(나노가 채움)'; then export FT_INDEX_ALLOW_EMPTY_BODY=1; _EBN=" ★빈 카드 템플릿: 카드 구현 범위·완료 조건 절을 네가 먼저 채우고 arch 1줄 확인 뒤 착수★"; else unset FT_INDEX_ALLOW_EMPTY_BODY; fi
bash "$HERE/ft-index-lint.sh" "$IDX" || { echo "REJECT lint 실패"; exit 1; }
# ①-0 제안서 «오빠가 본 승인» 게이트 (R77 · 판정 816 — 로직은 ft-proposal-gate.sh --card)
_pg="$(bash "$HERE/ft-proposal-gate.sh" --card "$IDX")" || { echo "REJECT 제안서 승인 증거 부족 — $_pg"; exit 1; }; echo "$_pg"
# ①a 머리줄 4줄(C6 · SPEC-roles P3-1) — 없으면 REJECT 가 아니라 «spawn 후보 제외» 경고(ft-nano-slots.sh 와 같은 검사 · 현행 동작 보존)
_hmiss="$(awk '/^##[[:space:]]/{exit} {print}' "$IDX" | python3 -c "
import re, sys
h = sys.stdin.read()
print(' '.join(k.replace(' ', '_') for k in ('Issue', '상태', '선행', '시험 입력') if not re.search(r'^\s*[-*]?\s*' + k + r':[ \t]*\S', h, re.M)))")"
[ -z "$_hmiss" ] || echo "WARN 후보 제외 — 카드 머리줄 없음: $_hmiss (REJECT 아님 · ft-nano-slots.sh 후보에서 빠진다): $IDX"
# ①a-2 기준값 머리줄(C20 · SPEC-github-issue-driven §12-1) — 없거나 빈칸이면 REJECT 가 아니라 «후보 제외» 경고(위 4줄 검사와 같은 방식 · 현행 동작 보존).
#   지표가 없으면 「없음 → 대체 축」 을 적어야 하며 빈칸은 안 된다(design/harness/BASELINE-TEMPLATE.md).
awk '/^##[[:space:]]/{exit} {print}' "$IDX" | grep -Eq '^[[:space:]]*[-*]?[[:space:]]*기준값:[[:space:]]*[^[:space:]]' \
  || echo "WARN 후보 제외 — 카드 머리줄 기준값 없음 또는 빈칸 (REJECT 아님 · 지표 없으면 「기준값: 없음 → 대체 축 <무엇>」 · 하네스 팀 폴더의 BASELINE-TEMPLATE.md): $IDX"

# ①b 카드 base_sha 대조 (M7 · single_set_testing §1 규칙 2 · 오빠 ORDERS 102): 09-25 카드를 10-02 코드에 재대조 없이 집행한 사고 차단.
#   카드 «## 상태» 에 `base_sha: <40-hex>` 가 없으면 첫 개설 = 현재 기준 브랜치 HEAD 를 써넣고 진행(REJECT 0).
#   있으면 재개·재spawn = base_sha..HEAD 사이에 카드 «## 구현 범위» 가 인용한 파일(경로 토큰 · `관련 파일:` 줄 포함 · 인용 0 이면 세트 경로 전체 worker/ gateway/ shared/ clients/web/src/ tests/e2e/ scripts/server/)이 바뀌었으면 REJECT.
#   통과 = `--recheck <판정문>` 이 실재하고 그 판정문이 «현재 HEAD sha»(7자 이상 접두)를 적고 있을 때만.
CUR_HEAD="$(git -C "$WT" rev-parse "${BASE_REF:-HEAD}^{commit}")" || { echo "REJECT 기준 ${BASE_REF:+ref(--base) }HEAD 조회 실패: ${BASE_REF:-HEAD}"; exit 1; }
CARD_BASE="$(grep -E '^[[:space:]-]*base_sha:[[:space:]]*[0-9a-f]{40}' "$IDX" | head -1 | grep -oE '[0-9a-f]{40}' | head -1)"
if [ "$RESEARCH" = 1 ]; then
  STAMP_BASE=0   # 리서치 좌석은 코드를 안 만든다 — 부모 카드 base_sha 대조·기록 0(허용 밖 변경은 닫을 때 «리서치 위반» 으로 기록)
elif [ -z "$CARD_BASE" ]; then
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
[ "$RESEARCH" != 1 ] || SLUG="$(printf '%s' "$SLUG" | cut -c1-30)-research"   # R387: 좌석 이름·브랜치·워크트리 꼬리 -research
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
# R387 --research 고정 문단 — 산출 1개·코드 0·arch relay·즉시 [완료·휴식]. 허용 경로 = 부모 카드가 있는 팀 폴더의 RESEARCH-*.md
_RS_DIR="$(dirname "$(dirname "$(dirname "$IDX_REL")")")"; _RS_ALLOW="$_RS_DIR/RESEARCH-*.md"; _RS_OUT="$_RS_DIR/RESEARCH-$(basename "$IDX" .md)-$(date +%F).md"
_RSP=" ★리서치 워커(판정 2282 · R387)★ 네 일 = 부모 카드가 막힌 문제의 자료 조사·가설 조정·BTS 결과 수집뿐이다 — 산출 1개 = $WT/$_RS_OUT (출처·가설·BTS 결과 표기) · 이 경로($_RS_ALLOW) 밖 파일·코드 수정 0(닫을 때 도구가 허용 밖 변경을 카드에 «- 리서치 위반:» 으로 기록한다) · 끝나면 mbox relay 로 arch 에 산출 경로 + 3줄 요약을 보내고 카드 «상태» 에 «- 리서치 산출: <경로> · relay #<seq>» 줄을 쓴다 · 증거 줄 시험 칸 = «RESEARCH 파일 작성 rc=0» · 그 뒤 즉시 [완료·휴식] — 후속 일·재질문 대기 외 작업 0(opencode 좌석은 relay 직후 닫힌다)."

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
# r444 ⑤ 디스크 여유 검사 — 새 워크트리를 만들 때만 · 여유 < FT_NANO_MIN_FREE_GI(40)Gi 면 spawn 0(부작용 «전»). 회수 연결(r440)은 착지 뒤 — 지금은 REJECT 1줄 + [HIL]. 측정 실패도 REJECT(여유 미상 ≠ 충분).
if [ ! -d "$WTDIR" ]; then
  _free="${FT_DISK_FREE_GIB:-$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2 && $4+0>0{print int($4/1048576)}')}"
  case "$_free" in ''|*[!0-9]*) echo "REJECT [HIL] 디스크 여유 측정 실패(df $ROOT · 값 '${_free}') — spawn 0 · 여유 미상은 충분하다는 뜻 아님"; exit 1;; esac
  [ "$_free" -ge "${FT_NANO_MIN_FREE_GI:-40}" ] || { echo "REJECT [HIL] 디스크 여유 ${_free}Gi < ${FT_NANO_MIN_FREE_GI:-40}Gi — spawn 0 · 회수 먼저(유휴·완료 좌석 ft-resource-reclaim.sh · 정리 계획 ft-wt-sweep.sh) 뒤 다시"; exit 1; }
fi
if [ "$DRY" = 1 ]; then [ "$RESEARCH" != 1 ] || echo "RESEARCH seat=$NAME allow=$_RS_ALLOW card=$IDX_REL body=$_RSP"; "${OPEN[@]}" --dry-run; exit 0; fi
# R251 ⓐ 추론 프록시 사전 확인(7초 룰 · 부작용 0 지점) — 순간 장애는 넘기고 진짜 장애면 직결로 바꾸지 않고 거절한다
bash "$HERE/ft-agent-ready.sh" --proxy "$WT" --agent "$AGENT" || exit 1
# 사건 원장 훅(PLAN-status-sheet §3-1 · 근원 ⑥): prepared 를 «먼저» — 못 쓰면 착수 거절 · 성공(⑥ 끝)에 committed · 그 밖의 종료는 abort(trap)
_SK="$(bash "$HERE/ft-sheet-events.sh" key spawn "$SLUG" "$NAME")"; _ST="$(printf '%s' "$IDX_REL" | sed -n 's#^design/\(teams/\)\{0,1\}\([a-z0-9]*\)/indices/.*#\2#p')"
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

# ★R181★ 웹 시험(jest)은 clients/web/node_modules 가 있어야 돈다 — 루트 것을 상대 심링크로 건다(없으면 건너뛰고 한 줄 출력).
#   lock 이 달라도 걸되 «판이 다르다» 를 출력해 환경 RED 를 결함으로 오판하지 않게 한다. 무시 규칙은 .gitignore `clients/web/node_modules`(슬래시 없음).
link_web_node_modules() {
  local root="$1" wt="$2" rel="../../../../clients/web/node_modules"
  if [ ! -d "$root/clients/web/node_modules" ]; then
    echo "node_modules=none (루트 clients/web/node_modules 없음 — 웹 시험 불가)"; return 0
  fi
  [ -d "$wt/clients/web" ] || { echo "node_modules=none (워크트리에 clients/web 없음 — 웹 시험 불가)"; return 0; }
  [ -e "$wt/clients/web/node_modules" ] || [ -L "$wt/clients/web/node_modules" ] || ln -s "$rel" "$wt/clients/web/node_modules"
  if cmp -s "$root/clients/web/package-lock.json" "$wt/clients/web/package-lock.json"; then
    echo "node_modules=link lock=same"
  else
    echo "node_modules=link lock=differ (루트 node_modules 판이 이 base 와 다름 — 웹 시험 RED 는 환경 원인 후보)"
  fi
}

# ② 워크트리 — 이미 있으면 재사용(재발주), 없으면 기준 브랜치에서 분기
# r444 ⑤ sparse — 남의 팀 폴더(design/teams/<남>/)는 체크아웃하지 않는다(나노 1개 1.5Gi 중 design 1.34Gi). 자기 팀 폴더는 통째(증거 폴더를 빼면 새 증거 `git add` 가 rc1 — 실측).
#   팀을 못 정하면(카드 경로가 design/(teams/)<팀>/indices 꼴 아님) 전체 체크아웃 · FT_NANO_SPARSE=0 이면 끔 · 되돌림: git -C <워크트리> sparse-checkout disable
sparse_patterns() { printf '/*\n!/design/teams/*/\n/design/teams/%s/\n' "$1"; }
if [ ! -d "$WTDIR" ]; then
  _SPT="$(printf '%s' "$IDX_ABS" | sed -nE 's#.*/design/(teams/)?([a-z0-9][a-z0-9_-]*)/indices/.*#\2#p')"   # 카드가 다른 워크트리(절대경로)에 있어도 팀을 푼다
  if [ "${FT_NANO_SPARSE:-1}" = 1 ] && [ -n "$_SPT" ]; then
    git -C "$ROOT" worktree add --no-checkout "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }
    sparse_patterns "$_SPT" | git -C "$WTDIR" sparse-checkout set --no-cone --stdin >/dev/null 2>&1 && git -C "$WTDIR" checkout -q 2>/dev/null \
      || { echo "REJECT sparse 체크아웃 실패($WTDIR · 브랜치 $BRANCH · 워크트리는 남김 — 사람 판정)"; exit 1; }
    echo "SPARSE team=$_SPT 남의 팀 design 제외 (되돌림: git -C $WTDIR sparse-checkout disable)"
  else
    git -C "$ROOT" worktree add "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }
  fi
  for l in .venv .env; do [ -e "$ROOT/$l" ] && ln -sfn "../../$l" "$WTDIR/$l"; done
  link_web_node_modules "$ROOT" "$WTDIR"
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
else
  # R196: 재사용인데 .worktree-info.json 이 없으면(정리·복원으로 소실) 새로 만들 때와 같은 꼴로 다시 쓴다 — 없는 채로 두면 ft-nano-close 가 branch=? 로 멈춘다. 있으면 손대지 않는다(created_at 보존).
  if [ ! -f "$WTDIR/.worktree-info.json" ]; then
    _reuse_head="$(git -C "$WTDIR" symbolic-ref --short HEAD 2>/dev/null)"
    [ "$_reuse_head" = "$BRANCH" ] || { echo "REJECT 재사용 워크트리 브랜치 불일치 — HEAD=${_reuse_head:-detached} 기대=$BRANCH"; exit 1; }
    _reuse_mb="$(git -C "$WTDIR" merge-base "$BRANCH" "$BASE_BRANCH" 2>/dev/null)" || { echo "REJECT 재사용 워크트리 merge-base 실패 — $BRANCH ↔ $BASE_BRANCH"; exit 1; }
    # 같은 폴더 임시 파일에 쓰고 mv — 완성본만 게시한다. 쓰기·mv 실패는 REJECT(info 없이 열기 0).
    _reuse_tmp="$WTDIR/.worktree-info.json.tmp.$$"
    { printf '{"branch":"%s","base":"%s","base_sha":"%s","created_at":"%s","purpose":"nano · reuse · %s"}\n' "$BRANCH" "$INFO_BASE" "$(git -C "$WTDIR" rev-parse --short "$_reuse_mb")" "$(date '+%F %T')" "$IDX_REL" > "$_reuse_tmp" && mv -f "$_reuse_tmp" "$WTDIR/.worktree-info.json"; } 2>/dev/null \
      || { rm -f "$_reuse_tmp" 2>/dev/null; echo "REJECT 재사용 워크트리 info 쓰기 실패 — $WTDIR/.worktree-info.json"; exit 1; }
    echo "INFO 재작성 $WTDIR"
  fi
fi

# ③ 열기 — 모델 인자에 대괄호가 있어 zsh 글롭 즉사 함정(글로벌 규칙) → 이 스크립트는 bash 라 그대로 통과
# R81 판정 847 — ③④(세션 열기·태그) 실패 = 이 실행이 연 세션만 undo 가 kill(소유권·착수 0 검사) · ⑤⑥ 실패 = kill 0 + 사람 판정
fail_rb() { echo "$1"; [ -n "${OWNED:-}" ] || { echo "롤백 불가 — 고아: $NAME (소유권 값 못 읽음)"; exit 1; }
  _o="$(FT_NANO_PREFIX="${FT_NANO_PREFIX:-ft-v65-temp-}" FT_SEATS_JSON="$SEATS" FT_ACTIVE_TAG="${FT_ACTIVE_TAG:-@zc_v65_active}" bash "$HERE/ft-nano-spawn-undo.sh" "$NAME" --owned "$OWNED" --card "$IDX")" && { printf '%s\n' "$_o"; exit 1; }; echo "롤백 실패 — 고아: $NAME ($_o)"; exit 1; }
human() { echo "REJECT $1 실패 — 세션 $NAME 떠 있음·명부 등록됨 — 사람 판정(ft-nano-spawn-undo.sh $NAME 단독 모드로 계획 생성 가능)"; exit 1; }
_OC_SINCE="$(date +%s)"   # r286: opencode 좌석이 띄운 serve(부모 잃음) 귀속 기준 시각
"${OPEN[@]}" >/dev/null 2>&1; _orc=$?
tmux has-session -t "=$NAME" 2>/dev/null || { [ "$_orc" -eq 0 ] && echo "REJECT 세션이 안 떴다: $NAME" || echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
IFS='|' read -r PANE _cr < <(tmux list-panes -a -F '#{session_name}|#{pane_id}|#{session_created}' | awk -F'|' -v s="$NAME" '$1==s{print $2"|"$3; exit}'); OWNED=""; [ -n "$PANE" ] && [ -n "$_cr" ] && OWNED="$PANE:$_cr"
[ "$_orc" -eq 0 ] || fail_rb "REJECT tmuxc open 실패 ($NAME)"
# R251 ⓑ 에이전트 본체 확인 — 명부·카드 이동 «전». 없으면 이 실행이 연 pane 에 기동 명령 1회 재입력, 그래도 없으면 롤백(카드는 대기 그대로)
bash "$HERE/ft-agent-ready.sh" --pane "$PANE" --agent "$AGENT" --restart "$("${OPEN[@]}" --dry-run 2>/dev/null | sed -n 's/^command=//p')" || fail_rb "REJECT 에이전트 미기동 ($NAME) — 재기동 1회 실패"
# r286: opencode 좌석 = 지금 프로세스 나무 + 열린 뒤 뜬 serve 를 pid 파일에(닫기가 세션 kill 뒤 부모 잃은 것까지 회수) — 기록 실패는 경고(닫기 앞 기록이 다시 모은다)
[ "$AGENT" != opencode ] || bash "$HERE/ft-opencode-reap.sh" "$NAME" --wt "$WTDIR" --record --since "$_OC_SINCE" >&2 || echo "WARN opencode pid 기록 실패($NAME) — 닫기 앞 기록이 다시 모은다" >&2

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
if [ "$RESEARCH" = 1 ]; then   # R387: 부모 카드는 이미 진행/ — 옮기지 않고 «리서치: 좌석 · base · 허용» 줄만 상태 절에 덧붙인다(닫을 때 위반 검사·완성 게이트가 읽는다)
  NEW_IDX="$IDX_REL"; printf -- '- 리서치: %s base=%s 허용=%s\n' "$NAME" "$CUR_HEAD" "$_RS_ALLOW" >> "$IDX" || human "⑥ 리서치 카드 줄"
else
  bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME" || human "⑥ 인덱스 이동"
  NEW_IDX="${IDX_REL/\/대기\//\/진행\/}"
fi
# ★R163 spawn 카드 기준선★ — 이 시각의 카드 내용 지문·브랜치·워크트리를 남겨 두면 자율 중 «nano-reopen» 대리 판정(r162)이 «승인 범위 그대로» 인지 비교한다.
#   spawn 출력·exit 는 불변 — 쓰기 실패는 stderr 1줄뿐(tmp→mv 원자 쓰기).
_CB_DIR="${FT_NANO_CARD_BASE_DIR:-$ROOT/.fable-team/state/nano-card-base}"
{ mkdir -p "$_CB_DIR" && _cb_blob="$(git -C "$WT" hash-object "$WT/$NEW_IDX")" && python3 - "$_CB_DIR/$NAME.json" "$NAME" "$NEW_IDX" "$_cb_blob" "$BRANCH" "$WTDIR" <<'PY'
import json, os, sys, datetime
p, name, card, blob, branch, wt = sys.argv[1:7]
tmp = f"{p}.tmp-{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump({"name": name, "card_path": card, "card_blob": blob, "branch": branch, "worktree": wt, "at": datetime.datetime.now().isoformat(timespec="seconds")}, f, ensure_ascii=False, indent=2); f.write("\n")
os.replace(tmp, p)
PY
} || echo "WARN spawn 카드 기준선 쓰기 실패($_CB_DIR/$NAME.json) — spawn 은 그대로 진행" >&2
bash "$HERE/ft-sheet-events.sh" commit "$_SK" >/dev/null || true   # 좌석 열림+명부+카드 이동까지 끝 = 착수 사건 성공 (append 실패는 stderr SHEET-EVENT-PENDING · rc 그대로)

# ⑦⑧ 첫 발주 = 인덱스 경로 한 줄 + README. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
if [ -n "${FT_SEATBELT_README:-}" ]; then _SBR="$WT/$FT_SEATBELT_README"   # R406: 기본값 = 명단 ref(FT_TEAMS_REF · 기본 origin/main) 의 v65 폴더 꼴·쌍둥이 중 WT 에 실재하는 1개
else _SBR="$(ft_team_file_ref "$WT" v65 SEATBELT-README.md)" || { echo "REJECT v65 팀 폴더를 못 풀었다(명단 ${FT_TEAMS_REF:-origin/main}:design/TEAMS.md · 후보 실재 1개) — SEATBELT-README 경로 없음"; exit 1; }; fi
BODY="[Seatbelt 발주] 네 인덱스: $WT/$NEW_IDX — 먼저 $_SBR §2 부팅 5단계(첫 보고까지), 그 다음 인덱스 §구현 범위만. 커밋은 브랜치 $BRANCH, push 금지. 산출 경로를 mbox 로 $FROM 에. ★press(라이브 오디오 시험) 금지 — 나노는 쏘지 않는다(ft-press-gate ⑦ 이 tester·checker 좌석만 허가 · 오빠 10-07) · 시험은 단위·캡처·기존 로그만, press 가 필요하면 산출에 「press 필요: <무엇을 볼지>」 1줄로 적어 $FROM 에 넘긴다★ ★측정 조작 금지(오빠 절대지침) — 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)·말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거 아님 · 측정은 trusted 클릭 + 기존 e2e 러너의 실제 음성 경로만 · 격리 Redis 픽스처 시험은 별개 · 이미 썼으면 [HIL] 로 올림 (BOOT 20)★ ★Serena 는 읽기만(find_symbol·search_for_pattern) — Serena 편집 도구(replace_*·insert_*·rename_*) 금지 · 편집은 Edit 절대경로($WTDIR/…)만★(Serena 서버 1개를 전 좌석이 공유해 활성 프로젝트가 전역 — 10-02 타 워크트리 편집 4회 · 오빠 판정). ★읽기는 Read/Serena, Bash 는 실행(git·pytest·ruff·mbox)만★ — cat/sed -n/grep 으로 파일을 읽으면 전문이 컨텍스트에 쌓인다(2026-09-14 나노 16좌석 실측: Bash 100~156회 중 절반이 파일 읽기). ★증거 줄(세트: … · 시험: … rc=… · 이슈: …)은 완료 턴에 네가 인덱스 «상태» 절에 직접 쓴다($WT/$NEW_IDX 절대경로 Edit) — master 는 커밋만(판정 1125)★ 증거 줄 템플릿(그대로 복사해 <> 만 채움): 세트: <나노 HEAD 40자> · 시험: <명령 — «(N passed)» 같은 꼬리는 여기> rc=<n> · 이슈: 0 — rc= 바로 뒤는 « · 이슈:» — 괄호·설명은 rc= 앞에. ★팀 구조: 각 팀 = master(집행) + arch(설계·발주·DA 소환) + DA(반박 게이트) 상시 · 실제 작업은 전부 나노(카드 1장 = 나노 1석) · master·arch·DA 는 코드·시안·카드 증거 줄을 쓰지 않는다★${_EBN}"
[ "$RESEARCH" != 1 ] || BODY="$BODY$_RSP"
[ "$TIER" != search ] || BODY="$BODY ★검색 나노(opencode · r286)★ 읽고 모으기만 — 코드 수정·커밋 0 · 산출 = 파일 1개 + mbox relay · 끝나면 [완료·휴식] (닫기 = master ft-nano-close · opencode 프로세스 left=0 확인)."
# (에이전트 본체는 ③ 직후 ft-agent-ready.sh 가 확인했다 — 옛 sleep 8 대체 · R251)
FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; _src=$?
[ "$_src" -eq 0 ] && { echo "SPAWNED $NAME index=$NEW_IDX wt=$WTDIR"; exit 0; }
echo "SPAWNED-UNVERIFIED $NAME rc=$_src — 좌석은 떴다. 도달을 사람이 확인"; exit 5
