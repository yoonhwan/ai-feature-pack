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
finish() { echo "단계별 초: 전체 $((SECONDS - T_START))"; [ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }; }
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/r1717.XXXXXX")" && pwd -P)"; trap 'rm -rf "$T"' EXIT
FK="$T/fake"; mkdir -p "$FK"
cat > "$FK/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
[ "$1" = list-sessions ] || exit 0
[ "${FAKE_TMUX_RC:-0}" = 0 ] || exit "$FAKE_TMUX_RC"
cat "$FAKE_SESS"
EOF
cat > "$FK/mbox.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 우편함 — send <to> <from> <body> · 기록 = <seq>\t<to>\t<from>\t<body> · 실패 주입: MBOX_FAIL(전부) · MBOX_FAIL_HEAD(본문 머리가 그 글이면)
[ "$1" = send ] || exit 2
case "$4" in "${MBOX_FAIL_HEAD:-$'\001'}"*) MBOX_FAIL=5;; esac
[ -z "${MBOX_FAIL:-}" ] || { printf 'FAIL\t%s\t%s\t%s\n' "$2" "$3" "$4" >> "$MBOX_LOG"; echo QUEUE_FULL >&2; exit "$MBOX_FAIL"; }
n=$(( $(cat "$MBOX_DIR/.mbox-seq") + 1 )); echo "$n" > "$MBOX_DIR/.mbox-seq"
printf '%s\n' "$4" > "$MBOX_DIR/bodies/$n.txt"; printf '%s\t%s\t%s\t%s\n' "$n" "$2" "$3" "$4" >> "$MBOX_LOG"
echo "QUEUED seq=$n to=$2 pending=1"
EOF
chmod +x "$FK/tmux" "$FK/mbox.sh"
CREM="$T/card.git"; ROOT="$T/root"; OPS="$ROOT/.worktrees/ops"; PREM="$T/pack.git"; PACK="$T/ai-pack"; IDX="design/harness/indices"
MASTER="byz-harness-master-pi#9"; ARCH="byz-harness-arch-pi#3"; STATE="$ROOT/.fable-team/state"; COMM="$ROOT/.fable-team/comm"
export PATH="$FK:$PATH" FT_ROOT="$ROOT" FT_MBOX="$FK/mbox.sh" MBOX_DIR="$COMM" MBOX_LOG="$T/mbox.log" FAKE_SESS="$T/sess" TMUX_LOG="$T/tmux.log"
g() { git -C "$@"; }
world() {  # 카드 리포(ROOT + 공유 작업 트리 OPS · 카드 ref = origin/ops/base) + 착지 리포(PACK)
  git init -q --bare -b main "$CREM"; git clone -q "$CREM" "$ROOT" 2>/dev/null; g "$ROOT" checkout -q -b main 2>/dev/null
  echo a > "$ROOT/a"; g "$ROOT" add -A; g "$ROOT" commit -qm base; g "$ROOT" push -q origin main
  printf '.fable-team/\n.worktrees/\n' >> "$ROOT/.git/info/exclude"
  g "$ROOT" worktree add -q "$OPS" -b ops/base; mkdir -p "$OPS/$IDX/진행" "$STATE" "$COMM/bodies"
  echo "# 하네스 카드" > "$OPS/$IDX/README.md"; g "$OPS" add -A; g "$OPS" commit -qm cards; g "$OPS" push -q -u origin ops/base
  printf 'harness\t.\torigin/ops/base\t%s\n' "$IDX" > "$STATE/directive-roots.tsv"
  echo 100 > "$COMM/.mbox-seq"; : > "$MBOX_LOG"; : > "$FAKE_SESS"; : > "$TMUX_LOG"
  git init -q --bare -b main "$PREM"; git clone -q "$PREM" "$PACK" 2>/dev/null; g "$PACK" checkout -q -b main 2>/dev/null
  echo p > "$PACK/p"; g "$PACK" add -A; g "$PACK" commit -qm base; g "$PACK" push -q origin main; g "$PACK" fetch -q origin
}
card() {  # card <stem> [상태 절 줄…] — 카드 ref(ops/base)에 카드 1장을 올린다(공유 작업 트리에서 커밋·push)
  local s="$1"; shift
  { printf '# 인덱스: %s\n- 배정: 좌석 x\n\n## 구현 범위\n- x\n\n## 상태\n- 2026-11-12 대기\n' "$s"; [ $# = 0 ] || printf '%s\n' "$@"; } > "$OPS/$IDX/진행/$s.md"
  g "$OPS" add -A; g "$OPS" commit -qm "card $s"; g "$OPS" push -q origin ops/base
}
land() {  # land <PR> → PACK origin/main 에 squash 착지 1건 · Q(착지 sha) · PH(PR head)
  g "$PACK" checkout -q -B "pr$1" origin/main; echo "$1" > "$PACK/f$1"; g "$PACK" add -A; g "$PACK" commit -qm "work $1"; PH="$(g "$PACK" rev-parse HEAD)"
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
rec() { OUT="$(cd "$T" && bash "${TOOL}" "$@" 2>&1)"; RC=$?; }   # 도구 1회 → OUT·RC
ctext() { g "$CREM" show "ops/base:$IDX/진행/$1.md" 2>/dev/null; }   # 카드 ref 판의 카드 본문
ncommit() { g "$CREM" rev-list --count ops/base; }
nline() { ctext "$1" | grep -c -- "$2" || true; }   # 카드 ref 판에서 그 글이 든 줄 수
nmsg() { grep -c -- "$1" "$MBOX_LOG" 2>/dev/null || true; }   # 보낸 쪽지 중 그 글이 든 줄 수(성공·실패 다)
nsent() { grep -v '^FAIL' "$MBOX_LOG" 2>/dev/null | grep -c -- "$1" || true; }   # 발신에 성공한 쪽지만
mutbin() {  # mutbin <이름> <파일> <옛 글> <새 글> [<파일> <옛> <새>…] → MB = bin 사본(그 자리만 바꿈 · 원본 불변)
  MB="$T/mut-$1"; rm -rf "$MB"; mkdir -p "$MB"; cp "$SRC"/ft_nano_record*.py "$SRC"/ft-nano-record.sh "$SRC"/ft-team-lib.sh "$SRC"/ft_team_lib.py "$MB/"; shift
  python3 - "$MB" "$@" <<'PY'
import sys
d, a = sys.argv[1], sys.argv[2:]
for i in range(0, len(a), 3):
    p = f"{d}/{a[i]}"; s = open(p, encoding="utf-8").read()
    assert s.count(a[i + 1]) == 1, f"변이 자리 {s.count(a[i + 1])}곳: {a[i + 1][:60]}"
    open(p, "w", encoding="utf-8").write(s.replace(a[i + 1], a[i + 2], 1))
PY
}
