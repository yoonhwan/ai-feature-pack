#!/bin/bash
# mbox-guard.sh — 발신 규율 가드 회귀 실측(F1~F6). 격리 우편함·doorbell 없음(--no-notify).
# 케이스별 기대 rc/값을 실측값과 비교해 PASS/FAIL 누적, 끝에 PASS=n FAIL=m, FAIL>0이면 exit 1.
# zsh 함정 회피: 명시적 #!/bin/bash, 배열 인자는 quoting.
set +e
HERE="$(cd "$(dirname "$0")" && pwd)"
MBOX="$HERE/../skill/scripts/ft-mbox.sh"
MBOXPY="$HERE/../skill/scripts/ft-mbox.py"
export FT_MBOX_DIR="$(mktemp -d)"
export FT_MBOX_RELAY_DIR="$(mktemp -d)"
export FT_MBOX_RATE_N=100          # RATE 간섭 회피 — RATE 케이스만 서브셸에서 5로 재설정.

PASS=0; FAIL=0
ok() {  # $1=desc  $2=expected  $3=actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "PASS $1 (=$3)"
  else FAIL=$((FAIL+1)); echo "FAIL $1 (expected $2 got $3)"; fi
}

PFX=$(printf 'x%.0s' {1..250})    # 250자 접두(>200, F2 검증용)

# T1 send rc0
bash "$MBOX" send seatA orch "hello-body-1" --no-notify >/dev/null 2>&1; ok "T1 send" 0 $?
# T2 같은 본문 pending 재발신 rc3 RESEND
bash "$MBOX" send seatA orch "hello-body-1" --no-notify >/dev/null 2>&1; ok "T2 resend-pending RESEND" 3 $?
# T3 recv에 READ 1행
out=$(bash "$MBOX" recv seatA 2>&1)
ok "T3 recv 1 READ" 1 "$(printf '%s\n' "$out" | grep -c '^READ ')"
# T4 소비 후 같은 본문 rc0 (F1)
bash "$MBOX" send seatA orch "hello-body-1" --no-notify >/dev/null 2>&1; ok "T4 resend-after-consume" 0 $?
# T5 250자 접두 + tail-ONE rc0
bash "$MBOX" send seatC orch "${PFX}ONE" --no-notify >/dev/null 2>&1; ok "T5 250prefix-ONE" 0 $?
# T6 같은 접두 + tail-TWO rc0 (F2 전문 해시라 ONE≠TWO)
bash "$MBOX" send seatC orch "${PFX}TWO" --no-notify >/dev/null 2>&1; ok "T6 250prefix-TWO (F2)" 0 $?
# T7 T5 본문을 다른 좌석으로 rc3 FANOUT
bash "$MBOX" send seatD orch "${PFX}ONE" --no-notify >/dev/null 2>&1; ok "T7 FANOUT other-seat" 3 $?
# T8 --force로 pending 중복 rc0, peek pending=2
bash "$MBOX" send seatE orch "dup-body-8" --no-notify >/dev/null 2>&1
bash "$MBOX" send seatE orch "dup-body-8" --no-notify --force >/dev/null 2>&1; ok "T8 force-dup" 0 $?
pk=$(bash "$MBOX" peek seatE 2>&1)
ok "T8 peek pending=2" 2 "$(printf '%s\n' "$pk" | grep -oE 'pending=[0-9]+' | head -1 | cut -d= -f2)"
# T9 빈 본문 rc3 EMPTY_BODY
bash "$MBOX" send seatF orch "" --no-notify >/dev/null 2>&1; ok "T9 empty EMPTY_BODY" 3 $?
# T10 빈 본문 --force rc0
bash "$MBOX" send seatF orch "" --no-notify --force >/dev/null 2>&1; ok "T10 empty-force" 0 $?
# T11 RATE_N=5에서 6번째 rc3 (서브셸 격리 + 전용 from으로 사전 발신 누적 회피)
(
  export FT_MBOX_RATE_N=5
  for i in 1 2 3 4 5; do bash "$MBOX" send seatR rateuser "rate-body-$i" --no-notify >/dev/null 2>&1; done
  bash "$MBOX" send seatR rateuser "rate-body-6" --no-notify >/dev/null 2>&1; exit $?
)
ok "T11 RATE 6th" 3 $?
# T12 relay 요약 공백 보존(READ에 원문 그대로)
echo "content-12" > "$FT_MBOX_RELAY_DIR/src12.txt"
bash "$MBOX" relay seatG orch "$FT_MBOX_RELAY_DIR/src12.txt" "hello   spaced   summary" --no-notify >/dev/null 2>&1
out=$(bash "$MBOX" recv seatG 2>&1)
printf '%s\n' "$out" | grep -q 'hello   spaced   summary'; ok "T12 relay ws-preserved" 0 $?
# T13 개행 보존
bash "$MBOX" send seatH orch "$(printf 'aaa\nbbb')" --no-notify >/dev/null 2>&1
out=$(bash "$MBOX" recv seatH 2>&1)
printf '%s\n' "$out" | grep -qx 'bbb'; ok "T13 newline-preserved" 0 $?
# T14 relay --force가 요약에 안 섞임(READ 본문에 --force 없음) (F3)
echo "content-14" > "$FT_MBOX_RELAY_DIR/src14.txt"
bash "$MBOX" relay seatI orch "$FT_MBOX_RELAY_DIR/src14.txt" "summary14" --no-notify --force >/dev/null 2>&1; rc=$?
out=$(bash "$MBOX" recv seatI 2>&1)
if [ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q -- '--force'; then ok "T14 relay-force not-in-summary" 0 0
else ok "T14 relay-force not-in-summary" 0 1; fi
# T15 relay 같은 요약 2회 — 스냅샷 경로가 달라 전문 해시가 다르므로 rc0
echo "content-15" > "$FT_MBOX_RELAY_DIR/src15.txt"
bash "$MBOX" relay seatJ orch "$FT_MBOX_RELAY_DIR/src15.txt" "same-summary-15" --no-notify >/dev/null 2>&1
bash "$MBOX" relay seatJ orch "$FT_MBOX_RELAY_DIR/src15.txt" "same-summary-15" --no-notify >/dev/null 2>&1
ok "T15 relay-same-summary-twice (경로차→해시차)" 0 $?
# T16 FT_MBOX_DIR 미설정 + 스크립트를 /tmp 복사본으로 실행 시 rc2 NO_MAILBOX_ROOT (F4)
TC=$(mktemp -d); cp "$MBOXPY" "$TC/"
( unset FT_MBOX_DIR; python3 "$TC/ft-mbox.py" send seatK orch "body16" >/dev/null 2>&1; exit $? )
ok "T16 NO_MAILBOX_ROOT" 2 $?
[ -d "$TC/.fable-team" ] && ok "T16 no-leaked-mailbox" 0 1 || ok "T16 no-leaked-mailbox" 0 0
# T17 --dispatch 700자 초과 rc0, --dispatch 빈 본문 rc3 (F5)
BIG=$(printf 'y%.0s' {1..800})
bash "$MBOX" send seatL orch "$BIG" --no-notify --dispatch >/dev/null 2>&1; ok "T17a dispatch-800chars" 0 $?
bash "$MBOX" send seatL orch "" --no-notify --dispatch >/dev/null 2>&1; ok "T17b dispatch-empty" 3 $?
# T18 본문 안의 --force 단어가 보존
bash "$MBOX" send seatM orch "please use --force here" --no-notify >/dev/null 2>&1
out=$(bash "$MBOX" recv seatM 2>&1)
printf '%s\n' "$out" | grep -q -- 'please use --force here'; ok "T18 force-word-in-body preserved" 0 $?
# T19 동시 3건 같은 본문 send(force 없이, 백그라운드 &) → 정확히 1건만 QUEUED (F6)
for i in 1 2 3; do bash "$MBOX" send seatN concurrent "same-concurrent-body" --no-notify >/dev/null 2>&1 & done
wait
pk=$(bash "$MBOX" peek seatN 2>&1)
ok "T19 concurrent-exactly-1 (F6)" 1 "$(printf '%s\n' "$pk" | grep -oE 'pending=[0-9]+' | head -1 | cut -d= -f2)"

# T20 seq 단조증가: send 3 → recv 전량 소비 → send 1. 마지막 seq가 소비된 최대 seq보다 커야 함.
#   (수정 전이면 recv가 max 행을 지워 seq가 되감겨 s4<=s3 으로 실패한다.)
s1=$(bash "$MBOX" send seatT20 t20user "t20-body-1" --no-notify 2>&1 | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
s2=$(bash "$MBOX" send seatT20 t20user "t20-body-2" --no-notify 2>&1 | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
s3=$(bash "$MBOX" send seatT20 t20user "t20-body-3" --no-notify 2>&1 | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
bash "$MBOX" recv seatT20 --all >/dev/null 2>&1     # 전량 소비 → 파일 max 되감김 유발
s4=$(bash "$MBOX" send seatT20 t20user "t20-body-4" --no-notify 2>&1 | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
[ -n "$s3" ] && [ -n "$s4" ] && [ "$s4" -gt "$s3" ]; ok "T20 seq-monotonic-after-consume (s3=$s3 s4=$s4)" 0 $?

# T21 카운터 손상 fail-loud: garbage 카운터 → rc≠0 이고 stderr에 카운터 경로 (격리 우편함).
t21dir="$(mktemp -d)"
printf 'garbage\n' > "$t21dir/.mbox-seq"
err=$(FT_MBOX_DIR="$t21dir" bash "$MBOX" send seatT21 t21user "t21-body" --no-notify 2>&1); rc=$?
[ "$rc" != 0 ]; ok "T21a corrupt-counter rc≠0 (rc=$rc)" 0 $?
printf '%s\n' "$err" | grep -q '\.mbox-seq'; ok "T21b corrupt-counter path-in-stderr" 0 $?

# T22 SEQ_FLOOR: 빈 우편함 첫 send seq가 1601 초과(≥1602 = floor 1601 + 1) (격리 우편함).
s22=$(FT_MBOX_DIR="$(mktemp -d)" bash "$MBOX" send seatT22 t22user "t22-body" --no-notify 2>&1 | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
[ -n "$s22" ] && [ "$s22" -ge 1602 ]; ok "T22 SEQ_FLOOR first-seq≥1602 (=$s22)" 0 $?

# T23 워크트리 깊이: 브랜치명에 슬래시가 있으면 `.worktrees/feat/wt` 처럼 두 단계다.
#     한 단계로 가정하면 «자기 워크트리 안»을 정본으로 잡아 조용히 별도 우편함을 판다
#     (에러 없이 send/recv 성공 → 그 좌석만 아무에게도 안 닿는다).
t23="$(mktemp -d)"
mkdir -p "$t23/repo/.worktrees/feat/wt1/.fable-team/bin" "$t23/repo/.worktrees/wt2/.fable-team/bin"
cp "$MBOXPY" "$t23/repo/.worktrees/feat/wt1/.fable-team/bin/"
cp "$MBOXPY" "$t23/repo/.worktrees/wt2/.fable-team/bin/"
canon_of() {  # <스크립트경로> → 그 사본이 정본으로 잡는 comm 디렉터리
  (unset FT_MBOX_DIR; python3 -c "
import importlib.util
sp=importlib.util.spec_from_file_location('m','$1')
m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m); print(m.CANON)" 2>/dev/null)
}
want="$t23/repo/.fable-team/comm"
c1="$(canon_of "$t23/repo/.worktrees/feat/wt1/.fable-team/bin/ft-mbox.py")"
c2="$(canon_of "$t23/repo/.worktrees/wt2/.fable-team/bin/ft-mbox.py")"
[ "$c1" = "$want" ]; ok "T23a two-level worktree → repo root" 0 $?
[ "$c2" = "$want" ]; ok "T23b one-level worktree → repo root (회귀)" 0 $?

# T23c union 읽기도 깊이를 가정하면 안 된다 — 두 단계 워크트리에 큐잉된 메시지가
#      보이지 않으면 그건 무증상 유실이다(recv 는 정상 종료한다).
# ★정본 판정은 «스크립트 위치»에서 유도되므로, 임시 리포 안에 사본을 두고 그걸 부른다★
#   (FT_MBOX_DIR 로 CANON 만 바꾸면 legacy 스캔은 여전히 팩 리포를 훑어 시험이 무의미해진다.)
mkdir -p "$t23/repo/.fable-team/bin" "$t23/repo/.worktrees/feat/wt1/.fable-team/comm"
cp "$MBOXPY" "$MBOX" "$t23/repo/.fable-team/bin/"
cp "$HERE/../skill/scripts/ft-lib.sh" "$t23/repo/.fable-team/bin/" 2>/dev/null
FT_MBOX_DIR="$t23/repo/.worktrees/feat/wt1/.fable-team/comm" \
  bash "$MBOX" send seatT23 t23user "t23-legacy-body" --no-notify >/dev/null 2>&1
out="$(bash "$t23/repo/.fable-team/bin/ft-mbox.sh" recv seatT23 2>&1)"
printf '%s' "$out" | grep -q 't23-legacy-body'; ok "T23c union reads two-level worktree mailbox" 0 $?

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
