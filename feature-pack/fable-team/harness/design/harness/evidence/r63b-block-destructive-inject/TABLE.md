# R63b 대조표 — block-destructive INJECT 블록 (r3 반영)

시험: `bash tests/harness/test_block_destructive_inject.sh` rc=0 (차단22·통과31·변이15) · 기존 `tests/harness/test_block_destructive.sh` rc=0 (64/20/2/5) · 훅 `bash -n` OK

| 행 | 명령 | 기대 rc | 실제 rc |
|---|---|---|---|
| B1 | `redis-cli PUBLISH room_events:r1 '{"t":1}'` | 2 | 2 |
| B2 | `redis-cli -p 6380 SET k v` | 2 | 2 |
| B3 | `docker exec byz-redis redis-cli HSET k f v` | 2 | 2 |
| B4 | `bash -c "redis-cli XADD s '*' a b"` | 2 | 2 |
| B5 | `curl -s 'http://127.0.0.1:3001/dev/bubble-replay?scenario=static'` | 2 | 2 |
| B6 | `python3 - <<'EOF'⏎page.goto('http://x/dev/bubble-replay')⏎EOF` | 2 | 2 |
| B7a | `redis-cli -c -p 7000 SET k v` | 2 | 2 |
| B7b | `redis-cli -h 10.0.0.1 -p 6379 -n 2 HSET k f v` | 2 | 2 |
| B7c | `redis-cli "PUBLISH" ch x` | 2 | 2 |
| B7d | `rg x tests; redis-cli SET k v` | 2 | 2 |
| B7e | `gh pr view 1; curl -s http://h/dev/bubble-replay` | 2 | 2 |
| B8 | `redis-cli --user=u -p 1 SET k v` | 2 | 2 |
| B9 | `python3 run.py --url "$BASE/dev/bubble-replay"` | 2 | 2 |
| P1a | `redis-cli GET k` | 0 | 0 |
| P1b | `redis-cli HGETALL k` | 0 | 0 |
| P1c | `redis-cli --scan --pattern 'stt:*'` | 0 | 0 |
| P1d | `redis-cli GET setting` | 0 | 0 |
| P2a | `redis-cli DEL k` | 0 | 0 |
| P2b | `redis-cli FLUSHDB` | 0 | 0 |
| P3 | `python -m pytest tests/shared/prompts -q` | 0 | 0 |
| P4 | `python3 tests/e2e/realtime_multi_e2e.py --help` | 0 | 0 |
| P5 | `curl -s http://127.0.0.1:8080/health` | 0 | 0 |
| P6 | `bash <mbox.sh> send a#1 b#1 "redis-cli SET 와 /dev/bubble-replay 글자 인용"` | 0 | 0 |
| P7a | `grep -n 'redis-cli PUBLISH' f` | 0 | 0 |
| P7b | `echo "/dev/bubble-replay"` | 0 | 0 |
| P7c | `git commit -m "redis-cli SET 금지"` | 0 | 0 |
| P8a | `npx eslint app/dev/bubble-replay/page.tsx` | 0 | 0 |
| P8b | `ls clients/web/app/dev/bubble-replay/` | 0 | 0 |
| P8c | `git diff origin/main -- clients/web/app/dev/bubble-replay/page.tsx` | 0 | 0 |
| P8d | `git grep -n 'redis-cli PUBLISH' origin/main` | 0 | 0 |
| P8e | `rg -n 'redis-cli SET' tests` | 0 | 0 |
| P8f | `gh pr create --title x --body 'redis-cli SET 금지 카드'` | 0 | 0 |
| P8g | `redis-cli GET "set"` | 0 | 0 |
| P9a | `redis-cli -c -p 7000 GET k` | 0 | 0 |
| P9b | `redis-cli -h 10.0.0.1 -n 2 HGETALL k` | 0 | 0 |
| P10a | `redis-cli --scan --pattern 'session:*' \| head` | 0 | 0 |
| P10b | `redis-cli CONFIG GET maxmemory` | 0 | 0 |
| P10c | `cat f.sh \| grep -n 'redis-cli SET'` | 0 | 0 |
| P11a | `git grep -n /dev/bubble-replay origin/main` | 0 | 0 |
| P11b | `rg -n "redis-cli SET k v" tests` | 0 | 0 |
| B10a | `gh pr create --title x --body "$(redis-cli SET k v)"` | 2 | 2 |
| B10b | `gh pr comment 1 --body "`redis-cli HSET k f v`"` | 2 | 2 |
| B10c | `rg x <(redis-cli SET k v)` | 2 | 2 |
| B10d | `git grep -n x $(redis-cli PUBLISH ch m)` | 2 | 2 |
| P12a | `echo "$(date)"` | 0 | 0 |
| P12b | `git log --format=%h -1 $(git merge-base origin/main HEAD)` | 0 | 0 |
| P12c | `gh pr create --title x --body-file /tmp/b.md` | 0 | 0 |
| B11a | `gh pr create --body "$(redis-''cli SET k v)"` | 2 | 2 |
| B11b | `gh pr create --body "$(redis-cli S''ET k v)"` | 2 | 2 |
| B11c | `redis-''cli SET k v` | 2 | 2 |
| B11d | `re\dis-cli SET k v` | 2 | 2 |
| B11e | `redis-cli "S"ET k v` | 2 | 2 |
| P13 | `redis-cli GET 'SET'` | 0 | 0 |
| M1-P6 | `bash <mbox.sh> send a#1 b#1 "redis-cli SET 와 /dev/bubble-replay 글자 인용"` | 2 | 2 |
| M1-P7b | `echo "/dev/bubble-replay"` | 2 | 2 |
| M1-P7c | `git commit -m "redis-cli SET 금지"` | 2 | 2 |
| M2-B1 | `redis-cli PUBLISH room_events:r1 '{"t":1}'` | 0 | 0 |
| M2-B5 | `curl -s 'http://127.0.0.1:3001/dev/bubble-replay?scenario=static'` | 0 | 0 |
| M3-P8f | `gh pr create --title x --body 'redis-cli SET 금지 카드'` | 2 | 2 |
| M3-P11a | `git grep -n /dev/bubble-replay origin/main` | 2 | 2 |
| M3-P11b | `rg -n "redis-cli SET k v" tests` | 2 | 2 |
| M4-P8g | `redis-cli GET "set"` | 2 | 2 |
| M5-P8a | `npx eslint app/dev/bubble-replay/page.tsx` | 2 | 2 |
| M5-P8b | `ls clients/web/app/dev/bubble-replay/` | 2 | 2 |
| M6-B10a | `gh pr create --title x --body "$(redis-cli SET k v)"` | 0 | 0 |
| M6-B10b | `gh pr comment 1 --body "`redis-cli HSET k f v`"` | 0 | 0 |
| M7-B11a | `gh pr create --body "$(redis-''cli SET k v)"` | 0 | 0 |
| M7-B11b | `gh pr create --body "$(redis-cli S''ET k v)"` | 0 | 0 |

※ 변이: M1 = `$CMD` 기준 · M2 = 블록 제거 · M3 = 검색·게시 구간 제거 빼기 · M4 = 옛 «아무 위치» Redis 규칙 · M5 = 페이지 경로 제거 빼기 · M6 = 실행 치환 검사 case 빼기 · M7 = `tr -d`(따옴표·역슬래시 제거) 빼기 — 각 변이에서 해당 행의 rc 가 뒤집힘.
※ 경계: Redis 동사는 `redis-cli` 뒤 옵션만 오고 첫 토큰일 때 + 인자 1개 이상일 때만 차단(`CONFIG SET`·`GET set` 통과). 검색·게시 구간(`git grep`·`rg`·`ag`·`gh pr|issue create|comment|edit|view`)은 `; & |` 까지만 검사에서 제외하되, 실행 치환(`$(`·백틱·`<(`·`>(`)이 하나라도 있으면 이 예외를 끈다(r2). 검사 사본에서 따옴표·역슬래시를 지워 `redis-''cli`·`S''ET` 이어붙임을 한 단어로 본다(r3). 알고 둔 범위 밖: 변수·별칭 우회(`r=redis-cli; $r SET k v`)·스크립트 파일 안 주입·파이프 stdin(`echo "SET k v" | redis-cli`) — 명령줄 글자 훅의 한계, 증거 무효 규정(BOOT 20)이 맡는다.

## 판정 595 추가 행 — 게시 싱크(`--inject` 모드 · 시험 `tests/harness/test_block_destructive_inject_post.sh`) · r1·r2 반송 반영

시험: `bash tests/harness/test_block_destructive_inject_post.sh` rc=0 (통과 F 7 · 차단 X 22 · 변이 9) · 기존 `test_block_destructive_inject.sh` rc=0 (22/32/15) · `test_block_destructive.sh` rc=0 · 훅 `bash -n` OK · 판정기 200줄. 명령 전문은 시험 파일(JSON 문자열일 뿐, 실행 0). 임시 경로는 예시 글자.

| 행 | 명령 | 기대 rc | 실제 rc |
|---|---|---|---|
| F1a | `(issues#6 실사례 원문 형태: 대입 3개 + cat > $SP/c887r.md <<'EOF' 본문(/dev/bubble-replay 인용) + bash $SP/ft-gh-as-tank.sh comment 887 $SP/c887r.md --apply \| tail -1 + close-check + mbox send)` | 0 | 0 |
| F1b | `cat > /tmp/fp-c.md <<'EOF'⏎(/dev/bubble-replay) 무효⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 887 /tmp/fp-c.md --apply` | 0 | 0 |
| F1c | `cat > /tmp/fp-c.md <<'EOF'⏎redis-cli SET k v 금지⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh edit 887 --body-file /tmp/fp-c.md --apply` | 0 | 0 |
| F1d | `cat > /tmp/fp-b.md <<'EOF'⏎redis-cli SET k v 금지⏎EOF⏎gh pr create --title x --body-file /tmp/fp-b.md` | 0 | 0 |
| F1e | `cat > /tmp/fp-m.txt <<'EOF'⏎[docs] /dev/bubble-replay 금지⏎EOF⏎git commit -F /tmp/fp-m.txt -- a.md` | 0 | 0 |
| F2a | `gh issue comment 1 --body "$(cat <<'EOF'⏎/dev/bubble-replay 무효⏎EOF⏎)"` | 0 | 0 |
| F2b | `git commit -m "$(cat <<'EOF'⏎[docs] redis-cli SET k v 금지⏎EOF⏎)" -- a.md` | 0 | 0 |
| X1 | `cat > /tmp/fp-x.sh <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash /tmp/fp-x.sh` | 2 | 2 |
| X2 | `cat > /tmp/fp-x.txt <<'EOF'⏎SET k v⏎EOF⏎redis-cli < /tmp/fp-x.txt; redis-cli SET k v` | 2 | 2 |
| X3 | `cat > /tmp/fp-c.md <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/fp-c.md --apply; bash /tmp/fp-c.md` | 2 | 2 |
| X4 | `cat > /tmp/fp-c.md <<EOF⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/fp-c.md --apply` | 2 | 2 |
| X5 | `cat > /tmp/fp-k <<'EOF'⏎url = http://h/dev/bubble-replay⏎EOF⏎curl -K /tmp/fp-k; bash x.sh` | 2 | 2 |
| X6 | `bash -c "$(cat <<'EOF'⏎redis-cli SET k v⏎EOF⏎)"` | 2 | 2 |
| X8 | `curl "$(cat <<'EOF'⏎http://h/dev/bubble-replay⏎EOF⏎)"` | 2 | 2 |
| X9 | `cat > /tmp/fp-c.md <<'EOF'⏎x⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/fp-c.md --apply; redis-cli SET k v` | 2 | 2 |
| X10 | `gh issue comment 1 --body "$(cat <<'EOF'⏎ok⏎EOF⏎)$(redis-cli SET k v)"` | 2 | 2 |
| X11 | `python3 - <<'EOF'⏎import os; os.system('redis-cli SET k v')⏎EOF` | 2 | 2 |
| X12 | `cat > /tmp/fp-c.md <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash x.sh /tmp/fp-c.md` | 2 | 2 |
| X13 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file /tmp/body595.txt; bash "$RUNFILE"` | 2 | 2 |
| X14 | `cat > <임시폴더>/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file <임시폴더>/body595.txt; bash <임시폴더>/other595.sh` | 2 | 2 |
| X15 | `R=/tmp/body595.txt; cat > $R <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash $R` | 2 | 2 |
| X16 | `D=/tmp; cat > $D/c.md <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash $D/../tmp/c.md` | 2 | 2 |
| X17 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/body595.txt --apply; sudo bash x.sh` | 2 | 2 |
| X18 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file /tmp/body595.txt; bash "$RUNFILE"; RUNFILE=/tmp/safe.sh` | 2 | 2 |
| X19 | `R=/tmp/safe.sh; cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file /tmp/body595.txt; R=/tmp/body595.txt; bash $R` | 2 | 2 |
| X20 | `gh issue comment 1 --body "$(cat <<'EOF'⏎ok⏎EOF⏎redis-cli SET k v⏎EOF⏎)"` | 2 | 2 |
| X21 | `cat > /tmp/fp-c.md <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash $D/fp-c.md` | 2 | 2 |
| X22 | `cat > /tmp/fp-c.md <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash /tmp/fp-c.m?` | 2 | 2 |
| X23 | `echo '<<"A"'; cat > /tmp/fp-c.md <<EOF⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/fp-c.md --apply` | 2 | 2 |
| M3-X12 | `cat > /tmp/fp-c.md <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash x.sh /tmp/fp-c.md` | 0 | 0 |
| M4-X14 | `cat > <임시폴더>/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file <임시폴더>/body595.txt; bash <임시폴더>/other595.sh` | 0 | 0 |
| M12-X13 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file /tmp/body595.txt; bash "$RUNFILE"` | 0 | 0 |
| M12-X17 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/body595.txt --apply; sudo bash x.sh` | 0 | 0 |
| M7-X18 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file /tmp/body595.txt; bash "$RUNFILE"; RUNFILE=/tmp/safe.sh` | 0 | 0 |
| M8-X4 | `cat > /tmp/fp-c.md <<EOF⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/fp-c.md --apply` | 0 | 0 |
| M9-F1a | `(issues#6 실사례 원문 형태: 대입 3개 + cat > $SP/c887r.md <<'EOF' 본문(/dev/bubble-replay 인용) + bash $SP/ft-gh-as-tank.sh comment 887 $SP/c887r.md --apply \| tail -1 + close-check + mbox send)` | 2 | 2 |
| M9-F1b | `cat > /tmp/fp-c.md <<'EOF'⏎(/dev/bubble-replay) 무효⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 887 /tmp/fp-c.md --apply` | 2 | 2 |
| M10-X20 | `gh issue comment 1 --body "$(cat <<'EOF'⏎ok⏎EOF⏎redis-cli SET k v⏎EOF⏎)"` | 0 | 0 |

※ X13~X17 = DA r1 반송(Q1): 같은 명령의 실행 소비 구간이 «대입 해소 + realpath ≠ F» 로 증명돼야 본문을 뺀다. X13 미해소 `$RUNFILE` · X14 다른 이름 심링크(시험이 임시 폴더에 other595.sh → body595.txt 생성) · X15 `R=…` 뒤 `$R` 실행 · X16 `$D/../tmp/c.md` 우회 · X17 `sudo bash`.
※ X18·X19 = DA r2 반송(Q1): 대입은 «구간 순서대로» — 검사 뒤에 대입된 값(X18 뒤쪽 `RUNFILE=/tmp/safe.sh` · X19 `R=F` 재대입)은 앞 구간 검사에 쓰지 않는다. X20~X23 = 1차 구현이 더한 행: X20 본문 안 구분자 줄 · X21 같은 끝 이름 별칭 · X22 글롭 · X23 따옴표 모양 문자열로 따옴표 없는 구분자를 가림.
※ 변이: M3 = F 를 가리키는 토큰 검사 빼기(X12 → 0) · M4 = realpath 비교 빼기(두 곳 · X14 → 0) · M12 = 실행 소비 구간 «비-F 증명» 빼기(X13·X17 → 0) · M7 = 대입을 전 구간 최종 값으로(r1 동작 · X18 → 0) · M8 = 따옴표 구분자 요구 빼기(X4 → 0) · M9 = 훅이 `INJ_SRC` 대신 `EFFECTIVE` 를 봄(F1a·F1b → 2) · M10 = 본문 안 구분자 줄 검사 빼기(X20 → 0). ★이중 방어★: X15·X16·X19 는 «끝 이름 검사» 와 «realpath 검사» 가 둘 다 잡는다.
※ 알고 둔 범위 밖: 카드의 X7(`redis-cli $(cat <<'EOF'`⏎`SET k v` — 동사가 다음 줄) 은 기존 `INJECT_REDIS` 가 못 보는 빈틈이라 이 카드 범위 밖이었다(키트 원본·595 변경 모두 rc=0) → 아래 «X7 계열 추가 행» 이 닫는다. 게시 래퍼 판별은 파일 «끝 이름»(`ft-gh-as-tank.sh`)이라 같은 이름의 다른 스크립트도 래퍼로 본다(닫힌 목록의 알려진 한계). 증명 불가 꼴(`eval`·`source`·`.`·`xargs`·`env`·`sudo`·`-c`·옵션 붙은 셸·`find -exec`·`read`/`declare` 등 변수 변경 명령·`$` 첫 단어)은 전부 Inelig = 명령 전체 검사.

## X7 계열 추가 행 — redis-cli 가 쓰기 동사를 argv 밖(치환·heredoc·stdin·파이프·xargs·줄 이음·실행 코드 인자 안 stdin)에서 받는 꼴 (카드 `x7-inject-redis-indirect-input` · 판정 595 후속 · DA r1·r2 반송 반영)

시험: `bash tests/harness/test_block_destructive_inject_post.sh` rc=0 (통과 F·Q·W 18 · 차단 X·Y·Z·V 43 · 변이 21) · 기존 `test_block_destructive_inject.sh` rc=0 (22/32/15) · `test_block_destructive.sh` rc=0 · 훅 `/bin/bash -n` OK · 판정기 200줄. 명령 전문은 시험 파일(JSON 문자열일 뿐, 실행 0). 변경 = 훅 INJECT 블록(대안 3개 + 옵션 접두 뒤 치환 대안 · `||` 제외 · stdin 은 `INJECT_STDIN` 별도 · 줄 잇기 `INJ_J` · `redis-cli` 가 안 든 따옴표 구간만 `<` 를 비운 `CHK_R` · 표지 `INJ_MARK`) + 판정기 `--inject` 경로만 단어 인용 복원(`judge(cmd, cwd, q)` · 기본 호출 출력 불변).

| 행 | 명령 | 기대 rc | 실제 rc |
|---|---|---|---|
| Y1 | `redis-cli $(cat <<'EOF'⏎SET k v⏎EOF⏎)` | 2 | 2 |
| Y2 | `` redis-cli `printf 'SET k v'` `` | 2 | 2 |
| Y3 | `redis-cli <<'EOF'⏎SET k v⏎EOF` | 2 | 2 |
| Y4 | `redis-cli <<< 'SET k v'` | 2 | 2 |
| Y5 | `redis-cli --pipe < /tmp/data.txt` | 2 | 2 |
| Y6 | `printf 'SET k v' \| redis-cli` | 2 | 2 |
| Y7 | `echo 'HSET k f v' \| redis-cli -p 6380` | 2 | 2 |
| Y8 | `echo k \| xargs redis-cli SET` | 2 | 2 |
| Q1 | `redis-cli GET $(cat key.txt)` | 0 | 0 |
| Q2 | `redis-cli --scan --pattern 'x:*' \| head` | 0 | 0 |
| Q3 | `grep -n 'redis-cli <<' docs/a.md` | 0 | 0 |
| Q4 | `echo 'printf SET \| redis-cli 는 금지'` | 0 | 0 |
| Z1 | `printf 'SET k v\n' \|⏎redis-cli` | 2 | 2 |
| Z2 | `printf 'SET k v' \|   ⏎  redis-cli -p 6380` | 2 | 2 |
| Z3 | `redis-cli \⏎SET k v` | 2 | 2 |
| Z4 | `printf 'SET k v' \⏎\| redis-cli` | 2 | 2 |
| Z5 | `redis-cli -n '<1>' < /tmp/d.txt` | 2 | 2 |
| Z6 | `redis-''cli <<< 'SET k v'` | 2 | 2 |
| Z7 | `curl 'http://h/dev/bubble-replay?<x>'` | 2 | 2 |
| W1 | `redis-cli GET '<literal-key>'` | 0 | 0 |
| W2 | `redis-cli GET "a<b"` | 0 | 0 |
| W3 | `false \|\| redis-cli GET k` | 0 | 0 |
| W4 | `false \|\|⏎redis-cli GET k` | 0 | 0 |
| W5 | `redis-cli --scan --pattern 'x:*' \|⏎head -3` | 0 | 0 |
| W6 | `redis-cli GET k 2>/dev/null` | 0 | 0 |
| V1 | `bash -c "redis-cli < /tmp/data.txt"` | 2 | 2 |
| V2 | `sh -c 'redis-cli < /tmp/data.txt'` | 2 | 2 |
| V3 | `python3 -c "import os; os.system('redis-cli < /tmp/data.txt')"` | 2 | 2 |
| V4 | `bash -c 'redis-cli</tmp/d'` | 2 | 2 |
| V5 | `bash -c "REDIS-CLI < /tmp/d"` | 2 | 2 |
| V6 | `ssh h 'redis-cli -p 1 < /tmp/d'` | 2 | 2 |
| W7 | `bash -c "echo hi"; redis-cli GET '<k>'` | 0 | 0 |
| M12-X13 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎gh pr create --title x --body-file /tmp/body595.txt; bash "$RUNFILE"` | 0 | 0 |
| M12-X17 | `cat > /tmp/body595.txt <<'EOF'⏎redis-cli SET k v⏎EOF⏎bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 1 /tmp/body595.txt --apply; sudo bash x.sh` | 0 | 0 |
| M5-Y1 | `redis-cli $(cat <<'EOF'⏎SET k v⏎EOF⏎)` | 0 | 0 |
| M5-Y6 | `printf 'SET k v' \| redis-cli` | 0 | 0 |
| M6-Q1 | `redis-cli GET $(cat key.txt)` | 2 | 2 |
| M6-Q2 | `redis-cli --scan --pattern 'x:*' \| head` | 2 | 2 |
| M6-Q3 | `grep -n 'redis-cli <<' docs/a.md` | 2 | 2 |
| M6-Q4 | `echo 'printf SET \| redis-cli 는 금지'` | 2 | 2 |
| M10q-W1 | `redis-cli GET '<literal-key>'` | 2 | 2 |
| M10q-W2 | `redis-cli GET "a<b"` | 2 | 2 |
| M11-Z1 | `printf 'SET k v\n' \|⏎redis-cli` | 0 | 0 |
| M11-Z3 | `redis-cli \⏎SET k v` | 0 | 0 |
| M12-V1 | `bash -c "redis-cli < /tmp/data.txt"` | 0 | 0 |
| M12-V3 | `python3 -c "import os; os.system('redis-cli < /tmp/data.txt')"` | 0 | 0 |

※ 변이: M5 = 추가 줄 + stdin 검사 제거(Y1·Y6 → 0) · M6 = 백틱 이스케이프(`\``) 빼기 → 큰따옴표 안에서 명령 치환이 시작돼 훅이 깨지고 전 명령이 rc=2(Q1~Q4 → 2) · M10q = 판정기 `--inject` 단어 인용 복원 끄기(W1·W2 → 2, 카드의 M10) · M11 = 줄 잇기 끄기(Z1·Z3 → 0). M12 = 표지 단계(redis-cli → \001) 빼기 = r1 동작(V1·V3 → 0). 기존 M9 는 `INJ_J` 입력을 `EFFECTIVE` 로 바꾼 꼴로 갱신.
※ 카드 설계 정정(r0): 카드는 M6 을 «`[|]` → `\|` 복사본» 으로 적었으나 BSD grep(/usr/bin/grep 2.6.0-FreeBSD)에서 `\|` 는 빈 대안이 아니라 글자 `|` 라 Q 행이 안 깨진다(arch 재실측 BAD 0 으로 확인) → 훅 주석의 해당 문장 삭제, 이스케이프 없는 백틱 꼴을 M6 으로 둔다. `[|]` 표기는 유지.
※ 경계: Q1 `redis-cli GET $(cat key.txt)`(동사 뒤 치환)·Q2 출력 파이프·Q3 검색 인용·Q4 쪽지 글자·W1~W6(따옴표 인자 안 `<`·`||`·출력 파이프 줄 이음·`2>`) 통과. 알고 둔 범위 밖: 변수·별칭 우회(`r=redis-cli; $r SET k v`)·스크립트 파일 안 주입 — 명령줄 글자 훅의 한계(BOOT 20 이 맡음).
