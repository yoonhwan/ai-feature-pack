#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT(Seatbelt 1.0.0).★
# ft-role-spawn.sh <master|da|pm> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--from <발주좌석>] [--dry-run]
#   Seatbelt 0.3 · 역할 좌석(master·da·pm)을 «갈아 끼운다» (SEATBELT-README §4 · DRAFT §0-A-2 · §4 표 4b).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인)
# ft-nano-spawn.sh 를 본떴다. 차이 셋:
#   ① 워크트리를 새로 만들지 않는다 — 역할 좌석은 «이 워크트리»(호출한 곳)에 뜬다.
#   ② seats.json 은 «등록»이 아니라 «교체» — 같은 role 의 기존 행에 `_replaced_by:<새 좌석>` 을 남기고,
#      새 행에 `_replaces:[구 좌석…]` 을 적는다. 구 행은 지우지 않는다(계보). ★구 좌석은 kill 하지 않는다★(정지 레디 — HIL).
#      ⇒ seats.json 을 읽는 쪽(틱·모니터)은 `_replaced_by` 가 있는 행을 «현역이 아님»으로 건너뛴다.
#   ③ 첫 발주 = 「README §2 부팅 5단계 → indices/inbox/<role>/ 정렬해 맨 위부터」 한 줄. 본문은 파일(인박스)에 있다.
# 새 좌석의 tick 은 null(=doorbell 울림). 틱 데몬이 seats.json 을 따라오는 것은 0.4(ft-tick.sh) — 그 전엔 알림이 울리는 쪽이 안전하다.
# ★런타임 자리는 <워크트리>/.fable-team/bin/ (gitignore) — 추적 사본은 scripts/fable-team-bin/ (ft-goal-check 관례).★
set -uo pipefail
ROLE="${1:-}"; shift || { echo "usage: $0 <master|da|pm> [--agent A] [--model M] [--effort E] [--from SEAT] [--dry-run]" >&2; exit 2; }
case "$ROLE" in master|da|pm) ;; *) echo "usage: role 은 master|da|pm (받은 값: $ROLE)" >&2; exit 2;; esac
AGENT="claude"; MODEL="claude-fable-5-1[1m]"; EFFORT="high"; FROM="${FT_SEND_FROM:-dispatch}"; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; shift 2;;
  --from) FROM="$2"; shift 2;; --dry-run) DRY=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$AGENT" in claude|codex|cmd|opencode) ;; *) echo "usage: --agent 는 claude|codex|cmd|opencode (받은 값: $AGENT)" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel)"                       # 역할 좌석이 뜨는 자리 = 이 워크트리
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
SEATS="$ROOT/.fable-team/seats.json"
INBOX_REL="${FT_INBOX_ROOT:-design/v65/indices/inbox}/$ROLE"; INBOX="$WT/$INBOX_REL"
README="$WT/${FT_SEATBELT_README:-design/v65/SEATBELT-README.md}"
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }
[ -d "$INBOX" ] || { echo "REJECT 인박스 폴더 없음: $INBOX (indices/inbox/<role>/ 가 먼저 있어야 후계가 읽을 것이 있다)"; exit 1; }
[ -f "$README" ] || { echo "REJECT SEATBELT-README 없음: $README (첫 발주가 가리키는 파일)"; exit 1; }

# 이름: ft-v65-<role>-<agent>#<N+1> — N = tmux 세션 + seats.json 키 중 같은 베이스의 최댓값 (없으면 -1 → #0)
BASE_NAME="ft-v65-$ROLE-$AGENT"
maxn="$( { tmux ls -F '#{session_name}' 2>/dev/null; python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1],encoding="utf-8")).keys()))' "$SEATS"; } \
  | awk -v b="$BASE_NAME#" 'index($0,b)==1{n=substr($0,length(b)+1); if(n ~ /^[0-9]+$/ && n+0>m){m=n+0}; f=1} END{print (f?m:-1)}')"
N=$((maxn+1)); while tmux has-session -t "=$BASE_NAME#$N" 2>/dev/null; do N=$((N+1)); done
NAME="$BASE_NAME#$N"

# 교체 대상 = 같은 role 이고 아직 _replaced_by 가 없는 행 (읽기만 — 실제 교체는 좌석이 뜬 뒤)
OLD="$(python3 - "$SEATS" "$ROLE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(" ".join(k for k, v in d.items() if isinstance(v, dict) and v.get("role") == sys.argv[2] and not v.get("_replaced_by")))
PY
)"
# tmuxc 옵션은 에이전트별로 다르다(tmuxc 도움말: `--ctx` 는 claude 만 · `--effort` 는 claude·cmd·codex). 안 받는 옵션을 넘기면
# tmuxc 가 거부한다(실측 dry-run 2026-09-14: `--ctx 는 --agent claude 에서만 사용 (agent=codex)`). 받는 것만 넘긴다.
OPEN=(tmuxc open "$WT" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && OPEN+=(--ctx 1m)
case "$AGENT" in claude|cmd|codex) OPEN+=(--effort "$EFFORT");; esac

echo "PLAN seat=$NAME role=$ROLE agent=$AGENT model=$MODEL wt=$WT inbox=$INBOX_REL replaces=[${OLD:-<없음>}] (구 좌석 kill 안 함)"
if [ "$DRY" = 1 ]; then "${OPEN[@]}" --dry-run; exit $?; fi
# 실전은 도달 판정기가 같은 디렉터리에 있어야 한다(런타임 .fable-team/bin). 추적 사본(scripts/)에서 dry-run 만 돌리는 경우는 위에서 끝났다.
[ -x "$HERE/ft-send-verified.sh" ] || { echo "REJECT ft-send-verified.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }

# 열기 — 모델 인자의 대괄호는 bash 라 글롭 안 됨(zsh 함정은 이 스크립트 밖)
"${OPEN[@]}" >/dev/null 2>&1 || { echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
tmux has-session -t "=$NAME" 2>/dev/null || { echo "REJECT 세션이 안 떴다: $NAME"; exit 1; }

# 소실 방지 두 줄 — pane_id 경유 (`-t "=$NAME"` 은 set-option 에 안 통한다 — nano-spawn ④ 실측 2026-09-14)
PANE="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' | awk -F'|' -v s="$NAME" '$1==s{print $2; exit}')"
[ -n "$PANE" ] || { echo "REJECT pane 못 찾음: $NAME"; exit 1; }
tmux set-option -t "$PANE" remain-on-exit on
tmux set-option -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}" 1
[ "$(tmux show-option -qv -t "$PANE" "${FT_ACTIVE_TAG:-@zc_v65_active}")" = 1 ] || { echo "REJECT 태그 확인 실패: $NAME"; exit 1; }

# seats.json 행 교체 — 구 행은 남기고 _replaced_by 만 찍는다. 새 행 tick=null(알림 울림).
python3 - "$SEATS" "$NAME" "$ROLE" "$AGENT" "$MODEL" "$INBOX_REL" <<'PY'
import json, sys, collections
p, name, role, agent, model, inbox = sys.argv[1:7]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
old = [k for k, v in d.items() if isinstance(v, dict) and v.get("role") == role and not v.get("_replaced_by") and k != name]
for k in old:
    d[k]["_replaced_by"] = name
d[name] = collections.OrderedDict([("role", role), ("agent", agent), ("tick", None), ("model", model), ("index", inbox + "/"), ("_replaces", old)])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY
echo "SEATS role=$ROLE now=$NAME replaced=[${OLD:-<없음>}] — 구 좌석은 정지 레디(kill 은 사람 승인)"

# 첫 발주 = README §2 → inbox 정렬. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
BODY="[Seatbelt 역할 교체] 너는 $ROLE 후계 좌석($NAME). 먼저 $README §2 부팅 5단계(첫 보고까지), 그 다음 $INBOX/ 를 정렬해 «맨 위» 파일부터 이어간다. 구 좌석 ${OLD:-없음} 은 정지 레디(kill 금지). 보고는 mbox 로 $FROM 에."
sleep 8   # 에이전트 부팅. 짧으면 doorbell 이 셸에 떨어진다(noagent)
if FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; then
  echo "SPAWNED $NAME role=$ROLE inbox=$INBOX_REL wt=$WT"; exit 0
fi
rc=$?; echo "SPAWNED-UNVERIFIED $NAME rc=$rc — 좌석은 떴다(seats.json 교체 완료). 도달을 사람이 확인"; exit 5
