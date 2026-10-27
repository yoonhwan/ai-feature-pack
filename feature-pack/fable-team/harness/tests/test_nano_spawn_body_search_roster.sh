#!/usr/bin/env bash
# test_nano_spawn_body_search_roster.sh — ft-nano-spawn.sh 의 첫 발주문(BODY) 고정 줄에
# ① «저장소 전체 검색 금지» ② «명부 손대지 않음» ③ «코드는 ci · ci 없으면 rg+Read 폴백» 이 있는가 (정적 · 실행·네트워크·tmux 0).
#   r1025: ③ 은 «serena 먼저»(r556) → «ci 문장 + 폴백 문장 + serena·find_symbol 0» 으로 바뀌었다(하드 룰 16 「사람·나노·스크립트 모두 ci」).
# 꼴 = test_nano_spawn_body_press.sh(r15t). 두 사본(추적본·키트)의 `_SRX=` 줄과 `^BODY=` 줄을 읽는다.
# ⓑ(pi 도 같은 줄) = 에이전트 분기 0 구조 검사: 고정 줄은 «무조건 실행되는» echo 한 줄에서만 나오고
#    BODY= 한 줄이 전 에이전트 공용이며 그 줄에 AGENT 분기가 없다 + 실제 emit 을 _SRX 값으로 재현해 두 에이전트 값이 같다.
#    (실 dry-run 은 런타임 .fable-team/bin·seats.json·팀 좌석상한이 있어야 BODY 줄까지 가므로 이 카드 범위 밖 — 설치 후 master 실사건.)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../harness/bin/ft-nano-spawn.sh"
KIT="$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# check_line <label> <파일> — _SRX 정의 1개 + 문장 셋 + echo 1개 + BODY 에 반영
check_line() {
  local label="$1" f="$2" n def
  n="$(grep -c '^_SRX="' "$f")"
  [ "$n" = "1" ] && ok "$label ^_SRX= 줄 1개" || { bad "$label ^_SRX= 줄 ${n}개 (기대 1)"; return; }
  def="$(grep '^_SRX="' "$f")"
  case "$def" in *"저장소 전체 검색 금지"*) ok "$label 검색 범위 금지 문장";; *) bad "$label _SRX 에 '저장소 전체 검색 금지' 없음";; esac
  case "$def" in *"grep -r"*"git log --all -S"*"find /"*) ok "$label 광역 명령 3종 명시";; *) bad "$label _SRX 에 grep -r·git log --all -S·find / 없음";; esac
  case "$def" in *"ci sym/refs/outline/search"*) ok "$label ci 문장";; *) bad "$label _SRX 에 ci 문장 없음";; esac
  case "$def" in *"grep 은 로그·결과·명부만"*) ok "$label grep 허용 범위 문장";; *) bad "$label _SRX 에 'grep 은 로그·결과·명부만' 없음";; esac
  case "$def" in *"ci 가 없으면 rg+Read"*) ok "$label ci 없을 때 폴백 문장";; *) bad "$label _SRX 에 ci 폴백 문장 없음";; esac
  case "$def" in *serena*|*Serena*|*find_symbol*) bad "$label _SRX 에 은퇴 도구 지시(serena·find_symbol) 남음";; *) ok "$label serena·find_symbol 0";; esac
  case "$def" in *"seats.json"*"손대지 않는다"*"spawn 이 이미 등록"*) ok "$label 명부 손대지 않음 문장";; *) bad "$label _SRX 에 명부 금지 문장 없음";; esac
  [ "$(grep -c '^echo "BODY+\${_SRX}"$' "$f")" = "1" ] && ok "$label BODY+ echo 1개" || bad "$label BODY+ echo 없음"
  case "$(grep '^BODY=' "$f")" in *'${_SRX}'*) ok "$label BODY= 에 반영";; *) bad "$label BODY= 에 \${_SRX} 없음(발주문에 안 붙는다)";; esac
}

bash -n "$TRACKED" && ok "bash -n 추적본" || bad "bash -n 추적본"
bash -n "$KIT" && ok "bash -n 키트" || bad "bash -n 키트"
cmp -s "$TRACKED" "$KIT" && ok "두 사본 cmp 동일" || bad "두 사본 cmp 불일치"
check_line "추적본" "$TRACKED"
check_line "키트" "$KIT"

# ⓑ 에이전트 분기 0 — 고정 줄·echo·BODY 줄에 AGENT 조건이 없고, 두 에이전트 값의 emit 이 같다
grep '^_SRX="' "$TRACKED" | grep -q 'AGENT' && bad "ⓑ _SRX 줄에 AGENT 분기" || ok "ⓑ _SRX 줄 AGENT 분기 0"
grep -q '^echo "BODY+\${_SRX}"$' "$TRACKED" && ok "ⓑ echo 무조건(조건문 안 아님)" || bad "ⓑ echo 줄 이상"
grep '^BODY=' "$TRACKED" | grep -q 'AGENT' && bad "ⓑ BODY 줄에 AGENT 분기" || ok "ⓑ BODY 줄 AGENT 분기 0"
DEF="$(grep '^_SRX="' "$TRACKED")"
eval "$DEF"
out_claude="$(AGENT=claude bash -c '_SRX="$1"; echo "BODY+${_SRX}"' _ "$_SRX")"
out_pi="$(AGENT=pi bash -c '_SRX="$1"; echo "BODY+${_SRX}"' _ "$_SRX")"
[ -n "$out_pi" ] && [ "$out_claude" = "$out_pi" ] && ok "ⓑ pi·claude emit 동일" || bad "ⓑ pi·claude emit 다름"
case "$out_pi" in *"저장소 전체 검색 금지"*) ok "ⓑ pi emit 에 그 줄";; *) bad "ⓑ pi emit 에 그 줄 없음";; esac
unset _SRX

# ⓓ 음성 대조 — 문장을 지운 복사본은 check_line 이 FAIL 을 내야 한다(정의 줄 삭제)
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LC_ALL=en_US.UTF-8 grep -v '^_SRX="' "$TRACKED" | sed 's/\${_SRX}//' > "$TMP/stripped.sh"
cmp -s "$TRACKED" "$TMP/stripped.sh" && bad "ⓓ 음성 대조: 복사본 == 원본"
before="$fail"
neg="$(check_line "음성복사본" "$TMP/stripped.sh")"
fail="$before"   # 음성 복사본의 FAIL 은 기대된 결과 — 총합에 넣지 않는다
echo "$neg" | grep -q '^FAIL 음성복사본' && ok "ⓓ 음성 대조: 문장 제거 시 FAIL 발생" || bad "ⓓ 문장을 지웠는데 FAIL 이 안 남"
# ⓓ-2 음성 대조 — '명부 손대지 않음' 만 지운 사본도 FAIL
LC_ALL=en_US.UTF-8 sed 's/ · 명부(seats.json · seats-<팀>.json)는 손대지 않는다(spawn 이 이미 등록 · 손 행 = 쪽지 반송)//' "$TRACKED" > "$TMP/stripped2.sh"
cmp -s "$TRACKED" "$TMP/stripped2.sh" && bad "ⓓ-2 음성 대조: sed 가 문장을 지우지 못함"
before="$fail"
neg2="$(check_line "음성복사본2" "$TMP/stripped2.sh")"
fail="$before"
echo "$neg2" | grep -q '^FAIL 음성복사본2 _SRX 에 명부 금지 문장 없음' && ok "ⓓ-2 음성 대조: 명부 문장 제거 시 FAIL" || bad "ⓓ-2 명부 문장을 지웠는데 FAIL 이 안 남"
# ⓓ-3 변이 — _SRX 를 «옛 문구(serena 먼저)» 로 되돌린 사본은 ③ 이 FAIL(ci 문장 없음 + serena 남음)
LC_ALL=en_US.UTF-8 sed 's#ci sym/refs/outline/search#serena 도구(find_symbol)#' "$TRACKED" > "$TMP/stripped3.sh"
cmp -s "$TRACKED" "$TMP/stripped3.sh" && bad "ⓓ-3 변이: sed 가 ci 문장을 바꾸지 못함"
before="$fail"
neg3="$(check_line "음성복사본3" "$TMP/stripped3.sh")"
fail="$before"
echo "$neg3" | grep -q '^FAIL 음성복사본3 _SRX 에 ci 문장 없음' && ok "ⓓ-3 변이: 옛 문구로 되돌리면 FAIL" || bad "ⓓ-3 옛 문구인데 ci 문장 FAIL 이 안 남"
echo "$neg3" | grep -q '^FAIL 음성복사본3 _SRX 에 은퇴 도구 지시' && ok "ⓓ-3 변이: serena 남음을 잡는다" || bad "ⓓ-3 serena 가 남았는데 FAIL 이 안 남"

# 기존 고정 줄(광역 pytest·팩 폴더·press 금지) 불변
grep -q '^_SPX=" ★광역 pytest 금지' "$TRACKED" && ok "기존 _SPX 불변" || bad "기존 _SPX 변경됨"
grep -q '★press(라이브 오디오 시험) 금지' "$TRACKED" && ok "기존 press 금지 문장 불변" || bad "press 금지 문장 사라짐"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
