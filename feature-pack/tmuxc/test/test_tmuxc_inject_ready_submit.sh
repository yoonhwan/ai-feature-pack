#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit.sh — r925 r4(인덱스 r925-tmuxc-inject-submit-verify-and-succ · DA⑥ r3 HOLD → DECISION-r925-r4-final.md 고침 4)
#   tmuxc 가 claude 를 띄우고 «고정 sleep 4 → 글자 → Enter 1번» 이라 컴퓨터가 바쁘면 글자만 입력줄에 남고 Enter 가
#   사라졌다(ops #56→#57 3회 정지). 원칙(r3 R1~R4 + r4 고침 4):
#     R1 제출 판정 = 세션 기록 — tmuxc 가 발급한 --session-id 의 <id>.jsonl «한 파일» 에서, Enter «직전» 파일 끝 뒤 user 레코드
#        · 마감 = 첫 Enter + TMUXC_SUBMIT_WAIT초 «벽시계»
#     R2 우리 글자 = 입력줄이 «이번 메시지 전문» 과 완전 일치(문장 안 공백 그대로 · SGR 벗김 · -J · 줄 끝 공백 · TUI 줄 경계만 너그럽게)
#     R3 재전송 Enter = 기록 없음 ∧ 입력줄 = 전문 ∧ 직전 기록 재조회에도 없음일 때만 1회 · R4 판독 불가 = rc≠0
#   시험(DECISION r3 ⓐ~ⓔ + r4 ⓕ~ⓙ):
#     ⓐ 옛 출력(화면·기록)에 같은 메시지 + 새 제출 0 → rc≠0 · «submitted» 0
#     ⓑ 늦은 기록 + 사람이 같은 접두 25자 입력 → 재전송 0 · 사람 입력 제출 0 · rc0
#     ⓒ boot-enter: 입력줄 = 전문 RGB 흰색 → Enter 1 · rc0 / 회색 앞부분만 → 손대지 않음 rc≠0
#     ⓓ capture-pane 이 정상 모양 출력 + rc1 → rc≠0(주입 0)
#     ⓔ boot-enter: 권한 프롬프트 화면 → rc≠0 «[HIL] 입력줄 판독 불가»
#     ⓕ boot-enter: 옛 기록(앞 30자 같음) + 입력줄 = 새 문장 → Enter 1 · 새 레코드 뒤 rc0(옛 기록으로 «이미 제출» 0)
#     ⓖ boot-enter: 세션 env id 없음 + resume 파일 id → 그 파일로 판정 / 둘 다 없음 → rc3
#     ⓗ 입력줄 «통 신표준»(공백 위치만 다름) → 우리 글자 아님 · Enter 0
#     ⓘ 마지막 조회 직후 첫 Enter 기록 생김 → 재전송 0 · rc0
#     ⓙ 조회 지연 0.04초 × 많음 + WAIT=7 → 9초 전에 끝남(벽시계 마감)
#   이어 온 시험: g1 준비 6초 늦음 · g2 첫 Enter 유실 → 재전송 1 · g3 Enter 전부 유실 → 실패 · g4 준비 빠름 ·
#     g5 새 claude 자리표시 «Try "…"» → 주입·제출 · g6 사람 글자 위 → Enter 0 · g7 id 없는 agent 주입 → rc≠0 ·
#     g8 TUI 가 긴 문장을 여러 줄로 감음(실측 꼴) → 전문 일치 · 제출 · g9 boot-enter 옛 기록만 + 자리표시 → rc4 ·
#     ⓛ codex·pi(plain) = 기준 커밋 cbe218a5 와 tmux 호출 바이트 같음 · ⓝ cmd_open 주입 실패 문구 · ⓞ open 이 id 를 발급·심음
#   픽스처 = 가짜 tmux(상태 폴더 파일) + 가짜 기록 폴더(<id>.jsonl) — 실 tmux 서버·실 에이전트·홈 쓰기 0.
#   시험 대상 = env FT_TMUXC_PATH (기본 = 이 저장소 사본) — 옛 사본으로 돌리면 빨강이어야 한다.
#   변이(FT_MUTATE): J = 기록 판정 → 화면 판정 복귀 · P = 재전송 판정에 접두 인정 복귀 · C = capture rc 무시 ·
#                    E = boot-enter 판독 불가 rc0 복귀
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="${FT_TMUXC_PATH:-$HERE/../core/bin/tmuxc}"
MUTATE="${FT_MUTATE:-0}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }

[ -f "$TMUXC" ] || { echo "FAIL 대상 없음: $TMUXC"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
D="$T/state"; B="$T/bin"; PROJ="$T/projects"; mkdir -p "$D" "$B" "$PROJ"
SHIM="$T/shim.sh"
SID="0f0e0d0c-1111-4222-8333-444455556666"
JF="$PROJ/-fake-proj/$SID.jsonl"
MSG='[byz-t-old-claude#1→byz-t-new-claude#2] 통신 표준: 지금 read로 읽고 그대로 따를 것'

# ---------- 가짜 tmux ----------
#   상태 파일: ready(입력 상자 그려짐) · buffer(입력줄) · transcript(입력 상자 «위» 화면) · placeholder(빈 입력줄에 «Try "…"»)
#     enters_lost(유실할 Enter 수) · submit_void(Enter 가 입력줄만 비우고 기록 0) · jsonl_delay(첫 제출 기록을 N초 늦게)
#     enter_deferred(Enter 가 화면·기록 둘 다 아직 안 바꿈) · rec_at_cap(N번째 판독 순간 MSG 기록 1줄)
#     human_at(N번째 판독 순간 사람이 HUMAN_TEXT 입력) · cap_rc1(정상 모양 출력 + rc1) · no_box(권한 프롬프트)
#     sgr(입력줄 글자 색 SGR) · wrap(폭 N — TUI 처럼 낱말 경계에서 감고 이어지는 줄 들여쓰기 2칸)
#     env_<KEY>(세션 env) · cap_n(판독 횟수) · log(호출)
cat > "$B/tmux" <<'SH'
#!/usr/bin/env bash
D="${FAKE_AGENT_DIR:?}"
JF="${TMUXC_CLAUDE_PROJECTS:?}/-fake-proj/${FAKE_SID:?}.jsonl"
printf '%s\n' "$*" >> "$D/log"
rec() { mkdir -p "$(dirname "$JF")"; python3 -c 'import json,sys;print(json.dumps({"type":"user","message":{"role":"user","content":sys.argv[1]}},ensure_ascii=False))' "$1" >> "$JF"; }
cmd="$1"; shift || true
case "$cmd" in
  has-session) exit 0 ;;
  list-panes) printf 'sess|%%0\n'; exit 0 ;;
  show-environment)
    key="${*: -1}"; [ -f "$D/env_$key" ] || exit 1
    printf '%s=%s\n' "$key" "$(cat "$D/env_$key")"; exit 0 ;;
  capture-pane)
    n=$(( $(cat "$D/cap_n" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$n" > "$D/cap_n"
    if [ -f "$D/human_at" ] && [ "$n" -ge "$(cat "$D/human_at")" ]; then
      rm -f "$D/human_at"; printf '%s' "${HUMAN_TEXT:-HUMAN LINE}" >> "$D/buffer"
    fi
    if [ -f "$D/rec_at_cap" ] && [ "$n" -ge "$(cat "$D/rec_at_cap")" ]; then rm -f "$D/rec_at_cap"; rec "$(cat "$D/buffer")"; fi
    if [ -f "$D/no_box" ]; then printf 'Do you want to proceed?\n❯ 1. Yes\n  2. No\n'; exit 0; fi
    if [ ! -f "$D/ready" ]; then printf 'starting agent...\n'; exit 0; fi
    [ -f "$D/transcript" ] && cat "$D/transcript"
    printf '─────\n'
    buf="$(cat "$D/buffer" 2>/dev/null || true)"
    if [ -n "$buf" ] && [ -f "$D/wrap" ]; then
      python3 -c 'import sys,textwrap
w=int(sys.argv[2]); ls=textwrap.wrap(sys.argv[1], width=w, break_long_words=True, break_on_hyphens=False) or [""]
print("❯ "+ls[0]); [print("  "+l) for l in ls[1:]]' "$buf" "$(cat "$D/wrap")"
    elif [ -n "$buf" ]; then
      if [ -f "$D/sgr" ]; then printf '❯ \033[%sm%s\033[0m\n' "$(cat "$D/sgr")" "$buf"; else printf '❯ %s\n' "$buf"; fi
    elif [ -f "$D/placeholder" ]; then printf '❯ \033[2mTry "how does cairn.py work?"\033[0m\n'
    else printf '❯ \n'; fi
    printf '─────\n'
    printf '  status\n'
    [ -f "$D/cap_rc1" ] && exit 1
    exit 0 ;;
  send-keys)
    lit=0; arg=""
    while [ $# -gt 0 ]; do case "$1" in
      -t) shift 2 ;;
      -l) lit=1; shift ;;
      *)  arg="$1"; shift ;;
    esac; done
    if [ "$lit" = 1 ]; then printf '%s' "$arg" >> "$D/buffer"; exit 0; fi   # pty 는 준비 전에도 글자를 받아 둔다
    [ "$arg" = Enter ] || exit 0
    [ -f "$D/ready" ] || exit 0                                            # 준비 전 Enter = 유실
    n="$(cat "$D/enters_lost" 2>/dev/null || echo 0)"
    if [ "$n" -gt 0 ]; then printf '%s\n' "$((n - 1))" > "$D/enters_lost"; exit 0; fi
    if [ -f "$D/enter_deferred" ]; then rm -f "$D/enter_deferred"; exit 0; fi   # 먹혔지만 화면·기록이 아직 안 바뀜
    if [ -f "$D/submit_void" ]; then rm -f "$D/submit_void"; : > "$D/buffer"; exit 0; fi
    txt="$(cat "$D/buffer" 2>/dev/null || true)"
    printf '%s\n' "$txt" >> "$D/transcript"; : > "$D/buffer"
    if [ -f "$D/jsonl_delay" ]; then
      dl="$(cat "$D/jsonl_delay")"; rm -f "$D/jsonl_delay"
      ( sleep "$dl"; rec "$txt" ) >/dev/null 2>&1 &
    else
      rec "$txt"
    fi
    exit 0 ;;
esac
exit 0
SH
chmod +x "$B/tmux"

# ---------- 함수 추출(대상 사본에서 그대로 잘라 온다) ----------
FUNCS='pane_id_of capture_input_line wait_input_box squash_ws now_ms claude_jsonl_of claude_jsonl_size claude_submitted_since input_is_message agent_inject inject_message session_env_value seat_uuid_fallback cmd_boot_enter'
FUNCS="$FUNCS text_head screen_flat buffer_is_ours submit_state"   # r2 판(8d6a4756)의 판정 함수 — 빨강 대조용(지금 판에는 없다)
: > "$SHIM"
for f in $FUNCS; do sed -n "/^${f}()/,/^}/p" "$TMUXC" >> "$SHIM"; done
printf 'die() { printf "tmuxc: %%s\\n" "$*" >&2; exit 1; }\nsession_agent_probe() { return 1; }\n' >> "$SHIM"
printf '_sq() { printf "%%s" "$1" | LC_ALL=C tr -d "[:space:]"; }\n' >> "$SHIM"   # 변이용(공백 지운 비교 · 지금 판은 안 쓴다)
grep -q '^inject_message()' "$SHIM" || { echo "FAIL inject_message 를 못 잘랐다: $TMUXC"; exit 1; }

# 한 판 실행 — 결과: RC · SECS · $T/out
call() {
  local t0 t1
  t0="$(python3 -c 'import time;print(time.time())')"
  ( set -uo pipefail; . "$SHIM"
    [ -n "${LOOKUP_DELAY:-}" ] && { eval "$(declare -f claude_submitted_since | sed '1s/claude_submitted_since/_css_orig/')"
      claude_submitted_since() { sleep "$LOOKUP_DELAY"; _css_orig "$@"; }; }
    export FAKE_AGENT_DIR="$D" FAKE_SID="$SID" PATH="$B:$PATH" TMUXC_CLAUDE_PROJECTS="$PROJ" HUMAN_TEXT="${HUMAN_TEXT:-HUMAN LINE}"
    export TMUXC_READY_MAX="${TMUXC_READY_MAX:-30}" TMUXC_SUBMIT_WAIT="${TMUXC_SUBMIT_WAIT:-7}"
    export TMUXC_SEAT_RESUME_DIR="$D/resume" TMUXC_SEATS_DIR="$D/seats"
    "$@" ) > "$T/out" 2>&1
  RC=$?
  t1="$(python3 -c 'import time;print(time.time())')"
  SECS="$(python3 -c "print(round($t1-$t0,2))")"
}
fresh() { rm -rf "$D" "$PROJ"; mkdir -p "$D" "$PROJ"; }
typed_lit()  { cat "$D/log" 2>/dev/null | grep -c ' -l ' || true; }
enters()     { cat "$D/log" 2>/dev/null | grep -c 'send-keys -t %0 Enter' || true; }
rec_count()  { cat "$JF" 2>/dev/null | grep -c '"type": *"user"' || true; }
seed_rec()   { mkdir -p "$(dirname "$JF")"; python3 -c 'import json,sys;print(json.dumps({"type":"user","message":{"role":"user","content":sys.argv[1]}},ensure_ascii=False))' "$1" >> "$JF"; }
outline()    { tr '\n' ' ' < "$T/out" | cut -c1-300; }

# ---------- 고치기 전 사본: 빨강의 «내용» 을 남긴다 ----------
if ! grep -q '^claude_submitted_since()' "$SHIM"; then
  echo "FAIL 고치기 전 사본 — 세션 기록 판정(claude_submitted_since)이 없다: $TMUXC"
  fresh; : > "$D/ready"; printf '%s\n' "$MSG" > "$D/transcript"; : > "$D/submit_void"
  call inject_message sess "$MSG" agent
  echo "옛 판 ⓐ(옛 출력 + 새 제출 0): rc=$RC out=[$(outline)] 새 기록=$(rec_count)"
  fresh; : > "$D/ready"; : > "$D/placeholder"
  call inject_message sess "$MSG" agent
  echo "옛 판 g5(자리표시): rc=$RC out=[$(outline)] 제출=[$(cat "$D/transcript" 2>/dev/null)]"
  exit 1
fi

case "$MUTATE" in
  J) # 기록 판정 → 화면 판정 복귀(입력줄 빔 ∧ 입력 상자 «위» 에 앞 30자) — r2 의 판정
     cat >> "$SHIM" <<'EOF'
claude_submitted_since() {  # MUTATE J
  local c h s
  c="$(capture_input_line "$pane" join)" || return 2
  [[ -z "$c" ]] || return 1
  h="$(_sq "$3")"; h="${h:0:30}"
  s="$(tmux capture-pane -t "$pane" -p)" || return 2
  s="$(printf '%s\n' "$s" | awk '/^─────/{exit} {print}' | LC_ALL=C tr -d '[:space:]')"
  [[ "$s" == *"$h"* ]]
}
EOF
     ;;
  P) # 재전송 판정에 접두 인정 복귀(입력줄이 전문의 앞부분 20자 이상이면 우리 글자) — r2 의 buffer_is_ours
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '''      # R3 재전송 판정 — 기록 없음 ∧ 입력줄 = 전문(접두·잘림 인정 0)
      st=0; input_is_message "$pane" "$message" || st=$?'''
new = '''      # R3 재전송 판정 — MUTATE P 접두 인정
      st=0; _c="$(capture_input_line "$pane" join)" || st=2
      if [[ "$st" -eq 0 ]]; then _c="$(_sq "$_c")"; _w="$(_sq "$message")"
        if [[ -n "$_c" && ${#_c} -ge 20 && "${_w:0:${#_c}}" == "$_c" ]]; then st=0; else st=1; fi; fi'''
assert old in s, "MUTATE P 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  C) # capture-pane rc 무시(정상 모양 출력이면 믿는다)
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
n = s.count('2>/dev/null)" || return 2')
assert n == 2, "MUTATE C 대체 실패 %d" % n
open(p, "w", encoding="utf-8").write(s.replace('2>/dev/null)" || return 2', '2>/dev/null)" || true  # MUTATE C'))
PY
     ;;
  E) # boot-enter 판독 불가 = rc0 복귀
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '''(권한 프롬프트·화면 못 읽음) · Enter 0\\n' "$name" >&2
    return 2'''
new = '''(권한 프롬프트·화면 못 읽음) · Enter 0\\n' "$name" >&2
    return 0  # MUTATE E'''
assert old in s, "MUTATE E 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  0) ;;
  *) echo "FAIL 모르는 변이: $MUTATE"; exit 1 ;;
esac

# 무한 대기 방지 — 20초 넘으면 124
call_limited() {
  local lim=20 p i
  ( call "$@"; printf '%s %s\n' "$RC" "$SECS" > "$T/res" ) & p=$!
  i=0
  while kill -0 "$p" 2>/dev/null; do
    sleep 0.2; i=$((i + 1))
    if [ "$i" -gt $((lim * 5)) ]; then kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; printf '124 %s\n' "$lim" > "$T/res"; break; fi
  done
  wait "$p" 2>/dev/null
  read -r RC SECS < "$T/res"
}

# ⓐ 옛 출력(화면 + 기록)에 같은 메시지 + 새 제출 0(Enter 가 입력줄만 비움) → rc≠0 · «submitted» 0 · 재전송 0
fresh; : > "$D/ready"; printf '%s\n' "$MSG" > "$D/transcript"; seed_rec "$MSG"; : > "$D/submit_void"
TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && ! grep -q 'state=submitted' "$T/out" && grep -q '제출 실패' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ]; } \
  && ok "ⓐ 옛 출력·옛 기록에 같은 메시지 + 새 제출 0 → rc=$RC «제출 실패» · submitted 0 · Enter 1(재전송 0)" \
  || bad "ⓐ rc=$RC enters=$(enters) rec=$(rec_count) out=$(outline)"

# ⓑ 늦은 기록(첫 Enter 가 3초 뒤 jsonl 에) + 재전송 판정 순간 사람이 같은 접두 25자 입력 → 재전송 0 · 사람 입력 제출 0 · rc0
HUMAN25="$(python3 -c 'import sys;print(sys.argv[1][:25])' "$MSG")"
fresh; : > "$D/ready"; printf '3\n' > "$D/jsonl_delay"; printf '3\n' > "$D/human_at"   # 판독 3번째 = 재전송 판정 순간
HUMAN_TEXT="$HUMAN25" TMUXC_SUBMIT_WAIT=4 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(grep -c . "$D/transcript" | tr -d ' ')" = 1 ] \
  && [ "$(cat "$D/buffer")" = "$HUMAN25" ]; } \
  && ok "ⓑ 늦은 기록 + 사람 접두 25자 → 재전송 0(Enter 1) · 사람 글자 제출 0 · 기록으로 rc=0 (${SECS}s)" \
  || bad "ⓑ rc=$RC enters=$(enters) transcript=[$(tr '\n' '|' < "$D/transcript" 2>/dev/null)] buffer=[$(cat "$D/buffer" 2>/dev/null)] out=$(outline)"

# ⓓ capture-pane 이 정상 모양 출력 + rc1 → 판독 불가 · rc≠0 · 주입 0
fresh; : > "$D/ready"; : > "$D/cap_rc1"
TMUXC_READY_MAX=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$(typed_lit)" = 0 ] && [ "$(enters)" = 0 ] && ! grep -q 'state=submitted' "$T/out"; } \
  && ok "ⓓ capture 정상 모양 + rc1 → rc=$RC · 주입 0 · Enter 0" \
  || bad "ⓓ rc=$RC lit=$(typed_lit) enters=$(enters) out=$(outline)"

# ⓗ 넣은 뒤 입력줄이 «통 신표준»(공백 위치만 다름)으로 그려짐 → 우리 글자 아님 · Enter 0 · rc≠0
#   대역: 입력줄에 글자가 이미 «통 신표준» 꼴로 남아 있게 해 두고(사람 글자 0) 우리 메시지를 넣는 대신 그 꼴을 비교시킨다.
fresh; : > "$D/ready"; boot_h="${MSG/통신 표준/통 신표준}"
printf '%s' "$SID" > "$D/env_TMUXC_CLAUDE_SESSION_ID"; printf '%s' "$MSG" > "$D/env_TMUXC_BOOT_TEXT"; printf '%s' "$boot_h" > "$D/buffer"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 4 ] && [ "$(enters)" = 0 ] && grep -q '전문이 아니다' "$T/out"; } \
  && ok "ⓗ 입력줄 «통 신표준»(공백 위치만 다름) → 우리 글자 아님 · Enter 0 · rc=$RC" \
  || bad "ⓗ rc=$RC enters=$(enters) out=$(outline)"

# ⓘ 첫 Enter 가 먹혔지만 기록이 «마지막 조회 직후»(재전송 판정 순간)에 생김 → 재전송 직전 재조회로 재전송 0 · rc0
fresh; : > "$D/ready"; : > "$D/enter_deferred"; printf '3\n' > "$D/rec_at_cap"   # 판독 3번째 = 재전송 판정의 입력줄 읽기
TMUXC_SUBMIT_WAIT=2 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ]; } \
  && ok "ⓘ 마지막 조회 직후 기록 생김 → 재전송 0(Enter 1) · rc=0" \
  || bad "ⓘ rc=$RC enters=$(enters) rec=$(rec_count) out=$(outline)"

# ⓙ 조회마다 0.04초 지연 × 많음 + WAIT=7 · Enter 전부 유실 → 벽시계 마감으로 9초 전에 rc≠0
fresh; : > "$D/ready"; printf '999\n' > "$D/enters_lost"
LOOKUP_DELAY=0.04 TMUXC_SUBMIT_WAIT=7 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q '제출 실패' "$T/out" && python3 -c "import sys; sys.exit(0 if ${SECS} < 9 else 1)"; } \
  && ok "ⓙ 조회 지연 0.04초 + WAIT=7 → ${SECS}s(<9) 에 rc=$RC · 벽시계 마감" \
  || bad "ⓙ rc=$RC secs=${SECS} out=$(outline)"

# g1 준비 6초 늦음 → 준비 확인 뒤 주입 · 기록으로 제출 확인 · 입력줄 빔
fresh; ( sleep 6; : > "$D/ready" ) & bg=$!
call_limited inject_message sess "$MSG" agent "$SID"; wait "$bg" 2>/dev/null
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(rec_count)" = 1 ] && [ ! -s "$D/buffer" ]; } \
  && ok "g1 준비 6초 늦음 → 준비 확인 뒤 제출 1(기록) · 입력줄 빔 (${SECS}s)" \
  || bad "g1 rc=$RC rec=$(rec_count) buffer=[$(cat "$D/buffer" 2>/dev/null)] out=$(outline)"

# g2 첫 Enter 유실 → 절반 시점 입력줄 = 전문 · 재조회 0 → 재전송 1회로 제출 · 글자 1회
fresh; : > "$D/ready"; printf '1\n' > "$D/enters_lost"
TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && [ "$(enters)" = 2 ] && [ "$(typed_lit)" = 1 ] && [ "$(rec_count)" = 1 ] && grep -q 'enters=2' "$T/out"; } \
  && ok "g2 첫 Enter 유실 → 재전송 1회 제출 · 글자 1회 (${SECS}s)" \
  || bad "g2 rc=$RC enters=$(enters) lit=$(typed_lit) rec=$(rec_count) out=$(outline)"

# g3 Enter 전부 유실 → 재전송 1회 뒤 rc≠0 «제출 실패» · 글자 재입력 0
fresh; : > "$D/ready"; printf '999\n' > "$D/enters_lost"
TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q '제출 실패' "$T/out" && [ "$(enters)" = 2 ] && [ "$(typed_lit)" = 1 ]; } \
  && ok "g3 Enter 전부 유실 → rc=$RC «제출 실패» · Enter 2(재전송 1) · 글자 1회" \
  || bad "g3 rc=$RC enters=$(enters) lit=$(typed_lit) out=$(outline)"

# g4 준비 빠름 → 제출 1 · 추가 대기(옛 판 sleep 0.3 대비) 0.9초 이내
fresh; : > "$D/ready"
call_limited inject_message sess "$MSG" agent "$SID"
ADD="$(python3 -c "print(round(${SECS}-0.3,2))")"
{ [ "$RC" = 0 ] && [ "$(rec_count)" = 1 ] && python3 -c "import sys; sys.exit(0 if ${ADD} <= 0.9 else 1)"; } \
  && ok "g4 준비 빠름 → 제출 1 · 추가 대기 ${ADD}s (≤0.9)" \
  || bad "g4 rc=$RC 추가대기=${ADD}s out=$(outline)"

# g5 새 claude 의 빈 입력줄 = 자리표시 «Try "…"»(실측 10-26) → 그대로 넣고 제출 1
fresh; : > "$D/ready"; : > "$D/placeholder"
call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(rec_count)" = 1 ]; } \
  && ok "g5 자리표시 «Try …» 입력줄 → 주입·제출 1 (rc=$RC)" \
  || bad "g5 rc=$RC rec=$(rec_count) out=$(outline)"

# g6 입력줄에 사람 글자 → 넣은 뒤 입력줄 ≠ 전문 → Enter 0 · rc≠0 · 사람 글자 제출 0
fresh; : > "$D/ready"; printf '%s' 'HUMAN DRAFT — 내가 쓰던 글' > "$D/buffer"
call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && grep -q 'state=input-mismatch' "$T/out" && [ "$(enters)" = 0 ] && [ ! -s "$D/transcript" ] && [ "$(rec_count)" = 0 ]; } \
  && ok "g6 사람 글자 위 → 전문 아님 · Enter 0 · rc=$RC · 사람 글자 제출 0" \
  || bad "g6 rc=$RC enters=$(enters) out=$(outline)"

# g7 agent 주입에 세션 기록 id 가 없다 → rc≠0 · 주입 0
fresh; : > "$D/ready"
call inject_message sess "$MSG" agent
{ [ "$RC" != 0 ] && grep -q 'state=no-session-id' "$T/out" && [ "$(typed_lit)" = 0 ]; } \
  && ok "g7 id 없음 → rc=$RC · 주입 0" || bad "g7 rc=$RC out=$(outline)"

# g8 TUI 가 긴 문장을 폭 40 으로 감아 그림(낱말 경계 공백 사라짐 · 이어지는 줄 들여쓰기 · 실측 꼴) → 전문 일치 · 제출 1
LONG="[byz-harness-master-claude#114→byz-t-new-claude#2] 통신 표준: ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(12줄)를 지금 Read하고 그대로 따를 것 — 전문 COMM-GUIDE.md 는 열지 않는다. 너의 세션명(me)=byz-t-new-claude#2."
fresh; : > "$D/ready"; printf '40\n' > "$D/wrap"
call_limited inject_message sess "$LONG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(rec_count)" = 1 ]; } \
  && ok "g8 긴 문장 TUI 줄 감김 → 전문 일치 · 제출 1 (rc=$RC)" || bad "g8 rc=$RC out=$(outline)"

# ---------- boot-enter(이어가기) ----------
BOOT="[byz-t-old-claude#1→byz-t-new-claude#2] 통신 표준: ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(12줄)를 지금 Read하고 그대로 따를 것 — 너의 세션명(me)=byz-t-new-claude#2."
boot_env() { printf '%s' "$SID" > "$D/env_TMUXC_CLAUDE_SESSION_ID"; printf '%s' "$BOOT" > "$D/env_TMUXC_BOOT_TEXT"; }

# ⓒ 입력줄 = 전문인데 RGB 흰색(38;2;255;255;255) → 우리 글자 → Enter 1 · 기록으로 rc0
fresh; : > "$D/ready"; boot_env; printf '%s' "$BOOT" > "$D/buffer"; printf '38;2;255;255;255' > "$D/sgr"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ]; } \
  && ok "ⓒ 입력줄 = 전문(RGB 흰색) → Enter 1 · 기록 확인 rc=0" \
  || bad "ⓒ rc=$RC enters=$(enters) rec=$(rec_count) out=$(outline)"
# ⓒ' 입력줄 = 회색 앞부분만 → 손대지 않음 · rc≠0
BOOT20="$(python3 -c 'import sys;print(sys.argv[1][:20])' "$BOOT")"
fresh; : > "$D/ready"; boot_env; printf '%s' "$BOOT20" > "$D/buffer"; printf '38;5;245' > "$D/sgr"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 4 ] && [ "$(enters)" = 0 ] && grep -q '전문이 아니다' "$T/out"; } \
  && ok "ⓒ' 입력줄 = 회색 앞부분만 → Enter 0 · rc=$RC" \
  || bad "ⓒ' rc=$RC enters=$(enters) out=$(outline)"

# ⓔ 권한 프롬프트 화면(입력 상자 없음) → rc≠0 «[HIL] 입력줄 판독 불가» · Enter 0
fresh; : > "$D/ready"; boot_env; : > "$D/no_box"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" != 0 ] && grep -q '\[HIL\] 입력줄 판독 불가' "$T/out" && [ "$(enters)" = 0 ]; } \
  && ok "ⓔ 권한 프롬프트 → rc=$RC «[HIL] 입력줄 판독 불가» · Enter 0" \
  || bad "ⓔ rc=$RC enters=$(enters) out=$(outline)"

# ⓕ 옛 기록(앞 30자 같음) + 입력줄 = 새 문장 → Enter 1 · 새 레코드가 생긴 뒤 rc0(옛 기록으로 «이미 제출» 0)
fresh; : > "$D/ready"; boot_env; seed_rec "$BOOT"; printf '%s' "$BOOT" > "$D/buffer"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && ! grep -q 'already' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 2 ]; } \
  && ok "ⓕ 옛 기록 + 새 문장 → Enter 1 · 새 레코드 뒤 rc=0 · «이미 제출» 0" \
  || bad "ⓕ rc=$RC enters=$(enters) rec=$(rec_count) out=$(outline)"
# ⓕ' 옛 기록 + 새 Enter 가 기록 안 됨 → rc≠0(옛 기록을 새 제출로 안 읽음)
fresh; : > "$D/ready"; boot_env; seed_rec "$BOOT"; printf '%s' "$BOOT" > "$D/buffer"; : > "$D/submit_void"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 1 ] && [ "$(enters)" = 1 ] && grep -q '제출 확인 실패' "$T/out"; } \
  && ok "ⓕ' 옛 기록 + 새 기록 0 → rc=1 «제출 확인 실패»" || bad "ⓕ' rc=$RC enters=$(enters) out=$(outline)"

# ⓖ 세션 env id 없음 + resume 파일 id → 그 파일로 판정 · rc0 / 둘 다 없음 → rc3
fresh; : > "$D/ready"; printf '%s' "$BOOT" > "$D/env_TMUXC_BOOT_TEXT"; printf '%s' "$BOOT" > "$D/buffer"
mkdir -p "$D/resume" "$D/seats"; printf '{"name":"sess","engine":"claude","uuid":"%s"}\n' "$SID" > "$D/resume/sess.json"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ]; } \
  && ok "ⓖ env id 없음 + resume 파일 id → 그 기록으로 판정 · rc=0" || bad "ⓖ rc=$RC enters=$(enters) out=$(outline)"
fresh; : > "$D/ready"; mkdir -p "$D/seats"; printf '{"sess":{"agent":"claude","uuid":"%s"}}\n' "$SID" > "$D/seats/seats-t.json"
printf '%s' "$BOOT" > "$D/env_TMUXC_BOOT_TEXT"; printf '%s' "$BOOT" > "$D/buffer"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 0 ] && [ "$(enters)" = 1 ]; } \
  && ok "ⓖ' env·resume 없음 + 명부 행 uuid → 그 기록으로 판정 · rc=0" || bad "ⓖ' rc=$RC out=$(outline)"
fresh; : > "$D/ready"; printf '%s' "$BOOT" > "$D/env_TMUXC_BOOT_TEXT"; printf '%s' "$BOOT" > "$D/buffer"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 3 ] && grep -q '세션 기록 못 찾음' "$T/out" && [ "$(enters)" = 0 ]; } \
  && ok "ⓖ'' env·resume·명부 모두 없음 → rc=3 · Enter 0" || bad "ⓖ'' rc=$RC enters=$(enters) out=$(outline)"

# g9 옛 기록만 있고 입력줄 = 자리표시 → «이미 제출» 로 보지 않음 · rc4 · Enter 0
fresh; : > "$D/ready"; boot_env; : > "$D/placeholder"; seed_rec "$BOOT"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 4 ] && [ "$(enters)" = 0 ]; } \
  && ok "g9 옛 기록 + 자리표시 → rc=4 · Enter 0" || bad "g9 rc=$RC enters=$(enters) out=$(outline)"

# ⓛ codex·pi(plain) 경로 = 기준 커밋(cbe218a5)과 «같은 tmux 호출» (P3 회귀 0) — 준비 2초 늦은 대역
BASE_SHA=cbe218a5
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$ROOT" ] && git -C "$ROOT" cat-file -e "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" 2>/dev/null; then
  git -C "$ROOT" show "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" > "$T/base-tmuxc"
  sed -n '/^inject_message()/,/^}/p' "$T/base-tmuxc" > "$T/shim-base.sh"
  plain_calls() { # plain_calls <shim> <결과파일> <kind 인자…>
    local shim="$1" out="$2"; shift 2
    fresh; ( sleep 2; : > "$D/ready" ) &
    ( set -uo pipefail; . "$shim"; export FAKE_AGENT_DIR="$D" FAKE_SID="$SID" PATH="$B:$PATH" TMUXC_CLAUDE_PROJECTS="$PROJ"
      inject_message sess "$MSG" "$@" ) > "$out" 2>&1
    printf 'rc=%s\n' "$?" >> "$out"
    wait $! 2>/dev/null || true
    cp "$D/log" "$out.log" 2>/dev/null || : > "$out.log"
  }
  plain_calls "$T/shim-base.sh" "$T/plain-base.txt"
  plain_calls "$SHIM" "$T/plain-new.txt" plain
  plain_calls "$SHIM" "$T/plain-new2.txt"
  { cmp -s "$T/plain-base.txt.log" "$T/plain-new.txt.log" && cmp -s "$T/plain-base.txt" "$T/plain-new.txt" \
    && cmp -s "$T/plain-base.txt.log" "$T/plain-new2.txt.log" && grep -q '^rc=0$' "$T/plain-new.txt" && ! grep -q 'capture-pane' "$T/plain-new.txt.log"; } \
    && ok "ⓛ plain·인자 없음(send·restore) → 기준 커밋 cbe218a5 과 tmux 호출·결과 바이트 같음 · 캡처 0" \
    || bad "ⓛ plain 회귀: base=[$(tr '\n' '|' < "$T/plain-base.txt.log")] new=[$(tr '\n' '|' < "$T/plain-new.txt.log")]"
else
  bad "ⓛ 기준 커밋 ${BASE_SHA} 을 못 읽어 plain 회귀를 못 잰다(root=${ROOT:-none})"
fi

# ⓝ·ⓞ cmd_open(claude) — 판독 실패면 «session created» 대신 실패 문구 + rc≠0 · tmuxc 가 --session-id 를 발급해 세션 env 에 심는다
OC="$T/open"; mkdir -p "$OC/bin" "$OC/home" "$OC/wt"
cat > "$OC/bin/tmux" <<'SH'
#!/usr/bin/env bash
echo "tmux $*" >> "$FAKE_OUT/log"
case "$1" in
  has-session) exit 1 ;;
  display-message) echo fakeorch ;;
  list-panes) echo 4242 ;;
  capture-pane) exit 1 ;;          # 판독 실패
  *) exit 0 ;;
esac
SH
chmod +x "$OC/bin/tmux"
OOUT="$(env -i PATH="$OC/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$OC/home" FAKE_OUT="$OC" TMUXC_READY_MAX=1 \
  TMUXC_CLAUDE_SESSION_ID=deadbeef-0000-4000-8000-000000000000 \
  bash "$TMUXC" open "$OC/wt" --name T925 --agent claude --model claude-sonnet-5 2>&1)"; ORC=$?
{ [ "$ORC" -ne 0 ] && printf '%s\n' "$OOUT" | grep -q '부팅 문장 제출 실패 rc=' \
  && ! printf '%s\n' "$OOUT" | grep -qx 'tmuxc session created'; } \
  && ok "ⓝ cmd_open 판독 실패 → rc=$ORC «부팅 문장 제출 실패» · «session created» 성공 문구 0" \
  || bad "ⓝ rc=$ORC out=$(printf '%s' "$OOUT" | tr '\n' ' ' | cut -c1-200)"
OSID="$(sed -n 's/.*-e TMUXC_CLAUDE_SESSION_ID=\([0-9a-f-]*\).*/\1/p' "$OC/log" | head -1)"
{ [ -n "$OSID" ] && [ "$OSID" != deadbeef-0000-4000-8000-000000000000 ] \
  && grep -q "send-keys -t T925 -l .*--session-id $OSID" "$OC/log" \
  && grep -q '^tmux set-environment -t =T925 TMUXC_BOOT_TEXT \[fakeorch→T925\] 통신 표준' "$OC/log"; } \
  && ok "ⓞ cmd_open claude → --session-id 발급($OSID) = 세션 env 같은 값 · 호출자 env 값 안 씀 · TMUXC_BOOT_TEXT 기록" \
  || bad "ⓞ sid=[$OSID] log=$(grep -E 'new-session|session-id|set-environment' "$OC/log" | tr '\n' '|' | cut -c1-400)"
CDRY="$(env -i PATH="$OC/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$OC/home" FAKE_OUT="$OC" bash "$TMUXC" open "$OC/wt" --name T925C --agent codex --dry-run 2>&1)"
{ ! printf '%s\n' "$CDRY" | grep -q 'session-id\|TMUXC_CLAUDE'; } \
  && ok "ⓞ' codex open → --session-id·TMUXC_CLAUDE 0(P3)" || bad "ⓞ' codex dry-run: $(printf '%s' "$CDRY" | tr '\n' ' ' | cut -c1-200)"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
