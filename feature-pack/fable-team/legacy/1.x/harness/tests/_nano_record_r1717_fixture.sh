#!/usr/bin/env bash
# _nano_record_r1717_fixture.sh — r1717 시험 3파일 공용 픽스처(사례 아님 · source 전용 · 실행 비트 0).
#   임시 bare remote 2개(카드 꼴 CREM · 팩 꼴 PREM) + 사본 리포 2개(ROOT = 카드 리포 · 카드 ref 가지 ops/base 와 공유 작업 트리 OPS 1개 / PACK = 착지 리포)
#   가짜 명부(seats-harness.json) · 가짜 mbox(FT_MBOX · seq·bodies 를 실제 꼴로 남긴다) · 가짜 tmux(PATH 앞) — 실 명부·실 우편함·실 tmux·네트워크 0 · sleep 0
#   R1717_BIN = 시험할 bin 폴더(기본 = 추적본 · 기준판·변이 대조 때 덮는다)
set -uo pipefail
export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_REPO_ROOT FT_SEAT FT_SEATS_JSON FT_CARD_REF FT_INBOX_ROOT FT_LAND_DEADLINE FT_NANO_AUTO_CLOSE
FX_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; H="$(cd -- "$FX_HERE/.." && pwd)"
SRC="$H/bin"; KIT="$H/kit/fable-team/bin"; BIN="${R1717_BIN:-$SRC}"; TOOL="$BIN/ft-nano-record.sh"
fail=0; T_START=$SECONDS
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1${2:+ :: ${2:0:500}}"; fail=$((fail+1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "기대 «$3» 실제 «$2»"; fi; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "없음: «$3» ← ${2:0:400}";; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "있으면 안 됨: «$3» ← ${2:0:300}";; *) ok "$1";; esac; }
step() { echo "== $1 (누적 $((SECONDS - T_START))초)"; }
E=0   # 사례 함수 = 하위 셸 1개(run) · 안에서 t 로 검사 · 끝줄 `return $E`
t() { local d="$1"; shift; "$@" && return 0; echo "  x $d :: rc=${RC:-} out=$(printf '%s' "${OUT:-}" | head -c 400)"; E=1; }   # 사례 안 검사 1개(실패 = 줄 1개 + 사례 rc 1)
inc() { case "$1" in *"$2"*) return 0;; esac; return 1; }; exc() { ! inc "$@"; }
run() { local n="$1" o; if o="$("$2" "${3:-}" 2>&1)"; then ok "$n"; else bad "$n" "$o"; fi; }   # run <이름> <사례 함수> [꼬리표]
finish() { echo "단계별 초: 전체 $((SECONDS - T_START))"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r1717.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT
FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  list-sessions) [ "${FAKE_TMUX_RC:-0}" = 0 ] || exit "$FAKE_TMUX_RC"; cat "$FAKE_SESS";;
  display-message) printf '%s\n' "${FAKE_CWD:-}";;   # close-due 가 묻는 pane cwd
esac
exit 0
EOF
printf '#!/bin/sh\necho "IDLE - - - jsonl"\n' > "$FK/seat-status.sh"; printf '#!/bin/sh\necho OK\n' > "$FK/quiet.sh"
cat > "$FK/nc.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 닫기 도구 — 받은 인자를 NC_LOG 에 1줄 · NC_RC(기본 0)로 끝난다 · rc 0 이면 «INFO» 줄 뒤 «CLOSED <좌석>»(실 도구처럼 첫 줄이 CLOSED 가 아니다)
echo "$*" >> "$NC_LOG"
[ "${NC_RC:-0}" = 0 ] || { echo "REJECT $1"; echo "  - 가짜 거절"; exit "$NC_RC"; }
echo "INFO 가짜 닫기"; echo "CLOSED $1 landed-pr"
EOF
cat > "$FK/crit.sh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CRIT_LOG"
EOF
cat > "$FK/mbox.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 우편함 — send <to> <from> <body> · 기록 = <seq>\t<to>\t<from>\t<body> · 실패 주입: MBOX_FAIL(전부) · MBOX_FAIL_HEAD(본문 머리가 그 글이면)
[ "$1" = send ] || exit 2
[ -z "${MBOX_TOUCH:-}" ] || : > "$MBOX_TOUCH"
case "$4" in "${MBOX_FAIL_HEAD:-$'\001'}"*) MBOX_FAIL=5;; esac
[ -z "${MBOX_FAIL:-}" ] || { printf 'FAIL\t%s\t%s\t%s\n' "$2" "$3" "$4" >> "$MBOX_LOG"; echo QUEUE_FULL >&2; exit "$MBOX_FAIL"; }
n=$(( $(cat "$MBOX_DIR/.mbox-seq") + 1 )); echo "$n" > "$MBOX_DIR/.mbox-seq"
printf '%s\n' "$4" > "$MBOX_DIR/bodies/$n.txt"; printf '%s\t%s\t%s\t%s\n' "$n" "$2" "$3" "$4" >> "$MBOX_LOG"
echo "QUEUED seq=$n to=$2 pending=1"
EOF
chmod +x "$FK"/*
CREM="$T/card.git"; ROOT="$T/root"; OPS="$ROOT/.worktrees/ops"; PREM="$T/pack.git"; PACK="$T/ai-pack"; IDX="design/harness/indices"
MASTER="byz-harness-master-pi#9"; ARCH="byz-harness-arch-pi#3"; STATE="$ROOT/.fable-team/state"; COMM="$ROOT/.fable-team/comm"
export PATH="$FK:$PATH" FT_ROOT="$ROOT" FT_MBOX="$FK/mbox.sh" MBOX_DIR="$COMM" MBOX_LOG="$T/mbox.log" FAKE_SESS="$T/sess" TMUX_LOG="$T/tmux.log"
export NC_LOG="$T/nc.log" CRIT_LOG="$T/crit.log" FAKE_CWD="$PACK" FT_PACK_REPO="$PACK" FT_CLOSE_DUE_SEAT_STATUS="$FK/seat-status.sh" FT_CLOSE_DUE_QUIET="$FK/quiet.sh" FT_NANO_CLOSE="$FK/nc.sh" FT_CRITICAL_NOTIFY="$FK/crit.sh"
g() { git -C "$@"; }
world() {  # 카드 리포(ROOT + 공유 작업 트리 OPS · 카드 ref = origin/ops/base) + 착지 리포(PACK)
  git init -q --bare -b main "$CREM"; git clone -q "$CREM" "$ROOT" 2>/dev/null; g "$ROOT" checkout -q -b main 2>/dev/null
  mkdir -p "$ROOT/design"; printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$ROOT/design/TEAMS.md"
  echo a > "$ROOT/a"; g "$ROOT" add -A; g "$ROOT" commit -qm base; g "$ROOT" push -q origin main
  printf '.fable-team/\n.worktrees/\n' >> "$ROOT/.git/info/exclude"
  g "$ROOT" worktree add -q "$OPS" -b ops/base; mkdir -p "$OPS/$IDX/진행" "$STATE" "$COMM/bodies"
  echo "# 하네스 카드" > "$OPS/$IDX/README.md"; g "$OPS" add -A; g "$OPS" commit -qm cards; g "$OPS" push -q -u origin ops/base
  printf 'harness\t.\torigin/ops/base\t%s\n' "$IDX" > "$STATE/directive-roots.tsv"
  echo 100 > "$COMM/.mbox-seq"; : > "$MBOX_LOG"; : > "$FAKE_SESS"; : > "$TMUX_LOG"; : > "$NC_LOG"; : > "$CRIT_LOG"
  git init -q --bare -b main "$PREM"; git clone -q "$PREM" "$PACK" 2>/dev/null; g "$PACK" checkout -q -b main 2>/dev/null
  echo p > "$PACK/p"; g "$PACK" add -A; g "$PACK" commit -qm base; g "$PACK" push -q origin main; g "$PACK" fetch -q origin
}
cardf() {  # cardf <stem> [상태 절 줄…] — 카드 파일만 쓴다(올리기 = cpush)
  local s="$1"; shift; mkdir -p "$OPS/$IDX/진행"
  { printf '# 인덱스: %s\n- 배정: 좌석 x\n\n## 구현 범위\n- x\n\n## 상태\n- 2026-11-12 대기\n' "$s"; [ $# = 0 ] || printf '%s\n' "$@"; printf '%b' "${CARD_TAIL:-}"; } > "$OPS/$IDX/진행/$s.md"   # CARD_TAIL = 상태 절 «뒤» 에 붙일 글(다른 절)
}
cpush() { g "$OPS" add -A; g "$OPS" commit -qm cards; g "$OPS" pull -q --rebase origin ops/base 2>/dev/null; g "$OPS" push -q origin ops/base; }   # 공유 작업 트리에서 커밋 → 도구가 앞서 보낸 커밋 위로 → push
fresh() {  # 사례 머리 — 장부·보낸 기록·세션 기록·쪽지·가짜 도구 기록을 비우고 공유 작업 트리를 원격 끝으로(카드 ref 의 옛 카드는 그대로 · 사례마다 새 stem)
  : > "$STATE/land-record-turn.jsonl"; rm -rf "$STATE/land-record-notified.json" "$STATE/seat-record" "$T/scanst"; : > "$MBOX_LOG"; : > "$TMUX_LOG"; : > "$NC_LOG"; : > "$CRIT_LOG"
  g "$OPS" reset -q --hard; g "$OPS" clean -qfd; g "$OPS" fetch -q origin; g "$OPS" reset -q --hard origin/ops/base; E=0
}
card() { cardf "$@"; cpush; }   # card <stem> [상태 절 줄…] — 카드 ref(ops/base)에 카드 1장
land() {  # land <PR> → PACK origin/main 에 squash 착지 1건 · Q(착지 sha) · PH(PR head)
  g "$PACK" checkout -q -B "pr$1" origin/main; echo "$1 $(g "$PACK" rev-parse origin/main)" > "$PACK/f$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; PH="$(g "$PACK" rev-parse HEAD)"
  Q="$(g "$PACK" commit-tree "$PH^{tree}" -p origin/main -m "t$1" -m "PR #$1 (head $PH)")"; g "$PACK" push -q origin "$Q:refs/heads/main"; g "$PACK" fetch -q origin
}
turn() {  # turn <PR> [stem…] — 장부 1줄(ft-merge-lib fm_land_turn 이 쓰는 꼴 · Q·PH 는 직전 land 값)
  local pr="$1"; shift
  python3 -c 'import json,sys;a=sys.argv;print(json.dumps({"pr":int(a[1]),"repo":a[2],"target":"main","landed":a[3],"pr_head":a[4],"by":a[5],"cards":[a[6]+"/"+s+".md" for s in a[7:]],"ts":"t"},ensure_ascii=False))' \
    "$pr" "$PACK" "$Q" "$PH" "${TURN_BY:-}" "$ROOT/$IDX/진행" "$@" >> "$STATE/land-record-turn.jsonl"
}
seats() {  # seats "<좌석>|<role>|<카드 stem>"… — 가짜 명부(_master·_arch·_cards) + 살아 있는 tmux 세션 = 전부(뺄 좌석은 dead <좌석>)
  python3 - "$ROOT/.fable-team/seats-harness.json" "$MASTER" "$ARCH" "$IDX" "$@" <<'PY'
import json, sys
p, m, a, idx, rows = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
d = {"_master": m, "_arch": a, "_cards": idx, m: {"role": "master"}, a: {"role": "arch"}}
for r in rows:
    s, role, stem = r.split("|")
    d[s] = {"role": role, "agent": "pi", "index": f".worktrees/ops/{idx}/진행/{stem}.md"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
  : > "$FAKE_SESS"; local r; for r in "$@"; do printf '%s\n' "${r%%|*}" >> "$FAKE_SESS"; done
}
dead() { grep -vxF "$1" "$FAKE_SESS" > "$FAKE_SESS.n"; mv "$FAKE_SESS.n" "$FAKE_SESS"; }
setl() { printf -- '- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0' "$PH"; }   # 손으로 쓴 꼴의 세트·착지·완료 줄(직전 land 값)
landl() { printf -- '- 착지: %s (ai-pack origin/main · PR #%s)' "$Q" "${1:-1}"; }
donel() { printf -- '- 완료: %s · 병합 상태: 착지 %s · %s · 차례 #-' "$1" "${Q:0:10}" "${2:-남은 일: 없음}"; }   # donel <좌석> [<남은 일 칸|좌석 계속(…)>]
fxpy() { PYTHONPATH="$BIN" python3 - "$@"; }   # 도구 모듈을 읽는 시험 보조(지문 계산 등)
recof() {  # recof <stem> <좌석> — 카드 ref 판의 지금 기록 지문(A11 rec)
  ctext "$1" | fxpy "$2" "$Q" <<'PY'
import sys
from ft_nano_record import marks, rec_of, section
lines, st, en = section(sys.stdin.read())
print(rec_of(marks(lines[st + 1:en], sys.argv[1], sys.argv[2])))
PY
}
storeset() {  # storeset <칸> <열쇠> <JSON 값> — 보낸 기록 파일의 한 칸을 손으로 둔다(전달 기록 주입)
  fxpy "$STATE/land-record-notified.json" "$@" <<'PY'
import json, sys
p, cell, key, val = sys.argv[1:5]
try: d = json.load(open(p, encoding="utf-8"))
except (OSError, ValueError): d = {}
d.setdefault(cell, {})[key] = json.loads(val)
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False)
PY
}
scan() {  # scan <notify|auto> [<bin>] [<루트>] — ft_stall_scan 사본의 그 한 조각만 부른다 → OUT(로그 줄)·RC
  OUT="$(cd "$T" && FT_NANO_AUTO_CLOSE="${AUTO:-1}" FT_NANO_CLOSE_DUE="${DUE:-${2:-$BIN}/ft-nano-close-due.sh}" python3 - "${2:-$BIN}/ft_stall_scan.py" "$1" "${3:-$ROOT}" "$T/scanst" 2>&1 <<'PY'
import importlib.util, os, pathlib, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("sa", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
o = object.__new__(m.Scan); o.state_dir = pathlib.Path(sys.argv[4]); o.now = time.time(); o.root = pathlib.Path(sys.argv[3])
print("\n".join(o.record_notify("T") if sys.argv[2] == "notify" else o.auto_close()))
PY
)"; RC=$?
}
cdue() { OUT="$(cd "$T" && FT_NANO_AUTO_CLOSE="${AUTO:-1}" bash "${1:-$BIN}/ft-nano-close-due.sh" --all --why 2>&1)"; RC=$?; }   # 닫기 차례 목록 1회(읽기만)
WFAIL=('    tmp.write_text(text, encoding="utf-8")' '    if "seat-record" in str(path):
        raise OSError("주입 — 세션 기록 쓰기 실패")
    tmp.write_text(text, encoding="utf-8")')   # E6·D2 주입: 쓰기 함수(write_atomic)가 세션 기록 경로에서 OSError(경로·파일 꼴은 그대로 — 하드 룰 19)
mutcase() {  # mutcase <M번호> <사례 함수> <꼬리표> — 직전 mutbin 사본(MB)으로 그 사례가 FAIL 인가 + 원본 BIN 으로 같은 사례 1회 더(반대 결과 대조)
  local keep="$BIN" o; BIN="$MB"; TOOL="$MB/ft-nano-record.sh"
  if o="$("$2" "m$3" 2>&1)"; then bad "$1 변이를 못 잡음($2)"; else ok "$1 변이 → $2 FAIL(잡힘) ::$(printf '%s\n' "$o" | grep -m1 '^  x ' | sed 's/ :: .*//')"; fi
  BIN="$keep"; TOOL="$BIN/ft-nano-record.sh"
  if o="$("$2" "o$3" 2>&1)"; then ok "$1 원본 대조 → $2 통과"; else bad "$1 원본 대조가 FAIL($2)" "$o"; fi
}
rec() { OUT="$(cd "$T" && bash "${TOOL}" "$@" 2>&1)"; RC=$?; }   # 도구 1회 → OUT·RC
ctext() { g "$CREM" show "ops/base:$IDX/진행/$1.md" 2>/dev/null; }   # 카드 ref 판의 카드 본문
ncommit() { g "$CREM" rev-list --count ops/base; }
nline() { ctext "$1" | grep -c -- "$2" || true; }   # 카드 ref 판에서 그 글이 든 줄 수
nmsg() { grep -c -- "$1" "$MBOX_LOG" 2>/dev/null || true; }   # 보낸 쪽지 중 그 글이 든 줄 수(성공·실패 다)
nto() { awk -F'\t' -v to="$1" '$1 != "FAIL" && $2 == to' "$MBOX_LOG" | grep -c -- "${2:-.}" || true; }   # nto <받는 이> [글] — 그 좌석이 받은(성공) 쪽지 수
nsent() { grep -v '^FAIL' "$MBOX_LOG" 2>/dev/null | grep -c -- "$1" || true; }   # 발신에 성공한 쪽지만
mutbin() {  # mutbin <이름> <파일> <옛 글> <새 글> [<파일> <옛> <새>…] → MB = bin 사본(그 자리만 바꿈 · 원본 불변) · MUTSRC = 사본의 바탕(기본 추적본 — 변이 사본 위에 주입을 겹칠 때)
  MB="$T/mut-$1"; rm -rf "$MB"; mkdir -p "$MB"; cp "${MUTSRC:-$SRC}"/*.py "${MUTSRC:-$SRC}"/ft-nano-record.sh "${MUTSRC:-$SRC}"/ft-team-lib.sh "${MUTSRC:-$SRC}"/ft-nano-close-due.sh "$MB/"; shift
  python3 - "$MB" "$@" <<'PY'
import sys
d, a = sys.argv[1], sys.argv[2:]
for i in range(0, len(a), 3):
    p = f"{d}/{a[i]}"; s = open(p, encoding="utf-8").read()
    assert s.count(a[i + 1]) == 1, f"변이 자리 {s.count(a[i + 1])}곳: {a[i + 1][:60]}"
    open(p, "w", encoding="utf-8").write(s.replace(a[i + 1], a[i + 2], 1))
PY
}
