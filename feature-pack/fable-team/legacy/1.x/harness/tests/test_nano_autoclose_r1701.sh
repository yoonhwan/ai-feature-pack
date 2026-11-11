#!/usr/bin/env bash
# test_nano_autoclose_r1701.sh — r1701: 나노 자동 닫기 0석의 세 막힘 — ① pi 좌석 판정이 LC_ALL=C 에서도 된다(-u) ② 판정 불가 1석이 전체를 막지 않는다
#   ③ 팩에서 일한 나노의 세트는 팩 origin/main 착지로 보고, 아카이브로 옮긴 카드도 근거로 읽는다.
#   ⓐ LC_ALL=C + 탭을 «_» 로 바꾸는 가짜 tmux 에서 ft_seat_pi.live_identity rc0(3칸) · 변이 M1(-u 삭제) → 판정 불가
#   ⓑ close-due rc=3 + «닫기 차례 A 갈래=승인» + «판정 불가 B» → A 닫기 1회 · 로그 «판정 불가 auto-close B» · 변이 M2
#   ⓒ close-due rc=99 → 닫기 0(지금과 같다)
#   ⓓ 세트 = 팩 origin/main 조상 → «닫기 차례» 1줄 · 변이 M3(팩 갈래 삭제) → 제외 · ⓔ 착지 아님 → 제외 · 변이 M4(착지 검사 삭제) → 닫기 차례
#   ⓕ 카드가 ref 의 아카이브/2026-11/ 에만 있음 → 세트 줄을 읽는다 · 변이 M5(아카이브 찾기 삭제) → «카드 파일 없음»
#   ⓖ 세트 sha 가 어느 리포에도 없음 → 제외(근거 0)
# 임시 리포·가짜 tmux·가짜 close-due/nano-close 만 · 실 tmux·실 명부·실 닫기 0 · sleep 0
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:300}"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3" "없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "있으면 안 됨: «$2»";; *) ok "$3";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
# ── ⓐ pi 좌석: 가짜 tmux 는 -u 가 없으면 탭을 «_» 로 바꾼다(실사건 꼴)
FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
a=" $* "; case "$a" in *" -u "*) sep=$'\t';; *) sep="_";; esac
[ "${1:-}" = -u ] && shift
case "$1" in
  list-panes) printf '%s\n' "byz-t-pi#0${sep}${TPID}${sep}$PWD${sep}0";;
  show-environment) echo "TMUXC_PI_SESSION_ID=abc123";;
esac
exit 0
EOF
chmod +x "$FK/tmux"
pi_run() {  # pi_run <도구경로> — live_identity 1회(같은 가짜 tmux · LC_ALL=C)
  TPID=$$ PATH="$FK:$PATH" python3 - "$1" <<'PY'
import os, sys, importlib.util
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("pi", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try: print("OK", *m.live_identity("byz-t-pi#0")); 
except Exception as e: print("ERR", e); sys.exit(1)
PY
}
OUT="$(pi_run "$BIN/ft_seat_pi.py")"; RC=$?
{ [ "$RC" = 0 ] && [ "$(printf '%s' "$OUT" | awk '{print NF}')" = 4 ] && case "$OUT" in *abc123*) true;; *) false;; esac; } \
  && ok "ⓐ LC_ALL=C 에서도 pi 좌석 판정 rc0(탭 3칸 + session id)" || bad "ⓐ" "rc=$RC out=$OUT"
MX="$T/mx"; mkdir -p "$MX"; cp -R "$BIN/." "$MX/"
python3 - "$MX/ft_seat_pi.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace('[tmux, "-u", "list-panes"', '[tmux, "list-panes"').replace('[tmux, "-u", "show-environment"', '[tmux, "show-environment"')
assert '"-u"' not in s
p.write_text(s)
PY
OUT="$(pi_run "$MX/ft_seat_pi.py")"; RC=$?
{ [ "$RC" != 0 ] && case "$OUT" in *"유일성 확인 불가"*) true;; *) false;; esac; } \
  && ok "M1 -u 삭제 → ⓐ 가 판정 불가(변이 잡힘)" || bad "M1" "rc=$RC out=$OUT"

# ── ⓑⓒ 자동 닫기: close-due/close 스텁으로 Scan.auto_close 만 부른다
ac() {  # ac <stall_scan.py> — auto_close 1회 → $OUT(줄들) $CLOSED(닫기 호출 로그)
  rm -f "$T/closed.log"
  OUT="$(FT_STALL_STATE_DIR="$T/state" FT_NANO_CLOSE_DUE="$T/cd.sh" FT_NANO_CLOSE="$T/nc.sh" FT_NANO_AUTO_CLOSE=1 \
    CLOSED_LOG="$T/closed.log" CD_RC="$1" python3 - "$2" <<'PY'
import importlib.util, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("sa", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
o = object.__new__(m.Scan); o.state_dir = __import__("pathlib").Path(os.environ["FT_STALL_STATE_DIR"]); o.now = time.time()
print("\n".join(o.auto_close()))
PY
)"; RC=$?; CLOSED="$(cat "$T/closed.log" 2>/dev/null)"
}
printf '#!/bin/sh\necho "닫기 차례 A 팀=harness 가지=nano/a 갈래=승인 set=%s — bash ft-nano-close.sh A --approved %s"\necho "판정 불가 B ft-seat-status turn rc=1"\nexit "${CD_RC:-0}"\n' 1111111111111111111111111111111111111111 1111111111111111111111111111111111111111 > "$T/cd.sh" 
printf '#!/bin/sh\necho "$*" >> "$CLOSED_LOG"\necho "CLOSED A"\n' > "$T/nc.sh"; chmod +x "$T/cd.sh" "$T/nc.sh"
ac 3 "$BIN/ft_stall_scan.py"
{ [ "$RC" = 0 ] && [ "$(grep -c . <<< "$CLOSED")" = 1 ] && case "$OUT" in *"판정 불가 auto-close B"*) true;; *) false;; esac; } \
  && ok "ⓑ close-due rc=3 이어도 승인 줄 A 는 닫고 판정 불가 B 는 1줄 남긴다" || bad "ⓑ" "rc=$RC closed=$CLOSED out=$OUT"
ac 99 "$BIN/ft_stall_scan.py"
{ [ -z "$CLOSED" ] && case "$OUT" in *"닫기 0"*) true;; *) false;; esac; } \
  && ok "ⓒ rc=99(시간 초과) → 닫기 0(지금과 같다)" || bad "ⓒ" "closed=$CLOSED out=$OUT"
python3 - "$MX/ft_stall_scan.py" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
old = '        if rc not in (0, 3):'
assert s.count(old) == 1
p.write_text(s.replace(old, '        if rc != 0:'))
PY
ac 3 "$MX/ft_stall_scan.py"
{ [ -z "$CLOSED" ]; } && ok "M2 rc=3 갈래 삭제 → ⓑ 가 닫기 0(변이 잡힘)" || bad "M2" "closed=$CLOSED out=$OUT"

# ── ⓓ~ⓖ close-due: 팩 세트(착지) · 아카이브 카드
SEAT="byz-harness-nano-pk#0"; REM="$T/rem/origin.git"; WT="$T/wt"; ROOT="$T/root"; PACK="$T/pack"
git init -q --bare -b main "$REM"; git clone -q "$REM" "$WT" 2>/dev/null; git -C "$WT" checkout -q -b main
mkdir -p "$WT/design/teams/harness"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |\n' > "$WT/design/TEAMS.md"
echo a > "$WT/a"; git -C "$WT" add -A; git -C "$WT" commit -qm M0; git -C "$WT" push -q origin main
git -C "$WT" checkout -q -b nano/pk; echo x > "$WT/x"; git -C "$WT" add x; git -C "$WT" commit -qm work
H="$(git -C "$WT" rev-parse HEAD)"; git -C "$WT" push -q origin "nano/pk:main"
git clone -q "$REM" "$ROOT"
# 팩 리포 — origin/main = S(착지) · S2 는 팩에만(착지 전)
git init -q -b main "$PACK"; git -C "$PACK" config user.name t; git -C "$PACK" config user.email t@t
echo p > "$PACK/p"; git -C "$PACK" add -A; git -C "$PACK" commit -qm S; S="$(git -C "$PACK" rev-parse HEAD)"
git -C "$PACK" update-ref refs/remotes/origin/main "$S"
echo q > "$PACK/q"; git -C "$PACK" add -A; git -C "$PACK" commit -qm S2; S2="$(git -C "$PACK" rev-parse HEAD)"
mkdir -p "$WT/design/teams/harness/indices/아카이브/2026-11"
card() { printf '# 인덱스: card1\n## 상태\n- 세트: %s · 시험: bash x rc=0 · 이슈: 0\n' "$1" > "$WT/design/teams/harness/indices/아카이브/2026-11/card1.md"; git -C "$WT" add -A; git -C "$WT" commit -qm "card $1"; git -C "$WT" push -q origin HEAD:main; }
mkdir -p "$ROOT/.fable-team/state" "$ROOT/.worktrees/cards-wt"
python3 - "$ROOT" "$SEAT" <<'PY'
import json, sys
root, seat = sys.argv[1], sys.argv[2]
json.dump({"_master": "byz-harness-master-pi#203", "_cards_wt": "cards-wt",
           seat: {"role": "nano", "agent": "pi", "cwd": "/nonexistent/bogus",
                  "index": "design/teams/harness/indices/진행/card1.md"}},
          open(root + "/.fable-team/seats-harness.json", "w"), ensure_ascii=False)
PY
mkdir -p "$T/ck"; cat > "$T/ck/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) cat "$FAKE_SESS";;
  display-message) s="${4#=}"; s="${s%:}"; cat "$FAKE_CWD_DIR/$s";;
  *) exit 9;;
esac
EOF
cat > "$FK/seat-status.sh" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = turn ] && [ -f "$FAKE_SS_DIR/$2" ] && { cat "$FAKE_SS_DIR/$2"; exit 0; }
exit 1
EOF
chmod +x "$T/ck/tmux" "$FK/seat-status.sh"; mkdir -p "$T/cwd" "$T/ss"
printf '%s\n' "$SEAT" > "$T/sess"; printf '%s\n' "$WT" > "$T/cwd/$SEAT"; printf 'IDLE - - - jsonl\n' > "$T/ss/$SEAT"
cd_run() { OUT="$(cd "$ROOT" && PATH="$T/ck:$FK:$PATH" FT_ROOT="$ROOT" FT_PACK_REPO="$PACK" \
  FT_CLOSE_DUE_SEAT_STATUS="$FK/seat-status.sh" FAKE_SESS="$T/sess" FAKE_CWD_DIR="$T/cwd" FAKE_SS_DIR="$T/ss" \
  bash "$1" --all --why 2>&1)"; RC=$?; }
card "$S"; cd_run "$BIN/ft-nano-close-due.sh"
has "$OUT" "닫기 차례 $SEAT" "ⓕ 카드가 아카이브/2026-11/ 에만 있어도 세트 줄을 읽는다"
hasnt "$OUT" "카드 파일 없음" "ⓕ «카드 파일 없음» 0"
has "$OUT" "닫기 차례 $SEAT" "ⓓ 세트 = 팩 origin/main 조상 → 닫기 차례 1줄"
card "$S2"; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "ⓔ 착지 전 세트(팩에만) → 닫기 차례 0"
card 2222222222222222222222222222222222222222; cd_run "$BIN/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "ⓖ 세트 sha 가 어느 리포에도 없음 → 제외(근거 0)"
cp "$MX/ft-nano-close-due.sh" "$T/cd3.sh" 2>/dev/null || true
mut3() {  # mut3 <사본이름> <python 치환 스크립트 인자> — bin 사본에서 한 곳만 바꾼다
  R="$T/m-$1"; rm -rf "$R"; cp -R "$BIN" "$R"; python3 - "$R/ft-nano-close-due.sh" "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); k = sys.argv[2]
def sub(old, new):
    global s
    assert s.count(old) == 1, old[:40]
    s = s.replace(old, new, 1)
if k == "M3":   # 팩 세트 갈래 삭제
    sub(" and not packed(sha_card)", "")
elif k == "M4":  # 착지 검사 삭제 — packed 를 항상 참으로
    sub('    if not re.fullmatch(r"[0-9a-f]{40}", sha or ""): return False', '    return True')
elif k == "M5":  # 아카이브 찾기 삭제
    sub('        rc, out, _e = run(["git", "-C", str(root), "ls-tree", "-d", "--name-only", f"{ref}:{cm.group(1)}/아카이브"])', '        rc, out, _e = 1, "", ""')
p.write_text(s)
PY
}
card "$S"; mut3 M3; cd_run "$T/m-M3/ft-nano-close-due.sh"
hasnt "$OUT" "닫기 차례 $SEAT" "M3 팩 세트 갈래 삭제 → ⓓ 닫기 차례 0(변이 잡힘)"
card "$S2"; mut3 M4; cd_run "$T/m-M4/ft-nano-close-due.sh"
has "$OUT" "닫기 차례 $SEAT" "M4 착지 검사 삭제 → ⓔ 가 닫기 차례(변이 잡힘)"
card "$S"; mut3 M5; cd_run "$T/m-M5/ft-nano-close-due.sh"
has "$OUT" "카드 파일 없음" "M5 아카이브 찾기 삭제 → ⓕ «카드 파일 없음»(변이 잡힘)"
# ── 짝 cmp
for f in ft_seat_pi.py ft_stall_scan.py ft-nano-close-due.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && ok "짝 cmp0 $f" || bad "짝 다름 $f" ""; done
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
