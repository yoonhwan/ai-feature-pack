#!/usr/bin/env bash
# test_board_publish_ctx_share.sh — ㊿아: ft-board-publish.sh 의 ctx-share 덧 호출 1줄(U9)이
#   부른 쪽 rc · stdout · 발행 호출 수를 바꾸지 않는다.
#   ⓐ 스텁 rc 9  ⓑ 안 끝나는 스텁(상한 = FT_CTX_SHARE_TIMEOUT=1초 · sleep 0 = fifo 읽기 대기)  ⓒ 스텁 파일 없음
# 변이 M126(덧 호출 rc 를 부른 쪽 rc 로 넘김)이면 ⓐ 가 baseline 과 달라져야 한다(변이 대조).
# R1(DA HOLD-IMPL 1/3): 같은 시험을 설치 키트 사본(harness/kit/fable-team)에도 돌린다 — install.sh 가 연결하는 자리.
# 실 Slack · 실 보드 · 실 state 쓰기 0 · 네트워크 0 — 전부 임시 폴더 + 스텁. sleep 0(포트 = fifo).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMPDIRS=""
trap 'rm -rf $TMPDIRS' EXIT

# suite <라벨> <ft-board-publish.sh 경로>
suite() {
  local label="$1" src="$2" T R SD BASE_RC BASE_POSTS A_RC B_RC C_RC MRC
  if [ ! -f "$src" ]; then bad "$label: 발행 스크립트 없음 ($src)"; return; fi
  T="$(mktemp -d)"; TMPDIRS="$TMPDIRS $T"
  R="$T/root"; SD="$R/.fable-team/state/usage-monitor"
  mkdir -p "$R/.fable-team" "$T/stub" "$T/hx/bin"
  mkfifo "$T/fifo"
  cp "$src" "$T/hx/bin/ft-board-publish.sh"
  cat > "$T/hx/bin/ft_board_news.py" <<'PY'
import sys
a = sys.argv[1:]
d = {a[i]: a[i + 1] for i in range(0, len(a) - 1, 2)}
open(d.get("--body", "/dev/null"), "w", encoding="utf-8").write("본문\n")
open(d.get("--state", "/dev/null"), "w", encoding="utf-8").write('{"key":"k1"}\n')
print("POST")
PY
  cat > "$T/stub/board" <<'EOF'
#!/usr/bin/env bash
[ "$1" = collect ] || exit 9
printf '{}\n' > "$3"
EOF
  cat > "$T/stub/tp.py" <<EOF
import sys
open("$T/posts.log", "a", encoding="utf-8").write("\t".join(sys.argv[1:]) + "\n")
EOF
  cat > "$T/stub/mbox.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$T/stub/share9" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/share.log"
exit 9
EOF
  cat > "$T/stub/sharehang" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$T/share.log"
read -r _ < "$T/fifo"
EOF
  chmod +x "$T/stub/board" "$T/stub/share9" "$T/stub/sharehang" "$T/stub/mbox.sh"
  chmod +x "$T/hx/bin/ft-board-publish.sh"

  export FT_ROOT="$R" FT_BOARD_BIN="$T/stub/board" FT_THREAD_POST="$T/stub/tp.py" \
         FT_BOARD_POST_ARGS="--channel C0TEST" FT_BOARD_NOW="2026-11-17T13:50:00" \
         FT_MBOX="$T/stub/mbox.sh" FT_CTX_SHARE_TIMEOUT=1

  # run <ctx-share 스텁 경로 · 없으면 호출 0> <이름> → rc 를 stdout 으로
  run() {
    : > "$T/posts.log"; : > "$T/share.log"
    FT_CTX_SHARE_BIN="$1" bash "$T/hx/bin/ft-board-publish.sh" --news \
        > "$T/out.$2" 2> "$T/err.$2"
    echo $?
  }
  posts() { wc -l < "$T/posts.log" | tr -d ' '; }
  calls() { wc -l < "$T/share.log" | tr -d ' '; }

  BASE_RC="$(run "$T/stub/gone" base)"; cp "$T/out.base" "$T/base.out"; BASE_POSTS="$(posts)"
  [ "$BASE_RC" = 0 ] && [ "$BASE_POSTS" = 1 ] && [ "$(calls)" = 0 ] \
    && ok "$label baseline(도구 없음): rc 0 · 발행 1 · ctx-share 호출 0" \
    || bad "$label baseline rc=$BASE_RC posts=$BASE_POSTS calls=$(calls)"

  A_RC="$(run "$T/stub/share9" a)"
  [ "$A_RC" = "$BASE_RC" ] && [ "$(posts)" = "$BASE_POSTS" ] && cmp -s "$T/out.a" "$T/base.out" \
    && [ "$(calls)" = 1 ] && ok "$label ⓐ 스텁 rc 9 → 부른 쪽 rc·stdout·발행 그대로 · 스텁 호출 1" \
    || bad "$label ⓐ rc=$A_RC/$BASE_RC posts=$(posts)/$BASE_POSTS calls=$(calls)"
  grep -q -- "--out $SD" "$T/share.log" \
    && ok "$label ⓐ 인자 = --out <ROOT>/.fable-team/state/usage-monitor" \
    || bad "$label ⓐ 인자 이상: $(head -1 "$T/share.log")"

  B_RC="$(run "$T/stub/sharehang" b)"
  [ "$B_RC" = "$BASE_RC" ] && [ "$(posts)" = "$BASE_POSTS" ] && cmp -s "$T/out.b" "$T/base.out" \
    && [ "$(calls)" = 1 ] && ok "$label ⓑ 안 끝나는 스텁(상한 1초) → 부른 쪽 rc·stdout·발행 그대로 · 스텁 호출 1" \
    || bad "$label ⓑ rc=$B_RC/$BASE_RC posts=$(posts)/$BASE_POSTS calls=$(calls)"

  C_RC="$(run "$T/stub/gone" c)"
  [ "$C_RC" = "$BASE_RC" ] && [ "$(posts)" = "$BASE_POSTS" ] && cmp -s "$T/out.c" "$T/base.out" \
    && [ "$(calls)" = 0 ] && ok "$label ⓒ 스텁 파일 없음 → 호출 0 · 부른 쪽 그대로" \
    || bad "$label ⓒ rc=$C_RC/$BASE_RC posts=$(posts)/$BASE_POSTS calls=$(calls)"

  # 변이 대조 M126 — 덧 호출 rc 를 부른 쪽 rc 로 넘기면 ⓐ 에서 rc 가 9 로 샌다
  mkdir -p "$T/mut/bin"
  sed 's/>\/dev\/null 2>&1; } || :/>\/dev\/null 2>\&1; } || exit $?/' \
      "$T/hx/bin/ft-board-publish.sh" > "$T/mut/bin/ft-board-publish.sh"
  cp "$T/hx/bin/ft_board_news.py" "$T/mut/bin/"
  chmod +x "$T/mut/bin/ft-board-publish.sh"
  if cmp -s "$T/mut/bin/ft-board-publish.sh" "$T/hx/bin/ft-board-publish.sh"; then
    bad "$label 변이 M126: 바꿀 자리를 못 찾음(시험이 무력 — 덧 호출 1줄 없음)"
  else
    : > "$T/posts.log"; : > "$T/share.log"
    FT_CTX_SHARE_BIN="$T/stub/share9" bash "$T/mut/bin/ft-board-publish.sh" --news \
        > "$T/out.m" 2> /dev/null
    MRC=$?
    [ "$MRC" = 9 ] && [ "$MRC" != "$BASE_RC" ] \
      && ok "$label 변이 M126: 덧 호출 rc 누수 → ⓐ 가 FAIL(rc 9)" \
      || bad "$label 변이 M126: rc 누수가 안 잡힘(rc=$MRC)"
  fi
  rm -f "$T/fifo"
}

suite "harness" "$HERE/../bin/ft-board-publish.sh"
suite "kit" "$HERE/../kit/fable-team/bin/ft-board-publish.sh"

echo "fail=$fail"
[ "$fail" = 0 ]
