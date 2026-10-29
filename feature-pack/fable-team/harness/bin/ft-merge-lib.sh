#!/usr/bin/env bash
# ft-merge-lib.sh — 병합·랜딩 도구 공용 함수 (R230 · source 전용 · 7초 룰 판정 666)
#   fm_try <초> <명령…>       : 한 번 시도 · timeout 도구 없으면 rc 127 (조용한 통과 0) — 초는 부른 쪽이 정한다
#   fm_t7 <명령…>            : 시도당 timeout 7 초 + 재시도 1 (총 14 초 상한) — timeout 도구 없으면 rc 127 (조용한 통과 0)
#   fm_fetch <repo> <remote> <ref> : 한 ref 만 받는다 · 시도당 상한 = fm_fetch_sec(기본 7 · FT_FETCH_TIMEOUT_SEC 1~70 = 오빠 예외 판정 · r1069) + 재시도 1
#   ★7 초 고정은 gh·push·게이트 등 나머지 그대로★ — 늘어나는 칸은 «PR head fetch» 하나뿐이고, 값을 준 실행은 ft-merge-land 첫 줄에 «오빠 예외 판정» 을 남긴다.
fm_timeout_bin() { command -v timeout || command -v gtimeout; }
fm_try() {
  local s="$1"; shift; local tb; tb="$(fm_timeout_bin)" || { echo "timeout/gtimeout 없음 — 상한을 걸 수 없어 외부 호출 거절" >&2; return 127; }
  "$tb" "$s" "$@"
}
fm_t7() {
  local rc=0 i; for i in 1 2; do fm_try 7 "$@" && return 0; rc=$?; done
  return "$rc"
}
#   fm_fetch_sec : fetch 상한 초 — FT_FETCH_TIMEOUT_SEC(정수 1~70 · 오빠 예외 판정) · 없으면 7 · 꼴이 틀리거나 70 초과면 WARN(stderr) 1줄 + 7
#     stdout = 초 · 결과를 FM_FETCH_SEC 에, «유효 지정» 여부를 FM_FETCH_SEC_VALID(1|0) 에 남긴다 ⇒ 부른 쪽은 `fm_fetch_sec >/dev/null` 꼴로 부른다(명령 치환 = 서브셸이면 표지가 안 남는다)
fm_fetch_sec() {
  local v="${FT_FETCH_TIMEOUT_SEC:-}"; FM_FETCH_SEC=7; FM_FETCH_SEC_VALID=0
  if [ -n "$v" ]; then
    case "$v" in
      *[!0-9]*) echo "WARN FT_FETCH_TIMEOUT_SEC=$v 는 1~70 정수가 아님 → 7 로" >&2;;
      *) if [ "$v" -ge 1 ] 2>/dev/null && [ "$v" -le 70 ] 2>/dev/null; then FM_FETCH_SEC="$v"; FM_FETCH_SEC_VALID=1
         else echo "WARN FT_FETCH_TIMEOUT_SEC=$v 는 1~70 밖 → 7 로" >&2; fi;;
    esac
  fi
  echo "$FM_FETCH_SEC"
}
#   fm_fetch_banner : 「오빠 예외 판정[ <N>] · 지정 <초>」 한 줄 — FT_FETCH_TIMEOUT_SEC 가 유효 지정일 때만(아니면 출력 0). N = FT_FETCH_EXCEPTION_ID(영숫자만 · 없으면 빈칸)
fm_fetch_banner() {
  local id; [ "${FM_FETCH_SEC_VALID:-0}" = 1 ] || return 0
  id="$(printf '%s' "${FT_FETCH_EXCEPTION_ID:-}" | tr -cd 'A-Za-z0-9')"
  echo "오빠 예외 판정${id:+ $id} · 지정 $FM_FETCH_SEC"
}
fm_fetch() {
  local s rc=0 i; s="$(fm_fetch_sec)"
  for i in 1 2; do fm_try "$s" git -c gc.auto=0 -C "$1" fetch --quiet "$2" "$3" && return 0; rc=$?; done
  return "$rc"
}
#   fm_head_branch <gh pr view JSON> : stdout = headRefName — isCrossRepository 가 «정확히 false»(같은 리포 PR) ∧ 가지 이름 꼴일 때만 · 아니면 rc 1(포크·칸 없음·빈 값 · r1127)
fm_head_branch() {
  local b; b="$(printf '%s' "$1" | python3 -c 'import json,sys;d=json.load(sys.stdin);sys.exit(1) if d.get("isCrossRepository") is not False else print(d.get("headRefName") or "")')" || return 1
  [ -n "$b" ] && git check-ref-format --branch "$b" >/dev/null 2>&1 && printf '%s' "$b"
}
#   fm_push_calc <객체수|?> : push «시도당 상한»(정수 초 · 소수 버림) = min(F + 7 × ceil(N/U0), 70) — 규칙 12 «쪼갤 수 없는 크기 아는 배치»(판정 1375). N 모름(?) = F + 7.
#     F = FT_PUSH_FIXED_S(기본 4.5 · ssh 접속 2.9 + pre-push 훅 1.1 실측 + 여유 · 7 초과는 7 로 클램프) · U0 = FT_PUSH_UNIT_OBJECTS(기본 100 객체/7 s 잠정 · 양의 정수 아니면 기본) · 잘못된 env 는 WARN(stderr)
#   fm_push_bound <repo> <M> <Q> : stdout "<객체수|?> <시도당 상한>" — 객체수 = rev-list --objects M..Q · 조회 실패는 WARN 1줄 + 호환값(F+7) (조용한 통과 0)
fm_push_calc() {
  local n="$1" f="${FT_PUSH_FIXED_S:-4.5}" u="${FT_PUSH_UNIT_OBJECTS:-100}"
  printf '%s' "$f" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && awk -v f="$f" 'BEGIN{exit !(f>0)}' || { echo "WARN FT_PUSH_FIXED_S=$f 는 0 보다 큰 숫자가 아님 → 기본 4.5" >&2; f=4.5; }
  awk -v f="$f" 'BEGIN{exit !(f>7)}' && { echo "WARN FT_PUSH_FIXED_S=$f 는 7 초과 → 7 로 클램프" >&2; f=7; }
  printf '%s' "$u" | grep -Eq '^[0-9]+$' && [ "$u" -gt 0 ] || { echo "WARN FT_PUSH_UNIT_OBJECTS=$u 는 양의 정수가 아님 → 기본 100" >&2; u=100; }
  if [ "$n" = '?' ]; then awk -v f="$f" 'BEGIN{printf "%d\n", f+7}'
  else awk -v f="$f" -v n="$n" -v u="$u" 'BEGIN{k=int((n+u-1)/u); if(k<1)k=1; t=f+7*k; if(t>70)t=70; printf "%d\n", t}'; fi
}
fm_push_bound() {
  local out n
  if out="$(git -C "$1" rev-list --objects "$2..$3" 2>&1)"; then n="$(printf '%s\n' "$out" | grep -c . || true)"
  else echo "WARN 객체 수 조회 실패(rev-list) → 크기 모름 · 상한 F+7 호환값: $(printf '%s' "$out" | tail -n1)" >&2; n='?'; fi
  echo "$n $(fm_push_calc "$n")"
}
#   fm_land_ctx <repo> <remote> <ft_root|빈> : r648 — 승인 루트(부른 리포)와 대상 리포를 가른다. stdout 1줄 "<원장루트>|<CROSS 0|1>|<owner/name|빈>|<base-head 경로>|<대상 리포 루트>" (칸 구분 = | — 빈 칸이 있어도 밀리지 않게 탭 금지)
#     원장 루트 = FT_ROOT → 부른 리포(cwd 공용 루트) → 대상 리포 · CROSS = 부른 리포 ≠ 대상 리포(«리포 기준» 모드 — 원장은 부른 쪽 한 곳)
#     owner/name 은 CROSS 일 때만 잡는다(아니면 빈 값 = 이전 판 그대로 -R·FT_ISSUE_REPO 0) · 실제 전송 URL «전부»(`remote get-url --all` + `remote get-url --push --all` — push 는 등록된 모든 URL 로 간다)가 같은 github owner/name 일 때만(목적지가 둘 이상이거나 갈리면 REJECT)
#     base-head = <원장루트>/.fable-team/state/base-head · CROSS 면 -<owner>-<name> 꼬리(다른 리포 sha 를 기준 헤드로 섞지 않는다)
#     rc 1 = 대상 리포 루트 확인 실패 또는 CROSS 인데 owner/name 을 못 풂(다른 리포 PR 을 조용히 조회하는 길 0)
fm_land_ctx() {
  local repo="$1" rem="$2" ft="${3:-}" xrepo="" rroot="" rt="" slug="" bh cross=0
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
    if o="$(fm_t7 ${slug:+env FT_ISSUE_REPO="$slug"} "$gw" pr-close "$pr" --comment "$cb" --apply 2>&1 </dev/null)"; then ok="$ok $pr"; echo "INFO 닫기 재시도 PR #$pr 닫음(착지 sha $sha)"
    else echo "WARN 닫기 재시도 실패 PR #$pr — 장부에 남김: $(printf '%s' "$o" | tail -n1 | cut -c1-160)"; fi
  done <<<"$items"
  rm -f "$cb"
  [ -z "$ok" ] || fm_close_pending_rm "$f" "$key" $ok || echo "WARN 닫기 대기 장부 정리 실패($f) — 닫힌 PR:$ok"
  return 0
}
