#!/usr/bin/env bash
# _autoclose_r1701_fixture.sh — r1701 시험 2파일 공용 픽스처(사례 아님 · source 전용).
#   가짜 tmux(탭을 «_» 로 바꾸는 꼴) · 가짜 close-due/nano-close/quiet/ft-seat-status · 임시 리포 3개(BYZ 꼴·데이터 루트·팩)
#   실 tmux·실 명부·실 닫기 0 · sleep 0
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1 :: ${2:0:300}"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3" "없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "있으면 안 됨: «$2»";; *) ok "$3";; esac; }
finish() { [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
FK="$T/fake"; mkdir -p "$FK"
# ⓐ 용 — -u 가 없으면 탭을 «_» 로 바꾼다(실사건 꼴)
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
pi_run() {  # pi_run <도구경로> — live_identity 1회(가짜 tmux · LC_ALL=C)
  TPID=$$ PATH="$FK:$PATH" python3 - "$1" <<'PY'
import os, sys, importlib.util
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("pi", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try: print("OK", *m.live_identity("byz-t-pi#0"))
except Exception as e: print("ERR", e); sys.exit(1)
PY
}
# ⓑⓒ 용 — Scan.auto_close 만 부른다
ac() {  # ac <stall_scan.py> <close-due rc>
  rm -f "$T/closed.log"
  OUT="$(FT_STALL_STATE_DIR="$T/state" FT_NANO_CLOSE_DUE="$T/cd.sh" FT_NANO_CLOSE="$T/nc.sh" FT_NANO_AUTO_CLOSE=1 \
    CLOSED_LOG="$T/closed.log" CD_RC="$2" python3 - "$1" <<'PY'
import importlib.util, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("sa", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
o = object.__new__(m.Scan); o.state_dir = __import__("pathlib").Path(os.environ["FT_STALL_STATE_DIR"]); o.now = time.time()
print("\n".join(o.auto_close()))
PY
)"; RC=$?; CLOSED="$(cat "$T/closed.log" 2>/dev/null)"
}
printf '#!/bin/sh\necho "닫기 차례 A 팀=harness 가지=nano/a 갈래=승인 set=%s — bash ft-nano-close.sh A --approved %s"\necho "판정 불가 B ft-seat-status turn rc=1"\nexit "${CD_RC:-0}"\n' 1111111111111111111111111111111111111111 1111111111111111111111111111111111111111 > "$T/cd.sh"
printf '#!/bin/sh\necho "$*" >> "$CLOSED_LOG"\necho "CLOSED A"\n' > "$T/nc.sh"
printf '#!/bin/sh\necho OK\n' > "$T/quiet.sh"; chmod +x "$T/cd.sh" "$T/nc.sh" "$T/quiet.sh"
# ⓓ~ⓖ 용 — 임시 리포 3개: 좌석 clone(WT) · 데이터 루트(ROOT) · 팩(PACK)
SEAT="byz-harness-nano-pk#0"; REM="$T/rem/origin.git"; WT="$T/wt"; ROOT="$T/root"; PACK="$T/pack"
git init -q --bare -b main "$REM"; git clone -q "$REM" "$WT" 2>/dev/null; git -C "$WT" checkout -q -b main
mkdir -p "$WT/design/teams/harness"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | byz-harness-master-pi | 현역 |\n' > "$WT/design/TEAMS.md"
echo a > "$WT/a"; git -C "$WT" add -A; git -C "$WT" commit -qm M0; git -C "$WT" push -q origin main
git -C "$WT" checkout -q -b nano/pk; echo x > "$WT/x"; git -C "$WT" add x; git -C "$WT" commit -qm work
git -C "$WT" push -q origin "nano/pk:main"; git clone -q "$REM" "$ROOT"
git init -q -b main "$PACK"; git -C "$PACK" config user.name t; git -C "$PACK" config user.email t@t
echo p > "$PACK/p"; git -C "$PACK" add -A; git -C "$PACK" commit -qm S; S="$(git -C "$PACK" rev-parse HEAD)"
git -C "$PACK" update-ref refs/remotes/origin/main "$S"
echo q > "$PACK/q"; git -C "$PACK" add -A; git -C "$PACK" commit -qm S2; S2="$(git -C "$PACK" rev-parse HEAD)"
IND="$WT/design/teams/harness/indices"; mkdir -p "$IND/아카이브/2026-11"
card() { printf '# 인덱스: card1\n## 상태\n- 세트: %s · 시험: bash x rc=0 · 이슈: 0\n' "$1" > "$IND/아카이브/2026-11/card1.md"; git -C "$WT" add -A; git -C "$WT" commit -qm "card $1"; git -C "$WT" push -q origin HEAD:main; }
card_da() { printf '# 인덱스: card1\n## 상태\n- 세트: %s · 시험: bash x rc=0 · 이슈: 0\n- DA 판정: %s#§1\n- 인수: %s\n' "$1" "$T/verdict.md" "$1" > "$IND/아카이브/2026-11/card1.md"; git -C "$WT" add -A; git -C "$WT" commit -qm "card da"; git -C "$WT" push -q origin HEAD:main; }
mkdir -p "$T/ck"
cat > "$T/ck/tmux" <<'EOF'
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
chmod +x "$T/ck/tmux" "$FK/seat-status.sh"; mkdir -p "$T/cwd" "$T/ss" "$ROOT/.fable-team/state" "$ROOT/.worktrees/cards-wt" "$ROOT/.fable-team/comm/bodies"
printf '%s\n' "$SEAT" > "$T/sess"; printf '%s\n' "$WT" > "$T/cwd/$SEAT"; printf 'IDLE - - - jsonl\n' > "$T/ss/$SEAT"
python3 - "$ROOT" "$SEAT" <<'PY'
import json, sys
root, seat = sys.argv[1], sys.argv[2]
json.dump({"_master": "byz-harness-master-pi#203", "_cards_wt": "cards-wt",
           seat: {"role": "nano", "agent": "pi", "cwd": "/nonexistent/bogus",
                  "index": "design/teams/harness/indices/진행/card1.md"}},
          open(root + "/.fable-team/seats-harness.json", "w"), ensure_ascii=False)
PY
cd_run() {  # cd_run <close-due 경로> [팩 리포] — 목록 1회(닫기는 하지 않는다 · --why)
  OUT="$(cd "$ROOT" && PATH="$T/ck:$FK:$PATH" FT_ROOT="$ROOT" FT_PACK_REPO="${2:-$PACK}" FT_NANO_AUTO_CLOSE=1 FT_CLOSE_DUE_QUIET="$T/quiet.sh" \
    FT_CLOSE_DUE_SEAT_STATUS="$FK/seat-status.sh" FAKE_SESS="$T/sess" FAKE_CWD_DIR="$T/cwd" FAKE_SS_DIR="$T/ss" \
    bash "$1" --all --why 2>&1)"; RC=$?
}
mut3() {  # mut3 <M3|M4|M5|M6> — bin 사본에서 한 곳만 바꾼다(사본에서만 · 원본 불변)
  R="$T/m-$1"; rm -rf "$R"; cp -R "$BIN" "$R"; cp -R "$BIN/../kit" "$R/../kit" 2>/dev/null || true
  python3 - "$R/ft-nano-close-due.sh" "$1" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); k = sys.argv[2]
def sub(old, new):
    global s
    assert s.count(old) == 1, old[:60]
    s = s.replace(old, new, 1)
if k == "M3":   # 팩 커밋 존재 갈래 삭제
    sub(" and not pack_commit(sha_card)", "")
elif k == "M4":  # 팩 존재 검사를 항상 참으로(X4 꼴)
    sub('    if not re.fullmatch(r"[0-9a-f]{40}", sha or ""): return False', '    return True')
elif k == "M5":  # 아카이브 카드 찾기 삭제
    sub('        rc, out, _e = run(["git", "-C", str(root), "ls-tree", "-d", "--name-only", f"{ref}:{cm.group(1)}/아카이브"])', '        rc, out, _e = 1, "", ""')
elif k == "M7":  # origin 만이 아니라 «모든 remote» 를 봄(전 판 꼴)
    sub('"for-each-ref", "--contains", sha, "--format=%(refname)", "refs/remotes/origin"', '"branch", "-r", "--contains", sha')
elif k == "M8":  # 팩 조회 실패를 False 로 삼킴(전 판 꼴)
    sub('    if rc != 0: raise Unjudged(f"팩 rev-parse rc={rc} {err.strip().splitlines()[:1]}")', '    if rc != 0: return False')
elif k == "M6":  # judge 의 squash 끝줄 파서 끔
    sub('            m = re.fullmatch(r"PR #(\\d+) \\(head " + jsha + r"\\)", ls[-1].strip()) if ls else None', '            m = None')
p.write_text(s)
PY
}
