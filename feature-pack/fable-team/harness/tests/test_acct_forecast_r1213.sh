#!/usr/bin/env bash
# test_acct_forecast_r1213.sh — ft-acct-usage.sh 확장(창 전수·관측 시각·잠금·표본) + ft-acct-forecast.sh 반례 R1~R12 + 변이 3
#   bash tests/test_acct_forecast_r1213.sh            # 전 칸
#   bash tests/test_acct_forecast_r1213.sh --mutate   # 변이 3회(각 칸이 빨강인지)
#   bash tests/test_acct_forecast_r1213.sh --mutate 2 # 변이 1개만
# 격리: 임시 HOME·임시 상태 폴더·가짜 auth·가짜 curl(실 네트워크 0)·가상 시각 FT_ACCT_USAGE_NOW · 자기 재호출 0 · 고정 sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../bin/ft-acct-usage.sh"
FC="$HERE/../bin/ft-acct-forecast.sh"
TOOL_KIT="$HERE/../kit/fable-team/bin/ft-acct-usage.sh"
FC_KIT="$HERE/../kit/fable-team/bin/ft-acct-forecast.sh"
NOW=1793400000
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export FT_ACCT_USAGE_NOW="$NOW" FT_ACCT_USAGE_CURL="curl"
hhmm() { python3 -c "import datetime as d,sys;print(d.datetime.fromtimestamp(float(sys.argv[1])).strftime('%H:%M'))" "$1"; }
iso()  { python3 -c "import datetime as d,sys;print(d.datetime.fromtimestamp(float(sys.argv[1]),d.timezone.utc).isoformat(timespec='seconds'))" "$1"; }

# ── 가짜 curl: 호출 기록 · 토큰별 상태/본문 ──────────────────────────────────
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env python3
import os, sys
a = sys.argv[1:]
url = next((x for x in a if x.startswith("http")), "")
tok = ""
for i, x in enumerate(a):
    if x == "-H" and a[i + 1].lower().startswith("authorization:"):
        tok = a[i + 1].split("Bearer ", 1)[-1].strip()
d = os.environ["FAKE_DIR"]
open(os.path.join(d, "log"), "a").write(tok + "\t" + url + "\n")
code = "200"
p = os.path.join(d, "status." + tok)
if os.path.exists(p):
    code = open(p).read().strip()
body = "{}"
p = os.path.join(d, "body." + tok)
if os.path.exists(p):
    body = open(p).read()
sys.stdout.write(body.rstrip("\n") + "\n" + code)
EOF
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
FAKE_DIR="$TMP/fake"; mkdir -p "$FAKE_DIR"; export FAKE_DIR
: > "$FAKE_DIR/log"

mk_auth() { # $1=폴더 $2=파일이름 $3=token [$4=disabled]
  printf '{"type":"claude","access_token":"%s","refresh_token":"rt-%s","expired":"2030-01-01T00:00:00+09:00","disabled":%s}\n' \
    "$3" "$3" "${4:-false}" > "$1/$2"
}
newdir() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }
body() { printf '%s\n' "$2" > "$FAKE_DIR/body.$1"; }
run_usage() { # $1=auth dir $2=state dir [args…] → OUT·RC·ERR
  local d="$1" s="$2"; shift 2
  OUT="$(FT_ACCT_USAGE_AUTH_DIR="$d" FT_ACCT_USAGE_STATE="$s" bash "$TOOL" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
  CUR_STATE="$s"; CUR_AUTH="$d"
}
run_fc() { # $1=auth dir $2=state dir [args…] → OUT·RC·ERR
  local d="$1" s="$2"; shift 2
  OUT="$(FT_ACCT_USAGE_AUTH_DIR="$d" FT_ACCT_USAGE_STATE="$s" bash "$FC" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
  CUR_STATE="$s"; CUR_AUTH="$d"
}
jget() { # $1=json $2=python 식(rows 변수) — 참이면 0
  printf '%s' "$1" | python3 -c "
import json,sys
rows=json.load(sys.stdin)
sys.exit(0 if ($2) else 1)"
}
calls() { grep -c . "$FAKE_DIR/log" 2>/dev/null || echo 0; }
samples() { printf '%s/samples.tsv' "$1"; }

# ── R1 창 전수 = limits[] 원소마다 · 캐시·json·표 · 기존 열 불변 ──────────────
W4='{"limits":[
 {"kind":"session","percent":12,"resets_at":"2026-10-31T10:00:00+00:00","scope":null},
 {"kind":"weekly_all","percent":20,"resets_at":"2026-11-04T05:59:59+00:00","scope":null},
 {"kind":"weekly_scoped","percent":30,"resets_at":"2026-11-04T06:00:00+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}},
 {"kind":"weekly_scoped","percent":31,"resets_at":"2026-11-04T06:00:01+00:00","scope":{"model":{"id":null,"display_name":"Opus"},"surface":null}}]}'
chip_r1() {
  local A S J n
  A="$(newdir r1)"; S="$(newdir r1s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a "$W4"
  run_usage "$A" "$S" --json
  J="$OUT"
  jget "$J" 'len(rows[0]["windows"])==4' && ok "R1 windows 4항목" || bad "R1 windows 4항목 ($J)"
  jget "$J" '[w["scope"]["model"]["display_name"] for w in rows[0]["windows"] if w["scope"]]==["Fable","Opus"]' \
    && ok "R1 scope 값 보존(모델별 2창)" || bad "R1 scope 보존"
  jget "$(cat "$S/cache.json")" 'len(list(json.loads(json.dumps(rows)).values())[0]["row"]["windows"])==4' \
    && ok "R1 캐시 행 windows 4" || bad "R1 캐시 행 windows"
  run_usage "$A" "$S"
  n="$(printf '%s\n' "$OUT" | grep -c '^claude')"
  [ "$n" -eq 1 ] && ok "R1 표 계정 행 수 그대로(1)" || bad "R1 표 계정 행 수 ($n)"
  jget "$(FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" --json)" 'len(rows[0]["windows"])==4' \
    && ok "R1 --json windows 4" || bad "R1 --json windows"
  run_usage "$A" "$S" --windows
  n="$(printf '%s\n' "$OUT" | grep -c 'weekly_scoped')"
  [ "$n" -eq 2 ] && ok "R1 --windows 표 창 행" || bad "R1 --windows 표 ($n)"
}

# ── R6·R7·R8 공용: 표본 주입 ───────────────────────────────────────────────
put_sample() { # $1=state $2=at $3=key $4=kind $5=scope $6=percent $7=resets_at
  printf '%s\tclaude\t%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" "$7" >> "$(samples "$1")"
}

# ── R2 재귀 마스킹·결측·구형 캐시 ─────────────────────────────────────────
chip_r2() {
  local A S
  A="$(newdir r2)"; S="$(newdir r2s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json TOK-R2
  body TOK-R2 '{"limits":[{"kind":"session","percent":0,"resets_at":"TOK-R2-rst","scope":null},
                          {"kind":"weekly_all","percent":null,"resets_at":null,"scope":null}]}'
  run_usage "$A" "$S" --windows
  { printf '%s' "$OUT"; printf '%s' "$ERR"; cat "$S"/*.json "$(samples "$S")" 2>/dev/null; } | grep -q 'TOK-R2' \
    && bad "R2 창 안 토큰 노출" || ok "R2 창 안 토큰 0(출력·캐시·표본)"
  printf '%s\n' "$OUT" | grep -q '근거 없음' && ok "R2 null 리셋 = 근거 없음" || bad "R2 null 리셋 ($OUT)"
  jget "$(FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" --json)" \
    'rows[0]["windows"][0]["percent"]==0' && ok "R2 관측된 0 은 0 그대로" || bad "R2 0 보존"
  printf '{"%s":{"at":%s,"row":{"provider":"claude","account":"%s","result":"OK"}}}\n' \
    "aaaa1111-x…b" "$NOW" "aaaa1111-x…b" > "$S/cache.json"
  run_usage "$A" "$S" --json
  jget "$OUT" 'rows[0]["windows"]=="근거 없음(구형 캐시)"' && ok "R2 구형 캐시 문구" || bad "R2 구형 캐시 문구 ($OUT)"
}

# ── R3 표본 1개 → 근거 없음(표본) · 풀림은 resets_at 그대로 · rc0 ────────────
chip_r3() {
  local A S J
  A="$(newdir r3)"; S="$(newdir r3s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a '{"limits":[{"kind":"weekly_all","percent":50,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  run_usage "$A" "$S" >/dev/null
  run_fc "$A" "$S" --json
  J="$OUT"
  [ "$RC" -eq 0 ] && ok "R3 rc0" || bad "R3 rc0 (rc=$RC)"
  jget "$J" 'rows[0]["windows"][0]["windows"][0]["why"]=="표본"' && ok "R3 근거 없음(표본)" || bad "R3 근거 없음(표본) ($J)"
  jget "$J" 'rows[0]["windows"][0]["windows"][0]["resets_at"]=="2026-11-04T05:59:59+00:00"' \
    && ok "R3 풀림 = resets_at 그대로" || bad "R3 resets_at 보존"
}

# ── R4 표본 2개(40→50 · 1시간) → 시간당 10% · 소진 예상 +4h48m ──────────────
chip_r4() {
  local A S J exp
  A="$(newdir r4)"; S="$(newdir r4s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a '{"limits":[{"kind":"weekly_all","percent":50,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  put_sample "$S" $((NOW - 3600)) aaaa1111 weekly_all "" 40.00 '2026-11-04T05:59:59+00:00'
  run_usage "$A" "$S" >/dev/null
  run_fc "$A" "$S" --json
  J="$OUT"; exp=$((NOW + 17280))
  jget "$J" "abs(rows[0]['windows'][0]['windows'][0]['eta']-$exp)<2" \
    && ok "R4 소진 예상 +4h48m" || bad "R4 소진 예상 ($J)"
  jget "$J" "rows[0]['windows'][0]['windows'][0]['why']=='시간당 10.0%'" && ok "R4 속도 시간당 10%" || bad "R4 속도 문구 ($J)"
  run_fc "$A" "$S"
  printf '%s\n' "$OUT" | head -1 | grep -q "$(hhmm $((NOW + 17280)))" && ok "R4 머리 줄 HH:MM 일치" || bad "R4 머리 줄 ($OUT)"
}

# ── R5 간격 30초 · 감소 뒤 표본 1개 · 감소 뒤 2개 · 리셋 바뀐 옛 표본 제외 ──
chip_r5() {
  local A S J
  A="$(newdir r5)"; S="$(newdir r5s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a '{"limits":[{"kind":"weekly_all","percent":50,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  put_sample "$S" $((NOW - 30)) aaaa1111 weekly_all "" 40.00 '2026-11-04T05:59:59+00:00'
  run_usage "$A" "$S" >/dev/null; run_fc "$A" "$S" --json
  jget "$OUT" 'rows[0]["windows"][0]["windows"][0]["why"]=="간격"' && ok "R5 근거 없음(간격)" || bad "R5 간격 ($OUT)"
  # 감소 40→70→60 · 감소 뒤 표본 1개
  S="$(newdir r5s2)"; rm -rf "$S"; mkdir -p "$S"
  put_sample "$S" $((NOW - 7200)) aaaa1111 weekly_all "" 40.00 '2026-11-04T05:59:59+00:00'
  put_sample "$S" $((NOW - 3600)) aaaa1111 weekly_all "" 70.00 '2026-11-04T05:59:59+00:00'
  body tok-a '{"limits":[{"kind":"weekly_all","percent":60,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  run_usage "$A" "$S" >/dev/null; run_fc "$A" "$S" --json
  jget "$OUT" 'rows[0]["windows"][0]["windows"][0]["why"]=="감소"' && ok "R5 근거 없음(감소)" || bad "R5 감소 ($OUT)"
  # 감소 뒤 표본 2개 더(60→65→70) → 속도가 선다
  S="$(newdir r5s3)"; rm -rf "$S"; mkdir -p "$S"
  put_sample "$S" $((NOW - 7200)) aaaa1111 weekly_all "" 40.00 '2026-11-04T05:59:59+00:00'
  put_sample "$S" $((NOW - 3600)) aaaa1111 weekly_all "" 70.00 '2026-11-04T05:59:59+00:00'
  put_sample "$S" $((NOW - 1800)) aaaa1111 weekly_all "" 60.00 '2026-11-04T05:59:59+00:00'
  put_sample "$S" $((NOW - 900)) aaaa1111 weekly_all "" 65.00 '2026-11-04T05:59:59+00:00'
  body tok-a '{"limits":[{"kind":"weekly_all","percent":70,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  run_usage "$A" "$S" >/dev/null; run_fc "$A" "$S" --json
  jget "$OUT" 'abs(float(rows[0]["windows"][0]["windows"][0]["why"].split()[1].rstrip("%"))-20.0)<0.2' \
    && ok "R5 감소 뒤 2개 = 시간당 20%" || bad "R5 감소 뒤 속도 ($OUT)"
  # resets_at 이 바뀌면 옛 표본은 다른 창이다
  S="$(newdir r5s4)"; rm -rf "$S"; mkdir -p "$S"
  put_sample "$S" $((NOW - 7200)) aaaa1111 weekly_all "" 40.00 '2026-10-31T05:59:59+00:00'
  put_sample "$S" $((NOW - 3600)) aaaa1111 weekly_all "" 45.00 '2026-10-31T05:59:59+00:00'
  run_usage "$A" "$S" >/dev/null; run_fc "$A" "$S" --json
  jget "$OUT" 'rows[0]["windows"][0]["windows"][0]["why"]=="표본"' && ok "R5 리셋 바뀐 옛 표본 제외" || bad "R5 리셋 제외 ($OUT)"
}

# ── R6 관측 시각 기준(30초 밀림 0) · 재조회 필요 ────────────────────────────
chip_r6() {
  local A S J
  A="$(newdir r6)"; S="$(newdir r6s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a '{"limits":[{"kind":"weekly_all","percent":50,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  put_sample "$S" $((NOW - 3630)) aaaa1111 weekly_all "" 40.00 '2026-11-04T05:59:59+00:00'
  FT_ACCT_USAGE_NOW=$((NOW - 30)) run_usage "$A" "$S" >/dev/null
  run_fc "$A" "$S" --json   # 캐시 적중(30초) → 관측 시각 = NOW-30
  J="$OUT"
  jget "$J" "abs(rows[0]['windows'][0]['windows'][0]['eta']-($NOW-30+17280))<2" \
    && ok "R6 관측 시각 기준(밀림 0)" || bad "R6 관측 기준 ($J)"
  # 캐시 유효 중 리셋이 지났다 → 재조회 필요 · 가용에 안 셈 · 과거 시각 0
  S="$(newdir r6s2)"
  body tok-a "{\"limits\":[{\"kind\":\"weekly_all\",\"percent\":50,\"resets_at\":\"$(iso $((NOW - 1800)))\",\"scope\":null}]}"
  FT_ACCT_USAGE_NOW=$((NOW - 60)) run_usage "$A" "$S" >/dev/null
  run_fc "$A" "$S"
  printf '%s\n' "$OUT" | grep -q '재조회 필요' && ok "R6 재조회 필요" || bad "R6 재조회 필요 ($OUT)"
  printf '%s\n' "$OUT" | grep -q '가용 0/1' && ok "R6 가용에 안 셈" || bad "R6 가용 ($OUT)"
  printf '%s\n' "$OUT" | grep -q "$(hhmm $((NOW - 1800)))" && bad "R6 과거 시각 출력" || ok "R6 과거 시각 0"
}

# ── R7 공통+모델 창 · scope 미상 ────────────────────────────────────────────
chip_r7() {
  local A S
  A="$(newdir r7)"; S="$(newdir r7s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  mk_auth "$A" claude-bbbb2222-x@byourz.com.json tok-b
  body tok-a '{"limits":[{"kind":"session","percent":100,"resets_at":"2026-10-31T12:00:00+00:00","scope":null},
                          {"kind":"weekly_scoped","percent":40,"resets_at":"2026-11-04T06:00:00+00:00","scope":{"model":{"display_name":"A"}}}]}'
  body tok-b '{"limits":[{"kind":"weekly_scoped","percent":10,"resets_at":"2026-11-04T06:00:00+00:00","scope":null}]}'
  run_fc "$A" "$S" --model A
  printf '%s\n' "$OUT" | grep -q '소진(공통 창)' && ok "R7 소진(공통 창)" || bad "R7 소진(공통 창) ($OUT)"
  printf '%s\n' "$OUT" | grep -q '가용 0/2' && ok "R7 가용 0" || bad "R7 가용 0 ($OUT)"
  printf '%s\n' "$OUT" | grep -q '근거 없음(scope)' && ok "R7 근거 없음(scope)" || bad "R7 scope 미상 ($OUT)"
}

# ── R8 계정 풀림 · 풀 풀림 · 풀 전체 소진 근거 없음 ─────────────────────────
chip_r8() {
  local A S J
  A="$(newdir r8)"; S="$(newdir r8s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  mk_auth "$A" claude-bbbb2222-x@byourz.com.json tok-b
  mk_auth "$A" claude-cccc3333-x@byourz.com.json tok-c
  body tok-a '{"limits":[{"kind":"session","percent":100,"resets_at":"2026-10-31T09:40:00+00:00","scope":null},
                          {"kind":"weekly_all","percent":100,"resets_at":"2026-11-01T02:00:00+00:00","scope":null}]}'
  body tok-b '{"limits":[{"kind":"weekly_all","percent":100,"resets_at":"2026-10-31T06:00:00+00:00","scope":null}]}'
  body tok-c '{"limits":[{"kind":"weekly_all","percent":40,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  put_sample "$S" $((NOW - 3600)) cccc3333 weekly_all "" 30.00 '2026-11-04T05:59:59+00:00'
  run_usage "$A" "$S" --json >/dev/null
  J="$(FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" --json)"
  run_fc "$A" "$S" --json
  jget "$OUT" 'rows[0]["available"]==1 and rows[0]["accounts"]==3' && ok "R8 가용 1/3" || bad "R8 가용 ($OUT)"
  jget "$J" 'True' && ok "R8 (조회 정상)" || bad "R8 조회"
  printf '%s\n' "$OUT" | python3 -c '
import json,sys,datetime as d
p=json.load(sys.stdin)[0]
acc={a["account"]:a for a in p["rows"]}
want=d.datetime(2026,11,1,2,0,tzinfo=d.timezone.utc).timestamp()
one=[a for k,a in acc.items() if k.startswith("aaaa1111")][0]
ok = one["free"] is not None and abs(d.datetime.fromisoformat(one["free"]).timestamp()-want)<2
ok = ok and p["earliest"] is not None and p["earliest"]["account"].startswith("cccc3333")
ok = ok and p["pool_reset"] is not None
sys.exit(0 if ok else 1)' && ok "R8 계정 풀림=가장 늦은 리셋 · 가장 이른 소진=정상 계정" || bad "R8 풀림·가장 이른 ($OUT)"
  jget "$OUT" 'rows[0]["pool_exhaust"]=="근거 없음(배정 순서)"' && ok "R8 풀 전체 소진 = 근거 없음(배정 순서)" || bad "R8 배정 순서"
}

# ── R9 시각 주입 0 유효 · 시계 역행 · 미래 표본 제외 ───────────────────────
chip_r9() {
  local A S n
  A="$(newdir r9)"; S="$(newdir r9s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a '{"limits":[{"kind":"weekly_all","percent":50,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  : > "$FAKE_DIR/log"
  FT_ACCT_USAGE_NOW=0 run_usage "$A" "$S"
  [ "$RC" -eq 0 ] && ok "R9 NOW=0 유효(rc0)" || bad "R9 NOW=0 (rc=$RC $OUT)"
  jget "$(FT_ACCT_USAGE_NOW=0 FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" --json)" \
    'rows[0]["windows"][0]["observed_at"].startswith("1970-01-01")' && ok "R9 observed_at = epoch 0" || bad "R9 observed_at"
  # 시계 역행: 캐시 at 이 미래 → 캐시 무시 + 재조회 1
  n="$(calls)"
  FT_ACCT_USAGE_NOW=$((NOW + 300)) run_usage "$A" "$S" >/dev/null
  [ "$(calls)" -gt "$n" ] && ok "R9 시계 역행 → 캐시 무시 + 재조회" || bad "R9 시계 역행"
  # 미래 표본 제외 — 미래 표본(90%)이 섞이면 속도가 42%대로 나온다(10% = 제외됨)
  S="$(newdir r9s2)"
  put_sample "$S" $((NOW - 3600)) aaaa1111 weekly_all "" 40.00 '2026-11-04T05:59:59+00:00'
  put_sample "$S" $((NOW + 600)) aaaa1111 weekly_all "" 90.00 '2026-11-04T05:59:59+00:00'
  run_usage "$A" "$S" >/dev/null; run_fc "$A" "$S" --json
  jget "$OUT" 'rows[0]["windows"][0]["windows"][0]["why"]=="시간당 10.0%"' && ok "R9 미래 표본 제외" || bad "R9 미래 표본 ($OUT)"
}

# ── R10 rc 전파: 단문 rc2 · 전 계정 429 rc2 · rc3 행 ───────────────────────
chip_r10() {
  local A S
  run_fc "$TMP/없는폴더" "$(newdir r10s)"
  [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q '판정 불가 auth 폴더' && ok "R10 단문 1줄 rc2" || bad "R10 단문 ($RC $OUT)"
  A="$(newdir r10)"; S="$(newdir r10s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-429
  echo 429 > "$FAKE_DIR/status.tok-429"
  run_fc "$A" "$S"
  [ "$RC" -eq 2 ] && printf '%s\n' "$OUT" | grep -q '판정 불가 전 계정' && ok "R10 전 계정 429 접기 rc2" \
    || bad "R10 전 계정 429 ($RC $OUT)"
  S="$(newdir r10s2)"
  mk_auth "$A" claude-bbbb2222-x@byourz.com.json tok-ok
  body tok-ok '{"limits":[{"kind":"weekly_all","percent":20,"resets_at":"2026-11-04T05:59:59+00:00","scope":null}]}'
  run_fc "$A" "$S" --json
  [ "$RC" -eq 3 ] && ok "R10 rc3(일부)" || bad "R10 rc3 (rc=$RC)"
  jget "$OUT" '[a["judge"] for a in rows[0]["rows"]].count("판정 불가")==1 and rows[0]["available"]==1' \
    && ok "R10 판정 불가 행 분리 + 가용 1" || bad "R10 판정 불가 행 ($OUT)"
}

# ── R11 잠금: 동시 실행 중복 조회 0 · 표본 유실·중복 0 · 잠금 초과 rc3 ─────
chip_r11() {
  local A S J n
  A="$(newdir r11)"; S="$(newdir r11s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  body tok-a "$W4"
  : > "$FAKE_DIR/log"
  FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" >/dev/null 2>&1 &
  FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" >/dev/null 2>&1 &
  wait
  n="$(calls)"
  [ "$n" -eq 1 ] && ok "R11 동시 실행 조회 1회(중복 0)" || bad "R11 동시 실행 조회 ($n)"
  n="$(grep -c . "$(samples "$S")")"
  [ "$n" -eq 4 ] && ok "R11 표본 4행(관측×창 수)" || bad "R11 표본 행 ($n)"
  # 잠금 8초 점유 → 두 번째는 «판정 불가 잠금» rc3 (대기 상한은 시험 env 로 1초)
  python3 - "$S" <<'PY' &
import fcntl, sys, time
fh = open(sys.argv[1] + "/lock", "a+")
fcntl.flock(fh, fcntl.LOCK_EX)
time.sleep(8)
PY
  sleep 0.4
  FT_ACCT_LOCK_WAIT=1 run_usage "$A" "$S"
  printf '%s\n' "$OUT" | grep -q '판정 불가 잠금' && [ "$RC" -eq 3 ] && ok "R11 잠금 초과 rc3" \
    || bad "R11 잠금 초과 ($RC $OUT)"
  wait
}

# ── R12 표본 키·접기·영속 기본 폴더 ─────────────────────────────────────────
chip_r12() {
  local A S n keys
  A="$(newdir r12)"; S="$(newdir r12s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
  mk_auth "$A" claude-aaaa1111-x@bmail.com.json tok-b   # 짧은 id 충돌(-2) 후보
  body tok-a "$W4"; body tok-b "$W4"
  run_usage "$A" "$S" >/dev/null
  keys="$(cut -f3 "$(samples "$S")" | sort -u | tr '\n' ' ')"
  printf '%s' "$keys" | grep -q '^aaaa1111' && ok "R12 표본 키 = uuid" || bad "R12 표본 키 ($keys)"
  printf '%s' "$keys" | grep -q '@' && bad "R12 표본 키에 이메일" || ok "R12 표본 키에 이메일 0"
  n="$(cut -f3 "$(samples "$S")" | sort -u | grep -c .)"
  [ "$n" -eq 2 ] && ok "R12 짧은 id 충돌 → 표본 키 다름" || bad "R12 충돌 키 ($keys)"
  rm -f "$A/claude-aaaa1111-x@bmail.com.json"
  S="$(newdir r12s2)"
  put_sample "$S" $((NOW - 86400 * 31)) aaaa1111 weekly_all "" 90.00 ''    # 31일 전 = 버린다
  local i
  for i in $(seq 1 250); do put_sample "$S" $((NOW - i)) "old${i}" weekly_all "" 50.00 ''; done
  FT_ACCT_SAMPLES_MAX=200 run_usage "$A" "$S" >/dev/null
  n="$(grep -c . "$(samples "$S")")"
  [ "${n}" -le 200 ] && ok "R12 상한 접기(${n}≤200)" || bad "R12 상한 접기 (${n})"
  grep -q 'old250' "$(samples "$S")" && bad "R12 오래된 행 안 버림" || ok "R12 오래된 행부터 버림"
  grep -q "$(printf '%s\t' $((NOW - 86400 * 31)))" "$(samples "$S")" && bad "R12 31일 전 행 잔존" || ok "R12 31일 전 행 제거"
  # 영속 기본 폴더 = <리포 루트>/.fable-team/state/acct-usage
  local R; R="$(newdir r12repo)"; mkdir -p "$R/.fable-team"; git -C "$R" init -q 2>/dev/null
  ( cd "$R" && FT_ACCT_USAGE_AUTH_DIR="$A" bash "$TOOL" >/dev/null 2>&1 )
  [ -f "$R/.fable-team/state/acct-usage/cache.json" ] && ok "R12 기본 상태 폴더 = 루트/.fable-team/state/acct-usage" \
    || bad "R12 기본 상태 폴더"
}

# ── ⓚ bin·kit 같음 · 기준판(origin/main) 14 값 동일 · 회귀 ─────────────────
chip_k() {
  local A S base
  bash -n "$TOOL" && ok "bash -n usage" || bad "bash -n usage"
  bash -n "$FC" && ok "bash -n forecast" || bad "bash -n forecast"
  { [ -f "$TOOL_KIT" ] && cmp -s "$TOOL" "$TOOL_KIT"; } && ok "bin·kit cmp0 usage" || bad "bin·kit cmp0 usage"
  { [ -f "$FC_KIT" ] && cmp -s "$FC" "$FC_KIT"; } && ok "bin·kit cmp0 forecast" || bad "bin·kit cmp0 forecast"
  base="$TMP/baseline-usage.sh"
  # 기준판 = 팩 origin/main 의 r1183 판 고정 40hex(떠다니는 이름 금지 · r1132)
  if git -C "$HERE/.." show 4580028c98de911a180c4ec2d5b9ab4925ce807a:feature-pack/fable-team/harness/bin/ft-acct-usage.sh > "$base" 2>/dev/null; then
    A="$(newdir rk)"; S="$(newdir rks)"
    mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a
    body tok-a "$W4"
    local newj oldj
    newj="$(FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S" bash "$TOOL" --json)"
    S2="$(newdir rks2)"
    oldj="$(FT_ACCT_USAGE_AUTH_DIR="$A" FT_ACCT_USAGE_STATE="$S2" bash "$base" --json)"
    python3 - "$oldj" "$newj" <<'PY' && ok "기준판 14 값 같음" || bad "기준판 14 값"
import json, sys
old, new = json.loads(sys.argv[1])[0], json.loads(sys.argv[2])[0]
keys = ["provider", "account", "limit", "used", "remaining", "spent", "reset_at", "unit", "result",
        "five_hour", "seven_day", "reset_5h", "reset_7d", "credits"]
sys.exit(0 if all(old.get(k) == new.get(k) for k in keys) else 1)
PY
  else
    bad "기준판(4580028c r1183) 없음"
  fi
}

chips() { chip_r1; chip_r2; chip_r3; chip_r4; chip_r5; chip_r6; chip_r7; chip_r8; chip_r9; chip_r10; chip_r11; chip_r12; chip_k; }

# ── 변이 3: 고친 자리 하나씩 망가뜨려 그 칸이 빨강인지 ──────────────────────
mutate_apply() { # $1=변이 번호 $2=대상 폴더
  python3 - "$2" "$1" <<'PY'
import os, sys
d, n = sys.argv[1], sys.argv[2]
M = {
 "1": ("bin/ft-acct-usage.sh",
       '            if not isinstance(x, dict):\n                continue\n            out.append({"kind": x.get("kind")',
       '            if not isinstance(x, dict) or str(x.get("kind") or "").endswith("_scoped"):\n                continue\n            out.append({"kind": x.get("kind")'),
 "2": ("bin/ft-acct-forecast.sh", 'or "98")', 'or "100")'),
 "3": ("bin/ft-acct-forecast.sh",
       "eta = (obs if obs is not None else NOW) + (FULL - pct) / rate * 3600.0",
       "eta = NOW + (FULL - pct) / rate * 3600.0"),
}
rel, old, new = M[n]
p = os.path.join(d, rel)
s = open(p, encoding="utf-8").read()
if old not in s:
    print("MUTATION-APPLY-FAIL " + n); sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

mutate_one() {
  local n="$1"
  local d="$TMP/mut$n" before
  mkdir -p "$d/bin"
  cp "$TOOL" "$FC" "$d/bin/"
  mutate_apply "$n" "$d" || { bad "변이 M$n 적용 실패"; return; }
  TOOL="$d/bin/ft-acct-usage.sh"; FC="$d/bin/ft-acct-forecast.sh"; before=$fail
  case "$n" in
    1) chip_r1 ;;
    2) chip_r4 ;;
    3) chip_r6 ;;
  esac
  [ "$fail" -gt "$before" ] && ok "변이 M$n FAIL(칸이 잡음)" || bad "변이 M$n 를 칸이 못 잡음"
  fail=$before
}

if [ "${1:-}" = "--mutate" ]; then
  if [ -n "${2:-}" ]; then mutate_one "$2"
  else
    for n in 1 2 3; do
      out="$(bash "${BASH_SOURCE[0]}" --mutate "$n" 2>&1)"; rc=$?
      printf '%s\n' "$out" | grep -E '^(PASS|FAIL) 변이 M' || true
      [ "$rc" -eq 0 ] || bad "변이 M$n 실행 rc=$rc"
    done
  fi
else
  chips
fi
echo "fail=$fail"; [ "$fail" -eq 0 ]
