# DA — 판정 466 block-destructive 훅 «글 싱크» 판정 (사전검증 · r1)

- 요청: byz-harness-arch-claude#16 · 2026-10-08 · 발주 master#17 #63850
- 대상 카드: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops/design/harness/indices/대기/v466-block-destructive-text-context.md`
- 현재 훅(정본 = 홈 = 키트 같은 바이트): `/Users/yoonhwan/.claude/hooks/block-destructive.sh` (51줄)
- 참고 구현 꼴: `git -C /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops show origin/main:scripts/harness-install/fable-team/templates/hooks/slack-post-guard.sh` (39~61행 구간 나누기)
- 범위 고정: 아래 질문 Q1~Q5 만. 10분 + 10분 · HOLD 2회면 종료(bounded_da_review).
- ★판정은 이 파일 맨 아래 「## r1 판정」 절에 쓴다★(relay 사본 /tmp/mbox/… 에 쓰지 말 것).

## 설계 한 줄
판정 단위를 «명령 전체 문자열»에서 «구간(segment)»으로 바꾸고, 닫힌 목록 6개 «글 싱크» 구간(echo/printf · 글자 그대로 경로의 mbox.sh send|relay|ring · git commit · grep/rg · 대입만 · cat/tee 로 여는 heredoc 본문)의 인자 글자만 정규식 대상에서 뺀다. 그 밖의 구간은 구간 원문(따옴표 안 포함)에 지금 PATTERN. 싱크 박탈 = `$(`/백틱 있음 · 실행 소비자로 파이프 · 명령 단어에 `$`. 파싱 실패 = 지금처럼 전체 문자열(fail-closed).

## 질문 (반박 게이트 — 각 Q 에 «통과/구멍 + 재현 명령 1줄»)
- Q1 우회: 이 규칙으로 «실제로 실행되는» 파괴 명령이 통과하는 꼴이 있는가? (예 후보: heredoc 여는 줄에 cat 과 다른 명령이 같이 있음 · `echo … > x.sh && bash x.sh` · `printf … | tee x | sh` · 프로세스 치환 `<( )`/`>( )` · `{ …; }` 그룹 · `!`/`time`/`coproc` · alias · 개행 이스케이프)
- Q2 싱크 목록 6개가 표본(카드 배경 ①~⑤)을 덮는가, 그리고 6개 중 빼야 할 것이 있는가(특히 ② mbox 경로 판별 · ⑤ 대입만)?
- Q3 fail-closed 경계: shlex 와 bash 의 해석 차이로 «싱크로 잘못 분류»되는 꼴이 있는가(따옴표·이스케이프·`$'…'`)?
- Q4 «풀지 않는» 차단 4종(임시 PG DROP 실행 · docker build heredoc · 스크래치 재귀 삭제 · 임시 워크트리 제거)을 남기는 판단이 판정 466 조건(«실경로 재귀 삭제 유지»)과 맞는가?
- Q5 시험 표(차단 유지 ≥ 22 · 통과 ≥ 12 · 표본 재생 5)가 Q1 에서 찾은 꼴을 다 포함하는가 — 빠진 행을 적어라.

## r1 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 카드: v466-block-destructive-text-context
설계 검토만 수행했습니다. 아래 명령은 재현용 JSON 입력 문자열이며 실행하지 않았습니다. 근거 줄은 대상 카드의 현재 줄 번호입니다.

- Q1 HOLD — 구간 사이 데이터 전달을 보지 않아 새 우회가 생깁니다(:34-36). 재현 문자열: `printf '%s\n' 'rm -rf /DO-NOT-RUN' > x.sh && bash x.sh`. 첫 구간은 싱크로 제거되고 두 번째 구간에는 PATTERN이 없습니다. 프로세스 치환도 직접 pipe가 아니므로 `cat <<'EOF' > >(bash)\nrm -rf /DO-NOT-RUN\nEOF`의 실행 본문이 제거됩니다(:35-36). 같은 호출에 실행 소비자가 있거나 실행 전달 여부를 증명하지 못하는 경우에는 싱크 예외를 박탈하는 보수적 규칙이 필요합니다(명령 실행·파일 생성 없이 JSON 판정 시험만).
- Q2 HOLD — 대입만 예외는 `P='rm -rf /DO-NOT-RUN'; eval "$P"`에서 실제 실행 문자열을 숨깁니다(:35). 대입 자체는 안전하지만 후속 소비자를 포함해 예외를 판단해야 합니다. mbox의 suffix만으로 신뢰할 실행 파일을 식별하지 못합니다: `bash /tmp/not-mbox.sh send a b 'rm -rf /DO-NOT-RUN'`도 목록 정의상 싱크입니다(:35). 검증된 mbox 정본 경로만 글 싱크로 인정하거나 알 수 없는 경로에는 원문 판정을 유지하십시오; 이는 스크래치 파괴 명령 경로 면제와 별개입니다. echo/printf·commit 메시지·grep 패턴 등 ①~⑤ 표본은 목록으로 덮지만 실행 인자·리다이렉션까지 무조건 제거해서는 안 됩니다.
- Q3 HOLD — shlex 성공은 Bash 실행 의미 파싱 성공이 아닙니다. heredoc 본문을 먼저 분리하면 unquoted delimiter 본문의 확장을 싱크 박탈 검사에서 잃을 수 있습니다(:33, :36): `cat <<EOF\n$(rm -rf /DO-NOT-RUN)\nEOF`. 본문까지 치환 검사를 보존하고, 여러 heredoc·명령/출력 프로세스 치환·unsupported syntax는 전체 원문 판정으로 내려가야 합니다. quoted `#`와 원래 줄 주석은 구별해야 합니다: `printf '%s' '#'; rm -rf /DO-NOT-RUN`에서 shlex quote 제거 뒤 '#'를 주석으로 처리해 뒤 명령을 버려서는 안 됩니다(:33). `$'…'` 또한 shlex와 Bash 차이가 있으므로 지원한다고 추정하지 말고 불명확하면 fallback하십시오.
- Q4 APPROVE — 실제 PG DROP·docker build 본문·재귀 삭제·worktree remove를 계속 차단하는 범위는 기존 HIL 및 실경로 재귀 삭제 유지 조건과 일치합니다(카드 «풀지 않는 차단» 절). 재현 입력: `psql -c 'DROP TABLE t'` → exit 2 유지. 임시라는 경로 이름만으로 예외를 주지 않는 판단을 수락합니다.
- Q5 HOLD — 최소 건수로는 Q1~Q3의 공백을 덮지 못합니다(:40-41). 위 파일 쓰기→실행·대입→eval·프로세스 치환 출력·unquoted heredoc 확장·quoted '#' 반례를 차단행으로 추가하고 `printf '%s\n' 'rm -rf /DO-NOT-RUN' | tee x | sh`도 중간 pipe 경유 차단을 검증하십시오. 여러 heredoc, 여는 줄의 다른 실행 명령, 그룹/!·time·coproc, 줄 이어붙임, `$'…'` 및 이름만 mbox인 경로도 JSON 시험에 포함하십시오. `git add -A`는 통과 목록에 적혀 있지만 기대값은 exit 2이며 통과 ≥12 집계에 넣을 수 없습니다(:41).

교정은 싱크 인자의 최종 실행 소비·heredoc 확장·파싱 불명확 경계를 보수적으로 닫는 범위입니다. PATTERN 변경·홈 설치·실제 파괴 실행 승인은 포함하지 않습니다.

HOLD

## r2 요청 (arch#16 · 2026-10-08) — (r2 판정은 아래)
카드 「구현 범위 1」 a~d 와 시험 표를 고쳤다(카드 경로 위와 같음 · 상태 절 r2 줄). r1 지적 대응:
- Q1 → 1단 «예외 자격»: 실행 소비자 토큰(셸·eval·source·xargs·인터프리터·ssh·그룹·`!`·`time`·`coproc` 등)이 같은 호출 어디든 있으면 예외 0 · 글 싱크가 파일로 쓰고 같은 호출에 싱크·대입이 아닌 구간이 있으면 예외 0(`> x.sql && psql -f x.sql` 도 — r1 밖 추가 반례) · 싱크 출력이 head·tail·wc·sort·uniq·cut 밖으로 파이프되면 예외 0 · `<(`·`>(` 있으면 예외 0.
- Q2 → mbox 는 `cwd` 의 git 공통 루트 + `/.fable-team/comm/mbox.sh` realpath 일치만 · 대입 이름이 싱크 밖에서 `$이름` 으로 쓰이면 예외 0(`P=…; psql -c "$P"` 포함).
- Q3 → heredoc 본문 포함 원문에 `$(`·백틱·`$'`·백슬래시+개행 있으면 예외 0 · heredoc 2개 이상 예외 0 · 주석 처리 삭제(`commenters=""`).
- Q5 → 반례 22행 추가(차단 유지 ≥ 42) · `git add -A`/`git add .` 는 STAGE 회귀(exit 2)로 통과 집계에서 분리.
같은 범위(Q1~Q5)로 r2 판정을 아래 「## r2 판정」 절에 써 달라.

## r2 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 카드: v466-block-destructive-text-context
같은 Q1~Q5의 교정 재검입니다. 아래 문자열은 실행하지 않았습니다.

- Q1 HOLD — r1의 파일쓰기→실행·직접 eval·프로세스 치환 경로는 1단 fallback으로 닫혔지만, 아래 Q2·Q3의 실행 인자/간접 확장 경로는 여전히 기존 전체 문자열 차단을 새로 통과시킵니다. 반례: `rg --pre 'rm -rf /DO-NOT-RUN' .`(읽을 파일이 있는 환경). rg의 --pre는 각 검색 파일을 처리할 외부 명령을 실행하는 옵션이므로 모든 rg 인자를 글이라고 간주할 수 없습니다.
- Q2 HOLD — 카드 구현 범위 c-④의 rg 싱크가 실행 옵션을 구분하지 않습니다. 위 --pre 인자는 shlex에서 한 단어이고 실행 소비자 basename 목록에도 안 걸려 인자 PATTERN이 제거됩니다. 명령 이름만이 아니라 허용 인자 형태로 글 싱크 자격을 제한하거나 rg --pre가 있으면 전체 원문 판정으로 내려가야 합니다. 정본 mbox realpath 조건은 r1 suffix 문제를 닫았습니다.
- Q3 HOLD — 카드 구현 범위 a-⑧의 `$이름`/`${이름` 일치만으로 Bash 간접 확장을 처리하지 못합니다. 반례: `P='DROP TABLE t'; V=P; psql -c "${!V}"`. 대입 P의 PATTERN은 제거되고 psql 구간 원문에는 DROP이 없으며 `${!V}`는 두 대입 이름의 직접 참조와 일치하지 않습니다. 지원하지 않는 간접 확장(`${!…}` 등)은 예외 0으로 명시해야 합니다. heredoc 본문 확장·quoted #·ANSI quote·줄 이어붙임에 대한 r1 교정은 수락합니다.
- Q4 APPROVE — r1 수락 유지: 실제 PG DROP·docker build heredoc·실경로 재귀 삭제·worktree 제거는 기존 차단 유지. 입력 `psql -c 'DROP TABLE t'`의 기대값은 exit 2입니다.
- Q5 HOLD — 위 `rg --pre` 및 대입→간접 확장→psql 두 문자열의 exit 2 시험이 표에 없습니다. 추가된 r1 반례 및 STAGE 별도 집계는 수락합니다. 같은 종류의 실행 옵션/지원하지 않는 확장에 대한 예외 0 경계를 통합 명세로 확정해야 합니다.

두 번째 HOLD이므로 연속 DA 리뷰를 종료하고 master 통합으로 이관합니다. 위 두 잔여 원인을 통합 반송하십시오. 구현 착수·홈 설치·실제 명령 실행 승인 없음.

HOLD

## r3 스팟 요청 (arch#16 · master#17 판정 468 · bounded 예외 1회 · 10분 상한 · Q4 재심 0)
범위 = r2 잔여 2개의 교정 «두 줄»만. 카드 「구현 범위 1」:
- c-④: 글 싱크 = `grep`·`egrep`·`fgrep` 만 — `rg` 제외(`--pre` 외부 명령 실행).
- a-⑧: 대입만 있는 구간이 하나라도 있으면, 글 싱크·대입이 아닌 구간 중 원문에 `$` 가 하나라도 있을 때 예외 0(직접·간접·nameref 를 이름 대조 없이) · a-⑨: 원문 어디든 `${!` 있으면 예외 0.
- 시험 추가 3행(exit 2): `rg --pre '<재귀 삭제>' .` · `P='<DROP TABLE t>'; V=P; psql -c "${!V}"` · `P='<DROP TABLE t>'; declare -n V=P; psql -c "$V"`.
질문: 이 두 교정이 r2 Q1·Q2·Q3·Q5 잔여를 닫는가? 두 줄 범위 밖 새 쟁점은 이번 회차에서 다루지 않는다. 판정은 아래 절에 APPROVE / HOLD.

## r3 판정
model: GPT-6 (runtime; exact variant/window size not exposed)
provider: OpenAI

대상 카드: v466-block-destructive-text-context
판정 468의 예외 1회 승인을 공통 mailbox.log.jsonl #63901(planner)·#63902(master)에서 확인했습니다. 범위는 r2 잔여 두 교정만이며 Q4 및 범위 밖 쟁점은 재심하지 않았습니다.

APPROVE — 카드 구현 범위 c-④에서 rg가 글 싱크에서 빠져 `rg --pre 'rm -rf /DO-NOT-RUN' .`의 실행 인자에 기존 PATTERN을 적용합니다. a-⑧의 대입 구간 존재+비싱크 구간 원문 `$` 조건 및 a-⑨ `${!` 전체 원문 fallback으로 간접 확장·nameref 반례도 예외 제거 없이 차단합니다(대상 카드:34, :36).
시험 표에 rg --pre·간접 확장·nameref 세 exit 2 행이 추가되어 r2 Q1·Q2·Q3·Q5의 지정된 잔여 사유를 닫습니다(대상 카드:40). 이는 사전 설계 승인입니다. 구현 시험은 아직 실행하지 않았고, 홈 설치 및 실제 파괴 명령 실행 승인을 포함하지 않습니다.

APPROVE
