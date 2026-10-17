#!/usr/bin/env bash
# test_teamset_check.sh — r-teamset-standard(판정 2170): design/TEAMSET.md 표 + ft-teamset-check.sh / ft_teamset.py check·cap·queue.
# 전부 mktemp 안 — 가짜 명부·가짜 TEAMSET 표·가짜 tmux(PATH)·임시 재개 기록 폴더. 실 좌석 kill 0 · 실 tmux 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/scripts/fable-team-bin"; KIT="$REPO/scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

MD="$T/TEAMSET.md"; ROOT="$T/root"; FAKE="$T/fake"; SESS="$T/sessions.txt"; RES="$T/resume"
mkdir -p "$ROOT/.fable-team/state" "$FAKE" "$RES"
cat > "$MD" <<'EOF'
# 가짜 팀셋
## 표 1 — 역할 표준
| 역할 | 수 | 모델 | effort | 명부 키 | 승계 | 닫기 |
|---|---|---|---|---|---|---|
| master | 필수 1 | `sonnet-5-5` | high | `_master` | a | b |
| arch | 상시 | `opus-5-5` | high | `_arch` | a | b |
| nano | 상한 N | `sonnet-5-5` | high | — | a | b |
- 나노 상한 기본: 3
- 명부 공용 키: `_name` `_doc` `_closed`
## 표 2 — 팀별 덮어쓰기
| 팀 | 나노 상한 | tester | arch 상시 |
|---|---|---|---|
| alpha | 3 | 0 | 상시 |
| beta | 2 | 0 | 상시 |
EOF
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
roster() { printf '{"_name":"%s","_master":"%s","_arch":"%s"%s}\n' "$1" "$2" "$3" "${4:-}" > "$ROOT/.fable-team/seats-$1.json"; }
sess() { : > "$SESS"; for n in "$@"; do echo "$n" >> "$SESS"; done; }
FM="$T/fake-mbox.sh"; printf '#!/bin/sh\necho "$*" >> %s/mbox.log\n[ -f %s/mbox.fail ] && exit 3\nexit 0\n' "$T" "$T" > "$FM"
FS="$T/fake-status.sh"; printf '#!/bin/sh\n[ -f %s/working.$(echo "$2" | tr "#" _) ] && echo "WORKING - - - jsonl" || echo "IDLE - - - jsonl"\n' "$T" > "$FS"
chk() { FT_TEAMSET_MBOX="$FM" FT_SEAT_STATUS="$FS" PATH="$FAKE:$PATH" FT_TEAMSET_ROOT="$ROOT" FT_TEAMSET_MD="${MDX:-$MD}" ZC_RESUME_DIR="$RES" bash "$BIN/ft-teamset-check.sh" "$@" 2>&1; }

[ -f "$BIN/ft-teamset-check.sh" ] && bash -n "$BIN/ft-teamset-check.sh" && ok "bash -n ft-teamset-check.sh" || bad "ft-teamset-check.sh 없음/문법"
[ -f "$BIN/ft_teamset.py" ] && python3 -m py_compile "$BIN/ft_teamset.py" && ok "py_compile ft_teamset.py" || bad "ft_teamset.py 없음/문법"
[ -f "$REPO/design/TEAMSET.md" ] && ok "design/TEAMSET.md 존재" || bad "design/TEAMSET.md 없음"

# ⓐ 표대로인 팀 → OK
roster alpha "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1"
sess "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-alpha-nano-x#0" "byz-alpha-nano-y#0"
o="$(chk alpha)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "alpha OK "* ]] && [ "$(grep -c . <<<"$o")" = 1 ]; } && ok "ⓐ 표대로 → OK rc0 · 팀당 1줄: $o" || bad "ⓐ rc=$rc $o"

# ⓑ master 없음 → ERR rc1
sess "byz-alpha-arch-claude#1" "byz-alpha-nano-x#0"
o="$(chk alpha)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "alpha ERR "*master* ]]; } && ok "ⓑ master 없음 → ERR rc1: $o" || bad "ⓑ rc=$rc $o"

# ⓒ 명부 _master 가 라이브 아님(다른 좌석은 살아 있음) → ERR
sess "byz-alpha-master-claude#9" "byz-alpha-arch-claude#1"
o="$(chk alpha)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == "alpha ERR "* ]]; } && ok "ⓒ 명부 _master 라이브 아님 → ERR" || bad "ⓒ rc=$rc $o"

# ⓓ 나노 3/상한 2 (beta) → WARN · rc0
roster beta "byz-beta-master-claude#1" "byz-beta-arch-claude#1"
sess "byz-beta-master-claude#1" "byz-beta-arch-claude#1" "byz-beta-nano-a#0" "byz-beta-nano-b#0" "byz-beta-nano-c#0"
o="$(chk beta)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == "beta WARN "*"나노 3/2"* ]]; } && ok "ⓓ 나노 3/상한 2 → WARN rc0: $o" || bad "ⓓ rc=$rc $o"

# ⓔ 세대 규칙(DA r1 ⑧) — 직전 1세대는 재개 기록과 무관하게 정상 · 3세대 동시 = keep-last-2 밖 WARN · 현역 2세대 동시 WORKING = WARN
sess "byz-alpha-master-claude#1" "byz-alpha-master-claude#2" "byz-alpha-arch-claude#1"
roster alpha "byz-alpha-master-claude#2" "byz-alpha-arch-claude#1"
o="$(chk alpha)"; [[ "$o" == "alpha OK "* ]] && ok "ⓔ 직전 1세대(재개 기록 없음) → 정상 OK" || bad "ⓔ-1 $o"
sess "byz-alpha-master-claude#1" "byz-alpha-master-claude#2" "byz-alpha-master-claude#3" "byz-alpha-arch-claude#1"
roster alpha "byz-alpha-master-claude#3" "byz-alpha-arch-claude#1"
o="$(chk alpha)"; [[ "$o" == "alpha WARN "*"3세대"* ]] && ok "ⓔ 3세대 동시 → keep-last-2 밖 WARN: $o" || bad "ⓔ-2 $o"
sess "byz-alpha-master-claude#1" "byz-alpha-master-claude#2" "byz-alpha-arch-claude#1"
roster alpha "byz-alpha-master-claude#2" "byz-alpha-arch-claude#1"
touch "$T/working.byz-alpha-master-claude_1" "$T/working.byz-alpha-master-claude_2"
o="$(chk alpha)"; [[ "$o" == "alpha WARN "*"동시 WORKING"* ]] && ok "ⓔ 2세대 둘 다 WORKING → WARN" || bad "ⓔ-3 $o"
rm -f "$T"/working.*

# ⓕ 표에 없는 _ 역할 키 → WARN
roster alpha "byz-alpha-master-claude#2" "byz-alpha-arch-claude#1" ',"_weird":"x"'
o="$(chk alpha)"; [[ "$o" == "alpha WARN "*"_weird"* ]] && ok "ⓕ 모르는 _키 → WARN: $o" || bad "ⓕ $o"

# ⓖ 모델 어긋남은 정보만 — 상태 OK 유지
python3 - "$ROOT/.fable-team/seats-beta.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["byz-beta-nano-a#0"] = {"role": "nano", "model": "claude-opus-5-5[1m]"}
json.dump(d, open(p, "w"))
PY
sess "byz-beta-master-claude#1" "byz-beta-arch-claude#1" "byz-beta-nano-a#0"
o="$(chk beta)"; { [[ "$o" == "beta OK "* ]] && [[ "$o" == *"모델≠표 1"* ]]; } && ok "ⓖ 모델 어긋남은 정보만(OK 유지): $o" || bad "ⓖ $o"

# ⓗ 휴면 팀(라이브 0) → OK 휴면 · rc0 · _closed 도 같다
sess
o="$(chk alpha)"; rc=$?; { [ "$rc" = 0 ] && [[ "$o" == "alpha OK "*휴면* ]]; } && ok "ⓗ 라이브 0 → OK 휴면" || bad "ⓗ rc=$rc $o"

# ⓘ --all: 팀 줄 수 = 명부 수 · ERR 하나면 rc1
sess "byz-beta-arch-claude#1" "byz-beta-nano-a#0"
o="$(chk --all)"; rc=$?; { [ "$rc" = 1 ] && [ "$(grep -c . <<<"$o")" = 2 ]; } && ok "ⓘ --all 2팀 2줄 · beta ERR → rc1" || bad "ⓘ rc=$rc $o"

# ⓙ 없는 팀 · 표 깨짐 → ERROR (조용한 통과 0)
o="$(chk nope)"; rc=$?; { [ "$rc" != 0 ] && [[ "$o" == *ERROR* ]]; } && ok "ⓙ 명부 없는 팀 → ERROR" || bad "ⓙ rc=$rc $o"
printf '# 표 없음\n' > "$T/bad.md"; o="$(MDX="$T/bad.md" chk alpha)"; rc=$?; { [ "$rc" != 0 ] && [[ "$o" == *ERROR* ]]; } && ok "ⓙ 표 없는 TEAMSET → ERROR" || bad "ⓙ-2 rc=$rc $o"

# ⓚ 실 표 — design/TEAMSET.md 가 도구로 읽히고 harness=4 · ops=5 · 기본 3(v65 5)
for spec in harness:4 ops:5 v65:5 cfo:3; do
  t="${spec%:*}"; n="${spec#*:}"
  pfx="byz-$t-nano-"; [ "$t" = v65 ] && pfx="ft-v65-temp-"
  o="$(PATH="$FAKE:$PATH" python3 "$BIN/ft_teamset.py" cap --root "$ROOT" --md "$REPO/design/TEAMSET.md" --prefix "$pfx" 2>&1)"
  [[ "$o" == *"cap=$n"* ]] && ok "ⓚ 실 표 $t 상한 $n" || bad "ⓚ $t → $o"
done

# ⓛ 큐(DA r1 ⑦) — 카드 경로 절대 · 순번 · 중복 0 · 카드가 대기 자리에서 사라지면(= spawn 성공) 항목 완료
Q="$ROOT/.fable-team/state/spawn-queue-alpha.tsv"; rm -f "$Q" "${Q%.tsv}.notified"; mkdir -p "$T/cards/대기" "$T/cards/진행"; : > "$T/cards/대기/c1.md"; : > "$T/cards/대기/c2.md"
q() { python3 "$BIN/ft_spawn_queue.py" "$@" --root "$ROOT" --prefix byz-alpha-nano- 2>&1; }
roster alpha "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1"
o1="$(q add --card "$T/cards/대기/c1.md" --from m#1)"; o2="$(q add --card "$T/cards/대기/c2.md" --from m#1)"; o3="$(q add --card "$T/cards/대기/c1.md" --from m#1)"
{ [[ "$o1" == "QUEUED alpha 순번=1"* ]] && [[ "$o2" == "QUEUED alpha 순번=2"* ]] && [[ "$o3" == "QUEUED alpha 순번=1"* ]] && [ "$(grep -c . "$Q")" = 2 ]; } && ok "ⓛ 큐 추가 순번 1·2 · 같은 카드 중복 0" || bad "ⓛ $o1 / $o2 / $o3"
# DA⑥ ② — 카드 경로가 사라진 것만으로는 완료 아님(소실 0): 명부 행 없이 사라지면 확인 필요로 남는다 · 진행/ 이동 + 명부 index 일치 = spawn 성공 → 완료
rm "$T/cards/대기/c1.md"; o="$(q stuck)"
{ [[ "$o" == *"/대기/c1.md" ]] && [ "$(grep -c . "$Q")" = 2 ]; } && ok "ⓛ 카드만 사라짐(명부 행 없음) → 큐 유지 · 확인 필요 1" || bad "ⓛ-2 $o"
mv "$T/cards/대기/c2.md" "$T/cards/진행/c2.md"; o="$(q stuck)"
{ [ "$(grep -c . <<<"$o")" = 2 ] && [ "$(grep -c . "$Q")" = 2 ]; } && ok "ⓛ 진행/ 로 옮겨졌어도 명부 행 없으면 완료 아님" || bad "ⓛ-3 $o"
printf '{"_name":"alpha","_master":"byz-alpha-master-claude#1","_arch":"byz-alpha-arch-claude#1","byz-alpha-nano-q#0":{"role":"nano","index":"%s"}}\n' "$T/cards/진행/c2.md" > "$ROOT/.fable-team/seats-alpha.json"
q stuck >/dev/null; { [ "$(grep -c . "$Q")" = 1 ] && grep -q 'c1.md' "$Q" && ! grep -q 'c2.md' "$Q"; } && ok "ⓛ 진행/ + 명부 index 일치(spawn 성공) → c2 만 완료로 지운다" || bad "ⓛ-4 $(cat "$Q")"
rm -f "$Q"

# ⓝ 알림 = teamset-check 가 매 실행 «빈 석 ∧ 큐 비지 않음» 이면 현역 _master 에 멱등 쪽지 (같은 카드 10분 1번 · 쪽지 실패면 표식 0 → 다음 실행 재시도)
roster alpha "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1"; rm -f "${Q%.tsv}.notified" "$T/mbox.log"; : > "$T/cards/대기/c2.md"; q add --card "$T/cards/대기/c2.md" --from m#1 >/dev/null
sess "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-alpha-nano-x#0" "byz-alpha-nano-y#0" "byz-alpha-nano-z#0"
o="$(chk alpha)"; { [ ! -f "$T/mbox.log" ] && [[ "$o" != *"큐 알림"* ]]; } && ok "ⓝ 빈 석 0(3/3) → 쪽지 0" || bad "ⓝ-1 $o"
sess "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-alpha-nano-x#0"
touch "$T/mbox.fail"; o="$(chk alpha)"; { [[ "$o" == *WARN* ]] && [ ! -f "${Q%.tsv}.notified" ]; } && ok "ⓝ 쪽지 실패 → 표식 0 · 큐 유지" || bad "ⓝ-2 $o"
: > "$T/mbox.log"
rm -f "$T/mbox.fail"; o="$(chk alpha)"
{ [[ "$o" == *"큐 알림 c2.md"* ]] && [ "$(grep -c . "$T/mbox.log")" = 1 ] && grep -F 'send byz-alpha-master-claude#1 ft-teamset-check' "$T/mbox.log" | grep -qF 'c2.md'; } && ok "ⓝ 빈 석 ∧ 큐 → 현역 _master 에 쪽지 1통" || bad "ⓝ-3 $o / $(cat "$T/mbox.log" 2>/dev/null)"
o="$(chk alpha)"; [ "$(grep -c . "$T/mbox.log")" = 1 ] && ok "ⓝ 같은 카드 10분 안 재실행 → 재발신 0(멱등)" || bad "ⓝ-4 $o"
printf '%s\t0' "$T/cards/c2.md" > "${Q%.tsv}.notified"; o="$(chk alpha)"; [ "$(grep -c . "$T/mbox.log")" = 2 ] && ok "ⓝ 10분 지난 표식 → 다시 알림(승계·쪽지 유실 대비)" || bad "ⓝ-5 $o"
rm "$T/cards/대기/c2.md"; : > "$T/mbox.log"; rm -f "${Q%.tsv}.notified"; o="$(chk alpha)"
{ [ ! -s "$T/mbox.log" ] && [[ "$o" == "alpha WARN "*"큐 확인 필요 1"* ]] && [ -s "$Q" ]; } && ok "ⓝ 카드가 사라진 항목 → 쪽지 0 · 큐 유지 · WARN 확인 필요" || bad "ⓝ-6 $o"
# DA⑥ ① — 활성 팀 _master 검증: 없음·다른 팀 master·형식 위반 → ERR + 쪽지 0
: > "$T/cards/대기/c2.md"; : > "$T/mbox.log"; rm -f "${Q%.tsv}.notified"
sess "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-alpha-nano-x#0" "byz-beta-master-claude#1"
roster alpha "byz-beta-master-claude#1" "byz-alpha-arch-claude#1"
o="$(chk alpha)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == "alpha ERR "*"형식·소속 위반"* ]] && [ ! -s "$T/mbox.log" ]; } && ok "ⓝ 다른 팀 라이브 master 를 _master 로 → ERR rc1 · 쪽지 0" || bad "ⓝ-8 rc=$rc $o / $(cat "$T/mbox.log")"
printf '{"_name":"alpha","_arch":"byz-alpha-arch-claude#1"}\n' > "$ROOT/.fable-team/seats-alpha.json"
o="$(chk alpha)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == "alpha ERR "*"_master 없음"* ]] && [ ! -s "$T/mbox.log" ]; } && ok "ⓝ _master 칸 없음 → ERR · 쪽지 0" || bad "ⓝ-9 rc=$rc $o"
roster alpha "alpha-master#1" "byz-alpha-arch-claude#1"; sess "alpha-master#1" "byz-alpha-nano-x#0" "byz-alpha-arch-claude#1"
o="$(chk alpha)"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == *"형식·소속 위반"* ]] && [ ! -s "$T/mbox.log" ]; } && ok "ⓝ 이름 형식 위반 _master(라이브여도) → ERR · 쪽지 0" || bad "ⓝ-10 rc=$rc $o"
roster alpha "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1"
! grep -q 'ft_spawn_queue' "$BIN/ft-nano-close.sh" && ok "ⓝ ft-nano-close.sh 는 큐를 모른다(알림은 teamset-check 한 곳)" || bad "ⓝ-7 nano-close 에 큐 호출 잔존"

# ⓜ 키트 사본 cmp 0
for f in ft-teamset-check.sh ft_teamset.py ft_spawn_queue.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 불일치 $f"; done
[ "$(git config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare != false"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit $fail
