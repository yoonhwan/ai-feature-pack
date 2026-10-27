#!/usr/bin/env bash
# ft-card-flow.sh --team <팀> [--root <리포>] [--dir <팀 폴더>] [--warn] [--branch-check] — 카드 흐름 숫자 1줄(읽기 전용 · 이동 0 · 삭제 0 · kill 0 · r954)
#   기본 출력(stdout) = `카드 대기 N · 진행 N(좌석 M) · 착지됐는데 진행 K`
#     대기/진행 = <팀 폴더>/indices/{대기,진행}/*.md 개수 · 좌석 M = 진행 카드 중 «-<slug>#» 가 tmux 세션명에 든 것(ft-orphan-cards.sh 와 같은 대응 · 대소문자 무시)
#     K = 카드 `- 착지:` 바로 뒤 «첫 낱말 하나»(양쪽 백틱 한 쌍은 벗김)가 `^[0-9a-f]{7,40}$` 이고, 그 낱말이 기준(main) 조상 커밋 sha 의 앞머리와 같을 때 센다 — 근거 없는 카드는 세지 않는다(거짓 양성 0 · 40자 고정은 완성 카드 착지 줄 184/321 을 버린다)
#       --branch-check = 착지 줄이 없는 카드 중 가지 nano/<slug> 가 ft-finished-check FINISHED 인 것도 센다(수동용 · 실측 한 번에 27초 · 틱·spawn 은 안 쓴다)
#   --warn = «건강 그리고 확인 불가 0» 일 때만 출력 0 · 진행 > 좌석 + 2 또는 K > 0 이면 `WARN 카드 흐름 — … 이동 먼저: <카드 최대 5>` 1줄(ft-nano-spawn 앞 경보 · rc 불변)
#   실패: 계산이 FT_CARD_FLOW_TIMEOUT_SEC(기본 7초)를 넘으면 숫자 대신 `카드 숫자 확인 불가(시간 초과)` 줄 · rc 3 / 그 밖 계산 실패도 `카드 숫자 확인 불가(<사유>)` · rc 3 (빈칸·0 금지 · #0 RULE)
#     입력 읽기 실패(카드 폴더·카드 파일)도 같은 «확인 불가» 길 · rc 3 (빈 목록으로 읽어 0 으로 보이게 하지 않는다 · DA r4 반례 1)
#     읽기 창구는 하나다(r5 재설계 · arch harnessclose#1): 폴더 = read_dir(os.listdir 직접) · 카드 = read_dir 가 준 경로를 open 직접 · os.path.lexists|exists|isdir|isfile 로 폴더·카드를 묻는 줄 0
#       카드 읽기는 대기·진행 «모든 상태 폴더의 .md» 가 같은 함수(read_card)를 지난다(r6 · 대기 수도 «읽을 수 있는 카드» 수 · 못 읽는 카드 1장 = 확인 불가 rc 3)
#       이름·경로 안 제어 문자(개행·CR·탭)는 python→셸 경계에서 esc() 로 이스케이프한 «한 줄» 로 건너간다 — 카드 줄·사유 줄에 이름 조각이 생기지 않는다(r6 · DA 반례 1·3)
#       FileNotFoundError 만 «없음»(상태 폴더 없음 = 카드 0장 정상 · 끊긴 심볼릭 링크는 lstat 로 갈라 «확인 불가») · 그 밖 OSError 는 사유에 errno 이름(EACCES·EISDIR·ENOTDIR·ELOOP …)을 넣어 확인 불가
#   확인 불가 사유는 요약 줄 한 줄 안에 붙는다(stdout): (가지 판정 시간 초과) · (가지 판정 실패) · (가지 판정 시작 실패 = 스크립트 없음·git 오류)
#     tmux 실패는 «서버 없음(no server running)» 만 세션 0개(M 0)로 인정, 그 외는 rc 1.
#   env: FT_FINISHED_MAIN(기준 ref · 기본 origin/main 있으면 그것 없으면 main) · FT_CARD_FLOW_FINISHED(finished-check 경로 · 기본 같은 bin) · FT_CARD_FLOW_TIMEOUT_SEC
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEAM=""; ROOT=""; DIR=""; WARN=0; BRANCHCHK=0
while [ $# -gt 0 ]; do case "$1" in
  --team) TEAM="${2:-}"; shift 2;; --root) ROOT="${2:-}"; shift 2;; --dir) DIR="${2:-}"; shift 2;; --warn) WARN=1; shift;; --branch-check) BRANCHCHK=1; shift;;
  *) echo "usage: $0 --team <팀> [--root <리포>] [--dir <팀 폴더>] [--warn] [--branch-check]" >&2; exit 2;; esac; done
[ -n "$TEAM" ] || { echo "usage: $0 --team <팀> [--root <리포>] [--dir <팀 폴더>] [--warn] [--branch-check]" >&2; exit 2; }
unavailable() { echo "$( [ "$WARN" = 1 ] && echo 'WARN ')카드 숫자 확인 불가($1) — $TEAM"; exit 3; }
LIMIT="${FT_CARD_FLOW_TIMEOUT_SEC:-7}"; START=$SECONDS
over() { [ $((SECONDS - START)) -ge "$LIMIT" ]; }

[ -n "$ROOT" ] || ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] && [ -d "$ROOT" ] || unavailable "리포 루트 없음"
if [ -z "$DIR" ]; then
  . "$HERE/ft-team-lib.sh" 2>/dev/null || unavailable "ft-team-lib.sh 없음"
  DIR="$(ft_team_in "$ROOT" "$TEAM" 2>/dev/null)" || DIR=""
  [ -n "$DIR" ] || for c in "$ROOT/design/$TEAM" "$ROOT/design/teams/$TEAM"; do [ -d "$c/indices" ] && { DIR="$c"; break; }; done
fi
[ -n "$DIR" ] && [ -d "$DIR/indices" ] || unavailable "카드 폴더 없음 또는 못 읽음($DIR/indices)"   # 폴더 선택 층 — 권한 오류를 «없음» 으로 단정하지 않는다(r5)

command -v python3 >/dev/null 2>&1 || unavailable "python3 없음"
err="$(tmux ls -F '#{session_name}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then
  case "$err" in *"no server running"*) err="";; *) echo "FAIL ft-card-flow — tmux ls 실패(rc=$rc): $err" >&2; exit 1;; esac
fi
sessions="$(printf '%s\n' "$err" | tr '[:upper:]' '[:lower:]')"

MAIN="${FT_FINISHED_MAIN:-}"
[ -n "$MAIN" ] || { git -C "$ROOT" rev-parse -q --verify origin/main >/dev/null 2>&1 && MAIN=origin/main || MAIN=main; }
git -C "$ROOT" rev-parse -q --verify "$MAIN^{commit}" >/dev/null 2>&1 || unavailable "기준 ref 없음: $MAIN"
FCHK="${FT_CARD_FLOW_FINISHED:-$HERE/ft-finished-check.sh}"

# 카드 수·좌석·착지 판정은 python 한 번 + git rev-list 한 번(카드마다 git 호출 = 진행 207장에서 7초 초과 · 실측 10-26)
PYOUT="$(CF_SESSIONS="$sessions" python3 -I - "$DIR" "$ROOT" "$MAIN" "$LIMIT" <<'PY'
import errno,os,re,subprocess,sys,time
d,root,main,limit=sys.argv[1],sys.argv[2],sys.argv[3],float(sys.argv[4]); t0=time.time()
sess=os.environ.get('CF_SESSIONS','').lower()
def ename(e):   # 사유에 errno 이름을 넣는다(«폴더 아님» 뭉갬 금지 · DA r4 표 2 9·11행)
    return (errno.errorcode.get(e.errno) if e.errno is not None else None) or type(e).__name__
def esc(s):   # 이름·경로 안 제어 문자(개행·CR·탭)가 python→셸 «줄» 경계를 넘지 않는다 — 셸은 한 줄로 읽는다(DA r6 반례 1·3)
    return s.replace('\r','\\r').replace('\n','\\n').replace('\t','\\t')
def fail(msg):   # 읽기·계산 실패는 «빈 목록» 도 «0» 도 아니다 — 확인 불가 · rc 3 으로 셸에 알린다(DA r4 반례 1 · r6 반례 3: 사유도 이스케이프한 한 줄)
    print(esc(msg)); sys.exit(3)
def read_card(f):   # 카드 읽기 창구 1개(r6 보강 ②) — 대기·진행 모든 .md 가 같은 길 · 사전 isfile 판정 0
    try: return open(f,encoding='utf-8',errors='replace').read()
    except OSError as e: fail('카드 파일 못 읽음 '+f+' ('+ename(e)+' '+(e.strerror or str(e))+')')
def read_dir(p):   # 폴더 읽기 창구 1개(r5) — os.path.* 선판정 0 · ENOENT 만 «없음»(None) · 그 밖 OSError = 확인 불가
    try: return os.listdir(p)
    except FileNotFoundError:
        try: os.lstat(p)   # 링크 자체는 있는데 대상이 없다 = 끊긴 링크 → «없음» 아님
        except FileNotFoundError: return None
        except OSError as e: fail('카드 폴더 못 읽음 '+p+' ('+ename(e)+' '+(e.strerror or str(e))+')')
        fail('카드 폴더 못 읽음 '+p+' (ENOENT 끊긴 심볼릭 링크)')
    except OSError as e: fail('카드 폴더 못 읽음 '+p+' ('+ename(e)+' '+(e.strerror or str(e))+')')
def listmd(sub):   # read_dir 만 쓴다 — None = 그 상태 폴더 없음 = 카드 0장(정상)
    p=os.path.join(d,'indices',sub)
    names=read_dir(p)
    if names is None: return []
    return sorted(os.path.join(p,n) for n in names if n.endswith('.md'))
wait=0
for _f in listmd('대기'):   # 대기 수도 «읽을 수 있는 카드» 수 — 못 읽는 카드 1장 = 확인 불가 rc3(DA r6 반례 2)
    read_card(_f); wait+=1
cards=listmd('진행')
pat=re.compile(r'^[ \t]*-[ \t]*착지:[ \t]*(\S+)',re.M)   # «착지:» 바로 뒤 첫 낱말 하나
valid=re.compile(r'[0-9a-f]{7,40}\Z')   # 7~40자 소문자 16진수(보강 ①: 40자 고정은 7자 약식을 버린다)
def word(w): return w[1:-1] if len(w)>2 and w[0]=='`' and w[-1]=='`' else w
rows=[];seat=0
for c in cards:
    slug=os.path.basename(c)[:-3]
    live=('-'+slug.lower()+'#') in sess; seat+=live
    body=read_card(c)   # 사전 isfile 판정 없이 바로 읽는다(r5 · EISDIR·EACCES·ENOENT 전부 같은 길 · r6 대기와 같은 함수)
    m=None
    for m in pat.finditer(body): pass
    tok=word(m.group(1)) if m else ''
    rows.append((slug,live,tok if valid.match(tok) else ('?' if m else '')))   # '?' = 착지 줄은 있으나 첫 낱말이 7~40자 소문자 16진수 아님 → 근거 없음
want={}
for _,_,sha in rows:
    if sha and sha!='?': want.setdefault(len(sha),set()).add(sha)
hit=set()
if want:
    try: out=subprocess.run(['git','-C',root,'rev-list',main],capture_output=True,text=True,timeout=max(limit-(time.time()-t0),0.1))
    except subprocess.TimeoutExpired: print('TIMEOUT'); sys.exit(0)
    if out.returncode!=0: fail('기준 가지 못 읽음 (git rev-list '+main+' rc='+str(out.returncode)+')')
    for c in out.stdout.split():
        for n,ws in want.items():
            if c[:n] in ws: hit.add(c[:n])
print('N',wait,len(rows),seat)
for slug,live,sha in rows:
    st='L' if sha and sha in hit else ('U' if not sha else 'N')   # L 착지 확인 · U 착지 줄 없음(가지 판정 후보) · N 착지 줄 있으나 main 조상 아님
    print('C',st,int(live),esc(slug))   # 이름 안 개행이 줄 조각으로 읽히지 않게 이스케이프(DA r6 반례 1)
PY
)"; PYRC=$?
case "$PYOUT" in TIMEOUT*) unavailable "시간 초과";; esac
[ "$PYRC" -eq 3 ] && unavailable "$(printf '%s\n' "$PYOUT" | head -1)"   # 확인 불가 = python rc 3(글자만 믿지 않는다 · r5)
[ "$PYRC" -eq 0 ] || unavailable "계산 실패(rc=$PYRC)"
over && unavailable "시간 초과"
read -r _ wait_n prog seat <<<"$(printf '%s\n' "$PYOUT" | grep '^N ')"
landed=0; unk_t=0; unk_f=0; unk_s=0; lcards=(); ocards=()
# 가지 판정 = 세 값(ACTIVE · FINISHED · UNKNOWN+사유) 한 함수 · 출력 = emit 한 함수 — 일반·--warn 모두 같은 길을 거친다(r3 재설계)
branch_verdict() { # <slug> → V=ACTIVE|FINISHED|UNKNOWN · VWHY=시간 초과|실패
  local slug="$1" rem out; V=UNKNOWN; VWHY="시간 초과"
  rem=$((LIMIT - (SECONDS - START))); [ "$rem" -gt 0 ] || return 0
  out="$(python3 -I - "$rem" "$FCHK" "nano/$slug" "$ROOT" <<'PY'
import os,signal,subprocess,sys
rem,f,br,root=float(sys.argv[1]),sys.argv[2],sys.argv[3],sys.argv[4]
p=subprocess.Popen(['bash',f,br,'--repo',root],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,start_new_session=True)
try: o,_=p.communicate(timeout=rem)
except subprocess.TimeoutExpired:
    os.killpg(p.pid,signal.SIGKILL); p.communicate(); print('TIMEOUT'); sys.exit(0)
print('RC%d %s'%(p.returncode,(o.splitlines() or [''])[0]))
PY
)"
  case "$out" in
    "RC0 FINISHED"*) V=FINISHED;; "RC0 ACTIVE"*|"RC0 EMPTY"*|"RC0 ORPHAN"*) V=ACTIVE;;
    TIMEOUT) ;; *) VWHY="실패";; esac   # rc≠0 · 빈 출력 · 모르는 첫 낱말 = 확인 불가(실패)
  return 0
}
emit() { # 모든 모드의 출력 — 확인 불가가 있으면 건강해도 줄을 낸다(조용한 빈 출력 0) · 사유는 요약 줄 한 줄 안
  local note="" pick
  [ "$unk_t" -eq 0 ] || note=" · 확인 불가 ${unk_t}(가지 판정 시간 초과)"
  [ "$unk_f" -eq 0 ] || note="$note · 확인 불가 ${unk_f}(가지 판정 실패)"
  [ "$unk_s" -eq 0 ] || note="$note · 확인 불가 ${unk_s}(가지 판정 시작 실패)"
  if [ "$WARN" != 1 ]; then echo "카드 대기 $wait_n · 진행 $prog(좌석 $seat) · 착지됐는데 진행 $landed$note"; return 0; fi
  if [ "$landed" -gt 0 ] || [ "$prog" -gt $((seat + 2)) ] || [ -n "$note" ]; then
    pick=("${lcards[@]+"${lcards[@]}"}"); [ "${#pick[@]}" -gt 0 ] || pick=("${ocards[@]+"${ocards[@]}"}")
    echo "WARN 카드 흐름 — $TEAM 진행 $prog(좌석 $seat) · 착지됐는데 진행 $landed$note$( [ "$landed" -gt 0 ] || [ "$prog" -gt $((seat + 2)) ] && echo " · 이동 먼저: $(printf '%s\n' "${pick[@]+"${pick[@]}"}" | head -5 | tr '\n' ' ' | sed 's/ $//')")"
  fi
}
while read -r _ st live slug; do
  [ "$live" = 1 ] || ocards+=("$slug.md")
  if [ "$st" = U ] && [ "$BRANCHCHK" = 1 ]; then   # 착지 줄이 없는 카드만 가지 판정 대상
    # 시작 실패 = 확인 불가(건너뛰지 않는다 · 보강 ③): 판정 스크립트 없음 · show-ref rc≥2(가지 없음 rc1 만 «대상 아님»)
    if [ ! -f "$FCHK" ]; then unk_s=$((unk_s+1)); continue; fi
    git -C "$ROOT" show-ref -q --verify "refs/heads/nano/$slug" >/dev/null 2>&1; _sr=$?
    [ "$_sr" -ge 2 ] && { unk_s=$((unk_s+1)); continue; }
    [ "$_sr" -eq 0 ] || continue
    branch_verdict "$slug"
    case "$V" in FINISHED) st=L;; UNKNOWN) [ "$VWHY" = "시간 초과" ] && unk_t=$((unk_t+1)) || unk_f=$((unk_f+1));; esac
  fi
  [ "$st" = L ] && { landed=$((landed+1)); lcards+=("$slug.md"); }
done <<<"$(printf '%s\n' "$PYOUT" | grep '^C ')"
emit
exit 0
