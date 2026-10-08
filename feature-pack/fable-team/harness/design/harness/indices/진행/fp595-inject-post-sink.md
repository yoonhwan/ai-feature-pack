# 인덱스: 가드 ㉠(INJECT) 라이브 오탐 보강 — 게시 본문(heredoc → Tank 래퍼·gh·git commit)은 글자, 실행 경로는 계속 차단 (판정 595 · master#21 쪽지 #67033)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 595(master#21 · 홈 훅 ㉠ 원복 중 = 오빠 절대지침 가드가 지금 꺼져 있음 · 우선 높음)
- 상태: 대기
- 선행: 없음
- 시험 입력: 키트 훅에 PreToolUse JSON 만 넣어 종료코드를 본다(명령 실행 0 · 홈 훅 0)
- 기준값: origin/main 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` = 홈 원복 직전 백업 `~/.claude/hooks/block-destructive.sh.bak-fp595-20261009` (cmp 동일 · arch#22 실측). 실사례 원문을 그 키트 훅에 JSON 으로 넣으면 rc=2.
## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」.
골의 축: C(배포·반영 — 키트 = 전 머신 설치본 · 원복된 ㉠ 을 다시 켠다) + A(오빠 절대지침 「임의 레디스·말풍선 DOM 주입 금지」 장치 유지). 핵심 한 줄: 게시 본문에 금지어를 «인용»한 명령은 통과하고, 같은 글자를 «실행»하는 경로는 하나도 안 열린다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
전역 PreToolUse(Bash) 훅 `block-destructive.sh` 의 INJECT 블록(R63b · `# INJECT-BEGIN`~`END`)은 판정기 `block-destructive-judge.py` 가 만든 `EFFECTIVE`(글 싱크 글자를 뺀 명령)에서 Redis 쓰기·`/dev/bubble-replay` 를 찾는다. 판정기는 명령 어느 구간에든 `bash <스크립트>` 같은 실행 소비자가 있으면 예외 자격을 잃고 «명령 전체»를 돌려준다(fail-closed · 파괴 PATTERN 용 설계). 그래서 issues master#6 의 Issue 코멘트 게시 명령 — `cat > $SP/c887r.md <<'EOF'`(본문에 「앞 닫힘(/dev/bubble-replay 측정)은 무효」 인용) → `bash $SP/ft-gh-as-tank.sh comment 887 $SP/c887r.md --apply` — 이 `bash` 때문에 heredoc 본문까지 검사돼 차단됐다(실제 주입 0). GitHub 쓰기는 규약상 Tank 래퍼(`ft-gh-as-tank.sh`)로만 하므로 이 꼴은 매일 나온다. 이 카드는 ★INJECT 전용★으로 «게시 싱크 닫힌 목록»을 더해, 따옴표 heredoc 본문이 게시 본문으로만 쓰일 때 그 본문을 검사에서 뺀다. 파괴 PATTERN·STAGE 경로는 손대지 않는다.

## 사전검증
- 소환: 아니오 — arch#22 프로토타입 실측(아래 «조사 근거»)으로 설계 확정.
- 구현 DA: ★예 1회 · bounded 10분 + 정정 10분 · 2 HOLD 면 리뷰 종료★ — 전 좌석·전 프로젝트 Bash 훅(오탐 = 전 팀 마비, 미탐 = 오빠 절대지침 구멍). 질문 고정: Q1 대조표 X 행 전부 2(실행 경로 미개방) · Q2 F 행 전부 0 · Q3 기존 두 시험 회귀 0 · Q4 기본 판정 경로(`judge` 인자 없는 호출 = 파괴 PATTERN 용 `EFFECTIVE`) 바이트 불변.

## 설계 (닫힌 목록 — 이 밖은 전부 지금처럼 «실행» 취급)
판정기에 INJECT 전용 모드 `--inject` 를 더한다. 훅의 INJECT 블록만 그것을 쓴다:
`INJ_SRC=$(judge --inject "$CMD" "$INPUT" 2>/dev/null) || INJ_SRC=$EFFECTIVE` → 기존 `case "$EFFECTIVE"`·`CHK=…"$EFFECTIVE"`·`|| CHK=$EFFECTIVE` 세 곳을 `INJ_SRC` 로. 나머지 INJECT 로직(치환 있으면 SKIP 해제·따옴표 제거·패턴)은 그대로.
`--inject` 동작: ①기존 `judge()` 가 자격 있으면 그 결과 그대로 ②`Inelig` 이면 아래 두 꼴만 본문을 빼고 돌려준다 ③그 밖·예외 = 명령 전체(fail-closed).
- **F1 파일 경유**: 명령에 heredoc 정확히 1개(기존 `strip_heredoc` 재사용 · 2개 이상·미종결 = 전체) · 구분자 따옴표(`<<'D'`/`<<"D"` — 따옴표 없으면 본문 안 `$(…)` 가 실행되므로 전체) · 그 구간이 `cat > F`(출력 1개) · F 가 명령의 다른 모든 자리에서 «게시 싱크의 본문 파일 자리»에만 나온다. 반환 = 본문 뺀 명령(나머지 구간은 전부 검사 대상 그대로).
- **F2 치환 값**: `"$(cat <<'D'` … `D` `)"` 가 게시 싱크의 본문 옵션 값(`--body -b --title -t -m --message`)일 때만 그 `$(…)` 를 뺀다. 다른 `$(…)`·백틱이 남으면 기존 규칙대로 SKIP 해제(X10).
- **게시 싱크(닫힌 목록 · 늘리는 것도 판정 사항)**: `bash scripts/fable-team-bin/ft-gh-as-tank.sh <create|comment|comment-edit|pr-comment|pr-create> <인자> F`(본문파일 = 4번째 단어) · 같은 래퍼 `edit|pr-edit … --body-file F` · `gh pr|issue create|comment|edit --body-file F`/`-F F` · `git commit -F F`/`--file F`(F2 는 `-m`/`--message`).
- 참고 구현(arch 프로토타입 · 그대로 써도 되고 다듬어도 됨 · 판정기 174줄): `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/drafts-r22/fp595/proto-judge.py` · `proto-hook.sh` · 재현 `probe595.py <훅> blocked_0.txt`. ★다듬을 것★: `tee` 분기 삭제(`cat` 만) · 200줄 이하 유지.

## 조사 근거 (arch#22 실측 · origin/main 키트)
- 실사례 원문 = issues master#6 jsonl `1de82fc3…` 2026-10-08T20:11:33Z(사본 `drafts-r22/fp595/blocked_0.txt`).
- 키트: 대조 19행 중 BAD 7(F 행 6 + X7) · 프로토타입: BAD 1(X7 만) · 기존 `test_block_destructive_inject.sh` rc=0 · `test_block_destructive.sh` rc=0(프로토 훅 `BD_HOOK=` 지정).
- ★X7 = 기존 빈틈(이 카드 범위 밖)★: `redis-cli $(cat <<'EOF'` ⏎ `SET k v` … — 동사가 다음 줄이라 `INJECT_REDIS` 가 못 본다. 키트에서도 0. 별 카드 후보로 기록만.

## 구현 범위 (닫힌 목록)
1. 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive-judge.py` 에 `--inject` 모드(위 설계) · 인자 없는 기본 경로 출력 바이트 불변.
2. 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh` INJECT 블록의 `EFFECTIVE` 세 곳 → `INJ_SRC`(+1줄). PATTERN·STAGE·judge 기본 호출 변경 0.
3. 시험 `tests/harness/test_block_destructive_inject.sh` 에 아래 F·X 행 추가(200줄 넘으면 새 파일 `test_block_destructive_inject_post.sh`) + 변이 M3(`--inject` 가 F1 조건 «F 의 다른 자리» 검사를 건너뛰는 복사본 → X3·X12 FAIL).
4. 대조표 `design/harness/evidence/r63b-block-destructive-inject/TABLE.md` 에 F·X 행 추가(실제 rc 칸 = 시험 산출).
커밋은 자기 브랜치, **push 금지**. **금지**: 홈 `~/.claude/hooks/` 쓰기·settings.json 수정(설치 = master).

## 대조표 추가 행 (1행 = 1검사 · 명령 전문은 probe595.py · 표 안 임시 경로는 예시 글자)
| # | 명령 | 기대 |
|---|---|---|
| F1a | issues#6 실사례 원문(`cat > $SP/c887r.md <<'EOF'` … `bash $SP/ft-gh-as-tank.sh comment 887 $SP/c887r.md --apply` …) | 0 |
| F1b | `cat > ` tmp-c.md ` <<'EOF'`⏎`(/dev/bubble-replay) 무효`⏎`EOF`⏎`bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 887 ` tmp-c.md ` --apply` | 0 |
| F1c | 같은 본문(`redis-cli SET k v 금지`) → 래퍼 `edit 887 --body-file ` tmp-c.md ` --apply` | 0 |
| F1d | 같은 본문 → `gh pr create --title x --body-file ` tmp-b.md  | 0 |
| F2a | `gh issue comment 1 --body "$(cat <<'EOF'`⏎`/dev/bubble-replay 무효`⏎`EOF`⏎`)"` | 0 |
| F2b | `git commit -m "$(cat <<'EOF'`⏎`[docs] redis-cli SET k v 금지`⏎`EOF`⏎`)" -- a.md` | 0 |
| X1 | heredoc 파일에 `redis-cli SET k v` → `bash ` tmp-x.sh  | 2 |
| X2 | heredoc 파일 → `redis-cli < ` tmp-x.txt `; redis-cli SET k v` | 2 |
| X3 | 래퍼 comment 로 올리고 같은 파일을 `bash ` tmp-c.md  | 2 |
| X4 | 따옴표 없는 `<<EOF` 본문 → 래퍼 comment | 2 |
| X5 | heredoc 파일 `url = http://h/dev/bubble-replay` → `curl -K ` tmp-k `; bash x.sh` | 2 |
| X6 | `bash -c "$(cat <<'EOF'`⏎`redis-cli SET k v`⏎`EOF`⏎`)"` | 2 |
| X8 | `curl "$(cat <<'EOF'`⏎`http://h/dev/bubble-replay`⏎`EOF`⏎`)"` | 2 |
| X9 | 래퍼 comment 뒤 `; redis-cli SET k v` | 2 |
| X10 | `gh issue comment 1 --body "$(cat <<'EOF'`⏎`ok`⏎`EOF`⏎`)$(redis-cli SET k v)"` | 2 |
| X11 | `python3 - <<'EOF'`⏎`os.system('redis-cli SET k v')`⏎`EOF` | 2 |
| X12 | heredoc 파일 → `bash x.sh ` tmp-c.md (게시 싱크 아님) | 2 |

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 시험 rc=0(새 행 포함) · 기존 `tests/harness/test_block_destructive.sh` rc=0 · `bash -n` 훅 · 구현 DA 판정문 APPROVE.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive_inject.sh rc=0 · 이슈: 0` (+ 대조표 경로).
- 루트 지침(governance §9 · BOOT 19 · 판정 514·532): 완료 조건을 다 채운 «그 턴에» 증거 줄 기록 + master 에 머리 `[완료·휴식]` 1통 → 쉰다.
- ★랜딩 뒤 master 집행(카드 밖)★: ①홈 백업 `cp ~/.claude/hooks/block-destructive.sh{,.bak-fp595b-<날짜>}` + 판정기 동일 ②키트 두 파일 → 홈 cp+cmp ③`/bin/bash` 홈 설치본에 F1a·X1·B1·P6 JSON 재생 ④첫 도구 호출 실측 + 다른 좌석 1곳 ⑤오탐 1건이면 즉시 원복 + 원장 기록.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>`.

## 상태
- base_sha: 50bab46af2bbcbec4a3a19766070e7a351b5c776 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#22 · 판정 595 · master#21 쪽지 #67033).
- 정본 영향 없음: 하네스 훅 템플릿·시험·대조표만 — docs/architect 제품 정본 변경 없음.
- 2026-10-09 05:21 — 대기→진행 · 좌석 byz-harness-nano-fp595-inject-post-sink#0

## 결과 (나노 RESULT #67053 + r1·r2 반송 · arch#22 서명 · master#21 옮김 2026-10-09)
세트: 729cd6cdf348549bf3ed48271bf6182c183f7e73 · 시험: bash tests/harness/test_block_destructive_inject.sh rc=0 · 이슈: 0
정본 영향 없음: 하네스 훅 템플릿·시험·대조표만 — docs/architect 제품 정본 변경 없음.
