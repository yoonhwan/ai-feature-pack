# 터널 전용 서비스 계정 키 장부 (비밀 0 — key_id 만)

| 호스트 | 서비스 계정 | key_id | 발급(UTC) | 상태 | 조치 |
|---|---|---|---|---|---|
| mini | byz-mini-tunnel | 42ec5f53069f6d1203b2aba070268672e1fd1d77 | 2026-10-22 09:09:26 | **미사용**(h3 rc=5 — 개인 부분은 실행 종료 때 삭제, 호스트 배치 0) | **폐기 대상(HIL)** |
| oci | byz-oci-tunnel | 36bea09d30d515d64cd0a68e17608d8733346be8 | 2026-10-22 09:09:27 | **미사용**(동일) | **폐기 대상(HIL)** |

폐기(오빠 승인 뒤): `gcloud iam service-accounts keys delete <key_id> --iam-account=<SA>@byz-agents-484214.iam.gserviceaccount.com --project=byz-agents-484214`
(원문 명령 줄은 훅 오탐을 피하려고 여기에만 적는다 — 실행은 HIL 묶음에서.)

h7(재실행)이 새 키를 SA 당 1개 발급한다 — 그 key_id 는 h7 출력의 «키 장부» 줄에서 이 표에 추가한다(교체 권장 90일).

## 결정 (오빠 · 상위 #3234)
- 옛 키 2개(위 표 폐기 대상)는 «h7 성공(새 키가 mini·OCI 에 배치된 것 확인) 뒤» 삭제한다. 삭제 h 는 폐기 대상 2개 key_id 만 지우도록 만들어 상위 점검 후 오빠께. h7 이 실패하면 지우지 않는다.
- 2026-10-22: 좌석 정리는 상위가 재개 기록(verdict 20261022-aifp3-close) 후 multihost#1·worker#2 를 닫음 — 되살림 zombie-clean.sh resume.

## 사용 중 키 (h7 rc=0 · 2026-10-22 13:48 UTC 발급 · 호스트 배치 0600)
| 호스트 | 서비스 계정 | key_id | 발급(UTC) | 교체 권장 |
|---|---|---|---|---|
| mini | byz-mini-tunnel | e07046b7c932931950bf4215197413f4ef4f0748 | 2026-10-22 13:48:03 | 2027-01-20 |
| oci | byz-oci-tunnel | d9db6b342a0cd926c0ee3056d865e30ee22f77e0 | 2026-10-22 13:48:07 | 2027-01-20 |

옛 키 폐기: `docs/multihost/h-plans/h-iap-old-keys-delete.sh` (DRY 통과 · 호스트 sa.json key_id == 위 사용 중 키 확인 후에만 지움).
