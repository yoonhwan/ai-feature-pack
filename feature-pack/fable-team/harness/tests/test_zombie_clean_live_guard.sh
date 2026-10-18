#!/usr/bin/env bash
# test_zombie_clean_live_guard.sh — zombie-clean.sh 보호선 2종 시험 (R178):
#   ① agent-browser 데몬(pid·sock·최근 mtime) 아래 크롬  ② 부모가 살아 있는 sleep·tail
# 가짜 ps 스냅샷 + 임시 ZC_AB_DIR + 임시 HOME 만 쓴다. `clean --dry-run` 이라 kill 0 — 좀비 목록 출력만 본다.
# 시험 대상은 ZC_SCRIPT 로 바꿀 수 있다(기본 = 리포 추적본). 변이 2종(보호선·판정 제거)은 임시 사본으로 만들어 단언이 FAIL 하는지 본다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ZC="${ZC_SCRIPT:-$HERE/../../harness/kit/zombie-clean/zombie-clean.sh}"
fail=0; pass=0
ok()  { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$ZC" || { echo "FAIL bash -n $ZC"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAKE="$TMP/fakebin"; mkdir -p "$FAKE" "$TMP/home"

# 스텁 — 실 프로세스·소켓·tmux 를 보지 않는다. ps 는 스냅샷 호출(-axwwo)만 픽스처로 답하고 자기 체인 조회는 비운다.
cat > "$FAKE/ps" <<'EOF'
#!/usr/bin/env bash
case "$1" in -axwwo) cat "$PS_FIXTURE"; exit 0 ;; esac
case "$*" in *"ppid="*) exit 0 ;; esac
exec /bin/ps "$@"
EOF
printf '#!/usr/bin/env bash\necho "PID Status Label"\n' > "$FAKE/launchctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE/tmux"
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE/lsof"
chmod +x "$FAKE/ps" "$FAKE/launchctl" "$FAKE/tmux" "$FAKE/lsof"

LIVE=$$                                   # kill -0 이 성공하는 «살아 있는 데몬 pid» (시험 셸 자신 — 신호는 보내지 않는다)
true & DEAD=$!; wait "$DEAD" 2>/dev/null  # 이미 끝난 자식의 pid = 죽은 데몬 pid
CHROME=90010; SLEEPP=90021; ORPHAN=90030; TAILP=90041; LOOP=90020; LOOP2=90040

# mkab <디렉터리> <pid> [sock|nosock] [fresh|old] — 세션 파일 3종 (.pid .sock .target)
mkab() {
  local d="$1" pid="$2" sock="${3:-sock}" age="${4:-fresh}"
  mkdir -p "$d"; printf '%s' "$pid" > "$d/s1.pid"; : > "$d/s1.target"
  [ "$sock" = sock ] && : > "$d/s1.sock"
  [ "$age" = old ] && touch -t 200001010000 "$d"/s1.*
  return 0
}
# fixture <데몬 pid> — 스냅샷: 데몬(ppid 1) → 크롬 / bash 루프(ppid 1) → sleep·tail / 부모 없는 ppid 1 sleep
fixture() {
  cat <<EOF
$1 1 ?? 1000 /usr/local/bin/agent-browser-darwin-arm64 daemon
$CHROME $1 ?? 5000 /Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing --remote-debugging-port=0
$LOOP 1 ?? 800 bash /tmp/observe-loop.sh
$SLEEPP $LOOP ?? 100 sleep 60
$LOOP2 1 ?? 800 bash /tmp/observe-loop2.sh
$TAILP $LOOP2 ?? 100 tail -f /tmp/observe.log
$ORPHAN 1 ?? 100 sleep 60
EOF
}
# classify <스크립트> <데몬 pid> <ZC_AB_DIR> → 좀비로 분류된 pid 집합(정렬·공백구분)
classify() {
  local zc="$1" dpid="$2" abdir="$3"
  fixture "$dpid" > "$TMP/ps.fix"
  env HOME="$TMP/home" PATH="$FAKE:$PATH" PS_FIXTURE="$TMP/ps.fix" ZC_AB_DIR="$abdir" bash "$zc" clean --dry-run 2>&1 \
    | sed -n 's/^  \([0-9][0-9]*\) \[.*$/\1/p' | sort -n | tr '\n' ' ' | sed 's/ $//'
}
has()  { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }   # has "<집합>" <pid>
expect_in()  { has "$2" "$3" && ok "$1" || bad "$1 → 좀비 집합 [$2] 에 $3 없음"; }
expect_out() { has "$2" "$3" && bad "$1 → 좀비 집합 [$2] 에 $3 있음" || ok "$1"; }

# 대조군 — AB 디렉터리 없음: 크롬·orphan sleep 은 좀비 (시험이 판별력을 가졌다는 증거)
Z="$(classify "$ZC" "$LIVE" "$TMP/none")"
expect_in "T0 대조군(세션 파일 없음) 크롬 좀비" "$Z" "$CHROME"

# ⓐ 살아 있는 데몬 + sock + 최근 mtime → 그 자식 크롬 좀비 0
mkab "$TMP/ab-a" "$LIVE"
Za="$(classify "$ZC" "$LIVE" "$TMP/ab-a")"
expect_out "T1ⓐ 살아 있는 세션 크롬 보호" "$Za" "$CHROME"
# ⓑ sock 없음 → 좀비
mkab "$TMP/ab-b" "$LIVE" nosock
expect_in "T2ⓑ sock 없음 → 좀비" "$(classify "$ZC" "$LIVE" "$TMP/ab-b")" "$CHROME"
# ⓒ mtime 이 문턱 밖 → 좀비
mkab "$TMP/ab-c" "$LIVE" sock old
expect_in "T3ⓒ mtime 문턱 밖 → 좀비" "$(classify "$ZC" "$LIVE" "$TMP/ab-c")" "$CHROME"
# ⓓ 데몬 pid 죽음 → 좀비
mkab "$TMP/ab-d" "$DEAD"
expect_in "T4ⓓ 데몬 죽음 → 좀비" "$(classify "$ZC" "$DEAD" "$TMP/ab-d")" "$CHROME"
# ⓓ' pid 파일이 숫자가 아님 → 좀비
mkab "$TMP/ab-e" "abc"
expect_in "T4ⓓ' pid 비숫자 → 좀비" "$(classify "$ZC" "$LIVE" "$TMP/ab-e")" "$CHROME"
# ⓒ' 문턱을 환경변수로 줄이면(ZC_AB_IDLE_MIN) 같은 신선 세션도 문턱 안/밖이 갈린다
expect_out "T4ⓒ' 문턱 안 보호(ZC_AB_IDLE_MIN=60)" "$(ZC_AB_IDLE_MIN=60 classify "$ZC" "$LIVE" "$TMP/ab-a")" "$CHROME"

# ⓔ 부모 bash 루프(ppid 1) 아래 sleep·tail → 좀비 0 / ⓕ ppid 1 sleep → 좀비
expect_out "T5ⓔ 루프 아래 sleep 보호" "$Za" "$SLEEPP"
expect_out "T5ⓔ' 루프 아래 tail 보호" "$Za" "$TAILP"
expect_in  "T6ⓕ ppid 1 sleep → 좀비" "$Za" "$ORPHAN"
# ⓕ' 부모가 스냅샷에 없는 sleep(부모 죽음) → 좀비
fixture "$LIVE" | sed "s/^$SLEEPP $LOOP /$SLEEPP 99999 /" > "$TMP/ps.fix"
Zp="$(env HOME="$TMP/home" PATH="$FAKE:$PATH" PS_FIXTURE="$TMP/ps.fix" ZC_AB_DIR="$TMP/ab-a" bash "$ZC" clean --dry-run 2>&1 | sed -n 's/^  \([0-9][0-9]*\) \[.*$/\1/p' | sort -n | tr '\n' ' ' | sed 's/ $//')"
expect_in "T6ⓕ' 부모 없는 sleep → 좀비" "$Zp" "$SLEEPP"

# ⓖ 변이 — 보호선 1 제거 → ⓐ 단언이 FAIL / 판정 2 제거 → ⓔ 단언이 FAIL (변이가 실제로 사본을 바꿨는지도 확인)
M1="$TMP/mut1.sh"; M2="$TMP/mut2.sh"
sed 's/ \$(agent_browser_live_pids)" \\$/" \\/' "$ZC" > "$M1"
sed 's/ || ((cat == "고아 sleep" || cat == "고아 tail") \&\& parent_live(pid))//' "$ZC" > "$M2"
cmp -s "$ZC" "$M1" && bad "T7ⓖ 변이1 이 사본을 바꾸지 못함" || ok "T7ⓖ 변이1 적용됨"
cmp -s "$ZC" "$M2" && bad "T7ⓖ 변이2 가 사본을 바꾸지 못함" || ok "T7ⓖ 변이2 적용됨"
has "$(classify "$M1" "$LIVE" "$TMP/ab-a")" "$CHROME" && ok "T7ⓖ 변이1(보호선 제거) → ⓐ 단언 FAIL 확인" || bad "T7ⓖ 변이1 인데 ⓐ 가 통과함"
has "$(classify "$M2" "$LIVE" "$TMP/ab-a")" "$SLEEPP" && ok "T7ⓖ 변이2(판정 제거) → ⓔ 단언 FAIL 확인" || bad "T7ⓖ 변이2 인데 ⓔ 가 통과함"

total=$((pass+fail))
echo "$pass/$total PASS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
