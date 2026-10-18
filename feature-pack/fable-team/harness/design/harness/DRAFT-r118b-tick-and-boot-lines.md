# 초안 — 뉴스 발행 연결 문장 두 줄 (R118b · 판정 1430) — 반영은 master (BOOT·planner 틱 정본은 나노가 직접 고치지 않는다)

## 1. planner 틱 문구에 붙일 줄 (planner 10분 틱 메시지 끝)
`초안(DRAFT-<시각>.md)이 새로 왔으면 다듬어 POLISHED-<같은 폴더·시각>.md 로 저장하고 bash scripts/fable-team-bin/ft-news-publish.sh <POLISHED> 로 발행 — 같은 내용이면 발행 0 이 정상이고 처리 기록은 그대로 남는다. 30분 넘게 처리 기록이 없으면 ft-tick 이 1통 보낸다.`

## 2. BOOT 16 (체크 크론) 뒤에 붙일 승계 줄 (planner 좌석 한정)
`planner 승계 좌석은 부팅 보고 직후 design/planner/news/ 에서 DRAFT-* 중 .fable-team/state/news-publish/processed.tsv 에 없는 것이 있는지 먼저 본다 — 있으면 그 초안부터 다듬어 발행한다(30분을 넘기면 ft-tick 이 대신 알린다).`

## 3. 08:00 매거진 예약 (master 판단 · plist 수정은 이 카드 밖)
`bash scripts/harness-install/slack-mirror/magazine_from_news.sh --publish` — 그날 08:00 직전 24시간 안의 마지막 POLISHED(커밋된 것)를 magazine_doc.py 원본으로 넘긴다. 없으면 «매거진 원본 없음» ERROR rc≠0(빈 매거진 0).
