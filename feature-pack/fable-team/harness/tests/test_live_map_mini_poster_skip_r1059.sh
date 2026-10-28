#!/usr/bin/env bash
# test_live_map_mini_poster_skip_r1059.sh — r1059: LIVE-MAP.tsv 가 mini 전용 게시기 템플릿
#   (ops-intake/com.hermes.ops-intake-poster.plist.template)을 «이 맥 launchctl 적재» 로 재지 않는다 — skip 1행이 */*.plist.template 보다 위.
#   임시 HOME·임시 키트 리포·가짜 launchctl 만 — 실 launchctl·실 라이브·실 원격 0 · press 0 · 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"; CHK="$HERE/../../harness/bin/ft-live-install-check.sh"
POSTER=ops-intake/com.hermes.ops-intake-poster.plist.template
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
tpl() { printf '<plist><dict><key>Label</key><string>%s</string></dict></plist>\n' "$1" > "$2"; }

# ── 픽스처: 임시 HOME + 임시 FT_BIN + 임시 키트 리포(지도 = 실제 키트 지도 사본) ─────────────
export HOME="$T/home" FT_BIN="$T/ftbin"; mkdir -p "$HOME/.claude/hooks" "$HOME/.hermes/scripts" "$FT_BIN"
R="$T/repo"; KD=scripts/harness-install
mkdir -p "$R/$KD"/{ops-intake,slack-mirror}
G() { git -C "$R" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
cp "$KITMAP" "$R/$KD/LIVE-MAP.tsv"
tpl com.hermes.ops-intake-poster "$R/$KD/$POSTER"
tpl com.byz.ops-intake-sync "$R/$KD/ops-intake/com.byz.ops-intake-sync.plist.template"
tpl com.byz.sat-pull "$R/$KD/ops-intake/com.byz.sat-pull.plist.template"
tpl com.hermes.slackx "$R/$KD/slack-mirror/com.hermes.slackx.plist.template"
G add -A && G commit -qm c0; C0="$(G rev-parse HEAD)"
for f in "$POSTER" ops-intake/com.byz.ops-intake-sync.plist.template ops-intake/com.byz.sat-pull.plist.template slack-mirror/com.hermes.slackx.plist.template; do
  echo '<!-- v1 -->' >> "$R/$KD/$f"
done
G add -A && G commit -qm c1; C1="$(G rev-parse HEAD)"
echo '<!-- v2 -->' >> "$R/$KD/$POSTER"
G add -A && G commit -qm c2; C2="$(G rev-parse HEAD)"; G update-ref refs/remotes/origin/main HEAD
# 가짜 launchctl: 적재 목록 비어 있음(STUB_LOADED="") · list <라벨> 은 rc113
cat > "$T/fake-launchctl" <<'EOF'
#!/bin/bash
[ "$1" = list ] || exit 64
case " ${STUB_LOADED:-} " in *" $2 "*) printf '{\n\t"Label" = "%s";\n\t"PID" = 4242;\n}\n' "$2"; exit 0;; esac
exit 113
EOF
chmod +x "$T/fake-launchctl"
export FT_LAUNCHCTL="$T/fake-launchctl" STUB_LOADED=""
check() { out="$(bash "$CHK" --range "$C0..$C1" --repo "$R" --kit "$KD" "$@" 2>&1)"; rc=$?; }

[ -f "$CHK" ] && [ -f "$KITMAP" ]; ck "도구·지도 실재" $?
check
# ① 게시기 템플릿 = skip (R1) — 가짜 목록에 라벨 없음 → NOTLOADED 0 · skip 에 포함
! has "NOTLOADED com.hermes.ops-intake-poster"; ck "ⓐ 게시기 템플릿 → NOTLOADED 0 (skip)" $?
# ①' 범위에 게시기 하나만 → plist 검사 0 · skip=1 (skip 이 실제로 세어진다)
out="$(bash "$CHK" --range "$C1..$C2" --repo "$R" --kit "$KD" 2>&1)"; rc=$?
[ "$rc" = 0 ] && has "OK n=0 skip=1"; ck "ⓐ' 게시기만 범위 → OK n=0 skip=1 rc0" $?
# ① 변이: 새 행을 지우면 게시기가 다시 plist 검사 → NOTLOADED (행이 실제로 일을 한다)
grep -v '^ops-intake/com\.hermes\.ops-intake-poster\.plist\.template' "$KITMAP" > "$T/map-norow.tsv"
check --map "$T/map-norow.tsv"
[ "$rc" = 1 ] && has "NOTLOADED com.hermes.ops-intake-poster"; ck "ⓐ 변이(행 삭제) → 게시기 NOTLOADED 재출현" $?
# ② 이 맥에서 도는 같은 폴더 템플릿은 그대로 plist 검사 (R2) + 다른 폴더 템플릿도 그대로 (R3)
check
[ "$rc" = 1 ] && has "NOTLOADED com.byz.ops-intake-sync" && has "NOTLOADED com.byz.sat-pull" && has "NOTLOADED com.hermes.slackx"
ck "ⓑ sync·sat-pull·slackx 템플릿은 NOTLOADED(plist 검사 유지)" $?
# ② 변이: 행 패턴을 ops-intake/*.plist.template 로 넓히면 R2 가 깨진다(NOTLOADED 사라짐)
sed 's#^ops-intake/com\.hermes\.ops-intake-poster\.plist\.template#ops-intake/*.plist.template#' "$KITMAP" > "$T/map-wide.tsv"
check --map "$T/map-wide.tsv"
! has "NOTLOADED com.byz.ops-intake-sync" && ! has "NOTLOADED com.byz.sat-pull"
ck "ⓑ 변이(패턴 확대) → sync·sat-pull 검사 사라짐(R2 반례 성립)" $?
# ③ 지도는 1행만 늘었다 (R4) — origin/main 대조(이미 병합된 사본이면 0/0 = 통과)
PR="$(cd "$HERE/../../../.." && pwd)"; REL=feature-pack/fable-team/harness/kit/LIVE-MAP.tsv
if git -C "$PR" rev-parse --verify -q origin/main >/dev/null && git -C "$PR" cat-file -e "origin/main:$REL" 2>/dev/null; then
  ns="$(git -C "$PR" diff --numstat origin/main -- "$REL")"; add=0; del=0
  if [ -n "$ns" ]; then add="${ns%%	*}"; rest="${ns#*	}"; del="${rest%%	*}"; fi
  added="$(git -C "$PR" diff -U0 origin/main -- "$REL" | grep '^+[^+]' || true)"
  { [ "$add" = 1 ] && [ "$del" = 0 ] || { [ "$add" = 0 ] && [ "$del" = 0 ]; }; } && [[ "$added" == *"+$POSTER"* || -z "$added" ]]
  ck "ⓒ origin/main 대조: 추가 1(게시기 행)·삭제 0 (add=$add del=$del)" $?
else
  out="origin/main 없음"; rc=0; ck "ⓒ origin/main 없음 → 대조 생략(사본 리포)" 0
fi

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
