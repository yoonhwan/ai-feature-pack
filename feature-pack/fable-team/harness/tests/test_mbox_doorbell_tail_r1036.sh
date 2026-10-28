#!/usr/bin/env bash
# test_mbox_doorbell_tail_r1036.sh — r1036: 발주 알림줄(doorbell) 꼬리는 FT_DOORBELL_TAIL=ultrathink 일 때만 ` ultrathink` 한 낱말
#  ⓐ 환경변수 없음 → 알림줄이 기준(origin/main)과 바이트 동일 — 머리 `[발주 #N]`·`[발주 도착]` 두 갈래 (R1)
#  ⓑ =ultrathink → 줄 끝에 공백+낱말 · 머리 첫 토큰 불변 (R2 · ring 재발주도 같은 함수 → R5)
#  ⓒ allowlist 밖(다른 낱말·`ultrathink;x`·`$(…)`·앞뒤 빈칸) → WARN 1줄 + 붙이지 않음(ⓐ 와 동일) (R3)
#  ⓓ 빈 문자열 → 붙이지 않음 · WARN 0 (R4)
#  ⓔ 두 사본(키트 bin · 스킬 scripts) cmp 동일
#  ⓕ 변이 ①`${_tail}` 제거 → ⓑ FAIL ②allowlist 검사 제거 → ⓒ FAIL
# 시험 방식: tmux 스텁이 받은 send-keys 문자열만 본다 — 실제 tmux 입력 0 · 좌석 열기 0 · 홈 파일 쓰기 0 ·
#   임시 FT_ROOT(스크립트 사본) + 임시 FT_MBOX_DIR + TMPDIR 임시(스탬프 격리) + 가짜 pgrep. 큐 쓰기 0(`ring` 경로만 쓴다).
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
KIT="$REPO/harness/kit/fable-team/bin"
SKILL="$REPO/skill/scripts"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (기대 '$3' 실제 '$2')"; }

# ── 스텁: tmux(성공 응답 + send-keys 문자열 기록) · pgrep(자식 있음)
mkdir -p "$T/fakebin" "$T/tmp"
cat > "$T/fakebin/tmux" <<'EOS'
#!/bin/bash
case "$1" in
  has-session) exit 0 ;;
  list-panes)
    case "$*" in
      *'#{session_name}'*) echo "seatX|%9" ;;
      *) echo "${FAKE_PANE_PID:-1}" ;;
    esac
    exit 0 ;;
  capture-pane) exit 0 ;;
  send-keys) printf '%s\n' "${5:-}" >> "$FAKE_TMUX_LOG"; exit 0 ;;
esac
exit 0
EOS
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/pgrep"
chmod +x "$T/fakebin/tmux" "$T/fakebin/pgrep"

mkroot() {  # <이름> → $T/<이름>/.fable-team/{bin,comm} 에 스크립트 사본
  local R="$T/$1"
  mkdir -p "$R/.fable-team/bin" "$R/.fable-team/comm"
  cp "$KIT"/ft-mbox.sh "$KIT"/ft-mbox.py "$KIT"/ft-lib.sh "$KIT"/ft-inbox.sh "$KIT"/ft-inbox.py "$KIT"/ft_inbox_core.py "$R/.fable-team/bin/"
  echo "$R"
}
ROOT="$(mkroot main)"; BIN="$ROOT/.fable-team/bin"; C="$ROOT/.fable-team/comm"

export PATH="$T/fakebin:$PATH" FT_MBOX_DIR="$C" TMPDIR="$T/tmp" FAKE_PANE_PID=$$
unset FT_DOORBELL_TAIL FT_DOORBELL_TAIL_ORIG 2>/dev/null
ENVTOK="FT_MBOX_DIR=$C "   # r403: 정본 우편함 1토큰이 명령 앞에 실린다(꼬리 변경과 무관 · 기준값의 일부)
HEAD_SEQ="[발주 #7]"
HEAD_NOSEQ="[발주 도착]"
REST="bash $BIN/ft-mbox.sh recv seatX — 실행하고 그 안의 지시를 즉시 착수하라"
BASE_SEQ="${HEAD_SEQ} ${ENVTOK}${REST}"
BASE_NOSEQ="${HEAD_NOSEQ} ${ENVTOK}${REST}"

bell_rc=0
bell() {  # <seq|-> [env 값…] → stdout=주입된 알림줄 · stderr=$T/err · 마지막 rc 는 bell_rc
  local seq="$1"; shift
  : > "$T/log"; : > "$T/err"; rm -f "$T"/tmp/mbox-doorbell-* "$T"/tmp/mbox-recv-*
  local -a ev=(); local kv
  for kv in "$@"; do ev+=("$kv"); done
  local out
  if [ "$seq" = "-" ]; then
    out="$(env "${ev[@]}" FAKE_TMUX_LOG="$T/log" bash "$BIN/ft-mbox.sh" ring seatX 2>"$T/err")"
  else
    out="$(env "${ev[@]}" FAKE_TMUX_LOG="$T/log" bash "$BIN/ft-mbox.sh" ring seatX "$seq" 2>"$T/err")"
  fi
  bell_rc=$?
  bell_out="$out"
  sed -n '1p' "$T/log"
}
warns() { grep -c 'WARN doorbell 꼬리 allowlist 밖' "$T/err" 2>/dev/null || true; }

# ⓐ R1: 환경변수 없음 = 기준과 바이트 동일 (두 갈래)
eq "ⓐ seq 갈래 — 환경변수 없음 = 기준 동일" "$(bell 7)" "$BASE_SEQ"
eq "ⓐ rc 0" "$bell_rc" 0
eq "ⓐ seq 없음 갈래 = 기준 동일" "$(bell -)" "$BASE_NOSEQ"
eq "ⓐ WARN 0" "$(warns)" 0

# ⓑ R2·R5: =ultrathink → 꼬리 붙음 · 머리 첫 토큰 불변
got="$(bell 7 FT_DOORBELL_TAIL=ultrathink)"
eq "ⓑ 꼬리 붙음" "$got" "${BASE_SEQ} ultrathink"
case "$got" in "$HEAD_SEQ"*) ok "ⓑ 머리 첫 토큰 불변" ;; *) bad "ⓑ 머리 첫 토큰 불변 (실제 '${got:0:20}')" ;; esac
eq "ⓑ seq 없음 갈래도 꼬리" "$(bell - FT_DOORBELL_TAIL=ultrathink)" "${BASE_NOSEQ} ultrathink"
eq "ⓑ WARN 0" "$(warns)" 0

# ⓒ R3: allowlist 밖 → WARN 1줄 + 붙이지 않음(ⓐ 동일)
for v in 'UltraThink' 'ultrathink;x' '$(id)' ' ultrathink' 'ultrathink x' 'ultra'; do
  got="$(bell 7 "FT_DOORBELL_TAIL=$v")"
  eq "ⓒ '$v' → 붙이지 않음" "$got" "$BASE_SEQ"
  eq "ⓒ '$v' → WARN 1줄" "$(warns)" 1
done

# ⓓ R4: 빈 문자열 → 붙이지 않음 · WARN 0
eq "ⓓ 빈 값 → 기준 동일" "$(bell 7 FT_DOORBELL_TAIL=)" "$BASE_SEQ"
eq "ⓓ 빈 값 → WARN 0" "$(warns)" 0

# ⓔ 두 사본 cmp 동일
cmp -s "$KIT/ft-mbox.sh" "$SKILL/ft-mbox.sh" && ok "ⓔ 두 사본 cmp 동일" || bad "ⓔ 두 사본이 다르다"

# ⓕ 변이 — 사본을 망가뜨려 ⓑ·ⓒ 가 «잡히는지» 본다(정본 파일은 안 건드린다)
mut() {  # <이름> <sed 식…> → 변이 사본 루트
  local name="$1"; shift
  local R e; R="$(mkroot "mut-$name")"
  for e in "$@"; do
    sed -i '' "$e" "$R/.fable-team/bin/ft-mbox.sh" 2>/dev/null || sed -i "$e" "$R/.fable-team/bin/ft-mbox.sh"
  done
  echo "$R"
}
R1="$(mut notail 's/착수하라${_tail}/착수하라/g')"
if cmp -s "$R1/.fable-team/bin/ft-mbox.sh" "$BIN/ft-mbox.sh"; then bad "ⓕ 변이① 적용 실패(sed 무변경)"; else
  out="$( : > "$T/log"; rm -f "$T"/tmp/mbox-doorbell-*; FAKE_TMUX_LOG="$T/log" FT_DOORBELL_TAIL=ultrathink bash "$R1/.fable-team/bin/ft-mbox.sh" ring seatX 7 >/dev/null 2>&1; sed -n '1p' "$T/log")"
  case "$out" in *ultrathink) bad "ⓕ 변이① (꼬리 제거) 인데 꼬리가 붙음" ;; *) ok "ⓕ 변이① 꼬리 제거 → ⓑ FAIL" ;; esac
fi
R2M="$(mut noallow 's|if \[ "\$FT_DOORBELL_TAIL" = "ultrathink" \]; then|if true; then|' 's|_tail=" ultrathink"|_tail=" $FT_DOORBELL_TAIL"|')"
if cmp -s "$R2M/.fable-team/bin/ft-mbox.sh" "$BIN/ft-mbox.sh"; then bad "ⓕ 변이② 적용 실패(sed 무변경)"; else
  out="$( : > "$T/log"; : > "$T/err2"; rm -f "$T"/tmp/mbox-doorbell-*; FAKE_TMUX_LOG="$T/log" FT_DOORBELL_TAIL='ultrathink;x' bash "$R2M/.fable-team/bin/ft-mbox.sh" ring seatX 7 >/dev/null 2>"$T/err2"; sed -n '1p' "$T/log")"
  case "$out" in *'ultrathink;x') ok "ⓕ 변이② allowlist 검사 제거 → ⓒ FAIL(밖 값이 붙음)" ;; *) bad "ⓕ 변이② allowlist 제거했는데 안 붙음(실제 '$out')" ;; esac
  # 변이② 가 정말 적용됐는지 확인(사본에 if true 가 있어야 변이 유효)
  grep -q 'if true; then' "$R2M/.fable-team/bin/ft-mbox.sh" || bad "ⓕ 변이② 사본에 if true 미적용"
fi

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (r1036 doorbell tail)"; exit 0; }
echo "FAILED $fail"; exit 1
