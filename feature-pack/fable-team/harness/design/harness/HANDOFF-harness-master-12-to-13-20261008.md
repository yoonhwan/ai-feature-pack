# HANDOFF — byz-harness-master-claude#12 → #13 (2026-10-08 · ctx 400k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: C(업그레이드·커밋·push·배포 발행·반영) + 6-b(개선요청 접수·협의) + 원문 5(머신 독립 배분) + 원문 7(쪼개 동시에).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#8)에 mbox 보고 → 같은 턴에 CronCreate 10분 틱(보고에 cron=job id) — 없으면 착수 0.★ BOOT 17조항(~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md) 먼저. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표.

## 지금 상태 (한 줄)
★아침 매거진 단위 진행 중(Issue #885)★ — 본체 병합(PR 886 · main cc9998ca0c) · 후속 PR 888 CI 중 · 풀디테일+eli5 나노 2석 구현 중 · 제안서 흐름 도구 나노 검증 통과·arch §47 대기.

## 이번 세션(#12)에 끝낸 것
- 승계 수령·cron 3f288bc1(후계는 새로 건다, 내 크론 CronDelete 하고 닫음).
- 오빠 결정 3건(판정 342~344): mac-mini bash=이미 homebrew 5.3.15 있음(설치 0) · 홈 훅 정본 지정만 · ~/.tmm 0.7.5 설치+current 전환(되돌림 ln -sfn ~/.tmm/versions/0.7.4 ~/.tmm/current).
- PR 884(브리핑 문서) 병합 main 6a39c2be29. CFO 나노 pr3b#1 kill(판정 346 한 건 한정).
- 아침 매거진: 설계(DESIGN-morning-magazine-20261008.md)+DA APPROVE → 나노 collect·publish·hil-pending 모두 닫힘(§43·§44·§45) → 수동 1회 실 슬랙 발행(ts 1791417434.528749 · PDF 첨부) → launchd com.byz.ft-magazine 매일 08:00 등록(다음 발사 10-09 08:00) → PR 886 병합.
- 제안서 흐름(판정 352): 설계+DA → proposal-docs 닫힘(§46) · proposal-tools 구현 검증 통과(nano/proposal-tools 002ae4dbf0+bf06faa21a, §47 대기).
- 명부: seats-cfo.json CFO #56 승계 · seats-harness.json _hil_route=planner#8 · arch #8→#9→#10 계보 · 나노 index 경로 치환.

## 열린 일 (순서)
1. **PR 888**(fix/harness-magazine-followup · 18파일 · 문구 보정 §45+제안서 정본 §46): CI 대기. 백그라운드 감시 루프(`/tmp/pr888-merge.log`, `seq 1 150` 프로세스)가 초록이면 자동 squash. 안 돌면 `gh pr checks 888` → 초록이면 `gh pr merge 888 --squash`. ★병합 뒤★ `BYZ_ROOT=<루트> bash scripts/harness-install/slack-mirror/install-magazine.sh`(--load 없이, 복사만)로 내일 08:00 호 반영.
2. **제안서 도구**: ★arch#10 재현에서 반송 r1 1건(머리에 「- 상태:」 줄 2개면 폐기 제안서가 등록됨 — ft-proposal-register.sh:27 · byz_proposal_publish.py:59) → tools#0 에 전달함(seq 로 확인), 고친 sha 오면 독립 검증 → arch §47★. arch#10 이 §47 초안(.fable-team/state/drafts-r21/OPS-VERDICT-47.md)을 주면 → 판정서 append → `ft-index-move 진행/proposal-tools.md 완성 --da …#§47`(카드에 「정본 영향 없음」 줄 필요 — arch 가 씀) → seats-harness.json index 치환 → 커밋 → `git cherry-pick 002ae4dbf0 bf06faa21a` → 나노 닫기 → #888 병합 뒤 도구 PR(ft-gh-as-tank pr-create --apply) → 병합 뒤 홈 governance 복사(`cp` + `.bak-1008-proposal`, 원본 diff=④행+인용 줄뿐 확인) + install-magazine.sh 재실행.
3. **매거진 풀디테일 PDF + eli5 HTML**(판정 354 · 설계 DESIGN-magazine-full-detail-20261008.md): 나노 ①magazine-detail-collect#0(Sonnet) · ③magazine-eli5-html#0(codex gpt-6.1-sol high) 구현 중 → 각 완료 보고 → master 독립 검증 → arch §48·§49 → cherry-pick → 닫기. ②magazine-full-render-publish 카드는 대기/ — proposal-tools 랜딩 뒤 spawn(upload_file 필요 · DA 조건: set_phase(magazine_publish.py:57)가 files·revs 를 지움 → 보존). 오늘 수동 1회 재발행 `--reattach r1`(새 뿌리 글 0, push 0) 결과(PDF·HTML 경로·페이지 수·슬랙 ts)를 planner 에 1줄 → 내일 08:00 호 적용.
3b. **★새 발주 미착수(판정 357 · planner#8 seq 61180, 전문 /tmp/mbox/20261008T092926-byz-planner-master-claude#8-to-byz-harness-master-claude#12-planner-357-proposal-upgrade.md)★** 제안서 흐름 업그레이드(다음 제안서부터): ①승인 제안서 풀 컨텍스트를 Issue 본문에 등록 ②제안서도 풀 md + eli5 HTML 세트 ③템플릿에 실험·예측 시뮬 절. 절차 = arch#10 에 DESIGN r2 발주(골 3줄+축 1줄) → DA → 나노 → 랜딩. 접수 회신을 planner 에 1줄 먼저.
4. 보류: 카드 대기/gate-hook-kit-equals-home.md(판정 345 — #717 진단·PR 884 뒤 ⓪ 차단 재검토 때). 커밋하지 말 것(미추적 유지).
5. 후속 후보(기록만): 요약 프롬프트 금지(번호·영어 약어)를 모델이 일부 어김 — 오빠가 원하면 1줄 · ops-magazine 워크트리 생성 시 beads(bd) post-checkout 훅 스택트레이스(워크트리는 정상 생성) · seats-feature/issues.json _hil_route 가 아직 #7.

## 운영 규칙 (BOOT 15·17 · governance §6·§7)
- master 손 = 집행(랜딩·커밋·push·좌석 개설/닫기·명부·원장·검증 파일 cp). 코드·시안·카드 증거 줄 직접 편집 0. 카드 «정본 영향 없음»/증거 줄은 arch.
- 흐름: 발주(골 3줄+축 1줄, 긴 본문은 Write 후 `mbox relay`) → arch 설계 → DA → 나노(`. <루트>/.fable-team/bin-harness/harness-env.sh; export FT_NANO_FEAT=ops/main-base`; `zsh -lc "bash scripts/harness-install/fable-team/bin/ft-nano-spawn.sh design/harness/indices/대기/X.md --model 'claude-sonnet-5-5[1m]'"`, 시각은 `--agent codex --model gpt-6.1-sol --effort high`) → master 독립 검증(.venv/bin/python -m pytest · ruff · 200줄) → arch 재현·§N → 판정서 append → ft-index-move → cherry-pick → 닫기(유휴 3분 필요, REJECT 면 잠시 뒤 재시도).
- 랜딩: origin/main 위에 «내 파일만» 트리 구성(`GIT_INDEX_FILE` 임시 인덱스 + `git commit-tree`) → 브랜치 push → `bash scripts/fable-team-bin/ft-gh-as-tank.sh pr-create "제목" 본문파일 --base main --head <브랜치> --apply` → CI 초록 → squash. gate-hook 카드는 절대 포함 금지(`git add` 는 파일 단위로).
- 발신 한도 5건/60초(초과 시 BLOCKED RATE_LIMIT — 강제 금지). 메시지 본문에 프로세스 종료 명령어 글자 금지(훅 오탐 → hil-falsepos.log 기록 후 본문 수정).
- 막힌 명령·사람 승인 = planner [HIL]. 나노 닫기 외 tmux kill-session·삭제·원격 쓰기는 승인 없이 0.
- 이슈는 issues master(지금 byz-issues-master-claude#3)로: 증거는 값으로 같은 턴에.

## 함정 (실측)
- `git add design/harness/indices/` 는 보류 카드(gate-hook)까지 쓸어 담는다 → 파일 단위 add.
- `ft-index-move` 는 정본 게이트(「정본 영향 없음: <이유≥10자>」 줄)로 REJECT 할 수 있다 — 명부 index 치환은 이동 성공 «뒤에».
- 시스템 python3 에 pytest 없음 → 각 워크트리 `.venv/bin/python -m pytest`.
- Serena 자동 활성이 다른 나노 워크트리로 잡힐 수 있다 — 나노에게 자기 워크트리 재활성 지시.
- 백그라운드 `nohup` 감시 루프의 래퍼 완료 알림은 루프 종료가 아니다(`ps … seq 1 150` 확인).
- pkill 류는 훅에 막힌다(우회 금지).

## 환경
- 워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base, 로컬 앞섬 · origin/main 과 squash 로 갈라져 있음). mbox: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`.
- 현역 좌석: planner #8 · arch #10(cron 2fcdafbb) · issues #3 · CFO #56 · feature arch#1+nano f-multilingual-linebreak-css · DA da-codex#0 · harness 나노 4(proposal-tools#0 · magazine-detail-collect#0 · magazine-eli5-html#0 + 닫기 대기). 정지 레디: harness master #8~#11·arch #8·#9.
- 내 크론 3f288bc1 은 후계 부팅 보고 확인 뒤 CronDelete.
