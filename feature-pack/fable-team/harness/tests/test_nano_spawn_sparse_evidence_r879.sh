#!/usr/bin/env bash
# test_nano_spawn_sparse_evidence_r879.sh — r879 r3: ft-nano-spawn.sh sparse = 자기 팀 폴더 안 «미디어 확장자»만 제외 · 카드 본문 글자 파싱 0
#   ⓐ 남의 카드 증거 폴더의 .wav·.mp4(대문자)·.png·.zip = OUT   ⓑ 같은 폴더의 .md·.txt·.json = IN(작은 글자는 받음)
#   ⓒ 카드가 적은 «evidence/my report.md»·«evidence/INV(final).md»·evidence 바로 아래 파일 = IN(글자 파싱 없이)
#   ⓓ 자기 stem 폴더(evidence/<slug>/)의 .wav = IN   ⓔ fixtures/ 아래 .wav = IN   ⓕ 남의 팀 design = OUT
#   ⓖ FT_NANO_SPARSE=0 이면 전체 (r5 변이는 파일 끝 변이 블록 — 4종)
#   r3b(REWORK-r879-r3b): ⓗ 남의 stem 폴더 result.json·x.jsonl = OUT(같은 폴더 summary.json = IN) · ⓘ 자기 stem 폴더 result.json·x.jsonl = IN
#     변이: result.json·jsonl 줄 제거 → ⓗ FAIL · 자기 stem 허용을 맨 앞으로 → ⓘ FAIL
#   r4(REWORK-r879-r4 · DA⑥ r3 반례 2): ⓚ 이름이 확장자로 끝나는 «폴더»(other.wav/) 안 글자 = IN · 그 안 미디어 = OUT
#     ⓛ 섞인 대소문자(a.WaV·b.PnG·Result.JSON·x.JsonL) = OUT · ⓐ'ⓑ' core.ignorecase=false 에서도 같은 판정
#   r5(REWORK-r879-r5 · 하드 룰 14 재설계): 제외 규칙 = «git 이 아는 실재 파일 이름 그대로»(literal) 1줄씩 · 손글자 glob 0
#     ⓨ1 other.wav/ 안 글자 IN(파일만 제외 · 폴더 오인 0) · ⓨ2 섞인 대소문자 OUT(소문자 비교)
#     ⓨ3 공백·괄호·`[` 이름 IN/OUT 정확(이스케이프 1규칙) · ⓨ4 evidence 바로 아래 md IN · 남의 카드 big.wav OUT · 자기 카드 big.wav IN(되살림 순서)
#     ⓨ5 새 파일(트리에 없음)은 제외 0 → add rc0 · 제외 줄 수 = 머리 3 + 실재 제외 파일 수 + 되살림 2
#     ⓨ6 미디어 15확장자 전부 OUT(디스크 회귀 = r3b 이상)
#     변이: «소문자 비교 삭제» → ⓨ2 FAIL · «이스케이프 삭제» → ⓨ3 FAIL · «파일/폴더 구분 없이 glob» → ⓨ1 FAIL · «되살림 줄을 제외 줄 앞으로» → ⓨ4 FAIL
#   r6(REWORK-r879-r6 · DA⑥ r4 반례 «파일명 속 개행»): 이름 안 제어 문자(개행·탭·CR)는 글자 하나당 `?` 한 글자로 적는다(규칙 파일이 줄 단위)
#     ⓨ7 DA 반례 그대로 — `other/line\nbreak.wav` OUT · `other/line/note.md` IN · `other/line\nnote.md` IN · 규칙 줄에 «!/도 /*도 아닌» 줄 0 · add rc0
#     ⓨ8 제어 문자 꼴 2 — `tab\there.mp3`(탭) · `cr\rhere.png`(CR) OUT · 같은 폴더 `tab/x.md` IN
#     변이: «제어 문자 갈래 삭제» → ⓨ7 FAIL
#     ★기본 core.ignorecase=true 에서는 git 이 대소문자를 무시해 ⓛ 만으로는 r3b 판을 못 가른다 — 판별 칸은 ⓐ'ⓑ'(ignorecase=false) 다.★
# 픽스처 = 임시 리포 + spawn 의 워크트리 블록만 잘라 실행 · 실 좌석·실 워크트리 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SPAWN="${FT_R879_SPAWN:-$HERE/../bin/ft-nano-spawn.sh}"   # 변이 시험은 사본 경로를 넘긴다
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

SLUG="r9-sparse-card"; L="design/teams/lecture"; R="$T/R"
mk() { mkdir -p "$(dirname "$R/$1")" && echo "${2:-x}" > "$R/$1"; }
# 카드 본문에 증거 경로를 «글자로» 적어 둔다 — r3 는 이 글자를 읽지 않는다(파싱 0). 글자가 있어도 없어도 결과가 같아야 한다.
mk "$L/indices/진행/$SLUG.md" "증거 $L/evidence/my report.md · $L/evidence/INV(final).md · 남의 팀 design/teams/v65/evidence/z/ · 참고 $L/20261025/evidence-t1/r.md"
mk "$L/PLAN.md"; mk "$L/fixtures/g.wav"; mk "$L/fixtures/deep/x.mp4"; mk "$L/evidence/$SLUG/old.md"; mk "$L/evidence/$SLUG/clip.wav"
# ⓐ 남의 카드 증거 폴더의 미디어 = OUT
mk "$L/evidence/other/big.wav"; mk "$L/evidence/other/clip.MP4"; mk "$L/evidence/other/pic.png"; mk "$L/evidence/arch1/arch.zip"; mk "$L/notes/a.wav"
# ⓑ 남의 카드 증거 폴더의 글자 = IN
mk "$L/evidence/other/note.md"; mk "$L/evidence/other/a.txt"; mk "$L/evidence/other/d.json"
# r3b ⓗ 남의 stem 폴더의 큰 글자(result.json·jsonl) = OUT · 같은 폴더 다른 json = IN
mk "$L/evidence/other/result.json"; mk "$L/evidence/other/x.jsonl"; mk "$L/evidence/other/y.JSONL"; mk "$L/evidence/arch1/result.json"
mk "$L/evidence/other/summary.json"; mk "$L/evidence/$SLUG/result.json"; mk "$L/evidence/$SLUG/x.jsonl"
# r4 ⓚ 이름이 미디어 확장자로 끝나는 «폴더»(other.wav/) — 그 안 글자 파일은 IN, 그 안 미디어는 OUT
mk "$L/evidence/other.wav/note.md"; mk "$L/evidence/other.wav/summary.json"; mk "$L/evidence/other.wav/x.wav"
# r4 ⓛ 섞인 대소문자 미디어·큰 글자 = OUT(core.ignorecase false 에서도)
mk "$L/evidence/other/a.WaV"; mk "$L/evidence/other/b.PnG"; mk "$L/evidence/other/Result.JSON"; mk "$L/evidence/other/x.JsonL"
# r5 ⓨ3 공백·괄호·`[` 이름(이스케이프 1규칙) · ⓨ6 미디어 15확장자 전부 + 섞인 대소문자 2
mk "$L/evidence/other/my song (final).WAV"; mk "$L/evidence/other/weird[1].png"
for _x in wav mp3 m4a flac ogg mp4 webm mov png jpg jpeg gif zip tar gz tgz; do mk "$L/notes/ext-s.$_x"; done
mk "$L/notes/ext-up.MP3"; mk "$L/notes/ext-up2.FlAc"
# r6 이름 안 제어 문자(개행·탭·CR) — 규칙이 «줄 단위»라 literal 로 적을 수 없다 · 같은 폴더 «글자» 파일로 폴더 오인도 함께 본다
mk "$L/evidence/other/line"$'\n'"break.wav"; mk "$L/evidence/other/line/note.md"; mk "$L/evidence/other/line"$'\n'"note.md"
mk "$L/evidence/other/tab"$'\t'"here.mp3"; mk "$L/evidence/other/cr"$'\r'"here.png"; mk "$L/evidence/other/tab/x.md"
# ⓒ 카드가 적은 evidence/ 바로 아래 파일 = IN
mk "$L/20261025/evidence-t1/r.md"; mk "$L/evidence/my report.md"; mk "$L/evidence/INV(final).md"; mk "$L/evidence/top.md"
# ⓕ 남의 팀 design = OUT
mk "design/teams/v65/evidence/z/q"; mk "design/teams/v65/evidence/z/big.wav"
mk "tests/fixtures/t.wav"; mk "code/f"; mk "README"
git -C "$R" init -q -b main && G "$R" add -A && G "$R" commit -qm base

# spawn 의 워크트리 분기 블록(함수 정의 + _SPT 부터 첫 «  fi») 만 잘라 실행 — 실제 배선 그대로
# r4: 함수가 여러 줄(r4 확장자 생성기)이므로 «함수 블록 전문» 을 뜬다 — 첫 함수 줄부터 WTDIR 분기 직전까지 + _SPT 블록
BLK="$(awk '/(^SPARSE_EXTS=|^sparse_[a-z_]+\(\) \{)/{f=1} /^if \[ ! -d "\$WTDIR" \]/{f=0} f{print} /^  _SPT=/{g=1} g{print} g&&/^  fi$/{exit}' "$SPAWN")"
grep -q 'sparse_patterns() {' <<<"$BLK" || { echo "FAIL 블록 추출 — r5 함수가 안 들어감"; exit 1; }
grep -q '^SPARSE_EXTS=' <<<"$BLK" || { echo "FAIL 블록 추출 — r5 확장자 목록(SPARSE_EXTS)이 안 들어감"; exit 1; }
run_blk() {  # $1 = 워크트리 · $2 = FT_NANO_SPARSE
  ( ROOT="$R"; WTDIR="$1"; BRANCH="nano/$(basename "$1")"; BASE_BRANCH=main; IDX_ABS="$R/$L/indices/진행/$SLUG.md"; FT_NANO_SPARSE="$2"
    eval "$BLK" ) >"$T/blk.out" 2>&1
}
W="$T/W1"; run_blk "$W" 1
has() { [ -e "$W/$1" ]; }

# ⓐ 미디어 OUT
out=""; for p in "$L/evidence/other/big.wav" "$L/evidence/other/clip.MP4" "$L/evidence/other/pic.png" "$L/evidence/arch1/arch.zip" "$L/notes/a.wav" design/teams/v65; do has "$p" && out="$out $p"; done
wavs="$(cd "$W/design/teams" 2>/dev/null && find . -type f \( -name '*.wav' -o -name '*.mp4' -o -name '*.MP4' -o -name '*.png' -o -name '*.zip' \) -not -path '*/fixtures/*' -not -path '*/evidence/'$SLUG'/*' | tr '\n' ' ')"
{ [ -z "$out" ] && [ -z "$wavs" ]; } && ok "ⓐ 남의 카드 증거 폴더 미디어(wav·MP4·png·zip)·자기 팀 notes/wav 0 · 남의 팀 0" || bad "ⓐ 남은 것:$out 미디어=[$wavs] ($(cat "$T/blk.out"))"

# ⓑ 글자 IN
keep=""; for p in "$L/evidence/other/note.md" "$L/evidence/other/a.txt" "$L/evidence/other/d.json" "$L/evidence/my report.md" "$L/evidence/INV(final).md" "$L/evidence/top.md" "$L/20261025/evidence-t1/r.md"; do has "$p" || keep="$keep $p"; done
[ -z "$keep" ] && ok "ⓑ 남의 카드 증거 폴더의 md·txt·json · 공백·괄호 파일명 · evidence 바로 아래 파일 = IN" || bad "ⓑ 빠진 것:$keep ($(git -C "$W" sparse-checkout list | tr '\n' ' '))"

# ⓒ 카드 글자에 없는 경로도 같은 결과(파싱 0) — 카드에서 경로를 지우고 다시
mk "$L/indices/진행/$SLUG.md" "증거 경로 없음"; G "$R" commit -qam nocite
W="$T/W2"; run_blk "$W" 1
{ has "$L/evidence/my report.md" && has "$L/evidence/INV(final).md" && ! has "$L/evidence/other/big.wav" && has "$L/evidence/other/note.md"; } \
  && ok "ⓒ 카드 글자 0 이어도 같은 결과(md IN · 미디어 OUT · 카드 글자 파싱 없음)" || bad "ⓒ 카드 글자 0 에서 결과가 달라짐 ($(cat "$T/blk.out"))"

# ⓓ 자기 stem 폴더 = 통째(미디어 포함) · ⓔ fixtures = 통째 · 새 파일 git add rc0
addok() { mkdir -p "$(dirname "$W/$1")" && echo n > "$W/$1" && git -C "$W" add "$1" >/dev/null 2>&1; }
{ has "$L/evidence/$SLUG/clip.wav" && has "$L/evidence/$SLUG/old.md" && addok "$L/evidence/$SLUG/new.wav" && addok "$L/evidence/$SLUG/new.md"; } \
  && ok "ⓓ 자기 stem 폴더(evidence/$SLUG/)의 wav·md 있음 + 새 wav·md git add rc0" || bad "ⓓ 자기 stem 폴더 미디어가 빠짐/막힘 ($(git -C "$W" sparse-checkout list | tail -2 | tr '\n' ' '))"
{ has "$L/fixtures/g.wav" && has "$L/fixtures/deep/x.mp4" && has tests/fixtures/t.wav; } && ok "ⓔ fixtures/ 아래 wav·mp4 IN(기존 그대로) · 팀 밖 tests/fixtures 도 IN" || bad "ⓔ fixtures 가 빠짐"
addok "$L/evidence/other/new.wav" && ok "ⓨ5' 남의 카드 증거 폴더 «새» wav add rc0 — r5 계약 ③ = 트리에 없는 새 파일은 제외 0" || bad "ⓨ5' 새 wav add 가 막혔음(r5 는 새 파일 제외 0)"
addok "$L/evidence/other/new.md" && ok "ⓑ' 남의 카드 증거 폴더 새 md add rc0(글자는 받음)" || bad "ⓑ' 남의 카드 증거 폴더 새 md add 막힘"

# r3b ⓗ 남의 stem 폴더 result.json·jsonl = OUT(남의 팀 폴더 안 큰 글자) · 같은 폴더 summary.json = IN
left=""; for p in "$L/evidence/other/result.json" "$L/evidence/other/x.jsonl" "$L/evidence/other/y.JSONL" "$L/evidence/arch1/result.json"; do has "$p" && left="$left $p"; done
{ [ -z "$left" ] && has "$L/evidence/other/summary.json"; } && ok "ⓗ 남의 stem 폴더 result.json·x.jsonl·y.JSONL OUT · summary.json IN" || bad "ⓗ 남의 result.json·jsonl 남음[$left] summary.json 있음=$([ -e "$W/$L/evidence/other/summary.json" ] && echo yes || echo no) ($(git -C "$W" sparse-checkout list | tail -3 | tr '\n' ' '))"
# r3b ⓘ 자기 stem 폴더의 result.json·jsonl = IN(자기 카드 증거는 통째 · 허용 줄이 맨 뒤)
{ has "$L/evidence/$SLUG/result.json" && has "$L/evidence/$SLUG/x.jsonl" && addok "$L/evidence/$SLUG/new-result.json" && addok "$L/evidence/$SLUG/new.jsonl"; } \
  && ok "ⓘ 자기 stem 폴더 result.json·x.jsonl IN + 새 result.json·jsonl git add rc0" || bad "ⓘ 자기 stem 폴더 result.json/jsonl 이 빠짐/막힘 ($(git -C "$W" sparse-checkout list | tail -2 | tr '\n' ' '))"

# r4 ⓚ 이름이 확장자로 끝나는 폴더(other.wav/) — 글자 IN · add rc0 · 그 안 미디어 OUT
{ has "$L/evidence/other.wav/note.md" && has "$L/evidence/other.wav/summary.json" && ! has "$L/evidence/other.wav/x.wav" && addok "$L/evidence/other.wav/note.md"; } \
  && ok "ⓚ other.wav/note.md·summary.json IN(git add rc0) · other.wav/x.wav OUT" \
  || bad "ⓚ 확장자로 끝나는 폴더를 통째로 뺴는 중 — note.md=$([ -e "$W/$L/evidence/other.wav/note.md" ] && echo IN || echo OUT) x.wav=$([ -e "$W/$L/evidence/other.wav/x.wav" ] && echo IN || echo OUT) ($(cat "$T/blk.out"))"

# r4 ⓛ 섞인 대소문자
mixed=""; for p in a.WaV b.PnG Result.JSON x.JsonL; do has "$L/evidence/other/$p" && mixed="$mixed $p"; done
[ -z "$mixed" ] && ok "ⓛ a.WaV·b.PnG·Result.JSON·x.JsonL OUT(기본 ignorecase=true · 판별력은 ⓐ'ⓑ' 칸)" || bad "ⓛ 섞인 대소문자 남음[$mixed] ($(git -C "$W" sparse-checkout list | grep -c '\[' ))"

# r4 ⓐ'ⓑ' core.ignorecase=false 에서도 같은 판정 — 판정은 실제 git 으로만
G "$R" config core.ignorecase false
W="$T/W4"; run_blk "$W" 1
mixed=""; for p in a.WaV b.PnG Result.JSON x.JsonL; do has "$L/evidence/other/$p" && mixed="$mixed $p"; done
{ [ -z "$mixed" ] && has "$L/evidence/other/note.md" && has "$L/evidence/other/summary.json" && has "$L/evidence/other.wav/note.md" && ! has "$L/evidence/other.wav/x.wav"; } \
  && ok "ⓐ'ⓑ' core.ignorecase=false — 섞인 대소문자 미디어 OUT · 글자 IN · other.wav/ 안 글자 IN" \
  || bad "ⓐ'ⓑ' ignorecase=false 판정 어긋남[$mixed] ($(cat "$T/blk.out" | tail -2))"
G "$R" config core.ignorecase true

# ── r5 ⓨ1~ⓨ6 — 제외 규칙 = 실재 파일 이름 그대로(literal) ─────────────────────────
W="$T/W5"; run_blk "$W" 1
OUTS() { local p m=""; for p in "$@"; do has "$p" && m="$m $p"; done; printf '%s' "$m"; }
# ⓨ1 other.wav/ = «파일만» 제외 — 폴더 이름이 확장자로 끝나도 그 안 글자는 IN · add rc0
{ has "$L/evidence/other.wav/note.md" && has "$L/evidence/other.wav/summary.json" && ! has "$L/evidence/other.wav/x.wav"; } \
  && ok "ⓨ1 other.wav/note.md·summary.json IN(git add rc0) · other.wav/x.wav OUT" \
  || bad "ⓨ1 확장자로 끝나는 폴더를 통째로 빼는 중 — note.md=$(has "$L/evidence/other.wav/note.md" && echo IN || echo OUT) x.wav=$(has "$L/evidence/other.wav/x.wav" && echo IN || echo OUT) ($(tail -2 "$T/blk.out"))"
# ⓨ2 섞인 대소문자 = 소문자 비교로 OUT · core.ignorecase 무관
m="$(OUTS "$L/evidence/other/a.WaV" "$L/evidence/other/b.PnG" "$L/evidence/other/Result.JSON" "$L/evidence/other/x.JsonL")"
[ -z "$m" ] && ok "ⓨ2 a.WaV·b.PnG·Result.JSON·x.JsonL OUT(소문자 비교)" || bad "ⓨ2 섞인 대소문자 남음[$m]"
# ⓨ3 공백·괄호·`[` 이름 — 이스케이프 1규칙
{ has "$L/evidence/my report.md" && has "$L/evidence/INV(final).md" && ! has "$L/evidence/other/my song (final).WAV" && ! has "$L/evidence/other/weird[1].png"; } \
  && ok "ⓨ3 'my report.md'·'INV(final).md' IN · 'my song (final).WAV'·'weird[1].png' OUT(이스케이프)" \
  || bad "ⓨ3 공백·괄호·[,] 이름 판정 어긋남 (space.docx=$(has "$L/evidence/other/my song (final).WAV" && echo IN || echo OUT) bracket=$(has "$L/evidence/other/weird[1].png" && echo IN || echo OUT))"
# ⓨ4 evidence 바로 아래 md IN · 남의 카드 big.wav OUT · 자기 카드 big.wav IN(되살림 순서)
{ has "$L/evidence/top.md" && has "$L/evidence/$SLUG/clip.wav" && ! has "$L/evidence/other/big.wav"; } \
  && ok "ⓨ4 evidence 바로 아래 md IN · 자기 카드 clip.wav IN · 남의 카드 big.wav OUT(되살림 줄이 제외 줄 뒤)" \
  || bad "ⓨ4 되살림 순서 어긋남 (top.md=$(has "$L/evidence/top.md" && echo IN || echo OUT) self=$(has "$L/evidence/$SLUG/clip.wav" && echo IN || echo OUT) other=$(has "$L/evidence/other/big.wav" && echo IN || echo OUT))"
# ⓨ5 제외 줄 수 = 머리 3 + 실재 제외 파일 수 + 되살림 2 · 새 파일은 제외 줄 0
# r6: 이름 안 개행·탭·CR 이 있어도 «파일 수» 를 세야 한다 — 줄 단위 grep 은 인용부호·개행에 속는다(-z + python)
EXC="$(git -C "$R" ls-tree -r -z --name-only main -- "$L" | python3 -c 'import sys
exts = "wav mp3 m4a flac ogg mp4 webm mov png jpg jpeg gif zip tar gz tgz".split()
n = 0
for p in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\0"):
    if not p:
        continue
    nm = p.rsplit("/", 1)[-1].lower()
    if nm == "result.json" or nm.endswith(".jsonl") or any(nm.endswith("." + e) for e in exts):
        n += 1
print(n)')"
NL="$(git -C "$W" sparse-checkout list | wc -l | tr -d ' ')"
{ [ "$NL" = "$((3 + EXC + 2))" ] && addok "$L/evidence/$SLUG/new.wav" && addok "$L/evidence/$SLUG/new.jsonl"; } \
  && ok "ⓨ5 규칙 줄 수 = 머리3+제외$EXC+되살림2=$NL · 새 wav·jsonl add rc0(트리에 없으면 제외 0)" \
  || bad "ⓨ5 줄 수 $NL ≠ $((3 + EXC + 2)) 또는 새 파일 add 막힘"
# ⓨ6 미디어 15확장자 전부 OUT — r3b 디스크 목표(제외 집합이 줄지 않음)
miss=""; for _x in wav mp3 m4a flac ogg mp4 webm mov png jpg jpeg gif zip tar gz tgz; do has "$L/notes/ext-s.$_x" && miss="$miss $_x"; done
{ [ -z "$miss" ] && ! has "$L/notes/ext-up.MP3" && ! has "$L/notes/ext-up2.FlAc"; } \
  && ok "ⓨ6 미디어 15확장자 · 대문자 MP3·FlAc 전부 OUT" || bad "ⓨ6 확장자 남음[$miss]"

# ── r6 ⓨ7·ⓨ8 — 이름 안 제어 문자 = `?` 1글자(규칙이 줄 단위라 개행을 literal 로 못 적는다) ──────────
W="$T/W6"; run_blk "$W" 1
# ⓨ7 DA 반례 그대로 · 규칙 줄에 «머리 3줄/* … 도 !/… 도 아닌» 조각 0(개행이 규칙을 갈라놓지 않았다)
frac="$(git -C "$W" sparse-checkout list | awk '!/^\/\*/ && !/^!\// && !/^\/design\/teams\//{c++} END{print c+0}')"
{ [ "$frac" = 0 ] && ! has "$L/evidence/other/line"$'\n'"break.wav" && has "$L/evidence/other/line/note.md" && has "$L/evidence/other/line"$'\n'"note.md"; } \
  && ok "ⓨ7 line\\nbreak.wav OUT · line/note.md IN · line\\nnote.md IN · 규칙 줄 조각 0(개행으로 안 갈라짐)" \
  || bad "ⓨ7 개행 이름 판정 어긋남 — 조각줄=$frac wav=$(has "$L/evidence/other/line"$'\n'"break.wav" && echo IN || echo OUT) 폴더md=$(has "$L/evidence/other/line/note.md" && echo IN || echo OUT)"
{ mkdir -p "$W/$L/evidence/other" && echo n > "$W/$L/evidence/other/new"$'\n'"two.md" && git -C "$W" add "$L/evidence/other/new"$'\n'"two.md" >/dev/null 2>&1; } \
  && ok "ⓨ7' 트리에 없는 개행 이름 새 글자 파일 add rc0" || bad "ⓨ7' 개행 이름 새 파일 add 가 막힘"
# ⓨ8 탭·CR 도 같은 갈래 · 같은 폴더 글자는 IN
{ ! has "$L/evidence/other/tab"$'\t'"here.mp3" && ! has "$L/evidence/other/cr"$'\r'"here.png" && has "$L/evidence/other/tab/x.md"; } \
  && ok "ⓨ8 tab\\there.mp3·cr\\rhere.png OUT · 같은 폴더 tab/x.md IN(제어 문자 갈래)" \
  || bad "ⓨ8 탭·CR 이름 판정 어긋남 — tab=$(has "$L/evidence/other/tab"$'\t'"here.mp3" && echo IN || echo OUT) cr=$(has "$L/evidence/other/cr"$'\r'"here.png" && echo IN || echo OUT) tabmd=$(has "$L/evidence/other/tab/x.md" && echo IN || echo OUT)"

W="$T/W0"; run_blk "$W" 0   # ⓖ FT_NANO_SPARSE=0 → 전체 체크아웃
{ has "$L/evidence/other/big.wav" && has "$L/notes/a.wav" && has design/teams/v65/evidence/z/big.wav; } && ok "ⓖ FT_NANO_SPARSE=0 → 전체 체크아웃" || bad "ⓖ 전체 아님 ($(cat "$T/blk.out"))"

# 변이 — 사본 spawn 으로 이 시험을 다시 돌려 FAIL 을 확인(재귀 1단만 · 변이 적용 자체를 단언한다)
if [ -z "${FT_R879_SPAWN:-}" ]; then
  mut() { python3 - "$HERE/../bin/ft-nano-spawn.sh" "$T/mut.sh" "$1" <<'PY'
import sys
src, dst, kind = sys.argv[1:4]
s = open(src, encoding="utf-8").read()
if kind == "nolower":      # r5 «소문자 비교 삭제» → ⓨ2 FAIL
    out = s.replace('name = p.rsplit("/", 1)[-1].lower()', 'name = p.rsplit("/", 1)[-1]'); n = 1 if out != s else 0
elif kind == "noescape":   # r5 «이스케이프 삭제» → ⓨ3 FAIL
    out = s.replace('out.append("\\\\" + ch)', 'out.append(ch)'); n = 1 if out != s else 0
elif kind == "glob":       # r5 «파일/폴더 구분 없이 glob»(r3 판) → ⓨ1 FAIL
    out = s.replace('sys.stdout.write("!/" + "".join(out) + "\\0")',
                    'sys.stdout.write("!/" + sys.argv[2] + "/**/*." + name.rsplit(".", 1)[-1] + "\\0")'); n = 1 if out != s else 0
elif kind == "noctrl":     # r6 «제어 문자 갈래 삭제»(r5 판) → ⓨ7 FAIL
    a = '        if ord(ch) < 0x20 or ord(ch) == 0x7f:\n            out.append("?")\n            continue\n'
    out = s.replace(a, ''); n = 1 if out != s else 0
elif kind == "front":      # r5 «되살림 줄을 제외 줄 앞으로» → ⓨ4 FAIL
    a = '  sparse_exclude_lines "$1" "$2" | tr \'\\0\' \'\\n\'\n'
    b1 = '  printf \'/design/teams/%s/**/fixtures/**\\n\' "$1"\n'
    b2 = '  [ -z "${3:-}" ] || printf \'/design/teams/%s/evidence/%s/**\\n\' "$1" "$3"\n'
    out = s.replace(a + b1 + b2, b1 + b2 + a); n = 1 if out != s else 0
else: sys.exit("unknown mut")
if n != 1: sys.exit("MUT NOT APPLIED: " + kind)
open(dst, "w", encoding="utf-8").write(out)
PY
    [ "$?" = 0 ] || { echo "MUTFAIL"; return 0; }
    FT_R879_SPAWN="$T/mut.sh" bash "$0" 2>&1 | grep -c "^FAIL" || true; }
  [ "$(mut nolower)" -ge 1 ] && ok "변이: 소문자 비교 삭제 → ⓨ2 FAIL" || bad "변이: 소문자 비교 없애도 통과"
  [ "$(mut noescape)" -ge 1 ] && ok "변이: 이스케이프 삭제 → ⓨ3 FAIL" || bad "변이: 이스케이프 없애도 통과"
  [ "$(mut glob)" -ge 1 ] && ok "변이: 파일/폴더 구분 없이 glob → ⓨ1 FAIL" || bad "변이: glob 으로 되돌려도 통과"
  [ "$(mut front)" -ge 1 ] && ok "변이: 되살림 줄을 제외 줄 앞으로 → ⓨ4 FAIL" || bad "변이: 되살림 순서 바꿔도 통과"
  [ "$(mut noctrl)" -ge 1 ] && ok "변이: 제어 문자 갈래 삭제 → ⓨ7 FAIL" || bad "변이: 제어 문자 갈래 없애도 통과"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
