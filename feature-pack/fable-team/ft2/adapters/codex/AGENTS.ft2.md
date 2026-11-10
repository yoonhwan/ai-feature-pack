# ft2 codex 좌석 지침 (호환 층 · 새 기능 0)

codex 좌석은 ft2 코어 동사를 «그대로» 부른다. 이 파일의 실행 줄 5개 밖에 돌리지 않는다.
코어 = `core/cli.py`(동사 1개 = stdout JSON 1줄 · rc = 계약값) · 진단 = `doctor/report.py`(읽기만).

## 부르는 법

1. 아래 실행 줄의 `<ROOT>`(작업 루트) · `<TEAM>`(팀 이름) · `<WORK>`(작업 이름) · `<HOLDER>`(좌석 이름) · `<GEN>`(실행권 세대)만 네 값으로 바꾼다.
2. 나머지 글자(동사·인자 이름·순서)는 고치지 않는다. 새 스크립트·래퍼·새 동사를 만들지 않는다.
3. stdout 은 JSON 1줄이다. 그 줄을 그대로 올린다. 요약·변형·추측 0.
4. rc=0 이면 그 줄은 성공이다. **rc≠0 이면 실패로 멈춘다** — 성공으로 감싸지 않고, 재시도하지 않고, rc 와 stdout 을 그대로 올린다.
5. 한 번 호출은 7초 안에 끝난다. 7초를 넘으면 그 줄은 실패다(재시도 0).

## 동사 4개 (이것만)

| 동사 | 필수 인자 | 하는 일 |
|---|---|---|
| claim | --work --holder | 실행권을 잡는다 |
| start | --work --holder --gen | 시작을 기록한다 |
| effect | --work --holder --gen --effect | 효과 1건을 기록한다 |
| result | --work --holder --gen | 결과를 낸다 |

```bash
python3 core/cli.py claim --root <ROOT> --team <TEAM> --work <WORK> --holder <HOLDER>
python3 core/cli.py start --root <ROOT> --team <TEAM> --work <WORK> --holder <HOLDER> --gen <GEN>
python3 core/cli.py effect --root <ROOT> --team <TEAM> --work <WORK> --holder <HOLDER> --gen <GEN> --effect <EFFECT>
python3 core/cli.py result --root <ROOT> --team <TEAM> --work <WORK> --holder <HOLDER> --gen <GEN>
```

## 진단 1개 (읽기만 · 쓰기 0)

```bash
python3 doctor/report.py --root <ROOT> --team <TEAM> --symptom-key <SYMPTOM_KEY> --install-sha <INSTALL_SHA> --evidence <SOURCE>=<REF> --owner <OWNER>
```

## 순서

claim → start → effect → result. 앞 줄이 rc≠0 이면 다음 줄로 가지 않는다.

## 하지 않는다

- 위 5줄 밖의 동사를 부르지 않는다(submit·assign·deliver·complete·reassess·recover·reclaim·project).
- 상주 프로세스·주기 폴링(cron·launchd·while 반복)·tmux 입력을 만들지 않는다.
- rc≠0 을 성공으로 감싸거나 stdout 을 손으로 고치지 않는다.
- 실패한 줄을 다른 동사로 대신하지 않는다.
