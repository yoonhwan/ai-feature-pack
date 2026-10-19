#!/usr/bin/env bash
# ft-goal-check.sh <seat> [--touch "<골 원장 닫는-증거 복붙 20자+>"]
# 골 재독 게이트 — 골 원장 + 정본 3파일 sha 를 «좌석 원장»과 대조한다.
#   exit 0 = GOAL-OK          (좌석 원장 최신 · NEXT 행 출력)
#   exit 3 = REREAD-REQUIRED  (좌석 원장 부재 / 골 원장·정본 sha 바뀜 / TTL 만료 / 커밋 N개 경과)
#   exit 4 = REJECT           (--touch 문구가 골 원장 본문에 실재하지 않음 = 복붙이 아니다)
#            ERROR            (명단 ref 못 읽음 · v65 폴더 실재 후보 2+ · 정본이 체크아웃에도 ref 에도 없음 — 추측 0)
# r479 자리 규칙: 명단 = ref(FT_TEAMS_REF · 기본 origin/main · 체크아웃 TEAMS.md 는 판정에 안 쓴다 · 어긋나면 끝에 WARN 1줄)
#   v65 폴더 = 그 루트에 실재하는 후보 정확히 1개 · 0개면 정본 4파일을 ref 본문(ft_team_doc_ref 임시 파일)으로 읽고 sha 도 ref 이력
# 「틱 기준 매 업데이트」(#11389 ①) 의 정의: 갱신되는 것은 골 원장 파일이 아니라 «좌석 원장»
#   .fable-team/state/goal-read-ledger.json[seat] = {ledger_sha, sources_sha, head_sha, read_at, cited}.
#   골 원장(GOAL-LEDGER-v65.md)은 수락 항목 원장이라 틱마다 안 바뀐다 — 바뀌는 것은 «읽었다는 증거»다.
#   변화 없는 틱도 --touch 로 read_at/head_sha 를 갱신한다(cited 는 실재 문구 필수).
# ★파이프 금지★ — `| head` 에 물리면 exit 가 파이프 끝단 것으로 읽힌다(ft-wall-check.sh 와 동일).
set -uo pipefail
SEAT="${1:?seat}"; shift || true
TOUCH=""
if [ "${1:-}" = "--touch" ]; then TOUCH="${2:?cite phrase}"; fi
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-team-lib.sh"
REF="${FT_TEAMS_REF:-origin/main}"
TMPS=(); WARN=""
trap 'rm -f ${TMPS[@]+"${TMPS[@]}"}; [ -z "$WARN" ] || echo "$WARN" >&2' EXIT
ref_rel() { ( md="$(mktemp)" || exit 1; trap 'rm -f "$md"' EXIT
  git -C "$ROOT" show "$REF:design/TEAMS.md" > "$md" 2>/dev/null && FT_TEAMS_MD="$md" FT_REPO_ROOT="$ROOT" ft_team_rel v65 2>/dev/null ); }
CANDS="$(ft_team_cands_ref "$ROOT" v65 "$REF" 2>&1)" || { echo "ERROR seat=$SEAT 명단 ref 못 읽음 — $CANDS"; exit 4; }
HITS=(); while IFS= read -r c; do [ -n "$c" ] && [ -d "$c" ] && HITS+=("$c"); done <<< "$CANDS"
[ "${#HITS[@]}" -le 1 ] || { echo "ERROR seat=$SEAT v65 폴더 실재 후보 ${#HITS[@]}개 — 정확히 1개여야 한다(명단 $REF:design/TEAMS.md · 후보 ${HITS[*]})"; exit 4; }
if [ -f "$ROOT/design/TEAMS.md" ] && [ "$(FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_REPO_ROOT="$ROOT" ft_team_rel v65 2>/dev/null)" != "$(ref_rel)" ]; then
  WARN="WARN 체크아웃 명단 $ROOT/design/TEAMS.md 의 v65 칸이 $REF 와 다르다 — 판정은 $REF 명단 + 실재 폴더"; fi
LEDGER_NAME=GOAL-LEDGER-v65.md
SRC_NAMES=(20260909/GOAL-archastra-lst-on-off-completion.md 20260910/LIST-v65-lst-completion-MERGED.md 20260911/PLAN-v65-sm65-experiment-completion-handoff.md)
if [ "${#HITS[@]}" = 1 ]; then
  # 체크아웃 실재 폴더 — «리포 밖» 은 꼴3 만 생긴다
  case "${HITS[0]}" in "$ROOT"/*) V65="${HITS[0]#"$ROOT"/}";; *) echo "REJECT seat=$SEAT v65 팀 폴더가 리포 밖이다: ${HITS[0]}"; exit 4;; esac
  LEDGER_MD="$V65/$LEDGER_NAME"; LEDGER_FILE="$ROOT/$LEDGER_MD"
  SRCS=(); for f in "${SRC_NAMES[@]}"; do SRCS+=("$V65/$f"); done
  for f in "$LEDGER_MD" "${SRCS[@]}"; do [ -f "$ROOT/$f" ] || { echo "REJECT seat=$SEAT 정본 부재: $f"; exit 4; }; done
  LSHA="$(git -C "$ROOT" log -1 --format=%h -- "$LEDGER_MD")"
  SSHA="$(git -C "$ROOT" log -1 --format=%h -- "${SRCS[@]}")"
else
  # 실재 0 — 정본은 ref 본문(임시 파일) · sha = ref 이력의 마지막 커밋(체크아웃이 따라잡아도 같은 값)
  V65="$(printf '%s\n' "$CANDS" | head -1)"; V65="${V65#"$ROOT"/}"
  for f in "$LEDGER_NAME" "${SRC_NAMES[@]}"; do
    t="$(ft_team_doc_ref "$ROOT" v65 "$f" "$REF" 2>&1)" || { echo "ERROR seat=$SEAT 정본 없음(체크아웃·$REF 둘 다) — $t"; exit 4; }
    TMPS+=("$t"); [ "$f" = "$LEDGER_NAME" ] && LEDGER_FILE="$t"
  done
  LEDGER_MD="$V65/$LEDGER_NAME"
  SRCS=(); for f in "${SRC_NAMES[@]}"; do SRCS+=("$V65/$f"); done
  LSHA="$(git -C "$ROOT" log -1 --format=%h "$REF" -- "$LEDGER_MD")"
  SSHA="$(git -C "$ROOT" log -1 --format=%h "$REF" -- "${SRCS[@]}")"
fi
STATE="$ROOT/.fable-team/state/goal-read-ledger.json"
TTL_SEC="${FT_GOAL_TTL_SEC:-7200}"
MAX_COMMITS="${FT_GOAL_MAX_COMMITS:-10}"
HEAD_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$TOUCH" ]; then
  [ "${#TOUCH}" -ge 20 ] || { echo "REJECT seat=$SEAT cited 20자 미만 (${#TOUCH})"; exit 4; }
  grep -qF -- "$TOUCH" "$LEDGER_FILE" \
    || { echo "REJECT seat=$SEAT cited 문구가 골 원장에 없다 (열지 않았다): $TOUCH"; exit 4; }
fi
python3 - "$STATE" "$SEAT" "$LSHA" "$SSHA" "$HEAD_SHA" "$TTL_SEC" "$MAX_COMMITS" "$TOUCH" "$ROOT" "$LEDGER_MD" "$LEDGER_FILE" <<'PY'
import json, sys, os, datetime, subprocess, re
state, seat, lsha, ssha, head, ttl, maxc, touch, root, ledger_md, ledger_file = sys.argv[1:12]
ttl = int(ttl); maxc = int(maxc)
d = json.load(open(state)) if os.path.exists(state) else {}
now = datetime.datetime.now()

def reread(why):
    print(f"REREAD-REQUIRED seat={seat} {why} · 골원장 sha={lsha} 정본 sha={ssha}")
    print(f"  열어라: {ledger_md} + 헤더 표의 정본 3 · 갱신: ft-goal-check.sh '{seat}' --touch \"<닫는 증거 복붙 20자+>\"")
    sys.exit(3)

if touch:
    d[seat] = {"ledger_sha": lsha, "sources_sha": ssha, "head_sha": head,
               "read_at": now.isoformat(timespec="seconds"), "cited": touch[:120]}
    os.makedirs(os.path.dirname(state), exist_ok=True)
    json.dump(d, open(state, "w"), ensure_ascii=False, indent=1)
    print(f"GOAL-READ seat={seat} ledger={lsha} sources={ssha} head={head} OK")

e = d.get(seat)
if not e: reread("(좌석 원장 부재 — 신규/승계)")
if e.get("ledger_sha") != lsha: reread(f"골 원장 갱신됨 {e.get('ledger_sha')}→{lsha}")
if e.get("sources_sha") != ssha: reread(f"정본 갱신됨 {e.get('sources_sha')}→{ssha}")
age = (now - datetime.datetime.fromisoformat(e["read_at"])).total_seconds()
if age > ttl: reread(f"만료 {int(age)}s > {ttl}s")
try:
    n = int(subprocess.check_output(["git", "-C", root, "rev-list", "--count", f"{e['head_sha']}..HEAD"],
                                    text=True, stderr=subprocess.DEVNULL).strip())
except subprocess.CalledProcessError:
    n = maxc + 1
if n > maxc: reread(f"커밋 {n}개 경과 > {maxc}")

# NEXT — 골 원장의 «열린 행»에서 고른다. K4 를 «품고 있는» 행 우선(오빠 최우선), 그 다음 원장 순서.
#   열 위치는 헤더에서 읽는다(원장 v2 = M0–M7 단일 표 · K 는 행이 아니라 열에 접혀 있다).
rows = []; status_idx = None
for line in open(ledger_file, encoding="utf-8"):
    if not line.startswith("|"): continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if status_idx is None and any(c.startswith("상태") for c in cells):
        status_idx = next(i for i, c in enumerate(cells) if c.startswith("상태")); continue
    if not line.startswith("| **") or status_idx is None or len(cells) <= status_idx: continue
    unit = re.sub(r"\*\*", "", cells[0]).split()[0]
    if not re.fullmatch(r"M[0-7]", unit): continue
    status = cells[status_idx]
    status_head = status.split(" — ")[0]  # 상태 칸 머리(첫 « — » 앞)만 판정 — 뒤 범위 서술의 「미관측」 이 CLOSE 행을 열지 않게
    closed = bool(re.search(r"CLOSE|닫힘", status_head)) and not re.search(r"미|진행|후보", status_head)
    rows.append((unit, cells[1], status, closed, "K4" in line))
open_rows = [r for r in rows if not r[3]]
pick = ([r for r in open_rows if r[4]] or open_rows or [None])[0]
print(f"GOAL-OK seat={seat} ledger={lsha} read_at={e['read_at']} age={int(age)}s "
      f"commits_since={n} open={len(open_rows)} closed={len(rows)-len(open_rows)}")
if pick:
    print(f"NEXT {pick[0]} / 닫는 증거: {pick[1]} / 상태: {pick[2]}")
PY
