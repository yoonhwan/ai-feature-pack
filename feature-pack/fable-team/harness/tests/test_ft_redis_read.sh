#!/usr/bin/env bash
# test_ft_redis_read.sh — r623 «읽기 전용 redis 묶음» 도구(ft-redis-read.sh) 시험.
# 실제 redis 0 · 네트워크 0 · 가짜 redis-cli(PATH)로 «받은 표준입력 바이트» 만 본다.
# 대조표 1행 = 1검사. 표 미달이면 exit 1.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/.."
TOOL="$ROOT/kit/fable-team/bin/ft-redis-read.sh"
fail=0; nb=0; np=0

T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
FB="$T/fb"; mkdir -p "$FB"
CAP="$T/got.bin"; LOG="$T/log.txt"
# 가짜 redis-cli: 받은 표준입력을 CAP 에 쓰고 되돌린 인자를 ARGS 에 남긴다(실제 redis 0)
cat > "$FB/redis-cli" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" > "$FAKE_ARGS"
cat > "$FAKE_CAP"
echo FAKE-OK
EOS
chmod +x "$FB/redis-cli"
export FAKE_CAP="$CAP" FAKE_ARGS="$T/args.txt" FT_REDIS_READ_LOG="$LOG"

run() {  # <도구 인자들…> → rc (가짜 redis-cli 만 보이는 PATH)
  PATH="$FB:$PATH" bash "$TOOL" "$@" >"$T/out.txt" 2>"$T/err.txt"
}
expect() {  # <id> <기대 rc> <카운터> <설명> <인자들…>
  local id="$1" want="$2" ctr="$3"; shift 3
  local rc
  run "$@"; rc=$?
  if [ "$rc" = "$want" ]; then echo "PASS [$id] rc=$rc"; eval "$ctr=\$((ctr+1))"
  else echo "FAIL [$id] want=$want got=$rc :: $(tail -1 "$T/err.txt")"; fail=$((fail+1)); fi
}
sha() { python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

# 픽스처 — 789줄 읽기 묶음(v65 실사건) · 쓰기 1줄 · 목록 밖 · 빈 파일
GRP="$T/cmds.txt"
python3 -c 'import sys
open(sys.argv[1],"w").write("\n".join("HSTRLEN room:events:r1 field%d" % i for i in range(789))+"\n")' "$GRP"
WR="$T/w.txt"; printf 'HSTRLEN a b\nHSET k f v\n' > "$WR"
OUT="$T/out.txt.bad"; printf 'DEL k\n' > "$OUT"
EMPTY="$T/empty.txt"; : > "$EMPTY"
ORIG_SHA="$(sha "$GRP")"

# ── ⓐ' 통과: 도구 rc0 · 가짜 redis-cli 가 받은 표준입력 sha == 파일 sha ────────────
rm -f "$CAP" "$T/args.txt"
expect r3-a 0 np -p 6379 "$GRP"
if [ -f "$CAP" ] && [ "$(sha "$CAP")" = "$ORIG_SHA" ]; then
  echo "PASS [r3-a-sha] 받은 표준입력 == 파일 바이트 ($ORIG_SHA)"; np=$((np+1))
else echo "FAIL [r3-a-sha] 표준입력이 파일과 다름"; fail=$((fail+1)); fi
if [ "$(cat "$T/args.txt" 2>/dev/null)" = "-p 6379" ]; then
  echo "PASS [r3-a-args] redis-cli 인자 = -p 6379"; np=$((np+1))
else echo "FAIL [r3-a-args] 인자 틀림: $(cat "$T/args.txt" 2>/dev/null)"; fail=$((fail+1)); fi

# ── ⓑ' 쓰기 1줄 섞임 → REJECT rc2 · 가짜 redis-cli 호출 0 ───────────────────────
rm -f "$CAP"
expect r3-b 2 nb -p 6379 "$WR"
if [ ! -f "$CAP" ]; then echo "PASS [r3-b-nocall] redis-cli 호출 0"; nb=$((nb+1))
else echo "FAIL [r3-b-nocall] REJECT 인데 redis-cli 가 불렸다"; fail=$((fail+1)); fi
grep -q 'HSET' "$T/err.txt" && { echo "PASS [r3-b-reason] 사유에 걸린 동사"; nb=$((nb+1)); } || { echo "FAIL [r3-b-reason] 사유 없음"; fail=$((fail+1)); }

# ── ⓒ' 검사 뒤 파일이 바뀌는 경합 → 보낸 바이트 = 판정한 바이트 ─────────────────
# 가짜 redis-cli 가 «stdin 을 읽기 전에» 원본 파일을 쓰기 내용으로 덮어쓴다(경합 재현).
cat > "$FB/redis-cli" <<EOS
#!/bin/bash
cp "$WR" "$GRP"
cat > "$FAKE_CAP"
EOS
chmod +x "$FB/redis-cli"
rm -f "$CAP"
expect r3-c 0 np -p 6379 "$GRP"
if [ -f "$CAP" ] && [ "$(sha "$CAP")" = "$ORIG_SHA" ] && [ "$(sha "$GRP")" != "$ORIG_SHA" ]; then
  echo "PASS [r3-c-race] 파일이 바뀌어도 보낸 바이트 = 판정한 바이트(원본)"; np=$((np+1))
else echo "FAIL [r3-c-race] 경합에서 바이트가 어긋남"; fail=$((fail+1)); fi
printf '%s' "$(python3 -c 'import sys
open(sys.argv[1],"w").write("\n".join("HSTRLEN room:events:r1 field%d" % i for i in range(789))+"\n")' "$GRP")"
cat > "$FB/redis-cli" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" > "$FAKE_ARGS"
cat > "$FAKE_CAP"
EOS
chmod +x "$FB/redis-cli"

# ── ⓓ' 인자 모양: -x·--eval·URL·추가 인자·-p abc → REJECT rc2 · 호출 0 ─────────
for a in "-x $GRP" "--eval lua.txt $GRP" "http://127.0.0.1:6379 $GRP" "$GRP $GRP"; do
  rm -f "$CAP"
  expect "r3-d[${a%% *}]" 2 nb $a
  [ ! -f "$CAP" ] && { echo "PASS [r3-d-nocall ${a%% *}] 호출 0"; nb=$((nb+1)); } || { echo "FAIL [r3-d-nocall ${a%% *}]"; fail=$((fail+1)); }
done
rm -f "$CAP"; expect r3-d-p2 2 nb -p abc "$GRP"
rm -f "$CAP"; expect r3-d-h2 2 nb -h 'x;y' "$GRP"
expect r3-d-none 2 nb
expect r3-d-out 2 nb -p 6379 "$OUT"
expect r3-d-empty 2 nb -p 6379 "$EMPTY"
expect r3-d-missing 2 nb -p 6379 "$T/nope.txt"

# ── ⓔ' 읽기 목록을 훅 파일에서 못 읽음 → REJECT ─────────────────────────────────
rm -f "$CAP"
PATH="$FB:$PATH" FT_REDIS_READ_HOOK="$T/no-hook.sh" bash "$TOOL" -p 6379 "$GRP" >/dev/null 2>"$T/err.txt"; rc=$?
if [ "$rc" = 2 ] && grep -qE '읽기 동사 목록|훅 파일을 못 읽음' "$T/err.txt" && [ ! -f "$CAP" ]; then
  echo "PASS [r3-e] 목록 못 읽음 → rc2 · 호출 0"; nb=$((nb+1))
else echo "FAIL [r3-e] rc=$rc 사유=$(tail -1 "$T/err.txt")"; fail=$((fail+1)); fi

# ── ⓕ' 훅 = 팩 origin/main 과 cmp0(훅 변경 0) · 기존 inject 시험 전부 PASS ────────
HOOK="$ROOT/kit/fable-team/templates/hooks/block-destructive.sh"
if git -C "$ROOT/../.." rev-parse --verify -q origin/main >/dev/null 2>&1; then
  if git -C "$ROOT/../.." show "origin/main:feature-pack/fable-team/harness/kit/fable-team/templates/hooks/block-destructive.sh" 2>/dev/null | cmp -s - "$HOOK"; then
    echo "PASS [r3-f-hook] 훅 = origin/main 판과 cmp0(변경 0)"; np=$((np+1))
  else echo "FAIL [r3-f-hook] 훅이 origin/main 판과 다르다"; fail=$((fail+1)); fi
else echo "SKIP [r3-f-hook] origin/main 없음 — cmp 생략"; np=$((np+1)); fi
if cmp -s "$ROOT/kit/fable-team/bin/ft-redis-read.sh" "$ROOT/bin/ft-redis-read.sh"; then
  echo "PASS [r3-f-twin] 키트 ↔ 추적본 cmp0"; np=$((np+1))
else echo "FAIL [r3-f-twin] 키트 ↔ 추적본 다름"; fail=$((fail+1)); fi
bash "$HERE/test_block_destructive_inject.sh" >"$T/inj.txt" 2>&1
if [ $? = 0 ] && grep -q '^OK' "$T/inj.txt"; then
  echo "PASS [r3-f-inject] 기존 inject 시험 PASS ($(grep -m1 '^SUMMARY' "$T/inj.txt"))"; np=$((np+1))
else echo "FAIL [r3-f-inject] 기존 inject 시험 실패: $(tail -2 "$T/inj.txt" | tr '\n' ' ')"; fail=$((fail+1)); fi

# ── ⓖ' 원장 1줄(시각·경로·줄수·sha256 앞16 · 내용 0) ────────────────────────────
if grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+ path=$GRP lines=789 sha256=[0-9a-f]{16}$" "$LOG" \
   && ! grep -q 'HSTRLEN room:events' "$LOG"; then
  echo "PASS [r3-g-log] 원장 1줄(내용 0)"; np=$((np+1))
else echo "FAIL [r3-g-log] 원장 줄 모양 틀림: $(tail -1 "$LOG" 2>/dev/null)"; fail=$((fail+1)); fi

echo "SUMMARY block=$nb pass=$np fail=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK"
