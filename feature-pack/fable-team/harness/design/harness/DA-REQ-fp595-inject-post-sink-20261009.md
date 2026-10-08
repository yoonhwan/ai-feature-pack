# DA 요청 — 판정 595 가드 ㉠(INJECT) 게시 싱크 보강 구현 검토 (arch#22 · 2026-10-09 · 구현 DA 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료)

## 골 원문 (3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 고정 대상
- 커밋 `e5588bb09644994b6061ee01b2fc27670ca3f2b2`(브랜치 `nano/fp595-inject-post-sink` · base origin/main). 변경 4파일: 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive-judge.py`(+53 · `--inject` 모드 · `inject_view`) · `…/hooks/block-destructive.sh`(INJECT 블록 `EFFECTIVE` → `INJ_SRC` 3곳 +1줄) · 시험 `tests/harness/test_block_destructive_inject_post.sh`(새 · 100줄) · 대조표 `design/harness/evidence/r63b-block-destructive-inject/TABLE.md`(+41).
- 카드 `design/harness/indices/진행/fp595-inject-post-sink.md`(설계 = «설계» 절 닫힌 목록).
- 배경: issues master#6 의 Tank 래퍼 코멘트 게시 명령(`cat > F <<'EOF'` 본문에 `/dev/bubble-replay` 인용 → `bash ft-gh-as-tank.sh comment 887 F --apply`)이 판정기 consumer(`bash`) 때문에 명령 전체 검사 → 차단(실제 주입 0). 홈 훅은 지금 ㉠ 블록이 원복돼 꺼져 있다.

## arch#22 독립 재현 (새 mktemp 폴더 · `git archive e5588bb096`)
- `test_block_destructive_inject.sh` rc=0 · `test_block_destructive_inject_post.sh` rc=0 · `test_block_destructive.sh` rc=0 · `/bin/bash -n` 훅 OK · 훅 88줄 · 판정기 176줄.
- arch 프로브(`/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/fp595/probe595.py <훅> blocked_0.txt` · JSON 주입 · 명령 실행 0) 19행: F(통과 기대) 7 = 전부 0 · X(차단 기대) 12 중 11 = 2 · ★X7 `redis-cli $(cat <<'EOF'`⏎`SET k v`⏎`EOF`⏎`)` = 0★ — 원 키트(origin/main)에서도 0 인 기존 빈틈(동사가 다음 줄 · `INJECT_REDIS` 가 못 봄), 이 커밋이 만든 것 아님.

## 질문 (bounded · 새 요구 금지)
- **Q1 실행 경로 미개방**: `inject_view` 가 본문을 빼는 조건(F1: heredoc 1개 · 구분자 따옴표 · `cat > F` · F 를 가리킬 수 있는 토큰(끝 이름·글롭)이 게시 싱크 본문 파일 자리에만 / F2: `"$(cat <<'D' … D)"` 가 `gh pr|issue create|comment|edit`·`git commit` 의 본문 옵션 값 · 본문 안 구분자 줄 0)을 통과하면서 같은 명령에서 Redis 쓰기·`/dev/bubble-replay` 가 «실행»되는 경로가 있는가. 예: F 를 다른 철자(상대경로·심링크·`$VAR`)로 실행 · 게시 래퍼 자리 오인 · F2 접두 구간 분리(`re.split(r"[;&|\n]")`) 오판 · 남은 텍스트에서 빠지는 글자.
- **Q2 오탐 0**: 카드 F 행 + 실사례 원문이 0 인가 · 일상 게시 꼴(`--body-file`·Tank `create|comment|edit|pr-comment|pr-create`·`git commit -F`·`-m "$(cat <<'EOF'…)"`)에서 이 블록이 막는 경로가 남는가.
- **Q3 기본 경로 불변**: 인자 2개 기본 호출(`judge "$CMD" "$INPUT"` → 파괴 PATTERN 용 `EFFECTIVE`)의 출력이 바뀌는 경로가 있는가 · `--inject` 실패 시 `INJ_SRC=$EFFECTIVE` 폴백이 원 동작과 같은가.
- **Q4 회귀 0**: 기존 두 시험 rc=0 · PATTERN·STAGE 변경 0 · bash 3.2 호환 · exit 2 외 종료코드 변화 0.
- X7 은 «설치 전에 막아야 할» 수준인가, 기록 후 설치 가능한 수준인가(판정만 · 새 설계 요구 금지).
- 범위 밖: 파괴 PATTERN 쪽 같은 꼴 오탐 · 스크립트 «파일 안» 주입(§92 증거 검사 몫) · 홈 설치 절차(master 몫).

## 판정문
`design/harness/DA-fp595-inject-post-sink-20261009.md` — 실행 헤더 `model:`/`provider:` 두 줄 · Q 별 APPROVE/HOLD + 근거 줄 · 끝 줄 APPROVE 또는 HOLD.

## r2 요청 (arch#22 · DA r1 HOLD Q1 만 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료)
- 고정 대상: `fdc6b3f36f8a39dff067b7da65ec97d1bc55952f`(부모 `e5588bb096`) — F1 은 heredoc 구간 밖 실행 소비 구간(첫 단어가 CONSUMERS·INTERP·경로·`$`)이 전부 «같은 명령 앞 `VAR=리터럴`/`export` 대입 해소 + 실행 스크립트 realpath ≠ realpath(F)» 로 증명될 때만 본문 제거 · 증명 불가 = Inelig. 반송서 `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/fp595/REJECT-fp595-inject-post-sink-r1.md`.
- 추가 행: X13 `bash "$RUNFILE"` · X14 심링크 other→F · X15 `R=F; bash $R` · X16 `$D/../tmp/c.md` · X17 `sudo bash` = 전부 2 · F1a(실사례) 0 유지 · 변이 M4(realpath 끔 → X14 FAIL · X15·X16 은 끝이름 검사와 이중 방어라 M4 단독으로 안 뒤집힘 — 나노 표 명시).
- arch#22 재현(git archive 새 mktemp): inject rc0 · inject_post rc0 · test_block_destructive rc0 · `bash -n` OK · 판정기 199줄 · 프로브 19행 BAD 1 = X7(master 판정 #67070: §100 명시 제한 + 설치 직후 별 카드 `design/harness/indices/대기/x7-inject-redis-indirect-input.md`).
- 질문: **Q1 만** — r1 반례 2종과 같은 성질(같은 명령 안에서 F 를 다른 철자로 실행)이 남는가. Q2~Q4 는 r1 APPROVE 유지(새 커밋이 기본 경로·셸 훅을 건드렸으면 그것만 지적). X7 은 판정 대상 아님(master 결정 완료).
- 판정문: 같은 파일 `design/harness/DA-fp595-inject-post-sink-20261009.md` 에 `## r2` 절 추가 · 끝 줄 APPROVE 또는 HOLD.
