#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT(Seatbelt 1.0.1).★
# ft-nano-spawn.sh <indices/대기/X.md> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--from <발주좌석>] [--dry-run]
#   Seatbelt 0.3 · 나노 좌석을 «손타이핑 없이» 연다 (SEATBELT-README §3 열기).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인)
# 한 번에: ①lint ②워크트리+.venv/.env 심링크+.worktree-info.json ③tmuxc open(--agent/--model 통과, 기본 claude/fable-5.1)
#          ④remain-on-exit on + @zc_v65_active=1 ⑤seats.json 등록 ⑥인덱스 대기→진행 ⑦첫 발주(인덱스 경로 한 줄, mbox) ⑧도달 확인(jsonl)
# ★팩 ft-tmux-spawn.sh 를 안 쓰는 이유★: install.json canonical·CAPABILITY_GAP 게이트가 v65 워크트리에 없다(troubleshoot 09-06
#   「install.json 부재 = exit 4」). 오빠 §0-A: 「tmuxc 로 생성해서 어차피 쓰니 모델까지 지정가능」 — tmuxc 를 직접 부른다.
set -uo pipefail
IDX="${1:-}"; shift || { echo "usage: $0 <indices/대기/X.md> [--agent A] [--model M] [--effort E] [--from SEAT] [--dry-run]" >&2; exit 2; }
AGENT="claude"; MODEL="claude-fable-5-1[1m]"; EFFORT="high"; FROM="${FT_SEND_FROM:-dispatch}"; DRY=0; FAST=""; TIER=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; shift 2;;
  --from) FROM="$2"; shift 2;; --dry-run) DRY=1; shift;; --tier) TIER="$2"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
# ★--tier checker|tester[:N] = 싼 모델 순위 (오빠 2026-09-14 확정 「zcode > cmd > luna > sonnet」 · README §5-1)★
#   N 생략 = 1순위. 한도·거부(usage_limit_reached·429·exit 10 크레딧)면 발주자가 :2 :3 :4 로 다음 순위. sonnet(4) 은 마지막.
#   zcode 슬러그는 설치마다 다르다 — FT_ZCODE_MODEL 로 준다(없으면 REJECT — 없는 모델을 지어내지 않는다).
# 2026-09-14 오빠 실측 정정 2회: 「zcode 구독 없네 제외」 → 「cmd 월제한이 18일날 풀린다.. cmd도 넘기자」
#   ⇒ 지금 순위 = luna > sonnet. cmd 는 FT_CMD_ENABLED=1 일 때만 1순위로 복귀(월제한 해제 후 오빠가 켠다).
_cmd_on="${FT_CMD_ENABLED:-0}"
case "$TIER" in
  checker|tester|checker:1|tester:1)
    if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
    else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-5.6-luna}"; EFFORT="high"; FAST="on"; fi;;
  checker:2|tester:2)
    if [ "$_cmd_on" = 1 ]; then AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-5.6-luna}"; EFFORT="high"; FAST="on";
    else AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5[1m]}"; EFFORT="high"; fi;;
  checker:3|tester:3)                AGENT="claude"; MODEL="${FT_SONNET_MODEL:-claude-sonnet-5[1m]}"; EFFORT="high";;
  # impl = 구현 나노. 1순위 fable(기본값 — 오빠 「fable 이 구현은 메인」), :2 luna (cmd 는 FT_CMD_ENABLED=1 일 때 :2 로 끼어듦)
  impl|impl:1) ;;
  impl:2) if [ "$_cmd_on" = 1 ]; then AGENT="cmd"; MODEL="${FT_CMD_MODEL:-deepseek/deepseek-v4-flash}"; EFFORT="high";
          else AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-5.6-luna}"; EFFORT="high"; FAST="on"; fi;;
  impl:3) AGENT="codex"; MODEL="${FT_LUNA_MODEL:-gpt-5.6-luna}"; EFFORT="high"; FAST="on";;
  '') ;; *) echo "unknown --tier $TIER (checker|tester[:1-3] · impl[:1-3])" >&2; exit 2;;
esac
# 역할을 seats.json 에 남긴다 — 세션 상태 절·stall 대상 판정이 «checker/tester/impl» 을 가른다
ROLE="${TIER%%:*}"; ROLE="${ROLE:-nano}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel)"                       # 호출 워크트리(기준 브랜치의 자리)
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
SEATS="$ROOT/.fable-team/seats.json"; MBOX="$HERE/../comm/mbox.sh"
[ -f "$IDX" ] || { echo "REJECT 인덱스 없음: $IDX"; exit 1; }
case "$IDX" in */대기/*) ;; *) echo "REJECT 대기/ 에 있는 인덱스만 연다: $IDX"; exit 1;; esac
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }

# ① lint — 누가 읽어도 착수 가능한가
bash "$HERE/ft-index-lint.sh" "$IDX" || { echo "REJECT lint 실패"; exit 1; }

SLUG="$(basename "$IDX" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | cut -c1-40)"
BASE_NAME="${FT_NANO_PREFIX:-ft-v65-temp-}$SLUG"
N=0; while tmux has-session -t "=$BASE_NAME#$N" 2>/dev/null; do N=$((N+1)); done
NAME="$BASE_NAME#$N"
BRANCH="nano/$SLUG"; WTDIR="$ROOT/.worktrees/${FT_NANO_WT_PREFIX:-v65-}$SLUG"
BASE_BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD)"
IDX_ABS="$(cd "$(dirname "$IDX")" && pwd)/$(basename "$IDX")"
IDX_REL="${IDX_ABS#$WT/}"

# tmuxc 옵션은 에이전트별로 다르다 — `--ctx` 는 claude 만, `--effort` 는 claude·cmd·codex, `--fast` 는 codex 만 (ft-role-spawn 과 같은 분기)
OPEN=(tmuxc open "$WTDIR" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && OPEN+=(--ctx 1m)
case "$AGENT" in claude|cmd|codex) OPEN+=(--effort "$EFFORT");; esac
[ "$AGENT" = codex ] && [ -n "$FAST" ] && OPEN+=(--fast "$FAST")
echo "PLAN seat=$NAME agent=$AGENT model=$MODEL${TIER:+ tier=$TIER}${FAST:+ fast=$FAST} wt=$WTDIR branch=$BRANCH base=$BASE_BRANCH index=$IDX_REL"
if [ "$DRY" = 1 ]; then "${OPEN[@]}" --dry-run; exit 0; fi

# ② 워크트리 — 이미 있으면 재사용(재발주), 없으면 기준 브랜치에서 분기
if [ ! -d "$WTDIR" ]; then
  git -C "$ROOT" worktree add "$WTDIR" -b "$BRANCH" "$BASE_BRANCH" >/dev/null || { echo "REJECT worktree add 실패"; exit 1; }
  for l in .venv .env; do [ -e "$ROOT/$l" ] && ln -sfn "../../$l" "$WTDIR/$l"; done
  printf '{"branch":"%s","created_at":"%s","purpose":"nano · %s"}\n' "$BRANCH" "$(date +%F)" "$IDX_REL" > "$WTDIR/.worktree-info.json"
fi

# ③ 열기 — 모델 인자에 대괄호가 있어 zsh 글롭 즉사 함정(글로벌 규칙) → 이 스크립트는 bash 라 그대로 통과
"${OPEN[@]}" >/dev/null 2>&1 || { echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
tmux has-session -t "=$NAME" 2>/dev/null || { echo "REJECT 세션이 안 떴다: $NAME"; exit 1; }

# ④ 소실 방지 두 줄 — E-190(remain-on-exit 없어 pane 통째 소실) · E-212(태그 없어 zombie-clean 이 kill)
# ★`-t "=$NAME"` 은 has-session 에만 통한다★ (실측 2026-09-14): `#` 든 이름에 set-option/display-message 는
#   `no such session`. pane_id 로 해석해 넘긴다(mbox.sh pane_of 와 같은 이유). 세션 옵션은 pane 타겟으로도 세션에 박힌다.
PANE="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' | awk -F'|' -v s="$NAME" '$1==s{print $2; exit}')"
[ -n "$PANE" ] || { echo "REJECT pane 못 찾음: $NAME"; exit 1; }
tmux set-option -t "$PANE" remain-on-exit on
tmux set-option -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}" 1
[ "$(tmux show-option -qv -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}")" = 1 ] || { echo "REJECT 태그 확인 실패: $NAME"; exit 1; }

# ⑤ seats.json 등록 (tick=null → 알림 울림)
python3 - "$SEATS" "$NAME" "$AGENT" "$MODEL" "$IDX_REL" "$ROLE" <<'PY'
import json, sys, collections
p, name, agent, model, idx, role = sys.argv[1:7]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
d[name] = collections.OrderedDict([("role",role),("agent",agent),("tick",None),("model",model),("index",idx.replace("/대기/","/진행/"))])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY

# ⑥ 대기→진행 (호출 워크트리에서 git mv — 인덱스 폴더의 정본은 기준 브랜치)
bash "$HERE/ft-index-move.sh" "$IDX" 진행 --seat "$NAME" || { echo "REJECT 인덱스 이동 실패"; exit 1; }
NEW_IDX="${IDX_REL/\/대기\//\/진행\/}"

# ⑦⑧ 첫 발주 = 인덱스 경로 한 줄 + README. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
BODY="[Seatbelt 발주] 네 인덱스: $WT/$NEW_IDX — 먼저 $WT/${FT_SEATBELT_README:-design/v65/SEATBELT-README.md} §2 부팅 5단계(첫 보고까지), 그 다음 인덱스 §구현 범위만. 커밋은 브랜치 $BRANCH, push 금지. 산출 경로를 mbox 로 $FROM 에."
sleep 8   # 에이전트 부팅. 짧으면 doorbell 이 셸에 떨어진다(noagent)
if FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; then
  echo "SPAWNED $NAME index=$NEW_IDX wt=$WTDIR"; exit 0
fi
rc=$?; echo "SPAWNED-UNVERIFIED $NAME rc=$rc — 좌석은 떴다. 도달을 사람이 확인"; exit 5
