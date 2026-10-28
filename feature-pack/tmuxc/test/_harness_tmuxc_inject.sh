#!/usr/bin/env bash
# _harness_tmuxc_inject.sh — r925 로컬 주입 시험의 «공용 대역»(r1075 · arch#173 반송 r3 로 쪼갠 결과).
#   이 파일은 시험이 아니다: 가짜 tmux·함수 추출(shim)·변이(FT_MUTATE)·call_limited·BOOT 정의만 있다.
#   쓰는 곳 = test_tmuxc_inject_ready_submit.sh(주입 경로) · test_tmuxc_inject_ready_submit_boot.sh(boot-enter 경로).
#   쪼갠 이유: 한 파일이 부하 49 에 70초를 넘었다(하드 룰 22 · arch#173 실측 rc124). 칸을 둘로 나눠 각 70초 안에 든다.
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
#     ⓙ2/ⓙ3 (r5 계약) WAIT=1 · 조회 1.4초 — 기록 1.2초 = 마감 뒤에 찾아도 rc0 / 기록 3초 = rc≠0 · 둘 다 Enter 1
#     ⓙ4 (r6 결과 계약) WAIT=1 · 조회 0.85초 · 기록 1.1초 → rc0 · Enter 1 · 총 < WAIT + 조회 + 0.2 + 0.5초
#     ⓙ5 (r7 계약 ①) 첫 Enter 먹힘·화면·기록 그대로 · 조회 0.6초 → 재전송 판정이 마감 뒤 → Enter 1 · rc≠0
#     ⓙ6/ⓙ6b (r8) 첫 Enter 처리만 3초 · WAIT=1 → 마감 기준 = Enter 앞 · 기록 0 → Enter 1 rc≠0 / 기록 생김 → rc0
#   시험 상한 숫자는 구현에 맞춘 값이라 계약 상한보다 빡빡하다 = 의도 · SECS 는 호출 전부터 잰다(계약은 첫 Enter 부터).
#   이어 온 시험: g1 준비 6초 늦음 · g2 첫 Enter 유실 → 재전송 1 · g3 Enter 전부 유실 → 실패 · g4 준비 빠름 ·
#     g5 새 claude 자리표시 «Try "…"» → 주입·제출 · g6 사람 글자 위 → Enter 0 · g7 id 없는 agent 주입 → rc≠0 ·
#     g8 TUI 가 긴 문장을 여러 줄로 감음(실측 꼴) → 전문 일치 · 제출 · g9 boot-enter 옛 기록만 + 자리표시 → rc4 ·
#     ⓛ codex·pi(plain) = 기준 커밋 cbe218a5 와 tmux 호출 바이트 같음 · ⓝ cmd_open 주입 실패 문구 · ⓞ open 이 id 를 발급·심음
#   픽스처 = 가짜 tmux(상태 폴더 파일) + 가짜 기록 폴더(<id>.jsonl) — 실 tmux 서버·실 에이전트·홈 쓰기 0.
#   시험 대상 = env FT_TMUXC_PATH (기본 = 이 저장소 사본) — 옛 사본으로 돌리면 빨강이어야 한다.
#   변이(FT_MUTATE): J = 기록 판정 → 화면 판정 복귀 · P = 재전송 판정에 접두 인정 복귀 · C = capture rc 무시 ·
#                    E = boot-enter 판독 불가 rc0 복귀 · D = 재전송 직전 마감 검사 삭제(→ ⓙ5 빨강)
#                    F = r8 고침 1 되돌림(inject 마감 기준점을 첫 Enter 뒤로 → ⓙ6 inject 빨강 · 결정문의 «변이 E» · E 는 이미 있어 F)
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
    if [ -f "$D/enter_slow" ]; then dl="$(cat "$D/enter_slow")"; rm -f "$D/enter_slow"; sleep "$dl"; fi   # 첫 Enter 처리만 N초
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
# ★r1075★ 판독 함수는 이제 core/libexec/agent-inject.sh 에 있다(로컬 tmuxc 는 source 해서 쓴다).
#   shim 도 «tmuxc 와 같은 해석 순서» 로 그 파일을 먼저 읽는다 — 안 읽으면 «고치기 전 사본» 으로 빠져
#   이 시험이 한 칸도 안 돌면서 초록으로 보인다(arch#173 격리 실측 2026-10-28).
INJ_LIB="${TMUXC_AGENT_INJECT_LIB:-$(cd -- "$(dirname -- "$TMUXC")/../libexec" 2>/dev/null && pwd)/agent-inject.sh}"
: > "$SHIM"
for f in $FUNCS; do
  for src in "$INJ_LIB" "$TMUXC"; do
    [ -f "$src" ] || continue
    grep -q "^${f}()" "$SHIM" && continue
    sed -n "/^${f}()/,/^}/p" "$src" >> "$SHIM"
  done
done
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
  D) # 재전송 직전 마감 검사 삭제(마감 뒤에도 두 번째 Enter)
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '''          now="$(now_ms)"
          if (( now < t_end )); then tmux send-keys -t "$pane" Enter; enters=2; fi ;;'''
new = '''          tmux send-keys -t "$pane" Enter; enters=2 ;;  # MUTATE D'''
assert old in s, "MUTATE D 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  F) # r8 고침 1 되돌림 — inject 마감 기준점을 첫 Enter 호출 «뒤» 로
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
nl = '''  now="$(now_ms)"; t_end=$(( now + wait_s * 1000 )); t_mid=$(( now + wait_s * 500 ))\n'''
en = '''  tmux send-keys -t "$pane" Enter; enters=1\n'''
assert (nl + en) in s, "MUTATE F 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(nl + en, en + nl.rstrip("\n") + "  # MUTATE F\n", 1))
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

BOOT="[byz-t-old-claude#1→byz-t-new-claude#2] 통신 표준: ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(12줄)를 지금 Read하고 그대로 따를 것 — 너의 세션명(me)=byz-t-new-claude#2."
boot_env() { printf '%s' "$SID" > "$D/env_TMUXC_CLAUDE_SESSION_ID"; printf '%s' "$BOOT" > "$D/env_TMUXC_BOOT_TEXT"; }

