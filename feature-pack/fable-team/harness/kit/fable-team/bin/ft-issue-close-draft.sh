#!/usr/bin/env bash
# ft-issue-close-draft.sh --card <완성 카드> [--issue <N>] [--post] [--out <초안 파일>]   (r1349 · Issue #6188)
#   완성 카드 1장 → Issue 닫는 코멘트 초안(8항 + «연결 PR: 팩 PR #N · 착지 sha <40hex>» + token) · Issue 를 닫지는 않는다.
#   읽는 곳 = 카드 0열 «- 키:» 줄(``` 울타리 밖 · 키마다 마지막 줄 하나) + 카드가 가리키는 판정문 «## §N — CLOSE rNNNN» 절.
#   --post = ft-issue-close-check.sh <N> --extra-comment <초안> 이 «PASS #N 완료 8항» 일 때만 Tank 래퍼로 1회 게시(재게시 0).
#   exit 0 = 초안 만듦·게시함·이미 있음(ALREADY) · 1 = REJECT(사전 검사 FAIL · 판정문 불일치 · 잠금) · 2 = usage·번호·--out 충돌
#        3 = 판정 불가(조회 실패 · 게시 결과 불명) · 4 = DRAFT-ONLY(게시 0 · 사유 1줄 · 카드 보완 또는 사람 확인)
#   저장소 = FT_ISSUE_REPO(기본 SecondWindStudio/byz-agents) 하나 — close-check(GH_REPO)·token 조회·래퍼 모두 같다.
#   시험 훅 = FT_CLOSE_DRAFT_CHECK(close-check 대신) · FT_CLOSE_DRAFT_CHECK_JSON(Issue JSON 픽스처 · close-check --from-json 겸용) · FT_TANK_WRAPPER · FT_CLOSE_DRAFT_STATE · FT_GATE_TIMEOUT_S
set -uo pipefail
unset GH_TOKEN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${FT_ISSUE_REPO:-SecondWindStudio/byz-agents}"
CHECK="${FT_CLOSE_DRAFT_CHECK:-$HERE/ft-issue-close-check.sh}"; WRAP="${FT_TANK_WRAPPER:-$HERE/ft-gh-as-tank.sh}"
CARD=""; ISSUE=""; POST=0; OUT=""; LOCKD=""
die() { echo "REJECT $2" >&2; exit "$1"; }
donly() { echo "DRAFT-ONLY $1"; exit 4; }
undecided() { echo "판정 불가 — $1"; exit 3; }
while [ $# -gt 0 ]; do case "$1" in
  --card) CARD="${2:-}"; shift 2;; --issue) ISSUE="${2:-}"; shift 2;; --out) OUT="${2:-}"; shift 2;; --post) POST=1; shift;;
  *) die 2 "usage: $0 --card <카드> [--issue <N>] [--post] [--out <초안>]";; esac; done
[ -f "$CARD" ] || die 2 "카드 파일 없음: ${CARD:-없음}"
case "${ISSUE:-0}" in *[!0-9]*) die 2 "--issue 는 숫자";; esac
TO="$(command -v timeout || command -v gtimeout)" || die 2 "timeout(coreutils) 필요 — 7초 룰"
command -v jq >/dev/null || die 2 "jq 필요"
realp() { python3 -I -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
clip() { jq -Rr --argjson n "$2" '.[0:$n]' <<<"$1"; }
card_lines() { awk '/^```/{f=!f; next} !f' "$CARD"; }   # 울타리 안 줄은 버린다
pick() { card_lines | grep -E "^- ($1):" | tail -1 | sed -E "s/^- ($1):[[:space:]]*//; s/[[:space:]]+\$//"; }   # 마지막 줄 하나 · 무효여도 앞 줄로 안 내려감
issue_json() { # → Issue 코멘트 JSON(stdout) · 조회 실패 rc≠0
  if [ -n "${FT_CLOSE_DRAFT_CHECK_JSON:-}" ]; then cat "$FT_CLOSE_DRAFT_CHECK_JSON"
  else "$TO" "${FT_GATE_TIMEOUT_S:-7}" gh issue view "$ISSUE" -R "$REPO" --json comments; fi; }
last_line_val() { # <키> <JSON> → «L:<값>»(그 키의 마지막 줄 · 없으면 빈 값)
  jq -r --arg k "$1" '[.comments[]?.body | split("\n")[] | select(test("^\\s*[-*]?\\s*" + $k + "\\s*[:：]"))] | last // empty
    | "L:" + (sub("^\\s*[-*]?\\s*" + $k + "\\s*[:：]\\s*"; "") | sub("\\s+$"; ""))' <<<"$2"; }

land_word() { # stdin 착지 값 → 첫 40hex 낱말 · 없으면 짧은 sha(7~39hex·숫자 포함)를 팩 리포에서 유일 해석+랜딩 ref 조상일 때만 40hex 로 펼침
  local words w o full root="${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}" ref="${FT_LAND_REF:-origin/main}"
  words="$(tr -cs 'A-Za-z0-9' '\n')"
  w="$(grep -E '^[0-9a-f]{40}$' <<<"$words" | head -1)"; [ -z "$w" ] || { echo "$w"; return 0; }
  for w in $(grep -E '^[0-9a-f]{7,39}$' <<<"$words" | grep '[0-9]'); do
    full=""; for o in $(git -C "$root" rev-parse --disambiguate="$w" 2>/dev/null); do
      [ "$(git -C "$root" cat-file -t "$o" 2>/dev/null)" = commit ] && full="$full $o"; done
    set -- $full; [ $# -eq 1 ] || continue
    git -C "$root" merge-base --is-ancestor "$1" "$ref" 2>/dev/null || continue
    echo "$1"; return 0
  done; return 0
}
vresolve() { # 판정문 경로 → 상대면 «카드가 든 워크트리 루트» 기준(호출 cwd 아님)
  local top; case "$1" in /*) echo "$1";; *) top="$(git -C "$(dirname "$CARD")" rev-parse --show-toplevel 2>/dev/null)" || top=.; echo "$top/$1";; esac; }
parse_card() { # 카드 필드 → 전역 · 못 채우면 DRAFT-ONLY(rc4)
  local n="$(basename "$CARD" .md)" ev line1 mv rx='(미실행|미확인|대기|HOLD|판정 불가)'
  CARDNO="$(sed -E 's/^(r[0-9]+[a-z]*)-.*/\1/' <<<"$n")"; [[ "$CARDNO" =~ ^r[0-9]+[a-z]*$ ]] || die 2 "카드 이름이 rNNNN-… 꼴 아님: $n"
  local ci="$(pick Issue | grep -oE '#[0-9]+' | head -1 | tr -d '#')"
  [ -n "$ci" ] || die 2 "카드에 «- Issue: #N» 줄 없음"
  [ -z "$ISSUE" ] && ISSUE="$ci"; [ "$ISSUE" = "$ci" ] || die 2 "Issue 번호 불일치 — --issue $ISSUE ≠ 카드 #$ci"
  [ "$(basename "$(dirname "$CARD")")" = 완성 ] || donly "완성 폴더 아님"
  LAND="$(pick 착지 | tr 'A-F' 'a-f' | land_word)"; [[ "$LAND" =~ ^[0-9a-f]{40}$ ]] || donly "착지 줄 없음 또는 40hex 아님(짧은 sha 는 유일·랜딩 조상일 때만)"
  EVT="$(pick 실사건)"; ev='(#[0-9]+|[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+)'
  { [[ "$EVT" =~ $ev ]] && ! [[ "$EVT" =~ $rx ]]; } || donly "실사건 줄 없음·무효(증거 토큰 없음 또는 미실행·대기)"
  CANON="$(card_lines | grep -E '^- (정본 영향 없음|정본):' | tail -1 | sed 's/^- //')"
  [[ "$CANON" =~ ^(정본 영향 없음|정본):[[:space:]]*[^[:space:]] ]] || donly "정본 줄 없음(기본 문구로 메우지 않음)"
  CAUSE="$(pick '원인 1줄')"; [ -n "$CAUSE" ] || donly "원인 1줄 없음"
  mv="$(card_lines | grep -oE '진행→완성 · DA [^[:space:]]+#§[0-9]+' | tail -1)"; [ -n "$mv" ] || donly "완성 이동(진행→완성 · DA …#§N) 줄 없음"
  VRAW="$(sed -E 's/^진행→완성 · DA //; s/#§[0-9]+$//' <<<"$mv")"; VPATH="$(vresolve "$VRAW")"; SEC="${mv##*#§}"
  line1="$(head -1 "$CARD")"; [[ "$line1" != *남김* && "$line1" != *보관* ]] || donly "머리에 남김 또는 보관 줄 — 사람 확인"
  HEADTXT="$(clip "$(sed -E 's/^.*끝:[[:space:]]*//; s/^# 인덱스:[[:space:]]*//' <<<"$line1")" 120)"
}
guard_out() { # --out 이 카드·판정문 실경로와 같으면 rc2 · 기본 = mktemp
  [ -n "$OUT" ] || { OUT="$(mktemp)"; return 0; }
  local o="$(realp "$OUT")"
  [ "$o" != "$(realp "$CARD")" ] && [ "$o" != "$(realp "$VPATH")" ] || die 2 "출력 = 입력 파일($OUT) — 카드·판정문은 덮어쓰지 않는다"
}
verdict_check() { # 판정문 «## §N — CLOSE rNNNN» 정확히 1개 · 둘째 줄 sha == 카드 착지 → PRN
  local h="## §${SEC} — CLOSE ${CARDNO}" cnt l2 rx='main\(팩\) `([0-9a-fA-F]{40})` / PR ([0-9]+)'
  [ -f "$VPATH" ] || die 1 "판정문 §$SEC 결정 불가 — 파일 없음: $VPATH"
  cnt="$(awk -v h="$h" 'index($0,h)==1 { r=substr($0,length(h)+1); if (r=="" || r ~ /^[ \t]/) c++ } END{print c+0}' "$VPATH")"
  [ "$cnt" = 1 ] || die 1 "판정문 §$SEC 결정 불가 — «${h}» 절 ${cnt}개(정확히 1개여야 함)"
  l2="$(awk -v h="$h" 'f{print; exit} index($0,h)==1{ r=substr($0,length(h)+1); if (r=="" || r ~ /^[ \t]/) f=1 }' "$VPATH")"
  [[ "$l2" =~ $rx ]] || die 1 "판정문 §$SEC 결정 불가 — 둘째 줄이 «main(팩) \`<40hex>\` / PR <번호>» 꼴 아님"
  [ "$(tr 'A-F' 'a-f' <<<"${BASH_REMATCH[1]}")" = "$LAND" ] || die 1 "착지 sha 불일치 — 카드 ${LAND:0:10} ≠ 판정문 §$SEC ${BASH_REMATCH[1]:0:10}"
  PRN="${BASH_REMATCH[2]}"
}
prior_verdict() { # 기존 Issue 코멘트의 마지막 «원인 확정»(N·빈칸) · «같은 증상 보류»(0 아님) → DRAFT-ONLY
  local ij cz hz
  ij="$(issue_json 2>&1)" || undecided "기존 Issue 코멘트 조회 실패: $(head -1 <<<"$ij")"
  cz="$(last_line_val '원인 확정' "$ij")"; hz="$(last_line_val '같은 증상 보류' "$ij")"
  if [ -n "$cz" ] && ! [[ "${cz#L:}" =~ ^[Yy]([[:space:]]|[—–-]|$) ]]; then donly "기존 미해결 판정(원인 확정 «${cz#L:}») — 덮어쓰지 않음"; fi
  if [ -n "$hz" ] && ! [[ "${hz#L:}" =~ ^0[[:space:]]*$ ]]; then donly "기존 미해결 판정(같은 증상 보류 «${hz#L:}») — 덮어쓰지 않음"; fi
}
build_draft() { # 8항 + 연결 줄 + token → $OUT · TOK
  local rel="${CARD#*/design/}"; [ "$rel" = "$CARD" ] || rel="design/$rel"
  { echo "닫는 사건: $HEADTXT — 팩 main 착지 · 라이브 설치"
    echo "PR: 팩 리포 PR $PRN → 팩 main $LAND ($CARDNO)"
    echo "재현 PASS: $EVT"
    echo "정리: 정리할 것 없음(나노 좌석 닫힘 · 카드 완성 이동)"
    echo "기록: 카드 $rel · 판정문 $VRAW#§$SEC"
    echo "$CANON"
    echo "원인 확정: Y — $(clip "$CAUSE" 200)"
    echo "같은 증상 보류: 0"
    echo "연결 PR: 팩 PR #$PRN · 착지 sha $LAND ($CARDNO · ai-feature-pack 쪽)"; } > "$OUT"
  TOK="$(shasum -a 256 < "$OUT" | cut -c1-12)"; echo "token=$TOK" >> "$OUT"
}
precheck() { # close-check 가 rc0 + 끝 줄 «PASS #N 완료 8항» 일 때만 통과(제안 마무리 PASS 는 거절)
  local a=("$ISSUE" --extra-comment "$OUT") o rc last
  [ -z "${FT_CLOSE_DRAFT_CHECK_JSON:-}" ] || a+=(--from-json "$FT_CLOSE_DRAFT_CHECK_JSON")
  [ -z "${FT_CLOSE_DRAFT_REPO:-}" ] || a+=(--repo "$FT_CLOSE_DRAFT_REPO")   # 시험 훅 — 정본 판정 리포
  o="$(GH_REPO="$REPO" bash "$CHECK" "${a[@]}" 2>&1)"; rc=$?; last="$(tail -1 <<<"$o")"
  { [ $rc -eq 0 ] && [[ "$last" == "PASS #$ISSUE 완료 8항"* ]]; } || die 1 "사전 검사 FAIL — $last (초안: $OUT)"
}
has_token() { # 정확 일치(줄 단위) token 이 Issue 코멘트에 있나 → 0 있음 · 1 없음 · 3 조회 실패
  local ij; ij="$(issue_json 2>/dev/null)" || return 3
  jq -e --arg t "token=$TOK" '[.comments[]?.body | split("\n")[] | sub("\\s+$"; "") | select(. == $t)] | length > 0' <<<"$ij" >/dev/null 2>&1
}
lock_issue() { # mkdir 잠금(macOS 에 flock 없음) · 못 잡으면 REJECT · 죽은 pid 면 치우고 1회 재시도
  local sd pid; if [ -n "${FT_CLOSE_DRAFT_STATE:-}" ]; then sd="$FT_CLOSE_DRAFT_STATE"
  else . "$HERE/ft-harness-root.sh" && sd="$(ft_data_root "$HERE")/state/issue-close-draft" || die 2 "상태 폴더를 못 풂"; fi
  mkdir -p "$sd" && LOCKD="$sd/$ISSUE.lock"
  mkdir "$LOCKD" 2>/dev/null || { pid="$(cat "$LOCKD/pid" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) die 1 "같은 Issue 게시 중(#$ISSUE · 잠금 $LOCKD)";; esac
    kill -0 "$pid" 2>/dev/null && die 1 "같은 Issue 게시 중(#$ISSUE · pid $pid)"
    rm -rf "$LOCKD"; mkdir "$LOCKD" 2>/dev/null || die 1 "같은 Issue 게시 중(#$ISSUE)"; }
  echo "$$" > "$LOCKD/pid"; trap 'rm -rf "$LOCKD"' EXIT
}
post() { # 게시 1회 · 재게시 0 — 실패하면 token 만 다시 본다
  local o rc t
  lock_issue; has_token; t=$?
  [ $t -ne 3 ] || undecided "token 조회 실패(게시 0)"
  [ $t -ne 0 ] || { echo "ALREADY #$ISSUE token=$TOK"; exit 0; }
  o="$(FT_ISSUE_REPO="$REPO" "$TO" 15 bash "$WRAP" comment "$ISSUE" "$OUT" --apply 2>&1)"; rc=$?
  if [ $rc -eq 0 ] && [[ "$o" =~ /issues/$ISSUE#issuecomment-[0-9]+ ]]; then echo "POSTED #$ISSUE token=$TOK url=$(grep -oE "[^ ]*/issues/$ISSUE#issuecomment-[0-9]+" <<<"$o" | tail -1)"; exit 0; fi
  has_token; t=$?
  [ $t -ne 3 ] || undecided "token 조회 실패(게시 결과 불명 · 재게시 0 · 수동 확인)"
  [ $t -ne 0 ] || { echo "POSTED #$ISSUE token=$TOK url=확인됨(래퍼 응답 불명 · token 재확인)"; exit 0; }
  undecided "게시 결과 불명(재게시 0 · 수동 확인) — 래퍼 rc=$rc: $(head -1 <<<"$o")"
}
parse_card; guard_out; verdict_check; prior_verdict; build_draft; precheck
[ $POST -eq 1 ] || { echo "DRAFT #$ISSUE token=$TOK file=$OUT"; exit 0; }
post
