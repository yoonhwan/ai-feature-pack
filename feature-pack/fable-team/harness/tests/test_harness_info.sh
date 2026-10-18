#!/usr/bin/env bash
# test_harness_info.sh — ft-harness-info.sh 조회 명령 시험: usage·map(없으면 REJECT)·rules·seats(가짜 tmux)·find. 읽기 전용.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="$HERE/../../harness/bin/ft-harness-info.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$S" && ok "bash -n" || bad "bash -n"

bash "$S" >/dev/null 2>&1; [ $? -eq 2 ] && ok "인자 없음 → usage rc=2" || bad "usage rc"
bash "$S" bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "모르는 명령 → rc=2" || bad "bogus rc"
bash "$S" find >/dev/null 2>&1; [ $? -eq 2 ] && ok "find 키워드 없음 → rc=2" || bad "find usage rc"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
FT_SKILL_DIR="$T/none" bash "$S" map >/dev/null 2>&1; [ $? -eq 1 ] && ok "지도 없음 → REJECT rc=1(폴백 0)" || bad "map 없음 rc"

mkdir -p "$T/ref"; printf '# 지도 시험\n' > "$T/ref/x"; mkdir -p "$T/s/references"; printf '# 지도 시험\n' > "$T/s/references/harness-map.md"
out="$(FT_SKILL_DIR="$T/s" bash "$S" map)"; [ "$out" = "# 지도 시험" ] && ok "map 출력" || bad "map 출력: $out"

rules="$(bash "$S" rules)"; echo "$rules" | grep -q "harness-map.md" && ok "rules 목록에 지도 포함" || bad "rules 목록"

# seats: 가짜 tmux 를 PATH 앞에 둔다
mkdir -p "$T/bin"
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'byz-cfo-master-claude#53\nFB_CFO#52\n'
EOF
chmod +x "$T/bin/tmux"
seats="$(PATH="$T/bin:$PATH" bash "$S" seats)"
echo "$seats" | grep -q "byz-cfo-master-claude#53 *PASS" && ok "seats 신 이름 PASS" || bad "seats PASS: $seats"
echo "$seats" | grep -q "FB_CFO#52 *REJECT" && ok "seats 구 이름 REJECT" || bad "seats REJECT: $seats"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "fail=$fail"
exit "$fail"
