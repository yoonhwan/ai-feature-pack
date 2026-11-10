#!/usr/bin/env bash
# test_r962_tick_install_root_bin_only.sh — r962: 데몬 설치 시작 경로 = «실제 경로 기준 공용 루트 .fable-team/bin 아래» 만.
#   ⓐ 루트 bin 절대 경로 → plist 생성 · ProgramArguments[1] = 루트 bin(실제 경로)
#   ⓑ v6 워크트리 bin → REJECT · plist 0 (진짜 git worktree 픽스처 — 경로 글자가 아니라 공용 루트로 판정)
#   ⓒ 상대 경로: 루트 bin 을 가리키면 통과 · 밖을 가리키면 REJECT
#   ⓓ `<루트>/.fable-team/bin/../../x` → REJECT · 루트 bin 을 가리키는 심볼릭 링크 → 통과 · 밖을 가리키는 심볼릭 링크 → REJECT
#   ⓔ 팀 갈래(FT_TICK_TEAM)도 같은 함수 — ⓑ·ⓓ 와 같은 입력에 같은 결과 · 메인 갈래와 함수 하나만 쓴다(변이로 확인)
#   ⓩ r3: plist 렌더 = 함수 1개(python plistlib 값 넣기 · 글자 치환 0)
#     ⓩ1 `a&b.sh` 링크 → 값이 realpath 그대로  ⓩ2 특수문자 5꼴(공백 \ | < __SCRIPT__) 값 보존 + lint rc0
#     ⓩ3 메인 렌더본을 팀 --from 으로 → ProgramArguments[1]·공유 env 값 같다  ⓩ4 모르는 표식(__X__) → rc≠0 · 파일 0
#     ⓩ5 r784·r962 r1 회귀(상대경로·다른 리포 링크·루트 bin 밖) — 변이 4: sed 되살림·팀 두 벌·잔재 검사 삭제·rc 미검사 파일 쓰기
#   ⓙ r4: 사용자 글자 안에 «아는» 표식이 섞인 값(root__SCRIPT__ 폴더 · goal__SCRIPT__.sh 파일 · --from 의 같은 값) → 메인·팀 rc0 · 값 보존
#     ⓚ 모르는 표식(__NEW__) = 값 «전체» 인 칸 → ERROR · 렌더본 0   (변이 8: «잔재 검사를 모든 값에» → ⓙ FAIL)
#   ⓠ r6: «칸 전체» = 값 그대로(앞뒤 공백 포함) — " __X__ " 같은 공백 값은 표식 하나만의 값이 아니다 → 메인·팀 rc0 · 값 보존
#     ⓠ2 공백 없는 "__X__"·"__SCRIPT__" 는 그대로 rc≠0 · plist 0   (변이 9: .strip() 되살림 → ⓠ1 FAIL)
#   ⓨ r7: ProgramArguments = 옛 판(1545012e)과 같게 «두 번째 칸부터 끝까지 [script] 로 대체» — 뒤 인자 삭제 · 빈 배열 → [bash, script]
#     메인(틀)·팀(--from) 같은 함수 · 뒤 인자 있음·없음·빈 배열 3꼴   (변이 10: «두 번째 칸만 교체» → ⓨ FAIL)
# 실 launchd·실 ~/Library/LaunchAgents 0 — HOME·FT_TICK_PLIST_DIR 를 임시 폴더로 돌린다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KBIN="$REPO/harness/kit/fable-team/bin"; KBIN_BIN="$REPO/harness/bin"
INST="$KBIN/ft-tick-install.sh"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
eq()  { chk "$3" "$1" "$2"; }
# r7 위생: 변이 생성 python 이 예외(AssertionError 등)로 죽으면 «변이가 잡힘» 이 아니라 «시험 오류» 다 — FAIL 로 센다.
mut_py() { python3 "$@" || bad "변이 생성 예외 — 변이 파일 미생성(시험 오류 · 변이 판정 무효)"; }
unset FT_ROOT FT_MBOX_DIR FT_TICK_MBOX FT_HARNESS_ROOT FT_TICK_TEAM_TSV FT_TICK_PLIST_DIR

bash -n "$INST" && ok "bash -n ft-tick-install.sh" || bad "bash -n ft-tick-install.sh"
chk "kit·bin 짝 cmp0" "$(cmp -s "$INST" "$KBIN_BIN/ft-tick-install.sh" && echo same || echo differ)" same

# ── 픽스처: 공용 루트(R · git 리포 · comm·bin) + v6 워크트리 + 루트 밖 폴더 ──
R="$TMP/root"; mkdir -p "$R/.fable-team/comm" "$R/.fable-team/bin"
git -C "$R" init -q -b main; git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
cp "$KBIN/ft-tick.sh" "$KBIN/ft-seat-status.sh" "$R/.fable-team/bin/"
git -C "$R" worktree add -q "$TMP/v6-wt" -b v6wt 2>/dev/null
WTB="$TMP/v6-wt/.fable-team/bin"; mkdir -p "$WTB"; cp "$KBIN/ft-tick.sh" "$KBIN/ft-seat-status.sh" "$WTB/"
OUT="$TMP/outside"; mkdir -p "$OUT"; cp "$KBIN/ft-tick.sh" "$KBIN/ft-seat-status.sh" "$OUT/"
printf 'x\n' > "$R/x.sh"
ln -s "$R/.fable-team/bin/ft-tick.sh" "$TMP/link-root.sh"
ln -s "$OUT/ft-tick.sh" "$TMP/link-out.sh"
B="$TMP/other-repo"; mkdir -p "$B"; git -C "$B" init -q -b main; git -C "$B" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
ln -s "$R/.fable-team/bin/ft-tick.sh" "$B/root-tick.sh"          # ⓕ 다른 리포에 놓인 링크 → 루트 bin 파일
ln -s "$OUT/ft-tick.sh" "$R/.fable-team/bin/leak-link.sh"        # ⓖ 루트 bin 안에 놓인 링크 → 밖 파일
export HOME="$TMP/home"; mkdir -p "$HOME"
LA="$HOME/Library/LaunchAgents"
PDIR="$TMP/plists"; mkdir -p "$PDIR"
python3 - "$TMP/from.plist" "$R" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p",
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY

main() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE FT_TICK_PRINT_PLIST=1 bash "$1" --worktree "$R" --script "$2" "${@:3}" 2>&1; echo "rc=$?"; }
team() { ( cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE FT_TICK_TEAM_TSV="$KBIN/team-tick-env.tsv" FT_TICK_PLIST_DIR="$PDIR" \
           bash "$1" --team ops --from "$TMP/from.plist" --script "$2" "${@:3}" 2>&1 ); echo "rc=$?"; }
rc() { printf '%s\n' "$1" | sed -n '$s/^rc=//p'; }
errs() { printf '%s\n' "$1" | grep -c '^ERROR'; }
pa1() {  # $1 = 출력 텍스트 → ProgramArguments[1] (없으면 <none>)
  printf '%s\n' "$1" | sed -n '/^<?xml/,/<\/plist>/p' > "$TMP/p.plist"
  python3 -c 'import plistlib,sys
try: print(plistlib.load(open(sys.argv[1],"rb"))["ProgramArguments"][1])
except Exception: print("<none>")' "$TMP/p.plist" 2>/dev/null
}

# ── ⓐ 루트 bin 절대 경로 → plist 생성 · 경로 = 루트 bin ──
o="$(main "$INST" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓐ 루트 bin 절대 경로 rc" "$(rc "$o")" 0
chk "ⓐ ProgramArguments[1] = 루트 bin" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"

# ── ⓑ v6 워크트리 bin → REJECT · plist 0 ──
o="$(main "$INST" "$WTB/ft-tick.sh")"
chk "ⓑ v6 워크트리 bin → rc≠0" "$([ "$(rc "$o")" != 0 ] && echo no || echo yes)" no
chk "ⓑ ERROR 1줄" "$(errs "$o")" 1
chk "ⓑ plist 쓰기 0" "$(ls "$LA" 2>/dev/null | wc -l | tr -d ' ')" 0
# 양성 대조: 같은 픽스처의 루트 bin 은 통과한다(픽스처가 «무조건 거절» 이 아님)
o="$(main "$INST" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓑ 양성 대조(같은 픽스처 루트 bin) rc" "$(rc "$o")" 0

# ── ⓒ 상대 경로 — 루트 bin 안 = 통과 · 밖 = REJECT ──
o="$(cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE FT_TICK_PRINT_PLIST=1 bash "$INST" --worktree "$R" --script .fable-team/bin/ft-tick.sh --dry-run 2>&1; echo "rc=$?")"
chk "ⓒ 상대 경로(루트 bin) rc" "$(rc "$o")" 0
chk "ⓒ 상대 경로(루트 bin) → 실제 경로로 풀려 plist 값" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"
o="$(cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash "$INST" --worktree "$R" --script ../outside/ft-tick.sh --dry-run 2>&1; echo "rc=$?")"
chk "ⓒ 상대 경로(밖) → REJECT rc" "$(rc "$o")" 1
chk "ⓒ 상대 경로(밖) ERROR 1줄 · plist 0" "$(errs "$o")/$(printf '%s\n' "$o" | grep -c '^<?xml')" 1/0

# ── ⓓ `..` · 심볼릭 링크 ──
o="$(main "$INST" "$R/.fable-team/bin/../../x.sh" --dry-run)"
chk "ⓓ <루트>/.fable-team/bin/../../x → REJECT rc" "$(rc "$o")" 1
o="$(main "$INST" "$R/.fable-team/bin/../ft-tick.sh" --dry-run)"
chk "ⓓ bin/../ft-tick.sh(= 루트 밖) → REJECT rc" "$(rc "$o")" 1
o="$(main "$INST" "$TMP/link-root.sh" --dry-run)"
chk "ⓓ 루트 bin 을 가리키는 심볼릭 링크 rc" "$(rc "$o")" 0
chk "ⓓ 링크 → 실제 경로가 plist 값" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"
o="$(main "$INST" "$TMP/link-out.sh" --dry-run)"
chk "ⓓ 밖을 가리키는 심볼릭 링크 → REJECT rc" "$(rc "$o")" 1

# ── ⓔ 팀 갈래도 같은 함수 ──
o="$(team "$INST" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓔ 팀 갈래 루트 bin rc" "$(rc "$o")" 0
chk "ⓔ 팀 갈래 루트 bin → ProgramArguments[1]" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"
o="$(team "$INST" "$WTB/ft-tick.sh")"
chk "ⓔ 팀 갈래 v6 워크트리 bin → REJECT rc · ERROR 1줄" "$(rc "$o")/$(errs "$o")" 1/1
chk "ⓔ 팀 갈래 REJECT: plist 쓰기 0" "$(ls "$PDIR" | wc -l | tr -d ' ')" 0
o="$(team "$INST" "$R/.fable-team/bin/../../x.sh" --dry-run)"
chk "ⓔ 팀 갈래 .. 우회 → REJECT rc" "$(rc "$o")" 1
o="$(team "$INST" "$TMP/link-root.sh" --dry-run)"
chk "ⓔ 팀 갈래 링크 → 실제 경로" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"
o="$(team "$INST" "$OUT/ft-tick.sh" --dry-run)"
chk "ⓔ 팀 갈래 루트 밖 절대 경로 → REJECT rc" "$(rc "$o")" 1

# ── ⓕⓖ 경계 판정 = «링크를 끝까지 푼 실제 파일의 부모 폴더» 만 (DA⑥ r2 반례: 링크 폴더로 판정했다) ──
o="$(main "$INST" "$B/root-tick.sh" --dry-run)"
chk "ⓕ 다른 리포 링크(→ 루트 bin) 메인 갈래 rc" "$(rc "$o")" 0
chk "ⓕ 메인 갈래 → 실제 경로가 plist 값" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"
o="$(team "$INST" "$B/root-tick.sh" --dry-run)"
chk "ⓕ 다른 리포 링크(→ 루트 bin) 팀 갈래 rc" "$(rc "$o")" 0
chk "ⓕ 팀 갈래 → 실제 경로가 plist 값" "$(pa1 "$o")" "$R/.fable-team/bin/ft-tick.sh"
o="$(main "$INST" "$R/.fable-team/bin/leak-link.sh")"
chk "ⓖ 루트 bin 안 링크(→ 밖 파일) 메인 갈래 REJECT rc·ERROR 1줄" "$(rc "$o")/$(errs "$o")" 1/1
chk "ⓖ REJECT: plist 쓰기 0" "$(ls "$LA" 2>/dev/null | wc -l | tr -d ' ')" 0
o="$(team "$INST" "$R/.fable-team/bin/leak-link.sh")"
chk "ⓖ 루트 bin 안 링크(→ 밖 파일) 팀 갈래 REJECT rc" "$(rc "$o")" 1

# ── 변이 1: 검사 함수를 «메인 갈래만» 부르게 하면 ⓔ(팀) 가 뚫린다 ──
mut_py - "$INST" "$TMP/mut-teamonly.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
team_call = '  SCRIPT="$(ft_tick_root_bin_script "$SCRIPT")" || { echo "$SCRIPT"; exit 1; }'
assert src.count(team_call) == 1, "팀 갈래 호출 1곳: %d" % src.count(team_call)
assert src.count('SCRIPT="$(ft_tick_root_bin_script "$SCRIPT")"') == 2, "두 갈래 호출: %d" % src.count('SCRIPT="$(ft_tick_root_bin_script "$SCRIPT")"')
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(team_call, '  : # 변이: 팀 갈래 검사 제거', 1))
PY
chk "변 1 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$TMP/mut-teamonly.sh" && echo same || echo changed)" changed
chk "변 1 고친 곳 = 팀 갈래 1곳(메인 보존)" "$(grep -c 'ft_tick_root_bin_script "$SCRIPT"' "$TMP/mut-teamonly.sh")" 1
o="$(team "$TMP/mut-teamonly.sh" "$WTB/ft-tick.sh" --dry-run)"
chk "변 1 «검사 함수를 메인만» → ⓔ FAIL(rc≠1)" "$([ "$(rc "$o")" = 1 ] && echo caught || echo leaked)" leaked

# ── 변이 2: realpath 를 빼고 «글자 비교» 로 바꾸면 ⓒ(상대 경로) 가 뚫린다 ──
mut_py - "$INST" "$TMP/mut-literal.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '  case "$real" in\n    "$root"/.fable-team/bin/?*) printf \'%s\\n\' "$real"; return 0;;\n  esac'
new = '  case "$p" in\n    "$root"/.fable-team/bin/?*) printf \'%s\\n\' "$p"; return 0;;\n  esac'
assert old in src
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new))
PY
chk "변 2 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$TMP/mut-literal.sh" && echo same || echo changed)" changed
o="$(team "$TMP/mut-literal.sh" "$R/.fable-team/bin/../../x.sh" --dry-run)"
chk "변 2 «realpath 빼고 글자 비교» → ⓓ 는 그대로 REJECT(리터럴 비교가 '..' 를 잡는다)" "$([ "$(rc "$o")" = 1 ] && echo caught || echo leaked)" caught
o="$(cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash "$TMP/mut-literal.sh" --worktree "$R" --script .fable-team/bin/ft-tick.sh --dry-run 2>&1; echo "rc=$?")"
chk "변 2 «realpath 빼고 글자 비교» → ⓒ FAIL(상대 경로가 안 풀린다)" "$([ "$(rc "$o")" = 1 ] && echo leaked || echo caught)" leaked

# ── env 틀 2: FT_BIN = 공용 루트 bin · 새 해석기 0(ft-harness-root.sh 함수 그대로) ──
PLANNER_ENV="$REPO/harness/kit/fable-team/bin-planner/planner-env.sh"; GRAPHICS_ENV="$REPO/harness/kit/graphics/graphics-env.sh"
for f in "$PLANNER_ENV" "$GRAPHICS_ENV"; do
  chk "env 틀 FT_BIN 공용 루트 bin — ${f#$REPO/}" "$(grep -c 'FT_BIN=.*\.fable-team/bin' "$f")" 1
  chk "env 틀 v6-realtime-live 글자 0 — ${f#$REPO/}" "$(grep -c 'v6-realtime-live/.fable-team/bin' "$f")" 0
done
bash -n "$PLANNER_ENV" && ok "planner-env.sh bash -n" || bad "planner-env.sh bash -n"
bash -n "$GRAPHICS_ENV" && ok "graphics-env.sh bash -n" || bad "graphics-env.sh bash -n"

# ── 변이 3: 경계 판정을 «링크가 놓인 폴더» 로 하면 ⓕ 가 뚫린다(DA⑥ r2 반례 그대로) ──
mut_py - "$INST" "$TMP/mut-linkdir.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '  root="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"'
new = '  root="$(git -C "$(cd -- "$(dirname -- "$p")" 2>/dev/null && pwd -P)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"'
assert old in src, "공용 루트 해석 줄을 못 찾음"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 3 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$TMP/mut-linkdir.sh" && echo same || echo changed)" changed
o="$(main "$TMP/mut-linkdir.sh" "$B/root-tick.sh" --dry-run)"
chk "변 3 «링크 폴더로 경계 판정» → ⓕ FAIL(rc≠0)" "$([ "$(rc "$o")" = 0 ] && echo leaked || echo caught)" caught

# ══ ⓩ r962 r3: 렌더 = 함수 1개(python plistlib 값 넣기) ═══════════════════════════════════════
plfile() { printf '%s\n' "$1" | sed -n '/^<?xml/,/<\/plist>/p' > "$TMP/pl.plist"; }
plint()  { plfile "$1"; plutil -lint "$TMP/pl.plist" >/dev/null 2>&1 && echo ok || echo bad; }
envkv()  { plfile "$1"; python3 -c 'import plistlib,sys
d = plistlib.load(open(sys.argv[1], "rb")); e = d.get("EnvironmentVariables") or {}
for k in sorted(e): print("%s=%s" % (k, e[k]))' "$TMP/pl.plist" 2>/dev/null; }
envget() { envkv "$1" | sed -n "s/^$2=//p"; }
wdval()  { plfile "$1"; python3 -c 'import plistlib,sys
try: print(plistlib.load(open(sys.argv[1], "rb")).get("WorkingDirectory", "<none>"))
except Exception: print("<none>")' "$TMP/pl.plist" 2>/dev/null; }
MUTD="$TMP/kitmut"; mkdir -p "$MUTD"; cp "$KBIN/ft-tick.plist" "$MUTD/"
BADK="$TMP/kitbad"; mkdir -p "$BADK"; cp "$INST" "$BADK/ft-tick-install.sh"
python3 - "$KBIN/ft-tick.plist" "$BADK/ft-tick.plist" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = "<string>/tmp/ft-tick.log</string>"
assert s.count(old) == 2, "틀의 로그 자리 2개: %d" % s.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "<string>__X__</string>", 1))   # r5: 거절 = 값 «전체» 가 표식
PY

# ── ⓩ1 r2 반례 그대로: `a&b.sh` 를 가리키는 링크 → 값이 realpath 그대로 ──
cp "$KBIN/ft-tick.sh" "$R/.fable-team/bin/a&b.sh"
ln -s "$R/.fable-team/bin/a&b.sh" "$R/.fable-team/bin/tick-amp.sh"
o="$(main "$INST" "$R/.fable-team/bin/tick-amp.sh" --dry-run)"
chk "ⓩ1 a&b.sh 링크 rc" "$(rc "$o")" 0
chk "ⓩ1 ProgramArguments[1] = realpath(a&b.sh)" "$(pa1 "$o")" "$R/.fable-team/bin/a&b.sh"

# ── ⓩ2 특수문자 5꼴 — 값 그대로 · plist lint rc0 ──
for nm in 'sp ace.sh' 'back\slash.sh' 'pi|pe.sh' 'lt<gt.sh' 'under__SCRIPT__.sh'; do
  cp "$KBIN/ft-tick.sh" "$R/.fable-team/bin/$nm"
  o="$(main "$INST" "$R/.fable-team/bin/$nm" --dry-run)"
  chk "ⓩ2 [$nm] rc·값 보존" "$(rc "$o")/$(pa1 "$o")" "0/$R/.fable-team/bin/$nm"
  chk "ⓩ2 [$nm] plist lint" "$(plint "$o")" ok
done

# ── ⓩ3 두 갈래 같은 함수 — 메인 렌더본을 팀 --from 으로(팀 갈래는 MASTER_MSG·PM_MSG 가 든 원본을 쓴다 — 틀에 문구가 없으면 팀이 거절하는게 정상 r199)
MSGK="$TMP/kitmsg"; mkdir -p "$MSGK"; cp "$INST" "$MSGK/ft-tick-install.sh"
python3 - "$KBIN/ft-tick.plist" "$MSGK/ft-tick.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
d["EnvironmentVariables"]["FT_TICK_MASTER_MSG"] = "m"
d["EnvironmentVariables"]["FT_TICK_PM_MSG"] = "p"
plistlib.dump(d, open(sys.argv[2], "wb"))
PY
o_main="$(main "$MSGK/ft-tick-install.sh" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
plfile "$o_main"; cp "$TMP/pl.plist" "$TMP/main-render.plist"
MAIN_KEYS="$(python3 -c 'import plistlib,sys
d = plistlib.load(open(sys.argv[1], "rb"))
print(" ".join(sorted((d.get("EnvironmentVariables") or {}).keys())))' "$TMP/main-render.plist")"
o_team="$(team "$INST" "$R/.fable-team/bin/ft-tick.sh" --from "$TMP/main-render.plist" --dry-run)"
chk "ⓩ3 팀 갈래(--from 메인 plist) rc" "$(rc "$o_team")" 0
chk "ⓩ3 ProgramArguments[1] 두 갈래 같다" "$(pa1 "$o_team")" "$(pa1 "$o_main")"
diffn=0
for k in $MAIN_KEYS; do [ "$(envget "$o_main" "$k")" = "$(envget "$o_team" "$k")" ] || diffn=$((diffn+1)); done
chk "ⓩ3 공유 env 키 값 두 갈래 같다(다른 키 수)" "$diffn" 0
chk "ⓩ3 팀 갈래 FT_TICK_SEAT_STATUS = 공용 bin" "$(envget "$o_team" FT_TICK_SEAT_STATUS)" "$R/.fable-team/bin/ft-seat-status.sh"

# ── ⓩ4 모르는 표식(__X__) = fail-closed ──
o="$(main "$BADK/ft-tick-install.sh" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓩ4 메인 갈래 모르는 표식 → rc≠0" "$(rc "$o")" 1
chk "ⓩ4 메인 갈래 렌더본 출력 0" "$(printf '%s\n' "$o" | grep -c '^<?xml')" 0
chk "ⓩ4 메인 갈래 plist 쓰기 0" "$(ls "$LA" 2>/dev/null | wc -l | tr -d ' ')" 0
python3 - "$TMP/from.plist" "$TMP/from-bad.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")); d["EnvironmentVariables"]["FT_TICK_EXTRA"] = "__X__"
plistlib.dump(d, open(sys.argv[2], "wb"))
PY
o="$(team "$INST" "$R/.fable-team/bin/ft-tick.sh" --from "$TMP/from-bad.plist" --dry-run)"
chk "ⓩ4 팀 갈래 모르는 표식 → rc≠0" "$(rc "$o")" 1
chk "ⓩ4 팀 갈래 렌더본 출력 0" "$(printf '%s\n' "$o" | grep -c '^<?xml')" 0
chk "ⓩ4 팀 갈래 plist 쓰기 0" "$(ls "$PDIR" | wc -l | tr -d ' ')" 0

# ── ⓩ5 r784·r962 r1 회귀(기존 칸 그대로) ──
o="$(cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE bash "$INST" --worktree "$R" --script ../outside/ft-tick.sh --dry-run 2>&1; echo "rc=$?")"
chk "ⓩ5 상대경로(밖) 회귀 REJECT" "$(rc "$o")" 1
o="$(main "$INST" "$B/root-tick.sh" --dry-run)"
chk "ⓩ5 다른 리포 링크 회귀 → 실제 경로" "$(rc "$o")/$(pa1 "$o")" "0/$R/.fable-team/bin/ft-tick.sh"
o="$(main "$INST" "$OUT/ft-tick.sh" --dry-run)"
chk "ⓩ5 루트 bin 밖 회귀 REJECT" "$(rc "$o")" 1
chk "글자 치환·sed 줄 0(계약 ①)" "$(grep -c 'sed -e' "$INST")" 0
chk "렌더 함수 1개(plistlib.dumps 1곳)" "$(grep -c 'plistlib.dumps' "$INST")" 1

# ── 변이 4: «렌더 함수 대신 sed 되살림» → ⓩ1·ⓩ2 FAIL ──
mut_py - "$INST" "$MUTD/mut-sed.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = 'render() { ft_tick_render_plist main "$TEMPLATE" "$1"; }'
new = 'render() { sed -e "s|__WORKTREE__|$COMMON|g" -e "s|__SCRIPT__|$SCRIPT|g" -e "s|__COMM__|$COMM|g" "$TEMPLATE"; }'
assert src.count(old) == 1, "메인 렌더 호출 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 4 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$MUTD/mut-sed.sh" && echo same || echo changed)" changed
o="$(main "$MUTD/mut-sed.sh" "$R/.fable-team/bin/tick-amp.sh" --dry-run)"
chk "변 4 «sed 되살림» → ⓩ1 FAIL(& 값)" "$([ "$(pa1 "$o")" = "$R/.fable-team/bin/a&b.sh" ] && echo leaked || echo caught)" caught
o="$(main "$MUTD/mut-sed.sh" "$R/.fable-team/bin/pi|pe.sh" --dry-run)"
chk "변 4 «sed 되살림» → ⓩ2 FAIL(| 값)" "$([ "$(rc "$o")" = 0 ] && [ "$(pa1 "$o")" = "$R/.fable-team/bin/pi|pe.sh" ] && echo leaked || echo caught)" caught

# ── 변이 5: «팀 갈래가 렌더를 두 벌(따로 한 번 더)» → ⓩ3 FAIL ──
mut_py - "$INST" "$MUTD/mut-team2.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
anchor = '  plutil -lint "$NEW" >/dev/null || { echo "REJECT 만든 plist lint 실패"; exit 1; }'
second = ('  python3 - "$NEW" <<\'MUT\'   # 변이: 팀 갈래가 렌더를 한 번 더 따로 한다(두 벌)\n'
          'import plistlib, sys\n'
          'd = plistlib.load(open(sys.argv[1], "rb"))\n'
          'd["EnvironmentVariables"]["FT_TICK_SEAT_STATUS"] = "/nonexistent/old-copy/ft-seat-status.sh"\n'
          'plistlib.dump(d, open(sys.argv[1], "wb"))\n'
          'MUT\n')
assert src.count(anchor) == 1, "팀 lint 줄 1곳: %d" % src.count(anchor)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(anchor, second + anchor, 1))
PY
chk "변 5 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$MUTD/mut-team2.sh" && echo same || echo changed)" changed
o="$(team "$MUTD/mut-team2.sh" "$R/.fable-team/bin/ft-tick.sh" --from "$TMP/main-render.plist" --dry-run)"
chk "변 5 «팀 두 벌» → ⓩ3 FAIL(좌석판정기 값)" "$([ "$(envget "$o" FT_TICK_SEAT_STATUS)" = "$R/.fable-team/bin/ft-seat-status.sh" ] && echo leaked || echo caught)" caught

# ── 변이 6: «잔재 검사 삭제» → ⓩ4 FAIL(모르는 표식이 그대로 렌더) ──
mut_py - "$BADK/ft-tick-install.sh" "$BADK/mut-noguard.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = ('scan(d, "원본 검사에서 멈춤 · 파일 쓰기 0")')
old2 = ('scan(back, "렌더본에 표식이 남았다 · 파일 쓰기 0", skip_fills=False)')
assert old in src, "잔재 검사(원본) 줄을 못 찾음"
assert old2 in src, "잔재 검사(렌더본) 줄을 못 찾음"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, "pass  # 변이: 잔재 검사 삭제", 1).replace(old2, "pass  # 변이: 잔재 재검사 삭제", 1))
PY
chk "변 6 사본이 실제로 바뀌었다" "$(cmp -s "$BADK/ft-tick-install.sh" "$BADK/mut-noguard.sh" && echo same || echo changed)" changed
o="$(main "$BADK/mut-noguard.sh" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "변 6 «잔재 검사 삭제» → ⓩ4 FAIL(rc=0 으로 샌다)" "$([ "$(rc "$o")" = 1 ] && echo caught || echo leaked)" leaked

# ── 변이 7: «rc 미검사로 파일 쓰기» → ⓩ4 파일 0 FAIL ──
mut_py - "$INST" "$MUTD/mut-writefile.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '    printf \'%s\\n\' "$ROUT"; rm -f "$NEW"; exit 1'
new = '    printf \'%s\\n\' "$ROUT"; touch "$PL"; rm -f "$NEW"; exit 1   # 변이: 렌더 실패에도 plist 를 만진다'
assert src.count(old) == 1, "팀 렌더 실패 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 7 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$MUTD/mut-writefile.sh" && echo same || echo changed)" changed
o="$(team "$MUTD/mut-writefile.sh" "$R/.fable-team/bin/ft-tick.sh" --from "$TMP/from-bad.plist" --dry-run)"
chk "변 7 «rc 미검사 파일 쓰기» → ⓩ4 파일 0 FAIL" "$([ "$(ls "$PDIR" | wc -l | tr -d ' ')" = 0 ] && echo caught || echo leaked)" leaked
rm -f "$PDIR"/*

# ══ ⓙ ⓚ r4: 잔재 검사 = «틀에서 온 칸» 만 (REWORK-r962-r4 고침 1 · DA⑥ r3 HOLD 반례) ══════════
R2="$TMP/root__SCRIPT__"; mkdir -p "$R2/.fable-team/comm" "$R2/.fable-team/bin"
git -C "$R2" init -q -b main; git -C "$R2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
cp "$KBIN/ft-tick.sh" "$KBIN/ft-seat-status.sh" "$R2/.fable-team/bin/"
cp "$KBIN/ft-tick.sh" "$R2/.fable-team/bin/goal__SCRIPT__.sh"
o="$(main "$INST" "$R2/.fable-team/bin/goal__SCRIPT__.sh" --worktree "$R2" --dry-run)"
chk "ⓙ 메인(폴더 root__SCRIPT__ · 파일 goal__SCRIPT__.sh) rc" "$(rc "$o")" 0
chk "ⓙ 메인: ProgramArguments[1] 값 보존" "$(pa1 "$o")" "$R2/.fable-team/bin/goal__SCRIPT__.sh"
chk "ⓙ 메인: WorkingDirectory 값 보존" "$(wdval "$o")" "$R2"
python3 - "$TMP/from-r4.plist" "$R2" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "WorkingDirectory": sys.argv[2] + "/root__SCRIPT__",
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p",
                           "FT_TICK_LOG": sys.argv[2] + "/goal__SCRIPT__.sh",
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
o="$(team "$INST" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-r4.plist" --dry-run)"
chk "ⓙ 팀(--from 사용자 글자) rc" "$(rc "$o")" 0
chk "ⓙ 팀: WorkingDirectory 값 보존" "$(wdval "$o")" "$R2/root__SCRIPT__"
chk "ⓙ 팀: env 값 보존" "$(envget "$o" FT_TICK_LOG)" "$R2/goal__SCRIPT__.sh"

NEWK="$TMP/kitnew"; mkdir -p "$NEWK"; cp "$INST" "$NEWK/ft-tick-install.sh"
python3 - "$KBIN/ft-tick.plist" "$NEWK/ft-tick.plist" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = "<string>/tmp/ft-tick.log</string>"
assert s.count(old) == 2, "틀의 로그 자리 2개: %d" % s.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "<string>__NEW__</string>", 1))
PY
o="$(main "$NEWK/ft-tick-install.sh" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓚ 틀에 모르는 표식(값 전체 __NEW__) → rc≠0" "$(rc "$o")" 1
chk "ⓚ 렌더본 출력 0" "$(printf '%s\n' "$o" | grep -c '^<?xml')" 0
chk "ⓚ plist 쓰기 0" "$(ls "$LA" 2>/dev/null | wc -l | tr -d ' ')" 0

# ══ ⓟ r5: 잔재 판정 2규칙 (값 «전체» 가 표식만 거절 — 값 안 글자 0 · DA⑥ r4 ② 반례) ══════════
python3 - "$TMP/from-r5.plist" "$R2" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p",
                           "FT_TICK_LOG": "goal__X__.sh",
                           "FT_TICK_LOG2": sys.argv[2] + "/root__SCRIPT__/x.log",
                           "FT_TICK_LOG3": "/tmp/__X__.log",
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
o="$(team "$INST" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-r5.plist" --dry-run)"
chk "ⓟ 모르는 표식이 값 안(goal__X__.sh) → rc" "$(rc "$o")" 0
chk "ⓟ 값 그대로 보존(goal__X__.sh)" "$(envget "$o" FT_TICK_LOG)" "goal__X__.sh"
chk "ⓟ 아는 표식이 값 안(root__SCRIPT__ 폴더) → 보존" "$(envget "$o" FT_TICK_LOG2)" "$R2/root__SCRIPT__/x.log"
chk "ⓟ 모르는 표식이 값 안(/tmp/__X__.log) → 보존" "$(envget "$o" FT_TICK_LOG3)" "/tmp/__X__.log"
for tok in __SCRIPT__ __NEW__; do
  python3 - "$TMP/from-tok.plist" "$R2" "$tok" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p", "FT_TICK_LOG": sys.argv[3],
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
  o="$(team "$INST" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-tok.plist" --dry-run)"
  chk "ⓟ 값 전체가 표식($tok) → rc≠0" "$(rc "$o")" 1
  chk "ⓟ 값 전체가 표식($tok) → 렌더본 출력 0" "$(printf '%s\n' "$o" | grep -c '^<?xml')" 0
done
chk "ⓟ 값 전체가 표식 → plist 쓰기 0" "$(ls "$PDIR" | wc -l | tr -d ' ')" 0

# ── 변이 8: «값 안 표식 검사 되살림» (r3 꼴) → ⓙ·ⓟ FAIL ──
mut_py - "$INST" "$TMP/mut-alltok.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = ('def residual(p, v):\n'
       '    if TOK.fullmatch(v):\n'
       '        return "REJECT 표식이 남는 자리: %s = %s — 표식은 «값을 넣는 자리» 에만 둔다" % (show(p), v)\n'
       '    return None')
assert old in src, "residual 판정 줄을 못 찾음"
new = ('def residual(p, v):\n'
       '    if TOK.search(v):   # 변이: 값 안 표식 검사 되살림\n'
       '        return "REJECT 표식이 값 안에 있다(변이): %s = %s" % (show(p), v)\n'
       '    return None')
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 8 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$TMP/mut-alltok.sh" && echo same || echo changed)" changed
chk "변 8 고친 곳 = residual 1곳" "$(grep -c '값 안 표식 검사 되살림' "$TMP/mut-alltok.sh")" 1
o="$(team "$TMP/mut-alltok.sh" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-r4.plist" --dry-run)"
chk "변 8 «값 안 표식 검사 되살림» → ⓙ FAIL(rc≠0)" "$([ "$(rc "$o")" = 0 ] && echo leaked || echo caught)" caught
o="$(team "$TMP/mut-alltok.sh" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-r5.plist" --dry-run)"
chk "변 8 «값 안 표식 검사 되살림» → ⓟ FAIL(rc≠0)" "$([ "$(rc "$o")" = 0 ] && echo leaked || echo caught)" caught

# ══ ⓠ r6: «칸 전체» = 값 그대로(앞뒤 공백 포함) — 공백이 있으면 표식 하나만의 값이 아니다 (DA⑥ r6 반례) ══════
#   ⓠ1 공백 있는 표식값(" __X__ "·" __SCRIPT__ "·"__X__ "·" __X__") → 메인·팀 모두 rc0 · 값 공백까지 보존
#   ⓠ2 공백 없는 표식값("__X__"·"__SCRIPT__") → 지금처럼 rc≠0 · plist 쓰기 0  (변이 9: .strip() 되살림 → ⓠ1 FAIL)
WSK="$TMP/kitws"; mkdir -p "$WSK"; cp "$INST" "$WSK/ft-tick-install.sh"
python3 - "$KBIN/ft-tick.plist" "$WSK/ft-tick.plist" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = "    <key>LANG</key><string>ko_KR.UTF-8</string>\n"
assert s.count(old) == 1, "틀의 LANG 줄 1개: %d" % s.count(old)
new = old + "    <key>FT_TICK_EXTRA</key><string> __X__ </string>\n"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
chk "ⓠ1 틀 사본이 실제로 바뀌었다" "$(cmp -s "$KBIN/ft-tick.plist" "$WSK/ft-tick.plist" && echo same || echo changed)" changed
o="$(main "$WSK/ft-tick-install.sh" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓠ1 메인: 틀 값 « __X__ »(앞뒤 공백) → rc" "$(rc "$o")" 0
chk "ⓠ1 메인: 공백까지 값 보존" "$(envget "$o" FT_TICK_EXTRA)" " __X__ "
for wsv in " __X__ " " __SCRIPT__ " "__X__ " " __X__"; do
  python3 - "$TMP/from-ws.plist" "$R2" "$wsv" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p", "FT_TICK_EXTRA": sys.argv[3],
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
  o="$(team "$INST" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-ws.plist" --dry-run)"
  chk "ⓠ1 팀: --from 값 [$wsv] → rc" "$(rc "$o")" 0
  chk "ⓠ1 팀: --from 값 [$wsv] 공백까지 보존" "$(envget "$o" FT_TICK_EXTRA)" "$wsv"
done
for tok in "__X__" "__SCRIPT__"; do
  python3 - "$TMP/from-ws2.plist" "$R2" "$tok" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/nonexistent"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p", "FT_TICK_EXTRA": sys.argv[3],
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
  o="$(team "$INST" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-ws2.plist" --dry-run)"
  chk "ⓠ2 팀: 공백 없는 표식값 [$tok] → rc≠0" "$(rc "$o")" 1
  chk "ⓠ2 팀: [$tok] → 렌더본 출력 0" "$(printf '%s\n' "$o" | grep -c '^<?xml')" 0
done
chk "ⓠ2 공백 없는 표식값 → plist 쓰기 0" "$(ls "$PDIR" | wc -l | tr -d ' ')" 0

# ── 변이 9: «.strip() 되살림»(r5 꼴) → ⓠ1 FAIL(공백 값이 거절된다) ──
mut_py - "$INST" "$TMP/mut-strip.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = 'def residual(p, v):\n    if TOK.fullmatch(v):\n'
assert src.count(old) == 1, "residual 판정 줄 1곳: %d" % src.count(old)
new = 'def residual(p, v):\n    if TOK.fullmatch(v.strip()):   # 변이: 값을 다듬어 판정\n'
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, new, 1))
PY
chk "변 9 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$TMP/mut-strip.sh" && echo same || echo changed)" changed
chk "변 9 고친 곳 = residual 1곳" "$(grep -c '변이: 값을 다듬어 판정' "$TMP/mut-strip.sh")" 1
o="$(team "$TMP/mut-strip.sh" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-ws.plist" --dry-run)"
chk "변 9 «.strip() 되살림» → ⓠ1 FAIL(rc≠0)" "$([ "$(rc "$o")" = 0 ] && echo leaked || echo caught)" caught

# ══ ⓨ r7: ProgramArguments = 옛 판(1545012e)과 같게 «두 번째 칸부터 끝까지 [script] 로 대체» (DA⑥ r7 반례) ══════
#   옛 판: pa = list(d.get("ProgramArguments") or [bash, script]); pa[1:] = [script]  → 뒤 인자가 사라진다
paeq() {  # $1 = 출력 텍스트 · $2 = 기대 script → same | diff:[…]
  plfile "$1"
  python3 -c 'import plistlib,sys
try: pa = plistlib.load(open(sys.argv[1],"rb")).get("ProgramArguments")
except Exception: print("diff:unreadable"); raise SystemExit
print("same" if pa == ["/opt/homebrew/bin/bash", sys.argv[2]] else "diff:%r" % (pa,))' "$TMP/pl.plist" "$2" 2>/dev/null
}
for paform in witharg noarg empty; do
  mut_py - "$TMP/from-pa.plist" "$R2" "$paform" <<'PY'
import plistlib, sys
forms = {"witharg": ["/opt/homebrew/bin/bash", "/old/ft-tick.sh", "--once"],
         "noarg": ["/opt/homebrew/bin/bash", "/old/ft-tick.sh"],
         "empty": []}
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": forms[sys.argv[3]],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p",
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
  o="$(team "$INST" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-pa.plist" --dry-run)"
  chk "ⓨ 팀: 원본 PA=$paform rc" "$(rc "$o")" 0
  chk "ⓨ 팀: 원본 PA=$paform → ProgramArguments = [bash, 새 script]" "$(paeq "$o" "$R2/.fable-team/bin/ft-tick.sh")" same
done
o="$(main "$INST" "$R/.fable-team/bin/ft-tick.sh" --dry-run)"
chk "ⓨ 메인(틀) → ProgramArguments = [bash, script]" "$(paeq "$o" "$R/.fable-team/bin/ft-tick.sh")" same

# ── 변이 10: «두 번째 칸만 교체»(r3 꼴 · 뒤 인자 잔존) → ⓨ FAIL ──
mut_py - "$INST" "$TMP/mut-pa2.sh" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = '            node[:] = (node[:1] or ["/opt/homebrew/bin/bash"]) + [v]\n'
assert src.count(old) == 1, "ProgramArguments 대체 줄 1곳: %d" % src.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(old, '            node[1] = v   # 변이: 두 번째 칸만 교체\n', 1))
PY
chk "변 10 사본이 실제로 바뀌었다" "$(cmp -s "$INST" "$TMP/mut-pa2.sh" && echo same || echo changed)" changed
chk "변 10 고친 곳 = ProgramArguments 1곳" "$(grep -c '변이: 두 번째 칸만 교체' "$TMP/mut-pa2.sh")" 1
mut_py - "$TMP/from-pa2.plist" "$R2" <<'PY'
import plistlib, sys
plistlib.dump({"Label": "com.byz.ft-tick-ops", "ProgramArguments": ["/opt/homebrew/bin/bash", "/old/ft-tick.sh", "--once"],
  "EnvironmentVariables": {"FT_TICK_MASTER_MSG": "m", "FT_TICK_PM_MSG": "p",
                           "FT_TICK_SEATS": sys.argv[2] + "/.fable-team/seats-ops.json"}}, open(sys.argv[1], "wb"))
PY
o="$(team "$TMP/mut-pa2.sh" "$R2/.fable-team/bin/ft-tick.sh" --from "$TMP/from-pa2.plist" --dry-run)"
chk "변 10 «두 번째 칸만 교체» → ⓨ FAIL(뒤 인자 잔존)" "$(paeq "$o" "$R2/.fable-team/bin/ft-tick.sh")" "diff:['/opt/homebrew/bin/bash', '$R2/.fable-team/bin/ft-tick.sh', '--once']"


echo "fail=$fail"
[ "$fail" = 0 ] && echo "ALL PASS"
exit "$fail"
