#!/usr/bin/env bash
# press 전 게이트 — 「랜딩+재기동 전에는 press 에 아무 반영이 없다」를 물리적으로 막는다.
# 왜: 2026-09-17 밤, 나노가 각자 nano/* 브랜치에서 고친 것을 feat 에 랜딩하지 않은 채
#     2시간 동안 발화를 돌렸다. 회차는 전부 「반영 0」인 서버에서 났고 분모만 늘었다.
#     같은 밤 재기동에서 화면(FE)만 1시간 뒤처져 회차가 또 오염됐다.
#     규칙에 네 번 적었고 네 번 빠뜨렸다 — 기억이 아니라 종료코드로 막는다.
# 쓰기: ft-press-gate.sh   → 통과 0 / 막힘 1. tester 는 이걸 통과해야만 쏜다.
set -u
# 경로·feat 브랜치는 env 로 바꾼다(ai-feature-pack 일반화 · 기본값 = BYZ 현행 — 동작 변경 0)
WT="${FT_PRESS_WT:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live}"
ROOT="${FT_PRESS_ROOT:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"
FEAT="${FT_NANO_FEAT:-feat/v6-realtime-live}"
HERE="$(cd "$(dirname "$0")" && pwd)"  # cd 전에 절대화 — 상대경로로 불러도 형제 스크립트(ft-press-set-check.sh)를 찾는다
cd "$WT" || exit 1
FAIL=0
say(){ printf '%s %s\n' "$1" "$2"; }
# ⓪ 전팀 정지(r626 DA⑥ r1 Q1) — 첫 검사 · 켜짐·깨짐이면 다른 검사 없이 막힘 1 (장치 허가 검사는 그대로)
[ -e "$ROOT/.fable-team/state/ALL_STOP.json" ] && { _as="$(FT_ROOT="$ROOT" bash "$HERE/ft-all-stop.sh" check 2>&1)" || { say "✗" "⓪ $_as"; exit 1; }; }
# ⑥ 기준선(Issue #834 · DESIGN-834-baseline-gate-arch165.md §7 r2) — 카드가 가리키는 v65 기본 동작 기준선 없이는 발사 0. 값 검사 본체는 ft-press-baseline-check.sh.
_baseline_gate(){
  local out rc
  if [ -z "${FT_PRESS_CARD:-}" ]; then say "✗" "⑥ 카드 미지정 — FT_PRESS_CARD=<카드> ft-press-gate.sh 로 발사(기준선 없는 발사 차단 · #834)"; FAIL=1; return; fi
  out="$("$HERE/ft-press-baseline-check.sh" --card "$FT_PRESS_CARD" --repo "$WT" 2>&1)"; rc=$?
  printf '%s\n' "$out" | sed 's/^/  /'
  [ "$rc" = "0" ] && say "✓" "⑥ 기준선 — $FT_PRESS_CARD" || { say "✗" "⑥ 기준선 막힘(rc=$rc) — 위 BLOCK 칸을 닫아라"; FAIL=1; }
}
# ⑦ 좌석 역할(R15 카드 H · PLAN-r15 ②) — press 는 tester·checker 좌석만. 이름 = byz-<팀>-<역할>-…#N (옛 ft-<팀>-<역할>-…#N 도 셋째 토막). 조회 실패는 fail-closed.
SEAT=""; ROLE=""
_seat_name(){ # SELFTEST 에서만 FT_PRESS_SEAT(시험용)를 읽는다 — 보통 모드는 TMUX_PANE 의 세션명뿐 · 못 구하면 빈 값
  if [ "${FT_PRESS_GATE_SELFTEST:-}" = "1" ] && [ -n "${FT_PRESS_SEAT:-}" ]; then printf '%s' "$FT_PRESS_SEAT"; return; fi
  [ -n "${TMUX_PANE:-}" ] && tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null
}
_role_gate(){
  local name; name="$(_seat_name)"
  if [ "${BYZ_PRESS_HUMAN:-}" = "1" ]; then
    # 좌석이 사람 행세(BYZ_PRESS_HUMAN)로 역할 검사를 피하는 길을 닫는다 — 이름 lint 를 통과하는 세션이면 좌석이다.
    if [ -n "$name" ] && "$HERE/ft-name-lint.sh" "$name" >/dev/null 2>&1; then
      say "✗" "⑦ 좌석($name)이 BYZ_PRESS_HUMAN 으로 사람 행세 — 금지(R15)"; FAIL=1; return
    fi
    echo "ERROR: BYZ_PRESS_HUMAN=1 — 사람 직접 press. ⑦ 좌석 역할 검사를 건너뛴다(R15)" >&2
    SEAT=human; ROLE=human; say "✓" "⑦ 사람 직접 press(BYZ_PRESS_HUMAN)"; return
  fi
  if [ -z "$name" ]; then
    say "✗" "⑦ 좌석 이름을 알 수 없다(FT_PRESS_SEAT·TMUX_PANE 둘 다 없거나 tmux 조회 실패) — fail-closed(R15)"; FAIL=1; return
  fi
  SEAT="$name"
  if [[ "$name" =~ ^[a-z0-9]+-[a-z0-9]+-([a-z0-9]+)(-[a-z0-9-]+)?#[0-9]+$ ]]; then ROLE="${BASH_REMATCH[1]}"
  else say "✗" "⑦ 역할 $name — 이름 형식 불일치(byz-<팀>-<역할>-…#N) · press 는 tester·checker 만(R15)"; FAIL=1; return; fi
  case "$ROLE" in
    tester|checker) say "✓" "⑦ 역할 $ROLE — $name" ;;
    *) say "✗" "⑦ 역할 $ROLE — press 는 tester·checker 만(R15) [$name]"; FAIL=1 ;;
  esac
}
# ⑧ 직전 회차 BTS 표(R15 카드 H · PLAN-r15 ③) — 이 좌석의 직전 허가가 가리키는 증거 폴더의 BTS.md 4자 표가 채워져 있어야 다음 회차를 쏜다.
PERMIT_DIR="${FT_PRESS_PERMIT_DIR:-}"   # r385: <라이브 루트>/.fable-team/state/press-permits — ft_data_root · 못 풀면 막는다(rc3)
[ -n "$PERMIT_DIR" ] || { . "$HERE/ft-harness-root.sh" && PERMIT_DIR="$(ft_data_root "$HERE")/.fable-team/state/press-permits"; } || exit 3
_bts_missing(){ # BTS.md → 모자란 칸 이름(" / " 구분 · 빈 출력 = 통과)
  awk -F'|' '
    function t(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function empty(s){ return s=="" || s=="-" || s=="TODO" || s=="?" }
    BEGIN{ split("아키텍처 문서,코드,로그,화면", L, ",") }
    { if (t($2)=="축" && t($3)=="사실" && t($4)=="시간") hdr=1
      for (i=1;i<=4;i++) if (t($2)==L[i]) { seen[i]=1; if (empty(t($3)) || empty(t($4))) bad[i]=1 } }
    END{ o=""; if(!hdr) o="표머리"; for(i=1;i<=4;i++) if(!seen[i]||bad[i]) o=o (o==""?"":" / ") L[i]; print o }' "$1"
}
_bts_gate(){
  local pf prev miss
  if [ -z "${FT_PRESS_EVID:-}" ]; then say "✗" "⑧ 증거 폴더 미지정 — FT_PRESS_EVID=<이번 회차 증거 폴더> ft-press-gate.sh"; FAIL=1; return; fi
  if [ -z "$SEAT" ]; then say "⊘" "⑧ 건너뜀 — 좌석을 알 수 없어(⑦ 막힘) 직전 허가를 찾지 못한다"; return; fi
  pf="$PERMIT_DIR/$SEAT.json"
  if [ ! -f "$pf" ]; then
    say "✓" "⑧ 첫 회차 — 직전 허가 없음($SEAT)"
  else
    prev="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("evid",""))' "$pf" 2>/dev/null)"
    if [ -z "$prev" ] || [ ! -f "$prev/BTS.md" ]; then
      say "✗" "⑧ 직전 회차 BTS.md 없음(${prev:-evid 칸 없음}) — 직전 허가 $pf 의 증거 폴더에 4자 표를 채워라"; FAIL=1; return
    fi
    miss="$(_bts_missing "$prev/BTS.md")"
    if [ -n "$miss" ]; then say "✗" "⑧ 직전 회차 BTS 표 미완 — 모자란 칸: $miss ($prev/BTS.md)"; FAIL=1; return; fi
    say "✓" "⑧ 직전 회차 BTS 표 4행 완료 — $prev/BTS.md"
  fi
  # 통과 → 이번 회차 골격(있으면 건드리지 않는다)
  if [ ! -e "$FT_PRESS_EVID/BTS.md" ]; then
    mkdir -p "$FT_PRESS_EVID" && printf '# BTS 4자 표 — %s\n\n| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 |  |  |\n| 코드 |  |  |\n| 로그 |  |  |\n| 화면 |  |  |\n' "$SEAT" > "$FT_PRESS_EVID/BTS.md" \
      && say "  ·" "이번 회차 BTS.md 골격 생성 — press 뒤 4행을 채워라: $FT_PRESS_EVID/BTS.md" \
      || { say "✗" "⑧ BTS.md 골격 쓰기 실패($FT_PRESS_EVID)"; FAIL=1; }
  fi
}
# 허가 파일 발급(R15 카드 H · PLAN-r15 ④) — ①~⑧ 전부 통과한 PASS 에서만. 임시파일 + mv · 같은 좌석은 덮어쓴다 · 이력은 permits.log.
_issue_permit(){
  local pf="$PERMIT_DIR/$SEAT.json" tmp ts head
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; head="$(git -C "$WT" rev-parse HEAD 2>/dev/null)"
  mkdir -p "$PERMIT_DIR" && tmp="$(mktemp "$PERMIT_DIR/.tmp.XXXXXX")" || return 1
  python3 -c 'import json,sys; k=["seat","role","runner_head","card","evid","ts"]; print(json.dumps(dict(zip(k,sys.argv[1:7])),ensure_ascii=False))' \
    "$SEAT" "$ROLE" "$head" "${FT_PRESS_CARD:-}" "$FT_PRESS_EVID" "$ts" > "$tmp" && mv "$tmp" "$pf" || { rm -f "$tmp"; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$SEAT" "$ROLE" "${FT_PRESS_CARD:-}" "$FT_PRESS_EVID" >> "$PERMIT_DIR/permits.log" || return 1
  [ "$SEAT" = "human" ] && { mkdir -p "$FT_PRESS_EVID" && printf 'human press %s by %s card=%s\n' "$ts" "$(whoami)" "${FT_PRESS_CARD:-}" > "$FT_PRESS_EVID/human.txt" || return 1; }
  say "✓" "허가 파일 발급 — $pf"
}
# 자체시험(FT_PRESS_GATE_SELFTEST=1): ①~⑤ 는 stub · ⑥⑦⑧ 은 진짜(허가 파일은 쓰지 않는다). 성공 = exit 3(GO 아님 — `gate && launch` 는 여기서 멈춘다) · 막힘 = 1. 「발화해도 된다」는 찍지 않는다.
if [ "${FT_PRESS_GATE_SELFTEST:-}" = "1" ]; then
  for n in ① ② ③ ④ ⑤; do say "⚠" "SELFTEST stub $n — 실제 검사 0"; done
  _baseline_gate; _role_gate; _bts_gate
  echo; [ "$FAIL" = "0" ] && { echo "PRESS-GATE SELFTEST PASS"; exit 3; }
  echo "PRESS-GATE SELFTEST BLOCK"; exit 1
fi

# ① 현역 나노 브랜치 미랜딩 0
UNLANDED=0
# ★현역 좌석이 붙어 있는 워크트리만 본다★ — 죽은 좌석 워크트리의 옛 커밋은 press 와 무관하다
LIVE_WT=$(python3 -c "
import json,subprocess,re
d=json.load(open('$ROOT/.fable-team/seats.json'))
live=set(subprocess.run(['tmux','list-sessions','-F','#{session_name}'],capture_output=True,text=True).stdout.split())
out=set()
for k,v in d.items():
    if not isinstance(v,dict) or v.get('role')=='stop-ready' or k not in live: continue
    m=re.match(r'ft-v65-temp-(.+?)#\\d+$',k) or re.match(r'ft-v65-(mr|le)-track#\\d+$',k)
    if m: out.add('v65-'+m.group(1))
print(' '.join(sorted(out)))" 2>/dev/null)
# ★세트 소속 표시(M7 · 표시만 — 차단 판정·FAIL 코드 불변)★ press 가 시험하는 세트 경로의 정의는 ft-press-set-check.sh 한 곳 — 여기서 복사하지 않고 읽는다.
SETP=()
while IFS= read -r p; do [ -n "$p" ] && SETP+=("$p"); done < <("$HERE/ft-press-set-check.sh" --print-set-paths 2>/dev/null)
_set_member(){ # 워크트리 → 이 나노의 «순 변경»(feat 와 merge-base 기준 3점 · 되돌림·merge 는 사라진다)이 press 세트에 닿는지 한 줄
  local w="$1" net n files
  net=$(git -C "$w" diff --name-only "$FEAT"...HEAD -- "${SETP[@]}" 2>/dev/null) || { say "  ⚠" "세트 소속 조회 실패 — $(basename "$w")"; return; }
  n=$(printf '%s\n' "$net" | grep -c .)
  if [ "$n" = "0" ]; then
    say "  ⊘" "세트 밖($(basename "$w")) — 랜딩해도 press 세트 불변(남은 커밋 = 되돌림·merge·문서)"
  else
    files=$(printf '%s\n' "$net" | head -5 | paste -sd, - | sed 's/,/, /g')
    [ "$n" -gt 5 ] && files="$files +$((n-5))"
    say "  ⊕" "press 세트 포함 예정($(basename "$w")) — 랜딩 전에는 이 press 가 이 수정을 시험하지 않는다: $files"
  fi
}
[ "${#SETP[@]}" = "0" ] && say "  ⚠" "ft-press-set-check.sh --print-set-paths 실패 — 세트 소속 표시 생략(차단 판정은 그대로)"
_other_trunk(){ # 워크트리 → 선언 base(.worktree-info.json)가 FEAT 가 아니고 git 으로 확인되면 «다른 줄기»(0) · 아니면 센다(1) — FEAT 랜딩 대상이 아니라 FEAT..HEAD 에 main 쪽 커밋이 섞인다(R58)
  local w="$1" decl base sha rc
  decl=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1])); print(d['base'] + '\t' + d['base_sha'])" "$w/.worktree-info.json" 2>/dev/null) || return 1
  base=${decl%%$'\t'*}; sha=${decl#*$'\t'}
  [ -n "$base" ] && [ -n "$sha" ] || return 1
  case "$base" in "$FEAT"|"origin/$FEAT") return 1;; esac
  if git -C "$w" rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 && git -C "$w" merge-base --is-ancestor "$sha" HEAD 2>/dev/null \
     && git -C "$w" merge-base --is-ancestor "$sha" "$base" 2>/dev/null; then  # ⒟ base_sha ⊂ 선언 base(정상 spawn 은 그때 tip) — 선언과 sha 의 계보 결합(DA r2)
    git -C "$w" merge-base --is-ancestor "$sha" "$FEAT" 2>/dev/null; rc=$?  # base_sha ⊂ FEAT 면 «다른 줄기» 근거 없음(옛 main 조상 오기 · DA Q1) — rc=1 만 «조상 아님»
    [ "$rc" = "0" ] && return 1
    [ "$rc" = "1" ] && { say "  ⊘" "다른 줄기($(basename "$w") · base=$base) — FEAT 랜딩 대상 아님 · ① 셈 제외"; return 0; }
  fi
  say "  ⚠" "base 선언 확인 실패($(basename "$w") · base=$base) — FEAT 기준으로 센다"; return 1
}
for W in $LIVE_WT; do
  W="$ROOT/.worktrees/$W"
  [ -e "$W/.git" ] || continue
  _other_trunk "$W" && continue
  # 제품 경로를 건드린 미랜딩만 센다(문서만이면 press 에 영향 0)
  # ★cherry-pick -x 로 이미 feat 에 올라간 것은 «미랜딩이 아니다»★ — 원본 sha 는 조상이 아니므로
  # 제목으로 대조한다(이 오탐 때문에 9건이 미랜딩으로 잡혔다).
  # ★테스트 파일은 실행 번들에 영향 0★ 이라 제품 경로에서 뺀다.
  # 랜딩 판정 셋 — 하나라도 맞으면 랜딩된 것으로 본다:
  #   ⒜같은 제목이 feat 에 있다(cherry-pick -x)
  #   ⒝feat 커밋 «본문»에 그 sha 가 인용돼 있다(통행증 규격으로 «재작성»해 올린 경우 — 실제로 있었다)
  #   ⒞sha 가 feat 의 조상이다
  P=0
  FEAT_SUBJ=$(git log "$FEAT" --format='%s' -400)
  FEAT_BODY=$(git log "$FEAT" --format='%H%n%B' -60)
  while IFS=$'\t' read -r h t; do
    [ -z "$h" ] && continue
    printf '%s\n' "$FEAT_SUBJ" | grep -qxF "$t" && continue
    printf '%s\n' "$FEAT_BODY" | grep -q "${h:0:9}" && continue
    git merge-base --is-ancestor "$h" "$FEAT" 2>/dev/null && continue
    P=$((P+1)); say "  ·" "미랜딩 후보: $t"
  done < <(git -C "$W" log --format='%H%t%s' "$FEAT"..HEAD -- worker shared gateway clients ':(exclude)*__tests__*' ':(exclude)tests/*' 2>/dev/null | sed 's/\(^[0-9a-f]*\)/\1\t/' )
  [ "${P:-0}" != "0" ] && { say "✗" "미랜딩 제품 커밋 $P — $(basename "$W")"; UNLANDED=$((UNLANDED+P)); }
  [ "${#SETP[@]}" != "0" ] && _set_member "$W"
done
[ "$UNLANDED" = "0" ] && say "✓" "미랜딩 제품 커밋 0" || FAIL=1

# ② 워커·관문·화면 기동시각 > 각자의 최신 제품 커밋
chk(){ # 이름 포트 경로들
  local name=$1 port=$2; shift 2
  local pid ep cp
  pid=$(lsof -ti:"$port" -sTCP:LISTEN 2>/dev/null | head -1)
  [ -z "$pid" ] && { say "✗" "$name 리스너 없음(:$port)"; FAIL=1; return; }
  ep=$(python3 -c "
import subprocess,datetime,re
o=subprocess.run(['ps','-o','lstart=','-p','$pid'],capture_output=True,text=True).stdout.strip()
m=re.search(r'(\\d{1,2})/\\s*(\\d{1,2})\\s+(\\d{2}):(\\d{2}):(\\d{2})\\s+(\\d{4})',o)
if m:
    mo,dd,hh,mi,ss,yy=map(int,m.groups())
    print(int(datetime.datetime(yy,mo,dd,hh,mi,ss).timestamp()))
else:
    try: print(int(datetime.datetime.strptime(' '.join(o.split()),'%a %b %d %H:%M:%S %Y').timestamp()))
    except Exception: print('')" 2>/dev/null)
  cp=$(git log -1 --format=%ct -- "$@" 2>/dev/null)
  if [ -n "$ep" ] && [ -n "$cp" ] && [ "$ep" -gt "$cp" ]; then
    say "✓" "$name pid=$pid 기동 > 최신 커밋($(date -r "$cp" '+%m-%d %H:%M:%S'))"
  else
    say "✗" "$name pid=$pid 기동이 최신 커밋보다 «앞»선다 — 재기동 필요"; FAIL=1
  fi
}
chk worker 8081 worker shared
chk gateway 8080 gateway shared
chk 화면 3001 clients/web ":(exclude)clients/web/__tests__/*"

# ③ 활성화 lane + health
grep -q 'activation bundle established' /tmp/byz-worker.log \
  && say "✓" "[C2c-ACT] activation bundle established" \
  || { say "✗" "활성화 번들 줄 없음 — legacy lane 의심"; FAIL=1; }
code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://localhost:8081/health 2>/dev/null)
[ "$code" = "200" ] && say "✓" "worker health 200" || { say "✗" "worker health=$code"; FAIL=1; }
# FE SSE 는 Caddy :8443 경유(run.command NEXT_PUBLIC_SSE_URL) — 죽으면 press 무효(2026-10-01 m7-rt-ledger 2회 · /health 는 307 이라 api 경로)
code2=$(curl -sk -m 4 -o /dev/null -w '%{http_code}' https://localhost:8443/api/v1/health/ 2>/dev/null)
[ "$code2" = "200" ] && say "✓" "Caddy 8443 health 200" || { say "✗" "Caddy 8443 health=$code2 — 리스너 없으면 run.command 로 기동"; FAIL=1; }
# HTTP 200 이어도 본문 consumer_ready=false 면 PTT disabled — press 가 no_viable_target 으로 무효(2026-09-26 long3m-002)
cr=$(curl -s -m 4 http://localhost:8081/health 2>/dev/null | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("unparsed"); sys.exit()
print("ok" if d.get("consumer_ready") is True else "status=%s consumer_ready=%s" % (d.get("status"), d.get("consumer_ready")))' 2>/dev/null)
[ "$cr" = "ok" ] && say "✓" "worker consumer_ready=true" || { say "✗" "worker ${cr:-unparsed} — LOOM DSN·언어 웜업 먼저(troubleshoot 20260926-local-worker)"; FAIL=1; }
# 재기동 직후 LOOM selfhost 프리워밍(전 튜플 실 LLM 호출 · ≈3 분)이 press 와 겹치면 vLLM 프리필 포화 → 번역 7 s 타임아웃 → 봉인 실패
# (2026-10-02 10:12 K5 p1 무효 · 타임아웃 30건). 이번 기동의 «Warming up» 줄 «뒤»에 prewarm SUMMARY 가 있어야 한다.
boot_ln=$(grep -n 'Worker Starting - Warming up services' /tmp/byz-worker.log 2>/dev/null | tail -1 | cut -d: -f1)
sum_ln=$(grep -n 'selfhost prewarm SUMMARY' /tmp/byz-worker.log 2>/dev/null | tail -1 | cut -d: -f1)
# SUMMARY 줄 «존재»만으로 통과시키지 않는다 — FAILED>0 이면 vLLM 이 그 순간 포화였다는 뜻(2026-10-02 20:22 K4 p1 무효 · 22 ok/14 FAILED 를 PASS).
sum_txt=$([ -n "$sum_ln" ] && sed -n "${sum_ln}p" /tmp/byz-worker.log | grep -oE 'SUMMARY: [0-9]+ ok / [0-9]+ FAILED')
sum_failed=$(printf '%s' "$sum_txt" | grep -oE '[0-9]+ FAILED' | grep -oE '[0-9]+')
if [ -n "$boot_ln" ] && [ -n "$sum_ln" ] && [ "$sum_ln" -gt "$boot_ln" ] && [ "${sum_failed:-1}" -gt 0 ]; then
  say "✗" "LOOM prewarm SUMMARY FAILED>0 ($sum_txt) — 공유 vLLM 포화 의심(다른 트랙 worker 기동·측정) → 원인 정리 뒤 worker 재기동"; FAIL=1
elif [ -n "$boot_ln" ] && [ -n "$sum_ln" ] && [ "$sum_ln" -gt "$boot_ln" ]; then
  say "✓" "LOOM prewarm SUMMARY 가 이번 기동 뒤에 있음($sum_txt)"
else
  say "✗" "LOOM selfhost 프리워밍 진행 중/미완 — SUMMARY 줄이 뜬 뒤 발사(겹치면 번역 타임아웃으로 회차 무효)"; FAIL=1
fi

# ④ 워커 필수 env(WORKER_ENV_SPEC 키 이름만 대조 · 값 복제 0)
wpid=$(lsof -ti:8081 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$wpid" ]; then
  miss=0
  while read -r k; do
    ps eww "$wpid" 2>/dev/null | tr ' ' '\n' | grep -q "^${k}=" || { say "✗" "env 없음: $k"; miss=$((miss+1)); }
  done < <(sed -n '/^WORKER_ENV_SPEC=(/,/^)/p' scripts/server/ready-check.sh | grep -oE '"[A-Z0-9_]+=' | tr -d '"=')
  [ "$miss" = "0" ] && say "✓" "필수 env 전부 실림" || FAIL=1
fi

# ⑤ 세트 축(M7 · single_set_testing §1 규칙 1) — 러너 파일 워크트리 HEAD == worker·gateway pid cwd 워크트리 HEAD · 세트 경로 dirty 0. 정의 본체는 ft-press-set-check.sh.
_cwd_of(){ lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }
# 기동 stamp = 서비스 pid 프로세스 시작시각(epoch) — set-check 가 «워크트리 HEAD 가 기동 뒤 움직였나» 를 가른다(A4). 못 구하면 빈 값 → set-check 가 REJECT.
_start_of(){ LC_ALL=C date -j -f '%a %b %e %T %Y' "$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)" +%s 2>/dev/null; }
gpid=$(lsof -ti:8080 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -z "${wpid:-}" ] || [ -z "$gpid" ]; then
  say "✗" "세트 축 — worker(:8081)·gateway(:8080) 리스너 pid 없음"; FAIL=1
else
  wcwd=$(_cwd_of "$wpid"); gcwd=$(_cwd_of "$gpid")
  if [ -z "$wcwd" ] || [ -z "$gcwd" ]; then say "✗" "세트 축 — pid cwd 조회 실패(worker=$wpid gateway=$gpid)"; FAIL=1
  else
    "$(dirname "$0")/ft-press-set-check.sh" --runner "$WT/tests/e2e/realtime_multi_e2e.py" --worker-cwd "$wcwd" --gateway-cwd "$gcwd" \
      --worker-start "$(_start_of "$wpid")" --gateway-start "$(_start_of "$gpid")" || FAIL=1
  fi
fi

# ⑥ 기준선 — 보통 모드에 시험 환경 변수가 «있기만 해도» 막는다(상속된 SELFTEST 로 실발사 0 · §7 C2 잔여 2)
[ -n "${FT_PRESS_GATE_SELFTEST+x}" ] && { say "✗" "⑥ 시험 모드 상속 — 발사 금지(FT_PRESS_GATE_SELFTEST=${FT_PRESS_GATE_SELFTEST} 를 unset)"; FAIL=1; }
_baseline_gate
# ⑦ 보통 모드에 FT_PRESS_SEAT 가 «있기만 해도» 막는다 — 좌석이 tester 이름을 변수 한 줄로 위조해 역할 검사를 통과하는 길(⑥ 의 시험 변수 상속 차단과 같은 규약)
[ -n "${FT_PRESS_SEAT+x}" ] && { say "✗" "⑦ 시험 변수 상속 — FT_PRESS_SEAT 는 SELFTEST 전용(unset)"; FAIL=1; }
_role_gate
_bts_gate

echo
if [ "$FAIL" = "0" ] && ! _issue_permit; then say "✗" "허가 파일 발급 실패($PERMIT_DIR) — 허가 없이 통과시키면 다음 회차 ⑧ 이 열리지 않으므로 BLOCK"; FAIL=1; fi
[ "$FAIL" = "0" ] && { echo "PRESS-GATE PASS — 발화해도 된다"; exit 0; }
echo "PRESS-GATE BLOCK — 위 ✗ 를 먼저 닫아라(랜딩 → stop→run → 화면도 같이)"; exit 1
