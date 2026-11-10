# 인덱스: block-destructive 훅 — «글자로만 들어 있는» 파괴 명령(쪽지 본문·echo·파일로 쓰는 heredoc·grep 패턴·변수 대입 — 같은 호출에 실행 소비자가 없을 때만)은 통과, «실행되는» 파괴 명령은 지금처럼 차단 (판정 466 · R28·R38·R39·R40 통합)
<!-- ledger: design/teams/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 466(master#17 발주 #63850 · R28·R38·R39·R40 누적 오탐 통합)
- 상태: 대기
- 선행: 사전 DA 1회(아래 「사전검증」) — APPROVE 전 착수 0 · origin/main 최신에서 브랜치
- 시험 입력: 훅에 넣는 PreToolUse JSON 문자열(가짜 `tool_input.command`)만 — 실제 명령 실행·삭제·kill·원격 쓰기 0
- 기준값: 홈 `~/.claude/hooks/block-destructive.sh`(정본 · 판정 343 «홈 = 정본, 키트 = 같은 바이트») = 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`(cmp 같음 · arch#16 확인 2026-10-08). 판정 = 명령 «전체 문자열»에 정규식 1개(`PATTERN`) → 따옴표 안·heredoc 본문·주석의 글자도 차단. 오늘(10-08) 기록된 오탐 ≥ 15건, 실제 파괴 0.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 / 닫는 증거(정본 복붙): 「REQUEST-LEDGER.md 행 + Issue 「채택/보류 + 오빠 값」 코멘트 + 반영 sha」.
골의 축: 6-b(메인·위성 오케 개선요청 접수 — CFO·loom·planner·harness 좌석 오탐 R28·R38·R39·R40) + C(반영 — 홈 훅 설치). 핵심 한 줄: 훅은 «실행되는 자리»의 글자만 보고, «남에게 보여 주는 글»의 글자는 보지 않는다.

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
`block-destructive.sh` 는 모든 세션의 Bash 호출 전에 돌며, 명령 문자열 전체에 `PATTERN` 정규식(서버 전체 종료 · 프로세스 일괄 종료 · 강제 종료 신호 · 브랜치 강제 삭제 · 강제 push · 재귀 강제 삭제 · DB DROP/TRUNCATE · dropdb · 클라우드/terraform/kubectl/supabase 삭제 · 워크트리 제거)을 대어 맞으면 exit 2 로 막는다. 그래서 «명령 글자를 담은 글»도 막힌다. 오늘 실측 표본(원문 = 아래 조사 근거): ①mbox send/relay 본문에 명령 이름을 인용(planner#8 · planner#10 · harness-master#12 · loom#1 2건 · CFO master #63611② · ops master #63848 류) ②오빠께 보일 문장을 echo 로 출력(loom#0) ③시험 파일을 `cat <<'EOF' > 파일` 로 만들 때 본문의 mktemp 정리 trap(R28 2회 · harness-master#11 relay 본문 파일) ④grep 패턴·변수 대입에 패턴 글자(arch#16 — 훅 패턴을 grep 하려다 차단) ⑤원장 행을 printf 로 쓸 때 본문 글자(R39 master 재현). 다섯 모두 «실행되지 않는 글자»다. 고치는 방법은 판정 단위를 «명령 전체»에서 «명령 구간(segment)»으로 바꾸고, 닫힌 목록의 «글 싱크(text sink)» 구간만 인자 글자를 보지 않는 것이다. 나머지 모든 구간은 지금과 똑같이 구간 원문(따옴표 안 포함)에 같은 정규식을 댄다 — 그래서 `bash -c "…"` · `psql -c "DROP …"` · `python3 -c "…"` · `eval` · `ssh` 처럼 문자열을 «실행»으로 넘기는 명령은 따옴표 안이어도 계속 막힌다. 파싱이 안 되면(따옴표 짝 불일치 등) 지금처럼 명령 전체에 정규식(fail-closed). 구간 나누기는 origin/main 의 키트 훅 slack-post-guard(판정 405 · `strip_heredocs`·`newlines_to_semicolons`·`segments` 39~61행 · ops/main-base 에는 없음 — `git show origin/main:scripts/harness-install/fable-team/templates/hooks/slack-post-guard.sh`)와 같은 꼴(shlex · `; && || | & ( )` · 개행 분리)을 이 훅 안에 그대로 둔다(훅 파일 하나 = 설치 단위 — 공용 lib 신설 0).

## 사전검증
- 소환: 예
- 사유: 전 세션 공통 안전 훅의 차단 범위를 줄이는 변경(되돌리기 쉬우나 놓친 우회 1개 = 실제 파괴 1건)이라 사전 DA 1회(판정 466 조건).
- DA: design/teams/harness/DA-block-destructive-466-20261008.md (byz-harness-da-codex#0 r1) — r1 HOLD(#63880) → r2 HOLD(#63894 · bounded 종료) → 판정 468(master#17 #63902 · 스팟 1회 예외) → r3 APPROVE(#63907 · 설계 승인만 — 구현 시험·홈 설치는 닫힘 판정에서).

## 조사 근거
- 키트 `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh:20` `PATTERN` · `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh:22` 차단 블록(~27행) · 29~51행 `git add` 전체 스테이징 차단(`STAGE_PATTERN` — 이 카드 무변경) · `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh:36` «정교하게 파싱하지 않는 이유»(판정기가 촘촘할수록 예외 목록이 자란다) — ★이 카드는 «예외 목록»이 아니라 «글 싱크 닫힌 목록 + 나머지 전부 지금 규칙»이고, 싱크 목록을 늘리는 것도 판정 사항으로 둔다(아래 금지).
- 오탐 기록: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/hil-falsepos.log`(10-08 행 7개) · `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/state/block-false-positives.log`(10-08 planner#10) · `design/teams/harness/REQUEST-LEDGER.md` R28·R38·R39·R40 행 · mbox #63116(loom#1 2건) · #63636(loom R9 나노).
- 이 카드가 «풀지 않는» 차단(실제 실행 — 지금처럼 HIL 또는 Write 도구 경로): R38 임시 PG 에 DROP 실제 실행 · R39 `docker build` heredoc 의 컨테이너 안 정리 줄(heredoc 이 cat/tee 가 아닌 명령에 들어감) · R40① 스크래치 폴더 재귀 삭제(실경로 재귀 삭제 — 판정 466 유지 목록) · loom 임시 detached 워크트리 제거. 텍스트로는 «임시 대상»을 증명할 수 없다.

## 구현 범위 (닫힌 목록 — 키트 사본만 고치고 홈 설치는 master)
1. `scripts/harness-install/fable-team/templates/hooks/block-destructive.sh`: `PATTERN` 판정 블록(22~27행)을 python3 판정기로 바꾼다. `PATTERN` 문자열·차단 메시지 3줄·exit 2·`STAGE_PATTERN` 블록 무변경. 규칙:
   - ★r2 = 2단 판정(DA r1 HOLD Q1·Q2·Q3 반영)★. «예외 0» = 명령 전체 문자열(heredoc 본문 포함)에 `PATTERN` — 지금 동작 그대로.
   - a. 1단 «예외 자격» — 아래 하나라도 해당하면 예외 0: ①원문 어디든(heredoc 본문 포함) `$(` · 백틱 · `<(` · `>(` · `$'` · 백슬래시+개행 ②heredoc 2개 이상 ③shlex 실패(ValueError)·python3 실행 실패 ④토큰(heredoc 본문 밖 · shlex 단어) 중 basename 이 실행 소비자 — `bash`·`sh`·`zsh`·`dash`·`ksh`·`fish`·`eval`·`source`·`.`·`exec`·`xargs`·`env`·`sudo`·`nohup`·`time`·`timeout`·`nice`·`watch`·`coproc`·`command`·`builtin`·`function`·`{`·`}`·`!`·`python`·`python3`·`perl`·`ruby`·`node`·`ssh` (유일한 예외 = 아래 c-② 정본 mbox 꼴의 `bash`) ⑤구간 첫 단어(명령 단어)에 `$` ⑥글 싱크 구간이 파일로 출력(`>`·`>>`·`>|`·`&>` — 대상이 `/dev/null`·`&N` 이면 제외 · 또는 명령 단어가 `tee`)하고 같은 명령에 «글 싱크·대입이 아닌» 구간이 하나라도 있음(파일 쓰기 → 같은 호출에서 소비: `… > x.sh && bash x.sh` · `… > x.sql && psql -f x.sql`) ⑦글 싱크 구간 출력이 `|` 로 이어지고 그 뒤 구간이 `head`·`tail`·`wc`·`sort`·`uniq`·`cut` 밖 ⑧(r3 · DA r2 Q3) 대입만 있는 구간이 하나라도 있는데, 글 싱크·대입이 아닌 구간 중 원문에 `$` 가 하나라도 있음(직접 `$이름`·간접 `${!V}`·nameref 를 이름 대조 없이 한 번에 닫는다) ⑨(r3) 원문 어디든 `${!` 가 있음.
   - b. 2단(1단 통과 시에만): heredoc 본문 분리 → 여는 줄 이하 개행→`;` → shlex(posix · punctuation_chars · `commenters=""` — ★주석 처리 없음★ · r1 Q3 quoted `#`)로 `; && || | & ( ) |&` 경계 구간. 구간 첫 단어 = 명령 단어. 글 싱크 구간이면 그 인자 글자를 정규식에서 빼고, 아니면 구간 원문(따옴표 안 포함)에 `PATTERN` — 맞으면 차단.
   - c. 글 싱크 닫힌 목록 6개: ① `echo` · `printf` ② 정본 mbox 송신 = `bash <경로> send|relay|ring …` 이고 `<경로>` 가 글자 그대로의 절대경로(변수·`..`·글롭 0)이며 그 realpath 가 «훅 입력 JSON `cwd` 에서 `git rev-parse --path-format=absolute --git-common-dir` 로 구한 루트 + `/.fable-team/comm/mbox.sh`» 의 realpath 와 같을 때만(이름 끝 일치 불인정 · r1 Q2) ③ `git commit`(인자) ④ `grep`·`egrep`·`fgrep`(인자 · ★r3: `rg` 제외 — `--pre` 가 외부 명령 실행 · DA r2 Q1·Q2 · 표본은 grep 뿐★) ⑤ 대입만 있는 구간(`NAME=값` 뒤 명령 단어 없음) ⑥ heredoc 본문 — 그 heredoc 을 여는 구간의 명령 단어가 `cat`·`tee` 일 때만. 그 밖의 명령(bash·python3·psql·docker…)에 들어가는 heredoc 본문은 정규식 대상.
   - d. 차단 메시지 3줄·exit 2 무변경(«예외 0» 이유 표시 추가 없음).
   - e. 파일 길이 180줄 이하(#3 RULE 아님 · 코드 지표) · 주석은 주변 밀도대로 — 위 「정교하게 파싱하지 않는 이유」 주석은 지우지 말고 «글 싱크 닫힌 목록으로 바꾼 이유(판정 466 · 오탐 표본)» 2줄을 덧붙인다.
2. 새 시험 `tests/harness/test_block_destructive.sh`: 키트 훅에 JSON 을 넣어 exit 코드만 본다(홈 훅·실제 명령 0). 표는 «차단 유지» ≥ 45 · «통과» ≥ 12 · STAGE 회귀 2:
   - 차단 유지(exit 2): 패턴 15종 각각 명령 자리(`tmux kill-server` · `pkill -f x` · `kill -9 1` · `git branch -D x` · `git push --force` · `git push -f origin x` · 재귀 강제 삭제 2꼴 · `dropdb x` · `psql -c "DROP TABLE t"` · `TRUNCATE TABLE` 를 psql 로 · `gcloud … delete` · `terraform destroy` · `kubectl delete` · `git worktree remove x` · supabase 삭제) + 우회 꼴(`bash -c "<재귀 삭제>"` · `sh -c '<일괄 종료>'` · `eval "<브랜치 강제 삭제>"` · `echo "$(<재귀 삭제>)"` · 백틱 · `X=1 <재귀 삭제>` · `sudo <재귀 삭제>` · `cd /tmp && <재귀 삭제>` · `echo "<재귀 삭제>" | sh` · `printf … | xargs <강제 종료>` · `bash <<EOF` 본문에 재귀 삭제 · `python3 - <<EOF` 본문에 `os.system("<재귀 삭제>")` · `$CMD x`(명령 단어 변수 + 구간에 패턴) · 따옴표 짝 불일치 + 패턴) + ★DA r1 반례·r2 추가★(`printf '%s\n' '<재귀 삭제>' > x.sh && bash x.sh` · `printf '<DROP TABLE t>' > x.sql && psql -f x.sql` · `echo '<DROP TABLE t>' | psql` · `P='<재귀 삭제>'; eval "$P"` · `P='<DROP TABLE t>'; psql -c "$P"` · `cat <<'EOF' > >(bash)` 본문 재귀 삭제 · `cat <<EOF` 본문 `$(<재귀 삭제>)` · `printf '%s' '#'; <재귀 삭제>` · `printf '%s\n' '<재귀 삭제>' | tee x | sh` · heredoc 2개 중 하나에 패턴 · `cat <<EOF | bash` · `cat > t.sh <<'EOF'`(본문 재귀 삭제) 뒤 `&& chmod +x t.sh && ./t.sh` · `{ <재귀 삭제>; }` · `! <재귀 삭제>` · `time <재귀 삭제>` · `coproc <재귀 삭제>` · 백슬래시+개행으로 쪼갠 재귀 삭제 · `echo $'<재귀 삭제>'` · `bash /tmp/x/mbox.sh send a b '<재귀 삭제>'`(이름만 mbox) · `bash $M send a b '<재귀 삭제>'`(변수 경로) · ★r3★ `rg --pre '<재귀 삭제>' .` · `P='<DROP TABLE t>'; V=P; psql -c "${!V}"` · `P='<DROP TABLE t>'; declare -n V=P; psql -c "$V"`).
   - 통과(exit 0 · ≥ 12): 정본 mbox 꼴(시험이 임시 git 리포 + `<루트>/.fable-team/comm/mbox.sh` 빈 파일을 만들고 JSON `cwd` = 그 리포) `bash <루트>/.fable-team/comm/mbox.sh send a#1 b#1 "<브랜치 강제 삭제> 원문 인용"` · 같은 경로 `relay` · 같은 send 뒤 `2>&1 | tail -1` · `echo "gcloud iam … keys delete 문장"` · `printf '%s\n' "<재귀 삭제> 설명" >> ledger.md` · `git commit -m "<강제 push> 금지 기록"` · `grep -E "<일괄 종료>|<강제 종료>" f | head` · `P='<패턴 문자열>'; grep -oiE "$P" f` · `cat > t.sh <<'EOF'` 본문에 `trap '<재귀 삭제> "$T"' EXIT` · `tee f <<'EOF'` 본문에 DROP TABLE · `echo a; grep -c "<강제 종료>" f` · `ls -la`.
   - STAGE 회귀(exit 2 · 통과 집계 밖): `git add -A` · `git add .`.
   - 실측 표본 재생: hil-falsepos.log 10-08 의 ①~⑤ 꼴 각 1건(본문은 시험 안에 재구성 · 시크릿 0).
3. 홈 훅·`~/.claude/settings.json`·프로젝트 `.claude/` 무변경.

커밋은 자기 브랜치, **push 금지**. **금지**: `PATTERN` 항목 삭제·약화 · 글 싱크 목록에 6개 밖 명령 추가(추가는 다음 판정) · 경로 허용 목록(스크래치·tmp 경로 면제) 신설 · fail-open · 홈 훅 직접 수정 · 실제 파괴 명령 실행(시험은 JSON 입력만).

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- `bash tests/harness/test_block_destructive.sh` rc=0(차단 유지 ≥ 45 · 통과 ≥ 12 · STAGE 회귀 2 · 표본 재생 5) · `bash -n` · 키트 훅 ≤ 180줄 · `bash tests/harness/test_kit_bin_sync.sh` rc=0.
- 카드 증거 줄 형식(필수 · 시험 칸은 명령 1개 · 없으면 반송): `세트: <40hex> · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0`.
  - 나노 워크트리(origin/main 기준)에 이 카드가 없으면 RESULT 맨 끝 줄에 `카드 증거 줄: 세트: <40hex> · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0` 을 복붙 가능한 그대로 쓴다 — master 가 카드 끝에 옮기고 `ft-nano-evidence-check.sh` 로 확인(master#16 #63821).
- 랜딩 뒤 master 집행(카드 밖): 홈 `~/.claude/hooks/block-destructive.sh` 에 키트 사본 cp + cmp(판정 343 홈=키트) · 설치 뒤 첫 Bash 호출 1회로 훅이 도는지 확인(셔뱅 그대로 · 원장 09-23 교훈) · 원장 R28·R38·R39·R40 행 상태 = 반영 sha.
- 진행→완성 이동은 `ft-index-move.sh <파일> 완성 --da <판정문#§N>` — 판정 절에 「대상 카드: v466-block-destructive-text-context」 줄.

## 상태
- base_sha: c970e05e74d0a14f9a1eb68f805883caee1f1092 (spawn 2026-10-08)
- 2026-10-08 — 대기/ 생성 (byz-harness-arch-claude#16 · 판정 466 · master#17 #63850).
- 2026-10-08 — r2: DA r1 HOLD(Q1·Q2·Q3·Q5 · Q4 APPROVE) 반영 — 2단 판정(실행 소비자·치환·이어붙임·heredoc 2개·파일 쓰기 뒤 소비·파이프·대입 이름 재사용 = 예외 0) · mbox = git 루트 정본 경로 realpath 일치만 · 주석 예외 삭제 · 반례 시험 행 추가.
- 2026-10-08 — r3: DA r2 HOLD 잔여 2 반영 — `rg` 를 글 싱크에서 제외(`--pre` 실행) · 대입 구간이 있으면 싱크·대입 밖 구간에 `$` 1개라도 있을 때 예외 0 + `${!` 있으면 예외 0(간접 확장·nameref) · 시험 3행 추가. DA bounded 2 HOLD 로 연속 리뷰 종료 → master 통합 판단.
- 정본 영향 없음: 전역 안전 훅의 판정 단위와 시험만 — docs/architect 제품 정본 변경 없음.
- 2026-10-08 18:55 — 대기→진행 · 좌석 byz-harness-nano-v466-block-destructive-text-context#0
세트: 6cd5541f9d6a0e85913a2c65253cfdf54b91e7a8 · 시험: bash tests/harness/test_block_destructive.sh rc=0 · 이슈: 0
- 2026-10-08 19:24 — 진행→완성 · DA design/teams/harness/OPS-VERDICTS-20261006.md#§73
