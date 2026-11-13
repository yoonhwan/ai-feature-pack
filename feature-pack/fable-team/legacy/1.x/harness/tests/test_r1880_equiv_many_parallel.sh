#!/usr/bin/env bash
# test_r1880_equiv_many_parallel.sh — r1880: ft_approval_equiv.py --many 가 후보를 4개씩 동시에 보되 출력 줄·첫 EQUIV 멈춤·rc 는 기준판(직렬) 그대로.
#   ① 후보 12 전부 NOT-EQUIV → 출력 바이트 = 직렬 기준(단건 판정을 차례로) · rc1  ② 7번째만 EQUIV → 1~7줄 · 뒤 줄 0 · rc0
#   ③ 없는 40hex 객체 → ERROR 문구 그대로 · 다른 후보 영향 0  ④ 대역 check 가 모은 스레드 id ≥ 2  ⑤ 후보 0개·40hex 아님 → rc2
#   ①②③ 은 후보 0 의 판정이 후보 1 끝난 뒤에야 끝나게 Event 로 역순 완료를 강제(M1 = 끝난 순서로 찍기 검출) · ④ 는 Barrier(4)
# 격리: 임시 리포·가짜 입력만 — 실 장부·원장·명부·라이브 bin 0 · sleep 0(대기는 Event/Barrier 상한 3초) · 변이·기준판 = FT_TEST_BIN=<bin 폴더>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_NO_LAZY_FETCH GIT_TRACE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_BIN:-$HERE/../bin}"
fail=0; rc=0; out=""; t_start=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300} err=${err:-}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# ===== 임시 리포: main B0→L1..L6→M1 · feat(L6 위) AQ · S = AQ + main 병합 · U1..U6 = B0 위 남남 커밋 =====
W="$T/w"; git -c init.defaultBranch=main init -q "$W"
g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
put() { printf '%s\n' "$2" > "$W/$1"; g add "$1"; g commit -qm "$1"; g rev-parse HEAD; }
B0="$(put base.txt base)"; L=(); for i in 1 2 3 4 5 6; do L+=("$(put "l$i.txt" "l$i")"); done
g checkout -qb feat; AQ="$(put own.txt own1)"; g checkout -q main; M1="$(put m1.txt m1)"; g update-ref refs/remotes/origin/main "$M1"
S="$(g checkout -q -B s "$AQ" && g merge -q --no-edit main && g rev-parse HEAD)"
U=(); for i in 1 2 3 4 5 6; do g checkout -q -B "u$i" "$B0"; U+=("$(put "u$i.txt" "u$i")"); done
MISS="0123456789abcdef0123456789abcdef01234567"

# 대역 구동기: 모듈을 읽어 check 를 감싼다 · stdout = many() 출력 그대로 · stderr = «REV <0|1> TIDS <n>»
cat > "$T/drive.py" <<'PY'
import importlib.util, sys, threading
spec = importlib.util.spec_from_file_location("eqv", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
mode, repo, s = sys.argv[2:5]
cands = [x for x in sys.stdin.read().split("\n") if x]
real, done, tids, ev, lk, bar = m.check, [], set(), threading.Event(), threading.Lock(), threading.Barrier(4, timeout=3)
def wrap(repo_, a, *r):
    i = cands.index(a)
    with lk:
        tids.add(threading.get_ident())
    try:
        if mode == "stub":
            if i < 4:
                bar.wait()
            if i == 6:
                return "EQUIV stub"
            raise m.No("stub %d" % i)
        return real(repo_, a, *r)
    finally:
        if i == 0:
            ev.wait(3)   # 후보 1 이 끝날 때까지 후보 0 을 붙든다(역순 완료 강제 · 직렬판이면 3초 뒤 풀림)
        with lk:
            done.append(i)
        if i == 1:
            ev.set()
m.check = wrap
rc = m.many(repo, s, "origin", "main", cands)
print("REV %d TIDS %d" % (int(0 in done and 1 in done and done.index(1) < done.index(0)), len(tids)), file=sys.stderr)
sys.exit(rc)
PY
DRV() { out="$(python3 -I "$T/drive.py" "$BIN/ft_approval_equiv.py" "$1" "$W" "$S" < "$2" 2>"$T/err")"; rc=$?; err="$(cat "$T/err")"; }
REF() {   # 직렬 기준: 단건 판정을 후보 순서대로 · 첫 EQUIV 에서 멈춤
  exp=""; erc=1
  while read -r a; do
    o="$(python3 -I "$BIN/ft_approval_equiv.py" "$W" "$a" "$S" origin main)"; r=$?
    exp+="$a $o"$'\n'; [ "$r" = 0 ] && { erc=0; break; }
  done < "$1"
}
t1=$SECONDS

# ① 12 전부 NOT-EQUIV
printf '%s\n' "${L[@]}" "${U[@]}" > "$T/c1"; REF "$T/c1"; DRV real "$T/c1"
[ "$rc" = 1 ] && [ "$erc" = 1 ] && [ "$out"$'\n' = "$exp" ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 12 ]; ck "① 12 NOT-EQUIV → 출력 바이트 = 직렬 기준 · 줄 12 · rc1" $?
[[ "$err" == "REV 1 "* ]]; ck "① 역순 완료 실재(후보 1 이 후보 0 보다 먼저 끝남)" $?
t2=$SECONDS

# ② 7번째만 EQUIV
printf '%s\n' "${L[@]}" "$AQ" "${U[@]:0:5}" > "$T/c2"; REF "$T/c2"; DRV real "$T/c2"
[ "$rc" = 0 ] && [ "$erc" = 0 ] && [ "$out"$'\n' = "$exp" ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 7 ] && [[ "$(tail -1 <<<"$out")" == "$AQ EQUIV "* ]]
ck "② 7번째 EQUIV → 1~7줄 = 직렬 기준 바이트 · 뒤 줄 0 · rc0" $?
[[ "$err" == "REV 1 "* ]]; ck "② 역순 완료 실재" $?
t3=$SECONDS

# ③ 없는 40hex 객체 섞임
printf '%s\n' "${U[0]}" "$MISS" "${L[0]}" "${U[1]}" > "$T/c3"; REF "$T/c3"; DRV real "$T/c3"
[ "$rc" = 1 ] && [ "$out"$'\n' = "$exp" ] && grep -qxF "$MISS ERROR 승인 sha ${MISS:0:10} 객체가 이 저장소에 없음(네트워크 0 — 대조 불가·재승인)" <<<"$out"
ck "③ 없는 객체 → ERROR 문구 기준 그대로 · 다른 후보 줄 = 직렬 기준 · rc1" $?
t4=$SECONDS

# ④ 동시 실행 실재(대역 check · Barrier(4) · 7번째 EQUIV 뒤 줄 0)
printf '%s\n' "${L[@]}" "$AQ" "${U[@]:0:5}" > "$T/c4"; DRV stub "$T/c4"
n="$(sed -n 's/.*TIDS \([0-9]*\).*/\1/p' <<<"$err")"
[ "${n:-0}" -ge 2 ]; ck "④ 대역 check 스레드 id ≥ 2 (받은 값: ${n:-없음})" $?
exp=""; for i in 0 1 2 3 4 5; do exp+="${L[$i]} NOT-EQUIV stub $i"$'\n'; done; exp+="$AQ EQUIV stub"
[ "$rc" = 0 ] && [ "$out" = "$exp" ]; ck "④ 대역 출력 = 후보 순서 1~7줄 · 뒤 줄 0 · rc0" $?
t5=$SECONDS

# ⑤ 입력 오류
: > "$T/c5"; python3 -I "$BIN/ft_approval_equiv.py" --many "$W" "$S" origin main < "$T/c5" >/dev/null; rc=$?; [ "$rc" = 2 ]; ck "⑤ 후보 0개 → rc2" $?
python3 -I "$BIN/ft_approval_equiv.py" --many "$W" "$S" origin main <<<"nothex" >/dev/null; rc=$?; [ "$rc" = 2 ]; ck "⑤ 40hex 아님 → rc2" $?
t6=$SECONDS

cmp -s "$BIN/ft_approval_equiv.py" "$BIN/../kit/fable-team/bin/ft_approval_equiv.py" || [ -n "${FT_TEST_BIN:-}" ]; ck "정본 미러 cmp0(bin ↔ kit)" $?
echo "단계별 초: 픽스처 $((t1 - t_start)) · ① $((t2 - t1)) · ② $((t3 - t2)) · ③ $((t4 - t3)) · ④ $((t5 - t4)) · ⑤ $((t6 - t5)) · 전체 $((SECONDS - t_start))"
echo "fail=$fail"; [ "$fail" = 0 ]
