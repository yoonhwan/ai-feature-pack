#!/usr/bin/env bash
# r2386_mut.sh — r2386 변이 도우미(사본에서만 고친다 · 원본 bin 은 읽기만). source 해서 쓴다.
#   mut <이름> <옛 줄=>새 줄> : 사본에 한 줄 치환(python 정확 치환 · 대상 없으면 실패)
#   ex <변이 이름> <사례 함수> <설명> : 변이 사본에서는 그 시험이 FAIL, 원본으로 돌리면 PASS(줄 끝 = 그 변이 초)
# shellcheck shell=bash
MUTD="$T/mut"; mkdir -p "$MUTD"
MUT="$MUTD/ft-live-bin-drift-check.sh"
ORIG="$SUT"
mut() { # mut <이름> <옛 줄=>새 줄> — 사본만 고친다(원본 무변경)
  local okp=1; cp -p "$ORIG" "$MUT"
  python3 - "$MUT" "$2" <<'PY' || okp=0
import sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old, new = (x.strip() for x in expr.split("=>", 1))
if old not in s:
    sys.exit(f"변이 대상 없음: {old!r}")
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  [ "$okp" = 1 ] || { echo "FAIL $1 변이 적용 실패"; fail=$((fail + 1)); return 1; }
  cmp -s "$ORIG" "$MUT" && { echo "FAIL $1 변이가 판을 안 바꿈"; fail=$((fail + 1)); return 1; }
  return 0
}
EXN=0
ex() { # ex <변이 이름> <사례 함수> <설명>
  local name="$1" fn="$2" desc="$3" t=$SECONDS base="$fail" mf of; EXN=$((EXN + 1))
  SUT="$MUT"; "$fn" >/dev/null 2>&1; mf=$((fail - base)); fail=$base       # 변이 쪽 FAIL 은 «잡았다» 는 증거 — 총계에서 뺀다
  SUT="$ORIG"; "$fn" >/dev/null 2>&1; of=$((fail - base)); fail=$base
  if [ "$mf" -ge 1 ] && [ "$of" -eq 0 ]; then echo "PASS $name 변이 → $desc FAIL · 원본 대조 → $desc 통과 ($((SECONDS - t))초)"
  elif [ "$mf" -eq 0 ]; then echo "FAIL $name 변이인데 $desc 가 통과 :: $MSG"; fail=$((fail + 1))
  else echo "FAIL $name 원본 대조인데 $desc 실패 :: $MSG"; fail=$((fail + 1)); fi
}
