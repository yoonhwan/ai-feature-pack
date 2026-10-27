#!/usr/bin/env bash
# test_press_gate_dev_target_r634.sh — r634: press 게이트 «dev 대상» 갈래.
#   FT_PRESS_TARGET=dev 를 «선언한» 회차만 ②~⑤(로컬 스택) 대신 dev 칸(web·gateway health 200 + 세 서비스 이미지 sha ⊇ WANT)을 본다.
#   가짜 tmux·curl·gcloud 만 · 실제 dev·Cloud Run·리스너·오디오 0 · 리포 파일 쓰기 0.
#   ★칸마다 «새 임시 루트»(r634 DA⑥ r1 H5①) — 앞 칸의 허가 파일·BTS 골격이 다음 칸을 GREEN 으로 만들지 않는다.
#   ★전 케이스 «게이트 최종 exit» 단언: 통과 0 · 막힘 1★
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${R634_SUT:-$HERE/../../harness/bin/ft-press-gate.sh}"   # base 판·변이 사본을 물릴 수 있다
SUT="$GATE"
fail=0; n=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"

REAL_BEFORE="$(git -C "$HERE/../.." status --porcelain)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
SVC_WEB=byz-agents-web-dev; SVC_GW=byz-agents-gateway-dev; SVC_WK=byz-agents-worker-dev
EXP_WEB=https://byz-agents-web-dev-a3yix5apcq-du.a.run.app      # 게이트 기본값과 «같은» 주소여야 한다
EXP_GW=https://byz-agents-gateway-dev-a3yix5apcq-du.a.run.app
GBIN="$T/stub"; mkdir -p "$GBIN"

# ── 스텁 3종(엄격 · r634 H5②: 모르는 URL = 404 · gcloud 정확 인자만)
cat > "$GBIN/tmux" <<'TMUX'
#!/bin/sh
case "$1" in
  display-message) [ -n "${FAKE_TMUX_SESSION:-}" ] || exit 1; echo "$FAKE_TMUX_SESSION" ;;
  list-sessions) exit 0 ;;   # 살아 있는 세션 0개(성공) — r655 판정기(ft_teamset.py wt-v65)는 목록 «실패» 를 ① 막힘으로 본다
esac
TMUX
cat > "$GBIN/curl" <<'CURL'
#!/bin/sh
url=""; of=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) of=$2; shift 2 ;;
    -m|-w) shift 2 ;;
    -s|-k) shift ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
[ "${FAKE_SLOW_HEALTH:-0}" = "1" ] && { trap '' TERM; sleep 30; }   # TERM 무시하는 느린 응답
case "$url" in
  # r685: 기본 본문 = 서비스별 «정상 모습»(web = 앱 HTML · gateway = status ok JSON) · 빈 값을 주면 빈 본문(«-» = 미설정만 기본값)
  #       기본값을 변수로 뺀다 — ${X-{…}} 꼴은 첫 «}» 에서 끝나 준 본문 뒤에 «}» 가 붙는다(r634 판 함정)
  "${EXP_WEB}/") dw='<!DOCTYPE html><html lang="ko"><head><title>하우투 톡 — 실시간 AI 음성 통역</title><script src="/_next/static/chunks/main.js"></script></head><body><main>하우투 톡 실시간 AI 통역 — 병원 진료 설명도 바로 통역합니다</main></body></html>'
    body="${FAKE_BODY_WEB-$dw}"; code="${FAKE_CURL_WEB:-200}" ;;
  "${EXP_GATEWAY}/api/v1/health/") dg='{"status":"ok","consumer_ready":true}'
    body="${FAKE_BODY_GW-$dg}"; code="${FAKE_CURL_GW:-200}" ;;
  *) body="not found"; code=404 ;;   # 모르는 URL 은 성공하지 않는다(과다 성공 제거)
esac
[ -n "$of" ] && printf '%s' "$body" > "$of"
printf '%s' "$code"
exit "${FAKE_CURL_RC:-0}"
CURL
cat > "$GBIN/gcloud" <<'GCLOUD'
#!/bin/sh
# 정확 인자만: run services describe <svc> --region=<R> --format=value(spec.template.spec.containers[0].image)
[ "${FAKE_SLOW:-0}" = "1" ] && { trap '' TERM; sleep 30; }
[ "${FAKE_SLOW_SVC:-}" = "$4" ] && { trap '' TERM; sleep 30; }
[ "$1" = run ] && [ "$2" = services ] && [ "$3" = describe ] || exit 2
case "$5" in --region=*) ;; *) exit 2 ;; esac
case "$*" in *"--format=value(spec.template.spec.containers[0].image)"*) ;; *) exit 2 ;; esac
case "$4" in
  "$SVC_WEB") printf 'r/web:%s\n' "${FAKE_IMG_WEB:-}" ;;
  "$SVC_GW")  printf 'r/gateway:%s\n' "${FAKE_IMG_GATEWAY:-}" ;;
  "$SVC_WK")  printf 'r/worker:%s\n' "${FAKE_IMG_WORKER:-}" ;;
  *) exit 1 ;;
esac
exit "${FAKE_GCLOUD_RC:-0}"   # r634 H2①: 출력이 유효해도 종료코드가 0 이 아니면 채택 금지
GCLOUD
cat > "$GBIN/sysctl" <<'SYSCTL'
#!/bin/sh
printf '{ 0.50 0.50 0.50 }\n'   # r769b: 부하 게이트 — 호스트 부하와 무관하게(이 시험은 포트 갈래만 본다)
SYSCTL
cat > "$GBIN/lsof" <<'LSOF'
#!/bin/sh
exit 1   # 리스너 0 — 시험이 이 머신의 실제 :8080·:8081·:3001 에 좌우되지 않게(hermetic)
LSOF
# r685 DA⑥ H2·H3: 본문 판별 python 만 느리게/실패시키는 감싸개(그 밖의 python3 호출은 진짜로 넘긴다 · 표식 = 판별 스크립트 안 «r685-dev-body»)
REALPY="$(command -v python3)"
cat > "$GBIN/python3" <<PYW
#!/bin/sh
case "\$*" in *r685-dev-body*)
  [ "\${FAKE_PY:-}" = slow ] && { trap '' TERM; sleep 30; exit 0; }
  [ "\${FAKE_PY:-}" = fail ] && exit 1 ;;
esac
exec "$REALPY" "\$@"
PYW
chmod +x "$GBIN"/*
grep -q FAKE_IMG_WORKER "$GBIN/gcloud" && grep -q 'not found' "$GBIN/curl" && [ -x "$GBIN/lsof" ] && ok "가짜 tmux·curl·gcloud·lsof 스텁 설치(엄격)" || bad "스텁 생성 실패"

# ── 칸마다 새 루트(리포·허가·전팀정지 원장·명부) — 이전 칸의 상태가 새지 않는다
mkroot(){ # $1 이름 → CASE · $SHA · $SIDE · $SHA_PREV
  CASE="$T/case-$1"; rm -rf "$CASE"; R="$CASE/repo"
  mkdir -p "$R/worker" "$R/design/v65/baselines/ev" "$CASE/root/.fable-team/state" "$CASE/permits" "$CASE/fakebin"
  cp "$GBIN"/* "$CASE/fakebin"/
  printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$CASE/root/.fable-team/state/all-stop.log"   # r626: 원장 없음 = 전팀 정지
  echo '{}' > "$CASE/root/.fable-team/seats.json"
  git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  echo 'x = 1' > "$R/worker/a.py"
  printf '| key | 기본값 | OFF 값 | 읽는 자리 |\n|---|---|---|---|\n| `V65_TOGGLE_A` | `1` | `0` | worker/a.py:1 |\n' > "$R/design/v65/baselines/FLAGS.md"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
  git -C "$R" add -A && git -C "$R" commit -qm base
  SHA="$(git -C "$R" rev-parse HEAD)"
  printf '{"set_sha":"%s","side_lang_at_press":{"right":"ko","left":"en"},"session_id":"run-1","failed":true}\n' "$SHA" > "$R/design/v65/baselines/ev/RESULT-ok.json"
  { echo "set_sha: $SHA"; echo "control: lane=c2c-dev stt_provider=gpu side_lang=right:ko,left:en click=PRESS_SIDE_LANG_CLICK:1 flags=V65_TOGGLE_A=1"
    echo "side_lang: right=ko left=en"; echo "server_ready: 2026-10-07T03:00:00Z"; echo "visible_at_settle: yes"
    echo "evidence: design/v65/baselines/ev/RESULT-ok.json"; echo "run_id: run-1"; printf '\n| 칸 | 값 |\n|---|---|\n| 빈 칸 | 0 |\n'; } > "$R/design/v65/baselines/ok.md"
  printf '# 카드 c-ok\n기준선: design/v65/baselines/ok.md\n실험: 없음\n' > "$R/card.md"
  git -C "$R" add -A && git -C "$R" commit -qm card   # 카드도 base 줄기에 — side 로 checkout 해도 남는다
  SHA="$(git -C "$R" rev-parse HEAD)"; SHA_PREV="$(git -C "$R" rev-parse HEAD~1)"
  SIDE="$(git -C "$R" commit-tree "$(git -C "$R" rev-parse 'HEAD^{tree}')" -m foreign)"   # 줄기 밖 커밋 = SHA 미포함
}
# dev 선언 회차의 «정상» env 묶음 — 이번 칸의 SHA 로
dev_env(){ DEV=(FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT="$SHA" BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW"
  FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"); }
gate(){ # [env…] → 최종 exit · 출력 $OUT
  OUT="$(env -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u BYZ_PRESS_HUMAN \
    -u FT_PRESS_TARGET -u FT_PRESS_DEV_WANT -u FT_PRESS_DEV_SVCS -u FT_PRESS_DEV_BUDGET -u BYZ_WEB_BASE -u BYZ_GATEWAY_BASE \
    -u FAKE_SLOW -u FAKE_SLOW_SVC -u FAKE_SLOW_HEALTH -u FAKE_GCLOUD_RC -u FAKE_CURL_RC -u FAKE_CURL_WEB -u FAKE_CURL_GW \
    -u FAKE_BODY_WEB -u FAKE_BODY_GW -u FT_PRESS_DEV_WEB_MARK -u FAKE_PY -u FAKE_IMG_WEB -u FAKE_IMG_GATEWAY -u FAKE_IMG_WORKER \
    FT_PRESS_WT="$R" FT_PRESS_ROOT="$CASE/root" FT_PRESS_CARD="$R/card.md" FT_PRESS_PERMIT_DIR="$CASE/permits" \
    FT_PRESS_EVID="$CASE/ev" TMUX_PANE=%1 FAKE_TMUX_SESSION='byz-v65-tester-claude#0' \
    SVC_WEB="$SVC_WEB" SVC_GW="$SVC_GW" SVC_WK="$SVC_WK" EXP_WEB="$EXP_WEB" EXP_GATEWAY="$EXP_GW" \
    PATH="${CASE_PATH:-$CASE/fakebin:$PATH}" "$@" bash "$SUT" 2>&1)"; }
expect(){ # 기대exit 패턴 설명 [env…]
  local want="$1" pat="$2" desc="$3"; shift 3; n=$((n+1)); gate "$@"; local got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$OUT" | grep -q -- "$pat"; then ok "$n. $desc (exit $got)"
  else bad "$n. $desc (exit $got want $want · pat=$pat)"; printf '%s\n' "$OUT" | sed 's/^/    /'; fi
}
expectnot(){ # 기대exit «없어야 할» 패턴 설명 [env…]
  local want="$1" npat="$2" desc="$3"; shift 3; n=$((n+1)); gate "$@"; local got=$?
  if [ "$got" -eq "$want" ] && ! printf '%s' "$OUT" | grep -q -- "$npat"; then ok "$n. $desc (exit $got)"
  else bad "$n. $desc (exit $got want $want · 없어야=$npat)"; printf '%s\n' "$OUT" | sed 's/^/    /'; fi
}

# ══ ⓐ dev 선언 + 로컬 리스너 0 + web·gateway 200 + 세 이미지 ⊇ WANT → 통과
mkroot a; dev_env
n=$((n+1)); gate "${DEV[@]}"; got=$?
[ "$got" -eq 0 ] && printf '%s' "$OUT" | grep -q 'dev 대상 — 로컬 칸 ②~⑤ 대신' \
  && printf '%s' "$OUT" | grep -q 'dev 러너 대상 일치' \
  && printf '%s' "$OUT" | grep -q 'dev web health 200' && printf '%s' "$OUT" | grep -q 'dev gateway health 200' \
  && printf '%s' "$OUT" | grep -q 'dev 이미지 worker ⊇' && ! printf '%s' "$OUT" | grep -q '리스너 없음' \
  && printf '%s' "$OUT" | grep -q 'PRESS-GATE PASS' \
  && ok "$n. ⓐ dev 선언 + 로컬 리스너 0 + web·gateway 200 + 세 이미지 ⊇ WANT → 통과 (exit $got)" \
  || { bad "$n. ⓐ dev 통과 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
n=$((n+1)); pf="$CASE/permits/byz-v65-tester-claude#0.json"
[ -f "$pf" ] && [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["target"])' "$pf" 2>/dev/null)" = dev ] \
  && [ "$(awk -F'\t' 'END{print NF"="$NF}' "$CASE/permits/permits.log")" = "6=dev" ] \
  && printf '%s' "$OUT" | grep -q '⑥ 기준선' && printf '%s' "$OUT" | grep -q '⑦ 역할 tester' \
  && ok "$n. ⓐ 허가 파일 target=dev(json) · permits.log 끝칸 dev · ⑥⑦⑧ 그대로 판정" \
  || { bad "$n. ⓐ 허가 target 칸"; cat "$pf" 2>/dev/null; cat "$CASE/permits/permits.log" 2>/dev/null; }

# ══ ⓑ~ⓗ 부정 칸
mkroot b; dev_env
expect 1 'dev gateway health=503' "ⓑ dev gateway 503 → 막힘" "${DEV[@]}" FAKE_CURL_GW=503
mkroot c; dev_env
expect 1 "byz-agents-worker-dev 이미지 ${SIDE:0:10} 에 ${SHA:0:10} 없음" "ⓒ worker 이미지에 WANT 없음 → 막힘" "${DEV[@]}" FAKE_IMG_WORKER="$SIDE"
mkroot d1; dev_env
expect 1 'dev worker 이미지 sha 못 읽음' "ⓓ1 이미지 못 읽음(빈 값) → 막힘" "${DEV[@]}" FAKE_IMG_WORKER=""
mkroot d2; dev_env
expect 1 'dev gateway 이미지 sha 못 읽음' "ⓓ2 이미지 형식 불명(:latest) → 막힘" "${DEV[@]}" FAKE_IMG_GATEWAY='r/gateway:latest'
mkroot d3; dev_env
expect 1 'dev web 이미지 sha 못 읽음' "ⓓ3 이미지 태그 39자(축약 sha) → 막힘" "${DEV[@]}" FAKE_IMG_WEB="${SHA:1}"
mkroot e
expect 1 '원하는 커밋 미지정' "ⓔ FT_PRESS_DEV_WANT 없음 → 막힘" FT_PRESS_TARGET=dev BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" \
  FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
mkroot f
expect 1 'FT_PRESS_TARGET=prod — 대상은 local(기본)·dev 만' "ⓕ 대상=prod → 막힘" FT_PRESS_TARGET=prod
mkroot g
expect 1 '리스너 없음(:8081)' "ⓖ 선언 없음 → 로컬 칸 그대로(막힘)" FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
expectnot 1 'dev 대상 — 로컬 칸' "ⓖ 선언 없음 → dev 갈래 출력 0" FAKE_CURL_WEB=200

# ══ ⓗ dev 선언이어도 ⑥⑦⑧ 은 그대로 막는다
mkroot h1; dev_env
n=$((n+1)); OUT="$(env -u FT_PRESS_GATE_SELFTEST -u FT_PRESS_SEAT -u FT_PRESS_TARGET -u FT_PRESS_DEV_WANT \
  FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT="$SHA" BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" \
  FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA" \
  FT_PRESS_WT="$R" FT_PRESS_ROOT="$CASE/root" FT_PRESS_PERMIT_DIR="$CASE/permits" FT_PRESS_EVID="$CASE/ev" \
  TMUX_PANE=%1 FAKE_TMUX_SESSION='byz-v65-tester-claude#0' \
  SVC_WEB="$SVC_WEB" SVC_GW="$SVC_GW" SVC_WK="$SVC_WK" EXP_WEB="$EXP_WEB" EXP_GATEWAY="$EXP_GW" \
  PATH="$CASE/fakebin:$PATH" bash "$SUT" 2>&1)"; got=$?
[ "$got" -eq 1 ] && printf '%s' "$OUT" | grep -q '⑥ 카드 미지정' && printf '%s' "$OUT" | grep -q 'dev web health 200' \
  && ok "$n. ⓗ1 dev 선언 + ⑥ 카드 미지정 → 막힘(dev 칸 통과했는데 ⑥ 이 막는다) (exit $got)" \
  || { bad "$n. ⓗ1 ⑥ 카드 미지정 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
mkroot h2; dev_env
expect 1 '⑦ 역할 nano — press 는 tester·checker 만' "ⓗ2 dev 선언이어도 ⑦ 역할 nano → 막힘" "${DEV[@]}" FAKE_TMUX_SESSION='byz-harness-nano-x#0'
mkroot h3; dev_env
mkdir -p "$CASE/prev3"
printf '| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 |  |  |\n| 코드 |  |  |\n| 로그 |  |  |\n| 화면 |  |  |\n' > "$CASE/prev3/BTS.md"
printf '{"seat":"byz-v65-tester-claude#0","role":"tester","evid":"%s"}\n' "$CASE/prev3" > "$CASE/permits/byz-v65-tester-claude#0.json"
expect 1 '⑧ 직전 회차 BTS 표 미완' "ⓗ3 dev 선언이어도 ⑧ 직전 BTS 빈칸 → 막힘" "${DEV[@]}" FT_PRESS_EVID="$CASE/ev-h3"
mkroot h4; dev_env
mkdir -p "$CASE/prev" && printf '| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 | a | 1 |\n| 코드 | b | 2 |\n| 로그 | c | 3 |\n| 화면 |  |  |\n' > "$CASE/prev/BTS.md"
printf '{"seat":"byz-v65-tester-claude#0","role":"tester","evid":"%s"}\n' "$CASE/prev" > "$CASE/permits/byz-v65-tester-claude#0.json"   # 옛 꼴(target 칸 없음)
expect 1 '모자란 칸: 화면' "ⓗ4 옛 허가(target 칸 없음)도 ⑧ 이 읽는다(하위 호환)" "${DEV[@]}"

# ══ ⓘ H1 러너 대상 ↔ 게이트 대상 결합(dev 선언만 하고 러너는 localhost 로 쏘는 길)
mkroot i1; dev_env
expect 1 'BYZ_WEB_BASE 이 비었다' "ⓘ1 러너 env BYZ_WEB_BASE 없음 → 막힘" "${DEV[@]}" BYZ_WEB_BASE=
mkroot i2; dev_env
expect 1 'BYZ_GATEWAY_BASE=http://localhost:8080 ≠' "ⓘ2 러너가 localhost 로 쏘면 → 막힘" "${DEV[@]}" BYZ_GATEWAY_BASE=http://localhost:8080

# ══ ⓙ H2 sha 판정(종료코드·40자·WANT 출처)
mkroot j1; dev_env
expect 1 'dev web 이미지 sha 못 읽음' "ⓙ1 gcloud rc≠0 + 유효 태그 출력 → 막힘(종료코드 유실 금지)" "${DEV[@]}" FAKE_GCLOUD_RC=1
mkroot j2
expect 1 'FT_PRESS_DEV_WANT=main — 40자 hex' "ⓙ2 WANT=가지 이름 → 막힘" FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT=main \
  BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
mkroot j3
expect 1 'FT_PRESS_DEV_WANT=HEAD~1 — 40자 hex' "ⓙ3 WANT=HEAD~1 → 막힘" FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT=HEAD~1 \
  BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" FAKE_IMG_WEB="$SHA" FAKE_IMG_GATEWAY="$SHA" FAKE_IMG_WORKER="$SHA"
mkroot j4; dev_env
expect 1 '≠ press 워크트리 HEAD' "ⓙ4 WANT=오래된 조상(≠HEAD) → 막힘" FT_PRESS_TARGET=dev FT_PRESS_DEV_WANT="$SHA_PREV" \
  BYZ_WEB_BASE="$EXP_WEB" BYZ_GATEWAY_BASE="$EXP_GW" FAKE_IMG_WEB="$SHA_PREV" FAKE_IMG_GATEWAY="$SHA_PREV" FAKE_IMG_WORKER="$SHA_PREV"

# ══ ⓚ H3 세 서비스 필수 · health 본문
mkroot k1; dev_env
expect 1 'FT_PRESS_DEV_SVCS 에 worker 가 없다' "ⓚ1 SVCS 에 web·gateway 만 → 막힘" "${DEV[@]}" FT_PRESS_DEV_SVCS=web="$SVC_WEB",gateway="$SVC_GW"
mkroot k2; dev_env
expect 1 'FT_PRESS_DEV_SVCS 에 web 가 없다' "ⓚ2 SVCS 빈 값(루프 0회 통과 0) → 막힘" "${DEV[@]}" FT_PRESS_DEV_SVCS=' '
mkroot k3; dev_env
expect 1 'FT_PRESS_DEV_SVCS 중복: web' "ⓚ3 SVCS 중복 → 막힘" "${DEV[@]}" FT_PRESS_DEV_SVCS=web="$SVC_WEB",web="$SVC_WEB",gateway="$SVC_GW",worker="$SVC_WK"
mkroot k4; dev_env
expect 1 'dev gateway health 200 이지만 본문이 status=ok JSON 객체가 아니다' "ⓚ4 gateway 200 이지만 HTML 오류 페이지 → 막힘(r685: JSON 판별)" "${DEV[@]}" FAKE_BODY_GW='<!DOCTYPE html><html><body>error</body></html>'

# ══ ⓝ r685 서비스별 본문 판별 — web = 앱 표지 ∧ 오류 표지 없음 · gateway = status ok JSON 객체
APP_HTML='<!DOCTYPE html><html lang="ko"><head><title>하우투 톡 — 실시간 AI 음성 통역</title><script src="/_next/static/chunks/main.js"></script></head><body><main>하우투 톡 실시간 AI 통역 — 병원 진료 설명도 바로 통역합니다</main></body></html>'
err_page(){ # 오류 문구 → 앱 표지(제목·/_next/static/·</html>·보이는 글자)를 «다 갖춘» 오류 화면 — 표지가 있어도 오류 문구로 막혀야 한다
  printf '<!DOCTYPE html><html><head><title>하우투 톡</title><script src="/_next/static/x.js"></script></head><body><h1>%s</h1><p>잠시 후 다시 시도해 주세요 — 하우투 톡 실시간 통역</p></body></html>' "$1"; }
mkroot n1; dev_env
expect 0 'dev web health 200 —' "ⓝ1 web 200 + 정상 앱 HTML(<title>하우투 톡 · /_next/static/ · </html>) → 통과" "${DEV[@]}" FAKE_BODY_WEB="$APP_HTML"
for em in 'Service Unavailable' 'Application failed to start' '502 Bad Gateway' '503 Service Temporarily Unavailable' 'Error: Server Error' 'That’s an error.' 'Internal Server Error' 'Application error: a client-side exception has occurred'; do
  mkroot n2; dev_env
  expect 1 "dev web health 200 이지만 본문에 오류 표지" "ⓝ2 web 200 + 앱 표지 있는 오류 HTML «${em}» → 막힘" "${DEV[@]}" FAKE_BODY_WEB="$(err_page "$em")"
done
mkroot n3; dev_env
expect 1 'dev web health 200 이지만 본문에 앱 표지' "ⓝ3 web 200 + 앱 표지 없는 HTML(다른 서비스·빈 페이지) → 막힘" "${DEV[@]}" FAKE_BODY_WEB='<!DOCTYPE html><html><body>hello</body></html>'
mkroot n4; dev_env
expect 1 'dev web health 200 이지만 본문이 비었다' "ⓝ4 web 200 + 빈 본문 → 막힘" "${DEV[@]}" FAKE_BODY_WEB=
mkroot n5; dev_env
expect 1 'dev web health 200 이지만 본문에 앱 표지' "ⓝ5 web 200 + JSON 본문(옛 픽스처 기본값) → 막힘" "${DEV[@]}" FAKE_BODY_WEB='{"ok":true}'
mkroot n6; dev_env
expect 0 'dev web health 200 —' "ⓝ6 FT_PRESS_DEV_WEB_MARK 로 앱 표지만 바꾼다(표지 있으면 통과)" "${DEV[@]}" FT_PRESS_DEV_WEB_MARK='data-app="byz"' \
  FAKE_BODY_WEB='<html><head><script src="/_next/static/a.js"></script></head><body data-app="byz"><main>다른 이름으로 배포한 우리 앱 화면입니다 — 표지만 다르다</main></body></html>'
mkroot n7; dev_env
expect 1 '앱 표지 «data-app="byz"» 없음' "ⓝ7 표지를 바꾸면 기본 표지(<title>하우투 톡)만으론 막힘" "${DEV[@]}" FT_PRESS_DEV_WEB_MARK='data-app="byz"' FAKE_BODY_WEB="$APP_HTML"
mkroot n8; dev_env
expect 1 'dev web health=302' "ⓝ8 web 302(리다이렉트 뒤 다른 서비스) → 막힘(따라가지 않는다)" "${DEV[@]}" FAKE_CURL_WEB=302
mkroot n9; dev_env
expect 1 'dev web health=200 rc=7' "ⓝ9 curl 실패(rc≠0) → 막힘" "${DEV[@]}" FAKE_CURL_RC=7
for gb in '' 'ok' '{"error":"boom"}' '{"status":"degraded"}' '[{"status":"ok"}]' '{"status":"ok"'; do
  mkroot n10; dev_env; gw_why='본문이 status=ok JSON 객체가 아니다'; [ -z "$gb" ] && gw_why='본문이 비었다'
  expect 1 "dev gateway health 200 이지만 ${gw_why}" "ⓝ10 gateway 200 + 본문 «${gb:-빈 본문}» → 막힘" "${DEV[@]}" FAKE_BODY_GW="$gb"
done
mkroot n11; dev_env
expect 0 'dev gateway health 200 —' "ⓝ11 gateway 200 + {\"status\":\"ok\",…} JSON → 통과" "${DEV[@]}" FAKE_BODY_GW='{"status":"ok","service":"gateway"}'
n=$((n+1)); grep -c '^DEV_ERR_MARKS=' "$GATE" | grep -qx 1 && grep -q '^DEV_WEB_MARK="\${FT_PRESS_DEV_WEB_MARK:-' "$GATE" \
  && ok "$n. ⓝ12 오류 표지 목록·앱 표지 기본값 = 파일 맨 위 1곳" || bad "$n. ⓝ12 표지 정의 위치"

# ══ ⓞ r685 DA⑥ r1 반례(H1 앱 표지 고유성 · H2 본문 판별 마감 · H3) — 오류 문구는 구현 목록과 «다른» 철자·대소문자로도
for em in 'Application error: a server-side exception has occurred (see the server logs for more information).' 'Failed to compile' 'service unavailable' '404 — 페이지를 찾을 수 없습니다' '404: This page could not be found.'; do
  mkroot o1; dev_env
  expect 1 "dev web health 200 이지만 본문에 오류 표지" "ⓞ1 앱 표지 다 갖춘 Next 오류 화면 «${em}» → 막힘" "${DEV[@]}" FAKE_BODY_WEB="$(err_page "$em")"
done
mkroot o2; dev_env
expect 1 'dev web health 200 이지만 본문에 앱 표지' "ⓞ2 200 로그인 화면(Sign in · /_next/static/ 있음 · 우리 제목 없음) → 막힘" "${DEV[@]}" \
  FAKE_BODY_WEB='<!DOCTYPE html><html><head><title>Sign in - Google Accounts</title><script src="/_next/static/s.js"></script></head><body><h1>Sign in</h1><p>to continue to Cloud Run — use your Google Account</p></body></html>'
mkroot o3; dev_env
expect 1 'dev web health 200 이지만 본문 <body> 의 보이는 글자' "ⓞ3 빈 body + 앱 표지만(정적 껍데기) → 막힘" "${DEV[@]}" \
  FAKE_BODY_WEB='<!DOCTYPE html><html><head><title>하우투 톡</title><script src="/_next/static/a.js"></script></head><body><div id="root"></div><script>self.__next_f.push([1,"하우투 톡 실시간 AI 통역 화면 데이터 조각"])</script></body></html>'
mkroot o4; dev_env
expect 1 'dev web health 200 이지만 본문에 «</html>» 없음' "ⓞ4 앱 표지만 있는 잘린 본문(</html> 없음) → 막힘" "${DEV[@]}" FAKE_BODY_WEB="${APP_HTML%</body></html>}"
mkroot o5; dev_env
expect 0 'dev web health 200 —' "ⓞ5 정상 화면의 스크립트(RSC 데이터) 안 «This page could not be found» 는 통과(실측 dev 루트 2회 · 보이는 글자만 대조)" "${DEV[@]}" \
  FAKE_BODY_WEB="${APP_HTML%</body></html>}<script>self.__next_f.push([1,\"404: This page could not be found.\"])</script></body></html>"
mkroot o6; dev_env
expect 1 'FT_PRESS_DEV_WEB_MARK=«<» 1글자 — 6글자 미만' "ⓞ6 약한 env 표지 «<» → 경고 + 기본값으로 판별(제목 없는 화면 막힘)" "${DEV[@]}" FT_PRESS_DEV_WEB_MARK='<' \
  FAKE_BODY_WEB='<!DOCTYPE html><html><head><script src="/_next/static/x.js"></script></head><body><main>아무 Next 앱 화면 — 우리 제목은 없다 아무 글자</main></body></html>'
printf '%s' "$OUT" | grep -q '본문에 앱 표지 «<title>하우투 톡» 없음' && ok "  ⓞ6b 기본값 «<title>하우투 톡» 으로 막았다" || bad "  ⓞ6b 기본값 판별 아님"
mkroot o7; dev_env
expect 1 'dev web health 200 이지만 본문 판별 실패' "ⓞ7 본문 판별 python 실패(rc=1·출력 0) → 막힘(fail-closed)" "${DEV[@]}" FAKE_PY=fail
mkroot o8; dev_env
n=$((n+1)); s0=$SECONDS; gate "${DEV[@]}" FT_PRESS_DEV_BUDGET=4 FAKE_PY=slow; got=$?; el=$((SECONDS-s0))
[ "$got" -eq 1 ] && [ "$el" -lt 20 ] && printf '%s' "$OUT" | grep -q 'dev web health 200 이지만 본문 판별' && ! printf '%s' "$OUT" | grep -q 'dev gateway health 200 —' \
  && ok "$n. ⓞ8 느린 본문 판별(30초·TERM 무시) + 마감 4초 → ${el}초 만에 web·gateway 막힘(판별도 마감 안 · exit $got)" \
  || { bad "$n. ⓞ8 느린 본문 판별 (el=${el}s exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ══ ⓛ H4 시간 상한(TERM 무시 자식 · 전체 마감)
mkroot l1; dev_env
n=$((n+1)); s0=$SECONDS; gate "${DEV[@]}" FAKE_SLOW_SVC="$SVC_WK"; got=$?; el=$((SECONDS-s0))
[ "$got" -eq 1 ] && [ "$el" -lt 15 ] && printf '%s' "$OUT" | grep -q 'dev worker 이미지 sha 못 읽음' \
  && ok "$n. ⓛ1 TERM 무시 스텁(gcloud 30초) → ${el}초 만에 막힘(timeout -k 강제종료 · exit $got)" \
  || { bad "$n. ⓛ1 TERM 무시 (el=${el}s exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
# ⓛ1b _bounded 단위 — timeout/gtimeout 이 «없는» PATH 에서 TERM 무시 자식을 KILL 로 끊는가(실제 경과 단언)
sed -n '/^_bounded(){/,/^}/p' "$GATE" > "$T/bounded.sh"
printf '#!/bin/sh\ntrap "" TERM\nsleep 30\n' > "$T/termsh"; chmod +x "$T/termsh"   # TERM 을 무시하는 자식
n=$((n+1)); u="$(PATH=/usr/bin:/bin bash -c 'source "$1"; s=$SECONDS; _bounded 3 "$2"; echo "rc=$? el=$((SECONDS-s))"' _ "$T/bounded.sh" "$T/termsh" 2>&1)"
urc="$(printf '%s' "$u" | sed -n 's/.*rc=\([0-9]*\).*/\1/p')"; uel="$(printf '%s' "$u" | sed -n 's/.*el=\([0-9]*\).*/\1/p')"
[ -n "$urc" ] && [ "$urc" != 0 ] && [ "${uel:-99}" -le 8 ] \
  && ok "$n. ⓛ1b _bounded(timeout 없는 PATH) = TERM 무시 자식을 ${uel}초에 KILL(rc=$urc)" \
  || bad "$n. ⓛ1b _bounded 대체 경로 (${u:-출력 없음})"

mkroot l2; dev_env
n=$((n+1)); s0=$SECONDS; gate "${DEV[@]}" FT_PRESS_DEV_BUDGET=5 FAKE_SLOW_HEALTH=1; got=$?; el=$((SECONDS-s0))
[ "$got" -eq 1 ] && [ "$el" -lt 25 ] && printf '%s' "$OUT" | grep -q 'dev 검사 시간 마감' \
  && ok "$n. ⓛ2 전체 마감(FT_PRESS_DEV_BUDGET=5) 넘기면 막힘 — ${el}초(exit $got)" \
  || { bad "$n. ⓛ2 전체 마감 (el=${el}s exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }

# ══ ⓜ 변이 대조(H5④): dev 칸 최종 판정(FAIL=1)을 «:» 로 지운 사본에서 ⓑ 가 통과해 버리는가
mkroot m; dev_env
mkdir -p "$T/mut"; for f in "$(dirname "$GATE")"/*; do b="$(basename "$f")"; [ "$b" = ft-press-gate.sh ] && continue; ln -sf "$f" "$T/mut/$b"; done
MUT="$T/mut/ft-press-gate.sh"
sed 's/^  \[ "\$bad" = "0" \] || FAIL=1$/  : # MUTANT/' "$GATE" > "$MUT"; chmod +x "$MUT"
n=$((n+1))
if ! grep -q 'MUTANT' "$MUT"; then bad "$n. ⓜ 변이 사본 생성 실패(패턴 불일치)"
else
  SUT="$MUT"; gate "${DEV[@]}" FAKE_CURL_GW=503; got=$?; SUT="$GATE"
  { echo "# 변이 대조 — dev 칸 최종 판정 줄을 지운 사본에서 ⓑ 가 통과하면 시험이 그 변이를 못 죽인 것"; echo "\$ sed 's/FAIL=1/:/'"; grep -n 'MUTANT' "$MUT"; echo "exit=$got (기대 0 = 변이 생존 = 이 시험이 죽인다)" ; printf '%s\n' "$OUT" | grep -E 'gateway|PRESS-GATE' ; } > "$T/mut.txt"
  [ -n "${R634_MUT_OUT:-}" ] && cp "$T/mut.txt" "$R634_MUT_OUT"   # 증거 수집용(리포 밖 경로만 — 시험 중 리포 쓰기 0 유지)
  [ "$got" -eq 0 ] && ok "$n. ⓜ 변이(최종 FAIL 판정 삭제) 사본에서 ⓑ 가 exit 0 = 부정 칸이 그 변이를 죽인다" \
    || { bad "$n. ⓜ 변이 생존 실패 (exit $got)"; printf '%s\n' "$OUT" | sed 's/^/    /'; }
fi

# ══ 정적: 하위 호환 칸 수 · 리포 쓰기 0
n=$((n+1))
grep -q 'printf .%s\\t%s\\t%s\\t%s\\t%s\\t%s' "$GATE" && grep -q '"ts","target"' "$GATE" \
  && ok "$n. 허가 줄 = 끝 칸 1개 덧붙임(옛 5칸 호환)" || bad "$n. 허가 줄 칸"
n=$((n+1)); [ "$(git -C "$HERE/../.." status --porcelain)" = "$REAL_BEFORE" ] && ok "$n. 실제 리포 파일 쓰기 0(시험 전후 git status 동일)" || bad "$n. 실제 리포가 바뀌었다"
echo "cases=$n fail=$fail"; [ $fail -eq 0 ] && echo "ALL PASS"
[ $fail -eq 0 ]
