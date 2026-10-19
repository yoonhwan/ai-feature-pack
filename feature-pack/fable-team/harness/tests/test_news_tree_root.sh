#!/usr/bin/env bash
# test_news_tree_root.sh — r489: ft-news-tree.py 루트·팀 폴더를 «부르는 쪽이 넘긴다»(--root · --team-dir) · 축 ⓐ~ⓓ + 틱 ⑥ 실사건 재현.
# 픽스처 = mktemp 임시 리포(design/TEAMS.md v65 행 · design/v65/NEWS-TREE.md 3행 · indices/진행/x.md · 가짜 origin/main ref)
#          + 리포 밖 임시 트리 사본(ref 임시본 자리) · 가짜 tmux(좌석 0) — 실 루트·외부 호출 0 · GIT_* env 0.
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_NEWS_ROOT FT_NEWS_TEAM_DIR FT_NEWS_TREE FT_TEAMS_REF; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KB="$HERE/../kit/fable-team/bin"; PY="$KB/ft-news-tree.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }

# 가짜 tmux = 좌석 0 (tmux_alive 빈 집합)
mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod 755 "$T/stub/tmux"; export PATH="$T/stub:$PATH"

R="$T/repo"; mkdir -p "$R/design/v65/indices/진행" "$R/.fable-team"
git init -q -b main "$R"
printf '| 팀 | 폴더 | 설명 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '[idx:x] 엑스 카드\n[🔄] 베타 하는 중\n[⏳] 감마 대기\n' > "$R/design/v65/NEWS-TREE.md"
printf '# x\n' > "$R/design/v65/indices/진행/x.md"
git -C "$R" add design && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m fixture
git -C "$R" update-ref refs/remotes/origin/main HEAD
printf '{}\n' > "$R/.fable-team/seats.json"   # 공용 .fable-team/seats.json (추적 밖)
mkdir -p "$T/tmp"; TMPTREE="$T/tmp/ft-team-doc.AbC123"; cp "$R/design/v65/NEWS-TREE.md" "$TMPTREE"   # 리포 밖 = ref 임시본 자리

# 대조(시험 이빨): 옛 꼴 = 인자 없이 리포 밖 임시본 → git 128 로 죽는다(arch 103 실측 재현)
out="$(python3 "$PY" "$TMPTREE" 2>&1)"; rc=$?
[ "$rc" != 0 ] && has "$out" "CalledProcessError" "대조: 인자 없이 임시본 = CalledProcessError 재현(rc=$rc)" || bad "대조: 인자 없이 임시본인데 rc=0"

# ⓐ --root · --team-dir → rc0 · 트리 줄 ≥1 · 카드 상태 = 체크아웃 폴더(진행=🔄)
out="$(python3 "$PY" "$TMPTREE" --root "$R" --team-dir "$R/design/v65" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓐ 임시본 + 두 인자"; has "$out" "🔄 엑스 카드" "ⓐ 카드 상태 = 체크아웃 indices/진행"; has "$out" "베타 하는 중" "ⓐ 트리 줄 ≥1"
hasnt "$out" "카드없음" "ⓐ ⚠카드없음 0"; hasnt "$out" "Traceback" "ⓐ Traceback 0"
OUT_A="$out"

# ⓑ 체크아웃에서 indices 제거 → ref(origin/main) 에서 같은 값
rm -rf "$R/design/v65/indices"
out="$(python3 "$PY" "$TMPTREE" --root "$R" --team-dir "$R/design/v65" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓑ indices 없음 → ref"; [ "$out" = "$OUT_A" ] && ok "ⓑ ref 읽기 = ⓐ 와 같은 출력" || bad "ⓑ ⓐ 와 다름 ← ${out:0:300}"
out="$(FT_NEWS_ROOT="$R" FT_NEWS_TEAM_DIR="$R/design/v65" python3 "$PY" "$TMPTREE" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓑ env 동치"; [ "$out" = "$OUT_A" ] && ok "ⓑ env(FT_NEWS_ROOT·FT_NEWS_TEAM_DIR) = 인자와 같은 출력" || bad "ⓑ env 출력 다름"

# ⓒ 루트에도 ref 에도 카드 폴더 없음 → «?(폴더 없음)» · rc0 · Traceback 0
out="$(python3 "$PY" "$TMPTREE" --root "$R" --team-dir "$R/design/nope" 2>&1)"; rc=$?
rc_is "$rc" 0 "ⓒ 폴더 없음"; has "$out" "? 엑스 카드 ?(폴더 없음)" "ⓒ 줄에 ?(폴더 없음)"; hasnt "$out" "Traceback" "ⓒ Traceback 0"
has "$out" "베타 하는 중" "ⓒ 카드 없는 줄은 그대로"

# ⓓ 역호환: 인자 없이 체크아웃 트리 → 옛 스크립트(origin/main 판)와 같은 출력
git -C "$R" checkout -q -- design/v65/indices
OLD="$T/old-ft-news-tree.py"
if git -C "$HERE" show "origin/main:feature-pack/fable-team/harness/kit/fable-team/bin/ft-news-tree.py" > "$OLD" 2>/dev/null; then
  new="$(python3 "$PY" "$R/design/v65/NEWS-TREE.md" 2>&1)"; rc=$?; old="$(python3 "$OLD" "$R/design/v65/NEWS-TREE.md" 2>&1)"
  rc_is "$rc" 0 "ⓓ 인자 없이 체크아웃 트리"; [ "$new" = "$old" ] && ok "ⓓ 옛 스크립트와 출력 바이트 같음" || bad "ⓓ 출력 다름 ← new=${new:0:200} old=${old:0:200}"
else bad "ⓓ origin/main 판 ft-news-tree.py 를 못 읽음"; fi

# 틱 ⑥ 실사건 재현: 체크아웃에 NEWS-TREE.md·indices 없음(공용 루트 꼴) → ref 임시본 → 두 인자 실려 트리 줄 ≥1
L="$T/live"; mkdir -p "$L"; cp -p "$PY" "$KB/ft-harness-root.sh" "$KB/ft-team-lib.sh" "$L/"
mk_s6() { awk '1; /^WT=/{exit}' "$1" > "$2"; awk '/════ ⑥/{p=1} p' "$1" >> "$2"; }
mk_s6 "$KB/ft-news-tick.sh" "$L/ft-news-tick-s6.sh"
grep -q -- '--root "$ROOT" --team-dir' "$L/ft-news-tick-s6.sh" && ok "틱 ⑥ 호출 줄에 --root · --team-dir 실림" || bad "틱 ⑥ 호출 줄에 두 인자 없음"
rm -rf "$R/design/v65/indices" "$R/design/v65/NEWS-TREE.md"
out="$(cd "$R" && TMPDIR="$T/tmp" FT_NEWS_ROOT="$R" bash "$L/ft-news-tick-s6.sh" 2>"$T/err")"; err="$(cat "$T/err")"
has "$out" "🔄 엑스 카드" "틱 ⑥ 트리 줄(카드 상태 = ref)"; hasnt "$err$out" "Traceback" "틱 ⑥ Traceback 0"; hasnt "$err$out" "SyntaxError" "틱 ⑥ SyntaxError 0"
[ -z "$(ls "$T/tmp" | grep -v AbC123)" ] && ok "틱 ⑥ ref 임시본 삭제(trap 그대로)" || bad "틱 ⑥ 임시본 남음: $(ls "$T/tmp")"
# 대조: 옛 틱(origin/main 판) ⑥ 절 = 같은 픽스처에서 CalledProcessError
if git -C "$HERE" show "origin/main:feature-pack/fable-team/harness/kit/fable-team/bin/ft-news-tick.sh" > "$T/old-tick.sh" 2>/dev/null; then
  cp -p "$OLD" "$L/ft-news-tree.py"; mk_s6 "$T/old-tick.sh" "$L/ft-news-tick-old-s6.sh"
  out="$(cd "$R" && TMPDIR="$T/tmp" FT_NEWS_ROOT="$R" bash "$L/ft-news-tick-old-s6.sh" 2>&1)"
  has "$out" "CalledProcessError" "대조: 옛 틱 ⑥ = CalledProcessError 재현"
  cp -p "$PY" "$L/ft-news-tree.py"
else bad "대조: origin/main 판 ft-news-tick.sh 를 못 읽음"; fi

# cfo 틱 ⑥ 호출 줄도 같은 꼴
grep -q 'ft-news-tree.py" "$TREE" --root "$ROOT" --team-dir "$CFO_DIR"' "$KB/ft-news-tick-cfo.sh" && ok "cfo ⑥ 호출 줄에 --root · --team-dir" || bad "cfo ⑥ 호출 줄 꼴 다름"

echo "== fail=$fail"; [ "$fail" = 0 ]
