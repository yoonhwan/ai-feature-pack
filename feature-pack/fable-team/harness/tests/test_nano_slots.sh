#!/usr/bin/env bash
# test_nano_slots.sh — C6 슬롯 정정 시험: ①노는 석≠빈 석 ②머리줄 없는 카드 제외 ③예약석 1 비어 있음
# 가짜 seats·카드 디렉터리·가짜 tmux/ft-seat-status 만 쓴다 — 실제 seats 파일·나노 세션은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$BIN/ft-nano-slots.sh" && bash -n "$BIN/ft-nano-spawn.sh" && ok "bash -n 2종" || bad "bash -n"

# 가짜 bin: 스크립트 사본 + 가짜 ft-seat-status(좌석 이름별 고정 출력) + 가짜 tmux(살아 있는 세션 = live.txt)
mkdir -p "$T/bin" "$T/idx/대기"
cp "$BIN/ft-nano-slots.sh" "$T/bin/"
cat > "$T/bin/ft-seat-status.sh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  idle*) echo "IDLE 2020-01-01T00:00:00Z" ;;
  *)     echo "WORKING 2999-01-01T00:00:00Z" ;;
esac
EOF
cat > "$T/bin/tmux" <<EOF
#!/usr/bin/env bash
cat "$T/live.txt"
EOF
chmod +x "$T/bin/"*

card() {  # card <파일> <머리줄 수 4|2> [상태값] [Issue값]
  { echo "# 인덱스: $1"
    echo "Issue: ${4:-#7}"
    [ "$2" = 4 ] && { echo "상태: ${3:-대기}"; echo "선행: 없음"; echo "시험 입력: 없음"; }
    echo "## 구현 범위"; echo "x"; } > "$T/idx/대기/$1.md"
}
run() { (cd "$HERE/../.." && PATH="$T/bin:$PATH" FT_SEATS_JSON="$T/seats.json" FT_INDEX_DIR="$T/idx" bash "$T/bin/ft-nano-slots.sh" "$@" 2>&1); }

# 케이스 1 — 노는 석이 빈 석으로 안 세어진다: 상한 5, 일하는 석 2 + 노는 석 3 = 점유 5 → 빈 석 0 · spawn 지시 없음
cat > "$T/seats.json" <<'EOF'
{"w1":{"role":"nano"},"w2":{"role":"nano"},"idle1":{"role":"nano"},"idle2":{"role":"nano"},"idle3":{"role":"nano"}}
EOF
printf 'w1\nw2\nidle1\nidle2\nidle3\n' > "$T/live.txt"
card ok-card 4
out="$(run)"
echo "$out" | grep -q 'SLOTS nano 점유 5/5 (일하는 석 2 · 노는 석 3) · 빈 석 0' && ok "1 노는 석 3 = 점유 · 빈 석 0 (상한 5)" || bad "1 SLOTS 줄: $(echo "$out" | head -1)"
echo "$out" | grep -q 'ft-nano-spawn.sh' && bad "1 빈 석 0 인데 spawn 지시 출력" || ok "1 빈 석 0 → spawn 지시 0"
echo "$out" | grep -q '노는 석 idle1' && ok "1 노는 석은 «푸는 대상» 으로 표시" || bad "1 노는 석 표시 없음"

# 케이스 2 — 머리줄 없는 카드는 후보에서 제외(REJECT 아님) + 사유 1줄, 충족 카드는 후보
echo '{"w1":{"role":"nano"}}' > "$T/seats.json"; printf 'w1\n' > "$T/live.txt"
card ok-card 4; card bare-card 2
out="$(run)"
echo "$out" | grep -q 'ft-nano-spawn.sh .*ok-card.md' && ok "2 머리줄 충족 카드 = 후보" || bad "2 ok-card 후보 없음"
echo "$out" | grep -q 'ft-nano-spawn.sh .*bare-card.md' && bad "2 머리줄 없는 카드가 후보" || ok "2 머리줄 없는 카드 후보 제외"
[ "$(echo "$out" | grep -c '후보 제외 1장')" = 1 ] && echo "$out" | grep -q 'bare-card.md(머리줄 없음: 상태·선행·시험 입력)' && ok "2 제외 사유 1줄(누락 키 명시)" || bad "2 제외 사유 줄: $(echo "$out" | grep '후보 제외')"
FT_ACTIVE_ISSUES="#99" run | grep -q 'ok-card.md(비활성 Issue #7)' && ok "2 활성 Issue 밖 카드 제외" || bad "2 활성 Issue 필터"

# 케이스 3 — 예약석 1 비어 있음: 일반 5석이 꽉 차도 예약석은 «비어 있음» · 라이브 카드만 예약석 후보 · 점유 시 예약석이 상한을 먹지 않음
cat > "$T/seats.json" <<'EOF'
{"a":{"role":"nano"},"b":{"role":"nano"},"c":{"role":"nano"},"d":{"role":"nano"},"e":{"role":"nano"}}
EOF
printf 'a\nb\nc\nd\ne\n' > "$T/live.txt"
card live-card 4 "라이브 대기"; card ok-card 4
out="$(run)"
echo "$out" | grep -q '점유 5/5 .* 빈 석 0 · 예약석 비어 있음' && ok "3 일반 5/5 꽉 참 + 예약석 비어 있음" || bad "3 SLOTS 줄: $(echo "$out" | head -1)"
echo "$out" | grep -A1 '예약석(+1' | grep -q 'live-card.md' && ok "3 라이브 카드만 예약석 후보" || bad "3 예약석 후보 없음"
cat > "$T/seats.json" <<'EOF'
{"a":{"role":"nano"},"b":{"role":"nano"},"c":{"role":"nano"},"d":{"role":"nano"},"r":{"role":"nano","reserved":true}}
EOF
printf 'a\nb\nc\nd\nr\n' > "$T/live.txt"
run | head -1 | grep -q '점유 4/5 .* 빈 석 1 · 예약석 점유 r' && ok "3 예약석 점유자는 상한을 먹지 않음(점유 4/5)" || bad "3 예약석 점유 줄: $(run | head -1)"

# 실제 seats 파일 무변경 확인은 완료 조건 쪽(git status) — 이 시험은 FT_SEATS_JSON 가짜만 읽는다
echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"
exit "$fail"
