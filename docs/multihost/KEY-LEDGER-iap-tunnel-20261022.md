# 터널 전용 서비스 계정 키 장부 (비밀 0 — key_id 만)

| 호스트 | 서비스 계정 | key_id | 발급(UTC) | 상태 | 조치 |
|---|---|---|---|---|---|
| mini | byz-mini-tunnel | 42ec5f53069f6d1203b2aba070268672e1fd1d77 | 2026-10-22 09:09:26 | **미사용**(h3 rc=5 — 개인 부분은 실행 종료 때 삭제, 호스트 배치 0) | **폐기 대상(HIL)** |
| oci | byz-oci-tunnel | 36bea09d30d515d64cd0a68e17608d8733346be8 | 2026-10-22 09:09:27 | **미사용**(동일) | **폐기 대상(HIL)** |

폐기(오빠 승인 뒤): `gcloud iam service-accounts keys delete <key_id> --iam-account=<SA>@byz-agents-484214.iam.gserviceaccount.com --project=byz-agents-484214`
(원문 명령 줄은 훅 오탐을 피하려고 여기에만 적는다 — 실행은 HIL 묶음에서.)

h7(재실행)이 새 키를 SA 당 1개 발급한다 — 그 key_id 는 h7 출력의 «키 장부» 줄에서 이 표에 추가한다(교체 권장 90일).
