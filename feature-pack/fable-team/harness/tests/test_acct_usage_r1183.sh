#!/usr/bin/env bash
# test_acct_usage_r1183.sh — ft-acct-usage.sh 반례 R1~R10 + 변이 1 (r1183 · 가짜 curl·가짜 auth·임시 HOME · 실 호출 0)
#   bash tests/test_acct_usage_r1183.sh [--mutate]
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../bin/ft-acct-usage.sh"
KIT="$HERE/../kit/fable-team/bin/ft-acct-usage.sh"
NOW=1793400000
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export FT_ACCT_USAGE_NOW="$NOW" FT_ACCT_USAGE_CURL="curl"

# ── 가짜 curl: 호출 기록 + 토큰별 상태/본문/지연 ───────────────────────────────
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env python3
import os, sys, time
a = sys.argv[1:]
url = next((x for x in a if x.startswith("http")), "")
tok = ""
for i, x in enumerate(a):
    if x == "-H" and a[i + 1].lower().startswith("authorization:"):
        tok = a[i + 1].split("Bearer ", 1)[-1].strip()
d = os.environ["FAKE_DIR"]
open(os.path.join(d, "log"), "a").write(tok + "\t" + url + "\n")
p = os.path.join(d, "delay." + tok)
delay = float(open(p).read().strip()) if os.path.exists(p) else 0.0
mt = 0.0
for i, x in enumerate(a):
    if x == "-m" and i + 1 < len(a):
        mt = float(a[i + 1])
if mt and delay >= mt:
    time.sleep(mt)
    sys.stderr.write("curl: (28) timed out\n")
    sys.exit(28)
if delay:
    time.sleep(delay)
p = os.path.join(d, "status." + tok)
code = open(p).read().strip() if os.path.exists(p) else "200"
p = os.path.join(d, "body." + tok)
body = open(p).read() if os.path.exists(p) else open(os.path.join(d, "default.json")).read()
sys.stdout.write(body + "\n" + code)
EOF
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
FAKE_DIR="$TMP/fake"; mkdir -p "$FAKE_DIR"; export FAKE_DIR
cat > "$FAKE_DIR/default.json" <<'EOF'
{"five_hour":{"utilization":40.0,"resets_at":"2026-10-31T10:00:00+00:00"},
 "seven_day":{"utilization":20.0,"resets_at":"2026-11-04T05:59:59+00:00"},
 "limits":[{"kind":"session","percent":40,"resets_at":"2026-10-31T10:00:00+00:00"},
           {"kind":"weekly_scoped","percent":20,"resets_at":"2026-11-04T05:59:59+00:00"}]}
EOF
cat > "$FAKE_DIR/codex.json" <<'EOF'
{"plan_type":"pro","rate_limit":{"allowed":true,"limit_reached":false,
 "primary_window":{"used_percent":55,"reset_after_seconds":3600,"reset_at":1793774220,"limit_window_seconds":604800},
 "secondary_window":{"used_percent":null}},
 "credits":{"has_credits":true,"unlimited":false,"balance":"100.5"}}
EOF

mk_auth() { # $1=폴더 $2=파일이름 $3=token $4=expired $5=disabled $6=account_id
  printf '{"type":"claude","access_token":"%s","refresh_token":"rt-%s","email":"yoonhwan.ko@byourz.com","expired":"%s","disabled":%s,"account_id":"%s"}\n' \
    "$3" "$3" "$4" "$5" "${6:-}" > "$1/$2"
}
newdir() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }
run() { # $1=auth dir $2=state dir [args…] — stdout·rc 를 OUT/RC 에
  local d="$1" s="$2"; shift 2
  OUT="$(FT_ACCT_USAGE_AUTH_DIR="$d" FT_ACCT_USAGE_STATE="$s" bash "$TOOL" "$@" 2>"$TMP/err")"; RC=$?
}
calls() { wc -l < "$FAKE_DIR/log" 2>/dev/null | tr -d ' ' || echo 0; }

bash -n "$TOOL" && ok "bash -n" || bad "bash -n"
[ -f "$KIT" ] && cmp -s "$TOOL" "$KIT" && ok "bin·kit cmp0" || bad "bin·kit cmp0"

# ── R1 정상 4파일(claude 3 · codex 1) → 4행 rc0 · 이메일 전문 0 ────────────────
A="$(newdir r1)"; S="$(newdir r1s)"
mk_auth "$A" claude-aaaa1111-yoonhwan.ko@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
mk_auth "$A" claude-bbbb2222-developer.ts@byourz.com.json tok-b 2030-01-01T00:00:00+09:00 false
mk_auth "$A" claude-cccc3333-admin.ts@byourz.com.json tok-c 2030-01-01T00:00:00+09:00 false
printf '{"type":"codex","access_token":"tok-d","email":"yoonhwan.ko@gmail.com","expired":"2030-01-01T00:00:00+09:00","disabled":false,"account_id":"acc-d"}\n' \
  > "$A/codex-dddd4444-yoonhwan.ko@gmail.com-pro.json"
cp "$FAKE_DIR/codex.json" "$FAKE_DIR/body.tok-d"
run "$A" "$S"
n="$(printf '%s\n' "$OUT" | grep -c '^claude\|^codex')"
[ "$RC" -eq 0 ] && ok "R1 rc0" || bad "R1 rc0 (rc=$RC)"
[ "$n" -eq 4 ] && ok "R1 4행" || bad "R1 4행 (n=$n)"
printf '%s\n' "$OUT" | grep -q 'yoonhwan' && bad "R1 이메일 전문 노출" || ok "R1 이메일 전문 0"
printf '%s\n' "$OUT" | grep -q '40' && ok "R1 5시간 % 표시" || bad "R1 5시간 % 표시"
printf '%s\n' "$OUT" | grep -qi 'codex.*55' && ok "R1 codex 7일 % 표시" || bad "R1 codex 7일 % 표시 ($(printf '%s\n' "$OUT" | tail -1))"

# ── R2 한 계정 429 → 그 행 판정 불가 · 나머지 정상 · rc3 ──────────────────────
B="$(newdir r2)"; SB="$(newdir r2s)"
mk_auth "$B" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
mk_auth "$B" claude-bbbb2222-x@byourz.com.json tok-429 2030-01-01T00:00:00+09:00 false
echo 429 > "$FAKE_DIR/status.tok-429"
run "$B" "$SB"
[ "$RC" -eq 3 ] && ok "R2 rc3" || bad "R2 rc3 (rc=$RC)"
printf '%s\n' "$OUT" | grep -q '429' && ok "R2 429 행" || bad "R2 429 행"
printf '%s\n' "$OUT" | grep -q 'OK' && ok "R2 나머지 정상" || bad "R2 나머지 정상"

# ── R3 8초 지연 → 7초에 끊고 재시도 1 → 판정 불가 시간 초과 · 상한 안 ───────────
C="$(newdir r3)"; SC="$(newdir r3s)"
mk_auth "$C" claude-aaaa1111-x@byourz.com.json tok-slow 2030-01-01T00:00:00+09:00 false
echo 8 > "$FAKE_DIR/delay.tok-slow"
t0=$(date +%s); run "$C" "$SC"; el=$(( $(date +%s) - t0 ))
printf '%s\n' "$OUT" | grep -q '판정 불가 시간 초과' && ok "R3 시간 초과 판정" || bad "R3 시간 초과 판정 ($OUT)"
[ "$el" -le 12 ] && ok "R3 배치 상한 10초 안 (${el}s)" || bad "R3 배치 상한 (${el}s)"

# ── R4 60초 캐시: 두 번째 호출 0 · 61초 뒤 다시 호출 ───────────────────────────
D="$(newdir r4)"; SD="$(newdir r4s)"
mk_auth "$D" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
: > "$FAKE_DIR/log"; run "$D" "$SD"; n1=$(calls)
FT_ACCT_USAGE_NOW=$((NOW + 30)) run "$D" "$SD"; n2=$(calls)
FT_ACCT_USAGE_NOW=$((NOW + 61)) run "$D" "$SD"; n3=$(calls)
[ "$n1" -eq 1 ] && [ "$n2" -eq 1 ] && ok "R4 60초 안 재조회 0 (n1=$n1 n2=$n2)" || bad "R4 캐시 (n1=$n1 n2=$n2)"
[ "$n3" -ge 2 ] && ok "R4 61초 뒤 재조회" || bad "R4 61초 뒤 재조회 (n3=$n3)"

# ── R5 만료 토큰 → 갱신 호출 0 · 파일 무변경 · «만료 · cliproxy 갱신 대기» ─────
E="$(newdir r5)"; SE="$(newdir r5s)"
mk_auth "$E" claude-aaaa1111-x@byourz.com.json tok-exp 2020-01-01T00:00:00+09:00 false
h0="$(shasum -a 256 "$E/claude-aaaa1111-x@byourz.com.json" | cut -d' ' -f1)"; m0="$(stat -f %m "$E/claude-aaaa1111-x@byourz.com.json")"
: > "$FAKE_DIR/log"; run "$E" "$SE"; n=$(calls)
h1="$(shasum -a 256 "$E/claude-aaaa1111-x@byourz.com.json" | cut -d' ' -f1)"; m1="$(stat -f %m "$E/claude-aaaa1111-x@byourz.com.json")"
[ "$n" -eq 0 ] && ok "R5 갱신·조회 호출 0" || bad "R5 조회 호출 0 (n=$n)"
[ "$h0" = "$h1" ] && [ "$m0" = "$m1" ] && ok "R5 auth 파일 해시·mtime 그대로" || bad "R5 auth 파일 무변경"
printf '%s\n' "$OUT" | grep -q '만료 · cliproxy 갱신 대기' && ok "R5 만료 행" || bad "R5 만료 행 ($OUT)"

# ── R6 disabled → 조회 0 · «비활성» ──────────────────────────────────────────
F="$(newdir r6)"; SF="$(newdir r6s)"
mk_auth "$F" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 true
: > "$FAKE_DIR/log"; run "$F" "$SF"; n=$(calls)
[ "$n" -eq 0 ] && ok "R6 비활성 조회 0" || bad "R6 비활성 조회 0 (n=$n)"
printf '%s\n' "$OUT" | grep -q '비활성' && ok "R6 비활성 행" || bad "R6 비활성 행 ($OUT)"

# ── R7 auth 폴더 없음 → 1줄 rc2 · 빈 표 0 ────────────────────────────────────
run "$TMP/없는폴더" "$(newdir r7s)"
[ "$RC" -eq 2 ] && ok "R7 rc2" || bad "R7 rc2 (rc=$RC)"
[ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ] && ok "R7 1줄" || bad "R7 1줄 ($OUT)"
printf '%s\n' "$OUT" | grep -q '판정 불가 auth 폴더' && ok "R7 문구" || bad "R7 문구 ($OUT)"

# ── R8 출력·캐시·stderr 에 토큰·비밀 문자열 0 ────────────────────────────────
if grep -q 'tok-a\|rt-tok-a\|tok-d\|rt-tok-d' "$TMP/err" "$S"/*.json 2>/dev/null; then
  bad "R8 캐시·stderr 비밀 노출"
else ok "R8 캐시·stderr 비밀 0"; fi
printf '%s' "$OUT" | grep -q 'tok-' && bad "R8 stdout 토큰 노출" || ok "R8 stdout 토큰 0"

# ── R9 --json 행마다 같은 키 집합 · 못 준 칸 «근거 없음» ───────────────────────
J="$(FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" --json 2>/dev/null)"
printf '%s' "$J" | python3 -c '
import json,sys
rows=json.load(sys.stdin); keys={tuple(sorted(r)) for r in rows}
need={"provider","account","limit","used","remaining","spent","reset_at","unit","result"}
sys.exit(0 if len(rows)==4 and len(keys)==1 and need<=set(list(keys)[0]) else 1)' \
  && ok "R9 키 집합 동일" || bad "R9 키 집합 동일"
printf '%s' "$J" | grep -q '근거 없음' && ok "R9 못 준 칸 = 근거 없음" || bad "R9 근거 없음 문자열"

# ── R10 어댑터 추가 = 본체 수정 0 · 미등록 provider 1줄 ───────────────────────
G="$(newdir r10)"; SG="$(newdir r10s)"; AD="$(newdir adapters)"
cat > "$AD/fake.py" <<'EOF'
PROVIDER = "fake"
def fetch(auth, http):
    return {"used": 12, "limit": 100, "remaining": 88, "unit": "%"}
EOF
mk_auth "$G" fake-eeee5555-x@byourz.com.json tok-f 2030-01-01T00:00:00+09:00 false
mk_auth "$G" antigravity-x@byourz.com.json tok-g 2030-01-01T00:00:00+09:00 false
sha0="$(shasum -a 256 "$TOOL" | cut -d' ' -f1)"
OUT="$(FT_ACCT_USAGE_ADAPTER_DIR="$AD" FT_ACCT_USAGE_AUTH_DIR="$G" FT_ACCT_USAGE_STATE="$SG" bash "$TOOL" 2>/dev/null)"; RC=$?
sha1="$(shasum -a 256 "$TOOL" | cut -d' ' -f1)"
[ "$sha0" = "$sha1" ] && ok "R10 본체 무변경" || bad "R10 본체 무변경"
printf '%s\n' "$OUT" | grep -q '^fake' && ok "R10 가짜 어댑터 행" || bad "R10 가짜 어댑터 행 ($OUT)"
printf '%s\n' "$OUT" | grep -q '판정 불가 어댑터 없음 antigravity' && ok "R10 미등록 provider 1줄" || bad "R10 미등록 provider ($OUT)"
[ "$RC" -eq 3 ] && ok "R10 rc3(일부 실패)" || bad "R10 rc3 (rc=$RC)"

# ── 변이 1: rc3 → rc0 으로 망가뜨린 사본은 R2 칸이 빨강이어야 한다 ─────────────
if [ "${1:-}" = "--mutate" ]; then
  M="$TMP/mut"; mkdir -p "$M"
  sed 's/    return 2 if len(bad) == len(out) else 3/    return 0/' "$TOOL" > "$M/ft-acct-usage.sh"
  if cmp -s "$TOOL" "$M/ft-acct-usage.sh"; then bad "변이 적용 실패"
  else
    TOOL="$M/ft-acct-usage.sh"; run "$B" "$(newdir r2m)"
    [ "$RC" -ne 3 ] && ok "변이 FAIL(rc3 상실 → rc=$RC)" || bad "변이를 시험이 못 잡음"
  fi
fi

echo "fail=$fail"; [ "$fail" -eq 0 ]
