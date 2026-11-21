# _press_evidence_pick_newest_r2381_lib.sh — r2381 공용(source 전용): r1230 픽스처 + 기준판(고치기 전 파일) · 가짜 git(호출 기록·빚 조회 고장·fetch 지연) · 묶음/빚/세트 도우미 · 기준판 대조 · 변이
#   부른 시험이 guard_begin 뒤에 source 한다 · 실 gh·실 원격 0 · 묶음 심기 = 임시 bare 에 push
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_evidence_fixture.sh"
export BASE_SHA="e33c6e4a146a942331cb3537052e06b4c5a0ecb0"   # r2381 착수 때 팩 origin/main(고치기 전 press_evidence_*.py) — 기준판 Red 근거
PACKDIR="$(git -C "$(dirname -- "${BASH_SOURCE[0]:-$0}")" rev-parse --show-toplevel)"
BASEBIN="$T/base"; mkdir -p "$BASEBIN"
for f in press_evidence_verify.py press_evidence_land.py; do
  git -C "$PACKDIR" show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/$f" > "$BASEBIN/$f" 2>/dev/null || {
    echo "FAIL 기준판($BASE_SHA) 못 읽음: $f"; exit 1; }
done
cp "$BIN/press_evidence_parts.py" "$BASEBIN/"

# ===== 가짜 git: 호출 1줄 기록 + 빚 조회 고장(STUB_BREAK_DEBT) + fetch 지연(STUB_FETCH_SLEEP) · 나머지 = 실 git =====
REAL_GIT="$(command -v git)"; FAKEB="$T/fakebin"; GITLOG="$T/git.log"; export REAL_GIT GITLOG
mkdir -p "$FAKEB"
cat > "$FAKEB/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$GITLOG"
case " $* " in *" fetch "*) [ -z "${STUB_FETCH_SLEEP:-}" ] && exec "$REAL_GIT" "$@"; exec sleep "$STUB_FETCH_SLEEP";; esac
[ -z "${STUB_BREAK_DEBT:-}" ] || case " $* " in *" for-each-ref "*refs/press-debt*) echo "fatal: stub for-each-ref" >&2; exit 128;; esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$FAKEB/git"

mt() { sha "$REPO" "origin/main^{tree}"; }
cnt() { local n; n="$(grep -c -- "$2" "$1" 2>/dev/null)"; echo "${n:-0}"; }   # cnt <로그> <정규식> → 줄 수

landat() {  # landat <bin 폴더> <head> [main] → out · rc · GITLOG(그 실행만) · dry(빚 ref push 0)
  local b="$1" h="$2" m="${3:-$(sha "$REPO" origin/main)}"
  : > "$GITLOG"
  out="$(FT_LAND_DRY=1 PATH="$FAKEB:$PATH" python3 "$b/press_evidence_land.py" land --repo "$REPO" --main "$m" --head "$h" --landing "$h" \
        --pr 99 --title "[harness] r2381" --root "$T" 2>&1)"; rc=$?
}
both() {  # both <head> [main] → 기준판 먼저(out=brc·out=bout) 고친 판(rc·out) · 로그 = $T/base.log · $T/fixed.log
  local h="$1" m="${2:-$(sha "$REPO" origin/main)}"
  landat "$BASEBIN" "$h" "$m"; bout="$out"; brc="$rc"; cp "$GITLOG" "$T/base.log"
  landat "$BIN" "$h" "$m"; cp "$GITLOG" "$T/fixed.log"
}
reset_press() {  # 묶음·빚 ref 전부 지운다(케이스마다 «검사 N개»·이름순 사유가 앞 케이스와 안 섞이게)
  local ns r
  for ns in refs/press refs/press-debt refs/press-debt-paid; do
    for r in $(git -C "$ORIGIN" for-each-ref --format='%(refname)' "$ns/"); do git -C "$ORIGIN" update-ref -d "$r"; done
    for r in $(git -C "$REPO" for-each-ref --format='%(refname)' "$ns/"); do git -C "$REPO" update-ref -d "$r"; done
  done
  git -C "$REPO" fetch -q --prune origin 2>/dev/null; return 0
}
wset() {  # wset <가지 이름> <파일>=<내용> … → origin/main 에서 갈라진 세트 커밋 sha(음성 경로를 바꾼다)
  git -C "$REPO" fetch -q origin; git -C "$REPO" checkout -q -B "$1" origin/main
  local kv; for kv in "${@:2}"; do put "${kv%%=*}" "${kv#*=}"; done
  cm "$REPO" "set $1"; sha "$REPO" HEAD
}
asrev() {  # asrev <이름> <부모 sha> <세트 sha> → 부모만 바꾼 같은 트리 커밋(빚 조상 여부 조절)
  git -C "$REPO" commit-tree "$(sha "$REPO" "$3^{tree}")" -p "$2" -m "$1"
}
vb() { ev "$T/ev/$2" "$2" >/dev/null; rawpk "$1" "$2"; }   # vb <세트> <run> → 유효 묶음(임시 bare 에 push)
bt() { ev "$T/ev/$2" "$2" >/dev/null; : > "$T/ev/$2/table.md"; rawpk "$1" "$2"; }   # bt = 표 빈 묶음(칸 틀림)
jb() {  # jb <부모 sha> <run> → 틀린 묶음(부모 트리 = main 이라 음성 경로 트리 다름 · 칸 검사는 안 본다)
  local c; c="$(git -C "$REPO" commit-tree "$(mt)" -p "$1" -m "junk $2")"; git -C "$REPO" push -q origin "$c:refs/press/$1-$2"
}
bk() {  # bk <이름40hex 꼴> <run> → 부모 없는 묶음(rev-parse <커밋>^ 실패 = 깨진 묶음)
  local c; c="$(git -C "$REPO" commit-tree "$(mt)" -m "broken $2")"; git -C "$REPO" push -q origin "$c:refs/press/$1-$2"
}
debt() {  # debt <착지 sha> [pr] → refs/press-debt/<착지>(미상환 빚)
  local c; c="$(git -C "$REPO" commit-tree "$(git -C "$REPO" mktree </dev/null)" -m "press-debt landed=$1 pr=${2:-61} reverted=x owner=o ts=0")"
  git -C "$REPO" push -q origin "$c:refs/press-debt/$1"
}
KT=""   # ⑩ 대량 — turbopack blob 한 번만
vbl() {  # vbl <세트> <run> → 유효 묶음 ref 로컬만(批量 · 나중에 한 번에 push)
  local run="$2" d="$T/evb/$2" t c f rows=""
  mkdir -p "$d" "$T/evb"
  [ -s "$T/evb/turbopack.txt" ] || printf '%s\n' 'data: {"result":{"content":[{"type":"text","text":"{\"configErrors\":[],\"sessionErrors\":[{\"url\":\"/realtime\",\"buildError\":null,\"runtimeErrors\":[{\"m\":1}]}]}"}]},"jsonrpc":"2.0","id":1}' > "$T/evb/turbopack.txt"
  printf 'set=%s\nrun_id=%s\nseat=t\nts=0\n' "$1" "$run" > "$d/meta.txt"
  printf '{"axis":"conn","epoch_ms":1,"run_id":"%s"}\n{"axis":"dom","epoch_ms":2,"poll":1}\n' "$run" > "$d/poller_dom.jsonl"
  printf 'run_id: %s\n\n| 축 | 사실 | 시간 |\n|---|---|---|\n| 아키텍처 문서 | 기획 §5 | 12:00 |\n| 코드 | 세트 | 12:00 |\n| 로그 | worker 12:00 줄 | 12:01 |\n| 화면 | 말풍선 1 | 12:02 |\n| turbopack | build 0 · runtime 1 · config 0 · 원문 turbopack.txt | 12:03 |\n' "$run" > "$d/table.md"
  [ -n "$KT" ] || KT="$(git -C "$REPO" hash-object -w "$T/evb/turbopack.txt")"
  for f in meta.txt poller_dom.jsonl table.md; do rows="$rows$(printf '100644 blob %s\t%s\n' "$(git -C "$REPO" hash-object -w "$d/$f")" "$f")"$'\n'; done
  rows="$rows$(printf '100644 blob %s\tturbopack.txt' "$KT")"
  t="$(printf '%s\n' "$rows" | git -C "$REPO" mktree)"
  c="$(git -C "$REPO" commit-tree "$t" -p "$1" -m "bundle $run")"
  git -C "$REPO" update-ref "refs/press/$1-$run" "$c"
}
jbl() {  # jbl <부모 sha> <run> → 틀린 묶음 ref 로컬만
  local c; c="$(git -C "$REPO" commit-tree "$(mt)" -p "$1" -m "junk $2")"; git -C "$REPO" update-ref "refs/press/$1-$2" "$c"
}
mut() {  # mut <이름> <verify|land> <바꿀 문자열> <새 문자열> → MBIN = 변이 도구(사본은 변이 파일 하나만 진짜)
  local d="$T/mut-$1" f tgt=press_evidence_verify.py; mkdir -p "$d"; [ "$2" = land ] && tgt=press_evidence_land.py
  for f in "$BIN"/*; do ln -sf "$f" "$d/$(basename "$f")"; done; rm -f "$d/$tgt"
  python3 - "$BIN/$tgt" "$d/$tgt" "$3" "$4" <<'PY' || { echo "FAIL 변이 대상 없음($1)"; exit 1; }
import sys
s = open(sys.argv[1], encoding="utf-8").read(); assert sys.argv[3] in s, "변이 문자열 없음"
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
  MBIN="$d"
}
samebytes() { [ "$out" = "$bout" ] && [ "$rc" = "$brc" ]; }   # 고친 판 = 기준판 출력·rc 바이트 같음
wants() { [ "$rc" = "$1" ] && [[ "$out" == *"$2"* ]]; }   # 지금 실행이 기대(rc · 부분문자열)를 만족하나
mutbad() {  # mutbad <설명> <bin 폴더> <head> <기대 부분문자열> → 변이 실행이 기대를 «못 내면» PASS(계약 깨짐 재현)
  local why="$1" b="$2" h="$3" want="$4"; landat "$b" "$h"
  if [ "$rc" = 0 ] && [[ "$out" == *"$want"* ]]; then echo "FAIL $why :: 변이가 기대와 같음 rc=0 out=${out:0:80}"; fail=$((fail + 1)); else echo "PASS $why"; fi
}
