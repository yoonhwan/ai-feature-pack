# mbox-sh-split-200 최종 DA
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 b5707adfca · 기준 78f8c0c739 · 고정 Q1~Q3 · 라이브 설치 제외.

- Q1 APPROVE — 도우미의 머리3줄 제외 본문=이전11~127행, 진입점 머리1~9행 및 source 뒤 본문=이전128행~를 독립 대조해 동일을 확인했습니다. source는 같은 셸에서 함수만 정의하므로 DIR/SELF/MBOXPY·local/반환값·doorbell_status 실패 처리의 의미는 유지됩니다. 두 사본 bash-n rc0, 임시 Python peek 대역으로 helper 있는 진입 rc0을 확인했습니다.
- Q2 APPROVE — DIR은 진입점 BASH_SOURCE의 디렉터리 절대경로이며 helper를 같은 DIR에서 source합니다(mbox.sh:7-12). helper 없는 임시 폴더에서 peek은 rc1/stderr helper 이름, Python 대역 호출 0으로 큐 처리 이전 종료를 독립 확인했습니다. 정본/라이브/짝 시험 사본 모두 같은 상대 부속 경로입니다. 라이브 경로는 이번에 쓰지 않았습니다.
- Q3 APPROVE(분리 사본 범위) — 고정 SHA의 복사 호출을 대조해 시험3곳은 helper를 함께 복사하고 README 복구에도 pair가 있으며 drift MAP에 라이브 진입점+helper 두 행이 있습니다(test_inbox.sh:163, test_mbox_inbox_notify_reply_rate.sh:17, :139, check-drift.sh:27-28). 키트/미러는 별도 진입점 단독 복사 호출을 발견하지 못했습니다. 주의: README cp 나열은 진입점→helper인데 설명은 helper 먼저입니다(README.md:44-46). 라이브 설치/복구는 카드대로 helper 먼저 적용해야 하며 README 명령 순서 자체를 무중단 설치 증거로 쓰지 마십시오. MAP 나머지 옛 경로는 범위 밖입니다.

독립 검증은 본문/머리/꼬리 동치·bash-n·임시 peek Python 대역 및 missing helper 실패입니다. arch의 send/relay/recv/ring 9시나리오·시험3종·shellcheck 결과는 보고 증거로 구분합니다. 실제 좌석 메시지/doorbell/tmux·라이브 .fable-team/comm 쓰기·홈 설치 0. 구현 분리 승인과 master의 pair 라이브 설치·복구 순서는 구분합니다.

APPROVE
