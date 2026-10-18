#!/usr/bin/env bash
# test_hil.sh — R83 ft-hil.sh(짧은 링크 /tmp/h<N> 등록기) + 출력처 ft-wt-sweep 안내 시험.
# 임시 HIL_DIR·임시 HOME·pbcopy 셸 스텁만 쓴다 — 실 /tmp·실 클립보드·실 계획 실행 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }

bash -n "$SRC/ft-hil.sh" && ok "bash -n ft-hil.sh" || bad "bash -n ft-hil.sh"
[ "$(wc -l < "$SRC/ft-hil.sh")" -le 200 ] && ok "ft-hil.sh 200줄 이하(R186: 표식·대체·미실행 3기능으로 100 → 200)" || bad "ft-hil.sh 200줄 초과"
cmp -s "$SRC/ft-hil.sh" "$HERE/../../scripts/fable-team-bin/ft-hil.sh" && ok "킷 두 벌 cmp 동일" || bad "킷 두 벌이 다르다"

mkdir -p "$T/fake" "$T/home" "$T/d"
printf '#!/usr/bin/env bash\ncat > "%s/clip.txt"\necho x >> "%s/clip.calls"\n' "$T" "$T" > "$T/fake/pbcopy"; chmod +x "$T/fake/pbcopy"
D="$T/d"
# hilx [env VAR=값 ...] <ft-hil.sh 인자...> — 임시 HOME·HIL_DIR·pbcopy 스텁 PATH
hilx() { local e=(); while [ "${1:-}" = env ]; do e+=("$2"); shift 2; done; env -i HOME="$T/home" PYTHONDONTWRITEBYTECODE=1 PATH="$T/fake:/usr/bin:/bin" HIL_DIR="$D" ${e[@]+"${e[@]}"} bash "$SRC/ft-hil.sh" "$@"; }

printf '#!/usr/bin/env bash\necho ran-A\nexit 0\n' > "$T/a.sh.hil"
printf '#!/usr/bin/env bash\necho ran-B\n' > "$T/b.sh.hil"

echo "== ① --add → ! bash <HIL_DIR>/h1 · 링크 1 · 클립보드"
out="$(hilx --add "$T/a.sh.hil")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "! bash $D/h1" ] && ok "--add 출력 = ! bash <HIL_DIR>/h1" || bad "--add rc=$rc out=$out"
[ -f "$D/h1" ] && [ ! -L "$D/h1" ] && [ "$(sed -n 's/^# ft-hil-entry plan=//p' "$D/h1")" = "$T/a.sh.hil" ] && ok "  └ h1 진입 파일 → 계획 절대경로(R186: 링크 아님)" || bad "h1 진입 파일 없음/불일치"
[ "$(ls "$D" | grep -c '^h[0-9]')" = 1 ] && ok "  └ h 파일 1개" || bad "h 파일 개수"
[ "$(cat "$T/clip.txt" 2>/dev/null)" = "bash $D/h1" ] && ok "  └ 클립보드 스텁 입력 = bash <HIL_DIR>/h1" || bad "클립보드: $(cat "$T/clip.txt" 2>/dev/null)"

echo "== ② 같은 계획 재등록 = h1 재사용"
out="$(hilx --add "$T/a.sh.hil")"
[ "$out" = "! bash $D/h1" ] && [ "$(ls "$D" | grep -c '^h[0-9]')" = 1 ] && ok "재등록 = h1 · 링크 늘지 않음" || bad "재등록 out=$out"

echo "== ③ 미리 있는 h2 파일(손 선례) + 새 등록 = h3 (덮기 0)"
echo hand > "$D/h2"
out="$(hilx --add "$T/b.sh.hil")"
[ "$out" = "! bash $D/h3" ] && ok "새 등록 = h3" || bad "새 등록 out=$out"
[ "$(cat "$D/h2")" = hand ] && ok "  └ 손 h2 파일 그대로" || bad "h2 가 덮임"
ln -s "$T/none-a.sh.hil" "$D/h9"
out="$(hilx --add "$T/a.sh.hil")"; [ "$out" = "! bash $D/h1" ] && ok "  └ 깨진 링크 h9 가 있어도 기존 대상은 h1 재사용" || bad "재사용 out=$out"
printf '#!/usr/bin/env bash\necho ran-C\n' > "$T/c.sh.hil"
out="$(hilx --add "$T/c.sh.hil")"; [ "$out" = "! bash $D/h10" ] && ok "  └ 최대값(깨진 링크 h9 포함)+1 = h10" || bad "최대값+1 out=$out"

echo "== ④ 없는 파일 = REJECT · 링크 0"
before="$(ls "$D" | grep -c '^h[0-9]')"
out="$(hilx --add "$T/nope.sh.hil" 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT" "없는 파일 → REJECT(rc=1)" || bad "없는 파일 rc=$rc"
[ "$(ls "$D" | grep -c '^h[0-9]')" = "$before" ] && ok "  └ 링크 늘지 않음" || bad "REJECT 인데 링크 생김"

echo "== ④b 판정기가 죽음(rc1 · reject 글 없음) = ERROR 판정기 실행 실패 · 등록 0 (R170)"
printf 'raise TypeError("broken judge")\n' > "$T/broken_judge.py"
out="$(hilx env FT_SECRET_JUDGE="$T/broken_judge.py" --add "$T/a.sh.hil" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -ne 0 ] && has "$out" "ERROR ft-hil 판정기 실행 실패(rc=1)" "판정기 죽음 → 보이는 ERROR · rc≠0" || bad "판정기 죽음 rc=$rc out=$out"
case "$out" in *"REJECT 계획 파일 비밀 출력 경로 — "*) bad "빈 사유 REJECT 로 보임: $out";; *) ok "  └ 빈 사유 REJECT 아님";; esac
[ "$(ls "$D" | grep -c '^h[0-9]')" = "$before" ] && ok "  └ 링크 늘지 않음" || bad "판정기 죽음인데 링크 생김"

echo "== ⑤ --cmd 'echo hi' → 링크 대상 실행 시 hi"
out="$(hilx --cmd 'echo hi')"; n="${out##*/h}"
[ "$out" = "! bash $D/h$n" ] && [ "$(bash "$D/h$n")" = "hi" ] && ok "--cmd 등록 → bash <링크> 출력 hi" || bad "--cmd out=$out"

echo "== ⑥ HIL_CLIP=0 = pbcopy 호출 0"
calls="$(wc -l < "$T/clip.calls" | tr -d ' ')"
printf '#!/usr/bin/env bash\ntrue\n' > "$T/d.sh.hil"
hilx env HIL_CLIP=0 --add "$T/d.sh.hil" >/dev/null
[ "$(wc -l < "$T/clip.calls" | tr -d ' ')" = "$calls" ] && ok "HIL_CLIP=0 → pbcopy 0회" || bad "pbcopy 호출됨"

echo "== ⑦ 목록 — 사라진 대상 표시"
out="$(hilx)"
has "$out" "h1  $T/a.sh.hil  실재" "목록: 실재 대상"
has "$out" "h9  $T/none-a.sh.hil  없음" "  └ 사라진 대상 = 없음"
has "$out" "h2  (링크 아님)" "  └ 손 파일 h2 = 링크 아님"

echo "== ⑧ \$HOME 아래 새 파일 0 · 기본 등록부 = /tmp"
[ -z "$(find "$T/home" -mindepth 1 2>/dev/null)" ] && ok "임시 HOME 아래 새 파일 0" || bad "HOME 아래 생성: $(find "$T/home" -mindepth 1)"
grep -q 'HIL_DIR:-/tmp}' "$SRC/ft-hil.sh" && ok "  └ 기본 HIL_DIR = /tmp" || bad "기본 등록부가 /tmp 아님"
grep -v '^#' "$SRC/ft-hil.sh" | grep -qE '[$]HOME|~/' && bad "ft-hil.sh 가 HOME 을 참조한다" || ok "  └ ft-hil.sh 는 \$HOME 을 참조하지 않는다"

echo "== ⑨ 실 /tmp 기준 출력 줄 길이 ≤ 18자"
out="$(hilx env HIL_CLIP=0 --add "$T/d.sh.hil" | sed "s|$D|/tmp|")"
[ "${#out}" -le 18 ] && ok "출력 줄 [${out}] ${#out}chars" || bad "출력 줄이 길다: ${out}"

echo "== 금지: 실행 기능 0 — 번호 인자는 usage exit 2"
hilx h1 >/dev/null 2>&1; rc=$?; [ "$rc" -eq 2 ] && ok "번호 실행 인자 = usage exit 2(실행 기능 없음)" || bad "rc=$rc"

echo "== 출력처 ft-wt-sweep: skipped 계획 → .sh.hil + 안내 ! bash <링크>"
W="$T/wtclean"; mkdir -p "$W" "$T/sw"
cp "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$T/sw/"
printf '#!/usr/bin/env bash\necho "skipped:실작업물 있음"\n' > "$W/seatX.sh"
sw() { ( cd "$T" && env -i HOME="$T/home" PYTHONDONTWRITEBYTECODE=1 PATH="/usr/bin:/bin" FT_WT_CLEAN_DIR="$W" HIL_CLIP=0 "$@" bash "$T/sw/ft-wt-sweep.sh" 2>&1 ); }
out="$(sw HIL_DIR="$T/sd")"
has "$out" "[HIL] seat=seatX 실작업물 있음 · ! bash $T/sd/h1" "ft-hil.sh 있음 → [HIL] … · ! bash <링크>"
[ "$(sed -n 's/^# ft-hil-entry plan=//p' "$T/sd/h1")" = "$W/seatX.sh.hil" ] && ok "  └ 진입 파일 대상 = 옮겨진 .sh.hil" || bad "진입 파일 대상 불일치"
mv "$W/seatX.sh.hil" "$W/seatX.sh"; : > "$T/notdir"
out="$(sw HIL_DIR="$T/notdir")"
has "$out" "스크립트 $W/seatX.sh.hil" "ft-hil.sh 실패 → 지금 문구 그대로"; has "$out" "WARN ft-hil 실패" "  └ WARN ft-hil 실패"
[ -z "$(find "$T/home" -mindepth 1 2>/dev/null)" ] && ok "  └ 임시 HOME 아래 새 파일 0" || bad "HOME 아래 생성"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
