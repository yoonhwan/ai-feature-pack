#!/usr/bin/env bash
# test_team_move_cleanup_r899.sh — r899 팀 폴더 이동 뒷정리 (카드 시험 ⓐ~ⓕ)
#   ⓐ --classify: 살아 있는 좌석(LIVE-OK·LIVE-FIX·LIVE-HAND) · 닫힌 좌석(ARCHIVE) · 코드(RUN·NOTE·RECORD·FIXTURE) 가름
#   ⓑ --cleanup-plan = 계획만(명부·nano-card-base 바이트 그대로) · plan.sh → 보관·다시 씀 · 실행 시점 살아난 좌석 SKIP · 계획 변조 REJECT · --cleanup-restore 되살림
#   ⓒ tmux 목록을 못 읽으면 분류·계획 전체 ERROR(보관 판정 0)
#   ⓓ --verify: 실행 글자 ERR · 주석·기록 WARN · 허용 목록(사유) 픽스처 셈 밖 · 사유 없는 줄/코드 파일은 예외 0 · 뒷정리 뒤 좌석 칸 ERR 0
#   ⓔ 문법 · 키트 사본 cmp0
#   ⓕ 변이: 분류 규칙 반전(살아 있음↔닫힘) → 살아 있는 좌석이 ARCHIVE 로 가는 칸 빨강
# 임시 리포·가짜 tmux·가짜 lsof 만 — 실제 리포·명부·tmux 세션은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()   { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
eq() { [ "$1" = "$2" ] && ok "$3" || bad "$3 — 기대 «$2» 실제 «$1»"; }

mkdir -p "$T/fake"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-sessions) [ -n "${FAKE_LOG:-}" ] && echo "$1" >> "$FAKE_LOG"; if [ -s "${FAKE_SESSIONS:-/nonexistent}" ]; then cat "$FAKE_SESSIONS"; else echo "no server running on /tmp/fake" >&2; exit 1; fi;;
  list-panes) echo "no server running on /tmp/fake"; exit 1;;
esac
EOF
printf '#!/usr/bin/env bash\nprintf "p1\\ncfake\\nn/dev/null\\n"\n' > "$T/fake/lsof"
chmod +x "$T/fake/tmux" "$T/fake/lsof"
GITC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

# ── 픽스처: 옮긴 팀 x(design/teams/x/) · 카드 워크트리 cards · 나노 워크트리 nanowt ──
R="$T/repo"; X="$R/design/teams/x"
mkdir -p "$X/indices/진행" "$R/.fable-team/state/nano-card-base" "$R/.baton" "$R/scripts" "$R/tests/fixtures" "$R/design/evidence/old"
git -C "$R" init -q -b main
printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| x | `design/teams/x/` | byz-x-master-claude | 현역 |\n' > "$R/design/TEAMS.md"
printf '# 팀셋\n## 표 1\n| x | y |\n|---|---|\n## 표 2 — 팀별\n| 팀 | 상한 |\n|---|---|\n| x | 3 |\n' > "$R/design/TEAMSET.md"
: > "$X/indices/.gitkeep"
printf '# x\n정본 위치: design/teams/x/README.md\n## 파일 지도\n| 경로 | 뜻 |\n|---|---|\n| `README.md` | 지도 |\n| `indices/` | 카드 |\n' > "$X/README.md"
printf '.worktrees/\n.fable-team/\n.baton/\n' > "$R/.gitignore"
CW="$R/.worktrees/cards/design/teams/x/indices"; mkdir -p "$CW/진행" "$CW/완성" "$R/.worktrees/nanowt"
echo a > "$CW/진행/a.md"; echo c > "$CW/진행/c.md"; echo e > "$CW/완성/e.md"
python3 -I -c 'import json,sys
rows = {"_cards_wt": "cards"}
for seat, idx in [("l1", "design/x/indices/진행/a.md"), ("l2", "design/x/indices/진행/zz.md"), ("l3", "design/teams/x/indices/진행/c.md"),
                  ("l4", "design/teams/x/indices/진행/e.md"), ("d1", "design/x/indices/진행/gone.md"),
                  ("m", "design/x/indices/inbox/master/"), ("t", "design/x/indices/진행/old.md")]:
    if seat == "t":
        rows["ft-x-temp-old#2"] = {"role": "stop-ready", "index": idx}
    elif seat == "m":
        rows["byz-x-master-claude#0"] = rows["byz-x-master-claude#3"] = {"role": "master", "index": idx}
        rows["byz-x-da-codex#2"] = {"role": "da", "index": "design/x/indices/진행/c.md"}
    else:
        rows[f"byz-x-nano-{seat}#0"] = {"role": "nano", "index": idx, "worktree": "nanowt"}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(rows, ensure_ascii=False, indent=2) + "\n")' "$R/.fable-team/seats-x.json"
NCB="$R/.fable-team/state/nano-card-base"
printf '{\n  "name": "byz-x-nano-d2#0",\n  "card_path": "design/teams/x/indices/진행/gone2.md",\n  "worktree": "%s"\n}\n' "$R/.worktrees/nanowt" > "$NCB/byz-x-nano-d2#0.json"
printf '{\n  "name": "byz-x-nano-l1#0",\n  "card_path": "design/x/indices/진행/a.md",\n  "worktree": "%s"\n}\n' "$R/.worktrees/nanowt" > "$NCB/byz-x-nano-l1#0.json"
printf 'byz-x-nano-l1#0\nbyz-x-nano-l2#0\nbyz-x-nano-l3#0\nbyz-x-nano-l4#0\nbyz-y-master-claude#1\n' > "$T/live.txt"
printf 'P = "design/x/a.md"\n' > "$R/scripts/run.py"
printf '"""설계 design/x/a.md 참고."""\n# 주석 design/x/a.md\nprint("인덱스: design/x/a.md")\n' > "$R/scripts/note.py"
printf '#!/usr/bin/env bash\ncat design/x/a.md\n' > "$R/scripts/run.sh"
printf '{"body": "design/x/a.md"}\n' > "$R/tests/fixtures/f.json"
printf 'A = "design/x/a.md"\n' > "$R/design/evidence/old/e.py"
GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m init

TM() { FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FT_TEAM_MOVE_LSOF="$T/fake/lsof" FAKE_SESSIONS="$T/live.txt" PATH="$T/fake:$PATH" bash "${BIN:-$SRC}/ft-team-move.sh" "$@" 2>&1; }
snap() { shasum "$R/.fable-team/seats-x.json" "$NCB"/*.json | sort; }

echo "== ⓐ --classify"
out="$(TM --classify x)"; rc=$?
eq "$rc" 0 "ⓐ classify rc0"
has "$out" "CLS LIVE-FIX x roster byz-x-nano-l1#0 design/x/indices/진행/a.md — design/teams/x/indices/진행/a.md" "ⓐ 살아 있는 좌석 옛 경로 → LIVE-FIX(새 경로 1개)"
has "$out" "CLS LIVE-HAND x roster byz-x-nano-l2#0 design/x/indices/진행/zz.md — 옮긴 경로에 없음 · 상태 폴더만 다른 후보 0개" "ⓐ 살아 있는 좌석 후보 0 → LIVE-HAND"
has "$out" "CLS LIVE-OK x roster byz-x-nano-l3#0" "ⓐ 카드 워크트리에 실재 → LIVE-OK"
has "$out" "CLS LIVE-HAND x roster byz-x-nano-l4#0 design/teams/x/indices/진행/e.md — 옮긴 경로에 없음 · 상태 폴더만 다른 후보 1개: design/teams/x/indices/완성/e.md" "ⓐ 상태 폴더만 다름 → 자동 0(LIVE-HAND · 후보는 사유에)"
has "$out" "CLS ARCHIVE x roster byz-x-nano-d1#0" "ⓐ tmux 세션 없음 → ARCHIVE(명부)"
has "$out" "CLS ARCHIVE x ncb byz-x-nano-d2#0" "ⓐ tmux 세션 없음 → ARCHIVE(nano-card-base)"
has "$out" "CLS LIVE-FIX x ncb byz-x-nano-l1#0" "ⓐ 살아 있는 nano-card-base → LIVE-FIX"
has "$out" "CLS ARCHIVE x roster byz-x-master-claude#0" "ⓐ 닫힌 역할 좌석(계보 최댓값 아님) → ARCHIVE"
has "$out" "CLS ARCHIVE x roster ft-x-temp-old#2" "ⓐ 닫힌 옛 나노(-temp-) → ARCHIVE(번호 계보 아님)"
has "$out" "CLS KEEP-FIX x roster byz-x-da-codex#2 design/x/indices/진행/c.md — design/teams/x/indices/진행/c.md" "ⓐ 계보 최댓값 + 옮긴 경로 실재 → KEEP-FIX(행 남기고 index 만)"
has "$out" "CLS KEEP-LINEAGE x roster byz-x-master-claude#3" "ⓐ 닫힌 역할 좌석 계보 최댓값 → KEEP-LINEAGE(번호 기준 · 빼지 않음)"
has "$out" "CLS CODE-RUN x code scripts/run.py:1" "ⓐ 파이썬 문자열 경로 → CODE-RUN"
has "$out" "CLS CODE-RUN x code scripts/run.sh:2" "ⓐ 셸 비주석 줄 → CODE-RUN"
has "$out" "CLS CODE-NOTE x code scripts/note.py:1" "ⓐ 독스트링 → CODE-NOTE"
has "$out" "CLS CODE-NOTE x code scripts/note.py:2" "ⓐ 주석 → CODE-NOTE"
has "$out" "CLS CODE-NOTE x code scripts/note.py:3" "ⓐ 메시지 문장 중간 → CODE-NOTE"
has "$out" "CLS CODE-FIXTURE-UNLISTED x code tests/fixtures/f.json:1" "ⓐ 허용 목록 밖 픽스처 → UNLISTED"
has "$out" "CLS CODE-RECORD x code design/evidence/old/e.py:1" "ⓐ 기록 폴더 → CODE-RECORD"
has "$out" "CLASSIFY LIVE-OK=1 LIVE-FIX=2 LIVE-HAND=2 ARCHIVE=4 KEEP-FIX=1 KEEP-LINEAGE=1 CODE-RUN=2 CODE-NOTE=3 CODE-RECORD=1 CODE-FIXTURE=0 CODE-FIXTURE-UNLISTED=1" "ⓐ 끝줄 셈"

echo "== ⓒ tmux 못 읽음 → ERROR · 보관 판정 0"
out="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS=/nonexistent PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" --classify x 2>&1)"; rc=$?
eq "$rc" 1 "ⓒ classify rc1"
has "$out" "ERROR tmux 세션 목록" "ⓒ ERROR 줄"
hasnt "$out" "ARCHIVE" "ⓒ ARCHIVE 0"
out="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS=/nonexistent PATH="$T/fake:$PATH" bash "$SRC/ft-team-move.sh" --cleanup-plan x --out "$T/p0" 2>&1)"; rc=$?
eq "$rc" 1 "ⓒ cleanup-plan rc1"
[ -e "$T/p0/plan.sh" ] && bad "ⓒ 계획 파일이 생겼다" || ok "ⓒ 계획 파일 0"

echo "== ⓑ --cleanup-plan = 계획만"
before="$(snap)"
out="$(TM --cleanup-plan x --out "$T/p1")"; rc=$?
eq "$rc" 0 "ⓑ plan rc0"
has "$out" "PLAN-OUT $T/p1/plan.sh 실행 대상 7" "ⓑ 실행 대상 7(ARCHIVE 4 + LIVE-FIX 2 + KEEP-FIX 1)"
eq "$(snap)" "$before" "ⓑ 계획만 — 명부·nano-card-base 바이트 그대로"
has "$(cat "$T/p1/plan.sh")" "--cleanup-run $T/p1/plan.json --plan-sha " "ⓑ plan.sh = sha 고정 실행 1줄"
has "$(cat "$T/p1/plan.tsv")" "LIVE-HAND	x	roster	byz-x-nano-l2#0" "ⓑ plan.tsv 에 사람 몫 표"
out="$(TM --cleanup-run "$T/p1/plan.json")"; rc=$?
eq "$rc" 1 "ⓑ --plan-sha 없이 run = REJECT rc1"
eq "$(snap)" "$before" "ⓑ REJECT 뒤 바이트 그대로"

echo "== ⓑ 변조 계획 REJECT"
cp -R "$T/p1" "$T/p2"; sha="$(sed -n 's/.*--plan-sha //p' "$T/p2/plan.sh")"
printf ' ' >> "$T/p2/plan.json"
out="$(TM --cleanup-run "$T/p2/plan.json" --plan-sha "$sha")"; rc=$?
eq "$rc" 1 "ⓑ 변조 rc1"; has "$out" "REJECT 계획 파일이 만든 뒤 바뀌었다" "ⓑ 변조 REJECT 줄"
eq "$(snap)" "$before" "ⓑ 변조 REJECT 뒤 바이트 그대로"

echo "== ⓑ 실행 시점에 살아난 좌석은 SKIP (d1 세션이 생김)"
cp "$T/live.txt" "$T/live.bak"; echo 'byz-x-nano-d1#0' >> "$T/live.txt"
out="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS="$T/live.txt" PATH="$T/fake:$PATH" bash "$T/p1/plan.sh" 2>&1)"; rc=$?
eq "$rc" 0 "ⓑ plan.sh rc0"
has "$out" "SKIP byz-x-nano-d1#0 살아 있음" "ⓑ 살아난 좌석 SKIP"
has "$out" "CLEANUP-RUN ARCHIVED=3 REWROTE=3 SKIPPED=1" "ⓑ 보관 3 · 다시 씀 3 · SKIP 1"
arch="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
rows="$(python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));print(sorted(k for k in d if not k.startswith("_")), d["byz-x-nano-l1#0"]["index"], d["byz-x-nano-l4#0"]["index"])' "$R/.fable-team/seats-x.json")"
eq "$rows" "['byz-x-da-codex#2', 'byz-x-master-claude#3', 'byz-x-nano-d1#0', 'byz-x-nano-l1#0', 'byz-x-nano-l2#0', 'byz-x-nano-l3#0', 'byz-x-nano-l4#0'] design/teams/x/indices/진행/a.md design/teams/x/indices/진행/e.md" "ⓑ 명부: d1 그대로(SKIP) · l1 새 경로 · l4(LIVE-HAND) 그대로"
[ -e "$NCB/byz-x-nano-d2#0.json" ] && bad "ⓑ d2 기록이 남았다" || ok "ⓑ d2 nano-card-base 보관으로 이동"
[ -f "$(dirname "$arch")/ncb/byz-x-nano-d2#0.json" ] && ok "ⓑ 보관본 실재(지우기 0)" || bad "ⓑ 보관본 없음"
has "$(cat "$NCB/byz-x-nano-l1#0.json")" '"card_path": "design/teams/x/indices/진행/a.md"' "ⓑ l1 nano-card-base 새 경로"

echo "== ⓓ --verify (뒷정리 뒤 좌석 칸 · 코드 칸)"
cp "$T/live.bak" "$T/live.txt"
printf '# r899\ntests/fixtures/f.json\t고정 입력 데이터\nscripts/run.py\t코드 파일은 예외 안 됨\n' > "$R/design/TEAM-MOVE-ALLOW.tsv"
out="$(TM --verify x)"; rc=$?
has "$out" "ERR x 명부 byz-x-nano-l2#0 index 실재 안 함" "ⓓ 남은 LIVE-HAND 는 ERR 유지"
has "$out" "ERR x 명부 byz-x-nano-d1#0 index 실재 안 함" "ⓓ SKIP 된 좌석 ERR 유지"
hasnt "$out" "byz-x-nano-l3#0" "ⓓ 카드 워크트리에 실재(LIVE-OK) = ERR 0"
hasnt "$out" "byz-x-nano-l1#0" "ⓓ 다시 쓴 좌석 ERR 0"
has "$out" "ERR x 코드 옛 경로 design/x/ : scripts/run.py:1 (CODE-RUN)" "ⓓ 실행 글자 ERR · 코드 파일은 허용 목록에 있어도 ERR"
has "$out" "ERR x 코드 옛 경로 design/x/ : scripts/run.sh:2 (CODE-RUN)" "ⓓ 셸 실행 줄 ERR"
has "$out" "WARN x 주석 옛 경로 design/x/ : scripts/note.py:2" "ⓓ 주석 WARN"
has "$out" "WARN x 기록 옛 경로 design/x/ : design/evidence/old/e.py:1" "ⓓ 기록 WARN"
has "$out" "INFO 허용 목록(TEAM-MOVE-ALLOW.tsv · 사유 있음) 픽스처 옛 경로 1곳 셈 밖" "ⓓ 사유 있는 픽스처 셈 밖"
has "$out" "ERR x 명부 byz-x-nano-l4#0 index 실재 안 함" "ⓓ 상태 폴더만 다른 좌석 ERR 유지(사람 몫)"
has "$out" "ERR x 명부 byz-x-master-claude#3 index 실재 안 함" "ⓓ KEEP-LINEAGE 행 ERR 유지(남은 표)"
has "$out" "VERIFY ERR=6 WARN=4" "ⓓ ERR 6(l2·l4·d1·master#3·run.py·run.sh) WARN 4(주석 3·기록 1)"
eq "$rc" 1 "ⓓ verify rc1"
printf 'tests/fixtures/f.json\t \n' > "$R/design/TEAM-MOVE-ALLOW.tsv"
has "$(TM --verify x)" "ERR x 코드 옛 경로 design/x/ : tests/fixtures/f.json:1 (CODE-FIXTURE-UNLISTED)" "ⓓ 사유 빈 줄 = 예외 0(ERR)"

echo "== ⓑ --cleanup-restore 되살림"
out="$(TM --cleanup-restore "$arch")"; rc=$?
eq "$rc" 0 "ⓑ restore rc0"
has "$out" "CLEANUP-RESTORE RESTORED=6 SKIPPED=0" "ⓑ 되살림 6(ncb 1 + 다시 쓴 칸 3 + 명부 2)"
[ -f "$NCB/byz-x-nano-d2#0.json" ] && ok "ⓑ d2 기록 되돌아옴" || bad "ⓑ d2 기록 없음"
eq "$(snap)" "$before" "ⓑ 되살린 뒤 명부·nano-card-base 바이트 = 처음"

echo "== ⓑ 보관 → 되살림 왕복 (명부 행 포함)"
out="$(TM --cleanup-plan x --out "$T/p3")"
out="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS="$T/live.txt" PATH="$T/fake:$PATH" bash "$T/p3/plan.sh" 2>&1)"
has "$out" "CLEANUP-RUN ARCHIVED=4 REWROTE=3 SKIPPED=0" "ⓑ 보관 4 · 다시 씀 3"
has "$(cat "$R/.fable-team/seats-x.json")" '"_cards_wt"' "ⓑ 명부 머리 칸 보존"
hasnt "$(cat "$R/.fable-team/seats-x.json")" "byz-x-nano-d1#0" "ⓑ d1 명부에서 빠짐"
arch="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
out="$(TM --cleanup-restore "$arch")"
has "$out" "CLEANUP-RESTORE RESTORED=7 SKIPPED=0" "ⓑ 되살림 7"
eq "$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["byz-x-nano-d1#0"]["index"])' "$R/.fable-team/seats-x.json")" "design/x/indices/진행/gone.md" "ⓑ d1 행 원문 되돌아옴"

echo "== ⓕ 변이: 분류 반전 → 살아 있는 좌석이 ARCHIVE (빨강이어야 함)"
mkdir -p "$T/mbin"; cp "$SRC"/ft-team-move.sh "$SRC"/ft_team_move*.py "$SRC"/ft-team-lib.sh "$SRC"/ft-team-map-lint.sh "$SRC"/ft-team-upgrade.sh "$T/mbin/" 2>/dev/null
python3 -I -c 'import sys;p=sys.argv[1];s=open(p,encoding="utf-8").read();assert s.count("    if not live:\n")==1;open(p,"w",encoding="utf-8").write(s.replace("    if not live:\n","    if live:\n"))' "$T/mbin/ft_team_move_classify.py"
mout="$(BIN="$T/mbin" TM --classify x)"
case "$mout" in *"CLS ARCHIVE x roster byz-x-nano-l1#0"*) ok "ⓕ 변이 빨강 — 살아 있는 l1 이 ARCHIVE 로 감(위 ⓐ «LIVE-FIX l1» 칸이 이 변이를 잡는다)";; *) bad "ⓕ 변이가 빨강을 안 냄 ← ${mout:0:300}";; esac

echo "== ⓖ 반례 1 — 명부 잠금(살아 있는 잠금 = REJECT · 죽은 잠금 회수) · tmux 목록은 파일 수만큼만"
out="$(TM --cleanup-plan x --out "$T/p4")"
sha4="$(sed -n 's/.*--plan-sha //p' "$T/p4/plan.sh")"
nfiles="$(python3 -I - "$T/p4/plan.json" <<'PY'
import json, sys
print(len({i["file"] for i in json.load(open(sys.argv[1]))["act"]}))
PY
)"
LK="$R/.fable-team/seats-x.json.lock.d"
mkdir -p "$LK"; echo $$ > "$LK/pid"
out="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS="$T/live.txt" PATH="$T/fake:$PATH" bash "$T/p4/plan.sh" 2>&1)"; rc=$?
eq "$rc" 1 "ⓖ 살아 있는 잠금 → REJECT rc1"
has "$out" "REJECT 잠금을 못 잡았다" "ⓖ REJECT 사유 = 남이 이 파일을 쓰는 중"
[ -d "$LK" ] && ok "ⓖ 남의 잠금은 안 지운다" || bad "ⓖ 남의 잠금을 지웠다"
hasnt "$out" "CLEANUP-RUN" "ⓖ 잠금 못 잡으면 쓰기 0(부분 적용 없음)"
[ -f "$NCB/byz-x-nano-d2#0.json" ] && ok "ⓖ REJECT 뒤 기록 그대로" || bad "ⓖ REJECT 전에 이미 썼다"
rm -rf "$LK"; mkdir -p "$LK"; echo 999999 > "$LK/pid"
: > "$T/tmuxcalls.txt"
out="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS="$T/live.txt" FAKE_LOG="$T/tmuxcalls.txt" PATH="$T/fake:$PATH" bash "$T/p4/plan.sh" 2>&1)"; rc=$?
eq "$rc" 0 "ⓖ 죽은 pid 잠금은 회수하고 진행"
[ -e "$LK" ] && bad "ⓖ 잠금이 안 풀렸다" || ok "ⓖ 잠금 풀림"
eq "$(grep -c . "$T/tmuxcalls.txt")" "$nfiles" "ⓖ tmux 목록 = 파일 ${nfiles}개만큼 1회씩(행마다 0)"

echo "== ⓖ 반례 2·3 — 계획 파일 1회 읽기 · 분류와 행 지문이 한 판 · 명부 재읽기 0"
P="$T/probe"; mkdir -p "$P/design/teams/x/indices/진행" "$P/.fable-team/state/nano-card-base"
echo b > "$P/design/teams/x/indices/진행/b.md"
printf '# x\n' > "$P/design/teams/x/README.md"
printf '.fable-team/\n' > "$P/.gitignore"   # 명부는 추적 밖(실 리포와 같게 — 코드 검색이 명부를 다시 읽지 않게)
printf '# 팀 명단\n| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| x | `design/teams/x/` | byz-x-master-claude | 현역 |\n' > "$P/design/TEAMS.md"
git -C "$P" init -q -b main
python3 -I -c 'import json,sys
d={"byz-x-nano-a#0":{"role":"nano","index":"design/x/indices/진행/a.md"},"byz-x-nano-b#0":{"role":"nano","index":"design/x/indices/진행/b.md"}}
open(sys.argv[1],"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")' "$P/.fable-team/seats-x.json"
printf 'byz-x-nano-b#0\n' > "$T/plive.txt"
GITC "$P" add -A >/dev/null 2>&1; GITC "$P" commit -q -m init
cp -R "$P" "$T/probe0"   # 깨끗한 원본 — 변이용 사본의 씨앗
cat > "$T/probe.py" <<'PY'
import collections, sys
from pathlib import Path
src, repo, out, mode = sys.argv[1:5]
sys.path.insert(0, src)
import ft_team_move as tm, ft_team_move_cleanup as cu
cnt = collections.Counter()
_rb, _rt = Path.read_bytes, Path.read_text

def _b(self):
    cnt[("bytes", str(self))] += 1
    return _rb(self)


def _t(self, *a, **k):
    cnt[("text", str(self))] += 1
    return _rt(self, *a, **k)


Path.read_bytes, Path.read_text = _b, _t
ctx = tm.Ctx(Path(repo), Path(repo), {"x": "design/teams/x/"})
if mode == "plan":
    cu.cmd_plan(ctx, "x", Path(out))
elif mode == "restore":
    rrc = cu.cmd_restore(ctx, Path(sys.argv[5]))
else:
    cu.cmd_run(ctx, Path(out) / "plan.json", sys.argv[5])
pj, rs = str(Path(out) / "plan.json"), str(Path(repo) / ".fable-team" / "seats-x.json")
print("READS plan_bytes=%d plan_text=%d roster_bytes=%d roster_text=%d"
      % (cnt[("bytes", pj)], cnt[("text", pj)], cnt[("bytes", rs)], cnt[("text", rs)]))
if mode == "restore":
    print("RESTORE rc=%d" % rrc)
PY
PR() { local repo="$1"; shift; FT_REPO_ROOT="$repo" FT_TEAM_MOVE_STATE="$T/ps-$(basename "$repo")" FAKE_SESSIONS="$T/plive.txt" PATH="$T/fake:$PATH" \
  python3 -I "$T/probe.py" "${BIN:-$SRC}" "$repo" "$@"; }
plan_sha() { python3 -I -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }
out="$(PR "$P" "$T/pp" plan)"
has "$out" "READS plan_bytes=1 plan_text=0 roster_bytes=0 roster_text=1" "ⓖ3 계획 = 명부 1회 읽기(분류·지문 같은 판)"
out="$(PR "$P" "$T/pp" run "$(plan_sha "$T/pp/plan.json")")"
has "$out" "READS plan_bytes=1 plan_text=0 roster_bytes=2 roster_text=0" "ⓖ2·3 실행 = 계획 1회(바이트) · 명부 2회 = 판정 B1 + 교체 직전 B2(CAS)뿐"
arch="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
has "$(cat "$P/.fable-team/seats-x.json")" '"index": "design/teams/x/indices/진행/b.md"' "ⓖ3 다시 쓴 좌석 = 새 경로"
hasnt "$(cat "$P/.fable-team/seats-x.json")" '"byz-x-nano-a#0"' "ⓖ3 보관된 좌석 = 명부에서 빠짐"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p,encoding="utf-8"));d["byz-x-nano-b#0"]["worktree"]="otherwt";open(p,"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")' "$P/.fable-team/seats-x.json"
out="$(PR "$P" "$T/pp" restore "$arch")"
has "$out" "SKIP seats-x.json 또 바뀜" "ⓢ ⓖ4 교체 직후 바이트가 아니면(남이 다른 칸을 고침) = 파일 통째 SKIP(행 지문 판정 0)"
has "$out" "CLEANUP-RESTORE RESTORED=0 SKIPPED=2" "ⓢ ⓖ4 그 파일의 행 2개(보관 a · 다시 쓴 b) 모두 SKIP — 남의 수정을 덮지 않는다"
has "$(cat "$P/.fable-team/seats-x.json")" '"index": "design/teams/x/indices/진행/b.md"' "ⓢ ⓖ4 SKIP 이면 새 경로 그대로(안 되돌림)"
has "$(cat "$P/.fable-team/seats-x.json")" '"worktree": "otherwt"' "ⓢ ⓖ4 남의 수정 그대로"
hasnt "$(cat "$P/.fable-team/seats-x.json")" '"byz-x-nano-a#0"' "ⓢ ⓖ4 보관 행도 그대로 빠진 채(일부만 되살리지 않는다)"
cp -R "$T/probe0" "$T/probe2"
PR "$T/probe2" "$T/pp2" plan >/dev/null
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p,encoding="utf-8"));d["byz-x-nano-a#0"]["index"]="design/x/indices/진행/moved.md";open(p,"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")' "$T/probe2/.fable-team/seats-x.json"
out="$(PR "$T/probe2" "$T/pp2" run "$(plan_sha "$T/pp2/plan.json")")"
has "$out" "SKIP byz-x-nano-a#0 행이 없거나 바뀜" "ⓖ3 계획 뒤 행이 바뀌면 = SKIP(읽은 판 ≠ 쓰는 판)"
has "$out" "CLEANUP-RUN ARCHIVED=0 REWROTE=1 SKIPPED=1" "ⓖ3 바뀐 행만 SKIP · 나머지는 그대로 진행"

echo "== ⓖ 반례 5 — «./» · 따옴표 안 공백 정규화 · 허용 목록은 코드 확장자에 효력 0"
printf 'P = "./design/x/a.md"\n' > "$R/scripts/dot.py"
printf 'P = "  design/x/a.md  "\n' > "$R/scripts/sp.py"
printf 'P = "design/x/a.md"\n' > "$R/tests/fixtures/code.py"
GITC "$R" add -A >/dev/null 2>&1; GITC "$R" commit -q -m norm
printf '# r899\ntests/fixtures/f.json\t고정 입력 데이터\ntests/fixtures/code.py\t코드 파일은 예외 0\n' > "$R/design/TEAM-MOVE-ALLOW.tsv"
out="$(TM --classify x)"
has "$out" "CLS CODE-RUN x code scripts/dot.py:1" "ⓖ5 앞 «./» 를 지우고 판정 → CODE-RUN"
has "$out" "CLS CODE-RUN x code scripts/sp.py:1" "ⓖ5 따옴표 안 앞뒤 공백을 지우고 판정 → CODE-RUN"
out="$(TM --verify x)"
has "$out" "ERR x 코드 옛 경로 design/x/ : tests/fixtures/code.py:1 (CODE-RUN)" "ⓖ5 허용 목록에 있어도 코드 파일은 ERR"
has "$out" "ERR x 코드 옛 경로 design/x/ : scripts/dot.py:1 (CODE-RUN)" "ⓖ5 «./» 경로도 실행 글자 = ERR"

echo "== ⓖ 변이 5개 — 각 고침을 끄면 그 칸이 빨강"
mkG() { rm -rf "$T/g$1"; mkdir -p "$T/g$1"; cp "$SRC"/ft-team-move.sh "$SRC"/ft_team_move*.py "$SRC"/ft-team-lib.sh "$SRC"/ft-team-map-lint.sh "$SRC"/ft-team-upgrade.sh "$T/g$1/"; }
mut() { python3 -I -c 'import sys;p,a,b=sys.argv[1:4];s=open(p,encoding="utf-8").read();assert s.count(a)==1,"조각 %d회" % s.count(a);open(p,"w",encoding="utf-8").write(s.replace(a,b))' "$1" "$2" "$3"; }
mkG 1; mut "$T/g1/ft_team_move_cleanup.py" 'd, t0 = p.with_name(p.name + ".lock.d"), time.time()' 'd, t0 = p.with_name(p.name + ".lock.d.%d" % os.getpid()), time.time()'
mkdir -p "$LK"; echo $$ > "$LK/pid"
gout="$(FT_REPO_ROOT="$R" FT_PROJECT_ROOT="$R" FAKE_SESSIONS="$T/live.txt" PATH="$T/fake:$PATH" bash "$T/g1/ft-team-move.sh" --cleanup-run "$T/p4/plan.json" --plan-sha "$sha4" 2>&1)"
hasnt "$gout" "REJECT 잠금" "ⓖ 변이1 잠금 끔 → 남이 쓰는 중에도 안 막힘(빨강 — 위 REJECT 칸이 잡는다)"
rm -rf "$LK"
mkG 2; mut "$T/g2/ft_team_move_cleanup.py" '    pb = plan_path.read_bytes()' '    plan_path.read_text()
    pb = plan_path.read_bytes()'
cp -R "$T/probe0" "$T/probe3"; PR "$T/probe3" "$T/pp3" plan >/dev/null
gout="$(BIN="$T/g2" PR "$T/probe3" "$T/pp3" run "$(plan_sha "$T/pp3/plan.json")")"
has "$gout" "READS plan_bytes=1 plan_text=1" "ⓖ 변이2 계획 두 번 읽기 → plan_text=1(빨강 — 위 1회 칸이 잡는다)"
mkG 3; mut "$T/g3/ft_team_move_cleanup.py" '    items = collect(ctx, arg)   # 반례 3: 분류와 행 지문이 «한 판» 에서 나온다(명부를 다시 읽지 않는다)' '    items = collect(ctx, arg)
    for i in [i for i in items if i["store"] in FIELD]:
        json.loads(Path(i["file"]).read_text(encoding="utf-8"))   # 변이: 다시 읽기'
cp -R "$T/probe0" "$T/probe4"
gout="$(BIN="$T/g3" PR "$T/probe4" "$T/pp4" plan)"
has "$gout" "READS plan_bytes=1 plan_text=0 roster_bytes=0 roster_text=3" "ⓖ 변이3 지문용 명부 재읽기 → roster_text=3(빨강)"
mkG 4; mut "$T/g4/ft_team_move_cleanup.py" '    if cs == m["new_sha"]:   # 교체 직후 바이트 그대로 — CAS 로 원본 바이트를 되돌린다' '    if cs != m["b1_sha"]:   # 변이: 교체 전만 아니면 되살림'
cp -R "$T/probe0" "$T/probe5"
BIN="$T/g4" PR "$T/probe5" "$T/pp5" plan >/dev/null
gout="$(BIN="$T/g4" PR "$T/probe5" "$T/pp5" run "$(plan_sha "$T/pp5/plan.json")")"
garch="$(printf '%s' "$gout" | sed -n 's/.*archive=//p')"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p,encoding="utf-8"));d["byz-x-nano-b#0"]["worktree"]="otherwt";open(p,"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")' "$T/probe5/.fable-team/seats-x.json"
gout="$(BIN="$T/g4" PR "$T/probe5" "$T/pp5" restore "$garch")"
hasnt "$gout" "또 바뀜" "ⓢ 변이4 현재 바이트 판정을 «교체 전만 아니면 되살림» 으로 → 남의 수정을 덮음(빨강 — 위 ⓖ4 칸이 잡는다)"
mkG 5; mut "$T/g5/ft_team_move_classify.py" '    t = re.sub(rf"\./design/{re.escape(team)}/", f"design/{team}/", text)' '    return text'
gout="$(BIN="$T/g5" TM --classify x)"
hasnt "$gout" "CLS CODE-RUN x code scripts/dot.py:1" "ⓖ 변이5 정규화 끔 → «./» 경로를 RUN 으로 못 봄(빨강)"


echo "== ⓗ 반례 r3 — 동시 쓰기: 교체 직전 B2 가 다르면 교체 0(다른 파일은 계속)"
cat > "$T/probe2.py" <<'PY'
import json, os, shutil, sys, threading, time
from pathlib import Path
src, repo, mode = sys.argv[1:4]
sys.path.insert(0, src)
import ft_team_move as tm, ft_team_move_cleanup as cu
target = Path(repo) / ".fable-team" / "seats-x.json"
lockd = target.with_name(target.name + ".lock.d")
for _p in target.parent.glob("*.lock.d.tmp.*"):   # 앞 시험이 남긴 잠금 임시 폴더 정리
    shutil.rmtree(_p, ignore_errors=True)


def band_write():   # 대역 = spawn 이 그 사이 새 좌석 행을 쓴 것
    d = json.loads(target.read_text(encoding="utf-8"))
    d["byz-x-nano-new#0"] = {"role": "nano", "index": "design/teams/x/indices/진행/b.md"}
    target.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def readd() -> dict:
    return json.loads(target.read_text(encoding="utf-8"))


if mode in ("run-race", "restore-race", "window"):
    plan = Path(sys.argv[4])
    fired, reads, wins = [], [], []
    _fs, _rb, _rp = shutil.copymode, Path.read_bytes, os.replace

    def fs(*a, **k):   # r5: 보관 기록 fsync 가 앞에 생겼으므로 «B1 뒤 · B2 앞» 은 copymode(tmp 쓰기 직후)에서 끼운다
        if mode != "window" and not fired:
            fired.append(1)
            band_write()
        return _fs(*a, **k)

    def rb(self):
        v = _rb(self)
        reads.append((str(self), time.perf_counter()))
        return v

    def rp(a, b):
        for path, t in reversed(reads):
            if path == str(b):
                wins.append((time.perf_counter() - t) * 1e6)
                break
        return _rp(a, b)

    shutil.copymode, Path.read_bytes, os.replace = fs, rb, rp
    ctx = tm.Ctx(Path(repo), Path(repo), {"x": "design/teams/x/"})
    try:
        if mode == "run-race":
            rc = cu.cmd_run(ctx, plan, sys.argv[5])
        elif mode == "restore-race":
            rc = cu.cmd_restore(ctx, plan)
        else:
            rc = cu.cmd_run(ctx, plan, sys.argv[5])
    finally:
        shutil.copymode, Path.read_bytes, os.replace = _fs, _rb, _rp
    d = readd()
    if mode == "window":
        print("WINDOW n=%d max_us=%.0f med_us=%.0f" % (len(wins), max(wins or [0]), sorted(wins or [0])[len(wins or [0]) // 2]))
    else:
        print("RACE rc=%d new_row=%d b_index=%s a_row=%d"
              % (rc, int("byz-x-nano-new#0" in d), d.get("byz-x-nano-b#0", {}).get("index", "-"), int("byz-x-nano-a#0" in d)))
elif mode in ("done-fail", "pend-fail"):   # r5: 보관 기록 쓰기 실패 주입
    import contextlib, io
    ctx = tm.Ctx(Path(repo), Path(repo), {"x": "design/teams/x/"})
    buf, _da = io.StringIO(), cu.dump_arch

    def da(path, rec):
        st = [m["status"] for m in rec.get("files", {}).values()]
        if (mode == "done-fail" and st and all(x == "done" for x in st)) or (mode == "pend-fail" and "pending" in st):
            raise PermissionError("주입: 보관 기록 쓰기 거부")   # done-fail = «done 표시» 쓰기만 · pend-fail = «pending 기록» 쓰기
        return _da(path, rec)
    cu.dump_arch = da
    try:
        with contextlib.redirect_stdout(buf):
            rc = cu.cmd_run(ctx, Path(sys.argv[4]), sys.argv[5])
    finally:
        cu.dump_arch = _da
    sys.stdout.write(buf.getvalue())
    print("ARCHFAIL rc=%d tmp_left=%d" % (rc, len(list(Path(repo).rglob("*.r899tmp")))))
elif mode in ("tmux-race", "ncb-race", "perm-race"):   # r4: 비교~교체 사이에 끼는 쓰기
    import contextlib, io
    import ft_team_move_classify as cl
    ctx = tm.Ctx(Path(repo), Path(repo), {"x": "design/teams/x/"})
    ncb = Path(repo) / ".fable-team" / "state" / "nano-card-base"
    fired, buf = [], io.StringIO()
    if mode == "tmux-race":   # ⓚ tmux 조회 도중(B1 뒤 · B2 앞) 새 행 추가
        _lv = cl.live_sessions

        def lv(run, err):
            v = _lv(run, err)
            if not fired:
                fired.append(1)
                band_write()
            return v
        cl.live_sessions = lv
    if mode == "ncb-race":   # ⓜ 되살림 대상 자리에 경쟁 새 파일(없음 확인 뒤 · 만들기 전)
        _ln = os.link

        def ln(a, b, *x, **k):
            if not fired and str(b).endswith("d9#0.json"):
                fired.append(1)
                Path(b).write_text('{"competitor": 1}\n', encoding="utf-8")
            return _ln(a, b, *x, **k)
        os.link = ln
    if mode == "perm-race":   # ⓝ 두 번째 파일 교체 직전 PermissionError
        _rp2 = os.replace

        def rp2(a, b, *x, **k):
            if str(b).endswith("b#0.json") and "nano-card-base" in str(b):
                raise PermissionError("주입: 두 번째 파일 교체 거부")
            return _rp2(a, b, *x, **k)
        os.replace = rp2
    try:
        with contextlib.redirect_stdout(buf):
            rc = cu.cmd_restore(ctx, Path(sys.argv[4])) if mode == "ncb-race" else cu.cmd_run(ctx, Path(sys.argv[4]), sys.argv[5])
    finally:
        if mode == "ncb-race":
            os.link = _ln
        if mode == "perm-race":
            os.replace = _rp2
    sys.stdout.write(buf.getvalue())
    tmp_left = len(list(target.parent.rglob("*.r899tmp")))
    if mode == "ncb-race":
        dst = ncb / "byz-x-nano-d9#0.json"
        print("NCBRACE rc=%d dst_competitor=%d kept_left=%d tmp_left=%d"
              % (rc, int("competitor" in dst.read_text(encoding="utf-8")), len(list(Path(sys.argv[4]).parent.glob("ncb/*.json"))), tmp_left))
    elif mode == "perm-race":
        ar = [l for l in buf.getvalue().splitlines() if "archive=" in l][-1].split("archive=")[1]
        rec = json.loads(Path(ar).read_text(encoding="utf-8"))
        dn = {f for f, m in rec["files"].items() if m["status"] == "done"}   # r5: pending 은 «교체된 파일» 만 done
        print("PERM rc=%d arch_roster=%d arch_rewrite=%d ncb_card=%s tmp_left=%d"
              % (rc, sum(1 for r in rec["roster"] if r["file"] in dn), sum(1 for r in rec["rewrite"] if r["file"] in dn),
                 json.loads((ncb / "byz-x-nano-b#0.json").read_text(encoding="utf-8"))["card_path"], tmp_left))
    else:
        d = readd()
        print("TMUXRACE rc=%d new_row=%d b_index=%s a_row=%d tmp_left=%d"
              % (rc, int("byz-x-nano-new#0" in d), d.get("byz-x-nano-b#0", {}).get("index", "-"), int("byz-x-nano-a#0" in d), tmp_left))
elif mode == "emptylock":
    seen, _wt = [0], Path.write_text

    def wt(self, *a, **k):
        if self.name == "pid" and lockd.exists() and not (lockd / "pid").is_file():
            seen[0] += 1   # pid 가 없는 잠금 폴더가 보이면 «빈 잠금 창»
        return _wt(self, *a, **k)

    Path.write_text = wt
    try:
        lock = cu.acquire(target)
        pid_ok = (lock / "pid").is_file()
        cu.release(lock)
    finally:
        Path.write_text = _wt
    print("LOCK empty_window=%d pid_ok=%d lock_left=%d tmp_left=%d"
          % (seen[0], int(pid_ok), int(lockd.exists()), len(list(target.parent.glob("*.lock.d.tmp.*")))))
elif mode == "reapfail":
    lockd.mkdir(parents=True, exist_ok=True)
    (lockd / "pid").write_text("999999", encoding="utf-8")   # 죽은 pid + 회수 영구 실패
    _rm = shutil.rmtree
    shutil.rmtree = lambda *a, **k: None
    res, el = ["HANG"], [0.0]

    def work():
        t0 = time.time()
        try:
            cu.acquire(target, 5.0)
            res[0] = "ACQUIRED"
        except tm.MoveError:
            res[0] = "REJECT"
        except BaseException as e:   # noqa: BLE001
            res[0] = "ERROR:" + type(e).__name__
        el[0] = time.time() - t0

    th = threading.Thread(target=work, daemon=True)
    th.start()
    th.join(15)
    shutil.rmtree = _rm
    _rm(lockd, ignore_errors=True)
    print("LOCK result=%s over5=%d under7=%d" % (res[0], int(el[0] >= 5.0), int(el[0] < 7.0)))
else:   # pidfail
    _wt = Path.write_text

    def boom(self, *a, **k):
        if self.name == "pid":
            raise OSError("주입: pid 쓰기 실패")
        return _wt(self, *a, **k)

    Path.write_text = boom
    try:
        try:
            cu.acquire(target)
            res = "ACQUIRED"
        except tm.MoveError:
            res = "REJECT"
        except BaseException as e:   # noqa: BLE001
            res = "ERROR:" + type(e).__name__
    finally:
        Path.write_text = _wt
    print("LOCK result=%s lock_left=%d tmp_left=%d"
          % (res, int(lockd.exists()), len(list(target.parent.glob("*.lock.d.tmp.*")))))
PY
P2() { local repo="$1"; shift; FT_REPO_ROOT="$repo" FT_TEAM_MOVE_STATE="$T/ps-$(basename "$repo")" FAKE_SESSIONS="$T/plive.txt" PATH="$T/fake:$PATH" \
  python3 -I "$T/probe2.py" "${BIN:-$SRC}" "$repo" "$@"; }
cp -R "$T/probe0" "$T/probe6"; PR "$T/probe6" "$T/pp6" plan >/dev/null
out="$(P2 "$T/probe6" run-race "$T/pp6/plan.json" "$(plan_sha "$T/pp6/plan.json")")"; rc=$?
has "$out" "SKIP byz-x-nano-a#0 바뀜 — 다시 실행" "ⓗ 교체 직전 B2 가 다르면 SKIP(다시 실행)"
has "$out" "RACE rc=1 new_row=1 b_index=design/x/indices/진행/b.md a_row=1" "ⓗ 그 파일 교체 0(새 행 남음 · a#0 남음 · 다른 행도 안 건드림) · rc1"
eq "$rc" 0 "ⓗ 시험 자체는 정상 종료"

echo "== ⓘ 되살림도 같은 CAS — 교체 0"
cp -R "$T/probe0" "$T/probe7"; PR "$T/probe7" "$T/pp7" plan >/dev/null
out="$(PR "$T/probe7" "$T/pp7" run "$(plan_sha "$T/pp7/plan.json")")"
arch7="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
out="$(P2 "$T/probe7" restore-race "$arch7")"
has "$out" "SKIP seats-x.json 바뀜 — 다시 실행" "ⓘ 되살림도 교체 직전 B2 비교 → SKIP"
has "$out" "RACE rc=1 new_row=1 b_index=design/teams/x/indices/진행/b.md a_row=0" "ⓛ 같은 파일 2행(보관 a · 다시 쓴 b) 되살림 · tmp 쓰기 뒤 새 행 → 그 파일 교체 0(둘 다 그대로) · rc1"
has "$out" "CLEANUP-RESTORE RESTORED=0 SKIPPED=2" "ⓛ 파일 통째 교체 0 — 그 파일의 행 둘 다 SKIP"

echo "== ⓙ 잠금 3건 — 빈 잠금 창 0 · 회수 실패에도 5초 상한 · pid 쓰기 실패 잔류 0"
out="$(P2 "$T/probe0" emptylock)"
has "$out" "LOCK empty_window=0 pid_ok=1 lock_left=0 tmp_left=0" "ⓙ 빈 잠금 폴더 관측 0(rename 잠금) · 잔류 0"
out="$(P2 "$T/probe0" reapfail)"
has "$out" "LOCK result=REJECT over5=1 under7=1" "ⓙ 회수 영구 실패 → 5초 넘고 7초 안에 REJECT(상한 우회 0)"
out="$(P2 "$T/probe0" pidfail)"
has "$out" "LOCK result=REJECT lock_left=0 tmp_left=0" "ⓙ pid 쓰기 실패 → 잠금 폴더 잔류 0"
out="$(P2 "$T/probe6" window "$T/pp6/plan.json" "$(plan_sha "$T/pp6/plan.json")")"
has "$out" "WINDOW n=" "ⓙ 남는 창(2회 읽기 → os.replace) 크기 측정"
printf '%s\n' "$out" | grep '^WINDOW' >> "$T/window.txt"
for n in $(seq 1 20); do   # r4 — run 이 «실제로 부르는» 경로에서 B2 읽기 → os.replace 사이 시간 20회
  cp -R "$T/probe0" "$T/pw$n"; PR "$T/pw$n" "$T/ppw$n" plan >/dev/null
  P2 "$T/pw$n" window "$T/ppw$n/plan.json" "$(plan_sha "$T/ppw$n/plan.json")" | grep '^WINDOW'
done | sed -n 's/.*max_us=\([0-9]*\) med_us=\([0-9]*\).*/\1/p' | sort -n | awk '{a[NR]=$1} END{printf "WINDOW20 runs=%d med_us=%d p95_us=%d max_us=%d\n", NR, a[int((NR+1)/2)], a[int(NR*0.95+0.5)], a[NR]}' | tee -a "$T/window.txt"

echo "== ⓚ r4 — tmux 조회 도중(B1 뒤 · B2 앞) 새 행 → 그 파일 교체 0 · 보관 기록 0 · tmp 0"
cp -R "$T/probe0" "$T/probe9"; PR "$T/probe9" "$T/pp9" plan >/dev/null
out="$(P2 "$T/probe9" tmux-race "$T/pp9/plan.json" "$(plan_sha "$T/pp9/plan.json")")"
has "$out" "SKIP byz-x-nano-a#0 바뀜 — 다시 실행" "ⓚ tmux 조회 사이 새 행 → B2 가 잡아 SKIP"
has "$out" "TMUXRACE rc=1 new_row=1 b_index=design/x/indices/진행/b.md a_row=1 tmp_left=0" "ⓚ 교체 0(새 행 남음 · a 남음 · b 그대로) · rc1 · tmp 0"
has "$out" "CLEANUP-RUN ARCHIVED=0 REWROTE=0 SKIPPED=2" "ⓚ 보관 기록 0(교체 안 된 파일 행은 안 적음)"

echo "== ⓜ r4 — 기록 파일 되살림: 경쟁 새 파일이 있으면 덮어쓰기 0 · rc1"
cp -R "$T/probe0" "$T/probe11"
printf '{\n  "name": "byz-x-nano-d9#0",\n  "card_path": "design/teams/x/indices/진행/gone9.md",\n  "worktree": "%s"\n}\n' "$T/probe11/.worktrees/nanowt" > "$T/probe11/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json"
PR "$T/probe11" "$T/pp11" plan >/dev/null
out="$(PR "$T/probe11" "$T/pp11" run "$(plan_sha "$T/pp11/plan.json")")"
arch11="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
[ -e "$T/probe11/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json" ] && bad "ⓜ 사전: d9 가 보관으로 안 감" || ok "ⓜ 사전: d9 보관 이동"
out="$(P2 "$T/probe11" ncb-race "$arch11")"
has "$out" "SKIP byz-x-nano-d9#0.json 바뀜 — 다시 실행" "ⓜ 되살림 직전 새 파일 → SKIP(다시 실행)"
has "$out" "NCBRACE rc=1 dst_competitor=1 kept_left=1 tmp_left=0" "ⓜ 경쟁 새 파일 덮어쓰기 0 · 보관본 그대로 · rc1"

echo "== ⓝ r4 — 두 번째 파일 교체 직전 PermissionError → 보관 기록엔 첫 파일만 · tmp 0"
cp -R "$T/probe0" "$T/probe12"
printf '{\n  "name": "byz-x-nano-b#0",\n  "card_path": "design/x/indices/진행/b.md",\n  "worktree": "%s"\n}\n' "$T/probe12/.worktrees/nanowt" > "$T/probe12/.fable-team/state/nano-card-base/byz-x-nano-b#0.json"
PR "$T/probe12" "$T/pp12" plan >/dev/null
out="$(P2 "$T/probe12" perm-race "$T/pp12/plan.json" "$(plan_sha "$T/pp12/plan.json")")"
has "$out" "SKIP byz-x-nano-b#0 교체 실패" "ⓝ 교체 거부 → 그 파일 SKIP"
has "$out" "PERM rc=1 arch_roster=1 arch_rewrite=1 ncb_card=design/x/indices/진행/b.md tmp_left=0" "ⓝ 보관 기록 = 첫 파일(명부)만 · 둘째 파일 원본 그대로 · tmp 0 · rc1"

arch12="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
out="$(PR "$T/probe12" "$T/pp12" restore "$arch12")"
has "$out" "SKIP byz-x-nano-b#0.json 교체 안 됨(pending)" "ⓠ pending 인데 교체 안 됨(PermissionError) → restore SKIP(현재 바이트 = 교체 전)"
has "$out" "CLEANUP-RESTORE RESTORED=2 SKIPPED=1" "ⓠ 교체된 첫 파일(보관 1 + 다시 쓴 1)만 되살림 · 안 된 파일 SKIP"
has "$(cat "$T/probe12/.fable-team/state/nano-card-base/byz-x-nano-b#0.json")" '"card_path": "design/x/indices/진행/b.md"' "ⓠ 교체 안 된 파일 = 원본 그대로"

echo "== ⓞ r5 — 교체 성공 뒤 «done 표시» 쓰기 PermissionError → WARN rc1 · restore 가 현재 바이트로 되살림(바이트 = 원본)"
cp -R "$T/probe0" "$T/probe16"; before16="$(shasum "$T/probe16/.fable-team/seats-x.json")"
PR "$T/probe16" "$T/pp16" plan >/dev/null
out="$(P2 "$T/probe16" done-fail "$T/pp16/plan.json" "$(plan_sha "$T/pp16/plan.json")")"
has "$out" "WARN seats-x.json done 표시 실패" "ⓞ done 표시 실패 = WARN 1줄"
has "$out" "ARCHFAIL rc=1 tmp_left=0" "ⓞ rc1 · tmp 0"
hasnt "$(cat "$T/probe16/.fable-team/seats-x.json")" '"byz-x-nano-a#0"' "ⓞ 사전: 교체는 이미 일어남(a 가 명부에서 빠짐)"
arch16="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
has "$(cat "$arch16")" '"status": "pending"' "ⓞ 디스크 기록은 pending 으로 남음(done 표시 안 써짐)"
out="$(PR "$T/probe16" "$T/pp16" restore "$arch16")"
has "$out" "CLEANUP-RESTORE RESTORED=2 SKIPPED=0" "ⓞ pending 이어도 현재 바이트 = new_sha → 되살림 2"
eq "$(shasum "$T/probe16/.fable-team/seats-x.json")" "$before16" "ⓞ 되살린 명부 바이트 = 원본"

echo "== ⓟ r5 — pending 기록 쓰기 실패 → 그 파일 교체 0(기록 없는 교체 불가)"
cp -R "$T/probe0" "$T/probe17"; before17="$(shasum "$T/probe17/.fable-team/seats-x.json")"
PR "$T/probe17" "$T/pp17" plan >/dev/null
out="$(P2 "$T/probe17" pend-fail "$T/pp17/plan.json" "$(plan_sha "$T/pp17/plan.json")")"
has "$out" "SKIP byz-x-nano-a#0 보관 기록 실패" "ⓟ pending 기록 실패 → SKIP"
has "$out" "CLEANUP-RUN ARCHIVED=0 REWROTE=0 SKIPPED=2" "ⓟ 교체 0 · 보관 0"
has "$out" "ARCHFAIL rc=1 tmp_left=0" "ⓟ rc1 · tmp 0"
eq "$(shasum "$T/probe17/.fable-team/seats-x.json")" "$before17" "ⓟ 명부 바이트 그대로"

echo "== ⓡⓢⓣ r6 — restore = 파일 통째 · 바이트 · 보관본 sha 검증(JSON 재생성 0)"
cp -R "$T/probe0" "$T/probe21"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p,encoding="utf-8"));d["_note"]="한글 머리 칸";open(p,"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=True,indent=4,sort_keys=True))' "$T/probe21/.fable-team/seats-x.json"
before21="$(shasum "$T/probe21/.fable-team/seats-x.json")"
PR "$T/probe21" "$T/pp21" plan >/dev/null
out="$(P2 "$T/probe21" done-fail "$T/pp21/plan.json" "$(plan_sha "$T/pp21/plan.json")")"
arch21="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
[ "$(shasum "$T/probe21/.fable-team/seats-x.json")" = "$before21" ] && bad "ⓡ 사전: 교체가 일어나야 함" || ok "ⓡ 사전: 4칸 들여쓰기·\\u 이스케이프 명부가 교체됨(형식이 바뀜)"
out="$(PR "$T/probe21" "$T/pp21" restore "$arch21")"
has "$out" "RESTORE rc=0" "ⓡ restore rc0"
eq "$(shasum "$T/probe21/.fable-team/seats-x.json")" "$before21" "ⓡ 4칸 들여쓰기·sort_keys·\\u 이스케이프 명부 → run → done 기록 실패 → restore → 바이트 동일"

echo "== ⓢ r6 — B2 불일치로 교체 0 → 남이 행을 고침 → restore SKIP «또 바뀜» rc1 · 남의 수정 그대로"
cp -R "$T/probe0" "$T/probe22"; PR "$T/probe22" "$T/pp22" plan >/dev/null
out="$(P2 "$T/probe22" run-race "$T/pp22/plan.json" "$(plan_sha "$T/pp22/plan.json")")"
arch22="$(printf '%s' "$out" | sed -n 's/.*archive=//p')"
has "$out" "SKIP byz-x-nano-a#0 바뀜 — 다시 실행" "ⓢ 사전: B2 불일치로 교체 0"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p,encoding="utf-8"));d["byz-x-nano-a#0"]["index"]="design/teams/x/indices/진행/others.md";open(p,"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")' "$T/probe22/.fable-team/seats-x.json"
before22="$(shasum "$T/probe22/.fable-team/seats-x.json")"
out="$(PR "$T/probe22" "$T/pp22" restore "$arch22")"
has "$out" "SKIP seats-x.json 또 바뀜" "ⓢ 교체 안 된 pending 을 행 지문으로 되살리지 않는다 → 또 바뀜 SKIP"
has "$out" "RESTORE rc=1" "ⓢ rc1"
eq "$(shasum "$T/probe22/.fable-team/seats-x.json")" "$before22" "ⓢ 남의 수정 그대로(덮어쓰기 0)"

echo "== ⓣ r6 — 보관본 없음·손상 = ERROR rc1 · 대상 그대로 (replace·move 둘 다)"
mkT() { cp -R "$T/probe0" "$T/probe$1"
  printf '{\n  "name": "byz-x-nano-d9#0",\n  "card_path": "design/teams/x/indices/진행/gone9.md",\n  "worktree": "%s"\n}\n' "$T/probe$1/.worktrees/nanowt" > "$T/probe$1/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json"
  PR "$T/probe$1" "$T/pp$1" plan >/dev/null
  PR "$T/probe$1" "$T/pp$1" run "$(plan_sha "$T/pp$1/plan.json")" | sed -n 's/.*archive=//p'; }
arch23="$(mkT 23)"; D9="$T/probe23/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json"; RS="$T/probe23/.fable-team/seats-x.json"
[ -e "$D9" ] && bad "ⓣ 사전: d9 가 보관으로 감" || ok "ⓣ 사전: d9 보관 이동 · 명부 교체"
before23="$(shasum "$RS")"
for k in "$(dirname "$arch23")"/orig/* "$(dirname "$arch23")"/ncb/*; do mv "$k" "$k.gone"; done   # 보관본 없음 흉내(이름만 바꿈 · replace=orig/ · move=ncb/ 한 벌씩)
out="$(PR "$T/probe23" "$T/pp23" restore "$arch23")"
has "$out" "ERROR seats-x.json 보관본 없음" "ⓣ replace: 보관본 없음 = ERROR (조용한 SKIP rc0 아님)"
has "$out" "ERROR byz-x-nano-d9#0.json 보관본 없음" "ⓣ move: 보관본 없음 = ERROR"
has "$out" "RESTORE rc=1" "ⓣ 보관본 없음 rc1"
[ -e "$D9" ] && bad "ⓣ 보관본 없음인데 d9 를 만들었다" || ok "ⓣ move: 대상 그대로(없음)"
eq "$(shasum "$RS")" "$before23" "ⓣ replace: 대상 그대로"
arch24="$(mkT 24)"; D9="$T/probe24/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json"; RS="$T/probe24/.fable-team/seats-x.json"
before24="$(shasum "$RS")"
for k in "$(dirname "$arch24")"/orig/* "$(dirname "$arch24")"/ncb/*; do printf 'x' >> "$k"; done
out="$(PR "$T/probe24" "$T/pp24" restore "$arch24")"
has "$out" "ERROR seats-x.json 보관본 손상" "ⓣ replace: 보관본 손상 = ERROR"
has "$out" "ERROR byz-x-nano-d9#0.json 보관본 손상" "ⓣ move: 보관본 손상 = ERROR"
has "$out" "RESTORE rc=1" "ⓣ 보관본 손상 rc1"
[ -e "$D9" ] && bad "ⓣ 손상 보관본으로 d9 를 만들었다" || ok "ⓣ move: 대상 그대로(없음)"
eq "$(shasum "$RS")" "$before24" "ⓣ replace: 대상 그대로"

echo "== ⓣ' r7 — 항목당 보관본 «한 경로»: ncb 항목은 ncb/ 에 «실제로» 있고 메타 kept 가 그 경로 · ncb/ 만 없음·손상 → ERROR rc1"
arch27="$(mkT 27)"; D9="$T/probe27/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json"; RS="$T/probe27/.fable-team/seats-x.json"
kept27="$(python3 -I -c 'import json,sys;m=json.load(open(sys.argv[1],encoding="utf-8"))["files"];print([v["kept"] for k,v in m.items() if v["kind"]=="move"][0])' "$arch27")"
eq "$kept27" "$(dirname "$arch27")/ncb/byz-x-nano-d9#0.json" "ⓣ' move 항목 메타 kept = 실제로 쓴 ncb/ 경로(orig/ 아님)"
[ -f "$kept27" ] && ok "ⓣ' 그 경로에 보관본 실재" || bad "ⓣ' 그 경로에 보관본 없음"
[ -e "$(dirname "$arch27")/orig/"*"-byz-x-nano-d9#0.json" ] 2>/dev/null && bad "ⓣ' 같은 파일을 orig/ 에도 또 썼다(보관본 1벌 아님)" || ok "ⓣ' orig/ 에 move 항목 사본 0(보관본 1벌)"
mv "$kept27" "$kept27.gone"; before27="$(shasum "$RS")"
out="$(PR "$T/probe27" "$T/pp27" restore "$arch27")"
has "$out" "ERROR byz-x-nano-d9#0.json 보관본 없음" "ⓣ' ncb/ 만 없음 → ERROR"
has "$out" "RESTORE rc=1" "ⓣ' ncb/ 만 없음 → rc1"
[ -e "$D9" ] && bad "ⓣ' ncb/ 없는데 d9 를 만들었다" || ok "ⓣ' ncb/ 없음 → 대상 그대로(없음)"
arch28="$(mkT 28)"; D9="$T/probe28/.fable-team/state/nano-card-base/byz-x-nano-d9#0.json"
printf 'x' >> "$(dirname "$arch28")/ncb/byz-x-nano-d9#0.json"
out="$(PR "$T/probe28" "$T/pp28" restore "$arch28")"
has "$out" "ERROR byz-x-nano-d9#0.json 보관본 손상" "ⓣ' ncb/ 만 손상 → ERROR"
has "$out" "RESTORE rc=1" "ⓣ' ncb/ 만 손상 → rc1"
[ -e "$D9" ] && bad "ⓣ' 손상 ncb/ 로 d9 를 만들었다" || ok "ⓣ' ncb/ 손상 → 대상 그대로(없음)"

echo "== ⓗⓘⓙ 변이 3개 — CAS 끔 · rename 잠금 끔 · 마감 검사 끔"
mkG 6; mut "$T/g6/ft_team_move_cleanup.py" '        if hashlib.sha256(p.read_bytes()).hexdigest() != sha1:   # B2' '        if False:   # B2'
cp -R "$T/probe0" "$T/probe8"; PR "$T/probe8" "$T/pp8" plan >/dev/null
gout="$(BIN="$T/g6" P2 "$T/probe8" run-race "$T/pp8/plan.json" "$(plan_sha "$T/pp8/plan.json")")"
hasnt "$gout" "바뀜 — 다시 실행" "ⓖ 변이6 CAS 비교 끔 → 동시 쓰기를 덮어씀(빨강 — 위 ⓗ 칸이 잡는다)"
mkG 7; mut "$T/g7/ft_team_move_cleanup.py" '            os.rename(tmp, d)
            return d' '            shutil.rmtree(tmp, ignore_errors=True)
            d.mkdir()
            (d / "pid").write_text(str(os.getpid()), encoding="utf-8")
            return d'
gout="$(BIN="$T/g7" P2 "$T/probe0" emptylock)"
hasnt "$gout" "empty_window=0" "ⓖ 변이7 rename 잠금 끔 → 빈 잠금 창이 보임(빨강)"
mkG 8; mut "$T/g8/ft_team_move_cleanup.py" '        if time.time() - t0 > wait:' '        if False:'
gout="$(BIN="$T/g8" P2 "$T/probe0" reapfail)"
hasnt "$gout" "result=REJECT over5=1" "ⓖ 변이8 마감 검사 끔 → 회수 실패에서 상한 우회(빨강)"
mkG 9; mut "$T/g9/ft_team_move_cleanup.py" '        live = cl.live_sessions(tm.run, tm.MoveError)   # 못 읽으면 이 파일만 SKIP · tmp 만들기 전' '        live = {"x-never-live"}'
mut "$T/g9/ft_team_move_cleanup.py" '        os.replace(tmp, p)   # B2 바로 다음 줄' '        cl.live_sessions(tm.run, tm.MoveError)
        os.replace(tmp, p)'
cp -R "$T/probe0" "$T/probe13"; PR "$T/probe13" "$T/pp13" plan >/dev/null
gout="$(BIN="$T/g9" P2 "$T/probe13" tmux-race "$T/pp13/plan.json" "$(plan_sha "$T/pp13/plan.json")")"
hasnt "$gout" "TMUXRACE rc=1 new_row=1" "ⓚ 변이9 B2 와 교체 사이에 tmux 호출 → 새 행 덮어씀(빨강 — 위 ⓚ 칸이 잡는다)"
mkG 10; mut "$T/g10/ft_team_move_cleanup.py" '            why = cas_replace(p, orig, cs)' '            why = cas_replace(p, dump_like(orig.decode("utf-8"), json.loads(orig)), cs)'
cp -R "$T/probe0" "$T/probe14"
python3 -I -c 'import json,sys;p=sys.argv[1];d=json.load(open(p,encoding="utf-8"));open(p,"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=True,indent=4,sort_keys=True))' "$T/probe14/.fable-team/seats-x.json"
before14="$(shasum "$T/probe14/.fable-team/seats-x.json")"
PR "$T/probe14" "$T/pp14" plan >/dev/null
gout="$(P2 "$T/probe14" done-fail "$T/pp14/plan.json" "$(plan_sha "$T/pp14/plan.json")")"
BIN="$T/g10" PR "$T/probe14" "$T/pp14" restore "$(printf '%s' "$gout" | sed -n 's/.*archive=//p')" >/dev/null
[ "$(shasum "$T/probe14/.fable-team/seats-x.json")" = "$before14" ] && bad "ⓡ 변이10 restore 가 JSON 재생성 → 바이트가 달라져야 함(빨강이어야 함)" || ok "ⓡ 변이10 restore 가 JSON 을 재생성해 쓰면 → 바이트 다름(빨강 — 위 ⓡ 칸이 잡는다)"
mkG 11; mut "$T/g11/ft_team_move_cleanup.py" '            add_pending(arch, rec, f, meta, rows, rew, list(base) if roster else None)
            why = None' '            why = None'
mut "$T/g11/ft_team_move_cleanup.py" '    meta["status"] = "done"   # 교체 뒤 표시 — 디스크 쓰기는 «있으면 좋은 것»
    try:
        dump_arch(arch / "archive.json", rec)' '    meta["status"] = "done"
    try:
        add_pending(arch, rec, f, meta, rows, rew, list(base) if roster else None)'
cp -R "$T/probe0" "$T/probe18"; before18="$(shasum "$T/probe18/.fable-team/seats-x.json")"; PR "$T/probe18" "$T/pp18" plan >/dev/null
gout="$(BIN="$T/g11" P2 "$T/probe18" done-fail "$T/pp18/plan.json" "$(plan_sha "$T/pp18/plan.json")")"
garch="$(printf '%s' "$gout" | sed -n 's/.*archive=//p')"; BIN="$T/g11" PR "$T/probe18" "$T/pp18" restore "$garch" >/dev/null
[ "$(shasum "$T/probe18/.fable-team/seats-x.json")" = "$before18" ] && bad "ⓞ 변이11 기록을 교체 뒤로 → 기록이 안 써지면 되살림 불가(빨강이어야 함)" || ok "ⓞ 변이11 기록을 교체 «뒤» 로 → 되살림 불가(빨강 — 위 ⓞ 칸이 잡는다)"
cp -R "$T/probe0" "$T/probe19"; PR "$T/probe19" "$T/pp19" plan >/dev/null
gout="$(BIN="$T/g11" P2 "$T/probe19" pend-fail "$T/pp19/plan.json" "$(plan_sha "$T/pp19/plan.json")")"
hasnt "$gout" "보관 기록 실패" "ⓟ 변이11 기록 실패 무시·교체 뒤 기록 → 기록 없이 교체됨(빨강 — 위 ⓟ 칸이 잡는다)"
mkG 12; mut "$T/g12/ft_team_move_cleanup.py" '    if cs == m["b1_sha"]:
        print(f"SKIP {p.name} 교체 안 됨(pending)")' '    if False:
        print(f"SKIP {p.name} 교체 안 됨(pending)")'
cp -R "$T/probe0" "$T/probe20"
printf '{\n  "name": "byz-x-nano-b#0",\n  "card_path": "design/x/indices/진행/b.md",\n  "worktree": "%s"\n}\n' "$T/probe20/.worktrees/nanowt" > "$T/probe20/.fable-team/state/nano-card-base/byz-x-nano-b#0.json"
PR "$T/probe20" "$T/pp20" plan >/dev/null
gout="$(P2 "$T/probe20" perm-race "$T/pp20/plan.json" "$(plan_sha "$T/pp20/plan.json")")"
garch="$(printf '%s' "$gout" | sed -n 's/.*archive=//p')"
gout="$(BIN="$T/g12" PR "$T/probe20" "$T/pp20" restore "$garch")"
hasnt "$gout" "교체 안 됨(pending)" "ⓠ 변이12 restore 가 현재 바이트 대신 기록만 믿음 → 교체 안 된 항목도 되살림 시도(빨강 — 위 ⓠ 칸이 잡는다)"
mkG 13; mut "$T/g13/ft_team_move_cleanup.py" '    if hashlib.sha256(orig).hexdigest() != m["b1_sha"]:' '    if False:'
arch25="$(mkT 25)"; for k in "$(dirname "$arch25")"/orig/* "$(dirname "$arch25")"/ncb/*; do printf 'x' >> "$k"; done
gout="$(BIN="$T/g13" PR "$T/probe25" "$T/pp25" restore "$arch25")"
hasnt "$gout" "보관본 손상" "ⓣ 변이13 보관본 sha 검사 끔 → 손상본을 그대로 되살림(빨강 — 위 ⓣ 손상 칸이 잡는다)"
mkG 14; mut "$T/g14/ft_team_move_cleanup.py" '        print(f"ERROR {p.name} 보관본 없음 — 되살림 0")
        return False, True' '        return False, False'
arch26="$(mkT 26)"; for k in "$(dirname "$arch26")"/orig/* "$(dirname "$arch26")"/ncb/*; do mv "$k" "$k.gone"; done
gout="$(BIN="$T/g14" PR "$T/probe26" "$T/pp26" restore "$arch26")"
hasnt "$gout" "ERROR" "ⓣ 변이14 보관본 없음을 조용한 rc0 로 → ERROR 줄·rc1 없음(빨강 — 위 ⓣ 없음 칸이 잡는다)"
has "$gout" "RESTORE rc=0" "ⓣ 변이14 rc0 (실패를 성공으로 — 위 ⓣ rc1 칸이 잡는다)"

mkG 15; mut "$T/g15/ft_team_move_cleanup.py" '    if hashlib.sha256(orig).hexdigest() != m["b1_sha"]:' '    if m["kind"] != "move" and hashlib.sha256(orig).hexdigest() != m["b1_sha"]:'
arch29="$(mkT 29)"; printf 'x' >> "$(dirname "$arch29")/ncb/byz-x-nano-d9#0.json"
gout="$(BIN="$T/g15" PR "$T/probe29" "$T/pp29" restore "$arch29")"
hasnt "$gout" "ERROR byz-x-nano-d9#0.json 보관본 손상" "ⓣ' 변이15 NCB 경로 sha 검증 끔 → 손상 ncb/ 를 그대로 되살림(빨강 — 위 ⓣ' 칸이 잡는다)"

#   ⓖ r2 반례 5꼴: 잠금(살아 있음 REJECT · 죽은 잠금 회수 · tmux 1회) · 계획 1회 읽기 · 분류=지문 한 판 · 되살림 전체 지문 · 정규화·코드 예외 0
echo "== ⓔ 문법 · 키트 사본 cmp0"
for f in ft_team_move.py ft_team_move_classify.py ft_team_move_cleanup.py; do python3 -I -c "import ast,sys;ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$SRC/$f" && ok "ast $f" || bad "ast $f"; done
bash -n "$SRC/ft-team-move.sh" && ok "bash -n ft-team-move.sh" || bad "bash -n ft-team-move.sh"
for f in ft_team_move.py ft_team_move_classify.py ft_team_move_cleanup.py ft-team-move.sh; do cmp -s "$SRC/$f" "$KIT/$f" && ok "키트 사본 cmp0 $f" || bad "키트 사본 cmp $f"; done
echo "== fail=$fail"; [ "$fail" = 0 ]
