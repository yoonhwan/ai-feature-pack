#!/usr/bin/env bash
# test_nano_spawn_body_press.sh — ft-nano-spawn.sh 의 첫 발주문(BODY)에 press 금지 문장이 있는가 (정적 · 실행·네트워크·tmux 0).
#   r1025 칸 1: BODY 에 은퇴 도구(serena) 0 + 송신 직전 최종 본문 검사(REJECT 1줄 · 송신 0).
# 두 사본(추적본·키트)의 ^BODY= 줄을 읽는다. spawn 의 --dry-run 은 BODY 를 출력하지 않아 정적 grep 이 유일한 관측점이다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="$HERE/../../harness/bin/ft-nano-spawn.sh"
KIT="$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh"
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
  case "$line" in *"측정 조작 금지"*"/dev/bubble-replay"*"BOOT 20"*) ok "$label 측정 조작 금지 문장";; *) bad "$label BODY 에 '측정 조작 금지' 문장 없음";; esac
  case "$line" in *serena*|*Serena*|*find_symbol*) bad "$label BODY 에 은퇴 도구 지시(serena·find_symbol) 남음";; *) ok "$label BODY 에 Serena 0";; esac
  case "$line" in *"증거 줄"*"완료 턴에 네가 인덱스 «상태» 절에 직접"*"master 는 커밋만"*) ok "$label 증거 줄 직접 기록 문장";; *) bad "$label BODY 에 '증거 줄 직접 기록' 문장 없음";; esac
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

# 음성 대조 2 — 측정 조작 금지 문장만 지운 복사본도 FAIL 을 내야 한다
LC_ALL=en_US.UTF-8 sed 's/★측정 조작 금지[^★]*★ //' "$TRACKED" > "$TMP/stripped2.sh"
cmp -s "$TRACKED" "$TMP/stripped2.sh" && bad "음성 대조 2: sed 가 문장을 지우지 못함(복사본 == 원본)"
before="$fail"
neg2="$(check_body "음성복사본2" "$TMP/stripped2.sh")"
fail="$before"
echo "$neg2" | grep -q '^FAIL 음성복사본2 BODY 에 .측정 조작 금지' && ok "음성 대조 2: 문장 제거 시 FAIL 발생" || bad "음성 대조 2: 문장을 지웠는데 FAIL 이 안 남"

# 음성 대조 3 — 증거 줄 직접 기록 문장만 지운 복사본도 FAIL 을 내야 한다
LC_ALL=en_US.UTF-8 sed 's/ ★증거 줄[^★]*★//' "$TRACKED" > "$TMP/stripped3.sh"
cmp -s "$TRACKED" "$TMP/stripped3.sh" && bad "음성 대조 3: sed 가 문장을 지우지 못함(복사본 == 원본)"
before="$fail"
neg3="$(check_body "음성복사본3" "$TMP/stripped3.sh")"
fail="$before"
echo "$neg3" | grep -q '^FAIL 음성복사본3 BODY 에 .증거 줄' && ok "음성 대조 3: 문장 제거 시 FAIL 발생" || bad "음성 대조 3: 문장을 지웠는데 FAIL 이 안 남"

# ── r1025 칸 1 — 송신 직전 최종 본문 검사(은퇴 도구 serena) : REJECT 1줄 · 송신 0 ──
# 잔문을 ci 로 바꿔도(_SRX·BODY) 나중에 덧붙는 본문이나 다른 글자에서 다시 섮일 수 있다 — 보내기 «전» 한 곳에서 본문 전문을 본다.
check_retired() {
  local label="$1" f="$2" n ln sl
  n="$(grep -c 'REJECT 발주문에 은퇴 도구 지시(serena)' "$f")"
  [ "$n" = "1" ] && ok "$label 최종 본문 검사 줄 1개" || { bad "$label 최종 본문 검사 줄 ${n}개 (기대 1)"; return; }
  ln="$(grep -n 'REJECT 발주문에 은퇴 도구 지시(serena)' "$f" | cut -d: -f1)"
  sl="$(grep -n '^FT_SEND_FROM="\$FROM" bash' "$f" | head -1 | cut -d: -f1)"
  [ -n "$sl" ] && [ "$ln" -lt "$sl" ] && ok "$label 검사 줄이 송신 줄보다 앞(송신 0)" || bad "$label 검사 줄이 송신 줄 뒤이거나 송신 줄 없음(ln=$ln sl=${sl:-없음})"
}
check_retired "추적본" "$TRACKED"
check_retired "키트" "$KIT"
RFN="$(awk '/^retired_probe\(\) \{/,/^\}/' "$TRACKED")"
[ -n "$RFN" ] && ok "retired_probe 함수 추출" || bad "retired_probe 함수 없음"
eval "$RFN"
RFN="$(awk '/^retired_line\(\) \{/,/^\}/' "$TRACKED")"
[ -n "$RFN" ] && ok "retired_line 함수 추출" || bad "retired_line 함수 없음"
eval "$RFN"
[ -z "$(retired_line '평법한 발주문 · ci sym/refs/outline/search · 명부 금지')" ] && ok "검사: 깨끗한 본문 → 일치 0" || bad "검사: 깨끗한 본문인데 일치"
[ "$(retired_line '★편집은 Edit 절대경로만★ serena 먼저')" = "serena" ] && ok "검사: serena → serena" || bad "검사: serena 를 못 잡음"
[ "$(retired_line 'Serena 는 읽기만')" = "Serena" ] && ok "검사: Serena → Serena" || bad "검사: Serena 를 못 잡음"
BLINE="$(grep '^BODY=' "$TRACKED")"
BEBN="$(sed -n 's/.*_EBN="\([^"]*\)".*/_EBN="\1"/p' "$TRACKED" | head -1)"
[ -n "$BEBN" ] && ok "_EBN 정의 추출" || bad "_EBN 정의 추출 실패"
eval "$BEBN" 2>/dev/null || true
[ -z "$(retired_line "$BLINE")" ] && ok "검사: 실제 BODY 줄 → 일치 0" || bad "검사: 실제 BODY 줄에서 은퇴 도구 글자 발견"
[ "$(retired_line "$BLINE$_EBN serena")" = "serena" ] && ok "검사: _EBN 뒤에 serena 를 넣으면 걸린다(REJECT 1줄)" || bad "검사: _EBN 뒤 serena 를 못 잡음"
[ "$(retired_line "$BLINE$_EBN find_symbol")" = "find_symbol" ] && ok "검사: _EBN 뒤 find_symbol 도 걸린다" || bad "검사: _EBN 뒤 find_symbol 을 못 잡음"
# r1025 r1(arch 163 반송) — 카드 경로·가지 이름에 «serena» 가 들어도(이 카드 r1025 자신) 지시문 serena 0 이면 REJECT 0
N_WT="/x/harness-ops"; N_IDX="design/harness/indices/진행/r1025-nano-spawn-body-serena-to-ci.md"; N_BR="nano/r1025-nano-spawn-body-serena-to-ci"; N_SLUG="r1025-nano-spawn-body-serena-to-ci"
N_BODY="네 인덱스: $N_WT/$N_IDX 커밋은 브랜치 $N_BR · 팩 폴더 .worktrees/$N_SLUG · 코드 찾기는 ci sym/refs/outline/search"
[ "$(retired_line "$N_BODY")" = "serena" ] && ok "반례 재현: 이름 값 그대로 보면 거짓 REJECT(serena)" || bad "반례 재현 실패 — 이름에 serena 가 안 걸린다"
[ -z "$(retired_line "$(retired_probe "$N_BODY" "$N_WT/$N_IDX" "$N_BR" "$N_SLUG")")" ] && ok "새 칸: 이름 값 지운 사본 → REJECT 0(송신 길로 감)" || bad "새 칸: 이름 값을 지웠는데도 REJECT"
[ "$(retired_line "$(retired_probe "$N_BODY ★빈 카드: serena 먼저★" "$N_WT/$N_IDX" "$N_BR" "$N_SLUG")")" = "serena" ] && ok "새 칸: 같은 이름 + 지시문 serena 1줄 → REJECT 1줄" || bad "새 칸: 지시문 serena 를 못 잡음"
# 검사 줄은 이름 값 지운 사본(_probe)을 본다 — BODY 를 직접 보면 이름 때문에 거잠 REJECT
[ "$(grep -c 'retired_line "\$_probe"' "$TRACKED")" = "1" ] && ok "추적본 검사 줄이 사본(_probe)을 본다" || bad "추적본 검사 줄이 사본을 보지 않음"
[ "$(grep -c 'retired_line "\$_probe"' "$KIT")" = "1" ] && ok "키트 검사 줄이 사본(_probe)을 본다" || bad "키트 검사 줄이 사본을 보지 않음"
# 변이 — «검사용 사본 대신 BODY 직접» 으로 바꾼 사본은 새 칸 FAIL
sed 's/retired_line "\$_probe"/retired_line "$BODY"/' "$TRACKED" > "$TMP/stripped5.sh"
cmp -s "$TRACKED" "$TMP/stripped5.sh" && bad "변이: sed 가 검사 줄을 바꾸지 못함"
[ "$(grep -c 'retired_line "\$_probe"' "$TMP/stripped5.sh")" = "1" ] && bad "변이: 사본 검사가 그대로남" || ok "변이 «BODY 직접 검사» → 새 칸 FAIL"
unset _EBN
# 변이 — 검사 줄을 지운 사본은 check_retired 가 FAIL
grep -v 'REJECT 발주문에 은퇴 도구 지시(serena)' "$TRACKED" > "$TMP/stripped4.sh"
cmp -s "$TRACKED" "$TMP/stripped4.sh" && bad "변이: sed 가 검사 줄을 지우지 못함"
before="$fail"; neg4="$(check_retired "음성복사본4" "$TMP/stripped4.sh")"; fail="$before"
echo "$neg4" | grep -q '^FAIL 음성복사본4 최종 본문 검사 줄 0개' && ok "변이: 검사 줄 삭제 → FAIL" || bad "변이: 검사 줄을 지웠는데 FAIL 이 안 남"

# ── R181 · link_web_node_modules (임시 git 저장소 + 워크트리 · 라이브 bin·실 node_modules 0) ──
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
# r687: 팩 이전(3b25f81d) 뒤 «$HERE/../../.gitignore» 는 BYZ 루트가 아니다(파일 없음 → ⓒ 빨강). spawn 대상 리포(BYZ) .gitignore 의 두 줄(R181 · origin/main 108~109행)을 픽스처로 둔다.
REPO_GI="$TMP/byz.gitignore"; printf 'node_modules/\nclients/web/node_modules\n' > "$REPO_GI"
BYZ_ROOT="${FT_BYZ_ROOT:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"   # 정본 대조 — 리포가 보이는 머신에서만(없으면 SKIP)
if _gi="$(git -C "$BYZ_ROOT" show origin/main:.gitignore 2>/dev/null)"; then printf '%s\n' "$_gi" | grep -qx 'clients/web/node_modules' && ok "BYZ origin/main .gitignore 에 clients/web/node_modules 줄 실재" || bad "BYZ origin/main .gitignore 에 clients/web/node_modules 줄 없음"; else echo "SKIP BYZ .gitignore 정본 대조 — $BYZ_ROOT 없음"; fi
# mk_repo <디렉터리> <.gitignore 원본> <루트 node_modules 0|1> <워크트리 lock 내용> — 루트 + .worktrees/wt 생성
mk_repo() {
  local d="$1" gi="$2" nm="$3" wtlock="$4"
  mkdir -p "$d/clients/web" && git -C "$d" init -q && cp "$gi" "$d/.gitignore"
  echo '{"lock":"root"}' > "$d/clients/web/package-lock.json"
  git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t commit -qm base
  echo "$wtlock" > "$d/clients/web/package-lock.json"   # 워크트리는 이 내용으로 갈라진다(같게/다르게)
  git -C "$d" -c user.name=t -c user.email=t@t commit -qam wtbase >/dev/null 2>&1 || true   # lock 같음이면 커밋할 것 없음
  echo '{"lock":"root"}' > "$d/clients/web/package-lock.json"
  git -C "$d" worktree add -q "$d/.worktrees/wt" -b nano/x HEAD
  [ "$nm" = 1 ] && mkdir -p "$d/clients/web/node_modules/jsdom"
  return 0
}
# 추적본에서 함수 본문만 뽑아 eval — 스크립트 전체(tmux·mbox)는 실행하지 않는다
FN="$(awk '/^link_web_node_modules\(\) \{/,/^\}/' "$TRACKED")"
[ -n "$FN" ] && ok "link_web_node_modules 함수 추출" || bad "link_web_node_modules 함수 없음"
eval "$FN"

# ⓐ 루트 있음 → 상대 심링크 · 대상이 루트 폴더 / ⓓ lock 같음
mk_repo "$TMP/a" "$REPO_GI" 1 '{"lock":"root"}'
out="$(link_web_node_modules "$TMP/a" "$TMP/a/.worktrees/wt")"
[ "$(readlink "$TMP/a/.worktrees/wt/clients/web/node_modules")" = "../../../../clients/web/node_modules" ] && ok "ⓐ 상대 심링크" || bad "ⓐ 상대 심링크 아님"
[ -d "$TMP/a/.worktrees/wt/clients/web/node_modules/jsdom" ] && ok "ⓐ 링크가 루트 폴더로 해석" || bad "ⓐ 링크 대상이 루트 폴더가 아님"
echo "$out" | grep -qx 'node_modules=link lock=same' && ok "ⓓ lock=same 출력" || bad "ⓓ lock=same 출력 아님: $out"
# ⓒ git status · 전체 스테이징 뒤 인덱스에 node_modules 0 (임시 저장소 안)
[ -z "$(git -C "$TMP/a/.worktrees/wt" status --porcelain | grep node_modules)" ] && ok "ⓒ status 에 node_modules 0" || bad "ⓒ status 에 node_modules 보임"
git -C "$TMP/a/.worktrees/wt" add -A && [ -z "$(git -C "$TMP/a/.worktrees/wt" diff --cached --name-only | grep node_modules)" ] && ok "ⓒ 전체 스테이징 뒤 인덱스에 node_modules 0" || bad "ⓒ 전체 스테이징이 node_modules 를 담음"
# 이미 있으면 손대지 않음(멱등)
link_web_node_modules "$TMP/a" "$TMP/a/.worktrees/wt" >/dev/null && ok "멱등 재호출 rc 0" || bad "멱등 재호출 실패"

# ⓓ lock 다름
mk_repo "$TMP/d" "$REPO_GI" 1 '{"lock":"other"}'
out="$(link_web_node_modules "$TMP/d" "$TMP/d/.worktrees/wt")"
echo "$out" | grep -q '^node_modules=link lock=differ' && ok "ⓓ lock=differ 출력" || bad "ⓓ lock=differ 출력 아님: $out"

# ⓑ 루트 없음 → 링크 0 + node_modules=none
mk_repo "$TMP/b" "$REPO_GI" 0 '{"lock":"root"}'
out="$(link_web_node_modules "$TMP/b" "$TMP/b/.worktrees/wt")"
[ ! -e "$TMP/b/.worktrees/wt/clients/web/node_modules" ] && [ ! -L "$TMP/b/.worktrees/wt/clients/web/node_modules" ] && ok "ⓑ 링크 0" || bad "ⓑ 루트 없는데 링크가 생김"
echo "$out" | grep -q '^node_modules=none (루트 clients/web/node_modules 없음' && ok "ⓑ node_modules=none 출력" || bad "ⓑ node_modules=none 출력 아님: $out"

# ⓔ 기존 .venv·.env 심링크 줄 불변 + spawn 이 새 단계를 호출
grep -q 'for l in .venv .env; do \[ -e "\$ROOT/\$l" \] && ln -sfn "../../\$l" "\$WTDIR/\$l"; done' "$TRACKED" && ok "ⓔ .venv .env 심링크 줄 그대로" || bad "ⓔ .venv .env 심링크 줄 변경됨"
grep -q '^  link_web_node_modules "\$ROOT" "\$WTDIR"$' "$TRACKED" && ok "spawn 이 심링크 단계를 호출" || bad "spawn 에 link_web_node_modules 호출 없음"

# ⓕ 변이 — .gitignore 의 clients/web/node_modules 줄을 지우면 ⓒ 가 FAIL(심링크가 status 에 잡힘)
grep -v '^clients/web/node_modules$' "$REPO_GI" > "$TMP/gi_mut"
cmp -s "$REPO_GI" "$TMP/gi_mut" && bad "ⓕ 변이: 줄이 .gitignore 에 없음"
mk_repo "$TMP/f" "$TMP/gi_mut" 1 '{"lock":"root"}'
link_web_node_modules "$TMP/f" "$TMP/f/.worktrees/wt" >/dev/null
git -C "$TMP/f/.worktrees/wt" status --porcelain | grep -q node_modules && ok "ⓕ 변이 시 ⓒ FAIL(심링크가 status 에 보임)" || bad "ⓕ 변이인데도 status 에 안 보임"

# r687: 이 시험이 든 리포 — r541 guard 가 cwd 를 git 밖으로 옮기면 cwd 기준 값은 빈 값
[ "$(git -C "$HERE" config --get core.bare)" = "false" ] && ok "core.bare=false" || bad "core.bare 가 false 아님"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
