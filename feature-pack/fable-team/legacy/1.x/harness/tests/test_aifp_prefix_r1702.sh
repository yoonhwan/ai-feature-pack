#!/usr/bin/env bash
# test_aifp_prefix_r1702.sh — r1702: 팀 접두 표(TEAM_PREFIX) 한 곳 — aifp 좌석(aifp-ft-) 을 팀셋 검사·좌석 정보·좌석 상한이 그 팀으로 센다.
#   ⓐ check --team aifp 가 라이브 aifp 좌석 3석에서 «휴면» 아님 · 나노 1/3 · «master 없음» 0
#   ⓑ seat-info 'aifp-ft-nano-k1#0' → 팀 aifp · 접두 aifp-ft-nano- · 키 k1 rc0   ⓒ team-of --prefix aifp-ft-nano- → aifp
#   ⓓ ft_seat_cap.py: FT_NANO_PREFIX=aifp-ft-nano- · 상한 1 · 라이브 나노 1석 → REJECT «좌석 상한 aifp 1/1» · 0석이면 통과
#   ⓔ 표 밖 팀(harness)은 앞 판과 같다 · v65 옛 접두 그대로   ⓕ 팀 사이 섞임 0   ⓖ 회귀 4파일 rc0
# 임시 루트·가짜 tmux(PATH)만 · 실 tmux·실 명부 0 · sleep 0 · 사례 70초 · 새 파일 100644
set -uo pipefail
export LC_ALL=C FT_ALLOW_TRACKED_BIN=1
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
BIN="${R1702_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
ROOT="$T/root"; FAKE="$T/fake"; SESS="$T/sessions.txt"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/design/teams/aifp/indices" "$ROOT/design/teams/harness/indices" "$FAKE"
cat > "$ROOT/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 | 오케 | 상태 |
|---|---|---|---|
| aifp | `design/teams/aifp/` | aifp-ft-master-pi | 현역 |
| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |
EOF
cat > "$T/TEAMSET.md" <<'EOF'
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
| aifp | 3 | 0 | 상시 |
| harness | 3 | 0 | 상시 |
EOF
printf '#!/bin/sh\ncase "$1" in list-sessions) cat %s;; *) exit 1;; esac\n' "$SESS" > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
roster(){ printf '{"_name":"%s","_master":"%s","_arch":"%s","_cards":"design/teams/%s/indices","_cards_wt":""}\n' "$1" "$2" "$3" "$1" > "$ROOT/.fable-team/seats-$1.json"; }
roster aifp "aifp-ft-master-pi#5" "aifp-ft-arch-pi#0"
roster harness "byz-harness-master-pi#71" "byz-harness-arch-pi#1"
sess(){ : > "$SESS"; local n; for n in "$@"; do echo "$n" >> "$SESS"; done; }
FM="$T/fake-mbox.sh"; printf '#!/bin/sh\nexit 0\n' > "$FM"; chmod +x "$FM"
FS="$T/fake-status.sh"; printf '#!/bin/sh\necho "IDLE - - - jsonl"\n' > "$FS"; chmod +x "$FS"
ts(){ ( cd "$ROOT" && PATH="$FAKE:$PATH" FT_TEAMSET_MBOX="$FM" FT_SEAT_STATUS="$FS" ZC_RESUME_DIR="$T/res" python3 "$1/ft_teamset.py" "${@:2}" 2>&1 ); }
chk(){ ts "$1" check --root "$ROOT" --md "$T/TEAMSET.md" --team "${2}" 2>&1; }
cap(){ ( cd "$ROOT" && PATH="$FAKE:$PATH" FT_NANO_PREFIX="$2" FT_TEAM_SEAT_CAP="$3" python3 "$1/ft_seat_cap.py" --root "$ROOT" 2>&1 ); }

# ── ⓐ 실사건 꼴: aifp 라이브 3석 + 나노 1석 → «휴면» 아님 · 나노 1/3 · master 없음 0
sess "aifp-ft-master-pi#5" "aifp-ft-arch-pi#0" "aifp-ft-nano-k1#0"
o="$(chk "$BIN" aifp)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *"휴면"* ]] && [[ "$o" == *"나노 1/3"* ]] && [[ "$o" != *"master 없음"* ]]; } \
  && ok "ⓐ aifp 라이브 3석 → «휴면» 아님 · 나노 1/3 · master 있음" || bad "ⓐ rc=$rc «$o»"
# ── ⓑ seat-info · ⓒ team-of
o="$(ts "$BIN" seat-info 'aifp-ft-nano-k1#0')"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *aifp* ]] && [[ "$o" == *"aifp-ft-nano-"* ]] && [[ "$o" == *k1* ]]; } \
  && ok "ⓑ seat-info aifp-ft-nano-k1#0 → 팀 aifp · 접두 aifp-ft-nano- · 키 k1" || bad "ⓑ rc=$rc «$o»"
o="$(ts "$BIN" team-of --prefix aifp-ft-nano-)"; rc=$?
{ [ "$rc" = 0 ] && [ "$(tr -d '[:space:]' <<<"$o")" = aifp ]; } && ok "ⓒ team-of --prefix aifp-ft-nano- → aifp" || bad "ⓒ rc=$rc «$o»"
# ── ⓓ 좌석 상한: aifp 팀 읽기 + aifp 나노를 셈
o="$(cap "$BIN" aifp-ft-nano- 1)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT"* ]] && [[ "$o" == *"aifp"*"1/1"* ]]; } \
  && ok "ⓓ aifp 나노 1석 · 상한 1 → REJECT «좌석 상한 aifp 1/1»" || bad "ⓓ rc=$rc «$o»"
sess "aifp-ft-master-pi#5" "aifp-ft-arch-pi#0"
o="$(cap "$BIN" aifp-ft-nano- 1)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" != *"REJECT"* ]]; } && ok "ⓓ aifp 나노 0석 · 상한 1 → 통과" || bad "ⓓ rc=$rc «$o»"
# ── ⓔ 표 밖 팀(harness) 회귀 · v65 옛 접두
o="$(ts "$BIN" seat-info 'byz-harness-nano-x#0')"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *harness* ]] && [[ "$o" == *"byz-harness-nano-"* ]]; } && ok "ⓔ harness seat-info 지금 그대로" || bad "ⓔ rc=$rc «$o»"
o="$(ts "$BIN" team-of --prefix byz-harness-nano-)"; [ "$(tr -d '[:space:]' <<<"$o")" = harness ] && ok "ⓔ harness team-of 지금 그대로" || bad "ⓔ «$o»"
o="$(ts "$BIN" team-of --prefix ft-v65-temp-)"; [ "$(tr -d '[:space:]' <<<"$o")" = v65 ] && ok "ⓔ v65 옛 접두 그대로" || bad "ⓔ «$o»"
sess "byz-harness-master-pi#71" "byz-harness-arch-pi#1" "byz-harness-nano-x#0"
o="$(chk "$BIN" harness)"; { [[ "$o" == *"나노 1/3"* ]] && [[ "$o" != *"휴면"* ]]; } && ok "ⓔ harness check 지금 그대로(나노 1/3)" || bad "ⓔ «$o»"
# ── ⓕ 섞임 0: byz-aifp-nano- 는 aifp 표 접두가 아니다 · aifp 좌석은 harness 셈에 안 든다
sess "byz-aifp-master-pi#1" "byz-aifp-arch-pi#1" "byz-aifp-nano-z#0"
o="$(chk "$BIN" aifp)"; [[ "$o" == *"휴면"* ]] && ok "ⓕ byz-aifp-nano-z#0 은 aifp 표 접두로 안 센다(휴면)" || bad "ⓕ «$o»"
sess "byz-harness-master-pi#71" "byz-harness-arch-pi#1" "aifp-ft-nano-k1#0"
o="$(chk "$BIN" harness)"; [[ "$o" == *"나노 0/3"* ]] && ok "ⓕ aifp-ft-nano- 좌석은 harness 셈에 안 든다(나노 0/3)" || bad "ⓕ «$o»"
# ── ⓖ 회귀 4파일 — FAIL 줄 0(앞 판과 같다)
PRW="$T/pristine-wt"; git -C "$REPO" worktree add -q --detach "$PRW" HEAD 2>/dev/null
T4="test_teamset_check.sh test_seat_cap_nano_only_r666.sh test_nano_spawn_teamset_cap.sh test_teamset_standby_r1119.sh"
n_now=0; n_old=0
for t in $T4; do
  n_now=$((n_now + $(timeout 70 bash "$HERE/$t" 2>&1 | grep -cE '^FAIL ')))
  n_old=$((n_old + $(timeout 70 bash "$PRW/feature-pack/fable-team/legacy/1.x/harness/tests/$t" 2>&1 | grep -cE '^FAIL ')))
done
git -C "$REPO" worktree remove --force "$PRW" 2>/dev/null
[ "$n_now" = "$n_old" ] && ok "ⓖ 회귀 4파일 FAIL 줄 앞 판과 같다($n_now = $n_old)" || bad "ⓖ 회귀 FAIL 줄 다름(이번 $n_now ≠ 앞 판 $n_old)"
for f in ft_teamset.py ft_seat_cap.py; do cmp -s "$REPO/harness/bin/$f" "$KIT/$f" && ok "ⓖ bin·kit cmp 0 $f" || bad "ⓖ bin·kit 불일치 $f"; done
# ── 기준판(고침 전) Red — HEAD 판 사본으로 돌리면 ⓐ~ⓓ 가 실패해야 한다
PRIS="$T/pristine"; mkdir -p "$PRIS"; cp -R "$REPO/harness/bin/." "$PRIS/"
for f in ft_teamset.py ft_seat_cap.py; do git -C "$REPO" show "HEAD:feature-pack/fable-team/legacy/1.x/harness/bin/$f" > "$PRIS/$f" 2>/dev/null; done
sess "aifp-ft-master-pi#5" "aifp-ft-arch-pi#0" "aifp-ft-nano-k1#0"
o="$(chk "$PRIS" aifp)"; { [[ "$o" == *"휴면"* ]]; } && ok "Red ⓐ — 고침 전 판은 aifp 를 «휴면» 으로 답한다" || bad "Red ⓐ 확인 실패 «$o»"
o="$(ts "$PRIS" seat-info 'aifp-ft-nano-k1#0')"; { [ "$?" != 0 ]; } && ok "Red ⓑ — 고침 전 판 seat-info rc≠0" || bad "Red ⓑ 확인 실패 «$o»"
o="$(cap "$PRIS" aifp-ft-nano- 1)"; { [[ "$o" == *"못 읽"* ]]; } && ok "Red ⓓ — 고침 전 판 seat_cap 팀 못 읽음" || bad "Red ⓓ 확인 실패 «$o»"
# ── 변이 3종(사본에서만 · 변이마다 원본 반대 결과 대조)
mkx(){ local d="$T/m-$1"; mkdir -p "$d"; cp -R "$BIN/." "$d/"   # 형제 모듈(ft_team_lib 등)까지 — 변이 사본이 그대로 돈다
  python3 - "$d" "$2" "$3" <<'PY'
import sys, pathlib
d, old, new = sys.argv[1:4]
for name in ("ft_teamset.py", "ft_seat_cap.py"):
    p = pathlib.Path(d) / name
    s = p.read_text(encoding="utf-8")
    if old in s:
        p.write_text(s.replace(old, new, 1), encoding="utf-8"); print("MUT " + name, file=sys.stderr); break
else:
    raise SystemExit("변이 대상 없음: " + old[:60])
PY
  printf '%s\n' "$d"; }
X="$(mkx m1 'TEAM_PREFIX = {"aifp": "aifp-ft-"}' 'TEAM_PREFIX = {}')"
o="$(chk "$X" aifp)"; o2="$(chk "$BIN" aifp)"
{ [[ "$o" == *"휴면"* ]] && [[ "$o2" != *"휴면"* ]]; } && ok "M1 표 행 삭제 → ⓐ FAIL(원본은 통과 · 대조)" || bad "M1 검출 실패 «$o»"
o="$(ts "$X" seat-info 'aifp-ft-nano-k1#0')"; o2="$(ts "$BIN" seat-info 'aifp-ft-nano-k1#0')"
{ [ "$?" != 0 ] || [[ "$o" == *"아니다"* || "$o" == *ERROR* ]]; } && { [[ "$o2" == *"aifp-ft-nano-"* ]]; } && ok "M2(M1 동반) seat-info → 실패(원본은 통과 · 대조)" || bad "M2 검출 실패 «$o» / «$o2»"
X="$(mkx m3 'if not any(s.startswith(f"{team_prefix(team)}master-") for s in mine):' 'if not any(s.startswith(f"byz-{team}-master-") for s in mine):')"
o="$(chk "$X" aifp)"; o2="$(chk "$BIN" aifp)"
{ [[ "$o" == *"master 없음"* ]] && [[ "$o2" != *"master 없음"* ]]; } && ok "M3 check_team master 검사 byz 고정 → ⓐ FAIL(원본 대조)" || bad "M3 검출 실패 «$o»"
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
