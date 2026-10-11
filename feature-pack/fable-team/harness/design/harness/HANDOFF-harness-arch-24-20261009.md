# HANDOFF — byz-harness-arch-claude#24 → #25 (2026-10-09 · 컨텍스트 407k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

이 좌석의 골 축: A(모니터·오빠 요청) + B(개선요청 접수·협의) + C(업그레이드·배포·반영).

## 승계 첫 일 (순서 고정)
1. `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` Read(★22 비밀 파일 내용 출력 0 · 23 ft-op-token(설치 뒤) · 21 7초 룰★) → Serena `initial_instructions` → `activate_project(project="/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops", session_id=…)` → i-have-adhd 로드.
2. 골 대조 + 부팅 보고(세션명 / 모델·창 / Serena / i-have-adhd / cron=<id>)를 현역 master(**byz-harness-master-claude#23** — 발신 전 루트 `.fable-team/seats-harness.json` `_master` 확인)에 mbox. 같은 턴 CronCreate 10분 틱(mbox recv + 하위 나노 pane 실측 + 오빠 3줄).
3. master 에 부탁: 루트에서 `bash .fable-team/bin/ft-seat-retire.sh byz-harness-arch-claude#24 byz-harness-arch-claude#25 --seats .fable-team/seats-harness.json`.

## ★지금 열린 일★ (판정서 초안 = 루트 `.fable-team/state/drafts-r22/OPS-VERDICT-<N>.md` · 다음 번호 §108)
| 판정 | 무엇 | 지금 상태 | 다음 한 수 |
|---|---|---|---|
| 690 그래픽스 팀장 체제 정본화 | 카드 `design/harness/indices/대기/g690-graphics-master-system-info.md` + 스테이징 `design/harness/staged-690/{main-team-governance.md,harness-map.md}` (커밋 `661d2519db`) | ★나노 `byz-harness-nano-g690-graphics-master-system-info#0` 13:42 열림(master#23 spawn)★ | 나노 [완료·휴식] → `git archive <세트>` 스크래치 재현(`tests/harness/test_graphics_690.sh` + 두 ft-harness-info 사본 출력 동일 + install.sh SKIP) → 서명 · 판정서 §109 초안 → master 집행 요청(홈 governance base `d16650b52a809ecf` · map `33065f92565e622f` 확인 뒤 cp) |
| 675 ft-op-token(운영 토큰 자동 발급) | 세트 `0e82391b40` · 보안 DA(Claude Opus) r1 APPROVE `b1fce39930` · arch 서명·랜딩 GO #68414 | master#23 랜딩·설치 집행 중(회신 미수신) · ★홈 BOOT 는 통째 cp 금지 — staged 23 줄만 덧붙임★ | master 회신 확인 → §108 초안(재현: 11 passed · ruff · 실값 0) · 후속 카드 `design/harness/indices/대기/op675b-ft-op-token-hardening.md`(DA 비차단 권고 1~3) = 675 랜딩·ops 반입 뒤 spawn 신호(그 전엔 lint «경로 실재 0» REJECT 가 정상) |
| 678 그래픽스 첫 요청(cfo 크레딧 5화면) | 카드 `design/graphics/indices/진행/g678-cfo-credits-uiux.md` (arch 카드 `e93883ff2c`) | ★판정 690 으로 그래픽스 팀장 `byz-graphics-master-claude#0` 소관 — harness arch 몫 0(도구·설치만)★ | 요청 오면 도구 쪽만 |

## ★위험 1 (실측 · 690 랜딩 전까지)★
origin/main `scripts/harness-install/graphics/install.sh` 20행이 `seats-graphics.json` 을 루트에 «덮어쓴다» — 지금 재실행하면 팀장·arch·나노 g678 행이 빈 템플릿으로 지워짐. 690 카드에서 «없을 때만 복사»로 고침. 그 전엔 graphics install.sh 실행 0(master 에 알림 #68713).

## 이 세션에서 닫힌 것
| § | 판정 | 랜딩 |
|---|---|---|
| — | 609 매거진 쉬운 판 | PR 1073 `7fbbff9353` (master#22 #67619) |
| 106 | 623 슬랙 팀별 뿌리 글 | PR 1074 `8133983651` · 실 슬랙 팀 뿌리 글 ts=1791509990.890499 |
| — | 635/636/641 그래픽 팀 제안서 r5 | Codex DA r1·r2 + Claude Opus DA r3 APPROVE `580821eada` · arch 서명 `27aeb63af0` |
| 107 | 649 그래픽 팀 설치 | PR 1076 `4fc3140297` · 판정 651(그래픽 나노 닫기 표준승인 확장) |
- 판정 666(7초 룰)·676(비밀 파일 내용 출력 0) 접수 — BOOT 21·22.
- ★arch#24 실수 기록(판정 676 · 오빠 «기록만 · 교체 0»)★: secrets/byztest910.cred 를 awk 로 보다가 JSON 이라 줄 전체(비밀번호)가 세션 jsonl 에 1회 노출. JSON cred 는 `python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))))' <파일>` 로 키 이름만.

## 별 카드 후보 (착수 0 — 지시 때만)
1. 워크트리 `scripts/fable-team-bin/` 에 `ft-index-lint.sh` 없음 → 그 사본으로 `ft-nano-spawn --dry-run` 하면 lint 단계 무조건 REJECT(설치본 키트엔 있음).
2. 다음 팀 신설 카드엔 «카드 폴더를 `_cards_wt` 줄기에 반입» 단계(649 설치 직후 ft-board RuntimeError 실측).
3. 미러 시험 기존 실패(12 + inbound 13) · 매거진 시험 기존 13 실패.

## 함정 (실측 · 이 세션)
- ft-index-lint: 「조사 근거」 절 = `경로:줄` 인용이 카드 줄기(ops/main-base)에 실재해야 함 · 「소환: 예」면 DA 판정문 경로 실재 필요 → 착수 전 DA 없으면 `소환: 아니오` + `면제: <사유> — arch 서명 <좌석>` · 구현 범위 = 기존 경로 ≥1 백틱 · 새 경로는 백틱 밖. 팀 카드 lint 는 그 팀 env(`bin-<팀>/<팀>-env.sh`) source 뒤 `scripts/harness-install/fable-team/bin/ft-index-lint.sh`.
- ops/main-base 는 origin/main 보다 많이 뒤처짐 — main 에만 있는 파일은 `git show origin/main:<경로>` 로 읽고, 나노는 `--base origin/main`.
- 홈 정본(governance·BOOT·map) 설치는 «base sha256 확인 → 다르면 cp 0» 를 집행 순서에 반드시 넣는다(staged 사본이 옛 base 로 만들어지는 일 실측 — 675 BOOT).
- 같은 워크트리를 master 도 쓴다 → 커밋은 항상 `git commit -- <내 경로>` · push 는 master 몫.
- 스크래치(#24) = `/private/tmp/claude-501/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents--worktrees-harness-ops/12d08be0-86d1-4891-8101-53d20d2d4279/scratchpad/` — 623 `r623b-*` · 649 `r649` · 675 `r675`.
