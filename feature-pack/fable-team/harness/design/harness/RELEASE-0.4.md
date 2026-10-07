# RELEASE 0.4 — 10-07 하네스 묶음 + 라이브 도구 폴더를 main 키트와 1:1 로 (2026-10-07 · 축 C)

골 축: C 「업그레이드하고 레포에 커밋 푸시 … 배포 발행 수신해 반영」 · 닫는 증거 = 이 1장 + 머신별 「반영됨」 행. 구현 판정 = design/harness/OPS-VERDICTS-20261006.md §20~§38 · 라이브 1:1 = Issue 816(트리아지 안 = design/harness/PLAN-release-0.4-and-816-20261007.md).

## 변경 (0.3 이후 main 랜딩분 · 하네스 범위)
| # | 변경 | 근거 | sha |
|---|---|---|---|
| 1 | Tank 봇 점검 스크립트 + 개선요청 원장 | PR #832 | 2b4d82b9be |
| 2 | ft-harness-info.sh 하네스 조회 + 부팅 안내 | PR #837 | f02307ea7a |
| 3 | gh 쓰기를 Tank 이름으로 — ft-gh-as-tank.sh + gh-issue-author-guard 훅 | PR #840·#841 | 78d6fee611 |
| 4 | master 좌석 게이트 판별 + gh 가드 main 보호·리포 범위 + 래퍼 pr-create | PR #843 | a1b0242ce9 |
| 5 | 키트 bin 단일 원본화 + install 홈 훅 확인 줄 | PR #845 | bc87df1302 |
| 6 | 나노 spawn·close 팀 env 자동 로드 + role-spawn 기본 접두 | PR #846 | 5663d3f9ce |
| 7 | Tank Issue edit · nano-close 명시 모드 · role-spawn 크론 고정(R13) | 하네스 운영 묶음 | 81c9f3c684 |
| 8 | pytest .env 격리(#855) + ft-index-lint 사전검증·조사 근거(R16) | PR #864 | c0f85616b4 |
| 9 | ft-nano-close 워크트리 접두 FT_NANO_WT_PREFIX | PR #867 | e16d52a871 |
| 10 | 키트 동기 — press 게이트 ⑥ 기준선 + baseline-check | PR #869 | b56365e381 |
| 11 | press 게이트 ⑦ 역할 · ⑧ 직전 BTS 표 · 허가 파일(R15 H) + 게이트 훅 TOP_MODELS 정합 + role-spawn 고스트 줄(R21) + 나노 닫기 원격 feat ref(R22) | PR #874 | 1840d5e9f6 |
| 12 | gh 가드 PR 쓰기 5종 차단 + 래퍼 pr-edit·pr-close (R6 ②) | PR #876 | 16201f18ea |
| 13 | 홈 문서: 전역 CLAUDE.md 하드 룰 10 · BOOT 17 · codex 동기 블록 · 승계 6단계(R21 고스트 서제스천) | 홈 설치(cp+cmp) | — |
| 14 | 라이브 도구 폴더(`.worktrees/v6-realtime-live/.fable-team/bin`)를 main 키트와 1:1 — Issue 816 범위 축소(⓪ 채택 단계 생략: 라이브만의 변경 0 실측 · tar 백업 뒤 덮어쓰기 1회) | Issue #816 · 오빠 승인(planner #60527 · issues #60531) | 키트 = 16201f18ea |

효과: Issue·PR 에 남는 글은 Tank 봇 이름으로만 나간다. press 는 tester·checker 좌석이 직전 회차 4자 표를 채운 뒤에만 허가된다. 나노 닫기는 팀 env 를 좌석 이름으로 찾고, 원격 main 을 기준으로 대조할 수 있다. 다른 좌석 화면의 자동완성 줄을 사람 입력으로 읽지 않는다. 이 Mac 의 나노 열기·닫기·틱이 main 키트와 같은 도구로 돈다(옛판 5개 해소).

## 설치 명령 (머신별)
이 Mac 은 «라이브 도구 폴더 1:1»(아래 집행 순서)이 본체다. 다른 머신은 키트 설치만:
1. `git pull origin main`
2. `bash scripts/harness-install/fable-team/install.sh --machine <머신> --apply`
3. 확인: 부팅 보고의 `machine=<머신>` · `kit_sha=<sha12>` 가 이 RELEASE 의 값과 같은가(집행 때 기입).

## 시험 (로컬 검증 · 집행 때 채움)
- main 16201f18ea 키트를 빈 HOME 에 `install.sh --apply` → rc · files · kit_sha
- `tests/harness/test_*.sh` 전부 rc=0
- 라이브 1:1 뒤 `diff -rq <키트 bin> <라이브 bin>`(.bak*·__pycache__ 제외) = 0줄

## 머신별 반영
값을 모르면 «미확인». 「반영됨」 행은 그 머신의 부팅 보고 값이 있을 때만 쓴다.

| 머신 | 상태 | sha |
|---|---|---|
| 이 Mac | 반영됨 10-07 23:2x — 키트 bin 73파일 → 라이브 v6-realtime-live/.fable-team/bin 덮어쓰기 · diff -rq 키트↔라이브 0줄 · bash -n 전부 OK · press 게이트 SELFTEST OK · 되돌림 tar = .fable-team/state/live-bin-pre-0.4-1007.tar (슬랙 게시 10-08 01:1x — mbox 미러 #60815 · 스레드 ts 1791389359.569739 · 요약기 실패로 첫 문장만 게시됨) | 키트 소스 1a577c3aa7 (origin/main · PR 882 R15 T 포함 · 라이브 drift-check OK · 이전 a3532619ba (PR 878 드리프트 검사 포함 · 10-08 재실측 diff -rq 키트↔라이브 실파일 0줄 · 이전 51beb7be05) |
| jarvis | 미확인 | |
| byzs-mac-mini | 반영됨 10-08 — ssh byz@100.71.41.107(키) · 키트 git archive origin/main → ~/.fable-team/harness 104파일 · 원격 diff -rq 키트↔설치 bin 0줄 · bash -n 87(원격 bin 72 + templates 15 는 동일 바이트로 이 Mac /bin/bash 3.2.57 에서 -n OK · arch#8 #60805) · 백업 없음(신규 디렉터리 — 이전에 없었음) · 되돌림 = 원격 ~/.fable-team 과 ~/.fable-team-kit-0.4-tmp 삭제(HIL) · 주의: 원격 bash 3.2 런타임이라 좌석 운용 전 env bash 스크립트 52개 호환 시험 별건 · tmux 없음 | 키트 소스 1a577c3aa7 (kit_sha=38d57db630ea · files=104) |

## 이 릴리스에 안 넣은 것 (다음으로)
| 무엇 | 언제 | 근거 |
|---|---|---|
| 드리프트 검사(키트 ↔ 라이브 cmp · tick 경고 · 나노 spawn/close 입구 BLOCK) — Issue 816 ②③ | 0.5 · 완성 전 | 카드 design/harness/indices/대기/live-bin-drift-check.md(교체 뒤 spawn) |
| FT_BIN 을 `~/.fable-team/<팀>/bin`(install.sh DEST)으로 이전 — Issue 816 ⑤ | 완성 후 · 단 v6-realtime-live 워크트리 정리보다 «먼저» | PLAN-release-0.4-and-816-20261007.md 「완성 전/후」 |
