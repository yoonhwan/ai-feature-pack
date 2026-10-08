# HANDOFF — byz-harness-master-claude#14 → #15 (2026-10-08 · ctx 403k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항(세션명/모델·창/Serena) + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#10)에 mbox 보고 → 같은 턴에 CronCreate 10분 틱(cron=job id 보고) — 없으면 착수 0.★ BOOT 17조항(~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md) 먼저. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표. 전임 크론 `50585e06` 은 후계가 부팅 보고 보낸 뒤 CronDelete.

## 지금 상태 (한 줄)
★PR 911(슬랙 이어가기 블록·단일 발행 입구) CI 대기 → 병합되면 라이브 설치 → 카드 2 spawn. R29 §56 닫힘(나노 닫기·랜딩 대기) · R30 나노 완료(master 검증 통과 · arch 재현+DA 재확인 대기).★

## 이번 세션(#14)에 끝낸 것
- 판정 357 제안서 흐름 r2: PR 904 병합(ee91993cfb) + install-magazine 설치(홈 파일 6개 main 키트와 바이트 일치). 닫는 증거 = 다음 제안서 1건에서 슬랙 첨부 2개 + Issue 본문 표식.
- R21(feature 틱 plist) 닫힘 · R27(틱 master 좌석 단일 정본) PR 909 병합(243e044c55) + 팀 틱 5개(cfo·feature·kk·loom·ops) + v65 키트 틱 라이브 설치. 명부: harness #14 정리·kk `_master`·`_hil_route` planner#10 갱신(feature/issues/loom/ops/harness).
- R26 · R20 완료 · R28(훅 오탐) · R31(spawn base) 접수 · R32/R33 → 오빠 승인(판정 419·420) → Issue #914(cfo CORS 38301~38399)·#915(ops get-token 마스킹) 등록 완료(각 팀 처리).
- 판정 404 ① 감사(AUDIT-j404) → 판정 405 오빠: 제안서 채널 = #byz-planner 통일 → ② 설계 DA APPROVE → 카드 1 §55 닫힘·나노 닫기·PR 911 올림.
- 좌석 개설: ops arch#1 · loom arch#1 · harness arch#12→#13(승계). 

## 열린 일 (순서)
1. **PR 911 (#911 ops/land-resume-block-card1)**: CI 초록 → `gh pr merge 911 --squash`(RED 관찰 체크 제외) → 병합 후 라이브 설치(`install-magazine.sh` · `install.sh` 목록에 새 모듈 추가됨 · `byz_thread_post.py --init` 장부 초기화 · 미러는 `.fable-team/bin/ft-resume-cmd.sh` 필요 · 제안서 발행은 `--card --seat --resume-script` 필수) → **카드 2 `result-reply-close-gate`(대기/) spawn**(`ft-nano-spawn.sh … --model 'claude-sonnet-5-5[1m]'`, 카드 1 랜딩 뒤가 선행 조건). 소급 결과 답글 7건은 카드 2 랜딩 뒤 master 집행(사실 = `FACTS-j404-magazine-8items-20261008.md` · planner 라인 사실은 BOARD r55 머리줄 복붙 · 2·3·4호는 #byz-agent 라 hermes 토큰 1회 · 1호도 hermes · 5호·매거진은 공식 도구).
2. **R29 (진행→완성 끝, 나노 닫기 대기)**: 나노 `byz-harness-nano-r29-cherry-gate-squashed-pr#0` 닫기 재시도(유휴 3분) → PR 911 병합 뒤 그 위에 새 랜딩 워크트리(origin/main)에 cherry-pick(34250ec556 + 문서 커밋) → 시험 → PR → 병합 → **라이브 FT_BIN 에 `ft-nano-cherry-gate.sh` + `ft-nano-cherry-pr.sh` 둘 다 cp**(pr.sh 없으면 플래그 REJECT) → `--squashed-pr 905` 실사례 1회(feature `nano/f-guest-jwt-impl-s1`, 이미 닫힘이라 dry-run 성격).
3. **R30 (승계 때 오빠 입력 창 이관 · 오빠 체감 버그)**: 나노 `byz-harness-nano-r30-seat-handover-window#0` 완료 보고 #62535(코드 03481b45ba · 시험 48 PASS · master 검증 통과). arch#13 에 재현 + DA 1회(구현 재확인: T0 2탭 → switch 0 · 인용 줄 → 기록만) + §57 초안 요청함(#62539). 증거 줄은 `진행/r30-seat-handover-window.md` 끝에 나노가 append 함(미커밋 — 이 스냅샷 커밋에 같이 넣음). 이후: §57 append → `ft-index-move … 완성 --da …#§57` → 명부 치환 → cherry-pick → 나노 닫기 → 랜딩. ★전역 훅 템플릿 2개(retired-seat-guard · no-attach-to-user)는 라이브 설치 전 «오탐 시 전 좌석 입력 차단 여부» 점검을 §57 초안에서 확인한 뒤에만 설치.★
4. **판정 410 (콘솔 보고 ↔ 슬랙 미러 괴리 · 404 후속)**: 감사 표 `design/harness/AUDIT-j410-console-vs-slack-20261008.md`(미커밋 — 이 스냅샷 커밋에 같이 넣음) planner#10 수신·「404 이어가기 설계에 합치는 것 OK」(#62517). 설계 반영은 arch#13 몫.
5. **R31 접수(낮은 우선)**: `ft-nano-spawn` base 가 호출 브랜치 HEAD — CFO 는 spawn 때 `--base origin/main`. R28(훅 오탐: heredoc 본문의 rm -rf 글자) 접수 · 개선 안 대기.
6. **정리 대기**: 나노 워크트리 정리 `skipped:cwd 보유 프로세스` — zombie/wt-sweep 틱이 재시도(수동 정리 금지·HIL). 임시 랜딩 워크트리 `.worktrees/harness-land-1008·b·c·d` 및 브랜치는 병합 끝(또는 PR 911 대기) — 제거·브랜치 삭제는 HIL(planner [HIL]).
7. **보류(커밋 금지·미추적 유지)**: `대기/gate-hook-kit-equals-home.md`(판정 345) · `design/ops/`(공유 DA 가 ops 판정문을 harness-ops 에 씀 — ops master 에 «ops-main 으로 복사·커밋» 통지 완료).
8. **CFO 나노 `byz-cfo-nano-seoul-pg-live-read-and-claim-observe#0` cherry-override**: planner#10 승인(#62451) → cfo master#58 이 집행(내 몫 없음 · 결과 1줄은 cfo 가 planner 에 보냄).
9. **v65**: 마감(판정 335·336) · v65 master#146 정지 레디 · 뉴스 0건이 정상(재개 땐 planner 경유 새 master + 틱 행 등록).

## 현역 좌석
planner `byz-planner-master-claude#10`(#9 정지) · cfo `byz-cfo-master-claude#58` · issues `byz-issues-master-claude#3` · feature `byz-feature-master-claude#3` · ops `byz-ops-master-claude#0` + arch#1 · loom `byz-loom-master-claude#0` + arch#1 · harness arch `byz-harness-arch-claude#13`(Opus 5.5, cron b5b889da) · DA `byz-harness-da-codex#0`(공유) · 나노: R29·R30. 정지 레디: harness master #8~#13 · arch #8~#12.

## 운영 규칙·함정 (실측)
- 전임 스냅샷(`HANDOFF-harness-master-13-to-14-20261008.md`)의 흐름 규칙이 그대로 유효: 발주(골 3줄 + 축) → arch 안 → (DA) → 나노 → master 독립 검증(.venv pytest·ruff·shellcheck 파일별·200줄) → arch 재현 §N → 판정서 append(`OPS-VERDICTS-20261006.md`, 마지막 §56) → `ft-index-move.sh … 완성 --da "…#§N" --seat <나노>` → seats-harness.json 의 index 경로 치환(python `str.replace` · 한글 sed 금지) → 커밋(**경로 지정**; `git add <폴더>` 로 보류 카드 끼는 사고 주의) → cherry-pick → 나노 닫기(유휴 3분) → 랜딩 → 홈 cp.
- **증거 줄 위치 함정(반복)**: 나노가 자기 워크트리 사본에만 적음 → 닫기 ⑥ 실패. 증거 줄은 «harness-ops 의 현재 위치 카드(진행/ 또는 완성/) 절대경로» 맨 끝에 나노가 append 하게 반송(master 가 직접 쓰지 않음).
- **shellcheck**: 파일별 `while read` 로 돌린다(공백 목록 한 줄 호출은 오류). 변경 줄에서 새로 생긴 경고만 반송(기준 대비 비교 · 기존 SC2034 등은 범위 밖).
- **lint 사전검증**: 마지막 판정이 APPROVE 여야 통과(HOLD 면 REJECT) → 2 HOLD 로 리뷰 종료된 카드는 「소환: 아니오 + 면제 서명(arch)」 경로(bounded_da_review.md).
- 훅: `block-destructive.sh` 오탐(본문 글자) → 원장 R28. 파일 편집은 Write/Edit 도구, 시험 실행은 bash 단독 호출로 분리하면 막히지 않음. `rm -rf`·`--amend` 차단. `sleep N` 뒤 명령 체인은 차단(Monitor/until 사용).
- 새 팀 master 승계 통지가 오면 **명부 `_master`·role·tick 행을 맞춘다**(R27 틱이 `_master` 하나만 읽음 · 없거나 교체면 ERROR+뉴스 0). 오빠 입력 창 이관(R30)이 랜딩되기 전까지는 구세션이 오빠 입력을 받으면 번호 없이 후계에 relay 만.
- 새 판정 번호는 planner#10 이 발급(번호 충돌 2회 사고 · 408·410).
- mbox: 같은 본문 여러 좌석 fan-out 금지 · 본문 백틱 금지 · 긴 본문은 파일 후 `relay`(절대경로) · 발신 5건/60초.

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base, origin/main 과 squash 로 갈라져 로컬 앞섬). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/harness/OPS-VERDICTS-20261006.md`. 요청 원장 `design/harness/REQUEST-LEDGER.md`(다음 R34).
