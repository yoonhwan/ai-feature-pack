#!/usr/bin/env bash
# test_nano_close_hint_placeholder_r1749.sh — r1749: ft-nano-close-due 채움 실패 줄 = «— 채울 일: ft-nano-close.sh …»(실행 꼴 0) · ft-nano-close ① 상대경로 거절 = «다음:» 1줄.
#   반례 ①~⑦(카드 동결) + 변이 M1·M2(각각 원본 대조) + 기준판(팩 901afc80 · 두 도구만 바꾼 사본)에서 ①②⑤ Red · ③④⑦ 기준판과 같음.
#   ② 는 카드 A1 글자(<산출>·<seq> 그대로)로는 bash 가 «<산출» redirect 를 command lookup 보다 먼저 처리해 «command not found» 가 나올 수 없다
#     → «실행 0 · rc≠0 · 파일 생성 0 · eval 대상 첫 낱말 ≠ bash» 로 본다(오빠 선택 · DA 요청 본문에 충돌 명시).
#   세계 = _nano_record_r1717_fixture.sh + _nano_record_r1717_close_fixture.sh(임시 bare remote · 가짜 명부·mbox·tmux·gh) — 실 명부·좌석·tmux·네트워크 0 · sleep 0.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"; . "$HERE/_nano_record_r1717_close_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'; BASE_SHA=901afc8059dc33d1bd3d0b4e5e23fa48bd0c3f33
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
lineof() { printf '%s\n' "$OUT" | grep -F "닫기 차례 $1 "; }

step "사전: 짝 사본 · 문법"
for f in ft-nano-close-due.sh ft-nano-close.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "bin·kit cmp0 $f" || bad "짝 사본 다름 $f"; bash -n "$SRC/$f" && /bin/bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"; done
world; closebin
BB="$T/basebin"; cp -R "$SRC" "$BB"; CBB="$T/closebin-base"; cp -R "$CB" "$CBB"; NCB="$T/nc-base.sh"
for f in ft-nano-close-due.sh ft-nano-close.sh; do git -C "$H" show "$BASE_SHA:./bin/$f" > "$BB/$f" 2>/dev/null || bad "기준판 꺼내기 실패 $f"; done
cp "$BB/ft-nano-close.sh" "$CBB/ft-nano-close.sh"; sed "s#$CB/ft-nano-close.sh#$CBB/ft-nano-close.sh#" "$NCREAL" > "$NCB"
grep -q "$CBB/ft-nano-close.sh" "$NCB" && ok "기준판 닫기 껍데기" || bad "기준판 닫기 껍데기"
DUEB="$SRC"; NCX="$NCREAL"
stepn() { sed -E 's/^(STEP .*) \+[0-9]+s$/\1 +Ns/'; }   # STEP 줄의 걸린 초는 실행마다 다르다(비교 밖)
ncl() { cprep "$1"; OUT="$(bash "$NCX" "$@" 2>&1)"; RC=$?; }

dworld() {  # <꼬리표> <PR> — 좌석 NA = 착지 뒤 기록 다 섬 · NC = 완료 줄 없음(자리표시 갈래)
  NA="$(NN "d$1a")"; NC="$(NN "d$1c")"; fresh; land "$2"; cardf "d$1a"; cardf "d$1c" "$(setl)" "$(landl "$2")"; cpush
  seats "$NA|nano|d$1a" "$NC|nano|d$1c"; turn "$2" "d$1a" "d$1c"; landed "$NA" "$2" "d$1a" --test "$TST"
}
c12() {  # ① 채울 일 꼴 · ② eval 해도 실행 0
  local L A EV EO ER; dworld "12$1" 31; cdue "$DUEB"; L="$(lineof "$NC")"
  t "① 채울 일 꼴" inc "$L" " — 채울 일: ft-nano-close.sh $NC --landed-pr 31 --result <산출> --recv <seq>"; t "① bash 낱말 0" exc "$L" "bash"
  t "① 끝 빠짐=" inc "$L" "빠짐=착지 뒤 완료 줄 채울 이=$NC"; t "① 머리 그대로" inc "$L" "닫기 차례 $NC 팀=harness "
  EV="$T/ev$1"; mkdir -p "$EV"; A="${L#* — }"; EO="$(cd "$EV" && L="$L" bash -c 'eval "${L#* — }"' 2>&1)"; ER=$?
  t "② eval rc≠0" [ "$ER" != 0 ]; t "② 파일 생성 0" [ -z "$(ls -A "$EV")" ]; t "② eval 대상 첫 낱말 ≠ bash" [ "${A%% *}" != bash ]; t "② 닫기 도구 실행 0" exc "$EO" "REJECT"
  return $E
}
c3() {  # ③ 착지기록 줄 = 기준판과 바이트 같음 · ④ --summary 도
  local Ln Lb Sn Sb; dworld "3$1" 33; cdue "$SRC"; Ln="$(lineof "$NA")"; cdue "$BB"; Lb="$(lineof "$NA")"
  t "③ 갈래=착지기록 — bash" inc "$Ln" " 갈래=착지기록 rec="; t "③ 실행 꼴 그대로" inc "$Ln" " — bash ft-nano-close.sh $NA --landed-pr 33 "; t "③ 기준판과 같음" [ "$Ln" = "$Lb" ]
  Sn="$(cd "$T" && FT_NANO_AUTO_CLOSE=1 bash "$SRC/ft-nano-close-due.sh" --summary 2>&1)"; Sb="$(cd "$T" && FT_NANO_AUTO_CLOSE=1 bash "$BB/ft-nano-close-due.sh" --summary 2>&1)"
  t "④ --summary 기준판과 같음" [ "$Sn" = "$Sb" ]; t "④ --summary 꼴" inc "$Sn" "닫기 차례 harness="; return $E
}
c4() {  # ④ FT_NANO_AUTO_CLOSE=1 승인 갈래 줄 = 기준판과 같음
  local R="$T/ap$1" W="$T/apw$1" S='byz-harness-nano-ap#0' M0 HH On Ob I="design/teams/harness/indices/진행"
  mkdir -p "$R/.fable-team/comm/bodies" "$R/.fable-team/state" "$R/$I" "$R/design/harness"; printf '%s\n' "$S" > "$T/apsess$1"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | m | 현역 |\n' > "$R/design/TEAMS.md"
  printf '{"seq": 7, "from": "%s", "to": "m#1", "body": "산출 보고"}\n' "$S" > "$R/.fable-team/comm/mailbox.jsonl"; echo 산출 > "$R/.fable-team/comm/bodies/7.txt"
  printf '{"%s": {"role": "nano", "agent": "pi", "index": "%s/ap.md"}}\n' "$S" "$I" > "$R/.fable-team/seats-harness.json"
  git init -q --bare -b main "$T/apr$1.git"; git clone -q "$T/apr$1.git" "$W" 2>/dev/null; g "$W" checkout -q -b main 2>/dev/null; echo a > "$W/a"; g "$W" add a; g "$W" commit -qm M0
  g "$W" push -q origin main; M0="$(g "$W" rev-parse HEAD)"; g "$W" checkout -q -b nano/ap; echo x > "$W/x"; g "$W" add x; g "$W" commit -qm w; HH="$(g "$W" rev-parse HEAD)"
  g "$W" push -q origin nano/ap; g "$W" update-ref refs/remotes/origin/main "$M0"
  printf '## §1 판정: APPROVE\n\n승인 sha: %s\n' "$HH" > "$R/design/harness/DA-ap.md"
  printf '# 인덱스: ap\n## 구현 범위\n- x\n## 상태\n- base_sha: %s (spawn)\n- 세트: %s\n- DA 판정: %s/design/harness/DA-ap.md#§1\n- 인수: %s · 남은 일: 검증=arch · 쓴 이: m\n' "$M0" "$HH" "$R" "$HH" > "$R/$I/ap.md"
  On="$(cd "$T" && FT_ROOT="$R" FAKE_SESS="$T/apsess$1" FAKE_CWD="$W" FT_NANO_AUTO_CLOSE=1 bash "$SRC/ft-nano-close-due.sh" --all --why 2>&1)"
  Ob="$(cd "$T" && FT_ROOT="$R" FAKE_SESS="$T/apsess$1" FAKE_CWD="$W" FT_NANO_AUTO_CLOSE=1 bash "$BB/ft-nano-close-due.sh" --all --why 2>&1)"
  t "④ 승인 갈래 줄" inc "$On" "닫기 차례 $S 팀=harness 갈래=승인 set=$HH"; t "④ 실행 꼴 그대로" inc "$On" " — bash ft-nano-close.sh $S --approved "; t "④ 기준판과 같음" [ "$On" = "$Ob" ]
  return $E
}
cworld() {  # <꼬리표> <PR> — 착지 뒤 기록까지 선 좌석 1 + 좌석 워크트리(NW) · NX = NEXT 인자
  S="cl$1"; N="$(NN "cl$1")"; fresh; land "$2"; card "$S"; seats "$N|nano|$S"; turn "$2" "$S"
  landed "$N" "$2" "$S" --test "$TST"; NX="$(printf '%s\n' "$OUT" | sed -n 's/^NEXT bash ft-nano-close.sh //p')"; RV="$(printf '%s\n' "$NX" | sed -n 's/.* --recv \([0-9]*\).*/\1/p')"; nwt "$S"
}
c5() {  # ⑤ 상대경로 · 나노 워크트리에 있음 → 다음: --result <NW>/out/r.md · 그 밖 출력은 기준판과 같음
  local On Ob Rn Rb; cworld "5$1" 35; mkdir -p "$NW/out"; echo r > "$NW/out/r.md"
  NCX="$NCB" CLOSE_LIVE=1 ncl "$N" --landed-pr 35 --result out/r.md --recv "$RV"; Ob="${OUT//"$CBB"/"$CB"}"; Rb=$RC   # 기준판 사본 폴더 경로(INFO 줄)만 맞춘다
  NCX="${NCX5:-$NCREAL}" CLOSE_LIVE=1 ncl "$N" --landed-pr 35 --result out/r.md --recv "$RV"; On="$OUT"; Rn=$RC
  t "⑤ ① 사유" inc "$On" "①결과 경로 없음: out/r.md"; t "⑤ 다음: 절대경로" inc "$On" "다음: --result $NW/out/r.md(나노 워크트리 기준 절대경로)"
  t "⑤ 마지막 줄 = 안내" [ "$(printf '%s\n' "$On" | tail -1)" = "다음: --result $NW/out/r.md(나노 워크트리 기준 절대경로)" ]
  t "⑤ 기준판 안내 0" exc "$Ob" "다음: --result"; t "⑤ A4 rc 같음" [ "$Rn $Rb" = "1 1" ]; t "⑤ A4 안내 줄 뺀 출력 = 기준판" [ "$(printf '%s\n' "$On" | sed '$d' | stepn)" = "$(printf '%s\n' "$Ob" | stepn)" ]
  return $E
}
c6() {  # ⑥ 상대경로 · 어디에도 없음 → cwd 기준 안내 1줄
  cworld "6$1" 36; CLOSE_LIVE=1 ncl "$N" --landed-pr 36 --result out/none.md --recv "$RV"
  t "⑥ ① 사유" inc "$OUT" "①결과 경로 없음: out/none.md"; t "⑥ 안내 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^다음: --result 는 cwd 기준 — 나노 워크트리 기준 절대경로로$')" = 1 ]
  t "⑥ 절대경로 안내 0" exc "$OUT" "(나노 워크트리 기준 절대경로)"; t "⑥ rc 1" [ "$RC" = 1 ]; return $E
}
c7() {  # ⑦ 절대경로 실재 → ① 통과 · 안내 0 · 닫힘(기준판 = 같은 사례를 NCX=기준판 껍데기로 한 번 더 · 세계 따로)
  cworld "7$1" 37; set -f; CLOSE_LIVE=1 ncl $NX; set +f
  t "⑦ ① 사유 0" exc "$OUT" "①결과"; t "⑦ 안내 0" exc "$OUT" "다음: --result"; t "⑦ CLOSED" inc "$OUT" "CLOSED $N landed-pr=37"; return $E
}
step "반례 ①~⑦"; run "①② 채울 일 꼴 · eval 실행 0" c12; run "③④ 착지기록 줄·요약 그대로" c3; run "④ 승인 갈래 줄 그대로" c4
run "⑤ 상대경로 → 나노 워크트리 절대경로 안내" c5; run "⑥ 상대경로 없음 → cwd 기준 안내" c6; run "⑦ 절대경로 진행" c7; NCX="$NCB"; run "⑦ 기준판도 같은 진행" c7 b; NCX="$NCREAL"
step "기준판 ①②⑤ Red"
( DUEB="$BB"; c12 b ) >/dev/null 2>&1 && bad "기준판 ①② 통과(Red 아님)" || ok "기준판 ①② FAIL(Red)"
( NCX5="$NCB"; c5 b ) >/dev/null 2>&1 && bad "기준판 ⑤ 통과(Red 아님)" || ok "기준판 ⑤ FAIL(Red)"
step "변이 M1·M2 (+원본 대조)"
M1="$T/m1"; cp -R "$SRC" "$M1"; M2="$T/m2"; cp -R "$CB" "$M2"; NCM="$T/nc-m2.sh"; sed "s#$CB/ft-nano-close.sh#$M2/ft-nano-close.sh#" "$NCREAL" > "$NCM"
python3 - "$M1/ft-nano-close-due.sh" '— 채울 일: ft-nano-close.sh {k} --landed-pr {pr}' '— bash ft-nano-close.sh {k} --landed-pr {pr}' \
  "$M2/ft-nano-close.sh" 'if [ -n "${SEAT_WT:-}" ] && [ -e "$SEAT_WT/$RESULT" ]; then' 'if false; then' <<'PY' && ok "변이 사본 2개" || bad "변이 자리 못 찾음"
import sys
a = sys.argv[1:]
for i in range(0, len(a), 3):
    s = open(a[i], encoding="utf-8").read(); assert s.count(a[i + 1]) == 1, a[i + 1]
    open(a[i], "w", encoding="utf-8").write(s.replace(a[i + 1], a[i + 2], 1))
PY
( DUEB="$M1"; c12 m1 ) >/dev/null 2>&1 && bad "M1 변이를 못 잡음(①②)" || ok "M1 «채울 일:»→«bash» → ①② FAIL(잡힘)"
( c12 o1 ) >/dev/null 2>&1 && ok "M1 원본 대조 → ①② 통과" || bad "M1 원본 대조 FAIL"
( NCX5="$NCM"; c5 m2 ) >/dev/null 2>&1 && bad "M2 변이를 못 잡음(⑤)" || ok "M2 \$SEAT_WT 대조 지움 → ⑤ FAIL(잡힘)"
( c5 o2 ) >/dev/null 2>&1 && ok "M2 원본 대조 → ⑤ 통과" || bad "M2 원본 대조 FAIL"
finish
