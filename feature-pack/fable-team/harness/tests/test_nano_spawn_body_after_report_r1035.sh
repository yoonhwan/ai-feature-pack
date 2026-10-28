#!/usr/bin/env bash
# test_nano_spawn_body_after_report_r1035.sh — ft-nano-spawn.sh 의 첫 발주문(BODY) 고정 줄에
# «산출 보고 뒤 = 멈춤 아님» 문장 셋이 있는가 (정적 · 실행·tmux·네트워크 0).
#   r1035: 나노가 산출 보고를 «턴 종료» 로 읽고 멈추던 사고(오빠 10-28 «왜 멈춰있었어?» · ops 나노 20분 유휴)
#          → 보고 직후 카드 «완료 조건» 표를 다시 훑어 닫을 수 있는 행을 닫게 하는 줄 1개.
# 꼴 = test_nano_spawn_body_search_roster.sh(r1025). 두 사본(추적본·키트)의 `_AFX=` 줄과 `^BODY=` 줄을 읽는다.
# 에이전트 분기 0 = claude·pi·opencode·codex 같은 줄(고정 줄은 «무조건 실행되는» echo 한 줄에서만 나온다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../harness/bin/ft-nano-spawn.sh"
KIT="$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# check_line <label> <파일> — _AFX 정의 1개 + 문장 셋 + echo 1개 + BODY 반영
check_line() {
  local label="$1" f="$2" n def
  n="$(grep -c '^_AFX="' "$f")"
  [ "$n" = "1" ] && ok "$label ^_AFX= 줄 1개" || { bad "$label ^_AFX= 줄 ${n}개 (기대 1)"; return; }
  def="$(grep '^_AFX="' "$f")"
  case "$def" in *"산출 보고 뒤 = 멈춤 아님"*) ok "$label 머리 문장";; *) bad "$label _AFX 에 '산출 보고 뒤 = 멈춤 아님' 없음";; esac
  case "$def" in *"«완료 조건» 표를 행마다 다시 훑어"*) ok "$label ① 완료조건 표 재확인";; *) bad "$label _AFX 에 ① 문장 없음";; esac
  case "$def" in *"master 회신 대기는 일이 아니다"*) ok "$label ① 회신 대기 배제";; *) bad "$label _AFX 에 'master 회신 대기는 일이 아니다' 없음";; esac
  case "$def" in *"«남은 것» 항목마다"*"못 닫는 이유"*) ok "$label ② 남은 것 이유 한 줄";; *) bad "$label _AFX 에 ② 문장 없음";; esac
  case "$def" in *"«남은 것 0 + 근거»"*"좌석 종료 요청"*) ok "$label ③ 남은 것 0 + 종료 요청";; *) bad "$label _AFX 에 ③ 문장 없음";; esac
  [ "$(grep -c '^echo "BODY+\${_AFX}"$' "$f")" = "1" ] && ok "$label BODY+ echo 1개" || bad "$label BODY+ echo 없음"
  case "$(grep '^BODY=' "$f")" in *'${_AFX}'*) ok "$label BODY= 에 반영";; *) bad "$label BODY= 에 \${_AFX} 없음(발주문에 안 붙는다)";; esac
  grep '^_AFX="' "$f" | grep -q 'AGENT' && bad "$label _AFX 줄에 AGENT 분기" || ok "$label _AFX 줄 AGENT 분기 0"
  grep -q '^echo "BODY+\${_AFX}"$' "$f" || bad "$label echo 줄 이상"
}

bash -n "$TRACKED" && ok "bash -n 추적본" || bad "bash -n 추적본"
bash -n "$KIT" && ok "bash -n 키트" || bad "bash -n 키트"
cmp -s "$TRACKED" "$KIT" && ok "두 사본 cmp 동일" || bad "두 사본 cmp 불일치"
check_line "추적본" "$TRACKED"
check_line "키트" "$KIT"

# ⓑ BODY 줄 AGENT 분기 0 · 두 에이전트 emit 이 같다
grep '^BODY=' "$TRACKED" | grep -q 'AGENT' && bad "ⓑ BODY 줄에 AGENT 분기" || ok "ⓑ BODY 줄 AGENT 분기 0"
DEF="$(grep '^_AFX="' "$TRACKED")"
eval "$DEF"
out_claude="$(AGENT=claude bash -c '_AFX="$1"; echo "BODY+${_AFX}"' _ "$_AFX")"
out_pi="$(AGENT=pi bash -c '_AFX="$1"; echo "BODY+${_AFX}"' _ "$_AFX")"
[ -n "$out_pi" ] && [ "$out_claude" = "$out_pi" ] && ok "ⓑ pi·claude emit 동일" || bad "ⓑ pi·claude emit 다름"
case "$out_pi" in *"산출 보고 뒤 = 멈춤 아님"*) ok "ⓑ pi emit 에 그 줄";; *) bad "ⓑ pi emit 에 그 줄 없음";; esac
unset _AFX

# ⓓ 음성 대조 — 정의 줄을 지운 복사본은 check_line 이 FAIL 을 내야 한다
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LC_ALL=en_US.UTF-8 grep -v '^_AFX="' "$TRACKED" | sed 's/\${_AFX}//g' > "$TMP/stripped.sh"
cmp -s "$TRACKED" "$TMP/stripped.sh" && bad "ⓓ 음성 대조: 복사본 == 원본"
before="$fail"
neg="$(check_line "음성복사본" "$TMP/stripped.sh")"
fail="$before"   # 음성 복사본의 FAIL 은 기대된 결과 — 총합에 넣지 않는다
echo "$neg" | grep -q '^FAIL 음성복사본' && ok "ⓓ 음성 대조: 정의 줄 제거 시 FAIL 발생" || bad "ⓓ 정의 줄을 지웠는데 FAIL 이 안 남"
# ⓓ-2 변이 — ③ 문장만 지운 사본도 FAIL
LC_ALL=en_US.UTF-8 sed 's/ ③남은 것이 0 이면 «남은 것 0 + 근거» 와 좌석 종료 요청을 같은 쪽지에 넣는다(r1035)//' "$TRACKED" > "$TMP/stripped2.sh"
cmp -s "$TRACKED" "$TMP/stripped2.sh" && bad "ⓓ-2 변이: sed 가 ③ 문장을 지우지 못함"
before="$fail"
neg2="$(check_line "음성복사본2" "$TMP/stripped2.sh")"
fail="$before"
echo "$neg2" | grep -q '^FAIL 음성복사본2 _AFX 에 ③ 문장 없음' && ok "ⓓ-2 변이: ③ 문장 제거 시 FAIL" || bad "ⓓ-2 ③ 문장을 지웠는데 FAIL 이 안 남"
# ⓓ-3 변이 — BODY 에서 ${_AFX} 삽입만 뺀 사본은 «BODY= 에 반영» 이 FAIL
LC_ALL=en_US.UTF-8 sed 's/\${_SRX}\${_AFX}/\${_SRX}/' "$TRACKED" > "$TMP/stripped3.sh"
cmp -s "$TRACKED" "$TMP/stripped3.sh" && bad "ⓓ-3 변이: sed 가 BODY 삽입을 빼지 못함"
before="$fail"
neg3="$(check_line "음성복사본3" "$TMP/stripped3.sh")"
fail="$before"
echo "$neg3" | grep -q '^FAIL 음성복사본3 BODY= 에 \${_AFX} 없음' && ok "ⓓ-3 변이: BODY 삽입 제거 시 FAIL" || bad "ⓓ-3 BODY 삽입을 뺐는데 FAIL 이 안 남"

# 기존 고정 줄(광역 pytest·저장소 전체 검색·press 금지) 불변
grep -q '^_SPX=" ★광역 pytest 금지' "$TRACKED" && ok "기존 _SPX 불변" || bad "기존 _SPX 변경됨"
grep -q '^_SRX=" ★저장소 전체 검색 금지' "$TRACKED" && ok "기존 _SRX 불변" || bad "기존 _SRX 변경됨"
grep -q '★press(라이브 오디오 시험) 금지' "$TRACKED" && ok "기존 press 금지 문장 불변" || bad "press 금지 문장 사라짐"
grep -q '★팩 작업 폴더' "$TRACKED" && ok "기존 팩 폴더 줄 불변" || bad "팩 폴더 줄 사라짐"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
