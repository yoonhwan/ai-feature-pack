#!/usr/bin/env bash
# ft-nano-cherry-pr.sh — source 전용. ft-nano-cherry-gate.sh 의 `--squashed-pr <N> --reason "<사유>"` 분류 (R29).
#   squash 랜딩은 PR 의 최종 트리만 남겨, PR 안에서 나노 내용이 더 고쳐지면 나노 blob 이 feat 역사에 없다(superseded 증거 부재).
#   기계는 «PR 사실 + 경로별 분류»까지만 한다 — 같음 / PR 안에서 고쳐짐 / 되돌림·제거·PR 에 없음(= 플래그로도 REJECT).
#   «PR 안에서 고쳐짐» 의 의미 보존은 자동 증명이 아니라 사람이 사유로 표명한다(override 원장에 kind=squashed-pr 1행).

#   is_doc_path 는 ft-nano-cherry-gate.sh 에 있다(문서 종류 WARN 분리는 플래그 없이도 적용되므로 본체 소속).

# _ent <repo> <rev> <경로> — `mode type blob`(없으면 빈 줄). git 실패면 rc≠0.
_ent() {
  local out rc
  out="$(git --literal-pathspecs -C "$1" ls-tree "$2" -- "$3")"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s\n' "${out%%$'\t'*}"
}

# _pr_hit <repo> <구간> <경로> <mode> <blob> — 구간에 그 (mode,blob) 이 새 blob 으로 있으면 0 + stdout 에 이후 고친 PR 커밋("sha 제목 / …" 최대 3)
_pr_hit() {
  local raw ln cur="" mods="" nmods=0 hit=0
  raw="$(git --literal-pathspecs -C "$1" -c core.quotepath=false log "$2" --no-renames --format='commit %H %s' --raw --no-abbrev -- "$3")" || return 2
  while IFS= read -r ln; do
    case "$ln" in commit\ *) cur="${ln#commit }"; continue ;; esac
    [[ "$ln" =~ ^: ]] || continue
    if [[ "$ln" =~ ^:[0-7]{6}\ $4\ [0-9a-f]+\ $5\ [A-Z] ]]; then hit=1; break; fi
    if [ "$nmods" -lt 3 ]; then mods="${mods:+$mods / }${cur:0:8} ${cur#* }"; nmods=$((nmods + 1)); fi
  done <<< "$raw"
  [ "$hit" -eq 1 ] || return 1
  printf '%s\n' "${mods:--}"
}

# cherry_squashed_pr_gate <repo> <feat> <nano> <pr> <reason> <경로 NUL 목록 파일>
#   0 = 통과(경로 표 + 한계 문구 + 원장 1행 + stderr ERROR) · 1 = REJECT(사유 stdout)
cherry_squashed_pr_gate() {
  local repo="$1" feat="$2" nano="$3" pr="$4" reason="$5" pf="$6"
  local tag="REJECT cherry 게이트 --squashed-pr #$pr" js st S H mbase mb2 p t f b s mods
  local ge; ge="$(mktemp)" || { echo "$tag — mktemp 실패"; return 1; }   # stderr 는 JSON 에 섞지 않는다(경고 한 줄이 jq 를 깬다) — 실패 때만 사유에 붙인다
  js="$(cd "$repo" && "${FT_CHERRY_GH:-gh}" pr view "$pr" --json state,mergeCommit,headRefOid 2>"$ge")" \
    || { js="$js$(cat "$ge")"; rm -f "$ge"; echo "$tag — gh pr view 실패: ${js:0:120}"; return 1; }
  rm -f "$ge"
  st="$(jq -r '.state // empty' <<< "$js" 2>/dev/null)"; S="$(jq -r '.mergeCommit.oid // empty' <<< "$js" 2>/dev/null)"
  H="$(jq -r '.headRefOid // empty' <<< "$js" 2>/dev/null)"
  [ "$st" = MERGED ] || { echo "$tag — PR state=${st:-<없음>} (MERGED 아님)"; return 1; }
  [[ "$S" =~ ^[0-9a-f]{40,64}$ && "$H" =~ ^[0-9a-f]{40,64}$ ]] || { echo "$tag — mergeCommit·headRefOid 를 못 읽음"; return 1; }
  mbase="$(git -C "$repo" merge-base "$nano" "$feat")" || { echo "$tag — merge-base($nano,$feat) 실패"; return 1; }
  if ! git -C "$repo" merge-base --is-ancestor "$S" "$feat" 2>/dev/null || git -C "$repo" merge-base --is-ancestor "$S" "$mbase" 2>/dev/null; then
    echo "$tag — mergeCommit ${S:0:8} 가 merge-base(${mbase:0:8})..$feat 구간에 없음(squash 가 이 feat 에 안 들어옴)"; return 1
  fi
  git -C "$repo" cat-file -e "$H^{commit}" 2>/dev/null || git -C "$repo" fetch -q origin "pull/$pr/head" 2>/dev/null
  git -C "$repo" cat-file -e "$H^{commit}" 2>/dev/null || { echo "$tag — PR head ${H:0:8} 를 로컬에서도 fetch origin pull/$pr/head 로도 못 구함"; return 1; }
  mb2="$(git -C "$repo" merge-base "$H" "$feat")" || { echo "$tag — merge-base(PR head,$feat) 실패"; return 1; }

  local nsame=0 nfix=0 nrej=0 rej="" fix="" fixpaths=""
  while IFS= read -r -d '' p; do
    [ -n "$p" ] || continue
    is_doc_path "$p" && continue
    t="$(_ent "$repo" "$nano" "$p")" && f="$(_ent "$repo" "$feat" "$p")" && b="$(_ent "$repo" "$mbase" "$p")" && s="$(_ent "$repo" "$S" "$p")" \
      || { echo "$tag — git ls-tree 실패 경로 $p"; return 1; }
    if [ "$t" = "$f" ]; then nsame=$((nsame + 1)); continue; fi
    if [ -z "$t" ]; then nrej=$((nrej + 1)); rej="${rej}  ${p} — 나노 tip 에서 삭제 · $feat 에는 존재"$'\n'; continue; fi
    if [ -z "$s" ]; then nrej=$((nrej + 1)); rej="${rej}  ${p} — squash(${S:0:8}) 에서 제거됨"$'\n'; continue; fi
    if [ "$s" = "$b" ]; then nrej=$((nrej + 1)); rej="${rej}  ${p} — squash 결과가 분기 시점과 같음(PR 안에서 되돌림)"$'\n'; continue; fi
    mods="$(_pr_hit "$repo" "$mb2..$H" "$p" "${t%% *}" "${t##* }")"; case $? in
      0) nfix=$((nfix + 1)); fixpaths="${fixpaths:+$fixpaths,}$p"; fix="${fix}  ${p} ← ${mods}"$'\n' ;;
      1) nrej=$((nrej + 1)); rej="${rej}  ${p} — 나노 tip (${t%% *} ${t##* }) 이 PR 구간(${mb2:0:8}..${H:0:8})에 새 blob 으로 없음"$'\n' ;;
      *) echo "$tag — git log(PR 구간) 실패 경로 $p"; return 1 ;;
    esac
  done < "$pf"
  if [ "$nrej" -gt 0 ]; then
    echo "$tag — 되돌림·제거·PR 에 없음 ${nrej}개 경로가 있어 플래그로도 통과 불가(사람 우회는 --override 뿐):"; printf '%s' "$rej" | head -20; return 1
  fi
  local root tip_s feat_s S8="${S:0:8}" H8="${H:0:8}" ledger row
  root="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)"; root="${root%/.git}"
  tip_s="$(git -C "$repo" rev-parse --short "$nano")" && feat_s="$(git -C "$repo" rev-parse --short "$feat")" && [ -d "$root" ] \
    || { echo "$tag — 원장 메타 조회 실패 — 원장 행 0 · 통과 불가"; return 1; }
  ledger="${FT_CHERRY_OVERRIDE_LEDGER:-$root/.fable-team/state/cherry-gate-override.log}"
  row="$(date '+%F %T')	seat=${FT_SEAT:-$nano}	nano=$nano	tip=$tip_s	feat=$feat_s	kind=squashed-pr pr=#$pr head=$H8 squash=$S8 paths=$fixpaths	reason=$(printf '%s' "$reason" | tr '\n\t' '  ')"
  { mkdir -p "$(dirname "$ledger")" && printf '%s\n' "$row" >> "$ledger"; } || { echo "$tag — 원장 기록 실패($ledger) — 보이는 기록 없이는 통과 불가"; return 1; }
  echo "INFO cherry 게이트 --squashed-pr #$pr (PR head $H8 → squash $S8) 경로 분류: 같음 ${nsame}개 · PR 안에서 고쳐짐 ${nfix}개 · 되돌림·제거 0개"
  [ "$nfix" -eq 0 ] || { echo "  PR 안에서 고쳐짐(경로 ← 그 뒤 고친 PR 커밋):"; printf '%s' "$fix"; }
  echo "  한계: S≠분기 시점은 의미 보존의 자동 증명이 아니다 — 보존 판단은 사유 작성자 책임 · 부분 변경 가능"
  echo "ERROR cherry 게이트 SQUASHED-PR — PR #$pr 안에서 고쳐진 나노 내용을 사람 사유로 통과: $reason (원장 $ledger)" >&2
  echo "PASS cherry 게이트 --squashed-pr — 사유: $reason · 원장 1행 기록: $ledger"
  return 0
}
