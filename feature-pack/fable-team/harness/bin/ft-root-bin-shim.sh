#!/usr/bin/env bash
# ft-root-bin-shim.sh --root <리포 루트> --live <라이브 bin> [--ref <ref>] [--repo <키트 리포>] [--path <키트 트리 경로>] [--dry-run]   (R201 · master 가 설치)
#   --repo·--path 기본 = 하네스 코드 루트(ft-harness-root.sh)의 리포 · 그 리포 기준 kit/fable-team/bin (r385 · --root 는 연결 파일을 둘 프로젝트 루트)
#   루트 `<루트>/.fable-team/bin` 의 옛 부분 사본을 «라이브 bin 으로 넘기는 연결 파일» 로 바꾼다.
#   ① `<루트>/.fable-team/LIVE_BIN` 에 라이브 경로 1줄 (+ R382: `<루트>/.fable-team/LIVE_ROOT` 데이터 루트 절대경로 1줄 — 없을 때만 만든다 · `--live-root <경로>` 없으면 라이브 bin/../.. 를 «설치 때 한 번» 풀어 적고 읽는 쪽은 유도 0 · 있으면 보존·다르면 NOTE)  ② 키트(--ref 의 --path 트리)의 *.sh·*.py 이름 중 라이브 bin 에 실재하는 것마다 연결 파일
#   ③ 연결 파일이 아닌 기존 항목(옛 사본·.bak-*·__pycache__·키트 밖 이름)은 `<루트>/.fable-team/bin.stale-<시각>/` 로 «옮긴다»(삭제 0 · 되돌리기 = 그 폴더를 bin 으로)
#     r613: 단 «git 이 추적하는 파일» 과 «로드된 LaunchAgent 의 인자 경로» 는 옮기지 않고 `남김(추적 N · 예약 대상 N): …` 1줄로 보고한다(팀 감시 데몬이 조용히 죽지 않게).
#     r616: 남긴 «예약 대상» 스크립트 본문이 부르는 같은 bin 의 키트 밖 이름도 1단계 남긴다 → `남김(추적 N · 예약 대상 N · 의존 N): …`(의존 0 이면 의존 칸 없음).
#           launchctl 목록을 못 읽으면 키트 밖 이름은 옮기지 않는다(fail-closed · 판정 불가 = 옮기기 0). git 밖 루트면 추적 판정만 생략 + WARN 1줄.
#   키트 밖 이름은 연결하지 않고 `UNKNOWN <이름>` 목록으로 보고. 멱등: 두 번째 실행 = 쓰기 0 · MOVED 0.
#   r657: 부른 쪽 셸이 -p(특권 모드)로 돌고 있으면 연결 파일도 «다음 bash 를 -p 로» 띄운다(.py 는 그대로 · 도구 쪽 -p 검사는 약화 0).
#   출력 끝줄 `SHIM n · MOVED m · UNKNOWN k` (--dry-run 은 쓰기 0 · 같은 숫자 · `PLAN …` 줄).  종료: 0 · 2 usage · 3 ERROR(조용한 통과 0)
#   r494 --init: 루트 bin 이 없을 때 루트가 «설치된 리포(공용 루트 .fable-team/LIVE_BIN 실재)의 git 워크트리 최상위» 면 bin 을 만들고 위 흐름 그대로
#     (LIVE_ROOT 기본 = 공용 루트 경로 그 자체 · 공용 루트 LIVE_ROOT 파일 값 복사 0) · 공용 루트 자체·git 밖·설치 안 된 리포 = ERROR rc3 + 사유
#   r746: 이름이 *.py 인 연결 파일은 «올바른 python» 본문으로 만든다 — 1행 `#!/usr/bin/env python3` · 2행 표식 그대로 · LIVE_BIN 검사 3종(문구·rc 3 은 bash 판과 같다) ·
#     import 하면 ImportError(크게 실패 · 조용한 성공 0) · 실행하면 os.execv(sys.executable, [라이브 사본, *argv[1:]]) — python 으로 읽는 모든 길(ast.parse · python3 직접 실행 · import)이 문법 오류 0. .sh 본문은 불변.
#     1b(arch 125): 3행 = bash·python 겸용 줄 `"exec" "python3" "$0" "$@"` — bash 로 부르면 python3 로 자기 자신을 exec · python 으로 읽으면 문자열 식(아무 일 없음) → 옛 호출 꼴 `bash <shim>.py` 도 그대로 돈다(옛 시험 단언 수정 0).
set -uo pipefail
usage() { echo "usage: $0 --root <리포 루트> --live <라이브 bin> [--live-root <데이터 루트>] [--ref <ref>] [--repo <키트 리포>] [--path <키트 경로>] [--init] [--dry-run]" >&2; exit 2; }
err()   { echo "ERROR $*"; exit 3; }
wt_common() {  # r494: $1 = 루트 → «설치된 리포의 git 워크트리 최상위» 면 공용 루트 물리 경로 · 아니면 사유 + rc1
  local rp top gd cp
  rp="$(cd -- "$1" 2>/dev/null && pwd -P)" || { echo "루트 폴더 없음: $1"; return 1; }
  top="$(git -C "$rp" rev-parse --show-toplevel 2>/dev/null)" || { echo "git 밖: $rp"; return 1; }
  [ "$(cd -- "$top" && pwd -P)" = "$rp" ] || { echo "워크트리 최상위가 아님: $rp (최상위 $top)"; return 1; }
  gd="$(git -C "$rp" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { echo "git 공용 폴더를 못 풂: $rp"; return 1; }
  cp="$(cd -- "${gd%/.git}" 2>/dev/null && pwd -P)" || { echo "공용 루트 폴더 없음: ${gd%/.git}"; return 1; }
  [ "$cp" != "$rp" ] || { echo "공용 루트 자체다: $rp — 공용 루트 설치는 install.sh --apply --project $rp"; return 1; }
  [ -f "$cp/.fable-team/LIVE_BIN" ] || { echo "설치된 리포가 아님(공용 루트 LIVE_BIN 없음): $cp/.fable-team/LIVE_BIN"; return 1; }
  echo "$cp"
}

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT=""; LIVE=""; LROOT=""; REF="${FT_DRIFT_REF:-origin/main}"; REPO=""; TPATH=""; DRY=0; INIT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift;;
    --init) INIT=1; shift;;
    --root|--live|--live-root|--ref|--repo|--path) [ $# -ge 2 ] || usage
      case "$1" in --root) ROOT="$2";; --live) LIVE="$2";; --live-root) LROOT="$2";; --ref) REF="$2";; --repo) REPO="$2";; --path) TPATH="$2";; esac; shift 2;;
    *) usage;;
  esac
done
[ -n "$ROOT" ] && [ -n "$LIVE" ] || usage
case "$LIVE" in /*) ;; *) err "--live 는 절대경로(/ 로 시작)여야 한다: $LIVE";; esac
NEWBIN=0; WTC=""   # r494: 새로 만들 bin · 워크트리의 공용 루트
if [ ! -d "$ROOT/.fable-team/bin" ]; then
  [ "$INIT" = 1 ] || err "루트 bin 없음: $ROOT/.fable-team/bin (새 워크트리면 --init)"
  WTC="$(wt_common "$ROOT")" || err "--init 불가 — $WTC"
  NEWBIN=1
elif [ "$INIT" = 1 ]; then WTC="$(wt_common "$ROOT")" || WTC=""; fi   # bin 있는 루트 = 지금 흐름 · LIVE_ROOT 기본값만 같은 규칙
[ -d "$LIVE" ] || err "라이브 bin 없음: $LIVE"
ROOT="$(cd -- "$ROOT" && pwd)"; LIVE="$(cd -- "$LIVE" && pwd)"
if [ -n "$LROOT" ]; then case "$LROOT" in /*) ;; *) err "--live-root 는 절대경로(/ 로 시작)여야 한다: $LROOT";; esac; [ -d "$LROOT" ] || err "--live-root 폴더 없음: $LROOT"; LROOT="$(cd -- "$LROOT" && pwd)"
elif [ -n "$WTC" ]; then LROOT="$WTC"
else LROOT="$(cd -- "$LIVE/../.." 2>/dev/null && pwd)" || err "LIVE_ROOT 를 라이브 bin/../.. 로 풀지 못했다: $LIVE (--live-root 로 지정)"; fi
RBIN="$ROOT/.fable-team/bin"
if [ -z "$REPO" ] || [ -z "$TPATH" ]; then  # 키트 트리 = 하네스 코드 루트(팩) 리포 · 프로젝트 루트(--root) 리포가 아니다 (r385)
  [ -f "$HERE/ft-harness-root.sh" ] || err "해석기 없음: $HERE/ft-harness-root.sh — --repo·--path 를 준다"; . "$HERE/ft-harness-root.sh"
  hr="$(ft_harness_root "$HERE")" || err "하네스 루트를 못 풂(FT_HARNESS_ROOT · ../HARNESS_ROOT 없음) — --repo·--path 를 준다"
  rk="$(ft_harness_kit "$hr")" || err "하네스 루트가 git 안이 아님: $hr — --repo·--path 를 준다"
  [ -n "$REPO" ] || REPO="${rk%%$'\t'*}"; [ -n "$TPATH" ] || TPATH="${rk#*$'\t'}"
fi
sha="$(git -C "$REPO" rev-parse --verify -q "$REF^{commit}")" || err "ref 를 풀 수 없음: $REF (repo=$REPO)"
kit="$(git -C "$REPO" ls-tree --name-only "$sha" "${TPATH%/}/")" || err "ls-tree 실패: $REF:$TPATH"
[ -n "$kit" ] || err "ref 에 경로가 없음: $REF:$TPATH"
kitnames="$(printf '%s\n' "$kit" | sed 's|.*/||')"
if [ "$NEWBIN" = 1 ]; then  # r494: 모든 검사를 통과한 뒤에만 만든다(ERROR = 생성 0)
  if [ "$DRY" = 1 ]; then echo "PLAN init $RBIN (새 워크트리 · 공용 루트 $WTC)"
  else mkdir -p "$RBIN" || err "bin 못 만듦: $RBIN"; echo "INIT $RBIN (새 워크트리 · 공용 루트 $WTC)"; fi
fi

MARK="# ft-root-bin-shim:"
shim_body_py() {  # $1 = 도구 이름(*.py) — r746: 이름이 .py 면 «올바른 python» 본문(실행 = os.execv 로 라이브 사본 · import = ImportError)
  local name="$1"
  cat <<EOF
#!/usr/bin/env python3
$MARK $name → LIVE_BIN (루트 옛 사본이 아니다 — ft-root-bin-shim.sh 생성 · 수정하지 말 것)
"exec" "python3" "\$0" "\$@"
import os
import sys

_h = os.path.dirname(os.path.abspath(__file__))
_f = os.path.join(_h, "..", "LIVE_BIN")
_l = ""
if os.path.isfile(_f):
    with open(_f, "r", encoding="utf-8", errors="replace") as _fh:
        _l = _fh.readline().strip()
if not _l:
    print("ERROR LIVE_BIN 이 없거나 비었다: " + _f)
    sys.exit(3)
if not _l.startswith("/"):
    print("ERROR LIVE_BIN 이 절대경로(/ 로 시작)가 아니다: " + _l + " (" + _f + ")")
    sys.exit(3)
_t = os.path.join(_l, "$name")
if not os.path.isfile(_t):
    print("ERROR 라이브 도구 없음: " + _t)
    sys.exit(3)
if __name__ != "__main__":
    raise ImportError("ft-root-bin-shim 의 .py 연결 파일이다 — import 하지 말고 LIVE_BIN 사본을 import 하거나 도구로 실행한다: " + _t)
os.execv(sys.executable, [sys.executable, _t] + sys.argv[1:])
EOF
}

shim_body() {  # $1 = 도구 이름
  local name="$1" runner="bash" runline
  case "$name" in *.py) shim_body_py "$name"; return;; esac
  # r657: 부른 쪽 셸에 p(특권 모드)가 있으면 «같은 해석기로 -p» 를 붙여 넘긴다.
  #       -p 없이 불렀으면 지금과 같은 맨 bash — 도구 쪽 «-p 아니면 거절» 검사는 그대로(약화 0).
  runline="exec $runner \"\$_l/$name\" \"\$@\""
  if [ "$runner" = bash ]; then
    runline="case \"\$-\" in *p*) exec \"\${BASH:-bash}\" -p \"\$_l/$name\" \"\$@\";; esac"$'\n'"$runline"
  fi
  cat <<EOF
#!/usr/bin/env bash
$MARK $name → LIVE_BIN (루트 옛 사본이 아니다 — ft-root-bin-shim.sh 생성 · 수정하지 말 것)
_h="\$(cd -- "\$(dirname -- "\${BASH_SOURCE[0]:-\$0}")" && pwd)"
_f="\$_h/../LIVE_BIN"
_l=""; [ -f "\$_f" ] && _l="\$(sed -n '1p' "\$_f" | tr -d '\\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*\$//')"
[ -n "\$_l" ] || { echo "ERROR LIVE_BIN 이 없거나 비었다: \$_f"; exit 3; }
case "\$_l" in /*) ;; *) echo "ERROR LIVE_BIN 이 절대경로(/ 로 시작)가 아니다: \$_l (\$_f)"; exit 3;; esac
[ -f "\$_l/$name" ] || { echo "ERROR 라이브 도구 없음: \$_l/$name"; exit 3; }
$runline
EOF
}

nshim=0; nmoved=0; unknown=""; nunk=0; tomove=""
want=""  # 연결 대상 이름
while IFS= read -r n; do
  [ -n "$n" ] || continue
  case "$n" in *.sh|*.py) ;; *) continue;; esac
  [ -f "$LIVE/$n" ] || continue
  want="$want$n"$'\n'
done <<< "$kitnames"

# 기존 항목 분류: 연결 파일(그대로 두거나 갱신) / 옮길 것 / 남길 것(r613)
shopt -s nullglob dotglob
cand=""
for p in "$RBIN"/*; do
  n="${p##*/}"
  if [ -f "$p" ] && [ ! -L "$p" ] && head -3 "$p" | grep -qF "$MARK" && grep -qxF -- "$n" <<< "$want"; then continue; fi
  cand="$cand$n"$'\n'
done
shopt -u nullglob dotglob

# r613 남김 판정 준비 — ⓐ git 추적(`ls-files`) ⓑ 예약 대상(`launchctl print` 인자 안의 그 bin 아래 경로)
gitok=1; git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || gitok=0
if [ -n "$cand" ] && [ "$gitok" = 0 ]; then echo "WARN git 밖 — 추적 판정 생략: $ROOT"; fi
refs=""; lctl_ok=0
if [ -n "$cand" ]; then   # launchctl 은 1회만 읽는다(Label 전수 · print 출력을 한 덩어리로 · FT_SHIM_LAUNCHCTL 주입점)
  lctl="${FT_SHIM_LAUNCHCTL:-launchctl}"
  if list="$("$lctl" list 2>/dev/null)" && [ -n "$list" ]; then
    while IFS= read -r lbl; do
      [ -n "$lbl" ] || continue
      one=""
      for dom in "gui/$(id -u)" system; do one="$("$lctl" print "$dom/$lbl" 2>/dev/null)" && [ -n "$one" ] && break; done
      refs="$refs$one"$'\n'
    done <<< "$(printf '%s\n' "$list" | awk 'NR>1 && NF>=3 {print $3}')"
    lctl_ok=1
  else
    echo "남김 판정 불가 — 키트 밖 이름 옮기기 0 (launchctl 목록 못 읽음)"
  fi
fi

nkeep=0; ntracked=0; nresv=0; kept=""; unk_kept=""; keptresv=""; unkcand=""
while IFS= read -r n; do
  [ -n "$n" ] || continue
  isunk=0
  if ! grep -qxF -- "$n" <<< "$kitnames" && ! case "$n" in *.bak*|__pycache__) true;; *) false;; esac; then isunk=1; fi
  trk=0
  if [ "$gitok" = 1 ] && [ -n "$(git -C "$ROOT" ls-files -- ".fable-team/bin/$n" 2>/dev/null)" ]; then trk=1; fi
  resv=0
  if [ "$lctl_ok" = 1 ]; then case "$refs" in *"$RBIN/$n"*) resv=1;; esac; fi
  if [ "$trk" = 1 ] || [ "$resv" = 1 ] || { [ "$isunk" = 1 ] && [ "$lctl_ok" = 0 ]; }; then
    nkeep=$((nkeep + 1)); [ "$trk" = 1 ] && ntracked=$((ntracked + 1)); [ "$resv" = 1 ] && nresv=$((nresv + 1))
    kept="$kept$n"$'\n'; [ "$isunk" = 1 ] && unk_kept="$unk_kept$n"$'\n'
    [ "$resv" = 1 ] && keptresv="$keptresv$n"$'\n'
    continue
  fi
  tomove="$tomove$n"$'\n'
  if [ "$isunk" = 1 ]; then unknown="$unknown$n"$'\n'; nunk=$((nunk + 1)); unkcand="$unkcand$n"$'\n'; fi
done <<< "$cand"
# r616: «의존 1단계» — 예약 대상으로 남긴 스크립트 본문이 부르는 «같은 bin 의 키트 밖 이름» 도 남긴다(의존의 의존은 범위 밖 · 폴더·바이너리 본문 검사 생략)
ndep=0
if [ -n "$keptresv" ] && [ -n "$unkcand" ]; then
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ -f "$RBIN/$s" ] || continue
    LC_ALL=C grep -Iq . "$RBIN/$s" 2>/dev/null || continue   # 바이너리·빈 파일 = 검사 생략
    toks="$(LC_ALL=C tr -cs 'A-Za-z0-9._-' '\n' < "$RBIN/$s")"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      grep -qxF -- "$d" <<< "$toks" || continue             # 본문에 그 이름이 낱말로 나와야 한다
      grep -qxF -- "$d" <<< "$kept" && continue             # 이미 남긴 이름
      nkeep=$((nkeep + 1)); ndep=$((ndep + 1)); kept="$kept$d"$'\n'
      tomove="$(printf '%s' "$tomove" | grep -vxF -- "$d")"$'\n'
      if grep -qxF -- "$d" <<< "$unknown"; then
        unknown="$(printf '%s' "$unknown" | grep -vxF -- "$d")"$'\n'; nunk=$((nunk - 1))
      fi
    done <<< "$unkcand"
  done <<< "$keptresv"
fi
if [ "$nkeep" -gt 0 ]; then
  fmt="$(printf '%s' "$kept" | grep . | head -5 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  if [ "$ndep" -gt 0 ]; then echo "남김(추적 $ntracked · 예약 대상 $nresv · 의존 $ndep): $fmt"
  else echo "남김(추적 $ntracked · 예약 대상 $nresv): $fmt"; fi
fi
nmoved=$(printf '%s' "$tomove" | grep -c .)

STALE="$ROOT/.fable-team/bin.stale-$(date +%Y%m%d-%H%M%S)"
if [ "$nmoved" -gt 0 ]; then
  while IFS= read -r n; do [ -n "$n" ] || continue
    if [ "$DRY" = 1 ]; then echo "PLAN move $n → ${STALE##*/}/"; else
      [ -d "$STALE" ] || mkdir -p "$STALE" || err "stale 폴더 못 만듦: $STALE"
      mv -- "$RBIN/$n" "$STALE/$n" || err "옮기기 실패: $n"
    fi
  done <<< "$tomove"
fi
[ -z "$unknown" ] || while IFS= read -r n; do [ -n "$n" ] && echo "UNKNOWN $n (키트 밖 — 연결 0 · stale 로 옮김)"; done <<< "$unknown"
[ -z "$unk_kept" ] || while IFS= read -r n; do [ -n "$n" ] && echo "UNKNOWN $n (키트 밖 — 연결 0 · 남김)"; done <<< "$unk_kept"

lr_cur=""; [ -f "$ROOT/.fable-team/LIVE_ROOT" ] && lr_cur="$(sed -n '1p' "$ROOT/.fable-team/LIVE_ROOT")"
if [ "$DRY" = 1 ]; then echo "PLAN LIVE_BIN=$LIVE → $ROOT/.fable-team/LIVE_BIN"; [ -n "$lr_cur" ] && echo "PLAN LIVE_ROOT 보존 $lr_cur" || echo "PLAN LIVE_ROOT=$LROOT → $ROOT/.fable-team/LIVE_ROOT"
else
  cur=""; [ -f "$ROOT/.fable-team/LIVE_BIN" ] && cur="$(sed -n '1p' "$ROOT/.fable-team/LIVE_BIN")"
  [ "$cur" = "$LIVE" ] || printf '%s\n' "$LIVE" > "$ROOT/.fable-team/LIVE_BIN" || err "LIVE_BIN 쓰기 실패"
  if [ -z "$lr_cur" ]; then printf '%s\n' "$LROOT" > "$ROOT/.fable-team/LIVE_ROOT" || err "LIVE_ROOT 쓰기 실패"; echo "LIVE_ROOT $LROOT (새로 씀)"
  elif [ "$lr_cur" != "$LROOT" ]; then echo "NOTE LIVE_ROOT 보존 $lr_cur (이번 값 $LROOT 와 다름 — 바꾸려면 파일 1줄을 손으로 고친다)"; fi
fi
while IFS= read -r n; do [ -n "$n" ] || continue
  nshim=$((nshim + 1))
  [ "$DRY" = 1 ] && continue
  body="$(shim_body "$n")"
  if [ ! -f "$RBIN/$n" ] || [ "$(cat "$RBIN/$n")" != "$body" ]; then printf '%s\n' "$body" > "$RBIN/$n" || err "연결 파일 쓰기 실패: $n"; fi
  [ -x "$RBIN/$n" ] || chmod 755 "$RBIN/$n"
done <<< "$want"
[ "$DRY" = 1 ] && echo "PLAN shim n=$nshim"
echo "SHIM $nshim · MOVED $nmoved · UNKNOWN $nunk"
exit 0
