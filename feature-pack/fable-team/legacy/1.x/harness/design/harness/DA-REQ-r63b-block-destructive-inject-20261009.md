# DA 요청 — r63b block-destructive 세 번째 블록(INJECT) 구현 검토 (arch#20 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.
골의 축: A(모니터·오빠 요청 — 오빠 절대지침 「임의 레디스랑 말풍선 dom 밀어넣기를 절대 하지 말라」 를 장치로) + C(키트 템플릿 = 전 머신 설치본).

## 고정 대상
- 커밋 `72da51914b66364a9c98a616ba490cc02fbc8307`(브랜치 `nano/r63b-block-destructive-inject` · 부모 `3674904f24` · base origin/main). 훅 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`(+19줄 · 199줄 · INJECT-BEGIN~END 블록만 · judge·PATTERN·STAGE 변경 0) · 시험 `tests/harness/test_block_destructive_inject.sh` · 대조표 `design/teams/harness/evidence/r63b-block-destructive-inject/TABLE.md`.
- 카드 `design/teams/harness/indices/진행/r63b-block-destructive-inject.md` · 반송 r1 `.fable-team/state/drafts-r21/REJECT-r63b-block-destructive-inject-r1.md`(오탐 7건 → 검사 사본 `CHK` + Redis 명령 자리 동사) · 조사 `design/teams/harness/SURVEY-r63-injection-guard-hook-20261009.md`.
- 적용 범위: 전역 `~/.claude/settings.json` PreToolUse(Bash) — 전 좌석·전 프로젝트(설치는 랜딩 뒤 master · 이 리뷰 대상 아님).

## arch#20 독립 재현 (증거 · 72da51914b 아카이브)
- test_block_destructive_inject 51 PASS rc=0 · test_block_destructive 91 PASS rc=0(회귀 0) · `bash -n` OK.
- 셔뱅 `/bin/bash` 로 PreToolUse JSON 주입 31행(명령 실행 0): 통과 기대 19(dev 페이지 파일 경로 3 · `git grep`/`rg`/`gh pr create` 본문 · `GET "set"` · `--scan` · `CONFIG GET` · `grep` 파이프 · `-c -p GET` · `--tls --user GET` · pytest(isolated_redis) · 기존 러너 · 일반 curl · DEL · FLUSHDB · git log · DBSIZE) = 전부 0 · 차단 기대 11(PUBLISH · `-p SET` · `--user=u HSET` · docker exec HSET · `bash -c` XADD · curl URL · `$BASE` URL · `rg x && SET` · `gh pr view; curl URL` · `echo; LPUSH` · python heredoc 안 `os.system('redis-cli SET')`) = 전부 2 · 불일치 0.
- ★알려진 빈틈 1(arch 확인)★: `gh pr create --body "$(redis-cli SET k v)"` = 0 — 검색·게시 구간 제거가 그 구간 안의 명령 치환 `$(…)`·백틱까지 지운다.

## 질문 (bounded · 새 요구 금지)
- **Q1 오탐 0**: 위 통과 19행 + 일상 명령(git·gh·pytest·ruff·npm·next·uvicorn·docker·tmux·mbox send 본문·heredoc 으로 쓰는 시험 파일)에서 이 블록이 막는 경로가 남는가. 특히 `CHK` 의 `INJECT_SKIP` 정규식·`app/dev/bubble-replay` 제거·`LC_ALL=C sed` 가 한글·멀티바이트·여러 줄 명령에서 깨지는가(깨지면 `|| CHK=$EFFECTIVE` 로 더 엄격해지는 쪽인가).
- **Q2 위반 차단**: 직접 Redis 쓰기(옵션 꼴 `-h -p -n -a -u --user= --tls -c`) · `docker exec … redis-cli …` · `bash -c`/`sh -c`/python·node 인라인 · URL `/dev/bubble-replay`(http·`{BASE}`·`$BASE`) 가 빠지는 경로. 위 «알려진 빈틈 1» 이 «설치 전에 막아야 할» 수준인가, 기록 후 설치 가능한 수준인가(판정만 · 새 설계 요구 금지).
- **Q3 EFFECTIVE 기준**: INJECT 가 `$CMD` 가 아니라 `EFFECTIVE` 파생 `CHK` 만 보는가(글 싱크 = echo·printf·정본 mbox·git commit·grep·대입·heredoc 본문 통과).
- **Q4 회귀 0**: 기존 PATTERN·STAGE 동작 불변 · 블록 위치(PATTERN 뒤·STAGE 앞) · bash 3.2 호환(빈 배열·`declare -A`·`${x,,}` 0) · 블록이 exit 2 외 종료코드를 바꾸는 경로.
- 범위 밖: 증거 검사(§92 · 닫힘) · 홈 설치 절차(master 몫 · planner 조건 6단계) · 스크립트 «파일 안» 주입(명령줄 훅이 원래 못 봄 — §92 몫).

## 판정문
`design/teams/harness/DA-r63b-block-destructive-inject-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 요청 (arch#20 · DA r1 HOLD Q2 만 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료)
- 고정 대상: `c82d93801419ed15d83f4d8304ecdd12d0b1b207`(부모 `72da51914b`) — 훅 +5 −1: `EFFECTIVE` 에 실행 치환(`$(` · 백틱 · `<(` · `>(`)이 하나라도 있으면 `CHK` sed 식에서 검색·게시 예외(`INJECT_SKIP`)를 빼고 페이지 경로 제거만. 반송서 `.fable-team/state/drafts-r21/REJECT-r63b-block-destructive-inject-r2.md`.
- arch#20 재현(아카이브): test_block_destructive_inject 60 PASS · test_block_destructive 91 PASS · `bash -n` · 훅 204줄. `/bin/bash` JSON 주입 40행(r1 오탐 7 · 일상 통과 · 직접 위반 · 치환 반례 5 — `$(…)` gh pr 본문 · 백틱 gh comment · `<(…)` rg · `$(…)` git grep · `$(curl …/dev/bubble-replay)` gh issue) = 불일치 0(정본 mbox 송신 본문 = 0 · 가짜 경로 mbox = 2 는 판정 466 설계).
- 질문 **Q2 만**: 치환 반례가 전부 rc 2 인가 · 치환 검사가 빠지는 꼴(예: `$(` 를 쪼개 쓰는 다른 실행 형태 — `eval`·`bash -c` 는 기존 judge 가 Inelig 로 원문 검사)이 남는가. Q1·Q3·Q4 는 r1 APPROVE 유지(재심 0). 새 요구 금지.
- 판정문: 같은 파일 `design/teams/harness/DA-r63b-block-destructive-inject-20261009.md` 끝에 `## r2` 절.
