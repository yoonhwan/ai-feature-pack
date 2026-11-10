#!/usr/bin/env bash
# ft-autonomy-level.sh — 자율 레벨 · 종류 학습 · 자율 인터뷰 쪽지 (r466) — ft-autonomy.sh 가 source 한다(단독 실행 금지)
#   레벨 = full(풀자동 · 기본) | mid(중간) | each(건마다 확인) — 기본 범위 = templates/autonomy-level.conf (줄: 레벨 max daily classes codemax repos · each = `-`)
#   on --level L [--max --daily --code-max] : 같은 잠금 안에서 «슬랙 게시 → 모드 줄 → 범위 승인 줄(level=L)» — 게시 실패 = 둘 다 쓰기 0(rc 1) · each = 범위 승인 줄 0
#   종류 학습: scope-approve 거절 `FORBID kind=X` = denied.tsv 1행 → 오빠 approve-merge(ON ∧ 레벨 full) = learned-kinds.tsv 1행 → 다음 같은 종류 = 분류기 docs(learned)
#   forget-kind <키>                    오빠 `!` 전용 — 학습표에서 그 종류를 뺀다(scope-stop·OFF 는 학습표를 지우지 않는다)
#   interview-note <A<N>> <expire|off>   planner 명부 `_desk` 에 `[자율 인터뷰]` 1통(연장/종료/레벨 변경 · 추천 1) · 같은 사건·종류 10분 중복 억제 · 명부 자리 = ①$ROOT ②$ROOT 가 속한 리포 공용 루트(r926 r2 · cwd·설치 위치는 보지 않는다) · 둘 다 없음 = WARN + rc1(조용한 건너뜀 0)
NEVER_LEARN=",secret,repo-outside,scope-table,mode,"   # 비밀 꼴 줄·경계 종류(r1208)는 오빠 승인으로도 «종류» 저장 0 (분류기 rules.NEVER_LEARN 과 같다)
level_label() { case "$1" in full) echo 풀자동 ;; mid) echo 중간 ;; each) echo "건마다 확인" ;; *) echo "$1" ;; esac; }
tpl_file() { local d; for d in "$HERE/../templates" "$HERE/../kit/fable-team/templates"; do [ -f "$d/$1" ] && { printf '%s\n' "$d/$1"; return 0; }; done; return 1; }

level_prepare() {  # ON_LEVEL ON_MAX ON_DAILY ON_CM(parse_end 가 채움) → 기본표 + 덮어쓰기 + 검사 → SV_*(each 면 검사 0) · 틀리면 REJECT rc 2(상태 쓰기 0)
  local f row l mx dl cl cm rp
  ON_LEVEL="${ON_LEVEL:-${FT_AUTONOMY_LEVEL:-full}}"   # --level 생략 = 풀자동(오빠 «기본 풀자동») · FT_AUTONOMY_LEVEL 은 기본값만 바꾼다(시험·슬랙 없는 환경)
  case "$ON_LEVEL" in full|mid|each) ;; *) reject "--level 은 full|mid|each(받은 값: $ON_LEVEL)" ;; esac
  if [ "$ON_LEVEL" = each ]; then [ -z "$ON_MAX$ON_DAILY$ON_CM" ] || reject "--level each 는 범위 승인 0 — --max·--daily·--code-max 를 못 쓴다"; return 0; fi   # each = 기본표 불필요
  f="${FT_AUTONOMY_LEVEL_CONF:-$(tpl_file autonomy-level.conf)}" || reject "레벨 기본표 없음(templates/autonomy-level.conf)"
  row="$(awk -v l="$ON_LEVEL" '$1==l {print; exit}' "$f" 2>/dev/null)"
  read -r l mx dl cl cm rp <<<"$row"
  [ -n "$rp" ] || reject "레벨 기본표에 $ON_LEVEL 줄 없음·꼴 틀림: $f"
  [ "$cm" = 0 ] && cm=""
  . "$HERE/ft-autonomy-scope.sh"
  scope_validate "${ON_MAX:-$mx}" "${ON_DAILY:-$dl}" "$cl" "${ON_CM:-$cm}" "$rp"
}

level_grant_post() {  # <사건> — 잠금 안 · 모드 줄 «전» 게시(실패 = rc 1 · 쓰기 0)
  [ "$ON_LEVEL" = each ] && return 0
  local now u endl=""; now="$(now_epoch)"; u="$UNTIL"; [ "$u" = null ] && { u=$(( now + 86400 )); endl=1; }   # 끝 없는 ON 의 범위 = 24h(그 뒤 재발급은 scope-approve) — 슬랙 3줄은 «끝 없음» 을 그대로 말한다(r658)
  scope_grant_post "$1" "$now" "$u" "$SV_MX" "$SV_DL" "$SV_CL" "$SV_CM" "$SV_REPOS" "$ON_LEVEL" "$endl"
}
level_grant_write() { [ "$ON_LEVEL" = each ] || scope_grant_write; }

level_status() {  # status 의 ON 줄 꼬리 — full·mid 만(each·level 칸 없는 옛 json = 옛 status 그대로 · 범위 승인은 scope-status 가 보인다)
  local l s="범위 없음"; l="$(jfield level)"
  [[ "$l" == full || "$l" == mid ]] || return 0
  . "$HERE/ft-autonomy-scope.sh"; scope_load && { scope_block; [ -z "$BLOCK" ] && s="범위 $G_S"; }
  printf ' · 레벨 %s · %s' "$(level_label "$l")" "$s"
}

learn_kind() {  # <sha> <승인 epoch> — approve-merge 잠금 안 · ON ∧ 레벨 full ∧ 거절 원장에 그 sha 행 → 종류 1행(같은 종류 재저장 0)
  local sd="$STATE/autonomy-scope" k
  [ "$(mode)" = on ] && [ "$(jfield level)" = full ] || return 0
  k="$(awk -F'\t' -v s="$1" '$1==s {k=$2} END{print k}' "$sd/denied.tsv" 2>/dev/null)"
  [ -n "$k" ] || return 0
  case "$NEVER_LEARN" in *",$k,"*) echo "LEARN-SKIP kind=$k (학습 불가 종류)"; return 0 ;; esac
  awk -F'\t' -v k="$k" '$1==k {f=1} END{exit !f}' "$sd/learned-kinds.tsv" 2>/dev/null && return 0
  printf '%s\t%s\t%s\tfull\n' "$k" "$1" "$2" >> "$sd/learned-kinds.tsv" || { echo "REJECT 학습표 쓰기 실패" >&2; exit 1; }
  echo "LEARNED kind=$k sha=$1"
}

cmd_forget_kind() {  # 오빠 `!` 전용(훅이 좌석 실행을 막는다)
  local k="${1:-}" f="$STATE/autonomy-scope/learned-kinds.tsv"
  [[ "$k" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "REJECT usage: forget-kind <종류 키>" >&2; exit 2; }
  lock; awk -F'\t' -v k="$k" '$1==k {f=1} END{exit !f}' "$f" 2>/dev/null || { echo "REJECT 학습표에 없는 종류: $k" >&2; exit 2; }
  { awk -F'\t' -v k="$k" '$1!=k' "$f" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"; } || { echo "REJECT 학습표 쓰기 실패" >&2; exit 1; }
  unlock; echo "FORGOT kind=$k"
}

cmd_on_check() { parse_end "$@"; level_prepare; echo "ON-CHECK-OK level=$ON_LEVEL until=$UNTIL"; }   # ft-autonomy-interview.sh 가 부른다 — on 과 같은 판정 · 상태 쓰기 0
cmd_interview_note() { interview_note "$@"; }

_roster_common_root() {  # <폴더> → 그 폴더가 속한 리포 공용 루트(git 공용 dir 의 부모) · 7초 상한 · timeout·gtimeout 둘 다 없으면 git 호출 0(rc1) — r926 r2
  local to g
  to="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$to" ] || return 1
  g="$("$to" 7 git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$g" ] || return 1
  printf '%s\n' "${g%/.git}"
}

interview_note() {  # <A<N>> <expire|off> — rc 1 = 못 보냄(WARN stderr · 모드 기록은 이미 끝)
  local ev="$1" kind="$2" desk mb body l gt mk="$STATE/autonomy-interview" now rr p found=""
  [[ "$ev" =~ ^A[0-9]+$ ]] && { [ "$kind" = expire ] || [ "$kind" = off ]; } || { echo "REJECT usage: interview-note <A<N>> <expire|off>" >&2; return 2; }
  desk="${FT_AUTONOMY_DESK:-}"
  if [ -z "$desk" ]; then
    # r926 r2: 명부 자리 = $ROOT 기준으로만 — ①$ROOT ②$ROOT 가 속한 리포 공용 루트. cwd·설치 위치는 보지 않는다(FT_ROOT=A · cwd=B 면 B 명부로 보내는 길 · DA⑥ r1 반례 1)
    rr="$(_roster_common_root "$ROOT")" || rr=""
    for p in "$ROOT/.fable-team/seats-planner.json" "${rr:+$rr/.fable-team/seats-planner.json}"; do
      [ -f "$p" ] || continue
      desk="$(python3 -c 'import json,sys;v=json.load(open(sys.argv[1])).get("_desk");print(v if isinstance(v,str) else "")' "$p" 2>/dev/null)"
      [ -z "$desk" ] || break
      found="$p"
    done
    if [ -z "$desk" ]; then
      [ -z "$found" ] || { echo "WARN 자율 인터뷰 쪽지 못 보냄: planner 명부에 _desk 없음 ($found)" >&2; return 1; }
      echo "WARN 자율 인터뷰 쪽지 못 보냄: planner 명부 못 찾음(찾은 자리 2곳: $ROOT/.fable-team/seats-planner.json · ${rr:-<공용 루트 못 풂>}/.fable-team/seats-planner.json)" >&2; return 1
    fi
  fi
  now="$(now_epoch)"; mkdir -p "$mk" || return 1
  if [ -f "$mk/$ev.$kind" ] && [ $(( now - $(head -1 "$mk/$ev.$kind") )) -lt $(( 10 * 60 )) ]; then echo "INTERVIEW-DUP $ev $kind"; return 0; fi
  l="$(jfield level)"; l="${l:-full}"
  if [ "$kind" = expire ]; then body="[자율 인터뷰] $ev 끝 도달 — ①연장(추천 · 같은 레벨 $(level_label "$l") · 12h) ②종료 ③레벨 변경(full 풀자동·mid 중간·each 건마다 확인)"
  else body="[자율 인터뷰] $ev OFF — 다음 ON 때 기간·레벨: ①다시 켜기(추천 · $(level_label "$l") · 12h) ②꺼 둠 ③레벨 변경(full·mid·each)"; fi
  body="$body"$'\n'"답 → desk 가 ft-autonomy-interview.sh --for <N>h --level <레벨> → ! bash /tmp/h<N> 1줄(오빠 손 1번 · 범위 승인까지 같이 걸림 · r466)"
  gt="${FT_AUTONOMY_GOAL_TABLE:-$HERE/ft-goal-table.sh}"
  if [ "$gt" != 0 ]; then l="$(bash "$gt" render 2>/dev/null)" && body="${body%%$'\n'*}"$'\n'"$l"$'\n'"${body#*$'\n'}" || echo "WARN 골 표 블록 못 붙임(ft-goal-table.sh render rc≠0)" >&2; fi
  mb="${FT_AUTONOMY_MBOX:-}"; [ -n "$mb" ] || { mb="$(. "$HERE/ft-harness-root.sh" && ft_comm_dir "$HERE")/mbox.sh" || return 1; }
  bash "$mb" send "$desk" ft-autonomy "$body" >/dev/null 2>&1 || { echo "WARN 자율 인터뷰 쪽지 못 보냄: mbox send rc≠0 → $desk" >&2; return 1; }
  printf '%s\n' "$now" > "$mk/$ev.$kind"; echo "INTERVIEW-SENT $ev $kind → $desk"
}
