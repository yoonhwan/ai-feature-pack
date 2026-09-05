#!/bin/bash
# mbox-guard.sh — 발신 규율 가드 회귀 실측(F1~F6 · seq · doorbell 굶김 · 수신측 절단).
# 격리 우편함·doorbell 없음(--no-notify). T24 만 살아 있는 tmux 세션을 쓴다.
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

# T24 doorbell 굶김 상한: outstanding 억제만 있으면 좌석이 «영구 벙어리»가 된다.
#     doorbell 은 주입됐는데 좌석이 그 입력을 삼키면 recv 가 영영 안 돌고, 이후 모든
#     send 가 skip 된다(실측: 좌석 2개가 19시간 벙어리였다). 오래된 outstanding 은
#     소비될 가망이 없다고 보고 다시 울려야 한다.
#     ★doorbell 은 살아 있는 tmux 세션이 필요하다★ — 없으면 이 케이스는 건너뛴다.
if command -v tmux >/dev/null 2>&1; then
  t24sess="mbox-guard-t24-$$"
  tmux new-session -d -s "$t24sess" -c /tmp 2>/dev/null; sleep 0.4
  # ★프로브를 «좌석처럼» 만든다★ — doorbell 은 에이전트 없는 맨 셸에는 주입하지 않는다
  #   (noagent). 실좌석은 pane 아래에 agent 프로세스가 있으므로, 자식을 하나 띄워
  #   그 조건을 맞춘다. 안 그러면 이 테스트는 «가드가 옳아서» 빨개진다.
  tmux send-keys -t "$t24sess" 'sleep 600' Enter 2>/dev/null; sleep 0.6
  t24tmp="$(mktemp -d)"
  db() { FT_MBOX_DIR="$(mktemp -d)" TMPDIR="$t24tmp" FT_MBOX_DOORBELL_MIN=0 \
         bash "$MBOX" send "$t24sess" t24user "$1" 2>&1 | grep -oE 'doorbell=[a-z]+'; }
  a="$(db t24-a)"; b="$(db t24-b)"
  [ "$a" = "doorbell=sent" ]; ok "T24a 첫 doorbell sent (=$a)" 0 $?
  [ "$b" = "doorbell=skipped" ]; ok "T24b outstanding 억제 (=$b)" 0 $?
  # recv 없이 doorbell 스탬프만 과거로 → «삼켜진 채 오래된» 상태를 만든다
  touch -t "$(date -v-130S '+%Y%m%d%H%M.%S')" \
        "$t24tmp/mbox-doorbell-$(printf '%s' "$t24sess" | tr -c 'A-Za-z0-9._#-' '_')" 2>/dev/null
  c="$(db t24-c)"
  [ "$c" = "doorbell=sent" ]; ok "T24c 굶김 상한 초과 → 다시 울린다 (=$c)" 0 $?
  d="$(db t24-d)"
  [ "$d" = "doorbell=skipped" ]; ok "T24d 최근 outstanding 은 여전히 억제 (=$d)" 0 $?
  tmux kill-session -t "$t24sess" 2>/dev/null || true
else
  echo "SKIP T24 doorbell-starvation (tmux 없음)"
fi

# T25 길이 규율 전환(B1, 2026-09-05): 700자는 «발신 차단»이 아니라 «수신 절단» 기준이다.
#     이전엔 초과 send 가 BODY_TOO_LONG(rc3)으로 막혔는데, 그 상한이 사람에게 가르친 것은
#     relay 가 아니라 --force 였다(실측: 정본 큐 51건 중 16건(31%)이 700자 초과, relay 형식 0건).
#     이제 ①send 는 통과 ②전문을 <CANON>/bodies/<seq>.txt 에 «큐잉 전»에 박음 ③recv 가 잘라 읽음.
#     ★RECV_LIMIT(표시 «건수» 5)과 다른 축이다★ — 이건 «본문 길이» 절단이다.
T25BIG=$(printf 'z%.0s' {1..800})
out=$(bash "$MBOX" send seatT25 t25user "$T25BIG" --no-notify 2>&1); ok "T25a 800자 send 차단 안 됨" 0 $?
t25seq=$(printf '%s\n' "$out" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
# T25c 는 recv «전»에 본다 — recv 는 행을 소비하므로 순서가 바뀌면 seq 를 잃는다.
t25body="$FT_MBOX_DIR/bodies/$t25seq.txt"
[ -f "$t25body" ]; ok "T25c bodies/<seq>.txt 존재 (seq=$t25seq)" 0 $?
[ "$(cat "$t25body" 2>/dev/null)" = "$T25BIG" ]; ok "T25c 전문이 원문과 동일" 0 $?
out=$(bash "$MBOX" recv seatT25 2>&1)
printf '%s\n' "$out" | grep -qF "전문: $t25body (800자)"; ok "T25b recv 전문경로+글자수" 0 $?
ok "T25b 본문 700자에서 잘림" 700 "$(printf '%s\n' "$out" | grep '^READ ' | head -1 \
    | python3 -c "import sys;print(len(sys.stdin.readline().rstrip(chr(10)).split(' — ',1)[1]))")"
# T25d 회귀: 700자 «이하»는 절단도 전문경로 부착도 없다.
T25OK=$(printf 'w%.0s' {1..700})
bash "$MBOX" send seatT25d t25user "$T25OK" --no-notify >/dev/null 2>&1
out=$(bash "$MBOX" recv seatT25d 2>&1)
ok "T25d 700자는 전문경로 없음" 0 "$(printf '%s\n' "$out" | grep -c '전문:')"
ok "T25d 700자 본문 온전" 700 "$(printf '%s\n' "$out" | grep '^READ ' | head -1 \
    | python3 -c "import sys;print(len(sys.stdin.readline().rstrip(chr(10)).split(' — ',1)[1]))")"
[ -e "$FT_MBOX_DIR/bodies/$(bash "$MBOX" peek seatT25d 2>/dev/null | grep -oE 'latest_seq=[0-9]+' | cut -d= -f2).txt" ]
ok "T25d 700자는 bodies 파일도 안 만든다" 1 $?

# T26 bodies TTL 청소(2026-09-06): 전문 파일을 «시간»으로 자른다 — 보존 14일.
#     ★«소비 여부»가 아니라 «시간»이 기준★ — 행이 recv 로 소비돼도 그 경로는 보고서·인계에
#     «인용»되어 3~4일 뒤 열린다(실측). 소비 시점 삭제는 그 인용을 죽인다.
#     14일 = 좌석 수명 실측 p90/max 4.2일의 3배 여유. 비용 4KB/건(gitignore 아래).
T26AGED="$(date -v-20d '+%Y%m%d%H%M.%S')"
# T26a/T26b 한 우편함에서 같이 본다 — «오래된 건 지우고 최근 건은 남긴다»가 한 쌍의 주장이다.
t26="$(mktemp -d)"; mkdir -p "$t26/bodies"
echo "t26-old-full" > "$t26/bodies/1.txt"
echo "t26-new-full" > "$t26/bodies/2.txt"
touch -t "$T26AGED" "$t26/bodies/1.txt"
rm -f "$t26/.bodies-pruned"                 # 억제 스탬프 제거 → 이번 send 가 청소를 돈다
FT_MBOX_DIR="$t26" bash "$MBOX" send seatT26 t26user "t26-trigger" --no-notify >/dev/null 2>&1
[ ! -e "$t26/bodies/1.txt" ]; ok "T26a TTL 경과 전문 삭제(20일 과거)" 0 $?
[ -f "$t26/bodies/2.txt" ];   ok "T26b 최근 전문 보존" 0 $?

# T26c 억제: 스탬프가 «방금» 찍혀 있으면 오래된 파일도 안 지운다.
#     이게 없으면 매 send 가 bodies 전체를 listdir 해 파일 수에 비례해 느려진다.
t26c="$(mktemp -d)"; mkdir -p "$t26c/bodies"
echo "t26c-old-full" > "$t26c/bodies/1.txt"
touch -t "$T26AGED" "$t26c/bodies/1.txt"
touch "$t26c/.bodies-pruned"                # 방금 돌았다고 표시
FT_MBOX_DIR="$t26c" bash "$MBOX" send seatT26c t26user "t26c-trigger" --no-notify >/dev/null 2>&1
[ -f "$t26c/bodies/1.txt" ]; ok "T26c 1시간 억제 — 오래된 파일도 안 지움" 0 $?

# T26d 회귀: TTL «안»의 전문은 살아 있어야 하고, recv 가 여전히 전문 경로를 준다.
#     청소가 «지금 온 메시지»의 전문까지 지우면 T25 가 되찾으려던 것을 다시 잃는다.
t26d="$(mktemp -d)"
T26BIG=$(printf 'q%.0s' {1..800})
out=$(FT_MBOX_DIR="$t26d" bash "$MBOX" send seatT26d t26user "$T26BIG" --no-notify 2>&1)
t26seq=$(printf '%s\n' "$out" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)
[ -f "$t26d/bodies/$t26seq.txt" ]; ok "T26d 청소 후에도 방금 전문 생존 (seq=$t26seq)" 0 $?
out=$(FT_MBOX_DIR="$t26d" bash "$MBOX" recv seatT26d 2>&1)
printf '%s\n' "$out" | grep -qF "전문: $t26d/bodies/$t26seq.txt (800자)"
ok "T26d recv 가 전문 경로 제공(회귀)" 0 $?


# T27 계보 합치(2026-09-06, F1·F2): pack 과 BYZ 정본은 «같은» .mbox-guard.json 을 공유하는데
#   해시 방식이 갈리면 서로의 기록을 못 읽어 RESEND·FANOUT 이 계보를 건너면 반쪽만 작동했다.
#   실측: 같은 본문 206자로 BYZ→QUEUED, 곧바로 pack→★QUEUED(안 막힘)★, 다시 BYZ→BLOCKED.
#   BYZ 정본에 F1(큐 pending 판정)·F2(전문 해시)를 넣은 뒤의 회귀를 여기서 잠근다.
#   ★BYZ 래퍼가 없는 환경(팩 단독)에서는 SKIP★ — 팩 테스트가 남의 리포에 의존해 깨지면 안 된다.
BYZ_MBOX="${FT_BYZ_MBOX:-$HOME/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live/.fable-team/comm/mbox.sh}"
if [ ! -f "$BYZ_MBOX" ]; then
  echo "SKIP T27 계보 합치 — BYZ 래퍼 없음 ($BYZ_MBOX)"
else
  t27=$(mktemp -d)
  # T27a BYZ 로 send → pack 으로 같은 본문 재발신 → RESEND 로 막혀야 한다(계보를 건너 억제).
  FT_MBOX_DIR="$t27" bash "$BYZ_MBOX" send seatT27 t27user "${PFX}ONE" --no-notify >/dev/null 2>&1
  ok "T27a BYZ send" 0 $?
  err=$(FT_MBOX_DIR="$t27" bash "$MBOX" send seatT27 t27user "${PFX}ONE" --no-notify 2>&1); rc=$?
  ok "T27a pack 재발신 차단(계보 건너)" 3 $rc
  printf '%s\n' "$err" | grep -q 'RESEND_COOLDOWN'
  ok "T27a 사유가 RESEND_COOLDOWN" 0 $?
  # T27b 앞 200자 동일 · 꼬리 다른 두 본문은 ★서로 막지 않는다★ (F2 전문 해시 = 오탐 제거).
  FT_MBOX_DIR="$t27" bash "$MBOX" send seatT27 t27user "${PFX}TWO" --no-notify >/dev/null 2>&1
  ok "T27b 200자 동일·꼬리 다름 → 통과(F2)" 0 $?
  # T27c 반대 방향도 같아야 «합치»다 — pack 으로 send → BYZ 로 같은 본문 재발신 → 차단.
  t27c=$(mktemp -d)
  FT_MBOX_DIR="$t27c" bash "$MBOX" send seatT27c t27user "${PFX}THREE" --no-notify >/dev/null 2>&1
  ok "T27c pack send" 0 $?
  err=$(FT_MBOX_DIR="$t27c" bash "$BYZ_MBOX" send seatT27c t27user "${PFX}THREE" --no-notify 2>&1); rc=$?
  ok "T27c BYZ 재발신 차단(계보 건너)" 3 $rc
  printf '%s\n' "$err" | grep -q 'RESEND_COOLDOWN'
  ok "T27c 사유가 RESEND_COOLDOWN" 0 $?
  # T27d F1 회귀: 소비되면 계보를 건너서도 통과한다(큐 pending 판정이지 시각 판정이 아니다).
  FT_MBOX_DIR="$t27c" bash "$BYZ_MBOX" recv seatT27c >/dev/null 2>&1
  FT_MBOX_DIR="$t27c" bash "$BYZ_MBOX" send seatT27c t27user "${PFX}THREE" --no-notify >/dev/null 2>&1
  ok "T27d 소비 후 재발신 통과(F1)" 0 $?
fi
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
