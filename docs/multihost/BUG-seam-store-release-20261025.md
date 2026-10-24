# BYZ 결함 후보 — release 가 «침묵 꼬리 회차» 를 회수할 때 seam_store 미전달 (2026-10-25)

골의 어느 축: 오빠 «시험 이관» — mini 에서 러너 1회차 성공 줄 `✅ host 단일 버블 (delta=1, polished Nchars)` 이 닫는 증거. 이 결함이 마지막 막힘.
발견: aifp-multihost-master-claude#4 · 러너 1회차(h313) 2026-10-24 23:58 · mini 설치본 BYZ main `c34fc47f`

## 관측 (mini `/tmp/h-byz-worker.log` L751~892)
1. STT 정상: seq=1 `provider=gpu_qwen3 text_len=13`(«오늘 회의를 시작합니다.») → polish·translate_dispatched 까지 통과.
2. seq=2 = 전부 0 PCM 꼬리(8276B) → `deterministic_silence` guard_drop (정상 침묵 회차).
3. release 단계: `VadInitiationWiringError: seam_store required for supersede: psid=… targets=[1]` → `[V6-PULSE-CONSUMER] batch infra error` + `V6-B:ingress:RETRYABLE` attempt 1·2 반복 → utterance.finalized 말풍선 0 → 러너 `host_empty`.

## 원인 위치 (코드)
- `worker/infrastructure/consumers/v6_pulse_consumer.py:276-290` `_reconcile_release_owner` 가 `reconcile_release(...)` 를 부를 때 `seam_store=` 를 넘기지 않는다. (같은 파일 :223·:251 과 `worker/c2c_act_entrypoint.py:180` 은 넘긴다.)
- `reconcile_release` 의 `seam_store` 기본값 None → `release_reconcile.py:359` `supersede_silence_rounds` 가 침묵 회차가 있으면 loud 실패(`vad_initiation.py:290-292`). `release_finalizer.py:143` legacy 직결 경로도 같다.
- BYZ `origin/main`(ecb405b486)·`origin/v65` 도 같은 상태(위 호출에 seam_store 0건 — `git show` 로 확인).

## 모르는 것
이 맥 시험은 같은 경로를 어떻게 통과하는지(침묵 꼬리가 없었는지 · 다른 경로 owner 인지) 확인하지 못했다. 원인 단정이 아니라 «후보».

## 요청
v65(또는 담당) 팀이 위 호출에 seam_store 전달이 맞는지 판정·수정. 이 팀은 BYZ 코드 편집 0. main 에 들어가면 알려 주면 mini 를 그 sha 로 올려 러너 1회차를 다시 돈다.
증거 원본: mini `~/Project/BYZ-Agents/.h-run1-20261024-235814.log` · worker 로그 위 구간.
