#!/usr/bin/env bash
# ft-sheet-publish.sh — 시트 슬랙 발행 (PLAN-status-sheet r4 §4·§4-1 · S2). `ft-board-publish.sh --sheet` 가 부른다.
#   뿌리 글 = render --sheet 트리(≤3500B) + 끝줄 «📄 최신 PDF rev <발행 rev> <HH:MM> <PDF 첨부 링크>»
#   발행 rev(렌더 md 전체의 정규화 해시)가 마지막 «업로드 성공» rev 와 다를 때만 PDF → 같은 스레드 첨부. 같은 rev 재실행 = 슬랙 호출 0.
#   순서: plan(원장 admission) → 로컬 준비(root·html·md·PDF) 전부 → update → attach → append → 끝줄 update → 기록. 준비·admission 실패 = 슬랙 호출 0.
#   rc: 0 | 2 부분 발행(쪽지함 말고 다른 원인의 일부 팀 «확인 못 함» — 나머지 팀은 발행됨 · 판정 r554) | 3 PDF 첨부 실패(끝줄에 «미갱신» · 다음 틱 재시도 · 원장 ok=false) | 그 밖 = 도구 rc 그대로(발행 0)
#       쪽지함 조회만 늦은 팀 = 발행 성공 rc 0 + 끝줄 «PARTIAL inbox-fail=<팀들>»(r677 · 보이는 경고 + ERROR 로그 + 명시 표시)
#       전 팀 수집 실패 = 지금과 같은 발행 0 · rc 1(한 팀 실패를 «건너뛰고 경고만» 으로 안 삼키는 자리)
# env: FT_ROOT · FT_BOARD_BIN · FT_THREAD_POST · FT_BOARD_POST_ARGS · FT_BOARD_LEDGER · FT_BOARD_NOW(시험) ·
#      FT_SHEET_MIRROR_DIR(magazine_pdf 폴더 · 기본 = TP 폴더 · 항상 export) · FT_SHEET_LEDGER(발행 원장) · FT_SHEET_PDF_BIN(`<html> <pdf>` → 쪽수 stdout · 시험은 스텁)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BOARD="${FT_BOARD_BIN:-$HERE/ft-board.py}"
TP="${FT_THREAD_POST:-$HOME/.hermes/scripts/byz_thread_post.py}"
ROOT="${FT_ROOT:-}"   # r385b: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 2
NOW="${FT_BOARD_NOW:-$(date +%Y-%m-%dT%H:%M:%S)}"; DAY="${NOW:0:10}"
SD="$ROOT/.fable-team/state/board/$DAY"; LEDGER="${FT_SHEET_LEDGER:-$ROOT/.fable-team/state/sheet-publish.jsonl}"
PDF="${FT_SHEET_PDF_BIN:-python3 $HERE/ft_sheet_publish.py pdf}"
SP="python3 $HERE/ft_sheet_publish.py"
die() { echo "ft-sheet-publish: $1" >&2; exit "${2:-1}"; }
[ -f "$TP" ] || die "도구 없음 $TP (#0 RULE · 폴백 0)" 2
export FT_SHEET_MIRROR_DIR="${FT_SHEET_MIRROR_DIR:-$(dirname "$TP")}"  # magazine_pdf 위치 — plist 환경 0 · 현재 폴더 탐색 0
# shellcheck disable=SC2206
POST_ARGS=(${FT_BOARD_POST_ARGS:-}); [ -n "${FT_BOARD_LEDGER:-}" ] && POST_ARGS+=(--ledger "$FT_BOARD_LEDGER")
tp() { python3 "$TP" "$1" ${POST_ARGS[@]+"${POST_ARGS[@]}"} "${@:2}"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$BOARD" collect --out "$TMP/collect.json" --refresh-gh || die "collect 실패 — 발행 0" 1  # 수집은 한 틱에 1회 — 아래 render·snapshot 은 전부 이 파일을 읽는다(--from)
# r554: 한 팀 수집 실패 = 그 팀 칸 «확인 못 함»(collect 가 stderr ERROR 줄을 낸다) — 나머지 팀은 발행한다. rc 는 원인으로 가른다(r677)
read -r NTEAM NERR NINBOX INBOXFAIL < <(python3 -c 'import json,sys; t=json.load(open(sys.argv[1], encoding="utf-8"))["teams"]; b=[x for x in t if x.get("error")]; print(len(t), len(b), sum(1 for x in b if x.get("inbox_fail")), ",".join(x["label"] for x in b if x.get("inbox_fail")))' "$TMP/collect.json") || die "collect 결과 해석 실패 — 발행 0" 1
[ "$NTEAM" -eq 0 ] || [ "$NERR" -lt "$NTEAM" ] || die "모든 팀($NERR/$NTEAM) 수집 실패 — 발행 0" 1
# r677: 쪽지함 조회만 늦은 팀(NINBOX)은 발행 성공으로 본다 — 그 팀 칸은 «확인 불가»(collect) · 끝줄에 PARTIAL · stderr ERROR 1줄
PARTIAL=$([ "$NERR" -gt "$NINBOX" ] && echo 1 || echo 0)  # 그 밖의 원인 = 지금처럼 rc 2(부분 발행)
exitv() { local c="$1"; [ "$PARTIAL" = 1 ] && [ "$c" -eq 0 ] && c=2; exit "$c"; }  # 부분 발행 = rc 2(조용한 성공 0)
FROM=(--from "$TMP/collect.json")
REVS="$("$BOARD" render --sheet --rev "${FROM[@]}")" || die "render --sheet --rev 실패 — 발행 0" 1
read -r STRUCT PUBREV < <(printf '%s' "$REVS" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["structure"], d["publish"])') || die "rev 해석 실패" 1
TREE="$("$BOARD" render --sheet --text "${FROM[@]}")" && [ -n "$TREE" ] || die "render --sheet --text 실패 — 발행 0" 1
PLAN="$($SP plan --ledger "$LEDGER" --day "$DAY" --rev "$PUBREV")" || die "발행 원장 admission 실패 — 슬랙 호출 0" 1  # 원장 쓰기 불가면 맨 앞에서 중단
eval "$PLAN"
mkdir -p "$SD"
mkroot() { printf '%s' "$TREE" | $SP root --ledger "$LEDGER" --day "$DAY" --rev "$PUBREV" --partial "$INBOXFAIL" > "$TMP/root.txt" || die "뿌리 글 본문 만들기 실패 — 발행 0" 1; }
mkroot
same() { cmp -s <(sed -E 's/[0-9]{2}:[0-9]{2}//g; s/멈춤 [0-9]+분/멈춤 N분/g' "$TMP/root.txt") <(sed -E 's/[0-9]{2}:[0-9]{2}//g; s/멈춤 [0-9]+분/멈춤 N분/g' "$SD/sheet-published.txt" 2>/dev/null); }  # 발행 rev 와 같은 정규화
if [ "$OK_REV" = "$PUBREV" ]; then  # 같은 rev — 슬랙 끝줄까지 맞아 있으면 발행 0 · 끝줄 update 만 실패했던 틱이면 update 1회 + 기록(PDF·원장 0)
  same && { echo "ft-sheet-publish: 같은 발행 rev $PUBREV — 발행 0"; exitv 0; }
  tp update --key "board:$DAY" --text-file "$TMP/root.txt" || die "끝줄 맞춤 update 실패" 1
  cp "$TMP/root.txt" "$SD/sheet-published.txt" || die "발행 기록 쓰기 실패" 1; exitv 0
fi
NEED_PDF=1; [ "$TODAY_OK" -ge 24 ] && NEED_PDF=0
[ "$NEED_PDF" = 0 ] && same && { echo "ft-sheet-publish: 상한 — 변화 없음"; exitv 0; }

# 변화 답글 = 구조 rev 가 직전 발행과 다를 때만(이야기·상세만 바뀌면 0)
REPLY=""
if [ -f "$SD/sheet-struct-rev" ] && [ "$(cat "$SD/sheet-struct-rev")" != "$STRUCT" ]; then
  SNAP="$("$BOARD" snapshot "${FROM[@]}")" || die "snapshot 실패 — 발행 0" 1
  REPLY="$(printf '%s' "$SNAP" | python3 -c 'import json,sys
d=json.load(sys.stdin); c=d["changes"]; print(" · ".join(c[:8]) + (" 외 %d건" % (len(c)-8) if len(c)>8 else "") + " · snap=" + d["snap"] if c else "")')" || die "snapshot 출력 해석 실패" 1
fi

# 로컬 준비 «전부» 를 슬랙 호출 전에 끝낸다 — render html/md · PDF 변환(6쪽 초과면 «자세히» 를 접어 재변환 + 전체 md 를 같은 첨부에)
prep() {
  "$BOARD" render --sheet --html "${FROM[@]}" > "$TMP/sheet.html" && "$BOARD" render --sheet "${FROM[@]}" > "$TMP/sheet-$PUBREV.md" || die "render --sheet html/md 실패 — 슬랙 호출 0" 1
  PAGES="$($PDF "$TMP/sheet.html" "$TMP/sheet-$PUBREV.pdf")" || die "PDF 변환 실패 — 슬랙 호출 0" 1
  FILES=(--file "$TMP/sheet-$PUBREV.pdf")
  if [ "$PAGES" -gt 6 ]; then
    $SP fold < "$TMP/sheet.html" > "$TMP/sheet-fold.html" && PAGES="$($PDF "$TMP/sheet-fold.html" "$TMP/sheet-$PUBREV.pdf")" || die "접힌 PDF 변환 실패 — 슬랙 호출 0" 1
    FILES+=(--file "$TMP/sheet-$PUBREV.md")
  fi
}
[ "$NEED_PDF" = 1 ] && prep  # F1

ARGS=(--key "board:$DAY" --text-file "$TMP/root.txt"); [ -n "$REPLY" ] && ARGS+=(--reply "$REPLY")
tp update "${ARGS[@]}"; rc=$?
{ [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; } || exit "$rc"
if [ "$NEED_PDF" = 0 ]; then  # 상한 — 원장 쓰기 없음
  cp "$TMP/root.txt" "$SD/sheet-published.txt" && printf '%s' "$STRUCT" > "$SD/sheet-struct-rev" || die "발행 기록 쓰기 실패" 1
  exitv "$rc"
fi

NOW_ARGS=(--ledger "$LEDGER" --rev "$PUBREV" --now "$NOW")
if OUT="$(tp attach --key "board:$DAY" "${FILES[@]}" --title "시트 rev $PUBREV" 2>"$TMP/attach.err")"; then
  LINK="$(printf '%s' "$OUT" | sed -n 's/.*link=\([^ ]*\).*/\1/p')"; PTS="$(printf '%s' "$OUT" | sed -n 's/.*ts=\([^ ]*\).*/\1/p')"
  [ -n "$LINK" ] || die "attach 출력에 link 없음: $OUT" 1
  $SP append "${NOW_ARGS[@]}" --ok 1 --pdf-ts "$PTS" --pdf-url "$LINK" || die "발행 원장 쓰기 실패" 1
  rc=0
else
  cat "$TMP/attach.err" >&2; echo "ft-sheet-publish: PDF 첨부 실패 rev=$PUBREV — 끝줄 미갱신 · 다음 틱 재시도" >&2
  $SP append "${NOW_ARGS[@]}" --ok 0 || die "발행 원장 쓰기 실패" 1
  rc=3
fi
# published/struct 기록은 원장 append 성공 «뒤» 에만 — 그 뒤 틱이 원장 없이 재발행하지 않게
mkroot; tp update --key "board:$DAY" --text-file "$TMP/root.txt" || die "끝줄 갱신 실패" 1
cp "$TMP/root.txt" "$SD/sheet-published.txt" && printf '%s' "$STRUCT" > "$SD/sheet-struct-rev" || die "발행 기록 쓰기 실패" 1
exitv "$rc"
