# lib/r2286_baseline_fixture.sh — r2286 시험 공용 몸통(source 전용)
#   대상 1.x 시험 3파일(r1348 · r726 · r728)을 git clone --shared 사본(mktemp · 실경로) 안에서 돌린다.
#   사본에 지금 작업 트리의 3파일을 덮는다 · 원 리포 쓰기 0 · 변형 파일 = 사본 tests 안 _r2286_* 이름.
#   쓰는 법: HERE 를 정한 뒤 `. "$HERE/lib/r2286_baseline_fixture.sh" && r2286_setup || exit 1`
R1348=test_news_relay_spacing_cover_pin_r1348.sh; R726=test_goal_renumber_grace_r726.sh; R728=test_goal_draft_render_no_notice_r728.sh
MAINSHA=4b5450cbe1   # 카드 r2286 기준판(팩 main · 이 카드 이전 · 고정 sha)
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
STAGE0=$SECONDS; STAGES=""; stage() { STAGES="$STAGES $1=$((SECONDS - STAGE0))s"; STAGE0=$SECONDS; }

r2286_setup() {  # TOP · TREL · T · C · CT 를 정하고 사본을 뜬다 · 실패 = «판정 불가» rc1
  TOP="$(git -C "$HERE" rev-parse --show-toplevel)" || { echo "판정 불가 — git 루트 못 찾음"; return 1; }
  TREL="${HERE#"$TOP"/}"
  T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT   # 실경로(/var → /private/var) — 3파일의 «git 루트 기준 상대 경로» 가 어긋나지 않게
  C="$T/copy"; CT="$C/$TREL"
  git clone -q --shared --no-checkout "$TOP" "$C" 2>/dev/null && git -C "$C" checkout -q --detach "$(git -C "$TOP" rev-parse HEAD)" \
    || { echo "판정 불가 — 사본 clone 실패"; return 1; }
  local f; for f in $R1348 $R726 $R728; do cp "$HERE/$f" "$CT/$f" || { echo "판정 불가 — $f 사본 못 덮음"; return 1; }; done
  stage 사본
}
variant() {  # <원본> <새 이름> <파이썬 정규식> <바꿀 글> — 사본 tests 안 변형 1개(정확히 1곳 치환)
  python3 - "$CT/$1" "$CT/$2" "$3" "$4" <<'PY' || bad "변형 $2 못 만듦(대상이 1번 나오지 않음)"
import re, sys
src, dst, pat, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
out, n = re.subn(pat, lambda m: new, s, flags=re.M)
assert n == 1, n
open(dst, "w", encoding="utf-8").write(out)
PY
}
main_tree() {  # 기준판(MAINSHA) 사본 = 둘째 clone(r728 ⓓ 처럼 다른 시험을 부르는 대상도 기준판 그대로 돈다)
  M="$T/main"; MT="$M/$TREL"
  git clone -q --shared --no-checkout "$TOP" "$M" 2>/dev/null && git -C "$M" checkout -q --detach "$MAINSHA" 2>/dev/null \
    || { echo "판정 불가 — 기준판 사본($MAINSHA) 못 뜸"; exit 1; }
}
run() {  # <이름> <시험 파일> <켬 0/1> [깨진 bin 폴더] [tests 폴더 · 기본 사본] — 배경 실행 · 결과 = $T/<이름>.{log,rc,sec}
  local n="$1" f="$2" on="$3" brk="${4:-}" dir="${5:-$CT}"
  ( unset FT_TEST_BASELINE R1348_TEST_RUNNING R2286_BROKEN
    [ "$on" = 1 ] && export FT_TEST_BASELINE=1
    [ -n "$brk" ] && export R2286_BROKEN="$brk"
    s=$SECONDS; bash "$dir/$f" > "$T/$n.log" 2>&1; echo $? > "$T/$n.rc"; echo $((SECONDS - s)) > "$T/$n.sec" ) &
}
cnt() { grep -c -- "$2" "$T/$1.log" 2>/dev/null || true; }
rc() { cat "$T/$1.rc"; }
sec() { cat "$T/$1.sec"; }
in70() { [ "$(sec "$1")" -le 70 ] && ok "$2 $1 $(sec "$1")초(70초 안)" || bad "$2 $1 $(sec "$1")초 > 70초"; }
default_ok() { [ "$(rc "$1")" = 0 ] && [ "$(cnt "$1" '^SKIP 기준판 구간(')" = 1 ] && [ "$(cnt "$1" '^FAIL')" = 0 ]; }   # ① 꼴
baseline_ok() { [ "$(cnt "$1" '사본 못 뜸')" = 0 ]; }   # ② 꼴(rc 는 따지지 않음)
names() { sed -n 's/^PASS //p' "$T/$1.log" | sed 's/(.*//; s/ *$//' | sort -u; }   # PASS 이름 집합(괄호 뒤 값 뺌)
bl_cases() { sed -n 's/^BL_CASES="\([^"]*\)".*/\1/p' "$CT/$1" | tr '|' '\n'; }   # 대상 파일의 끈 사례 이름 목록
pass_with() {  # <이름> <접두 목록 파일> — 접두로 시작하는 PASS 이름 수
  local n=0 x p; while IFS= read -r x; do while IFS= read -r p; do [ -n "$p" ] && case "$x" in "$p"*) n=$((n + 1)); break;; esac; done < "$2"; done < <(names "$1"); echo "$n"
}
only_prefixed() {  # <이름 목록 파일> <접두 목록 파일> — 접두 밖 이름(없으면 빈 글)
  local x p hit; while IFS= read -r x; do hit=; while IFS= read -r p; do [ -n "$p" ] && case "$x" in "$p"*) hit=1; break;; esac; done < "$2"; [ -n "$hit" ] || printf '%s\n' "$x"; done < "$1"
}
set_check() {  # <표지> <새 판 실행> <기준판 실행> <대상 파일> <④ 새 PASS 접두…> — ① ⊇ · ⑥ diff 0
  local tag="$1" new="$2" old="$3" tf="$4"; shift 4
  bl_cases "$tf" > "$T/$tag.bl"; printf '%s\n' "$@" > "$T/$tag.add"
  comm -23 <(names "$old") <(names "$new") > "$T/$tag.gone"; comm -13 <(names "$old") <(names "$new") > "$T/$tag.new"
  local stray; stray="$(only_prefixed "$T/$tag.gone" "$T/$tag.bl")"
  [ -z "$stray" ] && ok "① $tag PASS 이름 ⊇ 기준판 PASS − 끈 이름(빠진 $(wc -l < "$T/$tag.gone" | tr -d ' ')개 = 모두 끈 목록)" \
    || bad "① $tag 끈 목록 밖 이름이 빠졌다 :: $(printf '%s' "$stray" | tr '\n' '/')"
  stray="$(only_prefixed "$T/$tag.new" "$T/$tag.add")"
  [ -z "$stray" ] && [ "$(wc -l < "$T/$tag.new" | tr -d ' ')" = "$#" ] \
    && ok "⑥ $tag PASS 이름 = 기준판 − 끈 이름 + ④ 이름 $# 개(diff 0)" \
    || bad "⑥ $tag 새 PASS 이름 :: $(tr '\n' '/' < "$T/$tag.new") (기대 ④ $#개: $*)"
}
