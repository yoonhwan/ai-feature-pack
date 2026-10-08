#!/usr/bin/env bash
# ft-index-move.sh <indices/<from>/X.md> <대기|진행|완성> [--da <판정문경로#§N>] [--seat <좌석명>] [--landed <sha>]
#   Seatbelt 0.3 · 인덱스 상태 = 폴더. «닫힘» 글자를 손으로 쓸 자리를 없앤다.
#   exit 0 = 이동 · 1 = REJECT · 2 = usage
# 규칙:
#   대기→진행 : lint 통과 + --seat 필수(누가 들고 가는지). §상태 에 한 줄 append.
#   진행→완성 : --da 필수. 판정문 파일이 실재하고 그 §N 절에 「닫힘」 또는 「CLOSE」가 있어야 한다.
#               (DA 가 안 쓴 「닫힘」은 없다 — pm·master 가 대신 쓸 길을 두지 않는다.)
#   기타 방향 : 되돌리기(진행→대기 등)는 --seat 로 사유만 남기고 허용.
#   슬랙(판정 405) : 카드에 `- 슬랙:` 줄이 있으면 이동 «전»에 대기→진행=착수 답글 · 진행→완성=결과 답글 확인/발송.
#               도구 = env FT_THREAD_POST(기본 ~/.hermes/scripts/byz_thread_post.py) · 실패·장부 불명·도구 없음 = REJECT(이동 0 · 폴백 0).
set -uo pipefail
SRC="${1:-}"; DST="${2:-}"; shift 2 2>/dev/null || { echo "usage: $0 <index.md> <대기|진행|완성> [--da <file#§N>] [--seat <name>] [--landed <sha>]" >&2; exit 2; }
DA=""; SEAT=""; LANDED=""
while [ $# -gt 0 ]; do case "$1" in --da) DA="$2"; shift 2;; --seat) SEAT="$2"; shift 2;; --landed) LANDED="$2"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$DST" in 대기|진행|완성) ;; *) echo "REJECT dst 는 대기|진행|완성" >&2; exit 2;; esac
[ -f "$SRC" ] || { echo "REJECT 없음: $SRC"; exit 1; }
SRC="$(cd -- "$(dirname -- "$SRC")" && pwd)/$(basename -- "$SRC")"   # 절대경로 — 상대경로면 아래 git -C ls-files 추적 판정이 untracked 로 떨어져 mv 가 된다(DA r1 R5)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
IDX_ROOT="$(cd "$(dirname "$SRC")/.." && pwd)"
FROM="$(basename "$(dirname "$SRC")")"
[ "$FROM" != "$DST" ] || { echo "REJECT 이미 $DST 에 있다"; exit 1; }
if [ "$DST" = 진행 ]; then
  bash "$HERE/ft-index-lint.sh" "$SRC" || { echo "REJECT lint 실패 — 위 사유"; exit 1; }
  [ -n "$SEAT" ] || { echo "REJECT 대기→진행 은 --seat <좌석명> 필수"; exit 1; }
fi
if [ "$DST" = 완성 ]; then
  [ -n "$DA" ] || { echo "REJECT 진행→완성 은 --da <판정문#§N> 필수 — DA 판정 없이 닫지 않는다"; exit 1; }
  DAF="${DA%%#*}"; SEC="${DA#*#}"
  [ -f "$DAF" ] || { echo "REJECT DA 판정문 없음: $DAF"; exit 1; }
  # §N 절 본문에 닫힘/CLOSE 가 있어야 한다 (## 헤더가 §N 을 포함하는 절)
  body="$(awk -v s="$SEC" 'index($0,"## ")==1{f=index($0,s)>0; if(f){print;next}} f' "$DAF")"
  [ -n "$body" ] || { echo "REJECT $DAF 에 절 «${SEC}» 없음"; exit 1; }
  printf '%s' "$body" | grep -qE '닫힘|CLOSE' || { echo "REJECT $DAF $SEC 에 「닫힘」/「CLOSE」 없음 — DA 가 닫지 않았다"; exit 1; }
  # 정본 게이트(아키텍처 정본 트랙 완성 4항) — 이동 «전»에 검사한다. 카드에 아래 둘 중 하나가 없으면 REJECT·이동 0.
  #   ①「정본 갱신: docs/architect/….md §<절>」 — 파일 실재 + 그 절 제목(# 헤더) 실재
  #   ②「정본 영향 없음: <이유 ≥10자>」
  WT="$(git -C "$IDX_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$IDX_ROOT")"
  CANON_RES="$(python3 - "$SRC" "$WT" <<'PY'
import re, sys, os
card = open(sys.argv[1], encoding="utf-8").read().splitlines()
wt = sys.argv[2]
pre = r'^[\s>*\-]*'
upd = [re.match(pre + r'정본 갱신(?: 줄)?\s*:\s*(\S+?)\s*§\s*(.+?)\s*$', l) for l in card]
upd = [m for m in upd if m]
non = [re.match(pre + r'정본 영향 없음\s*:\s*(.*?)\s*$', l) for l in card]
non = [m for m in non if m]
def reject(why):
    print("REJECT\t" + why); sys.exit(0)
for m in upd:
    path, sec = m.group(1), m.group(2)
    if not path.startswith("docs/architect/") or not path.endswith(".md"):
        reject("정본 갱신 줄의 경로는 docs/architect/….md 여야 한다: " + path)
    full = os.path.join(wt, path)
    # 경계 재검증 — 문자열 prefix 만으로는 docs/architect/../outside 와 심볼릭 링크 탈출을 못 막는다.
    root = os.path.realpath(os.path.join(wt, "docs/architect"))
    real = os.path.realpath(full)
    if ".." in path.split("/") or os.path.commonpath([root, real]) != root:
        reject("정본 갱신 줄의 경로가 docs/architect/ 밖으로 나간다(.. 또는 심볼릭 링크): " + path)
    if not os.path.isfile(full):
        reject("정본 갱신 줄의 파일이 없다: " + path);
    heads = [l for l in open(full, encoding="utf-8", errors="ignore").read().splitlines() if l.startswith("#")]
    tok = sec.split()[0]
    if any(sec in h or tok in h for h in heads):
        print("OK\t정본 " + path + " §" + sec); sys.exit(0)
    reject("정본 문서에 그 절 제목이 없다: " + path + " §" + sec)
for m in non:
    why = re.sub(r'^이유\s*=\s*', '', m.group(1)).strip()
    if len(why) >= 10:
        print("OK\t정본 영향 없음: " + why); sys.exit(0)
    reject("「정본 영향 없음」 이유가 10자 미만이다")
reject("카드에 「정본 갱신: docs/architect/….md §<절>」 또는 「정본 영향 없음: <이유 ≥10자>」 줄이 없다")
PY
)"
  CANON_KIND="$(printf '%s' "$CANON_RES" | cut -f1)"; CANON_NOTE="$(printf '%s' "$CANON_RES" | cut -f2-)"
  case "$CANON_KIND" in
    OK) ;;
    REJECT) echo "REJECT 정본 게이트 — $CANON_NOTE (이동 0 · 카드에 줄을 쓰고 다시 이동)"; exit 1;;
    *) echo "REJECT 정본 게이트 검사 실행 실패(python3) — 이동 0"; exit 1;;
  esac
fi
# 슬랙 단위 스레드(판정 405 §4) — «게시 대상» = 카드의 `- 슬랙:` 줄 유무(장부 아님). 이동 «전»에 끝낸다: 실패면 이동 0.
if { [ "$FROM" = 대기 ] && [ "$DST" = 진행 ]; } || { [ "$FROM" = 진행 ] && [ "$DST" = 완성 ]; }; then
  if grep -q '^- 슬랙:' "$SRC"; then
    TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
    [ -f "$TP" ] || { echo "REJECT 카드에 「- 슬랙:」 줄이 있는데 발행 도구가 없다: $TP (FT_THREAD_POST) — 이동 0"; exit 1; }
    tp() { if [ -x "$TP" ]; then "$TP" "$@"; else python3 "$TP" "$@"; fi; }
    S_ISSUE="$(sed -n 's/^- Issue:[[:space:]]*//p' "$SRC" | head -1 | awk '{print $1}')"; S_ISSUE="${S_ISSUE:-없음}"
    S_SEAT="${SEAT:-없음}"; S_CANON=없음
    case "${CANON_NOTE:-}" in 정본\ docs/architect/*) S_CANON="$WT/$(printf '%s' "$CANON_NOTE" | awk '{print $2}')";; esac
    S_BLK=(--issue "$S_ISSUE" --seat "$S_SEAT" --canon "$S_CANON" --resume-script "$HERE/ft-resume-cmd.sh")
    if [ "$DST" = 진행 ]; then
      out="$(tp progress --card "$SRC" --text "착수 — ${SEAT:-좌석 미지정}" --next "구현·완료 조건 확인" "${S_BLK[@]}" 2>&1)" \
        || { echo "REJECT 슬랙 착수 답글 실패 — 이동 0: $out"; exit 1; }
    else
      tp check --card "$SRC" >/dev/null 2>&1; rc=$?
      case "$rc" in
        0) ;;
        1) out="$(tp result --card "$SRC" --verdict "$DA" ${LANDED:+--landed "$LANDED"} --next "없음" "${S_BLK[@]}" 2>&1)" \
             || { echo "REJECT 슬랙 결과 답글 실패 — 이동 0: $out"; exit 1; };;
        3) echo "REJECT 장부 복구 필요 — byz_thread_post.py repair --card $SRC (이동 0)"; exit 1;;
        *) echo "REJECT 슬랙 장부 확인 실패 rc=$rc — 이동 0"; exit 1;;
      esac
    fi
  fi
fi
mkdir -p "$IDX_ROOT/$DST"
NEW="$IDX_ROOT/$DST/$(basename "$SRC")"
TRACKED=0; git -C "$IDX_ROOT" ls-files --error-unmatch "$SRC" >/dev/null 2>&1 && TRACKED=1
if [ "$TRACKED" = 1 ]; then git mv "$SRC" "$NEW"; else mv "$SRC" "$NEW"; fi || { echo "REJECT 이동 실패: $SRC → $NEW"; exit 1; }
if [ "$DST" = 완성 ]; then
  # 하네스 0.5 행 3 — «완성 이동»이 원장 close 의 유일한 기록자. 원장 없는 완성은 없다(#0 RULE).
  #   트랙 = FT_TRACK(기본 default · 카드가 design/v65/indices 아래면 v65) · $ROOT/STATE_DIR 은 ft-index-gate.sh 와 같은 규약.
  ROOT="$(git -C "$IDX_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
  STATE_DIR="${FT_INDEX_STATE_DIR:-$ROOT/.fable-team/state}"
  TRACK="${FT_TRACK:-}"
  [ -n "$TRACK" ] || case "$IDX_ROOT" in */design/v65/indices) TRACK=v65;; *) TRACK=default;; esac
  LEDGER="$STATE_DIR/index-ledger.$TRACK.jsonl"
  ID="$(basename "$SRC" .md)"
  row="{\"ts\":\"$(date '+%Y-%m-%dT%H:%M:%S%z')\",\"ev\":\"close\",\"id\":\"$ID\",\"da\":\"$DA\",\"seat\":\"${SEAT:--}\",\"via\":\"index-move\"}"
  if ! printf '%s\n' "$row" >> "$LEDGER" 2>/dev/null; then
    # 되돌리기도 실패할 수 있다(DA r1 R1) — 성공 문구는 되돌리기가 «실제로» 성공했을 때만.
    if { [ "$TRACKED" = 1 ] && git mv "$NEW" "$SRC"; } || { [ "$TRACKED" != 1 ] && mv "$NEW" "$SRC"; }; then
      echo "REJECT 원장에 못 썼다: $LEDGER — 이동을 되돌렸다"; exit 1
    fi
    echo "REJECT 원장에 못 썼다: $LEDGER" >&2
    echo "★되돌리기 실패 — 카드 ${NEW} · 원장 0 · 복구: git mv ${NEW} ${SRC}★" >&2; exit 3
  fi
fi
printf -- '- %s — %s→%s%s%s\n' "$(date '+%Y-%m-%d %H:%M')" "$FROM" "$DST" "${SEAT:+ · 좌석 $SEAT}" "${DA:+ · DA $DA}" >> "$NEW"
printf 'MOVED %s→%s %s\n' "$FROM" "$DST" "$NEW"
if [ "$DST" = 완성 ]; then
  # 정본 갱신 신호(SB-arch-canon-standing-seat-r2 §구현 범위 1) — seats.json role=arch-canon 현역 좌석에 mbox 1건.
  #   게이트 아님: 좌석이 없거나 발신이 실패해도 이동은 이미 끝났고 exit 0 이다(경고 1줄만). 회복 경로 = CANON-DEBT 미반영 행.
  SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"
  CANON="$(python3 - "$SEATS" <<'PY' 2>/dev/null
import json, sys
s = json.load(open(sys.argv[1]))
s = s.get("seats", s)
print(next((k for k, v in s.items() if isinstance(v, dict) and v.get("role") == "arch-canon" and "_replaced_by" not in v), ""))
PY
)"
  if [ -z "$CANON" ]; then
    echo "WARN 정본 갱신 요청 미발신 — seats.json 에 role=arch-canon 현역 좌석 없음(이동은 완료 · CANON-DEBT 에 «미반영» 행을 손으로 추가)"
  elif ! bash "${FT_MBOX:-$ROOT/.fable-team/comm/mbox.sh}" send "$CANON" "${SEAT:-ft-index-move}" "[정본 갱신 요청] ${NEW#"$ROOT"/} · DA $DA · ${CANON_NOTE:-}" >/dev/null 2>&1; then
    echo "WARN 정본 갱신 요청 발신 실패 → $CANON (이동은 완료 · CANON-DEBT 에 «미반영» 행을 손으로 추가)"
  else
    echo "NOTIFIED 정본 갱신 요청 → $CANON"
  fi
fi
