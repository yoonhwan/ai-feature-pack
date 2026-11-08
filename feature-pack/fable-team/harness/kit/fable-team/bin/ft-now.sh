#!/usr/bin/env bash
# ft-now.sh — 하네스 «한 화면»(r1473 · STRATEGY §3 표 9행 · DA APPROVE #274598).
#   사람·좌석이 «부를 때 1회» 도는 비모델 스크립트다. 주기 0 · 모델 0 · 쓰기 0 · 쪽지 0 · 발행 0(launchctl·tmux 변경 0).
#   입력 = launchctl print(금지 라벨 23 · bash 허용 10) · ACCT_PAUSE + 틱 plist · ft-harness-info seats + ft-seat-status stalled
#          · mailbox.jsonl(pending) · git ls-tree origin/main 카드 3폴더 · ft-hil.sh --pending · 측정 파일 3종(events·postboot·waste) · 세션 크론(못 잼)
#   출력 계약 = 줄마다 `항목 | 값 | OK|실패|판정 불가 | 담당` · ≤30줄 · 마지막 줄 `실패 N · 판정 불가 M` · rc0 = 둘 다 0 · usage rc2.
#   ★판정 3값★ `_verdict <항목> <값> <OK|FAIL|NA> <담당> [rc]` — 항상 이 함수 하나로만 줄을 낸다(r1474 가 같은 함수를 복사해 쓴다 · 공용 lib 신설 0).
#     NA 는 `판정 불가`(rc 있으면 `판정 불가 rc=N`, 124 면 `판정 불가(시간 초과)`)로 찍고 집계 «불가 M» 에 넣는다.
#     NAFIX 는 «상시 못 재는 것»(세션 크론) 전용 — 표시는 판정 불가, 집계 제외(넣으면 rc0 이 영원히 불가 · DA #274584).
#   ★조용한 0 금지★(docs/rules/no_silent_fallback.md): 한 항목이 rc≠0 이면 그 줄만 판정 불가 · 나머지는 계속 돈다.
#   ★상주형 판정★(DA 반례1): loaded + last exit 0 만으로 OK 0 — `state = running` + pid 가 있어야 OK. 종료형은 last exit 0.
#   ★마지막 측정은 두 칸★: 신선도(오늘|N일 전|없음) 와 원 결과(OK|실패|판정 불가 rc=N) — 오늘 날짜가 실패를 가리지 않는다(DA 반례2).
#   ★정지 의도 vs 스위치★: ACCT_PAUSE 유효 항목이 있는데 모델 틱 plist 가 살아 있으면(.plist) 실패 — 둘이 «같아야» 한다(한 방향 검사).
#   env(시험·이식): FT_NOW_ROOT · FT_NOW_STATE · FT_NOW_LAUNCHCTL · FT_NOW_TMUX · FT_NOW_NOW · FT_NOW_UID · FT_NOW_BUDGET · FT_NOW_MAX_LINES
#     FT_NOW_FORBIDDEN · FT_NOW_RESIDENT · FT_NOW_ONESHOT · FT_NOW_ACCT_PAUSE · FT_NOW_LAUNCHAGENTS · FT_NOW_HARNESS_INFO · FT_NOW_SEAT_STATUS
#     FT_NOW_HIL · FT_NOW_MBOX_JSONL · FT_NOW_SEATS_DIR · FT_NOW_SEATS_JSON · FT_NOW_CARDS · FT_NOW_EVENTS_DIR · FT_NOW_POSTBOOT · FT_NOW_WASTE_LOG
#   사용: ft-now.sh [--help]   (인자 없이 1회 · 주기 실행 금지)
set -uo pipefail
case "${1:-}" in
  "") ;;
  --help|-h) sed -n '2,20p' "$0" 2>/dev/null; exit 0;;
  *) echo "usage: ft-now.sh" >&2; exit 2;;
esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="${FT_NOW_ROOT:-$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] || ROOT="$WT"
STATE="${FT_NOW_STATE:-$ROOT/.fable-team/state}"
LC="${FT_NOW_LAUNCHCTL:-launchctl}"
TMUXC="${FT_NOW_TMUX:-tmux}"
UIDN="${FT_NOW_UID:-$(id -u)}"
NOW="${FT_NOW_NOW:-$(date +%s)}"
BUDGET="${FT_NOW_BUDGET:-25}"
MAXL="${FT_NOW_MAX_LINES:-30}"
START="$(date +%s)"
TODAY="$(date -r "$NOW" +%Y-%m-%d 2>/dev/null || date -d "@$NOW" +%Y-%m-%d)"
FORBID="${FT_NOW_FORBIDDEN:-com.byz.ft-tick com.byz.ft-tick-ops com.byz.ft-tick-feature com.byz.ft-tick-cfo com.byz.ft-tick-knowledge com.byz.ft-stall-scan com.byz.ft-stall-scan-aifp com.byz.ft-stall-scan-kakao com.byz.ft-news-brief com.byz.ft-news-desk com.byz.ft-news-planner com.byz.ft-board-publish com.byz.ft-planner-decisions com.byz.ft-idle-wake com.byz.ft-postboot-measure com.byz.ft-waste-check com.byz.ft-eval-daily com.byz.ft-weekly-review com.byz.ft-issues-daily com.byz.ft-leak-reap com.byz.ft-wt-sweep com.byz.ft-resource-watch com.byz.cfo-g4-observe com.airag.ft-goal-tick com.airag.ft-news-tick}"
RES="${FT_NOW_RESIDENT:-com.byz.iap-tunnel-18703 com.byz.iap-tunnel-18712 com.byz.llm-tunnel-8000 com.byz.stt-tunnel-8001 com.byz.loom-pg-tunnel}"
ONE="${FT_NOW_ONESHOT:-com.byz.llm-tunnel-8000-health com.byz.ft-secret-scan com.byz.gce-guard-check com.byz.colima-periodic-restart com.byz.colima-periodic-restart-unlock}"
PAUSE="${FT_NOW_ACCT_PAUSE:-$STATE/ACCT_PAUSE}"
LA="${FT_NOW_LAUNCHAGENTS:-$HOME/Library/LaunchAgents}"
INFO="${FT_NOW_HARNESS_INFO:-$( [ -x "$ROOT/.fable-team/bin/ft-harness-info.sh" ] && echo "$ROOT/.fable-team/bin/ft-harness-info.sh" || echo "$HERE/ft-harness-info.sh")}"
LINT="${FT_NOW_NAME_LINT:-$( [ -x "$ROOT/.fable-team/bin/ft-name-lint.sh" ] && echo "$ROOT/.fable-team/bin/ft-name-lint.sh" || echo "$HERE/ft-name-lint.sh")}"
SEATST="${FT_NOW_SEAT_STATUS:-$( [ -x "$ROOT/.fable-team/bin/ft-seat-status.sh" ] && echo "$ROOT/.fable-team/bin/ft-seat-status.sh" || echo "$HERE/ft-seat-status.sh")}"
HIL="${FT_NOW_HIL:-$( [ -x "$ROOT/.fable-team/bin/ft-hil.sh" ] && echo "$ROOT/.fable-team/bin/ft-hil.sh" || echo "$HERE/ft-hil.sh")}"
SEATSDIR="${FT_NOW_SEATS_DIR:-$ROOT/.fable-team}"
MB="${FT_NOW_MBOX_JSONL:-$ROOT/.fable-team/comm/mailbox.jsonl}"
CARDS="${FT_NOW_CARDS:-design/harness/indices}"
EVENTS="${FT_NOW_EVENTS_DIR:-$STATE/events}"
POSTBOOT="${FT_NOW_POSTBOOT:-$STATE/postboot-measure.tsv}"
WASTE="${FT_NOW_WASTE_LOG:-$STATE/waste-check.log}"

to() {  # to <초> <명령…> — 항목당 7초 상한(외부 호출 7초 룰). macOS 에 timeout 이 없어 perl alarm 으로 받친다.
  local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$s" "$@" 2>/dev/null; fi
}
left() { echo $(( BUDGET - ( $(date +%s) - START ) )); }
X() {  # X <명령…> — 전체 예산과 항목 상한 7초 «둘 다» 지킨다. 시간 초과면 124(그 외 rc 는 그대로 전달)
  local l t t0 r; l="$(left)"
  [ "$l" -ge 1 ] || return 124
  t=$(( l > 7 ? 7 : l )); t0="$(date +%s)"
  to "$t" "$@"; r=$?
  if [ "$r" -ge 124 ] && [ $(( $(date +%s) - t0 )) -ge "$t" ]; then return 124; fi
  return "$r"
}
OUT=(); NF=0; NN=0
_verdict() {  # ★3값 함수 하나★ <항목> <값> <OK|FAIL|NA|NAFIX> <담당> [rc]
  local i="$1" v="$2" k="$3" w="$4" rc="${5:-}"
  case "$k" in
    OK) k=OK;;
    FAIL) k=실패; NF=$((NF+1));;
    NAFIX) k="판정 불가(세션 내부)";;
    *) if [ -n "$rc" ]; then if [ "$rc" = 124 ]; then k="판정 불가(시간 초과)"; else k="판정 불가 rc=$rc"; fi; else k="판정 불가"; fi
       NN=$((NN+1));;
  esac
  OUT+=("$i | $v | $k | $w")
}
nf() { printf '%s' "$*" | tr '\n\t' '  ' | cut -c1-220; }   # 셀 정리(줄바꿈 금지·길이 상한)
iso() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
nf_la() { case "$2" in *"Could not find service"*|"") return 0;; esac; return 1; }   # launchctl «미적재» 판별(rc 113 + 문구)
TLS=""; TRC=-1
livekeys() {  # 라이브 tmux 세션 이름 → 역할 키(#N 제거) 집합 · 한 줄에 하나
tls; [ "$TRC" -eq 0 ] || return 1
printf '%s\n' "$TLS" | awk 'NF && $1 ~ /:$/ {s=$1; sub(/:$/,"",s); sub(/#[0-9]+$/,"",s); print s}' | sort -u
}
tls() { [ "$TRC" -ge 0 ] && return 0; TLS="$(X "$TMUXC" ls 2>&1)"; TRC=$?; }
NLAB=$(printf '%s\n' $FORBID | wc -l | tr -d ' ')

# ① 모델 깨우는 주기 잡 — loaded 여야 0 (RULE §5 금지 라벨)
loaded=(); e1=""
for l in $FORBID; do
  o="$(X "$LC" print "gui/$UIDN/$l" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then loaded+=("$l")
  elif [ "$rc" = 113 ] || nf_la "$l" "$o"; then :
  elif [ "$rc" = 124 ]; then e1=124
  else e1="$rc"; fi
done
if [ -n "$e1" ]; then _verdict "모델 깨우는 주기 잡" "loaded ?/$(NLAB)" NA "harness master" "$e1"
elif [ "${#loaded[@]}" -gt 0 ]; then _verdict "모델 깨우는 주기 잡" "loaded ${#loaded[@]}/$NLAB — ${loaded[*]}" FAIL "harness master"
else _verdict "모델 깨우는 주기 잡" "loaded 0/$NLAB" OK "harness master"; fi

# ② bash 허용 잡 10 — 상주형 = state=running+pid · 종료형 = last exit 0
nr=0; badr=(); e2=""; nres=0
for l in $RES; do
  nres=$((nres+1)); o="$(X "$LC" print "gui/$UIDN/$l" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" = 124 ]; then e2=124; elif [ "$rc" = 113 ] || nf_la "$l" "$o"; then badr+=("$l(미적재)"); else e2="$rc"; fi
    continue
  fi
  st="$(printf '%s\n' "$o" | sed -n 's/^[[:space:]]*state = //p' | head -1)"
  pid="$(printf '%s\n' "$o" | sed -n 's/^[[:space:]]*pid = //p' | head -1)"
  if [ "${st:-}" = running ] && [ -n "${pid:-}" ] && [ "$pid" != 0 ]; then nr=$((nr+1)); else badr+=("$l(state=${st:-없음},pid=${pid:-없음})"); fi
done
no=0; bado=(); non=0
for l in $ONE; do
  non=$((non+1)); o="$(X "$LC" print "gui/$UIDN/$l" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$rc" = 124 ]; then e2=124; elif [ "$rc" = 113 ] || nf_la "$l" "$o"; then bado+=("$l(미적재)"); else e2="$rc"; fi
    continue
  fi
  ex="$(printf '%s\n' "$o" | sed -n 's/^[[:space:]]*last exit code = //p' | head -1)"; ex="${ex:-0}"
  case "$ex" in 0|"(never exited)") no=$((no+1));; *) bado+=("$l(exit=$ex)");; esac
done
v2="상주 ${nr}/${nres} · 종료형 ${no}/${non}"
[ "${#badr[@]}" -gt 0 ] && v2="$v2 · 상주 위반 ${badr[*]}"
[ "${#bado[@]}" -gt 0 ] && v2="$v2 · 종료형 위반 ${bado[*]}"
if [ -n "$e2" ]; then _verdict "bash 허용 잡" "조회 실패($v2)" NA "ops(터널)" "$e2"
elif [ "${#badr[@]}" -gt 0 ] || [ "${#bado[@]}" -gt 0 ]; then _verdict "bash 허용 잡" "$v2" FAIL "ops(터널)"
else _verdict "bash 허용 잡" "$v2" OK "ops(터널)"; fi

# ③ 오빠 정지 의도 vs 스위치 — ACCT_PAUSE 유효 항목 ↔ 모델 틱 plist 살아 있음(.plist)
pv="$(X python3 - "$PAUSE" "$NOW" <<'PY' 2>&1
import json,sys
p,now=sys.argv[1],int(sys.argv[2])
try: d=json.load(open(p,encoding="utf-8"))
except FileNotFoundError: print("active=0 none(파일 없음)"); sys.exit(0)
except Exception: sys.exit(4)
if not isinstance(d,dict): sys.exit(4)
act,exp=[], []
for k,v in sorted(d.items()):
    if k.startswith("_") or not isinstance(v,dict): continue
    try: until=int(v.get("until") or 0); rel=int(v.get("release_at") or until); e=min(until,rel)
    except Exception: sys.exit(4)
    m=(e-now)//60
    (act if m>0 else exp).append(f"{k}({m}분 남음)" if m>0 else f"{k}(만료 {__import__('datetime').datetime.fromtimestamp(e).strftime('%m-%d %H:%M')})")
print("active=%d %s" % (len(act), " ".join(act+exp) or "none"))
PY
)"; rc3=$?
livep=0
for l in $FORBID; do [ -f "$LA/$l.plist" ] && livep=$((livep+1)); done
if [ "$rc3" -ne 0 ]; then _verdict "정지 의도 vs 스위치" "ACCT_PAUSE 읽기 실패 · 틱plist 살아 있음 $livep/$NLAB" NA "harness master" "$rc3"
else
  ap="${pv#active=}"; nact="${ap%% *}"; adesc="${ap#* }"
  v3="pause ${adesc} · 틱plist 살아 있음 ${livep}/$NLAB"
  if [ "${nact:-0}" -gt 0 ] && [ "$livep" -gt 0 ]; then _verdict "정지 의도 vs 스위치" "$v3" FAIL "harness master"
  else _verdict "정지 의도 vs 스위치" "$v3" OK "harness master"; fi
fi

# ④ 좌석 — 이름 린트(ft-name-lint · ft-harness-info seats 와 같은 판정기) + ft-seat-status stalled(정지)
#   ★ft-harness-info.sh seats 는 실측 11.9초(87좌석) = 항목 7초 룰을 넘긴다★ → 같은 판정기를 좌석별로 직접 부른다(값에 근거를 적는다).
tls
LIVES=""; [ "$TRC" -eq 0 ] && LIVES="$(printf '%s\n' "$TLS" | awk 'NF && $1 ~ /:$/ {s=$1; sub(/:$/,"",s); print s}')"
NLIVE="$(printf '%s\n' "$LIVES" | grep -c . || true)"
LINTMAX="${FT_NOW_LINT_MAX:-120}"
sc="$(X bash "$SEATST" stalled 2>&1)"; rc5=$?
if [ "$TRC" -ne 0 ]; then _verdict "좌석" "tmux ls 실패 — 좌석 셀 수 없다" NA "각 팀장" 5
elif [ "$NLIVE" -gt "$LINTMAX" ]; then _verdict "좌석" "세션 $NLIVE > 린트 상한 $LINTMAX" NA "각 팀장" 4
elif [ "$rc5" -ne 0 ]; then _verdict "좌석" "ft-seat-status stalled 실패" NA "각 팀장" "$rc5"
else
  np_=0; nj=0; badl=""; e4=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    o="$(X bash "$LINT" "$s" 2>&1)"; r=$?
    if [ "$r" = 0 ]; then np_=$((np_+1))
    elif [ "$r" = 124 ]; then e4=124; break
    else nj=$((nj+1)); [ "${#badl}" -lt 90 ] && badl="$badl $s"; fi
  done <<< "$LIVES"
  ns="$(printf '%s\n' "$sc" | awk 'NF>=4 && $2 ~ /^(BUSY|IDLE|NOSEAT)$/{c++} END{print c+0}')"
  first="$(printf '%s\n' "$sc" | awk 'NF>=4 && $2 ~ /^(BUSY|IDLE|NOSEAT)$/{printf "%s(%s) ", $1, $2}' | cut -c1-90)"
  v4="세션 ${np_} PASS · REJECT ${nj} · 정지 ${ns}"
  [ -n "$badl" ] && v4="$v4 · 린트 위반$badl"
  [ -n "$first" ] && v4="$v4 · $first"
  if [ -n "$e4" ]; then _verdict "좌석" "$v4" NA "각 팀장" "$e4"
  elif [ "$nj" -gt 0 ] || [ "$ns" -gt 0 ]; then _verdict "좌석" "$(nf "$v4")" FAIL "각 팀장"
  else _verdict "좌석" "$(nf "$v4")" OK "각 팀장"; fi
fi

# ⑤ 우편함 — mailbox.jsonl 읽기만(pending 은 «행이 남아 있다» 로 판정 · recv 0) · pending 좌석이 살아 있나
mb="$(X python3 - "$SEATSDIR" "$MB" "$NOW" <<'PY' 2>&1
import datetime,glob,json,os,re,sys
d,mbox,now=sys.argv[1],sys.argv[2],int(sys.argv[3])
rk=lambda n: re.sub(r"#\d+$","",(n or "").strip())
grp={}
for f in sorted(glob.glob(os.path.join(d,"seats*.json"))):
    try: cfg=json.load(open(f,encoding="utf-8"))
    except Exception: continue
    if not isinstance(cfg,dict): continue
    for key,g in (("_master","master"),("_arch","arch"),("_desk","desk")):
        n=rk(cfg.get(key) or "")
        if n: grp.setdefault(n,g)
if not grp: sys.exit(4)
pend={}; last=0
try: fh=open(mbox,encoding="utf-8",errors="replace")
except FileNotFoundError: fh=None
for line in (fh or []):
    line=line.strip()
    if not line: continue
    try: r=json.loads(line)
    except ValueError: continue
    if not isinstance(r,dict): continue
    ts=str(r.get("ts") or "").replace("Z","+00:00")
    try: e=int(datetime.datetime.fromisoformat(ts).timestamp())
    except Exception: e=0
    if e>last: last=e
    to=rk(r.get("to") or "")
    if to in grp and rk(r.get("from") or "")!=to: pend[to]=pend.get(to,0)+1
if fh is not None: fh.close()
cnt={"master":0,"arch":0,"desk":0}
for s,n in pend.items(): cnt[grp[s]]+=n
print("M=%d A=%d D=%d AGE=%d DEAD=%s ALL=%s" % (cnt["master"],cnt["arch"],cnt["desk"],
      (now-last)//60 if last else -1, ",".join(sorted(pend)), ",".join(sorted(grp))))
PY
)"; rc6=$?
if [ "$rc6" -ne 0 ]; then _verdict "우편함" "mailbox.jsonl·명부를 못 읽었다" NA "수신 좌석" "$rc6"
else
  M=0; A=0; D=0; AGE=-1; DEAD=""; ROSTER=""
  for tok in $mb; do
    case "$tok" in M=*) M="${tok#M=}";; A=*) A="${tok#A=}";; D=*) D="${tok#D=}";; AGE=*) AGE="${tok#AGE=}";; DEAD=*) DEAD="${tok#DEAD=}";; ALL=*) ROSTER="${tok#ALL=}";; esac
  done
  tot=$((M+A+D)); v5="master $M · arch $A · desk $D · 마지막 쪽지 $( [ "$AGE" -ge 0 ] && echo "${AGE}분 전" || echo '없음')"
  if [ "$tot" -gt 0 ]; then
    tls; dead=""
    if [ "$TRC" -ne 0 ]; then _verdict "우편함" "$v5 · tmux 조회 실패" NA "수신 좌석" 5
    else
      lv="$(livekeys)"
      for s in ${DEAD//,/ }; do printf '%s\n' "$lv" | grep -qxF "$s" || dead="$dead $s"; done
      if [ -n "$dead" ]; then _verdict "우편함" "$v5 · 죽은 좌석$dead" FAIL "수신 좌석"
      else _verdict "우편함" "$v5 · pending 좌석 살아 있음" OK "수신 좌석"; fi
    fi
  else _verdict "우편함" "$v5" OK "수신 좌석"; fi
fi

# ⑥ 카드 — origin/main 카드 3폴더 수 + fetch 나이 + 진행 ≤ 일하는 좌석+2
cul=""; cw=0; cj=0; cs=0; rc7=0
for d in 대기 진행 완성; do
  o="$(X git -C "$ROOT" ls-tree origin/main --name-only -- "$CARDS/$d" 2>&1)"; r=$?
  if [ "$r" -ne 0 ]; then rc7="$r"; continue; fi
  n="$(printf '%s\n' "$o" | grep -c '\.md$')"
  case "$d" in 대기) cw="$n";; 진행) cj="$n";; 완성) cs="$n";; esac
done
gitdir="$(X git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
fage=-1; [ -n "$gitdir" ] && [ -f "$gitdir/FETCH_HEAD" ] && fage=$(( (NOW - $(stat -f %m "$gitdir/FETCH_HEAD" 2>/dev/null || stat -c %Y "$gitdir/FETCH_HEAD" 2>/dev/null || echo "$NOW")) / 60 ))
tls; nl=0; nnote="(라이브 tmux)"
if [ "$TRC" -eq 0 ]; then
  lv="$(livekeys)"
  if [ -n "$ROSTER" ]; then
    nnote="(명부 좌석)"
    for k in ${ROSTER//,/ }; do printf '%s\n' "$lv" | grep -qxF "$k" && nl=$((nl+1)); done
  else nl="$(printf '%s\n' "$lv" | grep -c . || true)"; fi
fi
v6="대기 $cw · 진행 $cj · 완성 $cs · fetch $( [ "$fage" -ge 0 ] && echo "${fage}분 전" || echo '모름') · 일하는 좌석 $nl$nnote"
if [ "$rc7" -ne 0 ]; then _verdict "카드" "$v6" NA "각 arch" "$rc7"
elif [ "$cw$cj$cs" = 000 ] && [ "$nl" -eq 0 ]; then _verdict "카드" "$v6 · 카드 폴더 0" NA "각 arch" 4
elif [ "$cj" -gt $((nl+2)) ]; then _verdict "카드" "$v6 (진행 > 좌석+2)" FAIL "각 arch"
else _verdict "카드" "$v6" OK "각 arch"; fi

# ⑦ h — 오빠 손 계획 미실행 수
ho="$(X bash "$HIL" --pending 2>&1)"; rc8=$?
hv="$(printf '%s\n' "$ho" | head -1)"
[ -n "${hv// /}" ] || hv="미실행 h 0개"
if [ "$rc8" -ne 0 ]; then _verdict "h" "ft-hil.sh --pending 실패" NA "오빠·desk" "$rc8"
else _verdict "h" "$(nf "$hv")" OK "오빠·desk"; fi

# ⑧ 마지막 측정 — 신선도 칸과 원 결과 칸을 «따로» 찍는다(오늘이 실패를 가리지 않는다)
MT=""; MW=0
mnote() { MT="${MT:+$MT · }$1 신선도=$2 원결과=$3"; [ "$4" -gt "$MW" ] && MW="$4"; }
fresh_of() {  # fresh_of <epoch> → 오늘|N일 전
  local e="$1" d; d=$(( (NOW - e) / 86400 ))
  if [ "$(date -r "$e" +%Y-%m-%d 2>/dev/null)" = "$TODAY" ]; then echo "오늘"; else echo "${d}일 전"; fi
}
ev="$EVENTS/$TODAY.tsv"
if [ -f "$ev" ]; then
  last="$(tail -n 1 "$ev" 2>/dev/null)"
  rcv="$(printf '%s' "$last" | sed -n 's/.*rc=\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [ -z "${rcv:-}" ]; then mnote events "오늘" "판정 불가(rc 칸 없음)" 1
  elif [ "$rcv" = 0 ]; then mnote events "오늘" OK 0
  elif [ "$rcv" = 124 ]; then mnote events "오늘" "판정 불가 rc=124" 1
  else mnote events "오늘" "실패 rc=$rcv" 2; fi
else mnote events "없음" "판정 불가" 1; fi
if [ -f "$POSTBOOT" ]; then
  pe="$(stat -f %m "$POSTBOOT" 2>/dev/null || stat -c %Y "$POSTBOOT" 2>/dev/null || echo "$NOW")"
  pl="$(tail -n 1 "$POSTBOOT" 2>/dev/null)"
  prc="$(printf '%s' "$pl" | sed -n 's/.*rc=\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [ -n "${prc:-}" ]; then
    case "$prc" in 0) mnote postboot "$(fresh_of "$pe")" OK 0;; 124) mnote postboot "$(fresh_of "$pe")" "판정 불가 rc=124" 1;; *) mnote postboot "$(fresh_of "$pe")" "실패 rc=$prc" 2;; esac
  elif printf '%s' "$pl" | grep -q '시간 초과'; then mnote postboot "$(fresh_of "$pe")" "판정 불가(시간 초과)" 1
  elif printf '%s' "$pl" | grep -q '실패'; then mnote postboot "$(fresh_of "$pe")" 실패 2
  else mnote postboot "$(fresh_of "$pe")" OK 0; fi
else mnote postboot "없음" "판정 불가" 1; fi
if [ -f "$WASTE" ]; then
  we="$(stat -f %m "$WASTE" 2>/dev/null || stat -c %Y "$WASTE" 2>/dev/null || echo "$NOW")"
  wl="$(tail -n 1 "$WASTE" 2>/dev/null)"
  if printf '%s' "$wl" | grep -qE '^WASTE +ok'; then mnote waste "$(fresh_of "$we")" OK 0
  elif printf '%s' "$wl" | grep -q '^WASTE'; then mnote waste "$(fresh_of "$we")" 실패 2
  else mnote waste "$(fresh_of "$we")" "판정 불가(꼴 없음)" 1; fi
else mnote waste "없음" "판정 불가" 1; fi
case "$MW" in 0) _verdict "마지막 측정" "$(nf "$MT")" OK "—";; 1) _verdict "마지막 측정" "$(nf "$MT")" NA "—";; *) _verdict "마지막 측정" "$(nf "$MT")" FAIL "—";; esac

# ⑨ 세션 크론 — bash 에서 못 잰다(고정 · 집계 제외)
_verdict "세션 크론" "측정 불가(세션 내부) · 좌석 자기 보고" NAFIX "각 좌석"

o_last="실패 $NF · 판정 불가 $NN"
n="${#OUT[@]}"
if [ "$n" -gt $((MAXL-1)) ]; then   # 상한 초과 = 앞을 접고 마지막 집계 줄은 지킨다
  keep=$((MAXL-2))
  OUT=("${OUT[@]:0:$keep}" "… 외 $((n-keep))줄 접음")
fi
OUT+=("$o_last")
printf '%s\n' "${OUT[@]}"
[ "$NF" -eq 0 ] && [ "$NN" -eq 0 ] && exit 0
exit 1
