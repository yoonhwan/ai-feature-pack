# HANDOFF — byz-harness-master-claude#26 → #27 (2026-10-10 · ctx 401k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: B(개선요청 접수·협의)+C(업그레이드·커밋·push·반영).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`byz-planner-master-claude#22` · `ft-harness-info.sh seats` 실측)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id). 전임 크론 `1d771081` 은 세션 종속이라 새로 건다. BOOT 23조항 먼저. 좌석표 교체: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-master-claude#26 byz-harness-master-claude#27 --seats .fable-team/seats-harness.json`.★

## 지금 상태 (한 줄)
R80·R81·R83·R86 전부 main 랜딩·라이브 설치·나노 닫음(main `aa724ad806`). 하네스 나노 0석 · arch#27 휴식 · da#1 대기. 열린 건 아래.

## 열린 일 (순서)
1. **R86 라이브 확인**: planner#22 가 감시(`ft-inbox-watch.sh` Monitor) 무장 끝(쪽지 #72595). 오빠 참여 라이브 1회 = planner 가 오빠가 입력창에 칠 때 «시험 쪽지 1통 보내 달라» 고 알리면 내가 발송(그 전엔 먼저 보내지 않음) → 입력창 글자 그대로·세션 안 알림 1건 확인 → 통과 뒤 요청 원장 R34·R57·R85 닫기(합침 기록은 판정 877 줄에 이미 있음) + BOOT·governance 에 1줄(완료 조건 4).
2. **graphics 시안 랜딩(쪽지 #72603 · 판정 891)**: 가지 `nano/g1087-next-preview` 70721bfef4(design/graphics 안 36파일·제품 diff 0·merge-tree 충돌 0). push 승인값은 planner#22 에 [HIL·push] 올림(#72615) — 값 오면 원격 push(가지 보존) + PR(본문 Refs #1087) → 체크·merge 따로 → tree 대조 → graphics#2 에 결과 1줄. 나노 닫기는 랜딩 뒤 graphics 요청 시.
3. **접수만 된 요청(착수 0)**: R82(게이트 ft-proposal-gate.sh:138 이 «재현 입력» PROPOSAL 인용을 우회로 REJECT — 구현 대상 인용과 구분) · R84 재발 방지(팀 명부에 역할 행 없으면 ft-role-spawn 이 다른 팀 명부로 떨어지지 말고 REJECT — 명부 복구는 이미 적용) · 정본 mbox.sh 는 R86 으로 반영됨. 우선순위는 planner 지시 대기.
4. **묶음 push 대기(판정 739)**: ops/main-base 로컬 커밋 666개(원장·카드 증거·나노 원장 등)는 push 금지 브랜치 — 코드 랜딩 때 land 브랜치로 옮겨 같이 올린다(R80·81·83·86 선례: `git worktree add ../harness-land-<x> -b land/<x> origin/main` → 나노 브랜치 merge --no-commit → 커밋 → 문서 `git show ops/main-base:<f> > <f>` → 로컬 시험 → push → `gh pr create --body-file` → `gh pr checks` 별 명령 → `gh pr merge --squash` 별 명령 → tree/파일 대조 → 라이브 cp+.bak+cmp+드리프트 → 나노 닫기). push 는 오빠 명시 승인값(planner [HIL·push])만. 미커밋: NANO-LEDGER-harness.md(도구 자동 기록) — 다음 land 때 같이.

## 이번 세션(#26)에 끝낸 것
R80 발행기 기록 rN(PR 1182 a3cbe3ba92) · R81 spawn 롤백·사전 장부 확인·undo·repair --root(PR 1183 ddcf90affc · 판정 845·846·847 — kill 은 ③④ 실패만 · 전역 CLAUDE.md+codex·hermes 전파본 반영) · R83 `! bash /tmp/h<N>` 짧은 명령(PR 1185 ce7fa8c8c6 · 판정 850·852·856·858 · 진입점은 /tmp 만) · R86 쪽지 세션 안 감시(PR 1196 aa724ad806 · 판정 876·877·881·887 · 제안 #1184·#1191) · R84 명부 오기록 복구(loom tester #34 이관) · CFO stale lock 2개 삭제 · 다음 번호: 판정서 §117+ · 요청 원장 R87 · 라이브 bin 백업은 `.bak-r81/r83/r86-<ts>`.

## 운영 규칙·함정 (이번 세션 실측)
- **환경**: `cd .worktrees/harness-ops && source ../../.fable-team/bin-harness/harness-env.sh && export FT_SEND_FROM=…` → `$FT_BIN`=`v6-realtime-live/.fable-team/bin`. mbox 정본 경로 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`.
- ★**planner 앞 쪽지는 doorbell 0**(R85 핫픽스+R86 정본) — 쪽지는 큐에만 쌓이고 planner 는 Monitor(세션 안 감시)·10분 틱으로 읽는다. 급해도 planner pane 에 send-keys 금지(오빠 입력 절단).
- ★**오빠 글 = 쉬운 말 · 번호는 각주 표**(10-10 오빠 「인댁스쓰면 내가 어떻게 이해해?」): 번호·R·r1 본문 사용 0 · 끝에 표(번호·종류·제목·상태). mbox 는 예외.
- **제안 흐름**: 제안서(arch) → 카드 → `ft-proposal-open.sh <md> --apply`(Tank Issue) → `byz_proposal_publish.py <md> --card <카드> --seat <좌석> --issue <N> --resume-script …` → planner [HIL] 컨펌 → issues#11 이 approved → 카드 머리 #N → spawn. 제안서 변경 시 `--revision rN`(approved 자동 해제 · 재승인). 카드 본문에 PROPOSAL-*.md 파일명 인용 금지(R82 오탐 — 판정 841).
- **나노 닫기**: 카드 `## 결과` 에 증거 줄 `세트: <40hex> · 시험: <명령> rc=<n> · 이슈: 0`(이슈 칸은 0 또는 카드 경로 — `#N` 은 REJECT) append → `ft-nano-close.sh <좌석> --result <카드> --recv <seq> --cherry-override "<사유>"`(squash 랜딩은 파일별 `git diff <nano>:<f> origin/main:<f>` 동일 확인 뒤).
- **gh**: `unset GH_TOKEN` · 체크 확인과 merge 별 명령(체크 0건은 경로 필터). squash 뒤 main 이 이동하면 tree 가 아니라 «우리 파일» 대조.
- ★하위 좌석(나노·arch·DA)은 AskUserQuestion 금지 — [HIL] 은 planner(`_hil_route`=#22)로. DA 3회 HOLD 규칙: bounded, 2회 HOLD 면 중단·3차는 planner 허가(판정 832·846).
- **zsh**: `$B:path` 수정자 · `$F` 단어 분리 안 됨 → 파이프+xargs.

## 현역 좌석
planner `byz-planner-master-claude#22` · harness arch `byz-harness-arch-claude#27`(Opus 5.5 · 휴식) · DA `byz-harness-da-codex#1`(대기) · v65 master `byz-v65-master-claude#162` · graphics master `byz-graphics-master-claude#2` · issues master `byz-issues-master-claude#11` · loom master `byz-loom-master-claude#13` · cfo master `#68` · 하네스 나노 0석.
