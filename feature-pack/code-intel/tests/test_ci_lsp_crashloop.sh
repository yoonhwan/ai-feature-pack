#!/usr/bin/env bash
# r1636 — ci LSP crash-loop 판정(ⓑⓒⓔ) 과 repair(ⓓ) 시험. 실 probe·실 캐시 0 (가짜 probe + tmp HOME).
#   실행: bash feature-pack/code-intel/tests/test_ci_lsp_crashloop.sh
[ -n "${CI_LSP_CRASH_TEST_GUARD:-}" ] && exit 0        # 재진입 표지(자기 호출 가드)
export CI_LSP_CRASH_TEST_GUARD=1
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$HERE/../skill/scripts/ci"
n=0; fail=0
ok()  { n=$((n+1)); echo "  ok   $1"; }
bad() { n=$((n+1)); fail=$((fail+1)); echo "  FAIL $1"; }
chk() { [ "$2" = "$3" ] && ok "$1 ($3)" || bad "$1 — 기대[$3] 얻음[$2]"; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 — [$3] 없음: $(printf '%s' "$2" | head -2)";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — [$3] 있으면 안 됨";; *) ok "$1";; esac; }

SB=""
mk() { # 새 샌드박스 (home/tmp/workspaces/ws_a·ws_b)
  [ -n "$SB" ] && rm -rf "$SB"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/ci-lsp-crash.XXXXXX")"
  ws="$SB/home/Library/Caches/probe/lsp/workspaces"
  mkdir -p "$ws/ws_a" "$ws/ws_b" "$SB/tmp"
  : > "$ws/ws_a/cache.db-log"; : > "$ws/ws_b/cache.db-log"
  cat > "$SB/probe" <<'FAKE'
#!/usr/bin/env bash
echo "ARGS: $*" >> "${FAKE_LOG:-/dev/null}"
case "$1" in
  --version) echo "probe 0.6.0-fake" ;;
  search)    echo "smoke-ok" ;;
  lsp) shift; case "${1:-status}" in
         status)   printf 'LSP Daemon Status\n  Status: Connected\n  Uptime: %s\n' "${FAKE_UPTIME:-120s}" ;;
         call)     echo "FAKE_REFERENCES 16" ;;
         shutdown|init) : ;;
       esac ;;
esac
exit 0
FAKE
  chmod +x "$SB/probe"; : > "$SB/fake.log"; UPTIME=120s
}
run_ci() { HOME="$SB/home" TMPDIR="$SB/tmp" PROBE_BIN="$SB/probe" FAKE_LOG="$SB/fake.log" \
           FAKE_UPTIME="$UPTIME" CI_TIMEOUT=10 bash "$CI" "$@" 2>&1; }
crash() { # $1=마지막 ts · $2=앞선 ts(기본 10초 전) · DB crash 형태 2건(loop = 반복)
  printf '==== LSP Daemon Crash ====\ntimestamp: %s\nmessage: %s\n==== LSP Daemon Crash ====\ntimestamp: %s\nmessage: %s\n' \
    "${2:-$(date -u -d '-10 seconds' +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-10S +%Y-%m-%dT%H:%M:%S.000Z)}" \
    "couldn't read enough data. Requested=187 got=179" \
    "$1" "couldn't read enough data. Requested=187 got=179" \
    > "$SB/home/Library/Caches/probe/lsp-daemon-crashes.log"; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%S.000Z; }

echo "== ⓑ doctor — crash-loop 판정 (데몬이 죽어 Uptime 0s 인 상태) =="
mk; crash "$(now_iso)"
out="$(run_ci doctor)"; rc=$?
chk "crash 최근 → doctor rc" "$rc" "3"
has "doctor CRASH-LOOP 1줄" "$out" "lsp   : CRASH-LOOP couldn't read enough data"
has "doctor 다음 안내" "$out" "ci lsp repair"

echo "== ⓒ refs — 매달리지 않고 rc3 =="
s=$SECONDS; out="$(run_ci refs "a.py#f")"; rc=$?; el=$((SECONDS - s))
chk "crash-loop refs rc" "$rc" "3"
has "판정 불가 1줄" "$out" "판정 불가 LSP 데몬 crash-loop — ci lsp repair"
chk "7초 안 (하드 룰 12)" "$([ "$el" -lt 7 ] && echo ok || echo "$el" )" "ok"
hasnt "probe call 미호출" "$(cat "$SB/fake.log")" "lsp call"

echo "== ⓔ 정상 회귀 — 옛 crash 는 crash-loop 아님(M1) =="
mk; crash "2020-01-01T00:00:00.000Z"
out="$(run_ci doctor)"; chk "옛 crash → doctor rc" "$?" "0"
has "doctor lsp 줄 그대로" "$out" "lsp   : LSP Daemon Status"
has "smoke 그대로" "$out" "smoke : OK"
out="$(run_ci refs "a.py#f")"; chk "정상 refs rc" "$?" "0"
has "probe call 실제 호출" "$(cat "$SB/fake.log")" "ARGS: lsp call references"
has "참조 결과 전달" "$out" "FAKE_REFERENCES 16"

mk; printf 'timestamp: %s\nmessage: %s\n' "$(now_iso)" "couldn't read enough data. Requested=187 got=179" \
    > "$SB/home/Library/Caches/probe/lsp-daemon-crashes.log"
out="$(run_ci doctor)"; chk "crash 1건(반복 없음)은 loop 아님" "$?" "0"
has "그때는 lsp 줄 정상" "$out" "lsp   : LSP Daemon Status"

mk; crash "$(now_iso)" "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S.000Z)"   # 창 밖 1 + 창 안 1
out="$(run_ci doctor)"; chk "1시간 전 1 + 10초 전 1 = 정상 판정" "$?" "0"
has "창 밖은 안 센다" "$out" "lsp   : LSP Daemon Status"

mk; printf 'timestamp: %s\nmessage: end byte index 4096 is not a char boundary; it is inside %s\n' \
    "$(now_iso)" "'용'" > "$SB/home/Library/Caches/probe/lsp-daemon-crashes.log"
out="$(run_ci doctor)"; chk "클라이언트 panic 은 crash-loop 아님" "$?" "0"
has "그래도 lsp 줄 정상" "$out" "lsp   : LSP Daemon Status"

echo "== ⓑ Uptime 0s 2회 연속 =="
mk; UPTIME=0s
out="$(run_ci doctor)"; chk "1회차 rc0" "$?" "0"
out="$(run_ci doctor)"; chk "2회차 rc3" "$?" "3"
has "Uptime 0s 2회 판정" "$out" "Uptime 0s 2회 연속"

echo "== ⓓ repair — 지우지 않고 옮긴다 =="
mk; UPTIME=120s
out="$(run_ci lsp repair)"; chk "repair rc" "$?" "0"
has "옮김 줄" "$out" "옮김:"
has "repair OK" "$out" "repair OK — 데몬 Uptime 120s · 옮긴 워크스페이스 2 개"
chk "원래 폴더 사라짐" "$([ -d "$ws/ws_a" ] && echo yes || echo no)" "no"
chk ".corrupt-* 로 남음(M2)" "$(ls -d "$ws"/*.corrupt-* 2>/dev/null | wc -l | tr -d ' ')" "2"
fl="$(cat "$SB/fake.log")"
has "shutdown 먼저" "$fl" "ARGS: lsp shutdown"
has "init 으로 재기동" "$fl" "ARGS: lsp init -w"

echo "== ⓓ repair --ws 이름 하나만 =="
mk
out="$(run_ci lsp repair --ws ws_b)"; chk "repair --ws rc" "$?" "0"
chk "ws_a 그대로" "$([ -d "$ws/ws_a" ] && echo yes || echo no)" "yes" 2>/dev/null || true
chk "ws_b 만 옮김" "$(ls -d "$ws"/ws_b* 2>/dev/null | wc -l | tr -d ' ')" "1"

echo "== ⓓ 옮기기 실패 = 판정 불가 rc3 =="
mk; chmod 500 "$SB/home/Library/Caches/probe/lsp/workspaces"
out="$(run_ci lsp repair)"; rc=$?
chmod 700 "$SB/home/Library/Caches/probe/lsp/workspaces"
chk "rename 실패 rc" "$rc" "3"
has "판정 불가 1줄" "$out" "판정 불가 repair — 옮기기 실패"

echo "== 요약: $n 검사 · 실패 $fail =="
[ -n "$SB" ] && rm -rf "$SB"
[ "$fail" -eq 0 ] || exit 1
echo "PASS"
