#!/usr/bin/env bash
# test_seat_reap_script_seed_shell_argv_r2327.sh — r2327: ④b 스크립트 본문 씨앗은 «bash|sh|zsh [옵션…] <절대 경로>» 꼴의 «첫 경로 낱말 1개» 만 읽는다. 그래서 «tail -F <우편함 파일>» 처럼 데이터 파일을 연 고아는 본문 씨앗이 되지 않는다(r2324 판은 절대 경로 낱말을 모두 읽었다).
#   ① 고아 «tail -F <tmp>/mailbox.jsonl»(본문에 옛 이름) → 0 · 기준판 = found=1(Red)
#   ② desk219 꼴 «bash <tmp>/desk219-tick.sh» → 후보 3 via=④(④b 불변)
#   ③ «/bin/zsh -x <tmp>/tick.sh»(옵션 낱말 뒤 첫 낱말) → 후보 3 via=④
#   ④ «bash <tmp>/tick.sh <tmp>/data.txt»(둘째 낱말만 본문에 이름) → 0
#   ⑤ «python3 <tmp>/tick.py»(본문에 이름) → 0(명령 이름 거름)
#   ⑥ 회귀 = test_seat_reap_name_tree_script_body_r2324.sh · test_seat_reap_name_tree_r2317.sh · test_seat_reap_keep_hil_r2160.sh · test_seat_reap_services.sh → 기준판과 실패 이름 diff 0
#   ⑦ «bash -lc <tmp>/tick.sh»(묶음 -lc) → 0(-c 와 같다 · DA#39 조건1)
#   변이 M1~M3(사본에서 1곳만) — 변이마다 원본으로 같은 사례 1회 더 = 반대 결과 대조
#   입력 = 가짜 ps 표(FT_PS) · 가짜 tmux(PATH) · 가짜 lsof(FT_LSOF) · 가짜 launchctl(FT_LAUNCHCTL) · 신호 0 = --dry-run · 실 프로세스 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
BIN="${R2327_REAP_DIR:-$HERE/../bin}"; BIN="$(cd "$BIN" && pwd)"
BASE_SHA="1054c36e"   # r2324 착지 판(팩 main · 이 카드의 부모) — 고정 sha 라 언제 돌려도 같은 Red
TMP="$(mktemp -d "${TMPDIR:-/tmp}/r2327.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
U="$(id -u)"; SEAT="byz-planner-desk-pi#219"; LS="Fri Nov 20 01:13:31 2026"
mkdir -p "$TMP/fake" "$TMP/defer" "$TMP/permit" "$TMP/s"
cat > "$TMP/fake/ps" <<'EOS'
#!/bin/bash
case " $* " in
  *" -axEww "*) awk -F'\t' '{n = split($1, a, " "); c = ""; for (i = 10; i <= n; i++) c = c (i > 10 ? " " : "") a[i]; printf "%s %s%s\n", a[1], c, ($2 == "" ? "" : " FT_SEAT=" $2)}' "$FPS";;
  *"pid=,tty="*) awk -F'\t' '{split($1, a, " "); printf "%s %s\n", a[1], ($3 == "" ? "??" : $3)}' "$FPS";;
  *) awk -F'\t' '{print $1}' "$FPS";;
esac
EOS
cat > "$TMP/fake/tmux" <<'EOS'
#!/bin/bash
[ "$1" = list-panes ] || exit 0
[ -s "$FTAB" ] && cat "$FTAB" || { echo "no server running on /tmp/tmux-501/none" >&2; exit 1; }
EOS
cat > "$TMP/fake/lsof" <<'EOS'
#!/bin/bash
case " $* " in
  *" -sTCP:LISTEN "*) [ -s "$FLIS" ] && { while read -r p; do [ -n "$p" ] && echo "p$p"; done < "$FLIS"; }; exit 0;;
  *) exit 1;;
esac
EOS
cat > "$TMP/fake/launchctl" <<'EOS'
#!/bin/bash
printf 'PID\tStatus\tLabel\n'
[ -s "$LPIDS" ] && while read -r p; do case "$p" in ''|-) ;; *) printf '%s\t0\tcom.byz.r2327fake%s\n' "$p" "$p";; esac; done < "$LPIDS"
exit 0
EOS
chmod +x "$TMP/fake/"*
ORIG_PATH="$PATH"   # ⑥ 회귀 = 아이 시험은 이 시험의 가짜 도구·env 를 물려받지 않는다
export PATH="$TMP/fake:$PATH" FT_PS="$TMP/fake/ps" FT_LSOF="$TMP/fake/lsof" FT_LAUNCHCTL="$TMP/fake/launchctl"
export FPS="$TMP/ps.txt" FTAB="$TMP/tmux.txt" FLIS="$TMP/listen.txt" LPIDS="$TMP/launchd.txt"
export FT_REAP_NOSIGNAL=1 FT_REAP_TERM_WAIT=0 FT_REAP_DEFER_DIR="$TMP/defer" FT_PERMIT_DIR="$TMP/permit" FT_BG_FINITE_LEDGER="$TMP/bg.tsv"
export FT_PRESS_PS_SNAPSHOT="$TMP/press.txt" FT_PRESS_RUNNER_RE="r2327press"
unset TMUX_PANE FT_SEATS_JSON

: > "$FPS"; : > "$FTAB"; : > "$FLIS"; : > "$LPIDS"; : > "$TMP/press.txt"
row() { printf '%s %s %s %s %s %s\t%s\t%s\n' "$1" "$2" "$1" "${6:-$U}" "$LS" "$3" "${4:-}" "${5:-}" >> "$FPS"; }   # row pid ppid cmd [env좌석] [tty] [uid]
tbl_reset() { : > "$FPS"; : > "$FTAB"; : > "$FLIS"; : > "$LPIDS"; : > "$TMP/press.txt"; rm -f "$TMP"/defer/* 2>/dev/null; }
reap() { ( cd "$TMP" && bash "$BIN/ft-seat-reap.sh" "$SEAT" "$@" 2>&1 ); }
n() { grep -c "$1" <<< "$2"; }
tail1() { tail -1 <<< "$1" | sed "s/^reap $SEAT //"; }
tick() {   # tick <본문에 넣을 이름> — 틱 스크립트 일반 파일(실물 6줄째 꼴)
  cat > "$TMP/tick.sh" <<EOS
#!/usr/bin/env bash
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents || exit 2
while :; do
  sleep 300
  { timeout 30 bash .fable-team/bin/ft-desk-tick.sh '$1'; } >> /tmp/r2327/tick.log 2>&1
done
EOS
}
WRAP="/bin/bash -c sed 's/#218/#219/g' /tmp/desk218-tick.sh > /tmp/desk219-tick.sh && nohup bash /tmp/desk219-tick.sh &"

case1() {  # ① 고아 «tail -F <우편함 파일>» — 본문에 옛 이름이 있어도 셸 명령이 아니다 → 0(기준판 = found=1)
  tbl_reset; printf '{"to":"%s"}\n{"to":"byz-harness-nano#0"}\n' "$SEAT" > "$TMP/mailbox.jsonl"
  row 4294000 1 "tail -F $TMP/mailbox.jsonl"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "① «tail -F <우편함>» → 후보 0 · skip 줄 0" "$(n '^reap-cand ' "$o") $(n '^reap-skip ' "$o")" "0 0"
  chk "① 끝 줄 found=0" "$(tail1 "$o")" "found=0 dry-run rc=0"
}
case2() {  # ② desk219 꼴 «bash <틱 파일>» → 후보 3 via=④(④b 불변)
  tbl_reset; tick "$SEAT"
  row 4294100 1 "$WRAP"
  row 4294101 4294100 "bash $TMP/tick.sh"
  row 4294102 4294101 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "② «bash <틱 파일>» → 후보 3 via=④" "$(n '^reap-cand pid=429410[0-2] via=④ ' "$o")" 3
  chk "② 끝 줄 found=3" "$(tail1 "$o")" "found=3 dry-run rc=0"
}
case3() {  # ③ «/bin/zsh -x <틱 파일>» — 옵션 낱말을 건너뛴 첫 낱말 = 경로
  tbl_reset; tick "$SEAT"
  row 4294200 1 "$WRAP"
  row 4294201 4294200 "/bin/zsh -x $TMP/tick.sh"
  row 4294202 4294201 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "③ «/bin/zsh -x <틱 파일>» → 후보 3 via=④" "$(n '^reap-cand pid=429420[0-2] via=④ ' "$o")" 3
}
case4() {  # ④ 둘째 경로 낱말만 본문에 이름 → 0(첫 경로 낱말 1개만 본다)
  tbl_reset; tick "byz-planner-desk-pi#220"; printf '# %s\n' "$SEAT" > "$TMP/data.txt"
  row 4294300 1 "$WRAP"
  row 4294301 4294300 "bash $TMP/tick.sh $TMP/data.txt"
  row 4294302 4294301 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "④ 둘째 낱말만 이름 → 후보 0" "$(n '^reap-cand ' "$o")" 0
  chk "④ 끝 줄 found=0(불변)" "$(tail1 "$o")" "found=0 dry-run rc=0"
}
case5() {  # ⑤ «python3 <파일>» — 명령 이름이 bash·sh·zsh 아님 → 0
  tbl_reset; printf 'seat = "%s"\n' "$SEAT" > "$TMP/tick.py"
  row 4294400 1 "/usr/bin/python3 $TMP/tick.py"
  row 4294401 4294400 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑤ «python3 <파일>» → 후보 0" "$(n '^reap-cand ' "$o")" 0
}
case7() {  # ⑦ «bash -lc <틱 파일>» — c 든 짧은 옵션 묶음 = 명령 문자열 → 0
  tbl_reset; tick "$SEAT"
  row 4294700 1 "$WRAP"
  row 4294701 4294700 "bash -lc $TMP/tick.sh"
  row 4294702 4294701 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑦ «bash -lc <틱 파일>» → 후보 0" "$(n '^reap-cand ' "$o")" 0
  chk "⑦ 끝 줄 found=0(불변)" "$(tail1 "$o")" "found=0 dry-run rc=0"
}
REGS="test_seat_reap_name_tree_script_body_r2324.sh test_seat_reap_name_tree_r2317.sh test_seat_reap_keep_hil_r2160.sh test_seat_reap_services.sh"
regbin() {  # regbin <테스트> <bin dir> — 그 시험을 그 bin 으로 1회(각 시험의 bin 재정의 env 를 쓴다)
  case "$1" in
    *r2324*) R2324_REAP_DIR="$2" bash "$1";;
    *r2317*) R2317_REAP_DIR="$2" bash "$1";;   # R2317_BASE 는 두 판 모두 안 준다 — 같은 «기준판 없음» 줄이 양쪽에 남아 diff 0
    *r2160*) R2160_BIN="$2" bash "$1";;
    *) bash "$1";;   # services = 시험 안에서 tests/../../harness/bin 고정
  esac
}
fails() { grep '^FAIL ' "$1" | sed 's/ (got=.*//' | sort; }
case6() {  # ⑥ 회귀 — 네 시험을 새 판으로 1회씩 · 실패 이름 집합이 기준판(1054c36e) 실행 때와 같아야 한다(손으로 뜬 기준판 = r2324 0 · r2317 «기준판 없음» 1 · keep_hil 0 · services 0)
  local t i=0 want got
  for t in $REGS; do
    i=$((i+1))
    ( cd "$HERE"
      unset FT_PS FT_LSOF FT_LAUNCHCTL FPS FTAB FLIS LPIDS FT_REAP_NOSIGNAL FT_REAP_TERM_WAIT FT_REAP_DEFER_DIR FT_PERMIT_DIR FT_BG_FINITE_LEDGER FT_PRESS_PS_SNAPSHOT FT_PRESS_RUNNER_RE
      PATH="$ORIG_PATH"; export PATH
      regbin "$t" "$BIN"
    ) > "$TMP/rg-$i.out" 2>&1
    case "$t" in
      *r2317*) want="FAIL 기준판 없음 — R2317_BASE=<옛 bin/ft-seat-reap.sh> 로 다시";;   # R2317_BASE 를 두 판 다 안 줘서 남는 같은 환경 줄
      *) want="";;
    esac
    got="$(fails "$TMP/rg-$i.out" | paste -sd '\t' -)"
    chk "⑥ $t 실패 이름 = 기준판과 같음" "${got:-없음}" "${want:-없음}"
  done
}
mutb() {  # mutb <이름> <옛 글자> <새 글자> — bin 통째 사본 + ft-seat-reap.sh 1곳만 치환
  local d="$TMP/mb/$1"; mkdir -p "$d"; for f in ft-seat-reap.sh ft-leak-reap.sh ft-harness-root.sh ft-bg-finite.sh; do [ -f "$BIN/$f" ] && cp "$BIN/$f" "$d/$f"; done
  python3 - "$d/ft-seat-reap.sh" "$2" "$3" <<'PY'
import sys
p, o, nw = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mutb: «{o[:60]}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, nw))
PY
}
mcheck() {  # mcheck <변이> <반례번호> <옛> <새> — 원본 PASS · 변이 FAIL 이면 ok
  local out_b="$TMP/x-base-$2.out" out_m="$TMP/x-m$1-$2.out"
  R2327_CASE="$2" R2327_REAP_DIR="$BIN" bash "$SELF" > "$out_b" 2>&1; local rb=$?
  if ! mutb "$1" "$3" "$4"; then bad "$1 사본 치환 실패"; return; fi
  R2327_CASE="$2" R2327_REAP_DIR="$TMP/mb/$1" bash "$SELF" > "$out_m" 2>&1; local rm=$?
  chk "$1 → 반례 $2 대조: 원본 PASS · 변이 FAIL" "$rb $rm" "0 1"
  [ "$rm" -eq 0 ] && grep '^FAIL' "$out_m" | head -2
}

if [ -n "${R2327_CASE:-}" ]; then
  case "$R2327_CASE" in
    1) case1;; 2) case2;; 3) case3;; 4) case4;; 5) case5;; 7) case7;;
    *) echo "FAIL 알 수 없는 사례 $R2327_CASE"; exit 1;;
  esac
  [ "$fail" -eq 0 ] && { echo "CASE $R2327_CASE PASS"; exit 0; }
  echo "CASE $R2327_CASE FAILED $fail"; exit 1
fi

T0=$SECONDS
bash -n "$BIN/ft-seat-reap.sh" && ok "bash -n ft-seat-reap.sh" || bad "bash -n ft-seat-reap.sh"
cmp -s "$BIN/ft-seat-reap.sh" "$BIN/../kit/fable-team/bin/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"
for c in 1 2 3 4 5 7; do
  echo "== ④b 사례 $c"
  R2327_CASE="$c" R2327_REAP_DIR="$BIN" bash "$SELF" 2>&1 | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=$((fail + 1))
done
echo "== 기준판($BASE_SHA) Red — ① 이 found=1 이어야 한다"
mkdir -p "$TMP/base"; for f in ft-leak-reap.sh ft-harness-root.sh ft-bg-finite.sh; do [ -f "$BIN/$f" ] && cp "$BIN/$f" "$TMP/base/$f"; done
git -C "$HERE" show "$BASE_SHA:feature-pack/fable-team/legacy/1.x/harness/bin/ft-seat-reap.sh" > "$TMP/base/ft-seat-reap.sh" 2>/dev/null
if [ -s "$TMP/base/ft-seat-reap.sh" ]; then
  R2327_CASE=1 R2327_REAP_DIR="$TMP/base" bash "$SELF" > "$TMP/base.out" 2>&1
  grep -q 'PASS ① «tail -F <우편함>» → 후보 0' "$TMP/base.out" && bad "기준판이 ① 을 통과(Red 아님)" || ok "기준판 ① Red — $(grep -m1 '^FAIL' "$TMP/base.out" | cut -c1-64)"
else bad "기준판 없음 — BASE_SHA $BASE_SHA 못 뜸"; fi
echo "== 변이 M1~M3(사본 · 원본 대조)"
mcheck M1 1 'if not words or os.path.basename(words[0]) not in SHELL_ARGV: return False' 'if not words: return False'
mcheck M2 4 'if not w.startswith("-"): return w.startswith("/") and body_seed(w)' 'if not w.startswith("-") and w.startswith("/") and body_seed(w): return True'
mcheck M3 7 'if len(w) > 1 and w[1:].isalpha() and "c" in w[1:]: return False' 'if w == "-c": return False'
echo "== ⑥ 회귀(네 시험 · 새 판/기준판)"
case6
Q=$((SECONDS - T0))
chk "시간 $Q 초 ≤ 70" "$([ "$Q" -le 70 ] && echo ok)" ok
echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS ($Q 초)"; exit 0; else echo "FAILED $fail"; exit 1; fi
