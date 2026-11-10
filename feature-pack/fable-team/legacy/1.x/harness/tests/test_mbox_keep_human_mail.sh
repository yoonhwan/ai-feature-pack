#!/usr/bin/env bash
# test_mbox_keep_human_mail.sh — r912: 큐가 넘칠 때 «버리는 순서» = 시스템 알림 → 일반 · 사람 글은 버리지 않는다.
# ★r3(반송 r3 · DA⑥)★ 분류는 «보낸 이 먼저» — slack-oppa · 좌석(byz-…-#N)의 [HIL]/[긴급] = 사람 ·
# 자동 도구(ft-tick·ft-news*·ft-secret-scan 등)는 머리가 있어도 시스템(사람 칸 0) · 그 밖 = 일반.
# 자르는 곳 «셋»(comm/mbox_ops.py · kit/ft-mbox.py · skill/ft-mbox.py)이 같은 규칙을 쓰는지 함께 본다.
#   ⓐ 사람 1 + 시스템 12 → 시스템부터 3통 버리고 사람 글은 남는다
#   ⓑ 사람 글만 10칸 + 사람 1통 → 버리기 0 · 11통 + ERROR 1줄
#   ⓒ 분류(보낸 이 먼저 · 머리는 좌석만) · 버리는 순서  ⓕ kit·skill 경로로 넘쳐도 사람 글 보존
#   ⓖ ft-tick/ft-news/ft-secret-scan 의 [HIL]/[긴급] 25통 → 사람 칸 0 · 넘친 만큼 버려진다
#   ⓗ 좌석 이름 보낸 이의 [HIL] → 사람  ⓘ 세 사본 «바이트 동일»
#   ⓚ 좌석 이름 판정 = ft-name-lint.sh 문법 그대로 — byz-tool#0·byz-x#1 은 «좌석 아님»(NORMAL) · 실 좌석 4개는 HUMAN
#      · 정본을 못 읽으면 «좌석 아님»(안전한 쪽) · 큐에서도 byz-tool#0 은 일반 쪽으로 먼저 버려진다
# 정본 .py 를 임시 폴더에 복사해 돈다 — 실 큐·실 doorbell 쓰기 0 · 변이는 사본에만 적용한다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; KIT="$REPO/harness/kit/fable-team/bin/ft-mbox.py"; SKILL="$REPO/skill/scripts/ft-mbox.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

new_env() {   # new_env [변이함수] — 격리 루트 + 빈 큐 + 세 자르기 사본. 변이함수는 사본에만 적용.
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/seats"; cp "$SRC"/mbox*.py "$C/"; cp "$KIT" "$C/kit.py"; cp "$SKILL" "$C/skill.py"
  cp "$REPO/harness/bin/ft-name-lint.sh" "$C/"   # ⓚ 좌석 이름 정본 — 런타임에선 comm/../bin 에 있다(같은 폴더로 복사해 같은 경로를 만든다)
  : > "$Q"; : > "$ENVROOT/errs"
  printf '{"_master": "byz-x-master-claude#1"}\n' > "$ENVROOT/seats/seats.json"
  if [ -n "${1:-}" ]; then "$1"; fi
}
# send <경로:comm|kit|skill> <to> <from> <body> — 발신 가드(rate·fanout)는 이 시험의 관심이 아니다 → --force.
send() {
  local how="$1"; local prog="$C/mbox.py"
  [ "$how" = kit ] && prog="$C/kit.py"; [ "$how" = skill ] && prog="$C/skill.py"
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" \
    python3 "$prog" send "$2" "$3" "$4" --force >"$ENVROOT/out" 2>"$ENVROOT/err"; RC=$?
  cat "$ENVROOT/err" >> "$ENVROOT/errs"
}
rows_to() { grep -c "\"to\": \"$1\"" "$Q"; }
rows_from() { grep -c "\"from\": \"$1\"" "$Q"; }

# 변이 ① 사람 보존 끔(모든 등급 = 0) → ⓐ 빨강 · ② 넘침 ERROR 끔 → ⓑ 빨강
# 변이 ③ 머리 우선 복귀(자동 도구의 [HIL] = 사람) → ⓖ 빨강 · ④ kit 자르기 옛 동작(종류 무관 최근 10) → ⓕ 빨강
mut_nohuman() { sed -i '' 's/^SYS_PLAIN, SYS_HEAD, NORMAL, HUMAN = 0, 1, 2, 3.*/SYS_PLAIN, SYS_HEAD, NORMAL, HUMAN = 0, 0, 0, 0/' "$C/mbox_keep.py"; grep -q '= 0, 0, 0, 0' "$C/mbox_keep.py"; }
mut_noerror() { sed -i '' 's/^    if overflow:/    if False:/' "$C/mbox_ops.py"; grep -q '    if False:' "$C/mbox_ops.py"; }
mut_headfirst() { sed -i '' 's/^        return SYS_HEAD if head else SYS_PLAIN.*/        return HUMAN if head else SYS_PLAIN/' "$C/mbox_keep.py"; grep -q 'return HUMAN if head' "$C/mbox_keep.py"; }
mut_kitold() { sed -i '' 's/^            k, d, _oldest, ov = trim(rs, MAX_PER_TO)$/            k, d, _oldest, ov = rs[-MAX_PER_TO:], max(0, len(rs) - MAX_PER_TO), None, 0/' "$C/kit.py"; grep -q 'rs\[-MAX_PER_TO:\], max' "$C/kit.py"; }
mut_skillold() { sed -i '' 's/^            k, d, _oldest, ov = trim(rs, MAX_PER_TO)$/            k, d, _oldest, ov = rs[-MAX_PER_TO:], max(0, len(rs) - MAX_PER_TO), None, 0/' "$C/skill.py"; grep -q 'rs\[-MAX_PER_TO:\], max' "$C/skill.py"; }
mut_wide() { sed -i '' 's/^    if head and seat(frm):$/    if head and _re.match(r"^byz-[a-z0-9][a-z0-9-]*#[0-9]+$", frm):/' "$C/mbox_keep.py"; grep -q 'byz-\[a-z0-9\]\[a-z0-9-\]\*#' "$C/mbox_keep.py"; }

# ── ⓐ 사람 1통 + 시스템 12통 → 시스템 3통만 버린다(사람 글 잔존)
a_case() {
  new_env "${1:-}"
  send comm R1 slack-oppa "[HIL] 오빠 슬랙 1건 — desk 응답 없음"
  for i in $(seq 1 12); do send comm R1 ft-model-swap "[자동 교대 불가] byz-x-arch-claude#$i · 대체 모델 없음"; done
  if [ "$(rows_to R1)" = 10 ] && [ "$(rows_from slack-oppa)" = 1 ] && [ "$(rows_from ft-model-swap)" = 9 ] \
     && [ "$(grep -c '^DROPPED' "$ENVROOT/errs")" = 3 ]; then
    ok "ⓐ 사람 1 + 시스템 12 → 큐 10(사람 1 · 시스템 9) · DROPPED 3회"; return 0
  fi
  bad "ⓐ rows_to=$(rows_to R1) human=$(rows_from slack-oppa) system=$(rows_from ft-model-swap) drops=$(grep -c '^DROPPED' "$ENVROOT/errs")"; return 1
}

# ── ⓑ 사람 글뿐인 큐 10칸 + 사람 1통 → 버리기 0 · 11통 · ERROR 1줄
b_case() {
  new_env "${1:-}"
  for i in $(seq 1 10); do
    if [ $((i % 2)) = 0 ]; then send comm R2 slack-oppa "[HIL] 사람 글 $i"; else send comm R2 byz-x-master-claude#1 "[긴급] 사람 글 $i"; fi
  done
  send comm R2 slack-oppa "[HIL] 사람 글 11 — 마지막"
  if [ "$(rows_to R2)" = 11 ] && grep -q '^ERROR 사람 글로 큐 넘침 — to=R2 pending=11' "$ENVROOT/errs" && ! grep -q '^DROPPED' "$ENVROOT/errs"; then
    ok "ⓑ 사람 글 11통 보존(버리기 0) + ERROR 1줄"; return 0
  fi
  bad "ⓑ rows_to=$(rows_to R2) err=$(tr '\n' ' ' < "$ENVROOT/errs")"; return 1
}

# ── ⓒ 분류(보낸 이 먼저) · 버리는 순서 — mbox_keep 을 직접 부른다(같은 사본)
c_case() {
  new_env "${1:-}"
  local out; out="$(python3 - "$C" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import mbox_keep as k
pairs = [("slack-oppa", "본문"), ("byz-x-master-claude#1", "[HIL] 질문"), ("x#1", "[긴급] 멈춤"),
         ("ft-model-swap", "[자동 교대 불가]"), ("ft-tick", "뉴스"), ("byz-x-arch-claude#2", "쪽지"),
         ("x#1", "머리에 없음 [HIL]"), ("ft-index-move", "[완료] 이동"), ("ft-tick", "[HIL] 뉴스"),
         ("ft-news-ledger", "[긴급] 경보"), ("ft-secret-scan", "[HIL] 비밀"), ("slack-oppa", ""),
         ("byz-x-nano-r912-x#0", "[긴급] 멈춤")]
print("C", [k.kind({"from": f, "body": b}) for f, b in pairs])
rows = [{"seq": 1, "from": "byz-x-nano#1", "body": "일반"}, {"seq": 2, "from": "ft-tick", "body": "뉴스"},
        {"seq": 3, "from": "ft-tick", "body": "[HIL] 뉴스"}, {"seq": 4, "from": "ft-model-swap", "body": "교대"},
        {"seq": 5, "from": "slack-oppa", "body": "[HIL] 사람"}]
for n in (4, 3):
    keep, drop, oldest, over = k.trim(rows, n)
    print("순서", n, [r["seq"] for r in keep], drop, oldest, over)
rows2 = [{"seq": i, "from": "slack-oppa", "body": "사람"} for i in range(1, 12)]
keep2, drop2, oldest2, over2 = k.trim(rows2, 10)
print("사람", len(keep2), drop2, over2)
PY
)"
  if grep -q '^C \[3, 3, 2, 0, 0, 2, 2, 0, 1, 1, 1, 3, 3\]$' <<<"$out" \
     && grep -q '^순서 4 \[1, 3, 4, 5\] 1 2 0$' <<<"$out" && grep -q '^순서 3 \[1, 3, 5\] 2 2 0$' <<<"$out" \
     && grep -q '^사람 11 0 1$' <<<"$out"; then
    ok "ⓒ 보낸 이 먼저 분류(사람 3·일반 2·시스템머리 1·시스템 0) · 자동 먼저 버림 · 사람은 버리기 0"; return 0
  fi
  bad "ⓒ $(tr '\n' ' ' <<<"$out")"; return 1
}

# ── ⓕ kit·skill 경로로 넘쳐도 사람 글이 남는다(자르는 곳 셋 = 한 규칙)
#    변이 대조 때는 부르는 쪽이 «이미 변이를 걸어 둔 환경» 을 넘긴다(KEEP_ENV=1) — 다시 만들면 변이가 사라진다.
f_case() {
  if [ -z "${KEEP_ENV:-}" ]; then new_env "${1:-}"; fi
  local how want_h=1 want_d=3
  for how in kit skill; do
    send "$how" "R5-$how" slack-oppa "[HIL] 오빠 슬랙 — $how 경로"
    for i in $(seq 1 12); do send "$how" "R5-$how" ft-model-swap "[자동 교대 불가] byz-x-arch-claude#$i"; done
    if [ "$(rows_to "R5-$how")" = 10 ] && [ "$(rows_from slack-oppa)" = "$want_h" ] && [ "$(grep -c '^DROPPED' "$ENVROOT/errs")" = "$want_d" ]; then
      ok "ⓕ $how 경로 사람 1 보존 · 시스템 3통 버림"
    else
      bad "ⓕ $how rows_to=$(rows_to "R5-$how") human=$(rows_from slack-oppa) drops=$(grep -c '^DROPPED' "$ENVROOT/errs")"; return 1
    fi
    want_h=2; want_d=6
  done
  return 0
}

# ── ⓖ 자동 도구가 [HIL]/[긴급] 을 달고 25통 → 사람 칸 0 · 넘친 만큼 버려진다(큐 무한 증가 0)
g_case() {
  new_env "${1:-}"
  send comm R3 slack-oppa "[HIL] 오빠 슬랙 — desk 응답 없음"
  for i in $(seq 1 10); do send comm R3 ft-tick "[HIL] 뉴스 $i"; done
  for i in $(seq 1 10); do send comm R3 ft-news-ledger "[긴급] 장바구니 $i"; done
  for i in $(seq 1 5); do send comm R3 ft-secret-scan "[HIL] 비밀 의심 $i"; done
  if [ "$(rows_to R3)" = 10 ] && [ "$(rows_from slack-oppa)" = 1 ] \
     && [ "$(rows_from ft-tick)" = 0 ] && [ "$(rows_from ft-news-ledger)" = 4 ] && [ "$(rows_from ft-secret-scan)" = 5 ] \
     && [ "$(grep -c '^DROPPED' "$ENVROOT/errs")" = 16 ] && ! grep -q '^ERROR 사람 글로 큐 넘침' "$ENVROOT/errs"; then
    ok "ⓖ 자동 [HIL]/[긴급] 25통 = 시스템(사람 칸 0) · 16통 버림 · 큐 10"; return 0
  fi
  bad "ⓖ rows_to=$(rows_to R3) human=$(rows_from slack-oppa) tick=$(rows_from ft-tick) news=$(rows_from ft-news-ledger) sec=$(rows_from ft-secret-scan) drops=$(grep -c '^DROPPED' "$ENVROOT/errs")"; return 1
}

# ── ⓗ 좌석 이름 보낸 이의 [HIL] = 사람(안 버린다)
h_case() {
  new_env "${1:-}"
  send comm R4 byz-x-master-claude#1 "[HIL] 사람 판정 질문"
  for i in $(seq 1 12); do send comm R4 ft-tick "뉴스 $i"; done
  if [ "$(rows_to R4)" = 10 ] && [ "$(rows_from byz-x-master-claude#1)" = 1 ] && [ "$(rows_from ft-tick)" = 9 ]; then
    ok "ⓗ 좌석 [HIL] → 사람(보존) · 시스템 3통 버림"; return 0
  fi
  bad "ⓗ rows_to=$(rows_to R4) seat=$(rows_from byz-x-master-claude#1) sys=$(rows_from ft-tick)"; return 1
}

# ── ⓘ 세 사본 «바이트 동일» — 한 곳만 고치면 그 경로로 사람 글이 다시 버려진다
i_case() {
  new_env
  local out; out="$(python3 - "$SRC/mbox_keep.py" "$KIT" "$SKILL" <<'PY'
import re, sys
pat = re.compile(r"^# >>> r912 mbox_keep shared begin.*?^# <<< r912 mbox_keep shared end\n", re.S | re.M)
blocks = []
for p in sys.argv[1:]:
    m = pat.search(open(p, encoding="utf-8").read())
    blocks.append(m.group(0) if m else "")
print("동일", len({b for b in blocks}) == 1 and bool(blocks[0]), len(blocks[0]))
PY
)"
  if grep -q '^동일 True ' <<<"$out"; then ok "ⓘ 세 사본 동일($(sed 's/^동일 True //' <<<"$out")바이트)"; return 0; fi
  bad "ⓘ $(tr '\n' ' ' <<<"$out")"; return 1
}

# ── ⓚ 좌석 이름 판정 = ft-name-lint.sh 문법 — 역할·에이전트 칸이 없는 byz-tool#0·byz-x#1 은 «좌석 아님»
#    (반송 r4 ①: 옛 정규식은 이 둘을 좌석으로 읽어 [HIL] 25통을 전부 사람 칸에 넣었다)
k_case() {
  new_env "${1:-}"
  local out; out="$(python3 - "$C" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import mbox_keep as k
names = [("byz-tool#0", "[HIL] 자동 도구"), ("byz-x#1", "[긴급] 멈춤"),
         ("byz-x-master-claude#1", "[HIL] 질문"), ("byz-x-nano-a#0", "[긴급] 멈춤"),
         ("byz-x-da-codex#2", "[HIL] 판정"),
         ("byz-harness-nano-r912-mbox-queue-keep-human-mail-coalesce#0", "[HIL] 나노"),
         ("byz-x-master-claude-extra#1", "[HIL] 에이전트 칸 아님"), ("byz-x-master#1", "[HIL] 꼬리 없음")]
print("K", [k.kind({"from": f, "body": b}) for f, b in names])
PY
)"
  # 정본(ft-name-lint.sh)을 못 읽으면 «좌석 아님» — 사람 칸을 넓히지 않는 쪽(DA⑥ 반례 1)
  local fc; fc="$(FT_NAME_LINT="$T/none.sh" python3 - "$C" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import mbox_keep as k
print("FC", k.kind({"from": "byz-x-master-claude#1", "body": "[HIL] 질문"}), repr(k.LINT))
PY
)"
  # 큐에서도 byz-tool#0 은 «보통(NORMAL)» 쪽 — 사람 글(slack-oppa)이 남고 byz-tool#0 이 버려진다
  send comm R6 slack-oppa "[HIL] 오빠 슬랙 — 보존되어야 한다"
  for i in $(seq 1 11); do send comm R6 byz-tool#0 "[HIL] 자동 도구 알림 $i"; done
  if grep -q '^K \[2, 2, 3, 3, 3, 3, 2, 2\]$' <<<"$out" && grep -q "^FC 2 " <<<"$fc" \
     && [ "$(rows_to R6)" = 10 ] && [ "$(rows_from slack-oppa)" = 1 ] && [ "$(rows_from byz-tool#0)" = 9 ] \
     && [ "$(grep -c '^DROPPED' "$ENVROOT/errs")" = 2 ]; then
    ok "ⓚ byz-tool#0·byz-x#1 = 좌석 아님(일반) · 실 좌석 4개 = 사람 · 정본 부재 = 좌석 아님 · 큐에서 일반으로 버려지고 사람 글은 남는다"; return 0
  fi
  bad "ⓚ $(tr '\n' ' ' <<<"$out") $(tr '\n' ' ' <<<"$fc") human=$(rows_from slack-oppa) tool=$(rows_from byz-tool#0) drops=$(grep -c '^DROPPED' "$ENVROOT/errs")"; return 1
}

a_case; b_case; c_case; f_case; g_case; h_case; i_case; k_case
echo "--- 변이 대조(빨강이어야 정상)"
for m in mut_nohuman mut_noerror mut_headfirst mut_kitold mut_skillold mut_wide; do
  rc=0
  case "$m" in
    mut_nohuman)   ( a_case "$m" ) >/dev/null 2>&1 || rc=$?;;
    mut_noerror)   ( b_case "$m" ) >/dev/null 2>&1 || rc=$?;;
    mut_headfirst) ( g_case "$m" ) >/dev/null 2>&1 || rc=$?;;
    mut_kitold)    ( KEEP_ENV=1; new_env "$m"; f_case ) >/dev/null 2>&1 || rc=$?;;
    mut_skillold)  ( KEEP_ENV=1; new_env "$m"; f_case ) >/dev/null 2>&1 || rc=$?;;
    mut_wide)      ( k_case "$m" ) >/dev/null 2>&1 || rc=$?;;
  esac
  if [ "$rc" != 0 ]; then echo "RED-OK $m"; else echo "RED-MISS $m"; fail=$((fail+1)); fi
done
echo "결과: fail=$fail"
[ "$fail" = 0 ]
