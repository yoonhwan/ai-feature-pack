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
