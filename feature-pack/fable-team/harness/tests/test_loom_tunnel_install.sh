#!/usr/bin/env bash
# LOOM 터널 launchd 설치 시험 (R87 · 판정 913 · DA r1 반송 6항) — launchctl·gcloud·lsof·ps·kill 전부 셸 스텁 · 임시 LaunchAgents 폴더.
# 실 터널·실 launchd·실 DB 0. 실행: bash tests/harness/test_loom_tunnel_install.sh (리포 어느 워크트리에서든)
set -uo pipefail
REPO="$(git -C "$(dirname -- "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
SRC="$REPO/feature-pack/fable-team/harness/kit/loom-tunnel"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/state"; B="$T/bin"; AG="$T/agents"; mkdir -p "$S" "$B"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$B/$1"; chmod +x "$B/$1"; }
VM=byz-agents-gce-stt-tts-dev; ACC=byz-local-dev@byz-agents-484214.iam.gserviceaccount.com; ZN=asia-northeast3-a
SESS_SSH='/usr/bin/ssh -t -i k -o ProxyCommand gcloud compute start-iap-tunnel byz-agents-gce-stt-tts-dev %p -N -L 38309:10.2.0.10:5432'
gc_argv() { echo "python gcloud.py compute ssh $1 --zone=$2 --account=$3 --tunnel-through-iap -- -N -L 38309:10.2.0.10:5432"; }

# 포트별 홀더: $S/holder_<port> · ps 필드: $S/ps_<pid>_<field>
mk lsof 'for a; do case "$a" in -iTCP:*) p="${a#-iTCP:}";; esac; done; [ -s "'$S'/holder_$p" ] && cat "'$S'/holder_$p"; true'
mk ps 'f=""; p=""; while [ $# -gt 0 ]; do case "$1" in -o) f="${2%=}"; shift;; -p) p="$2"; shift;; esac; shift; done
[ -f "'$S'/ps_${p}_$f" ] && cat "'$S'/ps_${p}_$f"; true'
mk kill "echo \"kill \$*\" >> '$S/log'; [ -f '$S/kill_fail' ] || { [ \"\$2\" = \"\$(cat '$S/holder_38309' 2>/dev/null)\" ] && : > '$S/holder_38309'; }; true"
mk prekill "echo \"prekill \$2\" >> '$S/log'; true"
# gcloud 스텁: 38309 아닌 포트 -L = 사전검증(prefail 이면 안 염) · 38309 = 옛 명령 복구(쓰이면 로그)
mk gcloud "args=\"\$*\"; echo gcloud >> '$S/log'
case \"\$args\" in *' -L 38309:'*) echo 'gcloud-on-38309' >> '$S/log';; *-L\ 383*)
  p=\"\$(echo \"\$args\" | sed -n 's/.*-L \\(383[0-9][0-9]\\):.*/\\1/p')\"
  if [ -f '$S/foreign' ]; then echo 6666 > \"$S/holder_\$p\"; echo 1 > '$S/ps_6666_ppid'
  elif [ ! -f '$S/prefail' ]; then echo 7777 > \"$S/holder_\$p\"; echo \$\$ > '$S/ps_7777_ppid'; fi
  [ -f '$S/mutate' ] && echo 'ssh -L 38309:10.2.0.10:5432 other' > '$S/ps_85243_command';; esac"
# launchctl 스텁: bootstrap 새 label = 9999 가 38309 점유(new_fail 이면 없음) · recover label = 8888 job, listener 8889(rec_foreign 이면 남의 5555)
mk launchctl "case \"\$1\" in
  print) [ -f '$S/loaded' ];;
  list) [ -f '$S/rloaded' ] && echo '	\"PID\" = 8888;';;
  bootstrap) case \"\$3\" in
      *recover.plist) echo bootstrap-recover >> '$S/log'; touch '$S/rloaded'
         if [ -f '$S/rec_foreign' ]; then echo 5555 > '$S/holder_38309'; echo 1 > '$S/ps_5555_ppid'
         else echo 8889 > '$S/holder_38309'; echo 8888 > '$S/ps_8889_ppid'; fi
         echo 1 > '$S/ps_8888_ppid'; echo \"\${REC_PGID:-111}\" > '$S/ps_8888_pgid';;
      *) echo bootstrap >> '$S/log'; touch '$S/loaded'; [ -f '$S/boot_fail' ] && exit 1
         [ -f '$S/new_fail' ] || { echo 9999 > '$S/holder_38309'; };;
    esac;;
  bootout) case \"\$2\" in
      */com.byz.loom-pg-tunnel) echo bootout >> '$S/log'; [ -f '$S/bootout_fail' ] && exit 3; rm -f '$S/loaded'
          [ \"\$(cat '$S/holder_38309' 2>/dev/null)\" = 9999 ] && : > '$S/holder_38309'; true;;
      *) true;;
    esac;;
esac"

reset() {  # $1 = none|session|other
  rm -rf "$S" "$AG"; mkdir -p "$S"; : > "$S/log"
  case "$1" in
    session) echo 85243 > "$S/holder_38309"; echo "$SESS_SSH" > "$S/ps_85243_command"; echo 83409 > "$S/ps_85243_ppid"
             echo "T1" > "$S/ps_85243_lstart"; echo "T0" > "$S/ps_83409_lstart"
             gc_argv $VM $ZN $ACC > "$S/ps_83409_command"; echo 7684 > "$S/ps_83409_ppid";;
    other)   echo 4242 > "$S/holder_38309"; echo 'python -m http.server 38309' > "$S/ps_4242_command"; echo 1 > "$S/ps_4242_ppid";;
  esac
}
# 터널을 쥔 옛 프로세스의 부모 argv 만 바꿔 «정확 대조» 시험
session_with() { reset session; gc_argv "$1" "$2" "$3" > "$S/ps_83409_command"; }
run() { env PATH="$B:$PATH" LOOM_TUNNEL_AGENTS_DIR="$AG" LOOM_TUNNEL_WAIT=2 LOOM_TUNNEL_KILL="$B/kill" LOOM_TUNNEL_PREKILL="$B/prekill" \
          LOOM_TUNNEL_CALL_TMO="${TMO:-1}" LOOM_TUNNEL_SELECT1_CMD="${SEL:-true}" REC_PGID="${REC_PGID:-111}" bash "$SRC/install.sh" "$@"; }
logs() { tr '\n' ' ' < "$S/log"; }

for f in "$SRC/install.sh" "${BASH_SOURCE[0]}"; do
  bash -n "$f" && ok "① bash -n ${f#$REPO/}" || bad "① bash -n ${f#$REPO/}"
done

# ② 포트 비어 있음 → 설치 · plist 내용
reset none; out="$(run install 2>&1)"; rc=$?
P="$AG/com.byz.loom-pg-tunnel.plist"
[ "$rc" = 0 ] && [[ "$out" == INSTALLED* ]] && ok "② 빈 포트 설치 rc=0" || bad "② rc=$rc out=$out"
miss=""
for k in 'com.byz.loom-pg-tunnel' '38309:10.2.0.10:5432' 'ServerAliveInterval=30' 'ServerAliveCountMax=3' 'ExitOnForwardFailure=yes' \
         '<key>RunAtLoad</key><true/>' '<key>KeepAlive</key><true/>' '<key>ThrottleInterval</key><integer>30</integer>' \
         '--tunnel-through-iap' "byz-local-dev@byz-agents-484214.iam.gserviceaccount.com" '/tmp/byz-loom-pg-tunnel.log' \
         '--quiet' '--strict-host-key-checking=yes' 'BatchMode=yes'; do
  grep -qF -- "$k" "$P" 2>/dev/null || miss="$miss [$k]"; done
grep -q '__[A-Z_]*__' "$P" 2>/dev/null && miss="$miss [치환 안 된 자리표시자]"
[ -z "$miss" ] && ok "② plist 내용 14칸 · 자리표시자 0" || bad "② plist 누락:$miss"
grep -q 'kill' "$S/log" && bad "② 빈 포트인데 kill 발생" || ok "② kill 0 · 사전검증 0(옛 터널 없음)"
plutil -lint "$P" >/dev/null 2>&1 && ok "② plutil -lint" || bad "② plutil -lint"

# ③ 정확히 같은 세션 터널 → 사전검증 ok → 그 pid 만 TERM → 곧바로 bootstrap
reset session; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == *"사전검증 ok"* && "$out" == *"넘겨받음=85243"* ]] && ok "③ 세션 터널 넘겨받기 rc=0" || bad "③ rc=$rc out=$out"
[ "$(grep -c '^kill' "$S/log")" = 1 ] && grep -q '^kill -TERM 85243$' "$S/log" && ok "③ 옛 터널 kill = 그 pid(85243) 1회만" || bad "③ kill 로그: $(logs)"
[ "$(logs | sed -E 's/prekill [0-9]+ //g')" = "gcloud kill -TERM 85243 bootstrap " ] && [[ "$(logs)" == gcloud\ prekill* ]] \
  && ok "③ 순서: 사전검증(gcloud→prekill) → 옛 pid 종료 → bootstrap" || bad "③ 순서: $(logs)"

# ④ 정확 대조 REJECT — 남의 프로세스 · VM 접미사 · 다른 계정 · 다른 지역 : 변경 0
check_reject() {  # $1=라벨
  local out rc; out="$(run install 2>&1)"; rc=$?
  [ "$rc" = 3 ] && [[ "$out" == REJECT* ]] && [ ! -e "$P" ] && [ ! -s "$S/log" ] && [ -n "$(cat "$S/holder_38309")" ] \
    && ok "④ $1 REJECT rc=3 · plist 0 · gcloud/kill/bootstrap 0" || bad "④ $1 rc=$rc out=$out log=$(logs)"
}
reset other;                                                     check_reject "남의 프로세스"
session_with "$VM-unrelated" $ZN $ACC;                            check_reject "VM 접미사(-unrelated)"
session_with "x$VM" $ZN $ACC;                                     check_reject "VM 접두사"
session_with $VM $ZN "other-$ACC";                                check_reject "다른 계정"
session_with $VM $ZN "${ACC}x";                                   check_reject "계정 접미사"
session_with $VM asia-northeast1-b $ACC;                          check_reject "다른 지역"

# ⑤ 사전검증 실패 → 옛 pid TERM 0 · 전환 0 · rc=6
reset session; touch "$S/prefail"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 6 ] && ok "⑤ 사전검증 실패 rc=6" || bad "⑤ rc=$rc out=$out"
! grep -q '^kill' "$S/log" && ! grep -q bootstrap "$S/log" && [ "$(cat "$S/holder_38309")" = 85243 ] && ok "⑤ 옛 pid TERM 0 · bootstrap 0 · 옛 터널 그대로" || bad "⑤ $(logs)"
# ⑤b select 1(빈 포트) 실패도 같은 사전검증 실패
reset session; out="$(SEL='[ "$LOOM_TUNNEL_SELECT1_PORT" = 38309 ]' run install 2>&1)"; rc=$?
[ "$rc" = 6 ] && ! grep -q '^kill' "$S/log" && ok "⑤b 빈 포트 select 1 실패 → rc=6 · TERM 0" || bad "⑤b rc=$rc log=$(logs)"
# ⑤c 사전검증 사이 옛 pid argv 가 바뀜 → TERM 0
reset session; touch "$S/mutate"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 3 ] && [[ "$out" == *"바뀜"* ]] && ! grep -q '^kill' "$S/log" && ok "⑤c TERM 직전 argv 재대조 불일치 → rc=3 · TERM 0" || bad "⑤c rc=$rc out=$out log=$(logs)"

# ⑤d 사전검증 빈 포트에 «남의» 리스너 → REJECT · 그 pid TERM 0 · 옛 터널 TERM 0
reset session; touch "$S/foreign"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 6 ] && [[ "$out" == REJECT* && "$out" == *"남의 리스너(pid 6666)"* ]] && ok "⑤d 남의 리스너 REJECT rc=6" || bad "⑤d rc=$rc out=$out"
! grep -q 'prekill 6666' "$S/log" && ! grep -q '^kill' "$S/log" && ! grep -q bootstrap "$S/log" && ok "⑤d 남의 pid PREKILL 0 · 옛 pid TERM 0 · bootstrap 0" || bad "⑤d $(logs)"

# ⑥ 새 터널 실패(TERM 뒤) → 복구: bootout 검사 → launchd 일회성 job 이 옛 명령 재기동 · 소유 pid ∧ ppid=1 ∧ pgid 확인
reset session; touch "$S/new_fail"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 5 ] && [[ "$out" == *"ROLLBACK ok"* && "$out" == *"ppid=1"* && "$out" == *"pgid=111"* ]] && ok "⑥ 새 터널 실패 → ROLLBACK ok(ppid=1 · pgid 출력) rc=5" || bad "⑥ rc=$rc out=$out"
[ "$(cat "$S/holder_38309")" = 8889 ] && grep -q bootstrap-recover "$S/log" && ! grep -q 'gcloud-on-38309' "$S/log" \
  && ok "⑥ 복구 = launchd job(listen pid 8889 ⊂ job 8888) · nohup 직접 기동 0" || bad "⑥ $(logs)"
# ⑥b select 1(38309) 실패 → 같은 복구 (사전검증 select 는 통과)
FAIL2='[ "$LOOM_TUNNEL_SELECT1_PORT" != 38309 ] && exit 0; n=$(cat '"$S"'/m 2>/dev/null || echo 0); echo $((n+1)) > '"$S"'/m; [ "$n" -ge 2 ]'
reset session; out="$(SEL="$FAIL2" run install 2>&1)"; rc=$?
[ "$rc" = 5 ] && grep -q bootstrap-recover "$S/log" && ok "⑥b 38309 select 1 실패 → 복구" || bad "⑥b rc=$rc out=$out log=$(logs)"
# ⑥c 옛 pid 가 안 내려감 → rc=4 · bootstrap 0
reset session; touch "$S/kill_fail"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 4 ] && ! grep -q bootstrap "$S/log" && ok "⑥c 옛 터널 종료 실패 rc=4 · 새 기동 0" || bad "⑥c rc=$rc log=$(logs)"
# ⑥d bootstrap 자체 실패 → 복구
reset session; touch "$S/boot_fail"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 5 ] && grep -q bootstrap-recover "$S/log" && ok "⑥d bootstrap 실패 → 복구" || bad "⑥d rc=$rc out=$out log=$(logs)"

# ⑦ 외부 호출 멈춤 → 7초 상한(시험은 1초) + 재시도 1회 뒤 복구 도달
reset session; touch "$S/new_fail"
HANG='if [ "$LOOM_TUNNEL_SELECT1_PORT" = 38309 ]; then n=$(cat '"$S"'/n 2>/dev/null || echo 0); echo $((n+1)) > '"$S"'/n; [ "$n" -lt 2 ] && sleep 30; fi; true'
reset session; t0=$SECONDS; out="$(SEL="$HANG" TMO=1 run install 2>&1)"; rc=$?; dt=$((SECONDS - t0))
[ "$rc" = 5 ] && [[ "$out" == *"ROLLBACK ok"* ]] && [ "$dt" -lt 15 ] && ok "⑦ select 1 멈춤 → 상한 1s×2 뒤 복구 도달(${dt}s)" || bad "⑦ rc=$rc dt=${dt}s out=$out"
[ "$(cat "$S/n" 2>/dev/null)" -ge 3 ] 2>/dev/null && ok "⑦ 재시도 1회 실재(38309 select 호출 ≥3 = 멈춤 2 + 복구 확인 1)" || bad "⑦ 호출 수 $(cat "$S/n" 2>/dev/null)"

# ⑦b TERM 무시 자식 → 상한(1s) 뒤 KILL · 자식까지 정리 · select1 은 rc≠0(fail) · 시간 유한
reset none; run install >/dev/null 2>&1
IGN='trap "" TERM; while :; do sleep 31.77; done'
t0=$SECONDS; st="$(SEL="$IGN" TMO=1 run status)"; rc=$?; dt=$((SECONDS - t0))
[ "$rc" = 1 ] && [[ "$st" == *"select1=fail"* ]] && [ "$dt" -lt 15 ] && ok "⑦b TERM 무시 자식 → KILL 로 끝남 select1=fail(${dt}s)" || bad "⑦b rc=$rc dt=${dt}s st=$st"
sleep 1; pgrep -f 'sleep 31.77' >/dev/null && { bad "⑦b 자식 프로세스 잔존"; } || ok "⑦b 자식 프로세스 잔존 0"

# ⑧ bootout 실패는 기록·출력된다(복구는 계속)
reset session; touch "$S/new_fail" "$S/bootout_fail"; out="$(run install 2>&1)"; rc=$?
[[ "$out" == *"bootout rc=3"* ]] && ok "⑧ bootout 실패 rc 출력" || bad "⑧ out=$out"

# ⑨ 복구 성공 판정 = 복구 job 이 띄운 pid — 다른 pid 가 LISTEN 이면 실패
reset session; touch "$S/new_fail" "$S/rec_foreign"; out="$(run install 2>&1)"; rc=$?
[ "$rc" = 5 ] && [[ "$out" == *"ROLLBACK 실패"* && "$out" == *"복구 job"* && "$out" != *"ROLLBACK ok"* ]] && ok "⑨ 남의 pid LISTEN → 복구 실패 판정" || bad "⑨ rc=$rc out=$out"

# ⑩ 복구 job 이 호출자와 같은 pgid(세션 안) 이면 실패
cpg="$(/bin/ps -o pgid= -p $$ | tr -d ' ')"
reset session; touch "$S/new_fail"; out="$(REC_PGID="$cpg" run install 2>&1)"; rc=$?
[ "$rc" = 5 ] && [[ "$out" == *"세션 밖이 아님"* ]] && ok "⑩ 복구 pgid = 호출자 pgid → 실패" || bad "⑩ rc=$rc out=$out"

# ⑪ status 3칸
reset none; run install >/dev/null 2>&1; : > "$S/log"
st="$(run status)"; rc=$?
[ "$rc" = 0 ] && [ "$st" = "launchd=loaded listen=9999 select1=ok" ] && ok "⑪ status 정상 3칸 rc=0" || bad "⑪ rc=$rc st=$st"
st="$(SEL=false run status)"; rc=$?
[ "$rc" = 1 ] && [ "$st" = "launchd=loaded listen=9999 select1=fail" ] && ok "⑪ select1 실패 칸 rc=1" || bad "⑪ rc=$rc st=$st"
reset none; st="$(run status)"; rc=$?
[ "$rc" = 1 ] && [ "$st" = "launchd=missing listen=none select1=skip" ] && ok "⑪ 미설치 3칸 rc=1" || bad "⑪ rc=$rc st=$st"

# ⑫ 이미 설치됨 → 변경 0
reset none; run install >/dev/null 2>&1; : > "$S/log"; out="$(run install 2>&1)"
[[ "$out" == ALREADY* ]] && [ ! -s "$S/log" ] && ok "⑫ 재실행 ALREADY · 변경 0" || bad "⑫ out=$out log=$(logs)"

# ⑬ loom_dsn.sh 안내 문구 — launchd 상태 확인으로 바뀜 · 검사 로직 줄(LISTEN)은 그대로
D="$REPO/scripts/server/loom_dsn.sh"
grep -q 'install.sh status' "$D" && ! grep -q 'gcloud compute ssh byz-agents-gce-stt-tts-dev' "$D" && ok "⑬ 안내 문구 교체" || bad "⑬ 안내 문구"
grep -q 'lsof -nP -iTCP:"$LOOM_PG_TUNNEL_PORT" -sTCP:LISTEN -t' "$D" && ok "⑬ LISTEN 검사 로직 그대로" || bad "⑬ 검사 로직 변경됨"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
