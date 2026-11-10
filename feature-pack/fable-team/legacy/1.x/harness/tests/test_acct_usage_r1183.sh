#!/usr/bin/env bash
# test_acct_usage_r1183.sh — ft-acct-usage.sh 반례 R1~R10 + DA 반송 D1~D7 + 변이 6 (r1183 · 가짜 curl·가짜 auth·임시 HOME · 실 호출 0)
#   bash tests/test_acct_usage_r1183.sh            # 전 칸
#   bash tests/test_acct_usage_r1183.sh --mutate   # 변이 6회(각 칸이 빨강인지)
#   bash tests/test_acct_usage_r1183.sh --mutate 3 # 변이 1개만
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

# ── 가짜 curl: 호출 기록 + 토큰별 상태/본문/지연(-m 무시 모드 지원) ─────────────
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
open(os.path.join(d, "log"), "a").write(f"{time.time():.3f}\t" + tok + "\t" + url + "\n")
mt = 0.0
for i, x in enumerate(a):
    if x == "-m" and i + 1 < len(a):
        mt = float(a[i + 1])
p = os.path.join(d, "delay." + tok)
delay = float(open(p).read().strip()) if os.path.exists(p) else 0.0
if mt and delay >= mt and not os.path.exists(os.path.join(d, "ignore_m")):
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
  printf '{"type":"claude","access_token":"%s","refresh_token":"rt-%s","email":"x@example.com","expired":"%s","disabled":%s,"account_id":"%s"}\n' \
    "$3" "$3" "$4" "$5" "${6:-}" > "$1/$2"
}
newdir() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }
run() { # $1=auth dir $2=state dir [args…] — OUT·ERR·RC·CUR_STATE
  local d="$1" s="$2"; shift 2
  CUR_STATE="$s"
  OUT="$(FT_ACCT_USAGE_AUTH_DIR="$d" FT_ACCT_USAGE_STATE="$s" bash "$TOOL" "$@" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"
}
calls() { wc -l < "$FAKE_DIR/log" 2>/dev/null | tr -d ' ' || echo 0; }
jq_row() { # $1=auth dir $2=state dir $3=account prefix — 그 행 JSON
  FT_ACCT_USAGE_AUTH_DIR="$1" FT_ACCT_USAGE_STATE="$2" bash "$TOOL" --json --account "$3" 2>/dev/null
}
leak_check() { # $1=칸 이름 · 나머지=비밀 문자열 — 그 실행의 stdout·stderr·캐시를 따로 grep
  local lb="$1"; shift; local hit=""
  for t in "$@"; do
    { printf '%s' "$OUT"; printf '%s' "$ERR"; cat "$CUR_STATE"/*.json 2>/dev/null; } | grep -q -- "$t" && hit="$hit $t"
  done
  [ -z "$hit" ] && ok "$lb 비밀 0(stdout·stderr·캐시)" || bad "$lb 비밀 노출:$hit"
}

chip_r1() { # 정상 4파일(claude 3 · codex 1) → 4행 rc0 · 이메일 전문 0
  local A S; A="$(newdir r1)"; S="$(newdir r1s)"
  mk_auth "$A" claude-aaaa1111-yoonhwan.ko@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
  mk_auth "$A" claude-bbbb2222-developer.ts@byourz.com.json tok-b 2030-01-01T00:00:00+09:00 false
  mk_auth "$A" claude-cccc3333-admin.ts@byourz.com.json tok-c 2030-01-01T00:00:00+09:00 false
  printf '{"type":"codex","access_token":"tok-d","expired":"2030-01-01T00:00:00+09:00","disabled":false,"account_id":"acc-d"}\n' \
    > "$A/codex-dddd4444-yoonhwan.ko@gmail.com-pro.json"
  cp "$FAKE_DIR/codex.json" "$FAKE_DIR/body.tok-d"
  run "$A" "$S"
  [ "$RC" -eq 0 ] && ok "R1 rc0" || bad "R1 rc0 (rc=$RC)"
  [ "$(printf '%s\n' "$OUT" | grep -c '^claude\|^codex')" -eq 4 ] && ok "R1 4행" || bad "R1 4행 ($OUT)"
  printf '%s\n' "$OUT" | grep -q 'yoonhwan' && bad "R1 이메일 전문 노출" || ok "R1 이메일 전문 0"
  printf '%s\n' "$OUT" | grep -q '40' && ok "R1 5시간 % 표시" || bad "R1 5시간 % 표시"
  printf '%s\n' "$OUT" | grep -qi 'codex.*55' && ok "R1 codex 7일 % 표시" || bad "R1 codex 7일 % 표시"
  leak_check R1 tok-a tok-b tok-c tok-d
}

chip_r2() { # 한 계정 429 → 그 행 판정 불가 · 나머지 정상 · rc3
  local B SB; B="$(newdir r2)"; SB="$(newdir r2s)"
  mk_auth "$B" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
  mk_auth "$B" claude-bbbb2222-x@byourz.com.json tok-429 2030-01-01T00:00:00+09:00 false
  echo 429 > "$FAKE_DIR/status.tok-429"
  run "$B" "$SB"
  [ "$RC" -eq 3 ] && ok "R2 rc3" || bad "R2 rc3 (rc=$RC)"
  printf '%s\n' "$OUT" | grep -q '429' && ok "R2 429 행" || bad "R2 429 행"
  printf '%s\n' "$OUT" | grep -q 'OK' && ok "R2 나머지 정상" || bad "R2 나머지 정상"
  leak_check R2 tok-a tok-429
}

chip_r3() { # 부모가 시간을 끊는다 — -m 을 무시하는 curl 이어도 7초 + 재시도 1 · 배치 상한
  local C SC; C="$(newdir r3)"; SC="$(newdir r3s)"
  mk_auth "$C" claude-aaaa1111-x@byourz.com.json tok-slow 2030-01-01T00:00:00+09:00 false
  echo 11 > "$FAKE_DIR/delay.tok-slow"; : > "$FAKE_DIR/ignore_m"
  : > "$FAKE_DIR/log"; local t0 el
  t0=$(date +%s); run "$C" "$SC"; el=$(( $(date +%s) - t0 )); rm -f "$FAKE_DIR/ignore_m"
  printf '%s\n' "$OUT" | grep -q '판정 불가 시간 초과' && ok "R3 시간 초과 판정" || bad "R3 시간 초과 판정 ($OUT)"
  [ "$el" -le 12 ] && ok "R3 배치 상한 10초 안 (${el}s)" || bad "R3 배치 상한 (${el}s)"
}

chip_r4() { # 60초 캐시: 두 번째 호출 0 · 61초 뒤 다시 호출
  local D SD; D="$(newdir r4)"; SD="$(newdir r4s)"
  mk_auth "$D" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
  : > "$FAKE_DIR/log"; run "$D" "$SD"; local n1 n2 n3; n1=$(calls)
  FT_ACCT_USAGE_NOW=$((NOW + 30)) run "$D" "$SD"; n2=$(calls)
  FT_ACCT_USAGE_NOW=$((NOW + 61)) run "$D" "$SD"; n3=$(calls)
  { [ "$n1" -eq 1 ] && [ "$n2" -eq 1 ]; } && ok "R4 60초 안 재조회 0 (n1=$n1 n2=$n2)" || bad "R4 캐시 (n1=$n1 n2=$n2)"
  [ "$n3" -ge 2 ] && ok "R4 61초 뒤 재조회" || bad "R4 61초 뒤 재조회 (n3=$n3)"
}

chip_r5() { # 만료 토큰 → 갱신 호출 0 · 파일 무변경 · «만료 · cliproxy 갱신 대기»
  local E SE f; E="$(newdir r5)"; SE="$(newdir r5s)"; f="$E/claude-aaaa1111-x@byourz.com.json"
  mk_auth "$E" claude-aaaa1111-x@byourz.com.json tok-exp 2020-01-01T00:00:00+09:00 false
  local h0 m0 h1 m1 n
  h0="$(shasum -a 256 "$f" | cut -d' ' -f1)"; m0="$(stat -f %m "$f")"
  : > "$FAKE_DIR/log"; run "$E" "$SE"; n=$(calls)
  h1="$(shasum -a 256 "$f" | cut -d' ' -f1)"; m1="$(stat -f %m "$f")"
  [ "$n" -eq 0 ] && ok "R5 갱신·조회 호출 0" || bad "R5 조회 호출 0 (n=$n)"
  { [ "$h0" = "$h1" ] && [ "$m0" = "$m1" ]; } && ok "R5 auth 파일 해시·mtime 그대로" || bad "R5 auth 파일 무변경"
  printf '%s\n' "$OUT" | grep -q '만료 · cliproxy 갱신 대기' && ok "R5 만료 행" || bad "R5 만료 행"
  leak_check R5 tok-exp
}

chip_r6() { # disabled → 조회 0 · «비활성»
  local F SF; F="$(newdir r6)"; SF="$(newdir r6s)"
  mk_auth "$F" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 true
  : > "$FAKE_DIR/log"; run "$F" "$SF"
  [ "$(calls)" -eq 0 ] && ok "R6 비활성 조회 0" || bad "R6 비활성 조회 0"
  printf '%s\n' "$OUT" | grep -q '비활성' && ok "R6 비활성 행" || bad "R6 비활성 행"
}

chip_r7() { # auth 폴더 없음 → 1줄 rc2 · 빈 표 0
  run "$TMP/없는폴더" "$(newdir r7s)"
  [ "$RC" -eq 2 ] && ok "R7 rc2" || bad "R7 rc2 (rc=$RC)"
  [ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ] && ok "R7 1줄" || bad "R7 1줄 ($OUT)"
  printf '%s\n' "$OUT" | grep -q '판정 불가 auth 폴더' && ok "R7 문구" || bad "R7 문구"
}

chip_r8() { # 비밀 0 — 칸마다 그 실행의 stdout·stderr·캐시를 따로 본다(DA 반송: R7 실행으로 덮이던 것)
  local A S; A="$(newdir r8)"; S="$(newdir r8s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-secret-1 2030-01-01T00:00:00+09:00 false
  printf '{"type":"codex","access_token":"tok-secret-2","expired":"2030-01-01T00:00:00+09:00","disabled":false,"account_id":"acc"}\n' \
    > "$A/codex-bbbb2222-y@byourz.com-pro.json"
  echo 429 > "$FAKE_DIR/status.tok-secret-1"
  run "$A" "$S"
  leak_check R8 tok-secret-1 tok-secret-2
}

chip_r9() { # --json 행마다 같은 키 집합 · 못 준 칸 «근거 없음»
  local A S J
  A="$(newdir r9)"; S="$(newdir r9s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-a 2030-01-01T00:00:00+09:00 false
  printf '{"type":"codex","access_token":"tok-d","expired":"2030-01-01T00:00:00+09:00","disabled":false,"account_id":"acc-d"}\n' \
    > "$A/codex-dddd2222-y@byourz.com-pro.json"
  cp "$FAKE_DIR/codex.json" "$FAKE_DIR/body.tok-d"
  J="$(jq_row "$A" "$S" "")"
  printf '%s' "$J" | python3 -c '
import json,sys
rows=json.load(sys.stdin); keys={tuple(sorted(r)) for r in rows}
need={"provider","account","limit","used","remaining","spent","reset_at","unit","result"}
sys.exit(0 if len(rows)==2 and len(keys)==1 and need<=set(list(keys)[0]) else 1)' \
    && ok "R9 키 집합 동일" || bad "R9 키 집합 동일"
printf '%s' "$J" | grep -q '근거 없음' && ok "R9 못 준 칸 = 근거 없음" || bad "R9 근거 없음 문자열"
}

chip_r10() { # 어댑터 추가 = 본체 수정 0 · 미등록 provider 1줄 · rc3
  local G SG AD sha0 sha1
  G="$(newdir r10)"; SG="$(newdir r10s)"; AD="$(newdir adapters)"
  cat > "$AD/fake.py" <<'EOF'
PROVIDER = "fake"
def fetch(auth, http):
    return {"used": 12, "limit": 100, "remaining": 88, "unit": "%"}
EOF
  mk_auth "$G" fake-eeee5555-x@byourz.com.json tok-f 2030-01-01T00:00:00+09:00 false
  mk_auth "$G" antigravity-x@byourz.com.json tok-g 2030-01-01T00:00:00+09:00 false
  sha0="$(shasum -a 256 "$TOOL" | cut -d' ' -f1)"
  OUT="$(FT_ACCT_USAGE_ADAPTER_DIR="$AD" FT_ACCT_USAGE_AUTH_DIR="$G" FT_ACCT_USAGE_STATE="$SG" bash "$TOOL" 2>"$TMP/err")"; RC=$?
  ERR="$(cat "$TMP/err")"; CUR_STATE="$SG"
  sha1="$(shasum -a 256 "$TOOL" | cut -d' ' -f1)"
  [ "$sha0" = "$sha1" ] && ok "R10 본체 무변경" || bad "R10 본체 무변경"
  printf '%s\n' "$OUT" | grep -q '^fake' && ok "R10 가짜 어댑터 행" || bad "R10 가짜 어댑터 행"
  printf '%s\n' "$OUT" | grep -q '판정 불가 어댑터 없음 antigravity' && ok "R10 미등록 provider 1줄" || bad "R10 미등록 provider"
  [ "$RC" -eq 3 ] && ok "R10 rc3(일부 실패)" || bad "R10 rc3 (rc=$RC)"
}

chip_d1() { # DA1: resets_at 에 토큰이 와도 stdout·캐시에 그대로 나가면 안 된다
  local A S; A="$(newdir d1)"; S="$(newdir d1s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json TOK-D1-SECRET 2030-01-01T00:00:00+09:00 false
  printf '{"five_hour":{"utilization":50,"resets_at":"TOK-D1-SECRET-rst"},"seven_day":null,"limits":[]}\n' > "$FAKE_DIR/body.TOK-D1-SECRET"
  run "$A" "$S"
  leak_check D1 TOK-D1-SECRET
  printf '%s\n' "$OUT" | grep -q '가림' && ok "D1 [가림] 치환" || bad "D1 [가림] 치환 ($OUT)"
  [ "$RC" -eq 0 ] && ok "D1 rc0" || bad "D1 rc0 (rc=$RC)"
}

chip_d2() { # DA2: 응답 꼴이 틀려도 traceback·토큰이 stderr 에 새지 않는다(계정 단위 격리)
  local A S; A="$(newdir d2)"; S="$(newdir d2s)"
  printf '{"type":"codex","access_token":"TOK-D2-SECRET","expired":"2030-01-01T00:00:00+09:00","disabled":false,"account_id":"acc"}\n' \
    > "$A/codex-bbbb1111-y@byourz.com-pro.json"
  mk_auth "$A" claude-aaaa2222-x@byourz.com.json tok-ok 2030-01-01T00:00:00+09:00 false
  printf '{"rate_limit":{"primary_window":{"used_percent":50,"limit_window_seconds":"TOK-D2-SECRET"}}}\n' > "$FAKE_DIR/body.TOK-D2-SECRET"
  run "$A" "$S"
  printf '%s\n' "$OUT" | grep -q '판정 불가 응답 꼴' && ok "D2 판정 불가 응답 꼴" || bad "D2 응답 꼴 행 ($OUT)"
  printf '%s' "$ERR" | grep -q 'Traceback' && bad "D2 traceback" || ok "D2 traceback 0"
  printf '%s\n' "$OUT" | grep -q 'OK' && ok "D2 다른 계정 정상" || bad "D2 다른 계정 정상"
  [ "$RC" -eq 3 ] && ok "D2 rc3" || bad "D2 rc3 (rc=$RC)"
  leak_check D2 TOK-D2-SECRET
}

chip_d3() { # DA3: 창은 limit_window_seconds 로 고르고 · 리셋 값은 그 창 응답값과 «정확히» 같다(순서 가정 0)
  local A S J; A="$(newdir d3)"; S="$(newdir d3s)"
  printf '{"type":"codex","access_token":"tok-w","expired":"2030-01-01T00:00:00+09:00","disabled":false,"account_id":"acc"}\n' \
    > "$A/codex-cccc1111-y@byourz.com-pro.json"
  printf '{"rate_limit":{"primary_window":{"used_percent":30,"limit_window_seconds":18000,"reset_at":1793500000},"secondary_window":{"used_percent":70,"limit_window_seconds":604800,"reset_at":1793900000}}}\n' \
    > "$FAKE_DIR/body.tok-w"
  J="$(jq_row "$A" "$S" "")"
  printf '%s' "$J" | python3 -c '
import json,sys,datetime as dt
r=json.load(sys.stdin)[0]
def iso(e): return dt.datetime.fromtimestamp(e, dt.timezone.utc).isoformat(timespec="seconds")
ok = (r["five_hour"]==30 and r["seven_day"]==70
      and r["reset_5h"]==iso(1793500000) and r["reset_7d"]==iso(1793900000))
sys.exit(0 if ok else 1)' && ok "D3 5h=30 · 7d=70 · 리셋 값 정확히 일치" || bad "D3 창·리셋 매핑 ($J)"
}

chip_d4() { # DA4: 계정 id 에 이메일 전문 0
  local A S J
  A="$(newdir d4)"; S="$(newdir d4s)"
  mk_auth "$A" claude-aaaa1111-abc@example.com.json tok-a 2030-01-01T00:00:00+09:00 false
  J="$(jq_row "$A" "$S" "")"
  printf '%s' "$J" | python3 -c '
import json,sys
a=json.load(sys.stdin)[0]["account"]
sys.exit(0 if "@" not in a and "abc" not in a and len(a)<=20 else 1)' \
    && ok "D4 짧은 id (이메일 전문 0)" || bad "D4 짧은 id ($J)"
}

chip_d5() { # DA5: 한 계정 200 본문 [] → 그 행만 «판정 불가 응답 꼴»(예외 문구 없이) · 나머지 정상 · traceback 0
  local A S; A="$(newdir d5)"; S="$(newdir d5s)"
  mk_auth "$A" claude-aaaa1111-empty@byourz.com.json tok-empty 2030-01-01T00:00:00+09:00 false
  mk_auth "$A" claude-bbbb2222-x@byourz.com.json tok-ok2 2030-01-01T00:00:00+09:00 false
  printf '[]\n' > "$FAKE_DIR/body.tok-empty"
  run "$A" "$S"
  printf '%s\n' "$OUT" | grep -q '판정 불가 응답 꼴 *$' && ok "D5 빈 본문 판정" || bad "D5 빈 본문 판정 ($OUT)"
  printf '%s\n' "$OUT" | grep -q 'AttributeError' && bad "D5 예외 문구가 결과에 실림" || ok "D5 예외 문구 0"
  printf '%s' "$ERR" | grep -q 'Traceback' && bad "D5 traceback" || ok "D5 traceback 0"
  [ "$RC" -eq 3 ] && ok "D5 rc3" || bad "D5 rc3 (rc=$RC)"
}

chip_d6() { # DA6: 429 결과도 60초 캐시 → 두 번째 실행 curl 0
  local A S n1 n2; A="$(newdir d6)"; S="$(newdir d6s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-429c 2030-01-01T00:00:00+09:00 false
  echo 429 > "$FAKE_DIR/status.tok-429c"
  : > "$FAKE_DIR/log"; run "$A" "$S"; n1=$(calls)
  run "$A" "$S"; n2=$(calls)
  [ "$n1" -eq 1 ] && [ "$n2" -eq 1 ] && ok "D6 429 캐시 (n1=$n1 n2=$n2)" || bad "D6 429 캐시 (n1=$n1 n2=$n2)"
  printf '%s\n' "$OUT" | grep -q '429' && ok "D6 캐시에서도 429 행" || bad "D6 429 행"
}

chip_d7() { # DA7: 부모가 «정확히 7초»에 끊고 재시도 1회 · 단일 계정 전체 10초 안
  local A S el n blk tot; A="$(newdir d7)"; S="$(newdir d7s)"
  mk_auth "$A" claude-aaaa1111-x@byourz.com.json tok-hang 2030-01-01T00:00:00+09:00 false
  echo 8 > "$FAKE_DIR/delay.tok-hang"; : > "$FAKE_DIR/ignore_m"; : > "$FAKE_DIR/log"
  local t0 t1; t0="$(python3 -c 'import time;print(f"{time.time():.3f}")')"
  run "$A" "$S"
  t1="$(python3 -c 'import time;print(f"{time.time():.3f}")')"
  read -r blk tot < <(python3 - "$t0" "$t1" "$FAKE_DIR/log" <<'PY'
import sys
t0, t1, log = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
ts = [float(l.split("\t")[0]) for l in open(log) if l.strip()]
print(f"{(ts[1] - ts[0]) if len(ts) > 1 else 0.0:.2f} {t1 - t0:.2f}")
PY
)
  n=$(calls); rm -f "$FAKE_DIR/ignore_m"
  [ "$n" -eq 2 ] && ok "D7 재시도 1회(호출 2)" || bad "D7 재시도 횟수 (n=$n)"
  awk "BEGIN{exit !($blk<=7.2)}" && ok "D7 첫 차단 7.2초 안 (${blk}s)" || bad "D7 첫 차단 (${blk}s)"
  awk "BEGIN{exit !($tot<=10)}" && ok "D7 단일 계정 전체 10초 안 (${tot}s)" || bad "D7 단일 계정 전체 (${tot}s)"
  printf '%s\n' "$OUT" | grep -q '판정 불가 시간 초과' && ok "D7 시간 초과 행" || bad "D7 시간 초과 행"
}

all_chips() {
  bash -n "$TOOL" && ok "bash -n" || bad "bash -n"
  { [ -f "$KIT" ] && cmp -s "$TOOL" "$KIT"; } && ok "bin·kit cmp0" || bad "bin·kit cmp0"
  chip_r1; chip_r2; chip_r3; chip_r4; chip_r5; chip_r6; chip_r7; chip_r8; chip_r9; chip_r10
  chip_d1; chip_d2; chip_d3; chip_d4; chip_d5; chip_d6; chip_d7
}

# ── 변이: 고친 자리 하나씩 망가뜨려 그 칸이 빨강인지 본다 ─────────────────────
mutate_apply() { # $1=원본 $2=사본 $3=변이 번호
  python3 - "$1" "$2" "$3" <<'PY'
import sys
src, dst, n = sys.argv[1], sys.argv[2], sys.argv[3]
M = {
 "1": ("    s = str(text)\n", "    return str(text)  # 변이: 가림 끔\n"),
 "2": ("    except Exception as e:\n        return {\"result\": \"판정 불가 응답 꼴",
       "    except ZeroDivisionError as e:\n        return {\"result\": \"판정 불가 응답 꼴"),
 "3": ("    return \"five_hour\" if secs <= 21600 else \"seven_day\"", "    return \"seven_day\""),
 "4": ("    core = f\"{local[:2]}…{dom[:1]}\" if at else (rest[:4] or hashlib.sha1(stem.encode()).hexdigest()[:8])",
       "    core = local if at else stem"),
 "5": ("        cache[row[\"account\"]] = {\"at\": NOW, \"row\": mask_row(row, secrets)}",
       "        if row[\"result\"] == \"OK\": cache[row[\"account\"]] = {\"at\": NOW, \"row\": mask_row(row, secrets)}"),
 "6": ("timeout=timeout)", "timeout=timeout + 0.5)"),
 "7": ("    return (j, \"\") if isinstance(j, dict) else (None, \"판정 불가 응답 꼴\")", "    return (j, \"\")"),
}
old, new = M[n]
s = open(src, encoding="utf-8").read()
if old not in s:
    print("MUTATION-APPLY-FAIL " + n); sys.exit(3)
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

mutate_one() { # $1=번호 — 그 변이의 칸이 빨강이어야 통과
  local n="$1"
  local d="$TMP/mut$n" before
  mkdir -p "$d"
  if ! mutate_apply "$TOOL" "$d/ft-acct-usage.sh" "$n"; then bad "변이 M$n 적용 실패"; return; fi
  TOOL="$d/ft-acct-usage.sh"; before=$fail
  case "$n" in
    1) chip_d1 ;;
    2) chip_d2 ;;
    3) chip_d3 ;;
    4) chip_d4 ;;
    5) chip_d6 ;;
    6) chip_d7 ;;
    7) chip_d5 ;;
  esac
  [ "$fail" -gt "$before" ] && ok "변이 M$n FAIL(칸이 잡음)" || bad "변이 M$n 를 칸이 못 잡음"
  fail=$before   # 기대한 빨강(변이가 잡힌 것)은 집계에서 뺀다 — 남는 FAIL 만 진짜 문제다
}

if [ "${1:-}" = "--mutate" ]; then
  if [ -n "${2:-}" ]; then mutate_one "$2"
  else
    for n in 1 2 3 4 5 6 7; do
      out="$(bash "${BASH_SOURCE[0]}" --mutate "$n" 2>&1)"; rc=$?
      printf '%s\n' "$out" | grep -E '^(PASS|FAIL) 변이 M' || true
      [ "$rc" -eq 0 ] || bad "변이 M$n 실행 rc=$rc"
    done
  fi
else
  all_chips
fi
echo "fail=$fail"; [ "$fail" -eq 0 ]
