#!/usr/bin/env bash
# ft-mbox-bridge.sh — 두 큐를 «한 번의 호출»로 조회한다.
#
# 왜 있나: 트랙 간 메시지를 «좌석»이 브리지하면 메시지마다 그 좌석이 깨어나고
#   그때마다 전체 문맥을 재전송한다. 틱 감사(Q7)에서 비용의 절반이 나온 구조와 같다
#   (400k+ 좌석에 도착한 틱 16,284건 = $29,954). 브리지는 명령이 맡는다.
#
# ★기존 mbox.py / mbox.sh 를 한 줄도 고치지 않는다★ — v65 좌석이 보는 파일은 그대로다.
#   큐는 FT_MBOX_DIR 로만 갈린다(mbox.py:109-111 「명시가 추론을 이긴다」).
#   _load/_consume 이 디렉토리별로 분리돼 있어 순차 조회해도 소비가 어긋나지 않는다.
#
# 사용:
#   ft-mbox-bridge.sh recv <me> [--all]     # 두 큐 전부 조회·소비, 큐 이름 표시
#   ft-mbox-bridge.sh peek <me>             # 두 큐 pending 합계 + 큐별 내역
#   ft-mbox-bridge.sh queues                # 현재 조회 대상 큐 나열
#   ft-mbox-bridge.sh send <queue> <to> <from> <body...>   # 그 큐로 넣고 ★브리지를 가리키는 doorbell★
#
# ★send 가 왜 필요한가 (검토 B1, 2026-09-22)★
#   원본 doorbell 은 `bash <mbox.sh> recv <to>` 를 주입한다 — FT_MBOX_DIR 이 안 실린다.
#   그래서 v2 큐로 보내면 창은 울리는데 좌석은 «공용 큐»를 열어 READ none 을 본다(재현됨).
#   해결: doorbell 이 가리키는 대상을 브리지로 바꾼다. 브리지 recv 는 두 큐를 다 본다.
#   구현: 원본을 고치지 않고 사본 mbox-v2.sh(SELF 만 env 로 교체 가능, 1줄 차이)를 쓴다.
#   ★mbox-v2.sh 는 mbox.py 와 같은 디렉토리에 둬야 한다★ — $DIR 로 py 를 찾기 때문이다.
#
# 큐 결정:
#   common = <repo-root>/.fable-team/comm          (트랙 간 · v65 와 공용)
#   v2     = $FT_MBOX_DIR_V2                        (v2 내부 전용, 없으면 건너뜀)
#   추가 큐는 FT_MBOX_DIRS 에 "이름=경로" 를 쉼표로 이어 넣는다.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-harness-root.sh"
_comm() { ft_comm_dir "$HERE" || exit 2; }   # r385 r3: 설치본엔 ../comm 없음 — 데이터 루트의 comm
MBOX="${FT_MBOX_CMD:-}"; [ -n "$MBOX" ] || MBOX="$(_comm)/mbox.sh" || exit 2
[ -x "$MBOX" ] || [ -f "$MBOX" ] || { echo "REJECT mbox 없음: $MBOX" >&2; exit 2; }

_repo_root() {
  local wt root
  wt="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  root="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  echo "${root:-$wt}"
}

# 조회 대상 큐 목록을 "이름<TAB>경로" 로 뽑는다. 없는 경로는 조용히 건너뛴다.
_queues() {
  local root common
  root="$(_repo_root)" || root=""
  common="${FT_MBOX_DIR_COMMON:-${root:+$root/.fable-team/comm}}"
  [ -n "$common" ] && [ -d "$common" ] && printf 'common\t%s\n' "$common"

  local v2="${FT_MBOX_DIR_V2:-}"
  [ -n "$v2" ] && [ -d "$v2" ] && printf 'v2\t%s\n' "$v2"

  local extra="${FT_MBOX_DIRS:-}"
  if [ -n "$extra" ]; then
    local IFS=','; local pair
    for pair in $extra; do
      local n="${pair%%=*}" p="${pair#*=}"
      [ -n "$n" ] && [ -n "$p" ] && [ -d "$p" ] && printf '%s\t%s\n' "$n" "$p"
    done
  fi

  # ★설정 파일 폴백★ — doorbell 로 깨어난 좌석의 셸에는 env 가 없다.
  #   env 만 믿으면 「창은 울리는데 READ none」이 그대로 재발한다(검토 B1).
  #   형식: 한 줄에 「이름=절대경로」, # 은 주석. env 로 이미 나온 이름은 덮지 않는다.
  local conf="${FT_MBOX_QUEUES_CONF:-${root:+$root/.fable-team/comm/queues.conf}}"
  if [ -n "$conf" ] && [ -f "$conf" ]; then
    local line n p
    while IFS= read -r line; do
      case "$line" in ''|'#'*) continue;; esac
      case "$line" in
        *=*) ;;
        *) printf 'WARN queues.conf 형식 오류 — 등호가 없다: %s\n' "$line" >&2; continue;;
      esac
      n="${line%%=*}"; p="${line#*=}"
      n="$(printf '%s' "$n" | tr -d '[:space:]')"
      p="$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      # ★조용히 건너뛰지 않는다★ (#0 RULE · 검토 조건①) — 설정에 적힌 큐가 실재하지 않으면
      #   그 큐로 온 메시지는 «영영 안 읽힌다». 에러 0줄로 사라지면 아무도 모른다.
      if [ -z "$n" ] || [ -z "$p" ]; then
        printf 'WARN queues.conf 형식 오류 — 「이름=절대경로」 아님: %s\n' "$line" >&2; continue
      fi
      if [ ! -d "$p" ]; then
        printf 'WARN queues.conf 의 큐 경로가 없다 — 이 큐로 온 메시지는 안 읽힌다: %s=%s\n' "$n" "$p" >&2; continue
      fi
      [ "$n" = "common" ] && continue
      [ "$n" = "v2" ] && [ -n "${FT_MBOX_DIR_V2:-}" ] && continue
      printf '%s\t%s\n' "$n" "$p"
    done < "$conf"
  fi
}

CMD="${1:-}"; shift || { echo "usage: $0 recv|peek|queues <me> [--all]" >&2; exit 2; }

case "$CMD" in
  queues)
    _queues | while IFS=$'\t' read -r name dir; do
      printf '%-8s %s  (pending 파일 %s)\n' "$name" "$dir" \
        "$([ -f "$dir/mailbox.jsonl" ] && echo 있음 || echo 없음)"
    done
    ;;

  recv)
    ME="${1:-}"; shift || true
    [ -n "$ME" ] || { echo "usage: $0 recv <me> [--all]" >&2; exit 2; }
    found=0; any=0
    while IFS=$'\t' read -r name dir; do
      any=1
      out="$(FT_MBOX_DIR="$dir" bash "$MBOX" recv "$ME" "$@" 2>&1)"
      # 빈 큐(READ none)는 줄을 차지하지 않게 한 줄로 줄인다
      if printf '%s' "$out" | grep -q 'READ none'; then
        printf '[%s] READ none\n' "$name"
      else
        printf '[%s]\n%s\n' "$name" "$out"
        found=1
      fi
    done < <(_queues)
    [ "$any" = 1 ] || { echo "REJECT 조회할 큐가 없다 — FT_MBOX_DIR_COMMON/FT_MBOX_DIR_V2 확인" >&2; exit 1; }
    exit 0
    ;;

  peek)
    ME="${1:-}"
    [ -n "$ME" ] || { echo "usage: $0 peek <me>" >&2; exit 2; }
    total=0; any=0
    while IFS=$'\t' read -r name dir; do
      any=1
      line="$(FT_MBOX_DIR="$dir" bash "$MBOX" peek "$ME" 2>&1)"
      n="$(printf '%s' "$line" | sed -n 's/.*pending=\([0-9]\{1,\}\).*/\1/p' | head -1)"
      [ -n "$n" ] || n=0
      total=$((total + n))
      printf '[%s] %s\n' "$name" "$line"
    done < <(_queues)
    [ "$any" = 1 ] || { echo "REJECT 조회할 큐가 없다" >&2; exit 1; }
    printf 'TOTAL pending=%s (큐 합계)\n' "$total"
    exit 0
    ;;

  send)
    # send <queue> <to> <from> <body...>
    Q="${1:-}"; shift || true
    [ -n "$Q" ] || { echo "usage: $0 send <queue> <to> <from> <body...>" >&2; exit 2; }
    dir=""
    while IFS=$'\t' read -r name d; do [ "$name" = "$Q" ] && dir="$d"; done < <(_queues)
    [ -n "$dir" ] || { echo "REJECT 큐 없음: $Q — 사용 가능: $(_queues | cut -f1 | tr '\n' ' ')" >&2; exit 1; }

    V2SH="${FT_MBOX_V2_CMD:-}"; [ -n "$V2SH" ] || V2SH="$(_comm)/mbox-v2.sh" || exit 1
    [ -f "$V2SH" ] || { echo "REJECT mbox-v2.sh 없음: $V2SH" >&2; exit 1; }
    # ★doorbell 이 브리지를 가리키게 한다★ — 수신 좌석이 두 큐를 다 열게 된다
    BRIDGE_ABS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename -- "${BASH_SOURCE[0]:-$0}")"
    FT_MBOX_DIR="$dir" FT_MBOX_SELF="$BRIDGE_ABS" bash "$V2SH" send "$@"
    exit $?
    ;;

  *)
    echo "unknown: $CMD (recv|peek|queues|send)" >&2; exit 2;;
esac
