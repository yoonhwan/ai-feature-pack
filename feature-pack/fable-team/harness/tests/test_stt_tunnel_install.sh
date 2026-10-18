#!/usr/bin/env bash
# STT 터널(:8001) launchd 상주 설치 시험 (ops R179 · 이슈 #1584) — launchctl·gcloud·lsof·ps·kill 전부 셸 스텁 · 임시 LaunchAgents 폴더.
# 실 터널·실 launchd·실 VM 0. 실행: bash tests/harness/test_stt_tunnel_install.sh (리포 어느 워크트리에서든)
set -uo pipefail
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SRC="$REPO/scripts/harness-install/stt-tunnel"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/state"; B="$T/bin"; AG="$T/agents"; mkdir -p "$S" "$B"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$B/$1"; chmod +x "$B/$1"; }
VM=byz-agents-gce-stt-tts-dev; ZN=asia-northeast3-a
OLD_ARGV="python gcloud.py compute start-iap-tunnel $VM 8000 --local-host-port=localhost:8001 --zone=$ZN"

# 포트별 홀더: $S/holder_<port> · ps 필드: $S/ps_<pid>_<field>
mk lsof 'for a; do case "$a" in -iTCP:*) p="${a#-iTCP:}";; esac; done; [ -s "'$S'/holder_$p" ] && cat "'$S'/holder_$p"; true'
mk ps 'f=""; p=""; while [ $# -gt 0 ]; do case "$1" in -o) f="${2%=}"; shift;; -p) p="$2"; shift;; esac; shift; done
[ -f "'$S'/ps_${p}_$f" ] && cat "'$S'/ps_${p}_$f"; true'
mk kill "echo \"kill \$*\" >> '$S/log'; [ -f '$S/kill_fail' ] || { [ \"\$2\" = \"\$(cat '$S/holder_8001' 2>/dev/null)\" ] && : > '$S/holder_8001'; }; true"
mk prekill "echo \"prekill \$2\" >> '$S/log'; true"
# gcloud 스텁: 사전검증(-L 383xx) 만 쓰인다 — prefail 이면 안 염 · foreign 이면 남의 리스너가 먼저 잡음
mk gcloud "echo gcloud >> '$S/log'; args=\"\$*\"
p=\"\$(echo \"\$args\" | sed -n 's/.*-L \\(383[0-9][0-9]\\):localhost:8000.*/\\1/p')\"
[ -n \"\$p\" ] || exit 0
if [ -f '$S/foreign' ]; then echo 6666 > \"$S/holder_\$p\"; echo 1 > '$S/ps_6666_ppid'
elif [ ! -f '$S/prefail' ]; then echo 7777 > \"$S/holder_\$p\"; echo \$\$ > '$S/ps_7777_ppid'; fi
[ -f '$S/mutate' ] && echo 'python other.py' > '$S/ps_85243_command'; true"
# launchctl 스텁: bootstrap = 9999 가 8001 점유(new_fail 이면 없음 · boot_fail 이면 rc=1) · bootout = 내림
mk launchctl "case \"\$1\" in
  print) [ -f '$S/loaded' ];;
  bootstrap) echo bootstrap >> '$S/log'; touch '$S/loaded'; [ -f '$S/boot_fail' ] && exit 1
      [ -f '$S/new_fail' ] || echo 9999 > '$S/holder_8001';;
  bootout) echo bootout >> '$S/log'; rm -f '$S/loaded'; [ \"\$(cat '$S/holder_8001' 2>/dev/null)\" = 9999 ] && : > '$S/holder_8001'; true;;
esac"

reset() {  # $1 = none|old|other
  rm -rf "$S" "$AG"; mkdir -p "$S"; : > "$S/log"
  case "$1" in
    old)   echo 85243 > "$S/holder_8001"; echo "$OLD_ARGV" > "$S/ps_85243_command"; echo T1 > "$S/ps_85243_lstart";;
    other) echo 4242 > "$S/holder_8001"; echo 'python -m http.server 8001' > "$S/ps_4242_command"; echo T1 > "$S/ps_4242_lstart";;
  esac
}
# health 스텁: 그 포트에 홀더가 있어야 ok · new_nohealth 면 8001 은 항상 실패
HC='[ -s "'$S'/holder_$STT_TUNNEL_HEALTH_PORT" ] && { [ "$STT_TUNNEL_HEALTH_PORT" != 8001 ] || [ ! -f "'$S'/new_nohealth" ]; }'
run() { env PATH="$B:$PATH" STT_TUNNEL_AGENTS_DIR="$AG" STT_TUNNEL_WAIT=2 STT_TUNNEL_KILL="$B/kill" STT_TUNNEL_PREKILL="$B/prekill" \
          STT_TUNNEL_CALL_TMO=1 STT_TUNNEL_HEALTH_CMD="$HC" bash "$SRC/install.sh" "$@"; }
logs() { tr '\n' ' ' < "$S/log"; }
P="$AG/com.byz.stt-tunnel-8001.plist"

for f in "$SRC/install.sh" "${BASH_SOURCE[0]}"; do
  bash -n "$f" && ok "① bash -n ${f#$REPO/}" || bad "① bash -n ${f#$REPO/}"
done

# ② 포트 비어 있음 → 설치 · plist 내용
reset none; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == INSTALLED* ]] && ok "② 빈 포트 설치 rc=0" || bad "② rc=$rc out=$out"
miss=""
for k in 'com.byz.stt-tunnel-8001' '8001:localhost:8000' 'ServerAliveInterval=30' 'ServerAliveCountMax=3' 'ExitOnForwardFailure=yes' \
         '<key>RunAtLoad</key><true/>' '<key>KeepAlive</key><true/>' '<key>ThrottleInterval</key><integer>30</integer>' \
         '--tunnel-through-iap' 'byz-local-dev@byz-agents-484214.iam.gserviceaccount.com' '/tmp/byz-stt-tunnel-8001.log' \
         "$VM" "--zone=$ZN" '--quiet' '--strict-host-key-checking=yes' 'BatchMode=yes'; do
  grep -qF -- "$k" "$P" 2>/dev/null || miss="$miss [$k]"; done
grep -q '__[A-Z_]*__' "$P" 2>/dev/null && miss="$miss [치환 안 된 자리표시자]"
[ -z "$miss" ] && ok "② plist 내용 17칸 · 자리표시자 0" || bad "② plist 누락:$miss"
[[ "$(logs)" != *kill* ]] && ok "② 옛 터널 없으면 kill 0" || bad "② kill 발생: $(logs)"

# ③ 옛 nohup 터널 → 사전검증(빈 포트) → 옛 pid TERM → bootstrap → INSTALLED 넘겨받음
reset old; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 0 ] && [[ "$out" == *"사전검증 ok"* ]] && [[ "$out" == *"INSTALLED"*"넘겨받음=85243"* ]] && ok "③ 옛 터널 인수 rc=0" || bad "③ rc=$rc out=$out"
[[ "$L" == *gcloud*"kill -TERM 85243"*bootstrap* ]] && ok "③ 순서: 사전검증 → 옛 pid 종료 → bootstrap" || bad "③ 순서: $L"

# ④ 8001 을 쥔 게 옛 nohup 터널이 아님 → REJECT rc=3 · 변경 0
reset other; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 3 ] && [[ "$out" == REJECT* ]] && ok "④ 남의 프로세스 REJECT rc=3" || bad "④ rc=$rc out=$out"
[[ "$L" != *kill* && "$L" != *bootstrap* && "$L" != *gcloud* && ! -e "$P" ]] && ok "④ kill·bootstrap·gcloud·plist 0" || bad "④ 변경 발생: $L"

# ⑤ 사전검증 실패(빈 포트 터널이 안 열림) → rc=6 · 옛 터널 그대로
reset old; touch "$S/prefail"; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 6 ] && [[ "$out" == REJECT* ]] && ok "⑤ 사전검증 실패 rc=6" || bad "⑤ rc=$rc out=$out"
[[ "$L" != *"kill -TERM 85243"* && "$L" != *bootstrap* ]] && ok "⑤ 옛 pid 종료·bootstrap 0" || bad "⑤ 변경 발생: $L"

# ⑥ 사전검증 포트에 남의 리스너 → rc=6 · 남의 pid TERM 0
reset old; touch "$S/foreign"; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 6 ] && [[ "$out" == *"남의 리스너"* ]] && ok "⑥ 남의 리스너 rc=6" || bad "⑥ rc=$rc out=$out"
[[ "$L" != *"prekill 6666"* && "$L" != *"kill -TERM 85243"* ]] && ok "⑥ 남의 pid·옛 pid TERM 0" || bad "⑥ 변경 발생: $L"

# ⑦ 사전검증 사이 옛 pid argv 변조 → rc=3 · 종료 0
reset old; touch "$S/mutate"; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 3 ] && [[ "$out" == *REJECT*"바뀜"* ]] && ok "⑦ 사전검증 사이 변조 rc=3" || bad "⑦ rc=$rc out=$out"
[[ "$L" != *"kill -TERM 85243"* && "$L" != *bootstrap* ]] && ok "⑦ 종료·bootstrap 0" || bad "⑦ 변경 발생: $L"

# ⑧ 새 터널 health 실패 → bootout + rc=5 · 옛 줄 출력
reset old; touch "$S/new_nohealth"; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 5 ] && [[ "$out" == *"ROLLBACK ok"*"start-iap-tunnel $VM 8000 --local-host-port=localhost:8001"* ]] && ok "⑧ health 실패 롤백 rc=5 · 옛 줄 출력" || bad "⑧ rc=$rc out=$out"
[[ "$L" == *bootstrap*bootout* && ! -e "$S/loaded" ]] && ok "⑧ launchd 항목 내림" || bad "⑧ 로그: $L"

# ⑨ bootstrap 자체 실패 → rc=5 롤백
reset old; touch "$S/boot_fail"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 5 ] && [[ "$out" == *"ROLLBACK ok"* ]] && ok "⑨ bootstrap 실패 롤백 rc=5" || bad "⑨ rc=$rc out=$out"

# ⑩ 이미 설치(launchd loaded + 홀더) → ALREADY · kill·bootstrap 0
reset none; run install >/dev/null 2>&1; : > "$S/log"; out="$(run install 2>&1)"; rc=$?; L="$(logs)"
[ "$rc" = 0 ] && [[ "$out" == ALREADY* ]] && ok "⑩ 재실행 ALREADY rc=0" || bad "⑩ rc=$rc out=$out"
[[ "$L" != *kill* && "$L" != *bootstrap* ]] && ok "⑩ 변경 0" || bad "⑩ 변경 발생: $L"

# ⑪ status — 설치됨 rc=0 · 미설치 rc=1
reset none; run install >/dev/null 2>&1; out="$(run status 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "launchd=loaded listen=9999 health=ok" ]] && ok "⑪ status 설치됨" || bad "⑪ rc=$rc out=$out"
reset none; out="$(run status 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == "launchd=missing listen=none health=skip" ]] && ok "⑪ status 미설치 rc=1" || bad "⑪ rc=$rc out=$out"

# ⑫ uninstall — bootout + plist 제거 + 옛 줄 출력(실행 0)
reset none; run install >/dev/null 2>&1; out="$(run uninstall 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == UNINSTALLED*"nohup gcloud compute start-iap-tunnel"* && ! -e "$P" ]] && ok "⑫ uninstall plist 제거 · 옛 줄 출력" || bad "⑫ rc=$rc out=$out"

# ⑬ 잘못된 인자 → rc=2
reset none; run bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "⑬ 잘못된 인자 rc=2" || bad "⑬ rc=$rc"

exit "$fail"
