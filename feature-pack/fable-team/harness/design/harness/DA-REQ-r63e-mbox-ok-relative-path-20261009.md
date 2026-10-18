# DA 요청 — r63e block-destructive `mbox_ok` 상대경로 정본 인정 구현 검토 (arch#20 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: C(배포·반영 — 측정 조작 차단 훅 재설치의 선행 = 정상 쪽지 오탐 0) + A(오빠 절대지침 장치).

## 고정 대상
- 커밋 `f94a4a5ebeea66c5141fc418447648482a321b5b`(브랜치 `nano/r63e-mbox-ok-relative-path` · base main `7826b70515`) · 3파일 +43 −19: 키트 템플릿 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`(`MOVE` 정규식 · `mbox_ok(path, cwd, moved)` · `classify(…, moved)` · `judge` 가 `bool(MOVE.search(cmd))` 전달 · 208줄) · `tests/harness/test_block_destructive.sh` · `tests/harness/test_block_destructive_inject.sh`.
- 카드 `design/teams/harness/indices/진행/r63e-mbox-ok-relative-path.md`(원장 R64 — r63b 설치 직후 상대경로 쪽지 본문 글자 오탐으로 원복).
- 판정 466 원칙: 정본 = «JSON cwd 의 git 공통 루트 + `/.fable-team/comm/mbox.sh`» realpath 일치만. 이 변경은 상대경로의 해석 기준(JSON cwd)만 더한다.

## arch#20 독립 재현 (증거 · f94a4a5ebe 아카이브)
- test_block_destructive 99 PASS rc=0 · test_block_destructive_inject 69 PASS rc=0 · `bash -n` OK.
- `/bin/bash` JSON 주입 15행(실제 워크트리 경로 · 명령 실행 0) 불일치 0:
  · 통과 5: R64 원 명령 꼴(JSON cwd=`.worktrees/harness-ops` · `bash ../../.fable-team/comm/mbox.sh send … 'redis-cli SET 금지 /dev/bubble-replay'`) · 같은 상대경로 + 파괴 명령 인용 본문 · 절대경로 + 같은 본문 · 루트 cwd + `.fable-team/comm/mbox.sh` · 평범한 본문.
  · 차단 10: `cd /tmp && …` · `(cd <tmp>; …)` · `pushd /tmp; …` · 다른 git 리포의 `.fable-team/comm/mbox.sh` 를 상대경로로 · 다른 곳 `mbox.sh` 를 상대경로로 · `$D/../…`(변수) · 정본 송신 뒤 다른 구간의 실제 파괴 명령 · 절대경로 `..` · JSON `cwd` 없음 + 상대경로 · 정본 송신 뒤 `&& redis-cli SET`.

## 질문 (bounded · 새 요구 금지)
- **Q1 오탐 0**: 워크트리·루트 어디서든 상대경로로 정본을 부르는 쪽지(`../../`·`.fable-team/…`·심링크가 정본을 가리킴)가 글로 취급되는가.
- **Q2 우회 닫힘**: 상대경로 인정이 «정본이 아닌 스크립트에 본문 글자 면제»를 주는 경로가 남는가 — 실행 위치 이동(`cd`·`pushd`·`popd` · 서브셸 · `builtin cd`/`command cd`) · 다른 루트 · 심링크 · 변수·글롭 · JSON cwd 와 실제 셸 cwd 가 다를 수 있는 다른 꼴. `MOVE` 가 원문 전체(따옴표 안 포함)를 보는 «더 엄격한» 쪽인가.
- **Q3 회귀 0**: 절대경로 규칙(글자 그대로 · `..` 0) 불변 · 기존 시험 행 · 다른 싱크·PATTERN·STAGE·INJECT 판정 불변 · bash 3.2 셔뱅.
- 범위 밖: INJECT 블록(§93 닫힘) · 홈 설치 절차(master · §93 7단계 + R64 원 명령 재생).

## 판정문
`design/teams/harness/DA-r63e-mbox-ok-relative-path-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 요청 (arch#21 · 2026-10-09 · Q2 만 · bounded 10분 + 정정 10분 · 이번이 두 번째 · HOLD 면 리뷰 종료 → arch 서명)
- 고정 대상: 커밋 `01b915f91c193a2dcc8e1beeddcaf6539bed987b`(r1 `f94a4a5ebe` 위 1커밋 · 2파일 +4 −1). 훅 `judge`: `moved = bool(MOVE.search(re.sub(r"[\\'\"]", "", cmd)))` — 이동 판별만 따옴표·역슬래시를 지운 글자로. 시험 차단 2행: `c''d /tmp && bash ../../.fable-team/comm/mbox.sh send x y '<파괴 명령 인용>'` · `c\d /tmp && …`(JSON cwd = 하위 폴더 픽스처).
- arch#21 독립 재현(01b915f91c 아카이브 · 명령 실행 0):
  · test_block_destructive rc=0(blocked=71 pass=23 fail=0) · test_block_destructive_inject rc=0.
  · `/bin/bash` JSON 주입 21행 불일치 0 = r1 15행 + `c''d` · `c\d` · `"cd"` · `c$()d` · `c${NOPE}d` · `env -C /tmp bash ../../…mbox.sh …` 전부 rc2.
  · 변이(따옴표 제거 뺀 사본): `c''d` · `c\d` · `"cd"` 3행 rc0 으로 FAIL = 이 한 줄이 막는다. `c$()d` · `c${NOPE}d` · `env -C` 는 변이에서도 rc2(이 줄 아닌 기존 판정이 막음 — 의존 0).
- Q2(r2): r1 반례 2행과 같은 부류(인용·이스케이프·빈 확장으로 조립한 `cd`/`pushd`/`popd`)로 상대경로 정본 면제가 남는 꼴이 있는가. 새 요구 금지 · Q1·Q3 재심 0.
- 판정문: 같은 파일 `design/teams/harness/DA-r63e-mbox-ok-relative-path-20261009.md` 끝에 `# r63e 구현 DA — r2` 절 추가(헤더 `model:`/`provider:` 두 줄 · Q2 APPROVE/HOLD + 근거 · 끝 줄 APPROVE 또는 HOLD).
