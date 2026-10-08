#!/usr/bin/env bash
# test_evidence_inject_scan.sh — R63 ㉡ ft-evidence-inject-scan.sh 대조표 11행(인덱스 r63c) + ft-index-move 진행→완성 출력 연결.
# 임시 폴더 픽스처 + 읽기 전용 실파일 2개만 — 네트워크·Redis·브라우저 0 · 실제 indices·mbox·상태 폴더 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRCDIR="$ROOT/scripts/fable-team-bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

for f in ft-evidence-inject-scan.sh ft-index-move.sh; do bash -n "$SRCDIR/$f" && ok "bash -n $f" || bad "bash -n $f"; done

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_INDEX_STATE_DIR="$T/state"; mkdir -p "$FT_INDEX_STATE_DIR"
SCAN="$SRCDIR/ft-evidence-inject-scan.sh"
FX="$T/fx"; mkdir -p "$FX"
sc() { bash "${SCAN_BIN:-$SCAN}" "$@" 2>&1; }          # 출력 전부(stderr 포함)
cnt() { echo "$1" | sed -n "s/.*$2=\([0-9]*\).*/\1/p" | tail -1; }   # 요약 줄에서 suspect|note 값

# 1 redis-cli PUBLISH → ⓐ
printf '#!/bin/bash\nredis-cli -p 6379 PUBLISH room_events:r1 %s\n' "'{}'" > "$FX/p1.sh"
out="$(sc "$FX/p1.sh")"; echo "$out" | grep -q '^SUSPECT .*p1.sh:2 ⓐ' && ok "1 redis-cli PUBLISH → SUSPECT ⓐ" || bad "1: $out"

# 2 docker exec … redis-cli HSET → ⓐ
printf '#!/bin/bash\ndocker exec byz-redis redis-cli HSET k f v\n' > "$FX/p2.sh"
out="$(sc "$FX/p2.sh")"; echo "$out" | grep -q '^SUSPECT .*p2.sh:2 ⓐ' && ok "2 docker exec redis-cli HSET → SUSPECT ⓐ" || bad "2: $out"

# 3 /dev/bubble-replay → ⓒ
printf "page.goto(f'{BASE}/dev/bubble-replay?scenario=static')\n" > "$FX/p3.py"
out="$(sc "$FX/p3.py")"; echo "$out" | grep -q '^SUSPECT .*p3.py:1 ⓒ' && ok "3 /dev/bubble-replay → SUSPECT ⓒ" || bad "3: $out"

# 4 appendChild(.js) → ⓓ · r.xadd(.py) → ⓑ
printf 'el.appendChild(bubble)\n' > "$FX/p4.js"; printf 'r.xadd("s", {"a": 1})\n' > "$FX/p4.py"
out="$(sc "$FX/p4.js")"; o2="$(sc "$FX/p4.py")"
echo "$out" | grep -q '^SUSPECT .*p4.js:1 ⓓ' && echo "$o2" | grep -q '^SUSPECT .*p4.py:1 ⓑ' && ok "4 appendChild → ⓓ · xadd → ⓑ" || bad "4: $out / $o2"

# 5 읽기·정리·health 만 → SUSPECT 0
cat > "$FX/p5.sh" <<'EOF'
#!/bin/bash
redis-cli GET k
redis-cli --scan --pattern 'stt:*'
redis-cli DEL k
redis-cli FLUSHDB
curl -s http://127.0.0.1:8080/health
EOF
out="$(sc "$FX/p5.sh")"; [ "$(cnt "$out" suspect)" = 0 ] && ok "5 읽기·정리·health → SUSPECT 0" || bad "5: $out"

# 6 isolated_redis 파일 안 hset → NOTE 1 · SUSPECT 0
printf 'from tests.shared.prompts._real_redis import isolated_redis\nclient.hset("k", "f", "v")\n' > "$FX/p6.py"
out="$(sc "$FX/p6.py")"; [ "$(cnt "$out" note)" = 1 ] && [ "$(cnt "$out" suspect)" = 0 ] && ok "6 isolated_redis → NOTE 1 · SUSPECT 0" || bad "6: $out"

# 7 실파일: 기존 러너(trusted 클릭) 오탐 0
out="$(sc "$ROOT/tests/e2e/realtime_multi_e2e.py")"; [ "$(cnt "$out" suspect)" = 0 ] && ok "7 기존 러너 SUSPECT 0" || bad "7: $out"

# 8 실파일: 위반 실례(#887)는 ⓒ 로 잡힌다 — 원본이 이 브랜치에 있어야 한다(없으면 FAIL: 시험이 자기 근거를 잃었다)
V="$ROOT/design/feature/evidence/multilingual-linebreak-impl-20261008/run.py"
out="$(sc "$V")"; [ "$(cnt "$out" suspect)" -ge 1 ] 2>/dev/null && echo "$out" | grep -q ' ⓒ ' && ok "8 #887 run.py SUSPECT ≥ 1 (ⓒ)" || bad "8: $out"

# 9 없는 경로 → rc=1 · MISSING / 인자 0 → rc=2
out="$(bash "$SCAN" "$T/nope" 2>&1)"; rc=$?; [ "$rc" = 1 ] && echo "$out" | grep -q '^MISSING ' && ok "9 없는 경로 rc=1 · MISSING" || bad "9: rc=$rc $out"
bash "$SCAN" >/dev/null 2>&1; [ "$?" = 2 ] && ok "9b 인자 0 → rc=2" || bad "9b"

# 9c SUSPECT 있으면 로그 1줄 append · SUSPECT 0 이면 안 쓴다
n1="$(wc -l < "$FT_INDEX_STATE_DIR/inject-scan.log" 2>/dev/null | tr -d ' ')"; sc "$FX/p5.sh" >/dev/null; n2="$(wc -l < "$FT_INDEX_STATE_DIR/inject-scan.log" | tr -d ' ')"
[ -n "$n1" ] && [ "$n1" -ge 1 ] && [ "$n1" = "$n2" ] && grep -q 'INJECT-SCAN files=' "$FT_INDEX_STATE_DIR/inject-scan.log" && ok "9c SUSPECT 시 log append · 0건이면 무기록" || bad "9c: n1=$n1 n2=$n2"

# 10 진행→완성 이동: SUSPECT 줄 출력 · rc=0 · 카드 완성/ 이동
BIN="$T/bin"; mkdir -p "$BIN"; cp "$SRCDIR/ft-index-move.sh" "$SRCDIR/ft-index-move-canon.sh" "$SCAN" "$BIN/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ft-index-lint.sh"
export FT_SEATS_JSON="$T/none.json" FT_MBOX=/bin/true
REPO="$T/repo"; IDX="$REPO/design/harness/indices"; mkdir -p "$IDX"/{대기,진행,완성} "$REPO/design/x/evidence/e1"
git -C "$REPO" init -q -b main . && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
cp "$FX/p3.py" "$REPO/design/x/evidence/e1/run.py"
git -C "$REPO" add -A && git -C "$REPO" commit -qm evidence
# 카드는 미추적으로 둔다(ft-index-move 는 추적 카드에 cwd 기준 git mv — 임시 리포 밖 cwd 에서 실패)
printf '# 인덱스: k10\n## 상태\n- 정본 영향 없음: 하네스 도구와 시험만 변경 — 제품 정본 없음\n증거: design/x/evidence/e1/run.py\n' > "$IDX/진행/k10.md"
printf '# 판정문\n## §1 닫힘: k10\n대상 카드: k10\n' > "$REPO/da10.md"
out="$(bash "$BIN/ft-index-move.sh" "$IDX/진행/k10.md" 완성 --da "$REPO/da10.md#§1" --seat s 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/완성/k10.md" ] && echo "$out" | grep -q '^SUSPECT .*run.py:1 ⓒ' && echo "$out" | grep -q '^MOVED' && ok "10 완성 이동: SUSPECT 출력 · rc=0 · 이동" || bad "10: rc=$rc $out"

# 10b 스캐너 실행 불가여도 이동은 계속 + stderr ERROR 1줄 (보이게 · 차단 0)
printf '# 인덱스: k10b\n## 상태\n- 정본 영향 없음: 하네스 도구와 시험만 변경 — 제품 정본 없음\n증거: design/x/evidence/e1/run.py\n' > "$IDX/진행/k10b.md"; rm "$BIN/ft-evidence-inject-scan.sh"
# 판정문에 k10b 이름을 추가(절-카드 결속 R37)
printf '대상 카드: k10b\n' >> "$REPO/da10.md"
out="$(bash "$BIN/ft-index-move.sh" "$IDX/진행/k10b.md" 완성 --da "$REPO/da10.md#§1" --seat s 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ -f "$IDX/완성/k10b.md" ] && echo "$out" | grep -q '^ERROR inject-scan rc=' && ok "10b 스캐너 실패 → ERROR 1줄 · 이동 계속" || bad "10b: rc=$rc $out"
cp "$SCAN" "$BIN/"

# 11 변이: ⓒ 패턴을 지운 복사본 → #3 이 FAIL(음성 대조)
SCAN_BIN="$T/mut.sh"; sed "s|^PAT_C=.*|PAT_C='ZZZ_NEVER_MATCHES_ZZZ'|" "$SCAN" > "$SCAN_BIN"
out="$(sc "$FX/p3.py")"; echo "$out" | grep -q '^SUSPECT .* ⓒ' && bad "11 변이 복사본이 여전히 ⓒ 를 잡는다(음성 대조 실패): $out" || ok "11 변이(ⓒ 제거) → #3 SUSPECT 안 나옴(음성 대조)"
unset SCAN_BIN

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
