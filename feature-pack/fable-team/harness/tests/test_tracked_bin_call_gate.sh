#!/usr/bin/env bash
# test_tracked_bin_call_gate.sh — R201 범위 추가: 축 ⓕ(홈 훅 tracked-bin-call-gate) + 축 ⓖ(입구 도구 6개의 비설치 위치 실행 = LIVE_BIN 으로 exec) + 변이.
# mktemp 만 쓴다(임시 루트 리포 + 임시 라이브 bin — 가짜 도구가 자기 $HERE·인자를 찍는다). 진짜 루트·라이브 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"
HK="$HERE/../../harness/kit/hooks/tracked-bin-call-gate.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
TOOLS="ft-nano-spawn ft-nano-close ft-role-spawn ft-successor-open ft-resource-gate ft-resource-reclaim"

bash -n "$HK" && ok "bash -n 훅" || bad "bash -n 훅"
for t in $TOOLS ft-live-entry; do bash -n "$SRC/$t.sh" && ok "bash -n $t" || bad "bash -n $t"; done

# ── 임시 루트: 리포 + 추적 사본(harness/bin — r385 뒤 추적 자리) + 라이브 bin(.fable-team/live-bin 아님 — 임의 폴더) ──
R="$T/root"; LIVE="$T/live"; mkdir -p "$R/harness/bin" "$R/.fable-team" "$LIVE"
git init -q -b main "$R"
for t in $TOOLS ft-live-entry; do cp -p "$SRC/$t.sh" "$R/harness/bin/$t.sh"; done
# 입구 도구가 읽는 형제 파일도 같이 둔다(없으면 도구가 옛 INFO/WARN 경로로 빠져 단언이 흔들린다)
for f in ft-team-lib.sh ft-harness-root.sh; do cp -p "$SRC/$f" "$R/harness/bin/$f"; done
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m kit
# r2: origin/main 이 HEAD 보다 «앞선» 뒤처진 워크트리 꼴(HEAD 가 origin/main 을 안 품음) — 넘김 조건
git -C "$R" -c user.email=t@t -c user.name=t commit -q --allow-empty -m newer; NEWER="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$NEWER"; git -C "$R" reset -q --hard HEAD~1
printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_BIN"
for t in $TOOLS; do
  printf '#!/usr/bin/env bash\nHERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"\necho "LIVE %s HERE=$HERE args=$* done=${FT_LIVE_ENTRY_DONE:-}"; cat; exit 5\n' "$t" > "$LIVE/$t.sh"
done

# ── 축 ⓕ: 훅 ──
mk() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$R"; }
hook() { out="$(mk "$1" | env -u FT_ALLOW_TRACKED_BIN FT_ROOT="$R" bash "${2:-$HK}" 2>"$T/err")"; rc=$?; }
denied()  { [ "$rc" = 0 ] && grep -q '"permissionDecision": "deny"' <<<"$out"; }
allowed() { [ "$rc" = 0 ] && ! grep -q 'deny' <<<"$out"; }
chk() { if "$1"; then ok "$2"; else bad "$2 :: rc=$rc out=${out:0:200}"; fi; }

hook 'bash /x/.worktrees/loom-main/scripts/fable-team-bin/ft-nano-spawn.sh --help'
chk denied "ⓕ 추적 사본 spawn 직접 호출 → deny"; has "$out" "$LIVE" "ⓕ 안내에 라이브 경로(LIVE_BIN 값)"; has "$out" 'FT_BIN/ft-nano-spawn.sh' "ⓕ 안내에 \$FT_BIN/<이름>"
hook 'bash /w/harness/bin/ft-nano-spawn.sh --help'; chk denied "ⓕ 새 추적 자리(harness/bin) spawn 직접 호출 → deny"; has "$out" 'FT_BIN/ft-nano-spawn.sh' "ⓕ 새 자리 안내에 \$FT_BIN/<이름>"
for t in ft-nano-close ft-role-spawn ft-successor-open ft-resource-gate ft-resource-reclaim; do
  hook "bash /w/scripts/fable-team-bin/$t.sh a b"; chk denied "ⓕ $t → deny"
done
hook 'cd /y && bash harness/bin/ft-role-spawn.sh da'; chk denied "ⓕ 새 추적 자리(상대) + && → deny"
hook 'cd /y && bash scripts/harness-install/fable-team/bin/ft-role-spawn.sh da'; chk denied "ⓕ 키트 사본 경로(상대) + && → deny"
hook 'FOO=1 timeout 60 bash /w/scripts/fable-team-bin/ft-nano-close.sh s'; chk denied "ⓕ 환경 대입·timeout 래퍼 뒤 → deny"
hook 'echo hi | bash /w/scripts/fable-team-bin/ft-resource-gate.sh check'; chk denied "ⓕ 파이프 뒤 → deny"
hook '/w/scripts/fable-team-bin/ft-nano-spawn.sh x'; chk denied "ⓕ 경로 직접 실행 → deny"
# 통과: 읽기·라이브 호출·입구 밖 이름
for c in 'cat /w/scripts/fable-team-bin/ft-nano-spawn.sh' 'grep -n HERE /w/scripts/fable-team-bin/ft-nano-close.sh' 'sed -n 1,5p /w/scripts/fable-team-bin/ft-nano-spawn.sh' \
         'git show HEAD:scripts/fable-team-bin/ft-nano-spawn.sh' 'bash -n /w/scripts/fable-team-bin/ft-nano-spawn.sh' 'bash $FT_BIN/ft-nano-spawn.sh --help' \
         'bash /r/.fable-team/bin/ft-nano-spawn.sh --help' 'bash /w/scripts/fable-team-bin/ft-tick.sh --once' 'bash /w/scripts/fable-team-bin/ft-index-move.sh a b' \
         'FT_ALLOW_TRACKED_BIN=1 bash /w/scripts/fable-team-bin/ft-nano-spawn.sh x' 'ls scripts/fable-team-bin/'; do
  hook "$c"; chk allowed "ⓕ 통과: ${c:0:60}"
done
out="$(printf 'not json' | FT_ROOT="$R" bash "$HK" 2>"$T/err")"; rc=$?; allowed_rc=$rc; [ "$allowed_rc" = 0 ] && ! grep -q deny <<<"$out" && grep -q WARN "$T/err" && ok "ⓕ 깨진 입력 → 통과 + stderr 경고" || bad "ⓕ 깨진 입력"
out="$(printf '' | FT_ROOT="$R" bash "$HK" 2>/dev/null)"; rc=$?; chk allowed "ⓕ 빈 입력 → 통과"
# H3(r3 · DA r1): JSON 이 dict 아님 · 파이썬 쪽 예외 · python3 없음 → 통과 + stderr 경고 1줄 rc0 (deny 0)
for pair in 'list:[1,2]' 'str:"x"' 'toolinput-list:{"tool_name":"Bash","tool_input":["x"]}'; do
  nm="${pair%%:*}"; js="${pair#*:}"
  out="$(printf '%s' "$js" | FT_ROOT="$R" bash "$HK" 2>"$T/err")"; rc=$?
  [ "$rc" = 0 ] && ! grep -q deny <<<"$out" && [ "$(grep -c '^WARN tracked-bin-call-gate' "$T/err")" = 1 ] && ok "H3 $nm → 통과 + 경고 1줄 rc0" || bad "H3 $nm rc=$rc out=${out:0:80} err=$(head -c 160 "$T/err")"
done
NP="$T/nopy"; mkdir -p "$NP"; ln -sf "$(command -v cat)" "$NP/cat"
out="$(mk 'bash /w/scripts/fable-team-bin/ft-nano-spawn.sh x' | env PATH="$NP" FT_ROOT="$R" /bin/bash "$HK" 2>"$T/err")"; rc=$?
[ "$rc" = 0 ] && ! grep -q deny <<<"$out" && grep -q '^WARN tracked-bin-call-gate: python3 없음' "$T/err" && ok "H3 python3 없음 → 통과 + 경고 rc0" || bad "H3 python3 없음 rc=$rc err=$(head -c 160 "$T/err")"
# 변이: 입구 도구 목록을 비운 훅 → deny 단언이 깨진다
sed 's/^ENTRY_TOOLS=.*/ENTRY_TOOLS=""/' "$HK" > "$T/hook-mut.sh"; grep -q '^ENTRY_TOOLS=""$' "$T/hook-mut.sh" && ok "변이 파일 생성(목록 비움)" || bad "변이 생성 실패"
hook 'bash /w/scripts/fable-team-bin/ft-nano-spawn.sh x' "$T/hook-mut.sh"
denied && bad "변이 훅이 여전히 deny — 시험이 이빨이 없다" || ok "변이 시 ⓕ deny 단언이 깨진다(시험이 변이를 잡는다)"

# ── 축 ⓖ: 입구 도구의 비설치 위치 실행 = LIVE_BIN 으로 exec ──
for t in $TOOLS; do
  out="$(printf 'IN\n' | env -u FT_ALLOW_TRACKED_BIN bash "$R/harness/bin/$t.sh" one "two w" 2>&1)"; rc=$?
  has "$out" "LIVE $t HERE=$LIVE args=one two w done=1" "ⓖ $t → 라이브 exec(\$HERE=라이브 · 인자·done=1)"; has "$out" "IN" "ⓖ $t stdin 그대로"
  [ "$rc" = 5 ] && ok "ⓖ $t rc 그대로(5)" || bad "ⓖ $t rc=$rc 기대=5"
done
# LIVE_BIN 없음·빈 값·대상 없음 → ERROR rc≠0 · 옛 사본 실행 0
S="$R/harness/bin/ft-nano-spawn.sh"
mv "$R/.fable-team/LIVE_BIN" "$T/lb"; out="$(env -u FT_ALLOW_TRACKED_BIN bash "$S" --dry-run 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "ERROR" "ⓖ LIVE_BIN 없음 → ERROR rc≠0(rc=$rc)" || bad "ⓖ LIVE_BIN 없음인데 rc=0"; hasnt "$out" "INFO drift-check" "ⓖ 옛 사본 실행 0(건너뜀 줄 없음)"
: > "$R/.fable-team/LIVE_BIN"; out="$(env -u FT_ALLOW_TRACKED_BIN bash "$S" --dry-run 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "ERROR" "ⓖ LIVE_BIN 빈 값 → ERROR rc≠0" || bad "ⓖ 빈 값인데 rc=0"
# H1(r3 · DA r1): 상대 경로 LIVE_BIN → ERROR rc3 · 라이브 도구 실행 0 (cwd=$T 에서 "live" 는 실재 폴더 — 검사가 없으면 가짜 라이브가 돈다)
printf 'live\n' > "$R/.fable-team/LIVE_BIN"
out="$(cd "$T" && env -u FT_ALLOW_TRACKED_BIN bash "$S" --dry-run 2>&1)"; rc=$?
[ "$rc" = 3 ] && has "$out" "ERROR ft-live-entry" "H1 ⓖ 상대 LIVE_BIN → ERROR rc3" || bad "H1 ⓖ 상대 LIVE_BIN rc=$rc :: ${out:0:160}"; hasnt "$out" "LIVE ft-nano-spawn" "H1 ⓖ 상대 LIVE_BIN → 라이브 실행 0"
printf '%s\n' "$LIVE" > "$R/.fable-team/LIVE_BIN"; mv "$LIVE/ft-nano-spawn.sh" "$T/s.bak"
out="$(env -u FT_ALLOW_TRACKED_BIN bash "$S" --dry-run 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "ERROR" "ⓖ 대상 도구 없음 → ERROR rc≠0" || bad "ⓖ 대상 없음인데 rc=0"; mv "$T/s.bak" "$LIVE/ft-nano-spawn.sh"
# FT_ALLOW_TRACKED_BIN=1 → 넘기지 않는다(옛 INFO 건너뜀 경로 · 가짜 라이브가 안 불린다)
out="$(FT_ALLOW_TRACKED_BIN=1 FT_RESOURCE_SENSORS_DIR=/nonexistent bash "$S" 2>&1 </dev/null)"; hasnt "$out" "LIVE ft-nano-spawn" "ⓖ FT_ALLOW_TRACKED_BIN=1 → 라이브로 안 넘김"
# r2 새 사례 1: origin/main 을 «품은» 워크트리(HEAD ⊇ origin/main) 의 추적 사본 → 제자리 실행(라이브로 안 넘김 · close 무인자 = usage rc2)
C="$R/harness/bin/ft-nano-close.sh"
git -C "$R" update-ref refs/remotes/origin/main HEAD
out="$(env -u FT_ALLOW_TRACKED_BIN bash "$C" 2>&1 </dev/null)"; rc=$?
hasnt "$out" "LIVE ft-nano-close" "r2·사례1 origin/main 을 품은 HEAD → 라이브로 안 넘김"; [ "$rc" = 2 ] && ok "r2·사례1 제자리 실행(usage rc=2)" || bad "r2·사례1 rc=$rc 기대=2 :: ${out:0:160}"
# r2 새 사례 2: 뒤처진 워크트리(origin/main 이 앞섬) → LIVE_BIN exec
git -C "$R" update-ref refs/remotes/origin/main "$NEWER"
out="$(env -u FT_ALLOW_TRACKED_BIN bash "$C" a 2>&1 </dev/null)"; rc=$?
has "$out" "LIVE ft-nano-close HERE=$LIVE" "r2·사례2 뒤처진 HEAD → LIVE_BIN exec"; [ "$rc" = 5 ] && ok "r2·사례2 rc 그대로(5)" || bad "r2·사례2 rc=$rc"
# r2: git 판단 실패(origin/main 없음) → ERROR rc3 · 옛 사본 실행 0
git -C "$R" update-ref -d refs/remotes/origin/main
out="$(env -u FT_ALLOW_TRACKED_BIN bash "$C" a 2>&1 </dev/null)"; rc=$?
[ "$rc" = 3 ] && has "$out" "ERROR ft-live-entry" "r2·판단 실패 → ERROR rc3" || bad "r2·판단 실패 rc=$rc :: ${out:0:160}"
git -C "$R" update-ref refs/remotes/origin/main "$NEWER"
# 설치 꼴(*/.fable-team/bin)에서는 아무것도 안 한다
IB="$T/inst/.fable-team/bin"; mkdir -p "$IB"; cp -p "$SRC/ft-live-entry.sh" "$SRC/ft-nano-spawn.sh" "$IB/"
out="$(env -u FT_ALLOW_TRACKED_BIN bash "$IB/ft-nano-spawn.sh" 2>&1 </dev/null)"; hasnt "$out" "ft-live-entry" "ⓖ 설치 꼴 → live-entry 개입 0"
# 추적 사본 위치도 설치 꼴도 아닌 임시 복사본(시험 픽스처 꼴) → 개입 0 (옛 INFO 건너뜀 경로) · git 밖이어도 ERROR 아님
TB="$T/tmpcopy/bin"; mkdir -p "$TB"; cp -p "$SRC/ft-live-entry.sh" "$SRC/ft-nano-close.sh" "$TB/"
out="$(env -u FT_ALLOW_TRACKED_BIN bash "$TB/ft-nano-close.sh" 2>&1 </dev/null)"; rc=$?
hasnt "$out" "ft-live-entry" "ⓖ 임시 복사본(추적 사본·설치 꼴 아님) → live-entry 개입 0"; [ "$rc" = 2 ] && ok "ⓖ 임시 복사본 제자리 실행(usage rc=2)" || bad "ⓖ 임시 복사본 rc=$rc"

echo "== fail=$fail"; [ "$fail" = 0 ]
