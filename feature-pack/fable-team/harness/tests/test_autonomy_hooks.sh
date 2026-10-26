#!/usr/bin/env bash
# test_autonomy_hooks.sh — 자율 대리 결정 모드 «강제 장치» 훅 3종 + ft-proxy-decide ok 파일 시험 (r-autonomy-hooks · 판정 1322·1355)
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR·FT_PLANNER_DIR) + 훅에 stdin JSON 만 먹인다 — 실 ~/.claude·실 상태 파일·실 gh 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/harness/kit/fable-team/templates/hooks"; BIN="$ROOT/harness/bin"; MIR="$ROOT/harness/kit/fable-team/bin"
IG="$HK/autonomy-interview-gate.sh"; SG="$HK/autonomy-state-guard.sh"; MG="$HK/autonomy-merge-guard.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
IH="$T/hooks"; mkdir -p "$IH"; cp "$ROOT/harness/kit/fable-team/templates/hooks/autonomy-"*.sh "$ROOT/harness/kit/hooks/merge_cmd.py" "$IH"/   # r546: 설치 꼴(한 폴더) 재현 — 공용 모듈 merge_cmd.py 를 훅 옆에 둔다
SG="$IH/autonomy-state-guard.sh"; MG="$IH/autonomy-merge-guard.sh"   # r546: 키트 templates 폴더에는 모듈이 없다(설치 후 홈은 한 폴더)
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_SH="$BIN/ft-autonomy.sh" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
S="$T/state"; OK="$S/autonomy-merge-ok"; mkdir -p "$T/.fable-team" "$S" "$T/planner" "$T/outside" "$T/stubs"

a() { "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
mode_off() { rm -f "$S/autonomy.json" "$S/autonomy.log"; }
mode_on() { mode_off; a on >/dev/null; }
mode_tamper() { mode_on; sed 's/"event":"A1"/"event":"A9"/' "$S/autonomy.json" > "$S/j.tmp" && mv "$S/j.tmp" "$S/autonomy.json"; }
mkask() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"AskUserQuestion","cwd":sys.argv[3],"tool_input":{"questions":[{"question":sys.argv[2],"header":sys.argv[1],"multiSelect":False,"options":[{"label":"a","description":"x"},{"label":"b","description":"y"}]}]}},ensure_ascii=False))' "$1" "$2" "${3:-$T}"; }
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "${2:-$T}"; }
mkfile() { python3 -c 'import json,sys;t,p,k,c=sys.argv[1:5];print(json.dumps({"tool_name":t,"cwd":sys.argv[5],"tool_input":{k:p,"content":"autonomy.json ft-autonomy.sh off"}},ensure_ascii=False))' "$1" "$2" "${3:-file_path}" "x" "${4:-$T}"; }
run() { out="$(printf '%s' "$2" | ${ENVPFX:-} "$BASH" "$1" 2>"$T/err")"; rc=$?; }
outside() { ENVPFX="env -u FT_ROOT -u CLAUDE_PROJECT_DIR"; "$@"; ENVPFX=""; }   # 루트를 못 찾는 BYZ 밖 호출
al() { run "$1" "$2"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$3" $?; }
dn() { run "$1" "$2"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "$3" $?; }
bal() { al "$1" "$(mkbash "$2" "${4:-$T}")" "$3"; }
bdn() { dn "$1" "$(mkbash "$2" "${4:-$T}")" "$3"; }

for f in "$IG" "$SG" "$MG"; do bash -n "$f" 2>/dev/null; ck "bash -n $(basename "$f")" $?; done

# ===== ① autonomy-interview-gate =====
mode_on;  dn "$IG" "$(mkask "" "배포 방식을 고를까요?")" "ⓐ1 ON → deny"
grep -q '\[자율 ON A1' <<<"$out" && grep -q 'ft-proxy-decide.sh' <<<"$out" && grep -q '오빠 큐' <<<"$out"; ck "ⓐ1b deny 사유 = status 1줄 + ft-proxy-decide + 오빠 큐" $?
mode_off; dn "$IG" "$(mkask "배포" "배포 방식을 고를까요?")" "ⓐ2 OFF + 머리 없음 → deny"
grep -q 'ft-autonomy.sh status' <<<"$out"; ck "ⓐ2b deny 사유에 status 붙이라는 안내" $?
al "$IG" "$(mkask "[자율 OFF]" "배포 방식을 고를까요?")" "ⓐ3 OFF + header 머리 → allow"
al "$IG" "$(mkask "배포" "[자율 OFF] 배포 방식을 고를까요?")" "ⓐ3b OFF + question 첫머리 → allow"
dn "$IG" "$(mkask "배포" "배포 방식을 [자율 OFF] 고를까요?")" "ⓐ3c 머리 아닌 중간에 있으면 → deny"
rm -f "$S/autonomy.json"; dn "$IG" "$(mkask "배포" "고를까요?")" "ⓐ4 상태 파일만 지움(log 남음 → OFF 취급) + 머리 없음 → deny"
mode_tamper; dn "$IG" "$(mkask "배포" "고를까요?")" "ⓐ5 위변조 + 머리 없음 → deny"
al "$IG" "$(mkask "[자율 OFF]" "고를까요?")" "ⓐ5b 위변조 + 머리 있음 → allow"
mode_off; FT_NOW=1800000000 a on --for 1h >/dev/null 2>&1; EX="$(FT_NOW=1800003600 a status)"   # R185: 끝 도달(until 지남 · expire 전) — status 가 [자율 OFF · A1 끝 도달 HH:MM]
grep -qE '^\[자율 OFF · A1 끝 도달 [0-9]{2}:[0-9]{2}\]$' <<<"$EX"; rc=$?; out="$EX"; ck "ⓐ5c 끝 도달 status 꼴 ($EX)" $?
ENVPFX="env FT_NOW=1800003600"; al "$IG" "$(mkask "$EX" "배포 방식을 고를까요?")" "ⓐ5d 끝 도달 머리(status 그대로) → allow"
dn "$IG" "$(mkask "배포" "고를까요?")" "ⓐ5e 끝 도달 상태 + 머리 없음 → deny 그대로"
dn "$IG" "$(mkask "[자율 ON A1 · 17:00~ · ~18:00까지 · 대리 0 · 큐 0]" "고를까요?")" "ⓐ5f 끝 도달 상태 + [자율 ON 머리 → deny 그대로"
ENVPFX=""
mode_on; outside al "$IG" "$(mkask "" "고를까요?" "$T/outside")" "ⓐ6 BYZ 밖(FT_ROOT 없음·git 아님) → allow"
run "$IG" '{깨진 json'; [ "$rc" = 0 ] && [ -z "$out" ] && grep -q 'fail-open' "$T/hook.log"; ck "ⓐ7 깨진 JSON → allow + 로그" $?
run "$IG" ''; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓐ7b 빈 stdin → allow" $?
al "$IG" "$(mkbash "ls" "$T")" "ⓐ7c AskUserQuestion 아닌 도구 → allow"
FT_AUTONOMY_SH=/nonexistent run "$IG" "$(mkask "" "고를까요?")"; [ "$rc" = 0 ] && ! grep -q permissionDecision <<<"$out" && grep -q 'systemMessage' <<<"$out" && grep -q '못 읽어' "$T/err" && grep -q 'ft-autonomy.sh' "$T/hook.log"; ck "ⓐ8 ft-autonomy.sh 못 찾음 → allow + 화면 경고(stderr·systemMessage) + 로그 (R176 · 판정 1675 ①)" $?

# ===== ② autonomy-state-guard =====
mode_on
for c in "echo x > $S/autonomy.json" "echo x >> \"$S/autonomy.log\"" "cat f >$S/autonomy.json" "printf a | tee $S/autonomy.log" "echo a | tee -a $S/autonomy.log" \
         "cp /tmp/x $S/autonomy.json" "mv /tmp/x $S/autonomy.json" "mv $S/autonomy.json /tmp/x" "rm $S/autonomy.json" ": > $S/autonomy.log" \
         "sed -i s/a/b/ $S/autonomy.json" "bash /x/ft-autonomy.sh on" "ft-autonomy.sh off" "FT_ROOT=/x bash -c 'ft-autonomy.sh on'" \
         "echo hi > $OK/1111111111111111111111111111111111111111" "touch $OK/abc" "cd /x && echo > autonomy.json" "true; echo x > \$STATE/autonomy.json"; do
  bdn "$SG" "$c" "ⓑ1 쓰기 꼴 deny: $c"
done
for c in "env -S 'cp /tmp/x $S/autonomy.json'" "env -S 'bash /x/ft-autonomy.sh off'" "env --split-string='ft-autonomy.sh on'" "env -S 'bash -c \"echo a > $S/autonomy.log\"'" "env -S 'sh -c \"touch $OK/z\"' extra" "sudo env -i -S 'rm $S/autonomy.json'" "env -S\"cp /tmp/x $S/autonomy.json\"" "env -u FOO -S 'mv /tmp/x $OK/abc'"; do
  bdn "$SG" "$c" "ⓑ1h(DA H2) env -S 안의 쓰기·토글 deny: ${c:0:60}"
done
for c in "env -S 'cat $S/autonomy.json'" "env -S 'ft-autonomy.sh status'" "env FOO=1 -S 'tail -n1 $S/autonomy.log'" "env -S 'echo a > $S/autonomy.log'" "env -S 'echo a >> $OK/x'" "echo \"env -S 'cp x autonomy.json'\"" "mbox.sh send x y \"env -S 'ft-autonomy.sh off' 는 막힌다\""; do
  bal "$SG" "$c" "ⓒ1h(DA H2) env -S 읽기·글자만 allow: ${c:0:60}"
done
dn "$SG" "$(mkfile Write "$S/autonomy.json")" "ⓑ2 Write autonomy.json → deny"
dn "$SG" "$(mkfile Edit "$S/autonomy.log")" "ⓑ2b Edit autonomy.log → deny"
dn "$SG" "$(mkfile NotebookEdit "$OK/1111111111111111111111111111111111111111" notebook_path)" "ⓑ2c NotebookEdit ok 파일 → deny"
dn "$SG" "$(mkfile Write "$OK/abc")" "ⓑ2d Write ok 디렉터리 → deny"
for c in "cat $S/autonomy.json" "jq . $S/autonomy.json" "tail -n1 $S/autonomy.log" "grep on $S/autonomy.log" "ft-autonomy.sh status" "bash ft-autonomy.sh mode" "bash ft-autonomy.sh event" \
         "cp $S/autonomy.json /tmp/copy" "ls $OK/" "cat $OK/1111111111111111111111111111111111111111" "echo x > /tmp/other.json" "git commit -m 'autonomy.json fix'" \
         "mbox.sh send x y \"autonomy.json 에 쓰지 마라 ft-autonomy.sh off > autonomy.log\"" "echo \"ft-autonomy.sh off\"" "echo ft-autonomy.sh off" \
         "ft-proxy-decide.sh --kind press-order --q q --choice c --why w --undo u" \
         $'cat > /tmp/note.md <<\'EOF\'\nft-autonomy.sh off\necho x > autonomy.json\nEOF'; do
  bal "$SG" "$c" "ⓒ1 읽기·글자만 allow: ${c:0:60}"
done
al "$SG" "$(mkfile Write /tmp/x.md)" "ⓒ2 Write 본문에 경로 글자만 → allow"
al "$SG" "$(mkfile Edit "$T/design.md")" "ⓒ2b Edit 다른 파일 → allow"
outside bal "$SG" "echo x > autonomy.json" "ⓑ3 BYZ 밖에서는 allow" "$T/outside"
# ⓑ-source (r947 r2 · DA 반례 1) — source·. 경유도 «같은 파일을 실행»이다: 좌석이 approve-standing·on/off 를 source 로 부르면 deny
for c in "source $BIN/ft-autonomy.sh approve-standing D1 --repos pack --classes code,docs" ". $BIN/ft-autonomy.sh approve-standing D1 --repos pack --classes code,docs" \
         "source $BIN/ft-autonomy.sh on" ". $BIN/ft-autonomy.sh off" "bash -c 'source $BIN/ft-autonomy.sh approve-standing D1 --repos pack --classes code,docs'" \
         "cd /x && source ../y/ft-autonomy.sh approve-merge 1111111111111111111111111111111111111111"; do
  bdn "$SG" "$c" "ⓑ-source source·. 경유 실행 deny: ${c:0:70}"
done
for c in "source /tmp/other.sh" ". $T/plan.sh" "source $BIN/ft-autonomy.sh status" "bash -c 'source /tmp/other.sh'"; do
  bal "$SG" "$c" "ⓑ-source2 다른 파일·읽기(하위명령 없음) allow: ${c:0:70}"
done
# ⓑ-source변 변이 — «source 처리 끔» 이면 ⓑ-source 칸이 allow 로 뒤집힌다(= 그 칸이 그 검사를 잡는다)
MH="$T/mhook"; mkdir -p "$MH"; cp "$IH"/autonomy-*.sh "$IH/merge_cmd.py" "$MH"/
python3 - "$IH/autonomy-state-guard.sh" "$MH/autonomy-state-guard.sh" <<'PY' || { echo "FAIL 변이 source 못 만듦"; fail=$((fail+1)); }
import sys
s = open(sys.argv[1], encoding="utf-8").read()
old = "elif b in SOURCE and len(w) > 1:"
assert s.count(old) == 1, old
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, "elif False:"))
PY
run "$MH/autonomy-state-guard.sh" "$(mkbash "source $BIN/ft-autonomy.sh approve-standing D1 --repos pack --classes code,docs")"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓑ-source변 변이(source 처리 끔) → ⓑ-source 칸 빨강" $?

run "$SG" '{깨진'; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓑ4 깨진 JSON → allow" $?
# ⓛ r466 5c — 진입 파일(h<N>) · 계획 파일(*.sh.hil) 안 명령도 같은 판정 · approve-merge 는 자율 ON 이면 허용 + 로그
HP="$T/plan-am.sh.hil"; HE="$T/h9999"; HSH=1111111111111111111111111111111111111111
printf '#!/usr/bin/env bash\nset -euo pipefail\nbash "$FT_BIN/ft-autonomy.sh" approve-merge %s\n' "$HSH" > "$HP"
printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s\nP=%s; bash "$P"\n' "$HP" "$HP" > "$HE"
mode_on; : > "$T/hook.log"
ENVPFX="env -u TMUX"; bal "$SG" "bash $HE" "ⓛ1 ON + 진입 파일 → 계획 approve-merge → allow"; ENVPFX=""
grep -q "hN-approve seat=unknown file=$HE plan=$HP approve-merge $HSH" "$T/hook.log"; ck "ⓛ1b allow 로그 hN-approve seat=… file=… (r466)" $?
bal "$SG" "bash $HP" "ⓛ1c ON + 계획 파일 직접 → allow"
mode_off; bdn "$SG" "bash $HE" "ⓛ2 OFF + 진입 파일 approve-merge → deny"
grep -q '진입 파일' <<<"$out"; ck "ⓛ2b deny 사유에 진입 파일·계획 경로" $?
for sub in on off forget-kind approve-scope; do
  printf 'bash /x/ft-autonomy.sh %s --for 12h\n' "$sub" > "$HP"
  mode_on; bdn "$SG" "bash $HE" "ⓛ3 ON + 계획에 ft-autonomy.sh $sub → deny"
  mode_off; bdn "$SG" "bash $HE" "ⓛ3b OFF + 계획에 ft-autonomy.sh $sub → deny"
done
printf 'echo x > %s/autonomy.json\n' "$S" > "$HP"; mode_on; bdn "$SG" "bash $HE" "ⓛ4 계획 안 상태 파일 쓰기 → deny"
printf 'echo hello\n' > "$HP"; bal "$SG" "bash $HE" "ⓛ5 계획에 자율 명령 없음 → allow"
: > "$T/hook.log"; bal "$SG" "bash $T/h8888" "ⓛ6 진입 파일 없음 → allow(fail-open)"
grep -q 'hN 파일 못 읽음' "$T/hook.log"; ck "ⓛ6b 못 읽음 로그" $?
printf '#!/usr/bin/env bash\n# ft-hil-entry plan=%s/none.sh.hil\n' "$T" > "$HE"; bal "$SG" "bash $HE" "ⓛ7 계획 파일 없음 → allow + 로그"
bdn "$SG" "bash /x/ft-autonomy.sh forget-kind deps" "ⓛ8 좌석 forget-kind 직접 → deny"

# ===== ③ autonomy-merge-guard =====
mkrepo() { git -c init.defaultBranch=main init -q "$1" && git -C "$1" checkout -q -B main && git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2"; }
R1="$T/r1"; R2="$T/r2"; R3="$T/r3"
mkrepo "$R1" one; mkrepo "$R2" two; mkrepo "$R3" three; git -C "$R3" checkout -q -b topic
H="$(git -C "$R1" rev-parse HEAD)"; F="$(git -C "$R2" rev-parse HEAD)"
git -C "$R1" branch topic; git -C "$R2" branch topic2; git -C "$R1" branch main-fix
mkdir -p "$OK"; echo "101 pr=7 da=x ev=A1" > "$OK/$F"   # 옛 push-merge PROXY 가 남긴 ok 파일 — 병합 가드는 더 읽지 않는다(판정 1675 · DA② H1)
mode_on; a approve-merge "$H" >/dev/null                 # 오빠 승인(H 만) = autonomy-merge-approved/<H> + autonomy.log 줄
GH="gh pr merge 7 --squash"
for c in "$GH --match-head-commit $H" "$GH --match-head-commit=$H" "ft-gh-as-tank.sh pr merge 7 --squash --match-head-commit $H" "bash /x/ft-gh-as-tank.sh pr merge 7 --match-head-commit $H" \
         "env -u GH_TOKEN gh pr merge 7 --match-head-commit $H" "gh api -X PUT repos/o/r/pulls/7/merge -f sha=$H"; do
  bal "$MG" "$c" "ⓔ1 ON + 오빠 승인(approve-merge)된 sha → allow: ${c:0:70}" "$R1"
done
for c in "$GH" "$GH --match-head-commit $F" "$GH --match-head-commit abc123" "ft-gh-as-tank.sh pr merge 7 --squash" "bash -c 'gh pr merge 7'" "gh api -X PUT repos/o/r/pulls/7/merge" \
         "ft-gh-as-tank.sh pr merge 7 --match-head-commit $F" "gh pr merge 7 --auto --squash"; do
  bdn "$MG" "$c" "ⓔ2 ON + 플래그 없음/다른 sha/옛 ok 파일만 있는 sha/승인 없음 → deny: ${c:0:70}" "$R1"
done
for c in "git push origin HEAD:main" "git push origin main" "git push origin refs/heads/main" "git push origin topic:main" "git push" "git push -u origin HEAD:refs/heads/main" "cd $R1 && git push origin HEAD:main" "git -C $R1 push origin main"; do
  bal "$MG" "$c" "ⓔ3 main push + ok sha → allow: ${c:0:70}" "$R1"
done
for c in "git push origin topic2:main" "git push origin +topic2:main" "git push origin :main" "git push --all origin" "git push --mirror" "cd $R2 && git push origin HEAD:main" "git -C $R2 push origin HEAD:main" "git push origin nosuchref:main"; do
  bdn "$MG" "$c" "ⓔ4 main push + ok 없음/삭제/전체 → deny: ${c:0:70}" "$R1"
done
for c in "git push --repo origin topic2:main" "git push --repo=origin topic2:main" "git push --delete origin main" "git push -d origin main" "git push origin --delete main" "git push --delete --repo origin main" \
         "env -S 'gh pr merge 7 --squash'" "env -S 'git push origin topic2:main'" "env --split-string='gh pr merge 7'" "env -S 'gh pr merge 7 --match-head-commit $F'"; do
  bdn "$MG" "$c" "ⓔ4h(DA H1·H2) --repo·--delete·env -S main 병합/push → deny: ${c:0:70}" "$R1"
done
bdn "$MG" "git push --repo origin HEAD:main" "ⓔ4h2 --repo + HEAD:main(ok 없음) → deny" "$R2"
bdn "$MG" "git push --repo=origin HEAD:main" "ⓔ4h3 --repo= + HEAD:main(ok 없음) → deny" "$R2"
for c in "git push --repo origin HEAD:main" "git push --repo=origin HEAD:main" "env -S 'gh pr merge 7 --match-head-commit $H'" "env -S 'git push origin HEAD:main'"; do
  bal "$MG" "$c" "ⓔ3h(DA H1·H2) 양성 대조 ok sha → allow: ${c:0:70}" "$R1"
done
for c in "git push --repo origin topic2" "git push --delete origin topic" "git push -d origin feat/x" "git push --repo=origin HEAD:feat/x" "env -S 'gh pr view 7'" "env -S 'git status'" "echo \"env -S 'gh pr merge 7'\"" "mbox.sh send x y \"git push --delete origin main 은 막힌다\""; do
  bal "$MG" "$c" "ⓔ5h(DA H1·H2) 다른 브랜치·읽기·글자만 allow: ${c:0:70}" "$R2"
done
bdn "$MG" "git push" "ⓔ4b 맨 push + main 위 HEAD 의 ok 없음 → deny" "$R2"
bdn "$MG" "git push origin HEAD:main" "ⓔ4c HEAD(F) ok 없음 → deny" "$R2"
for c in "git push origin topic" "git push origin HEAD:feat/x" "git push origin HEAD:main-fix" "git push --dry-run origin topic2:main" "git push -n origin main" "git log main" "git status" "gh pr view 7" "gh pr checks 7" "gh pr create --base main" \
         "echo \"gh pr merge 7\"" "mbox.sh send x y \"gh pr merge 7 와 git push origin main 은 막힌다\"" $'cat > /tmp/n.md <<\'EOF\'\ngh pr merge 7\ngit push origin main\nEOF'; do
  bal "$MG" "$c" "ⓔ5 다른 브랜치·읽기·dry-run·글자만 → allow: ${c:0:70}" "$R2"
done
bal "$MG" "git push" "ⓔ5b 맨 push + 다른 브랜치(topic) → allow" "$R3"
mode_off; bal "$MG" "$GH" "ⓔ6 OFF → allow" "$R1"
mode_tamper; bal "$MG" "$GH" "ⓔ6b 위변조 → allow" "$R1"
mode_on; outside bal "$MG" "$GH" "ⓔ6c BYZ 밖 → allow" "$T/outside"
run "$MG" '{깨진'; [ "$rc" = 0 ] && [ -z "$out" ]; ck "ⓔ7 깨진 JSON → allow" $?
mode_on; FT_AUTONOMY_SH=/nonexistent dn "$MG" "$(mkbash "$GH --match-head-commit $H" "$R1")" "ⓔ8 도구 못 찾음 → 병합 deny (승인 sha 여도 · R176 · 판정 1675 ①)"
grep -q '못 읽어' <<<"$out" && grep -q '못 읽음' "$T/hook.log"; ck "ⓔ8b deny 사유 + 로그에 못 읽음" $?
FT_AUTONOMY_SH=/nonexistent bal "$MG" "git push origin topic" "ⓔ8c 도구 못 찾음 + main 아닌 push → allow" "$R2"
FT_AUTONOMY_SH=/nonexistent bal "$MG" "gh pr view 7" "ⓔ8d 도구 못 찾음 + 병합 아닌 명령 → allow" "$R1"

# ===== ⓕ ft-proxy-decide push-merge → QUEUE 고정 (판정 1675 · ok 파일 쓰기 0) =====
printf '%s\n' '- **100** (오빠) x 착수 승인' > "$T/planner/VERDICTS-planner-1.md"
SHA=1111111111111111111111111111111111111111; SHB=2222222222222222222222222222222222222222
printf '# [DA⑥ t] APPROVE — 0건\n\n고정 세트 `%s`\n' "$SHA" > "$T/da.md"
printf '%s\n' '#!/bin/bash' 'case "$*" in *"pr view"*) echo "${GH_HEAD:-}";; *"pr checks"*) echo pass;; esac' > "$T/stubs/gh"; chmod +x "$T/stubs/gh"; export PATH="$T/stubs:$PATH"
pd() { out="$(GH_HEAD="$1" "$BASH" "$BIN/ft-proxy-decide.sh" --kind push-merge --q "머지 승인 진행할까요 $4" --choice 머지 --why DA6 --undo "git revert $1" --sha "$1" --da "$2" --pr 7 2>"$T/err")"; rc=$?; }
rm -rf "$OK" "$S/autonomy-merge-approved"; mode_on
pd "$SHA" "$T/da.md" x a; [ "$rc" = 2 ] && grep -q '^QUEUE main 병합·main push = 오빠 값(판정 1675)' <<<"$out"; ck "ⓕ1 PR head·DA⑥·checks 전부 맞아도 push-merge = QUEUE rc 2" $?
[ ! -e "$OK" ] && [ ! -e "$S/autonomy-merge-approved" ]; ck "ⓕ2 QUEUE → ok·approved 폴더 쓰기 0" $?
pd "$SHB" "$T/da.md" x b; [ "$rc" = 2 ] && [ ! -e "$OK" ]; ck "ⓕ3 다른 sha 도 QUEUE · ok 파일 0" $?
out="$("$BASH" "$BIN/ft-proxy-decide.sh" --kind press-order --q "순서?" --choice "A 다음 B" --why w --undo u 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$OK" ]; ck "ⓕ4 push-merge 아닌 PROXY → ok 폴더 안 생김" $?
mode_off; pd "$SHA" "$T/da.md" x d; [ "$rc" = 3 ] && [ ! -e "$OK" ]; ck "ⓕ6 OFF → rc 3 · ok 파일 0" $?
cmp -s "$BIN/ft-proxy-decide.sh" "$MIR/ft-proxy-decide.sh"; ck "ⓕ7 ft-proxy-decide 미러 cmp 0" $?

# ===== ⓓ 기존 인터뷰 훅 시험 회귀 =====
out="$("$BASH" "$HERE/test_proposal_interview_gate.sh" 2>&1)"; rc=$?; [ "$rc" = 0 ]; ck "ⓓ1 test_proposal_interview_gate.sh 회귀 0" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
