#!/usr/bin/env bash
# ft-role-spawn.sh <master|da|pm|arch|tester> [--agent claude|codex|cmd|opencode] [--model ID] [--effort E] [--from <발주좌석>] [--dry-run]
#   Seatbelt 0.3 · 역할 좌석(master·da·pm)을 «갈아 끼운다» (SEATBELT-README §4 · DRAFT §0-A-2 · §4 표 4b).
#   exit 0 = 열림+도달 · 1 = 실패(사유 stdout) · 2 = usage · 5 = 열렸으나 도달 미확인(사람 확인)
#   상향 모델(claude-fable-*·*astra* · 판정 1641)은 --raise "<사유>" --raise-card <indices/…/X.md> 필수 — 명부 행에 raised{reason,card,by,at,close_on} (R149)
# ft-nano-spawn.sh 를 본떴다. 차이 셋:
#   ① 워크트리를 새로 만들지 않는다 — 역할 좌석은 «이 워크트리»(호출한 곳)에 뜬다.
#   ② seats.json 은 «등록»이 아니라 «교체» — 같은 role 의 기존 행에 `_replaced_by:<새 좌석>` 을 남기고,
#      새 행에 `_replaces:[구 좌석…]` 을 적는다. 구 행은 지우지 않는다(계보). ★구 좌석은 kill 하지 않는다★(정지 레디 — HIL).
#      ⇒ seats.json 을 읽는 쪽(틱·모니터)은 `_replaced_by` 가 있는 행을 «현역이 아님»으로 건너뛴다.
#   ③ 첫 발주 = 「README §2 부팅 5단계 → indices/inbox/<role>/ 정렬해 맨 위부터」 한 줄. 본문은 파일(인박스)에 있다.
# 새 좌석의 tick 은 null(=doorbell 울림). 틱 데몬이 seats.json 을 따라오는 것은 0.4(ft-tick.sh) — 그 전엔 알림이 울리는 쪽이 안전하다.
# ★런타임 자리는 <워크트리>/.fable-team/bin/ (gitignore) — 추적 사본은 scripts/fable-team-bin/ (ft-goal-check 관례).★
set -uo pipefail
ROLE="${1:-}"; shift || { echo "usage: $0 <master|da|pm|arch|tester> [--agent A] [--model M] [--effort E] [--from SEAT] [--dry-run]" >&2; exit 2; }
case "$ROLE" in master|da|pm|arch|tester) ;; *) echo "usage: role 은 master|da|pm|arch|tester (받은 값: $ROLE)" >&2; exit 2;; esac
# 오빠 2026-09-29 「arch도 fable 쓰지말고 opus5.5 high 쓰자 이후로는」
AGENT="claude"; MODEL="claude-opus-5-5[1m]"; EFFORT="high"; FROM="${FT_SEND_FROM:-dispatch}"; DRY=0; RAISE=""; RAISE_CARD=""
while [ $# -gt 0 ]; do case "$1" in
  --agent) AGENT="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --effort) EFFORT="$2"; shift 2;;
  --raise) RAISE="${2:-}"; shift 2 2>/dev/null || shift;; --raise-card) RAISE_CARD="${2:-}"; shift 2 2>/dev/null || shift;;
  --from) FROM="$2"; shift 2;; --dry-run) DRY=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
# 오빠 확정(2026-09-24 · 09-28 재확인 · 09-29 세 번째 재발): v65 DA astra = low. 기본 high 로 뜨는 사고가 반복돼 여기서 막는다.
case "$MODEL" in gpt-6-astra*) [ "$EFFORT" = "low" ] || { echo "REJECT: gpt-6-astra 는 --effort low 만 (받은 값: $EFFORT) — 오빠 확정" >&2; exit 2; };; esac
case "$AGENT" in claude|codex|cmd|opencode) ;; *) echo "usage: --agent 는 claude|codex|cmd|opencode (받은 값: $AGENT)" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# ★자원 게이트 (Res-1014)★: 디스크·스왑·메모리·에이전트 수가 한계를 넘으면 열지 않는다(부작용 전). 우회 플래그 없음 — 조정은 env 문턱만.
[ -f "$HERE/ft-resource-gate.sh" ] || { echo "REJECT ft-resource-gate.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
_rgout="$(bash "$HERE/ft-resource-gate.sh" check 2>&1)"; _rgrc=$?
# R198(판정 1767): 에이전트 수로 막혔을 때만 — 기존 표준승인 범위 안의 유휴·완료 좌석을 자동 정리한 뒤 문지기 재검(FT_RECLAIM=0 으로 끔)
if [ "$_rgrc" != 0 ] && [ "${FT_RECLAIM:-1}" != 0 ] && [ -f "$HERE/ft-resource-reclaim.sh" ]; then
  _rgout="$(bash "$HERE/ft-resource-reclaim.sh" --on-reject "$_rgout" --gate "$HERE/ft-resource-gate.sh" 2>&1)"; _rgrc=$?
  [ "$_rgrc" = 0 ] && printf '%s\n' "$_rgout" >&2
fi
[ "$_rgrc" != 0 ] && { printf '%s\n' "$_rgout"; exit "$_rgrc"; }
# R149(판정 1641): 상향 모델은 사유 + 닫는 단위 카드 필수 — 해석이 끝난 실제 MODEL 로 판정, 부작용(tmux·명부) «전». rc 0=상향 1=기본 그 밖=도구 고장(조용히 기본 취급 0)
python3 "$HERE/ft_raised.py" is-raised "$MODEL"; _rrc=$?
case "$_rrc" in
  0) { [ -n "${RAISE//[[:space:]]/}" ] && [ -n "${RAISE_CARD//[[:space:]]/}" ]; } || { echo "REJECT 상향 모델($MODEL)은 --raise \"<사유>\" 와 --raise-card <닫는 단위 카드 경로> 필수 — 닫히면 원래 모델로(판정 1641)"; exit 1; };;
  1) ;;
  *) echo "REJECT ft_raised.py 판정 실패 rc=$_rrc ($HERE/ft_raised.py) — 부작용 0"; exit 1;;
esac
WT="$(git rev-parse --show-toplevel)"                       # 역할 좌석이 뜨는 자리 = 이 워크트리
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')"   # 리포 루트
SEATS="$ROOT/.fable-team/seats.json"
INBOX_REL="design/v65/indices/inbox/$ROLE"; INBOX="$WT/$INBOX_REL"
README="$WT/design/v65/SEATBELT-README.md"
[ -f "$SEATS" ] || { echo "REJECT seats.json 없음: $SEATS"; exit 1; }
[ -d "$INBOX" ] || { echo "REJECT 인박스 폴더 없음: $INBOX (indices/inbox/<role>/ 가 먼저 있어야 후계가 읽을 것이 있다)"; exit 1; }
[ -f "$README" ] || { echo "REJECT SEATBELT-README 없음: $README (첫 발주가 가리키는 파일)"; exit 1; }

# 이름: byz-v65-<role>-<agent>#<N+1> — N = tmux 세션 + seats.json 키 중 «세 베이스(BASE_NAME·NEW_BASE·OLD_BASE)» 의 최댓값 (없으면 -1 → #0)
BASE_NAME="${FT_ROLE_BASE_PREFIX:-byz-v65-}$ROLE-$AGENT"   # 기본 = 정본 이름 byz-v65-… (오빠 10-07) · FT_ROLE_BASE_PREFIX 로 바꿀 수 있음
NEW_BASE="byz-v65-$ROLE-$AGENT"                             # 정본 계보
OLD_BASE="ft-v65-$ROLE-$AGENT"                              # 옛 계보 — 접두를 무엇으로 주든 두 계보 모두 번호 이어받기·교체 대상
maxn="$( { tmux ls -F '#{session_name}' 2>/dev/null; python3 -c 'import json,sys;print("\n".join(json.load(open(sys.argv[1],encoding="utf-8")).keys()))' "$SEATS"; } \
  | awk -v a="$BASE_NAME#" -v b="$NEW_BASE#" -v c="$OLD_BASE#" '{p=""; if(index($0,a)==1){p=a}else if(index($0,b)==1){p=b}else if(index($0,c)==1){p=c}; if(p!=""){n=substr($0,length(p)+1); if(n ~ /^[0-9]+$/ && n+0>m){m=n+0}; f=1}} END{print (f?m:-1)}')"
N=$((maxn+1)); while tmux has-session -t "=$BASE_NAME#$N" 2>/dev/null; do N=$((N+1)); done
NAME="$BASE_NAME#$N"

# 교체 대상 = 같은 role 이고 아직 _replaced_by 가 없는 행 (읽기만 — 실제 교체는 좌석이 뜬 뒤)
OLD="$(python3 - "$SEATS" "$ROLE" "$BASE_NAME" "$NEW_BASE" "$OLD_BASE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(" ".join(k for k, v in d.items() if isinstance(v, dict) and v.get("role") == sys.argv[2] and not v.get("_replaced_by") and k.split("#")[0] in (sys.argv[3], sys.argv[4], sys.argv[5])))
PY
)"
# tmuxc 옵션은 에이전트별로 다르다(tmuxc 도움말: `--ctx` 는 claude 만 · `--effort` 는 claude·cmd·codex). 안 받는 옵션을 넘기면
# tmuxc 가 거부한다(실측 dry-run 2026-09-14: `--ctx 는 --agent claude 에서만 사용 (agent=codex)`). 받는 것만 넘긴다.
OPEN=(tmuxc open "$WT" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && OPEN+=(--ctx 1m)
case "$AGENT" in claude|cmd|codex) OPEN+=(--effort "$EFFORT");; esac

# 첫 발주 = README §2 → inbox 정렬. 본문은 파일에 있다. 도달은 jsonl 층(ft-send-verified)
BODY="[Seatbelt 역할 교체] 너는 $ROLE 후계 좌석($NAME). 먼저 $README §2 부팅 5단계(첫 보고까지), 그 다음 $INBOX/ 를 정렬해 «맨 위» 파일부터 이어간다. 구 좌석 ${OLD:-없음} 은 정지 레디(kill 금지). 보고는 mbox 로 $FROM 에."
# 세션 크론은 승계로 옮겨지지 않는다 — master·arch 후계는 부팅 보고 그 턴에 체크 틱을 직접 건다(BOOT 16 · 원장 R13). da·pm·tester 는 해당 없음.
case "$ROLE" in master|arch) BODY="$BODY ★부팅 보고를 보낸 그 턴에 CronCreate 10분 체크 틱(mbox recv + 하위 pane 실측 + 오빠 3줄)을 건다 — 없으면 착수 0 · 부팅 보고에 cron=<job id> (BOOT 16)★";; esac
# 승계 좌석 부팅 보고 게이트(P4 · 판정 1155 ①) — retire 칸이 없으면 쪽지 도구(mbox_guard)가 반송한다. 구 좌석이 있을 때만 붙인다.
[ -n "${OLD:-}" ] && BODY="$BODY ★부팅 보고에 retire=<구>-><후계> rc=0 칸 필수 — ft-seat-retire.sh <구> <후계> 를 먼저 실행해 출력을 복붙(칸이 없으면 쪽지 도구가 반송) — 출력 둘째 줄(RESUME ok … 또는 NORECORD …)도 retire 칸 옆에 그대로 붙인다(재개 기록 · 판정 1344)★"
# 고스트 서제스천(R21 · BOOT 17) — 남의 pane 을 읽는 전 역할에 붙인다.
BODY="$BODY ★남의 pane ❯ 뒤 글자 = 자동완성 제안 — 사용자 입력으로 착각 금지 · 그 줄로 보고·인터뷰·Enter 0 · 판단 근거는 jsonl·✻ done 줄뿐 (BOOT 17)★"
BODY="$BODY ★측정 조작 금지(오빠 절대지침) — 임의 Redis 쓰기(redis-cli SET·HSET·XADD·PUBLISH 등 제품 키 직접 주입)·말풍선 DOM 주입(재생 하네스·/dev/bubble-replay·appendChild)으로 만든 결과는 증거 아님 · 측정은 trusted 클릭 + 기존 e2e 러너의 실제 음성 경로만 · 격리 Redis 픽스처 시험은 별개 · 이미 썼으면 [HIL] 로 올림 (BOOT 20)★"

echo "PLAN seat=$NAME role=$ROLE agent=$AGENT model=$MODEL wt=$WT inbox=$INBOX_REL replaces=[${OLD:-<없음>}] (구 좌석 kill 안 함)"
if [ "$DRY" = 1 ]; then echo "BODY $BODY"; "${OPEN[@]}" --dry-run; exit $?; fi
# 실전은 도달 판정기가 같은 디렉터리에 있어야 한다(런타임 .fable-team/bin). 추적 사본(scripts/)에서 dry-run 만 돌리는 경우는 위에서 끝났다.
[ -x "$HERE/ft-send-verified.sh" ] || { echo "REJECT ft-send-verified.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }

# 열기 — 모델 인자의 대괄호는 bash 라 글롭 안 됨(zsh 함정은 이 스크립트 밖)
"${OPEN[@]}" >/dev/null 2>&1 || { echo "REJECT tmuxc open 실패 ($NAME)"; exit 1; }
tmux has-session -t "=$NAME" 2>/dev/null || { echo "REJECT 세션이 안 떴다: $NAME"; exit 1; }

# 소실 방지 두 줄 — pane_id 경유 (`-t "=$NAME"` 은 set-option 에 안 통한다 — nano-spawn ④ 실측 2026-09-14)
PANE="$(tmux list-panes -a -F '#{session_name}|#{pane_id}' | awk -F'|' -v s="$NAME" '$1==s{print $2; exit}')"
[ -n "$PANE" ] || { echo "REJECT pane 못 찾음: $NAME"; exit 1; }
tmux set-option -t "$PANE" remain-on-exit on
tmux set-option -t "$PANE" @zc_v65_active 1
[ "$(tmux show-option -qv -t "$PANE" @zc_v65_active)" = 1 ] || { echo "REJECT 태그 확인 실패: $NAME"; exit 1; }

# seats.json 행 교체 — 구 행은 남기고 _replaced_by 만 찍는다. ★새 행의 tick 은 «구 좌석에서 물려받는다»★.
# 2026-09-22 실측: 새 행을 tick=null 로 만들면 구 master 를 _replaced_by 로 닫는 순간 틱 대상이 0 이 되어
# ft-tick.sh 가 «no active seat with tick» 만 찍고 뉴스 발행이 통째로 멈춘다(15:03~15:08 · 5틱 연속).
# 위 11행 주석의 「틱 데몬이 seats.json 을 따라오는 것은 0.4 — 그 전엔 null 이 안전」은 stale 이다 —
# 지금 도는 ft-tick.sh 가 이미 그 0.4 이고, 매 루프 seats.json 을 다시 읽는다.
python3 - "$SEATS" "$NAME" "$ROLE" "$AGENT" "$MODEL" "$INBOX_REL" "$NEW_BASE" "$OLD_BASE" "$RAISE" "$RAISE_CARD" "$FROM" <<'PY'
import json, sys, collections, datetime
p, name, role, agent, model, inbox, new_base, old_base, raise_reason, raise_card, by = sys.argv[1:12]
d = json.load(open(p, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
# 같은 계열(베이스명 = #N 앞)만 잇는다 — 역할만 같으면 다른 트랙(CFO_F_ARCH 등) 좌석까지 닫는다(2026-09-29 CFO#30 제보).
base = name.split("#")[0]
old = [k for k, v in d.items() if isinstance(v, dict) and v.get("role") == role and not v.get("_replaced_by") and k != name and k.split("#")[0] in (base, new_base, old_base)]
# 승계는 «자리»를 잇는 것이라 그 자리의 틱도 잇는다. 구 좌석이 없으면 역할 기본값.
tick = next((d[k].get("tick") for k in old if d[k].get("tick")), None) \
       or {"master": "ft-master-tick", "pm": "ft-pm-tick"}.get(role)
for k in old:  # R43: _replaced_by 만으론 tick·role·_<역할> 키가 옛 좌석에 남는다 — ft-seat-retire.sh 와 같은 규칙으로 닫는다
    d[k]["_replaced_by"] = name; d[k]["_retired_role"] = d[k].get("role"); d[k]["tick"] = None; d[k]["role"] = "stop-ready"
    for tk, tv in d.items():
        if tk.startswith("_") and tv == k: d[tk] = name
d[name] = collections.OrderedDict([("role", role), ("agent", agent), ("tick", tick), ("model", model), ("index", inbox + "/"), ("_replaces", old)])
if raise_reason.strip() and raise_card.strip():   # R149: index(=inbox) 의미는 그대로 두고 «닫는 단위 카드» 는 raised.card 에만 — ft-tick raised_watch 가 ▶내릴 것
    d[name]["raised"] = collections.OrderedDict([("reason", raise_reason.strip()), ("card", raise_card.strip()), ("by", by), ("at", datetime.datetime.now().isoformat(timespec="seconds")), ("close_on", "card 가 완성/ 으로 가거나 없어짐 · 또는 좌석 닫기")])
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2); open(p, "a").write("\n")
PY
echo "SEATS role=$ROLE now=$NAME replaced=[${OLD:-<없음>}] — 구 좌석은 정지 레디(kill 은 사람 승인)"

sleep 8   # 에이전트 부팅. 짧으면 doorbell 이 셸에 떨어진다(noagent)
if FT_SEND_FROM="$FROM" bash "$HERE/ft-send-verified.sh" "$NAME" "$BODY"; then
  echo "SPAWNED $NAME role=$ROLE inbox=$INBOX_REL wt=$WT"; exit 0
fi
rc=$?; echo "SPAWNED-UNVERIFIED $NAME rc=$rc — 좌석은 떴다(seats.json 교체 완료). 도달을 사람이 확인"; exit 5
