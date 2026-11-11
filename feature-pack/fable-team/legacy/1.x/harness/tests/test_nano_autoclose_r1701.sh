#!/usr/bin/env bash
# test_nano_autoclose_r1701.sh — r1701 자동 닫기 0석의 막힘 ①②: pi 좌석 판정이 LC_ALL=C 에서도 되고, 판정 불가 1석이 전체를 막지 않는다.
#   ⓐ LC_ALL=C + 탭을 «_» 로 바꾸는 가짜 tmux 에서 ft_seat_pi.live_identity rc0(탭 3칸 + session id) · 변이 M1(-u 삭제) → 판정 불가
#   ⓑ close-due rc=3 + «닫기 차례 A 갈래=승인» + «판정 불가 B» → A 닫기 1회 · 로그 «판정 불가 auto-close B» 1줄 · 변이 M2(rc=3 갈래 삭제) → 닫기 0
#   ⓒ close-due rc=99(시간 초과) → 닫기 0(지금과 같다)
# 팩 세트·아카이브 카드(③)는 test_nano_autoclose_r1701_pack.sh — 픽스처는 _autoclose_r1701_fixture.sh 공용 · sleep 0
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_autoclose_r1701_fixture.sh"
MX="$T/mx"; mkdir -p "$MX"; cp -R "$BIN/." "$MX/"
# ⓐ pi 좌석 — -u 가 없으면 탭이 «_» 로 바뀌어 판정이 깨진다
OUT="$(pi_run "$BIN/ft_seat_pi.py")"; RC=$?
{ [ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | awk '{print NF}')" = 4 ] && case "$OUT" in *abc123*) true;; *) false;; esac; } \
  && ok "ⓐ LC_ALL=C 에서도 pi 좌석 판정 rc0(탭 3칸 + session id)" || bad "ⓐ" "rc=$RC out=$OUT"
python3 - "$MX/ft_seat_pi.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('[tmux, "-u", "list-panes"', '[tmux, "list-panes"').replace('[tmux, "-u", "show-environment"', '[tmux, "show-environment"')
assert '"-u"' not in s
p.write_text(s)
PY
OUT="$(pi_run "$MX/ft_seat_pi.py")"; RC=$?
{ [ "$RC" != 0 ] && case "$OUT" in *"유일성 확인 불가"*) true;; *) false;; esac; } \
  && ok "M1 -u 삭제 → ⓐ 가 판정 불가(변이 잡힘)" || bad "M1" "rc=$RC out=$OUT"
# ⓑⓒ 판정 불가 1석이 전체를 막지 않는다 · 시간 초과는 지금처럼 닫기 0
ac "$BIN/ft_stall_scan.py" 3
{ [ "$RC" = 0 ] && [ "$(grep -c . <<< "$CLOSED")" = 1 ] && case "$OUT" in *"판정 불가 auto-close B"*) true;; *) false;; esac; } \
  && ok "ⓑ close-due rc=3 이어도 승인 줄 A 는 닫고 판정 불가 B 는 1줄 남긴다" || bad "ⓑ" "rc=$RC closed=$CLOSED out=$OUT"
ac "$BIN/ft_stall_scan.py" 99
{ [ -z "$CLOSED" ] && case "$OUT" in *"닫기 0"*) true;; *) false;; esac; } \
  && ok "ⓒ rc=99(시간 초과) → 닫기 0(지금과 같다)" || bad "ⓒ" "closed=$CLOSED out=$OUT"
python3 - "$MX/ft_stall_scan.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        if rc not in (0, 3):'
assert s.count(old) == 1
p.write_text(s.replace(old, '        if rc != 0:'))
PY
ac "$MX/ft_stall_scan.py" 3
{ [ -z "$CLOSED" ]; } && ok "M2 rc=3 갈래 삭제 → ⓑ 가 닫기 0(변이 잡힘)" || bad "M2" "closed=$CLOSED out=$OUT"
for f in ft_seat_pi.py ft_stall_scan.py; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && ok "짝 cmp0 $f" || bad "짝 다름 $f" ""; done
finish
