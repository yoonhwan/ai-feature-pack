# ai-feature-pack 작업 인덱스 (2026-10-20 · 기준 origin/main `6231d988` = PR #151 Pi parity · 이전 `ccfa775d` = PR #148 · 작성 시점 `0b9e3618`=PR #145)

> 골(원문): 「팀 구성·작업 우선순위를 팀장이 알아서 판단」의 입력 = 이 저장소의 작업 인덱스(무엇이 열려 있고 무엇이 막혔는지)
> 닫는 증거 = 인덱스 파일 경로 + 우선순위 1~3 + 근거 sha/PR 번호
> 작성: aifp-worker-master-claude#0 · 모든 칸은 `git`/`gh` 실측(2026-10-20 10:5x)

## 우선순위 1~3

| # | 일 | 근거 | 막힌 곳 |
|---|---|---|---|
| 1 | ✅ **PR #146 tmm 0.8.5 머지 완료**(`42e513d0`) · ✅ PR #148 tmm 0.9.0 머지 완료(`ccfa775d`) — 이전 판단: | PR #146 `feat/tmm-0.8.5-land` · `feature-pack/tmm/test/verify.sh` rc=0 · 최신 origin/main 위 cherry-pick 충돌 0 | 오빠 결정(#2918 ①): 머지 = **승인**. 단 이 세션의 `gh pr merge` 는 병합 가드(R176)가 막는다(이 리포는 LIVE_ROOT 없음) → 오빠가 직접 머지하거나 가드 설치 판단 필요. 후속: tmm 0.8.6·0.9.0 이 PR #148 로 위에 쌓임(base = #146 가지) |
| 2 | **미착지 로컬 전용 가지 2개 착지** — `nano/r522-resource-watch-…` (1.1.80 · 3커밋) · `nano/r524-seat-resume-via-headroom-wrapper` (1.1.82 · 6커밋) | main 에 r522·r524 커밋 0건 · origin 에 가지 없음(로컬에만 있음) · 지금 팩은 1.1.85 라 재번호 필요 | ★주인 나노 좌석이 살아 있다★ — tmux `byz-harness-nano-r522-…#0`·`byz-harness-nano-r524-…#0` 가동 중(2026-10-20 실측) → 진행 중인 작업이라 «미착지»가 정상 · 오빠 결정(#2918 ③): 하네스 팀에 먼저 묻기, 이어받기 0 |
| 3 | ~~main 작업 트리의 미커밋 변경 출처 확인~~ → **오빠 본인 작업으로 확정**(2026-10-20 오빠 결정 · tmm-3 세션) — `agent-cli`·`tmm`·`tmuxc` 미커밋 변경은 읽기·커밋·되돌리기 일절 0 | 오빠 인터뷰 결정(쪽지 #2918 ④) | 해당 없음 — 다음 우선순위로 진행 |

## ① 열린 PR (1건)
- #146 `[fix] tmm 0.8.5 — 업그레이드 뒤 좀비 피커 정리 (@tmm_ver)` · 2026-10-20T01:45Z · 비초안 · 머지 대기
- 이미 머지된 PR 140건(최근 #145 r529 · #144 r530 · #143 r528 · #142 r525 · #141 r523 · #140 r516).

## ② 가지 현황 (origin/main 에 «미착지로 보이는» 가지의 실제 분류)
squash 머지라 `--no-merged` 가 착지된 가지를 미착지로 셉니다 → PR 번호 대조로 가름.
- **origin 21개 중**: 착지됨(머지 PR 있음) 14 — cairn 8(#6~14) · daily-trend 4(#27·29·30·36) · ft 2(#25·26) / 실제 열림 7 — `cfo/ft-root-and-mbox-fixes`(08-25) · `feat/baton-fanout-tracking`(05-25) · `feature/ai-feature-pack-pdf-reader`(03-25) · `wip/ft-version-0923-uncommitted`(10-03) · `nano/r407-freeze-gate-merge-head-blob-exclude`(+`-r2`) · `nano/r408-planner-quiet-…` · `feat/tmm-0.8.5-land`(#146)
- **로컬 36개 중 nano 20개**: 18개는 PR 로 착지됨(r408 #81 · r412 #71 · r413 #72 · r414 #70 · r416 #73 · r447 #77 · r448 #79 · r449 #80 · r450 #78 · r451 #82 · r426~r430·r437·r455a 는 묶음 PR #83/r464/r465 로 main 커밋에 흡수) / **미착지 2 = r522 · r524**(위 우선순위 2)
- 로컬 비-nano: `feat/*` 8 · `feature/*` 4 · `backup/*` 2(오늘 보존분 — 지우지 않음) · `wip/ft-version-0923-uncommitted` · `cfo/afp-integrate` · `fix/tmuxc-color` · `harness/r385-rest` — 오래된 가지, 착지 여부는 위 «착지됨» 대조에 없는 것만 후속 확인
- 브랜치 삭제·refs/archive 이동 판단은 전부 오빠 몫(삭제 HIL · 이동만 판정 2354 표준승인 — 착지·완성·닫힘 셋 다 참일 때)

## ③ 팩별 버전·최근 변경
| 팩 | 버전 | 마지막 변경 |
|---|---|---|
| fable-team | 1.1.86 | 2026-10-20 `5fb4b134`(r535 · 하네스 직렬: 1.1.87 r522 → … → 1.1.91 r524 예정) — 하루 1~3건 착지, 가장 활발 |
| tmm | 0.9.0 (0.8.5 #146 · 0.8.6 세션수 · 0.9.0 프로젝트→팀 트리 #148) | 2026-10-20 `ccfa775d` · 폰 실측·설치 대기 |
| tmuxc | 0.4.1 | 2026-10-19 `c84c6dd4`(r476) |
| baton | 1.2.17 | 2026-10-19 `ab4a9f20`(r443) |
| headroom | – | 2026-09-29 `85af1878` |
| daily-trend-viewer | – | 2026-07-19 `3ef4956f` |
| agent-cli | – | 2026-08-17 `e5c638ba` |
| cairn · auto · cliproxyapi · memory-system | – | 2026-07-08 / 07-08 / 06-30 / 03-15 (정지) |
- 팩 18개+(agent-browser·agent-cli·agent-surface-audit·agent-surface-sync·auto·baton·cairn·camfit·cartier-auto·cliproxyapi·daily-trend-viewer·fable-team·headroom·imsg·mcp-manager·memory-system·nanoclaw·notebooklm·obsidian-cli·termaid·tmm·tmuxc·tts-say·yt-transcribe)

## ④ 워크트리 현황 — 140개 (prunable 2)
- 리포 안 `.worktrees/` 122개 · 6.1G · 대부분 `nano/r4xx`·`master-r4xx-r2` 착지된 가지의 잔재. 디스크 여유 241Gi(여유 충분).
- `/private/tmp/claude-501/…/scratchpad/afp-*` 17개는 BYZ 하네스 좌석 소유 → 건드리지 않음. prunable 2 = `afp-merge`(cfo/afp-integrate)·`afp-081`.
- 내 소유: `.worktrees/aifp-work-index`(이 문서) · `.worktrees/tmm-085-land` · `.worktrees/wip-r386-save`.
- 정리 후보(삭제는 HIL): 착지 완료된 `.worktrees/nano-r4*`·`master-r4*` · `.worktrees/tmm-085-land`(PR #146 머지 뒤) · `.worktrees/wip-r386-save` · untracked `feature-pack/fable-team/skill/scripts/*.bak-r386` 3개.

## ⑤ 미해결 백로그 대조
- `.fable-team/state/ft-update-backlog.md` = 2026-07-03 자료. 항목 1(codex `--json`)·2(ft-checker 회신)·3(`exec resume -C`)·4(드라이버 실행 승인)·6(`/bin/bash` 3.2 훅 시험)은 FT 1.1.x 에서 대체·재작성됐을 가능성이 크다 — **현재 유효 여부는 미대조**(추정). 대조는 fable-team `CHANGES.md` 와 항목별 grep 로 별 단위.
- 정본 요청 원장은 BYZ 하네스 쪽(`ft-harness-info.sh requests`) — 이 리포는 «공용 정본» 이라 팀장이 따로 새 원장을 만들지 않는다.

## 이 리포의 운영 함정
- 같은 파일을 건드리면 충돌 — 착지 전 항상 최신 origin/main 위에서. 로컬 main 직접 커밋 금지(`.worktrees/<브랜치>`).
- 파괴(브랜치 삭제·force push·kill)는 HIL.

## 갱신 (2026-10-20 저녁)
- ✅ PR #146(tmm 0.8.5) · #148(tmm 0.9.0) · #151(Pi parity: agent-cli 2.2.0 · tmuxc 0.4.2 · tmm 0.9.1) 머지 · main `6231d988` · tmm 0.9.1 설치 완료(오빠 `! bash /tmp/h9002`)
- ✅ main 작업 트리 미커밋 23파일 정리(오빠 `! bash /tmp/h9003`) — 전부 origin/main 에 흡수·대체 확인 · 백업 `/tmp/main-dirty-20261020.patch` · 로컬 main = origin/main · `.bak-r386` 3개 삭제(main 과 동일)
- 하네스 직렬 대기: r534(1.1.88, PR #150) · r536(1.1.89, PR #152) · … · r540(pi 꼬리 허용)·r542(나노워커 pi 전환) 1.1.92 이후 — 속도 측정(pi 3.5~7배 빠름 · opencode 무료 경로 이 IP 차단) 전달 완료
- 좌석: aifp-pi-master#1(pi · 읽기 전용 · `.worktrees/pi-parity`) · 이름 lint 는 r540 대기
- 정정: 속도 측정이 main 트리 루트에 `count_files.sh` 를 만들었던 것(제 실수) 삭제함 — 측정은 임시 폴더에서 돌릴 것

## 갱신 (pi 팀장 교대 · 2026-10-20)
- r540(pi 꼬리 허용)이 PR #155 로 머지(`86bd129e` · fable-team 1.1.92 · `AGENTS="claude codex opencode cmd pi"`). `aifp-pi-master-pi#0` 이름 검사 PASS(main 판) — 하네스 설치 반영은 하네스 몫.
- 새 pi 팀장 `aifp-pi-master-pi#0` = pi · cwd `~/Project/pi-agent-ops/.worktrees/pi-master`(브랜치 pi/master · pi 프로젝트 git init `ccf8605`). 증류 도구가 pi 를 아직 못 받아 «열기→기동 확인→검증 송신»을 같은 순서로 직접 집행(인계 쪽지 seq=2928 도달 = 화면 `Steering` 관측). 도달 파일·부팅 보고는 미수신.
- 옛 pi 세션 `aifp-pi-master#1` 닫음(오빠 지시 «구형은 닫고»). 이 리포엔 좌석 명부가 없어 ft-seat-close/retire 가 거절 → `tmux kill-session` 로 닫음. 재개: `pi --name 'aifp-pi-master#1' --session 634e8250-2ff8-4a62-ad6d-0e59734a78a6` (cwd `.worktrees/pi-parity` · 기록 `~/.pi/agent/sessions/--Users-yoonhwan-Project-ai-feature-pack-.worktrees-pi-parity--/…634e8250….jsonl`).
- 남은 정리 후보(삭제는 HIL): `.worktrees/pi-parity`(브랜치 feat/pi-parity-1.3.0 은 PR #151 로 머지됨).
