#!/usr/bin/env bash
# test_disk_alarm_sweep_stage_r2301.sh — r2301 A1 · A1b: 사본 정리(sweep) 주기가 디스크 단계를 따라간다.
#   경보(warn·urgent) 단계 = 측정 틱마다(--sweep 2회 연속) · ok 단계 = 24시간 1회 그대로 · 단계가 이번 틱에 올라간 틱 = 그 틱에 1회.
#   경보 단계 틱 쪽지는 지운 것이 있을 때만(swept=0 = 로그 1줄 · 쪽지 0) · rc 5 = 기존 «[사본 정리 미완]» 그대로.
# 가짜 df(FT_DISK_FREE_GIB)·가짜 시계(FT_DISK_NOW)·가짜 mbox·가짜 정리 도구만 쓴다 — 실 디스크·실 쪽지·실 사본 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
TOOL="${FT_DISK_ALARM_BIN:-$REPO/harness/bin/ft-disk-alarm.sh}"   # r2301: 기준판(고치기 전 사본)을 같은 시험으로 돌려 Red 를 보이기 위한 갈래
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MLOG="$T/mbox.log"; : > "$MLOG"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$2" "$3" "$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '{"_hil_route":"byz-planner-master-claude#99"}\n' > "$T/seats.json"
printf '#!/bin/sh\nprintf "== 디스크 증가 상위 (직전 스냅샷 대비) ==\\n  /private/tmp/aaa  +3.00G  10.0MB/min\\n"\n' > "$T/watch.sh"; chmod 755 "$T/watch.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$T/noop.sh"
# 사본 정리 대역 — 부른 횟수를 적고, scr.out(마지막 줄 · swept=) · scr.rc 를 그대로 낸다
cat > "$T/scr.sh" <<EOF
#!/bin/sh
echo "\$*" >> "$T/scr.calls"
case "\$*" in
  *--sweep*) cat "$T/scr.out" 2>/dev/null
             if [ -f "$T/scr.rc" ]; then exit "\$(cat "$T/scr.rc")"; fi;;
  *) printf 'ORPHANS-SUMMARY 0곳\n';;
esac
exit 0
EOF
chmod 755 "$T/scr.sh"
printf -- '- [scratchpad 사본] DEAD-SAFE 0개 0.00GiB · DEAD-KEEP 0 · LIVE 0 · UNKNOWN 0 · 삭제 0\n' > "$T/spc.out"
printf '#!/bin/sh\ncat "%s/spc.out"\n' "$T" > "$T/spc.sh"; chmod 755 "$T/spc.sh"

# newroot <이름> — 시험마다 따로 트는 데이터 루트(앞 시험의 상태 파일이 새지 않게)
NR=0
newroot() { NR=$((NR+1)); RR="$T/r$NR"; mkdir -p "$RR/.fable-team/state"; cp "$T/seats.json" "$RR/.fable-team/seats-planner.json"; : > "$T/scr.calls"; : > "$MLOG"; echo 0 > "$T/scr.rc"; echo 'swept=0' > "$T/scr.out"; }
NOW=1000000
# tick <여유GiB> <시계 오프셋> — 쪽지 로그·호출 기록은 남기고 1회 실행(누적 관찰)
tick() { env FT_RES_ROOT="$RR" FT_DISK_FREE_GIB="$1" FT_DISK_NOW=$((NOW+$2)) FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$RR/.fable-team/seats-planner.json" \
  FT_RES_WATCH_SH="$T/watch.sh" FT_SCRATCH_REPO_SH="$T/scr.sh" FT_DOCKER_REAP_SH="$T/noop.sh" FT_WT_MODE_STAMP_SH="$T/noop.sh" FT_TMP_SWEEP_SH="$T/noop.sh" \
  FT_SCRATCHPAD_CENSUS_SH="$T/spc.sh" FT_ACCUM_SWEEP="$T/noop.sh" bash "$TOOL" >"$T/out" 2>&1; RC=$?; }
calls() { grep -cx -- "--sweep" "$T/scr.calls" 2>/dev/null || echo 0; }   # --report 호출은 안 셈
sent()  { grep -c . "$MLOG"; }
has()   { grep -q -- "$1" "$MLOG"; }
log()   { cat "$RR/.fable-team/state/disk-alarm.log" 2>/dev/null; }
T0=$SECONDS

[ -f "$TOOL" ] || { bad "ft-disk-alarm.sh 없음: $TOOL"; echo "(1 failed)"; exit 1; }
bash -n "$TOOL" && ok "bash -n" || bad "bash -n"

# ① 경보 단계 = 측정 틱마다(15분) — warn
newroot
tick 45 0;      c1=$(calls)
tick 45 900;    c2=$(calls)
tick 45 1800;   c3=$(calls)
[ "$c1$c2$c3" = 123 ] && ok "① warn 단계 틱 3번 = --sweep 3회(하루 1회 아님)" || bad "① warn 틱마다 호출 1/2/3 이어야 = $c1$c2$c3"
# ① urgent 도 같다
newroot
tick 25 0;      c1=$(calls)
tick 25 900;    c2=$(calls)
[ "$c1$c2" = 12 ] && ok "① urgent 단계 틱 2번 = --sweep 2회" || bad "① urgent 틱마다 호출 = $c1$c2"
# ① ok 단계 = 24시간 1회 그대로
newroot
tick 60 0;      c1=$(calls)
tick 60 900;    c2=$(calls)
tick 60 1800;   c3=$(calls)
tick 60 86460;  c4=$(calls)
[ "$c1$c2$c3$c4" = 1112 ] && ok "① ok 단계 = 24시간 안 1회 · 넘으면 다시 1회(1/1/1/2)" || bad "① ok 단계 호출 = $c1$c2$c3$c4 (1/1/1/2 이어야)"
# ① 이번 틱에 ok→warn 으로 바뀐 틱 = 그 틱에 1회(단계 판정이 한 틱 늦지 않다)
newroot
tick 60 0;      c1=$(calls)
tick 45 900;    c2=$(calls)
[ "$c1$c2" = 12 ] && ok "① ok→warn 으로 바뀐 틱에 바로 1회" || bad "① ok→warn 틱 호출 = $c1$c2"

# ①b 경보 단계 틱 swept=0 = 쪽지 0 · 로그 1줄 / swept≥1 = 쪽지 1
newroot
printf 'swept=0 owner-dead=0 tmp=0 held=0 refused-dirty=1 refused-keep=0 held-lsof=0 refused-other=0 kept=0 unknown=0\n' > "$T/scr.out"
tick 45 0;    b0=$(sent)          # 기준선 = 경고 본문 1 + 하루 1회 sweep 요약 1
tick 45 900;  b1=$(sent)
{ [ "$b1" = "$b0" ] && grep -q '사본 정리 rc=0 단계=warn' <<<"$(log)" && grep -q 'refused-dirty=1' <<<"$(log)"; } \
  && ok "①b 경보 단계 swept=0 = 쪽지 증가 0 · 로그 1줄" || bad "①b swept=0 증가=$((b1-b0)) log=$(tail -1 <<<"$(log)")"
printf 'swept=2 owner-dead=2 tmp=2 held=0 refused-dirty=0 refused-keep=0 held-lsof=0 refused-other=0 kept=0 unknown=0\n' > "$T/scr.out"
tick 45 1800; b2=$(sent)
{ [ $((b2-b1)) = 1 ] && has 'swept=2 owner-dead=2' && ! tail -1 "$MLOG" | grep -q '\[디스크 경고\]'; } \
  && ok "①b 경보 단계 swept≥1 = 쪽지 1(본문 아님)" || bad "①b swept=2 증가=$((b2-b1)) 마지막=[$(tail -1 "$MLOG")]"
# ①b 보류·unknown 요약 쪽지(scratchpad 사본 표)는 하루 1회 그대로 — 경보 틱마다 늘지 않는다
tick 45 2700; b3=$(sent)
{ [ $((b3-b2)) = 1 ] && ! tail -1 "$MLOG" | grep -q 'scratchpad 사본'; } \
  && ok "①b 보류 요약 쪽지는 경보 틱마다 늘지 않는다(하루 1회 그대로)" || bad "①b 보류 요약 증가=$((b3-b2)) 마지막=[$(tail -1 "$MLOG")]"

# ①b rc 5 = 기존 «[사본 정리 미완]» 그대로 · swept 를 안 바꿔 다음 틱 재시도
newroot
echo 5 > "$T/scr.rc"
tick 45 0;    w0=$(sent); c1=$(calls)
tick 45 900;  w1=$(sent); c2=$(calls)
{ [ "$c1" = 1 ] && [ "$c2" = 2 ] && [ $((w1-w0)) = 1 ] && has '\[사본 정리 미완\]'; } \
  && ok "①b rc 5 = [사본 정리 미완] 1통 · 다음 틱 재시도(호출 1/2)" || bad "①b rc5 c1=$c1 c2=$c2 증가=$((w1-w0))"

# ①b' 경보가 24시간 넘게 이어져도 «보류·unknown 요약 쪽지(sweep 끝 줄)» 는 하루 1통 — 경보 틱이 침묵하는 것은 swept=0 **이면서 하루 경계가 아닐 때** 뿐
newroot
printf 'swept=0 owner-dead=0 tmp=0 held=0 refused-dirty=1 refused-keep=0 held-lsof=0 refused-other=0 kept=0 unknown=0\n' > "$T/scr.out"
sw() { grep -c '|swept=0 owner-dead=0' "$MLOG"; }   # 경보 본문과 갈라 «sweep 요약 쪽지» 만 센다
tick 45 0;       s1=$(sw)
tick 45 900;     s2=$(sw)
tick 45 86460;   s3=$(sw)
tick 45 87360;   s4=$(sw)
{ [ "$s1" = 1 ] && [ "$s2" = 1 ]; } && ok "①b' 경보 틱 swept=0 · 하루 경계 전 = 쪽지 0(1통 그대로)" || bad "①b' 경계 전 s1=$s1 s2=$s2"
{ [ "$s3" = 2 ] && [ "$s4" = 2 ]; } && ok "①b' 24시간 넘긴 경보 틱 = 보류 요약 1통(하루 1회 그대로)" || bad "①b' 경계 뒤 s3=$s3 s4=$s4 (하루 1통이어야)"
{ tail -1 "$MLOG" | grep -q 'refused-dirty=1' || [ "$s4" = 2 ]; } && ok "①b' 본문 = 기준판과 같은 끝 줄(보류 수 그대로)" || bad "①b' 본문=[$(tail -1 "$MLOG")]"

T1=$SECONDS
# ⑥ 회귀: 기존 ft-disk-alarm 시험 그대로 rc0 · 70초 안
s=$SECONDS; o="$(bash "$HERE/test_disk_alarm.sh" 2>&1 | tail -1)"; e=$((SECONDS-s))
{ [ $e -lt 70 ] && grep -q 'ALL PASS' <<<"$o"; } && ok "⑥ 기존 ft-disk-alarm 시험 rc0 (${e}s)" || bad "⑥ 기존 시험 ${e}s tail=[$o]"
T2=$SECONDS
echo "TIME ①/①b=$((T1-T0))s ⑥=$((T2-T1))s 합=$((T2-T0))s"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $(( fail > 0 ))
