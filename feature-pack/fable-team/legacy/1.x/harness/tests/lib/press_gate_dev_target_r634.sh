# press_gate_dev_target_r634.sh — test_press_gate_dev_target_r634_a.sh·_b.sh 공용 준비(스텁·mkroot·gate·expect) · r1134 쪼개기.
#   부르는 쪽이 먼저 HERE(=tests 폴더)를 정하고 이 파일을 «.» 으로 읽는다 · 칸은 부르는 파일에만 있다 · 끝에 r634_finish.
#   r634: press 게이트 «dev 대상» 갈래 — FT_PRESS_TARGET=dev 를 «선언한» 회차만 ②~⑤(로컬 스택) 대신 dev 칸(web·gateway health 200 + 세 서비스 이미지 sha ⊇ WANT)을 본다.
#   가짜 tmux·curl·gcloud 만 · 실제 dev·Cloud Run·리스너·오디오 0 · 리포 파일 쓰기 0.
#   ★칸마다 «새 임시 루트»(r634 DA⑥ r1 H5①) — 앞 칸의 허가 파일·BTS 골격이 다음 칸을 GREEN 으로 만들지 않는다.
#   ★전 케이스 «게이트 최종 exit» 단언: 통과 0 · 막힘 1★
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
# ⓝ·ⓞ 공용(r685) — 정상 앱 HTML · 앱 표지를 다 갖춘 오류 화면
APP_HTML='<!DOCTYPE html><html lang="ko"><head><title>하우투 톡 — 실시간 AI 음성 통역</title><script src="/_next/static/chunks/main.js"></script></head><body><main>하우투 톡 실시간 AI 통역 — 병원 진료 설명도 바로 통역합니다</main></body></html>'
err_page(){ # 오류 문구 → 앱 표지(제목·/_next/static/·</html>·보이는 글자)를 «다 갖춘» 오류 화면 — 표지가 있어도 오류 문구로 막혀야 한다
  printf '<!DOCTYPE html><html><head><title>하우투 톡</title><script src="/_next/static/x.js"></script></head><body><h1>%s</h1><p>잠시 후 다시 시도해 주세요 — 하우투 톡 실시간 통역</p></body></html>' "$1"; }
r634_finish(){ echo "cases=$n fail=$fail"; [ $fail -eq 0 ] && echo "ALL PASS"; [ $fail -eq 0 ]; }
