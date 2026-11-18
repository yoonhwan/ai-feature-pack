#!/usr/bin/env bash
# r921_mut.sh — r921 변이 대조 8개의 몸(r2225 · 본문 파일 변이 절을 옮김 · 판정 꼴 DA⑥ r1 «전체 시험 재실행» 그대로).
#   판정 = 변이 사본에서 «그 칸은 FAIL» ∧ «대조 칸은 PASS» ∧ «문법 오류 없음». 재실행은 R921_NO_MUT=1 을 계속 넘긴다(본문에선 효과 0).
#   쓰는 법: 부르는 쪽이 REPO · T · ok · bad 를 정한 뒤 source → r921_mut <번호…>(1~8 = 기준판 변이1~8 · 없는 번호 = FAIL 1줄).
mutcase() { # <이름> <harness 상대경로 파일> <old> <new> <빨강 라벨 조각> <초록 라벨 조각>
  local name="$1" f="$2" old="$3" new="$4" redl="$5" greenl="$6"
  local st="$T/mstage"; rm -rf "$st"; mkdir -p "$st/harness"
  cp -R "$REPO/harness/bin" "$st/harness/" && cp -R "$REPO/harness/kit" "$st/harness/" && cp -R "$REPO/harness/tests" "$st/harness/" || { bad "변이 $name 준비 실패(copy)"; return; }
  local kf="${f/bin\//kit/fable-team/bin/}"   # bin/ → kit/fable-team/bin/ 짝도 같이 변이한다(시험은 kit 사본을 $B 로 쓰고 kit cmp 도 초록이어야 한다)
  python3 - "$REPO/harness/$f" "$st/harness/$f" "$old" "$new" "$REPO/harness/$kf" "$st/harness/$kf" <<'PP' || { bad "변이 $name 준비 실패(치환 0)"; return; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.exit("MUT-OLD 없음")
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
if len(sys.argv) == 7:
    k_src, k_dst = sys.argv[5], sys.argv[6]
    ks = open(k_src, encoding="utf-8").read()
    if old in ks:
        open(k_dst, "w", encoding="utf-8").write(ks.replace(old, new, 1))
PP
  local out; out="$(cd "$st/harness" && R921_NO_MUT=1 bash "$st/harness/tests/test_resource_warn_proceed_r921.sh" 2>&1)"
  local syn=0; case "$out" in *"syntax error"*|*"command not found"*) syn=1;; esac
  if [ "$syn" = 1 ]; then bad "변이 $name — 문법 오류라 검출로 안 친다"; return; fi
  local rd=0 gr=0
  case "$out" in *"FAIL ${redl}"*) rd=1;; esac     # 파이프 대신 case — pipefail + grep -q 조기종료의 EPIPE 헛빨강을 피한다
  case "$out" in *"PASS ${greenl}"*) gr=1;; esac
  { [ "$rd" = 1 ] && [ "$gr" = 1 ]; } \
    && ok "변이 $name → «${redl}» 만 빨강(대조 «${greenl}» 초록 · 전체 재실행)" \
    || bad "변이 $name — red=$rd green=$gr syntax=$syn :: $(printf '%s\n' "$out" | grep -E '^FAIL' | head -2 | tr '\n' ' ')"
}
r921_mut() { # <번호…>
  local k
  for k in "$@"; do
    case "$k" in
    1)
      # 변이1 «WARN 을 REJECT 로 복귀» → ⓐ 빨강 · 대조 ⓙ 초록
      mutcase "WARN→REJECT 복귀(문지기)" "bin/ft-resource-gate.sh" \
        '[ -z "$WARNS" ] || { echo "WARN resource $WARNS"; exit 0; }' \
        '[ -z "$WARNS" ] || { echo "REJECT resource $WARNS"; exit 3; }' \
        "ⓐ swap" "ⓙ FT_DISK_HARD_MIN_MIB=abc" ;;
    2)
      # 변이2 «하한 값 검증 끔» → ⓙ 빨강 · 대조 ⓒ 디스크 소프트 초록
      mutcase "하한 값 검증 끔" "bin/ft-resource-gate.sh" \
        '[ "$_dh_ok" = 1 ] || { echo "ERROR 하한 값 이상' \
        '[ "$_dh_ok" = 1 ] || [ -n x ] || { echo "ERROR 하한 값 이상' \
        "ⓙ abc" "ⓒ 디스크 4GiB" ;;
    3)
      # 변이3 «회수 상한 끔» → ⓚ 빨강 · 대조 ⓐ' 초록
      mutcase "회수 7초 상한 끔" "bin/ft-reclaim-capped.sh" \
        '  local lim="$FT_RECLAIM_TIMEOUT_SEC"' \
        '  local lim=999' \
        "ⓚ dt=" "ⓐ' 자원 넘김" ;;
    4)
      # 변이4 «상한 잠금 끔» → ⓛ 빨강 · 대조 ⓗ 초록
      mutcase "cap 잠금 끔" "bin/ft-nano-spawn.sh" \
        '    _ts_lock_take "$ROOT/.fable-team/state/nano-cap.lock.d" || _ts_lock_fail=1' \
        '    true' \
        "ⓛ 세션=" "ⓗ cap=4" ;;
    5)
      # 변이5 «좌석 상한 = cap 에서 큐»(W1 복귀) → ⓝ 빨강 · 대조 ⓗ 초록
      mutcase "좌석 상한 cap 에서 큐" "bin/ft-nano-spawn.sh" \
        '          elif [ "$_cl" -ge "$((_cc + 1))" ]; then' \
        '          elif [ "$_cl" -ge "$_cc" ]; then' \
        "ⓝ cap=4·live=4" "ⓗ cap=4" ;;
    6)
      # 변이6 «하한 자릿수 검사 끔»(W2 큰 수) → ⓞ 빨강 · 대조 ⓙ abc 초록
      mutcase "하한 7자리 검사 끔" "bin/ft-resource-gate.sh" \
        '=~ ^[0-9]{1,7}$ ]]' \
        '=~ ^[0-9]+$ ]]' \
        "ⓞ 큰 수" "ⓙ FT_DISK_HARD_MIN_MIB=abc" ;;
    7)
      # 변이7 «회수 입구 첫 항목만»(W3 복귀) → ⓟ 빨강 · 대조 ⓐ' 초록
      mutcase "회수 입구 첫 항목만" "bin/ft-resource-reclaim.sh" \
        "_items0=\"\$(printf '%s\\n' \"\$ONREJ\" | sed -nE 's/^(REJECT|WARN) resource //p' | tr ';' '\\n'" \
        "_items0=\"\$(printf '%s\\n' \"\$ONREJ\" | sed -nE 's/^(REJECT|WARN) resource //p' | sed 's/;.*//'" \
        "ⓟ freeze 뒤 agents" "ⓐ' 자원 넘김" ;;
    8)
      # 변이8 «abort trap 덮어쓰기»(W4 복귀) → ⓠ 빨강 · 대조 ⓗ 초록
      mutcase "abort trap 덮어쓰기" "bin/ft-nano-spawn.sh" \
        '_ON_EXIT+=(_sheet_abort)' \
        'trap _sheet_abort EXIT' \
        "ⓠ 잠금+abort+exit1" "ⓗ cap=4" ;;
    *) bad "변이 번호 $k 없음(r921_mut 1~8)" ;;
    esac
  done
}
