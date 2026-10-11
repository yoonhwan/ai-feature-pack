# 인덱스: Tank 래퍼에 `label-create` 동사 — 저장소 라벨을 byz-tank 이름으로 만든다 (R68 · 판정 710 · arch#25)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 요청 원장 `design/harness/REQUEST-LEDGER.md` R68(issues master#7 #67842) · 동기 = 10-09 issues#8 가 security 라벨을 래퍼 밖 `gh label create` 로 손으로 만듦
- 상태: 대기
- 선행: 없음(판정 710 이 보류 해제)
- 시험 입력: 기존 `tests/harness/test_gh_as_tank.sh` 방식 — PATH 맨 앞 가짜 gh(호출 로그 · 응답·종료코드 env 로 조정) · 실 GitHub 호출 0 · 실 토큰 0
- 기준값(arch#25 실측 · origin/main): ①래퍼 `ft-gh-as-tank.sh` 190줄(★200줄 한도 직전★) · 두 추적 사본(`scripts/fable-team-bin/`·`scripts/harness-install/fable-team/bin/`) 바이트 동일 sha256 앞12 `193b451e3d3d` · 설치본 `.worktrees/v6-realtime-live/.fable-team/bin/ft-gh-as-tank.sh` 도 `193b451e3d3d` ②동사 = create·comment·comment-edit·label(Issue 에 붙이기만)·close·reopen·edit·pr-* — 저장소 라벨 «생성» 없음 ③가드 `gh-issue-author-guard.sh`(홈 설치본 = 추적 사본 `8564682ab2c7`)는 `gh label create …` 와 `gh api repos/<o>/<r>/labels -f …` 를 둘 다 통과시킴(실측 rc=0) → 지금 라벨 생성은 오빠 기본 로그인으로 나간다 ④comment-edit 위임 본체 `ft-gh-tank-comment-edit.sh`(62줄 · `80882f02d20a`)가 «래퍼는 인자 검증·토큰 주인 확인 → 본체는 `FT_TANK_TOK` env 로만 토큰» 선례.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 B / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」 — 행 = R68 · 오빠 값 = 판정 710(Issue 없음 → 판정서) · 반영 sha = 이 카드 랜딩 sha.
골의 축: B(개선요청 접수·협의) + C(도구 업그레이드·설치).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
모든 Issue 쓰기는 Tank 래퍼(`ft-gh-as-tank.sh`)로 byz-tank 계정 이름으로 나가야 하는데(오빠 계정으로 남지 않게), 래퍼에는 Issue 에 라벨을 «붙이는» 동사만 있고 저장소에 라벨을 «만드는» 동사가 없다. 그래서 새 팀 라벨(team:graphics)·security 라벨을 만들 때마다 좌석이 `gh label create` 를 직접 쳐서 오빠 계정으로 만들어졌다. 래퍼에 `label-create <이름> --color <6hex> [--description <설명>]` 동사를 넣는다. 래퍼가 이미 190줄이라 본체는 comment-edit 선례처럼 별 스크립트 `ft-gh-tank-label-create.sh` 로 빼고, 래퍼에는 인자 검증·dry-run 출력·위임 몇 줄만 더한다. ★이미 있는 라벨은 «바꾸지 않고» 있다고만 알린다★(멱등 · exit 0) — 색·설명을 덮어쓰는 동작은 만들지 않는다. 존재 확인은 `gh label list`(기본 30개 제한 — issues#7 #68455 실측 함정) 대신 이름으로 한 건 조회한다.

## 사전검증
- 소환: 아니오 · 면제: 기존 래퍼 위임 패턴(comment-edit) 복제 · 쓰기 대상 = 저장소 라벨 1건 생성(삭제·수정 동작 0 · 되돌림 = 사람이 라벨 삭제) — arch 서명 byz-harness-arch-claude#25
- 조사 근거: `scripts/fable-team-bin/ft-gh-as-tank.sh:34` · `scripts/fable-team-bin/ft-gh-as-tank.sh:73` · `scripts/fable-team-bin/ft-gh-as-tank.sh:138` · `scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh:4`
- 7초 룰 점검(판정 666): 외부 호출 2곳(라벨 조회 GET · 생성 POST) — 각 1회 7 s(`timeout 7 gh api …`) · 재시도 1(시간 초과·5xx 만) · 600/300 s 0.

## 설계 (닫힌 목록)
1. 래퍼(두 추적 사본 바이트 동일 유지): 머리 주석 동작 목록 1줄 · `usage()` 동사 목록에 `label-create` · `case` 에 `label-create)` 분기 — 인자 검증만: 이름 1~50자 · 쉼표·줄바꿈 0 · `--color` 필수 `^[0-9a-fA-F]{6}$`(앞 `#` 금지) · `--description` 선택 0~100자 · 그 밖 인자 = exit 2. dry-run = `DRY as=byz-tank label-create <이름> color=<hex> desc=<있음|없음>` 1줄 · exit 0. `--apply` = 기존 토큰·주인 확인(`gh api user` = byz-tank) 통과 뒤 `FT_TANK_TOK="$TOK" bash "$HERE/ft-gh-tank-label-create.sh" <이름> <hex> [<설명>]` 위임 · exit 그대로. ★래퍼 총 줄 수 ≤ 200★.
2. 새 본체 `ft-gh-tank-label-create.sh`(두 폴더에 바이트 동일 사본 · ≤ 80줄): 토큰은 env `FT_TANK_TOK` 로만(없으면 exit 2 · 인자·출력 0 · 오빠 계정 폴백 0). 순서 ⓐ`timeout 7 gh api repos/$REPO/labels/<URL 인코딩 이름>` — 200 이면 `EXISTS as=byz-tank label <이름> color=<현재 hex>` · 생성 시도 0 · exit 0 / «HTTP 404» 면 ⓑ로 / 403·401 = `REJECT 권한 없음(HTTP 403) — Tank 토큰 Issues 쓰기 권한 확인` exit 1 / 그 밖 = REJECT exit 1 ⓑ`timeout 7 gh api -X POST repos/$REPO/labels -f name=… -f color=… [-f description=…]` — 성공 = `OK as=byz-tank label-create <이름> — <html_url 또는 api url>` exit 0 / «HTTP 422»(사이에 남이 만듦) = ⓐ 한 번 더 조회해 EXISTS 로 보고 exit 0 / 403·401 = 위와 같은 REJECT exit 1 ⓒ재시도 = 시간 초과(rc 124)·5xx 에 한해 1회.
3. 가드·홈 훅 변경 0 · 라벨 수정·삭제 동사 0.

## 구현 범위 (닫힌 목록 · 나노)
기존 파일(수정): `scripts/fable-team-bin/ft-gh-as-tank.sh` · `scripts/harness-install/fable-team/bin/ft-gh-as-tank.sh`. 새 파일: scripts/fable-team-bin/ft-gh-tank-label-create.sh · scripts/harness-install/fable-team/bin/ft-gh-tank-label-create.sh · tests/harness/test_gh_tank_label_create.sh.
시험(가짜 gh · 실 호출 0 · 시험 토큰 문자열이 stdout·stderr 에 0): ①**만들기** — 조회 404 → POST 1회 · 인자에 name·color·description · OK 줄 · rc 0 ②**이미 있음** — 조회 200 → POST 0회 · EXISTS 줄 · rc 0 (+ POST 422 경합 → 재조회 → EXISTS · rc 0) ③**권한 없음** — 조회 또는 POST 403 → REJECT 권한 없음 · rc 1 · POST 이후 재시도 0 ④인자 검증 — 색 `#d73a4a`·5자리·이름 쉼표·51자 → rc 2 · gh 호출 0 ⑤dry-run → gh 호출 0 · DRY 줄 ⑥토큰 주인 ≠ byz-tank → rc 1 · 본체 호출 0 ⑦시간 초과 1회(가짜 gh 가 rc 124) → 재시도 1회 뒤 성공 · 2회 연속이면 REJECT rc 1 ⑧두 사본 쌍 `cmp` 동일 · 래퍼 `wc -l` ≤ 200 · `bash -n` 4파일 ⑨기존 `bash tests/harness/test_gh_as_tank.sh` 그대로 PASS.
커밋은 자기 브랜치, **push 금지**. **금지**: 실 `gh` 쓰기 호출 · 실 토큰 파일 읽기·출력(판정 676) · 가드·홈 `~/.claude/hooks` 수정 · 루트 `.fable-team/` 쓰기.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · 기존 tank 시험 rc=0 · arch 독립 재현.
- 카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_gh_tank_label_create.sh rc=0 · bash tests/harness/test_gh_as_tank.sh rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#25 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행(앞 단계 값이 다르면 멈추고 보고)★: PR → CI 확인 → 병합(별 명령) → 설치본 `.worktrees/v6-realtime-live/.fable-team/bin/ft-gh-as-tank.sh` cp 전 sha256 앞12 `193b451e3d3d` 확인(다르면 cp 0 · arch 반송) → 래퍼 + 새 본체 cp + cmp 2 → 설치 자리에서 `ft-gh-as-tank.sh label-create probe --color 000000` dry-run 1회(DRY 줄 · 실 호출 0) → issues master(현역 — `ft-harness-info.sh seats` 로 이름 확인)·issues#8 에 «라벨 생성은 이제 `ft-gh-as-tank.sh label-create <이름> --color <hex> [--description …] --apply`» 1줄 → 요청 원장 R68 닫힘.

## 상태
- base_sha: 82e2c58b070c37c72678424e5fa7a3080343d006 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#25 · 판정 710 · R68 래퍼·가드 실측).
- 정본 영향: 하네스 키트 래퍼 2 + 새 본체 2 · 설치본 2 · 홈 정본 0.
- 별 후보(착수 0 · 오빠 컨펌 필요): 가드가 `gh label create|edit|delete` · `gh api …/labels`(쓰기)도 막아 래퍼로만 가게 할지 — 홈 훅 변경이라 이 카드 범위 밖. 이 카드 랜딩 전에 막으면 라벨 생성 길이 없어진다(순서: 이 카드 → 가드 후보).
- 2026-10-09 14:35 — 대기→진행 · 좌석 byz-harness-nano-r68-tank-label-create#0

## 결과
- 세트: c4b3c05daad8c7d57bb49f5c951ae755ce71a6b8 · 시험: bash tests/harness/test_gh_tank_label_create.sh rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 하네스 Tank 래퍼 label-create 동사·시험만 (arch 재현 #69133 · 판정서 §114).
- 2026-10-09 14:42 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§114
