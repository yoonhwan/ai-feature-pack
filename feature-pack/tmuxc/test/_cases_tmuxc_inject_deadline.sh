#!/usr/bin/env bash
# _cases_tmuxc_inject_deadline.sh — r925 r5~r8 «마감·재전송 경계» 칸 묶음(ⓙ2 ~ ⓙ6b).
#   시험 파일이 아니다: lib 를 source 한 뒤 이 파일을 source 하면 $FT_WHOS(inject·boot) 로 그 경로만 돈다.
#   r1075 에서 부하 43 에 주입 시험이 79초를 넘어(하드 룰 22 위반) «경계 칸» 을 따로 떼어 두 파일이 나눠 쓴다.
# ⓙ2 (r5 계약) WAIT=1 · 기록 1.2초 늦게 · 조회 1.4초 → 마감 전에 시작한 조회가 찾은 새 레코드 = rc0 · Enter 1 · < 1+1.4+0.5초
for who in $FT_WHOS; do
  fresh; : > "$D/ready"; printf '1.2\n' > "$D/jsonl_delay"
  if [ "$who" = inject ]; then
    LOOKUP_DELAY=1.4 TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
  else
    boot_env; printf '%s' "$BOOT" > "$D/buffer"
    LOOKUP_DELAY=1.4 TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
  fi
  { [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ] \
      && python3 -c "import sys; sys.exit(0 if ${SECS} < 2.9 else 1)"; } \
    && ok "ⓙ2 $who 조회 1.4초가 마감(1초)을 넘겨 찾은 새 기록 → rc=0 · Enter 1 · ${SECS}s(<2.9)" \
    || bad "ⓙ2 $who rc=$RC enters=$(enters) rec=$(rec_count) secs=${SECS} out=$(outline)"
done

# ⓙ3 (r5 계약) 같은 지연 · 기록 3초 늦게(마감 + 조회 1회 뒤) → rc≠0 · Enter 1(재전송 0 · 마감 뒤 Enter 0) · 기록은 그 뒤에 실제로 생김
for who in $FT_WHOS; do
  fresh; : > "$D/ready"; printf '3\n' > "$D/jsonl_delay"
  if [ "$who" = inject ]; then
    LOOKUP_DELAY=1.4 TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
  else
    boot_env; printf '%s' "$BOOT" > "$D/buffer"
    LOOKUP_DELAY=1.4 TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
  fi
  R3RC=$RC; R3OUT="$(outline)"; R3SECS=$SECS; R3EN="$(enters)"; R3REC="$(rec_count)"
  sleep 2   # 늦은 기록이 다음 칸으로 새지 않게 기다린 뒤, 정말 생겼는지 본다
  { [ "$R3RC" != 0 ] && [ "$R3RC" != 124 ] && [ "$R3EN" = 1 ] && [ "$(enters)" = 1 ] && [ "$R3REC" = 0 ] && [ "$(rec_count)" = 1 ] \
      && grep -q '제출.*실패' "$T/out" && python3 -c "import sys; sys.exit(0 if ${R3SECS} < 3.1 else 1)"; } \
    && ok "ⓙ3 $who 기록이 마감+조회 뒤(3초) → rc=$R3RC · Enter 1 · ${R3SECS}s(<1+1.4+0.2+0.5) · 기록은 그 뒤 생김" \
    || bad "ⓙ3 ${who} rc=${R3RC} enters=${R3EN}→$(enters) rec=${R3REC}→$(rec_count) secs=${R3SECS} out=${R3OUT}"
done

# ⓙ4 (r6 결과 계약 · astra r5 반례 꼴) WAIT=1 · 조회 0.85초 · 기록 1.1초 늦게 → 쉼 뒤 마감을 넘겨 시작한 조회가 찾음
#   → inject·boot 둘 다 rc0 · Enter 1 · 새 기록 1 · < 1+0.85+0.2+0.5초 (조회를 언제 시작했는지는 계약 아님)
for who in $FT_WHOS; do
  fresh; : > "$D/ready"; printf '1.1\n' > "$D/jsonl_delay"
  if [ "$who" = inject ]; then
    LOOKUP_DELAY=0.85 TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
  else
    boot_env; printf '%s' "$BOOT" > "$D/buffer"
    LOOKUP_DELAY=0.85 TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
  fi
  { [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ] \
      && python3 -c "import sys; sys.exit(0 if ${SECS} < 2.55 else 1)"; } \
    && ok "ⓙ4 ${who} 조회 0.85초 · 기록 1.1초 → rc=0 · Enter 1 · 새 기록 1 · ${SECS}s(<2.55)" \
    || bad "ⓙ4 ${who} rc=${RC} enters=$(enters) rec=$(rec_count) secs=${SECS} out=$(outline)"
done

# ⓙ5 (r7 계약 ①) 첫 Enter 를 먹고 입력줄·기록 그대로 · 조회 0.6초 · WAIT=1 → 재전송 판정이 마감 뒤에 끝남
#   → 마감 뒤 Enter 0: rc≠0 «제출 실패» · Enter 1 · 기록 0 · < 1+3×0.6+1 = 3.8초 (inject 만 · boot-enter 는 재전송 없음)
fresh; : > "$D/ready"; : > "$D/enter_deferred"
LOOKUP_DELAY=0.6 TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q '제출 실패' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 0 ] \
    && python3 -c "import sys; sys.exit(0 if ${SECS} < 3.8 else 1)"; } \
  && ok "ⓙ5 재전송 판정이 마감 뒤 → 두 번째 Enter 0 · rc=${RC} «제출 실패» · Enter 1 · 기록 0 · ${SECS}s(<3.8)" \
  || bad "ⓙ5 rc=${RC} enters=$(enters) rec=$(rec_count) secs=${SECS} out=$(outline)"

# ⓙ6 (r8 · sol r7 반례) 첫 Enter 처리만 3초 · WAIT=1 · 첫 Enter 뒤 기록 0(enter_deferred) → 마감은 Enter «앞» 시각 기준
#   → inject 두 번째 Enter 0 · rc≠0 «제출 실패» / boot rc≠0 · 둘 다 < 1 + 3×3 + 1 + 0.5 = 11.5초
for who in $FT_WHOS; do
  fresh; : > "$D/ready"; : > "$D/enter_deferred"; printf '3\n' > "$D/enter_slow"
  if [ "$who" = inject ]; then
    TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
  else
    boot_env; printf '%s' "$BOOT" > "$D/buffer"
    TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
  fi
  { [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q '제출.*실패' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 0 ] \
      && python3 -c "import sys; sys.exit(0 if ${SECS} < 11.5 else 1)"; } \
    && ok "ⓙ6 ${who} 첫 Enter 3초 · 기록 0 → 마감 뒤 Enter 0 · rc=${RC} · Enter 1 · ${SECS}s(<11.5)" \
    || bad "ⓙ6 ${who} rc=${RC} enters=$(enters) rec=$(rec_count) secs=${SECS} out=$(outline)"
done

# ⓙ6b 같은 3초 · 첫 Enter 가 기록됨 → rc0 · Enter 1
for who in $FT_WHOS; do
  fresh; : > "$D/ready"; printf '3\n' > "$D/enter_slow"
  if [ "$who" = inject ]; then
    TMUXC_SUBMIT_WAIT=1 call_limited inject_message sess "$MSG" agent "$SID"
  else
    boot_env; printf '%s' "$BOOT" > "$D/buffer"
    TMUXC_SUBMIT_WAIT=1 call_limited cmd_boot_enter sess
  fi
  { [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ] \
      && python3 -c "import sys; sys.exit(0 if ${SECS} < 11.5 else 1)"; } \
    && ok "ⓙ6b ${who} 첫 Enter 3초 · 기록 생김 → rc=0 · Enter 1 · ${SECS}s(<11.5)" \
    || bad "ⓙ6b ${who} rc=${RC} enters=$(enters) rec=$(rec_count) secs=${SECS} out=$(outline)"
done
