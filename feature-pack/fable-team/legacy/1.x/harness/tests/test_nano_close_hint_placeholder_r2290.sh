#!/usr/bin/env bash
# test_nano_close_hint_placeholder_r2290.sh — r2290: 닫기 차례 줄·닫기 ① 거절의 «출력 글자» 만 바뀐다(판정·rc·명부·원장 0).
#   A1 채움 실패 줄 = « — 채울 일: ft-nano-close.sh …»(«bash» 0) · A2 채움 성공·승인·--summary 줄 = 기준판과 바이트 같음
#   A3 상대경로 --result 가 없어 ① 거절 → 사유 뒤 «다음:» 1줄(나노 워크트리에 있으면 그 절대경로 · 없으면 cwd 기준 안내) · A4 그 밖 그대로.
#   반례 ①~⑦ + 변이 M1·M2(변이마다 원본 대조) · 기준판 = 팩 6fdbe0706(git show) 에서 ①②⑤ Red.
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote · 가짜 명부·mbox·tmux) + _nano_record_r1717_close_fixture.sh(«실» 닫기 도구 사본 · 가짜 gh·tmux)
#   ② 문구 정정: A1 꼴도 «<산출»(리다이렉트)이 명령 찾기보다 먼저라 «산출: No such file» 은 양쪽 같다 → ② = 산출·seq 파일이 있는 cwd 에서 eval 해도 닫기 도구가 안 돈다.
#   실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0 · 자기 재호출 0.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_nano_record_r1717_close_fixture.sh"
BASESHA=6fdbe0706407c489a1375cdedbc2e2b56b613f00
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
line_of() { printf '%s\n' "$1" | grep -F "닫기 차례 $2 " | head -1; }
nostep() { printf '%s\n' "$1" | grep -v '^STEP '; }   # STEP 초 = 계측 줄

step "사전: 짝 cmp · 문법 · 기준판 사본"
for f in ft-nano-close-due.sh ft-nano-close.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "cmp bin == kit $f" || bad "cmp 다름 $f"; done
bash -n "$SRC/ft-nano-close.sh" && /bin/bash -n "$SRC/ft-nano-close.sh" && /bin/bash -n "$SRC/ft-nano-close-due.sh" && ok "bash -n(3.2 포함)" || bad "bash -n"
BASEBIN="$T/basebin"; cp -R "$SRC" "$BASEBIN"
for f in ft-nano-close-due.sh ft-nano-close.sh; do git -C "$H" show "$BASESHA:./bin/$f" > "$BASEBIN/$f" 2>/dev/null || bad "기준판 꺼내기 실패 $f"; done
mkmut() {  # mkmut <파일> <옛> <새> → MB = SRC 사본(그 자리 1곳만 바꿈)
  MB="$T/mut"; rm -rf "$MB"; cp -R "$SRC" "$MB"
  python3 - "$MB/$1" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, "변이 자리 %d곳: %s" % (s.count(old), old[:60])
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ $? = 0 ] || { bad "변이 자리 못 찾음 $1"; MB=""; }   # 빈 MB = 원본으로 도는 꼴 → «생존» 으로 드러난다(거짓 «잡힘» 0)
}
world; closebin "$SRC"

step "세계: 착지 PR #20 · a = 착지 뒤 기록 다 섬 · c = 완료 줄 없음"
na="$(NN a)"; nc="$(NN c)"; fresh; land 20; cardf a; cardf c "$(setl)" "$(landl 20)"; cpush
seats "$na|nano|a" "$nc|nano|c"; turn 20 a c; landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }; landed "$na" 20 a --test "$TST"
due_of() { cdue "$1"; printf '%s' "$OUT"; }
NEW="$(due_of "$SRC")"; OLD="$(due_of "$BASEBIN")"

c1() {  # ① 채움 실패 줄 = « — 채울 일: ft-nano-close.sh» · «bash» 0 · 끝 «빠짐=착지 뒤 완료 줄 채울 이=…»
  local L; L="$(line_of "$2" "$nc")"
  t "① 채울 일 꼴" inc "$L" " — 채울 일: ft-nano-close.sh $nc --landed-pr 20 --result <산출> --recv <seq> 빠짐=착지 뒤 완료 줄 채울 이=$nc"
  t "① «bash» 0" exc "$L" "bash"; t "① 머리 그대로" inc "$L" "닫기 차례 $nc 팀=harness 가지="; return $E
}
c2() {  # ② 산출·seq 파일이 있는 cwd 에서 줄 꼬리를 eval → 닫기 도구(가짜 PATH 스텁) 호출 0 · «command not found» rc≠0
  local L d="$T/ev$RANDOM" o r; L="$(line_of "$2" "$nc")"; mkdir -p "$d/p"; : > "$d/산출"; : > "$d/seq"
  printf '#!/bin/sh\necho "$*" >> "%s/called"\n' "$d" > "$d/p/ft-nano-close.sh"; cp "$d/p/ft-nano-close.sh" "$d/p/bash"; chmod +x "$d/p/"*
  o="$(cd "$d" && PATH="$d/p:/usr/bin:/bin" /bin/bash -c "eval \"\${1#* — }\"" _ "$L" 2>&1)"; r=$?
  t "② 닫기 도구 호출 0" [ ! -e "$d/called" ]; t "② rc≠0" [ "$r" -ne 0 ]; t "② command not found" inc "$o" "command not found"; return $E
}
c3() {  # ③ 채움 성공 줄(갈래=착지기록) = 기준판과 바이트 같음
  local L; L="$(line_of "$NEW" "$na")"
  t "③ 갈래=착지기록 · bash 실행 꼴" inc "$L" " 갈래=착지기록 rec="; t "③ — bash" inc "$L" " — bash ft-nano-close.sh $na --landed-pr 20 "
  t "③ 기준판과 같음" [ "$L" = "$(line_of "$OLD" "$na")" ]; return $E
}
c4() {  # ④ --summary · 채움 실패 줄 밖 모든 줄 = 기준판과 같음 · 승인 갈래 = r1670 시험(줄 꼬리 «— bash … --approved …» 그대로) 통과
  local s1 s2; s1="$(cd "$T" && FT_NANO_AUTO_CLOSE=1 bash "$SRC/ft-nano-close-due.sh" --all --summary 2>&1)"; s2="$(cd "$T" && FT_NANO_AUTO_CLOSE=1 bash "$BASEBIN/ft-nano-close-due.sh" --all --summary 2>&1)"
  t "④ --summary 같음" [ "$s1" = "$s2" ]; t "④ --summary 2석" inc "$s1" "harness=2"
  t "④ 그 밖 줄 같음" [ "$(printf '%s\n' "$NEW" | grep -vF "닫기 차례 $nc ")" = "$(printf '%s\n' "$OLD" | grep -vF "닫기 차례 $nc ")" ]
  t "④ 승인 갈래(r1670)" bash "$HERE/test_nano_close_after_approve_r1670.sh" >/dev/null 2>&1; return $E
}
step "반례 ①~④ (close-due)"
c1n() { c1 x "$NEW"; }; c2n() { c2 x "$NEW"; }
run "① 새 판" c1n; run "② 새 판 eval 해도 안 돈다" c2n; run "③ 채움 성공 줄 그대로" c3; run "④ 승인·요약·그 밖 줄 그대로" c4
c1o() { c1 x "$OLD"; }; c2o() { c2 x "$OLD"; }
( c1o ) >/dev/null 2>&1 && bad "기준판 ① 통과(Red 아님)" || ok "기준판 ① Red"
( c2o ) >/dev/null 2>&1 && bad "기준판 ② 통과(Red 아님)" || ok "기준판 ② Red"
mkmut ft-nano-close-due.sh '— 채울 일: {lr}ft-nano-close.sh' '— {lr}bash ft-nano-close.sh'; MD="$(due_of "$MB")"   # M1
c1m() { c1 x "$MD"; }; c2m() { c2 x "$MD"; }
( c1m ) >/dev/null 2>&1 && bad "M1 ① 생존" || ok "M1 ① FAIL(잡힘)"; ( c2m ) >/dev/null 2>&1 && bad "M1 ② 생존" || ok "M1 ② FAIL(잡힘)"
run "M1 원본 대조 ①" c1n; run "M1 원본 대조 ②" c2n

step "세계: 닫기 ① 거절 — 팀장 워크트리(cwd=ROOT) · 나노 워크트리 NW"
ns="$(NN s)"; fresh; land 21; card s "$(setl)" "$(landl 21)"; seats "$ns|nano|s"; nwt s; mkdir -p "$NW/out"; echo r > "$NW/out/r.md"
nc_with() { cp "$1/ft-nano-close.sh" "$CB/ft-nano-close.sh"; nclose "${@:2}"; cp "$SRC/ft-nano-close.sh" "$CB/ft-nano-close.sh"; }   # 스텁 든 사본 폴더(CB)에 그 판만 끼운다
c5() {  # ⑤ 상대경로 · NW/out/r.md 있음 → ① 사유 + «다음: --result <NW>/out/r.md»
  nc_with "$1" "$ns" --landed-pr 21 --result out/r.md --recv 100
  t "⑤ rc1" [ "$RC" = 1 ]; t "⑤ ① 사유 그대로" inc "$OUT" "①결과 경로 없음: out/r.md"
  t "⑤ 다음 줄" inc "$OUT" "다음: --result $NW/out/r.md(나노 워크트리 기준 절대경로)"
  t "⑤ 다음 = 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^다음: --result')" = 1 ]; return $E
}
c6() {  # ⑥ 상대경로 · 나노 워크트리에도 없음 → cwd 기준 안내 1줄
  nc_with "$1" "$ns" --landed-pr 21 --result out/none.md --recv 100
  t "⑥ rc1" [ "$RC" = 1 ]; t "⑥ 안내" inc "$OUT" "다음: --result 는 cwd 기준 — 나노 워크트리 기준 절대경로로"
  t "⑥ 다음 = 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^다음: --result')" = 1 ]; return $E
}
c7() {  # ⑦ 절대경로 실재 → ① 통과 · 안내 0 · 기준판과 같은 출력(다른 사유 REJECT = ② 없는 seq)
  local o1 o2
  nc_with "$SRC" "$ns" --landed-pr 21 --result "$NW/out/r.md" --recv 999999; o1="$(nostep "$OUT")"
  nc_with "$BASEBIN" "$ns" --landed-pr 21 --result "$NW/out/r.md" --recv 999999; o2="$(nostep "$OUT")"
  t "⑦ rc1(② 거절)" inc "$o1" "②seq 999999"
  t "⑦ ① 통과" exc "$o1" "①결과"; t "⑦ 안내 0" exc "$o1" "다음: --result"; t "⑦ 기준판과 같음" [ "$o1" = "$o2" ]; return $E
}
c5n() { c5 "$SRC"; }; c6n() { c6 "$SRC"; }
step "반례 ⑤~⑦ (ft-nano-close ①)"; run "⑤ 나노 워크트리 기준 안내" c5n; run "⑥ cwd 기준 안내" c6n; run "⑦ 절대경로 그대로" c7
c5o() { c5 "$BASEBIN"; }; ( c5o ) >/dev/null 2>&1 && bad "기준판 ⑤ 통과(Red 아님)" || ok "기준판 ⑤ Red"
mkmut ft-nano-close.sh '[ -n "${SEAT_WT:-}" ] && [ -e "$SEAT_WT/$RESULT" ]' 'false'   # M2 — $SEAT_WT 대조 지움(r2290-mut:seatwt)
c5m() { c5 "$MB"; }; ( c5m ) >/dev/null 2>&1 && bad "M2 ⑤ 생존" || ok "M2 ⑤ FAIL(잡힘)"; run "M2 원본 대조 ⑤" c5n
finish
