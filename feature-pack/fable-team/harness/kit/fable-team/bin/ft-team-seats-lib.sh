#!/usr/bin/env bash
# ft-team-seats-lib.sh — 팀장 행·워크트리 뿌리 읽기 (ft-team-boot.sh B2 가 source 한다 · r1535)
#   팩 위성팀(SAT=1 · 지금 airag) : 명부 PACK/.fable-team/seats-aifp.json · 팀장 = 키 «aifp-<팀>-master-» 행 중 #N 최대 · 워크트리 뿌리 PACK/.worktrees
#                                   행이 0 이면 멈춤 — 팩 팀장(_master = aifp-pi-master-pi#N)으로 «대체하지 않는다»
#   그 밖 팀(SAT=0)              : 명부 <데이터 루트>/.fable-team/seats-<팀>.json · 팀장 = _master · 워크트리 뿌리 <루트>/.worktrees (r1519 그대로)
#   FT_SEATS_JSON 이 있으면 명부 «파일»만 그것을 쓴다 — 팀장 고르기 규칙은 팀 종류 그대로
#   v65(r1536 B-1·R1)             : 명부 = seats-v65.json 이 있으면 그것, 없으면 옛 이름 seats.json(«명부 없음» 으로 멈추지 않는다) · 후계 #N = 두 파일 최대 #N+1
#   부르는 쪽이 준다: TEAM · SAT · PACK · ROOT · DROOT · WROOT · FT_SEATS_JSON · FT_BOOT_WT · STOP()
#   돌려준다: SEATS · OLD · AGENT · MODEL · NEXT · RESUME_UUID · WT (실패 = STOP 1줄 · 조용한 대체 0)
seats_field() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); v=d.get(sys.argv[2],{})
print(v.get(sys.argv[3],"") if isinstance(v,dict) else "")' "$1" "$2" "$3" 2>/dev/null; }
if [ "$SAT" = 1 ]; then SEATS="${FT_SEATS_JSON:-$PACK/.fable-team/seats-aifp.json}"
elif [ "$TEAM" = v65 ] && [ -f "$DROOT/.fable-team/seats-v65.json" ]; then SEATS="${FT_SEATS_JSON:-$DROOT/.fable-team/seats-v65.json}"
elif [ "$TEAM" = v65 ] && [ -f "$DROOT/.fable-team/seats.json" ]; then SEATS="${FT_SEATS_JSON:-$DROOT/.fable-team/seats.json}"
else SEATS="${FT_SEATS_JSON:-$DROOT/.fable-team/seats-$TEAM.json}"; fi
[ -f "$SEATS" ] || STOP "명부 없음 $SEATS"
if [ "$SAT" = 1 ]; then
  OLD="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); p=sys.argv[2]+"-master-"
ks=[k for k in d if k.startswith(p) and k.rsplit("#",1)[-1].isdigit() and isinstance(d[k],dict)]
print(max(ks, key=lambda k:int(k.rsplit("#",1)[1])) if ks else "")' "$SEATS" "aifp-$TEAM" 2>/dev/null)"
  case "$OLD" in *"#"*) ;; *) STOP "명부 팀장 없음 $SEATS aifp-$TEAM-master-*(현역 #N 없음)";; esac
else
  OLD="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_master",""))' "$SEATS" 2>/dev/null)"
  case "$OLD" in *"#"*) ;; *) STOP "명부 팀장 없음 $SEATS _master(현역 #N 없음)";; esac
fi
AGENT="$(seats_field "$SEATS" "$OLD" agent)"; MODEL="$(seats_field "$SEATS" "$OLD" model)"
[ -n "$AGENT" ] && [ -n "$MODEL" ] || STOP "명부 팀장 행 불완전 $OLD(agent=$AGENT model=$MODEL)"
NEXT="${OLD%#*}#$(( ${OLD##*#} + 1 ))"
if [ "$TEAM" = v65 ] && [ -z "${FT_SEATS_JSON:-}" ]; then   # r1536 R1(DA): 명부 2장 공존 — 후계 번호는 두 파일 최대 #N+1(옛 파일이 더 높으면 그 번호를 피한다)
  n_max="$(python3 -c 'import json,re,sys
m=0
for f in sys.argv[1:]:
    try: d=json.load(open(f))
    except Exception: continue
    for k in d:
        r=re.search(r"master[^#]*#([0-9]+)$", k)
        if r: m=max(m,int(r.group(1)))
print(m)' "$DROOT/.fable-team/seats-v65.json" "$DROOT/.fable-team/seats.json" 2>/dev/null)"
  case "$n_max" in ''|*[!0-9]*) ;; *) [ "$n_max" -ge "${OLD##*#}" ] && NEXT="${OLD%#*}#$(( n_max + 1 ))";; esac
fi
RESUME_UUID="$(seats_field "$SEATS" "$OLD" _resume_uuid)"
WT=""; if [ -n "${FT_BOOT_WT:-}" ]; then WT="$FT_BOOT_WT"; else
  for w in "$(seats_field "$SEATS" "$OLD" worktree)" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_cards_wt",""))' "$SEATS" 2>/dev/null)"; do
    [ -n "$w" ] && [ -d "$WROOT/$w" ] && { WT="$WROOT/$w"; break; }; done; fi
[ -n "$WT" ] && [ -d "$WT" ] || STOP "워크트리 없음 $OLD(명부 worktree · _cards_wt · FT_BOOT_WT 모두 없음)"

# tick_launchd_loaded <팀> — com.byz.ft-tick-<팀> 등재는 «plist 파일 유무» 가 아니라 launchctl 로드 여부다(r1536 B-3)
#   launchctl print gui/$UID/… 1회 7초 + 재시도 1(하드 룰 12) · 로드 없음(rc113·«Could not find service») 만 «미등재(파일만)»
#   그 밖 rc≠0(시간 초과·I/O 오류·명령 없음) = «판정 불가» 1줄(하드 룰 20 · R2)
#   돌려준다: LD_CELL(등재(로드) · 미등재 · 미등재(파일만) · 판정불가(rc=N)) · LD_RC — 실패는 이 함수 하나가 끝낸다
 tick_launchd_loaded() {
  local team="$1" plist lc rc t=0 to=perl
  plist="${FT_LAUNCHAGENTS:-$HOME/Library/LaunchAgents}/com.byz.ft-tick-$team.plist"
  LD_CELL=미등재; LD_RC=0
  [ -e "$plist" ] || return 0
  lc="${FT_LAUNCHCTL:-launchctl}"
  if ! command -v "$lc" >/dev/null 2>&1; then LD_CELL="판정불가(명령없음)"; LD_RC=127; return 0; fi
  command -v timeout >/dev/null 2>&1 && to=timeout; command -v gtimeout >/dev/null 2>&1 && to=gtimeout
  while :; do
    t=$((t+1))
    if [ "$to" = perl ]; then err="$(perl -e 'alarm 7; exec @ARGV' "$lc" print "gui/$UID/com.byz.ft-tick-$team" 2>&1 >/dev/null)"; rc=$?
    else err="$("$to" 7 "$lc" print "gui/$UID/com.byz.ft-tick-$team" 2>&1 >/dev/null)"; rc=$?; fi
    [ "$rc" -eq 0 ] || [ "$t" -ge 2 ] || continue   # 실패 = 1회만 더(하드 룰 12)
    break
  done
  case "$rc" in
    0) LD_CELL="등재(로드)" ;;
    113) LD_CELL="미등재(파일만)" ;;
    *) case "$err" in *"Could not find service"*) LD_CELL="미등재(파일만)" ;; *) LD_CELL="판정불가(rc=$rc)" ;; esac ;;   # R2(DA): 로드 없음 아닌 오류를 «미등재» 로 내리지 않는다
  esac
  LD_RC="$rc"; return 0
}
