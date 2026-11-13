#!/usr/bin/env bash
# test_distill_gate_250_300.sh — 2026-11-06: context-distill-gate.sh 기본 임계 = 경고 250k · 차단 300k · recv 차단선 250k.
#   (옛 값 550k/600k = R445 · 2026-10-19. 내린 이유 = ctx-waste 실측 손익분기 4~9턴 < 세션당 평균 10~21턴)
# 훅을 «--warn-at/--block-at/--recv-gate-at 인자 없이» 부른다(settings.json 이 인자를 안 주는 실배선과 같음).
# 셔뱅 /bin/bash(macOS 3.2) 로 실행 · transcript fixture 로 토큰 값 · 가짜 tmux 로 좌석명 — 실 세션·홈·명부 쓰기 0.
# 인자: [BYZ 훅 경로] — 주면 같은 케이스를 BYZ 사본에도 돌리고 키트와 cmp 0 을 확인한다(ⓕ).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT_HOOK="$HERE/../../harness/kit/fable-team/templates/hooks/context-distill-gate.sh"
BYZ_HOOK="${1:-}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; HOMED="$TMP/home"; SEAT="byz-t-old-claude#1"
mkdir -p "$REPO" "$FAKE" "$HOMED"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"
MBOX="$REPO/.fable-team/comm/mbox.sh"
printf '#!/usr/bin/env bash\ncase "$1" in display) echo "%s";; esac; exit 0\n' "$SEAT" > "$FAKE/tmux"; chmod +x "$FAKE/tmux"

transcript() { # transcript <토큰> → 마지막 실 usage 가 그 값인 jsonl
  printf '{"type":"assistant","message":{"model":"claude-opus-5-5","usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1" > "$TMP/t.jsonl"
}
run() { # run <훅> <모드> <tool> <command|prompt> → $RC · stdout $TMP/out · stderr $TMP/err
  local h="$1" mode="$2" tool="$3" arg="$4" json
  json="$(python3 -c 'import json,sys
t=sys.argv[3]; ti={"command":sys.argv[4]} if t=="Bash" else {"prompt":sys.argv[4],"description":"r445 fixture"}
print(json.dumps({"transcript_path":sys.argv[1],"cwd":sys.argv[2],"tool_name":t,"tool_input":ti}))' "$TMP/t.jsonl" "$REPO" "$tool" "$arg")"
  printf '%s' "$json" | env HOME="$HOMED" PATH="$FAKE:$PATH" TMUX_PANE=%1 /bin/bash "$h" "$mode" >"$TMP/out" 2>"$TMP/err"
  RC=$?
}

cases() { # cases <이름> <훅>
  local n="$1" h="$2"
  /bin/bash -n "$h" && ok "$n /bin/bash -n" || bad "$n /bin/bash -n"
  # r1860: 훅 안 숫자 기본값 0 · 기본값 = 설치본 thresholds.env.sample(250k·300k·250k)
  local smp; smp="$(dirname -- "$h")/../thresholds.env.sample"
  ! grep -q '250_000\|300_000' "$h" && grep -q '^FT_DISTILL_WARN=250000$' "$smp" && grep -q '^FT_DISTILL_BLOCK=300000$' "$smp" && grep -q '^FT_DISTILL_RECV=250000$' "$smp" \
    && ok "$n 기본값 250k/300k/recv 250k = 샘플 한 곳(훅 숫자 0)" || bad "$n 기본값 줄"

  transcript 240000; run "$h" warn "" ""
  { [ "$RC" -eq 0 ] && [ ! -s "$TMP/out" ]; } && ok "$n ⓐ 240k warn → 출력 0" || bad "$n ⓐ rc=$RC out=$(cat "$TMP/out")"

  transcript 260000; run "$h" warn "" ""
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["hookSpecificOutput"]["additionalContext"])' "$TMP/out" >"$TMP/msg" 2>/dev/null
  { [ "$RC" -eq 0 ] && grep -q '260k' "$TMP/msg" && grep -q '경고선(250k)' "$TMP/msg" && grep -q '300k' "$TMP/msg"; } \
    && ok "$n ⓑ 260k warn → 경고 1 (250k·300k 표기)" || bad "$n ⓑ rc=$RC out=$(cat "$TMP/out")"

  transcript 290000; run "$h" block Task "implement feature x"
  { [ "$RC" -eq 2 ] && grep -q '새 일 수락 금지' "$TMP/err"; } && ok "$n ⓒ 290k block Task → 막음(r1429 새 일 금지)" || bad "$n ⓒ rc=$RC err=$(cat "$TMP/err")"
  FT_DISTILL_NEWWORK=300000 run "$h" block Task "implement feature x"
  [ "$RC" -eq 0 ] && ok "$n ⓒ′ NEWWORK=300000 · 290k Task → 허용" || bad "$n ⓒ′ rc=$RC err=$(cat "$TMP/err")"

  transcript 310000; run "$h" block Task "implement feature x"
  { [ "$RC" -eq 2 ] && grep -q '300k 절대값' "$TMP/err"; } && ok "$n ⓓ 310k block Task → exit 2" || bad "$n ⓓ rc=$RC err=$(cat "$TMP/err")"

  rm -rf "$STATE"; transcript 260000; run "$h" hard Bash "bash $MBOX recv $SEAT"
  { [ "$RC" -eq 2 ] && grep -q 'R107' "$TMP/err"; } && ok "$n ⓔ1 260k hard recv · 도달 파일 없음 → 차단" || bad "$n ⓔ1 rc=$RC err=$(cat "$TMP/err")"
  mkdir -p "$STATE"; printf '{"successor":"x","seq":1,"reached_at":"t","rc":0}\n' > "$STATE/$SEAT.json"
  run "$h" hard Bash "bash $MBOX recv $SEAT"
  [ "$RC" -eq 0 ] && ok "$n ⓔ2 260k hard recv · 도달 파일 있음 → 허용" || bad "$n ⓔ2 rc=$RC err=$(cat "$TMP/err")"
  rm -rf "$STATE"; transcript 240000; run "$h" hard Bash "bash $MBOX recv $SEAT"
  [ "$RC" -eq 0 ] && ok "$n ⓔ3 240k hard recv → 허용(recv 선 250k)" || bad "$n ⓔ3 rc=$RC err=$(cat "$TMP/err")"
  transcript 310000; run "$h" hard Bash "echo hi > $REPO/x.py"
  [ "$RC" -eq 2 ] && ok "$n ⓔ4 310k hard 일반 도구 → 차단" || bad "$n ⓔ4 rc=$RC"

  # ⓖ 600 s·300 s 시간 상한 0 · codex/opencode 설정 참조 0(이 훅은 claude 좌석 전용)
  { ! grep -Eq 'timeout *= *(600|300)\b|sleep (600|300)\b' "$h" && ! grep -Eq 'config\.toml|opencode\.json' "$h"; } \
    && ok "$n ⓖ 600/300 s 0 · codex/opencode 설정 참조 0" || bad "$n ⓖ"
}

cases kit "$KIT_HOOK"
if [ -n "$BYZ_HOOK" ]; then
  cmp -s "$KIT_HOOK" "$BYZ_HOOK" && ok "ⓕ BYZ 훅 == 키트 훅 (cmp 0)" || bad "ⓕ BYZ 훅 cmp ≠ 0"
  cases byz "$BYZ_HOOK"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL=$fail"
exit "$fail"
