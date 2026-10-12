model: GPT-6 기반 Codex (정확한 모델 ID 미노출)
provider: OpenAI (접속 경로 미확인)

# [DA⑥ r-autonomy-core] HOLD — 4건

고정 세트 `47c8e1c6bf6d1392aad4b1cdc94a72203cd6df3c`. 설계 참조 r3 `6cc227647a`. K1~K5 한정, 임시 FT_ROOT/상태/원장/gh 대역에서 실행. 실 상태·실 gh·실 판정 원장·큐·제품 변경·커밋 0. 본 판정은 현재 세션에 대리 승인 권한을 부여하지 않는다. Serena BYZ/LSP ready 확인; 고정 SHA는 git archive/show로 대조. 초기 검토 약 4분.

## 결과

- K1 PASS: 제외 표, 모르는 종류, reversible-choice, 인자 오류의 QUEUE 검사가 통과.
- K2 HOLD(H1/H4): 통상 head/SHA/pass 결속 및 실패 QUEUE는 통과하지만 현재 판정 오독과 실제 7초 상한 누출이 있음.
- K3 HOLD(H2): 카드 이름 경계 및 설계만 제외는 통과하나 착수를 허락하지 않은 원장 줄도 통과.
- K4 PASS: 없음/OFF rc3, json/log 불일치 위변조 표시·rc3, ON/OFF 사건 및 요약 시험 통과. 훅·시간 자동 전환·설치 권한은 이 판정 밖.
- K5 HOLD(H3): 정상 기록과 질문 재시도는 통과. 독립 동시 press-order 2호출은 판정103/104로 충돌 없음. 기록 실패에도 rc0/PROXY를 반환.

고정 기존 시험: `LC_ALL=en_US.UTF-8 /bin/bash tests/harness/test_autonomy_core.sh` rc0, bash3.2/5 포함 113 checks fail0. 초기 archive에서 shared/config/external_call.py 미추출로 마지막 정적 검사 1건 실패; 고정 파일 추가 후 전체 재실행 통과. 그 초기 실패를 제품 결함으로 세지 않음.

## 차단 사유 — 재현 명령 · 기대/실제

- H1(K2, ft-proxy-decide.sh push_merge_check): `python3 /tmp/da-autocore/diag3.py`의 DA 사례 → 기대 QUEUE; 실제 PROXY rc0. 문서 머리는 `DA HOLD — 1건`, 고정 SHA는 별도 줄, 과거 결과는 `이전 결과: APPROVE <동일SHA>`, 현재 판정은 별도 `현재 판정 HOLD`. grep이 SHA와 함께 있는 과거 APPROVE만 취하고 현재 HOLD를 못 읽음. 현재 최종 판정과 그 대상 SHA를 구조적으로 결속하고 모순/불명확은 QUEUE로 처리해야 함. 제목/고정 SHA가 분리된 일반 DA 문서 구성 안의 fixture이며 실제 원격 merge 아님.
- H2(K3, card_check): `python3 /tmp/da-autocore/diag3.py`의 card 사례 → 기대 QUEUE; 실제 PROXY rc0. 판정100=`(오빠) foo-card 착수 보류`, 카드 본문은 평범한 작업. 현재 검사는 이름+착수 낱말만 보아 보류를 승인으로 오독. 설계 r3의 «착수를 허락하는 낱말»·불명확 QUEUE와 충돌. 승인/보류/금지의 상태를 확인하며 허락을 확인하지 못하면 QUEUE로 처리해야 함.
- H3(K5, PROXY append): `python3 /tmp/da-autocore/diag3.py`의 readonly ledger 사례 → 기대 기록 실패에 PROXY 금지; 실제 Permission denied·원장 새 줄0인데 PROXY 판정103/rc0. 정상 파일 경로의 원장을 chmod444로 만들었고 테스트 뒤 복원. 파일 대신 디렉터리 인자도 같은 증상이나 주 근거는 정상 파일의 쓰기 실패. 원장 쓰기 성공을 검사한 뒤에만 PROXY를 반환하고, 큐/SEEN 쓰기도 실패를 숨기지 않아야 함.
- H4(K2, bounded): `python3 /tmp/da-autocore/diag4.py` → 기대 첫 시도 7초 초과 응답 폐기/재시도 후 QUEUE; 실제 9.36초 뒤 PROXY rc0. gh view 대역은 TERM을 무시하고 9초 후 일치 SHA를 반환, checks 대역은 즉시 pass. watchdog은 TERM 한 번만 보내고 wait하며, 늦게 종료한 프로세스의 rc0을 성공으로 채택함. 7초 deadline을 별도 판정하고 초과 출력은 폐기하며 해당 호출의 종료를 확실히 제한해야 함. 호출 대역은 스스로 9초에 끝나므로 영구 프로세스/외부 호출 0.

증거: `/tmp/da-autocore`(고정 소스·diag3.py·diag4.py), `/tmp/da-autocore-test2.log`, `/tmp/da-autocore-diag3.log`, `/tmp/da-autocore-diag4.log`. 위 반례는 고정 구현 실행과 구성 입력으로 재현한 fixture이며 운영 E2E/실 인간 판정/실 GitHub 집행 증거가 아니다.
이번은 구현 단위 초기 HOLD. 네 사유를 함께 회신하며 독립 사유를 순차 발굴하는 추가 probe는 중단. 교정 시 동일 단위 교정 1회·잔여 시간과 두 번째 HOLD 종료 규칙 적용. 이전 설계 DA의 중단을 재개한 판정이 아니라, 사용자 컨펌 뒤 발주된 구현 세트 검증이다.

대상 카드: r-autonomy-core
