#!/usr/bin/env bash
# ft-live-put.sh — r1704: 팩 git 그 판(--ref) 의 blob 하나를 라이브 dest 로 «git 모드 그대로» 설치한다(100755 → 755 · 100644 → 644).
#   손 chmod 755 고정을 없애는 공용 설치 함수 — ft-live-bin-drift-check.sh:80 의 모드 대응(100755 ↔ -x)과 같은 규칙.
#   사용: bash ft-live-put.sh --repo <리포> --ref <sha|ref> --path <리포 안 경로> --dest <파일> [--bak <표식>]
#   출력 1줄: `PUT <dest> mode=<755|644> blob=<12자>` rc0 · 그 밖은 `ERROR …` / `FAIL …` rc≠0 (하드 룰 20 — 조용한 통과 0)
#   A3: dest 가 이미 있으면 덮기 전에 <dest>.bak-<표식> 으로 둔다(표식 필수 · 같은 이름 bak 이 있으면 그대로 둔다). A5: 쓰기 뒤 대조 실패 = 되돌림 안내 1줄(자동 되돌림 0).
set -uo pipefail
die() { echo "$1"; exit "${2:-1}"; }
REPO=""; REF=""; PATH_IN=""; DEST=""; BAK=""
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="${2:-}"; shift 2;; --ref) REF="${2:-}"; shift 2;; --path) PATH_IN="${2:-}"; shift 2;;
  --dest) DEST="${2:-}"; shift 2;; --bak) BAK="${2:-}"; shift 2;;
  *) die "ERROR 사용법: --repo <리포> --ref <sha|ref> --path <경로> --dest <파일> [--bak <표식>]";;
esac; done
[ -n "$REPO" ] && [ -n "$REF" ] && [ -n "$PATH_IN" ] && [ -n "$DEST" ] || die "ERROR 인자 부족: --repo --ref --path --dest 가 모두 필요하다"
[ -d "$REPO" ] || die "ERROR 리포 없음: $REPO"
SHA="$(git -C "$REPO" rev-parse --verify -q "$REF^{commit}" 2>/dev/null)" || die "ERROR git 조회 실패: ref=$REF ($REPO)"
META="$(git -C "$REPO" ls-tree "$SHA" -- "$PATH_IN" 2>/dev/null)" || die "ERROR git 조회 실패: ls-tree rc≠0 ($REF $PATH_IN)"
[ -n "$META" ] || die "ERROR 경로 없음: $PATH_IN ($SHA)"
MODE="$(awk '{print $1}' <<<"$META")"; TYPE="$(awk '{print $2}' <<<"$META")"; BLOB="$(awk '{print $3}' <<<"$META")"
[ "$TYPE" = blob ] || die "ERROR blob 이 아닌 꼴: $PATH_IN type=$TYPE (심링크 120000·서브모듈 160000 은 설치 대상 아니다)"
case "$MODE" in 100755) WANT=755;; 100644) WANT=644;; *) die "ERROR 모르는 git 모드: $MODE ($PATH_IN)";; esac
# r1704 보정: 쓰기 전 검사(폴더·--bak·백업)를 먼저 — ERROR 경로에서 임시 파일이 dest 폴더에 남지 않는다(라이브 bin 이면 drift EXTRA)
[ -d "$(dirname "$DEST")" ] || die "ERROR dest 폴더 없음: $(dirname "$DEST")"
# r1704 보정 3(DA R1): CDPATH 가 있으면 cd 가 경로를 stdout 에 찍어 DEST 가 두 줄이 된다 → CDPATH 비우고 출력 버림 · cd 실패 = ERROR 1줄(쓰기 0)
DEST_ABS="$(CDPATH= cd -- "$(dirname "$DEST")" >/dev/null 2>&1 && pwd)" || die "ERROR dest 폴더 경로 해석 실패: $(dirname "$DEST")"
DEST="$DEST_ABS/$(basename "$DEST")"   # 상대 --dest 도 절대화 — 뒤 hash-object 가 cwd(REPO) 기준으로 읽지 않게
BAKED=""
if [ -e "$DEST" ]; then
  [ -n "$BAK" ] || die "ERROR 기존 파일이 있는데 --bak 표식이 없다: $DEST"
  BAKED="$DEST.bak-$BAK"
  [ -e "$BAKED" ] || cp -p "$DEST" "$BAKED" || die "ERROR 백업 실패: $BAKED"
fi
TMP0="$DEST.put.$$.src"
trap 'rm -f "$TMP0"' EXIT
git -C "$REPO" cat-file blob "$BLOB" > "$TMP0" 2>/dev/null || die "ERROR blob 읽기 실패: $BLOB ($PATH_IN)"   # 바이트 그대로(명령 치환은 끝 개행을 먹는다)
chmod "$WANT" "$TMP0" || die "ERROR chmod 실패: $WANT $TMP0"
mv -f "$TMP0" "$DEST" || die "ERROR mv 실패: $TMP0 → $DEST"
GOT="$(git -C "$REPO" hash-object --no-filters "$DEST")" || die "FAIL dest 해시를 못 읽었다: $DEST"
if [ "$GOT" != "$BLOB" ]; then
  die "FAIL 대조 실패(blob $BLOB ≠ dest $GOT) — 되돌림: mv ${BAKED:-<백업 없음>} $DEST" 1
fi
if [ "$WANT" = 755 ] && [ ! -x "$DEST" ]; then die "FAIL 대조 실패(실행 비트 없음) — 되돌림: mv ${BAKED:-<백업 없음>} $DEST" 1; fi
if [ "$WANT" = 644 ] && [ -x "$DEST" ]; then die "FAIL 대조 실패(실행 비트가 붙었다) — 되돌림: mv ${BAKED:-<백업 없음>} $DEST" 1; fi
echo "PUT $DEST mode=$WANT blob=${BLOB:0:12}"
