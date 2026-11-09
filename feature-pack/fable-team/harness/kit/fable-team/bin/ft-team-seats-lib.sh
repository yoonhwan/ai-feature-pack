#!/usr/bin/env bash
# ft-team-seats-lib.sh — 팀장 행·워크트리 뿌리 읽기 (ft-team-boot.sh B2 가 source 한다 · r1535)
#   팩 위성팀(SAT=1 · 지금 airag) : 명부 PACK/.fable-team/seats-aifp.json · 팀장 = 키 «aifp-<팀>-master-» 행 중 #N 최대 · 워크트리 뿌리 PACK/.worktrees
#                                   행이 0 이면 멈춤 — 팩 팀장(_master = aifp-pi-master-pi#N)으로 «대체하지 않는다»
#   그 밖 팀(SAT=0)              : 명부 <데이터 루트>/.fable-team/seats-<팀>.json · 팀장 = _master · 워크트리 뿌리 <루트>/.worktrees (r1519 그대로)
#   FT_SEATS_JSON 이 있으면 명부 «파일»만 그것을 쓴다 — 팀장 고르기 규칙은 팀 종류 그대로
#   부르는 쪽이 준다: TEAM · SAT · PACK · ROOT · WROOT · FT_SEATS_JSON · FT_BOOT_WT · STOP()
#   돌려준다: SEATS · OLD · AGENT · MODEL · NEXT · RESUME_UUID · WT (실패 = STOP 1줄 · 조용한 대체 0)
seats_field() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); v=d.get(sys.argv[2],{})
print(v.get(sys.argv[3],"") if isinstance(v,dict) else "")' "$1" "$2" "$3" 2>/dev/null; }
if [ "$SAT" = 1 ]; then SEATS="${FT_SEATS_JSON:-$PACK/.fable-team/seats-aifp.json}"
else SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats-$TEAM.json}"; fi
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
RESUME_UUID="$(seats_field "$SEATS" "$OLD" _resume_uuid)"
WT=""; if [ -n "${FT_BOOT_WT:-}" ]; then WT="$FT_BOOT_WT"; else
  for w in "$(seats_field "$SEATS" "$OLD" worktree)" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_cards_wt",""))' "$SEATS" 2>/dev/null)"; do
    [ -n "$w" ] && [ -d "$WROOT/$w" ] && { WT="$WROOT/$w"; break; }; done; fi
[ -n "$WT" ] && [ -d "$WT" ] || STOP "워크트리 없음 $OLD(명부 worktree · _cards_wt · FT_BOOT_WT 모두 없음)"
