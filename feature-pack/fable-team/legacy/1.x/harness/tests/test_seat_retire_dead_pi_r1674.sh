#!/usr/bin/env bash
# test_seat_retire_dead_pi_r1674.sh — r1674: PI ADAPTER 세 갈래 — 이미 죽은(세션 없음) pi 좌석은 NORECORD 로 은퇴를 계속하고, 살아 있는 좌석의 결속 판정 불가는 지금처럼 거절하며, tmux 확인 실패는 «판정 불가»(죽음으로 치지 않는다).
#   ⓐ 죽은 pi 좌석(has-session rc1) → RETIRED + `NORECORD <구> pi 좌석 tmux 없음 — 산출 커밋 보존` · rc0 · 명부 _replaced_by·역할 칸 옮김
#   ⓑ 살아 있는 pi 좌석(rc0) ∧ 결속 판정 불가 → REJECT rc1 · «Pi 결속 판정 불가» · 쓰기 0
#   ⓒ tmux 확인 실패(rc2 · 명령 없음) → REJECT rc1 · «Pi tmux 확인 실패» · 쓰기 0(«없음» 으로 치지 않는다)
#   ⓓ 기록 갈래(--record-only --keep-existing) 도 같은 규칙 — NORECORD 1줄 · rc0 · 옛 기록 보존 · 명부 쓰기 0
#   ⓔ 회귀 — claude 좌석 경로 불변(pi 갈래 안 탐) · 짝 cmp0 · bash -n
#   ⓕ 범위 보탬 1(planner#261 · #284446) — deaths-aifp 꼴 명부의 죽은 master 행(agent=pi · `_replaced_by` 없음)이 retire 길에서 막히지 않는다
#   ⓜ 변이 3/3 — ⓐ 갈래 삭제 / ⓒ 구별 삭제(판정 불가를 죽음으로) / ⓑ 생존 확인 삭제
# 모든 쓰기는 mktemp 리포·가짜 HOME·가짜 tmux(PATH 앞) 안 — 실 명부·실 tmux·실 pi 세션 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← $(printf '%s' "$1" | head -3 | tr '\n' ' ')";; esac; }
J() { jq -r "$2" "$1"; }

echo "== ⓔ 짝 cmp0 · bash -n"
cmp -s "$BIN/ft-seat-retire.sh" "$KIT/ft-seat-retire.sh" && ok "cmp ft-seat-retire.sh (bin == kit)" || bad "cmp ft-seat-retire.sh 다름"
bash -n "$BIN/ft-seat-retire.sh" && ok "bash -n ft-seat-retire.sh" || bad "bash -n ft-seat-retire.sh"

mkdir -p "$T/bin" "$T/home" "$T/resume" "$T/psess" "$T/root" "$T/fake"
cp "$BIN/ft-seat-retire.sh" "$BIN/ft_seat_bind.py" "$BIN/ft_roster_lib.py" "$BIN/ft_seat_pi.py" "$BIN/ft_seat_pi_turn.py" "$BIN/ft_seat_codex.py" "$T/bin/"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  has-session) n=""; for a in "$@"; do case "$a" in =*) n="${a#=}";; esac; done
               case "${FAKE_TMUX:-dead}" in
                 alive) exit 0;;
                 dead) echo "can't find session: $n" >&2; exit 1;;
                 sockfail) echo "error connecting to /x (Permission denied)" >&2; exit 1;;   # r1674-b1: rc1 이라도 «그 세션이 없다» 는 말이 아니면 죽음이 아니다
                 *) exit 2;;
               esac;;
  list-panes) [ "${FAKE_TMUX:-dead}" = alive ] && printf 'other-seat\t1\t/tmp\t0\n'; exit 0;;   # 세션 살아 있음 ≠ pane 결속 판정 가능
  *) exit 0;;
esac
EOF
chmod +x "$T/bin/"*.sh "$T/fake/tmux"
git -C "$T" init -q 2>/dev/null; R="$T/repo"; mkdir -p "$R/.fable-team"; git -C "$R" init -q
S="$R/.fable-team/seats.json"
row() { printf '"%s":{"role":"%s","agent":"%s","model":"m","tick":null}\n' "$1" "$2" "$3"; }   # <이름> <role> <agent>
roster() { printf '{"_master":"%s",%s}\n' "$1" "$(row "$2" "$3" "$4")"; }   # <_master> <행이름> <role> <agent>
run() { (cd "$R" && env PATH="$T/fake:$PATH" HOME="$T/home" ZC_RESUME_DIR="$T/resume" FT_ROOT="$T/root" FT_PI_SESSIONS="$T/psess" \
  FT_SEAT_REAP_BIN="$T/bin/ft-seat-reap.sh" FT_SEAT_QUIESCE_BIN="$T/bin/ft-seat-quiesce.sh" FAKE_TMUX="${FAKE_TMUX:-dead}" FT_SEAT_RETIRE_BIN="${RT:-$T/bin/ft-seat-retire.sh}" \
  bash "${RT:-$T/bin/ft-seat-retire.sh}" "$@" --seats "$S" 2>&1); }
mutate() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
txt = open(src, encoding="utf-8").read()
print(txt.count(mark)); open(dst, "w", encoding="utf-8").write(txt.replace(mark, repl))
PY
}

echo "== ⓐ 죽은 pi 좌석(tmux 세션 없음) → NORECORD 로 은퇴 계속 · rc0 · 칸 옮김"
roster 'byz-t-master-pi#1' 'byz-t-master-pi#1' master pi > "$S"
out="$(FAKE_TMUX=dead run 'byz-t-master-pi#1' 'byz-t-master-pi#2')"; rc=$?
chk "ⓐ rc 0 · RETIRED 줄 1" "$rc $(grep -c '^RETIRED byz-t-master-pi#1 -> byz-t-master-pi#2 ' <<< "$out")" "0 1"
chk "ⓐ NORECORD 사유 줄 1" "$(grep -cE '^NORECORD byz-t-master-pi#1 pi 좌석 tmux 없음 — 산출 커밋 보존' <<< "$out")" 1
chk "ⓐ 명부 구 행 은퇴 · _master 이동" "$(J "$S" '.["byz-t-master-pi#1"]|[.role,._replaced_by,._retired_role]|join(",")') $(J "$S" '._master')" "stop-ready,byz-t-master-pi#2,master byz-t-master-pi#2"
chk "ⓐ 후계 행 role master · 기록 파일 0" "$(J "$S" '.["byz-t-master-pi#2"].role') $(ls "$T/resume" | wc -l | tr -d ' ')" "master 0"

echo "== ⓑ 살아 있는 pi 좌석 ∧ 결속 판정 불가 → 지금처럼 REJECT rc1 · 쓰기 0"
roster 'byz-t-master-pi#3' 'byz-t-master-pi#3' master pi > "$S"; cp "$S" "$S.orig"; rm -f "$R/.fable-team"/*.bak-retire-*
out="$(FAKE_TMUX=alive run 'byz-t-master-pi#3' 'byz-t-master-pi#4')"; rc=$?
chk "ⓑ rc 1 · REJECT" "$rc $(cut -d' ' -f1 <<< "${out%%$'\n'*}")" "1 REJECT"
has "$out" "Pi 결속 판정 불가" "ⓑ  └ 사유에 «Pi 결속 판정 불가»"
chk "ⓑ 명부 바이트 불변 · .bak 0" "$(cmp -s "$S" "$S.orig" && echo same || echo changed) $(ls "$R/.fable-team" | grep -c 'bak-retire')" "same 0"

echo "== ⓒ tmux 확인 실패(rc2 · 명령 없음 · 소켓 연결 실패 rc1) → 판정 불가 REJECT rc1 · 쓰기 0(«없음» 으로 치지 않는다)"
for m in fail nosuch sockfail; do
  roster 'byz-t-master-pi#5' 'byz-t-master-pi#5' master pi > "$S"; cp "$S" "$S.orig"; rm -f "$R/.fable-team"/*.bak-retire-*
  case "$m" in nosuch) out="$(FT_TMUX="$T/nosuch/tmux" run 'byz-t-master-pi#5' 'byz-t-master-pi#6')";; *) out="$(FAKE_TMUX="$m" run 'byz-t-master-pi#5' 'byz-t-master-pi#6')";; esac; rc=$?
  chk "ⓒ$m rc 1 · REJECT" "$rc $(cut -d' ' -f1 <<< "${out%%$'\n'*}")" "1 REJECT"
  has "$out" "Pi tmux 확인 실패" "ⓒ$m  └ 사유에 «Pi tmux 확인 실패»"
  chk "ⓒ$m 명부 바이트 불변 · .bak 0" "$(cmp -s "$S" "$S.orig" && echo same || echo changed) $(ls "$R/.fable-team" | grep -c 'bak-retire')" "same 0"
done

echo "== ⓓ 기록 갈래(--record-only --keep-existing) 도 같은 규칙 · 옛 기록 보존"
printf '{"_master":"byz-t-master-pi#7","byz-t-master-pi#7":{"role":"stop-ready","agent":"pi","model":"m","tick":null,"_replaced_by":"byz-t-master-pi#8","_retired_role":"master"}}\n' > "$S"; cp "$S" "$S.orig"
printf '{"name":"old-keep","engine":"pi"}\n' > "$T/resume/byz-t-master-pi#7.json"; cp "$T/resume/byz-t-master-pi#7.json" "$T/keep.orig"
out="$(FAKE_TMUX=dead run 'byz-t-master-pi#7' --record-only --keep-existing)"; rc=$?
chk "ⓓ rc 0 · NORECORD 줄 1 · 사유" "$rc $(printf '%s\n' "$out" | grep -c '^NORECORD byz-t-master-pi#7 pi 좌석 tmux 없음 — 산출 커밋 보존')" "0 1"
has "$out" "기존 기록 보존 $T/resume/byz-t-master-pi#7.json" "ⓓ  └ 옛 기록 보존 안내"
chk "ⓓ 옛 기록 바이트 불변 · 명부 쓰기 0" "$(cmp -s "$T/resume/byz-t-master-pi#7.json" "$T/keep.orig" && echo same || echo changed) $(cmp -s "$S" "$S.orig" && echo same || echo changed)" "same same"

echo "== ⓔ 회귀 — claude 좌석 경로 불변(pi 갈래 안 탄다)"
roster 'byz-t-master-claude#1' 'byz-t-master-claude#1' master claude > "$S"
out="$(FAKE_TMUX=dead run 'byz-t-master-claude#1' 'byz-t-master-claude#2')"; rc=$?
chk "ⓔ rc 0 · RETIRED · pi 사유 0" "$rc $(grep -c '^RETIRED byz-t-master-claude#1 ' <<< "$out") $(grep -c 'pi 좌석 tmux 없음' <<< "$out")" "0 1 0"
chk "ⓔ claude 구 행 은퇴" "$(J "$S" '.["byz-t-master-claude#1"]|.role')" "stop-ready"

echo "== ⓕ 범위 보탬 1 — seats-aifp 꼴의 죽은 master 행(agent=pi · _replaced_by 없음)이 retire 길에서 막히지 않는다"
printf '{"_name":"Seatbelt-AIFP","_master":"aifp-pi-master-pi#0",%s,%s,%s}\n' \
  "$(row 'aifp-pi-master-pi#0' master pi)" "$(row 'aifp-ft-master-pi#1' master pi)" "$(row 'aifp-ft-master-pi#2' master pi)" > "$S"
for pair in 'aifp-ft-master-pi#1 aifp-ft-master-pi#3' 'aifp-ft-master-pi#2 aifp-ft-master-pi#4' 'aifp-pi-master-pi#0 aifp-ft-master-pi#5'; do
  set -- $pair; out="$(FAKE_TMUX=dead run "$1" "$2")"; rc=$?
  chk "ⓕ $1 → $2 rc 0 · RETIRED · NORECORD 1" "$rc $(grep -c "^RETIRED $1 -> $2 " <<< "$out") $(grep -c '^NORECORD ' <<< "$out")" "0 1 1"
  chk "ⓕ $1 은퇴 기록" "$(J "$S" ".[\"$1\"]|[.role,._replaced_by]|join(\",\")")" "stop-ready,$2"
done
chk "ⓕ _master 이 옮겨졌다" "$(J "$S" '._master')" "aifp-ft-master-pi#5"

echo "== ⓜ 변이 3/3 — 각 갈래를 지우면 그 사례가 무너진다"
SRC="$T/bin/ft-seat-retire.sh"
n="$(mutate "$SRC" "$T/bin/m1.sh" '    return (rec, why) if st == "alive" else (None, PI_DEAD if st == "dead" else "Pi tmux 확인 실패 · " + why)' '    return rec, why')"
chk "ⓜ1 표지 1줄(ⓐ 갈래 삭제)" "$n" 1
roster 'byz-t-master-pi#1' 'byz-t-master-pi#1' master pi > "$S"
out="$(RT="$T/bin/m1.sh" FAKE_TMUX=dead run 'byz-t-master-pi#1' 'byz-t-master-pi#2')"; rc=$?
chk "ⓜ1 죽은 좌석이 REJECT 로 돌아감(ⓐ FAIL)" "$rc $(grep -c '^RETIRED ' <<< "$out")" "1 0"
n="$(mutate "$SRC" "$T/bin/m2.sh" 'PI_DEAD if st == "dead" else "Pi tmux 확인 실패 · " + why' 'PI_DEAD')"
chk "ⓜ2 표지 1줄(ⓒ 구별 삭제)" "$n" 1
roster 'byz-t-master-pi#5' 'byz-t-master-pi#5' master pi > "$S"
out="$(RT="$T/bin/m2.sh" FAKE_TMUX=fail run 'byz-t-master-pi#5' 'byz-t-master-pi#6')"; rc=$?
chk "ⓜ2 판정 불가가 은퇴로 샘(ⓒ FAIL)" "$rc $(grep -c '^RETIRED ' <<< "$out")" "0 1"
n="$(mutate "$SRC" "$T/bin/m3.sh" '    rec, why = pi_seat_resume(seat, model, retired_by); st = "alive" if rec else pi_tmux_state(seat)' '    rec, why = pi_seat_resume(seat, model, retired_by); st = "alive" if rec else "dead"')"
chk "ⓜ3 표지 1줄(생존 확인 삭제)" "$n" 1
roster 'byz-t-master-pi#3' 'byz-t-master-pi#3' master pi > "$S"
out="$(RT="$T/bin/m3.sh" FAKE_TMUX=alive run 'byz-t-master-pi#3' 'byz-t-master-pi#4')"; rc=$?
chk "ⓜ3 산 좌석이 은퇴로 샘(ⓑ FAIL)" "$rc $(grep -c '^RETIRED ' <<< "$out")" "0 1"
n="$(mutate "$SRC" "$T/bin/m4.sh" '(r.stderr or "").strip().startswith(PI_ABSENT)' 'True')"
chk "ⓜ4 표지 1줄(stderr 검사 삭제)" "$n" 1
roster 'byz-t-master-pi#5' 'byz-t-master-pi#5' master pi > "$S"
out="$(RT="$T/bin/m4.sh" FAKE_TMUX=sockfail run 'byz-t-master-pi#5' 'byz-t-master-pi#6')"; rc=$?
chk "ⓜ4 소켓 연결 실패가 은퇴로 샘(ⓒsockfail FAIL)" "$rc $(grep -c '^RETIRED ' <<< "$out")" "0 1"
chk "ⓜ3 본 파일 복구(변이는 사본에서만)" "$(cmp -s "$SRC" "$BIN/ft-seat-retire.sh" && echo same || echo changed)" same

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
