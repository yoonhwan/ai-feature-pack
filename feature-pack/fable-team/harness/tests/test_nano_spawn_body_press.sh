#!/usr/bin/env bash
# test_nano_spawn_body_press.sh — ft-nano-spawn.sh 의 첫 발주문(BODY)에 press 금지 문장이 있는가 (정적 · 실행·네트워크·tmux 0).
# 두 사본(추적본·키트)의 ^BODY= 줄을 읽는다. spawn 의 --dry-run 은 BODY 를 출력하지 않아 정적 grep 이 유일한 관측점이다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../scripts/fable-team-bin/ft-nano-spawn.sh"
KIT="$HERE/../../scripts/harness-install/fable-team/bin/ft-nano-spawn.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# check_body <label> <파일> — ^BODY= 줄 정확히 1개 + 그 줄에 금지 문장·게이트 근거
check_body() {
  local label="$1" f="$2" n line
  n="$(grep -c '^BODY=' "$f")"
  [ "$n" = "1" ] && ok "$label ^BODY= 줄 1개" || { bad "$label ^BODY= 줄 $n개 (기대 1)"; return; }
  line="$(grep '^BODY=' "$f")"
  case "$line" in *"press(라이브 오디오 시험) 금지"*) ok "$label press 금지 문장";; *) bad "$label BODY 에 'press(라이브 오디오 시험) 금지' 없음";; esac
  case "$line" in *"ft-press-gate ⑦"*) ok "$label ft-press-gate ⑦ 근거";; *) bad "$label BODY 에 'ft-press-gate ⑦' 없음";; esac
}

bash -n "$TRACKED" && ok "bash -n 추적본" || bad "bash -n 추적본"
bash -n "$KIT" && ok "bash -n 키트" || bad "bash -n 키트"
cmp -s "$TRACKED" "$KIT" && ok "두 사본 cmp 동일" || bad "두 사본 cmp 불일치"
check_body "추적본" "$TRACKED"
check_body "키트" "$KIT"

# 음성 대조 — 문장을 지운 복사본은 check_body 가 FAIL 을 내야 한다
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LC_ALL=en_US.UTF-8 sed 's/★press(라이브 오디오 시험) 금지[^★]*★ //' "$TRACKED" > "$TMP/stripped.sh"
cmp -s "$TRACKED" "$TMP/stripped.sh" && bad "음성 대조: sed 가 문장을 지우지 못함(복사본 == 원본)"
before="$fail"
neg="$(check_body "음성복사본" "$TMP/stripped.sh")"
fail="$before"  # 음성 복사본의 FAIL 은 기대된 결과 — 총합에 넣지 않는다
echo "$neg" | grep -q '^FAIL 음성복사본 BODY 에 .press(라이브 오디오 시험) 금지' && ok "음성 대조: 문장 제거 시 FAIL 발생" || bad "음성 대조: 문장을 지웠는데 FAIL 이 안 남"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
