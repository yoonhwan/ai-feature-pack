#!/usr/bin/env bash
# test_install_hook_check.sh — install.sh 의 «훅 등록 확인 줄»: 홈 훅 same/diff/absent · settings registered/absent.
# mktemp 홈만 쓴다(실 ~/.claude 미접촉). block-destructive 템플릿은 실 홈 파일과 cmp(있을 때만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../harness/kit/fable-team"
INSTALL="$KIT/install.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$INSTALL" && ok "bash -n install.sh" || bad "bash -n install.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NAME="gh-issue-author-guard.sh"
TPL="$KIT/templates/hooks/$NAME"
run() { bash "$INSTALL" --home "$1" --machine t --team t; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }

# ⓐ 훅 파일 없음 + settings.json 없음 → absent / absent · rc=0 · 기존 줄 유지
H1="$T/h1"; mkdir -p "$H1"
OUT="$(run "$H1")"; rc=$?
[ "$rc" = 0 ] && ok "a rc=0" || bad "a rc=$rc"
has "hook $NAME home=absent settings=absent" && ok "a home=absent settings=absent" || bad "a absent 줄"
has "machine=t team=t mode=dry-run" && has "files=" && has "kit_sha=" && ok "a 기존 출력 줄(machine=·files=·kit_sha=) 유지" || bad "a 기존 출력 줄"
printf '%s\n' "$OUT" | grep -qE '^hooks same=0 diff=0 absent=[0-9]+ registered=0$' && ok "a 요약 줄" || bad "a 요약 줄"

# ⓑ 키트와 같은 파일 + settings 등록 → same / registered
H2="$T/h2"; mkdir -p "$H2/.claude/hooks"
cp -p "$TPL" "$H2/.claude/hooks/$NAME"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"$HOME/.claude/hooks/%s"}]}]}}\n' "$NAME" > "$H2/.claude/settings.json"
OUT="$(run "$H2")"; rc=$?
[ "$rc" = 0 ] && ok "b rc=0" || bad "b rc=$rc"
has "hook $NAME home=same settings=registered" && ok "b same/registered" || bad "b same/registered"
printf '%s\n' "$OUT" | grep -qE '^hooks same=1 diff=0 absent=[0-9]+ registered=1$' && ok "b 요약 줄" || bad "b 요약 줄"

# ⓒ 한 바이트 다른 파일 → diff
H3="$T/h3"; mkdir -p "$H3/.claude/hooks"
cp -p "$TPL" "$H3/.claude/hooks/$NAME"; printf '#' >> "$H3/.claude/hooks/$NAME"
OUT="$(run "$H3")"; rc=$?
[ "$rc" = 0 ] && ok "c rc=0" || bad "c rc=$rc"
has "hook $NAME home=diff settings=absent" && ok "c diff" || bad "c diff"
printf '%s\n' "$OUT" | grep -qE '^hooks same=0 diff=1 absent=[0-9]+ registered=0$' && ok "c 요약 줄" || bad "c 요약 줄"

# ⓓ settings.json 없음 + 훅은 있음 → settings=absent
has "settings=absent" && ok "d settings.json 없음 → settings=absent" || bad "d settings=absent"

# 읽기 전용: 홈 훅·settings 를 건드리지 않고 dest 도 만들지 않는다(dry-run)
[ ! -e "$H1/.fable-team" ] && ok "dry-run: dest 미생성" || bad "dry-run: dest 생성됨"
[ ! -e "$H1/.claude" ] && ok "홈 .claude 미생성(복사·등록 0)" || bad "홈 .claude 생성됨"

# block-destructive 템플릿 = 실 홈 파일(바이트 동일) — 홈 파일이 있는 머신에서만
BD="$KIT/templates/hooks/block-destructive.sh"
[ -f "$BD" ] && ok "block-destructive 템플릿 존재" || bad "block-destructive 템플릿 없음"
[ -x "$BD" ] && ok "block-destructive 실행 비트" || bad "block-destructive 실행 비트 없음"
if [ -f "$HOME/.claude/hooks/block-destructive.sh" ]; then
  cmp -s "$BD" "$HOME/.claude/hooks/block-destructive.sh" && ok "block-destructive 템플릿 == 홈 파일" || bad "block-destructive 템플릿 != 홈 파일"
else
  echo "SKIP block-destructive cmp — 이 머신에 홈 파일 없음"
fi

# 판정기(.py) — 훅과 같은 폴더에 같이 설치돼야 한다(없으면 훅이 fail-closed 로 과차단)
BDJ="$KIT/templates/hooks/block-destructive-judge.py"
[ -f "$BDJ" ] && ok "block-destructive-judge 템플릿 존재" || bad "block-destructive-judge 템플릿 없음"
if [ -f "$HOME/.claude/hooks/block-destructive-judge.py" ]; then
  cmp -s "$BDJ" "$HOME/.claude/hooks/block-destructive-judge.py" && ok "block-destructive-judge 템플릿 == 홈 파일" || bad "block-destructive-judge 템플릿 != 홈 파일"
else
  echo "SKIP block-destructive-judge cmp — 이 머신에 홈 파일 없음"
fi

# ══ r491: harness/install.sh — 홈 훅 = kit/hooks 전부 · chmod +x · settings 등록 훅 전수 점검(실재 + 실행 비트) ══
# 픽스처 = mktemp 홈·프로젝트(실 홈·실 settings 미접촉 · 가짜 launchctl · GIT_* env 0)
HROOT="$(cd "$HERE/.." && pwd -P)"; HINST="$HROOT/install.sh"; KH="$HROOT/kit/hooks"
bash -n "$HINST" && ok "r491 bash -n harness/install.sh" || bad "r491 bash -n harness/install.sh"
FB="$T/fb"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 0\n' > "$FB/launchctl"; chmod 755 "$FB/launchctl"
newproj() { local p="$T/$1"; mkdir -p "$p/.fable-team/bin"; git init -q -b main "$p"; (cd "$p" && pwd -P); }
newhome() { local h="$T/$1"; mkdir -p "$h/Library/LaunchAgents"; printf '%s\n' "$h"; }
reg() {  # reg <home> <command>… → settings.json(PreToolUse 에 명령 1개씩)
  local h="$1"; shift; mkdir -p "$h/.claude"
  python3 -I -c 'import json,sys; print(json.dumps({"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":c} for c in sys.argv[1:]]}]}}))' "$@" > "$h/.claude/settings.json"
}
hinst() { local h="$1" p="$2"; shift 2; env HOME="$h" FT_LAUNCHCTL="$FB/launchctl" bash "$HINST" "$@" --project "$p" --home "$h" 2>&1; }
NK="$(find "$KH" -maxdepth 1 -type f ! -name '*.pyc' | grep -c .)"
KF="harness-freeze-gate.sh"

# ⓐ 빈 홈 --apply → 홈 훅 = kit/hooks 전부 cmp0 · 전부 -x(.py 포함) · 등록 1(키트 훅) ok
HA="$(newhome ha)"; PA="$(newproj pa)"; reg "$HA" "\$HOME/.claude/hooks/$KF"
OUT="$(hinst "$HA" "$PA" --apply)"; rc=$?
[ "$rc" = 0 ] && ok "r491ⓐ apply rc0" || bad "r491ⓐ apply rc=$rc :: $(printf '%s' "$OUT" | tail -5)"
nok=0; for f in "$KH"/*; do n="$(basename "$f")"; cmp -s "$f" "$HA/.claude/hooks/$n" && [ -x "$HA/.claude/hooks/$n" ] && nok=$((nok+1)); done
[ "$nok" = "$NK" ] && ok "r491ⓐ 홈 훅 $NK/$NK cmp0 + 실행 비트" || bad "r491ⓐ 홈 훅 $nok/$NK"
[ -x "$HA/.claude/hooks/merge_cmd.py" ] && ok "r491ⓐ .py 도 실행 비트" || bad "r491ⓐ merge_cmd.py 실행 비트 없음"
has "HOOKS copied=$NK same=0" && ok "r491ⓐ HOOKS copied=$NK" || bad "r491ⓐ HOOKS copied 줄"
has "HOOKS registered=1 ok=1 bad=0" && ok "r491ⓐ 등록 1 ok" || bad "r491ⓐ HOOKS registered 줄"
OUT="$(hinst "$HA" "$PA" --apply)"; rc=$?
[ "$rc" = 0 ] && has "HOOKS copied=0 same=$NK chmod=0" && ok "r491ⓐ 2회째 멱등(copied=0 chmod=0)" || bad "r491ⓐ 2회째 :: rc=$rc"

# ⓑ 같은 내용 키트 훅을 644 로 미리 둠 → --apply 뒤 755 · `HOOK … chmod +x` 1줄
HB="$(newhome hb)"; PB="$(newproj pb)"; mkdir -p "$HB/.claude/hooks"; cp "$KH/$KF" "$HB/.claude/hooks/$KF"; chmod 644 "$HB/.claude/hooks/$KF"
OUT="$(hinst "$HB" "$PB" --apply)"; rc=$?
[ "$rc" = 0 ] && ok "r491ⓑ apply rc0 (settings 없음 → registered=0)" || bad "r491ⓑ rc=$rc"
[ "$(stat -f %Lp "$HB/.claude/hooks/$KF" 2>/dev/null || stat -c %a "$HB/.claude/hooks/$KF")" = 755 ] && ok "r491ⓑ 644 → 755" || bad "r491ⓑ 모드 그대로"
[ "$(printf '%s\n' "$OUT" | grep -c "^HOOK $HB/.claude/hooks/$KF chmod +x$")" = 1 ] && ok "r491ⓑ HOOK … chmod +x 1줄" || bad "r491ⓑ chmod 줄"
has "HOOKS registered=0 ok=0 bad=0" && ok "r491ⓑ settings 없음 = registered=0" || bad "r491ⓑ registered=0 줄"

# ⓒ 등록 훅 644 → apply = ERROR HOOK-EXEC … 실행 비트 없음 rc1 · dry-run = PENDING rc0 · `bash <경로>` 644 는 실재만(과차단 0)
HC="$(newhome hc)"; PC="$(newproj pc)"; mkdir -p "$HC/.claude/hooks"
printf '#!/bin/sh\nexit 0\n' > "$HC/.claude/hooks/fx-only.sh"; chmod 644 "$HC/.claude/hooks/fx-only.sh"
printf '#!/bin/sh\nexit 0\n' > "$HC/.claude/hooks/via-bash.sh"; chmod 644 "$HC/.claude/hooks/via-bash.sh"
reg "$HC" "\$HOME/.claude/hooks/$KF" "~/.claude/hooks/fx-only.sh" "bash $HC/.claude/hooks/via-bash.sh"
OUT="$(hinst "$HC" "$PC" --dry-run)"; rc=$?
[ "$rc" = 0 ] && has "PENDING HOOK-EXEC $HC/.claude/hooks/fx-only.sh 실행 비트 없음" && ok "r491ⓒ dry-run PENDING HOOK-EXEC rc0" || bad "r491ⓒ dry-run :: rc=$rc"
[ ! -e "$HC/.claude/hooks/$KF" ] && ok "r491ⓒ dry-run 홈 훅 쓰기 0" || bad "r491ⓒ dry-run 이 훅을 씀"
has "HOOK $HC/.claude/hooks/$KF <- $KH/$KF (exec)" && ok "r491ⓒ dry-run HOOK 줄 (exec) 표기" || bad "r491ⓒ (exec) 표기"
OUT="$(hinst "$HC" "$PC" --apply)"; rc=$?
[ "$rc" = 1 ] && has "ERROR HOOK-EXEC $HC/.claude/hooks/fx-only.sh 실행 비트 없음" && ok "r491ⓒ apply ERROR HOOK-EXEC rc1" || bad "r491ⓒ apply :: rc=$rc"
has "HOOKS registered=3 ok=2 bad=1" && ok "r491ⓒ registered=3 ok=2 bad=1" || bad "r491ⓒ 요약 줄"
printf '%s\n' "$OUT" | grep -q "HOOK-EXEC .*via-bash.sh" && bad "r491ⓒ bash 로 부르는 644 를 잡음(과차단)" || ok "r491ⓒ bash <경로> 644 = 실재만(과차단 0)"
[ "$(stat -f %Lp "$HC/.claude/hooks/fx-only.sh" 2>/dev/null || stat -c %a "$HC/.claude/hooks/fx-only.sh")" = 644 ] && ok "r491ⓒ 키트 밖 훅 모드 불변(chmod 는 키트 훅만)" || bad "r491ⓒ 키트 밖 훅을 바꿈"
grep -q 'fx-only' "$HC/.claude/settings.json" && ok "r491ⓒ settings 쓰기 0" || bad "r491ⓒ settings 바뀜"

# ⓓ 등록 훅 경로 없음 → ERROR HOOK-EXEC … 없음 rc1 · 고치면 registered=3 ok=3 bad=0 rc0
reg "$HC" "\$HOME/.claude/hooks/$KF" "~/.claude/hooks/fx-only.sh" "\${HOME}/.claude/hooks/gone.sh"
chmod 755 "$HC/.claude/hooks/fx-only.sh"
OUT="$(hinst "$HC" "$PC" --apply)"; rc=$?
[ "$rc" = 1 ] && has "ERROR HOOK-EXEC $HC/.claude/hooks/gone.sh 없음" && ok "r491ⓓ 없는 경로 → ERROR HOOK-EXEC 없음 rc1" || bad "r491ⓓ :: rc=$rc"
printf '#!/bin/sh\nexit 0\n' > "$HC/.claude/hooks/gone.sh"; chmod 755 "$HC/.claude/hooks/gone.sh"
OUT="$(hinst "$HC" "$PC" --apply)"; rc=$?
[ "$rc" = 0 ] && has "HOOKS registered=3 ok=3 bad=0" && ok "r491ⓓ 전부 정상 → registered=3 ok=3 bad=0 rc0" || bad "r491ⓓ 정상 :: rc=$rc"
printf '{"hooks":' > "$HC/.claude/settings.json"; OUT="$(hinst "$HC" "$PC" --dry-run)"; rc=$?
[ "$rc" = 1 ] && has "settings.json 못 읽음" && ok "r491ⓓ settings JSON 깨짐 → rc1(조용한 통과 0)" || bad "r491ⓓ 깨진 JSON :: rc=$rc"

# ⓔ ft-live-install-check: hooks 행 라이브 644 → EXEC-BIT(키트 모드 644 여도) · 755 → OK
CHK="$HROOT/kit/fable-team/bin/ft-live-install-check.sh"; R="$T/lic"; KDIR=kit
mkdir -p "$R/$KDIR/hooks"; git init -q -b main "$R"; cp "$HROOT/kit/LIVE-MAP.tsv" "$R/$KDIR/LIVE-MAP.tsv"
printf '#!/bin/sh\nexit 0\n' > "$R/$KDIR/hooks/h644.sh"; chmod 644 "$R/$KDIR/hooks/h644.sh"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -qm k
HE="$(newhome he)"; mkdir -p "$HE/.claude/hooks"; cp "$R/$KDIR/hooks/h644.sh" "$HE/.claude/hooks/"; chmod 644 "$HE/.claude/hooks/h644.sh"
lic() { env HOME="$HE" FT_BIN="$T/ftbin" GIT_CONFIG_GLOBAL=/dev/null bash "$CHK" --all --ref HEAD --repo "$R" --kit "$KDIR" 2>&1; }
OUT="$(lic)"; rc=$?
[ "$rc" = 1 ] && has "EXEC-BIT $KDIR/hooks/h644.sh -> $HE/.claude/hooks/h644.sh" && ok "r491ⓔ 라이브 홈 훅 644 → EXEC-BIT rc1" || bad "r491ⓔ EXEC-BIT :: rc=$rc $(printf '%s' "$OUT" | head -3)"
chmod 755 "$HE/.claude/hooks/h644.sh"; OUT="$(lic)"; rc=$?
[ "$rc" = 0 ] && has "OK n=1" && ok "r491ⓔ 755 → OK" || bad "r491ⓔ OK :: rc=$rc $(printf '%s' "$OUT" | head -3)"
cmp -s "$HROOT/kit/fable-team/bin/ft_live_install_check.py" "$HROOT/bin/ft_live_install_check.py" && cmp -s "$CHK" "$HROOT/bin/ft-live-install-check.sh" && ok "r491ⓔ bin/kit 짝 cmp0" || bad "r491ⓔ bin/kit 짝 다름"

echo "---"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
