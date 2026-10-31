#!/usr/bin/env bash
# ft-team-tidy.sh --team <팀> [--root <리포>] [--cards-root <체크아웃>] [--apply] — r1223: 팀 하나의 카드·좌석·사본을 «정리 전 수 → 정리 → 정리 후 수» 표 1장으로(기본 = 보기만 · 쓰기·이동·kill 0)
#   팀 소속(접두 검색 0): 좌석 = <리포>/.fable-team/seats-<팀>.json 의 행 키 «정확히» · 사본 주인 = 그 키 + `_replaced_by`·`_replaces` 값 · 세션 = 키와 정확히 같은 tmux 이름 · 카드 = 팀 폴더 indices/{대기,진행,완성}
#     --root = 명부·사본 장부가 있는 리포(기본 cwd 공용 루트) · --cards-root = 카드를 셀 최신 체크아웃(기본 --root · 전·후 같은 트리)
#   세는 규칙(전·후 같음): 카드 = 상태 폴더 *.md 수 · 좌석 = 행마다 한 칸(은퇴 `_replaced_by` → 닫힘 `_closed` → 열림) + «닫힘·은퇴인데 세션 생존» 수 · 사본 = 팀 주인 장부 줄(경로 기준 1번) · 그중 경로 없음 · 주인 세션 없음
#   --apply 집행(각 도구의 자기 게이트가 정한다 · rc1·3 = 게이트 거절 = 남김 + 원문 1줄):
#     카드 = 착지(`- 착지:` sha 가 기준 가지 조상)된 진행 카드 중 카드 안에 `<판정문>.md#§N` 이 있는 것만 → ft-index-move.sh <카드> 완성 --da <그것> --landed <sha>(cwd = --cards-root)
#            판정문 없는 착지 카드 · 착지 안 됐고 좌석 0 인 진행 카드 → 목록만(그 팀 master 판단)
#     좌석 = 닫힘·은퇴 행 중 원래 역할(_closed_role → _retired_role → 이름 byz-<팀>-<역할>-… 의 역할 토큰)이 nano 이고 세션이 살아 있는 것만 → ft-seat-close.sh <좌석> --reason … --seats <명부> · 역할 좌석 → 목록만 · ft-nano-close 는 부르지 않는다
#     사본 = 경로 있는 줄은 목록만(주인 세션 없음 = «다음 --sweep 대상») · 경로 없는 줄 → ft-scratch-repo.sh --prune-missing --owners <팀 주인 파일>(--sweep·--done·FT_SCRATCH_OWNER 대입 0)
#   영역 하나가 못 읽음·도구 rc≠0(거절 아님) → 그 영역 «판정 불가» 1줄 · 다른 영역은 끝까지 · 전체 rc 3 (하드 룰 20) · tmux ls 실패(서버 없음 제외) = 전체 판정 불가 rc 3
#   env: FT_TIDY_CARD_FLOW · FT_TIDY_INDEX_MOVE · FT_TIDY_SEAT_CLOSE · FT_TIDY_SCRATCH(도구 경로 · 기본 같은 bin) · FT_FINISHED_MAIN(기준 ref · 기본 origin/main 있으면 그것 없으면 main)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
USAGE="usage: $0 --team <팀> [--root <리포>] [--cards-root <체크아웃>] [--apply]"
TEAM=""; ROOT=""; CROOT=""; APPLY=0
while [ $# -gt 0 ]; do case "$1" in
  --team) TEAM="${2:-}"; shift 2;; --root) ROOT="${2:-}"; shift 2;; --cards-root) CROOT="${2:-}"; shift 2;; --apply) APPLY=1; shift;;
  *) echo "$USAGE" >&2; exit 2;; esac; done
[[ "$TEAM" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo "$USAGE" >&2; exit 2; }
[ -n "$ROOT" ] || ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "판정 불가 리포 루트 없음 — $TEAM"; exit 3; }
CROOT="${CROOT:-$ROOT}"; ROSTER="$ROOT/.fable-team/seats-$TEAM.json"
CF="${FT_TIDY_CARD_FLOW:-$HERE/ft-card-flow.sh}"; IM="${FT_TIDY_INDEX_MOVE:-$HERE/ft-index-move.sh}"
SC="${FT_TIDY_SEAT_CLOSE:-$HERE/ft-seat-close.sh}"; SR="${FT_TIDY_SCRATCH:-$HERE/ft-scratch-repo.sh}"
CDIR=""; if . "$HERE/ft-team-lib.sh" 2>/dev/null; then CDIR="$(ft_team_in "$CROOT" "$TEAM" 2>/dev/null)" || CDIR=""; fi
[ -n "$CDIR" ] || for c in "$CROOT/design/$TEAM" "$CROOT/design/teams/$TEAM"; do [ -d "$c/indices" ] && { CDIR="$c"; break; }; done
MAIN="${FT_FINISHED_MAIN:-}"; [ -n "$MAIN" ] || { git -C "$CROOT" rev-parse -q --verify origin/main >/dev/null 2>&1 && MAIN=origin/main || MAIN=main; }
SESS="$(tmux ls -F '#{session_name}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then case "$SESS" in *"no server running"*) SESS="";; *) echo "판정 불가 tmux ls 실패(rc=$rc): $SESS — $TEAM"; exit 3;; esac; fi

scan() { # → 탭 줄: COUNT <영역> <수> · ERR <영역> <사유> · CARDMOVE <카드> <판정문#§N> <sha> · CARDLIST/SEATLIST/COPYLIST <대상> <사유> · SEATCLOSE <좌석> · PRUNE <경로> · OWNER <이름>
  TT_SESS="$SESS" python3 -I - "$TEAM" "$ROOT" "$CDIR" "$CROOT" "$MAIN" <<'PY'
import glob,json,os,re,subprocess,sys
team,root,cdir,croot,main=sys.argv[1:6]
sess=set(l for l in os.environ.get('TT_SESS','').split('\n') if l)
def out(*a): print('\t'.join(str(x).replace('\t',' ').replace('\n',' ') for x in a))
def mds(s):
    p=os.path.join(cdir,'indices',s)
    try: return sorted(os.path.join(p,f) for f in os.listdir(p) if f.endswith('.md'))
    except FileNotFoundError: return []
def cards():
    if not cdir or not os.path.isdir(os.path.join(cdir,'indices')): return out('ERR','카드','카드 폴더 없음 (%s/indices)'%cdir)
    try: c={s:mds(s) for s in ('대기','진행','완성')}
    except OSError as e: return out('ERR','카드','카드 폴더 못 읽음 (%s)'%e)
    out('COUNT','카드','대기 %d · 진행 %d · 완성 %d'%tuple(len(c[s]) for s in ('대기','진행','완성')))
    pat=re.compile(r'^[ \t]*-[ \t]*착지:[ \t]*(\S+)',re.M); hexw=re.compile(r'[0-9a-f]{7,40}\Z')
    dap=re.compile(r'([^\s`\'"()<>«»\[\]]+\.md#§[0-9]+)'); rows=[]
    for f in c['진행']:
        try: b=open(f,encoding='utf-8',errors='replace').read()
        except OSError as e: return out('ERR','카드','카드 못 읽음 %s (%s)'%(f,e))
        m=pat.findall(b); w=m[-1].strip('`') if m else ''; d=dap.findall(b); slug=os.path.basename(f)[:-3]
        rows.append((f,slug,w if hexw.match(w) else '',d[-1] if d else '',any(('-'+slug+'#').lower() in s.lower() for s in sess)))
    hist=[]
    if any(r[2] for r in rows):
        try: p=subprocess.run(['git','-C',croot,'rev-list',main],capture_output=True,text=True,timeout=7)
        except subprocess.TimeoutExpired: return out('ERR','카드','기준 가지 못 읽음 (git rev-list %s 시간 초과)'%main)
        if p.returncode: return out('ERR','카드','기준 가지 못 읽음 (git rev-list %s rc=%d)'%(main,p.returncode))
        hist=p.stdout.split()
    for f,slug,sha,da,live in rows:
        if sha and any(h.startswith(sha) for h in hist):
            if da: out('CARDMOVE',f,da,sha)
            else: out('CARDLIST',slug,'착지됐는데 진행 · 판정문#§N 없음 — %s master 판단'%team)
        elif not live: out('CARDLIST',slug,'좌석 0 진행 — %s master 판단(이동 sha 또는 남김 사유)'%team)
def role_of(k,v):
    r=v.get('_closed_role') or v.get('_retired_role')
    if r: return r
    pre='byz-%s-'%team
    return k[len(pre):].split('-')[0] if k.startswith(pre) else ''
def seats():
    files=sorted(glob.glob(os.path.join(root,'.fable-team','seats-'+team+'.json')))
    rows={}
    try:
        if not files: raise OSError('명부 없음 seats-%s.json'%team)
        for f in files:
            d=json.load(open(f,encoding='utf-8'))
            rows.update({k:v for k,v in d.items() if not k.startswith('_') and isinstance(v,dict)})
    except (OSError,ValueError) as e:
        out('ERR','좌석','명부 못 읽음 (%s)'%e); out('ERR','사본','주인 집합 모름 — 명부 못 읽음'); return None
    n={'은퇴':0,'닫힘':0,'열림':0}; live=0
    for k,v in sorted(rows.items()):
        st='은퇴' if '_replaced_by' in v else ('닫힘' if '_closed' in v else '열림'); n[st]+=1
        if st=='열림' or k not in sess: continue
        live+=1
        if role_of(k,v)=='nano': out('SEATCLOSE',k)
        else: out('SEATLIST',k,'%s 역할 좌석(%s)인데 세션 생존 — 목록만'%(st,role_of(k,v) or '?'))
    out('COUNT','좌석','은퇴 %d · 닫힘 %d · 열림 %d · 닫힘·은퇴 생존 %d'%(n['은퇴'],n['닫힘'],n['열림'],live))
    owners=set(rows)
    for v in rows.values():
        for x in (v.get('_replaced_by'),v.get('_replaces')):
            owners.update([x] if isinstance(x,str) else [y for y in x if isinstance(y,str)] if isinstance(x,list) else [])
    owners.discard('')
    return owners
def copies(owners):
    for o in sorted(owners): out('OWNER',o)
    tsv=os.path.join(root,'.fable-team','state','scratch-repos.tsv')
    try: lines=open(tsv,encoding='utf-8',errors='replace').read().splitlines()
    except FileNotFoundError: lines=[]
    except OSError as e: return out('ERR','사본','장부 못 읽음 (%s)'%e)
    seen={}
    for l in lines:
        c=l.split('\t')
        if len(c)>1 and c[0] and c[1] in owners: seen.setdefault(c[0],c[1])
    miss=[p for p in seen if not os.path.lexists(p)]
    out('COUNT','사본','장부 %d · 경로 없음 %d · 주인 세션 없음 %d'%(len(seen),len(miss),sum(1 for o in seen.values() if o not in sess)))
    for p in miss: out('PRUNE',p)
    for p,o in seen.items():
        if p not in miss and o not in sess: out('COPYLIST',p,'주인 %s 세션 없음 — 다음 --sweep 대상(이 도구는 지우지 않음)'%o)
cards(); ow=seats()
if ow is not None: copies(ow)
PY
}
lines() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1==k'; }
count() { printf '%s\n' "$1" | awk -F'\t' -v a="$2" '$1=="COUNT" && $2==a{print $3; exit}'; }
LOG=""; add() { LOG="$LOG$1"$'\n'; }
EX_C=0; RJ_C=0; LS_C=0; EX_S=0; RJ_S=0; LS_S=0; EX_P=0; RJ_P=0; LS_P=0; BAD_C=""; BAD_S=""; BAD_P=""
key() { case "$1" in 카드) echo C;; 좌석) echo S;; *) echo P;; esac; }   # 영역 이름 → 변수 꼬리(셸 변수 이름은 ASCII)
bad() { local k; k="$(key "$1")"; eval "[ -n \"\$BAD_$k\" ] || BAD_$k=\"\$2\""; }
bump() { local k; k="$(key "$2")"; eval "$1_$k=\$(( $1_$k + 1 ))"; }
run() { # <cwd> <명령…> → O = stdout 첫 줄(없으면 stderr 첫 줄) · RC
  local d="$1" e; shift; e="$(mktemp)" || { O="mktemp 실패"; RC=99; return; }
  O="$(cd "$d" && "$@" 2>"$e")"; RC=$?; [ -n "$O" ] || O="$(cat "$e")"; rm -f "$e"; O="$(printf '%s\n' "$O" | sed -n '1p')"
}
verdict() { # <영역> <대상> — RC 0 = 집행 · 1·3 = 게이트 거절(남김) · 그 밖 = 그 영역 판정 불가
  case "$RC" in 0) bump EX "$1"; add "집행 $1 $2 rc=0 — $O";; 1|3) bump RJ "$1"; add "거절 $1 $2 rc=$RC — $O";; *) bad "$1" "$2 도구 rc=$RC — $O";; esac
}
B="$(scan)" || { echo "판정 불가 스캔 실패(rc=$?) — $TEAM"; exit 3; }
while IFS=$'\t' read -r k a v; do [ "$k" = ERR ] && bad "$a" "$v"; done <<<"$B"
run "$CROOT" bash "$CF" --team "$TEAM" --root "$CROOT" ${CDIR:+--dir "$CDIR"}; CFL="$O"; [ "$RC" = 0 ] || bad 카드 "ft-card-flow rc=$RC — $O"

while IFS=$'\t' read -r _ f da sha; do   # 카드: 판정문#§N 있는 착지 카드만 ft-index-move 게이트로
  [ -n "$f" ] && [ -z "$BAD_C" ] || continue
  if [ "$APPLY" = 0 ]; then bump LS 카드; add "목록 카드 ${f##*/} — 완성 이동 후보(--da $da --landed $sha)"; continue; fi
  run "$CROOT" bash "$IM" "$f" 완성 --da "$da" --landed "$sha"; verdict 카드 "${f##*/}"
done <<<"$(lines "$B" CARDMOVE)"
while IFS=$'\t' read -r _ s why; do [ -n "$s" ] && [ -z "$BAD_C" ] && { bump LS 카드; add "목록 카드 $s.md — $why"; }; done <<<"$(lines "$B" CARDLIST)"

while IFS=$'\t' read -r _ s; do   # 좌석: 닫힘·은퇴 나노 + 세션 생존만 ft-seat-close 게이트로
  [ -n "$s" ] && [ -z "$BAD_S" ] || continue
  if [ "$APPLY" = 0 ]; then bump LS 좌석; add "목록 좌석 $s — 닫힘·은퇴 나노인데 세션 생존(ft-seat-close 후보)"; continue; fi
  run "$ROOT" bash "$SC" "$s" --reason "team-tidy: 명부 닫힘인데 세션 생존" --seats "$ROSTER"; verdict 좌석 "$s"
done <<<"$(lines "$B" SEATCLOSE)"
while IFS=$'\t' read -r _ s why; do [ -n "$s" ] && [ -z "$BAD_S" ] && { bump LS 좌석; add "목록 좌석 $s — $why"; }; done <<<"$(lines "$B" SEATLIST)"

PR="$(lines "$B" PRUNE)"   # 사본: 경로 없는 팀 주인 줄만 --prune-missing · 경로 있는 줄은 목록만
if [ -n "$PR" ] && [ -z "$BAD_P" ]; then
  if [ "$APPLY" = 0 ]; then
    while IFS=$'\t' read -r _ p; do bump LS 사본; add "목록 사본 $p — 경로 없음(--prune-missing 후보)"; done <<<"$PR"
  elif OF="$(mktemp)"; then
    lines "$B" OWNER | cut -f2 > "$OF"; e="$(mktemp)"
    O="$(FT_RES_ROOT="$ROOT" bash "$SR" --prune-missing --owners "$OF" 2>"$e")"; RC=$?; rm -f "$OF"
    if [ "$RC" = 0 ]; then
      while IFS= read -r l; do case "$l" in "PRUNED n="*) ;; "PRUNED "*) bump EX 사본; add "집행 사본 ${l#PRUNED } rc=0 — 장부 줄 지움(디스크 0)";; esac; done <<<"$O"
    else bad 사본 "ft-scratch-repo --prune-missing rc=$RC — $(printf '%s\n' "$O" "$(cat "$e")" | grep -m1 .)"; fi
    rm -f "$e"
  else bad 사본 "mktemp 실패"; fi
fi
while IFS=$'\t' read -r _ p why; do [ -n "$p" ] && [ -z "$BAD_P" ] && { bump LS 사본; add "목록 사본 $p — $why"; }; done <<<"$(lines "$B" COPYLIST)"

A="$(scan)" || bad 카드 "다시 세기 실패"
while IFS=$'\t' read -r k a v; do [ "$k" = ERR ] && bad "$a" "다시 세기: $v"; done <<<"$A"
echo "팀 정리 — $TEAM ($( [ "$APPLY" = 1 ] && echo '--apply' || echo '보기만' )) · 카드 $CDIR · 명부 $ROSTER"
echo "| 영역 | 전 | 후 | 집행 | 게이트 거절 | 목록만 |"; echo "|---|---|---|---|---|---|"
for a in 카드 좌석 사본; do
  k="$(key "$a")"; eval "x=\$EX_$k r=\$RJ_$k l=\$LS_$k"
  echo "| $a | $(count "$B" "$a" | grep . || echo '?') | $(count "$A" "$a" | grep . || echo '?') | $x | $r | $l |"
done
echo "카드 흐름(ft-card-flow): $CFL"
printf '%s' "$LOG"
RCX=0
for p in "카드:$BAD_C" "좌석:$BAD_S" "사본:$BAD_P"; do [ -z "${p#*:}" ] || { echo "판정 불가 ${p%%:*} — ${p#*:}"; RCX=3; }; done
exit "$RCX"
