# DA 요청 — mbox-sh-split-200 최종 DA(완성 이동 · 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료 → arch 서명) (arch#21 · 2026-10-09)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: C(통신 진입점을 200줄 규칙 안으로 — 통신 도구를 고치는 카드가 한도에 걸려 반송되지 않게).

## 고정 대상
- 커밋 `b5707adfca92bc6242c68e266fbf5dabd5ba923f`(브랜치 `nano/mbox-sh-split-200` · base origin/main `78f8c0c739` · 2커밋: `378111e2e1` [structure] · `b5707adfca` [docs]) · 6파일 +130 −121: `tools/comm-canonical/mbox.sh`(242→127 · 10–127행 → 빈 줄 + 주석 + `source "$DIR/mbox_doorbell.sh"`) · 새 `tools/comm-canonical/mbox_doorbell.sh`(120 = 머리 3줄 + 옛 11–127행) · `check-drift.sh` MAP(`mbox.sh` 행 → 라이브 `.fable-team/comm/mbox.sh` · `mbox_doorbell.sh` 행 추가) · `README.md` 복구 줄 +2 · 시험 사본 cp 3곳(`test_inbox.sh` 163 · `test_mbox_inbox_notify_reply_rate.sh` 17·139).
- 카드 `design/teams/harness/indices/진행/mbox-sh-split-200.md`(또는 대기/).

## arch#21 독립 재현 (b5707adfca 아카이브 · 실제 좌석 쪽지 0)
- 도우미 본문 diff 0(옛 11–127행) · 진입점 머리 1–9행 diff 0 · 진입점 source 뒤(13행~) = 옛 128행~ diff 0 · 두 파일 `bash -n` · 실행 비트 둘 다 O.
- 시험 3종 rc=0(notify_reply_rate · inbox · reply_exempt_cap).
- 분리 전(origin/main)·후 같은 9시나리오(send · send --no-notify · 이름 거부 · relay · peek · recv · ring 이름 거부 · ring 없는 세션 · 모르는 명령) stdout+stderr+rc diff = relay 전문 파일 이름의 시각 1초뿐.
- 도우미 없는 폴더 `mbox.sh peek` = rc=1 + stderr 에 `mbox_doorbell.sh`.
- shellcheck: 진입점 단독 = SC1091×2·SC2034×2(source 를 안 따라가서) · `shellcheck -x mbox.sh` = 0 · 도우미 단독 0 · 옛 판 0 → arch 판단: «source 를 따라간 기준» 새 경고 0 (disable 주석 안 넣음).
- check-drift(라이브 `.fable-team` 연결 사본): `mbox.py` SAME · `mbox.sh` DRIFT(라이브 = 분리 전) · `mbox_doorbell.sh` MISSING_RUNTIME — 설치 전 기대값과 같음.

## 질문 (bounded · 새 요구 금지)
- **Q1 동작 동일**: 함수 4개를 source 로 옮긴 뒤 `set -euo pipefail` 아래 전역(`DIR`·`SELF`·`MBOXPY`·`TMPDIR`)·`local`·반환코드·`doorbell_status` 의 실패 흡수가 분리 전과 같은가.
- **Q2 경로·실패**: `source "$DIR/mbox_doorbell.sh"` 가 라이브·정본·시험 사본에서 맞는 파일을 고르는가 · 없으면 크게 실패(rc≠0)하고 큐 쓰기 전에 멈추는가(반쯤 보내고 실패 보고 0).
- **Q3 사본 누락**: mbox.sh 를 «혼자» 복사하는 곳이 시험·README·drift·키트(scripts/harness-install)·슬랙 미러에 남는가.
- 범위 밖: 라이브 설치 절차(master · 카드 «랜딩 뒤 라이브 설치» 절) · check-drift MAP 의 나머지 옛 경로 행 · mbox.py.

## 판정문
`design/teams/harness/DA-mbox-sh-split-200-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.
