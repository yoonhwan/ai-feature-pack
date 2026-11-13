#!/usr/bin/env bash
# test_land_verify_r1814.sh — r1814: A1 팀장 갈래 DONE 만(①②) · A2 나노 갈래 회귀(③③′) · B1 ft-land-verify.sh(④⑤⑤′⑥⑥′⑦⑦′) · B2 h 꼴 landed() 1줄(④)
#   변이 M1~M5(변이마다 원본 대조) · 기준판 ①④ Red(팩 70d621a474) · ⑧ = test_nano_record_r1717.sh · test_nano_record_land_r1717.sh · test_nano_record_ownerless_r1805.sh
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote · 가짜 명부·mbox·tmux) + B 사례마다 임시 bare 원격 1개(ft-merge-land 꼴 commit-tree squash)
#   gh 0 · 실 장부·실 우편함·실 착지·실 라이브 bin 0 · sleep 0 · 사례 = 하위 셸 1개
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
LV="$BIN/ft-land-verify.sh"; BASE_SHA=70d621a474894fec24ecc432abcbc1b3e925831f   # 기준판 = 이 카드 전 origin/main(r1805 착지판)
nnext() { printf '%s\n' "$OUT" | grep -c '^NEXT ' || true; }

step "사전: 짝 사본 · 줄 수 · 문법"
for f in ft_nano_record_write.py ft-land-verify.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"; done
[ "$(wc -l < "$SRC/ft_nano_record_write.py")" -le 199 ] && ok "write.py ≤199줄(+≤2)" || bad "write.py 줄 수 넘음"
[ -f "$SRC/ft-land-verify.sh" ] && [ "$(wc -l < "$SRC/ft-land-verify.sh")" -le 60 ] && ok "ft-land-verify.sh ≤60줄" || bad "ft-land-verify.sh 없음 또는 60줄 넘음"
bash -n "$SRC/ft-land-verify.sh" 2>/dev/null && /bin/bash -n "$SRC/ft-land-verify.sh" 2>/dev/null && ok "bash -n(/bin/bash 3.2 포함)" || bad "bash -n ft-land-verify.sh"
world

own0() { fresh; land "$2"; card "$1"; seats; turn "$2" "$1"; }   # own0 <stem> <PR> — 나노 없음 · 카드 팀(harness) 카드
c1() {  # ① 팀장 landed --test → DONE 1줄 · 세트·착지 두 줄 · 완료 줄 0 · 쪽지 0 · NEXT 0 · 세션 기록 0 · 다시 = ALREADY
  local s="c1$1" c0; own0 "$s" 41; c0="$(ncommit)"
  landed "$MASTER" 41 "$s" --test "$TST"; t "① rc0" [ "$RC" = 0 ]; t "① 출력 = DONE 1줄(NEXT 0)" [ "$OUT" = DONE ]
  t "① 1커밋" [ "$(ncommit)" = "$((c0 + 1))" ]; t "① 세트 줄" [ "$(nline "$s" "^- 세트: $PH · 시험: $TST")" = 1 ]; t "① 착지 줄" [ "$(nline "$s" "^- 착지: $Q ")" = 1 ]
  t "① 완료 줄 0" [ "$(nline "$s" "^- 완료:")" = 0 ]; t "① 쪽지 0(시도 포함)" [ ! -s "$MBOX_LOG" ]; t "① 세션 기록 0" [ -z "$(ls -A "$STATE/seat-record" 2>/dev/null)" ]
  landed "$MASTER" 41 "$s" --test "$TST"; t "① 재호출 = ALREADY 1줄" [ "$OUT $RC" = "ALREADY 0" ]; t "① 재호출 쪽지 0" [ ! -s "$MBOX_LOG" ]
  return $E
}
c2() {  # ② ① 뒤 due → 끝(주인 기록) · notify → 쪽지 0
  local s="c2$1"; own0 "$s" 42; landed "$MASTER" 42 "$s" --test "$TST"
  rec due --pr 42; t "② due 끝" inc "$OUT" "끝 $s pr=42"; t "② (주인 기록)" inc "$OUT" "(주인 기록)"; t "② 주인 없음 0" exc "$OUT" "주인 없음"
  rec notify --pr 42; t "② notify rc0" [ "$RC" = 0 ]; t "② 쪽지 0" [ ! -s "$MBOX_LOG" ]
  return $E
}
c3() {  # ③ 나노 «닫기» 차례 좌석 landed → 완료 줄 · 닫기 요청 1 · NEXT 1(회귀)
  local s="c3$1" n; n="$(NN "c3$1")"; fresh; land 43; card "$s"; seats "$n|nano|$s"; turn 43 "$s"
  landed "$n" 43 "$s" --test "$TST"; t "③ DONE" inc "$OUT" "DONE"; t "③ rc0" [ "$RC" = 0 ]
  t "③ 완료 줄" [ "$(nline "$s" "^- 완료: $n · 병합 상태: 착지 ${Q:0:10} · 남은 일: 없음")" = 1 ]
  t "③ 닫기 요청 1" [ "$(nto "$MASTER" "\[완료·닫기 요청\] $s ")" = 1 ]; t "③ NEXT 1" [ "$(printf '%s\n' "$OUT" | grep -c "^NEXT bash ft-nano-close.sh $n --landed-pr 43 ")" = 1 ]
  return $E
}
c3b() {  # ③′ «기록만» 좌석 → 완료 줄(좌석 계속) · NEXT 0 · 팀장 발신 0(회귀)
  local s="c3b$1" m; m="$(NN "c3m$1")"; fresh; land 44; card "$s" "- 2026-11-12 — 대기→진행 · 좌석 $m"; seats "$m|nano|x$s"; turn 44 "$s"
  landed "$m" 44 "$s" --test "$TST"; t "③′ DONE" inc "$OUT" "DONE"; t "③′ NEXT 0" [ "$(nnext)" = 0 ]; t "③′ 팀장 발신 0" [ "$(nto "$MASTER")" = 0 ]
  t "③′ 완료 줄 좌석 계속" [ "$(nline "$s" "^- 완료: $m · 병합 상태: 착지 ${Q:0:10} · 좌석 계속(지금 카드 x$s)")" = 1 ]
  return $E
}

vrepo() {  # vrepo <이름> → V(사본) · 임시 bare 원격 · OLD = 착지 전 origin/main
  V="$T/v$1"; rm -rf "$V" "$V.git"; git init -q --bare -b main "$V.git"; git clone -q "$V.git" "$V" 2>/dev/null; g "$V" checkout -q -b main 2>/dev/null
  echo b > "$V/b"; g "$V" add -A; g "$V" commit -qm base; g "$V" push -q origin main; g "$V" fetch -q origin; OLD="$(g "$V" rev-parse origin/main)"
}
prb() { g "$V" checkout -q -B "$1" origin/main; echo "$1" > "$V/$1"; g "$V" add -A; g "$V" commit -qm "$1"; S="$(g "$V" rev-parse HEAD)"; }   # prb <가지> → S = PR 끝
sq() {  # sq <트리 커밋> <본문 줄…> → Q = ft-merge-land 꼴 squash(commit-tree · 부모 origin/main) → 원격 main
  local tr="$1" a=() x; shift; for x in "$@"; do a+=(-m "$x"); done
  Q="$(g "$V" commit-tree "$tr^{tree}" -p origin/main -m "title" "${a[@]}")"; g "$V" push -q origin "$Q:refs/heads/main"; g "$V" fetch -q origin
}
vf() { OUT="$(cd "$T" && bash "$LV" "$@" 2>&1)"; RC=$?; }
c4() {  # ④ squash 착지 → LANDED-SQUASH <Q> rc0 · h 꼴 landed() 1줄 rc0(B2)
  vrepo "4$1"; prb p7; sq "$S" "PR #7 (head $S)"
  vf "$V" 7 "$S" --since "$OLD" --head "$S"; t "④ LANDED-SQUASH Q rc0" [ "$OUT $RC" = "LANDED-SQUASH $Q 0" ]
  vf "$V" 7 "$S"; t "④ --since·--head 생략(최근 200 · head=세트)" [ "$OUT $RC" = "LANDED-SQUASH $Q 0" ]
  local P="$V" PR=7 SET="$S" HEADSHA="$S" LB; LB="$(dirname "$LV")"
  landed() { bash "$LB/ft-land-verify.sh" "$P" "$PR" "$SET" --since "$OLD" --head "$HEADSHA" >/dev/null; }
  landed; RC=$?; t "④ h 꼴 landed() rc0" [ "$RC" = 0 ]
  return $E
}
c5() {  # ⑤ --ff 착지(세트 = main 조상) → LANDED-ANCESTOR
  vrepo "5$1"; prb p7; g "$V" push -q origin "$S:refs/heads/main"; g "$V" fetch -q origin
  vf "$V" 7 "$S" --since "$OLD"; t "⑤ LANDED-ANCESTOR rc0" [ "$OUT $RC" = "LANDED-ANCESTOR $S 0" ]
  return $E
}
c5b() {  # ⑤′ 자동 병합 C 착지(본문 PR #7 (head S) + C=<c>) · --head = 원래 PR head → LANDED-SQUASH
  local c s7; vrepo "5b$1"; prb p7; s7="$S"; prb oth; S="$s7"; g "$V" push -q origin "oth:refs/heads/main"; g "$V" fetch -q origin; OLD="$(g "$V" rev-parse origin/main)"
  g "$V" checkout -q -B cm origin/main; g "$V" merge -q --no-edit "$S" >/dev/null 2>&1; c="$(g "$V" rev-parse HEAD)"; t "⑤′ C = 병합 커밋(부모 2)" [ "$(g "$V" rev-list --parents -n 1 "$c" | wc -w | tr -d ' ')" = 3 ]
  sq "$c" "PR #7 (head $S)" "main 자동 병합(코드 · 승인 EQUIV) C=$c"
  vf "$V" 7 "$S" --since "$OLD" --head "$S"; t "⑤′ LANDED-SQUASH Q rc0" [ "$OUT $RC" = "LANDED-SQUASH $Q 0" ]
  return $E
}
c6() {  # ⑥ 다른 PR(#8) 본문만 → MISS rc1
  vrepo "6$1"; prb p7; sq "$S" "PR #8 (head $S)"
  vf "$V" 7 "$S" --since "$OLD"; t "⑥ MISS rc1" [ "$OUT $RC" = "MISS PR #7 세트 ${S:0:10} 1" ]
  return $E
}
c6b() {  # ⑥′ 같은 PR 번호 · head 가 다른 세트 → MISS rc1
  local s1; vrepo "6b$1"; prb p7; s1="$S"; prb p7b; sq "$S" "PR #7 (head $S)"
  vf "$V" 7 "$s1" --since "$OLD" --head "$s1"; t "⑥′ MISS rc1" [ "$OUT $RC" = "MISS PR #7 세트 ${s1:0:10} 1" ]
  return $E
}
c7() {  # ⑦ 같은 PR #7 (head S) 줄 커밋 2개 → 판정 불가 rc3
  vrepo "7$1"; prb p7; sq "$S" "PR #7 (head $S)"; sq "$S" "PR #7 (head $S)"
  vf "$V" 7 "$S" --since "$OLD"; t "⑦ 판정 불가 2개 rc3" [ "$OUT $RC" = "판정 불가 같은 PR·세트 커밋 2개 3" ]
  return $E
}
c7b() {  # ⑦′ repo 경로 없음 → 판정 불가 git rc3 · (덧) --since 객체 없음 → 판정 불가 git log rc3
  local z=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  vf "$T/none" 7 "$z"; t "⑦′ 판정 불가 git rc3" [ "$RC" = 3 ]; t "⑦′ 줄 꼴" inc "$OUT" "판정 불가 git rev-parse rc="; t "⑦′ 1줄" [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ]
  vrepo "7b$1"; prb p7; sq "$S" "PR #7 (head $S)"
  vf "$V" 7 "$S" --since "$z"; t "⑦′ --since 없음 객체 = 판정 불가 git log rc3" [ "$RC" = 3 ]; t "⑦′ git log 줄" inc "$OUT" "판정 불가 git log rc="
  return $E
}
step "사례 ①②③③′ (A)"
run "① 팀장 landed = DONE 만" c1; run "② due 끝 · notify 0" c2; run "③ 나노 닫기 회귀" c3; run "③′ 기록만 회귀" c3b
step "사례 ④⑤⑤′⑥⑥′⑦⑦′ (B)"
run "④ squash · h landed()" c4; run "⑤ --ff 조상" c5; run "⑤′ 자동 병합 C" c5b; run "⑥ 다른 PR MISS" c6; run "⑥′ 다른 head MISS" c6b; run "⑦ 2개 판정 불가" c7; run "⑦′ git 실패 판정 불가" c7b

step "변이 M1~M5 (+원본 대조)"
mutbin m1 ft_nano_record_write.py '{s: ("팀장", stem) for s in [doc.get("_master")]' '{s: ("닫기", stem) for s in [doc.get("_master")]'; mutcase M1 c1 1
mutbin m2 ft_nano_record_write.py 'elif not m["c"] and info["sort"] != "팀장":' 'elif not m["c"]:'; mutcase M2 c1 2
lvmut() {  # lvmut <옛 글> <새 글> → LM = ft-land-verify.sh 사본(그 자리만 · 원본 불변)
  LM="$T/lvmut-$RANDOM.sh"; python3 - "$LV" "$LM" "$1" "$2" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]; s = open(src, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳"
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
lvcase() {  # lvcase <M번호> <사례> <꼬리표> — 변이 사본으로 FAIL + 원본으로 통과
  local o; if o="$(LV="$LM"; "$2" "m$3" 2>&1)"; then bad "$1 변이를 못 잡음($2)"; else ok "$1 변이 → $2 FAIL(잡힘) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
  if o="$("$2" "o$3" 2>&1)"; then ok "$1 원본 대조 → $2 통과"; else bad "$1 원본 대조가 FAIL($2)" "$o"; fi
}
lvmut 'if (L[i] == w)' 'if (index(L[i], substr(w, 1, index(w, "(head") + 5)) == 1)'; lvcase M3 c6b 3
lvmut 'N="$(printf' 'N=1; read -r HITS <<< "$HITS"; : "$(printf'; lvcase M4 c7 4
lvmut 'if [ -n "$SINCE" ]; then R=' 'echo "MISS PR #$PR 세트 ${SET:0:10}"; exit 1; if [ -n "$SINCE" ]; then R='; lvcase M5 c4 5

step "기준판 ①④ Red · ③③′ 통과(회귀) (팩 $BASE_SHA)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$H" archive "$BASE_SHA" -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-nano-record.sh" ]; then
  ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; c1 base ) >/dev/null 2>&1 && bad "기준판에서 ① 통과함" || ok "기준판 ① FAIL(기대 Red)"
  ( LV="$BASE/bin/ft-land-verify.sh"; c4 base ) >/dev/null 2>&1 && bad "기준판에서 ④ 통과함" || ok "기준판 ④ FAIL(기대 Red · 도구 없음)"
  ( vrepo hb; prb p7; sq "$S" "PR #7 (head $S)"; P="$V" SET="$S"; git -C "$P" merge-base --is-ancestor "$SET" origin/main ) >/dev/null 2>&1
  [ $? = 1 ] && ok "기준판 h landed()(조상 판정) = rc1 — squash 를 못 알아봄" || bad "기준판 h landed() rc 가 1 아님"
  for c in c3 c3b; do ( BIN="$BASE/bin"; TOOL="$BIN/ft-nano-record.sh"; "$c" base ) >/dev/null 2>&1 && ok "기준판 $c 통과(회귀)" || bad "기준판 $c FAIL"; done
else bad "기준판 꺼내기 실패 — 팩 리포 밖이거나 얕은 사본"; fi
finish
