#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit_boot.sh — r925 이어가기(boot-enter) 경로 — 대역은 …_lib.sh(쪼갠 2/2 · r1075).
#   칸: ⓗ 공백 위치만 다른 입력줄 · ⓒ/ⓒ' 흰색=전문·회색 앞부분 · ⓔ 권한 프롬프트 · ⓕ/ⓕ' 옛 기록 ·
#       ⓖ/ⓖ'/ⓖ'' id 해석 순서 · g9 옛 기록+자리표시 · ⓛ plain 경로 기준 커밋 대조 · ⓝ/ⓞ/ⓞ' cmd_open
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_harness_tmuxc_inject.sh"

# ⓗ 넣은 뒤 입력줄이 «통 신표준»(공백 위치만 다름)으로 그려짐 → 우리 글자 아님 · Enter 0 · rc≠0
#   대역: 입력줄에 글자가 이미 «통 신표준» 꼴로 남아 있게 해 두고(사람 글자 0) 우리 메시지를 넣는 대신 그 꼴을 비교시킨다.
fresh; : > "$D/ready"; boot_h="${MSG/통신 표준/통 신표준}"
printf '%s' "$SID" > "$D/env_TMUXC_CLAUDE_SESSION_ID"; printf '%s' "$MSG" > "$D/env_TMUXC_BOOT_TEXT"; printf '%s' "$boot_h" > "$D/buffer"
TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
{ [ "$RC" = 4 ] && [ "$(enters)" = 0 ] && grep -q '전문이 아니다' "$T/out"; } \
  && ok "ⓗ 입력줄 «통 신표준»(공백 위치만 다름) → 우리 글자 아님 · Enter 0 · rc=$RC" \
  || bad "ⓗ rc=$RC enters=$(enters) out=$(outline)"

# ---------- boot-enter(이어가기) ----------  (BOOT · boot_env 는 ⓙ2 앞에 둔다)

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
