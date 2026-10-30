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
FEAT="${FT_NANO_FEAT:-origin/main}"   # r1128: 옛 기본 feat/v6-realtime-live 는 10-23 에 멈춰 main 위 작업을 «미랜딩» 으로 셌다(460 오탐)
HERE="$(cd "$(dirname "$0")" && pwd)"  # cd 전에 절대화 — 상대경로로 불러도 형제 스크립트(ft-press-set-check.sh)를 찾는다
cd "$WT" || exit 1
FAIL=0
say(){ printf '%s %s\n' "$1" "$2"; }
# ★숫자 env 입력 검사 «한 곳»(r769 r2 반송 · DA⑥ r2 HOLD: 변수마다 case 로 검사해 구멍 2개가 났다)★
#   _int_port = ^[1-9][0-9]{3,4}$ 이고 1024~65535 일 때만 rc0 — 앞 0(017620 은 8진으로 8080) · 부호 · 공백 · 빈 값 = rc1
#   _decimal  = ^[0-9]+(\.[0-9]+)?$ 일 때만 rc0 — 60..0 · 1e2 · 60. · .5 · -1 = rc1
_int_port(){
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  case "$1" in 0*) return 1 ;; esac
  [ "${#1}" -ge 4 ] && [ "${#1}" -le 5 ] || return 1
  [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}
_decimal(){
  case "$1" in ''|*[!0-9.]*|.*|*.|*.*.*) return 1 ;; esac
  return 0
}
# r634: press 대상 갈래 — FT_PRESS_TARGET=dev 로 «선언한 회차만» ②~⑤ 를 dev 세트 검사로 바꾼다(기본 local = 지금과 같음 · 조용히 건너뛰기 0 · ①⑥⑦⑧·허가 파일은 그대로)
TARGET="${FT_PRESS_TARGET:-local}"
DEV_WEB="${FT_PRESS_DEV_WEB:-https://byz-agents-web-dev-a3yix5apcq-du.a.run.app}"
DEV_GATEWAY="${FT_PRESS_DEV_GATEWAY:-https://byz-agents-gateway-dev-a3yix5apcq-du.a.run.app}"
DEV_WANT="${FT_PRESS_DEV_WANT:-}"
DEV_REGION="${FT_PRESS_DEV_REGION:-asia-northeast3}"
DEV_SVCS="${FT_PRESS_DEV_SVCS:-web=byz-agents-web-dev,gateway=byz-agents-gateway-dev,worker=byz-agents-worker-dev}"
DEV_WEB_MARK_DEFAULT='<title>하우투 톡'   # r685 DA⑥ H1: 이 앱만의 표지(실측 dev 루트 «<title>하우투 톡 — 실시간 AI 음성 통역 · 강의 자막</title>») — /_next/static/ 는 모든 Next 화면에 있어 고유하지 않다
DEV_WEB_MARK="${FT_PRESS_DEV_WEB_MARK:-$DEV_WEB_MARK_DEFAULT}"   # env 로 이것만 바꾼다(6글자 미만이면 경고 + 기본값 · _dev_gate)
DEV_ERR_MARKS=('Service Unavailable' 'Application failed to start' '502 Bad Gateway' '503 Service' 'Error: Server Error' 'That’s an error' "That's an error" 'Internal Server Error' 'Application error:' 'Failed to compile' 'This page could not be found' '페이지를 찾을 수 없')   # r685: 오류 화면 표지 — 대소문자 무시 · script·style 을 뺀 «보이는 글자»에만 대조(정상 화면 RSC 데이터에 «This page could not be found» 2회)
# r685: 본문 판별 1곳(web·json) — _bounded 안에서 돈다(DA⑥ H2) · 출력 = 막을 이유(rc 1) · 빈 출력 rc 0 = 정상. 표식 «r685-dev-body» 는 시험 감싸개가 이 호출만 고른다
_DEV_BODY_PY='# r685-dev-body · argv = 종류 파일 앱표지 오류표지…
import json,re,sys
k,f,mark=sys.argv[1:4]; errs=sys.argv[4:]
b=open(f,"rb").read().decode("utf-8","replace")
def bad(s): print(s); sys.exit(1)
def text(s): return re.sub(r"\s+"," ",re.sub(r"(?s)<[^>]+>"," ",re.sub(r"(?is)<(script|style|noscript)\b.*?</\1\s*>"," ",s))).strip()
if not b.strip(): bad("본문이 비었다")
if k=="json":
    try: d=json.loads(b)
    except Exception: d=None
    if not (isinstance(d,dict) and d.get("status")=="ok"): bad("본문이 status=ok JSON 객체가 아니다")
    sys.exit(0)
vis=text(b).lower(); lb=b.lower()
for e in errs:
    if e.lower() in vis: bad("본문에 오류 표지 «%s»" % e)
for need in (mark,"/_next/static/"):
    if need.lower() not in lb: bad("본문에 앱 표지 «%s» 없음" % need)
if "</html>" not in lb: bad("본문에 «</html>» 없음 — 잘린 본문")
m=re.search(r"(?is)<body\b[^>]*>(.*)</body\s*>",b)
n=len(text(m.group(1))) if m else 0
if n<20: bad("본문 <body> 의 보이는 글자 %d자(20 미만) — 빈 껍데기" % n)'
DEV_WAIT=7   # dev 호출 1회 상한(초) — 콜드스타트로 늘어지면 막는다(fail-closed)
DEV_BUDGET="${FT_PRESS_DEV_BUDGET:-70}"   # dev 검사 «전체» 마감(초 · r634 DA⑥ r1 H4) — 넘기면 그 자리에서 막는다
DEV_END=0
# ⓪ 전팀 정지(r626 DA⑥ r1 Q1) — 첫 검사 · 켜짐·깨짐이면 다른 검사 없이 막힘 1 (장치 허가 검사는 그대로)
[ -e "$ROOT/.fable-team" ] && { _as="$(FT_ROOT="$ROOT" bash "$HERE/ft-all-stop.sh" check 2>&1)" || { say "✗" "⓪ $_as"; exit 1; }; }
# ⓪b 부하 게이트(r769b · 오빠 지시 2026-10-23) — 5분 평균 load ≥ 임계(기본 60 FT_PRESS_LOAD_MAX)면 press 시작 REJECT.
#   왜: 부하 81~102 에서 돈 lecture p3-r6 이 청크 POST 1500ms 초과 15 · Redis Timeout 14 로 무효가 됐다.
#   임계는 env 로 덮는다 · 못 읽으면 경고만(이 머신의 load 를 못 읽는 것과 부하를 구분한다).
LOAD_MAX="${FT_PRESS_LOAD_MAX:-60}"
_load5(){ # macOS sysctl vm.loadavg = "{ 1분 5분 15분 }" · 없으면 /proc/loadavg 의 2칸
  local v
  v="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $2}')"
  [ -n "$v" ] || v="$(awk '{print $2}' /proc/loadavg 2>/dev/null)"
  printf '%s' "$v"
}
_retry_at(){ # 10분 뒤 시각(HH:MM) — macOS date -v · GNU date -d
  local t
  t="$(date -v+10M '+%H:%M' 2>/dev/null)" || t=""
  [ -n "$t" ] || t="$(date -d '+10 minutes' '+%H:%M' 2>/dev/null)"
  printf '%s' "${t:-+10분}"
}
_load_gate(){
  local v
  _decimal "$LOAD_MAX" || { say "✗" "FT_PRESS_LOAD_MAX=$LOAD_MAX — 숫자(부하 임계)만"; FAIL=1; return; }
  v="$(_load5)"
  if [ -z "$v" ]; then say "⚠" "부하 5분 평균 못 읽음 — 부하 게이트 건너뜀"; return; fi
  if awk -v a="$v" -v b="$LOAD_MAX" 'BEGIN{exit !(a>=b)}'; then
    say "✗" "5분 평균 부하 $v ≥ 임계 $LOAD_MAX — 지금 쏘면 회차가 무효(청크 POST 타임아웃·Redis Timeout) · 원인 상위 3 프로세스:"
    ps -Ao pcpu,pid,comm -r 2>/dev/null | head -4 | tail -3 | sed 's/^/      /'
    # 거절 = «기다림 신호» — 지금 값·기준·다시 볼 시각을 1줄로 준다(planner 2681)
    say "·" "지금 load $v · 기준 FT_PRESS_LOAD_MAX=$LOAD_MAX · 다시 볼 시각 $(_retry_at) (5분 평균이 그때 내려오는지)"
    FAIL=1; return
  fi
  say "✓" "부하 5분 평균 $v < 임계 $LOAD_MAX"
}
# ★갈래를 «분명히 적은» 회차만 dev 검사 — 오타·미지 값은 막는다(선언 없이 로컬 칸을 건너뛰는 길 0)★
case "$TARGET" in
  local|dev) ;;
  *) say "✗" "FT_PRESS_TARGET=$TARGET — 대상은 local(기본)·dev 만"; echo "PRESS-GATE BLOCK — 위 ✗ 를 먼저 닫아라"; exit 1 ;;
esac
_bounded(){ # 초 명령… — timeout/gtimeout 은 -k(TERM 뒤 KILL) · 없으면 자식을 TERM→2초 뒤 KILL(r634 H4: TERM 무시 자식)
  local secs=$1; shift
  local t p w rc
  for t in timeout gtimeout; do
    if command -v "$t" >/dev/null 2>&1; then "$t" -k 2 "$secs" "$@"; return $?; fi
  done
  "$@" & p=$!
  ( sleep "$secs"; kill -TERM "$p" 2>/dev/null; sleep 2; kill -KILL "$p" 2>/dev/null ) & w=$!
  wait "$p"; rc=$?
  kill -TERM "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}
_dev_left(){ local l=$(( DEV_END - $(date +%s) )); [ "$l" -gt 0 ] || l=0; printf '%s' "$l"; }
_dev_cap(){ local l; l="$(_dev_left)"; [ "$l" -gt "$DEV_WAIT" ] && l="$DEV_WAIT"; printf '%s' "$l"; }
_dev_body_bad(){ # 종류(web|json) 파일 → 막을 이유 · 빈 출력 = 그 서비스의 정상 모습(r685) · 판별도 dev 마감 안(DA⑥ H2)
  local kind=$1 f=$2 cap out rc
  case "$kind" in web|json) ;; *) printf '모르는 본문 종류 %s' "$kind"; return ;; esac
  cap="$(_dev_cap)"
  [ "$cap" = "0" ] && { printf '본문 판별 전 dev 검사 시간 마감(%s초)' "$DEV_BUDGET"; return; }
  out="$(_bounded "$cap" python3 -c "$_DEV_BODY_PY" "$kind" "$f" "$DEV_WEB_MARK" "${DEV_ERR_MARKS[@]}" 2>/dev/null)"; rc=$?
  if [ "$rc" = "1" ] && [ -n "$out" ]; then printf '%s' "$out"; return; fi
  [ "$rc" = "0" ] || { printf '본문 판별 실패(rc=%s · 시간 초과·python 오류) — fail-closed' "$rc"; return; }
  [ "$(_dev_left)" = "0" ] && printf '본문 판별이 dev 검사 시간 마감(%s초)을 넘김' "$DEV_BUDGET"
}
_dev_health(){ # 이름 url 종류(web|json) → 종료코드 0 ∧ 200 ∧ 본문이 그 서비스의 정상 모습(r634 H3 → r685: 서비스별 판별)
  local name=$1 url=$2 kind=$3 cap code rc tmp why
  cap="$(_dev_cap)"
  if [ "$cap" = "0" ]; then say "✗" "dev $name — dev 검사 시간 마감(${DEV_BUDGET}초)"; return 1; fi
  tmp="$(mktemp)" || { say "✗" "dev $name — 임시파일 실패"; return 1; }
  code=$(_bounded "$cap" curl -s -m "$cap" -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null); rc=$?
  if [ "$rc" != "0" ] || [ "$code" != "200" ]; then
    rm -f "$tmp"; say "✗" "dev $name health=${code:-000} rc=$rc — $url"; return 1
  fi
  why="$(_dev_body_bad "$kind" "$tmp")"; rm -f "$tmp"
  if [ -n "$why" ]; then say "✗" "dev $name health 200 이지만 $why — 서비스가 아니라 오류 페이지다: $url"; return 1; fi
  say "✓" "dev $name health 200 — $url"; return 0
}
_dev_image(){ # 서비스 → 배포 이미지 40자 hex sha · rc0 아님·형식 불명·시간 초과면 실패(빈 값 · fail-closed)
  local svc=$1 out rc img sha cap
  cap="$(_dev_cap)"
  if [ "$cap" = "0" ]; then say "✗" "dev $svc — dev 검사 시간 마감(${DEV_BUDGET}초)"; return 1; fi
  out=$(_bounded "$cap" gcloud run services describe "$svc" --region="$DEV_REGION" \
        --format='value(spec.template.spec.containers[0].image)' 2>/dev/null); rc=$?   # r634 H2①: 종료코드를 잃지 않는다
  [ "$rc" = "0" ] || return 1
  img="$(printf '%s' "$out" | tr -d '\r' | tail -1)"
  [ -n "$img" ] || return 1
  sha="${img##*[:@]}"   # 이미지 참조의 «맨 끝» = 태그(커밋 sha) — registry:tag · digest(@sha256:) 둘 다
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1   # r634 H2②: 40자 hex 만(축약·latest 불가)
  printf '%s' "$sha"
}
_dev_svcs(){ # r634 H3: web·gateway·worker 세 키 «필수» · 빠짐·중복·모르는 이름 = 막힘(빈 값으로 루프 0회 통과 0)
  local pair name seen=""
  for pair in ${DEV_SVCS//,/ }; do
    case "$pair" in *=*) ;; *) say "✗" "FT_PRESS_DEV_SVCS 항목이 «이름=서비스» 꼴이 아니다: $pair"; return 1 ;; esac
    name="${pair%%=*}"
    case " web gateway worker " in *" $name "*) ;; *) say "✗" "FT_PRESS_DEV_SVCS 모르는 서비스 이름: $name — web·gateway·worker 만"; return 1 ;; esac
    case " $seen " in *" $name "*) say "✗" "FT_PRESS_DEV_SVCS 중복: $name"; return 1 ;; esac
    seen="$seen $name"
  done
  for name in web gateway worker; do
    case " $seen " in *" $name "*) ;; *) say "✗" "FT_PRESS_DEV_SVCS 에 $name 가 없다 — 세 서비스(web·gateway·worker)를 모두 지정해야 한다"; return 1 ;; esac
  done
  return 0
}
_norm_url(){ local u="$1"; while [ "${u%/}" != "$u" ]; do u="${u%/}"; done; printf '%s' "$u"; }
_dev_runner(){ # r634 H1: 게이트가 검사한 주소 = 러너가 실제로 쏠 주소. 다르면 dev 시험이 아니다
  local vname want got ok=0
  for vname in BYZ_WEB_BASE BYZ_GATEWAY_BASE; do
    case "$vname" in BYZ_WEB_BASE) want="$DEV_WEB" ;; *) want="$DEV_GATEWAY" ;; esac
    got="${!vname:-}"
    if [ -z "$got" ]; then
      say "✗" "dev 대상인데 러너 env $vname 이 비었다 — 러너는 기본 localhost 로 쏜다(게이트가 본 주소 ≠ 러너가 쏠 주소)"; ok=1; continue
    fi
    if [ "$(_norm_url "$got")" != "$(_norm_url "$want")" ]; then
      say "✗" "러너 env $vname=$got ≠ 게이트 검사 주소 $want — 같은 주소여야 한다"; ok=1; continue
    fi
    say "✓" "dev 러너 대상 일치 — $vname=$want"
  done
  return "$ok"
}
_dev_gate(){ # ②~⑤ 대신 — dev 세트가 살아 있고(health 200) 배포된 판이 «이 워크트리 HEAD» 를 포함하는가
  local pair name svc sha bad=0 head
  if [ -z "$DEV_WANT" ]; then
    say "✗" "dev 대상인데 원하는 커밋 미지정 — FT_PRESS_DEV_WANT=<커밋 sha> 를 줘야 «반영 0 회차» 를 막는다"; FAIL=1; return
  fi
  [[ "$DEV_WANT" =~ ^[0-9a-f]{40}$ ]] || { say "✗" "FT_PRESS_DEV_WANT=${DEV_WANT:0:12} — 40자 hex 커밋 sha 만(가지 이름·HEAD~1·축약 sha 금지)"; FAIL=1; return; }
  head="$(git -C "$WT" rev-parse HEAD 2>/dev/null)"
  if [ "$DEV_WANT" != "$head" ]; then
    say "✗" "FT_PRESS_DEV_WANT=${DEV_WANT:0:10} ≠ press 워크트리 HEAD=${head:0:10} — 시험하려는 판이 이 워크트리의 판이 아니다(오래된 조상으로 통과 0)"; FAIL=1; return
  fi
  _dev_svcs || { FAIL=1; return; }
  DEV_END=$(( $(date +%s) + DEV_BUDGET ))
  say "·" "dev 대상 — 로컬 칸 ②~⑤ 대신 dev 칸(health 200 · 배포 이미지 sha ⊇ ${DEV_WANT:0:10}) · $DEV_WEB · $DEV_GATEWAY"
  _dev_runner || bad=1
  if [ "${#DEV_WEB_MARK}" -lt 6 ]; then   # r685 DA⑥ H1: «<» 같은 짧은 표지는 아무 화면에나 있다
    say "⚠" "FT_PRESS_DEV_WEB_MARK=«${DEV_WEB_MARK}» ${#DEV_WEB_MARK}글자 — 6글자 미만은 표지로 못 쓴다 · 기본값 «${DEV_WEB_MARK_DEFAULT}» 로 본다"
    DEV_WEB_MARK="$DEV_WEB_MARK_DEFAULT"
  fi
  _dev_health web "$DEV_WEB/" web || bad=1
  _dev_health gateway "$DEV_GATEWAY/api/v1/health/" json || bad=1
  for pair in ${DEV_SVCS//,/ }; do
    name="${pair%%=*}"; svc="${pair#*=}"
    sha="$(_dev_image "$svc")"
    if [ -z "$sha" ]; then say "✗" "dev $name 이미지 sha 못 읽음($svc · region=$DEV_REGION) — fail-closed"; bad=1; continue; fi
    if git -C "$WT" merge-base --is-ancestor "$DEV_WANT" "$sha" 2>/dev/null; then
      say "✓" "dev 이미지 $name ⊇ ${DEV_WANT:0:10}($svc ${sha:0:10})"
    else
      say "✗" "$svc 이미지 ${sha:0:10} 에 ${DEV_WANT:0:10} 없음"; bad=1
    fi
  done
  [ "$bad" = "0" ] || FAIL=1
}
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
  python3 -c 'import json,sys; k=["seat","role","runner_head","card","evid","ts","target"]; print(json.dumps(dict(zip(k,sys.argv[1:8])),ensure_ascii=False))' \
    "$SEAT" "$ROLE" "$head" "${FT_PRESS_CARD:-}" "$FT_PRESS_EVID" "$ts" "$TARGET" > "$tmp" && mv "$tmp" "$pf" || { rm -f "$tmp"; return 1; }
  # r634: 대상 칸은 «끝에 덧붙인다» — 옛 줄(5칸)을 읽는 쪽이 있어도 하위 호환
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$SEAT" "$ROLE" "${FT_PRESS_CARD:-}" "$FT_PRESS_EVID" "$TARGET" >> "$PERMIT_DIR/permits.log" || return 1
  [ "$SEAT" = "human" ] && { mkdir -p "$FT_PRESS_EVID" && printf 'human press %s by %s card=%s\n' "$ts" "$(whoami)" "${FT_PRESS_CARD:-}" > "$FT_PRESS_EVID/human.txt" || return 1; }
  say "✓" "허가 파일 발급 — $pf (target=$TARGET)"
}
# 자체시험(FT_PRESS_GATE_SELFTEST=1): ①~⑤ 는 stub · ⑥⑦⑧ 은 진짜(허가 파일은 쓰지 않는다). 성공 = exit 3(GO 아님 — `gate && launch` 는 여기서 멈춘다) · 막힘 = 1. 「발화해도 된다」는 찍지 않는다.
if [ "${FT_PRESS_GATE_SELFTEST:-}" = "1" ]; then
  for n in ① ② ③ ④ ⑤; do say "⚠" "SELFTEST stub $n — 실제 검사 0"; done
  _baseline_gate; _role_gate; _bts_gate
  echo; [ "$FAIL" = "0" ] && { echo "PRESS-GATE SELFTEST PASS"; exit 3; }
  echo "PRESS-GATE SELFTEST BLOCK"; exit 1
fi

_load_gate   # ⓪b 부하 — 자체시험(위 stub 경로)은 부하와 무관하게 돈다

# ① 현역 나노 브랜치 미랜딩 0
UNLANDED=0
# ★v65 나노 접두·이름 판정은 공용 규칙(ft_teamset.py) 한 곳(r655)★ — 옛 이름과 새 이름을 둘 다 세는 판정을 스크립트마다 복사하지 않는다. 판정기를 못 부르면 조용한 통과 없이 막는다.
LIVE_WT="$(python3 "$HERE/ft_teamset.py" wt-v65 --seats "$ROOT/.fable-team/seats.json" 2>/dev/null)" || { say "✗" "① 나노 이름 규칙(ft_teamset.py wt-v65) 못 읽음: $HERE — 막힘(조용한 통과 0)"; exit 1; }
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
  case "$base" in "$FEAT"|"origin/$FEAT"|"${FEAT#origin/}") return 1;; esac   # r1128: FEAT=origin/main 이면 선언 base «main» 도 같은 줄기
  if git -C "$w" rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 && git -C "$w" merge-base --is-ancestor "$sha" HEAD 2>/dev/null \
     && git -C "$w" merge-base --is-ancestor "$sha" "$base" 2>/dev/null; then  # ⒟ base_sha ⊂ 선언 base(정상 spawn 은 그때 tip) — 선언과 sha 의 계보 결합(DA r2)
    git -C "$w" merge-base --is-ancestor "$sha" "$FEAT" 2>/dev/null; rc=$?  # base_sha ⊂ FEAT 면 «다른 줄기» 근거 없음(옛 main 조상 오기 · DA Q1) — rc=1 만 «조상 아님»
    [ "$rc" = "0" ] && return 1
    [ "$rc" = "1" ] && { say "  ⊘" "다른 줄기($(basename "$w") · base=$base) — FEAT 랜딩 대상 아님 · ① 셈 제외"; return 0; }
  fi
  say "  ⚠" "base 선언 확인 실패($(basename "$w") · base=$base) — FEAT 기준으로 센다"; return 1
}
# ★r1076: press 카드의 «선언 제외»★ — 이 press 가 «시험하지 않는» 나노를 카드가 한 줄로 선언하면 ① 셈에서 뺀다(모순·꼴은 막는다).
#   꼴(정확히 이 꼴만): `- press 제외 나노: <워크트리 이름>[, <이름>…] — <사유 1글자 이상>` · 이름 = .worktrees/ 아래 폴더 이름 그대로
#   왜: 게이트는 «이 press 가 무엇을 시험하려는지» 모른다 — 선언이 없으면 지금처럼 막는다(09-17 사고 보존).
DECL=(); DECL_HIT=(); DECL_BAD=0
_decl_read(){ # 카드 → DECL(선언된 이름) · 꼴 틀림은 DECL_BAD=1
  local card="$1" line names n
  [ -n "$card" ] && [ -f "$card" ] || return 0     # 카드 미지정·파일 없음 = 선언 0(지금과 같다)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *"press 제외 나노"*) ;; *) continue ;; esac
    if [[ "$line" =~ ^-\ press\ 제외\ 나노:\ ([^—]+)\ —\ (.+)$ ]]; then
      names="${BASH_REMATCH[1]}"
    else
      say "✗" "press 제외 선언 꼴 틀림 — «- press 제외 나노: <이름>[, <이름>…] — <사유>» 만 읽는다: $line"; DECL_BAD=1; continue
    fi
    local IFS=','
    for n in $names; do
      n="${n#"${n%%[![:space:]]*}"}"; n="${n%"${n##*[![:space:]]}"}"
      case "$n" in
        ''|*[!A-Za-z0-9._-]*) say "✗" "press 제외 선언 꼴 틀림 — 이름 «${n}» 이 워크트리 폴더 이름 꼴이 아니다(이름은 쉼표로 구분): $line"; DECL_BAD=1 ;;
        *) DECL+=("$n") ;;
      esac
    done
  done < "$card"
}
_declared(){ local d; for d in ${DECL[@]+"${DECL[@]}"}; do [ "$d" = "$1" ] && return 0; done; return 1; }
_decl_hit(){ local d; for d in ${DECL_HIT[@]+"${DECL_HIT[@]}"}; do [ "$d" = "$1" ] && return 0; done; return 1; }
_decl_read "${FT_PRESS_CARD:-}"
[ "$DECL_BAD" = "0" ] || FAIL=1
# r1128: 기준 줄기를 못 풀면 셈이 빈 결과(= 0건 통과 꼴)가 된다 — 셀 나노가 있을 때 판정 불가로 막고 셈 0
FEAT_OK=1
if [ -n "$LIVE_WT" ] && ! git rev-parse --verify -q "$FEAT^{commit}" >/dev/null 2>&1; then
  say "✗" "① 판정 불가 — 기준 줄기 $FEAT 를 못 풂(FT_NANO_FEAT 확인)"; FAIL=1; FEAT_OK=0; LIVE_WT=""
fi
# ★r1201: 가지 단위 착지 판정★ — ft-merge-land 의 squash 는 PR 제목 + 끝줄 «PR #N (head X)» 만 남겨 아래 ⒜⒝⒞(커밋 단위)가 셋 다 거짓이다.
#   FEAT 최근 60커밋(FEAT_BODY 와 같은 범위)의 끝줄(문서 자동 병합 꼬리 «main 자동 병합(문서 전용 · 겹침 0) C=<40hex>» 1줄은 건너뜀)이
#   정확히 «PR #<수> (head <40hex>)» 인 X 를 모은다(ft-nano-close _lp_lastline_head 와 같은 꼴).
_hex40(){ [ "${#1}" -eq 40 ] && case "$1" in *[!0-9a-f]*) return 1;; esac; }
_squash_heads(){ # → «<FEAT 커밋>\t<X>\t<N>» 줄들
  local rec c l prev x n
  while IFS= read -r -d '' rec || [ -n "$rec" ]; do
    c="${rec%%$'\n'*}"; l=""; prev=""
    while IFS= read -r x; do x="${x%"${x##*[![:space:]]}"}"; [ -n "$x" ] && { prev="$l"; l="$x"; }; done <<< "${rec#*$'\n'}"
    case "$l" in "main 자동 병합(문서 전용 · 겹침 0) C="*) _hex40 "${l#*C=}" && l="$prev";; esac
    case "$l" in "PR #"*" (head "*")") ;; *) continue;; esac
    n="${l#PR #}"; n="${n%% (head *}"; x="${l##* (head }"; x="${x%)}"
    case "$n" in ''|*[!0-9]*) continue;; esac
    [ "$l" = "PR #$n (head $x)" ] && _hex40 "$x" && printf '%s\t%s\t%s\n' "$c" "$x" "$n"
  done < <(git log -z "$FEAT" --format='%H%n%B' -60 2>/dev/null)
}
_squash_landed(){ # 워크트리 → rc0 = 착지됨(⊘ 한 줄) · rc1 = 판정 안 함(X 없음·git 실패 = 지금처럼 커밋 단위로 센다)
  local w="$1" c x n nm
  while IFS=$'\t' read -r c x n; do
    git -C "$w" cat-file -e "$x^{commit}" 2>/dev/null || continue
    if git -C "$w" merge-base --is-ancestor HEAD "$x" 2>/dev/null; then :     # ⓐ 나노가 PR head 뒤에 머묾
    elif git -C "$w" merge-base --is-ancestor "$x" HEAD 2>/dev/null \
      && nm="$(git -C "$w" rev-list --no-merges "$x"..HEAD ^"$FEAT" 2>/dev/null)" && [ -z "$nm" ]; then :   # ⓑ X 뒤 병합 아닌 커밋이 전부 이미 FEAT 에 있음(main 병합만 · 미착지 옆 가지 병합은 센다)
    else continue; fi
    say "  ⊘" "착지됨($(basename "$w") · PR #$n squash ${c:0:10}) — ① 셈 제외"; return 0
  done <<< "$SQUASH_HEADS"
  return 1
}
SQUASH_HEADS=""; [ -n "$LIVE_WT" ] && SQUASH_HEADS="$(_squash_heads)"

for W in $LIVE_WT; do
  W="$ROOT/.worktrees/$W"
  [ -e "$W/.git" ] || continue
  _other_trunk "$W" && continue
  _squash_landed "$W" && continue
  # 제품 경로를 건드린 미랜딩만 센다(문서만이면 press 에 영향 0)
  # ★cherry-pick -x 로 이미 feat 에 올라간 것은 «미랜딩이 아니다»★ — 원본 sha 는 조상이 아니므로
  # 제목으로 대조한다(이 오탐 때문에 9건이 미랜딩으로 잡혔다).
  # ★테스트 파일은 실행 번들에 영향 0★ 이라 제품 경로에서 뺀다.
  # 랜딩 판정 셋 — 하나라도 맞으면 랜딩된 것으로 본다:
  #   ⒜같은 제목이 feat 에 있다(cherry-pick -x)
  #   ⒝feat 커밋 «본문»에 그 sha 가 인용돼 있다(통행증 규격으로 «재작성»해 올린 경우 — 실제로 있었다)
  #   ⒞sha 가 feat 의 조상이다
  P=0; IN_SET=0
  FEAT_SUBJ=$(git log "$FEAT" --format='%s' -400)
  FEAT_BODY=$(git log "$FEAT" --format='%H%n%B' -60)
  while IFS=$'\t' read -r h t; do
    [ -z "$h" ] && continue
    printf '%s\n' "$FEAT_SUBJ" | grep -qxF "$t" && continue
    printf '%s\n' "$FEAT_BODY" | grep -q "${h:0:9}" && continue
    git merge-base --is-ancestor "$h" "$FEAT" 2>/dev/null && continue
    P=$((P+1)); say "  ·" "미랜딩 후보: $t"
    # r1076 모순 검사 재료 — 이 미랜딩 커밋이 press 세트 HEAD 의 조상인가(이미 세트에 있으면 «제외» 가 아니라 «모순»)
    #   ★${h:0:40}★ 위 로그 꼴의 %t 는 «탭» 이 아니라 «축약 tree 해시»(git 이 7자를 붙인다) — 40자만 쓰면 sha 다(기존 ① 판정은 손대지 않는다).
    git merge-base --is-ancestor "${h:0:40}" HEAD 2>/dev/null && IN_SET=$((IN_SET+1))
  done < <(git -C "$W" log --format='%H%t%s' "$FEAT"..HEAD -- worker shared gateway clients ':(exclude)*__tests__*' ':(exclude)tests/*' 2>/dev/null | sed 's/\(^[0-9a-f]*\)/\1\t/' )
  if [ "${P:-0}" != "0" ]; then
    if _declared "$(basename "$W")"; then
      DECL_HIT+=("$(basename "$W")")
      if [ "$IN_SET" != "0" ]; then
        say "✗" "선언 모순 — $(basename "$W") 의 커밋이 이미 세트에 있다(미랜딩 $P)"; UNLANDED=$((UNLANDED+P))
      else
        say "⊘" "선언 제외($(basename "$W")) — 이 press 는 이 수정을 시험하지 않는다(카드: ${FT_PRESS_CARD:-}) · 미랜딩 $P"
      fi
    else
      say "✗" "미랜딩 제품 커밋 $P — $(basename "$W")"; UNLANDED=$((UNLANDED+P))
    fi
  fi
  [ "${#SETP[@]}" != "0" ] && _set_member "$W"
done
for _d in ${DECL[@]+"${DECL[@]}"}; do   # r1076 R6: 선언했는데 ✗ 워크트리에 없으면 경고만(rc 영향 0)
  _decl_hit "$_d" || say "⚠" "선언 이름 없음: $_d"
done
[ "$FEAT_OK" = "1" ] && { [ "$UNLANDED" = "0" ] && say "✓" "미랜딩 제품 커밋 0" || FAIL=1; }

# r769: 로컬 갈래 포트 해석 «1곳» — 팀이 선언한 슬롯을 따르고, 선언이 없으면 지금과 똑같다(조용한 바뀜 0).
#   FT_PRESS_PORTS("gw,worker,fe") > FT_PRESS_PORT_BASE(+0/+1/+2) > 기본 8080·8081·3001
#   ★일반 FT_PORT_BASE 는 «읽지 않는다»★ — 팀 env(lecture-env.sh 등)가 이미 export 하고 있어서, 그걸 읽으면
#   press 갈래가 팀 잡일 env 에 끌려간다(lecture 는 기본 포트 서버로 press 해 왔다 — 그 동작 그대로).
#   기본이 아닌 갈래는 로그·SSE 주소도 «같이» 선언해야 한다 — 반쪽 선언은 엉뚱한 서버를 통과시킨다.
GW_PORT=8080; WK_PORT=8081; FE_PORT=3001
WORKER_LOG=/tmp/byz-worker.log
SSE_HEALTH_URL=https://localhost:8443/api/v1/health/
SSE_LABEL="Caddy 8443"
_ports(){ # rc 0 = 해석 끝(GW_PORT·WK_PORT·FE_PORT·WORKER_LOG·SSE_HEALTH_URL 확정) · rc 1 = 막힘
  local gw wk fe p
  if [ -n "${FT_PRESS_PORTS:-}" ]; then
    IFS=, read -r gw wk fe p <<<"$FT_PRESS_PORTS"
    [ -z "$p" ] && [ -n "$gw" ] && [ -n "$wk" ] && [ -n "$fe" ] \
      || { say "✗" "FT_PRESS_PORTS 는 «gw,worker,fe» 3칸이어야 한다(지금: $FT_PRESS_PORTS)"; return 1; }
    for p in "$gw" "$wk" "$fe"; do
      _int_port "$p" || { say "✗" "FT_PRESS_PORTS 포트가 숫자 1024~65535 가 아니다: $p"; return 1; }
    done
    GW_PORT=$gw; WK_PORT=$wk; FE_PORT=$fe
    printf '포트 갈래: FT_PRESS_PORTS=%s → gateway %s · worker %s · 화면 %s\n' "$FT_PRESS_PORTS" "$gw" "$wk" "$fe"
  elif [ -n "${FT_PRESS_PORT_BASE:-}" ]; then
    _int_port "$FT_PRESS_PORT_BASE" || { say "✗" "FT_PRESS_PORT_BASE 가 숫자 1024~65535 가 아니다: $FT_PRESS_PORT_BASE"; return 1; }
    GW_PORT=$FT_PRESS_PORT_BASE; WK_PORT=$((10#$FT_PRESS_PORT_BASE + 1)); FE_PORT=$((10#$FT_PRESS_PORT_BASE + 2))
    for p in "$WK_PORT" "$FE_PORT"; do
      _int_port "$p" || { say "✗" "FT_PRESS_PORT_BASE=$FT_PRESS_PORT_BASE 에서 나온 포트가 1024~65535 밖이다: $p"; return 1; }
    done
    printf '포트 갈래: FT_PRESS_PORT_BASE=%s → gateway %s · worker %s · 화면 %s\n' "$FT_PRESS_PORT_BASE" "$GW_PORT" "$WK_PORT" "$FE_PORT"
  else
    printf '포트 갈래: 기본\n'
    return 0
  fi
  if [ -z "${FT_PRESS_WORKER_LOG:-}" ] || [ -z "${FT_PRESS_SSE_HEALTH_URL:-}" ]; then
    say "✗" "슬롯 선언 회차는 worker 로그·SSE health 주소도 지정 — FT_PRESS_WORKER_LOG · FT_PRESS_SSE_HEALTH_URL 둘 다 필요(지금: log=${FT_PRESS_WORKER_LOG:-없음} sse=${FT_PRESS_SSE_HEALTH_URL:-없음})"
    return 1
  fi
  return 0
}

# r634: ②~⑤ 는 로컬 스택 전제 — dev 로 선언한 회차만 dev 칸으로 바꾼다(로컬 갈래는 문자 그대로)
if [ "$TARGET" = "dev" ]; then
  _dev_gate
else
_ports || { echo; echo "PRESS-GATE BLOCK — 위 ✗ 를 먼저 닫아라(랜딩 → stop→run → 화면도 같이)"; exit 1; }
[ -n "${FT_PRESS_WORKER_LOG:-}" ] && { WORKER_LOG=$FT_PRESS_WORKER_LOG; }
[ -n "${FT_PRESS_SSE_HEALTH_URL:-}" ] && { SSE_HEALTH_URL=$FT_PRESS_SSE_HEALTH_URL; SSE_LABEL=$FT_PRESS_SSE_HEALTH_URL; }
true
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
chk worker "$WK_PORT" worker shared
chk gateway "$GW_PORT" gateway shared
chk 화면 "$FE_PORT" clients/web ":(exclude)clients/web/__tests__/*"

# ③ 활성화 lane + health
grep -q 'activation bundle established' "$WORKER_LOG" \
  && say "✓" "[C2c-ACT] activation bundle established" \
  || { say "✗" "활성화 번들 줄 없음 — legacy lane 의심"; FAIL=1; }
code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' "http://localhost:$WK_PORT/health" 2>/dev/null)
[ "$code" = "200" ] && say "✓" "worker health 200" || { say "✗" "worker health=$code"; FAIL=1; }
# FE SSE 는 Caddy :8443 경유(run.command NEXT_PUBLIC_SSE_URL) — 죽으면 press 무효(2026-10-01 m7-rt-ledger 2회 · /health 는 307 이라 api 경로)
code2=$(curl -sk -m 4 -o /dev/null -w '%{http_code}' "$SSE_HEALTH_URL" 2>/dev/null)
[ "$code2" = "200" ] && say "✓" "$SSE_LABEL health 200" || { say "✗" "$SSE_LABEL health=$code2 — 리스너 없으면 run.command 로 기동"; FAIL=1; }
# HTTP 200 이어도 본문 consumer_ready=false 면 PTT disabled — press 가 no_viable_target 으로 무효(2026-09-26 long3m-002)
cr=$(curl -s -m 4 "http://localhost:$WK_PORT/health" 2>/dev/null | python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("unparsed"); sys.exit()
print("ok" if d.get("consumer_ready") is True else "status=%s consumer_ready=%s" % (d.get("status"), d.get("consumer_ready")))' 2>/dev/null)
[ "$cr" = "ok" ] && say "✓" "worker consumer_ready=true" || { say "✗" "worker ${cr:-unparsed} — LOOM DSN·언어 웜업 먼저(troubleshoot 20260926-local-worker)"; FAIL=1; }
# 재기동 직후 LOOM selfhost 프리워밍(전 튜플 실 LLM 호출 · ≈3 분)이 press 와 겹치면 vLLM 프리필 포화 → 번역 7 s 타임아웃 → 봉인 실패
# (2026-10-02 10:12 K5 p1 무효 · 타임아웃 30건). 이번 기동의 «Warming up» 줄 «뒤»에 prewarm SUMMARY 가 있어야 한다.
boot_ln=$(grep -n 'Worker Starting - Warming up services' "$WORKER_LOG" 2>/dev/null | tail -1 | cut -d: -f1)
sum_ln=$(grep -n 'selfhost prewarm SUMMARY' "$WORKER_LOG" 2>/dev/null | tail -1 | cut -d: -f1)
# SUMMARY 줄 «존재»만으로 통과시키지 않는다 — FAILED>0 이면 vLLM 이 그 순간 포화였다는 뜻(2026-10-02 20:22 K4 p1 무효 · 22 ok/14 FAILED 를 PASS).
sum_txt=$([ -n "$sum_ln" ] && sed -n "${sum_ln}p" "$WORKER_LOG" | grep -oE 'SUMMARY: [0-9]+ ok / [0-9]+ FAILED')
sum_failed=$(printf '%s' "$sum_txt" | grep -oE '[0-9]+ FAILED' | grep -oE '[0-9]+')
if [ -n "$boot_ln" ] && [ -n "$sum_ln" ] && [ "$sum_ln" -gt "$boot_ln" ] && [ "${sum_failed:-1}" -gt 0 ]; then
  say "✗" "LOOM prewarm SUMMARY FAILED>0 ($sum_txt) — 공유 vLLM 포화 의심(다른 트랙 worker 기동·측정) → 원인 정리 뒤 worker 재기동"; FAIL=1
elif [ -n "$boot_ln" ] && [ -n "$sum_ln" ] && [ "$sum_ln" -gt "$boot_ln" ]; then
  say "✓" "LOOM prewarm SUMMARY 가 이번 기동 뒤에 있음($sum_txt)"
else
  say "✗" "LOOM selfhost 프리워밍 진행 중/미완 — SUMMARY 줄이 뜬 뒤 발사(겹치면 번역 타임아웃으로 회차 무효)"; FAIL=1
fi

# ④ 워커 필수 env(WORKER_ENV_SPEC 키 이름만 대조 · 값 복제 0)
wpid=$(lsof -ti:"$WK_PORT" -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$wpid" ]; then
  miss=0
  while read -r k; do
    ps eww "$wpid" 2>/dev/null | tr ' ' '\n' | grep -q "^${k}=" || { say "✗" "env 없음: $k"; miss=$((miss+1)); }
  done < <(sed -n '/^WORKER_ENV_SPEC=(/,/^)/p' scripts/server/ready-check.sh | grep -oE '"[A-Z0-9_]+=' | tr -d '"=')
  [ "$miss" = "0" ] && say "✓" "필수 env 전부 실림" || FAIL=1
fi

# ④-b 화면 env(r1196) — poller 화면 축(data-dbg-*)은 FE 를 NEXT_PUBLIC_BUBBLE_DEBUG=true 로 띄워야 붙는다(#8 RULE)
#   읽기 = ready-check.sh FE 세대 env 와 같다: FE 리스너의 «부모» pid env · 값 true 만 통과
fpid=$(lsof -ti:"$FE_PORT" -sTCP:LISTEN 2>/dev/null | head -1)
fppid=$([ -n "$fpid" ] && ps -o ppid= -p "$fpid" 2>/dev/null | tr -d ' ')
if [ -z "$fppid" ]; then
  say "✗" "④-b 화면 env 판정 불가 — FE 리스너(:$FE_PORT) 부모 env 못 읽음"; FAIL=1
elif ps eww "$fppid" 2>/dev/null | tr ' ' '\n' | grep -qx 'NEXT_PUBLIC_BUBBLE_DEBUG=true'; then
  say "✓" "④-b 화면 env NEXT_PUBLIC_BUBBLE_DEBUG=true"
else
  say "✗" "④-b 화면 env NEXT_PUBLIC_BUBBLE_DEBUG=true 없음 — poller 화면 축 0(#8 RULE) · FE 를 NEXT_PUBLIC_BUBBLE_DEBUG=true bash scripts/client/web/run.command 로 다시 띄운다"; FAIL=1
fi

# ⑤ 세트 축(M7 · single_set_testing §1 규칙 1) — 러너 파일 워크트리 HEAD == worker·gateway pid cwd 워크트리 HEAD · 세트 경로 dirty 0. 정의 본체는 ft-press-set-check.sh.
_cwd_of(){ lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1; }
# 기동 stamp = 서비스 pid 프로세스 시작시각(epoch) — set-check 가 «워크트리 HEAD 가 기동 뒤 움직였나» 를 가른다(A4). 못 구하면 빈 값 → set-check 가 REJECT.
_start_of(){ LC_ALL=C date -j -f '%a %b %e %T %Y' "$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null)" +%s 2>/dev/null; }
gpid=$(lsof -ti:"$GW_PORT" -sTCP:LISTEN 2>/dev/null | head -1)
if [ -z "${wpid:-}" ] || [ -z "$gpid" ]; then
  say "✗" "세트 축 — worker(:$WK_PORT)·gateway(:$GW_PORT) 리스너 pid 없음"; FAIL=1
else
  wcwd=$(_cwd_of "$wpid"); gcwd=$(_cwd_of "$gpid")
  if [ -z "$wcwd" ] || [ -z "$gcwd" ]; then say "✗" "세트 축 — pid cwd 조회 실패(worker=$wpid gateway=$gpid)"; FAIL=1
  else
    "$(dirname "$0")/ft-press-set-check.sh" --runner "$WT/tests/e2e/realtime_multi_e2e.py" --worker-cwd "$wcwd" --gateway-cwd "$gcwd" \
      --worker-start "$(_start_of "$wpid")" --gateway-start "$(_start_of "$gpid")" || FAIL=1
  fi
fi
fi   # r634: TARGET=local 갈래 끝(dev 면 _dev_gate 만)

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
