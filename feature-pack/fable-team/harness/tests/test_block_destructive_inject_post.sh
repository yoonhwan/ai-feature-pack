#!/usr/bin/env bash
# test_block_destructive_inject_post.sh — 판정 595: INJECT 블록의 «게시 싱크»(--inject 모드). 본문 인용은 통과(F), 같은 글자를 실행하는 경로는 차단(X).
# 키트 훅에 PreToolUse JSON 만 넣어 종료코드를 본다. 홈 훅·실제 명령 실행 0 (명령은 JSON 문자열일 뿐).
# 변이(M): 판정기·훅 복사본에서 결과가 뒤집혀야 시험이 «잡는 힘»이 있다. TABLE_OUT=<경로> 면 대조표 행을 그 파일에 쓴다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
HOOK="${BD_HOOK:-$ROOT/scripts/harness-install/fable-team/templates/hooks/block-destructive.sh}"
JUDGE="$(dirname "$HOOK")/block-destructive-judge.py"
T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
cp "$JUDGE" "$T/"
git -C "$T" init -q
H="$HOOK"
fail=0; nf=0; nx=0; nm=0
[ -n "${TABLE_OUT:-}" ] && : > "$TABLE_OUT"

run() {  # <명령> → H 훅 종료코드 (셔뱅 그대로 /bin/bash)
  python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T" \
    | /bin/bash "$H" >/dev/null 2>&1
  return $?
}
expect() {  # <id> <기대 rc> <카운터> <명령>
  local id="$1" want="$2" ctr="$3" cmd="$4" rc shown
  run "$cmd"; rc=$?
  if [ "$rc" = "$want" ]; then echo "PASS [$id] rc=$rc :: ${cmd:0:60}"; eval "$ctr=\$(($ctr+1))"
  else echo "FAIL [$id] want=$want got=$rc :: $cmd"; fail=$((fail+1)); fi
  if [ -n "${TABLE_OUT:-}" ]; then
    shown="${cmd//$'\n'/⏎}"; shown="${shown//|/\\|}"
    printf '| %s | `%s` | %s | %s |\n' "$id" "$shown" "$want" "$rc" >> "$TABLE_OUT"
  fi
}
fpass() { expect "$1" 0 nf "$2"; }
xblk() { expect "$1" 2 nx "$2"; }
mutate() {  # <변이 디렉터리> <훅|판정기> <바꿀 글자> <새 글자> — 훅+판정기 복사본, 적용 안 되면 시험 실패
  [ -d "$1" ] || { mkdir -p "$1"; cp "$HOOK" "$1/block-destructive.sh"; cp "$JUDGE" "$1/block-destructive-judge.py"; }   # 같은 디렉터리 재호출 = 변이 누적
  local f="$1/block-destructive.sh"; [ "$2" = "판정기" ] && f="$1/block-destructive-judge.py"
  python3 -c 'import sys
t=open(sys.argv[1]).read()
if sys.argv[2] not in t: sys.exit(1)
open(sys.argv[1],"w").write(t.replace(sys.argv[2],sys.argv[3],1))' "$f" "$3" "$4" \
    || { echo "FAIL [변이 미적용] $1"; fail=$((fail+1)); }
}

W='bash scripts/fable-team-bin/ft-gh-as-tank.sh'
RS='redis-cli SET k v'
BR='/dev/bubble-replay'

# ── 통과 (F): 게시 본문 안의 금지 글자 ───────────────────────────────────
F1a=$'unset GH_TOKEN; SP=/tmp/sp; export FT_ME=\'me#1\'; M=/tmp/mbox.sh\ncat > $SP/c887r.md <<\'EOF\'\n증거 재게시 — 앞 닫힘('"$BR"$' 측정)은 무효였고 이 코멘트가 대체한다\n금지 grep(el.click·appendChild·PUBLISH·redis-cli) 0건\nEOF\nbash $SP/ft-gh-as-tank.sh comment 887 $SP/c887r.md --apply 2>&1 | tail -1\nbash $SP/ft-issue-close-check.sh 887 --repo . 2>&1 | tail -3\nbash $M send \'a#1\' \'b#1\' "[b#1->a#1] #887 게시 확인" 2>&1 | tail -1'
fpass F1a "$F1a"
fpass F1b $'cat > /tmp/fp-c.md <<\'EOF\'\n('"$BR"$') 무효\nEOF\n'"$W"' comment 887 /tmp/fp-c.md --apply'
fpass F1c $'cat > /tmp/fp-c.md <<\'EOF\'\n'"$RS"$' 금지\nEOF\n'"$W"' edit 887 --body-file /tmp/fp-c.md --apply'
fpass F1d $'cat > /tmp/fp-b.md <<\'EOF\'\n'"$RS"$' 금지\nEOF\ngh pr create --title x --body-file /tmp/fp-b.md'
fpass F1e $'cat > /tmp/fp-m.txt <<\'EOF\'\n[docs] '"$BR"$' 금지\nEOF\ngit commit -F /tmp/fp-m.txt -- a.md'
fpass F2a $'gh issue comment 1 --body "$(cat <<\'EOF\'\n'"$BR"$' 무효\nEOF\n)"'
fpass F2b $'git commit -m "$(cat <<\'EOF\'\n[docs] '"$RS"$' 금지\nEOF\n)" -- a.md'

# ── 차단 (X): 같은 글자가 «실행» 되는 경로 ───────────────────────────────
xblk X1 $'cat > /tmp/fp-x.sh <<\'EOF\'\n'"$RS"$'\nEOF\nbash /tmp/fp-x.sh'
xblk X2 $'cat > /tmp/fp-x.txt <<\'EOF\'\nSET k v\nEOF\nredis-cli < /tmp/fp-x.txt; '"$RS"
xblk X3 $'cat > /tmp/fp-c.md <<\'EOF\'\n'"$RS"$'\nEOF\n'"$W"$' comment 1 /tmp/fp-c.md --apply; bash /tmp/fp-c.md'
xblk X4 $'cat > /tmp/fp-c.md <<EOF\n'"$RS"$'\nEOF\n'"$W"' comment 1 /tmp/fp-c.md --apply'
xblk X5 $'cat > /tmp/fp-k <<\'EOF\'\nurl = http://h'"$BR"$'\nEOF\ncurl -K /tmp/fp-k; bash x.sh'
xblk X6 $'bash -c "$(cat <<\'EOF\'\n'"$RS"$'\nEOF\n)"'
xblk X8 $'curl "$(cat <<\'EOF\'\nhttp://h'"$BR"$'\nEOF\n)"'
xblk X9 $'cat > /tmp/fp-c.md <<\'EOF\'\nx\nEOF\n'"$W"' comment 1 /tmp/fp-c.md --apply; '"$RS"
xblk X10 $'gh issue comment 1 --body "$(cat <<\'EOF\'\nok\nEOF\n)$('"$RS"$')"'
xblk X11 $'python3 - <<\'EOF\'\nimport os; os.system(\''"$RS"$'\')\nEOF'
xblk X12 $'cat > /tmp/fp-c.md <<\'EOF\'\n'"$RS"$'\nEOF\nbash x.sh /tmp/fp-c.md'
# DA r1 반송(Q1): 같은 명령의 실행 소비 구간이 «대입 해소 + realpath ≠ F» 로 증명돼야 본문을 뺀다
ln -s "$T/body595.txt" "$T/other595.sh"                                   # 다른 이름 심링크 → F
BD=$'\nredis-cli SET k v\nEOF\n'
xblk X13 "cat > /tmp/body595.txt <<'EOF'${BD}gh pr create --title x --body-file /tmp/body595.txt; bash \"\$RUNFILE\""
xblk X14 "cat > $T/body595.txt <<'EOF'${BD}gh pr create --title x --body-file $T/body595.txt; bash $T/other595.sh"
xblk X15 "R=/tmp/body595.txt; cat > \$R <<'EOF'${BD}bash \$R"
xblk X16 "D=/tmp; cat > \$D/c.md <<'EOF'${BD}bash \$D/../tmp/c.md"
xblk X17 "cat > /tmp/body595.txt <<'EOF'${BD}$W comment 1 /tmp/body595.txt --apply; sudo bash x.sh"
# DA r2 반송(Q1): 대입은 «구간 순서대로» — 검사 뒤에 대입된 값은 앞 구간 검사에 쓰지 않는다
xblk X18 "cat > /tmp/body595.txt <<'EOF'${BD}gh pr create --title x --body-file /tmp/body595.txt; bash \"\$RUNFILE\"; RUNFILE=/tmp/safe.sh"
xblk X19 "R=/tmp/safe.sh; cat > /tmp/body595.txt <<'EOF'${BD}gh pr create --title x --body-file /tmp/body595.txt; R=/tmp/body595.txt; bash \$R"
# 이 좌석이 더한 행: 구분자 줄이 본문 안에 있음(셸은 거기서 heredoc 을 끝낸다) · 같은 끝 이름 별칭 · 글롭 · 따옴표 모양 구분자 가짜
xblk X20 $'gh issue comment 1 --body "$(cat <<\'EOF\'\nok\nEOF\n'"$RS"$'\nEOF\n)"'
xblk X21 $'cat > /tmp/fp-c.md <<\'EOF\'\n'"$RS"$'\nEOF\nbash $D/fp-c.md'
xblk X22 $'cat > /tmp/fp-c.md <<\'EOF\'\n'"$RS"$'\nEOF\nbash /tmp/fp-c.m?'
xblk X23 $'echo \'<<"A"\'; cat > /tmp/fp-c.md <<EOF\n'"$RS"$'\nEOF\n'"$W"' comment 1 /tmp/fp-c.md --apply'

# ── 변이 (M): 변이 복사본에서는 결과가 뒤집혀야 한다 ──────────────────────
mutate "$T/m3" 판정기 'if (touches(t, base) or r is not None and (touches(r, base) or rp(r, cwd, moved) == frp)) and not' 'if False and not'   # F 를 가리키는 토큰 검사 빼기
H="$T/m3/block-destructive.sh"
expect M3-X12 0 nm $'cat > /tmp/fp-c.md <<\'EOF\'\n'"$RS"$'\nEOF\nbash x.sh /tmp/fp-c.md'
mutate "$T/m4" 판정기 '(touches(r, base) or rp(r, cwd, moved) == frp)' '(touches(r, base) or False)'      # realpath 비교 빼기 (토큰 쪽)
mutate "$T/m4" 판정기 'return p is not None and p != frp' 'return p is not None'                            # realpath 비교 빼기 (실행 구간 쪽)
H="$T/m4/block-destructive.sh"
expect M4-X14 0 nm "cat > $T/body595.txt <<'EOF'${BD}gh pr create --title x --body-file $T/body595.txt; bash $T/other595.sh"
mutate "$T/m12" 판정기 'if not runs_only_other(toks, env, frp, cwd, moved): raise Inelig' 'pass'          # 실행 소비 구간 «비-F 증명» 빼기
H="$T/m12/block-destructive.sh"
expect M12-X13 0 nm "cat > /tmp/body595.txt <<'EOF'${BD}gh pr create --title x --body-file /tmp/body595.txt; bash \"\$RUNFILE\""
expect M12-X17 0 nm "cat > /tmp/body595.txt <<'EOF'${BD}$W comment 1 /tmp/body595.txt --apply; sudo bash x.sh"
mutate "$T/m7" 판정기 'zip(segs, envs)' 'zip(segs, [envs[-1]] * len(segs))'                              # 대입을 전 구간 최종 값으로 (r1 동작)
H="$T/m7/block-destructive.sh"
expect M7-X18 0 nm "cat > /tmp/body595.txt <<'EOF'${BD}gh pr create --title x --body-file /tmp/body595.txt; bash \"\$RUNFILE\"; RUNFILE=/tmp/safe.sh"
mutate "$T/m8" 판정기 'any(o[0] not in "'"'"'\"" for o in opens)' 'False'                          # 따옴표 구분자 요구 빼기
H="$T/m8/block-destructive.sh"
expect M8-X4 0 nm $'cat > /tmp/fp-c.md <<EOF\n'"$RS"$'\nEOF\n'"$W"' comment 1 /tmp/fp-c.md --apply'
mutate "$T/m9" 훅 "printf '%s' \"\$INJ_SRC\" | LC_ALL=C sed" "printf '%s' \"\$EFFECTIVE\" | LC_ALL=C sed"   # 훅이 INJ_SRC 대신 EFFECTIVE 를 보게
H="$T/m9/block-destructive.sh"
expect M9-F1a 2 nm "$F1a"
expect M9-F1b 2 nm $'cat > /tmp/fp-c.md <<\'EOF\'\n('"$BR"$') 무효\nEOF\n'"$W"' comment 887 /tmp/fp-c.md --apply'
mutate "$T/m10" 판정기 'if any(l.strip(" \t") == m.group(2) for l in m.group(3).split("\n")): continue' 'pass'   # 본문 안 구분자 줄 검사 빼기
H="$T/m10/block-destructive.sh"
expect M10-X20 0 nm $'gh issue comment 1 --body "$(cat <<\'EOF\'\nok\nEOF\n'"$RS"$'\nEOF\n)"'
H="$HOOK"

echo "SUMMARY pass=$nf block=$nx mutant=$nm fail=$fail"
[ "$nf" -eq 7 ] && [ "$nx" -eq 22 ] && [ "$nm" -eq 9 ] && [ "$fail" -eq 0 ] || { echo "FAIL 표 미달 또는 실패 있음"; exit 1; }
echo "OK"
