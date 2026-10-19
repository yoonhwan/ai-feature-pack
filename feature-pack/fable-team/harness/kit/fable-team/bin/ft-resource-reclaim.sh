#!/usr/bin/env bash
# ft-resource-reclaim.sh [--dry-run] --caller <세션명> --need <n> [--team <팀>]
#   --team = 그 팀 나노만 후보(이름 접두 `byz-<팀>-nano-`(v65 = `ft-v65-temp-`) ∧ 그 팀 명부 `seats-<팀>.json`(v65 = 기본 명부)에 행) — 팀셋 나노 상한(ft-nano-spawn.sh)이 부른다 · 닫기 직전 fresh_ok 가 소속을 다시 확인(DA r1 ⑤)
# ft-resource-reclaim.sh [--dry-run] --preventive
#   R332 · 선제 모드 — 문지기 상태와 무관하게 승인 두 행의 후보를 «전부» 닫는다(감시자 ft-resource-preventive.sh 가 600초마다 부름 · 새 파괴 권한 0).
#     문지기 호출·재검 0 · [HIL]·재부팅 줄 0 · 닫기 직전 fresh_ok 재검증은 그대로 · 잠금 경합이면 대기 0 → `PREVENTIVE skipped=lock`(rc0 · 다음 틱 재시도).
#     R332·판정 2197(오빠 2026-10-17 · N=3시간): 선제 모드에서만 세 번째 후보 «쉬는 역할 좌석» — 팀 명부 `_master`·`_arch` 현역(planner 명부·`_hil_route`·`_desk` 제외 · 명부 행 role=master|arch)이 ★대기 카드 0(그 팀 `<_cards_wt>/<_cards>/대기/*.md`)·mbox pending 0·턴 종료 FT_RECLAIM_ROLE_IDLE_MIN(180분)↑ IDLE★ 이고 검증된 재개 기록이 있으면 tmux kill-session(재개 `zombie-clean.sh resume`). --on-reject 경로는 그대로(역할 좌석 닫기 0).
#     출력 마지막 1줄 `PREVENTIVE reclaimed=N candidates=M skipped=K`(reclaim.log 에도 append · 뉴스 첫 줄 reclaimed=N 이 읽는 줄) · --dry-run = 실행권·로그·닫기 0.
# ft-resource-reclaim.sh [--dry-run] --on-reject "<문지기 출력>" [--caller <세션명>] [--gate <ft-resource-gate.sh>]
#   R198(판정 1767) · 자원 문지기가 «에이전트 수» 로 막았을 때만 불려, 기존 표준승인 범위 안의 유휴·완료 좌석을 need 개 닫는다.
#   새 파괴 권한 0 — 닫는 경로는 승인 표의 두 행뿐(표 밖 kill 0 · 브랜치 삭제 0):
#     병합 끝 나노   : 세션 `*-nano-*#0` ∧ 가지 착지(r500 · `ft-landed-check.sh` rc0 = ancestor·cherry·card · 7초 상한) · 명부 index 카드 · jsonl IDLE → `ft-nano-close.sh` (그 도구의 게이트 그대로 · REJECT 면 후보 탈락)
#       착지 아님(grep·no·가지 없음·시간 초과) = «미병합 나노» — 닫지 않고 표 «승인 범위 밖» 줄만(fail-closed)
#     직전 세대 좌석 : 같은 계보에 더 새 #N 현역 · 검증된 재개 기록(zombie-clean resume_record_check 와 같은 규칙 + pid) · idle·attached·라이브서버·V65 active 가드 → tmux kill-session
#   그 밖(현역 역할 좌석·기록 없는 직전 세대·codex DA 등)은 닫지 않고 표의 «승인 범위 밖» 으로만 올린다.
#   제외(후보 아님): 부르는 쪽 세션과 그 조상 pane · 명부 `_*` 상위 오케 · attached · jsonl WORKING/PENDING/UNKNOWN · mbox pending>0 · press 허가 보유.
#   --on-reject: 출력이 `REJECT resource agents=A limit=L` 이면 need=A−L+1 로 1번 → 문지기 재검 OK 면 rc0 · 아니면 원래 REJECT + 표 + [HIL] 1통 후 rc3.
#     R320: `REJECT resource swap|memfree|level|rate=…` 도 받는다 — 필요 개수가 없으므로 승인 두 행의 후보를 «전부» 닫고 재검 · 그래도 REJECT 면 [HIL] 1통에 재부팅 계획(`ft-hil.sh --add` 가 돌려주는 `! bash /tmp/h<N>` 1줄 · 안내만 · 재부팅은 사람 손).
#     병합 끝 나노(카드가 indices/완성/ 에 있음 · 또는 r500 압력 = swap 사용률 ≥ FT_RECLAIM_PRESSURE_SWAP_PCT(기본 85))는 idle 문턱 FT_RECLAIM_DONE_IDLE_MIN(기본 5분) · 그 밖 후보는 FT_RECLAIM_IDLE_MIN(기본 30분).
#     표 끝 요약 줄(RECLAIMED · PREVENTIVE)에 `pressure=0|1 swap=<pct>%` · swap 측정 실패 = 압력 아님 + `WARN swap 측정 실패` 1줄.
#     다른 사유(디스크·동결·측정 실패 ERROR)·형식 불일치는 손대지 않고 그대로 rc3·rc4 (좌석을 닫아도 안 풀리는 사유).
#   FT_RECLAIM=0 이면 호출처가 이 도구를 부르지 않는다(시험·비상용 · 기본 1).
#   잠금 mkdir 로 동시 호출이 같은 좌석을 두 번 닫지 않는다 · 표는 .fable-team/state/reclaim.log 에 그대로 append · 비밀 0.
#   env(시험): FT_RES_ROOT FT_SEATS_JSON FT_SEAT_STATUS FT_NANO_CLOSE FT_MBOX_SH ZC_RESUME_DIR FT_RECLAIM_IDLE_MIN FT_RECLAIM_DONE_IDLE_MIN FT_RECLAIM_LOCK_TRIES FT_PRESS_PERMIT_DIR FT_HIL_SH FT_RECLAIM_ROLE_IDLE_MIN
#     FT_RECLAIM_PRESSURE_SWAP_PCT FT_SWAPUSAGE(가짜 `vm.swapusage` 줄 · 빈 값 = 측정 실패) FT_LANDED_CHECK FT_PACK_ROOT(기본 ~/Project/ai-feature-pack)
#   bash 3.2 호환(declare -A·mapfile 금지) · 외부 호출 0(로컬 tmux·프로세스·파일·mbox·git 만).
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec

DRY=0; CALLER=""; NEED=""; ONREJ=""; HAVE_ONREJ=0; GATE=""; TEAM=""; PREV=0; MODE=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) DRY=1; shift;; --caller) CALLER="${2:-}"; shift 2 2>/dev/null || shift;; --need) NEED="${2:-}"; shift 2 2>/dev/null || shift;;
  --on-reject) HAVE_ONREJ=1; ONREJ="${2:-}"; shift 2 2>/dev/null || shift;; --gate) GATE="${2:-}"; shift 2 2>/dev/null || shift;;
  --team) TEAM="${2:-}"; shift 2 2>/dev/null || shift;; --preventive) PREV=1; shift;;
  *) echo "usage: $0 [--dry-run] (--preventive | --caller <세션명> --need <n> | --on-reject \"<문지기 출력>\" [--caller <세션명>] [--gate <path>])" >&2; exit 2;; esac; done
[ "$PREV" = 0 ] || [ "$HAVE_ONREJ" = 0 ] || { echo "usage: --preventive 는 --on-reject 와 함께 쓰지 않는다" >&2; exit 2; }
# R213·R320: 좌석을 닫아 풀리는 사유(에이전트 수·스왑·메모리·압력·속도)가 아니면 정리할 것이 없다 — 시작 작업(tmux·명부)·exit 코드 변질 전에 그대로 돌려준다(측정 실패 ERROR 는 rc 4 유지).
if [ "$HAVE_ONREJ" = 1 ] && ! printf '%s\n' "$ONREJ" | grep -Eq '^REJECT resource (agents|swap|memfree|level|rate)='; then
  printf '%s\n' "$ONREJ"; printf '%s\n' "$ONREJ" | grep -q '^ERROR ' && exit 4; exit 3
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 3
STATE="$ROOT/.fable-team/state"
SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
SEATST="${FT_SEAT_STATUS:-$HERE/ft-seat-status.sh}"
NANOCLOSE="${FT_NANO_CLOSE:-$HERE/ft-nano-close.sh}"
MBOX="${FT_MBOX_SH:-}"; [ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 3; MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 형제 comm 폴더가 없다 — 데이터 루트의 comm
MAILBOX="$(dirname -- "$MBOX")/mailbox.jsonl"
RESUME_DIR="${ZC_RESUME_DIR:-$HOME/.claude/state/seat-resume}"
PERMITS="${FT_PRESS_PERMIT_DIR:-$ROOT/.fable-team/state/press-permits}"
IDLE_MIN="${FT_RECLAIM_IDLE_MIN:-30}"; DONE_IDLE_MIN="${FT_RECLAIM_DONE_IDLE_MIN:-5}"; ROLE_IDLE_MIN="${FT_RECLAIM_ROLE_IDLE_MIN:-180}"
HILBIN="${FT_HIL_SH:-$HERE/ft-hil.sh}"
LOCK="$STATE/reclaim.lock.d"; LOG="$STATE/reclaim.log"; HILSIG="$STATE/reclaim-hil.sig"
PRESS_PCT="${FT_RECLAIM_PRESSURE_SWAP_PCT:-85}"; PACK_ROOT="${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}"
LANDED="${FT_LANDED_CHECK:-$HERE/ft-landed-check.sh}"; TOBIN="$(command -v timeout || command -v gtimeout)"
SRVRE='server\.sh|uvicorn|next-server|next dev|caddy|redis-server|postgres|cli-proxy|headroom|hermes|[Oo]llama|node .*(dev|start|watch)'
[ "$DRY" = 1 ] || mkdir -p "$STATE" 2>/dev/null || { echo "ERROR reclaim 상태 폴더 생성 실패: $STATE" >&2; exit 4; }   # dry-run 은 파일시스템·mbox·kill 0 (DA⑥ H3)
# BYZ 명부 = 기본 명부 + 같은 폴더의 seats*.json(팀별). 후보 판정(H1)·상위 오케 보호·index 조회가 전부 이 목록을 본다.
ROSTERS="$SEATS"; for _r in "$(dirname -- "$SEATS")"/seats*.json; do [ -f "$_r" ] && [ "$_r" != "$SEATS" ] && ROSTERS="$ROSTERS
$_r"; done

# 보호 집합 = 부르는 쪽(--caller + 이 프로세스 조상이 쥔 tmux pane 의 세션) + 명부 `_*` 문자열 값(_master·_hil_route·_arch·_tester·_da …) = 상위 오케.
#   시작 시 1회 만든 값은 «후보 1차 거르기» 용일 뿐이다 — 닫기 직전엔 fresh_ok 가 이 함수를 «다시» 불러 현재 명부·조상을 다시 읽는다(H2 r3).
build_protect() {
  local r pv p n s2 panes
  if [ -z "${_ANC:-}" ]; then   # 부르는 쪽 + 이 프로세스 조상이 쥔 tmux pane 의 세션 — 실행 중 바뀌지 않으므로 한 번만 계산한다(조상 ps 반복이 가장 비쌌다 · R332 H5)
    _ANC=" "
    [ -z "$CALLER" ] || _ANC="$_ANC$CALLER "
    panes="$(tmux list-panes -a -F '#{session_name} #{pane_pid}' 2>/dev/null)"
    if [ -n "$panes" ]; then
      p=$$; n=0
      while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$n" -lt 40 ]; do
        s2="$(printf '%s\n' "$panes" | awk -v p="$p" '$2==p{print $1; exit}')"
        [ -z "$s2" ] || _ANC="$_ANC$s2 "
        p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; n=$((n+1))
      done
    fi
  fi
  # 명부는 «매번 지금» 다시 읽는다(H2 r3) — 파일당 python 1회로 두 집합(전체 `_*` 값 · 좁은 집합 = planner 명부 전부 + `_hil_route`·`_desk`)을 한꺼번에
  pv="$(printf '%s\n' "$ROSTERS" | while IFS= read -r r; do [ -f "$r" ] && python3 -c '
import json,sys
d=json.load(open(sys.argv[1])); pl=sys.argv[1].endswith("seats-planner.json")
ok=[(k,v) for k,v in d.items() if k.startswith("_") and isinstance(v,str) and v and " " not in v]
print(" ".join(v for k,v in ok)+"\t"+" ".join(v for k,v in ok if pl or k in ("_hil_route","_desk")))' "$r" 2>/dev/null; done)"
  PROTECT="$_ANC$(printf '%s\n' "$pv" | cut -f1 | tr '\n' ' ') "
  PROTECT_HARD="$_ANC$(printf '%s\n' "$pv" | cut -f2 | tr '\n' ' ') "   # R332: 쉬는 역할 좌석 후보용 좁은 보호 = 부르는 쪽·조상 + planner 명부 전부 + 모든 `_hil_route`·`_desk`
}
build_protect
HIL_ROUTE="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_hil_route",""))' "$SEATS" 2>/dev/null)"
protected() { case "$PROTECT" in *" $1 "*) return 0;; *) return 1;; esac; }
protected_hard() { case "$PROTECT_HARD" in *" $1 "*) return 0;; *) return 1;; esac; }

roster_table() {   # 모든 BYZ 명부의 행 → `이름<TAB>role<TAB>index` (파일당 python 1회 · reclaim_core 시작 시 RTAB 에 담는다)
  local r
  while IFS= read -r r; do [ -f "$r" ] && python3 -c '
import json,sys
for k,v in json.load(open(sys.argv[1])).items():
    if isinstance(v,dict):
        g=lambda f: v.get(f) if isinstance(v.get(f),str) else ""
        print("\t".join((k,g("role"),g("index"))))' "$r" 2>/dev/null; done < <(printf '%s\n' "$ROSTERS")
}
RTAB=""
roster_field() {   # $1=세션명 $2=role|index → 값(없으면 빈 문자열). RTAB 스냅샷의 첫 비어 있지 않은 값 — 후보 1차 거르기 전용(닫기 직전 재확인은 live)
  printf '%s\n' "$RTAB" | awk -F'\t' -v n="$1" -v f="$2" '$1==n{v=(f=="role")?$2:$3; if(v!=""){printf "%s", v; exit}}'
}
in_roster() {   # $1=세션명 → rc0 = BYZ 명부(seats*.json)에 행이 있다
  local r; while IFS= read -r r; do [ -f "$r" ] || continue
    python3 -c 'import json,sys;sys.exit(0 if isinstance(json.load(open(sys.argv[1])).get(sys.argv[2]),dict) else 1)' "$r" "$1" 2>/dev/null && return 0
  done < <(printf '%s\n' "$ROSTERS")
  return 1
}
team_ok() {   # $1=세션명 → rc0 = --team 팀의 나노(이름 접두 ∧ 그 팀 명부 행). TEAM 이 비면 항상 rc0
  [ -n "$TEAM" ] || return 0
  local pfx="byz-$TEAM-nano-" ros="$(dirname -- "$SEATS")/seats-$TEAM.json"
  [ "$TEAM" != v65 ] || { pfx="ft-v65-temp-"; ros="$SEATS"; }
  case "$1" in "$pfx"*) ;; *) return 1;; esac
  [ -f "$ros" ] && python3 -c 'import json,sys;sys.exit(0 if isinstance(json.load(open(sys.argv[1])).get(sys.argv[2]),dict) else 1)' "$ros" "$1" 2>/dev/null
}
# R332·판정 2197: «쉬는 역할 좌석» 판별 — rc0 + stdout=그 팀 «대기» 카드 폴더. 팀 명부(planner 명부 제외)의 `_master`·`_arch` 현역 ∧ 명부 행 role master|arch ∧ `_hil_route`·`_desk` 아님 ∧ `_cards`·`_cards_wt` 로 읽는 대기 폴더가 실재(못 읽으면 «0장» 을 증명할 수 없으니 후보 아님)
role_seat_table() {   # 쉬는 역할 좌석 후보 표 `이름<TAB>대기 폴더` — python 1회(명부 전체). 호출할 때마다 «지금» 의 명부·폴더를 읽는다
  local r; set --; while IFS= read -r r; do [ -f "$r" ] && set -- "$@" "$r"; done < <(printf '%s\n' "$ROSTERS")
  [ $# -gt 0 ] || return 0
  python3 - "$ROOT" "$@" <<'PYEND' 2>/dev/null
import json, os, sys
root = sys.argv[1]
for f in sys.argv[2:]:
    if f.endswith("seats-planner.json"): continue
    try: d = json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError): continue
    cards, wt = d.get("_cards"), d.get("_cards_wt")
    if not (isinstance(cards, str) and cards and isinstance(wt, str) and wt): continue
    p = os.path.join(root, ".worktrees", wt, cards, "대기")
    if not os.path.isdir(p): continue
    for name in (d.get("_master"), d.get("_arch")):
        row = d.get(name) if isinstance(name, str) else None
        if name and name not in (d.get("_hil_route"), d.get("_desk")) and isinstance(row, dict) and row.get("role") in ("master", "arch"):
            print(f"{name}\t{p}")
PYEND
}
role_seat_cards() {   # $1=세션명 → rc0 + stdout=그 팀 «대기» 카드 폴더(지금 다시 읽음)
  local d; d="$(role_seat_table | awk -F'\t' -v n="$1" '$1==n{print $2; exit}')"
  [ -n "$d" ] || return 1
  printf '%s' "$d"
}
waiting_cards() {   # 대기 폴더의 카드(.md · README.md 제외) 장수 — 목록 조회 성공(rc0)일 때만 «N장»(0 포함) · 조회 실패는 rc1(0장으로 읽지 않는다 · DA⑥ H1)
  local l n; l="$(ls -1 "$1" 2>/dev/null)" || return 1
  n="$(printf '%s\n' "$l" | grep '\.md$' | grep -vc '^README\.md$')"; echo "${n:-0}"
}
iso_age_min() { python3 -c '
import datetime, sys
try: t = datetime.datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
except ValueError: sys.exit(1)
print(int((datetime.datetime.now(datetime.timezone.utc) - t).total_seconds() // 60))' "$1" 2>/dev/null; }

# R320: 명부 index 카드 경로 → 지금 실재하는 카드(DA 뒤 indices/완성/ 으로 옮겨졌으면 그 경로) · 없으면 빈 값
card_for() {
  local i="$1" d
  [ -n "$i" ] || return 0
  if [ -e "$i" ]; then printf '%s' "$i"; return 0; fi
  case "$i" in */indices/*/*) d="${i%/indices/*}/indices/완성/${i##*/}"; [ -e "$d" ] && printf '%s' "$d";; esac
  return 0
}
idle_min_for() {   # $1=세션명 $2=종류 → 이 후보의 idle 문턱(분) — 병합 끝 나노 + (카드가 완성/ ∨ r500 압력) 이면 DONE_IDLE_MIN
  [ "$2" != "쉬는 역할 좌석" ] || { echo "$ROLE_IDLE_MIN"; return; }
  [ "$2" = "병합 끝 나노" ] || { echo "$IDLE_MIN"; return; }
  [ "$PRESSURE" != 1 ] || { echo "$DONE_IDLE_MIN"; return; }
  case "$(card_for "$(roster_field "$1" index)")" in */indices/완성/*) echo "$DONE_IDLE_MIN";; *) echo "$IDLE_MIN";; esac
}
# r500: 메모리 압력 = swap 사용률 ≥ PRESS_PCT — 한 실행에 1번(reclaim_core 시작 · 메인 셸) · 측정 실패 = 압력 아님 + WARN 1줄(표 끝)
PRESSURE=0; SWAP_PCT="?"; SWAP_WARN=""
measure_pressure() {
  local s; s="${FT_SWAPUSAGE-$(sysctl -n vm.swapusage 2>/dev/null)}"
  SWAP_PCT="$(printf '%s\n' "$s" | awk 'function mb(v,  u){u=substr(v,length(v)); v+=0; return u=="G"?v*1024:(u=="K"?v/1024:v)}
    {for(i=1;i+2<=NF;i++){if($i=="total"){t=mb($(i+2)); seen=1} if($i=="used")w=mb($(i+2))}}
    END{if(seen) printf "%d", (t>0 ? w*100/t : 0)}')"
  case "$SWAP_PCT" in ''|*[!0-9]*) SWAP_PCT="?"; PRESSURE=0; SWAP_WARN="WARN swap 측정 실패 — 압력 아님(문턱 ${IDLE_MIN}분)"; return;; esac
  if [ "$SWAP_PCT" -ge "$PRESS_PCT" ]; then PRESSURE=1; else PRESSURE=0; fi
}
# r500: 나노 가지가 main 에 «착지» 했는가 — 판정기는 ft-landed-check.sh 하나(census·nano-close 계획과 같은 판정) · 7초 상한 · 판정 실패·시간 초과 = 미착지(fail-closed)
#   가지 = nano/<세션 키> 또는 가장 큰 nano/<세션 키>-r<N>(ft-nano-spawn 재사용 꼴) · BYZ 루트와 팩 리포 중 «그 가지가 있는 리포 전부» 가 rc0 이어야 착지
#   (하네스 나노는 BYZ 에도 커밋 0 인 같은 이름 가지가 있어 BYZ 만 보면 늘 ancestor 로 읽힌다 — 작업 가지는 팩)
LN_CACHE=""; LN_RC=1; LN_WHY=""
landed_nano() {   # $1=세션명 → LN_RC(0 = 착지 강한 근거) · LN_WHY(근거 1단어 | 가지 없음 | 시간 초과) — 메인 셸에서 부른다(같은 실행 세션별 1회 캐시)
  local n="$1" key card repo br out rc found=0 hit
  hit="$(printf '%s' "$LN_CACHE" | awk -F'\t' -v n="$n" '$1==n{print $2"\t"$3; exit}')"
  if [ -n "$hit" ]; then LN_RC="${hit%%	*}"; LN_WHY="${hit#*	}"; return 0; fi
  key="${n%#0}"; case "$key" in ft-v65-temp-*) key="${key#ft-v65-temp-}";; *) key="${key#*-nano-}";; esac
  card="$(roster_field "$n" index)"; card="${card##*/}"; card="${card%.md}"
  LN_RC=0; LN_WHY=""
  for repo in "$ROOT" "$PACK_ROOT"; do
    [ -e "$repo/.git" ] || continue
    br="$(git -C "$repo" for-each-ref --format='%(refname:short)' "refs/heads/nano/$key" "refs/heads/nano/$key-r*" 2>/dev/null \
      | awk -v b="nano/$key" '$0==b{r=1} $0!=b{x=substr($0,length(b)+3); if(x !~ /^[0-9]+$/) next; r=x+0} r>=m{m=r; best=$0} END{print best}')"
    [ -n "$br" ] || continue
    found=1
    if [ -z "$TOBIN" ]; then LN_RC=1; LN_WHY="7초 상한 도구 없음"; break; fi
    out="$("$TOBIN" 7 bash "$LANDED" "$repo" origin/main "$br" "${card:-$key}" 2>/dev/null)"; rc=$?; out="${out%%$'\n'*}"
    case "$rc" in 0) LN_WHY="$out";; 124|137) LN_RC=1; LN_WHY="시간 초과"; break;; *) LN_RC=1; LN_WHY="${out:-no}"; break;; esac
  done
  [ "$found" = 1 ] || { LN_RC=1; LN_WHY="가지 없음"; }
  LN_CACHE="$LN_CACHE$n	$LN_RC	$LN_WHY
"
}
fresh_att() { tmux list-sessions -F '#{session_name}|#{session_attached}' 2>/dev/null | awk -F'|' -v n="$1" '$1==n{print $2; exit}'; }

# 재개 기록 검증 — zombie-clean.sh resume_record_check 와 같은 규칙 + 기록 pid 가 지금 그 세션 pane 의 자식인가(닫기 근거). rc0=검증됨 · 그 밖=사유 1단어 stdout
resume_ok() {
  local f="$RESUME_DIR/$1.json" why pp
  [ -f "$f" ] || { echo "재개 기록 없음"; return 1; }
  why="$(python3 - "$f" "$1" <<'PY'
import json, os, sys
f, name = sys.argv[1:3]
try: d = json.load(open(f, encoding="utf-8"))
except (OSError, ValueError): print("파일읽기"); sys.exit(1)
if not isinstance(d, dict): print("파일읽기"); sys.exit(1)
uuid, jl, cwd, model = (d.get(k) for k in ("uuid", "jsonl", "cwd", "model"))
for why, ok in (("name", d.get("name") == name), ("engine", d.get("engine") == "claude"), ("uuid", isinstance(uuid, str) and bool(uuid)),
                ("jsonl", isinstance(jl, str) and os.path.isfile(jl) and os.path.basename(jl) == f"{uuid}.jsonl"),
                ("cwd", isinstance(cwd, str) and os.path.isdir(cwd)), ("model", isinstance(model, str) and bool(model))):
    if not ok: print(why); sys.exit(1)
PY
)" || { echo "재개 기록 불일치($why)"; return 1; }
  local pid; pid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$f" 2>/dev/null)"
  pp="$(tmux list-panes -t "$1" -F '#{pane_pid}' 2>/dev/null | head -1)"
  { [ -n "$pid" ] && [ -n "$pp" ] && pgrep -P "$pp" 2>/dev/null | grep -qx "$pid"; } || { echo "재개 기록 불일치(pid)"; return 1; }
  return 0
}

# ★닫기 결정의 단일 재확인 함수★ — 후보 1차 거르기와 kill/nano-close 직전 둘 다 이 함수 하나만 본다(다른 재확인 조각 0).
#   $1=세션명 $2=종류 → rc0 = 지금도 닫아도 된다 · rc1 = 거절(사유 stdout). 매번 «지금» 다시 조회: jsonl 턴 · mbox pending · press 허가 · attached · V65 active · 보호 집합(명부 `_*`·부르는 쪽 조상) · 명부 행.
#   보호 집합 재조회는 가장 마지막(닫기 바로 앞)에 한다 — 앞선 조회 도중 명부가 바뀌어도(master 승계 등) 잡는다.
fresh_ok() {
  local n="$1" kind="$2" st pend att trow tend age cdir wc
  trow="$(bash "$SEATST" turn "$n" 2>/dev/null | head -1)"; st="${trow%% *}"
  [ "$st" = IDLE ] || { echo "jsonl ${st:-UNKNOWN}(IDLE 아님)"; return 1; }
  pend="$(bash "$MBOX" peek "$n" 2>/dev/null | sed -n 's/.*pending=\([0-9][0-9]*\).*/\1/p' | head -1)"
  [ "${pend:-x}" = 0 ] || { echo "mbox pending=${pend:-?}"; return 1; }
  if [ -d "$PERMITS" ] && grep -rlF -- "$n" "$PERMITS" >/dev/null 2>&1; then echo "press 허가 보유"; return 1; fi
  att="$(fresh_att "$n")"
  [ "${att:-0}" -gt 0 ] 2>/dev/null && { echo "attached(사람이 보는 화면)"; return 1; }
  if [ "$kind" = "직전 세대 좌석" ]; then
    [ "$(tmux show-options -qv -t "=$n:" @zc_v65_active 2>/dev/null)" = 1 ] && { echo "V65 active"; return 1; }
    in_roster "$n" || { echo "BYZ 명부에 행 없음"; return 1; }
  fi
  team_ok "$n" || { echo "팀 소속 아님($TEAM)"; return 1; }
  if [ "$kind" = "쉬는 역할 좌석" ]; then   # R332·판정 2197: 현역 master·arch 는 «지금도» 현역이고 대기 카드 0 · 턴 종료 ROLE_IDLE_MIN 분↑ 일 때만(매번 지금 다시 조회)
    [ "$(tmux show-options -qv -t "=$n:" @zc_v65_active 2>/dev/null)" = 1 ] && { echo "V65 active"; return 1; }
    cdir="$(role_seat_cards "$n")" || { echo "현역 master·arch 판별 불가(명부·카드 폴더)"; return 1; }
    wc="$(waiting_cards "$cdir")" || { echo "대기 폴더 조회 실패"; return 1; }
    [ "${wc:-x}" = 0 ] || { echo "대기 카드 ${wc:-?}장"; return 1; }
    tend="$(printf '%s' "$trow" | awk '{print $2}')"; age="$(iso_age_min "$tend")"
    [ -n "$age" ] || { echo "턴 종료 시각 없음(3시간 IDLE 확인 불가)"; return 1; }
    [ "$age" -ge "$ROLE_IDLE_MIN" ] || { echo "턴 종료 ${age}분 전 < ${ROLE_IDLE_MIN}분"; return 1; }
    build_protect; protected_hard "$n" && { echo "부르는 쪽·상위 오케(planner·_hil_route·_desk)"; return 1; }
    return 0
  fi
  build_protect
  protected "$n" && { echo "부르는 쪽·상위 오케"; return 1; }
  return 0
}

latest_seq_from() {   # $1=발신 좌석 → 그 좌석이 보낸 가장 큰 seq (없으면 빈 문자열)
  [ -f "$MAILBOX" ] || return 0
  python3 -c '
import json,sys
best=""
for ln in open(sys.argv[1],encoding="utf-8",errors="replace"):
    try: r=json.loads(ln)
    except ValueError: continue
    if r.get("from")==sys.argv[2] and isinstance(r.get("seq"),int): best=r["seq"]
print(best)' "$MAILBOX" "$1" 2>/dev/null
}

TABLE=""; OOS=""; CLOSED_N=0; CAND_N=0
row() { TABLE="$TABLE$(printf '%s | %s | %s | %s' "$1" "$2" "$3" "$4")
"; }

reclaim_core() {   # $1=need → TABLE·OOS·CLOSED_N 채움
  local need="$1" now sess cand="" name act att idle base gen newer line kind basis
  now=$(date +%s); measure_pressure
  RTAB="$(roster_table)"; local roletab=""; [ "$PREV" = 1 ] && roletab="$(role_seat_table)"   # 1차 거르기용 스냅샷(R332 H5 — 세션마다 python 을 부르지 않는다)
  sess="$(tmux list-sessions -F '#{session_name}|#{session_activity}|#{session_attached}' 2>/dev/null)"
  while IFS='|' read -r name act att; do
    [ -n "$name" ] || continue
    [ -z "$TEAM" ] || team_ok "$name" || continue   # r-teamset-standard: 그 팀 나노 밖은 후보도 «승인 범위 밖» 표도 아니다
    idle=$(( (now - act) / 60 ))
    kind=""
    [ -n "$roletab" ] && printf '%s\n' "$roletab" | awk -F'\t' -v n="$name" '$1==n{f=1} END{exit !f}' && kind="쉬는 역할 좌석"   # R332·판정 2197: 선제 모드만 · --on-reject 는 역할 좌석을 닫지 않는다
    [ -n "$kind" ] || case "$name" in
      *-nano-*'#0') kind="나노";;   # r500: 착지 판정 전 — 1차 거르기(idle·attached·보호) 뒤 «병합 끝 나노»|«미병합 나노» 로 가른다
      *) base="${name%#*}"; gen="${name##*#}"
         case "$gen" in ''|*[!0-9]*) ;; *)
           newer="$(printf '%s\n' "$sess" | awk -F'|' -v b="$base" -v g="$gen" '{n=$1; if(index(n,b"#")==1){x=substr(n,length(b)+2); if(x ~ /^[0-9]+$/ && x+0>g+0) print n}}' | head -1)"
           [ -z "$newer" ] || kind="직전 세대 좌석";; esac;;
    esac
    if [ -z "$kind" ]; then
      # 에이전트 좌석(명부 행 있거나 claude/codex 이름)만 «승인 범위 밖» 으로 올린다 — 서버·셸 세션은 표에 안 쓴다
      if [ -n "$(roster_field "$name" role)" ] || case "$name" in *-claude'#'*|*-codex'#'*) true;; *) false;; esac; then
        [ "$idle" -ge "$IDLE_MIN" ] && ! protected "$name" && [ "${att:-0}" -eq 0 ] \
          && OOS="$OOS$name
" && row "$name" "현역 역할/기타" "-" "HIL(승인 범위 밖: 현역 역할 좌석·재개 기록 없는 직전 세대·codex DA·미병합 나노)"
      fi
      continue
    fi
    if [ "$kind" = "직전 세대 좌석" ] && ! in_roster "$name"; then   # H1: 다른 프로젝트·명부 밖 좌석은 재개 기록이 유효해도 후보 아님
      [ "$idle" -ge "$IDLE_MIN" ] && ! protected "$name" && [ "${att:-0}" -eq 0 ] \
        && OOS="$OOS$name
" && row "$name" "$kind" "-" "HIL(승인 범위 밖: 다른 프로젝트 — BYZ 명부 seats*.json 에 행 없음)"
      continue
    fi
    cand="$cand$idle|$kind|$name|$att
"
  done < <(printf '%s\n' "$sess")
  CAND_N="$(printf '%s' "$cand" | grep -c .)"
  local why seq idx out rc imin
  while IFS='|' read -r idle kind name att; do
    if [ "$kind" = "나노" ]; then   # r500: idle(착지했다고 볼 때의 문턱)·attached·보호를 먼저 거르고 통과한 나노만 git 착지 판정(압력 때 git 호출 최소)
      imin="$(idle_min_for "$name" "병합 끝 나노")"
      [ "$idle" -ge "$imin" ] || { row "$name" "$kind" "-" "SKIP idle ${idle}분 < ${imin}분"; continue; }
      [ "${att:-0}" -eq 0 ] 2>/dev/null || { row "$name" "$kind" "-" "SKIP attached(사람이 보는 화면)"; continue; }
      ! protected "$name" || { row "$name" "$kind" "-" "SKIP 부르는 쪽·상위 오케"; continue; }
      landed_nano "$name"
      if [ "$LN_RC" != 0 ]; then
        kind="미병합 나노"
        [ "$idle" -ge "$IDLE_MIN" ] || { row "$name" "$kind" "-" "SKIP idle ${idle}분 < ${IDLE_MIN}분"; continue; }
        OOS="$OOS$name
"; row "$name" "$kind" "-" "HIL(승인 범위 밖: 미병합 나노 — 착지 판정 $LN_WHY)"; continue
      fi
      kind="병합 끝 나노"
    fi
    imin="$(idle_min_for "$name" "$kind")"
    [ "$idle" -ge "$imin" ] || { row "$name" "$kind" "-" "SKIP idle ${idle}분 < ${imin}분"; continue; }
    why="$(fresh_ok "$name" "$kind")" || { row "$name" "$kind" "-" "SKIP $why"; continue; }
    if [ "$kind" = "병합 끝 나노" ]; then
      idx="$(card_for "$(roster_field "$name" index)")"
      [ -n "$idx" ] || { row "$name" "$kind" "나노 세션 정리 2026-10-02" "SKIP 명부 index 카드 없음"; continue; }
      seq="$(latest_seq_from "$name")"
      [ -n "$seq" ] || { row "$name" "$kind" "나노 세션 정리 2026-10-02" "SKIP 회수할 보고 seq 없음"; continue; }
      [ "$CLOSED_N" -lt "$need" ] || { row "$name" "$kind" "-" "SKIP need 충족(필요 수만 닫음)"; continue; }
      if [ "$DRY" = 1 ]; then row "$name" "$kind" "나노 세션 정리 2026-10-02 · 워크트리 2026-09-25" "WOULD-CLOSE(nano-close)"; CLOSED_N=$((CLOSED_N+1)); continue; fi
      why="$(fresh_ok "$name" "$kind")" || { row "$name" "$kind" "-" "SKIP(재확인 거절) $why"; continue; }
      out="$(bash "$NANOCLOSE" "$name" --result "$idx" --recv "$seq" 2>&1)"; rc=$?
      if [ "$rc" = 0 ]; then row "$name" "$kind" "나노 세션 정리 2026-10-02 · 워크트리 2026-09-25" "CLOSED"; CLOSED_N=$((CLOSED_N+1))
      else OOS="$OOS$name
"; row "$name" "$kind" "나노 세션 정리 2026-10-02" "HIL(승인 범위 밖: nano-close 거절 rc=$rc — $(printf '%s' "$out" | sed -n '1,2p' | tr '\n' ' ' | cut -c1-120))"; fi
    else
      why="$(resume_ok "$name")" || { OOS="$OOS$name
"; row "$name" "$kind" "-" "HIL(승인 범위 밖: $why)"; continue; }
      if [ "$(tmux show-options -qv -t "=$name:" @zc_v65_active 2>/dev/null)" = 1 ]; then row "$name" "$kind" "-" "SKIP V65 active"; continue; fi
      local pp srv; pp="$(tmux list-panes -t "$name" -F '#{pane_pid}' 2>/dev/null | head -1)"; srv=""
      [ -z "$pp" ] || srv="$(pgrep -P "$pp" 2>/dev/null | while read -r k; do ps -o command= -p "$k" 2>/dev/null; done | grep -aoE "$SRVRE" | head -1)"
      [ -z "$srv" ] || { row "$name" "$kind" "-" "SKIP 라이브 서버 보유($srv)"; continue; }
      [ "$CLOSED_N" -lt "$need" ] || { row "$name" "$kind" "-" "SKIP need 충족(필요 수만 닫음)"; continue; }
      basis="판정 1344 · tmux 정리 2026-07-11"; [ "$kind" != "쉬는 역할 좌석" ] || basis="오빠 판정 2197 · tmux 정리 2026-07-11"
      if [ "$DRY" = 1 ]; then row "$name" "$kind" "$basis" "WOULD-CLOSE(kill-session)"; CLOSED_N=$((CLOSED_N+1)); continue; fi
      why="$(fresh_ok "$name" "$kind")" || { row "$name" "$kind" "-" "SKIP(재확인 거절) $why"; continue; }
      if tmux kill-session -t "=$name" 2>/dev/null; then row "$name" "$kind" "$basis · 재개: zombie-clean.sh resume '$name'" "CLOSED"; CLOSED_N=$((CLOSED_N+1))
      else row "$name" "$kind" "판정 1344" "SKIP kill-session 실패"; fi
    fi
  done < <(printf '%s' "$cand" | sort -t'|' -k1,1nr)
}

acquire_lock() {
  [ "$DRY" = 1 ] && return 0   # dry-run 은 쓰기 0 — 잠금도 안 잡는다
  local tries="${FT_RECLAIM_LOCK_TRIES:-30}" i=0 hp
  [ "$PREV" = 1 ] && tries=1   # R332: 선제 모드는 경합이면 기다리지 않고 포기(다음 틱 재시도)
  while ! mkdir "$LOCK" 2>/dev/null; do
    hp="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$hp" ] && ! kill -0 "$hp" 2>/dev/null; then rm -rf "$LOCK"; continue; fi   # 죽은 보유자의 낡은 잠금
    i=$((i+1)); [ "$i" -lt "$tries" ] || { [ "$PREV" = 1 ] && { echo "PREVENTIVE skipped=lock"; return 5; }; echo "ERROR reclaim 잠금 대기 초과(보유 pid=${hp:-?}) — 다른 정리가 진행 중" >&2; return 4; }
    sleep 1
  done
  echo $$ > "$LOCK/pid"; trap 'rm -rf "$LOCK"' EXIT
}

emit_table() {
  printf '후보 | 종류 | 승인 근거 | 결과\n%s' "$TABLE"
  [ -z "$SWAP_WARN" ] || echo "$SWAP_WARN"
  echo "RECLAIMED $CLOSED_N pressure=$PRESSURE swap=$SWAP_PCT%"
}
log_table() { [ "$DRY" = 1 ] && return 0; { echo "# $(date '+%F %T') caller=${CALLER:-?} need=${1:-?} why=${WHY:--} mode=${MODE:--} dry=$DRY"; emit_table; } >> "$LOG" 2>/dev/null; }

reboot_plan() {   # R320: 재부팅 전 좌석 저장 순서 안내 파일(출력만 · 재부팅·kill 0)을 쓰고 사람이 칠 `! bash /tmp/h<N>` 1줄을 돌려준다(실패면 빈 값)
  local p="$STATE/reboot-plan-$(date +%F).sh.hil"
  cat > "$p" <<'EOS' || return 0
#!/usr/bin/env bash
# R320 자원 정리 뒤에도 메모리가 모자랄 때의 안내 — 이 파일은 글자만 출력한다(재부팅·좌석 닫기 0). 재부팅은 사람 손.
cat <<'TXT'
재부팅 전 순서
1. 각 팀 master 가 진행 중 나노의 미커밋·미랜딩을 정리한다(미커밋 0 · baton save · 승계 스냅샷 tracked 경로).
2. ls ~/.claude/state/seat-resume/ — 열린 claude 좌석마다 재개 기록이 있어야 한다(없으면 그 좌석의 대화 uuid 를 따로 적어 둔다).
3. 사람이 맥을 재부팅한다.
4. 재부팅 뒤: zombie-clean.sh resume '<세션명>' 로 같은 대화를 다시 열고, 나노는 카드로 새로 spawn 한다.
TXT
EOS
  [ -f "$HILBIN" ] || return 0
  bash "$HILBIN" --add "$p" 2>/dev/null | tail -1
}

if [ "$PREV" = 1 ]; then   # R332: 선제 모드 — 문지기·[HIL]·재부팅 줄 0 (공통 reclaim_core 경로 그대로 · 닫기 직전 fresh_ok 재검증 포함)
  WHY=preventive; MODE=preventive
  acquire_lock; _lrc=$?
  [ "$_lrc" = 0 ] || { [ "$_lrc" = 5 ] && exit 0; exit 4; }
  reclaim_core 9999 || exit 4
  _pl="PREVENTIVE reclaimed=$CLOSED_N candidates=$CAND_N skipped=$(printf '%s' "$TABLE" | grep -c ' | SKIP') pressure=$PRESSURE swap=$SWAP_PCT%"
  log_table 9999; [ "$DRY" = 1 ] || echo "$_pl" >> "$LOG" 2>/dev/null
  emit_table; echo "$_pl"; exit 0
fi

if [ "$HAVE_ONREJ" = 1 ]; then
  GATE="${GATE:-$HERE/ft-resource-gate.sh}"
  WHY="$(printf '%s\n' "$ONREJ" | sed -nE 's/^REJECT resource ((agents|swap|memfree|level|rate)=[^ ]*).*/\1/p' | head -1)"; _kind="${WHY%%=*}"
  _a="$(printf '%s' "$ONREJ" | sed -n 's/^REJECT resource agents=\([0-9][0-9]*\) limit=\([0-9][0-9]*\).*/\1/p' | head -1)"
  _l="$(printf '%s' "$ONREJ" | sed -n 's/^REJECT resource agents=\([0-9][0-9]*\) limit=\([0-9][0-9]*\).*/\2/p' | head -1)"
  if [ "$_kind" = agents ]; then
    if [ -z "$_a" ] || [ -z "$_l" ] || [ "$_a" -le "$_l" ]; then printf '%s\n' "$ONREJ"; exit 3; fi
    NEED=$((_a - _l + 1))
  else NEED=9999; fi   # 스왑·메모리·압력·속도 = 필요 개수 없음 → 승인 두 행의 후보 전부
  acquire_lock || { printf '%s\n' "$ONREJ"; exit 3; }
  reclaim_core "$NEED" || { printf '%s\n' "$ONREJ"; exit 3; }
  log_table "$NEED"
  if [ "$DRY" = 1 ]; then printf '%s\n' "$ONREJ"; emit_table; echo "dry-run: 로그·[HIL]·kill 0"; exit 3; fi
  _gout="$(bash "$GATE" check 2>&1)"; _grc=$?
  if [ "$_grc" = 0 ]; then { echo "RECLAIM ok need=$NEED"; emit_table; echo "$_gout"; }; exit 0; fi
  # 여전히 REJECT — 원래 문구 + 표 + HIL 1통(같은 날 같은 후보 묶음이면 재발신 0)
  printf '%s\n' "$ONREJ"; emit_table
  _n="$(printf '%s' "$OOS" | grep -c .)"
  _sig="$(date +%F) ${_kind} $(printf '%s' "$OOS" | sort | shasum | cut -c1-16)"
  if [ "$(cat "$HILSIG" 2>/dev/null)" = "$_sig" ]; then echo "HIL 재발신 0(같은 날 같은 후보 묶음)"
  elif [ -z "$HIL_ROUTE" ]; then echo "HIL 수신자 없음(_hil_route 비어 있음) — 표를 사람이 본다"
  else
    _hm=""; [ "$_kind" = agents ] || _hm="$(reboot_plan)"
    bash "$MBOX" send "$HIL_ROUTE" "${CALLER:-ft-resource-reclaim}" "[HIL] 자원 — 승인 범위 밖 후보 $_n · 문지기 ${WHY} · 자동 정리 $CLOSED_N 개 뒤에도 REJECT. 표: .fable-team/state/reclaim.log 마지막 블록${_hm:+
재부팅 계획(안내만 · 재부팅은 사람 손):
$_hm}" >/dev/null 2>&1 \
      && printf '%s' "$_sig" > "$HILSIG" || echo "WARN [HIL] 발신 실패"
  fi
  exit 3
fi

case "$NEED" in ''|*[!0-9]*|0) echo "usage: --need 는 1 이상 정수 (받은 값: ${NEED:-<없음>})" >&2; exit 2;; esac
[ -n "$CALLER" ] || { echo "usage: --caller <세션명> 필수" >&2; exit 2; }
acquire_lock || exit 4
reclaim_core "$NEED" || exit 4
log_table "$NEED"
emit_table
exit 0
