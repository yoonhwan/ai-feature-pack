#!/usr/bin/env bash
# test_goal_table_notify_budget_r2285.sh — 골 번호 공지가 표 출력 앞에서 합계 상한 없이 돌고 «전부 성공해야 표식 전진» 이라
#   바깥 25초 timeout 에 끊기면 표도 안 나오고(stdout 0) 다음 렌더가 같은 공지를 처음부터 다시 보내던 것(r2285).
#   ① 번호표 바뀜 · 가짜 mbox 1통 5초 · 팀장 12명 → 표 블록이 stdout 첫 줄(공지 전에 이미 flush) · rc0 · 12초 안 · WARN «공지 남음»
#   ①ⓑ 번호표 바뀜 · 가짜 mbox 5초 · 같은 프로세스 gt.render() 1회 → ≤1초 · mbox 0 · 표식 그대로(뉴스 경로 공지 0)
#   ②ⓑ ① 과 다음 렌더 사이 main 커밋 1(번호표 같음 · sha10 다름) → 받은 팀장 다시 0 · 남은 팀장만
#   ② ① 뒤 다시 렌더 → 앞 렌더가 보낸 팀장에게 다시 0 · 남은 팀장만 · 모두 받으면 표식 첫 줄 = 새 sig
#   ③ 팀장 1명만 rc1 → 그 1명만 남음(표식 전진 0) · 다음 렌더에 그 1명만 다시 · 나머지 중복 0
#   ⑤ 번호표 그대로 → 공지 0 · 표식 그대로 · 3초 안
#   ④ 잠금이 이미 잡혀 있음 → 공지 0 · INFO 1줄 · rc0 · 기다림 0
#   ⑥ 시안 렌더(FT_GOAL_A6_MD = 파일) → 공지 · 표식 0 · INFO 그대로
# 픽스처 = mktemp 임시 git 리포·임시 루트·가짜 mbox·가짜 명부 — 실 리포·실 좌석·외부 호출 0.
# env: GT_TOOL = 다른 판 ft_goal_table.py(기준판·변이) · CASES = 돌릴 사례 번호(기본 123546 · 1 = ①ⓑ+① · 2 = ②ⓑ+② · ② 는 ① 뒤)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
TOOL="${GT_TOOL:-$REPO/harness/bin/ft_goal_table.py}"; CASES="${CASES:-123546}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
on() { case "$CASES" in *"$1"*) return 0;; *) return 1;; esac; }
CPATH=design/planner/AUTONOMY-GOAL-A6-20261021.md; LPATH=design/planner/PLAN-oppa-ledger.md
R="$T/repo"; MARK="$R/.fable-team/state/goal-numbering.tsv"
mkdir -p "$R/design/planner" "$R/.fable-team/comm" "$T/mbox"; git -C "$R" init -q -b main
canon_of() {  # <골 이름...>
  printf '# 자율 골 A6 (시험 픽스처)\n\n## 골 → 팀 → 닫는 증거\n\n| 골(원문) | 담당 팀 | 닫는 증거 |\n|---|---|---|\n'
  local g; for g in "$@"; do printf '| %s | 팀 | 착지 sha |\n' "$g"; done
}
ledger() {  # <행 수>
  printf '# 원장\n\n> 마지막 갱신: %s · planner#1\n\n## 메인 골 — 지금 상태\n\n| 골(오빠 원문) | 지금 상태 | 닫히는 조건 |\n|---|---|---|\n' "$(date '+%Y-%m-%d %H:%M')"
  local i; for i in $(seq 1 "$1"); do printf '| 원장 %s | 상태 %s | 남은 %s |\n' "$i" "$i" "$i"; done
}
commit() { git -C "$R" add -A && git -C "$R" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" && git -C "$R" update-ref refs/remotes/origin/main HEAD; }
put() { local n=$#; canon_of "$@" > "$R/$CPATH"; ledger "$n" > "$R/$LPATH"; commit "$1"; }
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do printf '{"_master":"m%s#%s"}\n' "$i" "$i" > "$R/.fable-team/seats-$i.json"; done
# 가짜 mbox — 받는 이 1줄 기록(+ 그 순간 stdout 파일에 표가 이미 있나) · MBOX_FAIL 이름이면 rc1 · MBOX_SLEEP 초만큼 걸림
cat > "$T/mbox/mbox.sh" <<'SH'
#!/usr/bin/env bash
to="$2"; seen=0
[ -n "${OUTFILE:-}" ] && grep -q '^★골 표 A6' "$OUTFILE" 2>/dev/null && seen=1
case ",${MBOX_FAIL:-}," in *",$to,"*) echo "가짜 실패 $to" >&2; exit 1;; esac
printf '%s seen=%s\n' "$to" "$seen" >> "$MBOX_LOG"
[ -n "${MBOX_SLEEP:-}" ] && sleep "$MBOX_SLEEP"
exit 0
SH
chmod +x "$T/mbox/mbox.sh"
export MBOX_LOG="$T/mbox.log"; : > "$MBOX_LOG"
genv() { env -u FT_GOAL_MAX -u FT_TEAMS_REF -u FT_TEAMS_REF_PINNED_FROM -u FT_GOAL_REF_PIN -u FT_GOAL_A6_MD FT_ROOT="$R" FT_MBOX="$T/mbox/mbox.sh" \
  FT_GOAL_A6_MD="${MD:-gitref:origin/main:$CPATH}" FT_GOAL_A6_LEDGER="gitref:origin/main:$LPATH" FT_GOAL_REPO="$R" FT_LEDGER_REPO="$R" "$@"; }
render() {  # <stdout 파일> <stderr 파일> [env…] — 바깥 timeout 15(기준판 25초+ 가 이 시험을 넘기지 않게) · rc → RC · 걸린 초 → EL
  local o="$1" e="$2"; shift 2; local s=$SECONDS
  genv OUTFILE="$o" "$@" timeout 15 python3 "$TOOL" > "$o" 2> "$e"; RC=$?; EL=$((SECONDS - s))
}
names() { cut -d' ' -f1 "$MBOX_LOG" | sort; }
first() { head -1 "$MARK" 2>/dev/null; }
head10() { git -C "$R" rev-parse origin/main | cut -c1-10; }

# 기준선 — 6행(표식 없음 + 옛 고정 6 = 공지 0 · 표식만)
put a1 a2 a3 a4 a5 a6; render "$T/o0" "$T/e0"
[ "$RC" = 0 ] && [ ! -s "$MBOX_LOG" ] && [ "$(first | cut -f1)" = "$(head10)" ] && ok "기준선 6행 = 공지 0 · 표식 첫 줄" || bad "기준선 rc=$RC :: $(cat "$MBOX_LOG" "$T/e0")"
OLD="$(first)"

if on 1; then
  put b1 b2 b3 b4 b5; : > "$MBOX_LOG"; cp "$MARK" "$T/mark1b"
  OUT="$(genv MBOX_SLEEP=5 timeout 3 python3 - "$(dirname "$TOOL")" <<'PY' 2>&1
import sys, time
sys.path.insert(0, sys.argv[1])
import ft_goal_table as gt
t = time.monotonic(); text = gt.render(); el = time.monotonic() - t
print("EL %.2f HEAD %s" % (el, text.startswith("★골 표 A6 (")))
PY
)"
  EL1="$(printf '%s' "$OUT" | sed -n 's/^EL \([0-9.]*\) HEAD True$/\1/p')"
  [ -n "$EL1" ] && python3 -c "import sys; sys.exit(0 if float('$EL1') <= 1 else 1)" && [ ! -s "$MBOX_LOG" ] && cmp -s "$MARK" "$T/mark1b" \
    && ok "①ⓑ 같은 프로세스 gt.render() = ${EL1}s · mbox 0 · 표식 그대로" || bad "①ⓑ :: $(cat "$MBOX_LOG") :: ${OUT:0:300}"
  render "$T/o1" "$T/e1" MBOX_SLEEP=5
  N1="$(wc -l < "$MBOX_LOG" | tr -d ' ')"
  [ "$RC" = 0 ] && [ "$EL" -lt 12 ] && ok "① rc0 · 12초 안(${EL}s)" || bad "① rc=$RC ${EL}s :: $(head -c 300 "$T/e1")"
  case "$(head -1 "$T/o1")" in "★골 표 A6 ("*) ok "① 표 블록 = stdout 첫 줄";; *) bad "① stdout 첫 줄 :: $(head -c 120 "$T/o1")";; esac
  [ "$N1" -ge 1 ] && ! grep -q 'seen=0' "$MBOX_LOG" && ok "① 공지 ${N1}통 = 모두 표 출력 뒤" || bad "① 공지 순서 :: $(cat "$MBOX_LOG")"
  grep -q "WARN 골 번호 공지 남음 $((12 - N1))" "$T/e1" && [ "$(first)" = "$OLD" ] \
    && ok "① 상한 멈춤 = WARN «공지 남음 $((12 - N1))» · 표식 첫 줄 그대로" || bad "① WARN/표식 :: $(first) :: $(head -c 300 "$T/e1")"
  names > "$T/sent1"
fi

if on 2; then
  printf '\n<!-- 번호표 같은 main 커밋 -->\n' >> "$R/$CPATH"; commit "same-numbering"; : > "$MBOX_LOG"
  render "$T/o2b" "$T/e2b" MBOX_SLEEP=5
  names > "$T/sent2b"; DUP="$(comm -12 "$T/sent1" "$T/sent2b" 2>/dev/null | tr '\n' ' ')"
  [ "$RC" = 0 ] && [ -s "$T/sent2b" ] && [ -z "$DUP" ] && [ "$(first)" = "$OLD" ] \
    && ok "②ⓑ 번호표 같은 main 커밋 뒤 = 남은 팀장 $(wc -l < "$T/sent2b" | tr -d ' ')명만 · 중복 0" || bad "②ⓑ rc=$RC 중복 [$DUP] :: $(cat "$MBOX_LOG") :: $(first)"
  sort -u "$T/sent1" "$T/sent2b" > "$T/sent1u" && mv "$T/sent1u" "$T/sent1"
  : > "$MBOX_LOG"; render "$T/o2" "$T/e2"
  names > "$T/sent2"; N2="$(wc -l < "$T/sent2" | tr -d ' ')"; N1="$(wc -l < "$T/sent1" 2>/dev/null | tr -d ' ')"
  DUP="$(comm -12 "$T/sent1" "$T/sent2" 2>/dev/null | tr '\n' ' ')"
  [ "$RC" = 0 ] && [ -z "$DUP" ] && [ "$((N1 + N2))" = 12 ] && [ "$(sort -u "$T/sent1" "$T/sent2" | wc -l | tr -d ' ')" = 12 ] \
    && ok "② 다시 렌더 = 남은 팀장 ${N2}명만 · 중복 0" || bad "② rc=$RC 앞 $N1 · 이번 $N2 · 중복 [$DUP]"
  [ "$(first | cut -f1)" = "$(head10)" ] && [ "$(first)" != "$OLD" ] && grep -q '^prev	' "$MARK" && ! grep -q '^sent	' "$MARK" \
    && ok "② 모두 받음 → 표식 첫 줄 = 새 sig(+ prev 줄 · sent 줄 지움)" || bad "② 표식 :: $(cat "$MARK")"
fi

if on 3; then
  put c1 c2 c3 c4 c5; PRE="$(first)"; : > "$MBOX_LOG"
  render "$T/o3" "$T/e3" MBOX_FAIL='m03#03'
  [ "$RC" = 0 ] && [ "$(wc -l < "$MBOX_LOG" | tr -d ' ')" = 11 ] && ! grep -q '^m03#03 ' "$MBOX_LOG" && grep -q 'WARN 골 번호 공지 실패 m03#03' "$T/e3" \
    && [ "$(first)" = "$PRE" ] && ok "③ 1명 rc1 = 그 1명만 남음 · WARN · 표식 첫 줄 그대로" || bad "③ rc=$RC :: $(cat "$MBOX_LOG") :: $(first) :: $(head -c 300 "$T/e3")"
  : > "$MBOX_LOG"; render "$T/o3b" "$T/e3b"
  [ "$RC" = 0 ] && [ "$(cat "$MBOX_LOG")" = "m03#03 seen=1" ] && [ "$(first | cut -f1)" = "$(head10)" ] && [ "$(first)" != "$PRE" ] \
    && ok "③ 다음 렌더 = 그 1명만 다시 · 표식 전진" || bad "③ 다음 rc=$RC :: $(cat "$MBOX_LOG") :: $(first)"
fi

if on 5; then
  cp "$MARK" "$T/mark5"; : > "$MBOX_LOG"; render "$T/o5" "$T/e5"
  [ "$RC" = 0 ] && [ ! -s "$MBOX_LOG" ] && cmp -s "$MARK" "$T/mark5" && [ "$EL" -lt 3 ] \
    && ok "⑤ 번호표 그대로 = 공지 0 · 표식 그대로 · ${EL}s" || bad "⑤ rc=$RC ${EL}s :: $(cat "$MBOX_LOG")"
fi

if on 4; then
  put d1 d2 d3 d4 d5; cp "$MARK" "$T/mark4"; : > "$MBOX_LOG"
  cat > "$T/hold.py" <<'PY'
import fcntl, subprocess, sys
lock = open(sys.argv[1], "a+")
fcntl.flock(lock.fileno(), fcntl.LOCK_EX)   # 다른 렌더가 보내는 중인 자리
try:
    p = subprocess.run(sys.argv[2:], capture_output=True, text=True, timeout=5)
    sys.stdout.write(p.stdout); sys.stderr.write(p.stderr); raise SystemExit(p.returncode)
except subprocess.TimeoutExpired:
    print("잠금 기다리다 5초 끊김", file=sys.stderr); raise SystemExit(124)
PY
  s=$SECONDS; genv python3 "$T/hold.py" "$MARK.lock" python3 "$TOOL" > "$T/o4" 2> "$T/e4"; RC=$?; EL=$((SECONDS - s))
  [ "$RC" = 0 ] && [ "$EL" -lt 3 ] && [ ! -s "$MBOX_LOG" ] && cmp -s "$MARK" "$T/mark4" && [ "$(grep -c '^INFO 골 번호 공지 건너뜀' "$T/e4")" = 1 ] \
    && ok "④ 잠금 잡힘 = 공지 0 · INFO 1줄 · rc0 · ${EL}s" || bad "④ rc=$RC ${EL}s :: $(cat "$MBOX_LOG") :: $(head -c 300 "$T/e4")"
fi

if on 6; then
  cp "$MARK" "$T/mark6"; : > "$MBOX_LOG"; canon_of e1 e2 e3 e4 e5 > "$T/draft.md"
  MD="$T/draft.md" render "$T/o6" "$T/e6"
  [ "$RC" = 0 ] && [ ! -s "$MBOX_LOG" ] && cmp -s "$MARK" "$T/mark6" && grep -q '^INFO 시안 렌더' "$T/e6" \
    && ok "⑥ 시안 렌더 = 공지 · 표식 0 · INFO" || bad "⑥ rc=$RC :: $(cat "$MBOX_LOG") :: $(head -c 300 "$T/e6")"
fi
unset MBOX_LOG
echo "== test_goal_table_notify_budget_r2285: fail=$fail"
[ "$fail" = 0 ]
