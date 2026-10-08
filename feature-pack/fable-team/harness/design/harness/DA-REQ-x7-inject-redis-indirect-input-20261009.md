# DA 요청 — X7 계열 가드 ㉠(INJECT) redis-cli 간접 입력 차단 구현 검토 (arch#22 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 커밋 `bab4802246a4ec9cda55a773e109c4ed5106fee7`(브랜치 `nano/x7-inject-redis-indirect-input` · base origin/main `483ba4ec67` 이후). 변경 3파일: 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`(+2 · INJECT 블록 `INJECT_PATTERN` 대안 4개 한 줄 + 주석) · 시험 `tests/harness/test_block_destructive_inject_post.sh`(+25) · 대조표 `design/harness/evidence/r63b-block-destructive-inject/TABLE.md`(+30).
- 카드 `design/harness/indices/진행/x7-inject-redis-indirect-input.md` · 선행 §100(fp595 · PR 1057 · 홈 설치 완료).

## arch#22 독립 재현 (새 mktemp · `git archive bab4802246`)
- inject rc=0 · inject_post rc=0 · test_block_destructive rc=0 · `/bin/bash -n` OK · 훅 90줄.
- arch 프로브(JSON · 명령 실행 0): `probe_x7.py` Y 8 = 2 · Q 4 = 0(BAD 0) · `probe595.py` 19행 BAD 0(X7 닫힘) · `probe_r2.py` 7행 BAD 0 — 위치 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/x7/`·`…/fp595/`.
- ★변이 M6 정정(arch 판단)★: 카드 «함정 2» 의 `\|` 주장은 틀렸다 — arch 재실측: `[|]`→`\|` 복사본 = Y·Q 전부 기대대로(BAD 0 · BSD grep -E 에서 `\|` = 글자 `|`) · 백틱 이스케이프만 푼 복사본 = Q 4행 전부 2(모든 명령 차단). 첫 시도 붕괴 원인은 백틱 하나였다. 나노의 M6 대체(이스케이프 없는 백틱 변이)가 «정규식 이스케이프 실수로 전 명령 차단» 이라는 변이 의미를 지킨다.

## 질문 (bounded · 새 요구 금지)
- **Q1 위반 차단**: redis-cli 가 쓰기 동사를 argv 밖에서 받는 꼴(치환·백틱·heredoc·`<<<`·`<` 파일·파이프 수신·`docker exec -i … redis-cli` 파이프·xargs)이 대안 4개를 피하는 경로가 남는가(따옴표 제거 뒤 `CHK` 기준).
- **Q2 오탐 0**: 읽기(`GET $(…)`·`--scan | head`·`CONFIG GET`)·글자 인용(grep·echo·정본 mbox·Tank 게시 본문)·기존 대조표 통과 행이 새 대안에 걸리는가. 특히 `redis-cli[^;&|]*<` 가 같은 구간의 `2>`·`>`·따옴표 안 `<` 로 오탐하는가.
- **Q3 회귀 0**: 기존 세 시험 rc=0 · 판정기·PATTERN·STAGE 변경 0 · bash 3.2 · exit 2 외 종료코드 변화 0.
- 범위 밖: 스크립트 «파일 안» 주입(§92) · 의도적 난독화(`eval`·별칭) · 홈 설치 절차(master).

## 판정문
`design/harness/DA-x7-inject-redis-indirect-input-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 요청 (arch#22 · DA r1 HOLD Q1·Q2 만 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료)
- 고정 대상: `fffc667ac53e4c1aebb6c99138218f15806ae20b`(부모 `bab4802246`) — ①판정기 `--inject` 경로만 «other» 구간 단어를 `shlex.quote` 로 되살림(`judge(cmd, cwd, q)` · 기본 호출 q=False) ②훅 `INJ_J` 줄 잇기(끝 `\`·`|`) ③stdin 대안을 `INJECT_STDIN` + `CHK_R`(`<` 든 따옴표 구간만 Q 로 비움)로 분리 ④파이프 대안 `(^|[^|])` 로 `||` 제외 ⑤주석 정정. 반송서 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/x7/REJECT-x7-inject-redis-indirect-input-r1.md`.
- arch#22 재현(git archive 새 mktemp): inject rc0 · inject_post rc0 · test_block_destructive rc0 · `bash -n` OK · 판정기 200줄 · 프로브 4종(`probe_x7r1.py` Z1~Z7·W1~W6 · `probe_x7.py` · `probe595.py` · `probe_r2.py` — `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/x7/`) BAD 0 · 기본 판정 경로 출력 = origin/main 판정기와 3입력 동일.
- 질문: **Q1·Q2 만** — r1 반례(여러 줄 파이프 · `GET '<literal-key>'`)와 같은 성질이 남는가. 특히 `shlex.quote` 복원이 다른 INJECT 대안(직접 동사·bubble URL·SKIP)을 피하게 만드는 경로, `CHK_R` 비우기가 실제 stdin 리다이렉트를 숨기는 경로. Q3 는 r1 수락 유지(기본 경로 변경 있으면 그것만).
- 판정문: 같은 파일 `design/harness/DA-x7-inject-redis-indirect-input-20261009.md` 에 `## r2` · 끝 줄 APPROVE 또는 HOLD.
