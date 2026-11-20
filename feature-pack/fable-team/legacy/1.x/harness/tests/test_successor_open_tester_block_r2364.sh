#!/usr/bin/env bash
# test_successor_open_tester_block_r2364.sh — tester 승계 본문 첫머리에 §17 tester 블록(S17-TESTER)이 실린다 (r2364 · Issue #10315 · 골좌표 6).
# 실사건: room-tester-33 pi 세션 7개(byz-room-tester-pi#47~#53)가 press 1~3건마다 280k 문턱 승계 · 창 몫 = 폴링(sleep·tail·capture) 28~43% · sleep 부름 23~142회.
#   지금 tester [개설] 첫머리 = 팀장 루프 블록(S17-BOOT) 3줄 — 기다림·press 꼴 줄 0 이라 매 좌석이 sleep 폴링과 긴 명령 되풀이를 다시 만든다.
#   ⓐ 이름 «-tester-» → 보낸 본문 첫머리 = K1 tester 블록 3줄 · «목적 0 = 진행 카드»(S17-BOOT) 줄 0
#   ⓑ S17-TESTER 표식 0·2개·블록 301자 = REJECT rc1 · 송신 0        ⓒ desk = S11-DESK 그대로 · arch = S17-BOOT 그대로
#   ⓓ 실 governance(팩 판) 블록 = K1 코드 블록 3줄 글자 그대로 · 300자 안  ⓔ 본문 4행~ 의 앞 블록 3줄 = 보낸 본문에 1번만(중복 0)
# 변이(사본에서만 · 변이마다 원본으로 같은 사례 1회 더): M1 tester 갈래 지움 → ⓐ FAIL · M2 tester 갈래만 표식 개수 검사 건너뜀 → ⓑ(2개) FAIL
#   M3 300자 검사 지움 → ⓑ(301자) FAIL · M4 «*-desk-*|*-tester-*» 합침 → ⓐ FAIL(desk 블록이 실림) · M5 governance 줄 2 지움 → ⓓ FAIL · M6 sed tester 머리 3개 되돌림 → ⓔ FAIL(블록 2번)
# 격리: lib/r1660_successor_env.sh 대역(가짜 tmux·tmuxc·pgrep·ps·send·mbox·reach·retire + 격리 시계) · FT_GOV_MD 주입(임시 governance 사본) · 실 tmux·실 좌석·실 우편함 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/r1660_successor_env.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:400}"; fail=$((fail+1)); }
SO="$SO0"; SET0="$(date +%s)"; T0=$SET0
GOV_REAL="$HERE/../../skill/references/main-team-governance.md"
KIT="$HERE/../kit/fable-team/bin/ft-successor-open.sh"
secs() { echo "$1 $(( $(date +%s) - T0 ))초"; }
# K1 동결 글 — 카드 코드 블록 3줄(266자) · 이 시험은 governance 를 읽지 않고 이 글자와 대조한다
EXPECT="$(cat <<'EOF'
tester 목적 0 = 맡은 press 완성·보고 → 1 = 다음 발주.
기다림 = sleep 폴링 0 · 긴 단계는 작업 폴더 스크립트가 timeout 상한 안에서 돌고 성공·실패 모두 끝에 요약 파일 + mbox.sh ring <me> 1회(trap EXIT) · 깨우면 요약 파일 읽기.
press 단계 = 작업 폴더 스크립트 1개 실행(긴 명령 되풀이 0) · 결과 = 요약 파일 1개 읽기(로그 통째 0) · cron=0 · 받을 일 0 = «[다음 없음]» 1줄.
EOF
)"
[ "$(python3 -c 'import sys; print(len(sys.argv[1]))' "$EXPECT")" = 266 ] || bad "K1 대조 글 길이" "266자 아님 — $(python3 -c 'import sys; print(len(sys.argv[1]))' "$EXPECT")"
# 보낸 본문 기록 대역 — send 스텁이 본문($2)을 파일로 남긴다(r1660 대역의 send 를 갈아 끼운다)
SENTB="$TMP/sentbody.txt"
cat > "$TMP/sendbody" <<EOF
#!/usr/bin/env bash
echo send >> "\$LOG"
printf '%s\n' "\$2" > "$SENTB"
echo "QUEUED seq=777 to=\$1"
exit 0
EOF
chmod +x "$TMP/sendbody"; export FT_SEND_VERIFIED_OVERRIDE="$TMP/sendbody"
sent() { cat "$SENTB" 2>/dev/null; }
sline() { sent | sed -n "$1p"; }
head_block() { sent | awk 'NR>=4 { if ($0 ~ /^좌석 기억\(1회 로드\)=/) exit; print }'; }   # 골 3줄 다음 = 첫 지침 블록(줄 수 무관)
scount() { sent | grep -c "^$1" || true; }
sends() { grep -c '^send' "$LOG" 2>/dev/null || true; }
reset_out() { rm -f "$SENTB"; : > "$LOG"; }
block_of() {   # block_of <gov> <BEGIN표식> <END표식> — 표식 사이 글(앞뒤 빈 줄 걷음) · 표식이 1개가 아니면 rc1
  python3 - "$1" "$2" "$3" <<'PY'
import sys
p, b, e = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
if t.count(b) != 1 or t.count(e) != 1: sys.exit(1)
print(t.split(b, 1)[1].split(e, 1)[0].strip("\n"))
PY
}
T_BEG='<!-- S17-TESTER-BEGIN -->'; T_END='<!-- S17-TESTER-END -->'
D_BEG='<!-- S11-DESK-BEGIN -->'; D_END='<!-- S11-DESK-END -->'
B_BEG='<!-- S17-BOOT-BEGIN -->'; B_END='<!-- S17-BOOT-END -->'
NOW="$(date +%s)"; echo "준비 $(( NOW - SET0 ))초 — 대역·대조 글"
# ── ① tester 승계 = tester 블록 (기준판 Red: 지금은 S17-BOOT 가 실린다)
OLD="byz-room-tester-pi#54"; NEW="byz-room-tester-pi#55"
set_body() { printf '%s\n' "$@" > "$BODY"; }
PLAIN=('골 원문 1줄' '골 원문 2줄' '골 원문 3줄' '본문 나머지' '열린 칸 감시: 없음')
set_body "${PLAIN[@]}"; world pi; reset_out; run pi
NOW="$(date +%s)"
{ [ "$RC" = 0 ] && [ "$(head_block)" = "$EXPECT" ] && ! sent | grep -q '목적 0 = 진행 카드'; } \
  && ok "$(secs "① tester 이름 → 보낸 본문 첫머리 = K1 3줄 · S17-BOOT 줄 0 rc=$RC")" || bad "① rc=$RC" "$(sed -n '1,8p' <<<"$(sent)")"
# ── ②③④ 표식 없음·여럿·301자 = REJECT rc1 · 송신 0
mk_gov() { python3 - "$GOV_REAL" "$1" "$2" <<'PY'
import sys
src, dst, mode = sys.argv[1:4]
t = open(src, encoding="utf-8").read()
b, e = "<!-- S17-TESTER-BEGIN -->", "<!-- S17-TESTER-END -->"
if mode == "none":       # 표식 0 — 표식 두 줄만 지운다(블록 글은 남는다)
    t = t.replace(b + "\n", "", 1).replace(e + "\n", "", 1)
elif mode == "two":      # 표식 2개 — 같은 블록을 한 벌 더 붙인다
    blk = t.split(b, 1)[1].split(e, 1)[0]
    t = t.replace(e + "\n", e + "\n" + b + blk + e + "\n", 1)
elif mode == "long":     # 블록 301자
    blk = t.split(b, 1)[1].split(e, 1)[0]
    t = t.replace(blk, "\n" + "a" * 301 + "\n", 1)
else:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(t)
PY
}
for pair in "none:②:표식 0" "two:③:표식 2개" "long:④:블록 301자"; do
  mode="${pair%%:*}"; rest="${pair#*:}"; tag="${rest%%:*}"; why="${rest#*:}"
  mk_gov "$TMP/gov-$mode.md" "$mode" || { bad "$tag governance 사본 만들기" "$mode"; continue; }
  world pi; reset_out; run pi FT_GOV_MD="$TMP/gov-$mode.md"
  { [ "$RC" = 1 ] && [ "$(sends)" = 0 ] && [ ! -f "$SENTB" ] && grep -q 'REJECT 승계 블록' "$TMP/out"; } \
    && ok "$(secs "$tag $why → REJECT rc1 · 송신 0")" || bad "$tag rc=$RC send=$(sends)" "$(SOUTC)"
done
# ── ⑤ 다른 역할 그대로 — desk = S11-DESK · arch = S17-BOOT
DESK_BLK="$(block_of "$GOV_REAL" "$D_BEG" "$D_END")"; BOOT_BLK="$(block_of "$GOV_REAL" "$B_BEG" "$B_END")"
# desk 게이트(안내서 원문 구절·묻는 기준)를 통과시키는 최소 안내서 — 임시 리포에 넣고 FT_GUIDE_REF=HEAD 로 읽게 한다
mkdir -p "$REPO/design/t/planner"
printf '%s\n' '- **desk 좌석** desk 는 인터뷰·응대·요청 정리만 하고 master 에 1통)' \
  '- **desk 묻는 기준** 오빠 답이 필요한 것만 묻는다' > "$REPO/design/t/planner/GUIDE-planner.md"
git -C "$REPO" add -A >/dev/null 2>&1 && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m guide >/dev/null 2>&1
printf '%s\n' "$REPO" > "$REPO/.fable-team/LIVE_ROOT"   # r756 데이터 루트 갈래 검사 = 워크트리·공용 루트 같은 값
DESK_BODY=('골 원문 1줄' '골 원문 2줄' '골 원문 3줄' '- **desk 좌석** desk 는 인터뷰·응대·요청 정리만 하고 master 에 1통)' '- **desk 묻는 기준** 오빠 답이 필요한 것만 묻는다' '본문 나머지' '열린 칸 감시: 없음')
OLD="byz-room-desk-pi#2"; NEW="byz-room-desk-pi#3"
set_body "${DESK_BODY[@]}"; world pi; reset_out
run pi FT_GUIDE_REF=HEAD FT_GUIDE_PATH=design/t/planner/GUIDE-planner.md FT_SO_MAIN_REF=HEAD
NOW="$(date +%s)"
{ [ "$RC" = 0 ] && [ "$(head_block)" = "$DESK_BLK" ] && ! sent | grep -q 'tester 목적 0 ='; } \
  && ok "$(secs "⑤ desk 이름 → S11-DESK 그대로 rc=$RC")" || bad "⑤ desk rc=$RC" "$(SOUTC)"
OLD="byz-harness-arch-pi#8"; NEW="byz-harness-arch-pi#9"
set_body "${PLAIN[@]}"; world pi; reset_out; run pi
{ [ "$RC" = 0 ] && [ "$(head_block)" = "$BOOT_BLK" ] && ! sent | grep -q 'tester 목적 0 ='; } \
  && ok "$(secs "⑤ arch 이름 → S17-BOOT 그대로 rc=$RC")" || bad "⑤ arch rc=$RC" "$(sed -n '1,8p' <<<"$(sent)")"
# ── ⑥ 실 governance(팩 판) 블록 = K1 글자 그대로 · 300자 안
block_ok() {   # block_ok <gov> — 표식 1개씩 · 글 = EXPECT · 300자 안 · 줄 2 의 네 구절
  local b; b="$(block_of "$1" "$T_BEG" "$T_END")" || return 1
  [ "$b" = "$EXPECT" ] || return 1
  [ "${#b}" -le 300 ] || return 1
  local l2; l2="$(printf '%s\n' "$b" | sed -n 2p)"
  case "$l2" in *"timeout 상한"*"성공·실패 모두"*"trap EXIT"*"요약 파일 읽기"*) return 0;; esac
  return 1
}
block_ok "$GOV_REAL" && ok "$(secs "⑥ 실 governance 블록 = K1 3줄 글자 그대로 · ${#EXPECT}자")" \
  || bad "⑥ 실 governance 블록" "$(block_of "$GOV_REAL" "$T_BEG" "$T_END" | head -3)"
# ── ⑦ 본문 4행~ 에 앞 블록 3줄이 이어져도 보낸 본문에 1번만(중복 0)
OLD="byz-room-tester-pi#54"; NEW="byz-room-tester-pi#55"
printf '%s\n' '골 원문 1줄' '골 원문 2줄' '골 원문 3줄' "$EXPECT" '본문 나머지' '열린 칸 감시: 없음' > "$BODY"
world pi; reset_out; run pi
{ [ "$RC" = 0 ] && [ "$(scount 'tester 목적 0 =')" = 1 ] && [ "$(head_block)" = "$EXPECT" ]; } \
  && ok "$(secs "⑦ 본문 4행~ 에 블록 3줄 이어짐 → 1번만 rc=$RC")" || bad "⑦ rc=$RC 중복=$(scount 'tester 목적 0 =')" "$(sed -n '1,10p' <<<"$(sent)")"
# ── 변이 M1~M6 (사본에서만 · 변이마다 원본으로 같은 사례 1회 더)
mut() { rm -rf "$TMP/mut"; mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"; MUT="$TMP/mut/ft-successor-open.sh"; SO="$MUT"; }
patch() { python3 - "$MUT" "$@" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); pairs = sys.argv[2:]
for i in range(0, len(pairs), 2):
    old, new = pairs[i], pairs[i + 1]
    if s.count(old) != 1: sys.exit(f"변이 대상이 {s.count(old)}곳: {old[:60]}")
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
PY
}
TB="'<!-- S17-TESTER-BEGIN -->'; _end='<!-- S17-TESTER-END -->'"
# M1 tester 갈래 지움 → ⓐ FAIL(S17-BOOT 가 실린다)
mut; patch ";; *-tester-*) _beg=$TB" "" || bad "M1 적용" "$MUT"
set_body "${PLAIN[@]}"; world pi; reset_out; run pi
{ ! sent | grep -q 'tester 목적 0 =' && sent | grep -q '목적 0 = 진행 카드'; } \
  && ok "$(secs "M1 tester 갈래 지움 → ⓐ FAIL 재현(S17-BOOT 실림 · rc=$RC)")" || bad "M1 이 ⓐ 에 안 잡힘" "$(sed -n '1,6p' <<<"$(sent)")"
SO="$SO0"; world pi; reset_out; run pi
{ [ "$RC" = 0 ] && [ "$(head_block)" = "$EXPECT" ]; } \
  && ok "$(secs "M1 원본 대조 — tester 블록 다시 실림 rc=$RC")" || bad "M1 원본 대조" "$(SOUTC)"
# M2 tester 갈래만 표식 개수 검사를 건너뜀 → ⓑ(2개) FAIL
mut; patch ";; *-tester-*) _beg=$TB" ";; *-tester-*) _skip=1; _beg=$TB" \
  'BLOCK="$(GOV="$GOV" BEG="$_beg" END="$_end" python3' 'BLOCK="$(GOV="$GOV" BEG="$_beg" END="$_end" SKIP_MARK="${_skip:-0}" python3' \
  'if text.count(beg) != 1 or text.count(end) != 1:' 'if os.environ.get("SKIP_MARK") != "1" and (text.count(beg) != 1 or text.count(end) != 1):' \
  || bad "M2 적용" "$MUT"
world pi; reset_out; run pi FT_GOV_MD="$TMP/gov-two.md"
{ [ "$RC" != 1 ] && [ "$(sends)" -ge 1 ]; } \
  && ok "$(secs "M2 tester 갈래만 개수 검사 건너뜀 → ⓑ(2개) FAIL 재현(송신 $(sends) · rc=$RC)")" || bad "M2 가 ⓑ(2개)에 안 잡힘" "rc=$RC $(SOUTC)"
SO="$SO0"; world pi; reset_out; run pi FT_GOV_MD="$TMP/gov-two.md"
{ [ "$RC" = 1 ] && [ "$(sends)" = 0 ]; } \
  && ok "$(secs "M2 원본 대조 — 표식 2개 REJECT rc1")" || bad "M2 원본 대조" "rc=$RC $(SOUTC)"
# M3 300자 검사 지움 → ⓑ(301자) FAIL
mut; patch 'if len(block) > 300:
    print(f"REJECT 승계 블록이 300자 초과({len(block)}자) — mbox 739자 절단 안에 들어가게 줄여라: {path}"); sys.exit(3)
' "" || bad "M3 적용" "$MUT"
world pi; reset_out; run pi FT_GOV_MD="$TMP/gov-long.md"
{ [ "$RC" = 0 ] && [ "$(sends)" -ge 1 ]; } \
  && ok "$(secs "M3 300자 검사 지움 → ⓑ(301자) FAIL 재현(송신 $(sends) · rc=$RC)")" || bad "M3 이 ⓑ(301자)에 안 잡힘" "rc=$RC $(SOUTC)"
SO="$SO0"; world pi; reset_out; run pi FT_GOV_MD="$TMP/gov-long.md"
{ [ "$RC" = 1 ] && [ "$(sends)" = 0 ]; } \
  && ok "$(secs "M3 원본 대조 — 301자 REJECT rc1")" || bad "M3 원본 대조" "rc=$RC $(SOUTC)"
# M4 tester 갈래를 desk 갈래 앞에 «*-desk-*|*-tester-*» 로 합침 → ⓐ FAIL(desk 블록이 실림)
mut; patch "case \"\$NAME\" in *-desk-*) _beg='<!-- S11-DESK-BEGIN -->'; _end='<!-- S11-DESK-END -->';; *-tester-*) _beg=$TB;; *)" \
  "case \"\$NAME\" in *-desk-*|*-tester-*) _beg='<!-- S11-DESK-BEGIN -->'; _end='<!-- S11-DESK-END -->';; *)" || bad "M4 적용" "$MUT"
set_body "${PLAIN[@]}"; world pi; reset_out; run pi
{ [ "$(head_block)" = "$DESK_BLK" ] && ! sent | grep -q 'tester 목적 0 ='; } \
  && ok "$(secs "M4 «desk|tester» 합침 → ⓐ FAIL 재현(desk 블록 실림 · rc=$RC)")" || bad "M4 가 ⓐ 에 안 잡힘" "$(sed -n '1,6p' <<<"$(sent)")"
SO="$SO0"; world pi; reset_out; run pi
{ [ "$RC" = 0 ] && [ "$(head_block)" = "$EXPECT" ]; } \
  && ok "$(secs "M4 원본 대조 — tester 블록 다시 실림 rc=$RC")" || bad "M4 원본 대조" "$(SOUTC)"
# M5 governance 블록 줄 2 지움 → ⑥ FAIL
python3 - "$GOV_REAL" "$TMP/gov-l2.md" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
b, e = "<!-- S17-TESTER-BEGIN -->", "<!-- S17-TESTER-END -->"
head, rest = t.split(b, 1); blk, tail = rest.split(e, 1)
lines = blk.split("\n"); del lines[2]          # 첫 줄 = 빈 줄 · 둘째 줄 = K1 줄 1 · 셋째 줄 = K1 줄 2
open(sys.argv[2], "w", encoding="utf-8").write(head + b + "\n".join(lines) + e + tail)
PY
! block_ok "$TMP/gov-l2.md" && ok "$(secs "M5 governance 블록 줄 2 지움 → ⑥ FAIL 재현")" || bad "M5 가 ⑥ 에 안 잡힘" ""
block_ok "$GOV_REAL" && ok "$(secs "M5 원본 대조 — ⑥ 다시 통과")" || bad "M5 원본 대조" ""
# M6 sed 에 더한 tester 머리 3개 되돌림 → ⑦ FAIL(블록 2번)
mut; patch '열린 칸 감시: |tester 목적 0 =|기다림 = sleep 폴링 0|press 단계 = 작업 폴더)' '열린 칸 감시: )' || bad "M6 적용" "$MUT"
printf '%s\n' '골 원문 1줄' '골 원문 2줄' '골 원문 3줄' "$EXPECT" '본문 나머지' '열린 칸 감시: 없음' > "$BODY"
world pi; reset_out; run pi
{ [ "$(scount 'tester 목적 0 =')" = 2 ]; } \
  && ok "$(secs "M6 sed tester 머리 3개 되돌림 → ⑦ FAIL 재현(블록 2번 · rc=$RC)")" || bad "M6 이 ⑦ 에 안 잡힘" "중복=$(scount 'tester 목적 0 =')"
SO="$SO0"; world pi; reset_out; run pi
{ [ "$RC" = 0 ] && [ "$(scount 'tester 목적 0 =')" = 1 ]; } \
  && ok "$(secs "M6 원본 대조 — 블록 1번만 rc=$RC")" || bad "M6 원본 대조" "중복=$(scount 'tester 목적 0 =')"
# ── bin·kit 같은 글자(cmp 0)
cmp -s "$SO0" "$KIT" && ok "$(secs "bin·kit cmp 0")" || bad "bin·kit 다름" "cmp $SO0 $KIT"
echo "단계 초 — 준비 4 · 사례 ①②③④⑤⑦⑥ · 변이 6쌍 = $(( $(date +%s) - SET0 ))초"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
