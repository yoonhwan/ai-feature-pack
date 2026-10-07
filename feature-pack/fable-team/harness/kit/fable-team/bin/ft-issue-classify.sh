#!/usr/bin/env bash
# ft-issue-classify.sh [--from-json <파일>] — Issue 작성 경로 4종 분류 + 처리 분기 + 발견 지연 (C16 · 읽기 전용)
#
# 왜 있나: GitHub 작성자는 전부 한 계정이라 login 으로는 오빠·좌석·사내 멤버를 못 가른다(SPEC-github-issue-driven §1 1-3).
#   그래서 «폼 마커·라벨»로만 가른다 — login·author 는 읽지 않는다. 쓰기(gh/mbox) 0.
#
# 작성 경로 판정(위에서 아래로 첫 일치 · 근거 열에 그대로 출력):
#   ② 세션 에이전트  본문 마커 「ft-origin: seat」(ft-issue-create-pair.sh 가 찍는다)
#   ① 기획 세션      본문 마커 「ft-origin: planner-session」 · planner_task 칸 「골좌표 + 닫는 증거」(제목 줄) · BOARD 행 표 「| 골좌표 |」(실측: 열린 Issue 70건이 이 두 모양)
#   ④ 사내 멤버      라벨 from:member
#   ③ 오빠 GitHub    live_bug 폼 칸 「발생 위치 넷 가르기」
#   미분류           위에 없음 (마커 없는 Issue — 근거 열 「마커 없음」)
# 처리 분기: 라벨 6 계열(type·status·team·scope·phase·priority) 중 빠진 것이 있을 때만
#   ③④ = 보완(매니저가 붙임) · ② = 반려(좌석이 보정) · ① = 그대로(planner 값 뒤 매니저가 완성) · 미분류 = 그대로. 빠진 게 없으면 전부 그대로.
# 발견 지연: Issue 생성 → 매니저 첫 코멘트(본문 첫 줄 「[issue-manager]」 또는 마커 「ft-issue-manager」). 없으면 「미발견 · 나이」.
# 시험용: FT_NOW=<epoch초> 로 «지금» 고정.   exit 0 = 출력 완료 · 2 = usage/조회 실패
set -uo pipefail
unset GH_TOKEN
FROM_JSON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from-json) FROM_JSON="${2:-}"; shift 2;;
    *) echo "usage: $0 [--from-json <파일>]" >&2; exit 2;;
  esac
done
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }

if [ -n "$FROM_JSON" ]; then
  [ -f "$FROM_JSON" ] || { echo "json 없음: $FROM_JSON" >&2; exit 2; }
  JSON="$(cat "$FROM_JSON")"
else
  JSON="$(gh issue list --state open --limit 500 --json number,title,labels,createdAt,body,comments 2>&1)" \
    || { echo "gh issue list 실패: $JSON" >&2; exit 2; }
fi
jq -e 'if type=="array" then . else error("배열 아님") end' >/dev/null 2>&1 <<<"$JSON" \
  || { echo "입력 JSON 이 Issue 배열이 아니다" >&2; exit 2; }
NOW="${FT_NOW:-$(date +%s)}"

jq -r --argjson now "$NOW" '
  def ts: sub("\\.[0-9]+Z$";"Z") | fromdateiso8601;
  def dur($s): ($s/86400|floor) as $d | (($s%86400)/3600|floor) as $h
    | (if $d>0 then "\($d)일" else "" end) + "\($h)시간";
  def origin($l; $b):
    if   ($b|test("ft-origin:\\s*seat"))            then ["② 세션 에이전트", "본문 마커 ft-origin: seat"]
    elif ($b|test("ft-origin:\\s*planner-session")) then ["① 기획 세션", "본문 마커 ft-origin: planner-session"]
    elif ($b|test("골좌표 \\+ 닫는 증거"))            then ["① 기획 세션", "planner_task 칸 골좌표 + 닫는 증거"]
    elif ($b|test("(^|\\n)\\|\\s*골좌표\\s*\\|"))     then ["① 기획 세션", "BOARD 행 표 골좌표"]
    elif ($l|index("from:member"))                  then ["④ 사내 멤버", "라벨 from:member"]
    elif ($b|test("발생 위치 넷 가르기"))              then ["③ 오빠 GitHub", "live_bug 폼 칸 발생 위치 넷 가르기"]
    else ["미분류", "마커 없음"] end;
  def missing($l): ["type","status","team","scope","phase","priority"]
    | map(select(. as $f | ($l | map(startswith($f + ":")) | any) | not));
  def branch($p; $m): if ($m|length)==0 then "그대로"
    elif ($p|startswith("③")) or ($p|startswith("④")) then "보완"
    elif ($p|startswith("②")) then "반려" else "그대로" end;
  def mgr: [.comments[]? | select(.body|test("^\\s*\\[issue-manager\\]|ft-issue-manager"))] | sort_by(.createdAt) | first;
  [ .[] | . as $i | ([.labels[]?.name]) as $l | (.body // "") as $b
    | origin($l; $b) as $o | missing($l) as $m
    | ($i|mgr) as $c
    | { n: .number, p: $o[0], why: $o[1], miss: $m, br: branch($o[0]; $m),
        found: ($c != null),
        delay: (if $c then "발견 +" + dur(($c.createdAt|ts) - (.createdAt|ts))
                else "미발견 · 나이 " + dur($now - (.createdAt|ts)) end),
        t: (.title|gsub("[\\n\\r]";" ")|.[0:50]) } ] as $rows
  | "번호 | 작성 경로 | 처리 분기 | 발견 지연 | 판단 근거 | 빠진 라벨 계열 | 제목",
    ($rows[] | "#\(.n) | \(.p) | \(.br) | \(.delay) | \(.why) | \(.miss|join(",")) | \(.t)"),
    ("SUMMARY total=\($rows|length)"
     + " ①=\([$rows[]|select(.p|startswith("①"))]|length)"
     + " ②=\([$rows[]|select(.p|startswith("②"))]|length)"
     + " ③=\([$rows[]|select(.p|startswith("③"))]|length)"
     + " ④=\([$rows[]|select(.p|startswith("④"))]|length)"
     + " 미분류=\([$rows[]|select(.p=="미분류")]|length)"
     + " 보완=\([$rows[]|select(.br=="보완")]|length)"
     + " 반려=\([$rows[]|select(.br=="반려")]|length)"
     + " 그대로=\([$rows[]|select(.br=="그대로")]|length)"
     + " 미발견=\([$rows[]|select(.found|not)]|length)")
' <<<"$JSON"
