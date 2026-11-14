#!/usr/bin/env bash
# test_mbox_ring_keep_real_reports_r1651.sh — r1651: ring(기본 10)이 차도 «실보고»는 안 버리고,
# 자기에게 보낸 사건 알림([착지]·[카드 이동])을 먼저 버리고, 버린 seq 는 받는 좌석의 다음 recv 에 보인다.
#   ⓔ① ring=3 에 실보고 2(ft-hil-h1 [완료] · 좌석 [완료]) + 일반 1 + 자기 알림 2 → «나중에 온 자기 알림» 부터 버리고 실보고 2 남는다
#   ⓔ② 실보고만 4통 = 버리기 0 · 큐 4 · ERROR 넘침 1줄(r912 꼴)
#   ⓔ③ 버림이 생기면 다음 recv 가 SCANNED 다음 줄에 DROPPED-SEEN 1줄 · 두 번째 recv 는 0줄
#   ⓔ④(DA R1) 은퇴한 옛 좌석 recv 는 표시를 소비하지 않는다 · 현역이 받는다
#   ⓔ⑤(DA R2) 동시 report 2개가 표식을 잃지 않는다 · 이미 보여준 seq 재표시 0
# 변이(사본에만): M1 ft-hil-h 정규식 삭제 · M2 from==to 규칙 삭제 · M3 recv 유실 줄 삭제
#   M4 표식 갱신 잠금 삭제 · M5 현역 소유권 가드 삭제
# 정본 .py 를 임시 폴더에 복사해 돈다 — 실 큐·실 doorbell 쓰기 0(측정 조작 금지 · 오빠 절대지침).
set -uo pipefail
export FT_MBOX_RING_LEAD=1   # r1466 역할 좌석(_master·_arch·_desk) 상한 = 옛 ring 과 같게 — 이 시험의 관심은 등급·역할 합이다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT   # ⓔ⑤ 가 & 로 띄운 자식 정리(r1234)
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
MASTER="byz-x-master-claude#1"

new_env() {   # 격리 루트 · 빈 큐 · ring 3 · comm 사본(mbox*.py 전부 = mbox_drops 포함) · MUT 변이
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/seats"; cp "$SRC"/mbox*.py "$C/"
  cp "$REPO/harness/bin/ft-name-lint.sh" "$C/"
  : > "$Q"; : > "$ENVROOT/errs"
  printf '{"_master": "byz-x-master-claude#1"}\n' > "$ENVROOT/seats/seats.json"
  if [ -n "${MUT:-}" ]; then "$MUT"; fi
}
send() {   # send <to> <from> <body> — 발신 가드는 이 시험의 관심이 아니다 → --force
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RING=3 \
    python3 "$C/mbox.py" send "$1" "$2" "$3" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?
  cat "$ENVROOT/err" >> "$ENVROOT/errs"
}
recv() {   # recv <me>
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_MBOX_RING=3 \
    python3 "$C/mbox.py" recv "$1" >"$ENVROOT/recv" 2>"$ENVROOT/rerr"; RC=$?
}
rows_to() { grep -c "\"to\": \"$1\"" "$Q"; }
rows_from() { grep -c "\"from\": \"$1\"" "$Q"; }

# ── 변이(사본에만 · 원본 0): M1 실보고 정규식 삭제 · M2 자기 알림 규칙 삭제 · M3 recv 유실 줄 삭제
mut_m1() { sed -i '' 's/^    if REAL_SENDERS.match(frm):$/    if False:/' "$C/mbox_keep.py"; grep -q '^    if False:$' "$C/mbox_keep.py"; }
mut_m2() { sed -i '' 's/^    if frm and frm == str(r.get("to") or ""):$/    if False:/' "$C/mbox_keep.py"; grep -q '^    if False:$' "$C/mbox_keep.py"; }
mut_m3() { sed -i '' 's/^    if not succ and (lost := .*$/    if False:/' "$C/mbox_ops.py"; grep -q '^    if False:$' "$C/mbox_ops.py"; }
mut_m4() { sed -i '' 's/^    return _locked(canon, lambda: _mark(canon, me, names, lines))$/    return _mark(canon, me, names, lines)/' "$C/mbox_drops.py"; grep -q '^    return _mark(' "$C/mbox_drops.py"; }
mut_m5() { sed -i '' 's/^    if not succ and (lost := mbox_drops.report/    if (lost := mbox_drops.report/' "$C/mbox_ops.py"; grep -q '^    if (lost := ' "$C/mbox_ops.py"; }

# ── ⓔ① 실보고는 남고 자기 알림만 먼저 버려진다(M1·M2 가 여기서 빨강)
e1() {
  new_env
  send "$MASTER" ft-hil-h1 "[완료 h8178] rc=0"
  send "$MASTER" byz-x-nano-a#0 "[완료 h8180] rc=0"
  send "$MASTER" byz-x-da-codex#2 "쪽지 1"
  send "$MASTER" "$MASTER" "[착지] byz-x-nano-a#0"
  send "$MASTER" "$MASTER" "[카드 이동] r1651 → 완성"
  if [ "$(rows_to "$MASTER")" = 3 ] && [ "$(rows_from ft-hil-h1)" = 1 ] \
     && [ "$(rows_from byz-x-nano-a#0)" = 1 ] && [ "$(rows_from byz-x-da-codex#2)" = 1 ] \
     && [ "$(rows_from "$MASTER")" = 0 ] && [ "$(grep -c '^DROPPED' "$ENVROOT/errs")" = 2 ]; then
    ok "ⓔ① «나중에 온 자기 알림» 2통이 먼저 버려짐 · 실보고 2 + 일반 1 남음(큐 3)"; return 0
  fi
  bad "ⓔ① rows=$(rows_to "$MASTER") hil=$(rows_from ft-hil-h1) nano=$(rows_from byz-x-nano-a#0) da=$(rows_from byz-x-da-codex#2) self=$(rows_from "$MASTER") drops=$(grep -c '^DROPPED' "$ENVROOT/errs")"; return 1
}

# ── ⓔ② 실보고만 넘치면 «버리기 0» + ERROR 1줄(r912 꼴)
e2() {
  new_env
  send R2 slack-oppa "[HIL] 사람 글 1"
  send R2 ft-hil-h2 "[완료 h8181] rc=0"
  send R2 byz-x-nano-b#0 "[완료 h8182] rc=0"
  send R2 ft-hil-h3 "[HIL] h8183 발급"
  if [ "$(rows_to R2)" = 4 ] && ! grep -q '^DROPPED' "$ENVROOT/errs" \
     && grep -q '^ERROR 사람 글로 큐 넘침 — to=R2 pending=4 (ring=3)' "$ENVROOT/errs"; then
    ok "ⓔ② 실보고 4통 보존(버리기 0) + ERROR 넘침 1줄"; return 0
  fi
  bad "ⓔ② rows=$(rows_to R2) err=$(tr '\n' ' ' < "$ENVROOT/errs")"; return 1
}

# ── ⓔ③ 버린 seq 가 받는 좌석의 다음 recv 에 1줄 · 같은 seq 는 두 번 안 보인다(M3 가 여기서 빨강)
e3() {
  new_env
  for i in 1 2 3 4 5; do send "$MASTER" "$MASTER" "[착지] byz-x-nano-a#0 $i"; done
  local seqs; seqs="$(sed -n 's/.*seqs=//p' "$C/mailbox.drops.log" 2>/dev/null | tr '\n' ' ')"
  recv "$MASTER"; cp "$ENVROOT/recv" "$ENVROOT/recv1"
  local first line s seen=1
  first="$(grep -c '^DROPPED-SEEN 2 #' "$ENVROOT/recv1")"
  line="$(grep '^DROPPED-SEEN 2 #' "$ENVROOT/recv1")"
  for s in $seqs; do grep -q "#$s" <<<"$line" || seen=0; done
  recv "$MASTER"; local second; second="$(grep -c '^DROPPED-SEEN' "$ENVROOT/recv")"
  if [ "$(grep -c '^DROPPED' "$ENVROOT/errs")" = 2 ] && [ "$seen" = 1 ] && [ "$first" = 1 ] \
     && [ "$second" = 0 ] && [ "$(head -1 "$ENVROOT/recv1" | cut -c1-7)" = "SCANNED" ]; then
    ok "ⓔ③ 원장 seqs=$seqs · 다음 recv 에 DROPPED-SEEN 1줄(SCANNED 다음) · 두 번째 recv 0줄"; return 0
  fi
  bad "ⓔ③ seqs=[$seqs] line=[$line] first=$first second=$second"; return 1
}

# ── ⓔ④(DA R1) 은퇴한 옛 좌석은 표시를 못 먹는다 — 소유권은 recv 계보 규칙 그대로(M5 가 여기서 빨강)
e4() {
  new_env
  printf '{"_master": "byz-zz-master-claude#79", "byz-zz-master-claude#78": {"_replaced_by": "byz-zz-master-claude#79"}}\n' \
    > "$ENVROOT/seats/seats-zz.json"
  for i in 1 2 3 4 5; do send byz-zz-master-claude#79 ft-tick "[HIL] 뉴스 $i"; done   # ring 3 → 2통 버림
  local seqs; seqs="$(sed -n 's/.*seqs=//p' "$C/mailbox.drops.log" 2>/dev/null | tr '\n' ' ')"
  recv byz-zz-master-claude#78; local old; old="$(grep -c '^DROPPED-SEEN' "$ENVROOT/recv")"
  recv byz-zz-master-claude#79; cp "$ENVROOT/recv" "$ENVROOT/recv2"
  local new line s seen=1
  new="$(grep -c '^DROPPED-SEEN 2 #' "$ENVROOT/recv2")"; line="$(grep '^DROPPED-SEEN 2 #' "$ENVROOT/recv2")"
  for s in $seqs; do grep -q "#$s" <<<"$line" || seen=0; done
  if [ "$old" = 0 ] && [ "$new" = 1 ] && [ "$seen" = 1 ]; then
    ok "ⓔ④ 은퇴 #78 표시 0줄 · 현역 #79 가 DROPPED-SEEN 2 #$seqs 받음"; return 0
  fi
  bad "ⓔ④ old=$old new=$new line=[$line] seqs=[$seqs]"; return 1
}

# ── ⓔ⑤(DA R2) 동시 report 2개 — 표식 키가 둘 다 남고, 이미 보여준 seq 는 다시 안 나온다(M4 가 여기서 빨강)
e5() {
  new_env
  cat > "$T/child.py" <<'CHILD'
import json, os, sys, time
comm, me, ready, go = sys.argv[1:5]
sys.path.insert(0, comm)
import mbox_drops
real = json.load
def slow(f, *a, **k):            # 표식 읽기 직후 «둘 다 읽었다» 를 맞춘다 — report 단위 검증(제품 파일 그대로)
    d = real(f, *a, **k)
    open(os.path.join(ready, os.path.basename(me)), "w").close()
    t0 = time.time()
    while not os.path.exists(go) and time.time() - t0 < 1.0:
        pass
    return d
json.load = slow
print(mbox_drops.report(comm, me, [me]))
CHILD
  python3 - "$C" <<'SEED'
import sys; sys.path.insert(0, sys.argv[1])
import mbox_drops
mbox_drops.log_drop(sys.argv[1], "byz-zz-master-claude#79", 1, 1601, [1601])
mbox_drops.log_drop(sys.argv[1], "byz-zz-da-codex#10", 1, 1602, [1602])
SEED
  mkdir -p "$ENVROOT/ready"
  python3 "$T/child.py" "$C" byz-zz-master-claude#79 "$ENVROOT/ready" "$ENVROOT/go" >"$ENVROOT/a.out" 2>&1 &
  python3 "$T/child.py" "$C" byz-zz-da-codex#10 "$ENVROOT/ready" "$ENVROOT/go" >"$ENVROOT/b.out" 2>&1 &
  python3 - "$ENVROOT/ready" "$ENVROOT/go" <<'GO'
import os, sys, time
ready, go, t0 = sys.argv[1], sys.argv[2], time.time()
while len(os.listdir(ready)) < 2 and time.time() - t0 < 1.5:   # 잠금이 직렬화하면 한쪽만 준비된다 → 시간 상한
    time.sleep(0.005)
open(go, "w").close()
GO
  wait
  local keys again
  keys="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]+"/mailbox.drops.seen.json",encoding="utf-8"))))' "$C")"
  again="$(python3 - "$C" <<'AGAIN'
import sys; sys.path.insert(0, sys.argv[1])
import mbox_drops
print(sum(bool(mbox_drops.report(sys.argv[1], m, [m])) for m in ("byz-zz-master-claude#79", "byz-zz-da-codex#10")))
AGAIN
)"
  if [ "$(grep -c '^DROPPED-SEEN 1 #' "$ENVROOT/a.out")" = 1 ] && [ "$(grep -c '^DROPPED-SEEN 1 #' "$ENVROOT/b.out")" = 1 ] \
     && [ "$keys" = 2 ] && [ "$again" = 0 ]; then
    ok "ⓔ⑤ 동시 report 2개 → 표식 키 2개 보존 · 재표시 0"; return 0
  fi
  bad "ⓔ⑤ a=$(tr '\n' ' ' < "$ENVROOT/a.out") b=$(tr '\n' ' ' < "$ENVROOT/b.out") keys=$keys again=$again"; return 1
}

e1; e2; e3; e4; e5
echo "--- 변이 대조(빨강이어야 정상)"
for m in mut_m1 mut_m2 mut_m3 mut_m4 mut_m5; do
  rc=0
  case "$m" in
    mut_m1)        ( MUT=$m; e2 ) >/dev/null 2>&1 || rc=$?;;   # ft-hil-h 가 «일반» 이 되면 넘칠 때 버려진다
    mut_m2)        ( MUT=$m; e1 ) >/dev/null 2>&1 || rc=$?;;   # 자기 알림이 «일반» 이 되면 오래된 일반이 먼저 버려진다
    mut_m3)        ( MUT=$m; e3 ) >/dev/null 2>&1 || rc=$?;;
    mut_m4)        ( MUT=$m; e5 ) >/dev/null 2>&1 || rc=$?;;   # 잠금 삭제 = 표식 키 유실 · 재표시
    mut_m5)        ( MUT=$m; e4 ) >/dev/null 2>&1 || rc=$?;;   # 소유권 가드 삭제 = 은퇴가 표시를 먹는다
  esac
  if [ "$rc" != 0 ]; then echo "RED-OK $m"; else echo "RED-MISS $m"; fail=$((fail+1)); fi
done
echo "결과: fail=$fail"
[ "$fail" = 0 ]
