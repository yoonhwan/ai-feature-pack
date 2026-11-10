#!/usr/bin/env bash
# ft-issue-card-audit.sh <--tick|--table|--mail <팀>> [--all-open] [--from-json <파일>] [--repo <dir>] [--ref-main <ref>] [--ref-harness <ref>]
#   approved 열린 Issue ↔ 팀 카드 대조 (읽기 전용 · gh 는 list 1회 · git 은 ls-tree+cat-file 1회씩 · 쓰기 0).
#   정본 = design/harness/PLAN-issue-card-audit-20261028.md §2 · 반례 §3 · 판정 파이썬 = _issue_card_audit.py.
#   --tick  한 줄  `ISSUE-CARD approved=<A> 카드없음=<N>[ #a #b #c #d #e][ +<나머지>] 언급만=<K> 닫기후보=<M>` (번호 = 큰 번호부터 5개)
#   --table 이슈마다 `#N · 제목 40자 · 상태(없음|언급만|연결) · 카드 칸(대기/진행/완성…) · 추천 팀 (근거)` (approved 기본 · --all-open 이면 열린 이슈 전부)
#   --mail <팀>  그 팀 몫 «카드 없음» Issue 로 쪽지 본문 — 출력만 · 발송 0 (보내는 것은 planner)
#   입력 = 이슈 gh issue list(7초 + 재시도 1) · 카드 ref 2개(origin/main · origin/ops/main-base)를 ls-tree + cat-file --batch 로 1회씩.
#   번호 규칙 «한 곳» = #N(?![0-9]) (#12 는 #123 에 걸리지 않는다 · R4). 연결/언급/없음 = 카드 머리 «- Issue:» 줄 / 본문 어디든 / 둘 다 0.
#   실패 = 호출마다 7초 상한 + 재시도 1 · 하나라도 2회 실패·시간 초과 = `ISSUE-CARD 판정 불가 — <원인>` rc5 1줄 · 부분 결과 0 (하드 룰 12·20 · R6·R9).
#   추천 팀 = team:* 라벨 → 별칭 data(team_aliases.json) → 제목 머리 [xxx] → planner (§2-2 · R8).
#   exit 0 = 출력 완료 · 2 = usage · 5 = 판정 불가. 시험 = tests/test_issue_card_audit.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; exec python3 "$DIR/_issue_card_audit.py" "$@"
