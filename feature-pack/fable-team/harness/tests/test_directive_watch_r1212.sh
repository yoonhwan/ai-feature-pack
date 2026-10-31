#!/usr/bin/env bash
# test_directive_watch_r1212.sh — r1212 오빠 지시 감시(ft-directive-watch) 반례 R1~R10 + 부팅 보고 판본 칸(R7) + 변이 5.
# 임시 루트(판정 원장 사본 · 임시 git 리포 카드 폴더 · 카드 루트 표) · 가상 시각 --now · 가짜 FT_MBOX_SH 수집기 · 실 STATE·실 쪽지 0 · 자기 재호출 0 · 고정 sleep 0.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_directive_watch_r1212.sh
set -uo pipefail
export TZ=Asia/Seoul
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; COMM="$REPO/harness/comm"; FX="$REPO/harness/tests/fixtures/directive_watch"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
TOOL="$BIN/ft_directive_watch.py"; LINT="$COMM/ft-boot-report-lint.py"
PLANNER='byz-planner-master-claude#9'; HMASTER='byz-harness-master-claude#33'
NOW=$(date +%s)

gc() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
row() { python3 -c 'import json,sys; print(json.dumps({"ev":sys.argv[1],"n":int(sys.argv[2]),"ts":sys.argv[3],"title":sys.argv[4],"teams":sys.argv[5].split(",")},ensure_ascii=False))' "$@"; }
new_root() {  # 임시 루트 R = git 리포(main) + .fable-team/state(원장·카드 루트 표) + 명부(_master) + 가짜 mbox
  R="$(mktemp -d "$T/r.XXXXXX")"; R="$(cd "$R" && pwd -P)"; mkdir -p "$R/.fable-team/state" "$R/design/harness/indices/대기" "$R/design/teams/room/indices/대기"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "2026-10-01 09:00:00 +0900" init
  printf 'harness\t.\tmain\tdesign/harness/indices\n*\t.\tmain\tdesign/teams/*/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
  printf '{"_master":"%s","%s":{"role":"master"}}\n' "$PLANNER" "$PLANNER" > "$R/.fable-team/seats-planner.json"
  printf '{"_master":"%s","%s":{"role":"master"}}\n' "$HMASTER" "$HMASTER" > "$R/.fable-team/seats-harness.json"
  printf '{"_master":"byz-room-master-claude#1"}\n' > "$R/.fable-team/seats-room.json"; printf '{}\n' > "$R/.fable-team/seats.json"
  cat > "$R/mbox.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\x1f%s\n' "$2" "$(printf '%s' "$4" | tr '\n' '|')" >> "$(dirname "$0")/sent.log"
[ "$2" = "${FAKE_FAIL_TO:-}" ] && { echo "REJECT 가짜 실패"; exit 3; }; echo "QUEUED seq=1 to=$2"
EOF
  : > "$R/sent.log"
}
card() {  # <R> <상대경로> <날짜> <본문 줄...>
  local r="$1" p="$2" d="$3"; shift 3; mkdir -p "$(dirname "$r/$p")"; printf '%s\n' "# 카드 $(basename "$p" .md)" "$@" > "$r/$p"; git -C "$r" add -A design; gc "$r" "$d" "card $p"
}
run() { OUT="$(cd "$R" && env FT_ROOT="$R" FT_MBOX_SH="$R/mbox.sh" FT_DIRECTIVE_NANO_REPOS="$R" ${EXTRA_ENV:-} python3 "${TOOL_RUN:-$TOOL}" "$@" 2>&1)"; RC=$?; }
sent() { grep -c . "$R/sent.log" 2>/dev/null || true; }
row2888() { python3 -c 'import json,sys; [print(l.strip()) for l in open(sys.argv[1],encoding="utf-8") if json.loads(l).get("n")==2888]' "$FX/verdicts-20261031.jsonl"; }
r1180_env() {  # R1·R2 사본 — 판정 2888(18:23:06) · r1180 대기 카드 18:43:29 · 10-31 09:14 커밋 · 09:20 완성 이동(둘 다 평가 시각 뒤)
  new_root; row2888 > "$R/.fable-team/state/verdicts.jsonl"
  card "$R" "design/harness/indices/대기/r1180-news-normalize.md" "2026-10-30 18:43:29 +0900" "- 지시: 판정 2888" "## 상태" "- 대기"
  printf '%s\n' "- 2026-10-31 09:14 재개" >> "$R/design/harness/indices/대기/r1180-news-normalize.md"; git -C "$R" add -A design; gc "$R" "2026-10-31 09:14:00 +0900" "r1180 09:14"
  mkdir -p "$R/design/harness/indices/완성"; git -C "$R" mv "design/harness/indices/대기/r1180-news-normalize.md" "design/harness/indices/완성/r1180-news-normalize.md"; gc "$R" "2026-10-31 09:20:00 +0900" "r1180 완성"
}

# ⓐ R1 — 가상 시각 10-31 01:00 → 멈춘 오빠 지시 1(2888 · r1180 · 18:43:29) · rc1 · 운영 파일 쓰기 0
r1180_env; run status --now 2026-10-31T01:00:00
case "$OUT" in "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 1 · 판본 "*) h=1;; *) h=0;; esac
[ "$RC" = 1 ] && [ "$h" = 1 ] && printf '%s' "$OUT" | grep -q '^멈춤 판정 2888 · r1180-news-normalize · 마지막 움직임 10-30 18:43:29' && [ ! -e "$R/.fable-team/state/directive-watch" ] \
  && ok "R1 01:00 → 멈춤 1 · 2888 · r1180 · 18:43:29 · rc1 · 평가 시각 뒤 완성 이동(09:20) 안 봄 · 가상 시각 쓰기 0" || bad "R1 rc=$RC :: $OUT"
# ⓐ R2 — 같은 사본 23:00 → 멈춤 0(4시간 16분) · 09:14 커밋은 평가 시각 뒤라 안 셈 · rc0
run status --now 2026-10-30T23:00:00
[ "$RC" = 0 ] && case "$OUT" in "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0 · 판본 "*) true;; *) false;; esac && ok "R2 23:00 → 멈춤 0 · rc0" || bad "R2 rc=$RC :: $OUT"
# R1 나노 가지 — nano/<stem 앞 40자> 의 base 밖 커밋 22:00 → 01:00 에 멈춤 0 · 03:30 엔 다시 멈춤 아님(5시간 30분) · 04:30 → 멈춤 1
git -C "$R" branch -q "nano/r1180-news-normalize" "$(git -C "$R" rev-list -1 --before='2026-10-30 19:00:00 +0900' main)"
git -C "$R" checkout -q "nano/r1180-news-normalize"; gc "$R" "2026-10-30 22:00:00 +0900" "nano work"; git -C "$R" checkout -q main
run status --now 2026-10-31T01:00:00; a=$RC; run status --now 2026-10-31T04:30:00
[ "$a" = 0 ] && [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '마지막 움직임 10-30 22:00:00' && ok "R1′ 나노 가지 커밋 = 움직임(01:00 정상 · 04:30 멈춤 · 22:00)" || bad "R1′ a=$a rc=$RC :: $OUT"
lap R1R2
# R2b — 운영 캐시에 r1180 의 09:14 시각이 들어 있는 상태에서 --now 01:00 → 캐시 무시 · 멈춤 1(18:43:29) · 캐시 바이트 그대로
r1180_env; run status; c="$(grep -l '^r1180-news-normalize' "$R"/.fable-team/state/directive-watch/commits-*.tsv 2>/dev/null | head -1)"
a0=$RC; grep -q "^r1180-news-normalize	$(date -j -f '%Y-%m-%d %H:%M:%S' '2026-10-31 09:20:00' +%s)$" "${c:-/x}"; pre=$?
cp "$c" "$T/cache.before"; cp "$R/.fable-team/state/directive-watch/stamps.tsv" "$T/stamps.before"; run status --now "$(( $(date +%s) - 30 ))"; r30=$RC
ls -l "$R"/.fable-team/state/directive-watch > "$T/ls.before"; run status --now 2026-10-31T01:00:00
[ "$a0" = 0 ] && [ "$pre" = 0 ] && [ "$r30" = 0 ] && [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q '마지막 움직임 10-30 18:43:29' && cmp -s "$c" "$T/cache.before" && cmp -s "$R/.fable-team/state/directive-watch/stamps.tsv" "$T/stamps.before" \
  && ok "R2b 운영(지금 = 완성 · rc0) 캐시(09:20) 있음 + 30초 전·01:00 가상 → 캐시 무시 · 01:00 멈춤 1 · 캐시·stamps 바이트 그대로" || bad "R2b rc=$RC c=$c :: $OUT"
lap R2b
# R3 — 후보 · 연결 카드 0 · 판정 뒤 61분 → 담당 없음 1 · 59분 → 0 · 배경으로만 판정 N 을 인용한 카드는 연결 0
new_root; row new 3001 2026-10-20T10:00:00 "오빠 지시(slack 1792900000.123456): 새 감시" harness > "$R/.fable-team/state/verdicts.jsonl"
card "$R" "design/harness/indices/대기/r9001-bg.md" "2026-10-20 10:30:00 +0900" "- 근거: 판정 3001 · 오빠 slack 1792900000.123456" "## 배경" "판정 3001 을 인용"
run status --now 2026-10-20T11:01:00; a=$RC; ao="$OUT"; run status --now 2026-10-20T10:59:00
case "$ao" in "담당 없는 오빠 지시 1 · 멈춘 오빠 지시 0"*) h=1;; *) h=0;; esac
[ "$a" = 1 ] && [ "$h" = 1 ] && printf '%s' "$ao" | grep -q '^담당 없음 판정 3001 · 10-20 10:00:00 · harness' && [ "$RC" = 0 ] \
  && ok "R3 61분 → 담당 없음 1 · 59분 → 0 · 배경 인용 카드 연결 0" || bad "R3 a=$a rc=$RC :: $ao :: $OUT"
lap R3
# R4 — 같은 n 에 done(무효) → 제외 · 연결 카드 전부 완성 → 닫힘 · 닫음 표 «결정만» → 닫힘
new_root; { row new 3002 2026-10-20T10:00:00 "오빠 결정 slack 1792900001" harness; row done 3002 2026-10-20T10:01:00 "무효 — 번호 충돌" harness
  row new 3003 2026-10-20T10:00:00 "오빠 지시 slack 1792900002.1" harness; row new 3004 2026-10-20T10:00:00 "오빠 «1» slack 1792900003.2" room; } > "$R/.fable-team/state/verdicts.jsonl"
card "$R" "design/harness/indices/완성/r9003-done.md" "2026-10-20 10:20:00 +0900" "- 지시: 판정 3003"
printf '3004\t결정만(답 1)\tplanner#9\t2026-10-20T10:05\n' > "$R/.fable-team/state/directive-closed.tsv"
run status --now 2026-10-21T10:00:00
[ "$RC" = 0 ] && case "$OUT" in "담당 없는 오빠 지시 0 · 멈춘 오빠 지시 0"*) true;; *) false;; esac && ok "R4 done(무효)·완성 카드·닫음 표 → 경보 0 · rc0" || bad "R4 rc=$RC :: $OUT"
lap R4
# R5·R6 — 운영 시각 사본(판정 = 지금−8시간 · 카드 대기 지금−7시간) · tick
op_env() {
  new_root; row new 3010 "$(date -r $((NOW - 28800)) +%Y-%m-%dT%H:%M:%S)" "오빠 지시(slack 1793400000.5): 감시 A" harness > "$R/.fable-team/state/verdicts.jsonl"
  card "$R" "design/harness/indices/대기/r9010-a.md" "$((NOW - 25200)) +0900" "- 지시: 판정 3010"
}
op_env; FAKE_FAIL_TO="$HMASTER"; export FAKE_FAIL_TO; run tick; t1=$RC; s1=$(sent)
unset FAKE_FAIL_TO; run tick; s2=$(sent); run tick; s3=$(sent); run status
# R5 경보 쪽지가 카드 id(r9010)를 언급해도 다음 틱 멈춤 그대로
[ "$RC" = 1 ] && case "$OUT" in *"멈춘 오빠 지시 1"*) true;; *) false;; esac && grep -q 'r9010' "$R/sent.log" && ok "R5 경보 쪽지(카드 id 언급) 뒤에도 멈춤 1 그대로" || bad "R5 rc=$RC :: $OUT"
# R6 수신자 둘 중 하나만 QUEUED → 그 수신자만 표식 · 다음 틱 나머지 1통 · 같은 목록 0통
p1=$(grep -c "^$PLANNER" "$R/sent.log"); m1=$(grep -c "^$HMASTER" "$R/sent.log")
[ "$t1" = 1 ] && [ "$s1" = 2 ] && [ "$s2" = 3 ] && [ "$s3" = 3 ] && [ "$p1" = 1 ] && [ "$m1" = 2 ] && grep -qF '[긴급] 지시 멈춤 — 담당 없는 오빠 지시 0 · 멈춘 오빠 지시 1' "$R/sent.log" \
  && ok "R6 부분 전달 → 실패 수신자만 다음 틱 1통 · 같은 목록 60분 안 0통" || bad "R6 t1=$t1 s=$s1/$s2/$s3 p=$p1 m=$m1 :: $(cat "$R/sent.log")"
row new 3011 "$(date -r $((NOW - 28800)) +%Y-%m-%dT%H:%M:%S)" "오빠 지시 slack 1793400001.5 감시 B" harness >> "$R/.fable-team/state/verdicts.jsonl"; run tick; s4=$(sent)
[ "$s4" = 5 ] && ok "R6′ 목록 바뀜(담당 없음 +1) → 그 틱 받는이마다 1통" || bad "R6′ s4=$s4 :: $(cat "$R/sent.log")"
EXTRA_ENV="FT_DIRECTIVE_NOW=$((NOW + 3700))" run tick; s5=$(sent)
[ "$s5" = 7 ] && ok "R6″ 같은 목록이라도 60분 지나면 다시 1통" || bad "R6″ s5=$s5"
lap R5R6
# R6‴ 실제 mbox_guard(FT_PLANNER_HEAD_MODE=reject) 에서 planner 앞 [긴급] 머리 통과
op_env; mkdir -p "$R/.fable-team/comm" "$T/stub"; cp "$COMM"/mbox*.py "$COMM"/mbox*.sh "$LINT" "$R/.fable-team/comm/"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"
OUT="$(cd "$R" && env PATH="$T/stub:$PATH" FT_ROOT="$R" FT_SEATS_JSON="$R/.fable-team/seats.json" FT_PLANNER_HEAD_MODE=reject FT_MBOX_DIR="$R/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
  FT_DIRECTIVE_NANO_REPOS="$R" python3 "$TOOL" tick 2>&1)"
q="$(grep -c "\"to\": *\"$PLANNER\"" "$R/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"
[ "${q:-0}" = 1 ] && printf '%s' "$OUT" | grep -q "tick 1통 → $PLANNER" && ok "R6‴ 실제 mbox_guard reject 모드 · planner [긴급] 큐 1행" || bad "R6‴ q=$q :: $OUT"
lap R6real
# R7 — 부팅 보고 판본 칸(stamps.tsv 대조) · 승계 master
op_env; run status; HEAD1="$(printf '%s' "$OUT" | head -1)"; ST="$(printf '%s' "$HEAD1" | sed -n 's/.*판본 \([0-9]*-[0-9a-f]*\).*/\1/p')"
mkdir -p "$T/seats7"; printf '%s\n' '{"_master":"byz-harness-master-claude#33","byz-harness-master-claude#32":{"role":"stop-ready","_replaced_by":"byz-harness-master-claude#33"},"byz-harness-master-claude#33":{"role":"master","_replaces":["byz-harness-master-claude#32"]},"byz-harness-nano-x#0":{"role":"nano"}}' > "$T/seats7/seats-harness.json"
BOOT='[부팅 보고] 세션=x retire=byz-harness-master-claude#32->byz-harness-master-claude#33 rc=0 cron=abc123'
lint() { LOUT="$(printf '%s' "$2" | env FT_DIRECTIVE_STAMPS="$R/.fable-team/state/directive-watch/stamps.tsv" ${LENV:-} python3 "${LINT_RUN:-$LINT}" --from "$1" --seats-dir "$T/seats7" 2>&1)"; LRC=$?; }
lint "$HMASTER" "$BOOT"; r_none=$LRC; lint "$HMASTER" "$BOOT ${HEAD1/판본 $ST/판본 ${ST%%-*}-00000000}"; r_row=$LRC
lint "$HMASTER" "$BOOT ${HEAD1/멈춘 오빠 지시 1/멈춘 오빠 지시 2}"; r_num=$LRC
LENV="FT_DIRECTIVE_NOW=$(( ${ST%%-*} + 1860 ))" lint "$HMASTER" "$BOOT $HEAD1"; r_old=$LRC
lint "$HMASTER" "$BOOT 지시 감시 판정 불가 · git 상한 넘김"; r_und=$LRC; und="$LOUT"; lint "$HMASTER" "$BOOT $HEAD1"; r_ok=$LRC
[ "$r_none$r_row$r_num$r_old" = 1111 ] && [ "$r_und" = 0 ] && case "$und" in *WARN*) true;; *) false;; esac && [ "$r_ok" = 0 ] \
  && ok "R7 칸 없음·판본 행 없음·숫자 다름·31분 → 반송 · 판정 불가 → 통과+WARN · 맞는 칸 → OK" || bad "R7 $r_none$r_row$r_num$r_old und=$r_und ok=$r_ok :: $und :: $LOUT"
lint 'byz-harness-nano-x#0' "[부팅 보고] 세션=x"; a=$LRC
LOUT="$(printf '%s' "$BOOT $HEAD1" | env FT_DIRECTIVE_STAMPS="$T/none.tsv" python3 "$LINT" --from "$HMASTER" --seats-dir "$T/seats7" 2>&1)"; b=$?
[ "$a" = 0 ] && [ "$b" = 1 ] && case "$LOUT" in *'REJECT'*'판본 파일 없음'*) true;; *) false;; esac && ok "R7′ 나노(승계 아님) 검사 0 · 판본 파일 없음 = 반송" || bad "R7′ a=$a b=$b :: $LOUT"
lap R7
# R8 — 원장 못 읽음 · git 상한 넘김(틱 예산 · 첫 실행 예산) → rc3 1줄 · tick = planner [긴급] 판정 불가 1통 · 60분 억제
op_env; mv "$R/.fable-team/state/verdicts.jsonl" "$R/.fable-team/state/verdicts.off"; run status
[ "$RC" = 3 ] && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && case "$OUT" in "지시 감시 판정 불가 · 판정 원장 못 읽음"*) true;; *) false;; esac && ok "R8 원장 못 읽음 → rc3 1줄(숫자 머리 없음)" || bad "R8 rc=$RC :: $OUT"
mv "$R/.fable-team/state/verdicts.off" "$R/.fable-team/state/verdicts.jsonl"
EXTRA_ENV="FT_DIRECTIVE_FIRST_SEC=0" run status; a=$RC; ao="$OUT"; run status; EXTRA_ENV="FT_DIRECTIVE_TICK_SEC=0" run tick; b=$RC; bo="$OUT"; EXTRA_ENV="FT_DIRECTIVE_TICK_SEC=0" run tick
[ "$a" = 3 ] && case "$ao" in "지시 감시 판정 불가 · git 상한 넘김"*) true;; *) false;; esac && [ "$b" = 3 ] && case "$bo" in "지시 감시 판정 불가 · git 상한 넘김"*) true;; *) false;; esac \
  && [ "$(grep -c '\[긴급\] 지시 감시 판정 불가' "$R/sent.log")" = 1 ] && ok "R8′ 첫 실행·틱 git 상한 → rc3 · tick [긴급] 판정 불가 1통 · 다음 틱 억제" || bad "R8′ a=$a b=$b :: $ao :: $bo :: $(cat "$R/sent.log")"
lap R8
# R9 — 지금 원장 사본(323행) 후보 목록 = 기대 목록(2859 포함 · 2675·2822 제외 · 오빠 없는 planner 대리 결정 제외)
new_root; cp "$FX/verdicts-20261031.jsonl" "$R/.fable-team/state/verdicts.jsonl"; run status --now 2026-10-31T09:30:00
printf '%s\n' "$OUT" | sed -n 's/^담당 없음 판정 \([0-9]*\) .*/\1/p' | sort > "$T/got9"; cut -f1 "$FX/candidates-expected.txt" | sort > "$T/want9"
cmp -s "$T/got9" "$T/want9" && grep -qx 2859 "$T/got9" && ! grep -qxE '2675|2822|2916' "$T/got9" && ok "R9 후보 $(grep -c . "$T/got9")건 = 기대 목록 · 2859 포함 · 2675·2822·2916 제외" || bad "R9 :: $(diff "$T/want9" "$T/got9" | head -5)"
lap R9
# R10 — 카드 대기→진행→완성 이동 = stem 으로 이음 · 증분 캐시에 오래된 카드 시각이 남음
new_root; row new 3020 "$(date -r $((NOW - 50000)) +%Y-%m-%dT%H:%M:%S)" "오빠 지시 slack 1793400002 이동" harness > "$R/.fable-team/state/verdicts.jsonl"
card "$R" "design/harness/indices/대기/r9020-mv.md" "$((NOW - 36000)) +0900" "- 지시: 판정 3020"
card "$R" "design/harness/indices/대기/r9021-old.md" "$((NOW - 40000)) +0900" "- 지시: 판정 9999"
mkdir -p "$R/design/harness/indices/진행"; git -C "$R" mv "design/harness/indices/대기/r9020-mv.md" "design/harness/indices/진행/r9020-mv.md"; gc "$R" "$((NOW - 28800)) +0900" "mv 진행"
run status; a=$RC; ao="$OUT"; card "$R" "design/teams/room/indices/대기/x1.md" "$((NOW - 100)) +0900" "- 지시: 판정 9998"; run status
c="$(grep -l '^r9021-old' "$R"/.fable-team/state/directive-watch/commits-*.tsv | head -1)"
[ "$a" = 1 ] && printf '%s' "$ao" | grep -q "마지막 움직임 $(date -r $((NOW - 28800)) '+%m-%d %H:%M:%S')" && grep -q "^r9021-old	$((NOW - 40000))$" "$c" && grep -q "^r9020-mv	$((NOW - 28800))$" "$c" \
  && ok "R10 폴더 이동 = stem 이음(8시간 전 이동 = 마지막 움직임) · 증분 뒤에도 오래된 카드 시각 유지" || bad "R10 a=$a :: $ao :: $(cat "$c")"
mkdir -p "$R/design/harness/indices/완성"; git -C "$R" mv "design/harness/indices/진행/r9020-mv.md" "design/harness/indices/완성/r9020-mv.md"
gc "$R" "$((NOW - 60)) +0900" "mv 완성"; run status --now "$((NOW - 120))"; a=$RC; run status
[ "$a" = 1 ] && [ "$RC" = 0 ] && ok "R10′ 완성 이동 → 닫힘(rc0) · 이동 전 시각 평가는 진행 그대로(멈춤 rc1)" || bad "R10′ a=$a rc=$RC :: $OUT"
lap R10

# ── 변이 5 (그 칸만 다시 돈다)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
export PYTHONPATH="$BIN"
mut "$TOOL" "$T/m1.py" "6 * 3600" "10 ** 9"; r1180_env; TOOL_RUN="$T/m1.py" run status --now 2026-10-31T01:00:00
[ "$RC" = 0 ] && ok "변이1(6시간 → 무한) → R1 빨강(rc0)" || bad "변이1 이 R1 에 안 잡힘 rc=$RC"
mut "$TOOL" "$T/m2.py" '"^- 지시:"' '"판정"'; new_root; row new 3001 2026-10-20T10:00:00 "오빠 지시(slack 1792900000.123456): 새 감시" harness > "$R/.fable-team/state/verdicts.jsonl"
card "$R" "design/harness/indices/대기/r9001-bg.md" "2026-10-20 10:30:00 +0900" "- 근거: 판정 3001 · 오빠 slack 1792900000.123456"; TOOL_RUN="$T/m2.py" run status --now 2026-10-20T11:01:00
case "$OUT" in "담당 없는 오빠 지시 0"*) ok "변이2(인용 아무 데나 연결) → R3 빨강(담당 없음 0)";; *) bad "변이2 가 R3 에 안 잡힘 :: $OUT";; esac
mut "$TOOL" "$T/m4.py" "if not self.virtual and c.is_file():" "if c.is_file():"; r1180_env; run status; TOOL_RUN="$T/m4.py" run status --now 2026-10-31T01:00:00
[ "$RC" = 0 ] && ok "변이4(가상 시각에 운영 캐시 재사용) → R2b 빨강(rc0)" || bad "변이4 가 R2b 에 안 잡힘 rc=$RC :: $OUT"
mut "$TOOL" "$T/m5.py" '"rev-list", "-1", until(self.now), r[2]' '"rev-parse", r[2]'; r1180_env; TOOL_RUN="$T/m5.py" run status --now 2026-10-31T01:00:00
[ "$RC" = 0 ] && ok "변이5(카드를 현재 ref 에서 읽음) → R1 빨강(미래 완성 이동으로 rc0)" || bad "변이5 가 R1 에 안 잡힘 rc=$RC :: $OUT"
unset PYTHONPATH
op_env; run status; HEAD1="$(printf '%s' "$OUT" | head -1)"; ST="$(printf '%s' "$HEAD1" | sed -n 's/.*판본 \([0-9]*-[0-9a-f]*\).*/\1/p')"
mut "$LINT" "$T/m3.py" 'm.group(3) not in rows else "숫자 다름" if rows[m.group(3)] != [m.group(1), m.group(2)]' 'False else "숫자 다름" if False'
LINT_RUN="$T/m3.py" lint "$HMASTER" "$BOOT ${HEAD1/판본 $ST/판본 ${ST%%-*}-00000000}"
[ "$LRC" = 0 ] && ok "변이3(판본 대조 뺌) → R7 빨강(행 없음 반송 0)" || bad "변이3 이 R7 에 안 잡힘 rc=$LRC :: $LOUT"
lap mutation

# ⓘ bin·kit 같은 내용 · 문법 · 크기
cmp -s "$BIN/ft_directive_watch.py" "$KIT/ft_directive_watch.py" && cmp -s "$BIN/ft-directive-watch.sh" "$KIT/ft-directive-watch.sh" && ok "bin·kit 같은 내용 2파일" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" "$LINT" 2>/dev/null && bash -n "$BIN/ft-directive-watch.sh" && ok "py_compile · bash -n" || bad "문법"
n="$(wc -l < "$LINT")"; [ "$n" -le 80 ] && ok "lint ≤80줄($n)" || bad "lint 줄수 $n"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
