#!/usr/bin/env bash
# test_baseline_lint.sh — C20 카드 머리줄 «기준값:» 검사 3케이스: ①값 있음 ②없음 → 대체 축 ③빈칸·줄 없음
# 가짜 seats·임시 카드·가짜 ft-index-lint 만 쓴다 — --dry-run 이라 spawn·gh·카드 수정 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n ft-nano-spawn.sh" || bad "bash -n"

# 가짜 bin: spawn 사본 + 항상 통과하는 ft-index-lint (이 시험은 기준값 줄만 본다)
mkdir -p "$T/bin" "$T/idx/대기"
cp "$BIN/ft-nano-spawn.sh" "$BIN/ft-proposal-gate.sh" "$BIN/ft_raised.py" "$BIN/ft_teamset.py" "$BIN/ft_spawn_queue.py" "$BIN/ft-team-lib.sh" "$T/bin/"   # ft_raised.py = 상향 모델 판정(R149) — spawn 이 부르는 형제
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ft-index-lint.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ft-resource-gate.sh"   # spawn 입구 자원 문지기(Res-1014) — 사본 폴더에 없으면 spawn 이 경고 줄 전에 죽어 3a·3b 가 FAIL 한다. 이 시험은 기준값 줄만 본다
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/ft-all-stop.sh"   # r626 DA⑥ r2: spawn 이 .fable-team 있으면 늘 전팀 정지 check — 사본 폴더에 없으면 REJECT 로 죽는다. 이 시험은 기준값 줄만 본다
. "$HERE/lib/fake_tmm.sh"; fake_tmm "$T/fake" byz-v65-master-claude#1   # r975 r4: 살아 있는 좌석 목록 대역(실 tmm 누출 0)
. "$HERE/lib/bin_source_deps.sh"; copy_source_deps "$BIN" "$T/bin" || bad "r686 사본 source 대상 채우기"   # r686: spawn 이 source 하는 같은 폴더 lib(r672 research-seat …) — 이름 골라 복사하면 빠진다
echo '{"_master":"byz-harness-master-claude#1","byz-harness-master-claude#1":{"role":"master"}}' > "$T/seats.json"   # r975: 회신 대상 = 명부 _master(옛 기본값 글자 폐기)

card() {  # card <파일> [기준값 줄(통째로, 생략하면 줄 없음)]
  { echo "# 인덱스: $1"
    echo "Issue: #7"; echo "상태: 대기"; echo "선행: 없음"; echo "시험 입력: 없음"
    [ $# -ge 2 ] && echo "$2"
    echo "## 구현 범위"; echo "x"
    echo "기준값: 본문에 있는 줄은 머리줄이 아니다"; } > "$T/idx/대기/$1.md"
}
run() { (cd "$HERE/../.." && PATH="$T/fake:$PATH" FT_TEAMSET=0 FT_SEATS_JSON="$T/seats.json" bash "$T/bin/ft-nano-spawn.sh" "$T/idx/대기/$1.md" --dry-run 2>&1); }
warned() { echo "$1" | grep -q 'WARN 후보 제외 — 카드 머리줄 기준값 없음 또는 빈칸'; }

# 케이스 1 — 기준값 있음: 경고 없음
card has-value "기준값: 첫 원문 p90 2.8초 (n=10)"
out="$(run has-value)"
warned "$out" && bad "1 기준값 있는데 경고: $(echo "$out" | grep WARN)" || ok "1 기준값 있음 → 기준값 경고 0"

# 케이스 2 — 없음 → 대체 축: 값이 있는 줄이므로 경고 없음
card no-metric "기준값: 없음 → 대체 축 재현 명령 종료코드"
out="$(run no-metric)"
warned "$out" && bad "2 없음→대체 축인데 경고: $(echo "$out" | grep WARN)" || ok "2 없음 → 대체 축 → 기준값 경고 0"

# 케이스 3 — 빈칸 / 줄 없음: 경고(REJECT 아님: 4줄 머리줄 경고와 같은 방식 · 출력에 REJECT 카드사유 없음)
card blank "기준값:   "
out="$(run blank)"
warned "$out" && ok "3a 기준값 빈칸 → 후보 제외 경고" || bad "3a 빈칸 경고 없음"
echo "$out" | grep -q 'REJECT 인덱스\|REJECT lint' && bad "3a 경고인데 REJECT" || ok "3a REJECT 아님(lint/인덱스 REJECT 0)"
card absent
out="$(run absent)"
warned "$out" && ok "3b 기준값 줄 없음(본문에만 있음) → 후보 제외 경고" || bad "3b 줄 없음 경고 없음"

# 기존 4줄 머리줄 경고는 그대로(현행 동작 보존): 4줄 다 있으면 그 경고 0
echo "$out" | grep -q '카드 머리줄 없음:' && bad "4줄 머리줄 충족 카드에 기존 경고 출력" || ok "기존 4줄 머리줄 경고 무영향"

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
