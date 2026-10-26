# r955 증거 — ops-intake 스크립트 키트 (하네스팀 몫 1/2)

카드: `design/harness/indices/진행/r955-ops-intake-scripts-kit.md` (BYZ-Agents harness-ops 워크트리)
브랜치: `nano/r955-ops-intake-scripts-kit` (팩) · base = origin/main `a1fccaf7`

## 무엇을 냈나

`kit/ops-intake/` 새 폴더 — write(ⓐⓑⓒ) · poster(ⓓ) · sync intake/status(ⓑ2ⓑ3ⓔ) · sat-mbox 이식(ⓕ) · plist 템플릿 3 · README 계약.
시험 = `tests/test_ops_intake.py`(19 cases) + `tests/test_ops_intake.sh` 러너(변이 6종 포함). 실 슬랙·실 gh·실 ssh·실 mini 호출 0.

## 시험 (2026-10-26 · 이 워크트리)

```
bash feature-pack/fable-team/harness/tests/test_ops_intake.sh      → ALL PASS (rc=0)
  py_compile 5/5 · plutil 3/3 · cases 19/19 · mutate 6/6
```

- `test-all.log` = 위 실행 전문.
- 변이 6종(ⓗ): mask-off → ⓑ / rescan-off → ⓑ2 / declared-off → ⓑ3 / guard-ts → ⓓ / ledger-off → ⓓ중복 / notice-off → ⓔ — 전부 «잡았다».

## 재사용한 정본 (규칙 복제 0)

| 축 | 정본 | 어떻게 |
|---|---|---|
| 비밀 마스킹 | `harness/bin/ft_secret_shapes.py` `mask()` | import 해서 그대로 호출. 모듈 없으면 rc2 «판정 불가» |
| 게시 문장 검사 | `kit/slack-mirror/post_guard.py` `SECRETS`·`INTERNAL` | 규칙표만 import(명부 판정은 mini 에 명부가 없어 «항상 사람 채널»). sha 꼴 +1줄 |
| 슬랙 호출 | `kit/slack-mirror/mirror_lib.post` | 7초 상한·재시도 1 그대로 |
| 쪽지 | `~/.claude/skills/fable-team/scripts/ft-mbox.{sh,py}` | send 는 sh, 읽기·ack 는 py 모듈(잠금·형식 복제 0) |
| pull 데몬 | 멀티호스트 가지 `docs/multihost/satellite/sat-mbox.py` | 이식(aifp #3335 승인) · 원본 그대로 보존 |

## 이식 조건(멀티호스트 팀 승인 aifp #3335) 반영

1. 내부 절대경로 기본값 제거 — `FT_MBOX_DIR`·`SAT_STATE` env → 리포 루트 추정 → 중단.
2. ssh 대상·hostname = `MINI` / `SAT_SSH`(argv 통째 교체 — 시험용).
3. 좌석 목록 파일 1개(`--seats-file` / `SAT_SEATS_FILE`) — pull 데몬 1개가 읽는다.
4. 쪽지함 큐 ≥10 이면 보내지 않고 로그 1줄(`PULL defer … 버리지 않음`), rc5.
5. 비밀·내부 식별자(프로젝트 ID·IP·계정) 코드·주석에 0.

## 시험 부작용 1건(정정 완료)

첫 시험판이 «목록 밖 좌석» 픽스처로 실 좌석 이름을 써서 그 좌석 창에 doorbell 1발이 갔다(aifp #3336 지적).
정정 = 시험 좌석명을 전부 가짜(`byz-opsintake-*`)로 · `FT_SEATS_JSON` 픽스처(tick 있음 = quiet) · `FT_MBOX_RATE_N` 상향. 이후 실행에서 실 좌석 doorbell 0.

## press 필요: 없음 (이 카드는 라이브 오디오 시험 없이 단위·캡처만)

라이브 확인이 필요한 축은 r956(h-A mini 설정 · h-B mini 설치 · h-C 이 맥 launchd)이다 — 이 카드 범위 밖.

## 남은 것(다음 카드)

- h-B 설치 목록(README §mini 설치) 그대로 실행 + `launchctl list` 확인.
- 시험 사용자 글 1건 → 이슈 #N → 상태 답 3게시가 «같은 스레드» 인지(기획 §7 합격 기준).
