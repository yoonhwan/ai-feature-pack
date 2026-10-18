#!/usr/bin/env bash
# ft-verdict-lock.sh — ft-verdict.sh 가 source 하는 잠금 함수 (직접 실행하지 않는다).
# 호출 쪽이 die · STATE · LOCK 을 먼저 정의해야 한다.
# 잠금 = mkdir verdicts.lock + 안에 보유 pid 기록 (macOS 에 flock 없음). 대기 중 보유 pid 가 죽었으면(kill -0 실패)
#   stderr 1줄 남기고 해제 후 획득 · 살아 있으면 10초(FT_VERDICT_LOCK_TRIES×0.1s) 뒤 rc 1 + 보유 pid 표시.

release_lock() { [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK"; }

# 보유 pid 가 죽은 잠금이면 stderr 1줄 남기고 치운다. rename 으로 «한 대기자만» 가져가고, 가져온 것이 관측한 죽은 pid 가 아니면 되돌린다.
reap_stale_lock() {
  local pid moved="$LOCK.stale.$$"
  pid="$(cat "$LOCK/pid" 2>/dev/null)"
  case "$pid" in ''|*[!0-9]*) return 1;; esac   # pid 미기록(방금 생성 중)이면 건드리지 않는다
  kill -0 "$pid" 2>/dev/null && return 1
  mv "$LOCK" "$moved" 2>/dev/null || return 1
  if [ "$(cat "$moved/pid" 2>/dev/null)" = "$pid" ]; then
    rm -rf "$moved"
    echo "WARN 죽은 잠금 해제: 보유 pid $pid 없음 — $LOCK" >&2
    return 0
  fi
  mv "$moved" "$LOCK" 2>/dev/null || rm -rf "$moved"   # 산 잠금을 잘못 가져왔다 — 되돌림
  return 1
}

acquire_lock() {
  mkdir -p "$STATE" || die "state 폴더 생성 실패: $STATE"
  local i=0 tries="${FT_VERDICT_LOCK_TRIES:-100}"
  until mkdir "$LOCK" 2>/dev/null; do
    reap_stale_lock && continue
    i=$((i+1))
    [ "$i" -gt "$tries" ] && die "원장 잠금 $((tries/10))초 초과 — $LOCK 보유 pid $(cat "$LOCK/pid" 2>/dev/null || echo 미기록) (살아 있는 보유자 — 사람 확인)"
    sleep 0.1
  done
  echo "$$" > "$LOCK/pid"
  trap release_lock EXIT
}
