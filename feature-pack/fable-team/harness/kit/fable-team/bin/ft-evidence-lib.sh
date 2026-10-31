#!/usr/bin/env sh
# ft-evidence-lib.sh — r449 «증거 로그» 판정식 한 곳 (source 전용 · POSIX sh/bash 공용 · 외부 호출 0)
#   쓰는 곳 3: .fable-team/githooks/pre-commit(index 단계) · ft-merge-land.sh(착지 가지 diff) · ft-evidence-untrack.sh(이미 tracked 인 것 빼기)
#   증거 로그 = design/ 아래 ①이름 끝 .log·.out·.nohup·.stdout·.stderr·.pid ②이름에 guard·poller 가 들고 끝이 .jsonl·.jsonl.gz·.txt
#   (md·json·py·sh 는 이름에 guard·poller 가 있어도 아님 — 요약 SUMMARY-*.md · 설계 문서 · 도구는 tracked 로 남는다)
#   .gitignore(BYZ) 의 design/** 줄과 같은 집합이다 — 판정식을 바꾸면 .gitignore 줄도 같이 바꾼다.
FT_EVIDENCE_RX='^design/(.*/)?([^/]*\.(log|out|nohup|stdout|stderr|pid)|[^/]*(guard|poller)[^/]*\.(jsonl(\.gz)?|txt))$'
ft_evidence_log_path() { printf '%s\n' "$1" | grep -Eq "$FT_EVIDENCE_RX"; }   # ft_evidence_log_path <리포 기준 경로> → rc0 = 증거 로그
ft_evidence_filter() { grep -E "$FT_EVIDENCE_RX"; }                          # stdin 경로 줄 → 증거 로그 줄만 (0줄이면 rc1)
