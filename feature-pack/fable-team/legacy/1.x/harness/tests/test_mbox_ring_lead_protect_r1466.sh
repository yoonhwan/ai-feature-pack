#!/usr/bin/env bash
# test_mbox_ring_lead_protect_r1466.sh — r1466: ring 이 결과·판정 쪽지를 안 버리고 · 역할 좌석 상한은 FT_MBOX_RING_LEAD ·
#   버림이 생기면 그 좌석 팀 master 에 «큐 포화» 경보 1통(10분 1회 · pending < ring 이면 표식 삭제).
#   T1 ring=3 · 도구 알림 2 + 좌석 쪽지 2 + [완료 hN](ft-hil-) 1 → 버림 2 = 도구 알림부터 · [완료 hN] 남음
#   T2 좌석 쪽지 머리 [결과·[레디·[인계·[결정·[회신 5통 = 버리기 0 · ERROR 넘침 1줄
#   T3 명부 _master·_arch 좌석 = ring 5(LEAD) · 일반 좌석 = 3 · 명부 없음 = 3 · 명부 깨짐 = 3
#   T4 버림 1 → 팀 master 에 ft-mbox-ring 1통 · 10분 안 재발 0통 · 10분 지나면 1통 더 · master 자신의 포화 = 하네스 master ·
#      pending < ring 이 되면 표식 삭제(닫는 사건)
#   T5 좌석 발신 [HIL] 은 도구 알림이 넘쳐도 보존(#273409 꼴)
#   T7(DA R1 #300019) 동시 ring_after 2개 — ring_alarm_to 뒤 barrier 로 두 sender 를 맞춰도 경보 1통(표식 판독·예약 직렬화)
#   T6 기존 r1116c 시험 불변 — base(팩 origin/main e2184720)에서 이미 FAIL 3(변이가 안 잡힘 · ⓓ R7 · ⓔ holder ·
#      ft_teamset TeamPathError · 이 카드 밖) → «FAIL 목록이 그 3개의 부분집합» 이면 PASS(새 FAIL 0)
# 세 경로를 모두 돈다: comm(mbox.py→mbox_ops.py · 실 send 길) · kit ft-mbox.py · skill ft-mbox.py.
# 정본 .py 를 임시 루트에 복사해 돈다 — 실 우편함·실 명부 쓰기 0 · sleep 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin/ft-mbox.py"; SKILL="$REPO/skill/scripts/ft-mbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS [$IMPL] $1"; }; bad() { echo "FAIL [$IMPL] $1"; fail=$((fail+1)); }
PM="byz-planner-master-pi#244"; PA="byz-planner-arch-claude#9"; HM="byz-harness-master-pi#254"
DA="byz-planner-da-codex#2"; NANO="byz-planner-nano-foo#0"; OPS="byz-ops-master-pi#9"

new_env() {   # 격리 루트 · 빈 큐 · 합성 명부(planner·harness) · comm 사본 + kit·skill 사본
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; FT="$ENVROOT/.fable-team"; C="$FT/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C"; cp "$SRC"/mbox*.py "$C/"; cp "$KIT" "$C/ft-mbox-kit.py"; cp "$SKILL" "$C/ft-mbox-skill.py"
  cp "$REPO/harness/bin/ft-name-lint.sh" "$C/"
  : > "$Q"; : > "$ENVROOT/errs"; printf '{}\n' > "$FT/seats.json"
  printf '{"_master": "%s", "_arch": "%s", "_desk": "byz-planner-desk-claude#5"}\n' "$PM" "$PA" > "$FT/seats-planner.json"
  printf '{"_master": "%s"}\n' "$HM" > "$FT/seats-harness.json"
}
py() {   # py <명령…> — 고른 경로로 1회
  local f; case "$IMPL" in comm) f="$C/mbox.py";; kit) f="$C/ft-mbox-kit.py";; skill) f="$C/ft-mbox-skill.py";; esac
  FT_MBOX_DIR="$C" FT_MBOX_RING=3 FT_MBOX_RING_LEAD=5 FT_NAME_LINT="$C/ft-name-lint.sh" FT_DESK_GATE="$T/없음" \
    python3 "$f" "$@"
}
send() { py send "$1" "$2" "$3" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?; cat "$ENVROOT/err" >> "$ENVROOT/errs"; }
recv() { py recv "$1" --all >/dev/null 2>&1; }
rows_to() { grep -c "\"to\": \"$1\"" "$Q"; }
rows_from() { grep -c "\"from\": \"$1\"" "$Q"; }
alarms_to() { grep "\"from\": \"ft-mbox-ring\"" "$Q" | grep -c "\"to\": \"$1\""; }
mark() { echo "$FT/state/ring-full.${1%#*}"; }

t1() {
  new_env
  send "$DA" ft-tick "뉴스 1"; send "$DA" ft-stall-scan "정체 1"
  send "$DA" "$NANO" "쪽지 a"; send "$DA" "$NANO" "쪽지 b"
  send "$DA" ft-hil-h48 "[완료 h48] rc=0"
  if [ "$(rows_to "$DA")" = 3 ] && [ "$(rows_from ft-tick)" = 0 ] && [ "$(rows_from ft-stall-scan)" = 0 ] \
     && [ "$(rows_from ft-hil-h48)" = 1 ] && [ "$(rows_from "$NANO")" = 2 ]; then
    ok "T1 도구 알림 2통만 버려짐 · [완료 h48]·좌석 쪽지 2 남음"; return 0
  fi
  bad "T1 rows=$(rows_to "$DA") tick=$(rows_from ft-tick) stall=$(rows_from ft-stall-scan) hil=$(rows_from ft-hil-h48) nano=$(rows_from "$NANO")"; return 1
}

t2() {
  new_env
  local h; for h in "[결과] a" "[레디] b" "[인계] c" "[결정] d" "[회신] e"; do send "$DA" "$NANO" "$h"; done
  if [ "$(rows_to "$DA")" = 5 ] && ! grep -q '^DROPPED' "$ENVROOT/errs" \
     && grep -q "^ERROR 사람 글로 큐 넘침 — to=$DA pending=5 (ring=3)" "$ENVROOT/errs"; then
    ok "T2 결과·판정 머리 5통 보존(버리기 0) + ERROR 넘침 1줄"; return 0
  fi
  bad "T2 rows=$(rows_to "$DA") err=$(grep -v '^WARN desk' "$ENVROOT/errs" | tr '\n' ' ' | cut -c1-300)"; return 1
}

t3() {
  new_env
  local i; for i in 1 2 3 4 5 6; do send "$PM" ft-tick "m$i"; send "$PA" ft-tick "a$i"; send "$DA" ft-tick "d$i"; done
  local pm pa da; pm="$(rows_to "$PM")"; pa="$(rows_to "$PA")"; da="$(rows_to "$DA")"
  rm -f "$FT/seats-planner.json"; for i in 7 8 9 10; do send "$PM" ft-tick "m$i"; done; local none; none="$(rows_to "$PM")"
  new_env; printf '{"_master": ' > "$FT/seats-planner.json"; for i in 1 2 3 4; do send "$PM" ft-tick "x$i"; done
  local broken; broken="$(rows_to "$PM")"
  if [ "$pm" = 5 ] && [ "$pa" = 5 ] && [ "$da" = 3 ] && [ "$none" = 3 ] && [ "$broken" = 3 ]; then
    ok "T3 _master 5 · _arch 5 · 일반 3 · 명부 없음 3 · 명부 깨짐 3"; return 0
  fi
  bad "T3 master=$pm arch=$pa da=$da none=$none broken=$broken"; return 1
}

t4() {
  new_env
  local i; for i in 1 2 3 4; do send "$DA" ft-tick "d$i"; done            # 버림 1
  local a1 m1; a1="$(alarms_to "$PM")"; [ -f "$(mark "$DA")" ] && m1=1 || m1=0
  local body; body="$(grep '"from": "ft-mbox-ring"' "$Q" | head -1)"
  send "$DA" ft-tick "d5"; local a2; a2="$(alarms_to "$PM")"            # 10분 안 재발 = 0통
  python3 -c 'import os,sys,time;t=time.time()-660;os.utime(sys.argv[1],(t,t))' "$(mark "$DA")" 2>/dev/null
  send "$DA" ft-tick "d6"; local a3; a3="$(alarms_to "$PM")"            # 10분 지남 = 1통 더
  recv "$DA"; send "$DA" ft-tick "d7"; local m2; [ -f "$(mark "$DA")" ] && m2=1 || m2=0   # pending 1 < 3 → 표식 삭제
  for i in 1 2 3 4 5 6; do send "$PM" ft-tick "p$i"; done; local h1; h1="$(alarms_to "$HM")"   # master 자신 포화 → 하네스 master
  if [ "$a1" = 1 ] && [ "$m1" = 1 ] && [ "$a2" = 1 ] && [ "$a3" = 2 ] && [ "$m2" = 0 ] && [ "$h1" = 1 ] \
     && grep -q "\[큐 포화\] to=$DA pending=3 ring=3 버림 1 oldest=#" <<<"$body"; then
    ok "T4 경보 1 · 10분 안 0 · 10분 뒤 1 · 표식 닫힘 · master 포화 → 하네스 master"; return 0
  fi
  bad "T4 a1=$a1 m1=$m1 a2=$a2 a3=$a3 m2=$m2 hm=$h1 body=[$(cut -c1-200 <<<"$body")]"; return 1
}

t5() {
  new_env
  send "$DA" "$OPS" "[HIL] ops 판정 요청"
  local i; for i in 1 2 3 4; do send "$DA" ft-tick "t$i"; done
  if [ "$(rows_from "$OPS")" = 1 ] && [ "$(rows_to "$DA")" = 3 ]; then ok "T5 좌석 [HIL] 보존"; return 0; fi
  bad "T5 hil=$(rows_from "$OPS") rows=$(rows_to "$DA")"; return 1
}

t7() {   # DA concurrent-probe 그대로 — 사본의 실 공유 블록을 읽어 실행 · send 는 관측만(큐 쓰기 0)
  new_env
  local f; case "$IMPL" in comm) f="$C/mbox_keep.py";; kit) f="$C/ft-mbox-kit.py";; skill) f="$C/ft-mbox-skill.py";; esac
  local out; out="$(FT_NAME_LINT="$C/ft-name-lint.sh" python3 - "$f" "$FT" <<'PY' 2>&1
import sys, threading
from pathlib import Path
from types import ModuleType
from concurrent.futures import ThreadPoolExecutor
path, ft = Path(sys.argv[1]), Path(sys.argv[2])
block = path.read_text(encoding="utf-8").split("# >>> r912 mbox_keep shared begin", 1)[1].split("\n", 1)[1].split("# <<< r912 mbox_keep shared end", 1)[0]
m = ModuleType("probe"); m.__file__ = str(path); exec(compile(block, str(path), "exec"), m.__dict__)
gate, original, sent = threading.Barrier(2), m.ring_alarm_to, []
def target(fd, to):
    r = original(fd, to); gate.wait(timeout=3); return r
m.ring_alarm_to = target
def send(to, frm, body, force=False): sent.append(to)
with ThreadPoolExecutor(max_workers=2) as pool:
    for fu in [pool.submit(m.ring_after, str(ft / "comm"), "byz-planner-da-codex#2", 3, 3, 1, n, send) for n in (1, 2)]:
        fu.result(timeout=5)
print("alarms=%d mark=%s" % (len(sent), (ft / "state/ring-full.byz-planner-da-codex").is_file()))
PY
)"
  if [ "$out" = "alarms=1 mark=True" ]; then ok "T7 동시 ring_after 2개(barrier) → 경보 1통 · 표식 1"; return 0; fi
  bad "T7 $(tr '\n' ' ' <<<"$out" | cut -c1-200)"; return 1
}

for IMPL in comm kit skill; do t1; t2; t3; t4; t5; t7; done
IMPL=all
bash "$HERE/test_mbox_ring_unregistered_successor_r1116c.sh" >"$T/r1116c.out" 2>&1
new_fail="$(grep '^FAIL ' "$T/r1116c.out" | grep -vE '^FAIL (변이가 안 잡힘|ⓓ R7|ⓔ holder) ' || true)"
if [ -z "$new_fail" ] && grep -q '^PASS ' "$T/r1116c.out"; then ok "T6 r1116c 새 FAIL 0(base FAIL $(grep -c '^FAIL ' "$T/r1116c.out")건 그대로·이하)"
else bad "T6 r1116c 새 FAIL: $(tr '\n' ' ' <<<"$new_fail" | cut -c1-300)"; fi
echo "결과: fail=$fail"
[ "$fail" = 0 ]
