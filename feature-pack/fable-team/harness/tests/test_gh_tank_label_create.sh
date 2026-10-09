#!/usr/bin/env bash
# test_gh_tank_label_create.sh — ft-gh-as-tank.sh label-create + ft-gh-tank-label-create.sh 시험. 실제 GitHub 호출 0 · 실 토큰 0 — PATH 맨 앞 가짜 gh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
WRAP="$ROOT/scripts/fable-team-bin/ft-gh-as-tank.sh"
BODY="$ROOT/scripts/fable-team-bin/ft-gh-tank-label-create.sh"
WRAP2="$ROOT/scripts/harness-install/fable-team/bin/ft-gh-as-tank.sh"
BODY2="$ROOT/scripts/harness-install/fable-team/bin/ft-gh-tank-label-create.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"; LOG="$T/gh.log"; Q="$T/queue"; QPOS="$T/qpos"; : > "$LOG"
# 가짜 gh: 호출을 로그에 남긴다. `api user` = STUB_LOGIN. 그 밖의 `api` 호출은 큐(줄 = "rc|문구")에서 한 줄씩 소비 —
# rc=0 이면 문구를 stdout, 아니면 stderr 로 내고 그 rc 로 끝난다. 큐가 비면 rc=99(시험 설계 오류가 눈에 띄게).
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "GH_TOKEN=${GH_TOKEN:-} $*" >> "$STUB_LOG"
[ "$1 $2" = "api user" ] && { echo "${STUB_LOGIN:-byz-tank}"; exit 0; }
[ "$1" = api ] || exit 0
n=$(( $(cat "$STUB_QPOS" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_QPOS"
line="$(sed -n "${n}p" "$STUB_QUEUE")"
[ -n "$line" ] || { echo "큐 소진(호출 $n)" >&2; exit 99; }
rc="${line%%|*}"; msg="${line#*|}"
if [ "$rc" = 0 ]; then printf '%s\n' "$msg"; else printf '%s\n' "$msg" >&2; fi
exit "$rc"
EOF
chmod +x "$T/bin/gh"
export STUB_LOG="$LOG" STUB_QUEUE="$Q" STUB_QPOS="$QPOS" PATH="$T/bin:$PATH"
TOKEN="tok_SECRET_VALUE_123"
NF='1|gh: Not Found (HTTP 404)'
CREATED='0|{"name":"team:graphics","color":"d73a4a","url":"https://api.github.com/repos/SecondWindStudio/byz-agents/labels/team:graphics"}'

# q <큐 줄…> : 큐·로그·소비 위치 초기화
q() { : > "$LOG"; rm -f "$QPOS"; : > "$Q"; for l in "$@"; do printf '%s\n' "$l" >> "$Q"; done; }
# lc <인자…> : 래퍼 label-create --apply (Tank 토큰)
lc() { out="$(env FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" label-create "$@" --apply 2>&1)"; rc=$?; }
n_api() { grep -c "^GH_TOKEN=[^ ]* api $1" "$LOG" || true; }   # 라벨 api 호출 수(api user 제외)
n_label_calls() { grep "api " "$LOG" | grep -vc "api user" || true; }
n_post() { grep -c "api -X POST" "$LOG" || true; }
notoken() { ! grep -qF "$TOKEN" <<<"$out" && ok "출력에 토큰 없음: $1" || bad "출력에 토큰 노출: $1"; }

# ── ⑧ 정적: bash -n 4파일 · 두 사본 쌍 cmp · 줄 수 ──
for f in "$WRAP" "$BODY" "$WRAP2" "$BODY2"; do bash -n "$f" && ok "bash -n ${f##*/}" || bad "bash -n $f"; done
cmp -s "$WRAP" "$WRAP2" && ok "래퍼 두 사본 바이트 동일" || bad "래퍼 두 사본이 다르다"
cmp -s "$BODY" "$BODY2" && ok "본체 두 사본 바이트 동일" || bad "본체 두 사본이 다르다"
[ "$(wc -l < "$WRAP")" -le 200 ] && ok "래퍼 줄 수 ≤ 200 ($(wc -l < "$WRAP"))" || bad "래퍼 줄 수 > 200"
[ "$(wc -l < "$BODY")" -le 80 ] && ok "본체 줄 수 ≤ 80 ($(wc -l < "$BODY"))" || bad "본체 줄 수 > 80"

# ── ① 만들기: 조회 404 → POST 1회(name·color·description 인자) · OK 줄 ──
q "$NF" "$CREATED"
lc team:graphics --color d73a4a --description "그래픽스 팀"
[ $rc -eq 0 ] && grep -q "^OK as=byz-tank label-create team:graphics — https://api.github.com/.*/labels/team:graphics" <<<"$out" && ok "① 만들기 rc=0 · OK 줄" || bad "① 만들기 → rc=$rc $out"
[ "$(n_post)" -eq 1 ] && ok "① POST 1회" || bad "① POST $(n_post)회"
POSTLINE="$(grep "api -X POST" "$LOG")"
grep -qF "repos/SecondWindStudio/byz-agents/labels -f name=team:graphics -f color=d73a4a -f description=그래픽스 팀" <<<"$POSTLINE" && ok "① POST 인자: name·color·description" || bad "① POST 인자: $POSTLINE"
grep -qF "api repos/SecondWindStudio/byz-agents/labels/team%3Agraphics" "$LOG" && ok "① 조회 경로 = URL 인코딩 이름" || bad "① 조회 경로: $(cat "$LOG")"
[ "$(grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -vc "api user")" -eq 2 ] && ok "① 조회·POST 모두 Tank 토큰" || bad "① 토큰 누락: $(cat "$LOG")"
notoken "① 만들기"
q "$NF" "$CREATED"; lc security --color 000000
[ $rc -eq 0 ] && ! grep -q "description" "$LOG" && ok "① 설명 없으면 description 인자 0" || bad "① 설명 없음 → rc=$rc $(cat "$LOG")"

# ── ② 이미 있음: 조회 200 → POST 0 · EXISTS 줄 · 색 그대로 ──
q '0|{"name":"security","color":"ededed"}'; lc security --color d73a4a
[ $rc -eq 0 ] && grep -q "^EXISTS as=byz-tank label security color=ededed" <<<"$out" && ok "② 이미 있음 rc=0 · EXISTS 줄(현재 색)" || bad "② → rc=$rc $out"
[ "$(n_post)" -eq 0 ] && [ "$(n_label_calls)" -eq 1 ] && ok "② POST 0 · 라벨 호출 1회(조회)" || bad "② 호출: $(cat "$LOG")"
# 422 경합: 조회 404 → POST 422 → 재조회 200
q "$NF" '1|gh: Validation Failed (HTTP 422)' '0|{"name":"security","color":"ededed"}'; lc security --color d73a4a
[ $rc -eq 0 ] && grep -q "^EXISTS as=byz-tank label security color=ededed" <<<"$out" && ok "② 422 경합 → 재조회 → EXISTS rc=0" || bad "② 422 → rc=$rc $out"
[ "$(n_post)" -eq 1 ] && [ "$(n_label_calls)" -eq 3 ] && ok "② 422: POST 1 · 라벨 호출 3(조회·POST·재조회)" || bad "② 422 호출: $(cat "$LOG")"
# 422 인데 재조회에도 없음(색 무효 등) → REJECT
q "$NF" '1|gh: Validation Failed (HTTP 422)' "$NF"; lc security --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 라벨 생성 422" <<<"$out" && ok "② 422 인데 재조회 없음 → REJECT rc=1" || bad "② 422 무효 → rc=$rc $out"

# ── ③ 권한 없음: 조회 또는 POST 403/401 → REJECT 권한 없음 · rc=1 · POST 이후 재시도 0 ──
q '1|gh: Forbidden (HTTP 403)'; lc security --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 권한 없음(HTTP 403) — Tank 토큰 Issues 쓰기 권한 확인" <<<"$out" && ok "③ 조회 403 → REJECT rc=1" || bad "③ 조회 403 → rc=$rc $out"
[ "$(n_post)" -eq 0 ] && [ "$(n_label_calls)" -eq 1 ] && ok "③ 조회 403: POST 0 · 재시도 0" || bad "③ 조회 403 호출: $(cat "$LOG")"
q "$NF" '1|gh: Forbidden (HTTP 403)'; lc security --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 권한 없음(HTTP 403)" <<<"$out" && ok "③ POST 403 → REJECT rc=1" || bad "③ POST 403 → rc=$rc $out"
[ "$(n_post)" -eq 1 ] && [ "$(n_label_calls)" -eq 2 ] && ok "③ POST 403: POST 1회 · 재시도 0" || bad "③ POST 403 호출: $(cat "$LOG")"
q '1|gh: Bad credentials (HTTP 401)'; lc security --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 권한 없음(HTTP 401)" <<<"$out" && ok "③ 401 → REJECT 권한 없음(HTTP 401)" || bad "③ 401 → rc=$rc $out"
q "$NF" '1|gh: Gone (HTTP 410)'; lc security --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 라벨 생성 실패" <<<"$out" && ok "③ 그 밖 오류 → REJECT rc=1 (조용한 폴백 0)" || bad "③ 410 → rc=$rc $out"

# ── ④ 인자 검증: rc=2 · gh 호출 0 ──
L51="$(printf 'a%.0s' $(seq 1 51))"; L101="$(printf 'd%.0s' $(seq 1 101))"
chk() { q; lc "$@"; [ $rc -eq 2 ] && [ ! -s "$LOG" ] && ok "④ rc=2 · gh 호출 0: ${2:-$1}" || bad "④ rc=2·gh 0 여야 함: [$*] → rc=$rc $out · $(cat "$LOG")"; }
chk x --color '#d73a4a'
chk x --color d73a4
chk x --color d73a4ab
chk x --color zzzzzz
chk x
chk 'a,b' --color d73a4a
chk "$(printf 'a\nb')" --color d73a4a
chk "$L51" --color d73a4a
chk x --color d73a4a --description "$L101"
chk x --color d73a4a --bogus 1
chk x --color
chk --color d73a4a
q; lc "$(printf 'a%.0s' $(seq 1 50))" --color D73A4A --description "$(printf 'd%.0s' $(seq 1 100))" 2>/dev/null; [ $rc -ne 2 ] && ok "④ 경계값(이름 50자·색 대문자·설명 100자)은 검증 통과" || bad "④ 경계값이 검증에서 거부됨: $out"

# ── ⑤ dry-run: gh 호출 0 · DRY 줄 ──
q; out="$(env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" label-create team:graphics --color d73a4a --description x 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "DRY as=byz-tank label-create team:graphics color=d73a4a desc=있음" ] && ok "⑤ dry-run DRY 줄(desc=있음) rc=0" || bad "⑤ dry-run → rc=$rc $out"
out="$(env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" label-create security --color 000000 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$out" = "DRY as=byz-tank label-create security color=000000 desc=없음" ] && ok "⑤ dry-run DRY 줄(desc=없음) rc=0" || bad "⑤ dry-run 설명 없음 → rc=$rc $out"
[ ! -s "$LOG" ] && ok "⑤ dry-run gh 호출 0" || bad "⑤ dry-run 인데 gh 호출됨: $(cat "$LOG")"

# ── ⑥ 토큰 주인 ≠ byz-tank → rc=1 · 본체(라벨 api) 호출 0 ──
q "$NF" "$CREATED"; out="$(STUB_LOGIN=yoonhwan FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" label-create security --color 000000 --apply 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -q "REJECT 토큰 주인이 byz-tank 가 아니다(주인=yoonhwan)" <<<"$out" && ok "⑥ 토큰 주인 불일치 → REJECT rc=1" || bad "⑥ → rc=$rc $out"
[ "$(n_label_calls)" -eq 0 ] && ok "⑥ 본체 호출 0(조회·POST 0)" || bad "⑥ 본체가 호출됨: $(cat "$LOG")"
# 토큰 없음 → rc=2 · gh 호출 0 (오빠 로그인 폴백 0)
q; out="$(env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" label-create security --color 000000 --apply 2>&1)"; rc=$?
[ $rc -eq 2 ] && grep -q "봇 토큰 없음" <<<"$out" && [ ! -s "$LOG" ] && ok "⑥ 토큰 없음 → rc=2 · gh 호출 0" || bad "⑥ 토큰 없음 → rc=$rc $out"
# 본체 직접: FT_TANK_TOK 없음 → rc=2 · gh 호출 0
q; out="$(env -u FT_TANK_TOK bash "$BODY" security 000000 2>&1)"; rc=$?
[ $rc -eq 2 ] && [ ! -s "$LOG" ] && ok "⑥ 본체 FT_TANK_TOK 없음 → rc=2 · gh 호출 0" || bad "⑥ 본체 토큰 없음 → rc=$rc $out"

# ── ⑦ 시간 초과(rc 124)·5xx: 1회 재시도 · 2회 연속이면 REJECT ──
q '124|' "$NF" "$CREATED"; lc team:graphics --color d73a4a
[ $rc -eq 0 ] && grep -q "^OK as=byz-tank label-create team:graphics" <<<"$out" && ok "⑦ 조회 시간 초과 1회 → 재시도 뒤 성공 rc=0" || bad "⑦ 조회 시간 초과 → rc=$rc $out"
[ "$(n_label_calls)" -eq 3 ] && ok "⑦ 라벨 호출 3회(조회 2 · POST 1)" || bad "⑦ 호출 수: $(cat "$LOG")"
q "$NF" '124|' "$CREATED"; lc team:graphics --color d73a4a
[ $rc -eq 0 ] && [ "$(n_post)" -eq 2 ] && ok "⑦ POST 시간 초과 1회 → 재시도 뒤 성공 rc=0" || bad "⑦ POST 시간 초과 → rc=$rc post=$(n_post) $out"
q "$NF" '1|gh: Bad Gateway (HTTP 502)' "$CREATED"; lc team:graphics --color d73a4a
[ $rc -eq 0 ] && [ "$(n_post)" -eq 2 ] && ok "⑦ POST 5xx 1회 → 재시도 뒤 성공 rc=0" || bad "⑦ POST 5xx → rc=$rc post=$(n_post) $out"
q '124|' '124|' "$NF"; lc team:graphics --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 라벨 조회 실패(rc=124)" <<<"$out" && ok "⑦ 조회 2회 연속 시간 초과 → REJECT rc=1" || bad "⑦ 조회 2회 연속 → rc=$rc $out"
[ "$(n_label_calls)" -eq 2 ] && [ "$(n_post)" -eq 0 ] && ok "⑦ 조회 2회 뒤 중단 · POST 0(재시도 상한 1)" || bad "⑦ 호출: $(cat "$LOG")"
q "$NF" '124|' '124|' "$CREATED"; lc team:graphics --color d73a4a
[ $rc -eq 1 ] && grep -q "REJECT 라벨 생성 실패(rc=124)" <<<"$out" && [ "$(n_post)" -eq 2 ] && ok "⑦ POST 2회 연속 시간 초과 → REJECT rc=1 · 더 시도 0" || bad "⑦ POST 2회 연속 → rc=$rc post=$(n_post) $out"
q '1|gh: Forbidden (HTTP 403)'; lc x --color 000000
[ "$(n_label_calls)" -eq 1 ] && ok "⑦ 403 은 재시도 대상 아님" || bad "⑦ 403 재시도됨: $(cat "$LOG")"

# ── ⑨ 기존 tank 시험 그대로 PASS ──
out="$(bash "$HERE/test_gh_as_tank.sh" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "⑨ test_gh_as_tank.sh PASS ($(tail -1 <<<"$out"))" || bad "⑨ test_gh_as_tank.sh rc=$rc: $(grep '^FAIL' <<<"$out" | head -3)"

echo "fail=$fail"; [ $fail -eq 0 ]
