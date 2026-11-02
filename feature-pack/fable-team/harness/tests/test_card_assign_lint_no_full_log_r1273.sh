#!/usr/bin/env bash
# test_card_assign_lint_no_full_log_r1273.sh — r1273 카드 lint 배정 줄 검사: 전체 이력 git log 대신 «설치 전 추가 커밋 1개» 질문(git log -1 --until) · 반례 R1~R8 + 변이 3.
# 임시 git 리포 · 가짜 installed_at · 옛 판 질문(전체 이력 min < installed_at)을 오라클로 대조 · 실 STATE·실 좌석·네트워크 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0.
# 돌리기: ulimit -u <지금+여유>; timeout 70 bash harness/tests/test_card_assign_lint_no_full_log_r1273.sh
[ -z "${R1273_TEST_ACTIVE:-}" ] || { echo "재진입 금지 — R1273_TEST_ACTIVE 가 이미 켜져 있다"; exit 3; }; export R1273_TEST_ACTIVE=1
set -uo pipefail
export TZ=Asia/Seoul
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_CARD_ASSIGN_GIT_TIMEOUT
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; TOOL="$BIN/ft_card_assign_watch.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0=$(date +%s); STEP=""; lap() { STEP="$STEP $1=$(( $(date +%s) - T0 ))s"; T0=$(date +%s); }
NOW=$(date +%s); H=design/harness/indices; MSG='줄 없음 (새 카드 의무 · r1224)'
gc() { GIT_AUTHOR_DATE="$2 +0900" GIT_COMMITTER_DATE="$2 +0900" git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$3"; }
new_root() {  # R = git 리포(main) + 대기·진행 폴더 · INST = 가짜 installed_at(정수 초 · 인자로 바꾼다)
  R="$(mktemp -d "$T/r.XXXXXX")"; mkdir -p "$R/.fable-team/state/card-assign" "$R/$H/대기" "$R/$H/진행"
  git -C "$R" init -q -b main; printf '.fable-team/\n' > "$R/.gitignore"; git -C "$R" add .gitignore; gc "$R" "$((NOW - 200000))" init
  INST="${1:-$((NOW - 5000))}"; echo "$INST" > "$R/.fable-team/state/card-assign/installed_at"
}
add() {  # <상대경로> <커밋 epoch> — 배정 줄 없는 카드 추가 커밋(같은 바이트)
  mkdir -p "$(dirname "$R/$1")"; printf '# 카드\n- 상태: 대기\n## 상태\n- 시험\n' > "$R/$1"; git -C "$R" add "$1"; gc "$R" "$2" "add $1"
}
mv_card() { git -C "$R" mv "$1" "$2"; gc "$R" "$3" "mv $1"; }
lint() { OUT="$(cd "$R" && env FT_ROOT="$R" python3 "${TOOL_RUN:-$TOOL}" lint "$R/$1" 2>&1)"; RC=$?; }
oracle() {  # 옛 판 질문(전체 이력) — 0 = 옛 카드 · 1 = 새 카드
  local m; m="$(git -C "$R" log --no-renames --diff-filter=A --format=%ct -- "$R/$H/*/$1" | sort -n | head -1)"
  { [ -n "$m" ] && [ "$m" -lt "$INST" ]; } && echo 0 || echo 1
}
isnew() { [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -qF "$MSG" && [ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ]; }

# R1 — 설치 전 추가 · 배정 줄 없음 · 대기→진행 이동 뒤 → OK
new_root; add "$H/대기/old.md" "$((NOW - 9000))"; mv_card "$H/대기/old.md" "$H/진행/old.md" "$((NOW - 100))"; lint "$H/진행/old.md"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "R1 설치 전 추가 카드(진행 이동 뒤) 줄 없음 → OK 빈 출력" || bad "R1 rc=$RC :: $OUT"
lap R1
# R2 — 설치 뒤 추가·커밋 → REJECT(새 카드 문구 1줄)
new_root; add "$H/대기/new.md" "$((NOW - 200))"; lint "$H/대기/new.md"
isnew && ok "R2 설치 뒤 추가 카드 줄 없음 → REJECT 1줄" || bad "R2 rc=$RC :: $OUT"
lap R2
# R3 — 아직 커밋 안 된 새 카드 → REJECT
new_root; printf '# u\n- 상태: 대기\n## 상태\n' > "$R/$H/대기/unc.md"; lint "$H/대기/unc.md"
isnew && ok "R3 미커밋 새 카드 줄 없음 → REJECT 1줄" || bad "R3 rc=$RC :: $OUT"
lap R3
# R4 — 설치 전 추가 → 삭제 → 설치 뒤 같은 이름 다시 추가 → OK(옛 판과 같음)
new_root; add "$H/대기/re.md" "$((NOW - 9000))"; git -C "$R" rm -q "$H/대기/re.md"; gc "$R" "$((NOW - 8000))" rm; add "$H/대기/re.md" "$((NOW - 200))"; lint "$H/대기/re.md"
[ "$RC" = 0 ] && [ -z "$OUT" ] && [ "$(oracle re.md)" = 0 ] && ok "R4 삭제 뒤 재추가 카드 → OK(옛 판 오라클 0 과 같음)" || bad "R4 rc=$RC oracle=$(oracle re.md) :: $OUT"
lap R4
# R5 — 경계: 추가 커밋 시각 == installed_at → REJECT · 1초 전 → OK · 소수 installed_at 도 옛 판의 «<» 와 같음
new_root "$((NOW - 1000))"; add "$H/대기/eq.md" "$((NOW - 1000))"; add "$H/대기/lt.md" "$((NOW - 1001))"; lint "$H/대기/eq.md"; a="$RC:$(isnew && echo n)"; lint "$H/대기/lt.md"; b="$RC:${OUT:-empty}"
new_root; INST="$((NOW - 1001)).5"; echo "$INST" > "$R/.fable-team/state/card-assign/installed_at"  # = NOW−1000.5
add "$H/대기/fa.md" "$((NOW - 1001))"; add "$H/대기/fb.md" "$((NOW - 1000))"; lint "$H/대기/fa.md"; c="$RC"; lint "$H/대기/fb.md"; d="$RC"
[ "$a|$b|$c|$d" = "1:n|0:empty|0|1" ] && ok "R5 ct==installed_at → REJECT · ct=installed_at−1 → OK · 소수 installed_at 도 «<» 경계 같음" || bad "R5 $a|$b|$c|$d"
lap R5
# R6 — 시각 역전·가지 병합: 옛 판(전체 이력) 오라클과 같은 결과
new_root; add "$H/대기/va.md" "$((NOW - 100))"; gc "$R" "$((NOW - 9000))" child; lint "$H/대기/va.md"; va="$RC/$(oracle va.md)"      # 부모 추가가 설치 뒤 · 자식 시각이 설치 전
add "$H/대기/vb.md" "$((NOW - 9000))"; gc "$R" "$((NOW - 100))" child; lint "$H/대기/vb.md"; vb="$RC/$(oracle vb.md)"                 # 부모 추가가 설치 전 · 자식이 설치 뒤
git -C "$R" checkout -q -b A; add "$H/대기/vc.md" "$((NOW - 9000))"; git -C "$R" checkout -q main; add "$H/대기/vc.md" "$((NOW - 100))"
GIT_AUTHOR_DATE="$((NOW - 50)) +0900" GIT_COMMITTER_DATE="$((NOW - 50)) +0900" git -C "$R" -c user.name=t -c user.email=t@t merge -q --no-ff -m merge A >/dev/null 2>&1
lint "$H/대기/vc.md"; vc="$RC/$(oracle vc.md)"
[ "$va|$vb|$vc" = "1/1|0/0|1/1" ] && ok "R6 시각 역전 둘 · 설치 전 가지 A + 늦은 B 병합(경로 이력 단순화 = 첫 부모) → 옛 판과 같은 결과(1/1 · 0/0 · 1/1)" || bad "R6 $va|$vb|$vc (lint/oracle)"
lap R6
# R7 — git 실패(리포 아님) · 시간 초과(상한 env 입력) → 판정 불가 1줄 rc1 · Traceback 0 · 옛 카드로 통과 0
new_root; mkdir -p "$T/plain/$H/대기"; printf '# p\n- 상태: 대기\n## 상태\n' > "$T/plain/$H/대기/p.md"
OUT="$(cd "$T/plain" && env FT_ROOT="$R" python3 "$TOOL" lint "$T/plain/$H/대기/p.md" 2>&1)"; RC=$?; n1="$(printf '%s\n' "$OUT" | grep -c .)"
[ "$RC" = 1 ] && [ "$n1" = 1 ] && printf '%s' "$OUT" | grep -q '^배정 줄 검사 판정 불가 — git log rc=[0-9]* · 배정 줄을 넣으면 조회 0$' && ! printf '%s' "$OUT" | grep -q Traceback && r7a=1 || r7a=0
add "$H/대기/to.md" "$((NOW - 9000))"; OUT="$(cd "$R" && env FT_ROOT="$R" FT_CARD_ASSIGN_GIT_TIMEOUT=0.001 python3 "$TOOL" lint "$R/$H/대기/to.md" 2>&1)"; RC=$?; n2="$(printf '%s\n' "$OUT" | grep -c .)"
[ "$RC" = 1 ] && [ "$n2" = 1 ] && printf '%s' "$OUT" | grep -q '^배정 줄 검사 판정 불가 — git log 0.001초 초과 · 배정 줄을 넣으면 조회 0$' && ! printf '%s' "$OUT" | grep -q Traceback && r7b=1 || r7b=0
[ "$r7a$r7b" = 11 ] && ok "R7 리포 아님 rc≠0 · 시간 초과 → «배정 줄 검사 판정 불가» 1줄 rc1 · Traceback 0 · 옛 카드로 통과 0" || bad "R7 a=$r7a b=$r7b :: $OUT"
lap R7
# R8 — 배정 줄 있는 카드 → git 호출 0 · 값 꼴 그대로(좌석 이름 OK · 잘못된 꼴 REJECT)
new_root; mkdir -p "$T/stub"; printf '#!/bin/sh\necho called >> "%s/git.calls"\nexit 99\n' "$T" > "$T/stub/git"; chmod +x "$T/stub/git"; : > "$T/git.calls"
printf '# s\n- 배정: 좌석 byz-harness-nano-x#0\n## 상태\n' > "$R/$H/대기/s.md"; printf '# b\n- 배정: 아무거나\n## 상태\n' > "$R/$H/대기/b.md"
OUT="$(cd "$R" && env PATH="$T/stub:$PATH" FT_ROOT="$R" python3 "$TOOL" lint "$R/$H/대기/s.md" 2>&1)"; s=$?
OUT2="$(cd "$R" && env PATH="$T/stub:$PATH" FT_ROOT="$R" python3 "$TOOL" lint "$R/$H/대기/b.md" 2>&1)"; b=$?
[ "$s" = 0 ] && [ -z "$OUT" ] && [ "$b" = 1 ] && printf '%s' "$OUT2" | grep -q '값 꼴' && [ ! -s "$T/git.calls" ] && ok "R8 배정 줄 있는 카드 git 호출 0 · 올바른 값 OK · 잘못된 꼴 REJECT 그대로" || bad "R8 s=$s b=$b calls=$(wc -l < "$T/git.calls") :: $OUT :: $OUT2"
lap R8

# ── 변이 3 (그 칸만 다시 돈다)
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src, encoding="utf-8").read(); assert a in s, a
open(dst, "w", encoding="utf-8").write(s.replace(a, b))
PY
}
mkdir -p "$T/m1" "$T/m2" "$T/m3"; for d in m1 m2 m3; do cp "$BIN"/ft_*.py "$T/$d/"; done
mut "$TOOL" "$T/m1/ft_card_assign_watch.py" 'math.ceil(inst) - 1' 'math.ceil(inst)'
new_root "$((NOW - 1000))"; add "$H/대기/eq.md" "$((NOW - 1000))"; TOOL_RUN="$T/m1/ft_card_assign_watch.py" lint "$H/대기/eq.md"
[ "$RC" = 0 ] && ok "변이1(--until 을 ceil(installed_at) 로 · 같은 초 포함) → R5 빨강(ct==installed_at 가 OK 로)" || bad "변이1 이 R5 에 안 잡힘 rc=$RC :: $OUT"
mut "$TOOL" "$T/m2/ft_card_assign_watch.py" 'raise Undecided(why)' 'return True'
new_root; add "$H/대기/to.md" "$((NOW - 9000))"; OUT="$(cd "$R" && env FT_ROOT="$R" FT_CARD_ASSIGN_GIT_TIMEOUT=0.001 python3 "$T/m2/ft_card_assign_watch.py" lint "$R/$H/대기/to.md" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "변이2(시간 초과를 «옛 카드» 로) → R7 빨강(판정 불가 줄 없이 rc0)" || bad "변이2 가 R7 에 안 잡힘 rc=$RC :: $OUT"
mut "$TOOL" "$T/m3/ft_card_assign_watch.py" 'f"--until=@{math.ceil(inst) - 1}", ' ''
new_root; add "$H/대기/new.md" "$((NOW - 200))"; TOOL_RUN="$T/m3/ft_card_assign_watch.py" lint "$H/대기/new.md"
[ "$RC" = 0 ] && ok "변이3(--until 제거 · 아무 추가나 옛 카드) → R2 빨강(새 카드가 OK 로)" || bad "변이3 이 R2 에 안 잡힘 rc=$RC :: $OUT"
lap mutation

# bin·kit 같은 판 · 문법
cmp -s "$BIN/ft_card_assign_watch.py" "$KIT/ft_card_assign_watch.py" && ok "bin·kit ft_card_assign_watch.py 같은 내용" || bad "bin·kit 다름"
python3 -m py_compile "$TOOL" 2>/dev/null && ok "py_compile" || bad "py_compile"
echo "단계별 초:$STEP"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
