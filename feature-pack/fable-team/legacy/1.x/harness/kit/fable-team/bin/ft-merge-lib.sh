#!/usr/bin/env bash
# ft-merge-lib.sh — 병합·랜딩 도구 공용 함수 (R230 · source 전용 · 7초 룰 판정 666)
#   fm_try <초> <명령…>       : 한 번 시도 · timeout 도구 없으면 rc 127 (조용한 통과 0) — 초는 부른 쪽이 정한다
#   fm_t7 <명령…>            : 시도당 timeout 7 초 + 재시도 1 (총 14 초 상한) — timeout 도구 없으면 rc 127 (조용한 통과 0)
#   fm_fetch <repo> <remote> <ref> : 한 ref 만 받는다 · 시도당 상한 = fm_fetch_sec(지정 없음 = 25 · FT_FETCH_TIMEOUT_SEC 1~70 = 오빠 예외 판정 · r1069) + 재시도 1
#   ★r1363: fetch 1회는 연결·협상 고정비가 붙은 «쪼갤 수 없는 1회» 다 — 기본 상한 = 25초 고정(판정 4114 · 로컬 하네스 외부 호출 상한). gh·push 등 런타임 7 초는 그대로★
#   ★FT_LAND_DEADLINE(epoch 초)이 env 에 있으면 착지 1회 마감 — 시도마다 min(상한, 남은 시간) · 재시도 1 은 남은 ≥ 상한일 때만 · 남은 ≤ 0 = 시도 0 «마감 넘김»★
#   ★지정 없음 실행은 첫 fetch 앞에 «INFO fetch 상한 <초>(판정 4114)» 1줄(fm_fetch_info · 맨 끝) · 값을 준 실행은 ft-merge-land 첫 줄에 «오빠 예외 판정» 을 남긴다★
fm_timeout_bin() { command -v timeout || command -v gtimeout; }
fm_try() {
  local s="$1"; shift; local tb; tb="$(fm_timeout_bin)" || { echo "timeout/gtimeout 없음 — 상한을 걸 수 없어 외부 호출 거절" >&2; return 127; }
  "$tb" "$s" "$@"
}
fm_t7() {
  local rc=0 i; for i in 1 2; do fm_try 7 "$@" && return 0; rc=$?; done
  return "$rc"
}
#   fm_fetch_sec : fetch «시도당 상한» 초 — 지정 없음 = 25(판정 4114 · 로컬 하네스 외부 호출 상한 · 11-05 실측 고정비 10~16 초를 덮는다 · r1363 · F/FT_FETCH_FIXED_S 공식 없음)
#     FT_FETCH_TIMEOUT_SEC(정수 1~70 · 오빠 예외 판정 r1069) 를 주면 그 값이 이긴다(꼴이 틀리거나 70 밖이면 WARN(stderr) 1줄 + 25)
#     stdout = 초 · 결과를 FM_FETCH_SEC 에, «유효 지정» 여부를 FM_FETCH_SEC_VALID(1|0) 에 남긴다 ⇒ 부른 쪽은 `fm_fetch_sec >/dev/null` 꼴로 부른다(명령 치환 = 서브셸이면 표지가 안 남는다)
fm_fetch_sec() {
  local v="${FT_FETCH_TIMEOUT_SEC:-}" b=25; FM_FETCH_SEC=$b; FM_FETCH_SEC_VALID=0
  if [ -n "$v" ]; then
    case "$v" in
      *[!0-9]*) echo "WARN FT_FETCH_TIMEOUT_SEC=$v 는 1~70 정수가 아님 → 기본 상한 $b" >&2;;
      *) if [ "$v" -ge 1 ] 2>/dev/null && [ "$v" -le 70 ] 2>/dev/null; then FM_FETCH_SEC="$v"; FM_FETCH_SEC_VALID=1
         else echo "WARN FT_FETCH_TIMEOUT_SEC=$v 는 1~70 밖 → 기본 상한 $b" >&2; fi;;
    esac
  fi
  echo "$FM_FETCH_SEC"
}
#   fm_fetch_info : 「INFO fetch 상한 <초>(판정 4114)」 한 줄 — «지정 없음» 실행만(지정 실행은 fm_fetch_banner 가 그 몫)
fm_fetch_info() {
  [ "${FM_FETCH_SEC_VALID:-0}" = 1 ] && return 0
  echo "INFO fetch 상한 ${FM_FETCH_SEC:-?}(판정 4114)"
}
#   fm_fetch_deadline_rem : stdout = 남은 초(FT_LAND_DEADLINE epoch 초 − 지금 · 음수 가능) · rc 1 = 마감 없음/꼴 아님(옛 동작 그대로)
fm_fetch_deadline_rem() {
  local d="${FT_LAND_DEADLINE:-}"
  { [ -n "$d" ] && printf '%s' "$d" | grep -Eq '^[0-9]+$'; } || return 1
  echo $(( d - $(date +%s) ))
}
#   fm_fetch_banner : 「오빠 예외 판정[ <N>] · 지정 <초>」 한 줄 — FT_FETCH_TIMEOUT_SEC 가 유효 지정일 때만(아니면 출력 0). N = FT_FETCH_EXCEPTION_ID(영숫자만 · 없으면 빈칸)
fm_fetch_banner() {
  local id; [ "${FM_FETCH_SEC_VALID:-0}" = 1 ] || return 0
  id="$(printf '%s' "${FT_FETCH_EXCEPTION_ID:-}" | tr -cd 'A-Za-z0-9')"
  echo "오빠 예외 판정${id:+ $id} · 지정 $FM_FETCH_SEC"
}
fm_fetch() {
  local s rc=0 i a rem; s="$(fm_fetch_sec)"
  for i in 1 2; do
    a="$s"
    if rem="$(fm_fetch_deadline_rem)"; then   # r1363 3bⓐ: 착지 1회 마감이 env 에 있으면 시도 = min(상한, 남은) · 남은 ≤ 0 = 시도 0
      [ "$rem" -gt 0 ] || { echo "총 마감 넘김(fetch 시도 0 · FT_LAND_DEADLINE=$FT_LAND_DEADLINE 남은 ${rem}s)" >&2; return 1; }
      if [ "$rem" -lt "$a" ]; then echo "WARN fetch 상한이 남은 시간으로 잘림(${rem}s < ${s}s) — 총 마감 우선" >&2; a="$rem"; fi
    fi
    fm_try "$a" git -c gc.auto=0 -C "$1" fetch --quiet "$2" "$3" && return 0; rc=$?
    if rem="$(fm_fetch_deadline_rem)"; then [ "$rem" -ge "$s" ] || return "$rc"; fi   # 재시도 1 은 남은 ≥ 상한일 때만
  done
  return "$rc"
}
#   fm_head_branch <gh pr view JSON> : stdout = headRefName — isCrossRepository 가 «정확히 false»(같은 리포 PR) ∧ 가지 이름 꼴일 때만 · 아니면 rc 1(포크·칸 없음·빈 값 · r1127)
fm_head_branch() {
  local b; b="$(printf '%s' "$1" | python3 -c 'import json,sys;d=json.load(sys.stdin);sys.exit(1) if d.get("isCrossRepository") is not False else print(d.get("headRefName") or "")')" || return 1
  [ -n "$b" ] && git check-ref-format --branch "$b" >/dev/null 2>&1 && printf '%s' "$b"
}
#   fm_push_calc <객체수|?> : push «시도당 상한»(정수 초 · 소수 버림) = min(F + 7 × ceil(N/U0), 70) — 규칙 12 «쪼갤 수 없는 크기 아는 배치»(판정 1375). N 모름(?) = F + 7.
#     F = FT_PUSH_FIXED_S(기본 7 · r1336: 부하 50~60 에서 ssh·ref 광고 + pre-push 훅 + 서버 처리 6~10 s 실측 · 7 초과는 7 로 클램프) · U0 = FT_PUSH_UNIT_OBJECTS(기본 100 객체/7 s 잠정 · 양의 정수 아니면 기본) · 잘못된 env 는 WARN(stderr)
#   fm_push_bound <repo> <M> <Q> : stdout "<객체수|?> <시도당 상한>" — 객체수 = rev-list --objects M..Q · 조회 실패는 WARN 1줄 + 호환값(F+7) (조용한 통과 0)
fm_push_calc() {
  local n="$1" f="${FT_PUSH_FIXED_S:-7}" u="${FT_PUSH_UNIT_OBJECTS:-100}"
  printf '%s' "$f" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && awk -v f="$f" 'BEGIN{exit !(f>0)}' || { echo "WARN FT_PUSH_FIXED_S=$f 는 0 보다 큰 숫자가 아님 → 기본 7" >&2; f=7; }
  awk -v f="$f" 'BEGIN{exit !(f>7)}' && { echo "WARN FT_PUSH_FIXED_S=$f 는 7 초과 → 7 로 클램프" >&2; f=7; }
  printf '%s' "$u" | grep -Eq '^[0-9]+$' && [ "$u" -gt 0 ] || { echo "WARN FT_PUSH_UNIT_OBJECTS=$u 는 양의 정수가 아님 → 기본 100" >&2; u=100; }
  if [ "$n" = '?' ]; then awk -v f="$f" 'BEGIN{printf "%d\n", f+7}'
  else awk -v f="$f" -v n="$n" -v u="$u" 'BEGIN{k=int((n+u-1)/u); if(k<1)k=1; t=f+7*k; if(t>70)t=70; printf "%d\n", t}'; fi
}
#   fm_push_log <tsv> <시도> <객체수> <PB> <AB> <소요초> <rc> <판정 ok|timeout|ls=M|ls=Q|불명|non-ff|연결실패|실패> : r1336 — push 시도마다 1줄(시각 · 시도 · 1분 부하 · 객체 수 · PB · AB · 소요 · rc · 판정) · 쓰기 실패는 WARN 1줄(착지 rc 영향 0 · rc 항상 0)
fm_push_log() {
  local f="$1" ld; shift; ld="$(uptime 2>/dev/null | sed 's/.*load averages*: *//' | awk '{gsub(",","",$1); print $1}')"
  { mkdir -p "$(dirname "$f")" && printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" "${ld:-?}" "$2" "$3" "$4" "$5" "$6" "$7" >>"$f"; } 2>/dev/null \
    || echo "WARN push-timing 기록 실패($f) — 착지 rc 불변" >&2
  return 0
}
fm_push_bound() {
  local out n
  if out="$(git -C "$1" rev-list --objects "$2..$3" 2>&1)"; then n="$(printf '%s\n' "$out" | grep -c . || true)"
  else echo "WARN 객체 수 조회 실패(rev-list) → 크기 모름 · 상한 F+7 호환값: $(printf '%s' "$out" | tail -n1)" >&2; n='?'; fi
  echo "$n $(fm_push_calc "$n")"
}
#   fm_base_head_file <기준경로> <대상 가지> : r1687 — 기준 헤드는 «대상 가지마다 따로» 다. main = 지금 경로 그대로(옛 파일 호환) · 그 밖 = <경로>@<가지를 /→-> (예 base-head@ops-main-base).
#     이유: 기준 헤드가 리포에 1개뿐이면 main 기준을 ops/main-base 착지에도 들이대, main 이 ops 의 조상이 아닌 동안 ops 착지가 늘 DENY 된다(PR 8346·8347 실사건).
fm_base_head_file() {
  [ "${2:-main}" = main ] && { printf '%s\n' "$1"; return 0; }
  printf '%s@%s\n' "$1" "${2//\//-}"
}
#   fm_land_ctx <repo> <remote> <ft_root|빈> [대상 가지] : r648 — 승인 루트(부른 리포)와 대상 리포를 가른다. stdout 1줄 "<원장루트>|<CROSS 0|1>|<owner/name|빈>|<base-head 경로>|<대상 리포 루트>" (칸 구분 = | — 빈 칸이 있어도 밀리지 않게 탭 금지)
#     원장 루트 = FT_ROOT → 부른 리포(cwd 공용 루트) → 대상 리포 · CROSS = 부른 리포 ≠ 대상 리포(«리포 기준» 모드 — 원장은 부른 쪽 한 곳)
#     owner/name 은 CROSS 일 때만 잡는다(아니면 빈 값 = 이전 판 그대로 -R·FT_ISSUE_REPO 0) · 실제 전송 URL «전부»(`remote get-url --all` + `remote get-url --push --all` — push 는 등록된 모든 URL 로 간다)가 같은 github owner/name 일 때만(목적지가 둘 이상이거나 갈리면 REJECT)
#     base-head = <원장루트>/.fable-team/state/base-head · CROSS 면 -<owner>-<name> 꼬리(다른 리포 sha 를 기준 헤드로 섞지 않는다)
#     rc 1 = 대상 리포 루트 확인 실패 또는 CROSS 인데 owner/name 을 못 풂(다른 리포 PR 을 조용히 조회하는 길 0)
fm_land_ctx() {
  local repo="$1" rem="$2" ft="${3:-}" tgt="${4:-main}" xrepo="" rroot="" rt="" slug="" bh cross=0
  rroot="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && rroot="$(dirname "$rroot")" || return 1
  [ -n "$rroot" ] || return 1
  xrepo="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && xrepo="$(dirname "$xrepo")" || xrepo=""
  rt="${ft:-${xrepo:-$rroot}}"
  [ -z "$xrepo" ] || [ "$xrepo" = "$rroot" ] || cross=1
  bh="$rt/.fable-team/state/base-head"
  if [ "$cross" = 1 ]; then   # 전송 목적지 «전부» 가 같은 값이어야 한다 — push 는 등록된 모든 URL 로 간다(land:82)
    local u s
    for u in $(git -C "$repo" remote get-url --all "$rem" 2>/dev/null) $(git -C "$repo" remote get-url --push --all "$rem" 2>/dev/null); do
      s="$(fm_gh_slug "$u")" || return 1
      [ -n "$s" ] || return 1
      [ -z "$slug" ] || [ "$slug" = "$s" ] || return 1
      slug="$s"
    done
    [ -n "$slug" ] || return 1
    bh="$bh-${slug//\//-}"
  fi
  bh="$(fm_base_head_file "$bh" "$tgt")"   # r1687: 대상 가지마다 다른 파일(다른 리포 접미 뒤에 붙는다)
  printf '%s|%s|%s|%s|%s\n' "$rt" "$cross" "$slug" "$bh" "$rroot"
}
#   fm_gh_slug <url> : https://github.com/o/n[.git] · ssh://git@github.com/o/n[.git] · git@github.com:o/n[.git] 만 — 호스트가 «정확히» github.com 이고 owner/name 꼴이면 1줄, 아니면 빈 줄(rc0) · 꼴이 깨졌으면 rc1
fm_gh_slug() {
  local s
  case "$1" in
    https://github.com/*|ssh://git@github.com/*|git@github.com:*) ;;
    *) return 0;;
  esac
  s="${1#*github.com}"; s="${s#:}"; s="${s#/}"; s="${s%.git}"; s="${s%/}"
  printf '%s' "$s" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  printf '%s\n' "$s"
}
#   fm_flag_off_new <repo> <옛> <새> : R239 랜딩 직후 «새로 생긴 기본 꺼짐 플래그» 줄 출력 — 출력만(rc 항상 0 · 실패는 WARN 1줄 · 로컬 git 만 읽는다)
FM_HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
#   fm_doc_exempt <상태폴더> <리포> <루트> <base> <head> : R725 — «문서 전용 PR» 예외 판정(1곳 = ft_doc_exempt.py) + autonomy.log 기록 한 줄.
#     성공 rc0 = stdout `doc-exempt=yes team=<팀> files=<N> by=<좌석>`(판정 줄은 stderr) · 실패 rc1 = stdout 사유 + `doc-exempt-reject` 1줄(착지 0)
#     판정 규칙·범위는 ft_doc_exempt.py 머리말 하나 — 여기서 다시 판정하지 않는다(사본 0). 기준 = master #140107 확정(모든 팀 폴더 .md).
fm_doc_exempt() {
  local st="$1" repo="$2" root="$3" base="$4" head="$5" out rc f dc dt seat
  seat="$(printf '%s' "${FT_SEAT:-unknown}" | tr -cd 'A-Za-z0-9#_-')"; [ -n "$seat" ] || seat=unknown
  out="$(fm_t7 env -u FT_DOC_EXEMPT_SELFTEST -u FT_DOC_EXEMPT_SEAT python3 "$FM_HERE/ft_doc_exempt.py" --mode doc-exempt --repo "$repo" --root "$root" --base "$base" --head "$head" 2>&1)"; rc=$?
  f="$(printf '%s\n' "$out" | head -n1)"
  if [ "$rc" -eq 0 ] && [ "${f#DOC-EXEMPT "$head" }" != "$f" ]; then
    dc="$(printf '%s' "$f" | sed -n 's/.* files=\([0-9]*\).*/\1/p')"; dt="$(printf '%s' "$f" | sed -n 's/.* team=\([a-z0-9_-]*\).*/\1/p')"
    dse="$(printf '%s' "$f" | sed -n 's/.* by=\([A-Za-z0-9#_-]*\).*/\1/p')"; [ -z "$dse" ] || seat="$dse"   # R725 r2: 기록 좌석 = 판정 모듈이 «실측»한 좌석(자기 신고가 아니다)
    printf '%s\n' "$f" >&2
    printf 'doc-exempt %s team=%s files=%s by=%s\n' "$head" "${dt:-planner}" "${dc:-0}" "$seat" >> "$st/autonomy.log" || { echo "autonomy.log 기록 실패 — 착지 0"; return 1; }
    echo "doc-exempt=yes team=${dt:-planner} files=${dc:-0} by=$seat"; return 0
  fi
  printf 'doc-exempt-reject %s by=%s\n' "$head" "$seat" >> "$st/autonomy.log" 2>/dev/null || true
  echo "doc-exempt 아님(rc=$rc): ${f:-출력 없음}"; return 1
}
fm_flag_off_new() {
  local tb out rc; tb="$(fm_timeout_bin)" || { echo "WARN flag-off 검사 실패 timeout 도구 없음"; return 0; }
  out="$("$tb" 7 python3 "$FM_HERE/ft_flag_off.py" --repo "$1" --new-between "$2" "$3" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then [ -z "$out" ] || printf '%s\n' "$out"; else echo "WARN flag-off 검사 실패 rc=$rc $(printf '%s' "$out" | tail -n1)"; fi
  return 0
}
#   fm_close_pending_add <장부> <repo키> <PR> <착지 sha> : r1131 — ⑦ 코멘트/닫기 실패 PR 을 «닫기 대기» 장부(jsonl)에 1줄 · 기록 실패는 WARN 1줄(착지 rc 불변)
fm_close_pending_add() {
  { mkdir -p "$(dirname "$1")" && python3 -c 'import json,sys,time;print(json.dumps({"repo":sys.argv[1],"pr":int(sys.argv[2]),"sha":sys.argv[3],"ts":int(time.time())},ensure_ascii=False))' "$2" "$3" "$4" >>"$1"; } 2>/dev/null \
    || echo "WARN 닫기 대기 장부 기록 실패($1) — PR #$3 손으로(착지 sha $4)"
}
#   fm_close_pending_ls <장부> <repo키> : 같은 repo 항목 «pr sha» 줄(장부 순서 · 최대 3) — 꼴이 깨진 줄·다른 repo 는 건너뛴다(지우지 않는다)
#   fm_close_pending_rm <장부> <repo키> <pr…> : 같은 repo 의 그 PR 줄만 지운다(임시 파일 + mv · 나머지 줄 바이트 그대로)
FM_CP_PY='import json,sys
f,key,mode=sys.argv[1],sys.argv[2],sys.argv[3]; drop=set(sys.argv[4:]); keep=[]; n=0
def item(l):
  try: d=json.loads(l); return d if isinstance(d,dict) and d.get("repo")==key and str(d.get("pr","")).isdigit() else None
  except ValueError: return None
for l in open(f,encoding="utf-8").read().splitlines():
  d=item(l)
  if mode=="ls" and d and n<3: print(d["pr"],d.get("sha","")); n+=1
  if mode=="rm" and not (d and str(d["pr"]) in drop): keep.append(l)
if mode=="rm": open(f+".tmp","w",encoding="utf-8").write("".join(x+"\n" for x in keep))'
fm_close_pending_ls() { [ -s "$1" ] || return 0; python3 -c "$FM_CP_PY" "$1" "$2" ls; }
fm_close_pending_rm() { python3 -c "$FM_CP_PY" "$1" "$2" rm "${@:3}" && mv -f "$1.tmp" "$1"; }
#   fm_pr_done <닫기 실패 출력> <slug|빈> <pr> <남은초> : r1336 — 이미 닫힌 PR 판정(rc0 = 닫힌 것) · 닫기 출력에 «already merged|already closed» 또는 gh pr view state 가 MERGED/CLOSED · 그 밖(조회 실패 포함) rc1 = 지금처럼 장부에 남김
#     gh pr view 는 1회 7 s(재시도 0) · 부르기 전 남은 ≥ 7 s 재검사 — 모자라면 호출 0 + INFO 1줄 + rc1(사전 DA ① R2 · 총 마감 70 s 안)
fm_pr_done() {
  printf '%s' "$1" | grep -qiE 'already (merged|closed)' && return 0
  [ "${4:-0}" -ge 7 ] 2>/dev/null || { echo "INFO 닫기 재시도 PR #$3 이미 닫힘 확인 건너뜀 — 남은 ${4:-0}s < 7s · 장부 그대로"; return 1; }
  fm_try 7 "${FT_GH:-gh}" pr view "$3" ${2:+-R "$2"} --json state 2>/dev/null </dev/null | python3 -c 'import json,sys;sys.exit(0 if json.load(sys.stdin).get("state") in ("MERGED","CLOSED") else 1)' 2>/dev/null
}
#   fm_close_retry <장부> <repo키> <slug|빈> <닫기도구> <남은초> : r1131 — 착지 시작 때 장부의 같은 repo 항목(최대 3)을 pr-close --comment 로 다시 닫는다
#     건마다 fm_t7 · 건 시작 때 남은 ≥ 20 s 일 때만(아니면 «재시도 미룸» 1줄 · 재시도 0) · 성공 = 장부에서 지움 · 실패 = 남김 + stdout 1줄 · rc 항상 0(착지 판정 불변)
fm_close_retry() {
  local f="$1" key="$2" slug="$3" gw="$4" r0="$5" t0=$SECONDS items pr sha rem o cb ok=""
  items="$(fm_close_pending_ls "$f" "$key" 2>/dev/null)" || { echo "WARN 닫기 대기 장부 읽기 실패($f) — 재시도 0"; return 0; }
  [ -n "$items" ] || return 0
  cb="$(mktemp)" || { echo "WARN 닫기 재시도 코멘트 파일 실패 — 재시도 0"; return 0; }
  while read -r pr sha; do
    rem=$((r0 - (SECONDS - t0)))
    [ "$rem" -ge 20 ] || { echo "INFO 닫기 재시도 미룸 — 남은 ${rem}s < 20s · 장부 그대로($f)"; break; }
    printf '%s\n' "착지 sha $sha (ft-merge-land · 닫기 재시도 r1131)" > "$cb"
    if o="$(fm_pr_close "$slug" "$pr" "$cb" "$gw" 2>&1 </dev/null)"; then ok="$ok $pr"; echo "INFO 닫기 재시도 PR #$pr 닫음(착지 sha $sha)"
    elif fm_pr_done "$o" "$slug" "$pr" $((r0 - (SECONDS - t0))); then ok="$ok $pr"; echo "INFO 닫기 재시도 PR #$pr 이미 MERGED/CLOSED — 성공으로 보고 장부에서 지움"
    else echo "WARN 닫기 재시도 실패 PR #$pr — 장부에 남김: $(printf '%s' "$o" | tail -n1 | cut -c1-160)"; fi
  done <<<"$items"
  rm -f "$cb"
  [ -z "$ok" ] || fm_close_pending_rm "$f" "$key" $ok || echo "WARN 닫기 대기 장부 정리 실패($f) — 닫힌 PR:$ok"
  return 0
}
#   fm_ap_wait <repo> <remote> <target> <승인 sha> <승인 상태 폴더> : r1200 — 승인 파일 없는 거절 줄 1개(stdout) · 커밋 아님(로컬 없으면 fetch 1회 7 s) = 표식 0
#     · 승인된 조상(main 밖 · 가장 가까운 1개) 있음 = 표식 0 + «--approve-sha <조상>» 안내 · 그 밖(git 실패 포함) = r1117 기다림 표식 그대로 · 종료는 부르는 쪽(exit 2)
fm_ap_wait() {
  local r="$1" rm="$2" tg="$3" ap="$4" st="$5" x d b="" bd=""
  git -C "$r" cat-file -e "$ap^{commit}" 2>/dev/null || { fm_try 7 git -c gc.auto=0 -C "$r" fetch --quiet "$rm" "$ap" >/dev/null 2>&1; git -C "$r" cat-file -e "$ap^{commit}" 2>/dev/null; } \
    || { echo "REJECT 승인 sha 가 이 리포 커밋이 아님(오타 또는 받기 실패) — ${ap:0:10} · 기다림 등록 0 — 실행 0"; return; }
  for x in $(git -C "$r" rev-list "$ap" "^refs/remotes/$rm/$tg" 2>/dev/null | grep -vxF "$ap" | grep -xF -f <(ls "$st/autonomy-merge-approved" 2>/dev/null | grep -xE '[0-9a-f]{40}')); do
    d="$(git -C "$r" rev-list --count "$x..$ap" 2>/dev/null)" || continue; [ -n "$bd" ] && [ "$d" -ge "$bd" ] || { b="$x"; bd="$d"; }; done
  [ -z "$b" ] || { echo "REJECT 이 sha 는 승인 sha 가 아님 — 승인된 조상 ${b:0:10} 가 있다(승인 뒤 병합만 얹은 head 면 --approve-sha $b 로 다시 · 동일승인 대조가 받는다) · 기다림 등록 0 — 실행 0"; return; }
  echo "REJECT 오빠 승인 파일 없음 — 승인 h 한 줄 먼저(approve-merge $ap 승인 파일·로그 한 줄 없음) — 실행 0$(bash "$(dirname -- "${BASH_SOURCE[0]}")/ft-hil-notify.sh" wait "$ap" "$st")"
}
#   fm_pr_close <slug|빈> <pr> <본문파일> <쓰기도구> : r1179 — PR 코멘트+닫기 1회(fm_t7) · slug 가 FT_PR_CLOSE_AS_USER(공백 구분 · 기본 yoonhwan/ai-feature-pack · 빈 값 = 목록 0)에
#     정확히 있으면 사람 gh(GH_TOKEN·GITHUB_TOKEN 비움 = 로그인 계정 · 봇 토큰이 개인 리포에 코멘트 못 함) · 그 밖은 Tank 래퍼 그대로 · rc 그대로 · 실패 때 다른 도구로 갈아타기 0(#0 RULE)
fm_pr_close() {
  local slug="$1" pr="$2" cb="$3" gw="$4" u
  for u in ${FT_PR_CLOSE_AS_USER-yoonhwan/ai-feature-pack}; do
    [ -n "$slug" ] && [ "$u" = "$slug" ] || continue
    fm_t7 env -u GH_TOKEN -u GITHUB_TOKEN "${FT_GH:-gh}" pr close "$pr" -R "$slug" --comment "$(cat "$cb")" || return
    echo "INFO PR #$pr 닫기 = 사람 gh($slug)"; return 0
  done
  fm_t7 ${slug:+env FT_ISSUE_REPO="$slug"} "$gw" pr-close "$pr" --comment "$cb" --apply
}
#   fm_ddl_list <repo> <M> <S> : r1347 — stdout «DDL <경로>»(상태 A·M ∧ design/rag/sql/<00~89>-*.sql ∧ -rollback.sql 아님) · «CODE»(상태 무관 ∧ design/·docs/ 밖 ∧ *.md 아님) 줄 · rc≠0 = git 실패
#     diff 1회 = name-status -z --no-renames(-z = 경로 따옴표 0 · --no-renames = 이름 바꾸기를 D+A 로 · 지우기·바꾸기도 코드 동반으로 센다) · $() 는 NUL 을 지우므로 임시 파일로 읽는다
fm_ddl_list() {
  local f st p; f="$(mktemp)" || return 1
  git -C "$1" diff --name-status -z --no-renames "$2...$3" >"$f" 2>/dev/null || { rm -f "$f"; return 1; }
  while IFS= read -r -d '' st && IFS= read -r -d '' p; do
    case "$st" in A|M) if [[ "$p" =~ ^design/rag/sql/[0-8][0-9]-[^/]*\.sql$ ]] && [[ "$p" != *-rollback.sql ]]; then echo "DDL $p"; continue; fi;; esac
    case "$st" in A|M|D|T) [[ "$p" == design/* || "$p" == docs/* || "$p" == *.md ]] || echo CODE;; esac   # 코드 = 상태 A·M·D(·T) 아무거나 — 이름 바꾸기(R)는 --no-renames 가 D+A 로 풀어 준다
  done <"$f"; rm -f "$f"
}
#   FM_DDL_PY: 증거 줄 고르기 — argv = <PR 본문> <코멘트 JSON> <파일 이름들(줄바꿈)> · 본문 먼저 · 코멘트는 createdAt 순 · 파일마다 «DDL dev 적용: <이름>» 줄 중 «가장 마지막» 하나(R102 선택 규칙) · stdout «h\t이름\tN»(· hN rc=0) · «ex\t이름\t사유»(· 면제 — 사유 ≥10자) · «short\t이름» · «none\t이름»
FM_DDL_PY='import json,re,sys
try: cs=sorted(json.loads(sys.argv[2]).get("comments") or [],key=lambda x:x.get("createdAt") or "")
except (ValueError,AttributeError): sys.exit(3)
L="\n".join([sys.argv[1]]+[x.get("body") or "" for x in cs]).splitlines()
for n in sys.argv[3].split("\n"):
  rx=re.compile(r"DDL dev 적용\s*[:：]\s*"+re.escape(n)+r"(?![\w.\-])(.*)$"); v=None
  for l in L:
    m=rx.search(l); v=m.group(1) if m else v
  h=v is not None and re.match(r"\s*·\s*h(\d+)\s+rc=0\b",v); e=v is not None and re.match(r"\s*·\s*면제\s*—\s*(.+?)\s*$",v)
  print("h\t%s\t%s"%(n,h.group(1)) if h else ("ex\t%s\t%s"%(n,e.group(1)) if e and len(e.group(1))>=10 else ("short\t"+n if e else "none\t"+n)))'
#   fm_ddl_dev_gate <repo> <M> <S> <PR> <남은초> <PR본문> <slug|빈> <gh> : r1347 — «DDL 파일 + 그 DDL 을 쓰는 코드» 를 같이 올리는 PR 은 DDL 파일마다 dev 적용 증거 줄이 있어야 착지(PR 6104 · DDL 60 보다 코드가 20분 먼저 배포된 사건)
#     rc0 = 통과(stdout 에 «WARN … 면제» 줄 0~n) · rc1 = 거절 사유 1줄(부른 쪽 rej 가 «REJECT … (착지 0)» 로 감싼다) · DDL 0 또는 코드 0 = 코멘트 조회 0 으로 통과
#     코멘트 1회 조회(시도 상한 min(7, 남은 초 − 1) · 재시도 1 은 남은 초 안에서만 · 남은 초 < 2 = 판정 불가) · h<N> 인정 = FT_HIL_RAN_DIR(기본 /tmp)/h<N>.ran 마지막 줄이 «rc=0 …» 일 때만
fm_ddl_dev_gate() {
  local repo="$1" m="$2" s="$3" pr="$4" rem="$5" body="$6" slug="$7" gh="$8" lst nd nc names att c="" t0=$SECONDS i ev k n v rcv ran
  lst="$(fm_ddl_list "$repo" "$m" "$s")" || { echo "DDL dev 적용 판정 불가 — git diff 실패"; return 1; }
  nd="$(grep -c '^DDL ' <<<"$lst" || true)"; nc="$(grep -c '^CODE$' <<<"$lst" || true)"
  [ "$nd" -gt 0 ] && [ "$nc" -gt 0 ] || return 0
  for i in 1 2; do
    att=$((rem - (SECONDS - t0) - 1)); [ "$att" -le 7 ] || att=7
    [ "$att" -ge 1 ] || { echo "DDL dev 적용 판정 불가 — $([ "$i" = 1 ] && echo 남은 시간 부족 || echo PR 코멘트 조회 실패)"; return 1; }
    c="$(fm_try "$att" "$gh" pr view "$pr" ${slug:+-R "$slug"} --json comments 2>/dev/null)" && break; c=""
  done
  [ -n "$c" ] || { echo "DDL dev 적용 판정 불가 — PR 코멘트 조회 실패"; return 1; }
  names="$(sed -n 's#^DDL design/rag/sql/##p' <<<"$lst")"
  ev="$(python3 -c "$FM_DDL_PY" "$body" "$c" "$names")" || { echo "DDL dev 적용 판정 불가 — PR 코멘트 해석 실패"; return 1; }
  while IFS=$'\t' read -r k n v; do
    case "$k" in
      h) ran="${FT_HIL_RAN_DIR:-/tmp}/h$v.ran"; rcv="$(tail -n 1 "$ran" 2>/dev/null | sed -n 's/^rc=\([0-9]*\).*/\1/p')"
         [ "$rcv" = 0 ] || { echo "DDL dev 적용 h$v 확인 실패($([ -e "$ran" ] && echo "rc=${rcv:-미완}" || echo 기록 없음))"; return 1; };;
      ex) echo "WARN DDL dev 적용 면제 $n — $v";;
      short) echo "DDL dev 적용 면제 사유 10자 미만 — $n"; return 1;;
      *) echo "DDL dev 적용 증거 없음 — $n (코드 ${nc}개 동반) · PR 에 «DDL dev 적용: $n · h<N> rc=0» 줄을 올리거나 DDL 을 먼저 적용"; return 1;;
    esac
  done <<<"$ev"
}
#   fm_land_ledger <상태폴더> <승인 상태 폴더> <승인 sha> <착지 sha> <승인 줄 이벤트> : R298(DA⑥ H3) · r947 — 그 승인 sha 의 «마지막 scope-use S<n>» 한 원장(+ D1 상시 승인이면 D1 원장)의 «착지 sha 칸이 빈 행»(승인 sha == AP)에 Q·되돌림 명령 기록 · 실패해도 WARN 만(착지 rc 불변 · r1336: ft-merge-land.sh 120줄 상한 때문에 이사 · 동작 불변)
fm_land_ledger() {
  local st="$1" ast="$2" ap="$3" q="$4" afv="${5:-}" sn dl="" lf arc
  sn="$(awk -v ap="$ap" '$1=="scope-use" && $3==ap && $2 ~ /^S[0-9]+$/ {s=$2} END{print s}' "$st/autonomy.log" 2>/dev/null)"
  [ "$afv" != D1 ] || dl="$ast/autonomy-standing/D1.ledger.tsv"; [ "$afv" != D2 ] || dl="$ast/autonomy-standing/D2.ledger.tsv"   # r1577: D2 상시 승인도 같은 7칸 원장
  for lf in "$st/autonomy-scope/${sn:-none}.ledger.tsv" ${dl:+"$dl"}; do
    [ -f "$lf" ] || continue
    awk -F'\t' -v OFS='\t' -v ap="$ap" -v q="$q" '$2==ap && $6=="" {$6=q; $7="git revert --no-edit " q; n++} {print} END{exit n?0:3}' "$lf" 2>/dev/null > "$lf.$$"; arc=$?
    if [ "$arc" -eq 0 ]; then mv -f "$lf.$$" "$lf" 2>/dev/null || { rm -f "$lf.$$"; echo "WARN 대리 승인 원장 기록 실패($lf) — 착지는 성공 · 손으로: git revert --no-edit $q"; }
    else rm -f "$lf.$$"; [ "$arc" -eq 3 ] || echo "WARN 대리 승인 원장 기록 실패($lf) — 착지는 성공 · 손으로: git revert --no-edit $q"; fi
  done
  return 0
}
#   fm_land_notify <종류> <본문 1줄> [카드 경로…] : r1478 — 착지·이동 «사건» 1줄을 카드 팀 master 에 1통(착지 1건 = 1통 · 묶음 1통 · r1476 종류 표의 «사건 = doorbell»)
#     팀 = 카드 경로들의 팀 «합집합»(ft_team_has · 카드마다 그 팀 · 2팀이면 각 팀 1통) · 카드 0 일 때만 부른 좌석 FT_SEAT 둘째 토막 · 하나도 못 정하면 `INFO <종류> 쪽지 생략 — 팀 못 정함` 1줄(아무 팀장에게나 보내기 0)
#     수신 = 명부 seats-<팀>.json(FT_SEATS_JSON 이 이김 · v65 = seats.json) `_master` · 발신 = FT_SEAT | ft-merge-land | ft-index-move
#     발신 1회 상한 7초(재시도 0 · FT_LAND_DEADLINE 남은 시간이 더 짧으면 그 값 · 모자라면 호출 0) · 반환 0 고정(부른 쪽 rc 불변)
#     카드 리포 루트 = FM_NOTIFY_REPO → FT_REPO_ROOT → FT_ROOT → 카드 경로의 git 루트(팀 판정 = 그 워크트리)
#     ★명부·comm 은 «공용 루트»(--git-common-dir)에서 찾는다(보정 r2 · 착지 aaa7d2bf 뒤 실사건: 연결 worktree 안 카드 이동이 워크트리/.fable-team 을 뒤져 4통 유실)★
#     우선순위·env(FT_SEATS_JSON · FT_MBOX · FT_REPO_ROOT) 는 그대로 · INFO 에는 «찾은 경로» 를 적는다
fm_land_notify() {
  local kind="$1" body="$2"; shift 2
  local hd line root="" common="" t tg teams c seats m from rc cap used el t0=$SECONDS
  case "$kind" in 착지) hd='[착지]';; 이동) hd='[카드 이동]';; *) hd="[$kind]";; esac
  case "$body" in '['*) line="$body";; *) line="$hd $body";; esac
  from="${FT_SEAT:-}"
  [ -n "$from" ] || case "$kind" in 착지) from=ft-merge-land;; 이동) from=ft-index-move;; *) from=ft-harness;; esac
  for t in "${FM_NOTIFY_REPO:-}" "${FT_REPO_ROOT:-}" "${FT_ROOT:-}"; do
    [ -n "$t" ] || continue
    root="$(git -C "$t" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ] && break
    root=""
  done
  if [ -z "$root" ] && [ $# -gt 0 ]; then root="$(git -C "$(dirname -- "$1")" rev-parse --show-toplevel 2>/dev/null)"; fi
  if [ -n "$root" ]; then   # 보정 r2: 명부·comm = 공용 루트 — 연결 worktree 의 toplevel 에는 없다(팀 판정만 워크트리 그대로)
    common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && common="${common%/.git}"
    [ -n "$common" ] || common="$root"
  fi
  teams=""
  if [ $# -gt 0 ] && [ -n "$root" ] && [ -f "$FM_HERE/ft-team-lib.sh" ]; then
    teams="$( . "$FM_HERE/ft-team-lib.sh" >/dev/null 2>&1 || exit 0
      for c in "$@"; do
        for tg in $(FT_REPO_ROOT="$root" ft_team_names 2>/dev/null); do
          FT_REPO_ROOT="$root" ft_team_has "$tg" "$c" >/dev/null 2>&1 && printf '%s\n' "$tg"
        done
      done | awk '!seen[$0]++' )"
  fi
  if [ -z "$teams" ] && [ $# -eq 0 ] && [ -n "${FT_SEAT:-}" ]; then teams="$(printf '%s' "$FT_SEAT" | cut -d- -f2)"; fi
  if [ -z "$teams" ]; then echo "INFO $kind 쪽지 생략 — 팀 못 정함"; return 0; fi
  for tg in $teams; do
    [ -n "$tg" ] || continue
    seats="${FT_SEATS_JSON:-}"
    if [ -z "$seats" ]; then
      [ -n "$common" ] || { echo "INFO $kind 쪽지 생략 — 카드 리포 공용 루트 못 풂($tg)"; continue; }
      if [ "$tg" = v65 ]; then seats="$common/.fable-team/seats.json"; else seats="$common/.fable-team/seats-$tg.json"; fi
    fi
    [ -f "$seats" ] || { echo "INFO $kind 쪽지 생략 — 팀 명부 없음($tg · $seats)"; continue; }
    m="$(python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: sys.exit(0)
v=d.get("_master","") if isinstance(d,dict) else ""
print(v if isinstance(v,str) else "")' "$seats" 2>/dev/null)"
    [ -n "$m" ] || { echo "INFO $kind 쪽지 생략 — 명부에 _master 없음($tg · $seats)"; continue; }
    if [ -z "${FT_MBOX:-}" ] && [ -z "$common" ]; then echo "INFO $kind 쪽지 생략 — 우편함 경로 못 풂($tg)"; continue; fi
    used=$((SECONDS - t0)); cap=$((7 - used)); [ "$cap" -ge 1 ] || cap=0
    if el="$(fm_fetch_deadline_rem)"; then [ "$el" -ge "$cap" ] || cap="$el"; fi
    if [ "$cap" -lt 1 ]; then echo "WARN $kind 쪽지 발신 실패 → $m(0 · 시간 초과)"; continue; fi
    fm_try "$cap" bash "${FT_MBOX:-$common/.fable-team/comm/mbox.sh}" send "$m" "$from" "$line" >/dev/null 2>&1; rc=$?
    case "$rc" in
      0) echo "NOTIFIED $kind → $m";;
      124|143) echo "WARN $kind 쪽지 발신 실패 → $m($rc · 시간 초과)";;
      *) echo "WARN $kind 쪽지 발신 실패 → $m($rc)";;
    esac
  done
  return 0
}
#   fm_cards_by_tokens <리포루트> <r<숫자> 토큰…> : stdout = 이름에 그 토큰이 든 카드 파일 절대경로(design/**/indices/*/*.md) · 토큰 0 = 출력 0
#   ★r1743 A1: 출처 = «카드 ref 트리»(directive-roots.tsv 3칸의 서로 다른 ref · 표 없음 = FT_CARD_REF|origin/main) ls-tree 1/ref(7초) · 루트 index·디스크 안 봄 · A2 중복 1줄 · A3 ref 전부 못 읽으면 stdout 0 + FM_CARDS_ERR + stderr WARN★
#   ★r1821: 표 = <root> 의 표 → 없으면 git common root 의 표 · 토큰 있는데 0장 = FM_CARDS_ERR · 부른 쪽 셸에 FM_CARDS_TAB·FM_CARDS_REFS(결과 줄용)★
#     카드 이름 꿴 «r1478-…» · 다른 글자로 이어진 «ar1478» 은 안 잡는다(-<토큰>- 로 본다)
fm_cards_by_tokens() {
  local root="$1"; shift; FM_CARDS_ERR=""; FM_CARDS_TAB=""; FM_CARDS_REFS=""
  [ -n "$root" ] && [ $# -gt 0 ] || return 0
  local ref refs out rc ok=0 bad="" rd="" p b t c tab="$root/.fable-team/state/directive-roots.tsv"; local -a hit=()
  if [ ! -f "$tab" ]; then   # r1821 C1: root 자신의 표 먼저 → 없으면 git common root(라이브 worktree 로 불려도 공용 표) · 카드는 그대로 root 의 ref 트리
    c="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; tab=""; [ -z "$c" ] || tab="${c%/*}/.fable-team/state/directive-roots.tsv"
  fi
  [ -f "$tab" ] || tab=""; FM_CARDS_TAB="${tab:-없음}"
  refs="$(awk -F'\t' 'NF>=3 && $3!="" && !s[$3]++{print $3}' "${tab:-/dev/null}" 2>/dev/null)"
  [ -n "$refs" ] || refs="${FT_CARD_REF:-origin/main}"; FM_CARDS_REFS="$(printf '%s\n' $refs | paste -sd, -)"
  for ref in $refs; do
    out="$(fm_try 7 git -c core.quotepath=false -C "$root" ls-tree -r --name-only "$ref" -- design 2>/dev/null)"; rc=$?
    if [ "$rc" -ne 0 ]; then bad="${bad:+$bad, }$ref(rc=$rc)"; continue; fi
    ok=$((ok + 1)); rd="${rd:+$rd,}$ref"
    while IFS= read -r p; do   # r1717: 한글 폴더(진행·완성)를 따옴표 꼴로 내지 않게 — 차례 장부가 이 경로를 그대로 쓴다
      case "$p" in design/*/indices/*/*.md|design/teams/*/indices/*/*.md) ;; *) continue;; esac
      b="-${p##*/}"; b="${b%.md}-"
      for t in "$@"; do case "$b" in *"-$t-"*) hit[${#hit[@]}]="$p"; break;; esac; done
    done <<< "$out"
  done
  if [ "$ok" -eq 0 ]; then   # 하드 룰 20: 조용한 0장 금지 — 판정 불가를 글자로 남긴다
    FM_CARDS_ERR="카드 ref 를 하나도 못 읽음 — $bad"; echo "WARN cards_err: $FM_CARDS_ERR" >&2; return 0
  fi
  [ -z "$bad" ] || echo "WARN 카드 ref 일부 못 읽음 — $bad(나머지 ref 결과만)" >&2
  if [ "${#hit[@]}" -eq 0 ]; then   # r1821 C2: 토큰이 있는데 0장 = 판정 불가(«카드 없음» 아님)
    FM_CARDS_ERR="토큰 $* 카드 0장 · 읽은 ref $rd · 표 $FM_CARDS_TAB"; echo "WARN cards_err: $FM_CARDS_ERR" >&2; return 0
  fi
  printf '%s\n' "${hit[@]}" | awk '!s[$0]++' | while IFS= read -r p; do printf '%s/%s\n' "$root" "$p"; done
}
#   fm_land_notify_land <카드리포루트> <PR> <착지 sha 앞자리> <PR 제목> <설치 검사 rc> <설치 검사 출력> [<head 가지>] : r1478 — ft-merge-land 끝 1줄
#     카드 = r1848: head 가 nano/r<N>- 이면 r<N> 하나 · 아니면 제목의 r<숫자> 토큰(본문 0 — 옛 카드 재알림 막음) · 설치 칸 = OK(대조 n>=1) | PENDING(검사 rc!=0 · 시간 초과 포함) | SKIP(범위에 하네스 파일 0)
#     받은 root 는 FM_NOTIFY_REPO 로 넘긴다(env 가 다른 리포를 가리켜도 카드 리포가 이김 · DA HOLD #274782 F2)
fm_land_notify_land() {
  local root="$1" pr="$2" sh="$3" txt="$4" irc="$5" iout="$6" nst=SKIP tok t0=$SECONDS
  printf '%s\n' "$iout" | head -n1 | grep -qE '^OK n=[1-9]' && nst=OK
  [ "${irc:-0}" = 0 ] || nst=PENDING
  tok="$(printf '%s\n' "${7:-}" | grep -oE '^nano/r[0-9]{2,5}-' | grep -oE 'r[0-9]+')"
  [ -n "$tok" ] || tok="$(printf '%s\n' "$txt" | grep -oE 'r[0-9]{2,5}' | sort -u | tr '\n' ' ')"
  tok="${tok% }"
  # shellcheck disable=SC2086
  FM_NOTIFY_REPO="$root" fm_land_notify 착지 "[착지] pr=$pr sha=$sh 카드 ${tok:-없음} · 설치 $nst" $(fm_cards_by_tokens "$root" $tok)
  fm_land_turn "$root" "$pr" "$t0" $tok
}
#   fm_land_turn <카드리포루트> <PR> <시작 SECONDS> [<r토큰>…] : r1717 A1·A4ⓐ — ①차례 장부 1줄 append(<공용 루트>/.fable-team/state/land-record-turn.jsonl · 카드 0장도 cards:[] · 쓰기 실패 = WARN 1줄 · 네트워크 0) ②ft-nano-record.sh notify --pr <N> --no-fetch 1회
#     ② 상한 = 착지 쪽지와 같은 7초 몫의 «남은 시간»(착지 마감이 더 짧으면 그 값 · < 1초 = 호출 0 → 장부가 남아 ft_stall_scan 이 보낸다) · 착지 값(Q·HEADSHA·REPO·TARGET)은 부른 ft-merge-land 의 변수 · 반환 0 고정(착지 rc 불변)
fm_land_turn() {
  local root="$1" pr="$2" t0="$3" c f cap el of err="" p dk="" dn=""; local -a cd=(); shift 3; c="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; c="${c%/.git}"; c="${c:-$root}"; f="$c/.fable-team/state/land-record-turn.jsonl"
  of="$(mktemp "${TMPDIR:-/tmp}/fm-cards.XXXXXX" 2>/dev/null)" || of=""   # r1743 A3: FM_CARDS_ERR 를 부른 쪽 셸에서 읽는다(명령 치환 = 서브셸이면 표지가 안 남는다)
  if [ -n "$of" ]; then fm_cards_by_tokens "$root" "$@" >"$of"; err="$FM_CARDS_ERR"; while IFS= read -r p; do [ -z "$p" ] || cd[${#cd[@]}]="$p"; done <"$of"; rm -f "$of"; else err="카드 목록 임시 파일 생성 실패 — mktemp(${TMPDIR:-/tmp})"; echo "WARN cards_err: $err" >&2; fi   # r1743 R1: 임시 파일 실패도 조용한 0장 금지(하드 룰 20)
  [ $# -eq 0 ] || echo "카드 root=$root 표=${FM_CARDS_TAB:-없음} refs=${FM_CARDS_REFS:-없음} cards=${#cd[@]}"   # r1821 C3: 착지 결과 1줄(카드 stdout 과 따로)
  cap=$((7 - (SECONDS - t0))); if el="$(fm_fetch_deadline_rem)"; then [ "$el" -ge "$cap" ] || cap="$el"; fi   # r1782 A1: 착지가 main 에 더한 파일(M→Q · 실제 착지 REPO · 남은 7초 몫) · 전부 design/·docs/ = doc_only · 실패 = doc_err(구현으로 본다)
  if [ -z "${M:-}" ] || [ -z "${Q:-}" ]; then dk="M·Q 빈 값"; elif [ "$cap" -lt 1 ]; then dk="시간 초과(남은 0초)"; else dn="$(fm_try "$cap" git -C "${REPO:-$root}" diff --no-renames --name-only -z "$M" "$Q" | tr '\0' '\n'; exit "${PIPESTATUS[0]}")" || dk="git diff 실패 rc=$?"; fi
  [ -z "$dk" ] || { dn=""; echo "WARN doc_err: $dk — 구현 착지로 본다(pr=$pr)" >&2; }; [ -n "$dn" ] && ! grep -qvE '^(design|docs)/' <<<"$dn" && dn=1 || dn=""
  { mkdir -p "${f%/*}" && python3 -c 'import json,sys,time;a=sys.argv;d={"pr":int(a[1]),"repo":a[2],"target":a[3],"landed":a[4],"pr_head":a[5],"by":a[6],"cards":a[10:],"ts":time.strftime("%Y-%m-%dT%H:%M:%S")};a[9] and d.update(cards_err=a[9]);a[7] and d.update(doc_only=True);a[8] and d.update(doc_err=a[8]);print(json.dumps(d,ensure_ascii=False))' "$pr" "$(cd -- "${REPO:-$root}" 2>/dev/null && pwd -P)" "${TARGET:-main}" "${Q:-}" "${HEADSHA:-}" "${FT_SEAT:-}" "$dn" "$dk" "$err" ${cd[@]+"${cd[@]}"} >>"$f"; } 2>/dev/null || echo "WARN 착지 차례 장부 쓰기 실패($f) — 착지는 성공"   # r1717-mut:ledger
  cap=$((7 - (SECONDS - t0))); if el="$(fm_fetch_deadline_rem)"; then [ "$el" -ge "$cap" ] || cap="$el"; fi
  [ "$cap" -lt 1 ] || [ ! -f "$FM_HERE/ft-nano-record.sh" ] || FT_ROOT="$c" fm_try "$cap" bash "$FM_HERE/ft-nano-record.sh" notify --pr "$pr" --no-fetch 2>&1 || true
}
#   fm_land_notify_d2 <PR> <착지 sha> <PR 제목·본문> : r1577 — D2 승인 줄로 착지했을 때 슬랙 1줄(«병합함: PR #N · 카드 · DA APPROVE · 되돌림 명령»)
#     게시 = ft-autonomy-scope.sh 의 scope_slack_post 재사용(사본 0 · 서브셸이라 scope_err 의 exit 이 착지 rc 를 못 건드린다) · 실패 = stderr 1줄 · 착지 rc 불변
fm_land_notify_d2() {
  local pr="$1" q="$2" txt="$3" tok body out rc
  tok="$(printf '%s' "$txt" | grep -oE 'r[0-9]{2,5}' | sort -u | tr '\n' ' ')"; tok="${tok% }"
  body="$(printf '병합함: PR #%s · 카드 %s · DA APPROVE · 되돌림: git revert --no-edit %s' "$pr" "${tok:-없음}" "$q")"
  out="$( ( . "$FM_HERE/ft-autonomy-scope.sh" >/dev/null 2>&1; scope_slack_post "$body" ) 2>&1 )"; rc=$?
  [ "$rc" = 0 ] || echo "WARN 병합 뒤 슬랙 알림 실패(rc=$rc) — 착지는 성공(sha $q) · ${out%%$'\n'*}" >&2
  return 0
}
#   fm_land_notify_move <from> <to> <카드 절대경로> [<DA>] : r1478 — ft-index-move 끝 1줄 · 팀 판정은 카드 경로가 이긴다(이동은 이미 끝났다 · 실패 = WARN 1줄 · rc 불변)
fm_land_notify_move() {
  local from="$1" dst="$2" card="$3" da="${4:-}" rt b
  b="$(basename -- "$card" .md)"; rt="$(printf '%s' "$b" | grep -oE 'r[0-9]{2,5}' | head -n1)"
  [ -n "$rt" ] || rt="$b"
  fm_land_notify 이동 "[카드 이동] $rt ${from}→${dst}${da:+ · DA $da}" "$card"
}
