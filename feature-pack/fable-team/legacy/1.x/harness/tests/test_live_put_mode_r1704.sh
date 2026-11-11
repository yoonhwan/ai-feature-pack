#!/usr/bin/env bash
# test_live_put_mode_r1704.sh — r1704: ft-live-put.sh 가 새 파일을 «팩 git 모드 그대로» 설치한다(손 chmod 755 고정 금지).
#   ① 100644 → dest 644 PUT rc0   ② 100755 → dest 755 PUT rc0   ③ 기존 dest(755)를 100644 판으로 덮기 → bak(755 보존) · dest 644
#   ④ --path 없음 → ERROR rc≠0 · dest 쓰기 0   ⑤ 120000(심링크) → ERROR rc≠0 · dest 쓰기 0   ⑥ ①~③ 뒤 같은 꼴 모드 대조 = MODE 0
#   기준판 = 함수 없음(h 꼴 cat + chmod 755) → ①·⑥ FAIL · 변이 W1~W3 + 원본 대조 · 임시 리포·dest 만 · 실 라이브 0 · sleep 0
set -uo pipefail
export LC_ALL=C
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO_DIR="$(cd "$HERE/../.." && pwd)"
BIN="${R1704_BIN:-$REPO_DIR/harness/bin}"; KIT="$REPO_DIR/harness/kit/fable-team/bin"; PUT="$BIN/ft-live-put.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "PASS $1"; }; bad(){ echo "FAIL $1${2:+ :: $2}"; fail=$((fail+1)); }
[ -f "$PUT" ] && bash -n "$PUT" && ok "bash -n ft-live-put.sh" || { bad "ft-live-put.sh 없음/문법"; exit 1; }
cmp -s "$PUT" "$KIT/ft-live-put.sh" && ok "bin·kit cmp 0" || bad "bin·kit 불일치"
[ "$(wc -l < "$PUT" | tr -d ' ')" -le 60 ] && ok "ft-live-put.sh ≤60줄($(wc -l < "$PUT" | tr -d ' '))" || bad "60줄 초과"
# ── 임시 git 리포: bin/plain.sh(100644) · bin/exec.sh(100755) · bin/link(120000) ──────────────
R="$T/repo"; mkdir -p "$R/bin"; git init -q -b main "$R"
G(){ git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
printf '#!/bin/sh\necho plain\n' > "$R/bin/plain.sh"
printf '#!/bin/sh\necho exec\n' > "$R/bin/exec.sh"; chmod 755 "$R/bin/exec.sh"
ln -s plain.sh "$R/bin/link"
G add -A >/dev/null; G commit -qm base; REV="$(G rev-parse HEAD)"
G ls-tree "$REV" -- bin/plain.sh | awk '{print "INFO mode", $1, $2}' >/dev/null   # (읽기만)
MODE_PLAIN="$(G ls-tree "$REV" -- bin/plain.sh | awk '{print $1}')"; MODE_EXEC="$(G ls-tree "$REV" -- bin/exec.sh | awk '{print $1}')"
D="$T/dest"; mkdir -p "$D"
put(){ bash "$1" --repo "$R" --ref "$REV" --path "$2" --dest "$3" ${4:+--bak "$4"} 2>&1; }
mode_of(){ [ -x "$1" ] && echo 755 || echo 644; }

# ① 100644 → dest 644 · PUT rc0
o="$(put "$PUT" bin/plain.sh "$D/plain.sh")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == PUT*"mode=644"* ]] && [ "$(mode_of "$D/plain.sh")" = 644 ]; } \
  && ok "① 100644($MODE_PLAIN) → dest 644 · PUT rc0" || bad "① rc=$rc «$o» mode=$(mode_of "$D/plain.sh" 2>/dev/null)"
# ② 100755 → dest 755 · PUT rc0
o="$(put "$PUT" bin/exec.sh "$D/exec.sh")"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == PUT*"mode=755"* ]] && [ "$(mode_of "$D/exec.sh")" = 755 ]; } \
  && ok "② 100755($MODE_EXEC) → dest 755 · PUT rc0" || bad "② rc=$rc «$o» mode=$(mode_of "$D/exec.sh" 2>/dev/null)"
# ③ 기존 dest(755) 위에 100644 판 → bak(755 보존) · dest 644
printf '#!/bin/sh\necho old\n' > "$D/plain.sh"; chmod 755 "$D/plain.sh"
o="$(put "$PUT" bin/plain.sh "$D/plain.sh" b1)"; rc=$?
{ [ "$rc" = 0 ] && [ "$(mode_of "$D/plain.sh")" = 644 ] && [ -f "$D/plain.sh.bak-b1" ] && [ "$(mode_of "$D/plain.sh.bak-b1")" = 755 ]; } \
  && ok "③ 기존 dest 755 → 백업(755 보존) + dest 644" || bad "③ rc=$rc «$o» bak=$(ls "$D" | tr '\n' ' ')"
# ④ 없는 경로 → ERROR rc≠0 · 쓰기 0
o="$(put "$PUT" bin/nope.sh "$D/nope.sh")"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == ERROR* ]] && [ ! -e "$D/nope.sh" ]; } && ok "④ 없는 경로 → ERROR rc≠0 · 쓰기 0" || bad "④ rc=$rc «$o»"
# ⑤ 심링크(120000) → ERROR rc≠0 · 쓰기 0
o="$(put "$PUT" bin/link "$D/link")"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == ERROR* ]] && [ ! -e "$D/link" ]; } && ok "⑤ 120000 심링크 → ERROR rc≠0 · 쓰기 0" || bad "⑤ rc=$rc «$o»"
# ⑥ ①~③ 뒤 모드 대조(drift-check:80 과 같은 규칙) = MODE 0
drift(){ local n=0 p m; for p in bin/plain.sh bin/exec.sh; do m="$(G ls-tree "$REV" -- "$p" | awk '{print $1}')"; f="$D/${p##*/}"
  if [ "$m" = 100755 ]; then [ -x "$f" ] || n=$((n+1)); else [ ! -x "$f" ] || n=$((n+1)); fi; done; echo "$n"; }
[ "$(drift)" = 0 ] && ok "⑥ ①~③ 뒤 모드 대조 = MODE 0" || bad "⑥ MODE $(drift)"
# ── 기준판(함수 없음 = h 꼴 cat + chmod 755) → ①·⑥ FAIL ──────────────────────────────
OLD="$T/old"; mkdir -p "$OLD"; printf '#!/bin/sh\n# 기준판: h 꼴 — git 모드 안 읽고 손 chmod 755\nset -e\ncp %s/bin/plain.sh "$2"; chmod 755 "$2"\n' "$R" > "$OLD/put.sh"
D2="$T/dest2"; mkdir -p "$D2"; bash "$OLD/put.sh" x "$D2/plain.sh" 2>/dev/null
{ [ "$(mode_of "$D2/plain.sh")" = 755 ]; } && ok "Red ① — 기준판(h 꼴 chmod 755)은 100644 파일을 755 로 깐다" || bad "Red ① 확인 실패"
DD="$D2" bash -c 'f="$DD/plain.sh"; [ -x "$f" ] && echo 1 || echo 0' | grep -qx 1 && ok "Red ⑥ — 기준판 설치 뒤 모드 대조 = MODE 1" || bad "Red ⑥ 확인 실패"
# ── 변이 W1~W3(사본에서만 · 변이마다 원본으로 같은 사례 반대 결과 대조) ────────────────────────
mkx(){ local d="$T/w-$1"; mkdir -p "$d"; cp "$PUT" "$d/ft-live-put.sh"
  python3 - "$d/ft-live-put.sh" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
assert old in s, "변이 대상 없음: " + old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  printf '%s\n' "$d/ft-live-put.sh"; }
X="$(mkx w1 'case "$MODE" in 100755) WANT=755;; 100644) WANT=644;; *) die "ERROR 모르는 git 모드: $MODE ($PATH_IN)";; esac' 'WANT=755')"
D3="$T/dest3"; mkdir -p "$D3"
o="$(put "$X" bin/plain.sh "$D3/plain.sh")"; o2="$(put "$PUT" bin/plain.sh "$D3/o.sh")"
{ [ "$(mode_of "$D3/plain.sh")" = 755 ] && [ "$(mode_of "$D3/o.sh")" = 644 ]; } \
  && ok "W1 모드 맞추기 «항상 755» → ① FAIL(원본은 644 · 대조)" || bad "W1 검출 실패 «$o»"
X="$(mkx w2 '  [ -e "$BAKED" ] || cp -p "$DEST" "$BAKED" || die "ERROR 백업 실패: $BAKED"' ':')"
printf 'old\n' > "$D3/b.sh"; chmod 755 "$D3/b.sh"
o="$(put "$X" bin/plain.sh "$D3/b.sh" b2)"; printf 'old2\n' > "$D3/b2.sh"; chmod 755 "$D3/b2.sh"; o2="$(put "$PUT" bin/plain.sh "$D3/b2.sh" b2)"
{ [ ! -f "$D3/b.sh.bak-b2" ] && [ -f "$D3/b2.sh.bak-b2" ]; } \
  && ok "W2 백업 단계 삭제 → ③ FAIL(원본은 bak 생김 · 대조)" || bad "W2 검출 실패 «$o»"
X="$(mkx w3 '[ "$TYPE" = blob ] || die "ERROR blob 이 아닌 꼴: $PATH_IN type=$TYPE (심링크 120000·서브모듈 160000 은 설치 대상 아니다)"' ':')"
o="$(put "$X" bin/link "$D3/link")"; o2="$(put "$PUT" bin/link "$D3/link2")"
{ [ "$?" != 0 ] || [ -e "$D3/link" ]; } && [ ! -e "$D3/link2" ] \
  && ok "W3 blob 꼴 검사 삭제 → ⑤ FAIL(원본은 거절 · 대조)" || bad "W3 검출 실패 «$o»"
# ⑦ ERROR 경로마다 dest 폴더가 그대로(임시 파일 0) — <dest>.put.<pid>.src 잔존 금지
D4="$T/dest4"; mkdir -p "$D4"; printf 'old\n' > "$D4/keep.sh"; chmod 755 "$D4/keep.sh"
before="$(ls "$D4" | sort | tr '\n' ' ')"
put "$PUT" bin/nope.sh "$D4/nope.sh" >/dev/null; put "$PUT" bin/link "$D4/link" >/dev/null; put "$PUT" bin/plain.sh "$D4/keep.sh" >/dev/null
after="$(ls "$D4" | sort | tr '\n' ' ')"
{ [ "$before" = "$after" ] && ! ls "$D4" | grep -q '\.put\.'; } && ok "⑦ ERROR 경로 3종 뒤 dest 폴더 그대로(임시 파일 0)" || bad "⑦ «$before» → «$after»"
X="$(mkx w4 '[ -d "$(dirname "$DEST")" ] || die "ERROR dest 폴더 없음: $(dirname "$DEST")"' 'git -C "$REPO" cat-file blob "$BLOB" > "$DEST.put.$$.src" 2>/dev/null; [ -d "$(dirname "$DEST")" ] || die "ERROR dest 폴더 없음: $(dirname "$DEST")"')"
D5="$T/dest5"; mkdir -p "$D5"; printf 'old\n' > "$D5/k.sh"; chmod 755 "$D5/k.sh"
bash "$X" --repo "$R" --ref "$REV" --path bin/plain.sh --dest "$D5/k.sh" >/dev/null 2>&1
leaked="$(ls "$D5" | grep -c '\.put\.')"
{ [ "$leaked" -ge 1 ]; } && ok "W4 검사 순서 되돌림(임시 파일 먼저) → ⑦ FAIL(원본은 잔존 0 · 대조)" || bad "W4 검출 실패 leaked=$leaked"
# ⑧ 상대 --dest — 절대 --repo 와 함께 줘도 PUT rc0(종전엔 hash-object 가 REPO 기준으로 읽어 rc1)
D8="$T/rel8"; mkdir -p "$D8"
o="$( cd "$T" && bash "$PUT" --repo "$R" --ref "$REV" --path bin/plain.sh --dest rel8/plain.sh 2>&1 )"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == PUT*"mode=644"* ]] && [ "$(mode_of "$D8/plain.sh")" = 644 ]; } \
  && ok "⑧ 상대 --dest → PUT rc0 · dest 644" || bad "⑧ rc=$rc «$o»"
X="$(mkx w5 'DEST="$DEST_ABS/$(basename "$DEST")"' ':')"   # 절대화를 없앤다 → 상대 --dest 는 hash-object 가 REPO 기준으로 읽어 실패
o="$( cd "$T" && bash "$X" --repo "$R" --ref "$REV" --path bin/plain.sh --dest rel8/p2.sh 2>&1 )"; rc=$?
{ [ "$rc" != 0 ] && [[ "$o" == *"FAIL dest 해시"* || "$o" == *ERROR* ]]; } && ok "W5 절대화 삭제 → ⑧ FAIL(원본은 rc0 · 대조)" || bad "W5 검출 실패 rc=$rc «$o»"
# ⑨ CDPATH=. + 상대 --dest — cd 가 경로를 찍어 DEST 가 두 줄이 되지 않는다(DA R1)
D9="$T/rel9"; mkdir -p "$D9"
o="$( cd "$T" && CDPATH=. bash "$PUT" --repo "$R" --ref "$REV" --path bin/plain.sh --dest rel9/plain.sh 2>&1 )"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == PUT*"mode=644"* ]] && [ "$(mode_of "$D9/plain.sh")" = 644 ]; } \
  && ok "⑨ CDPATH=. 상대 --dest → PUT rc0 · dest 644" || bad "⑨ rc=$rc «$o»"
X="$(mkx w6 'DEST_ABS="$(CDPATH= cd -- "$(dirname "$DEST")" >/dev/null 2>&1 && pwd)"' 'DEST_ABS="$(cd -- "$(dirname "$DEST")" && pwd)"')"
o="$( cd "$T" && CDPATH=. bash "$X" --repo "$R" --ref "$REV" --path bin/plain.sh --dest rel9/p2.sh 2>&1 )"; rc=$?
{ [ "$rc" != 0 ] || [[ "$o" != PUT* ]]; } && ok "W6 CDPATH 차단 삭제 → ⑨ FAIL(원본은 rc0 · 대조)" || bad "W6 검출 실패 rc=$rc «$o»"
echo "FAILED $fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit $([ "$fail" = 0 ] && echo 0 || echo 1)
