#!/usr/bin/env bash
# ft-goal-check.sh <seat> [--touch "<골 원장 닫는-증거 복붙 20자+>"]
# 골 재독 게이트 — 골 원장 + 정본 3파일 sha 를 «좌석 원장»과 대조한다.
#   exit 0 = GOAL-OK          (좌석 원장 최신 · NEXT 행 출력)
#   exit 3 = REREAD-REQUIRED  (좌석 원장 부재 / 골 원장·정본 sha 바뀜 / TTL 만료 / 커밋 N개 경과)
#   exit 4 = REJECT           (--touch 문구가 골 원장 본문에 실재하지 않음 = 복붙이 아니다)
#            ERROR            (명단 ref 못 읽음 · v65 쌍둥이가 ref 에 둘 다 없음 · 정본이 체크아웃에도 ref 에도 없음 — 추측 0)
# r479 자리 규칙: 명단 = ref(FT_TEAMS_REF · 기본 origin/main · 체크아웃 TEAMS.md 는 판정에 안 쓴다 · 어긋나면 끝에 WARN 1줄)
#   v65 폴더 = ft_team_in_ref(실재 1개 · 쌍둥이 = ref 트리에 있는 쪽 + stderr WARN TWIN-STALE/BOTH · r495) · 0개면 정본 4파일을 ref 본문(ft_team_doc_ref 임시 파일)으로 읽고 sha 도 ref 이력
#   고른 폴더에 없는 정본은 그 파일만 ref 본문 + 출력 끝 `NOTE 정본 = <ref> 본문(체크아웃 ref 뒤 N커밋): <파일…>` 1줄(r495)
# 「틱 기준 매 업데이트」(#11389 ①) 의 정의: 갱신되는 것은 골 원장 파일이 아니라 «좌석 원장»
#   <공용 루트>/.fable-team/state/goal-read-ledger.json[seat] = {ledger_sha, sources_sha, ref_sha, head_sha, read_at, cited}.
#   골 원장(GOAL-LEDGER-v65.md)은 수락 항목 원장이라 틱마다 안 바뀐다 — 바뀌는 것은 «읽었다는 증거»다.
#   변화 없는 틱도 --touch 로 read_at/ref_sha 를 갱신한다(cited 는 실재 문구 필수).
# r485 자리 규칙(r459): 상태 = 공용 루트 1개(FT_ROOT · 없으면 ft_repo_root) · 원장·정본 sha = $REF 의 명단 꼴 경로 이력(공유 .git 라 어느 워크트리서도 같다)
#   커밋 경과 = rev-list <ref_sha>..$REF(좌석 로컬 커밋은 안 센다) · 체크아웃(cwd 루트)은 cited grep·NEXT 읽기에만 · head_sha 칸은 옛 꼴 호환으로 남김
# ★파이프 금지★ — `| head` 에 물리면 exit 가 파이프 끝단 것으로 읽힌다(ft-wall-check.sh 와 동일).
set -uo pipefail
SEAT="${1:?seat}"; shift || true
TOUCH=""
if [ "${1:-}" = "--touch" ]; then TOUCH="${2:?cite phrase}"; fi
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-team-lib.sh"; . "$HERE/ft-harness-root.sh"
DATA="${FT_ROOT:-$(ft_repo_root "$HERE")}" || { echo "ERROR seat=$SEAT 공용 루트를 못 풂(상태 파일 자리) — FT_ROOT 또는 .fable-team/ 있는 git 리포 cwd"; exit 4; }
REF="${FT_TEAMS_REF:-origin/main}"
TMPS=(); WARN=""
trap 'rm -f ${TMPS[@]+"${TMPS[@]}"}; [ -z "$WARN" ] || echo "$WARN" >&2' EXIT
ref_rel() { ( md="$(mktemp)" || exit 1; trap 'rm -f "$md"' EXIT
  git -C "$ROOT" show "$REF:design/TEAMS.md" > "$md" 2>/dev/null && FT_TEAMS_MD="$md" FT_REPO_ROOT="$ROOT" ft_team_rel v65 2>/dev/null ); }
CANDS="$(ft_team_cands_ref "$ROOT" v65 "$REF" 2>&1)" || { echo "ERROR seat=$SEAT 명단 ref 못 읽음 — $CANDS"; exit 4; }
# r495: 폴더 = ft_team_in_ref 하나(쌍둥이 = ref 트리로 가름 · WARN TWIN-* 은 stderr 그대로) · «실재 0» 만 아래 ref 본문 경로 · 그 밖 실패 = ERROR
EF="$(mktemp)" || exit 4; TMPS+=("$EF")
V65ABS="$(FT_TEAM_SPARSE_CHECK=0 ft_team_in_ref "$ROOT" v65 "$REF" 2>"$EF")"; IRC=$?; IERR="$(cat "$EF")"
if [ "$IRC" != 0 ]; then case "$IERR" in *"실재 후보 0개"*) V65ABS="";; *) echo "ERROR seat=$SEAT v65 ${IERR#ERROR v65 }"; exit 4;; esac
elif [ -n "$IERR" ]; then echo "$IERR" >&2; fi
BEHIND="$(git -C "$ROOT" rev-list --count "HEAD..$REF" 2>/dev/null)" || BEHIND="?"; NOTE=""
if [ -f "$ROOT/design/TEAMS.md" ] && [ "$(FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_REPO_ROOT="$ROOT" ft_team_rel v65 2>/dev/null)" != "$(ref_rel)" ]; then
  WARN="WARN 체크아웃 명단 $ROOT/design/TEAMS.md 의 v65 칸이 $REF 와 다르다 — 판정은 $REF 명단 + 실재 폴더"; fi
LEDGER_NAME=GOAL-LEDGER-v65.md
SRC_NAMES=(20260909/GOAL-archastra-lst-on-off-completion.md 20260910/LIST-v65-lst-completion-MERGED.md 20260911/PLAN-v65-sm65-experiment-completion-handoff.md)
# 판정 키 = $REF 의 명단 꼴 폴더 이력(체크아웃 폴더가 옛 꼴이어도 ref 쪽 경로로 잰다 — 원장 갱신 감지를 잃지 않게)
RV65="$(printf '%s\n' "$CANDS" | head -1)"; RV65="${RV65#"$ROOT"/}"
if [ -n "$V65ABS" ]; then
  # 체크아웃 실재 폴더 — «리포 밖» 은 꼴3 만 생긴다
  case "$V65ABS" in "$ROOT"/*) V65="${V65ABS#"$ROOT"/}";; *) echo "REJECT seat=$SEAT v65 팀 폴더가 리포 밖이다: $V65ABS"; exit 4;; esac
  LEDGER_MD="$V65/$LEDGER_NAME"; LEDGER_FILE="$ROOT/$LEDGER_MD"
  # r495: 고른 폴더에 없는 정본은 그 파일만 $REF 본문($REF:<명단 꼴>/<파일>) — ref 에도 없을 때만 REJECT 정본 부재
  for f in "$LEDGER_NAME" "${SRC_NAMES[@]}"; do
    [ -f "$ROOT/$V65/$f" ] && continue
    t="$(mktemp "$(_ft_team_doc_dir)/ft-team-doc.XXXXXX")" || exit 4; TMPS+=("$t")
    { git -C "$ROOT" show "$REF:$RV65/$f" > "$t" 2>/dev/null && [ -s "$t" ]; } || { echo "REJECT seat=$SEAT 정본 부재: $V65/$f ($REF:$RV65/$f 도 없음)"; exit 4; }
    NOTE+="${NOTE:+ }$f"; [ "$f" = "$LEDGER_NAME" ] && LEDGER_FILE="$t"
  done
else
  # 실재 0 — 정본은 ref 본문(임시 파일) · sha = ref 이력의 마지막 커밋(체크아웃이 따라잡아도 같은 값)
  V65="$(printf '%s\n' "$CANDS" | head -1)"; V65="${V65#"$ROOT"/}"
  for f in "$LEDGER_NAME" "${SRC_NAMES[@]}"; do
    t="$(ft_team_doc_ref "$ROOT" v65 "$f" "$REF" 2>&1)" || { echo "ERROR seat=$SEAT 정본 없음(체크아웃·$REF 둘 다) — $t"; exit 4; }
    TMPS+=("$t"); [ "$f" = "$LEDGER_NAME" ] && LEDGER_FILE="$t"
  done
  LEDGER_MD="$V65/$LEDGER_NAME"
fi
RSRCS=(); for f in "${SRC_NAMES[@]}"; do RSRCS+=("$RV65/$f"); done
git -C "$ROOT" cat-file -e "$REF:$RV65/$LEDGER_NAME" 2>/dev/null || { echo "ERROR seat=$SEAT 골 원장이 $REF 에 없다: $RV65/$LEDGER_NAME — 판정 키 = ref sha(추측 0)"; exit 4; }
LSHA="$(git -C "$ROOT" log -1 --format=%h "$REF" -- "$RV65/$LEDGER_NAME")"
SSHA="$(git -C "$ROOT" log -1 --format=%h "$REF" -- "${RSRCS[@]}")"
REF_SHA="$(git -C "$ROOT" rev-parse --short "$REF")"
STATE="$DATA/.fable-team/state/goal-read-ledger.json"
TTL_SEC="${FT_GOAL_TTL_SEC:-7200}"
MAX_COMMITS="${FT_GOAL_MAX_COMMITS:-10}"
HEAD_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
if [ -n "$TOUCH" ]; then
  [ "${#TOUCH}" -ge 20 ] || { echo "REJECT seat=$SEAT cited 20자 미만 (${#TOUCH})"; exit 4; }
  grep -qF -- "$TOUCH" "$LEDGER_FILE" \
    || { echo "REJECT seat=$SEAT cited 문구가 골 원장에 없다 (열지 않았다): $TOUCH"; exit 4; }
fi
# r495: NOTE 는 판정 출력 «뒤» stdout 1줄(첫 줄 = 판정 그대로) — rc 는 판정기 것
[ -z "$NOTE" ] || trap 'rm -f ${TMPS[@]+"${TMPS[@]}"}; [ -z "$WARN" ] || echo "$WARN" >&2; echo "NOTE 정본 = $REF 본문(체크아웃 ref 뒤 ${BEHIND}커밋): $NOTE"' EXIT
python3 - "$STATE" "$SEAT" "$LSHA" "$SSHA" "$HEAD_SHA" "$TTL_SEC" "$MAX_COMMITS" "$TOUCH" "$ROOT" "$LEDGER_MD" "$LEDGER_FILE" "$REF" "$REF_SHA" <<'PY'
import json, sys, os, datetime, subprocess, re
state, seat, lsha, ssha, head, ttl, maxc, touch, root, ledger_md, ledger_file, ref, ref_sha = sys.argv[1:14]
ttl = int(ttl); maxc = int(maxc)
d = json.load(open(state)) if os.path.exists(state) else {}
now = datetime.datetime.now()

def reread(why):
    print(f"REREAD-REQUIRED seat={seat} {why} · 골원장 sha={lsha} 정본 sha={ssha}")
    print(f"  열어라: {ledger_md} + 헤더 표의 정본 3 · 갱신: ft-goal-check.sh '{seat}' --touch \"<닫는 증거 복붙 20자+>\"")
    sys.exit(3)

if touch:
    d[seat] = {"ledger_sha": lsha, "sources_sha": ssha, "ref_sha": ref_sha, "head_sha": head,
               "read_at": now.isoformat(timespec="seconds"), "cited": touch[:120]}
    os.makedirs(os.path.dirname(state), exist_ok=True)
    json.dump(d, open(state, "w"), ensure_ascii=False, indent=1)
    print(f"GOAL-READ seat={seat} ledger={lsha} sources={ssha} head={head} ref={ref_sha} state={state} OK")

e = d.get(seat)
if not e: reread("(좌석 원장 부재 — 신규/승계)")
if not e.get("ref_sha"): reread("(옛 꼴 행 — ref_sha 없음 · 다시 touch)")
if e.get("ledger_sha") != lsha: reread(f"골 원장 갱신됨 {e.get('ledger_sha')}→{lsha}")
if e.get("sources_sha") != ssha: reread(f"정본 갱신됨 {e.get('sources_sha')}→{ssha}")
age = (now - datetime.datetime.fromisoformat(e["read_at"])).total_seconds()
if age > ttl: reread(f"만료 {int(age)}s > {ttl}s")
try:
    n = int(subprocess.check_output(["git", "-C", root, "rev-list", "--count", f"{e['ref_sha']}..{ref}"],
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
