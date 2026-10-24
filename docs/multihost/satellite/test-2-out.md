# out — test-2 요약

1. 결함: release 가 침묵 꼬리 회차를 회수할 때 `v6_pulse_consumer.py:276-290` `_reconcile_release_owner` 가 `reconcile_release(...)` 를 부르며 `seam_store=` 를 넘기지 않는다(같은 파일 :223·:251 과 `c2c_act_entrypoint.py:180` 은 넘긴다).
2. 증상: `seam_store` 기본값 None → `release_reconcile.py:359` `supersede_silence_rounds` 가 침묵 회차에서 `VadInitiationWiringError` 로 loud 실패 → `[V6-PULSE-CONSUMER] batch infra error` + `RETRYABLE` 재시도 반복 → utterance.finalized 0 → 러너 `host_empty`.
3. 요청: v65(또는 담당) 팀이 호출에 `seam_store` 전달이 맞는지 판정·수정(이 팀은 BYZ 코드 편집 0), main 반영 sha 를 알려주면 mini 를 올려 러너 1회차 재실행. 원인 단정이 아닌 «후보».

SAT-DONE host=BYZs-Mac-mini.local
