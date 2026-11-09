# airag-tick-op-7s — tick.py op 호출 상한을 런타임 7초 룰에 맞춘다

골 원문: 최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: C12(consumer 상시 서비스 회복 · 안 B AIRAG.app) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 C12 — 앱이 5분마다 부르는 tick 의 op 호출이 런타임 7초 절대 룰(판정 4114)을 지킨다.

담당: airag (aifp-airag-master-claude#10) · 줄 주인: master#10
연 근거: planner arch#41 #3530 (2026-11-05) · DA r2 판정 처분 별건(feature-pack/rag/docs/artifacts/da-20261105-appB-r2.md 끝 2줄 · 커밋 35347c52)
분리: build.sh(make-identity·sign) 카드와 범위·DA 회차가 따로다. build.sh 는 로컬 도구라 10.5초 유지(판정 4114 로컬 25초).
순서: h-S1(인증서 만들기) 뒤에 착수한다.

## 기준값

- `feature-pack/rag-consumer/src/airag_consumer/tick.py:48` `OP_ATTEMPT_TIMEOUT_S = 10.5`
- `feature-pack/rag-consumer/src/airag_consumer/tick.py:49` `OP_CALL_DEADLINE_S = 21.0`
- 기준 sha: feature/rag-transplant @ 35347c52

## 끝 줄 (전부 채워야 완성)

1. [ ] 실측: 지금 tick 로그에서 op 1회 소요 분포(p50·p95·최대 · 최근 N회 · 로그 경로·기간 명시)
2. [ ] 멈춤 관문: 실측 p95 가 7초를 넘으면 구현 전에 멈추고 `[HIL]` 1통(planner master 경유 · 7초 안으로 쪼갤 방법 또는 예외 질문)
3. [ ] 상한: 시도 7초 + 재시도 1(합 14초) · tick.py:48-49 두 값만 바꾼다
4. [ ] 시험: 7초 넘는 가짜 op(sleep) → 재시도 1 → 실패 raise · ERROR 로그 1줄(조용한 성공 0) · 시험 1개 70초 이내
5. [ ] 회귀: 기존 tick 시험 통과(느린 파일은 쪼개 돌림)
6. [ ] 설치본 반영 여부: 설치된 runtime 의 tick.py 교체는 사람 승인 h 로만(이 카드 범위 밖이면 «알려진 한계» 1줄)

## 증거 줄 (진행 중에 채운다)

- [11-06 00:0x master#10 · 끝 줄 1 사전 실측] `~/.local/share/airag/logs/tick-2026101{1,2,3,6,7,8}.log` 308줄: 성공 틱 64줄(status degraded)은 op 소요 칸이 없다 · 실패 틱 244줄(OP_READ_UNAVAILABLE) 중 probe 시도 기록 10줄 · 시도 60건 전부 outcome=timeout(약 10.5초 · 10-16~18 launchd 맥락) · 성공 시도 0건 → 로그만으로 p50·p95 판정 불가. 끝 줄 1 은 터미널 op read 반복 측정(h)으로 채워야 한다.
- [11-07 master#12 · 끝 줄 1·2 닫힘 근거] h10 = `.fable-team/state/airag/op-timing-plan.sh` 실행(오빠 손 · 2026-11-07 08:08 · rc 0 · 17.2초) · `요약: n=15 · 성공 수=15 · p50=2.61초 · p95=2.80초 · 최대=2.80초 · 7초 넘은 수=0` · `판정 이름: p95 ≤ 7` · 전문 /tmp/h10.out · 멈춤 관문 통과(p95 2.80 ≤ 7).
- [11-07 nano#2 · 끝 줄 3~6] 069e64a8(rag-transplant · push 0): tick.py:48-49 `OP_ATTEMPT_TIMEOUT_S` 10.5→7.0 · `OP_CALL_DEADLINE_S` 21.0→14.0 · 새 시험 `test_op_slower_than_the_real_7s_limit_is_retried_once_then_fails_loudly`(실제 한도 · `exec sleep 30` 가짜 op · 시도 2회 · key_error/OP_READ_UNAVAILABLE/TimeoutExpired · 통과 20.7초) · 회귀 test_tick 158 · test_tick_probe 90 · test_tick_op_home 18 · test_tick_store_keys 32 · test_pass_gate 85 · test_pass_trace 84 전부 통과 · 알려진 한계: 설치된 runtime 의 tick.py 는 아직 옛 값(10.5/21.0) — 교체는 사람 승인 h 로만 · tick.py:47 주석(«총 21.0»)은 발주 범위(48-49 두 값만) 때문에 그대로라 값과 어긋남 · test_probe_opa m1 경계 시험은 HEAD 사본에서도 간헐 실패(무관).
- [11-07 master#13 · 끝 줄 6 앞 R-H·R-F 코드 DA] r1 REJECT(569405f2 · 반례 1·형식 2) → 수정 b193b054(nano#3) → r2 REJECT(2febb4ce · r1 3건 해소 · 상위 경로 교체 경합 1건) · [범위 밖] — planner arch#43 덧판정 2(BYZ #3637): 입력 범위 규칙 «AIRAG 가 만든 폴더(`~/.config/airag` 이하)는 tick 실행 중 다른 프로세스가 symlink·다른 폴더로 바꾸지 않는다» (하드 룰 19 · da-counterexample §6 · 같은 권한이면 설치본을 바로 고칠 수 있어 경계 넘음 0 · 자식 op 는 HOME 을 경로로 받아 부모 검사로 원리상 못 닫음) · 정적 상위 symlink 는 b193b054 로 닫힘 · DA 3회 중 2회 사용 · 남은 미시험 = b193b054 위 tick 회귀 9파일.
- [11-07 master#13 · R-H·R-F 카드 판정 D2 = APPROVE] 남은 미시험 닫힘 — nano#3 #3642: HEAD 2febb4ce(tick 코드 = b193b054) 위 tick 회귀 9파일 737 통과 · 실패 0 · 오류 0(test_tick 158 · test_tick_probe 90 · test_pass_gate 85 · test_pass_trace 84 · test_reason_codes 18 · test_tick_op_home 23 · test_tick_store_keys 36 · test_plist_edit 144 · test_chain_opa 99 · 30묶음 동시 4 · 전체 139초 · 시험 1개 최장 14초대) · [수용] 반례 0 ∧ 미시험 0 → D2 APPROVE(arch#43 덧판정 2 순서 3) · 다음 = R-H wip 해제 새 커밋 → tick-install-plan.sh COMMIT 핀 → 점검 rc 0 → 설치 h.
