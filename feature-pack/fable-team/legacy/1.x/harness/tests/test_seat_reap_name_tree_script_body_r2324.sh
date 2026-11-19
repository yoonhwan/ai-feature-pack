#!/usr/bin/env bash
# test_seat_reap_name_tree_script_body_r2324.sh — r2324: 승계(retire) 때 옛 좌석 틱이 «bash <스크립트 파일>» 꼴로 떠서 argv 에 좌석 이름이 없어도, 그 작은 일반 파일 본문에 옛 좌석 이름이 정확 경계로 들어 있으면 ④ 이름 나무 씨앗으로 잡는다(실사건 desk219 꼴).
#   ① 실물 desk219 꼴(본문 6줄째 그대로 · 따옴표 포함) 래퍼(bash -c) → 틱(bash <파일>) → sleep 300 = 후보 3 via=④(기준판 = 0 → Red) · 실물 파일 복사본 1회 더
#   ② 본문이 새 좌석 이름만(#220) → 0 · 거름·skip 줄 0(불변)  ③ 따옴표 꼴 «'…#2190'»·앞 글자 붙음 → 0
#   ④ 64KiB 밖에 이름 → 0(읽기 상한)  ⑤ NUL 든 파일 → 0  ⑥ 심링크 · 디렉터리 → 0(lstat · 따라가기 0)
#   ⑦ r2317 argv 정확 낱말 씨앗 그대로 → 후보 4 via=④(회귀)  ⑧ 본문 씨앗 나무에도 r2317 거름 그대로(root-pane · root-protect)
#   ⑨ «bash -c …»(-c 있음)는 경로 아님 → 본문 씨앗 0  ⑩ 상대 경로 → 씨앗 0(cwd 풀기 0)
#   변이 M1~M5(사본에서 1곳만) — 변이마다 원본으로 같은 사례 1회 더 = 반대 결과 대조
#   입력 = 가짜 ps 표(FT_PS) · 가짜 tmux(PATH) · 가짜 lsof(FT_LSOF) · 가짜 launchctl(FT_LAUNCHCTL) · 신호 0 = --dry-run · 실 프로세스 0 · sleep 0
#   범위 밖: 다른 좌석이 nohup 으로 띄운 감시 스크립트 본문에 옛 이름이 있으면 씨앗이 된다(env 숨음·tty 0·pane 밖이면 S1 거름 다 통과) — 지금 실물 0 이라 범위 밖
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
BIN="${R2324_REAP_DIR:-$HERE/../bin}"; BIN="$(cd "$BIN" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/r2324.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
U="$(id -u)"; SEAT="byz-planner-desk-pi#219"; NEW="byz-planner-desk-pi#220"; LS="Fri Nov 20 01:13:31 2026"
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
[ -f "$LFAIL" ] && { echo "launchctl: Could not find service" >&2; exit 1; }
printf 'PID\tStatus\tLabel\n'
[ -s "$LPIDS" ] && while read -r p; do case "$p" in ''|-) ;; *) printf '%s\t0\tcom.byz.r2324fake%s\n' "$p" "$p";; esac; done < "$LPIDS"
exit 0
EOS
chmod +x "$TMP/fake/"*
export PATH="$TMP/fake:$PATH" FT_PS="$TMP/fake/ps" FT_LSOF="$TMP/fake/lsof" FT_LAUNCHCTL="$TMP/fake/launchctl"
export FPS="$TMP/ps.txt" FTAB="$TMP/tmux.txt" FLIS="$TMP/listen.txt" LPIDS="$TMP/launchd.txt" LFAIL="$TMP/launchd.fail"
export FT_REAP_NOSIGNAL=1 FT_REAP_TERM_WAIT=0 FT_REAP_DEFER_DIR="$TMP/defer" FT_PERMIT_DIR="$TMP/permit" FT_BG_FINITE_LEDGER="$TMP/bg.tsv"
export FT_PRESS_PS_SNAPSHOT="$TMP/press.txt" FT_PRESS_RUNNER_RE="r2324press"
unset TMUX_PANE FT_SEATS_JSON

: > "$TMP/ps.txt"; : > "$TMP/tmux.txt"; : > "$TMP/listen.txt"; : > "$TMP/launchd.txt"; : > "$TMP/press.txt"; rm -f "$LFAIL" "$TMP"/defer/* 2>/dev/null
row() { printf '%s %s %s %s %s %s\t%s\t%s\n' "$1" "$2" "$1" "${6:-$U}" "$LS" "$3" "${4:-}" "${5:-}" >> "$FPS"; }   # row pid ppid cmd [env좌석] [tty] [uid]
tbl_reset() { : > "$FPS"; : > "$FTAB"; : > "$FLIS"; : > "$LPIDS"; : > "$TMP/press.txt"; rm -f "$LFAIL" "$TMP"/defer/* 2>/dev/null; }
pane() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$TMP" "$TMP" >> "$FTAB"; }                        # pane 세션 pane_pid cwd 세션경로
reap() { ( cd "$TMP" && bash "$BIN/ft-seat-reap.sh" "$SEAT" "$@" 2>&1 ); }
n() { grep -c "$1" <<< "$2"; }
tail1() { tail -1 <<< "$1" | sed "s/^reap $SEAT //"; }
body() { cat > "$TMP/desk219-tick.sh"; }   # 실물 틱 파일 자리(본문만 갈아 끼운다)
body_real() {  # 실물 /tmp/desk219-tick.sh 6줄째 그대로(따옴표 포함) · ① 의 픽스처
  body <<'EOS'
#!/usr/bin/env bash
# desk219 5분 틱 — ft-desk-tick.sh 1회(planner 에 [완료] 3줄 = 심박) · 로그 /tmp/desk219/tick.log
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents || exit 2
while :; do
  sleep 300
  { date '+%F %T'; timeout 30 bash .fable-team/bin/ft-desk-tick.sh 'byz-planner-desk-pi#219' 2>&1 | tail -3; } >> /tmp/desk219/tick.log 2>&1
done
EOS
}
WRAP="/bin/bash -c sed 's/#218/#219/g' /tmp/desk218-tick.sh > /tmp/desk219-tick.sh && nohup bash /tmp/desk219-tick.sh &"

case1() {  # ① 실물 desk219 꼴 — 래퍼(bash -c) 4292400 · 틱 4292401 · sleep 300 4292402
  tbl_reset; body_real
  row 4292400 1 "$WRAP"
  row 4292401 4292400 "bash $TMP/desk219-tick.sh"
  row 4292402 4292401 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "① 본문 씨앗 나무 후보 3 via=④(--orphans-only · env·pane·cwd 안 보임)" "$(n '^reap-cand pid=429240[0-2] via=④ ' "$o")" 3
  chk "① 끝 줄 found=3" "$(tail1 "$o")" "found=3 dry-run rc=0"
  mkdir -p "$TMP/s/sub"; cp "$TMP/desk219-tick.sh" "$TMP/s/sub/copy-tick.sh"    # 실물 복사본 1회 더(경로·이름 달라도 같은 결론)
  tbl_reset
  row 4292410 1 "$WRAP"
  row 4292411 4292410 "bash $TMP/s/sub/copy-tick.sh"
  row 4292412 4292411 "sleep 300"
  o="$(reap --orphans-only --dry-run)"
  chk "① 실물 복사본(다른 경로) → 후보 3 via=④" "$(n '^reap-cand pid=429241[0-2] via=④ ' "$o")" 3
  if [ -r /tmp/desk219-tick.sh ]; then                      # 이 머신의 실물 파일이 있으면 그것도 1회
    cp /tmp/desk219-tick.sh "$TMP/real-copy.sh"; tbl_reset
    row 4292420 1 "$WRAP"
    row 4292421 4292420 "bash $TMP/real-copy.sh"
    row 4292422 4292421 "sleep 300"
    o="$(reap --orphans-only --dry-run)"
    chk "① /tmp/desk219-tick.sh 실물 복사본 → 후보 3 via=④" "$(n '^reap-cand pid=429242[0-2] via=④ ' "$o")" 3
  else ok "① 실물 파일 없음 — 복사본 2회로 대신"; fi
}
case2() {  # ② 본문이 새 좌석 이름만 → 0(불변: 거름 줄도 0)
  tbl_reset; body_real; sed -i '' "s/#219/#220/g" "$TMP/desk219-tick.sh" 2>/dev/null || sed -i "s/#219/#220/g" "$TMP/desk219-tick.sh"
  row 4292500 1 "$WRAP"
  row 4292501 4292500 "bash $TMP/desk219-tick.sh"
  row 4292502 4292501 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "② 본문 = 새 이름($NEW) → 후보 0 · skip 줄 0" "$(n '^reap-cand ' "$o") $(n '^reap-skip ' "$o") $(n "\\$NEW" "$o")" "0 0 0"
  chk "② 끝 줄 found=0" "$(tail1 "$o")" "found=0 dry-run rc=0"
}
case3() {  # ③ 따옴표 꼴 «'…#2190'» · 앞 글자 붙음 → 0
  tbl_reset; body <<'EOS'
#!/usr/bin/env bash
while :; do
  sleep 300
  { date '+%F %T'; timeout 30 bash .fable-team/bin/ft-desk-tick.sh 'byz-planner-desk-pi#2190' 2>&1 | tail -3; } >> /tmp/desk219/tick.log 2>&1
done
EOS
  row 4292600 1 "$WRAP"
  row 4292601 4292600 "bash $TMP/desk219-tick.sh"
  row 4292602 4292601 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "③ «'…#2190'» 부분 글자 → 후보 0" "$(n '^reap-cand ' "$o")" 0
  tbl_reset; body <<'EOS'
#!/usr/bin/env bash
while :; do
  sleep 300
  { date '+%F %T'; timeout 30 bash .fable-team/bin/ft-desk-tick.sh 'xbyz-planner-desk-pi#219' 2>&1 | tail -3; } >> /tmp/desk219/tick.log 2>&1
done
EOS
  row 4292610 1 "$WRAP"
  row 4292611 4292610 "bash $TMP/desk219-tick.sh"
  row 4292612 4292611 "sleep 300"
  o="$(reap --orphans-only --dry-run)"
  chk "③ 앞에 이름 글자 붙은 «x…#219» → 후보 0" "$(n '^reap-cand ' "$o")" 0
}
case4() {  # ④ 이름이 64KiB 밖 → 0(읽기 상한)
  tbl_reset; { head -c 70000 /dev/zero | tr '\0' 'a'; printf '\n# %s\n' "$SEAT"; } > "$TMP/desk219-tick.sh"
  row 4292700 1 "$WRAP"
  row 4292701 4292700 "bash $TMP/desk219-tick.sh"
  row 4292702 4292701 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "④ 이름이 64KiB 밖 → 후보 0" "$(n '^reap-cand ' "$o")" 0
  chk "④ 끝 줄 found=0(불변)" "$(tail1 "$o")" "found=0 dry-run rc=0"
}
case5() {  # ⑤ NUL 든 파일 → 0
  tbl_reset; printf '#!/usr/bin/env bash\nA=1\0B=2\n  timeout 30 bash .fable-team/bin/ft-desk-tick.sh %s\n' "$SEAT" > "$TMP/desk219-tick.sh"
  row 4292750 1 "$WRAP"
  row 4292751 4292750 "bash $TMP/desk219-tick.sh"
  row 4292752 4292751 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑤ NUL 파일 → 후보 0" "$(n '^reap-cand ' "$o")" 0
}
case6() {  # ⑥ 심링크 · 디렉터리 → 0(lstat)
  tbl_reset; mkdir -p "$TMP/s/real"; body_real; mv "$TMP/desk219-tick.sh" "$TMP/s/real/desk219-tick.sh"; ln -sfn "$TMP/s/real/desk219-tick.sh" "$TMP/link-tick.sh"
  row 4292800 1 "$WRAP"
  row 4292801 4292800 "bash $TMP/link-tick.sh"
  row 4292802 4292801 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑥ 심링크 → 후보 0" "$(n '^reap-cand ' "$o")" 0
  tbl_reset; mkdir -p "$TMP/dir-tick.sh"
  row 4292810 1 "$WRAP"
  row 4292811 4292810 "bash $TMP/dir-tick.sh"
  row 4292812 4292811 "sleep 300"
  o="$(reap --orphans-only --dry-run)"
  chk "⑥ 디렉터리 → 후보 0" "$(n '^reap-cand ' "$o")" 0
}
case7() {  # ⑦ r2317 argv 정확 낱말 씨앗 그대로 → 후보 4
  tbl_reset
  row 4292900 1 "/bin/bash -c while :; do sleep 5; done"
  row 4292901 4292900 "timeout 30 bash .fable-team/bin/ft-desk-tick.sh $SEAT"
  row 4292902 4292901 "bash .fable-team/bin/ft-mbox.sh ring $SEAT"
  row 4292903 4292900 "bash .fable-team/bin/ft-mbox.sh ring $SEAT"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑦ argv 씨앗 회귀 → 후보 4 via=④" "$(n '^reap-cand pid=429290[0-3] via=④ ' "$o")" 4
}
case8() {  # ⑧ 본문 씨앗 나무에도 r2317 거름 그대로 — root-pane · root-protect
  tbl_reset; body_real; pane "$NEW" 4293002
  row 4293000 1 "$WRAP"
  row 4293001 4293000 "bash $TMP/desk219-tick.sh"
  row 4293002 4293001 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑧ pane 자손 → 후보 0 · why=root-pane 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4293000 why=root-pane ' "$o")" "0 1"
  tbl_reset; body_real; echo 4293010 > "$LPIDS"
  row 4293010 1 "$WRAP"
  row 4293011 4293010 "bash $TMP/desk219-tick.sh"
  row 4293012 4293011 "sleep 300"
  o="$(reap --orphans-only --dry-run)"
  chk "⑧ launchd 뿌리 → 후보 0 · why=root-protect 1줄" "$(n '^reap-cand ' "$o") $(n '^reap-skip pid=4293010 why=root-protect ' "$o")" "0 1"
}
case9() {  # ⑨ «bash -c …»(-c 있음)는 경로 아님 → 본문 씨앗 0
  tbl_reset; body_real
  row 4293100 1 "/bin/bash -c cat $TMP/desk219-tick.sh | head -3"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑨ bash -c 뒤 경로 → 본문 씨앗 0" "$(n '^reap-cand ' "$o")" 0
}
case10() {  # ⑩ 상대 경로 → 씨앗 0(cwd 풀기 0)
  tbl_reset; body_real
  row 4293200 1 "$WRAP"
  row 4293201 4293200 "bash desk219-tick.sh"
  row 4293202 4293201 "sleep 300"
  local o; o="$(reap --orphans-only --dry-run)"
  chk "⑩ 상대 경로 → 후보 0" "$(n '^reap-cand ' "$o")" 0
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
  R2324_CASE="$2" R2324_REAP_DIR="$BIN" bash "$SELF" > "$out_b" 2>&1; local rb=$?
  if ! mutb "$1" "$3" "$4"; then bad "$1 사본 치환 실패"; return; fi
  R2324_CASE="$2" R2324_REAP_DIR="$TMP/mb/$1" bash "$SELF" > "$out_m" 2>&1; local rm=$?
  chk "$1 → 반례 $2 대조: 원본 PASS · 변이 FAIL" "$rb $rm" "0 1"
  [ "$rm" -eq 0 ] && grep '^FAIL' "$out_m" | head -2
}

if [ -n "${R2324_CASE:-}" ]; then
  case "$R2324_CASE" in
    1) case1;; 2) case2;; 3) case3;; 4) case4;; 5) case5;; 6) case6;; 7) case7;; 8) case8;; 9) case9;; 10) case10;;
    *) echo "FAIL 알 수 없는 사례 $R2324_CASE"; exit 1;;
  esac
  [ "$fail" -eq 0 ] && { echo "CASE $R2324_CASE PASS"; exit 0; }
  echo "CASE $R2324_CASE FAILED $fail"; exit 1
fi

T0=$SECONDS
bash -n "$BIN/ft-seat-reap.sh" && ok "bash -n ft-seat-reap.sh" || bad "bash -n ft-seat-reap.sh"
cmp -s "$BIN/ft-seat-reap.sh" "$BIN/../kit/fable-team/bin/ft-seat-reap.sh" && ok "짝 cmp0 ft-seat-reap.sh" || bad "짝 다름 ft-seat-reap.sh"
for c in 1 2 3 4 5 6 7 8 9 10; do
  echo "== ④b 사례 $c"
  R2324_CASE="$c" R2324_REAP_DIR="$BIN" bash "$SELF" 2>&1 | sed 's/^/  /'
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=$((fail + 1))
done
BASE="${R2324_BASE:-}"
if [ -z "$BASE" ]; then   # 못 받으면 «고치기 전 판»(r2321 착지 = 이 카드의 부모)을 git 에서 뜬다 — 고정 sha 라 언제 돌려도 Red
  BASE="$TMP/base-src.sh"
  git -C "$HERE" show 1876f3b7:feature-pack/fable-team/legacy/1.x/harness/bin/ft-seat-reap.sh > "$BASE" 2>/dev/null || rm -f "$BASE"
fi
echo "== 기준판(옛 ft-seat-reap.sh) Red — ① 이 0 이어야 한다"
if [ -s "$BASE" ]; then
  mkdir -p "$TMP/base"; for f in ft-leak-reap.sh ft-harness-root.sh ft-bg-finite.sh; do [ -f "$BIN/$f" ] && cp "$BIN/$f" "$TMP/base/$f"; done; cp "$BASE" "$TMP/base/ft-seat-reap.sh"
  R2324_CASE=1 R2324_REAP_DIR="$TMP/base" bash "$SELF" > "$TMP/base.out" 2>&1
  grep -q '^PASS ① 본문 씨앗 나무 후보 3' "$TMP/base.out" && bad "기준판이 ① 을 통과(Red 아님)" || ok "기준판 ① Red(후보 0) — $(grep -m1 '^FAIL' "$TMP/base.out" | cut -c1-70)"
else bad "기준판 없음 — R2324_BASE=<옛 bin/ft-seat-reap.sh> 로 다시"; fi
echo "== 변이 M1~M5(사본 · 원본 대조)"
mcheck M1 1 'return any(w.startswith("/") and body_seed(w) for w in words[1:])' 'return False'
mcheck M2 3 'r"(?:^|[^" + NAME_CH + r"])" + re.escape(seat) + r"(?:$|[^" + NAME_CH + r"])", re.M)' 're.escape(seat), re.M)'
mcheck M3 4 'SEED_BYTES = 65536' 'SEED_BYTES = 1 << 30'
mcheck M4 5 'b"\x00" not in data and bool(' 'bool('
mcheck M5 1 '_seed_re = re.compile(r"(?:^|[^" + NAME_CH + r"])" + re.escape(seat) + r"(?:$|[^" + NAME_CH + r"])", re.M)' '_seed_re = re.compile(r"(?:^|\s)" + re.escape(seat) + r"(?:$|\s)", re.M)'
Q=$((SECONDS - T0))
chk "시간 $Q 초 ≤ 70" "$([ "$Q" -le 70 ] && echo ok)" ok
echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS ($Q 초)"; exit 0; else echo "FAILED $fail"; exit 1; fi
