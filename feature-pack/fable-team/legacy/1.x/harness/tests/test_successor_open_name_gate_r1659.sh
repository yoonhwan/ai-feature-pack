#!/usr/bin/env bash
# test_successor_open_name_gate_r1659.sh — r1659: 승계 개설 입구 = 이름 lint 관문 · 꼬리 에이전트 = --agent · 같은 계보도 모델 꼬리 예외 0.
#   ⓐ sol 꼬리 → REJECT rc1 첫 줄 «REJECT 이름 lint» + lint 사유 · 열기 0 · 명부 쓰기 0 | ⓑ 꼬리 pi ≠ codex → REJECT · 열기 0
#   ⓒ codex 꼬리 → 관문 통과(문지기 스텁까지) | ⓓ2 구 sol#60 → sol#61 REJECT · codex#61 통과 | ⓓ nano = lint 만
#   ⓔ 같은 이름 세션 있음(재실행 r609)도 관문 먼저 · r1468 시험 rc0
#   임시 bin 사본(FT_SO_KIT 로 바꿀 수 있음 = 변이 시험)·가짜 tmux·tmuxc·문지기·send·reach 스텁만 — 실 좌석·실 명부 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${FT_SO_KIT:-$HERE/../kit/fable-team/bin}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"; cp -R "$KIT/." "$BIN/"; SO="$BIN/ft-successor-open.sh"
printf '#!/usr/bin/env bash\necho "GATE $*" >> "$LOG"; echo "REJECT stub gate"; exit 1\n' > "$BIN/ft-resource-gate.sh"
printf 'import sys\nsys.exit(0)\n' > "$BIN/ft_teamset.py"
printf '#!/usr/bin/env bash\necho "SEND $*" >> "$LOG"; exit 1\n' > "$TMP/send.sh"; cp "$TMP/send.sh" "$TMP/reach.sh"
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; RES="$TMP/res"
mkdir -p "$REPO" "$FAKE" "$RES/.fable-team"; git -C "$REPO" init -q
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux  'case "$1" in has-session) case " $LIVE " in *" ${3#=} "*) exit 0;; esac; exit 1;; esac; exit 0'
mkstub tmuxc 'echo "tmuxc $*" >> "$LOG"; exit 0'
printf '골 1\n골 2\n골 3\n본문\n열린 칸 감시: 없음\n' > "$BODY"
printf '| 팀 | 오케 | arch 상시 |\n|---|---|---|\n| t | byz-t-master-codex | — |\n' > "$TMP/teamset.md"
SEATS="$RES/.fable-team/seats-t.json"
run() {   # run <구> <후계> <agent> [살아 있는 세션들]
  : > "$LOG"
  printf '{"_master": "%s", "%s": {"agent": "codex"}}\n' "$1" "$1" > "$SEATS"; SUM0="$(shasum "$SEATS")"
  env HOME="$TMP/home" PATH="$FAKE:$PATH" LOG="$LOG" LIVE="$1 ${4:-}" FT_RES_ROOT="$RES" FT_TEAMSET_MD="$TMP/teamset.md" FT_RECLAIM=0 \
      FT_NAME_LINT="$BIN/ft-name-lint.sh" FT_SEND_VERIFIED="$TMP/send.sh" FT_REACH_CHECK="$TMP/reach.sh" \
      bash "$SO" "$1" "$REPO" --name "$2" --agent "$3" --model m --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
show() { echo "rc=$RC out=$(tr '\n' ' ' < "$TMP/out" | cut -c1-300) log=$(tr '\n' ' ' < "$LOG")"; }
opened0() { ! grep -qE '^(tmuxc|GATE|SEND)' "$LOG" && [ "$(shasum "$SEATS")" = "$SUM0" ]; }
passed()  { grep -q '^GATE check' "$LOG" && ! grep -q '이름 lint\|이름 꼬리' "$TMP/out"; }

# ⓐ 모델 꼬리 sol → lint REJECT rc1 · 첫 줄 · lint 사유 · 열기 0 · 명부 쓰기 0
run 'byz-t-master-codex#0' 'byz-t-master-sol#1' codex
{ [ "$RC" = 1 ] && head -1 "$TMP/out" | grep -q "^REJECT 이름 lint — REJECT byz-t-master-sol#1: .*꼬리는 에이전트여야 한다.*'sol'" && opened0; } \
  && ok "ⓐ sol 꼬리 → REJECT 이름 lint rc1 · 열기·명부 0" || bad "ⓐ $(show)"
# ⓑ 꼬리 pi ≠ --agent codex → REJECT(r1468 관문) · 열기 0
run 'byz-t-master-codex#0' 'byz-t-master-pi#1' codex
{ [ "$RC" != 0 ] && grep -q '^REJECT 이름 꼬리 pi ≠ --agent codex' "$TMP/out" && opened0; } \
  && ok "ⓑ 꼬리 pi ≠ codex → REJECT · 열기 0" || bad "ⓑ $(show)"
# ⓒ 맞는 이름 → 관문 통과(문지기 스텁까지)
run 'byz-t-master-codex#0' 'byz-t-master-codex#1' codex
passed && ok "ⓒ codex 꼬리 → 관문 통과" || bad "ⓒ $(show)"
# ⓓ2 모델 꼬리 계보 sol#60 → sol#61 = REJECT(같은 계보 예외 0) · codex#61 = 통과
run 'byz-t-master-sol#60' 'byz-t-master-sol#61' codex
{ [ "$RC" = 1 ] && head -1 "$TMP/out" | grep -q '^REJECT 이름 lint' && opened0; } \
  && ok "ⓓ2-1 같은 계보 sol#61 → REJECT" || bad "ⓓ2-1 $(show)"
run 'byz-t-master-sol#60' 'byz-t-master-codex#61' codex
passed && ok "ⓓ2-2 sol#60 → codex#61 통과" || bad "ⓓ2-2 $(show)"
# ⓓ nano 이름 = lint 만(꼬리 대조 0) · nano lint 위반은 REJECT
run 'byz-t-master-codex#0' 'byz-t-nano-r1-x#0' codex
passed && ok "ⓓ nano → lint 만 · 통과" || bad "ⓓ $(show)"
run 'byz-t-master-codex#0' 'byz-t-nano#0' codex
{ [ "$RC" = 1 ] && grep -q '^REJECT 이름 lint.*slug' "$TMP/out" && opened0; } && ok "ⓓ-2 slug 없는 nano → REJECT" || bad "ⓓ-2 $(show)"
# ⓔ 재실행(같은 이름 세션 있음)도 관문 먼저 — 이어감 0
run 'byz-t-master-sol#60' 'byz-t-master-sol#61' codex 'byz-t-master-sol#61'
{ [ "$RC" = 1 ] && head -1 "$TMP/out" | grep -q '^REJECT 이름 lint' && ! grep -q '이어감' "$TMP/out" && opened0; } \
  && ok "ⓔ 재실행도 관문 먼저 · 이어감 0" || bad "ⓔ $(show)"
# ⓔ-2 기존 r1468 시험 rc0(같은 KIT)
FT_SO_KIT="$KIT" bash "$HERE/test_successor_open_agent_token_r1468.sh" > "$TMP/r1468" 2>&1 \
  && ok "ⓔ-2 r1468 시험 rc0" || bad "ⓔ-2 $(grep FAIL "$TMP/r1468" | tr '\n' ' ')"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
