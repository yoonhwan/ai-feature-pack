#!/usr/bin/env bash
# ft-nano-cherry-gate.sh <feat 브랜치> <nano 브랜치> [--repo <dir>]
#   ft-nano-close.sh 의 «산출물이 들어왔는가» 게이트 (G4 · 골좌표 M7 — 나노 브랜치에만 남은 커밋은 feat push 가 따라오지 않는다).
#   `git cherry <feat> <nano>` 의 «+»(feat 에 같은 patch 가 없는 커밋): design/ 밖 경로를 건드린 것이 있으면 목록 출력 + exit 1 ·
#   design/ 만 건드린 «+» 는 WARN 목록 + exit 0(브랜치 보존으로 복구 가능 — G4 실측 docs-only 134 를 전부 막으면 닫기 정지) · «+» 0 이면 `OK` + exit 0.
#   코드 «+» 는 ①merge-tree 실제 delta 가 design/ 밖 0 → PASS(content_landed_via_merge_tree) ②충돌·delta 면 «+» 경로마다 tip 의 (mode,blob) 이 feat 역사에 있으면 PASS(content_landed_then_superseded) ③아니면 REJECT.
#   면제 목록·무조건 우회 없음. 유일한 사람 우회 = `--override "<사유>"`(코드 «+» 의 내용 REJECT 만 · 사유 빈 문자열 거부 · ERROR 로그 + 원장 1행 — #0 RULE 예외 3조건).
#   --mode land|close (기본 close = 위 동작 그대로): land = 랜딩 «요청» 시점 — nano 가 feat HEAD 를 조상으로 포함(최신 루트 병합 완료)하지 않으면 REJECT(M7 · single_set_testing §2 규칙 2).
#   close 에는 이 검사를 걸지 않는다 — squash 랜딩 뒤엔 feat 가 앞서 가 «포함» 이 항상 거짓이다(REVIEW arch141 §2-3).
#   exit 0 = 통과 · 1 = REJECT(+ 있음 / ref 없음 / git 실패 — 전부 사유 stdout) · 2 = usage. ★침묵 통과 0★ — 어느 경로든 한 줄 이상 출력한다.
set -uo pipefail
FEAT="${1:-}"; NANO="${2:-}"; shift 2 2>/dev/null || { echo "usage: $0 <feat-branch> <nano-branch> [--repo <dir>] [--mode land|close] [--override <사유>]" >&2; exit 2; }
REPO="."; HAVE_OVERRIDE=0; OVERRIDE=""; MODE="close"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-.}"; shift 2 2>/dev/null || shift ;;
    --mode) MODE="${2:-}"; shift 2 2>/dev/null || shift
            case "$MODE" in land|close) ;; *) echo "usage: --mode land|close (받은 값: ${MODE:-<빈 값>})" >&2; exit 2 ;; esac ;;
    --override) HAVE_OVERRIDE=1; OVERRIDE="${2:-}"; shift 2 2>/dev/null || shift ;;
    *) echo "usage: $0 <feat-branch> <nano-branch> [--repo <dir>] [--mode land|close] [--override <사유>]" >&2; exit 2 ;;
  esac
done
if [ "$HAVE_OVERRIDE" -eq 1 ] && [ -z "${OVERRIDE//[[:space:]]/}" ]; then
  echo "REJECT cherry 게이트 — --override 사유가 비어 있음(사유 없는 우회 거부)"; exit 1
fi
for r in "$FEAT" "$NANO"; do
  git -C "$REPO" rev-parse --verify -q "refs/heads/$r" >/dev/null || { echo "REJECT cherry 게이트 — 브랜치 없음: $r (refs/heads/)"; exit 1; }
done
if [ "$MODE" = land ] && ! git -C "$REPO" merge-base --is-ancestor "$FEAT" "$NANO"; then
  _mb="$(git -C "$REPO" merge-base "$FEAT" "$NANO" 2>/dev/null)"
  echo "REJECT cherry 게이트 — land: $NANO 가 feat HEAD($(git -C "$REPO" rev-parse --short "$FEAT"))를 포함하지 않음(merge-base ${_mb:0:7}) — 최신 루트를 병합한 뒤 다시 랜딩 요청 (docs/rules/single_set_testing.md §3 ②)"
  exit 1
fi
out="$(git -C "$REPO" cherry "$FEAT" "$NANO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "REJECT cherry 게이트 — git cherry 실패(rc=$rc): ${out:0:120}"; exit 1; }
plus="$(printf '%s\n' "$out" | grep '^+' || true)"
# «+» 커밋을 둘로 가른다 — design/ 밖 경로(코드·시험·스크립트)를 건드린 것 = 차단 · design/ 만 건드린 것 = WARN 통과(브랜치가 남아 복구 가능 · arch#137)
#   ★경로 목록은 변수로 «완독» 한 뒤 분류한다(DA 575 H2: `diff-tree | grep -qv` 는 grep 조기 종료 → SIGPIPE → 큰 혼합 커밋이 «design/ 만» 으로 판정) · diff-tree·log 각 rc 를 따로 본다(H1: 실패가 WARN 통과)★
block=""; warn=""
delta_file="$(mktemp)"; plus_file="$(mktemp)"; trap 'rm -f "$delta_file" "$plus_file"' EXIT
while read -r _ sha; do
  [ -n "$sha" ] || continue
  line="$(git -C "$REPO" log -1 --format='  + %h %s' "$sha")"; lrc=$?
  [ "$lrc" -eq 0 ] && [ -n "$line" ] || { echo "REJECT cherry 게이트 — git log 실패(rc=$lrc) 커밋 ${sha:0:9}"; exit 1; }
  line="${line:0:120}"
  paths="$(git -C "$REPO" -c core.quotepath=off diff-tree --no-commit-id --name-only -r -m --root "$sha")"; prc=$?
  [ "$prc" -eq 0 ] || { echo "REJECT cherry 게이트 — git diff-tree 실패(rc=$prc) 커밋 ${sha:0:9} — 경로를 못 읽어 분류 불가"; exit 1; }
  git -C "$REPO" -c core.quotepath=false diff-tree --no-commit-id --name-only -r -m --root -z "$sha" >> "$plus_file"; zrc=$?
  [ "$zrc" -eq 0 ] || { echo "REJECT cherry 게이트 — git diff-tree -z 실패(rc=$zrc) 커밋 ${sha:0:9}"; exit 1; }
  outside=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in design/*) ;; *) outside=1; break ;; esac
  done <<< "$paths"
  if [ "$outside" -eq 1 ]; then block="${block}${line}"$'\n'; else warn="${warn}${line}"$'\n'; fi
done <<< "$plus"
nb="$(printf '%s' "$block" | grep -c . || true)"; nw="$(printf '%s' "$warn" | grep -c . || true)"
if [ "$nb" -gt 0 ]; then
  # G4c: patch-id 는 «같은 변경» 의 충분조건일 뿐(cherry-pick 이 다른 문맥 base 에 앉으면 «+» 로 남는다). 정본은 «머지하면 무엇이 바뀌나» = merge-tree.
  # ★«+» 경로와의 교집합이 아니라 «실제 merge delta»(merge-tree 결과 트리 vs feat HEAD 트리)를 본다 — rename·경로 인코딩 불일치가 교집합을 비우는 누출(DA 597 H1)★
  # design/ 밖 delta 가 하나라도 있으면 REJECT · 없으면 PASS. 종료코드는 1행 OID 와 따로 본다(5c). 경로는 -z 로 완독(quotepath 무관).
  conflict=0
  mt="$(git -C "$REPO" merge-tree --write-tree "$FEAT" "$NANO")"; mrc=$?
  if [ "$mrc" -eq 1 ]; then conflict=1
  elif [ "$mrc" -ne 0 ]; then
    echo "REJECT cherry 게이트 — git merge-tree 실패(rc=$mrc): ${mt:0:120}"; exit 1
  fi
  differ=""; ndesign=0
  if [ "$conflict" -eq 0 ]; then
    tree="${mt%%$'\n'*}"
    git -C "$REPO" -c core.quotepath=false diff-tree -r --name-only -z --no-commit-id "$FEAT^{tree}" "$tree" > "$delta_file"; drc=$?
    [ "$drc" -eq 0 ] || { echo "REJECT cherry 게이트 — git diff-tree(merge-tree 결과 대조) 실패(rc=$drc)"; exit 1; }
    while IFS= read -r -d '' p; do
      case "$p" in design/*) ndesign=$((ndesign + 1)) ;; *) differ="${differ}  ${p}"$'\n' ;; esac
    done < "$delta_file"
    if [ -z "$differ" ]; then
      echo "INFO cherry 게이트 — $NANO 의 «+» 커밋 $((nb + nw))개는 git cherry 로는 미랜딩이나 merge-tree 실제 delta 가 design/ 밖 0개(design/ ${ndesign}개) — 통과 (사유 content_landed_via_merge_tree)"
      exit 0
    fi
  fi
  # G4c r3: 반영 «뒤» feat 가 같은 파일을 더 고치면 merge-tree 는 충돌/delta 가 된다(G4b 실가동). 판정 단순화 = «이 브랜치 내용이 feat 역사에 한 번이라도 있었나».
  # «+» 커밋이 건드린 경로 P 전부(NUL 완독)에 대해 tip 의 (mode,blob) 이 feat 역사의 P 에 존재 → 전부 있으면 PASS. tip 에서 P 가 삭제됐으면 feat HEAD 에도 없을 때만 존재로 친다.
  # ★superseded 증거 = merge-base(NANO,FEAT)..FEAT 구간의 «새 blob» 뿐(DA 599 H1)★ — 분기 전 역사의 옛 blob 으로 rollback 한 브랜치를 PASS 시키지 않는다.
  mbase="$(git -C "$REPO" merge-base "$NANO" "$FEAT")"; mbrc=$?
  [[ "$mbrc" -eq 0 && "$mbase" =~ ^[0-9a-f]{40,64}$ ]] || { echo "REJECT cherry 게이트 — git merge-base 실패(rc=$mbrc) — superseded 증거 구간을 못 정함"; exit 1; }
  sort -z -u -o "$plus_file" "$plus_file"
  nsup=0; nmiss=0; missing=""; sup_commit=""
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    [ "$nmiss" -lt 20 ] || break   # REJECT 확정 + 목록 상한 20 — 나머지는 안 돈다(경로 수천 개 혼합 커밋에서 git log 수천 번 방지)
    entry="$(git --literal-pathspecs -C "$REPO" ls-tree "$NANO" -- "$p")"; erc=$?
    [ "$erc" -eq 0 ] || { echo "REJECT cherry 게이트 — git ls-tree 실패(rc=$erc) 경로 $p"; exit 1; }
    if [ -z "$entry" ]; then
      fe="$(git --literal-pathspecs -C "$REPO" ls-tree "$FEAT" -- "$p")"; frc=$?
      [ "$frc" -eq 0 ] || { echo "REJECT cherry 게이트 — git ls-tree($FEAT) 실패(rc=$frc) 경로 $p"; exit 1; }
      if [ -z "$fe" ]; then nsup=$((nsup + 1)); else nmiss=$((nmiss + 1)); missing="${missing}  ${p} (tip 삭제 · $FEAT 에는 존재)"$'\n'; fi
      continue
    fi
    meta="${entry%%$'\t'*}"; mode="${meta%% *}"; sha1="${meta##* }"
    raw="$(git --literal-pathspecs -C "$REPO" -c core.quotepath=false log "$mbase..$FEAT" --no-renames --format='commit %h' --raw --no-abbrev -- "$p")"; lrc2=$?
    [ "$lrc2" -eq 0 ] || { echo "REJECT cherry 게이트 — git log($FEAT) 실패(rc=$lrc2) 경로 $p"; exit 1; }
    hit=""; cur=""
    while IFS= read -r ln; do
      case "$ln" in commit\ *) cur="${ln#commit }" ;; esac
      if [[ "$ln" =~ ^:[0-7]{6}\ $mode\ [0-9a-f]+\ $sha1\ [A-Z] ]]; then hit="$cur"; break; fi
    done <<< "$raw"
    if [ -n "$hit" ]; then nsup=$((nsup + 1)); sup_commit="$hit"; else nmiss=$((nmiss + 1)); missing="${missing}  ${p} (tip ${mode} ${sha1:0:9} 가 분기 뒤 $FEAT 구간(${mbase:0:9}..)에 새 blob 으로 없음)"$'\n'; fi
  done < "$plus_file"
  if [ -z "$missing" ] && [ "$nsup" -gt 0 ]; then
    echo "INFO cherry 게이트 — $NANO 의 «+» 커밋 $((nb + nw))개: 경로 ${nsup}개 전부 tip 내용이 분기 뒤 $FEAT 구간에 새 blob 으로 있음(예 $sup_commit) — 통과 (사유 content_landed_then_superseded)"
    exit 0
  fi
  if [ "$conflict" -eq 1 ]; then
    echo "REJECT cherry 게이트 — $NANO 와 $FEAT 의 merge-tree 충돌(rc=1) + tip 내용이 $FEAT 역사에 없는 경로가 있음 — 사람이 판정:"
  else
    echo "REJECT cherry 게이트 — $NANO 머지 시 $FEAT 에 design/ 밖 변경 $(printf '%s' "$differ" | grep -c .)개가 생김(내용 미랜딩 · merge-tree 실제 delta):"
    printf '%s' "$differ" | head -20
  fi
  echo "  tip 내용이 $FEAT 역사에 없는 경로:"; printf '%s' "$missing" | head -20
  echo "REJECT cherry 게이트 — $NANO 에 $FEAT 로 안 들어온 코드·시험·스크립트 커밋 ${nb}개 (git cherry '+' · design/ 밖 경로):"
  printf '%s' "$block" | head -20
  [ "$nb" -le 20 ] || echo "  … 외 $((nb - 20))개"
  [ "$nw" -eq 0 ] || { echo "  (별도 WARN: design/ 만 건드린 미랜딩 문서 커밋 ${nw}개)"; printf '%s' "$warn" | head -5; }
  echo "  → cherry-pick -x 로 $FEAT 에 반영하거나 폐기 사유를 값으로 적은 뒤 닫는다 (사람 우회: --override \"<사유>\")"
  if [ "$HAVE_OVERRIDE" -eq 1 ]; then
    # 원장 메타는 행 합성 «전» 에 각각 조회 · rc 와 값 검증 — 하나라도 실패하면 빈 값 행 없이 exit 1 (DA 599 H2)
    root="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)"; r1=$?
    tip_s="$(git -C "$REPO" rev-parse --short "$NANO")"; r2=$?
    feat_s="$(git -C "$REPO" rev-parse --short "$FEAT")"; r3=$?
    root="${root%/.git}"
    if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ] || [ "$r3" -ne 0 ] || [ ! -d "$root" ] || [[ ! "$tip_s" =~ ^[0-9a-f]{7,64}$ ]] || [[ ! "$feat_s" =~ ^[0-9a-f]{7,64}$ ]]; then
      echo "REJECT cherry 게이트 — --override 원장 메타 조회 실패(common-dir rc=$r1 tip rc=$r2 feat rc=$r3) — 원장 행 0 · 우회 불가"; exit 1
    fi
    ledger="${FT_CHERRY_OVERRIDE_LEDGER:-$root/.fable-team/state/cherry-gate-override.log}"
    row="$(date '+%F %T')	seat=${FT_SEAT:-$NANO}	nano=$NANO	tip=$tip_s	feat=$feat_s	reason=$(printf '%s' "$OVERRIDE" | tr '\n\t' '  ')"
    { mkdir -p "$(dirname "$ledger")" && printf '%s\n' "$row" >> "$ledger"; } || { echo "REJECT cherry 게이트 — --override 원장 기록 실패($ledger) — 보이는 기록 없이는 우회 불가"; exit 1; }
    echo "ERROR cherry 게이트 OVERRIDE — 위 REJECT 를 사람 사유로 우회: $OVERRIDE (원장 $ledger)" >&2
    echo "OVERRIDE cherry 게이트 — 위 REJECT 를 우회해 통과 · 사유: $OVERRIDE · 원장 1행 기록: $ledger"
    exit 0
  fi
  exit 1
fi
if [ "$nw" -gt 0 ]; then
  echo "WARN cherry 게이트 — $NANO 의 design/ 문서 커밋 ${nw}개가 $FEAT 에 없음(코드 0 · 브랜치 보존으로 복구 가능) — 통과:"
  printf '%s' "$warn" | head -20
  [ "$nw" -le 20 ] || echo "  … 외 $((nw - 20))개"
  exit 0
fi
echo "OK cherry 게이트 — $NANO 의 모든 커밋이 $FEAT 에 patch 단위로 존재(+ 0)"
exit 0
