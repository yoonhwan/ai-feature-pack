#!/usr/bin/env bash
# test_desk_tick_news_early_stop_r2180.sh — ft-desk-tick.sh NEWS 표 커밋 T 찾기가 T 를 정하면 멈춘다(r2180).
#   ② 표 커밋 뒤 설명 줄만 바꾼 커밋 2 → T = 표 커밋 · NEWS 줄 = 기준판
#   ③ 멈춤: 가짜 git -L = 첫 커밋 덩이 + 4KB 덩이 200(덩이마다 표식 1줄) → 표식 < 200 · NEWS = 첫 덩이 커밋 시각
#   ④ SIGPIPE 는 실패 아님: ③ 입력에서 «NEWS 판정 불가» 0 · 결정 필요 = ②
#   ⑤ T 없음(머리 줄만 · rc0) → «표 rc=1» · ⑥ T 앞 실패 rc 128 · 124 → 그 rc 그대로
#   ⑦ ② 입력에서 tick 전체 출력 · rc = 기준판(«초:» 줄의 숫자만 가림) · bin = kit cmp 0
# 기준판 = 시험할 bin 사본의 T 찾기 두 줄을 r2180 앞 원문으로 되돌린 사본(R2180_BASE 로 바꿀 수 있다).
# 전부 합성(임시 루트 · 임시 git 리포 · 가짜 mbox · hil · launchctl · ps · git) · 외부 호출 0 · sleep 0.
# R2180_BIN = 시험할 bin 폴더(변이 사본용).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="${R2180_BIN:-$HERE/../bin}/ft-desk-tick.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

NOW=1794103664
DESK='byz-planner-desk-claude#121'; PLANNER='byz-planner-master-claude#240'
R="$T/root/.fable-team"; NL="$R/state/board/news-last.json"; LED=design/teams/planner/PLAN-oppa-ledger.md
mkdir -p "$R/comm" "$R/state/board" "$T/fakebin" "$T/hil" "$T/state" "$T/base"
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$R/seats-planner.json"
printf '#!/usr/bin/env bash\ncase "$1" in send) echo QUEUED; exit 0;; peek) echo "pending=0 scanned=1 lineage=fake"; exit 0;; recv) echo "SCANNED 1 mailbox(es): fake"; exit 0;; esac\nexit 2\n' > "$R/comm/mbox.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil/ft-hil.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n\\tstate = running\\n\\tlast exit code = 0\\n" "$2"\n' > "$T/fakebin/launchctl"
printf '#!/usr/bin/env bash\necho "4242 python3 -u - /x %s"\n' "$DESK" > "$T/fakebin/ps"
# 가짜 git — -L 호출만 FAKE_L 꼴로 낸다(그 밖 = 진짜 git) · FAKE_C = «<sha> <시각>»
cat > "$T/fakebin/git" <<'EOS'
#!/usr/bin/env bash
L=0; for a in "$@"; do [ "$a" = -L ] && L=1; done
[ "$L" = 1 ] || exec git "$@"
case "${FAKE_L:-big}" in
  head) printf 'C %s\n' "$FAKE_C"; exit 0;;
  rc*) exit "${FAKE_L#rc}";;
esac
printf 'C %s\n\ndiff --git a/l b/l\n@@ -5 +5 @@\n-| 1 | a |\n+| 1 | b |\n' "$FAKE_C" || exit 141
pad="$(head -c 4095 < /dev/zero | tr '\0' x)"
for _ in $(seq 200); do echo m >> "$FAKE_MARK"; printf ' %s\n' "$pad" || exit 141; done
exit 0
EOS
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps" "$T/fakebin/git" "$R/comm/mbox.sh" "$T/hil/ft-hil.sh"
printf 'ts=%s stall=0\n' "$NOW" > "$T/stall.log"
printf '{"ts":"2026-11-08T11:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" > "$R/comm/mailbox.log.jsonl"

# 기준판 사본 — T 찾기 두 줄을 r2180 앞 원문으로 되돌린다
if [ -n "${R2180_BASE:-}" ]; then B="$R2180_BASE/ft-desk-tick.sh"; else
  B="$T/base/ft-desk-tick.sh"
  python3 - "$S" "$B" <<'EOP'
import sys
old1 = """  tl="$(X "$GIT" -C "$ROOT" log --format='C %H %ct' -L "/^## 골 진행$/,/^## /:$LEDGER" origin/main 2>/dev/null | awk '/^C [0-9a-f]+ [0-9]+$/{c=substr($0,3); next} /^[-+]\\|/ && t==""{t=c} END{print t}')"; rc=$?\n"""
old2 = """  if [ "$rc" -ne 0 ] || [ -z "$tl" ]; then news_fail 표 "$rc"; else\n"""
src = open(sys.argv[1], encoding="utf-8").read().splitlines(keepends=True)
out, i, n = [], 0, 0
while i < len(src):
    if src[i].startswith('  tl="$(X "$GIT" -C "$ROOT" log --format=') and 'news_fail 표' in src[i + 1]:
        out += [old1, old2]; i += 2; n += 1; continue
    out.append(src[i]); i += 1
assert n == 1, n
open(sys.argv[2], "w", encoding="utf-8").write("".join(out))
EOP
fi

run() {  # run <bin>
  env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" FT_DESK_TICK_MBOX="$R/comm/mbox.sh" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" FT_DESK_TICK_STALL_LOG="$T/stall.log" \
      FT_DESK_TICK_LOG="$R/comm/mailbox.log.jsonl" FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 FT_DESK_TICK_STATE_DIR="$T/state" \
      bash "$1" "$DESK" 2>&1
}
at() { python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1])).isoformat())' "$((NOW - $1))"; }
mi() { at "$1" | cut -c1-16; }
dec() { printf '%s\n' "$1" | tail -1 | sed -n 's/^결정 필요: //p'; }
nl() { printf '%s\n' "$1" | grep '^NEWS '; }
mask() { printf '%s\n' "$1" | sed '/^초: /s/[0-9][0-9]*/N/g'; }
G() { git -C "$T/root" -c user.email=t@t -c user.name=t "$@"; }
led() { printf '# 원장\n\n## 골 진행\n\n%s\n\n| 1 | %s |\n\n## 다른 절\n\nx\n' "$2" "$1" > "$T/root/$LED"; }   # led <표 값> <설명 줄>
cm() { G add -A design; GIT_COMMITTER_DATE="$((NOW - $1)) +0000" GIT_AUTHOR_DATE="$((NOW - $1)) +0000" G commit -qm "$2"; }

# ② 입력 — 표 a(10시간 전) → 표 b(4시간 전 = T) → 설명 줄만 2번
mkdir -p "$T/root/design/teams/planner" "$T/root/design/harness/indices/완성"; G init -q -b main
printf '{"at": "%s", "key": [], "snap": {}}\n' "$(at 7200)" > "$NL"
led a d0; cm 36000 R0; led b d0; cm 14400 T; led b d1; cm 10000 D1; led b d2; cm 5000 D2
G update-ref refs/remotes/origin/main HEAD; G update-ref refs/remotes/origin/ops/main-base HEAD
TSHA="$(G rev-parse HEAD~2)"; WANT="NEWS last_post=$(mi 7200) table=$(mi 14400) age=4h behind=0"

O2="$(run "$S")"; rc2=$?; OB="$(run "$B")"; rcb=$?
chk "② 설명 줄만 2커밋 뒤 → T = 표 커밋 «${WANT}»" '[ "$(nl "$O2")" = "$WANT" ]'
chk "② NEWS 줄 = 기준판" '[ "$(nl "$O2")" = "$(nl "$OB")" ]'

export FAKE_C="$TSHA $((NOW - 14400))" FAKE_MARK="$T/mark"
rm -f "$T/mark"; O3="$(FT_DESK_TICK_GIT="$T/fakebin/git" FAKE_L=big run "$S")"; m3="$(wc -l < "$T/mark" | tr -d ' ')"
echo "  ③ 표식 줄 수 = $m3"
chk "③ 표식 < 200(T 뒤 git 출력을 더 읽지 않음)" '[ "$m3" -lt 200 ]'
chk "③ NEWS = 첫 덩이 커밋 시각 «${WANT}»" '[ "$(nl "$O3")" = "$WANT" ]'
chk "④ ③ 입력 «NEWS 판정 불가» 0" '! printf "%s\n" "$O3" | grep -q "NEWS 판정 불가"'
chk "④ 결정 필요 = ② ($(dec "$O2"))" '[ -n "$(dec "$O3")" ] && [ "$(dec "$O3")" = "$(dec "$O2")" ]'

O5="$(FT_DESK_TICK_GIT="$T/fakebin/git" FAKE_L=head run "$S")"
chk "⑤ T 없음(머리 줄만 · rc0) → «NEWS 판정 불가 — 표 rc=1»" 'printf "%s\n" "$O5" | grep -qx "NEWS 판정 불가 — 표 rc=1" && [ "$(dec "$O5")" = $(( $(dec "$O2") + 1 )) ]'
for c in 128 124; do
  O6="$(FT_DESK_TICK_GIT="$T/fakebin/git" FAKE_L=rc$c run "$S")"
  chk "⑥ T 앞 실패 rc $c → «NEWS 판정 불가 — 표 rc=${c}»" 'printf "%s\n" "$O6" | grep -qx "NEWS 판정 불가 — 표 rc=$c"'
done

chk "⑦ ② 입력 tick 전체 출력 = 기준판(«초:» 숫자만 가림)" '[ "$(mask "$O2")" = "$(mask "$OB")" ]'
chk "⑦ ② 입력 rc = 기준판 ($rcb)" '[ "$rc2" = "$rcb" ]'
K="$(dirname "$S")/../kit/fable-team/bin/ft-desk-tick.sh"
if [ -z "${R2180_BIN:-}" ]; then chk "⑦ bin = kit cmp 0" 'cmp -s "$S" "$K"'; fi

echo "fail=$fail"; [ "$fail" = 0 ]
