#!/usr/bin/env bash
# test_squash_tail_code_automerge_r1278.sh — r1278: squash 끝줄을 읽는 두 곳(ft-nano-close _lp_lastline · ft-press-gate _squash_heads)이
#   r1270 의 새 꼬리 «main 자동 병합(코드 · 승인 EQUIV) C=<40hex>» 1줄도 건너뛰고 그 앞 «PR #N (head X)» 를 끝줄로 본다(옛 문서 꼬리 그대로).
# 함수 본문만 파일에서 떼어 임시 리포(커밋 메시지 꼴만)에 돌린다 — 실 리포·tmux·gh·네트워크 0 · 자기 재호출 0 · 고정 sleep 0.
# R1 코드 꼬리 → 두 곳 모두 끝줄 «PR #7 (head X)» / X 수집   R2 문서 꼬리(옛 꼴) → 같음   R3 꼬리 없음(옛 착지) → 같음
# R4 코드 꼬리 · C= 짧은 sha → 건너뜀 0 · 후보 0   R5 꼬리 문구가 한 글자 다름 → 건너뜀 0 · 후보 0   R6 코드 꼬리 2줄 → 1줄만 건너뜀 → 후보 0
# 변이 1 nano-close 코드 꼬리 갈래 무력화 → R1 FAIL   변이 2 press-gate 코드 꼬리 갈래 무력화 → R1 FAIL   bin == kit cmp0
set -uo pipefail
[ -z "${FT_R1278_TEST_ACTIVE:-}" ] || { echo "재진입 차단"; exit 9; }; export FT_R1278_TEST_ACTIVE=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"

R="$T/repo"; git init -q -b main "$R"
g() { git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
g commit -q --allow-empty -m init
X="$(printf '%040d' 0 | tr 0 a)"; Y="$(printf '%040d' 0 | tr 0 c)"
CODE="main 자동 병합(코드 · 승인 EQUIV) C=$Y"; DOC="main 자동 병합(문서 전용 · 겹침 0) C=$Y"
INIT="$(g rev-parse main)"
mkc() { local tree c; tree="$(g rev-parse "$INIT^{tree}")"; c="$(g commit-tree "$tree" -p "$INIT" -m "$1")"; g update-ref refs/heads/main "$c"; }   # 칸마다 init 위 커밋 1개

ext() { awk -v s="$2" 'index($0,s)==1{p=1} p{print} p&&/^}/{exit}' "$1"; }   # <파일> <시작 접두> → 함수 본문
load() {  # load <nano-close.sh> <press-gate.sh> → 함수 정의(eval)
  eval "$(ext "$1" '_lp_lastline() {')"
  eval "$(ext "$2" '_hex40(){')"; eval "$(ext "$2" '_squash_heads(){')"
}
last_nc() { _lp_lastline "$R" main; }                       # nano-close 끝줄
heads_pg() { FEAT=main; ( cd "$R" && _squash_heads | cut -f2 ); }   # press-gate 가 모은 X

want="PR #7 (head $X)"
check() {  # check <이름> <기대: SKIP(건너뜀→끝줄=PR 줄) | KEEP(끝줄=꼬리 그대로·후보 0)> <꼬리 줄들…>
  local name="$1" exp="$2" msg tl; shift 2
  msg="착지

$want"; for tl in "$@"; do msg="$msg
$tl"; done
  mkc "$msg"
  local ln hd; ln="$(last_nc)"; hd="$(heads_pg)"
  if [ "$exp" = SKIP ]; then
    [ "$ln" = "$want" ] && ok "$name nano-close 끝줄 = PR 줄" || bad "$name nano-close 끝줄 «$ln»"
    [ "$hd" = "$X" ] && ok "$name press-gate X 수집" || bad "$name press-gate «$hd»"
  else
    [ "$ln" != "$want" ] && ok "$name nano-close 건너뜀 0 (끝줄 «${ln:0:30}…»)" || bad "$name nano-close 가 건너뜀"
    [ -z "$hd" ] && ok "$name press-gate 후보 0" || bad "$name press-gate 후보 «$hd»"
  fi
}

echo "== bin == kit cmp0 · bash -n"
for f in ft-nano-close.sh ft-press-gate.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp $f" || bad "cmp $f 다름"; bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"
done

load "$BIN/ft-nano-close.sh" "$BIN/ft-press-gate.sh"
echo "== R1 코드 꼬리";   check R1 SKIP "$CODE"
echo "== R2 문서 꼬리";   check R2 SKIP "$DOC"
echo "== R3 꼬리 없음";   check R3 SKIP
echo "== R4 짧은 sha";    check R4 KEEP "main 자동 병합(코드 · 승인 EQUIV) C=${Y:0:10}"
echo "== R5 문구 다름";   check R5 KEEP "main 자동 병합(코드 · 승인 EQUIV2) C=$Y"; check R5b KEEP "main 자동 병합(코드 · 승인 EQUIV) C=${Y}d"
echo "== R6 꼬리 2줄";    check R6 KEEP "$CODE" "$CODE"
echo "== R6b 코드+문서 꼬리(1줄만)"; check R6b KEEP "$CODE" "$DOC"

echo "== 변이 1 nano-close 코드 꼬리 갈래 무력화 → R1 FAIL"
cp "$BIN/ft-nano-close.sh" "$T/nc.sh"
python3 - "$T/nc.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
old = '*) l="$p";; esac; fi   # r1278-mut:skip'
assert s.count(old) == 1, s.count(old)
open(p, 'w', encoding='utf-8').write(s.replace(old, '*) ;; esac; fi   # r1278-mut:skip', 1))
PY
unset -f _lp_lastline; eval "$(ext "$T/nc.sh" '_lp_lastline() {')"
mkc "착지

$want
$CODE"
[ "$(last_nc)" != "$want" ] && ok "변이 1 → R1 nano-close FAIL(잡힘)" || bad "변이 1 안 잡힘"

echo "== 변이 2 press-gate 코드 꼬리 갈래 무력화 → R1 FAIL"
cp "$BIN/ft-press-gate.sh" "$T/pg.sh"
python3 - "$T/pg.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
old = '_hex40 "${l#*C=}" && l="$prev";;   # r1278-mut:skip'
assert s.count(old) == 1, s.count(old)
open(p, 'w', encoding='utf-8').write(s.replace(old, '_hex40 "${l#*C=}" && l="$l";;   # r1278-mut:skip', 1))
PY
unset -f _hex40 _squash_heads; eval "$(ext "$T/pg.sh" '_hex40(){')"; eval "$(ext "$T/pg.sh" '_squash_heads(){')"
[ -z "$(heads_pg)" ] && ok "변이 2 → R1 press-gate FAIL(잡힘)" || bad "변이 2 안 잡힘"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
