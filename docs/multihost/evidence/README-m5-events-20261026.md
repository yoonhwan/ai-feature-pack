# M5 증거 2장 — flag-off vs dev 레인 이벤트 스트림 (2026-10-26)

mini 격리 Redis(38311)의 `v5:session:<sid>:events:stream` 을 읽기 전용 XRANGE 로 뜬 원본(쓰기 0). 같은 코드 BYZ main `3c250223d1`, worker 레인만 다름.

| 파일 | 회차 | 레인 | 러너 | press_contexts released | segment.confirmed segment_id |
|---|---|---|---|---|---|
| m5-events-flagoff-20261026-1144.txt | 11:44 | flag-off(기본) | host_empty ok=0/1 | 스냅샷 10건 전부 false | 2종(해시형 931dcf12.. + psid형 v5_cd1c86..:ptt:..) |
| m5-events-dev-20261026-1302.txt | 13:02 | dev(WORKER_LANE=dev) | ok=1/1 cer 0 | 11건 중 마지막 2건 true | 1종(해시형 108bbde0..) |

v65 arch#313 확정(쪽지 169295): flag-off 말풍선 0 = 제품 결함(M5) · release legacy 경로(authority port_absent)가 owner 창을 닫지 않음 + 확정 segment_id 이중. 러너·FE 회귀 아님. 카드는 v65 정지 해제 뒤 작성, 착지 뒤 확인 시험 = flag-off 레인 h191 1회(released true · segment_id 1종 · ok 1/1).

읽는 법: 각 항목은 `<id>` 줄, `event` 줄, JSON 줄 순서(redis-cli --raw).
