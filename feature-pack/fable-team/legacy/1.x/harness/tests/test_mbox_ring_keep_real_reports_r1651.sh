#!/usr/bin/env bash
# test_mbox_ring_keep_real_reports_r1651.sh — r1651: ring(기본 10)이 차도 «실보고»는 안 버리고,
# 자기에게 보낸 사건 알림([착지]·[카드 이동])을 먼저 버리고, 버린 seq 는 받는 좌석의 다음 recv 에 보인다.
#   ⓔ① ring=3 에 실보고 2(ft-hil-h1 [완료] · 좌석 [완료]) + 일반 1 + 자기 알림 2 → «나중에 온 자기 알림» 부터 버리고 실보고 2 남는다
#   ⓔ② 실보고만 4통 = 버리기 0 · 큐 4 · ERROR 넘침 1줄(r912 꼴)
#   ⓔ③ 버림이 생기면 다음 recv 가 SCANNED 다음 줄에 DROPPED-SEEN 1줄 · 두 번째 recv 는 0줄
# 변이(사본에만): M1 ft-hil-h 정규식 삭제 · M2 from==to 규칙 삭제 · M3 recv 유실 줄 삭제
# 정본 .py 를 임시 폴더에 복사해 돈다 — 실 큐·실 doorbell 쓰기 0(측정 조작 금지 · 오빠 절대지침).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
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
mut_m3() { sed -i '' 's/^    if lost := .*$/    if False:/' "$C/mbox_ops.py"; grep -q '^    if False:$' "$C/mbox_ops.py"; }

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

e1; e2; e3
echo "--- 변이 대조(빨강이어야 정상)"
for m in mut_m1 mut_m2 mut_m3; do
  rc=0
  case "$m" in
    mut_m1)        ( MUT=$m; e2 ) >/dev/null 2>&1 || rc=$?;;   # ft-hil-h 가 «일반» 이 되면 넘칠 때 버려진다
    mut_m2)        ( MUT=$m; e1 ) >/dev/null 2>&1 || rc=$?;;   # 자기 알림이 «일반» 이 되면 오래된 일반이 먼저 버려진다
    mut_m3)        ( MUT=$m; e3 ) >/dev/null 2>&1 || rc=$?;;
  esac
  if [ "$rc" != 0 ]; then echo "RED-OK $m"; else echo "RED-MISS $m"; fail=$((fail+1)); fi
done
echo "결과: fail=$fail"
[ "$fail" = 0 ]
