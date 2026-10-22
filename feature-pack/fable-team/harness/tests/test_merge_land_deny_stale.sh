#!/usr/bin/env bash
# test_merge_land_deny_stale.sh — r755: «착지 금지 가지» 목록(ft-merge-deny.txt) + ft-merge-land 결속 시험
#   임시 origin(bare)+clone · gh 는 스텁 — 실 gh·실 원격·실 push 0 (ⓘ)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$BIN/../kit/fable-team/bin"; LAND="$BIN/ft-merge-land.sh"; DENY="$BIN/ft-merge-deny.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state" "$T/.fable-team" "$T/deny" "$T/red"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
cat > "$T/gh-stub" <<'EOF'
#!/bin/bash
[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }
case "$1" in pr-comment|pr-close) ;; *) echo "BADVERB $*" >> "$STUB_LOG"; echo "REJECT usage" >&2; exit 2;; esac
body=""; for a in "$@"; do [ -f "$a" ] && body="$(cat "$a")"; done
echo "$* :: $body" >> "$STUB_LOG"
EOF
chmod +x "$T/gh-stub"
omain() { sha "$ORIGIN" refs/heads/main; }
pushpr() {  # pushpr <PR번호> <가지> [시작점] — W 의 그 가지를 origin refs/pull/N/head 로 밀고 PR JSON(headRefName 포함) 작성
  [ $# -ge 3 ] && git -C "$W" checkout -q -B "$2" "$3"
  git -C "$W" push -q origin "$2:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"headRefName":sys.argv[2],"title":"feat: PR "+sys.argv[3],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$2" "$1" > "$STUB_JSON"
}
landb() { local b="$1"; shift; apv "$@"; out="$(FT_MERGE_DENY_FILE="${DF:-$T/deny/name.txt}" bash "$b" "$@" --repo "$W" 2>&1)"; rc=$?; }

# ===== 사전: 도구 자체 · 짝 사본 · 기본 목록 =====
bash -n "$DENY"; ck "bash -n ft-merge-deny.sh" $?
bash -n "$LAND"; ck "bash -n ft-merge-land.sh" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄(기존 상한 유지)" $?
for f in ft-merge-land.sh ft-merge-deny.sh ft-merge-deny.txt; do cmp -s "$BIN/$f" "$KIT/$f"; ck "짝 사본 cmp0 $f" $?; done
[ "$(grep -c . "$BIN/ft-merge-deny.txt")" -ge 1 ] && grep -qE '^\^feat/v6-realtime-live\$[[:space:]]+-$' "$BIN/ft-merge-deny.txt"; ck "기본 목록에 ^feat/v6-realtime-live$ 1줄(끝 sha '-')" $?
printf '# 시험 목록\n^big\t-\n' > "$T/deny/name.txt"; printf '# 주석만\n# ^big\t-\n' > "$T/deny/empty.txt"
printf '^big -\n' > "$T/deny/notab.txt"; printf '^big\txyz\n' > "$T/deny/badsha.txt"

# main 에 한 줄 더 — big 가지가 이 main 을 «합쳐서» 착지하는 것이 원래 구멍(카드 배경)
printf 'l1\nMAIN-LINE\nl2\nl3\n' > "$W/a.txt"; cm "$W" "main adds"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
M1="$(omain)"

# ===== ⓐ 빨강: 옛 판(origin/main) ft-merge-land 는 main 을 품은 거대 가지만 보면 착지한다 =====
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"; PFX="$(cd "$HERE/.." && pwd)"; PFX="${PFX#$TOP/}"
for f in "$BIN"/*; do ln -s "$f" "$T/red/$(basename "$f")"; done; rm -f "$T/red/ft-merge-land.sh"
git -C "$TOP" show "origin/main:$PFX/kit/fable-team/bin/ft-merge-land.sh" > "$T/red/ft-merge-land.sh" || { echo "FAIL 옛 판을 못 꺼냄"; exit 1; }
[ -s "$T/red/ft-merge-land.sh" ] || { echo "FAIL 옛 판이 비었다"; exit 1; }
git -C "$W" checkout -q -B big origin/main; for i in 1 2 3; do echo "big$i" > "$W/big$i.txt"; cm "$W" "big $i"; done
git -C "$W" fetch -q origin; git -C "$W" merge -q --no-edit origin/main; BIG1="$(sha "$W" HEAD)"
pushpr 1 big
landb "$T/red/ft-merge-land.sh" 1 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain)" != "$M1" ]; ck "ⓐ 빨강(옛 판): main 을 품은 big 가지가 그대로 착지(구멍 재현)" $?
M2="$(omain)"

# ===== ⓑ 후판: 같은 꼴(방금 착지한 main 을 합친 big) → 이름 검사로 REJECT · 쓰기 0 =====
git -C "$W" fetch -q origin; git -C "$W" checkout -q big; git -C "$W" merge -q --no-edit origin/main; BIG2="$(sha "$W" HEAD)"
pushpr 2 big; : > "$STUB_LOG"
landb "$LAND" 2 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [[ "$out" == *"착지 금지 가지(big"* ]] && [[ "$out" == *"목록 $T/deny/name.txt:2"* ]] && [ "$(omain)" = "$M2" ] && [ ! -s "$STUB_LOG" ]
ck "ⓑ 후판: 착지 금지 가지 big → REJECT(목록 파일:줄) · main 불변 · PR 쓰기 0" $?
printf '# 시험 목록 — 커밋 품기(big 이름 + 끝 sha)\n^big\t%s\n' "$BIG2" > "$T/deny/anc.txt"

# ===== ⓒ 이름이 달라도 금지 가지의 커밋을 조상으로 품으면 REJECT =====
git -C "$W" checkout -q -B feat-x origin/main; git -C "$W" merge -q --no-edit big; echo x > "$W/x.txt"; cm "$W" "feat-x work"
pushpr 3 feat-x; DF="$T/deny/anc.txt" landb "$LAND" 3 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [[ "$out" == *"착지 금지 가지의 커밋 ${BIG2:0:10} 을 품음"* ]] && [ "$(omain)" = "$M2" ] && [ ! -s "$STUB_LOG" ]
ck "ⓒ feat-x 가 big 의 커밋 ${BIG2:0:10} 을 품음 → REJECT · main 불변 · 쓰기 0" $?

# ===== ⓓ 목록 밖 보통 가지 = 지금과 같음(착지) =====
git -C "$W" checkout -q -B feat-y origin/main; echo y > "$W/y.txt"; cm "$W" "feat-y work"; pushpr 4 feat-y
DF="$T/deny/anc.txt" landb "$LAND" 4 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(omain)" != "$M2" ]; ck "ⓓ 목록 밖 가지(main 품음) → 지금과 같이 착지" $?
M3="$(omain)"

# ===== ⓔ 목록 없음·못 읽음 = REJECT(fail-closed) · 주석만(빈 목록) = 통과 =====
git -C "$W" checkout -q -B feat-z origin/main; echo z > "$W/z.txt"; cm "$W" "feat-z work"; pushpr 5 feat-z; : > "$STUB_LOG"
DF="$T/deny/none.txt" landb "$LAND" 5 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [[ "$out" == *"착지 금지 목록을 읽을 수 없음"* ]] && [ "$(omain)" = "$M3" ] && [ ! -s "$STUB_LOG" ]
ck "ⓔ 목록 파일 없음 → REJECT(fail-closed · 설치 누락을 조용히 통과 0) · main 불변" $?
git -C "$W" checkout -q -B feat-w origin/main; echo w > "$W/w.txt"; cm "$W" "feat-w work"; pushpr 6 feat-w
DF="$T/deny/empty.txt" landb "$LAND" 6 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "ⓔ 주석만(빈 목록) → 통과(착지)" $?
M4="$(omain)"

# ===== ⓕ 목록 꼴 = <정규식><TAB><40hex|-> · # 주석 — 꼴 오류는 REJECT =====
git -C "$W" checkout -q -B feat-v origin/main; echo v > "$W/v.txt"; cm "$W" "feat-v work"; pushpr 7 feat-v
DF="$T/deny/notab.txt" landb "$LAND" 7 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [[ "$out" == *"착지 금지 목록 꼴 오류"* ]] && [ "$(omain)" = "$M4" ]; ck "ⓕ TAB 둘째 칸 없음 → 꼴 오류 REJECT · main 불변" $?
DF="$T/deny/badsha.txt" landb "$LAND" 7 --approve-sha "$PRSHA"
[ "$rc" = 1 ] && [[ "$out" == *"착지 금지 목록 꼴 오류"* ]] && [ "$(omain)" = "$M4" ]; ck "ⓕ 둘째 칸이 40hex/'–' 아님 → 꼴 오류 REJECT · main 불변" $?
bash "$DENY" "$(sha "$W" HEAD)" --branch big --repo "$W" --deny-file "$T/deny/empty.txt"; rc=$?
[ "$rc" = 0 ]; ck "ⓕ '#' 주석 줄은 검사 대상 아님(주석 안의 ^big 은 안 걸린다)" $?
bash "$DENY" "$(sha "$W" HEAD)" --branch big --repo "$W" --deny-file "$T/deny/name.txt" >/dev/null; rc=$?
[ "$rc" = 1 ]; ck "ⓕ 이름 정규식 줄은 이름 전체 일치 — big 걸림(단독 호출 rc1)" $?
bash "$DENY" "$(sha "$W" HEAD)" --branch bigness --repo "$W" --deny-file "$T/deny/name.txt" >/dev/null; rc=$?
[ "$rc" = 0 ]; ck "ⓕ 이름 전체 일치 — bigness 는 ^big$ 에 안 걸린다" $?

# ===== ⓗ 변이: 이름 검사 삭제 → ⓑ FAIL 재현 · 조상 검사 삭제 → ⓒ FAIL 재현 =====
mutb() {  # mutb <이름> <옛 본문> <새 본문> → 변이 사본 폴더 출력
  local d="$T/mut-$1"; mkdir -p "$d"; for f in "$BIN"/*; do ln -s "$f" "$d/$(basename "$f")"; done; rm -f "$d/ft-merge-deny.sh"
  python3 - "$DENY" "$d/ft-merge-deny.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = sys.argv[3].replace("\\n", "\n").replace("\\t", "\t")
assert old in s, "변이 대상 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, sys.argv[4].replace("\\n", "\n").replace("\\t", "\t"), 1))
PY
  printf '%s' "$d"
}
MUT1="$(mutb name '  [ -z "$BR" ] || ! brhit "$pat" || rej "착지 금지 가지($BR · 목록 $DF:$LN)"' '  :')"
git -C "$W" fetch -q origin; git -C "$W" checkout -q -B big origin/main; git -C "$W" merge -q --no-edit origin/main; echo m1 > "$W/m1.txt"; cm "$W" "big again"
pushpr 8 big
landb "$MUT1/ft-merge-land.sh" 8 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "ⓗ 이름 검사 삭제 → ⓑ 가 FAIL(착지됨 = 변이로 재현)" $?
M5="$(omain)"
MUT2="$(mutb anc '  [ "$arc" -eq 1 ] && continue\n  [ "$arc" -eq 0 ] && rej "착지 금지 가지의 커밋 ${end:0:10} 을 품음(가지 ${BR:-?} · 목록 $DF:$LN)"\n  rej "착지 금지 목록의 끝 sha ${end:0:10} 를 이 리포에서 확인 못 함(가지 ${BR:-?} · 목록 $DF:$LN · 그 가지를 fetch 했나)"' '  continue')"
git -C "$W" fetch -q origin; git -C "$W" checkout -q -B feat-x2 origin/main; git -C "$W" merge -q --no-edit big; echo m2 > "$W/m2.txt"; cm "$W" "feat-x2"
printf '# 커밋 품기(변이용) — big 이름 + 끝 sha\n^big\t%s\n' "$M5" > "$T/deny/anc2.txt"; pushpr 9 feat-x2
DF="$T/deny/anc2.txt" landb "$MUT2/ft-merge-land.sh" 9 --approve-sha "$PRSHA"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "ⓗ 조상 검사 삭제 → ⓒ 가 FAIL(착지됨 = 변이로 재현)" $?

# ===== ⓘ 격리: 실 PR·실 push 0 — 모든 원격은 임시 bare 하나뿐 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "ⓘ 격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
grep -qv BADVERB "$STUB_LOG"; ck "ⓘ gh 스텁 밖 동사 호출 0" $?

echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
