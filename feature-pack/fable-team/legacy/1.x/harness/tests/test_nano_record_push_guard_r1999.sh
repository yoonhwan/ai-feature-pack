#!/usr/bin/env bash
# test_nano_record_push_guard_r1999.sh — r1999: 나노 가드(ft2/tools/pre-push-nano-guard.sh)가 «카드 1장에 줄만 더한 커밋 1개» 의 ops/main-base push 만 통과시킨다
#   가드 반례 ①~⑦ + 면제 0 꼴(새 원격·삭제·merge 부모 2) + mixed refs 두 순서 + git 실패 = 판정 불가 · 기록 도구 ⑧(PUSH_DENIED → REJECT · push 1번) · 연결 ⑨(실 BYZ 훅 사본 + 가드 → landed DONE)
#   변이 M1(부모 검사)·M2(지운 줄 검사)·M3(PUSH_DENIED 갈래) + 원본 대조 · 세계 = 임시 bare 리포 + _nano_record_r1717_fixture.sh · 실 원격·명부·우편함·설치 0 · sleep 0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
unset FT2_HOLDER FT_SEAT_NAME   # 이 시험을 부른 셸이 나노여도 «나노 아님» 사례가 나노로 읽히지 않게
FT2="$(cd -- "$H/../../../ft2" && pwd)"; GUARD="$FT2/tools/pre-push-nano-guard.sh"; NANO="byz-x-nano-r9#0"; TST='bash tests/t.sh rc=0'
CA="design/harness/indices/진행/a.md"; CB="design/harness/indices/진행/b.md"
hooks() {  # hooks <폴더> [<가드 파일>] — 실 BYZ 훅 사본(r1900 픽스처) + 가드 사본
  mkdir -p "$1"; cp "$FT2/tests/fixtures/byz-pre-push-r1900" "$1/pre-push"; cp "${2:-$GUARD}" "$1/pre-push-nano-guard.sh"; chmod +x "$1/pre-push"
}
gw() {  # gw <이름> — bare 원격(main·ops/main-base = 카드 2장 + 코드 1) + clone C(core.hooksPath = 훅 사본)
  local d="$T/g-$1"; rm -rf "$d"; hooks "$d/hk" "${GUARD_SRC:-}"; git init -q --bare -b main "$d/r.git"; git clone -q "$d/r.git" "$d/c" 2>/dev/null; C="$d/c"
  mkdir -p "$C/design/harness/indices/진행" "$C/src"; printf '# a\n\n## 상태\n- x\n' > "$C/$CA"; printf '# b\n' > "$C/$CB"; echo 'x = 1' > "$C/src/a.py"
  g "$C" add -A; g "$C" commit -qm base; g "$C" push -q origin HEAD:main HEAD:ops/main-base; g "$C" config core.hooksPath "$d/hk"
}
addl() { local f; for f in "$@"; do printf -- '- 더한 줄\n' >> "$C/$f"; done; g "$C" add -A; g "$C" commit -qm add; }
rtip() { g "$C" ls-remote origin "refs/heads/$1" | cut -f1; }
gp() { OUT="$(cd "$C" && env ${SEAT:+FT_SEAT_NAME="$SEAT"} git push origin "$@" 2>&1)"; RC=$?; }   # SEAT 비면 나노 아님
denied() { local a; a="$(rtip ops/main-base) $(rtip main)"; SEAT="${SEAT-$NANO}" gp "$@"; t "$D 거절 rc≠0" [ "$RC" != 0 ]; t "$D PUSH_DENIED" inc "$OUT" PUSH_DENIED; t "$D 원격 그대로" [ "$(rtip ops/main-base) $(rtip main)" = "$a" ]; }

c1() { D=①; gw "c1$1"; addl "$CA" "$CA"; SEAT=$NANO gp HEAD:ops/main-base; t "① 카드 1장 +2줄 = 통과" [ "$RC $(rtip ops/main-base)" = "0 $(g "$C" rev-parse HEAD)" ]; return $E; }
c2() { D=②; gw "c2$1"; addl "$CA"; denied HEAD:main; return $E; }
c3() { D=③; gw "c3$1"; printf '# a 고침\n\n## 상태\n- x\n- 더한 줄\n' > "$C/$CA"; g "$C" commit -qam fix; denied HEAD:ops/main-base; return $E; }
c4() { D=④; gw "c4$1"; addl "$CA" "$CB"; denied HEAD:ops/main-base; return $E; }
c5() { D=⑤; gw "c5$1"; addl src/a.py; denied HEAD:ops/main-base; return $E; }
c6() { D=⑥; gw "c6$1"; addl "$CA"; addl "$CA"; denied HEAD:ops/main-base; return $E; }
c7() { D=⑦; gw "c7$1"; addl src/a.py; SEAT="" gp HEAD:ops/main-base; t "⑦ 나노 아님 · 코드 = 통과" [ "$RC $(rtip ops/main-base)" = "0 $(g "$C" rev-parse HEAD)" ]; return $E; }
cz() {  # 면제 0 꼴: 새 원격(remote 0) · 삭제(local 0) · merge 부모 2(내용은 카드 줄뿐)
  D=Z; gw "cz$1"; addl "$CA"; SEAT="" gp :ops/main-base; D="Z 새 원격"; denied HEAD:ops/main-base
  SEAT="" gp HEAD~1:refs/heads/ops/main-base; D="Z 삭제"; denied :ops/main-base
  local a; a="$(g "$C" rev-parse HEAD)"; g "$C" checkout -q -b side HEAD~1; g "$C" merge -q --no-ff -m m "$a"; D="Z merge 부모 2"; denied HEAD:ops/main-base; return $E
}
cm() {  # mixed refs 두 순서 — 허용 카드 뒤 main 거절 · main 거절 뒤 허용 카드(앞 거절을 뒤 면제가 지우지 않음)
  gw "cm$1"; addl "$CA"; D="M 카드→main"; denied HEAD:ops/main-base HEAD:main; t "M 카드 행 문구 0" exc "$OUT" "의 refs/heads/ops/main-base push"
  D="M main→카드"; denied HEAD:main HEAD:ops/main-base; t "M main 행 문구" inc "$OUT" "의 refs/heads/main push"; return $E
}
cf() {  # git 실패(rev-parse·diff) = PUSH_DENIED + 판정 불가 1줄 · 통과 0
  local fk="$T/fkgit$1" s; mkdir -p "$fk"; printf '#!/bin/sh\nexit 128\n' > "$fk/git"; chmod +x "$fk/git"; s="$(printf 'a%.0s' $(seq 40))"
  OUT="$(printf 'refs/heads/x %s refs/heads/ops/main-base %s\n' "$s" "${s//a/b}" | PATH="$fk:$PATH" FT_SEAT_NAME="$NANO" sh "${GUARD_SRC:-$GUARD}" 2>&1)"; RC=$?
  t "F rc1" [ "$RC" = 1 ]; t "F PUSH_DENIED" inc "$OUT" PUSH_DENIED; t "F 판정 불가 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '판정 불가')" = 1 ]; return $E
}
cworld() { g "$ROOT" config core.hooksPath "$1"; }   # r1717 세계(카드 ref = ops/main-base)의 훅 폴더
mcard() {  # mcard <stem> — 카드 ref(ops/main-base) 끝 위에 카드 1장(훅 밖 · 시험 준비)
  g "$OPS" fetch -q origin; g "$OPS" checkout -q --detach origin/ops/main-base; cardf "$1"; g "$OPS" add -A; g "$OPS" commit -qm "card $1"
  g "$OPS" -c core.hooksPath=/nonexistent push -q origin HEAD:ops/main-base; g "$ROOT" fetch -q origin
}
mtext() { g "$CREM" show "ops/main-base:$IDX/진행/$1.md"; }
c8() {  # ⑧ 가드가 PUSH_DENIED 를 내는 스텁 → REJECT PUSH_DENIED … rc1 · push 시도 1번 · 쓰기 0
  local s="c8$1" n="byz-harness-nano-c8$1#0" hk="$T/hk8$1"; fresh; mkdir -p "$hk"
  printf '#!/bin/sh\necho x >> "%s/pp.log"\necho "PUSH_DENIED 나노 좌석 스텁 — 착지 = master" >&2\nexit 1\n' "$hk" > "$hk/pre-push"; chmod +x "$hk/pre-push"
  land 8; mcard "$s"; cworld "$hk"; seats "$n|nano|$s"; turn 8 "$s"; rec landed --seat "$n" --pr 8 --card "$s" --test "$TST"
  t "⑧ REJECT PUSH_DENIED" [ "${OUT%%$'\n'*}" = "REJECT PUSH_DENIED 나노 좌석 스텁 — 착지 = master" ]; t "⑧ rc1" [ "$RC" = 1 ]
  t "⑧ push 1번" [ "$(wc -l < "$hk/pp.log" | tr -d ' ')" = 1 ]; t "⑧ 카드 줄 0" [ "$(mtext "$s" | grep -c '^- 착지: ')" = 0 ]; return $E
}
c9() {  # ⑨ 연결: 실 BYZ 훅 사본 + 가드 · 나노 env · 나노 차례 카드 → landed DONE · 카드 ref 에 ⓢⓛⓒ
  local s="c9$1" n="byz-harness-nano-c9$1#0"; fresh; hooks "$T/hk9$1" "${GUARD_SRC:-}"; land 9; mcard "$s"; cworld "$T/hk9$1"; seats "$n|nano|$s"; turn 9 "$s"
  FT_SEAT_NAME="$n" rec landed --seat "$n" --pr 9 --card "$s" --test "$TST"; t "⑨ DONE" inc "$OUT" DONE; t "⑨ PUSH_DENIED 0" exc "$OUT" PUSH_DENIED
  t "⑨ ⓢⓛⓒ" [ "$(mtext "$s" | grep -c -e "^- 세트: $PH " -e "^- 착지: $Q " -e "^- 완료: $n ")" = 3 ]; return $E
}
gmut() {  # gmut <M> <사례> <옛 글> — 가드 사본에서 그 줄을 지움 → 사례 FAIL · 원본으로 1회 더
  local mg="$T/mut-$1.sh" o; python3 - "$GUARD" "$mg" "$3" <<'PY' || { bad "$1 변이 자리 없음"; return; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert s.count(sys.argv[3]) == 1, sys.argv[3]
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], ":", 1))
PY
  if o="$(GUARD_SRC="$mg" "$2" "m$1" 2>&1)"; then bad "$1 변이를 못 잡음($2)"; else ok "$1 변이 → $2 FAIL(잡힘)"; fi
  if o="$("$2" "o$1" 2>&1)"; then ok "$1 원본 대조 → $2 통과"; else bad "$1 원본 대조 FAIL($2)" "$o"; fi
}

step "사전: 문법 · 짝 사본"
sh -n "$GUARD" && bash -n "$GUARD" && ok "sh -n 가드" || bad "sh -n 가드"
cmp -s "$SRC/ft_nano_record_write.py" "$KIT/ft_nano_record_write.py" && ok "짝 사본 bin·kit cmp0" || bad "짝 사본 다름"
world; g "$OPS" push -q origin HEAD:ops/main-base; g "$ROOT" fetch -q origin; export FT_CARD_REF=origin/ops/main-base
step "가드 반례"; for c in c1 c2 c3 c4 c5 c6 c7 cz cm cf; do run "가드 $c" "$c"; done
step "기록 도구 ⑧ · 연결 ⑨"; run "⑧ PUSH_DENIED → REJECT" c8; run "⑨ 연결 landed DONE" c9
step "변이 M1·M2·M3 (+원본 대조)"
gmut M1 c6 '[ "$p" = "$2" ] || return 1   # r1999-mut:parent'
gmut M2 c3 '[ "$d" = 0 ] || return 1   # r1999-mut:del'
mutbin m3 ft_nano_record_write.py '        if "PUSH_DENIED" in err:   # r1999-mut:denied' '        if False:'; mutcase M3 c8 3
finish
