# mbox 발신 규율 가드 리뷰 — 9611e78 (2026-09-02, ft-mbox-review)

대상: `feature-pack/fable-team/skill/scripts/ft-mbox.py` / `ft-mbox.sh` / `ft-tmux-send.sh`
방법: 격리 우편함(`FT_MBOX_DIR=<scratch>`)에서 19케이스 실측. 설치본(`~/.claude/skills/fable-team/scripts/`)은 소스와 SAME.
정상 확인: BODY_TOO_LONG·FANOUT·RATE_LIMIT·EMPTY_BODY 판정, DROPPED 카운트, relay 스냅샷·요약 공백 보존, 본문 개행 보존, `--force`가 본문 단어와 안 섞임.

## 결함 (심각도순)

### F1. RESEND_COOLDOWN이 «큐»가 아니라 «발신 기록»을 본다 — 소비된 뒤에도 300s 차단
- 실측 T4: `send → recv(소비) → 같은 본문 send` = `BLOCKED RESEND_COOLDOWN 0s<300s`. 큐는 비어 있는데 메시지는 「같은 본문은 이미 큐에 있다」.
- 커밋 메시지·주석은 "pending 동안 재발신 금지"인데 코드(`ft-mbox.py:141-147`)는 `.mbox-guard.json`의 마지막 발신 시각만 본다. 선언과 강제가 어긋난다.
- 실전 영향: 좌석이 같은 짧은 보고(예 `DONE`, `READ none 확인`)를 5분 안에 두 번 보내면 두 번째가 조용히 exit 3. 발신 측이 stderr를 안 읽으면 미발신인 채 「보냈다」가 된다(§1.05 실증과 같은 계열).
- 개선: 판정을 `_load(CANON)`에서 `from/to/hash` 일치 행이 **실제 pending**인지로 바꾼다. 소비됐으면 통과. 쿨다운은 pending일 때만 의미가 있다.

### F2. 해시가 앞 200자만 — 같은 헤더로 시작하는 다른 보고가 RESEND/FANOUT 오탐
- 실측 T6: 250자 동일 접두 + 다른 꼬리 → `RESEND_COOLDOWN`. T17: relay 요약 210자 동일 → 차단.
- 실전 영향: 보고 본문이 템플릿(`[TASK-03 결과] 4축: FE콘솔 … `)으로 시작하면 200자 안에서 갈리지 않는 경우가 흔하다. 다른 내용이 "같은 본문"으로 죽는다.
- 개선: `_body_hash`를 **전문** 해시로(`ft-mbox.py:116`). 본문이 이미 700자 상한이라 비용 없음.

### F3. `relay`에 `--force` 탈출구가 없고, 붙이면 요약 텍스트에 섞인다
- 실측 T14: `relay … "요약" --force` → 큐 본문이 `요약 --force`. T17: relay 재발신 차단 시 힌트는 「--force를 붙인다」인데 relay case(`ft-mbox.sh:88-101`)는 `--force`를 파싱하지 않아 힌트대로 해도 안 풀린다.
- 개선: relay case에 send와 동일한 `--force` 파싱 + py `relay()`에 force 인자 전달.

### F4. `.fable-team` 조상이 없으면 스크립트 디렉토리 «안»에 우편함을 만든다
- 실측 T16: `FT_MBOX_DIR` 미설정 + 스크립트가 `feature-pack/fable-team/skill/scripts/`에 있으면 `_repo_root`가 start를 반환 → CANON=`…/scripts/.fable-team/comm`. **이미 실물이 있다**: 그 경로에 09-01 01:59 `orch-test→dispatch-test-62808` 가드 기록 2건(gitignore로 가려져 안 보였을 뿐).
- 글로벌 설치본 `~/.claude/skills/fable-team/scripts/`도 같은 조건이라 거기서 직접 부르면 `~/.claude/skills/fable-team/scripts/.fable-team/comm`이 생긴다 — 프로젝트 우편함과 다른 곳.
- 개선: `.fable-team` 조상을 못 찾고 env도 없으면 **fail-loud**(`NO_MAILBOX_ROOT: FT_MBOX_DIR 를 지정하라`, exit 2). 조용히 엉뚱한 곳에 쓰는 것이 08-25 「셋으로 갈라진 우편함」과 같은 클래스.

### F5. `ft-tmux-send.sh`의 상시 `--force`가 doorbell 3s 억제까지 푼다
- `ft-mbox.sh:78` `--force → dbf=1`. 발주 shim이 항상 `--force`라(`ft-tmux-send.sh:41,43`) 오케의 연속 발주는 매 건 doorbell 주입 → 09-01에 잡은 「사용자 터미널 입력 막힘」 기제가 발주 경로에서 되살아난다.
- 또 `--force`는 EMPTY_BODY·RATE·FANOUT까지 전부 우회한다(T10: 빈 본문 큐잉 성공). 발주가 막히면 안 된다는 취지는 맞지만 «길이 상한만» 풀면 되는 일에 전부를 풀었다.
- 개선: 별도 플래그 `--dispatch`(발주): BODY_TOO_LONG·RESEND만 면제, EMPTY_BODY·RATE·FANOUT은 유지, doorbell 억제도 유지. `--force`는 사람이 명시할 때만.

### F6. 가드 판정이 잠금 밖 — 동시 send는 서로를 못 본다
- `send()`에서 `_guard_verdict`는 `_locked` 진입 전(`ft-mbox.py:166`). 두 프로세스가 동시에 같은 본문을 보내면 둘 다 기록 전 판정을 받아 둘 다 통과(T19는 force라 재현 확정은 아님 — 구조상 성립).
- 개선: 판정을 `op()` 안으로 옮긴다. 잠금 획득 수는 늘지 않는다(주석의 우려와 무관).

### F7. 테스트 0건
- `feature-pack/fable-team/test/verify.md`에 mbox 언급 0. 가드는 물리 강제인데 회귀 검증이 없어 F1~F3 같은 오탐이 실전에서만 드러난다.
- 개선: `test/mbox-guard.sh` — 위 T1~T19를 격리 우편함으로 돌리는 bash 스크립트(rc 기대값 비교). `verify.sh`가 있으면 거기서 호출.

## 권고 순서
F1·F2·F3 (오탐으로 «보고가 조용히 죽는» 것) → F4 (경로 fail-loud) → F5 (발주 플래그 분리) → F7 테스트 → F6.
전부 `ft-mbox.py`·`ft-mbox.sh`·`ft-tmux-send.sh` 3파일, 합쳐 ~60줄. 구조 변경 없음.
