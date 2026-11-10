# HANDOFF — byz-harness-master-claude#15 → #16 (2026-10-08 · ctx 404k 증류)

## ★골 원문 (GOAL-harness.md 복붙 — 읽기 전엔 착수 금지)★
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
이 단위의 골 축: A(모니터·오빠 요청) + 6-b(개선요청 접수·협의) + C(업그레이드·커밋·push·반영) + 원문 5(머신 독립 배분).
★승계 첫 일 = 골 대조 3줄 + 부팅 3항 + i-have-adhd 를 현역 planner(`ft-harness-info.sh seats` · 지금 byz-planner-master-claude#11)에 mbox 보고 → 같은 턴 CronCreate 10분 틱(cron=job id 보고).★ BOOT 17조항 먼저. 전임 크론 `b17e625e` 는 후계 부팅 보고 뒤 내가 삭제. 오빠 보고 = 결론→할 일→바뀐 것→근거 + PR·Issue 번호는 맨 아래 각주 표.

## 지금 상태 (한 줄)
★PR 929(판정 원장+인박스+슬랙 게이트 코드 · §58·§59·§60) 새 CI 1건 남음(실패 0) → 초록이면 `gh pr merge 929 --squash` → 나노 3석 닫기 → 라이브 설치. 나노 v438(Python Test 속도) 구현 중. 신규 발주 대기: 판정 440.★

## 이번 세션(#15)에 끝낸 것
- 부팅·크론, PR 911·923·930 병합(911 슬랙 이어가기 · 923 R29 cherry 게이트+R30 승계 창 이관 · 930 CI 비용 차단 판정 436), 라이브 설치: 슬랙 미러 키트 · `.fable-team/bin/ft-resume-cmd.sh` · 라이브 FT_BIN(`v6-realtime-live/.fable-team/bin`)에 `ft-nano-cherry-gate.sh`(+백업 .bak-r29-1009)·`ft-nano-cherry-pr.sh`·`ft-seat-handover.sh`.
- 판정서 §57(R30)·§58(판정 원장)·§59(인박스)·§60(카드2 결과 답글/CLOSE 게이트)·§61(CI 비용) append + 카드 완성 이동 + 나노 R29·R30·v436 닫기.
- loom master#1 개설(+명부), arch#13→#14 승계, 명부 `_hil_route` → planner#11 (feature·harness·loom·ops).
- 원장 R34(planner 지연 → 읽기는 빠름·오빠 미보고 26%) · R35(ft-role-spawn 팀 env) · R36(local-dev 캐시 키) · R37(ft-index-move 인용 절 대조 없음) 접수.

## 열린 일 (순서)
1. **PR 929 (ops/land-v430-v425-card2, 머지 sha 65e85dc205)**: CI 초록 확인 → squash 병합(**push·re-run 0**, 판정 436) → 나노 3석(`byz-harness-nano-v430-verdict-ledger#0` · `v425-master-inbox#0` · `result-reply-close-gate#0`) `ft-nano-close.sh`(PR 929 squash 라 cherry 게이트 REJECT 시 `--cherry-override "<사유>"` — 단 3분 유휴 후 «한 번만» 시도, 반복하면 override 원장에 행이 쌓임). 나노 닫기 `--recv` 값: v430=62796→ 나노 마지막 완료 보고 seq(62854), v425=62881, result-reply=62924(재산출2).
2. **라이브 설치(PR 929 병합 뒤 · 판정서 표 순서)**: ①`ft-inbox.sh`·`ft-inbox.py`·`ft_inbox_core.py` 3파일을 라이브 bin 에 «먼저» cp → 그 뒤 `.fable-team/comm/mbox.sh`(= `tools/comm-canonical/mbox.sh` 231줄 판) ②`ft-verdict.sh`+`ft-verdict-lock.sh` 한 쌍 cp · 명부 `_verdict_host=MacBook-Pro.local` · seed · 발급 전환(§58 표 5행) ③`slack-post-guard.sh` 는 «BYZ 프로젝트 settings 에만» 등록(전역 0 · 판정 §60 표 3) ④R30 전역 훅 2개(`retired-seat-guard`·`no-attach-to-user`)는 §57 점검 표 순서(7 bin 먼저 → 3·4 확인 → settings 등록 · 옛 좌석 MISMATCH 쪽지 일괄 각오) ⑤`ft-live-bin-drift-check.sh --bin <FT_BIN> --repo . --ref origin/main` 로 마무리(MODE 경고는 PR 929 가 chmod 로 해소).
3. **나노 v438 (판정 438 · Python Test 19분→≤6분)**: `byz-harness-nano-v438-l6-redis-fixture-fast#0`(base origin/main). 안 (가) = `tests/worker/unit/_v65_l6_redis.py` 소켓 대기+kill(격리 유지 · DA 없음). 산출이 오면 master 독립 검증(관련 pytest 만 · tests/ 전체 금지 · `LOCAL_VLLM_BASE_URL=http://127.0.0.1:9/v1` · timeout) → arch 재현 → 판정서 §62 → 랜딩 PR(push 1회) → PR CI 분 측정. 6분 초과 시에만 (다)xdist·(라)slow 마크.
4. **판정 440 (오빠 · planner#11 #63092)**: 「팀·이슈 랜딩 때 정본화·문서화 완성을 어디서·어떻게」 기획+DA 발주 — arch 설계→DA→planner 회신 · 집행 0. 전문 `/tmp/mbox/20261008T155942-byz-planner-master-claude#11-to-byz-harness-master-claude#15-order-440-landing-canon.md` — ★아직 arch#14 에 발주 안 함★ (이 증류 직전 도착). 첫 발주문 맨 앞 3줄 = 골 원문.
4-b. **판정 441 (오빠 · planner#11 #63093)**: 판정 430 인박스(스크립트 큐+Haiku 5.5 일회 호출 · 나노 v425)의 랜딩 후 점검 — 실측 3: ①랜딩 sha·설치 여부(cmp) ②실제 쪽지가 큐→Haiku 요약까지 돈 건수·실패 건수(로그 근거) ③상시 세션 0 유지·호출 비용. «판정 440 기획 다음 순서 OK». 회신 = 표 1장 + 이상 있으면 원인 층. ★PR 929 병합+라이브 설치 «뒤»에만 의미 있음.★
5. **R35 / R37 카드(대기)**: `r35-role-spawn-team-env-reject.md`(대기·낮은 우선) · `r37-index-move-da-section-binding.md`(미커밋 · 선행 = 카드2 슬랙 단계 랜딩=PR 929). 카드 커밋은 PR 929 병합 뒤.
6. **보류(커밋 금지·미추적 유지)**: `대기/gate-hook-kit-equals-home.md`(판정 345) · `design/ops/`. 
7. **R36**: planner 판정 대기(scripts/server 터널 안내·회전 체크리스트 = ops 소관 제안).
8. **판정서 번호**: 마지막 §61. 다음 §62(v438). 판정 번호는 planner 발급(원장 도구 ft-verdict.sh 가 설치되면 거기서).

## 현역 좌석
planner `byz-planner-master-claude#11` · cfo `byz-cfo-master-claude#59` · issues `byz-issues-master-claude#4` · feature `byz-feature-master-claude#3` · ops `byz-ops-master-claude#0`+arch#1 · loom `byz-loom-master-claude#1`+arch#1 · harness arch `byz-harness-arch-claude#14`(Opus 5.5 · cron 28d672e1) · DA `byz-harness-da-codex#0` · 나노: v430·v425·result-reply(PR 929 대기) · v438(구현 중). 정지 레디: harness master #9~#15 · arch #8~#13.

## 운영 규칙·함정 (실측)
- **CI 비용(판정 436)**: 로컬 검증 증거 없이 push 0 · push 1회 · re-run 0 · PR 열린 브랜치에 docs push 0. main 합치기는 merge(force-push 0). ci.yml 은 PR 930 으로 이미 적용(PR 10잡 · main push 4잡).
- 독립 검증 표준 3종: 변경 shell `shellcheck -S warning` · 변경 py `.venv/bin/ruff check` · 시험 `bash tests/harness/<t>.sh` · 200줄 한도(mbox.sh 는 원래 226줄이라 예외 — 분할 카드 `mbox-sh-split-200.md` 대기). 한도 초과·형식 위반은 나노 반송.
- 카드 이동 `--da §N` 은 «닫힘» 글자만 본다 → **카드에 맞는 절을 직접 인용**(R37). 증거 줄은 harness-ops 카드 끝에 «맨몸 1줄».
- 나노 닫기 cherry 게이트: nano base 가 origin/main 이면 ops/main-base 대비 +N 으로 보임 → 직접 `ft-nano-cherry-gate.sh origin/main <branch>` OK 확인 후 `--cherry-override`.
- 훅 `block-destructive.sh` 오탐(heredoc 본문 글자 등)은 원장 R28 — 기록+Write 도구 허용. `rm -rf` 는 새 디렉터리에도 쓰지 말 것(rm 없이 mkdir -p 새 이름).
- `--urgent` 는 mbox send 의 «마지막 인자». 앞에 두면 수신자로 오인.
- 나노는 «seats.json 에 내 행 없음» 오인 → 명부는 `seats-harness.json`, 이미 등록됨(답장 1줄).
- mbox: 본문 백틱 금지 · 긴 본문은 파일 후 relay(절대경로) · 같은 본문 fan-out 금지. 읽힌 행은 현역 mailbox 에서 회전(bodies/<seq>.txt 에 원문).
- `ft-nano-spawn` base = 호출 브랜치 HEAD → 나노가 origin/main 기반이면 `--base origin/main` (카드 파일은 harness-ops 절대경로로 읽게 안내).

## 환경
워크트리 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops` (브랜치 ops/main-base · 로컬 앞섬 · push 대상 아님). 랜딩 워크트리 `.worktrees/harness-land-1008f`(PR 929 브랜치). mbox `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/comm/mbox.sh`. 판정서 `design/teams/harness/OPS-VERDICTS-20261006.md`. 요청 원장 `design/teams/harness/REQUEST-LEDGER.md`(다음 R38).
