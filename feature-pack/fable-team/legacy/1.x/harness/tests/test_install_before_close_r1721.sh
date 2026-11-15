#!/usr/bin/env bash
# test_install_before_close_r1721.sh — r1721: 도구를 바꾸는 착지 뒤 «설치 → 닫기» 순서. 반례 ①~⑧ + 변이 M1~M6(변이마다 원본 대조) + 기준판 ①·②(R1721_BASE).
#   ① [착지] 본문 끝 «다음 손: 설치 h 먼저»(PENDING 만) · ②~⑥ ft-nano-record.sh 닫기 요청 앞 drift 갈래(가짜 drift 검사 FT_DRIFT_CHECK: ok rc0 / drift rc1 / to rc124)
#   ⑦ ft-critical-notify.sh 닫기 거절 «라이브 도구가 main 키트와 다르다» → 다음 손 «설치 h 먼저 — 드리프트 파일: …»
#   ⑧ ft-index-move-install.sh 표식 지우기(팩 착지 sha · 공용 루트 표식 · 워크트리 쪽 같은 이름 손 0 · rev-list 실패 = 판정 불가 줄 · 표식 손 0) — r1738 판 그대로(회귀 증명)
#   세계 = _nano_record_r1717_fixture.sh(임시 bare remote 2 · 가짜 명부·mbox·tmux) · 실 명부·실 우편함·실 state·라이브 bin·네트워크 0 · sleep 0
#   R1721_BASE = 기준판 bin 폴더(고치기 전 · 주면 ①·② 가 그 판에서 FAIL 인지 본다 · ⑧ 은 r1738 이 먼저 착지해 기준판도 PASS — 결과 줄만 남긴다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_nano_record_r1717_fixture.sh"
NN() { printf 'byz-harness-nano-%s#0' "$1"; }
TST='bash tests/t.sh rc=0'; S0=$SECONDS; ST=""
lap() { ST="$ST $1=$((SECONDS - S0))s"; S0=$SECONDS; }
landed() { rec landed --seat "$1" --pr "$2" --card "$3" "${@:4}"; }
cat > "$FK/drift.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 drift 검사 — DRIFT_MODE: ok(rc0) · drift(rc1 · 실제 꼴 머리 줄 + 항목 줄) · to(rc124 = 시간 초과 주입) · 호출마다 DRIFT_LOG 1줄
echo "$*" >> "$DRIFT_LOG"
case "${DRIFT_MODE:-ok}" in
  ok) echo "OK ref=origin/main@abc bin=$2 files=3"; exit 0;;
  drift) echo "DRIFT n=1 ref=origin/main@abc bin=$2"; echo "DIFF ft-x.sh"; echo "HINT master 라이브 cp 필요"; exit 1;;
  *) exit 124;;
esac
EOF
chmod +x "$FK/drift.sh"; export FT_DRIFT_CHECK="$FK/drift.sh" DRIFT_LOG="$T/drift.log"

echo "== 사전: 짝 사본 · 줄 수 · 문법"
for f in ft_nano_record.py ft_nano_record_notify.py ft_nano_record_write.py ft-merge-lib.sh ft-critical-notify.sh ft-index-move-install.sh; do
  cmp -s "$SRC/$f" "$KIT/$f" && ok "짝 사본 bin·kit cmp0 $f" || bad "짝 사본 다름 $f"
done
for f in ft_nano_record.py ft_nano_record_notify.py ft_nano_record_write.py; do [ "$(wc -l < "$SRC/$f")" -le 200 ] && ok "≤200줄 $f" || bad "200줄 넘음 $f"; done
bash -n "$SRC/ft-merge-lib.sh" && /bin/bash -n "$SRC/ft-merge-lib.sh" && bash -n "$SRC/ft-critical-notify.sh" && ok "bash -n(/bin/bash 3.2 포함)" || bad "bash -n"
world; lap 준비

body1() {  # body1 <bin> <설치 검사 rc> <설치 검사 출력> → fm_land_notify_land 가 만든 [착지] 본문(발신·장부 함수는 가로챔)
  ( . "$1/ft-merge-lib.sh" >/dev/null 2>&1; fm_land_notify() { printf '%s\n' "$2"; }; fm_land_turn() { :; }; fm_cards_by_tokens() { :; }
    fm_land_notify_land "$ROOT" 7 abc1234 "feat r1721 x" "$2" "$3" "nano/r1721-x" )
}
c1() {  # ① PENDING → 끝에 «다음 손» · SKIP·OK = 본문 그대로
  local b="${BIN}"; E=0
  t "① PENDING 본문" [ "$(body1 "$b" 1 "x")" = "[착지] pr=7 sha=abc1234 카드 r1721 · 설치 PENDING · 다음 손: 설치 h 먼저(그 전 나노 닫기는 DRIFT 로 거절됨)" ]
  t "① SKIP 본문 그대로" [ "$(body1 "$b" 0 "")" = "[착지] pr=7 sha=abc1234 카드 r1721 · 설치 SKIP" ]
  t "① OK 본문 그대로" [ "$(body1 "$b" 0 "OK n=2 x")" = "[착지] pr=7 sha=abc1234 카드 r1721 · 설치 OK" ]
  return $E
}
mk2() {  # mk2 <꼬리표> <PR> → s·n · 카드 1장 · 현역 나노 · 장부 1줄 · drift 있음으로 landed 1회
  s="c2$1"; n="$(NN "$s")"; fresh; : > "$DRIFT_LOG"; land "$2"; card "$s"; seats "$n|nano|$s"; turn "$2" "$s"
  DRIFT_MODE=drift landed "$n" "$2" "$s" --test "$TST"
}
c2() {  # ② drift 있음 + landed(종류=닫기) → 기록은 남고 닫기 요청 0 · [설치 먼저] 1통
  local s n; mk2 "$1" 21; E=0
  t "② landed rc0 · DONE" [ "$RC" = 0 ]; t "② DONE" inc "$OUT" "DONE"; t "② NEXT 0" exc "$OUT" "NEXT "
  t "② 카드 ref 착지 줄" [ "$(nline "$s" "^- 착지: $Q")" = 1 ]; t "② 카드 ref 완료 줄" [ "$(nline "$s" "^- 완료: $n ")" = 1 ]
  t "② 닫기 요청 0" [ "$(nsent "\[완료·닫기 요청\]")" = 0 ]
  t "② [설치 먼저] 1통" [ "$(nto "$MASTER" "\[설치 먼저\] $s 착지 ${Q:0:10} — 라이브 DRIFT 1파일(ft-x.sh) · 설치 h 뒤 닫기 요청이 나갑니다")" = 1 ]
  t "② drift 검사 1회(--bin)" [ "$(grep -c -- '--bin ' "$DRIFT_LOG")" = 1 ]
  return $E
}
c3() {  # ③ ② 를 한 번 더 → [설치 먼저] 추가 0
  local s n; mk2 "$1" 22; DRIFT_MODE=drift landed "$n" 22 "$s" --test "$TST"; E=0
  t "③ 두 번째 ALREADY" inc "$OUT" "ALREADY"; t "③ [설치 먼저] 그대로 1통" [ "$(nsent "\[설치 먼저\]")" = 1 ]; t "③ 닫기 요청 0" [ "$(nsent "\[완료·닫기 요청\]")" = 0 ]
  return $E
}
c4() {  # ④ ② 뒤 drift 0 → notify 1회 = 닫기 요청 1통 · 한 번 더 = 0통
  local s n; mk2 "$1" 23; E=0
  DRIFT_MODE=ok rec notify --pr 23; t "④ notify rc0" [ "$RC" = 0 ]
  t "④ 닫기 요청 1통" [ "$(nto "$MASTER" "\[완료·닫기 요청\] $s 착지 ${Q:0:10} · 좌석 $n ")" = 1 ]
  DRIFT_MODE=ok rec notify --pr 23; t "④ 한 번 더 = 그대로 1통" [ "$(nsent "\[완료·닫기 요청\]")" = 1 ]
  return $E
}
c5() {  # ⑤ ② 뒤 drift 그대로 notify 3회 → 발신 0
  local s n k0; mk2 "$1" 24; k0="$(grep -c . "$MBOX_LOG")"; E=0
  DRIFT_MODE=drift rec notify --pr 24; DRIFT_MODE=drift rec notify --pr 24; DRIFT_MODE=drift rec notify --pr 24
  t "⑤ 발신 0(3회)" [ "$(grep -c . "$MBOX_LOG")" = "$k0" ]; t "⑤ 미룸 줄" inc "$OUT" "닫기 요청 미룸 $n $s"
  return $E
}
c6() {  # ⑥ drift 검사 rc 124 → 판정 불가 1줄 · 닫기 요청 0 · 기록은 남음
  local s="c6$1" n; n="$(NN "$s")"; fresh; land 25; card "$s"; seats "$n|nano|$s"; turn 25 "$s"; E=0
  DRIFT_MODE=to landed "$n" 25 "$s" --test "$TST"
  t "⑥ 판정 불가 drift 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '^판정 불가 drift rc=124')" = 1 ]; t "⑥ NEXT 0" exc "$OUT" "NEXT "
  t "⑥ 닫기 요청 0" [ "$(nsent "\[완료·닫기 요청\]")" = 0 ]; t "⑥ [설치 먼저] 0" [ "$(nsent "\[설치 먼저\]")" = 0 ]
  t "⑥ 완료 줄은 남음" [ "$(nline "$s" "^- 완료: $n ")" = 1 ]
  DRIFT_MODE=to rec notify --pr 25; t "⑥ notify 도 판정 불가 · 발신 0" [ "$(nsent "\[완료·닫기 요청\]")" = 0 ]; t "⑥ notify 판정 불가 줄" inc "$OUT" "판정 불가 drift rc=124"
  return $E
}
c7() {  # ⑦ 닫기 거절 «라이브 도구가 main 키트와 다르다» → [크리티컬] 다음 손 = 설치 h 먼저 — 드리프트 파일
  local n; n="$(NN "c7$1")"; fresh; E=0
  printf '{"_master":"x","_desk":"byz-planner-desk-pi#9"}\n' > "$ROOT/.fable-team/seats-planner.json"
  printf '#!/usr/bin/env bash\nprintf "DRIFT n=2 ref=origin/main@abc bin=/b\\nDIFF ft-x.sh\\nMISSING ft-y.sh\\nHINT h\\nREJECT 라이브 도구가 main 키트와 다르다 — master 라이브 cp 뒤 다시\\n"; exit 1\n' > "$T/fclose.sh"
  OUT="$(FT_MBOX_DIR="$COMM" FT_CRITICAL_STATE_DIR="$T/cst$1" bash "${BIN}/ft-critical-notify.sh" --wrap ft-nano-close "$T/fclose.sh" "$n" --landed-pr 7 2>&1)"; RC=$?
  t "⑦ 본 작업 rc 1 그대로" [ "$RC" = 1 ]
  t "⑦ desk [크리티컬] 다음 손" [ "$(nto "byz-planner-desk-pi#9" "다음 손: 설치 h 먼저 — 드리프트 파일: DIFF ft-x.sh / MISSING ft-y.sh")" = 1 ]
  return $E
}
c8() {  # ⑧ 팩 착지 카드 완성 이동 사본 → 공용 루트 표식 지움 · 워크트리 쪽 같은 이름 손 0 · rev-list 실패 = 판정 불가 줄 · 표식 손 0
  local W8="$T/w8$1" P8="$T/p8$1" G PK P0 P1 MISS=0123456789abcdef0123456789abcdef01234567 WTX; E=0
  G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
  mkdir -p "$W8/design/harness/indices/진행"; G "$W8" init -q -b main
  printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$W8/design/TEAMS.md"
  printf '# 인덱스: t\n- 설치: 있음\n- 실사건: x · 증거 mbox #1\n## 상태\n- x\n' > "$W8/design/harness/indices/진행/t.md"; G "$W8" add -A; G "$W8" commit -qm c
  WTX="$W8/.worktrees/wt"; G "$W8" worktree add -q "$WTX" -b side 2>/dev/null
  PK="$P8/feature-pack/fable-team/harness"; mkdir -p "$PK/kit/fable-team/bin"; echo v1 > "$PK/kit/fable-team/bin/x.sh"
  G "$P8" init -q -b main; G "$P8" add -A; G "$P8" commit -qm p0; P0="$(G "$P8" rev-parse HEAD)"
  echo v2 > "$PK/kit/fable-team/bin/x.sh"; G "$P8" add -A; G "$P8" commit -qm p1; P1="$(G "$P8" rev-parse HEAD)"
  mkdir -p "$W8/.fable-team/state/install-pending" "$WTX/.fable-team/state/install-pending"
  : > "$W8/.fable-team/state/install-pending/$P1.txt"; : > "$WTX/.fable-team/state/install-pending/$P1.txt"
  printf '#!/bin/bash\nexit 0\n' > "$T/fchk8"; chmod 755 "$T/fchk8"
  OUT="$(FT_INSTALL_CHECK="$T/fchk8" FT_INSTALL_RESTART_GATE=0 FT_HARNESS_ROOT="$PK" bash "${IMB:-$SRC}/ft-index-move-install.sh" "$WTX/design/harness/indices/진행/t.md" --landed "$P1" 2>&1)"; RC=$?
  t "⑧ 이동 게이트 rc0" [ "$RC" = 0 ]; t "⑧ 공용 루트 표식 지워짐" [ ! -e "$W8/.fable-team/state/install-pending/$P1.txt" ]
  t "⑧ 워크트리 쪽 같은 이름 손 0" [ -e "$WTX/.fable-team/state/install-pending/$P1.txt" ]
  : > "$W8/.fable-team/state/install-pending/$P1.txt"
  OUT="$(FT_INSTALL_CHECK="$T/fchk8" FT_INSTALL_RESTART_GATE=0 FT_HARNESS_ROOT="$PK" bash "${IMB:-$SRC}/ft-index-move-install.sh" "$WTX/design/harness/indices/진행/t.md" --landed "$MISS..$P1" 2>&1)"; RC=$?
  t "⑧ rev-list 실패 = 판정 불가 1줄" [ "$(printf '%s\n' "$OUT" | grep -c '판정 불가 — .* rev-list .* rc=[1-9]')" = 1 ]; t "⑧ rev-list 실패 표식 그대로" [ -e "$W8/.fable-team/state/install-pending/$P1.txt" ]
  return $E
}
echo "== 반례 ①~⑧"
run "① [착지] 다음 손(A1)" c1; lap ①; run "② drift = 닫기 요청 미룸(A2)" c2; lap ②; run "③ [설치 먼저] 1회(A2)" c3; lap ③
run "④ drift 0 → 미룬 요청 1통(A3)" c4; lap ④; run "⑤ drift 그대로 = 발신 0(A3)" c5; lap ⑤; run "⑥ 검사 실패 = 판정 불가(A4)" c6; lap ⑥
run "⑦ [크리티컬] 설치 h 먼저(A5)" c7; lap ⑦; run "⑧ 표식 지우기(A6 · r1738 판)" c8; lap ⑧

echo "== 변이 M1~M6(변이마다 원본 대조)"
mutm() {  # mutm <M> <파일> <옛> <새> <사례> — 전체 bin 사본에서 그 자리만 바꿔 사례 FAIL + 원본 대조 PASS
  local keep="$BIN" o mb="$T/mm-$1"; rm -rf "$mb"; cp -R "$SRC" "$mb"; rm -rf "$mb/__pycache__"
  python3 - "$mb/$2" "$3" "$4" <<'PY' || { bad "$1 변이 자리 없음"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(3)
open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  cmp -s "$SRC/$2" "$KIT/$2" || bad "$1 원본 bin·kit 다름"
  BIN="$mb"; TOOL="$mb/ft-nano-record.sh"; IMB="$mb"
  if o="$("$5" "m$1" 2>&1)"; then bad "$1 변이가 살아남음($5)"; else ok "$1 변이 → $5 FAIL ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
  BIN="$keep"; TOOL="$BIN/ft-nano-record.sh"; IMB=""
  if o="$("$5" "o$1" 2>&1)"; then ok "$1 원본 대조 → $5 PASS"; else bad "$1 원본 대조 FAIL($5)" "$o"; fi
}
mutm M1 ft-merge-lib.sh '[ "$nst" = PENDING ] && nst="PENDING' 'nst="$nst' c1
mutm M2 ft_nano_record_notify.py '    rc, names = drift(ctx)   # r1721-mut:drift' '    rc, names = 0, []' c2
mutm M3 ft_nano_record_notify.py 'if not ctx.store()["install"].get(key) and r["master"]:   # r1721-mut:once' 'if r["master"]:' c3
mutm M4 ft_nano_record_notify.py '    ctx.held = held(ctx, r)
    if ctx.held:
        return None' '    ctx.held = held(ctx, r) or "drift"
    if ctx.held:
        return None' c4
mutm M5 ft_nano_record_notify.py '    if rc != 1:   # r1721-mut:unjudged' '    if rc not in (1, 124):' c6
mutm M6 ft-index-move-install.sh '"$LRREPO" rev-list' '"$WT" rev-list' c8
lap 변이

if [ -n "${R1721_BASE:-}" ]; then
  echo "== 기준판(${R1721_BASE})"
  for c in c1 c2 c8; do
    BIN="$R1721_BASE"; TOOL="$BIN/ft-nano-record.sh"; IMB="$R1721_BASE"
    if o="$("$c" "b" 2>&1)"; then r=PASS; else r=FAIL; fi
    BIN="$SRC"; TOOL="$BIN/ft-nano-record.sh"; IMB=""
    case "$c:$r" in c8:*) echo "INFO 기준판 $c = $r (r1738 이 기준판보다 먼저 착지 — 표식 지우기는 이미 그 판에 있다)";; *:FAIL) ok "기준판 $c FAIL(정상)";; *) bad "기준판 $c PASS(시험이 못 가름)";; esac
  done
  lap 기준판
fi
for f in ft_nano_record.py ft_nano_record_notify.py ft_nano_record_write.py ft-merge-lib.sh ft-critical-notify.sh ft-index-move-install.sh; do cmp -s "$SRC/$f" "$KIT/$f" || bad "끝 bin·kit 다름 $f"; done
echo "단계별 초:$ST"
finish
