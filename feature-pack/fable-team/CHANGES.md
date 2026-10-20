## 2026-10-21 — 뉴스 갈래 HTTP 스트림 읽기가 «한 번 읽기» 상한만 봐 조각이 계속 오면 총 마감 70초를 넘겨 115.5초 → 조각마다 시각을 보고 총 마감·조각 사이 무진행에서 끊는다 (r592 · 1.1.137 · 동작 변경 · 재시도 규칙·요청 필드·opencode 길·총 마감 값 무변경)

- 사건(arch 112 틱 실측 2026-10-21 02:2x · `/tmp/byz-ft-news-planner.log`): «만듦 NEWS-20261021-0216.html secs=115.5(summary=4.0 important=115.5 goals=5.9 teams=16.2)» — 갈래 하나가 총 마감 `DEADLINE_S = 70` 을 넘어 뉴스 데몬이 2분 가까이 묶였다(하드 룰 12 «첫 출력·청크 간 무진행 각 7초 + 같은 총 마감» 위반). 원인 = `_http_once` 의 `urlopen(req, timeout=left)` 는 **소켓 한 번 읽기** 상한이고 `_sse_text` 는 `for raw in lines` 를 시각 검사 없이 끝까지 돈다 — 조각이 그 상한보다 짧은 간격으로 계속 오면 얼마든 길어진다. opencode 길(`t.join(max(0, t0 + left - now))`)은 이미 총 시간을 봐서 HTTP 길만 빠져 있었다.
- 고침(키트 1 `ft_news_html_render.py` · 3곳): ① `IDLE_S = 7.0` + `idle_s()`(env `FT_NEWS_IDLE_S` · 기본 7.0) ② `_sse_text(lines, deadline, idle_s)` — 줄마다 `time.monotonic()` 을 보고 **마감 넘음 = break «총 마감»** · **직전 줄 뒤 idle_s 넘음 = break «무진행»**, 끊은 이유를 `meta["stop"]` 에 남긴다 ③ `_http_once` — `deadline = t0 + left` · 끊겼으면 **rc 1 + 사유(«{part} 총 마감 N초 초과 · … · 답 M자» / «{part} 무진행 N초 · … · 답 M자»)** · `with` 블록 그대로라 연결은 닫힌다. **출력이 시작된 뒤 실패라 재시도 0** — `call_part` 의 «글 있으면 재시도 0» 규칙 그대로(코드 변경 0)이고, 첫 출력 전에 마감을 넘긴 경우만 종전처럼 1회 재시도(남은 시간 0 이면 즉시 포기).
- 시험 `harness/tests/scripts/test_news_stream_deadline_r592.py` ⓐ~ⓔ(로컬 가짜 SSE 서버 · 조각 간격 조절 · 실 공급자 0 · 키는 가짜 값): ⓐ 0.05초마다 조각이 계속 오고 시험용 마감 0.5초 → **옛 판 = 끝까지 읽음(rc0) · 고친 판 = rc1 «총 마감 … 답 N자»**(2초 안에 끊김) ⓑ 첫 조각 뒤 0.8초 공백(`FT_NEWS_IDLE_S=0.3`) → «무진행 …» rc1 ⓒ 정상 스트림(마감 안) → rc0 · 답 글 원문 그대로(동작 불변) ⓓ 출력이 시작된 뒤 시도당 상한(2초) 초과 → `NewsHtmlError` · **호출 수 1**(재시도 0) ⓔ 끊은 뒤 서버의 다음 쓰기가 OSError = 소켓 열린 채 남음 0. **전(origin/main 판 = ⓐⓑⓓⓔ FAIL 4 · ⓒ PASS) → 후 5 PASS**(`harness/evidence/r592/01-before-red-base.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r592/03-existing-tests.txt`): `test_ft_news_html.py`·`test_news_direct_api.py`·`test_news_truncated.py`·`test_news_html_cli_startup.py`·`test_ft_news_publish.py`·`test_news_summary_schema_lines.py`·`test_news_team_status_line.py` = **93 passed**(첫출력·재시도·키·공급자·잘림·린트 길 그대로) · `ruff check` All checks passed · kit/bin 사본 cmp0(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_news_html_render.py` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.137 · `install.sh` REQUIRED 변경 0 · 데몬 0. **LIVE_BIN 설치(cmp0) · 뉴스 데몬 재기동 · 실사건 1(설치 뒤 뉴스 틱 20회 «만듦 … secs=» 의 갈래 초가 전부 ≤70)은 master 소관 — 미실행.** 되돌림 = `.bak-r592`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다.
- 범위 밖: opencode 길(이미 총 시간을 본다) · 재시도 규칙 · 요청 필드(`REASONING_OFF`·`max_tokens`·`stream_options`) · 총 마감 값(70) · 다른 도구의 스트림 · 소켓 읽기 timeout 자체(무진행은 «다음 조각이 왔을 때» 판정 — 완전 정지는 종전처럼 socket timeout 이 잡는다).

## 2026-10-21 — 파괴 명령 훅이 이름이 «-f» 로 끝나는 새 가지 올리기를 강제 올리기로 오판해 차단 → `-f` 도 다른 옵션처럼 «앞 공백» 자리만 강제 올리기로 본다 (r591 · 1.1.136 · 동작 변경 · 판정기·다른 절·예외 무변경)

- 사건(v65 쪽지 124272 · planner 124285 · master 88 발주 124292 · arch 112 실측 2026-10-21 02:0x): 키트 `templates/hooks/block-destructive.sh:18` PATTERN 의 올리기 절이 `(-f\b|--mirror|--delete|[[:space:]]-d\b|[[:space:]]\+…|[[:space:]]:…)` 이다 — 다른 옵션(`-d`)은 «앞 공백이 있는 -d» 만 보는데 `-f` 만 공백 조건이 없어, 가지 이름이 `-f` 로 끝나면(예: `nano/c-tour-f`) 강제 올리기로 오판해 `git push -u origin nano/x-f` 가 rc2 로 막혔다(팀 착지 정지). 옵션은 늘 공백 뒤에 오고 가지 이름은 `-` 로 시작할 수 없으므로, `-f` 에도 앞 공백을 요구하면 진짜 강제 올리기는 그대로 막고 이름 끝 글자만 풀린다.
- 고침(키트 PATTERN 1토큰): 올리기 절의 `-f\b` → `[[:space:]]-f\b` + 주석 1줄 «r591: -f 도 옵션 자리(앞 공백)만 — 이름 끝 -f 오탐». 판정기(`block-destructive-judge.py`)·다른 절·예외(kill-session) 변경 0.
- 시험 `harness/tests/test_block_destructive.sh` 에 r591 칸 4줄 추가: ⓐ `git push -u origin nano/x-f` 통과 ⓑ `git push -f origin x` 차단 ⓒ `git push origin x -f` 차단 ⓔ `git push origin nano/a-f:nano/a-f` 통과 (ⓓ = 기존 `--force`·`--force-with-lease`·`--mirror`·`--delete`·`␣-d`·`␣+ref`·`␣:ref` 차단 줄 그대로 rc2 — r44 꼴 불변). **전(origin/main 판 훅 = ⓐ·ⓔ FAIL 2) → 후 SUMMARY blocked=76 pass=25 stage=2 sample=5 fail=0** (`harness/evidence/r591/01-before-red-base.txt`·`02-after-pass.txt`). 훅 직접 실행 rc 대조: base=2 new=0 ⓐ / base=2 new=2 나머지 9꼴 / base=2 new=0 ⓔ.
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r591/03-existing-tests.txt`): `test_block_destructive_inject.sh`·`test_block_destructive_inject_post.sh`·`test_block_destructive_hil.sh` = fail=0 3/3 · `bash -n` rc=0 · PATTERN 원문 diff = 한 토큰 1줄.
- 설치: 있음 — 키트 1(`kit/fable-team/templates/hooks/block-destructive.sh`) + 시험 1 · manifest 1.1.136 · `install.sh` REQUIRED 변경 0 · 데몬 0. **홈 `~/.claude/hooks/block-destructive.sh` cp -p · cmp0 · 실행 비트 확인 · 실사건 1(이름 끝 `-f` 가지 올리기 통과 원문 + `-f` 옵션 차단 원문)은 master 소관 — 미실행**(현재 cmp≠0 = 미설치). 되돌림 = `.bak-r591`. press 아님 — 나노는 쏘지 않는다.
- 범위 밖: 짧은 옵션 묶음(`-uf` 꼴) 새로 잡기 · 다른 훅 · 오탐 기록 파일 형식.

## 2026-10-21 — 하위 좌석의 사람 질문(HIL)이 늘 «하네스 명부» 의 `_hil_route`(planner)로 가 팀별 분산이 안 되던 것 → 질문 도구가 «보내는 좌석의 팀 명부» 를 읽는다 (r578 · 1.1.135 · 동작 변경 · 원장·답 회신·lint 판정 규칙 무변경)

- 사건(master 87 발주 123168 ① · planner arch 8 제안 · arch 111 실측 2026-10-20 23:5x): 팀 명부마다 `_hil_route` 칸은 이미 있고(11개 = `byz-planner-master-claude#86` · cfo·kk = 칸 없음) 틱·handover 는 «그 팀 명부» 값을 읽는다. 그러나 HIL 질문 도구 `ft-hil-ask.sh` 는 명부 기본값이 `seats-harness.json`(`FT_SEATS` 없으면)이라 ★어느 팀이 물어도 하네스 명부의 `_hil_route` 로 갔다★ — 팀 명부 값을 desk 로 바꿔도 소용이 없었다(10팀 질문이 planner 한 곳에 묶여 정지 · 오빠 «플랜팀 집중보다 분산가능한건 분산»).
- 고침 1(`ft-hil-ask.sh` · 명부 선택 1곳): `FT_SEATS` 명시 > ★보내는 좌석 이름의 팀 명부★(`mbox_guard.sh` tfile 과 같은 규칙 — `^(byz|ft)-<팀>-` · `v65` = `seats.json`, 그 외 = `seats-<팀>.json`). 팀을 못 읽거나 파일이 없으면 `REJECT`(«좌석 이름에서 팀을 못 읽어 …» / «팀 명부 없음 <경로>») — 조용히 하네스 명부로 대체 0. `FT_HIL_ROUTE` 를 명시한 호출은 예전처럼 명부를 안 읽는다(해석은 수신을 정할 때만). 머리 주석 10행 갱신.
- 고침 2(`ft-seats-lint.sh`): 손대지 않았다 — `_hil_route` 검사는 이미 ★어느 명부든★ 행이 있으면 통과(`rowed` = 전 명부 합본 · `:109-112,:154`)라 «그 명부 안에 행이 있어야» 가 아니다. 바꾸는 대신 시험 ⓔ 로 그 동작을 못박았다(desk 좌석이 planner 명부에만 있어도 경보 0 · 세션이 죽으면 ⓑ 경보).
- 정본 덧말 1(`skill/references/main-team-governance.md` §7): 수신 = «그 팀 명부 `_hil_route`(기본 planner · 팀별 desk 가능)» · 도구가 읽는 명부 규칙 · 어느 팀을 desk 로 돌릴지는 planner·desk 가 정하고 그 팀장이 명부 값을 바꾼다(값 변경 = 이 카드 밖) 2줄 추가, «현역 planner 에» → «그 팀 명부 `_hil_route`(기본 planner · 팀별 desk 가능) 로».
- 시험 `harness/tests/test_hil_route_team.sh` ⓐ~ⓔ(임시 루트 `git init`·가짜 명부 3벌(planner·ops·feature)+cfo 꼴·가짜 mbox·가짜 tmux ls · 실 우편함·실 명부·실 좌석 0): ⓐ ops 좌석 · ops 명부 `_hil_route`=desk, 하네스 명부=planner → desk 로 감 ⓑ feature 좌석 · 명부=planner → planner ⓒ cfo 꼴(`_hil_route` 칸 없음) → `REJECT`·송신 0·사유에 읽은 명부 경로 ⓒ2 팀 명부 파일 없음 → «팀 명부 없음» `REJECT` ⓓ `FT_SEATS`·`FT_HIL_ROUTE` 명시 = 그대로 우선 ⓔ lint: 다른 명부에만 행이 있는 살아 있는 desk 좌석 = 경보 0(«불일치 0» rc0), 그 좌석이 죽으면 «_hil_route … 세션 없음» ⓑ 경보 rc≠0. **전(origin/main 판 = ⓐ 가 planner 로 가는 9 FAIL) → 후 ALL PASS**(`harness/evidence/r578/01-before-red-base.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r578/03-existing-tests.txt`): `test_hil_ledger.sh`(ask→answer→applied 1바퀴) ALL PASS rc0 — 명부 기본값이 바뀌어도 `FT_HIL_ROUTE` 명시 호출은 예전 그대로임을 이 시험이 잰다. `ft-seats-lint.sh` 전용 시험 파일은 팩·BYZ 어디에도 없다(2026-10-21 확인) — 판정 시험은 새 시험 ⓔ 가 맡는다. `bash -n` rc0 · kit/bin 두 사본 cmp0(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-hil-ask.sh` · `harness/bin` 짝 cmp0) + 시험 1 + 정본 덧말 1 · manifest 1.1.135 · `install.sh` REQUIRED 변경 0 · 데몬 0. **LIVE_BIN 설치(cmp0) · 팀 1개명부 `_hil_route`=desk 값 변경 · 실사건 1(그 팀 질문이 desk 우편함에 도착한 쪽지 번호 · 다른 팀 planner 그대로)은 master 소관 — 미실행(값 변경 = 데이터 · planner·desk 결정).** 되돌림 = `.bak-r578`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다.
- 범위 밖: 팀별 `_hil_route` 값 변경(데이터 · planner·desk 결정 → master 집행) · planner 사본/집계 장치 · r579 재질문 · BOOT 8 정본 문구 갱신(`~/.agents/skills/tmuxc/COMM-GUIDE-BOOT.md`) · ft-seats-lint.sh 코드 변경.

## 2026-10-21 — 루트 clients/web/node_modules 안 «자기 링크» 가 두 번 생겨 루트 FE 500 → 감시자가 1분 틱에서 보고 planner 에 «지우기: unlink» 쪽지 1통 (r589 · 1.1.134 · 동작 변경 · 삭제·자동 고침 0)

- 사건(master 87 발주 123816 · v65 쪽지 123803 · arch 112 실측 2026-10-21 01:4x): 루트 `clients/web/node_modules/node_modules` → 그 폴더 자신 심링크가 23:35 · 00:45 두 번 생겨 루트 FE 를 쓰는 좌석이 500(tester 가 23:44 unlink). 원리 = `ln -s A B` 에서 B 가 이미 폴더(또는 폴더로 가는 링크 · `-n` 없음)면 «B 안에» A 이름으로 링크가 생긴다 — 손 명령 한 번이면 루트 안에 자기 링크. **주체 확정 0**(그 순간의 B 상태 기록 없음) → 이 카드는 «원인 명령 고치기» 가 아니라 «생기면 그 틱에 알림» 으로 닫는다.
- 고침(키트 2 · `ft-resource-watch.sh` + 새 `ft-resource-selflink-lib.sh`): `tick` 에 `selflink_watch` 1회 추가 — `test -L <루트>/clients/web/node_modules/node_modules` 1회(비용 = stat 1). 링크면 로그 `WARN node_modules 자기 링크 <경로> → <대상>` 1줄 + 서명(경로·대상)이 바뀔 때만 planner 명부(`FT_SEATS_JSON`) `_master` 에 쪽지 1통 «[장비 정리] … 루트 FE 500 원인 · 지우기: unlink <경로>»(r522 CPU 쪽지와 같은 보내기 함수 · 서명 파일 `state/.selflink-node-modules.sig`). 링크가 사라지면 서명을 지워 다음 발생은 새 사건으로 알린다. **삭제·자동 고침 0**(머리 주석 그대로 — 지우는 한 줄은 쪽지에 적기만). 동결 분기 «앞» 에 두어 이른 return(동결 생성·측정 오류)에도 돈다.
- lib 분리 이유 = 감시자 본문 줄 수 상한(≤245 · `test_resource_watch_incremental_r534.sh`·`test_resource_gate_pressure.sh` 가 잰다). r534 `ft-resource-du-lib.sh` 와 같은 이유·같은 꼴이고, 설치(`install.sh --apply`)는 키트 `bin` 일반 파일을 통째로 cp 하므로 `REQUIRED` 목록 변경 0.
- 시험 `harness/tests/test_resource_selflink_r589.sh` ⓐ~ⓔ(가짜 센서·임시 루트·가짜 mbox · 실 루트·실 쪽지·삭제 0): ⓐ 자기 링크 → WARN 1줄 + 쪽지 1통(수신자 `_master` · «[장비 정리]» · «루트 FE 500 원인» · «지우기: unlink <경로>») 이고 링크는 그대로 ⓑ 같은 서명 다음 틱 = 쪽지·로그 중복 0, 대상이 바뀌면 1통 더 ⓒ 일반 폴더 `node_modules` → 0 ⓓ 폴더 없음 → 0 ⓔ planner `_master` 없음 = 로그 ERROR · 쪽지 0(조용한 통과 0). **전(origin/main 판 = 17칸 FAIL) → 후 20 PASS**(`evidence/r589/01-before-red-base.txt`·`02-after-pass.txt`).
- 기존 시험(카드 인접만 · 광역 0 · `evidence/r589/03-existing-tests.txt`): `test_resource_watch.sh`·`test_resource_watch_incremental_r534.sh`·`test_resource_cpu_owner.sh`·`test_resource_gate_pressure.sh` = fail=0 4/4 · `bash -n` 2종 rc0 · kit/bin 사본 cmp0 2 · 감시자 245줄(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 2(`kit/fable-team/bin/ft-resource-watch.sh`·`ft-resource-selflink-lib.sh` · `harness/bin` 짝 cmp0 2) + 시험 1 · manifest 1.1.134(r590 위로 rebase) · `install.sh` REQUIRED 변경 0 · **LIVE_BIN 설치(cmp0) · 감시 데몬 재기동 · 실사건 1(설치 뒤 감시 로그 1시간 «자기 링크» 0)은 master 소관 — 미실행.** 되돌림 = `.bak-r589`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다.
- 범위 밖: 좌석 손 명령 차단(훅) · 다른 폴더 링크 감시 · `ft-nano-spawn.sh` 링크 걸기(원인 아님) · 원인 좌석 추적 · 자동 삭제.

## 2026-10-21 — 뉴스 요약 프롬프트 안 줄 수 지시 둘이 어긋남(견본 «3줄 이하» ↔ 규칙 «1~2줄») → 견본·규칙 줄을 상한 상수 한 곳(SUMMARY_LINES - 1)에서 만든다 (r590 · 1.1.133 · 동작 변경 · ERROR 판정·자르기 규칙 무변경)

- 사건(master 87 발주 124059 · arch 112 실측 2026-10-21 01:5x · `/tmp/byz-ft-news-planner.log` 293행): r588 이 요약 첫 줄을 코드가 넣게 바꾸면서 규칙 줄은 «1~2줄» 로 고쳤는데, 같은 프롬프트의 «응답 꼴 견본» 은 옛 값 `["3줄 이하"]` 그대로였다 — 모델이 3줄을 내면 상태 줄까지 4줄이 되어 «요약 4줄·536B — 팀 상태 줄 포함 3줄·600B 이내여야 한다(자르지 않는다)» 로 발행 0.
- 고침(`ft_news_html_render.py` 2곳): `SCHEMAS["summary"]` 견본과 summary 갈래 규칙 줄의 줄 수를 둘 다 `SUMMARY_LINES - 1` f-string 으로 만든다 — 글자 숫자 하드코딩 0 · 상한을 바꾸면 둘 다 따라간다. `add_status_line` 의 ERROR 판정·문구, 바이트 상한(500/600)·상태 줄 내용(r588)·린트·다른 갈래 견본은 글자 그대로 무변경.
- 시험 `harness/tests/scripts/test_news_summary_schema_lines.py` ⓐ~ⓓ(가짜 opencode · 실 모델·슬랙·좌석 0): ⓐ summary 프롬프트 안 줄 수 숫자가 한 값(견본 «2줄 이하» · 규칙 «1~2줄») ⓑ 상한을 4로 바꾼 사본은 견본·규칙 줄이 «3» 으로 따라감(하드코딩 0) ⓒ 모델 3줄 = 상태 줄 포함 4줄 → `NewsHtmlError`(«자르지 않는다» · html 0) ⓓ 모델 2줄 + 상태 줄 = 3줄 → 통과(린트 0 · 상태 줄이 첫 줄). **전(origin/main 판 = ⓐ·ⓑ FAIL 2) → 후 4 passed**(`evidence/r590/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r590/03-existing-tests.txt`): `test_ft_news_html.py`·`test_news_team_status_line.py`·`test_news_summary_schema_lines.py` = 51 passed rc0. kit/bin 두 사본 cmp0 · `py_compile` rc=0 · ruff rc=0(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_news_html_render.py` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.132 · `install.sh` REQUIRED 변경 0 · **LIVE_BIN 설치(cmp0 1)·뉴스 데몬 재기동·실사건 1(틱 10회)은 master 소관 — 미실행.** 되돌림 = `.bak-r590`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다. `press 필요: 설치 뒤 뉴스 틱 10회 «요약 N줄 … 이내여야 한다» ERROR 0 + 발행 완료 원문` (master·tester 소관).
- 범위 밖: 상태 줄 내용(r588) · 바이트 상한 값 · 린트 · 다른 갈래 견본 · 공급자·재시도.

## 2026-10-21 — 팀 폴더 이동 확인(--verify)이 팀 폴더 «안» 파일만 봐 코드·시험에 박힌 옛 경로를 놓치던 것 → 코드·시험 옛 경로를 ERR 로 짚고 --plan 은 BEFORE code-ref 줄 + blockers (r587 · 1.1.132 · 동작 변경 · 적용/되돌림·자동 재작성 무변경)

- 사건(ops 쪽지 123753 · master 87 발주 123772 ③ · arch 112 실측 2026-10-21 01:2x): `design/cfo→teams/cfo`(ad7253b141)·`design/ops→teams/ops`(edbd9d2300) 이동 뒤 main 시험 6 FAIL — 이동 도구는 카드·명부·지도 같은 «저장 참조» 만 고치고, 코드·시험 안에 박힌 `design/<팀>/` 문자열은 보지 않았다. `--verify` 의 잔여 옛 경로 검사는 `folder.rglob("*")` = 팀 폴더 «안» 만 WARN. 남은 rag·sql 이동 때 시험 9파일 재발 예상(BYZ origin/main `git grep -l 'design/(cfo|ops|rag|sql)/' -- tests scripts` = 12파일).
- 고침(읽기 2곳 · `ft_team_move.py`만): 새 `code_refs(ctx, team)` — `git grep -n -F "design/<팀>/"` 1회(7초 룰 · 꼴 `*.py *.sh *.ts *.tsx *.js *.json *.toml *.yaml`), 히트 = (경로, 줄) 정렬 목록, 검색 실패(rc≠0·1)는 `ERROR … 검색 실패` rc1(조용한 통과 0). ①`--verify`: 히트마다 `ERR <팀> 코드 옛 경로 design/<팀>/ : <경로>:<줄>` + ERR 셈(끝줄 `VERIFY ERR=<n>`) ②`--plan`: `  BEFORE <팀> code-ref <n>` 줄 + blockers 에 n. **기록은 셈 밖** — `design/teams/<팀>/{archive,evidence,closeout}/**` · `design/teams/<팀>/CLOSEOUT*` · `.claude/archives/**` 는 새 ERR 과 기존 WARN(rglob) 둘 다에서 제외(옛 경로가 남는 게 정상인 기록). **코드 자동 재작성 0 · --apply·--revert·저장 참조 7종·점유 판정·종료 코드 규칙 무변경.**
- 시험 `harness/tests/test_team_move_code_refs.sh` ⓐ~ⓓ(임시 리포 · 가짜 tmux·lsof · 실 리포·seats·press 0): ⓐ 이동 뒤 `--verify x` = `ERR x 코드 옛 경로 design/x/ : tests/test_x.py:1`·`scripts/y.sh:2` + `VERIFY ERR=2` rc1(고치기 전 판 = ERR 0) ⓑ archive·evidence·CLOSEOUT 기록 3종은 ERR·WARN 0 + `code_refs` 직접 호출 = 코드·시험 2건만 ⓒ 이동 전 `--plan x` = `BEFORE x code-ref 2` + `PLAN-END blockers=2` ⓓ 옛 경로 0(기록만) = `VERIFY ERR=0` rc0. **전(origin/main 판 = 10 FAIL) → 후 ALL PASS**(`evidence/r587/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r587/03-existing-tests.txt`): `test_team_move_occupancy.sh`·`test_team_move_resume.sh`·`test_team_path_oldpath_md.sh` rc0 · `test_team_move_roundtrip.sh` rc1 = **FAIL 3 은 선행**(origin/main 판 파일로 같은 시험 돌린 `03b` 도 같은 3줄 — 꼴3 env 없음 케이스가 이 체크아웃의 HARNESS_ROOT 폴백을 타는 것 + `ⓑ' drift-check 건너뜀` 환경) · `bash -n` OK · `ast` OK · kit/bin 두 사본 cmp0(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_team_move.py` · `harness/bin` 짝 cmp0) + 그 도구 머리 주석(`ft-team-move.sh` --plan/--verify 설명 2줄) + 시험 1 · manifest 1.1.132 · `install.sh` REQUIRED 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치(cmp0 1) · 실사건 1(다음 팀 이동 `ft-team-move.sh --verify <팀>` 원문)은 master 소관 — 미실행.** 되돌림 = `.bak-r587`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다.
- 범위 밖: 코드 자동 재작성 · ops 몫 8파일 경로 수리 · 다른 팀 이동 실행 · `--apply` 재작성 대상(TEAMS.md·카드·지도·.gitignore·명부·baton) · 점유 판정 · press.
## 2026-10-21 — 뉴스 요약의 «팀 상태» 문장 때문에 발행 0(2판: 린트 오판 + 모델 지어냄) → 팀 상태 줄은 코드가 만들어 요약 첫 줄로 넣고, 린트는 «확인 불가 팀이 든 절» 안에서만 쉼 단정을 본다 (r588 · 1.1.131 · 동작 변경 · ALL_STOP·APPROVAL_WAIT 규칙 무변경)

- 사건(master 87 발주 123789 · arch 112 실측 2026-10-21 01:3x · `/tmp/byz-ft-news-planner.log`): ①00:57 판 요약 «지금은 다섯 팀(chatbot·loom·planner·ops·v65)이 일하고, 다섯 팀(cfo·issues·kk·lecture·room)이 쉬며, 세 팀(feature·graphics·harness)은 상태 확인 불가다» — 문장은 확인 불가 3팀을 «확인 불가» 로 맞게 썼는데 린트가 위반 3건으로 발행 0(문장 단위로 «팀 이름 ∧ 쉼 글자» 를 봤다 · `ft_news_html_lint.py:78-85`) ②01:02 판 «일하는 팀 6개인데 «모든 팀 정지» 문장» = 모델 오류 — 프롬프트 `FACT_RULES`(:55-57)에 이미 «확인 불가 팀은 쉬는 팀이 아니다» 가 있는데도 났다 = 프롬프트 보강만으로는 이미 실패한 꼴.
- 고침 1(`ft_news_html_render.py` · 상태 줄 코드화): 새 함수 `status_line()` 이 `bucket()`(좌석·jsonl 실측)이 정한 셋에서 «일하는 팀 N개: … · 쉬는 팀 M개: … · 상태 확인 불가 K개: …» 1~3문장을 만들고(0개 칸 생략), `add_status_line()` 이 그 줄을 요약 **첫 줄**로 넣는다. summary 갈래 프롬프트 = «1~2줄 · 첫 줄은 코드가 넣는다 · 팀 상태(일함·쉼·정지·확인 불가·몇 팀)는 쓰지 말 것» 2줄로 교체. 상태 줄 포함 3줄·600B 를 넘으면 **모델 줄을 자르지 않고 `NewsHtmlError`(발행 0)** — 조용한 자르기 0.
- 고침 2(`ft_news_html_lint.py` · `unknown_problems`): 판정 단위를 «문장» → «절»(CLAUSE_END 로 나눈 조각)로 좁혔다 — 팀 이름이 든 절에만 `_rest_asserted` 를 적용하고, 같은 문장의 다른 절(«…이 쉬며»)은 보지 않는다. **보고 문구는 문장 그대로**(기존 시험 문구 불변) · 진짜 단정(«feature 는 쉬고 있다»)은 그대로 잡는다 · ALL_STOP·APPROVAL_WAIT·important/goals/teams 갈래·공급자·재시도 무변경.
- 시험 `harness/tests/scripts/test_news_team_status_line.py` ⓐ~ⓔ(가짜 opencode · 실 모델·슬랙·좌석 0): ⓐ 00:57 문장 그대로 → 위반 0 ⓑ «feature 는 쉬고 있다»·«graphics 는 멈춘 상태다»·«harness 는 대기 중이다» 는 그대로 위반 ⓒ 코드가 만든 상태 줄 = 요약 첫 줄(0개 칸 생략 · 모델 줄은 그 뒤) 이고 `lint.problems == []` ⓒ2 3줄·600B 초과 = `NewsHtmlError`(«자르지 않는다» · html 0) ⓓ 모델 «모든 팀이 멈췄다» = «일하는 팀 1개인데» 위반 + `publish_files` rc3(발행 0) ⓔ `facts` 팀 수·이름 = 상태 줄 수·이름(일하는 6 = 줄의 6). **전(origin/main 판 = ⓐ·ⓒ·ⓒ2·ⓔ FAIL 4)·후 8 passed**(`evidence/r588/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r588/03-existing-tests.txt`): `test_ft_news_html.py`·`test_news_truncated.py`·`test_news_direct_api.py`·`test_news_html_cli_startup.py` = 69 passed rc0. 요약이 «상태 줄 + 모델 2줄» 로 바뀌므로 그 꼴을 박아 둔 3칸(`CONTENT["summary"]` 3→2줄 · 요약 첫 줄 단언 · 슬랙 본문 첫 줄 단언)만 새 꼴로 맞췄다 — 판정 규칙 변경 0.
- 설치: 있음 — 키트 2(`kit/fable-team/bin/ft_news_html_render.py`·`ft_news_html_lint.py` · `harness/bin` 짝 cmp0 2) + 시험 1 · manifest 1.1.131 · `install.sh` REQUIRED 변경 0 · **LIVE_BIN 설치·뉴스 데몬 재기동·실사건 1(틱 10회 린트 위반 0)은 master 소관 — 미실행.** 되돌림 = `.bak-r588`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다. `press 필요: 설치 뒤 뉴스 틱 10회 요약 첫 줄이 코드 상태 줄 원문인지 + «LINT» 0` (master·tester 소관).
- 범위 밖: ALL_STOP·APPROVAL_WAIT 규칙 · important·goals·teams 갈래 · 공급자·요청 필드(r582) · 재시도 · 402 크레딧 · 뉴스 발행 간격.


## 2026-10-21 — desk 의 오빠 글 답이 그 글 스레드 뿌리를 안 읽고 번호 3줄로 나가던 것 → 게시 «전» 뿌리 원문을 읽어 보여 주고 본문 3검사 (r585 · 1.1.130 · 동작 변경 · 답 자리 판정·--thread 거절 무변경)

- 사건(오빠 슬랙 1792511760 질책 · desk 123741 · master 87 발주 123772 ① · arch 112 실측 2026-10-21 01:2x): `thread_reply_slack.py` 의 `reply_to_slack` 은 오빠 글 ts 로 «답 자리» 만 정하고 그 글·스레드 뿌리 원문은 읽지 않았다 — 답하는 좌석이 «무엇을 물었는지» 를 도구에서 못 보고, 실제로 제안서 스레드 질문을 다른 스레드로 착각한 번호·약어 3줄 답이 나갔다.
- 고침(파일 1 · `kit/slack-mirror/thread_reply_slack.py`): ①게시 «전» `conversations.replies`(ts = 뿌리 · 7초 상한 · GET 재시도 1 = `mirror_lib.api_call`)로 뿌리 원문을 읽는다 — HTTP 실패·빈 뿌리는 REJECT(조용히 게시 0 · 답 기록도 안 씀) ②본문 검사 ⓐ첫 줄 «요청 N개 중 M개 답함» 없음 ⓑ번호·약어 꼴 줄(`r\d+`·`#\d+`·`K4b` 꼴)이 3줄 이상이고 절반 초과 ⓒM < N 인데 «남은 것:» 줄 없음 → REJECT ③REJECT 문구에 뿌리 원문 앞 400자 + «쓰는 법: 첫 줄 … · 남으면 «남은 것: …» · 번호 대신 쉬운 말» 을 붙인다(답하는 사람이 읽게) ④통과만 지금 흐름 그대로 게시(`post_guard` 사람 채널 검사 · 답 기록). **답 자리 판정(r558) · `--thread` 거절(r561) · `post --to` 방 글 · 쪽지 보고 틀은 글자 그대로 무변경.**
- 시험 `harness/tests/scripts/test_thread_reply_to_slack.py` ⓐ~ⓔ + 기존 9칸(가짜 Slack · 실 슬랙 0): ⓐ 선언 줄 없음 = REJECT + 뿌리 원문 + «요청 N개 중 M개 답함» 안내 · 게시 0 ⓑ 번호·약어 4줄 = REJECT «쉬운 말로» ⓒ «요청 3개 중 1개 답함» + «남은 것:» 없음 = REJECT ⓓ 선언 + 쉬운 말 + «남은 것:» = 게시(뿌리 ts 밑) ⓔ `conversations.replies` HTTP 실패 = REJECT «뿌리 글 읽기 실패» · 게시 0. **전(옛 판 = ⓐ~ⓔ 중 4칸 FAIL · ⓓ 만 통과) → 후 15 passed**(`evidence/r585/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r585/03-existing-tests.txt`): `test_thread_room_post.py` + `test_byz_slack_mbox_inbound.py` + `test_byz_mbox_slack_mirror.py` = 80 passed · `test_thread_reply_named.sh` ALL PASS. **선행 FAIL 1(내 변경 무관)**: `test_thread_room_post.py::test_thread_desk_force_sends_with_warning` 은 origin/main 판에서도 같은 칸으로 실패(`03b-preexisting-base.txt`) — 손대지 않음. `test_thread_room_post.py::test_existing_paths_unchanged` 는 r585 동작 변경(선언 줄)에 맞춰 본문·뿌리 1줄만 갱신.
- 설치: 있음 — 키트 1(`kit/slack-mirror/thread_reply_slack.py` → `~/.hermes/scripts/` cp -p → cmp0 1 · 답 도구는 호출마다 새로 뜨므로 수신 데몬 재기동 0). **설치·실사건 1(desk 가 오빠 글에 `reply --to-slack <ts>` 1회 → 답 첫 줄 «요청 N개 중 M개 답함» + 그 글 밑 원문)은 master 소관 — 미실행**(`04-kit-live-diff.txt`: 설치 전 diff 42줄). 되돌림 = `.bak-r585`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다.
- 범위 밖: `post --to desk` 방 글 · 쪽지(mbox) 보고 틀(`GUIDE-human-report`) · 요청 개수 자동 세기 · 답 자리 판정(r558) · `--thread` 거절(r561) · `test_thread_desk_force_sends_with_warning` 선행 실패.

## 2026-10-21 — 뉴스 시험 두 파일을 같이 돌리면 원장 동기화 env 가 새어 순서 의존 FAIL 1 → 시험 준비 자동 픽스처가 그 두 값을 시험마다 지움 (r584 · 설치 없음 · 동작 변경 0 · 시험 파일만)

- 사건(arch 112 실측 2026-10-21 01:1x · r569 나노 쪽지 123636 «선행 FAIL 1(내 변경 무관)»): 팩 origin/main 판에서 `pytest tests/scripts/test_news_direct_api.py tests/scripts/test_ft_news_html.py` 를 «한 번에» 돌리면 `1 failed, 54 passed` — `test_ft_news_html.py::test_h_head_phrase_one_place_and_deadline_70` 의 머리 줄이 `[뉴스 09:15] 팀 지도 · 원장 ref fetch 실패 — fatal: 'origin' does not appear to be a git repository` 로 나온다. 각 파일 단독은 초록(16·39) — 순서 의존.
- 원인(키트 변경 0 · 설계는 그대로): 뉴스 원장 동기화는 «이번 틱에 했다»(`FT_LEDGER_SYNCED=1`)와 «실패 문구»(`FT_LEDGER_SYNC_ERROR`)를 **프로세스 전역 env** 에 적는다(`bin/ft_news_ledger.py:212·214·231`) — 틱 자식 프로세스에 물려주려는 설계라 실 틱(1회 실행)에서는 옳다. 시험은 한 프로세스에서 여러 시험을 돌리므로 앞 시험이 적은 값이 뒤 시험에 남고, 틱이 그 값을 `FT_NEWS_HEAD` 머리에 붙여(`bin/ft_news_html.py:249-251`) 다음 시험의 고정 문구 단언이 깨진다. 누수 자국(`evidence/r584/04-leak-trace-and-minimal-repro.txt`): 첫 누수 = `test_f_sync_skipped_within_120s`(SYNCED='1'), 첫 «실패 문구» = `test_i_ledger_read_from_origin_main_not_checkout_head`(임시 리포에 origin 없음 → `fatal: 'origin' does not appear…`).
- 고침(1곳 · 시험 파일): `harness/tests/scripts/conftest.py` 에 자동 픽스처 `_ledger_sync_env_off` — 시험마다 `monkeypatch.delenv("FT_LEDGER_SYNCED"/"FT_LEDGER_SYNC_ERROR", raising=False)`, 끝나면 monkeypatch 가 되돌린다. 그 폴더(`tests/scripts`)의 공용 자동 픽스처 자리라 두 파일이 같이 덮이고, 시험이 스스로 그 값을 쓰는 칸(`test_f` 의 `FT_LEDGER_SYNCED=0`)은 그대로 동작. **키트·LIVE_BIN·홈·데몬·install.sh REQUIRED·manifest 변경 0.**
- 시험(`evidence/r584/01-before-red.txt`·`02-after-pass.txt`·`04-leak-trace-and-minimal-repro.txt`): ⓐ 전(origin/main 판) 두 파일 한 번에 = `1 failed, 54 passed` rc=1 → 후 = `55 passed` rc=0 ⓑ 순서 바꿔(html 먼저) = `55 passed` ⓒ 각 파일 단독 = api `16 passed` · html `39 passed`(전과 같은 수). 최소 재현 = 앞 파일 전체 + `test_h` 1개: 전 `1 failed, 16 passed` → 후 `17 passed`.
- 인접 기존 시험(광역 0 · `03-adjacent-tests.txt`): `test_ft_news_ledger`·`test_ft_news_io`·`test_news_fetch_cap`·`test_ft_news_goal_block`·`test_ft_news_ledger_notify`·`test_ft_news_publish`·`test_news_status_section`·`test_news_truncated` = 전 90 passed · 후 90 passed(자동 픽스처가 남의 시험을 깎지 않는다).
- 설치: 없음 — 시험 파일 1(`tests/scripts/conftest.py`) + 증거 5 · 키트 파일 변경 0(설치 대조 대상 0) · 데몬 재기동 0. **실사건 1(팩 origin/main 두 파일 한 번에 «0 failed» 원문)은 master 소관 — 미실행.** 되돌림 = 이 커밋 revert. (r582 착지 뒤 origin/main `0d3ae97d` 위로 rebase — CHANGES 는 r582 절 보존 후 r584 절을 위에)
- 범위 밖: 원장 동기화 설계(env 로 자식에 물려주는 방식) · `ft_news_html.py` 머리 줄 규칙 · 다른 시험 폴더 · r569 내용 · press(나노는 쏘지 않는다).
## 2026-10-21 — 뉴스 important 갈래가 «잘린 답» 으로 발행 0 을 반복 → 끝난 이유·생각 글자수 기록 + 잘림을 «답이 잘림» 으로 이름 붙임 + 요청에 생각 끄기 1필드 (r582 · 1.1.129 · 동작 변경 · 재시도 규칙 무변경)



- 사건(master 87 발주 123497 ① · arch 112 실측 2026-10-21 00:4x · 오빠 슬랙 1792509798): deepseek 교체(r575) 뒤 뉴스 «중요한 일» 갈래가 가끔 «important 응답이 JSON 아님: Expecting ',' delimiter: line 1 column 686·324·702» 또는 «답 글 0자» 로 죽어 그 판 발행 0. 깨진 열이 매번 답 끝 근처 = 답이 중간에 잘린 모양인데, 코드는 답 글만 모으고 **끝난 이유(finish_reason)·생각(reasoning_content) 양·usage 를 버려** 로그로 원인을 가를 수 없었다(`_json` 은 첫 `{` ~ 마지막 `}` 를 잘라 읽으므로 잘림이 «JSON 문법 오류» 로 둔갑).
- 0단계 측정(`evidence/r582/00-measure.txt` · 실설치본과 같은 요청 · 프롬프트 14,302B · 실 공급자): **같은 요청 5회 중 2회 실패 = 둘 다 `finish_reason=length`** — 1회는 답 0자(생각 13.5K자) · 1회는 답 472자에서 끊김. 정상 3회도 생각 8.7K~13.5K자(≈2.9K~4.5K 토큰)로 `max_tokens 4096` 을 생각이 먼저 먹었다(usage 확인: completion 3,325 · 생각 8,690자). 갈래 = ⓐ(length + 생각 큼).
- 고침 3곳(모두 `ft_news_html_render.py`): ①`_sse_text` 가 `finish_reason`(마지막 값)·`usage`·`reasoning_content` 글자 수를 함께 돌려줌(답 글은 지금처럼 content 만) ②`_http_once` 실패 문구에 «끝난 이유=… · 답 N자 · 생각 M자» 를 붙이고, `finish_reason=length` 면 «<갈래> 답이 잘림(finish_reason=length · 답 N자 · 생각 M자) — 발행 0» 으로 이름 붙인다(JSON 파싱 오류로 오해 금지) ③요청 본문에 `REASONING_OFF = {"reasoning_effort": "none"}` 1필드 — 0단계에서 후보 7종을 재어 «생각 0자 · JSON OK» 가 3/3 으로 나온 필드(같은 효과의 `thinking.type=disabled`·`chat_template_kwargs.thinking=false` 는 공급자 확장이라 OpenAI 호환 이름을 골랐다) · 공급자가 이 필드를 4xx 로 거부하면 `HTTP 400 — 생각 끄기 필드(reasoning_effort) 거부: <본문 160자>` 를 ERROR 로 남긴다(조용히 빼고 보내기 0). **재시도 규칙(전역 하드 룰 12 · 출력 시작 뒤 0회)·직전 판 대체·다른 갈래 프롬프트·공급자 교체·fetch(r569)·발행 간격은 글자 그대로 무변경.**
- 시험 `harness/tests/scripts/test_news_truncated.py` ⓐ~ⓔ(가짜 SSE 서버 · 실 모델·슬랙 0): ⓐ 잘린 JSON + length → «답이 잘림·finish_reason=length·생각 N자» 이고 «Expecting ',' delimiter» 아님 · 발행 0 ⓑ content 0 + 생각만 + length → «답 0자 · 생각 N자 · 끝난 이유=length» ⓒ 정상 stop + 온전한 JSON → 그대로 성공(지도·요약 파일) ⓓ 요청 본문 `reasoning_effort=none` 4갈래 전부 + 400 이면 «HTTP 400 — 생각 끄기 필드(reasoning_effort) 거부» ⓔ 출력 시작 뒤 끊김 = important 호출 1회(재시도 0). **전(origin/main 판 = ⓐ·ⓑ·ⓓ FAIL) → 후 ALL PASS**(`evidence/r582/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r582/03-existing-tests.txt`): `test_news_direct_api.py` + `test_ft_news_html.py` = 54 passed · **1 failed 는 이 카드와 무관한 이미 있던 것** — origin/main 판 render 로 돌린 `03b` 도 «1 failed, 54 passed» 로 같다(`ft_news_ledger.py` 가 `FT_LEDGER_SYNC_ERROR` 를 os.environ 에 남겨 뒤 파일로 새는 것 · 단독 실행 통과 · 손대지 않음). `test_news_truncated.py` 단독 5 passed · kit/bin 두 사본 cmp0 · `py_compile` rc=0(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_news_html_render.py` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.129 · `install.sh` REQUIRED 변경 0 · **뉴스 데몬 재기동은 master 소관 — 미실행.** (r583 착지 뒤 origin/main a61419cf 위로 rebase — CHANGES 는 이 절을 맨 위에, r583 절 보존) 되돌림 = `.bak-r582`. press(라이브 오디오 시험) 아님 — 나노는 쏘지 않는다.
- 범위 밖: 재시도 규칙 · 직전 판 대체 · 다른 갈래 프롬프트 내용 · 공급자 교체 · fetch(r569) · 발행 간격 · `FT_LEDGER_SYNC_ERROR` 누수(다른 카드 몫).

## 2026-10-21 — 설치 대조기가 팀 env 의 FT_BIN(연결 파일 폴더)을 라이브로 보고 연결 파일 자체를 해시 비교하던 것 → 연결 파일이면 판 폴더(LIVE_BIN) 파일과 대조 (r583 · 1.1.127 · 동작 변경 · 판정 규칙·종료 코드 규칙 무변경)

- 사건(master 87 발주 123538 · arch 112 실측 2026-10-21 00:5x · 카드 r583): 판정 난 카드 16장(r527·r538·r542·r544·r545·r548·r549·r551·r557·r559·r563·r566·r570~r575)이 `ft-index-move.sh … 완성` 에서 `rc=1 live=<연결 파일 해시> tip=<키트 해시>` 로 막혔다(이동 4/16). 원인은 대조기가 아니라 «대조 대상» — 팀 env 8곳의 `FT_BIN` 이 `<루트>/.worktrees/<팀>/.fable-team/bin`(연결 파일 폴더)인데 `ft_live_install_check.py:413` 이 그 폴더의 연결 파일(shim · 717바이트)을 키트와 해시 비교했다. 같은 파일 안의 `is_shim`·`shim_deps`(연결 파일 → `../LIVE_BIN`)는 데몬 재기동 판정에만 쓰이고 bin 행 대조에는 안 쓰였다.
- 고침(1곳 · `kit/fable-team/bin/ft_live_install_check.py` bin 행 대조): 새 함수 `shim_compare(lp)` — 라이브 파일이 연결 파일이면 `<그 폴더>/../LIVE_BIN` 1행의 판 폴더에서 같은 상대 경로 파일을 대조 대상으로 삼는다(`shim_deps` 와 같은 풀이). DIFF/MISSING 줄 끝에 `via shim → <판 폴더>`. 못 풂 = `../LIVE_BIN` 없음 → MISSING · LIVE_BIN 이 절대경로 폴더 아님 → ERROR(종료 3 · 조용한 OK·조용한 폴백 0) · 판 폴더 파일 없음 → MISSING(통과로 후퇴 0). **연결 파일이 아니면 동작 불변**(판정 규칙·EXEC-BIT·MODE·UNMAPPED·STALE 등 그대로).
- 시험 `harness/tests/test_live_install_check_bin_row_shim.sh` ⓐ~ⓓ + 오염 1(임시 HOME·임시 git 리포·임시 판 폴더·임시 연결 파일 · 실 라이브·실 원격·press·Redis 0): ⓐ 연결 파일 → 판 폴더 파일 대조 = `OK n=1` rc0 ⓑ 판 폴더 어긋남 = 진짜 DIFF + `via shim → 판 폴더` ⓒ1 `../LIVE_BIN` 없음 = MISSING rc1 ⓒ2 LIVE_BIN 절대경로 아님 = ERROR rc3 ⓒ3 판 폴더 파일 없음 = MISSING rc1 ⓓ FT_BIN = 판 폴더 = 동작 불변 rc0. **전(origin/main 판 = ⓐ 포함 5칸 FAIL) → 후 ALL PASS**(`evidence/r583/01-before-red.txt`·`02-after-pass.txt`).
- 실사건 재현(읽기 전용 · 쓰기 0 · `evidence/r583/04-real-case-readonly.txt`): 범위 `41af1eed..ab9d3b7a` · `FT_BIN=<팀 env 연결 파일 폴더>` — 옛 판 `PENDING n=4`(DIFF 4 · live=연결 파일 해시) rc=1 → 고친 판 `OK n=4 skip=0` rc=0 · `FT_BIN=<판 폴더>` = `OK n=4` rc=0(불변). arch 112 실측값과 일치.
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r583/03-existing-tests.txt`): `test_live_install_check.sh`·`_shim`·`_tip`·`test_install_check_repo_outside.sh` 모두 rc=0 · `bash -n` OK · kit/bin 두 사본 cmp0(`05-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_live_install_check.py` · `harness/bin` 짝 cmp0) + 시험 1파일 · manifest 1.1.127 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치(cmp0 1) · 실사건 1(팀 env 그대로 16장 `ft-index-move.sh … 완성` → «OK 설치 확인» + MOVED 16 원문)은 master 소관 — 미실행.** 되돌림 = `.bak-r583`.
- 범위 밖: 팀 env 8곳의 `FT_BIN` 값 · 연결 파일 생성기(`ft-root-bin-shim.sh`) · shim 존재 검사(`shim_items`) · STALE-COPY · plist 검사 · `ft-index-move-install.sh` · press(나노는 쏘지 않는다).

## 2026-10-21 — 뉴스 틱 원장 ref fetch 상한이 CLI 기동 고정비를 빼고 7초이던 것 → 시도당 10.5초(총 마감 70초) + 실패 경고에 «N분 전 받은 판» (r569 · 1.1.127 · 동작 변경)

- 사건(arch 111 실측 2026-10-20 22:1x · master 86 발주 122284 · 카드 r569): r563 이 넣은 `fetch_if_stale` 이 `subprocess.run(..., timeout=7)` × `range(2)` 였다. `git fetch` 는 CLI 서브프로세스인데 7초 룰의 «기동 고정비 3.5초»(전역 하드 룰 12)가 빠져 부하 평균 37~45 에서 실측 5.05초·2.97초 = 상한 턱밑. `/tmp/byz-ft-news-planner.log` 194줄 중 7회 «원장 ref fetch 실패 … timed out». 발행은 이미 지금 ref 로 계속(r563 · 188행 «발행 완료»)이지만 경고에 «그 ref 가 몇 분 전 판인지» 가 없었다.
- 고침 ①(상한): `FETCH_TIMEOUT_S = 10.5`(3.5 + 7) · `FETCH_BUDGET_S = 70.0` · 새 함수 `_attempt_timeout(spent)` = `min(FT_NEWS_FETCH_TIMEOUT(기본 10.5), FT_NEWS_FETCH_BUDGET(기본 70) - spent)` — 재시도 1(`range(2)`) 그대로, env 로 크게 줘도 70초에서 자른다.
- 고침 ②(경고): 실패 문구 = `원장 ref fetch 실패 — <원인 160자> · origin/main = <N>분 전 받은 판` — N = `_fetch_age(_fetch_stamp(repo))` = FETCH_HEAD mtime(새 함수 `_fetch_age` · 없거나 못 읽으면 «받은 시각 모름»). `LOG.error` 와 `FT_LEDGER_SYNC_ERROR` 가 **같은 문구**.
- 시험 `harness/tests/scripts/test_news_fetch_cap.py` ⓐ~ⓔ(가짜 `FT_LEDGER_FETCH` 스크립트 sleep + 임시 리포 FETCH_HEAD mtime · 실제 원격·슬랙 0): ⓐ 8초 fetch = 고친 판 성공·1회로 끝(옛 판 = 7초 초과 실패) ⓑ 11초 × 2 = 둘 다 실패 · 시도당 10.5초 · 합 ≤ 22.5초 · 경고에 «origin/main = 40분 전 받은 판» · 머리 줄 = 로그 문구 ⓒ FETCH_HEAD 없음 = «받은 시각 모름» ⓓ FETCH_HEAD 300초 안 = fetch 0(지금 동작) ⓔ `_attempt_timeout` = 55/3/≤0(마감 70초에서 자름). **전(origin/main 판 = 5 FAILED) → 후 5 passed**(`evidence/r569/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0 · `03-existing-tests.txt`): `test_news_direct_api.py` 16 · `test_ft_news_ledger.py` 24 · `test_ft_news_html.py` 39 · `test_ft_news_io.py` 1 = 80 passed FAIL 0. **선행 FAIL 1(내 변경 무관)**: 두 파일을 «한 번에» 돌리면 `test_news_direct_api` 가 남긴 env `FT_LEDGER_SYNC_ERROR` 가 `test_ft_news_html::test_h` 로 새어 머리 줄이 달라진다 — origin/main 판에서도 같은 칸(`04-preexisting-fail.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_news_ledger.py` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.127 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치(cmp0 1) · 뉴스 데몬 재기동 · 실사건 1(설치 뒤 뉴스 로그에서 «ref fetch 실패» 수 · 나오면 «분 전 받은 판» 조각)은 master 소관 — 미실행.** 되돌림 = `.bak-r569`.
- 범위 밖: 402(크레딧) · 사본 체크아웃 동기화(`sync_repo`) · `_fetch_stamp` 의 rev-parse 7초(로컬 명령) · `FT_NEWS_FETCH_MIN` 건너뜀 규칙 그대로 · 뉴스 발행 간격 · 다른 fetch 도구 · press(나노는 쏘지 않는다).
## 2026-10-21 — 완성 이동 설치 게이트가 하네스 파일 대조에 «카드 워크트리» 리포를 넘기던 것 → 하네스 루트의 리포(도구 기본값)로 (r581 · 1.1.126 · 동작 변경 · 대조 도구 판정 무변경)

- 사건(master 87 발주 123398 ① · arch 112 실측 2026-10-21 00:3x): 팩 착지 카드 9장(r527·r538·r545·r544·r548·r546·r551·r550·r549)이 `완성` 이동에서 rc=3 «하네스 루트가 --repo 밖 — --kit 를 준다» 로 막혔다(이동 0). 원인은 `ft-index-move-install.sh:26` 이 `bash "$CHK" --range "$RANGE" --repo "$WT"` 로 **카드 워크트리(BYZ)** 를 대조 리포로 넘긴 것 — BYZ 리포에 팩 착지 ref(`refs/pack-landing/harness-main`)가 들어온 뒤로는 그 리포에서도 `:(glob)**/harness/kit/**` 변경이 보여 `ft_live_install_check.py` 의 `outside_repo()` 가 설계대로(fail-closed) 막았다. 도구는 맞게 막았고 «문»이 틀린 리포를 넘겼다. 같은 범위를 하네스 루트 리포로 돌리면 `OK n=4 skip=0` rc0.
- 고침(호출 인자 1개 제거): 대조 호출에서 `--repo "$WT"` 를 뺀다 — 도구 기본값 = 하네스 코드 루트(`FT_HARNESS_ROOT` · `../HARNESS_ROOT`)의 리포 · 키트 = 그 리포 기준 `kit/`. 주석 1줄 «r581: 하네스 파일 대조는 하네스 루트 리포 — 카드 워크트리 아님». **`ft_live_install_check.py` 의 fail-closed 판정·`ft-index-move.sh`·install-pending 정리(`git -C "$WT" rev-list`)·카드 꼬리 줄 규칙은 글자 그대로 무변경.**
- 시험 `harness/tests/test_index_move_install_harness_repo.sh` ⓐ~ⓓ + 오염 1: 임시 리포 2개(하네스 리포 = 팩 꼴 경로 `feature-pack/fable-team/harness/kit/…` · 범위 A..B 가 키트 1파일 변경 / 카드 리포 = 그 객체를 fetch 해 둔 꼴 = BYZ 실사건 재현) ⓐ 검사 도구 주입(받은 인자 기록) → 게이트가 `--repo` 를 넘기지 않는다 ⓑ 실제 `ft-live-install-check.sh` 로 같은 꼴 → 하네스 루트 리포 = `OK n=1` rc0 · 변이(카드 리포를 `--repo` 로) = `ERROR … 밖` rc3(옛 판 재현 · fail-closed 그대로) ⓒ `설치: 없음` 카드 = 대조 호출 0 · 통과 rc0 ⓓ 하네스 루트를 못 풂 = REJECT rc1(통과로 후퇴 0) + core.bare 오염 0. **전(origin/main 판 = ⓐ·ⓑ FAIL rc=1) → 후 ALL PASS**(`evidence/r581/01-before-red.txt`·`02-after-pass.txt`).
- 실사건 재현(읽기 전용 · 쓰기 0 · `evidence/r581/04-real-case-readonly.txt`): r545 범위 `0a0844b4..4355379f` — 옛 판 꼴(`--repo` = BYZ harness-ops 워크트리) `ERROR … 범위에 하네스 파일 4` rc=3 · 고친 판 꼴(`--repo` 없음) `OK n=4 skip=0` rc=0. arch 112 실측값과 일치.
- 기존 시험(이 카드 인접만 · 광역 0 · `evidence/r581/03-existing-tests.txt`): 설치·이동 게이트 12종 rc=0 — `test_live_install_check_tip.sh`(ⓕ 픽스처에 `--repo` 를 시험이 준다 = 게이트 계약 변경 반영) · `test_live_install_check.sh` · `_shim` · `test_install_check_repo_outside.sh` · `index_move_canon_{landed,route,canonize,rule_line}` · `index_move_slack` · `da_hold_gate_landed` · `team_literal_paths2` 모두 FAIL 0 · `bash -n` OK · kit/bin 두 사본 cmp0(`05-kit-bin-cmp.txt` · 35줄 ≤60).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-index-move-install.sh` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.126 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치(cmp0 1) · 실사건 1(판정 난 9장 `FT_LAND_REF=refs/pack-landing/harness-main ft-index-move.sh … 완성` → «OK 설치 확인» + MOVED 9)은 master 소관 — 미실행.** 되돌림 = `.bak-r581`.
- 범위 밖: `ft_live_install_check.py` 의 fail-closed 판정(r385 r4) · `ft-index-move.sh` · 카드 꼬리 줄 규칙 · press(나노는 쏘지 않는다).

## 2026-10-21 — 부팅 보고 lint 의 «발동 조건» 이 첫 줄 정확히 `[부팅 보고]` 일 때만 돌던 것 → 머리(`[<보낸이>-><받는이>]`)를 떼고 보되 머리 안에 «부팅 보고» 가 있으면 검사 (r577 · 1.1.125 · 동작 변경 · 검사 규칙 무변경 · origin/main ca1c277f(r580) 위로 rebase)

- 사건(planner arch 8 제안 ③ · master 87 발주 123168 · 카드 r577 · arch 111 실측 2026-10-20 23:5x): 쪽지 가드는 `mbox_guard.sh` `_guard_boot_lint` 가 **첫 줄이 정확히 `[부팅 보고]` 로 시작할 때만** 돌았다. 그런데 통신 표준(BOOT 5)은 `[<보낸이>-><받는이>]` 머리를 앞에 붙이라고 하고, 승계 좌석들은 `[feature master#35 부팅 보고]` 처럼도 쓴다 — 그래서 **검사가 한 번도 돌지 않았고**, 교대 뒤 명부 누락 2건(planner 84→85 · feature 34→35 «retire=… 후계 보고로 대체»)이 그대로 전송됐다. arch 111 자기 부팅 보고(`[…->…] 부팅 보고: …`)도 같은 이유로 검사 0 이었다.
- 고침(1곳 · `harness/comm/mbox_guard.sh` `_guard_boot_lint` 첫 줄 판정): 첫 줄 → 앞 공백 제거 → 앞의 `[<x>-><y>]`(또는 `→`) 머리 **1개** 제거 → 남은 줄이 `[` 로 시작해 첫 `]` 안에 «부팅 보고» 이거나 «부팅 보고» 로 시작(`:`·공백)이면 lint 실행 · 그 밖은 지금처럼 건너뜀. **lint 호출·rc 처리·REJECT/WARN 문구·검사 규칙(`ft-boot-report-lint.py`)은 글자 그대로 무변경** · 줄 수 200 유지(≤200 계약).
- 시험 `harness/tests/test_boot_report_gate.sh` R577-ⓐ~ⓕ + 변이5: ⓐ(머리 붙은 꼴 + retire 칸 꼴 아님 → REJECT rc3·큐 0) ⓑ(`[팀 master N번 부팅 보고] … 후계 보고로 대체` → REJECT) ⓒ(`[a->b] 부팅 보고:` + 올바른 retire 칸 + 명부 반영 → OK)·ⓒ'(머리 화살표가 `→` 여도 같은 판정) ⓓ(머리 없는 `[부팅 보고]` 꼴 = 종전과 같은 판정) ⓔ(첫 줄에 «부팅 보고» 없고 본문 아래에만 → 검사 0 · 오탐 0) ⓕ(`[부팅]` 등 다른 머리 → 검사 0) ⓓ'/ⓓ''(머리 없는 `[부팅 보고]` 본문에 화살표 `->` 가 있어도 머리로 오인해 떼지 않는다 — 칸 없으면 REJECT · 칸 맞으면 OK) · 변이5(발동 조건을 옛 판으로 되돌리면 ⓐ·ⓑ 빨강). **전(origin/main 판 = ⓐ·ⓑ FAIL rc=0) → 후 ALL PASS**(`evidence/r577/01-before-red.txt`·`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0): `test_mbox_guard.sh` ALL PASS(`03-existing-mbox-guard.txt` — 명부 8종×머리 8종 표 · planner 머리 · relay · drift · 정지 쪽지) · `bash -n` OK · 기존 ⓐ~ⓗ 칸 판정 무변경.
- 실사건 읽기 전용(`04-real-cases-readonly.txt` · 발신 0 · 쓰기 0): 실제 우편함 본문 3건을 새 발동 조건으로 돌리면 planner#85(`[…->…] [부팅 보고] … retire rc=0`) · feature#35(`[feature master#35 부팅 보고] … retire=#34 후계 보고로 대체`) · arch#111(`[…->…] 부팅 보고: …`) 모두 **예전 = 검사 0, 지금 = REJECT «retire 칸 없음: …»** — 누락 2건이 실제로 잡힌다.
- 설치: 있음 — 팩 `harness/comm/mbox_guard.sh` 1파일(comm 설치 경로 r459 = 루트 `.fable-team/comm` · kit 사본 0 · `check-drift.sh` MAP 행 그대로) + 시험 1파일 · manifest 1.1.124 · 데몬 재기동 0. **LIVE 사본 설치(cmp0 1) + 실사건 1(다음 승계 좌석의 머리 붙은 부팅 보고가 retire 칸 없으면 REJECT)은 master 소관 — 미실행.** 되돌림 = `.bak-r577`.
- 범위 밖: lint 검사 규칙 · 명부 누락 2건 손 복구(그 팀 몫) · planner 머리 규칙(`_guard_planner_head`) · 부팅 보고를 머리 없이 쓰게 하는 안내 · press(나노는 쏘지 않는다).

# Changes

## 2026-10-21 — 나노 spawn 재대조(①b) «인용 파일 뽑기» 정밀화 — 폴더 토큰은 인용 아님 · 확장자 긴 것 먼저 · 통과면 카드 base_sha 갱신 (r580 · 1.1.124 · 동작 변경)

- 사건(feature arch 47 쪽지 123204 · planner 86 승인 123206 · master 87 발주 123223 · arch 111 재현 2026-10-21 00:0x): feature 팀 카드 `F-toolbar-caption-controls-red` 가 `base_sha` 재대조에 3회 연속 REJECT(base 11bc→8ce7→9b41→248f · 인용 3파일 blob 매번 동일)됐다. 원인은 판정식이 아니라 **«인용 파일 뽑기»** 두 결함 — ①구현 범위 본문의 폴더 토큰(`clients/web` · `clients/web/src/`)을 접두로 써서 그 아래 아무 변경(credits 18파일)이나 «겹침» ②확장자 교대가 `ts|tsx`·`js|json` 순서라 `corner-controls-v5.tsx` → `corner-controls-v5.ts` 로 잘려 **진짜 인용 파일이 바뀌어도 못 잡는 거짓 통과** 구멍.
- 고침 ①(인용 뽑기): 확장자 교대를 긴 것 먼저(`tsx|ts|json|js|yaml|yml|sh|py|md`)로 바꾸고, «구현 범위» 본문에서는 **확장자 있는 파일 토큰만** 인용으로 본다(경로·맨 이름 모두). 확장자 없는 토큰(폴더·`origin/main` 같은 ref)은 버린다. `관련 파일:` 줄은 지금처럼 전부 인정(폴더 = 접두) — 명시한 폴더만 넓게 본다.
- 고침 ②(대조): 경로 있는 파일 토큰 = 정확 일치 또는 `endswith("/"+토큰)` · **맨 이름 = basename 일치** · `관련 파일:` 폴더 = 접두. 인용 0 이면 기본 세트 경로 6개 그대로.
- 고침 ③(통과 시 카드 기준 시점 갱신): 겹침 0 통과 ∧ 카드 `base_sha` 있음 ∧ 리서치 아님 → 카드 `base_sha:` 줄을 지금 HEAD 로 바꾸고 `(recheck-auto <날짜> · 겹침 0)` 를 붙인다. 출력 1줄 `BASE-RENEW <옛 9자> → <새 9자> · 인용 <N>개 겹침 0`. 카드 쓰기 실패 = REJECT(첫 개설 STAMP 실패와 같은 처리). 다음 재spawn 은 갱신된 시점부터 본다(main 이 빨리 움직여도 같은 카드가 반복 REJECT 되지 않는다).
- 시험 `harness/tests/test_nano_spawn_recheck_cited.sh` ⓐ~ⓖ(임시 리포 + 임시 카드 · ①b 블록만 잘라 실행 · 실 tmux·실 워크트리·실 좌석 0): ⓐ툴바 꼴(폴더 토큰 2 + 인용 `.tsx` 3 · 변경은 인용 밖) → 통과 + `BASE-RENEW` + 카드 base_sha = HEAD ⓑ맨 이름 `.tsx` 인용 · 그 파일 변경 → REJECT(옛 판은 `.ts` 잘림으로 거짓 통과) ⓒ`.json` 인용 · 그 파일 변경 → REJECT ⓓ`관련 파일: clients/web/src/components/toolbar/` 명시 폴더 아래 변경 → REJECT ⓔ인용 0 → 기본 세트(`worker/` 변경 = REJECT) ⓕ겹침 있음 + `--recheck` 판정문에 지금 HEAD → `RECHECK 통과` · base_sha 그대로 ⓖ리서치 좌석 면제 그대로(출력 0 · 갱신 0). 고치기 전 판 red = `evidence/r580/01-before-red.txt`(FAILED 7) → 고친 판 `02-after-pass.txt` ALL PASS.
- 툴바 카드 재현(읽기 전용 · `evidence/r580/05-toolbar-card-repro.txt`): 구간 `9b410eb61d..248f1f4236`(변경 18파일) · 옛 판 인용 8개(`clients/web`·`clients/web/src/`·`corner-controls-v5.ts`·`origin/main` 포함) → **HIT 18/18 REJECT** · 고친 판 인용 5개 → **HIT 0/18 통과 + BASE-RENEW**. arch 111 실측값과 일치.
- 기존 시험(`evidence/r580/03-existing-tests.txt`): 나노 spawn 6종 중 4종 ALL PASS · 선행 FAIL 2종은 **origin/main 판에서도 같은 칸**(`body_press` ⓒ node_modules 스테이징 2칸 · `teamset_cap` `core.bare` 칸 = 팩 루트 cwd 탓) — 이 카드 무관. `bash -n` OK · kit/bin 두 사본 cmp0(`04-kit-bin-cmp.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-nano-spawn.sh` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.124 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치(cmp0 1) · 실사건 1(main 전진 뒤 재spawn 1건이 RECHECK 없이 통과 + `BASE-RENEW` 줄)은 master 소관 — 미실행.**
- 범위 밖: 병합 줄 게이트(R243) · 판정문 꼴 · 기본 세트 경로 목록 · 카드 쪽 안내(폴더 대신 파일 이름) · press(나노는 쏘지 않는다).

## 2026-10-20 — 뉴스 «지도 만들기» 공급자 표에 opengateway 1줄 + 키 = pi 설정 (r575 · 1.1.123 · 동작 변경)

- 사건(오빠 결정 «pi 딥식으로 변경 교체» · 슬랙 1792506609 · desk 쪽지 122981 · master 87 발주 122998 ① · arch 111 실측 2026-10-20 23:3x): 뉴스 틱의 요약 호출(`ft_news_html_render.py` HTTP 직접 경로)이 OpenRouter 의 haiku 계정 잔액 −0.19달러로 HTTP 402 → 발행 0(`/tmp/byz-ft-news-planner.log` 180·182·186·191행 `rc=402`). 나노가 쓰는 pi 의 deepseek 는 OpenRouter 가 아니라 **OpenGateway**(`https://apis.opengateway.ai/v1` · OpenAI 호환)라 402 와 무관 — 다만 공급자 표에 그 이름이 없어 지금 판은 `모델 id 접두 opengateway — HTTP 주소 없음` 으로 실패한다.
- 고침 ①(공급자 표 2줄): `HTTP_BASE["opengateway"] = "https://apis.opengateway.ai/v1"` · `HTTP_KEY["opengateway"] = "OPENGATEWAY_API_KEY"` — 접두 하나로 주소·키 이름이 정해지는 기존 구조 그대로(상한·재시도·프롬프트·발행 흐름 변경 0 · CLI 기동 0 유지).
- 고침 ②(키 출처 = pi 설정 1곳 · 새 함수 `pi_models_path()`·`pi_key()`): `api_key()` 가 env 다음에 opengateway 만 pi 설정(`FT_NEWS_PI_MODELS` 대역 · 기본 `~/.pi/agent/models.json`) `providers.opengateway.apiKey` 를 읽는다. pi models.md 의 꼴 3가지를 그대로 따른다 — 글자 그대로 · `$NAME`/`${NAME}` = 그 env · **`!명령` = 그 명령 stdout**(실 pi 설정 값이 `!security find-generic-password -ws opengateway` = 47자 «글자 그대로» 가 아니라 명령 참조였다 · 2026-10-20 실측 · 401 은 그 때문). 없으면 `키 없음: OPENGATEWAY_API_KEY · pi 설정 opengateway(<경로>)` = NewsHtmlError(조용한 대체 0) · **값은 어디에도 출력 0**(반환만).
- 고침 ③(사고 필드 = **넣지 않는다** · 실측 근거): deepseek 는 스트림에 `reasoning_content` 를 함께 흘린다. 후보 `reasoning_effort: "low"` 는 이 모델에서 **역효과**(같은 프롬프트: base = 첫 내용 0.92s·총 4.89s·내용 575자 vs low = 첫 내용 0자·총 6.48s·reasoning 7,293자) → 필드 0 · 7초 룰 그대로. 다만 `max_tokens=2048` 을 reasoning 이 먹으면 내용이 빈다(300 으로 두면 내용 0자 실측) — **운영 env `FT_NEWS_HTTP_MAX_TOKENS` 를 4096 으로 올리는 것이 안전**(plist/env 는 master 소관 · 코드 상수 변경 0).
- 시험 `tests/scripts/test_news_direct_api.py` r575 5칸(가짜 HTTP 서버 · 가짜 pi 설정 · 실 원격·실 키 0): ⓐ(실패 시험 먼저 — base 판 = `NewsHtmlError: 모델 id 접두 opengateway — HTTP 주소 없음` · `evidence/r575/01-before-red.txt`) 접두 opengateway → `/chat/completions` · 모델 = 접두 뒤 · `Authorization: Bearer <pi 키>` ⓐ₂ pi 설정 꼴 `!명령` = stdout · `${NAME}` = env ⓑ pi 키 빈 값·파일 없음·타 공급자만 = `키 없음` ERROR + 서버에 닿기 전 실패 + 키 글자 로그 0 ⓒ env `OPENGATEWAY_API_KEY` 가 pi 설정보다 이김 ⓓ openrouter 경로 그대로(공급자 표 2줄 · zshrc 마지막 활성 줄 · `sk-or-fake-r563`). 후 5/5 PASS(`02-after-pass.txt`).
- ⓔ 실제 1회(나노 · 짧은 프롬프트 1~2갈래 · 실 OpenGateway): `http_target = https://apis.opengateway.ai/v1/chat/completions` · 모델 `deepseek/deepseek-v4.1-flash-ultrafast` · 키 37자(출력 0) · summary 갈래 5.19s JSON 파싱 OK(첫 바이트 0.5s) · goals 갈래 31.88s JSON 파싱 OK(첫 바이트 15.0s — 갈래 상한 안). 원문 = `evidence/r575/06-real-opengateway-once.txt` · 사고 필드 대조 = `07-thinking-field-measure.txt`.
- 기존 시험(이 카드 인접만 · 광역 0): `test_news_direct_api.py` 16/16 · `test_ft_news_html.py`·`test_news_html_cli_startup.py`·`test_news_planner_digest.py` 66/66 PASS(`03-related-and-cmp.txt`) · `py_compile` OK · kit/bin 두 사본 cmp0. ⚠ 선행 실패 1: `test_ft_news_html.py::test_h_head_phrase_one_place_and_deadline_70` 은 **파일 2개를 이어 돌릴 때만** 실패(base origin/main 에서도 같은 값 — 앞 파일이 남긴 env 로 fetch 를 타는 순서 의존 · 이 카드 무관).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft_news_html_render.py` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.123 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치(cmp0 1) · plist `FT_NEWS_MODEL=opengateway/deepseek/deepseek-v4.1-flash-ultrafast` 교체(.bak-r575) · kickstart · 실사건 1(첫 뉴스 틱 402 0 · 발행 완료 1)은 master 소관 — 미실행.** 되돌림 = plist `FT_NEWS_MODEL` 원래 값 + `.bak-r575`.
- 범위 밖: OpenRouter 충전 · `FT_NEWS_MODEL` 코드 상수(`MODEL`) 변경 · r569 fetch 상한 · press(나노는 쏘지 않는다).
## 2026-10-20 — 나노 워크트리 정리 계획 본문 ④ 가 «같은 좌석 키의 -rN 형제 가지» 를 인정 (r574 · 1.1.122 · 동작 변경 · origin/main b44ecf8e 위로 rebase)

- 사건(arch 111 실측 2026-10-20 23:1x · 카드 r574 · master 87 발주 122828 · desk 쪽지 122778 · ops-nano-ops-1810-credit-topup-dialog): 나노는 착지 게이트(줄 계약) 때문에 같은 작업을 `-rN` 형제 가지로 갈아타 다시 올린다(작업 폴더는 그대로 · 가지만 새로). 그러면 워크트리는 `.worktree-info.json` branch = `nano/ops-1810-credit-topup-dialog` · `git branch --show-current` = `nano/ops-1810-credit-topup-dialog-r2` 가 된다. wt-clean 계획 본문 ④ 는 «HEAD 가지 = info branch» 를 요구해 이 껍데기를 `HEAD=… ≠ info …` 로 거절 — 미커밋 0 · 원격 밖 0 · 세션 0 인데도 폴더가 사람 손 대기로 남았다.
- 고침(계획 본문 ④ 1곳): `hb != br` ∧ `NAMED_BR` 비어 있음 ∧ `hb`·`br` 둘 다 `^nano/${KEY}(-r[0-9]+)?$` 이면 `INFO ④ 형제 가지 — info <info> · HEAD <HEAD> (같은 키) · HEAD 가지로 판정` 1줄 + `br="$hb"` 로 판정. 그 밖(다른 키 `nano/other-r2` · 꼴 밖 `nano/k-rx` · detached)은 지금 fail 문구 그대로. 좌석 키는 계획 생성 때 이미 박혀 있고 한 리포 안에서 가지 이름은 유일하므로 다른 좌석·다른 팀 가지는 이 꼴에 들 수 없다.
- 그 뒤 `merge-base --is-ancestor HEAD refs/heads/$br` · ⑤ 이하(가드 6 · ignored 보관 · WIP · worktree move · baton wt-clean)는 바뀐 `br`(HEAD 가지) 로 그대로 · 원장 표식 문구에 ` · 형제=<HEAD 가지>` 1조각 · **가지 삭제 0** · named(`--wt/--branch`) 계획·`.worktree-info.json` 갱신 쪽은 범위 밖(변경 0).
- 시험 `tests/test_wt_clean_plan_rn_sibling.sh` ⓐ~ⓔ(임시 리포·가짜 tmux/sweep/baton/landed-check · 실제 삭제 0 · press 0): ⓐinfo=`nano/k` · HEAD=`nano/k-r2` · 미커밋 0 → cleaned + 두 가지 그대로 + 원장 `형제=nano/k-r2` ⓑ반대(info=`-r2` · HEAD=본 가지) → cleaned ⓒHEAD=`nano/other-r2` → fail 그대로 ⓓHEAD=`nano/k-rx`·detached → fail 그대로 ⓔ형제 HEAD + 실작업물 1(`FT_NANO_WIP=1`) → [wip] 커밋이 HEAD 가지에 붙고 cleaned · 정보 가지 tip 그대로. 전(고치기 전 판) FAIL 12칸(`evidence/r574/01-before-red.txt`) → 후 ALL PASS(`02-after-pass.txt`).
- 기존 시험(이 카드 인접만 · 광역 0): 나노-close·wt-clean 14종 ALL PASS(`03-existing-tests.txt`) · `bash -n` OK · kit/bin 두 사본 cmp0(`04-kit-bin-cmp.txt`).
- 실사건 읽기 전용 실측(`05-real-cases-readonly.txt`): ops-1810 워크트리 = info `nano/ops-1810-credit-topup-dialog` · HEAD `nano/ops-1810-credit-topup-dialog-r2`(78c81060b0) · 미커밋 0 · HEAD ⊂ `origin/…-r2` · 두 가지 존재 = 이 카드가 고치는 바로 그 꼴. **실사건 1(ops 팀장이 ops-1810 좌석 nano-close 표준 재실행 → cleaned · 폴더 없음 · 두 가지 유지)은 master 집행 — 미실행.**
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-nano-close.sh` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.121 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치·실사건은 master 소관 — 미실행.** 되돌림 = `.bak-r574`.
- 범위 밖(후속 후보): `.worktree-info.json` 을 가지 전환 때 갱신하기(spawn·재착수 쪽) · named(`--wt/--branch`) 계획도 같은 인정을 할지 · 가지 정리(refs/archive 이동 = 판정 2354 경로).

## 2026-10-20 — 나노 닫기 «재실행» 의 --wt/--branch 가 표준 좌석 해석과 «같은 값»이면 정리한다 + 조용한 건너뜀 0 (r572 · 1.1.120 · 동작 변경)

- 사건(arch 111 실측 2026-10-20 23:0x · 카드 r572 · master 87 발주 122624 · desk 쪽지 122574): 팀장 2명(cfo · ops)이 나노 닫기를 다시 돌리면서 `--wt <워크트리> --branch nano/<키>` 를 직접 적어 넣었다. 이름 지정 모드(NAMED=1)는 본래 «표준 이름이 아닌 폴더» 용이라 재실행 분기가 `SEAT_WT=$NWT` 만 넣고 `_RERUN_STD=0` → r566 의 `_wt_clean_rerun` 을 안 탔다. 두 폴더는 실제로 표준 이름(`cfo-<키>` · `ops-nano-<키>`)이었고 `_resolve_seat_wt` 로도 같은 경로가 나왔다. 결과 = `CLOSED … 재실행` 만 남고 정리 줄 0 · INFO 0(조용한 건너뜀) — r566 시험 ⓔ(«named 재실행 = 지금 동작 그대로»)가 그 길을 고정하고 있었다.
- 고침 ①(`ft-nano-close.sh` 재실행 분기 NAMED 갈래): `_KEY`·`cwd=""` 로 `_resolve_seat_wt` 를 한 번 부른 뒤, `pwd -P` 로 맞춘 받은 `--wt` == 해석 `SEAT_WT` ∧ 받은 `--branch` == 해석 `SEAT_BR` 이면 `_RERUN_STD=1`(SEAT_WT·SEAT_BR = 해석 값) + `INFO 재실행 — --wt/--branch 가 표준 좌석 해석과 같은 값(<경로> · <가지>) — 정리는 조건 4 그대로` 1줄 · 다르면 지금 값 그대로(`SEAT_WT=$NWT` · 정리 0) + `INFO 재실행 — --wt/--branch 명시가 표준 해석과 다름(해석=<경로|없음> 받은=<경로>) · 정리 계획 0` 1줄.
- 고침 ②(조용한 건너뜀 0): `_RERUN_STD=0` 이고 기존 `.sh` 계획도 없을 때 `INFO 재실행 — 정리 계획 0(<사유>)` 1줄(사유 = 표준 좌석 해석 밖 · 공유 워크트리(--shared-wt) · 이미 낸 사유 INFO 는 중복 0).
- 고침 ③(`_wt_clean_plan` 1조건): 같은-값 named 재실행(`_RERUN_STD=1`)은 표준 좌석이므로 계획을 `.sh.hil`(사람 실행)이 아니라 `.sh`(sweep 순회/즉시 실행)로 만든다 — `X.sh.hil.hil` 이중 꼬리 방지.
- 조건 4(세션 0 · `nano/<키>[-rN]` · `$ROOT/.worktrees/` 등록 · HEAD 가 어떤 원격 ref 에 포함)·계획 본문·처음 닫기의 named 경로(`.sh.hil` 사람 실행)는 변경 0.
- 시험 `tests/test_nano_close_rerun_named_equal.sh` ⓐ~ⓔ(임시 리포·가짜 tmux·가짜 reap/baton/sweep · 실제 삭제 0): ⓐ표준 좌석 · 같은 값 named 재실행 → 옛 계획 `.superseded-<시각>` 보존 + `워크트리 정리: cleaned` + 폴더 없음 + 가지 보존 + 원장 행 1개 그대로 ⓑ팀 접두 `cfo-`(`FT_NANO_WT_PREFIX=cfo-` · 워크트리 `cfo-<키>`) → cleaned ⓒ`--wt` 가 표준 해석과 다른 경로 → 정리 0 + `해석=… 받은=…` INFO + 워크트리 둘 다 그대로 ⓓ`--branch main`(nano/* 아님) → 정리 0 + 같은 INFO ⓔ같은 값이라도 HEAD 가 원격에 없음 → `.sh.hil` + `[HIL] 재실행 — 원격에 없는 커밋 N` + 폴더 그대로. 전 FAIL 13칸(`evidence/r572/01-before-red.txt`) → 후 ALL PASS(`02-after-pass.txt`) · r566 시험 ⓔ 칸은 «다른 값 named» 로 바꿔 유지.
- 기존 시험(이 카드 인접만 · 광역 0): 나노-close 11종 ALL PASS(`03-existing-tests.txt` — fail_closed 48 · named_wt 63 · never_started 155 · pack_wt 30 · rerun_early 37 · rerun_wt_clean 32 · sha_base 21 · superseded_by 140 · suspended 92 · worktree_list_pipe 18 · wt_deletion_only 23) · `bash -n` OK · kit/bin 두 사본 cmp0(`04-kit-bin-cmp.txt`).
- 실사건 2 읽기 전용 실측(`05-real-cases-readonly.txt`): 가지 `nano/cfo-insight-billing-flashlite-peg-1283`·`nano/ta-1-tree-read` 는 보존 · 등록 워크트리 0(이 시점 폴더 이미 없음 — arch 111 23:0x 등록 실측과 다름) · 팀 접두 cfo `byz-cfo-nano-`/`cfo-` · ops `byz-ops-nano-`/`ops-nano-` = 받은 `--wt` 와 같은 경로가 표준 해석 값. **실사건 2(같은 인자로 재실행 → cleaned·폴더 없음·보관 tar)는 master 집행 — 미실행.**
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-nano-close.sh` · `harness/bin` 짝 cmp0) + 시험 1 · manifest 1.1.120 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치·실사건은 master 소관 — 미실행.** 되돌림 = `.bak-r572`.
- 범위 밖(큐): 재실행이 «아닌» 처음 닫기의 같은-값 named 처리(지금은 `.sh.hil` 사람 실행) · 팀장 발주문에서 `--wt/--branch` 를 안 쓰게 하는 안내.
## 2026-10-20 — 은퇴 도구 R282 ② 가 «옛 이름» 에 이름 lint 를 걸어 못 넘으면 은퇴가 영구 실패하던 것 → 후계 이름에서 팀·역할·에이전트를 뽑는다 (r573 · 1.1.121 · 동작 변경 · r572 위로 rebase)

- 사건(aifp 쪽지 120239 · master 87 발주 122747 · arch 111 실측 2026-10-20 23:1x): `ft-seat-retire.sh` R282 ② 갈래(옛 행이 어느 명부에도 없는 «지금 승계 중»)가 `ft-name-lint.sh <옛 이름>` 을 먼저 걸고 실패하면 `REJECT 명부 후보 0개 · 이름 lint 실패` 로 끝났다. 이름 규칙 이전의 옛 좌석(`aifp-pi-master#1` = 에이전트 꼬리 없음 · `tmm` = 계보 번호 없음)은 이 검사를 못 넘어 **명부 없는 리포에서 은퇴가 영구 rc 1** — 은퇴·재개 기록은 옛 이름 모양과 무관한데 lint 가 «팀·역할·에이전트 칸 뽑기» 를 겸해서 막혔다(aifp 는 `seats-aifp.json` 신설로 우회).
- 고침(`kit/fable-team/bin/ft-seat-retire.sh` R282 ② 갈래): 옛 이름 lint **실패** ∧ 후계 `new` 있음 ∧ `new` lint **PASS** → `parts`(팀·역할·에이전트)를 `new` 에서 뽑아 팀 명부(`seats.json`=v65 · `seats-<팀>.json`)에 은퇴 행을 만들고 출력에 `INFO 옛 이름 lint 실패 — 후계 <new> 이름으로 팀·역할·에이전트` 1줄. 후계도 lint 실패면 지금 문구 + ` · 후계도 이름 lint 실패` 로 REJECT rc 1(쓰기 0). 옛 이름이 **다른 명부 `_*` 칸의 현역**이면 이 갈래보다 먼저 REJECT(` · 다른 명부 `_*` 칸의 현역 — --seats 로 지정` · 쓰기 0) — 행을 만들 명부를 추측하지 않는다. 새 이름 lint 규칙·현역 가드(다른 경로)·기록 모드·`ft-name-lint.sh` 규칙은 그대로.
- 시험 `tests/test_seat_retire_old_name_lint.sh` ⓐ~ⓓ(mktemp scratch 리포 3 · 가짜 tmux(세션 없음) · reap 스텁 · 실 명부 쓰기 0 · `FT_RETIRE_BIN` 으로 옛 판 주입 대조): ⓐ(실패 시험 먼저) 옛 `old-aifp-master#1`(lint REJECT)·후계 `old-aifp-master-pi#0`(lint PASS) → 지금 판 REJECT rc 1(FAIL 6칸·`01-before-red.txt`), 고친 판 `RETIRED` rc 0 + `seats-aifp.json` 옛 행 `_retired_role=master`·`agent=pi`·`_created_by=retire`·`_replaced_by=<후계>` + 후계 행 `_replaces` + 재개 기록 1줄 ⓑ 옛 이름 lint PASS → 지금 동작 그대로(INFO 0 · 옛 이름 팀 명부 · 옛 칸) ⓒ 옛·후계 둘 다 lint 실패(`tmm`→`tmm2`) → REJECT rc 1 + `후계도 이름 lint 실패` · 명부 3개 바이트 불변 ⓓ 옛 이름이 다른 명부 `_*` 칸에 현역 → REJECT rc 1 · 쓰기 0 · INFO 0. 후 PASS(`02-after-pass.txt` ALL PASS).
- 기존 시험(카드 인접만 · 광역 금지): `test_seat_retire_rosters.sh` ALL PASS · `test_seat_retire_keep.sh` ALL PASS · `test_seat_retire.sh` = FAIL 4칸(①stall·②×2·⑧`test_ft_tick_master_seat.sh` rc 44) — **base(origin/main `40dfbd09`)에서 같은 4칸**(`04-base-retire-same.txt`) = 이 카드 무관 선행 실패. `bash -n` OK · 정본/키트 cmp0(`05-kit-bin-cmp.txt`).
- 파일 줄 수: `ft-seat-retire.sh` 200줄 유지(하드 상한 ≤200 · `[structure]` 커밋에서 `mkrow`/`cand` 두 줄 병합으로 자리 확보 · 동작 불변).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-seat-retire.sh`) + 시험 1 · manifest 1.1.120 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치 집행(cmp0 1)·실사건 1(구 이름 승계 RETIRED·RESUME ok)은 master 소관 — 미실행.** 되돌림 = `.bak-r573`.
- 범위 밖: `byz-` 아닌 접두(aifp-…)의 «팀 이름» 뽑기 규칙(지금 `parts[1]` — aifp 는 `--seats` 로 우회) · `ft-name-lint.sh` 규칙 · 옛 이름 일괄 개명 · press(나노는 쏘지 않는다).

## 2026-10-20 — 나노 첫 발주문에 «저장소 전체 검색 금지 · 명부 손대지 않음 » 고정 줄 1개 (r570 · 1.1.118 · 동작 변경)

- 사건(arch 111 실측 2026-10-20 22:3x · 카드 r570 · master 86 발주 122355): ① r566 pi 나노가 BYZ 루트에서 `grep -r` 를 4분+ 돌려 load 40 → v65 M6 press 첫 원문이 5.8~13.3초 지연(planner 85 규칙 상기 요청 · 메모리 규칙 117521 계열 «repo-wide git log -S 금지»). ② r561·r566 나노가 공용 `seats.json` 에 자기 행을 손으로 넣어 쪽지 반송 REJECT 2회(spawn 이 이미 명부 등록). 두 사고 모두 첫 발주문 고정 줄(`_SPX` 광역 pytest · `_PKX` 팩 폴더)에 «금지 문장» 이 없어서 반복됐다.
- 고침(`ft-nano-spawn.sh` `_SPX` 줄 바로 뒤 1줄 + BODY): `_SRX` = «★저장소 전체 검색 금지 — grep -r · git log --all -S · find / 를 리포 루트·홈에서 돌리지 않는다(부하 40 → 다른 팀 press 오염 · r570) · 카드 §구현 범위 경로나 자기 워크트리 폴더를 지정해 찾는다 · 코드 심벌 찾기는 serena 도구(find_symbol · get_symbols_overview · search_for_pattern) 먼저(r556) · 명부(seats.json · seats-<팀>.json)는 손대지 않는다(spawn 이 이미 등록 · 손 행 = 쪽지 반송)★» — `echo "BODY+${_SRX}"`(dry-run 같은 글자) + `BODY=` 끝에 `${_SRX}`(실 발주문에도 붙는다) · 에이전트 분기 0(claude·pi·opencode·codex 같은 줄).
- 시험 `tests/test_nano_spawn_body_search_roster.sh` (정적 · 실행·네트워크·tmux 0 · PASS 26칸): `_SRX` 줄 1개 · 광역 명령 3종 · serena 먼저 · 명부 금지 문장 · `BODY+` echo 1개 · `BODY=` 반영 · ⓑ 에이전트 분기 0(고정 줄·echo·BODY 줄에 AGENT 조건 0 + pi·claude emit 동일) · ⓓ 음성 대조 2종(줄 삭제·명부 문장 삭제 → FAIL) · 기존 `_SPX`·press 금지 불변. 전 FAIL 9칸(`evidence/r570/01-before-red.txt`) → 후 PASS 26칸(`02-after-pass.txt`).
- 기존 시험: `test_nano_spawn_pi_effort_serena`·`test_nano_spawn_reuse_info`·`test_nano_spawn_tier` ALL PASS · `test_nano_spawn_body_press.sh` = ⓒ 2칸 FAIL · `test_nano_spawn_teamset_cap.sh` = 1칸 FAIL — 둘 다 base(origin/main `ab9d3b7a`)에서 같은 값(`04-base-press-same.txt`·`06-base-teamset-cap-same.txt`) = 이 카드 무관 선행 실패. `bash -n` OK · 두 사본 cmp0(`07-kit-bin-cmp-and-diff.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-nano-spawn.sh` · 정본 bin 짝 cmp0) + 시험 1 · manifest 1.1.118 · `install.sh` REQUIRED 목록 변경 0 · 데몬 재기동 0. **LIVE_BIN 설치 집행·실사건(다음 spawn dry-run BODY 에 그 줄 · pi·claude)은 master 소관 — 미실행.** 되돌림 = `.bak-r570`.
- 범위 밖: 검색·명부 쓰기를 «막는» 훅(별도 카드 후보 · 지금은 문장) · 역할 좌석(master·arch·DA) 부팅 문장 · 이미 열린 나노.

## 2026-10-20 — 좌석 상태 조회가 폴더의 jsonl «전부» 를 매번 읽던 것 → 폴더별 색인 1개 (r571 · 1.1.119 · 동작 변경·답 불변)

- 사건(planner 85 요청 · CPU 폭주 경보 쪽지 122491 «Python×5 210% · 누적 251분» · arch 111 실측 2026-10-20 22:4x): `ft-seat-status.sh` `newest_jsonl_of` 가 좌석 1석 조회마다 그 cwd 의 `*.jsonl` «전부» 를 앞 1MB 씩 읽고 `agentName`/`customTitle` 을 찾는다. 폴더당 jsonl 203~10,003개 — v6-realtime-live 8석이면 좌석당 5.7GB · 45석 한 바퀴 61GB · 따뜻한 캐시에서도 6.9초/석. 부르는 곳 = `ft-tick.sh` 3 · `ft-idle-wake` 2 · `ft-news-tick` 2 · `ft-nano-slots` · `ft-resource-reclaim` · `ft-blocked-on-master`. 그 부하가 press·뉴스 fetch·나노 시험을 함께 늦췄다.
- 고침 ①(신규 `ft_seat_jsonl_index.py` 165줄): `newest <폴더> <좌석>` — 색인 `<FT_SEAT_INDEX_DIR 기본 $HOME/.claude/state/seat-jsonl-index>/<폴더 이름>.json` = 경로 → {size · mtime · read · names[]}. 갱신 = `os.scandir` 1회 + «색인에 없거나 크기·시각이 바뀐 파일» 의 «아직 안 읽은 앞부분» 만 더 읽음(경계 이름 레코드 = 1KB 겹쳐 읽기) · 사라진 경로 삭제 · 1MB 상한(FT_SEAT_HEAD_BYTES)에 닿은 파일은 stat 만 · 쓰기 = 임시 파일 + `os.replace` · 폴더당 잠금 `fcntl.flock`(대기 상한 7초 — 넘으면 마지막 색인으로 답 + stderr WARN) · 깨진 색인 = stderr `ERROR r571-index` + 처음부터(조용한 빈 답 0) · 답 = names 에 좌석이 든 항목 중 mtime 최대 경로.
- 고침 ②(`ft-seat-status.sh` `newest_jsonl_of`): 인라인 python 대신 `python3 "$(dirname "$0")/ft_seat_jsonl_index.py" newest "$dir" "$1"` — 출력 꼴·빈 답 뜻·호출처는 그대로(판정 결과 변경 0).
- 계측: `FT_SEAT_INDEX_STATS=1` 이면 stderr `READ <바이트> FILES <개수> NEW <개수> MS <밀리초>` 1줄 · 기본 출력 0.
- 시험 `tests/test_seat_jsonl_index.sh` ⓐ~ⓖ(임시 HOME `.claude/projects/<인코딩>/` jsonl 301개 · 가짜 tmux · 실 홈 쓰기 0 · 답은 HEAD 판 인라인 판정기와 대조): ⓐ같은 좌석 2회 → 1회째 READ = 전 파일 합 · 2회째 READ 0(지금 판은 2회째도 전 파일 재읽기) ⓑ좌석 21개 답 == 지금 판(차이 0) ⓒ새 jsonl 1개 = 그 파일이 최신 · READ = 그 파일 크기 ⓓ작았던 파일이 자라 이름 레코드 생김 → 다음 조회에 잡힘(전체 재읽기 0) ⓔ삭제 파일 = 색인에서 빠짐 · 잔재 0 ⓕ동시 5개 조회 = 답 동일 · 읽기 합 = 전 파일 합(한 번만 읽음) · 예외 0 ⓖ색인 깨짐 = ERROR + 처음부터(답 동일). 전 FAIL 12칸(`evidence/r571/01-before-red.txt` · base 판정기) → 후 PASS(`02-after-pass.txt`).
- 기존 시험(좌석상태 인접만 · 광역 금지): `test_tick_line.sh`·`test_team_tick_unify.sh`·`test_nano_slots.sh` ALL PASS(`03-existing-tests.txt`) · `ruff check` PASS · `bash -n` OK · 정본/키트 cmp0 2(`04-…`).
- 실측(읽기 전용 · 실 홈 projects · 색인은 /tmp · `06-live-readonly-measure.txt`): harness-ops 폴더(jsonl 5,328 · 3,427MB · 지금 판 1회 = 2,892,298,409 바이트) — 1회째 `READ 2892364185 FILES 5328 MS 8813` → 2회째 `READ 0 MS 66` · 같은 폴더 2번째 좌석 = `NEW 1 READ 14883 MS 1022` · base 판정기 같은 좌석 2회 = real 3.35s·1.60s(색인 판 0.10s).
- 설치: 있음 — 키트 2(`ft_seat_jsonl_index.py` 신규 · `ft-seat-status.sh`) + 시험 1 · `harness/bin` 짝 cmp0 2 · `install.sh` 는 kit 트리 전체를 복사하므로 목록 변경 0 · LIVE_BIN cmp0 · 틱·감시 데몬 재기동은 master 소관(미실행). 되돌림 = `.bak-r571`(색인 파일을 지우면 처음 판으로 다시 만든다).
- 범위 밖(후속 카드 후보 · 같은 부하 갈래): 같은 «좌석→jsonl» 찾기를 따로 가진 8곳(`ft-reach-check.sh` grep 전문 · `ft-nano-close` · `ft-nano-spawn-undo` · `ft-nano-never-started-check` · `ft-seat-retire` · `ft-successor-open` · `ft_tick_line_io.py` · `ft_api_outage_util.py`)을 이 색인으로 옮기기 · 옛 jsonl 정리(삭제 = HIL) · 틱 안 호출 횟수 줄이기 · r539 경보 판정식.

## 2026-10-20 — 뉴스 «지도 만들기» = 모델 HTTP 직접 호출(CLI 기동 0) + 원장·골 = origin/main ref + 자율 = 데이터 루트 (r563 · 1.1.114 · 동작 변경)

- 사건(arch 110 실측 2026-10-20 21:2x · `/tmp/byz-ft-news-planner.log`): 부하 52 에서 매 틱 `opencode run summary 실패(openrouter/anthropic/claude-haiku-5.5): summary 상한 7s 초과(총 마감 70s)` = 발행 0. 원인은 부하가 아니라 구조 — 모델 호출이 매번 `opencode` CLI 를 새로 띄워 «첫 출력까지» 가 한가할 때도 13~41초(`state/news-cli-startup.tsv`) → 7초 룰의 상한 대부분이 기동 시간. 덤: 원장 사본 체크아웃이 매분 fetch+checkout(20초 timeout)으로 실패하며 «낡은 사본» 을 발행하고, 본문 자율 칸은 공용 루트 상태 폴더를 읽어 «off» 로 오독, 골 표가 0줄이어도 «정상» 발행.
- 고침 ①(`ft_news_html_render.py` `via`/`http_target`/`api_key`/`_http_once` · `call_part`): `FT_NEWS_VIA`(기본 `http`) — 같은 모델을 OpenAI 호환 chat completions(`<공급자 접두>` → `https://openrouter.ai/api/v1/chat/completions` · 모델 = 접두 뒤 · 스트림 켬 · 첫 바이트까지 기록)로 직접 부른다. 시도당 상한 = `cap_s(prompt, part, fixed=0)`(CLI 고정비 0 · 7초 룰 그대로) · 재시도(첫 출력 전 실패만 1회)·총 마감 70초 그대로 · 키 = `OPENROUTER_API_KEY`(env › `~/.zshrc` 마지막 활성 줄 · `ft_key_rotate_lines.parse_line` 재사용 · 값 출력 0) · 키 없음·모르는 접두 = `NewsHtmlError`(조용한 CLI 대체 0) · `max_tokens` = `FT_NEWS_HTTP_MAX_TOKENS`(기본 2048 · 미지정이면 모델 최대 65536 을 요구해 이 계정 크레딧에서 402 «can only afford 2527» 실측) · `FT_NEWS_VIA=opencode` = 옛 CLI 경로(되돌림).
- 고침 ②(`ft_news_ledger.py`): `sync_repo()` 가 마지막 성공(`FT_LEDGER_SYNC_MIN` 기본 120초) 안이면 건너뜀 + INFO 1줄(성공 시각 = `state/news-ledger/last-sync.ts` · subprocess timeout 20초 그대로) · `fetch_if_stale(repo)`(신규 · 뉴스 HTML 경로 전용) = 체크아웃 전진 0 · 마지막 fetch 가 `FT_NEWS_FETCH_MIN`(300초) 안이면 건너뜀 · 필요하면 `git fetch origin main`(7초 + 재시도 1 · `FT_LEDGER_FETCH` 대역) · 실패는 ERROR + 머리 줄(발행은 지금 ref 로 계속) · `news_cur(repo, rel)` = `FT_NEWS_MODE=html` 이면 판이 «사본 체크아웃 HEAD» 가 아니라 `FT_NEWS_MAIN_REF`(기본 `origin/main`) 커밋(r545·r557 꼴).
- 고침 ③(`ft_news_html.py`): `autonomy()` 가 `FT_ROOT` 대신 데이터 루트(`<root>/.fable-team/LIVE_ROOT` 1행 · 없으면 root)를 넘김(자율 ON 인데 «승인을 기다린다» 로 오독하던 것) · `build()` 가 골 표 0줄이면 `RuntimeError` («골 표 0줄 — 지도 발행 0» · 골 없는 뉴스를 «정상» 으로 내지 않음) · `_ledger_args()` = fetch_if_stale + ref 판 · 지도 실패 틱마다 INFO «직전 판 유지 <마지막 발행 시각>(<링크>)» 1줄(r510 지연 글 3틱 규칙은 그대로).
- 시험 `tests/scripts/test_news_direct_api.py` ⓐ~ⓚ 11칸(가짜 HTTP 서버 1 · 가짜 opencode 1 · 가짜 키 파일 · 실 모델/슬랙/`~/.zshrc` 쓰기 0): ⓐ지금 판 = 서버 안 씀 FAIL → 고친 판 = 갈래 4개 HTTP 병렬 + 기동 기록 4줄(첫 출력 ≤7초) ⓑ첫 바이트 상한 초과 = 1회 재시도 · 둘 다 실패 = 발행 0 ⓒHTTP 상한 = `7 × ceil(units)`(고정비 0) · 70초 천장 ⓓ키 없음·모르는 접두 = ERROR + 키 값 로그 0 ⓔ`FT_NEWS_VIA=opencode` = 옛 CLI 경로 ⓕ동기화 2분 건너뜀 + INFO · 121초 지나면 다시 ⓖ실패 틱마다 «직전 판 유지» INFO 1줄 ⓘ원장 판 = origin/main ref(사본 HEAD 옛 판 무시) ⓙ자율 = 데이터 루트(LIVE_ROOT) ⓚ골 0줄 = 발행 0 + 이유. 전 FAIL 10 failed/1 passed(`evidence/r563/01-before-red.txt`) → 후 PASS 11 passed. 실 HTTP 스모크(`06-real-http-smoke.txt`): 같은 모델(haiku-5.5) 갈래 1개 = 첫 바이트 2.3초 · 끝 2.9초(CLI 13~41초 대조).
- 기존 시험(카드·뉴스 인접만 · 광역 금지): `test_ft_news_html.py`·`test_news_html_cli_startup.py`·`test_ft_news_ledger.py`·`test_ft_news_goal_block.py`·`test_ft_news_ledger_notify.py`·`test_ft_news_publish.py` + 새 시험 = **123 passed**(`02-after-pass.txt`) · `tests/test_news_html.sh` 39 passed(`03-…`) · `ruff check` PASS + `bash -n` OK(`04-…`). 기존 시험은 «CLI 경로를 보는 픽스처» 에 `FT_NEWS_VIA=opencode` 1칸(`oc` 픽스처 · effort 표 도구) · `test_ft_news_ledger.py` env 에 `FT_LEDGER_SYNC_MIN=0` 1칸만 더했다(나머지 diff 0).
- 설치: 있음 — 키트 4(`ft_news_html.py`·`ft_news_html_render.py`·`ft_news_ledger.py`·`ft-news-effort-test.sh`) + 시험 1 · `harness/bin` 짝 cmp0 4(`05-kit-bin-cmp.txt`) · `install.sh` REQUIRED 목록 변경 0 · plist 변경 0(키는 zshrc/env 에서 읽는 기존 꼴) · 데몬 재기동 0(60초마다 새로 부름). **설치 집행·실사건 press 는 master 소관 — 미실행.** 되돌림 = `FT_NEWS_VIA=opencode`(옛 CLI 경로) 또는 `.bak-r563`.
- 범위 밖: 모델·프롬프트·린트·HTML 틀 불변(호출 수단만) · 다른 팀 뉴스 틱 · 부하 50 의 주인(r522·r539) · plist `.bak` 정리.
## 2026-10-20 — 스레드는 주제 대화 전용: 방 글 `post --to <이름>` + `--thread desk` 거절 + 쪽지 방 글 안내 (r561 · 1.1.111 · 동작 변경)

- 오빠 원문(슬랙 10-20 20:2x): «대화스레드는 주제에 대한 대화만 남기게 하거 지금 발행하는 요청이나 뉴스나 세션에서 스레드와 관련없는 메시지는 방에 바로 보내줘서 스레드는 주제별 대화로 사용하도록 개선해줘라». 지금 desk 는 승인 요청·뉴스·세션 알림을 `reply --thread desk`(아침 뿌리 글) 밑에 쌓아 주제 대화와 섞였다 — r558 이 «오빠 글 답» 반쪽을 만들었고 이 카드가 나머지 반쪽이다.
- 고침 ①(`thread_post_args.py` `post` 하위 명령 + `thread_post_update.cmd_post` · `byz_thread_post` 배선): `post (--to <등록부 이름> | --channel <ID>) (--text|--text-file)` = 방에 최상위 글 1개(`thread_ts` 없음) · stdout `POSTED <ts>` · 등록부·장부·답 기록 쓰기 0 · 첨부 0. 이름은 `.fable-team/state/slack-threads.json` 의 채널을 쓰고, 등록부에 없는 이름·꼴 위반은 추측 없이 REJECT(게시 0). 본문은 `post_guard` 사람 채널 검사를 «글 전» 에 건다.
- 고침 ②(`thread_reply_slack.refuse_topic` ← `refuse_unanswered` 첫줄): 이름이 주제 전용 목록(env `FT_SLACK_TOPIC_ONLY` · 기본 `desk` · 쉼표)이면 «답 안 된 오빠 글» 유무와 무관하게 REJECT — 문구 = `REJECT --thread desk — desk 스레드는 주제 대화 전용 — 방 글은 post --to desk · 오빠 글 답은 reply --to-slack <ts>` · `--force-thread` 면 보내고 stderr WARN(명시). env 를 **빈 값**으로 두면 r558 규칙만 남는다(되돌림).
- 고침 ③(`mirror_share.answer_hint`): 좌석 쪽지 끝이 2줄 — r558 `답 = … reply --to-slack <ts>` 아래 `방 글(승인·뉴스·알림) = … post --to desk --text "…"`. 출처 토큰 줄 `(slack:<ts>:<role>)` 은 그대로(중복 판정 `marker_seen`/`queue_has` 가 줄 끝 일치를 읽는다).
- 고침 ④(`ft-successor-open.sh` ⓐ' 거절 문구): «`reply --thread <이름>` 으로(r414)» → «방 글 = post --to <이름> · 오빠 글 답 = reply --to-slack <ts>». 판정 규칙(본문 `--ts <10자리>.<6자리>` = 열기 0)은 불변.
- 시험 `tests/scripts/test_thread_room_post.py` ⓐ~ⓖ 8칸(가짜 Slack `_proposal_fakes.slack` · 임시 등록부·원장·답 기록 · 실제 Slack·실제 `~/.hermes/state` 쓰기 0): ⓐ`post --to desk` → `thread_ts` 없음·등록부 채널·`POSTED <ts>`·답 기록/등록부 불변 ⓑ`--channel` 직접 + 모르는 이름 REJECT + 인자 택1 강제(rc2) ⓒ답 안 된 글 0 인데 `--thread desk` REJECT(전 FAIL 자리) ⓓ`--force-thread` → 보냄 + WARN ⓔ`FT_SLACK_TOPIC_ONLY=` 빈 값 = r558 거절만 · `desk,ops` = 두 이름 ⓕ쪽지 끝 2줄 + 토큰 줄 불변 ⓖ`--to-slack`·`--ts` 기존 길 불변 · `post` 는 장부 미기록. 전 FAIL 8 failed(`evidence/r561/01-before-red.txt`) → 후 PASS 8 passed(`02-after-pass.txt`).
- 기존 시험(카드·slack-mirror 인접만 · 광역 금지): `test_thread_reply_to_slack.py`·`test_thread_post.py`·`test_thread_post_args.py`·`test_post_guard.py` = 83 passed · `tests/test_thread_reply_named.sh` ALL PASS(`06-…txt`). r558 시험은 `FT_SLACK_TOPIC_ONLY=`(빈 값)을 env fixture 에 넣어 r558 규칙만 보게 했고, 쪽지 끝 시험은 `답` 줄이 `lines[-2]` 로 한 칸 밀린 것을 반영 — r414 셸 시험도 같은 env 1개 추가. base 대조(`05-base-diff.txt`): `test_thread_post_attach.py` 1건이 base(4066f4d4)에서도 같은 rc = 이 카드 무관(이 머신 `.md` mimetypes). `ruff check`(바꾼 8파일) PASS(`04-ruff.txt`).
- 설치: 있음 — 새 파일 0 · `install.sh` REQUIRED 목록 변경 0(기존 `thread_post_update.py`·`thread_reply_slack.py`·`mirror_share.py`·`thread_post_args.py`·`byz_thread_post.py` 경로 그대로) + 키트 `ft-successor-open.sh` 문구 1 → `~/.hermes/scripts` cmp0·LIVE_BIN cmp0·수신 데몬 재기동은 master 소관(미실행). 되돌림 = `FT_SLACK_TOPIC_ONLY=`(빈 값) 또는 `.bak-r561`.
- 범위 밖: 등록부 desk 뿌리 글 정리·삭제(보고용 옛 글 · 남김) · 다른 채널(대화 수신 r238·보드) · desk 인계서·메모리 문구(장치가 막으니 desk 몫) · 범위 승인 알림(`autonomy_scope_post` 는 이미 최상위) · 실제 사건 확인(방 글 1건 + 거절 1건)은 master press 소관.
## 2026-10-20 — 동일승인 판정의 기준 main = «세트가 실제로 병합한 main» + 훅 판정기 자리·후보 순서·이유 + 재승인 셈 0 (r560 · 1.1.115 · 동작 변경)

- 사건(판정 1917 · R247 · r462 장치 · arch 110 직접 재현 2026-10-20 20:1x): 승인 sha 위에 main 병합만 더한 head 는 재승인 없이 통과해야 하는데, main 이 빨리 움직이는 날 거의 안 닿아 같은 세트를 2~3번 재승인(하루 한도 15 중 9 소진). 원인 셋 — ①판정기 넷째 검사가 S 트리를 «승인 + **지금** origin/main» 병합 트리와 비교(main 이 한 칸만 더 가도 NOT-EQUIV · rebase 경로도 «지금 main ⊂ S» 요구) ②병합 훅이 승인 후보 418개를 최신순으로 21초 안에 하나씩 판정기에 넣어 자기 승인이 뒤에 있으면 못 닿고, 판정기 stderr·rc 를 버려 «판정기 출력 없음» 만 남김 ③훅이 판정기를 `<도구 폴더>/ft_approval_equiv.py` 로 잡는데 그 자리가 루트 shim(`bash` 대리 파일)이면 `python3 -I` 가 SyntaxError → stdout 0 → EQUIV 항상 거절.
- 고침 ①(`ft_approval_equiv.py`): 기준 main `mx` = 마지막(가장 새) 병합 커밋의 main 쪽 부모(병합 2번이면 마지막 병합의 main 쪽 부모) · `mx` 는 `merge-base(A,main)` 의 자손이어야 한다(승인 이후 main · 아니면 NOT-EQUIV) · merge-base·norm·merge-tree·overlap 을 전부 `mx` 기준으로 · rebase 경로는 `mx = merge-base(S, main)`(옛 «지금 main ⊂ S» 폐기) · 출력 끝 칸 `base=<mx 10자>`. 판정 규칙 넷(조상·병합만·자기 변경 같음·깨끗한 병합 트리)은 그대로 = 거짓 통과 0.
- 고침 ②(`templates/hooks/autonomy-merge-guard.sh`): 판정기 자리 = `<루트>/.fable-team/LIVE_BIN` 1줄 + `/ft_approval_equiv.py`(첫 줄이 bash 대리 파일이면 안 씀) → 없으면 도구 폴더 형제(설치·시험 꼴) → 둘 다 없으면 판정 0 + 이유 «라이브 판정기 없음: <경로>» · 후보 순서 = `git rev-list <S> ^origin/main` 에 든 승인 먼저, 그다음 최신순 · `autonomy.log` 는 한 번만 읽어 집합(후보마다 다시 읽던 것) · 거절 이유에 판정기 stderr·rc·«판정기 7초 초과»·«후보 N 중 M 대조 · 마감 21초»(마감 21초·후보당 7초 불변 — 판정 666).
- 고침 ③(`ft-autonomy-scope.sh` + `ft-autonomy.sh` 정규식 1곳): 같은 범위 원장에 «이미 센 승인 A» 가 새 sha 의 EQUIV(판정기 rc0)면 원장 줄 종류 `equiv` · used·today 증가 0 · 출력 `SCOPE-OK … class=equiv equiv=<A>`(판정 후보 = 원장 sha 최신순 · 총 21초·판정기 7초 상한) · `SCOPE_USE_RE` 종류에 `equiv` 추가(로그 꼴 정본 — 안 넣으면 상태가 위변조로 읽힌다).
- 시험 `tests/test_r560_approval_equiv_base_and_hook.sh` ⓐ~ⓙ 19칸(임시 git 리포+가짜 origin/main ref · 임시 루트/상태/훅 폴더 · 실 상태·실 gh·실 슬랙·외부 호출 0): ⓐmain 한 칸 전진에도 EQUIV(base=병합한 main) ⓑ병합 커밋이 그 밖의 변경 → NOT-EQUIV ⓒmain 아닌 가지 병합 → NOT-EQUIV ⓓ병합 2번 = 마지막 병합의 main 쪽 부모 ⓔ옛 main 위 rebase → EQUIV mode=rebase ⓕ훅: 남의 세트 400개 + 자기 승인(가장 옛날) → EQUIV(0s) ⓖ판정기 rc≠0·stderr · 7초 초과 · 마감 21초 이유 ⓗ도구 자리가 루트 shim 폴더여도 LIVE_BIN 판정기로 EQUIV · 라이브 판정기 없음 = 거절 · 로그 여는 자리 1곳 ⓘ범위: EQUIV 재승인 = class=equiv · used·today 그대로 · 원장 종류 equiv ⓙ정본 미러 cmp0. 전 FAIL 12칸(`evidence/r560/00-before-red.txt` · base 판정기·훅·범위 도구로 같은 시험) → 후 PASS 19/19(`01-after-pass.txt`).
- 기존 시험: `test_autonomy_merge_equiv.sh` fail=0 · `test_merge_land_equiv.sh` ALL PASS · `test_autonomy_scope.sh` fail=0 · `test_autonomy_hooks_layout.sh`/`test_autonomy_hooks.sh`/`test_autonomy_scope_classify.sh` ALL PASS · `test_autonomy_scope_pack.sh` fail=0 · `test_autonomy_core.sh` = 192 checks fail=3(선행 실패 — base 에서도 같은 3건: H3 큐 쓰기 실패 2건·7초+재시도 값) (`02-existing-tests.txt`) · `ruff check` PASS(`03-ruff-and-cmp.txt`).
- 기존 시험 1칸을 이 카드의 계약으로 고쳐 씀: `test_merge_land_equiv.sh` ⓜ «rebase 대상이 옛 main → NOT-EQUIV» 는 r560 이 뒤집는 동작이라 «judge 는 EQUIV(base=옛 main) · 착지는 게이트가 막는다(«현재 main 을 포함하지 않음»)» 두 칸으로 바꿨다 — 판정 완화가 착지 틈이 아님을 같은 시험에서 확인.
- **DA⑥ r1 HOLD(2026-10-20) 반영** — 근본 2: ①판정기 `mx` 가 «마지막 병합의 main 쪽 부모» 라서, 뒤 병합이 더 옛 main 을 병합한 역행 그래프에서 main 이 지운 파일을 되살린 S 가 EQUIV 로 샐 수 있다 → `mx = merge-base(S, origin/main)`(«S 가 이미 품은 가장 새 main») 로 바꾸고 **병합 커밋의 main 쪽 부모가 전부 mx 의 조상**인지 덧검사(아니면 NOT-EQUIV «main 부모 역행») · 정상 꼴(S 가 M1 병합 뒤 main 이 M2)에선 mx = M1 그대로라 ⓐ~ⓙ 결과 불변. ②판정기 출력 해독 실패(잘못된 UTF-8)가 훅 **바깥** 예외로 새서 허용(fail-open) → EQUIV 경로(판정기 찾기·실행·해독·파싱) 전체를 try 로 감싸 예외 = **deny**(이유 `판정기 예외: <종류>`) · 출력은 bytes 로 받아 `errors="replace"` 로 해독 · 바깥 «파싱 불가 = 허용» 은 도구 입력 JSON 파싱에만 남긴다. 덧처방 3: 후보 중 **이미 origin/main 의 조상인 승인**(착지한 세트)은 근거에서 제외(이유 줄 «착지한 승인은 근거 아님») · **main push 는 최신 main 을 품은 head 만**(옛 main 위 head 직접 push = main 이 지운 것을 되살림 → deny).
- **DA⑥ r2 HOLD② 반영(시험만 · 코드 손 0)** — 남은 결함 = ⓚ·ⓛ·ⓞ 가 구판(b31f65a3a8)에서도 PASS(회귀를 못 잡음). 원인 = 나노 픽스처의 «옛 main 을 git merge» 가 이미 조상이라 no-op(병합 커밋 0) → DA 원본 그래프와 달랐다. 고침 = DA 원본 두 그래프를 **plumbing(`commit-tree`+`merge-tree`)** 으로 글자 그대로 재현 — 그래프 1(역행): A = B+own · U = merge-tree(A,M2) · S = merge-tree(A,M1)(retired.md 부활 · M2 ⊂ S) · 그래프 2(착지한 승인 B): V = M2 트리 · F = M1 트리. 훅 라이브 판정기 사본도 `$BIN` 고정에서 `$EQP` 로(구판 대조 때 훅도 그 판을 쓰게). 실측 = 신판 `fail=0`(29칸 · C 로케일) · 구판 b31f65a3 `fail=7`(ⓚ·ⓛ×3·ⓜ·ⓝ·ⓞ) → `evidence/r560/05-r2-before-after.txt`.
- 추가 시험 ⓚ~ⓞ(같은 파일 · 29칸으로 확장): ⓚ 역행 그래프(main 이 지운 gone.txt 를 옛 main 병합으로 되살린 S) → NOT-EQUIV ⓛ 그 head(남의 승인만 등록) → 훅 deny ⓜ 판정기 출력 잘못된 UTF-8 + rc3 → 훅 deny · 판정기 내부 예외(트레이스백) → 훅 deny + 이유에 stderr 첫 줄 ⓝ 옛 main 위 head 직접 main push → deny · 최신 main 을 품은 승인 head push 는 통과 ⓞ 역행 꼴 세트의 scope-approve → `class=equiv` 비차감을 못 받음(일반 셈 used=2/5). DA⑥ r1 판(직전 커밋 `bd0c5b9c`)으로 돌리면 ⓜ·ⓝ 2칸 FAIL(`evidence/r560/04-before-red-da6.txt`) — ⓚ·ⓛ·ⓞ 는 그 판에서도 다른 규칙(자기 변경 diff·승인 부재)이 먼저 막아 FAIL 이 아니다(DA 원문 픽스처와 완전히 같지는 않다는 뜻 · 거짓 통과 0 은 양쪽 동일). C 로케일(`LC_ALL=C LANG=C`)에서도 29칸 PASS · 기존 시험 8종 567칸 PASS(코어 3건 = base 동일 선행 실패).
- 설치: 있음 — 키트 3(`bin/ft_approval_equiv.py`·`bin/ft-autonomy-scope.sh`·`bin/ft-autonomy.sh` 정본 짝 cmp0) + 훅 1(`templates/hooks/autonomy-merge-guard.sh` → `~/.claude/hooks/`) + 시험 1 → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · 홈 훅 cmp0 · 데몬 0. **설치 집행·실사건 확인(chatbot `1aa037dc9a`→`226c4c4fff`)은 master 소관 — 미실행.** 되돌림 = `.bak-r560`.
- 범위 밖: 판정 규칙 넷 완화(거짓 통과 0 유지) · 승인 폴더 418개 정리(완성 후 원장 · 삭제는 HIL) · shim 생성기가 `.py` 를 bash 대리 파일로 만드는 것 자체(다른 호출자 있으면 같은 고장 — 완성 후 원장 1행) · `ft-merge-land.sh` 의 30초 상한 · 이미 오빠께 간 재승인 h(desk 몫).

## 2026-10-20 — `ft-nano-close` «재실행» 이 표준 나노 좌석의 워크트리 정리를 통째로 건너뛰던 것 (r566 · 1.1.116 · 동작 변경)

- 사건(arch 111 실측 2026-10-20 22:1x · 두 팀 보고): 재실행 경로(명부에 행 없음 ∧ 원장에 닫힘 행 있음)는 워크트리를 «원장 행의 `wt=/절대경로`» 에서만 찾았다. 표준 나노 행은 `wt=planned`·`wt=skipped:…` 같은 상태 말이라 `SEAT_WT=""` → 계획 생성 0 · 실행 0. 그래서 09-25 표준승인 범위 안의 ops `ta-1` · cfo `1283` 워크트리 2곳이 남았고, 두 팀장이 손으로 `worktree remove` 를 치다 훅에 막혔다(우회 0). 덤: 두 좌석의 첫 계획(10-12)은 baton «워크트리 삭제» 단계가 시간 상한에 죽어(`Terminated: 15`) `.sh.hil` → 생성기 버전이 바뀌어 `.sh.hil.stale` 이 됐는데, sweep 은 `.sh` 만 돌고 재실행은 새 계획을 안 만들어 영영 멈춰 있었다.
- 고침 ①(`ft-nano-close.sh` 재실행 분기): `--wt`/`--branch`·`--shared-wt` 가 아니면 `_KEY` 를 계산해 `_resolve_seat_wt` 로 `SEAT_WT`·`SEAT_BR` 를 «좌석 이름으로» 다시 잡는다(`wt=<경로>` 유효 시에는 그 값이 이긴다 · 그 밖에는 옛 동작 그대로). 함수 정의 2개(`_is_seat_branch`·`_resolve_seat_wt`)를 재실행 분기 «앞» 으로 옮겼다(동작 불변 · `[structure]` 커밋 분리).
- 고침 ②(조건 4 · 전부 참일 때만 실행): ⓐ세션 0(기존 tmux 조회 성공 + PANE 없음 또는 kill 성공 뒤) ⓑ`nano/<키>[-rN]` ⓒ`$ROOT/.worktrees/` 아래 `git worktree list --porcelain` 등록 ⓓ`git branch -r --contains HEAD` ≥1줄(그 커밋이 원격에 있다). ⓓ 만 거짓이면 실행 0 · 계획은 `.sh.hil` + `# 실행 보류 — 원격에 없는 커밋 N` 1줄.
- 고침 ③(통과 시): 옛 계획(`.sh.hil`·`.sh.hil.stale`·`.sh.stale`)을 **지우지 않고** `.superseded-<YYYYmmdd-HHMMSS>` 로 `mv` → `_wt_clean_plan` → `_wt_clean_run`(계획 본문의 가드 6·` D` 처리·보관 tar·가지 보존 **그대로 재사용**) → 출력 `워크트리 정리: <결과>` 1줄. 가지 삭제 0 · 계획 본문 변경 0.
- 시험 `tests/test_nano_close_rerun_wt_clean.sh` ⓐ~ⓖ(임시 git 리포 + bare 원격 + 가짜 tmux·reap·baton·sweep · 실제 리포·명부·tmux 세션·외부 호출 0 · `GIT_*` env 0): ⓐ옛 `.sh.hil.stale` 잔존 재실행 → 옛 계획 보존 + 새 계획 실행(`sweep --finish` 위임) + `워크트리 정리: cleaned` + 폴더 없음 + 가지 sha 그대로 ⓑ추적 파일 ` D` 다수 → [wip] 커밋 0(가지 sha 그대로) ⓒ가지 HEAD 가 어떤 원격 ref 에도 없음 → 실행 0 · `.sh.hil` + 이유 줄 ⓓ세션 살아 있음 → kill 뒤 실행 · kill 실패면 실행 0 ⓔ`--wt/--branch`·`--shared-wt` 재실행 → 지금 동작 그대로(새 계획 0) ⓕtmux 조회 실패 → REJECT · 실행 0 ⓖ명부 행 있음 = 재실행 분기 0. **전 FAIL 10 failed/17 passed**(`evidence/r566/01-before-red.txt`) → 후 PASS **ALL PASS**(`02-after-pass.txt`).
- 기존 나노-close 시험 10종 그대로 PASS(627 passed · 0 failed · `evidence/r566/03-existing-tests.txt`) · `bash -n` 2종 OK · 키트↔`harness/bin` 짝 cmp0(`04-kit-bin-cmp.txt`). 실사건 2건 재료는 읽기 전용으로만 확인(`05-real-cases-readonly.txt`: 두 좌석 원장 행 `wt=skipped:…` · 워크트리 등록 · 가지 HEAD = `origin/nano/…` · 잔존 `.sh.hil.stale` 2) — **정리 실행은 master 착지·설치 뒤 두 팀장의 같은 재실행이 한다**.
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-nano-close.sh`) + `harness/bin` 짝 cmp0 + 시험 1 · `install.sh` REQUIRED 목록 변경 0 · 새 스크립트 0 · 데몬 재기동 0. **설치 집행·실사건 2(cleaned · 폴더 없음 · 가지 보존)는 master 소관 — 미실행.** 되돌림 = `.bak-r566`.
- 범위 밖: 계획 본문(가드·baton 호출) · `ft-wt-sweep.sh` 시간 상한(`r-wt-sweep-route-timeout` 이 이미 처리) · 원장 행 꼴 · 지금 두 폴더의 손 정리 · 브랜치 삭제(HIL 그대로).


## 2026-10-20 — 자율 범위 분류기가 «팀 폴더 첫 문서 착지» 를 docs 로 읽는다: 카드 이동 짝 맞추기 + 팀 폴더 비실행 파일 + 분류 속도 (r559 · 1.1.117 · 동작 변경 · r566 위)

- 사건(arch 110 실측 2026-10-20 20:0x): 11팀이 첫 일로 하는 «팀 폴더에 문서 옮겨 담기» 를 `autonomy_scope_classify.py` 가 docs 로 못 읽어 오빠 낱건 승인이 폭주했다 — ①cfo `ad8810719b`(970파일) 분류 **114.4초**(상한 7초 → rc=142 «출력 없음») ②chatbot `1aa037dc9a` 카드가 대기→진행으로 옮겨지며 상태 줄이 바뀌자 git 이 `D`+`A` 로 봄 → `FORBID kind=delete` ③lecture `5ef99a2634` 팀 폴더 증거의 `.txt·.json·.raw·.py·.sh` 가 «`.md` 만 docs» 규칙에 걸려 `CLASS code`. desk 추가 사건: ops `d1df8c06cf` 가 `FORBID kind=move-changed R080`(카드 이동 + 증거 줄 추가).
- 고침 ①(`autonomy_scope_rules.py` `BYZ_TABLE`): **낱말 금지 줄 아래**에 세 줄 — `("code","pytest", …(test_*.py|*_test.py|conftest.py))` · `("docs","team-file", ^design/teams/<팀>/(?!.*\.(py|sh)$).+$)` · `("docs","team-evidence", ^design/teams/<팀>/evidence*/.+\.sh$)`(★DA⑥ r1 H3: evidence 안이라도 `.py` 는 code — pytest 수집이 `__init__.py`·import helper 를 실제 실행★). ★낱말 금지(billing·key)보다 **위**에 두면 cfo `…toss-payments.html` 이 docs 로 새므로 아래에 둔다(cfo 는 `FORBID kind=billing` 유지 · 카드 문구 «낱말 금지 줄보다 위» 와 다른 이유 = 완료조건 «cfo billing 유지» 가 우선)★.
- 고침 ②(`judge_row` + `pair_card_moves`): 같은 팀 `indices/{대기,진행,완성,보류}/` 사이 «같은 파일 이름 · 같은 모드 · 양쪽 docs» 이동은 **유사도와 무관하게** `docs move`(R0xx 포함 · ops R080 닫힘). `D`+`A` 로 잡힌 같은 카드는 판정 전에 `R100` 한 행으로 짝을 맞춘다(`pair_card_moves`). ★짝 없는 `D` 는 지금처럼 `FORBID delete` · 다른 팀 폴더/indices 밖 이동은 그대로 `FORBID` · `R100` 의 «이름 바뀜» 금지도 그대로★.
- 고침 ③(속도 · 원인은 프로파일로 확정 · DA⑥ r1 H1/H2 반영): 114초의 **96%가 `ft_secret_judge.plan(추가 줄 전문)`** 이었다(14MB 글을 세그먼트마다 다시 훑는 이차 비용 · git 호출 7회는 합 3.8초). 새 모듈 `autonomy_scope_secret.py` — ⑴**diff 를 상태 기계로** 읽는다(H1): `diff --git`=새 파일 · `@@` 뒤=hunk 안 · hunk 안의 `+` 줄은 `+++` 여도 추가 줄 · 경로는 `-c core.quotepath=off` + C 따옴표 풀기(`"b/…"` 가 따옴표로 감싸여도 풀린다) · 경로를 못 풀면 그 파일=code ⑵새 파일은 «바뀐 뒤 전문 = 추가 줄» 이라 `cat-file` 생략, 바뀐 문서는 `git cat-file --batch`(400개씩 · 바이트로 읽어 크기 어긋남 0)로 1회 ⑶문서는 **«평범한 산문» 만 plan() 밖**(H2 — 바뀐 뒤 전문 기준: ``` `~~~` 울타리 안 · 4칸/탭 들여쓰기 · 백틱 포함 · `! `/`$ `/`> ` 시작 · 표 행(백틱) 은 plan() · `$ `·`! ` 는 프롬프트 표시를 떼고 넘긴다 · 전문을 못 읽으면 그 문서 전부 plan()) ⑷code 파일은 추가 줄 전문 ⑸`SECRET_SHAPE`(키 원문)는 상태 기계가 뽑은 **모든 추가 줄**(줄이지 않음) ⑹`ft_secret_judge` 자체는 무변경.
- 고침 ④(`ft-successor-open.sh` ⓐ' 거절 문구): «`reply --thread <이름>` 으로(r414)» → «방 글 = post --to <이름> · 오빠 글 답 = reply --to-slack <ts>». 판정 규칙(본문 `--ts <10자리>.<6자리>` = 열기 0)은 불변.
- 시험 `tests/scripts/test_thread_room_post.py` ⓐ~ⓖ 8칸(가짜 Slack `_proposal_fakes.slack` · 임시 등록부·원장·답 기록 · 실제 Slack·실제 `~/.hermes/state` 쓰기 0): ⓐ`post --to desk` → `thread_ts` 없음·등록부 채널·`POSTED <ts>`·답 기록/등록부 불변 ⓑ`--channel` 직접 + 모르는 이름 REJECT + 인자 택1 강제(rc2) ⓒ답 안 된 글 0 인데 `--thread desk` REJECT(전 FAIL 자리) ⓓ`--force-thread` → 보냄 + WARN ⓔ`FT_SLACK_TOPIC_ONLY=` 빈 값 = r558 거절만 · `desk,ops` = 두 이름 ⓕ쪽지 끝 2줄 + 토큰 줄 불변 ⓖ`--to-slack`·`--ts` 기존 길 불변 · `post` 는 장부 미기록. 전 FAIL 8 failed(`evidence/r561/01-before-red.txt`) → 후 PASS 8 passed(`02-after-pass.txt`).
- 기존 시험(카드·slack-mirror 인접만 · 광역 금지): `test_thread_reply_to_slack.py`·`test_thread_post.py`·`test_thread_post_args.py`·`test_post_guard.py` = 83 passed · `tests/test_thread_reply_named.sh` ALL PASS(`06-…txt`). r558 시험은 `FT_SLACK_TOPIC_ONLY=`(빈 값)을 env fixture 에 넣어 r558 규칙만 보게 했고, 쪽지 끝 시험은 `답` 줄이 `lines[-2]` 로 한 칸 밀린 것을 반영 — r414 셸 시험도 같은 env 1개 추가. base 대조(`05-base-diff.txt`): `test_thread_post_attach.py` 1건이 base(4066f4d4)에서도 같은 rc = 이 카드 무관(이 머신 `.md` mimetypes). `ruff check`(바꾼 8파일) PASS(`04-ruff.txt`).
- 설치: 있음 — 새 파일 0 · `install.sh` REQUIRED 목록 변경 0(기존 `thread_post_update.py`·`thread_reply_slack.py`·`mirror_share.py`·`thread_post_args.py`·`byz_thread_post.py` 경로 그대로) + 키트 `ft-successor-open.sh` 문구 1 → `~/.hermes/scripts` cmp0·LIVE_BIN cmp0·수신 데몬 재기동은 master 소관(미실행). 되돌림 = `FT_SLACK_TOPIC_ONLY=`(빈 값) 또는 `.bak-r561`.
- 범위 밖: 등록부 desk 뿌리 글 정리·삭제(보고용 옛 글 · 남김) · 다른 채널(대화 수신 r238·보드) · desk 인계서·메모리 문구(장치가 막으니 desk 몫) · 범위 승인 알림(`autonomy_scope_post` 는 이미 최상위) · 실제 사건 확인(방 글 1건 + 거절 1건)은 master press 소관.

## 2026-10-20 — desk 답이 «오빠 글 밑»으로 간다: `reply --to-slack` + `--thread` 거절 + 쪽지 답 명령 1줄 (r558 · 1.1.110 · 동작 변경)

- 사건(desk 29 실측 · arch 110 2026-10-20 19:5x): 오빠 새 최상위 글 ts=1792492349.071989(19:32) 수신은 정상인데 desk 답 5건이 전부 등록부 `.fable-team/state/slack-threads.json` 의 옛 뿌리(1792422462.316339 · 그날 아침) 밑으로 갔다 — 오빠 글 밑 답 0. 원인 = 답장 도구에 「오빠 글이 온 스레드로 답한다」 길이 없음(`reply` = `--ts`(손으로 아는 스레드) | `--thread <이름>`(등록부 뿌리) 둘뿐) · 규칙·메모리로만 적어 둔 것이라 desk 승계마다 새 desk 가 인계서의 같은 명령을 써서 재발.
- 고침 ①(`thread_post_args.py` reply): `--to-slack <오빠 글 ts>` 를 `--ts`·`--thread` 와 택1(상호 배타)로 추가 · `--force-thread` · 본문은 `--text` 또는 `--text-file` 택1(쪽지의 답 명령을 그대로 복사해 쓸 수 있게). `--channel` 기본값 규칙은 그대로(`--ts` 만 옛 기본 채널 — `--to-slack` 채널은 수신 원장이 정한다).
- 고침 ②(`thread_reply_slack.py` 신규 = 분리 · 200줄 한도 · `thread_post_update.cmd_reply` 가 부른다): `--to-slack T` → 수신 원장(`~/.hermes/state/byz_slack_mbox_inbound.<채널>.json` · env `FT_SLACK_STATE_DIR`/`FT_SLACK_INBOUND_LEDGER`)의 `ledger[T].thread`(빈 값 = T)를 뿌리로 답하고 답 기록(`byz_slack_answered.json` · env `FT_SLACK_ANSWERED`)에 T→답 ts. 원장에 없는 ts 는 REJECT(추측 뿌리 0). `--thread <이름>` → 원장에서 «그 이름 계보 좌석(`#N` 뗀 이름)에 이미 전달 · 창(7일) 안 · 답 기록 없음» 오빠 글이 있으면 뿌리 글·등록부를 건드리기 «전» 에 REJECT(그 ts + `--to-slack` 명령 출력) · `--force-thread` 면 보내고 stderr WARN(답 기록이 비어 처음 켜면 지난 7일치가 전부 «답 안 됨» 이므로 문구는 최신 3건 + «…외 N건»). 원장은 «읽기만» 한다.
- 고침 ③(`mirror_share.answer_hint` · `mirror_inbound.attempt_send`): 좌석 쪽지 끝에 `답 = python3 ~/.hermes/scripts/byz_thread_post.py reply --to-slack <ts> --text "…"` 1줄(기존 출처 토큰 `(slack:<ts>:<role>)` 줄 «뒤» · 토큰 줄 글자 불변 — 중복 판정 `marker_seen`/`queue_has` 가 줄 끝 일치를 읽는다).
- 시험 `tests/scripts/test_thread_reply_to_slack.py`(가짜 Slack·임시 원장·등록부·답 기록 · 실제 Slack·실제 `~/.hermes/state` 쓰기 0) ⓐ~ⓗ 10칸: ⓐ최상위 글 T → `thread_ts=T` + 답 기록 ⓑ스레드 답글 R(`thread=P`) → `thread_ts=P`·새 스레드 0 ⓒ원장에 없는 ts REJECT ⓓ답 안 된 오빠 글 + `--thread desk` REJECT + 명령 출력 ⓔ답 기록 있으면 지금과 같음 ⓕ`--force-thread` 경고 후 전송 ⓖ쪽지 끝 답 명령 1줄 + 토큰 줄 불변 ⓗ기존 시험 무변경. 전 FAIL 7 failed/3 passed(`evidence/r558/01-before-red.txt`) → 후 PASS 10 passed(`02-after-pass.txt`).
- 기존 시험: `test_thread_post.py`·`test_thread_post_args.py`·`test_post_guard.py`·`test_inbound_humans_and_install.py`·`test_byz_slack_mbox_inbound.py` = 166 passed 1 skipped(`03-existing-tests.txt`) · `tests/test_thread_reply_named.sh` ALL PASS · `tests/test_magazine_install_list.sh` ALL PASS · `ruff check` PASS(`04-ruff.txt`). 선행 실패 2건은 이 변경과 무관함을 base 대조로 확인: `test_thread_post_attach.py` 의 `.md` content-type(이 머신 python mimetypes) · `test_slack_readonly_share.sh`(`Namespace` 에 `state_dir` 없음) — base 에서도 같은 rc.
- 설치: 있음 — `install-magazine.sh` REQUIRED 에 `thread_reply_slack.py` 추가(빠지면 `byz_thread_post` ImportError) → 키트 6 + 시험 1 · `~/.hermes/scripts` cmp0·수신 데몬 재기동은 master 소관(미실행). 되돌림 = `.bak-r558` 또는 `--thread desk --force-thread`(명시 + WARN).
- 범위 밖: 이름 스레드 등록부(r414)·보고 글(`start`/`progress`/`result`)·수신 판정·수신 원장 쓰기 · desk 인계서·메모리 문구 정리(장치가 막으니 desk 몫) · 다른 채널(대화 수신 r238)의 같은 꼴 · 실사건(desk 승계 1회 → 오빠 새 글 → 답이 그 글 밑 → 그 밑 오빠 답글이 새 desk 도착)은 master 가 press 로 확인.

## 2026-10-20 — 상태판 발행: 한 팀을 못 읽어도 «그 팀 칸 확인 못 함» + 나머지 팀 발행, 전 팀 실패만 발행 0 (r554 · 1.1.106 · 동작 변경)

- 사건(arch 110 실측 2026-10-20 18:5x · `/tmp/byz-ft-board-publish.log`): `com.byz.ft-board-publish`(5분)가 `ft-board: RuntimeError: seats-graphics.json: 카드 폴더 없음 — …/.worktrees/harness-ops/design/teams/graphics/indices` + `ft-sheet-publish: collect 실패 — 발행 0` 으로 **매 틱 전 팀 발행 0**(`launchctl list` last exit 1). 원인은 명부 `seats-graphics.json` 의 `_cards_wt=harness-ops`(그 가지엔 새 자리 카드 폴더 없음) 한 칸 — `ft_board_collect.team_block` 이 raise 하고, `collect()` 가 팀 목록을 한 리스트 식으로 돌아 한 팀 예외 = 전체 예외가 됐다.
- 고침 ①(격리 · `ft_board_collect.py`): `collect()` 가 팀마다 `team_or_error()` 로 감싼다 — 실패 팀 = `{"key","label","error": "<원인 원문>"}` 칸 하나(숫자 칸 **없음** · 0·빈 값·옛 값으로 채우지 않는다 = #0 RULE) + stderr `ERROR <명부 이름>: <원인>` 1줄. `team_block` 의 raise 2곳(카드 폴더 없음 · `_tree` 파일 없음)은 그대로 — 원인 문구 유지. 명부 JSON 이 깨진 팀은 `error="<명부 파일> <예외 이름>: <메시지>"`.
- 고침 ②(그리기): `ft_board_render.summary_lines/session_lines` 는 error 팀을 `- <팀> | 확인 못 함: <원인>` / `└─ 확인 못 함: …` 한 줄로(숫자 칸 대신) · `ft_board_render_tree`(① 완성 트리)도 같은 꼴 · 다른 팀 그리기 글자 불변. **시트**(오빠가 보는 판)는 `ft_board_sheet` 모델에 `errors` 를 실어 `ft_board_sheet_tree.tree_lines` 첫머리에 `⚠ 확인 못 함 <팀>: <원인>` 을 찍고, ③ 칸에는 «확인 못 함» 칸(소유자 미확인 계수에 들어간다). `ft_board_teams`(틱 «일함/정지» 줄)·`ft_board_seat.stalled_lines`(master 감시)도 그 팀을 «확인 못 함»/«확인 불가» 행으로 남긴다(팀 목록에서 빼지 않는다). `ft_board_snapshot.diff` 는 `states` 없는 팀을 빈 dict 로 본다.
- 고침 ③(종료 코드 · `ft-sheet-publish.sh`): collect 결과를 읽어 `NERR>0` = **부분 발행**(나머지 팀은 지금처럼 발행됨) · rc **2** — 같은 발행 rev 로 발행 0 인 틱도 rc 2(조용한 성공 0) · 전 팀 실패(`NERR==NTEAM`) = 지금과 같은 발행 0 · rc 1. 3(PDF 첨부 실패)은 그대로 우선.
- 시험: `tests/scripts/test_ft_board_teams.py` 에 ⓐ~ⓔ 5칸(카드 폴더 없음 · `_tree` 없음 · 명부 JSON 깨짐 · 그리는 쪽 줄 + 다른 팀 줄 base 대조 · stderr ERROR) · `tests/test_sheet_publish.sh` 에 ⓔⓕ 3칸(부분 발행 rc 2 · 같은 rev 재실행도 rc 2 · 전 팀 실패 발행 0 rc 1 · 가짜 보드가 `$D/collect.json` 을 그대로 내보내게 1줄). `tests/test_board.sh` 의 「`_tree` 없음 = raise」 칸은 이 카드의 계약(격리)으로 고쳐 씀 — 옛 기대(전 팀 중단)는 r554 로 폐기.
- 전 FAIL → 후 PASS: 고치기 전 코드 + 새 시험 = pytest **5 failed · 6 passed** · `test_sheet_publish.sh` fail=3 · test_board.sh 새 칸 1 FAIL(`evidence/r554/00-before-fix.txt`) → 고친 뒤 pytest **23 passed**(teams+roster) · `test_board.sh` ALL PASS 72 · `test_sheet_publish.sh` fail=0 37 PASS(`01-after-fix.txt`) · 관련 셸 시험 8종 rc0 · `ruff check` PASS.
- 실사건 재현(임시 픽스처 루트 · 실 gh/tmux/슬랙/LLM 호출 0 · 실 `.fable-team` 쓰기 0 · `03-real-incident.txt`): 명부 한 장의 `_cards_wt` 를 없는 워크트리로 → collect **rc 0** + stderr `ERROR seats-cfo.json: 카드 폴더 없음 — …` · `render --sheet --text` 에 `⚠ 확인 못 함 cfo: …` · `render --term` ⓪·①·② 세 자리에 «확인 못 함» 줄 · `snapshot` 정상.
- 설치: 있음 — 키트 8(`ft_board_{collect,render,render_tree,sheet,sheet_tree,teams,seat,snapshot}.py` 중 이번 변경분) + `ft-sheet-publish.sh`(`harness/bin` 짝 cmp0 9 · `02-kit-bin-cmp.txt`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 9 · 데몬 재기동 0(launchd 가 5분마다 새로 부름) · 되돌림 = `.bak-r554`. **설치 집행·명부 2칸 고침은 master 소관 — 미실행.**
- 범위 밖: `seats-graphics.json` 2칸(`_cards_wt`·`_tree`) 고침 = master 즉시(이 카드의 ①) · `_tree` 가 남의 임시 워크트리를 가리키는 명부 5장 · `ft_board_sheet_cards:team_cards` 의 같은 칸 읽기(폴더 없으면 조용히 0장 — 이 카드 뒤에도 남는 결) · 이동 도구가 `_cards_wt` 를 안 바꾼 문제 · harness-ops 가지 뒤처짐.
## 2026-10-20 — 부팅 ensure 가 좌석이 «실제로 쓰는 포트» 의 프로젝트를 띄운다 + ensure 자식이 안 끊긴다 (r555 · 1.1.107 · 하네스 내부 장치 · 새 장치 0)

- 사건(재부팅 뒤 좌석 다수가 «Serena 미사용» · arch 110 실측 2026-10-20 19:0x): ①좌석은 전부 `~/.claude.json` 의 `http://127.0.0.1:9493/mcp`(v6-realtime-live 해시 포트)에 붙는데 부팅 ensure(`com.byz.serena-ensure`)는 루트 경로로 렌더돼 해시 포트 9228 을 띄웠다 ②그 9228 조차 `~/.claude/logs/serena-ensure.launchd.log` «READY (port=9228, pid=25526)» 1초 뒤 `serena-http-9228.log:76` «Shutting down» · 오류 줄 0 = 밖에서 내린 꼴(plist 에 `AbandonProcessGroup` 이 없어 ensure 스크립트 종료 시 launchd 가 nohup 자식까지 정리 — 시각 근거).
- 고침(설치기 렌더 1곳 + 템플릿 키 1 + BOOT 문구 1줄): ①`install.sh` `resolve_ensure_project` — ensure 프로젝트 = ⓐ`--ensure-project <경로>` ⓑ없으면 `$HOME/.claude.json` `projects[ROOT].mcpServers.serena.url` 의 포트 → `~/.serena/bridges/<포트>.json` 의 `project` ⓒserena url 자체가 없으면 ROOT + stderr WARN 1줄. 고른 경로의 `port_for`(serena-mcp.sh:33 과 같은 식)가 url 포트와 다르면 die 2 — «맞출 기록이 없으면 조용히 루트로 내려가기 0». dry-run·apply 줄에 `ensure project=<경로> port=<n> (출처 …)` ②템플릿 자리표 `__ROOT__` → `__ENSURE_PROJECT__` + `<key>AbandonProcessGroup</key><true/>` ③tmuxc `COMM-GUIDE-BOOT.md` 1번 항목 인자 이름 `session_id=…` → `session=…`(«session 없이 부르면 `Field required`») — 줄 수 46 불변 · 매핑표 무변경.
- 시험 `tests/test_r555_serena_ensure_port.sh`(가짜 HOME `.claude.json`·`bridges/` · 가짜 launchctl · 임시 루트 — 실 launchd·uvx·9493 호출 0 · 실 홈 쓰기 0): 고치기 전 **FAILED=16** → 고친 뒤 **ALL PASS 22 rc0**. ⓐ좌석 포트 기록으로 렌더 → ensure 인자 = 그 프로젝트(옛 판 = ROOT) ⓑurl 포트 기록 없음 → rc2 «좌석 포트 <n> 의 프로젝트 기록 없음» ⓒ`--ensure-project` 명시 = 그 경로 · 포트 불일치 rc2 ⓓurl 없음 → ROOT + WARN 1줄 ⓔ`plutil -lint` OK · `AbandonProcessGroup true` · 템플릿에 옛 자리표 0 ⓕBOOT 줄 수 불변 · diff 한 덩이 · 1번 줄 `session=`·«session 없이» 있고 옛 `session_id=…` 0.
- 실 구성 dry-run(쓰기 0): `ensure project=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live port=9493 (출처 claude.json url port=9493 → bridges/9493.json)` rc0 — 사건 ①이 렌더 단계에서 닫힌다.
- 증거 `harness/evidence/r555/`: `01-before-red.txt`(FAILED=16) · `02-after-pass.txt`(ALL PASS 22) · `03-existing-tests.txt` · `04-real-dryrun.txt` · `05-base-diff.txt`.
- 기존 시험: `test_serena_guard_bash32.sh` rc0 ALL PASS(무변경). `test_r66_codex_serena_boot.sh` FAIL 2 는 내 변경 파일이 아니다 — ①홈 BOOT sha 가 r66 기준·staged-r66 어느 쪽도 아님(그 사이 판이 바뀜) ④`docs/rules/serena-mcp-usage.md` 가 이 팩에 없음.
- 설치: 있음 — `harness/install.sh --apply --project <루트>` 로 키트 2 + tmuxc 문서 1줄, 그리고 `kit/zombie-clean/install.sh --apply --root <BYZ 루트>` → 새 렌더 plist(cmp0) + bootout/bootstrap. **설치 집행은 master 소관 — 미실행.** 되돌림 = plist `.bak-r555` + BOOT `.bak-r555` + `launchctl bootout/bootstrap`.
- 범위 밖: `~/.claude.json` 좌석 url 바꾸기(오빠 설정) · `serena-mcp.sh` 포트 계산식 · serena-guard 메모리 재시작 규칙 · pyright 반복 종료(미확인) · 옛 bridges 기록 정리 · `AbandonProcessGroup` 추정이 실사건에서 틀리면(kickstart 뒤 30초 안에 또 꺼짐) 이 카드 안에서 재측정.

## 2026-10-20 — pi 나노 기본 effort = low + pi «코드» 나노에 tmuxc `--serena` (r556 · 1.1.108 · 동작 변경)

- 사건: pi 로 여는 나노가 claude 나노와 같이 «생각 많이(high)» 로 열렸다 — 오빠 인터뷰 결정 «pi 나노만 low»(aifp 팀장 1 → 하네스 master 85 쪽지 · arch 110 실측 2026-10-20 19:2x: `ft-nano-spawn.sh:13` `EFFORT="high"` 리터럴 · `--tier search` 는 `EFFORT` 를 손대지 않아 high 상속 · aifp 실측 같은 일 off 1.25s vs high 2.08s). 같은 자리에서 pi «코드» 나노는 Serena(코드 탐색 도구)가 없어 글자 검색만 했다(tmuxc 0.4.3 에 `--serena` 가 이미 있는데 spawn 이 안 넘김).
- 고침 ①(`ft-nano-spawn.sh:13`·`:15`·`:112` 뒤): `EFFORT_SET=0` 칸을 두고 `--effort` 를 받을 때만 `1` — 티어·명시 `--agent` 결정이 끝난 자리에서 «`AGENT=pi` ∧ `EFFORT_SET=0` → `EFFORT=${FT_PI_EFFORT:-low}`» 1줄로 덮는다. **직접 적은 `--effort` 만 이긴다**(티어가 넣은 high 도 pi 면 low). 되돌림 = env `FT_PI_EFFORT=high`.
- 고침 ②(`:249` 뒤 · `OPEN` 배열): «`AGENT=pi` ∧ `TIER≠search` ∧ `RESEARCH=0` ∧ `FT_PI_SERENA≠0`» 이면 설치 tmuxc 가 `--serena` 를 아는지(`tmuxc help` 글자) 확인해 `OPEN+=(--serena)`. **모르는 tmuxc 면 REJECT**(«설치 tmuxc 가 --serena 모름(0.4.3+ 필요) — FT_PI_SERENA=0 으로 끄면 serena 없이 연다») — 조용히 빼고 열지 않는다. `FT_PI_SERENA=0` 은 명시 끄기 = 붙이지 않고 stderr WARN + PLAN 에 `off(FT_PI_SERENA=0)` 표시. 읽고 모으기만 하는 검색(`--tier search`)·리서치(`--research`) 나노엔 안 붙인다.
- 고침 ③(PLAN 줄): **pi 일 때만** 끝에 ` effort=$EFFORT serena=on|off(<사유>)` 를 덧붙인다 — 기존 칸 순서 불변 · claude·codex·cmd 줄은 문자 단위 동일(`_PLANX` 빈칸).
- 시험: 새 파일 `tests/test_nano_spawn_pi_effort_serena.sh`(ⓐ~ⓗ · 50 PASS · 기존 `test_nano_spawn_tier.sh` 꼴 = 스크립트 블록을 꺼내 돌림 · 실제 tmux·워크트리·pi 실행 0 · 가짜 tmuxc 2벌 `--serena` 있음/없음) ⓐ `--agent pi` 기본 → low(고치기 전 high = FAIL) ⓑ `--effort high` 명시 우선 ⓒ `--tier search`(pi) → low · `--serena` 없음 ⓓ `--research`(pi) → `--serena` 없음 ⓔ `--agent pi`(코드) → `OPEN` 에 `--serena` · PLAN `effort=low serena=on` ⓕ `--serena` 모르는 tmuxc → REJECT(OPEN 전에 끝남 = 부작용 0) · `FT_PI_SERENA=0` → 없이 열고 WARN ⓖ claude·codex·cmd `_PLANX` 빈칸 · `--serena` 없음 · PLAN echo 줄 = base 글자 + `$_PLANX` 1개 ⓗ `FT_PI_EFFORT=high` → high. **전 FAIL → 후 PASS**: 고치기 전 코드에서 6 FAIL(ⓐ·ⓒ ×2 사본 · 블록 B 추출 실패 ×2 · `00-before-red.txt`) → 고친 뒤 ALL PASS 50(`01-after-pass.txt`). **base = ee7b2f60(r555 · 1.1.107) 위로 rebase** — 충돌은 manifest 번호 1칸·CHANGES 순서뿐(r555 항목 보존 · r556 항목을 그 아래에) · 번호는 1.1.108 유지.
- 기존 시험: `test_nano_spawn_tier.sh` · `test_nano_spawn_reuse_info.sh` ALL PASS(무변경) · `test_nano_spawn_body_press.sh`(ⓒ node_modules 2칸)·`test_nano_spawn_teamset_cap.sh`(core.bare 1칸)은 **base 201a08dc 에서도 같은 FAIL** = 원래 실패하던 환경 결함(이 카드가 만든 RED 0 · `02-existing-tests.txt`). 키트 = 추적본 `cmp0`(`03-base-diff.txt`).
- 설치: 있음 — 키트 1(`kit/fable-team/bin/ft-nano-spawn.sh` · 정본 bin 짝 `harness/bin/ft-nano-spawn.sh` cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 데몬 0(spawn 은 부를 때마다 새로 읽음) · 되돌림 = env `FT_PI_EFFORT=high` · `FT_PI_SERENA=0` 또는 `.bak-r556`. **설치 집행은 master 소관 — 미실행.**
- 범위 밖: tmuxc 쪽 변경 · pi 모델 기본값 · claude·codex·cmd effort · pi 닫기 회수 판정기(r542 — 실사건 ⓘ 에서 serena 프로세스가 남으면 그때 이 카드 안에서 고침) · 좌석당 serena 메모리 상한(실사건 ⓘ 에서 RSS 1줄만 기록).

## 2026-10-20 — 오빠 큐 재질문이 매 틱 «큐 읽기 실패» 로 죽던 것: 읽기만 하는 remind·due 는 큐를 origin/main 판에서 읽는다 (r557 · 1.1.109 · 동작 변경)

- 사건(arch 110 실측 2026-10-20 19:3x): `/tmp/ft-tick.log` 에 `2026-10-20 19:16:02 queue_watch: ERROR 큐 읽기 실패: …/.fable-team/state/planner/AUTONOMY-QUEUE.md: [Errno 2] No such file or directory` **37회**. 자율 ON 중엔 쪽지를 안 보내 손실이 ERROR 줄뿐이지만, 자율이 꺼지면 재질문이 **조용히 0** 이 된다.
- 원인: 틱이 서 있는 맨 위 작업 폴더(공용 루트 체크아웃)엔 큐의 새 자리 `design/teams/planner/` 가 없다(main 과 246커밋 갈라짐). `ft_planner_queue` 가 옛 자리 `.fable-team/state/planner` 로 후퇴하는데 그 파일은 이제 없다 — 큐 정본 = `origin/main` `design/teams/planner/AUTONOMY-QUEUE.md`.
- 고침(키트 1파일 · 1곳 · 새 도구 0 · 새 데몬 0 · plist 변경 0): `ft-queue.sh` 에서 `cmd` 가 `remind`·`due` 이고 `FT_QUEUE_FILE`·`FT_PLANNER_DIR` **둘 다 없으면** `ft_queue_ref()` 가 `FT_TEAMS_REF`(기본 `origin/main`)의 명단 꼴 planner 폴더 `AUTONOMY-QUEUE.md` 를 `git show` 로 임시 파일에 써서 그 경로를 쓴다(리포 = `FT_LEDGER_REPO` › `ROOT` · r545 꼴 · 정리 = trap). 못 읽으면 `ERROR 오빠 큐 origin/main 판을 못 읽음: <ref>:<경로>` rc 2 — 옛 자리·체크아웃·뉴스 사본으로 **후퇴 0**(조용한 0건 통과 0). **쓰는 명령(shown·take·add) 의 자리 고르기·`ft_planner_queue` 규칙·틱 순서·상태 폴더 자리(ROOT 기준) 변경 0.**
- 왜 plist 하드코딩·사본 읽기가 아닌가: `FT_PLANNER_DIR` 를 plist 에 박으면 틱 env 전체에 걸려 같은 틱이 부르는 쓰는 명령까지 그 폴더를 쓰게 되고, 값이 읽기 전용 사본(news-ledger-main)이면 미커밋 변경이 생겨 `ft-ledger-repo-sync.sh` 가 영영 전진 0 → 뉴스·매거진까지 낡는다. 사본을 읽는 안은 사본이 몇 시간 낡는다. `origin/main` 판은 모든 체크아웃이 같이 보므로 어느 쪽도 안 건드린다.
- 시험: `tests/test_queue_remind_origin_main_r557.sh` ⓐ~ⓖ — **전 FAIL 9 · PASS 17 → 후 ALL PASS 25**(`evidence/r557/01-before-red.txt` · `02-after-pass.txt`). 기존 큐 시험 4종(`test_queue_reask_r529` · `test_queue_state_r528` · `test_queue_bulk_r530` · `test_proxy_decide_queue_card_resolve`) rc0(`03-existing-tests.txt`) · `bash -n` · `shellcheck` rc0 · py_compile 0.
- 실사건 재현(읽기만 · 격리 상태·가짜 mbox · 제품 쓰기 0 · `evidence/r557/04-real-incident.txt`): FT_ROOT = BYZ 공용 루트에서 옛 판(라이브 1.1.106) `due`·`remind` = rc **2** «큐 읽기 실패» → 새 판 `due` rc **0** `QUEUE-DUE n=0 old=1` · `remind` rc **0** `QUEUE-REMIND sent=0 skip=0 err=0`.
- 설치: 있음 — 키트 1(`ft-queue.sh` · 정본 bin 짝 cmp0 · `05-kit-cmp-and-diff.txt`) → `install.sh --apply --project <루트>`. 틱은 매 회 새로 부르므로 데몬 재기동 0 · plist 렌더 0. **설치 집행·실사건(설치 뒤 첫 틱 `/tmp/ft-tick.log` `queue_watch: ERROR` 0)은 master 소관 — 미실행.** 되돌림 = env `FT_QUEUE_FILE`/`FT_PLANNER_DIR` 명시(지금도 있는 손잡이 · 옛 경로) 또는 `.bak-1.1.109`.
- 범위 밖: 틱 plist 6장·템플릿(변경 0) · `ft_planner_queue`/`planner_queue` 의 공용 루트 후퇴 꼴(쓰는 쪽 · 이동 전 체크아웃 — 그 자리 파일이 없어 ERROR 가 보이는 것이 맞다) · 쓰는 명령이 어디에 쓰고 언제 main 에 올라가는가(planner·desk 몫) · 틱 6장이 같은 줄을 중복 재질문하는가 · 공용 루트 체크아웃 뒤처짐(병합 처방 금지).

## 2026-10-20 — 보낸 쪽지 사본을 `.1` 한 벌이 아니라 `.1`~`.3` 으로 밀어 보관 — 매거진 24시간 창이 창 앞을 덮게 (r553 · 1.1.105 · 하네스 내부 장치 · 새 장치 0)

- 사건(2026-10-20 08:00 매거진 발행 실패 · `~/.hermes/logs/byz_magazine_model.err:220` 원문 «MagazineError: mbox 사본이 회전본을 이어도 창 앞부분을 덮지 못해요(창 시작 2026-10-19T08:00:00)»): 쪽지가 바쁜 날 하루 약 12.5MB 라 `mailbox.log.jsonl` 이 5MB 를 약 10시간 만에 채우고 회전했다. 회전본은 `.1` 한 벌뿐이라 10-19 18:04 보다 앞은 지워졌고, 매거진의 24시간 창(10-19 08:00 시작) 앞부분을 아무도 못 덮어 발행이 매일 위험했다.
- 고침(쓰는 쪽 2 + 읽는 쪽 1 · 한도 5MB 그대로): ① `comm/mbox_conf.py` 에 `SENT_LOG_KEEP = max(1, FT_MBOX_LOG_KEEP or 3)` ② `comm/mbox_guard.py` `_log_sent` 가 한도 초과 시 `.{K-1}`→`.{K}` … `.1`→`.2` 로 밀어 보관한 뒤 현재판→`.1`(새 함수 `_rotate_sent_log`) ③ 같은 꼴을 키트 `kit/fable-team/bin/ft-mbox.py` 에도(`skill/scripts/ft-mbox.py` 정본 bin 짝 cmp0) ④ `kit/slack-mirror/magazine_collect_mbox.py` `read_window` 가 현재판이 창을 못 덮으면 `.1`~`.N`(최대 `FT_MBOX_LOG_KEEP` · 기본 3)을 하나씩 이어 읽고, **빠진 벌에서 멈추며**, 다 이어도 못 덮으면 이어 읽은 파일·첫 ts 를 전부 메시지에 적고 raise(숨기기 0). docstring «회전본은 1개뿐» 고침.
- 왜 한도를 안 키우나: `_received_seqs` 가 send 마다 `.1`+현재판을 통째로 읽으므로 파일이 커지면 쪽지 보내기가 느려진다. 벌 수를 늘리면 파일 하나의 크기는 그대로다.
- 시험(ⓐ~ⓗ · 실 우편함·`~/.hermes` 쓰기 0 · tmp_path 만): ⓐ `FT_MBOX_LOG_KEEP=3`·한도 600B·60건 send → `.1`·`.2`·`.3` 실재 `.4` 없음 · 네 벌 seq 이어 붙이면 오름차순·빈틈 0(r553 전 FAIL) ⓑ 기본값 = 3벌(전 FAIL) ⓒ `=1` = 옛 동작 `.1` 하나 ⓓ 같은 계약을 키트 경로 `tests/test_ft_mbox_sent_log.sh` ⓖ 칸으로 ⓔ 창 시작이 `.2` 안에만 → 전 FAIL·후 PASS ⓕ `.1`~`.3` 다 이어도 못 덮으면 raise(파일 3개·첫 ts 전부 · `.4` 는 안 읽음) ⓖ 중간 벌(`.2`) 빠짐 → `.3` 이 덮어도 건너뛰지 않고 멈춤 ⓗ 기존 시험 파일은 칸 추가만(삭제 0).
- 증거 `harness/evidence/r553/`: `01-before-red.txt`(고치기 전 ⓐ·ⓑ·ⓔ·ⓕ 4 FAIL) · `02-after-pass.txt` · `03-kit-sh-test.txt` · `04-base-diff.txt`.
- 설치: 있음 — 루트 `.fable-team/comm/{mbox_conf,mbox_guard}.py` cmp0 2 · LIVE_BIN `ft-mbox.py` cmp0 1 · `~/.hermes/scripts/magazine_collect_mbox.py` cmp0 1 → `harness/install.sh --apply --project <루트>` + `kit/slack-mirror/install-magazine.sh`. **설치 집행은 master 소관 — 미실행.** 데몬 재기동 0(매거진은 launchd 가 매일 새로 부름). 되돌림 = env `FT_MBOX_LOG_KEEP=1`(옛 동작) 또는 `.bak-<버전>`.
- 범위 밖: 한도 5MB 변경 · `.1` 만 읽는 다른 5곳(`_received_seqs`·`ft_board_mail.py`·`ft-measure-net.sh`·`ft-nano-never-started-check.sh`·`ft_da_hold_gate.py` — 그들은 «최근 2벌» 로 충분한 짧은 창 · 이 카드는 «더 오래된 벌이 지워지지 않고 남음» 만 바꾼다) · 날짜별 보관 · `bodies/` TTL · 매거진 창 길이 · 이미 지워진 10-19 08:00~18:04 기록 복구(불가).

## 2026-10-20 — 공용 라이브 뿌리 `feat/v6-realtime-live` = «병합하지 않는 줄기»: 뒤처짐 알림·병합 처방이 그 폴더를 더 이상 가리키지 않는다 (r549 · 1.1.104 · 데이터 1줄)

- 사건: main 이 움직일 때마다 planner 앞으로 «`v6-realtime-live`(feat/v6-realtime-live) 가 main 보다 284커밋 뒤 — 받아 오라» 는 알림과 «`ft-head-sync --apply`» 처방이 반복해서 갔다(v65 알림 120284 · master 85 발주 120290). 그 폴더는 여러 팀이 같이 쓰는 라이브 작업 뿌리라 남의 staged·수정이 1500줄 넘게 있고, main 으로 병합하지 않기로 한 줄기다(메모리 10-18 «merge 처방 금지»). 처방을 그대로 따르면 전 팀 라이브가 흔들린다.
- 원인: 하네스에는 이미 «병합하지 않는 줄기» 목록(`ft-head-skip.txt`)이 있고 `ft_head_lag.py`(알림)와 `ft-head-sync.sh`(병합 표)가 둘 다 그 파일 하나를 읽는데, 그 브랜치 줄만 빠져 있었다. 그래서 두 도구가 같은 폴더를 계속 대상으로 잡았다.
- 고침(데이터 1줄 + 주석 1줄 · 코드 0 · 새 도구 0): 정본 키트 `kit/fable-team/bin/ft-head-skip.txt` 와 정본 bin 짝 `harness/bin/ft-head-skip.txt` 의 «문서·운영 줄기» 묶음 끝에 `feat/v6-realtime-live` 1줄 + 사유 주석 1줄. 정규식 앵커(`^(…)$`) 그대로 — 다른 기능 브랜치의 뒤처짐 알림은 안 넓어진다.
- 시험 `tests/test_head_skip_list.sh`(기존 · 새 시험 파일 0)에 칸 3개 추가 — ⓕ 임시 리포에 `feat/v6-realtime-live` 워크트리를 main 뒤로 두면 `ft_head_lag --event` 알림 0 ⓖ 같은 폴더가 `ft-head-sync` 표에도 안 나옴(같은 파일 1줄이 두 도구를 같이 멈춘다) ⓗ 대조 — 다른 기능 브랜치(`nano/r549fn`)는 그대로 알림 1 · 표 1(제외가 넓어지지 않음). 전부 임시 리포·임시 tmux 서버 픽스처(실 리포·실 좌석 0).
- 전 FAIL → 후 PASS: 고치기 전 3건 FAIL(`evidence/r549/before-fix.txt` — ⓕ · ⓖ · 정적 키트 사본 일치) → 고친 뒤 ALL PASS 21(`evidence/r549/after-fix.txt`). 기존 `tests/test_head_lag.sh` · `tests/test_head_sync.sh` 도 ALL PASS(rc0 · 무변경).
- 설치: 키트 1(`ft-head-skip.txt`) → `install.sh --apply --project <루트>` → 라이브 사본 cmp0 1 · 데몬 0(두 도구가 부를 때마다 새로 읽음) · 되돌림 = 그 줄 지움(또는 env `FT_HEAD_SYNC_SKIP`).
- 병합: 팩 main f3710109(r551 · 1.1.102) 위에 쌓고, 이어 r550 가지(b2225587 · 1.1.103)를 병합 — 충돌은 CHANGES·manifest 뿐(기계 해소) · 번호는 r551=1.1.102 · r550=1.1.103 이 이미 쓰고 있어 **1.1.104** · 앞 두 항목 보존.
- 범위 밖: `v6-realtime-live` 를 main 에 맞추기 · «미커밋≠0 이면 알림 대신 기록» 같은 새 판정 · 다른 공용 뿌리 찾기(지금 LIVE_ROOT 는 이것 하나).

## 2026-10-20 — 죽은 복사 설치기 `ft-live-install.sh` 은퇴 + 옛 설치 레이아웃 시험 2개의 글자·픽스처 자리 고침 (r550 · 1.1.103)

- 사건: 나노가 일을 끝낼 때마다 돌리는 기존 시험이 두 개(나중에 셋) 늘 FAIL 이라 «원래 실패하던 것» 으로 넘어갔다(r457 · r491 · r544 세 번 · master 85 발주 120311 · 판정 1395). 실측하니 셋 다 **10-18 리포 분리(r385) 전 모양**이 시험에 남은 것이다.
- 원인 ①(도구 은퇴): `ft-live-install.sh`(R215 · 키트 ref → `<x>/.fable-team/bin` 에 «파일 복사» 설치)를 `tests/test_live_install.sh` 가 시험하는데, r385 뒤 설치는 `install.sh --apply --project <루트>`(루트 shim + 판 폴더 LIVE_BIN)로 바뀌었고 `kit/fable-team/bin/ft-live-bin-drift-check.sh:28-40` 이 «옛 설치 사본(shim 아님 · LIVE_BIN 없음)» 을 일부러 거절(rc3) → 이 설치기는 지금 어떤 설치에도 못 쓴다 = **죽은 도구**. 부르는 곳 0 실측(`git grep ft-live-install.sh` = 자기 시험·LIVE-MAP 주석뿐 · 홈 `~/.claude/skills`·`rules`·`CLAUDE.md` 언급 0).
- 원인 ②(시험 글자): `tests/test_live_install_check.sh` ⑥ 1 FAIL = 린트(`kit/fable-team/bin/ft-index-lint-install.sh:17`)가 보는 키트 경로 글자가 `harness/kit/`·`harness/bin/` 로 바뀌었는데 시험 카드 글은 옛 `scripts/harness-install/`.
- 원인 ③(같은 꼴 세 번째 · r546 나노 실측 · 발주 120421): `tests/test_tracked_bin_call_gate.sh` FAIL 25(r546 이전부터) = 픽스처가 추적 사본을 옛 자리 `scripts/fable-team-bin/` 에 놓는데 `harness/bin/ft-live-entry.sh` 의 넘김 조건은 `*/harness/bin|*/harness/kit/fable-team/bin`(r385 뒤) → 옛 자리 사본은 LIVE_BIN 으로 안 넘어가고 제자리 실행(«unknown two w» · «usage: role 은 …») = ⓖ 22 FAIL · r2 3 은 같은 자리에 `ft-team-lib.sh` 가 없어 «WARN ft-team-lib.sh 없음». 홈 훅 ⓕ(deny)는 옛·새 자리 둘 다 받아 PASS.
- 고침 ①: `git rm` 3 — `harness/bin/ft-live-install.sh` · `harness/kit/fable-team/bin/ft-live-install.sh`(같은 판 · cmp0) · `harness/tests/test_live_install.sh`. `kit/LIVE-MAP.tsv:15` 주석의 `ft-live-install.sh` → `install.sh --apply --project <루트>`. 옛 staged 설계 문서는 기록이라 그대로.
- 고침 ②: `tests/test_live_install_check.sh` l4 카드 글 → `harness/kit/hooks/x.sh`(⑥ REJECT 단언 유지) + `l4b` 칸 추가 — 옛 경로 `scripts/harness-install/hooks/x.sh` 만 = 키트 아님 → 통과(r385 뒤 린트 동작을 시험으로 고정). PASS 50 → 52.
- 고침 ③: `tests/test_tracked_bin_call_gate.sh` 픽스처 추적 사본 자리 `scripts/fable-team-bin/` → `harness/bin/` + 그 자리에 형제 파일 `ft-team-lib.sh`·`ft-harness-root.sh` 복사(도구가 읽는 형제). ⓕ 칸에 새 자리 deny 사례 2 추가(`bash /w/harness/bin/ft-nano-spawn.sh --help` · `cd /y && bash harness/bin/ft-role-spawn.sh da`) · 옛 자리 deny 사례는 훅이 아직 받으므로 그대로 둠. 도구·훅 코드 변경 0. FAIL 25 → 0 · PASS 47 → 75.
- 시험: `test_tracked_bin_call_gate.sh` rc0 ALL PASS 75 · `test_live_install_check.sh` rc0 ALL PASS 52 · `test_live_install.sh` 은퇴(파일 0). 기존 시험 묶음 12(base 대조 = `evidence/r550/05-base-compare.txt` · 고친 판 = `06-after-compare.txt`) 전부 rc0 — base 에서 rc1 이던 셋만 0 이 됐고 나머지는 rc·PASS 수 그대로.
- 증거 `harness/evidence/r550/`: `01-before-test_live_install.txt`(6 FAIL · «ERROR 옛 설치 사본(shim 아님 · LIVE_BIN 없음)» 원문) · `00-before-test_live_install_check.txt`(⑥ 1 FAIL) · `02-before-test_tracked_bin_call_gate.txt`(PASS 47 FAIL 25) · `03/04-after-*` · `07-d-grep.txt`(은퇴 뒤 `git grep ft-live-install.sh` = 0).
- 설치: 있음 — 키트 bin 에서 1 파일 빠짐 → `install.sh --apply --project <루트>` → 새 판 LIVE_BIN 에 `ft-live-install.sh` 없음 · 옛 판 폴더는 그대로(되돌림) · 루트 shim 은 남아 rc3 «라이브 도구 없음» 으로 멈춤(조용한 통과 0). **설치 집행은 master 소관 — 미실행.**
- 되돌림 = `git revert` 1~2커밋(지우는 것은 git 추적 파일뿐 · 브랜치 삭제 0). 범위 밖: 루트 `.fable-team/bin/ft-live-install.sh` shim 지우기(설치기 shim 정리 몫 · 지금은 rc3 오류로 멈춤) · 옛 staged 문서 고치기 · 다른 «사전 실패» 찾기(나오면 그때 카드).
## 2026-10-20 — 주간 점검표 planner 칸 P1·P2 의 «읽는 출처» = origin/main gitref (r551 · 1.1.102 · r545 꼴 · 쓰는 자리 그대로)

- 사건(r544 착지 뒤 첫 실행 · master 85 kickstart 16:39 · 쪽지 120375 · arch 109 실측 2026-10-20 16:4x): 주간 점검표의 planner 두 칸(결정 대기열·원장↔발주 대조)이 planner 좌석이 앉은 공용 체크아웃(`.worktrees/v6-realtime-live` · main 보다 **290커밋 뒤**)의 **디스크 폴더**를 읽었다. 그 체크아웃에는 새 자리 `design/teams/planner/` 가 없고 옛 자리 `design/planner/`(원장 마지막 커밋 10-19 18:55)만 있어, 점검표가 **어제 저녁 판**으로 채워지고 «문제 없음» 을 보일 수 있었다 — 10-19 뉴스 22시간 정지·r545 골 표와 같은 뿌리(세 번째).
- 고침(키트 1 + 정본 bin 짝): `ft_weekly_review.py` 의 `p1_queue`·`p2_ledger` 가 파일을 `git -C <planner 리포> show <ref>:<planner 폴더>/<파일>` 로 읽고, 대기열 파일 목록은 `git ls-tree --name-only <commit> <폴더>/`. 폴더는 r545 `ft_goal_ledger.planner_rel_in_ref` **재사용**(ref 트리에 있는 후보 정확히 1개 · 디스크 실재 여부 안 봄) · ref = env `FT_TEAMS_REF`(기본 `origin/main`) · ref 는 `rev-parse --verify` 로 1회 commit 확정.
- 칸 값 끝에 **` · origin/main@<sha10>`** — 점검표가 «어느 판에서 읽었나» 를 스스로 말한다. ref 에 폴더·파일이 없으면 예외 → 기존 `safe()` 가 «확인 못 함» 으로 칸에 남긴다(체크아웃으로 조용히 내려가기 0).
- 시험 `tests/scripts/test_ft_weekly_review.py` ⓐ~ⓔ: 픽스처에 «뒤처진 체크아웃 + 앞선 origin/main» 2판을 넣었다(옛 꼴 `design/planner` = 문제 0 · ref `design/teams/planner` = 문제 1). 새 코드 전 **6 failed · 11 passed**(red-first · `harness/evidence/r551/before-red-base-code.txt`) → 뒤 **17 passed**(`after-pass-mine.txt`). 기존 시험 13건은 단언 그대로 통과 · 짝 셸 시험 `tests/test_team_literal_paths.sh` `fail=0`(120 PASS).
- 실측(읽기 전용 · 쪽지 0 · 쓰기 0 · `harness/evidence/r551/real-behind-checkout-readonly.txt`): 고치기 전 P1/P2 = 출처 표기 없는 체크아웃 판 → 고친 뒤 `… · origin/main@b7366fecfc`. 원장 두 판 실제 차이 = origin/main 333줄(10-20 15:59) vs 체크아웃 310줄(10-19 18:55) · diff 64줄.
- 범위 밖(그대로): 점검표를 쓰는 자리(planner 좌석 체크아웃 · 설계대로) · `v6-realtime-live` 에 생긴 untracked 점검표 파일(planner 팀 몫) · planner 좌석이 뒤처진 공용 체크아웃에 앉는 문제(planner·ops 몫) · H1~H8 칸 · 쪽지 규칙.
- 설치: 키트 1(`kit/fable-team/bin/ft_weekly_review.py` · `harness/bin` 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 데몬 0(launchd 가 매주 새로 부름) · 되돌림 = `.bak-r551`. press 0(점검 도구 — 제품 키·말풍선·음성 경로 무관).

## 2026-10-20 — 실행 전 Bash 훅 4 의 «명령 조각내기·env argv 분해» 사본을 공용 모듈 1 로 (r546 · 1.1.101 · 구조 커밋 · 동작 변경 0)

- 사건(r532 점검표 `design/harness/AUDIT-hooks-devices-20261020.md:26` · arch 109 실측 2026-10-20 16:0x): Bash 한 번에 훅 16개가 먼저 도는데, 그중 4개가 «명령을 `;`·`|`·`&&` 로 쪼개 보는» 함수를 **각자 사본으로** 들고 있었다 — `op-vault-develop-gate.sh:38-57` ↔ `tracked-bin-call-gate.sh:28-48` `segments(cmd)` = 본문 diff 0(독스트링 1줄만) · `autonomy-merge-guard.sh:108-121` ↔ `autonomy-state-guard.sh:118-131` `env_split` md5 같음 · 이미 있는 공용 `merge_cmd.py:42-55` 와도 독스트링 1줄 차이. 한 곳을 고치면 나머지 사본은 옛 판으로 남는다.
- 고침(구조만): ① `kit/hooks/merge_cmd.py` 에 `segments(cmd)` 추가 — 본문 = `op-vault-develop-gate.sh:38-57` **글자 그대로**(글자 변경 0). ② 훅 4 의 사본 함수 삭제 + import(`sys.path.insert(0, <훅 폴더>)` → `from merge_cmd import segments` / `env_split` — `merge-head-gate.sh:15` 꼴). 사본 4 → 0, 모듈 1.
- ★막는 기준은 하나도 안 바꿨다★: 4훅 × 30명령(따옴표·`$(`·백틱·`;&|`·줄바꿈·`env -S` 섞음) × 자율 off/on = **240판정**(rc·종류·stderr 첫 줄)이 바꾸기 전 판과 **바이트 동일**(`harness/tests/fixtures/r546_hook_cmd_split/base_verdicts.tsv` · ⓑ). `merge_cmd.segments` 는 옛 사본과 30/30, `merge_cmd.env_split` 는 옛 사본 2와 90/90 출력 동일(ⓒⓓ).
- 모듈 없음 = **막음**(조용히 통과 0 · 0번 규칙 no silent fallback): 훅 4 는 같은 폴더에 `merge_cmd.py` 가 없으면 stderr `REJECT … merge_cmd 없음 …` + **rc2**(ⓔ). autonomy 2 는 종전 마지막 줄 `exit 0` 이 파이썬 종료코드를 삼켰으므로 `exit $?` 로 바꿔 rc2 가 전달되게 했다.
- 시험 `tests/test_hook_cmd_split_shared_r546.sh`(새 · 임시 HOME·임시 루트·«설치 꼴» 임시 훅 폴더 · 외부 호출 0 · 실 settings·실 상태 쓰기 0) ⓐ~ⓕ **ALL PASS 19**(61초). 기록기 = `tests/lib/r546_verdicts.py`(픽스처 = 진짜 git 리포 + `byz-agents` origin + `.claude/skills/byz-keys` · 자율 모드 = 임시 스텁). 변이 2종(모듈 숨김 · `segments` 구분자 1개 제거)에서 ⓑⓒ 가 실제로 빨개지는 것 확인.
- 기존 시험 5종 base 대조: `test_op_vault_develop_gate` 48 PASS · `test_autonomy_hooks` ALL PASS · `test_autonomy_merge_equiv` ALL PASS · `test_merge_head_gate` ALL PASS · `test_tracked_bin_call_gate` **FAIL 25 = base 와 같은 값**(ⓖ live-entry 계열 · r546 이전부터 빨강 · 이 카드와 무관). 키트 templates 폴더에는 `merge_cmd.py` 가 없어(홈 설치 뒤엔 한 폴더) autonomy 시험 5종이 «설치 꼴 임시 폴더 복사» 2줄을 쓰도록 고쳤다 — 단언·PASS/FAIL 줄은 그대로.
- 범위 밖(2단계 r547 몫): 규칙이 다른 조각내기 3벌(`press-runner`·`block-destructive-judge`·`context-distill-gate`) · `gh-issue-author-guard` 의 `segments(text)` · 훅 진입점 1개(프로세스 16 → 1 · 기준값 실측 먼저) · 키트 훅 폴더 둘 합치기 · `merge_cmd.py` 의 `simple_commands`/`resolve` 와 autonomy 사본의 차이(동작 동일하나 글자가 달라 이 카드 경계 밖).
- 설치: 키트 5(`kit/hooks/{op-vault-develop-gate.sh,tracked-bin-call-gate.sh,merge_cmd.py}` · `kit/fable-team/templates/hooks/{autonomy-merge-guard.sh,autonomy-state-guard.sh}`) → `install.sh --apply --project <루트>` → 홈 `~/.claude/hooks/` cmp0 5 · 데몬 0(훅은 매번 새로 읽음) · settings 변경 0 · 되돌림 = `.bak-r546`.

## 2026-10-20 — 고장 데몬 3개: 렌더가 템플릿의 `WorkingDirectory` 도 옮기고 · 설치 검사가 «실행 경로 스크립트 없음» 을 DRIFT 로 (r544 · 1.1.99)

- 사건(r532 점검표 · arch 108 실측 2026-10-20 15:0x): launchd 주기 작업 셋이 매번 실패 — ① `com.byz.gce-guard-check` 종료 78 = **지운 워크트리**(`.worktrees/ops-guard`)의 스크립트를 실행 ② `com.byz.ft-secret-scan` 종료 3 · `com.byz.ft-weekly-review` 종료 1 = 설치본에 `WorkingDirectory` 가 없어 launchd cwd=`/` → 로그 `ERROR 리포 공용 루트를 못 풂`.
- 원인(실측): 키트 템플릿은 `kit/fable-team/com.byz.ft-secret-scan.plist.template:20` 처럼 `<key>WorkingDirectory</key><string>__BYZ_ROOT__</string>` 를 갖고 있는데, r538 렌더(`ft_plist_env.py render-bin`)는 ① `bin-list` 가 `__FT_BIN__` 템플릿만 골라 이 두 라벨이 **렌더 목록에도 안 들어갔고** ② 설치 plist 를 줬을 때 `sync_args` 가 **ProgramArguments 만** 옮겨 `WorkingDirectory` 를 두었다. 설치 검사(`ft_live_install_check.py`)는 판 고정(`pinned`)만 보고 **«실행 경로 파일이 실재하는가»** 를 안 봤다.
- `ft_plist_env.py`(키트 + `harness/bin` 짝 cmp0): ① `bin-list` = **루트 bin 을 부르는 템플릿 전부** — `__FT_BIN__` 템플릿 7 + `__BYZ_ROOT__/.fable-team/bin/` 실행 경로 템플릿 2(secret-scan·weekly-review) = **9**. `__HOME__`·`__REPO__` 를 쓰는 magazine 류는 실행 경로가 루트 bin 이 아니라 제외(렌더하면 자리표시 잔재 ERROR). ② `sync_args` = 옮기는 키가 `ProgramArguments` + **템플릿에 있는 `WorkingDirectory`** 로 늘었다 — 템플릿에 그 키가 없으면 설치본 값을 **지어내지 않고 그대로** 둔다(머신별 env·주기·로그 경로·손 값 보존 그대로).
- `ft_live_install_check.py`: `missing_script_drift(pdir)` — `~/Library/LaunchAgents/com.byz.*.plist` 의 ProgramArguments 실행 경로(`.sh`/`.py`)가 없는 파일이면 `DRIFT launchd <라벨> missing=<경로>` + `HINT launchd-missing …`(PENDING rc1). 키트 템플릿이 없는 plist(gce-guard 꼴)도 «실재» 만 본다 — 렌더·고치기 0 · 읽기만 · 외부 호출 0.
- 시험 `tests/test_plist_workdir_exist_r544.sh`(새 · 임시 HOME·루트·키트 리포·가짜 launchctl · 실 launchd 0) ⓐ~ⓖ **ALL PASS 18** — 고치기 전 **FAIL 4**(ⓐ 사건본 → 렌더본에 WorkingDirectory 없음 · ⓑ 멱등 · ⓓ bin-list 7 · ⓔ 지운 경로 DRIFT 0 · `harness/evidence/r544/before-test_plist_workdir_exist_r544.txt`) → 고친 뒤 `after-test_plist_workdir_exist_r544.txt`.
- 기존 시험: install·install-check 계열 11 중 rc0 9 · rc1 2(`test_live_install` 6 FAIL · `test_live_install_check` ⑥ 1 FAIL)는 **base 와 같은 기존 FAIL**(`harness/evidence/r538/base-origin-main-preexisting.txt` · `evidence/r544/after-two-preexisting-fails.txt`). `test_install_launchd_render.sh` 는 ⓐ bin-list 개수 기대 **7 → 9** 한 줄만 고쳤다(이 카드가 목록을 늘린 사실 반영 · 나머지 22 PASS 그대로).
- 실측(읽기만 · press 0): 실제 루트 `--dry-run` = `LAUNCHD rendered=7 changed=2`(r538 때 rendered=5 — secret-scan·weekly-review 가 이제 목록에 들어온다) · 설치본↔렌더본 차이 = **`WorkingDirectory` 추가 1 + weekly-review 실행 경로가 워크트리 심(`.worktrees/v6-realtime-live/.fable-team/bin/…`) → 루트 심**(`evidence/r544/real-diff-installed-vs-render.txt`). gce-guard 는 이 카드 전에 **이미 루트 정본(`<루트>/scripts/ops/gce-guard-check.sh`)으로 고쳐져 있었다**(ops 손 단계 선행 · `launchctl list` 종료 91 = 15:29 실행 `FAIL=0 BLIND=1` 의 종료값).
- 설치: 키트 2(`ft_plist_env.py` · `ft_live_install_check.py`) → `install.sh --apply --project <루트>` = LIVE_BIN cmp0 2 + plist 2 재렌더·재적재(LAUNCHD 줄) → 시각 03:17 이후 `/tmp/ft-secret-scan.log` 에 «리포 공용 루트 못 풂» 0 · 종료 0. 되돌림 = 키트 2 `.bak-r544` + 각 plist `.bak-<version>`.
- 범위 밖: 훅 합치기·조각내기 · 키트 밖 plist(gce-guard 내용·launchd env) · `ft-tick` KakaoBot 옛 사본 · planner-decisions·board-publish 실패(원인 미확인) · 새 도구·새 훅 0.

## 2026-10-20 — 골 표 도구 기본 출처 = `gitref:origin/main`: 공용 체크아웃이 main 에 뒤처져도 planner 앞 발신이 안 막힌다 (r545 · 1.1.98)

- 사건: 모든 팀이 planner 에 쪽지를 보낼 때 붙는 «오빠 골 표» 가 ERROR 로 비었고, 그 탓에 planner 앞 발신 게이트가 전 팀에서 REJECT(1.1.92~95 전부 · 설치 무관 · harness master 85 발주 120203). master 가 공용 체크아웃(`LIVE_ROOT` = `.worktrees/v6-realtime-live`)의 `design/teams/planner/` 에 origin/main 파일 2개를 임시 복사(untracked)해 막아 둔 상태였다.
- 원인(arch 108 실측): 도구가 골 정본·원장을 «공용 체크아웃의 디스크 파일» 에서 읽었고(`ft_goal_table._spec` → `planner_dir` · `ft_goal_ledger.ledger_spec`), 그 체크아웃은 main 보다 281커밋 뒤처져 planner 폴더가 옛 자리(`design/planner/`)에만 있었다. 폴더도 «디스크에 실재하는 후보» 로 골랐다(`team_in_ref`). 임시 복사본은 planner 가 원장을 고칠 때마다 옛 값을 새 값처럼 보여준다 — 10-19 «뉴스 22시간 정지» 와 같은 뿌리.
- 고침(키트 2 + 정본 bin 짝): ①`ft_goal_ledger.py` — `planner_rel_in_ref()`(명단 = `ref:design/TEAMS.md` · 후보 = 명단 꼴 + 쌍둥이 · **ref 트리에 있는 후보 정확히 1개** · `git cat-file -e` 로 확인 · 디스크 실재 여부는 안 본다) · `default_spec()` = `gitref:<FT_TEAMS_REF·origin/main>:<planner 폴더>/<파일>` · `ledger_spec` 기본값이 이걸 쓴다 · `read_spec` 은 «그 ref 에 경로가 없으면 None»(원장 없음 = «상태 없음» WARN 경로 그대로 — git 자체 실패는 예외 그대로 = fail-closed). ②`ft_goal_table.py` — `_spec` 기본 = 같은 `default_spec` · `_repo()` = `FT_GOAL_REPO` › 원장 리포(`FT_LEDGER_REPO`·LIVE_ROOT, r545: planner 파일이 사는 리포. 데이터 루트는 git 이 아닐 수 있다) · 머리 = `★골 표 A6 (<출처><sha10> · …)★`, 출처 = `origin/main@`(commit sha) | `file:`(내용 sha256) · `HEAD` 정규식이 출처 표지 붙은 새 꼴과 옛 꼴을 둘 다 받는다(읽기 하위 호환 — 이미 나간 쪽지가 REJECT 되지 않게). ③같은 마커를 읽는 `ft_goal_gate.py`·`ft_news_ledger_text.py` 의 sha10 정규식에 같은 선택 표지(출처가 바뀌어도 게이트·뉴스 묶음 표지가 계속 sha10 을 뽑는다).
- 시험 `tests/test_goal_table_gitref_r545.sh`(새 · 임시 git 리포 1 + 그 리포의 뒤처진 worktree 픽스처 · 실 리포·실 원장·외부 호출 0) ⓐ~ⓖ: ⓐ origin/main 에만 planner 파일이 있고 체크아웃엔 없음 → render rc0 · 표 = origin/main 판 ⓑ 머리 = `origin/main@<sha10>` ⓒ 체크아웃에 낡은 복사본(untracked · master 임시 조치 그 꼴)이 있어도 origin/main 판 ⓓ origin/main 에 정본 없음 → ERROR rc1(체크아웃 파일로 조용히 내려가지 않음) ⓔ env 파일 경로 2개 = 그 파일 · 머리 `file:<sha10>` ⓕ 원장 24h 초과 = «상태 낡음»(gitref 에서도 같은 규칙) ⓖ 읽기 하위 호환(옛 꼴 마커 check rc0 · 게이트·뉴스 정규식이 새 머리에서 sha10). 고치기 전 FAIL 6(`harness/evidence/r545/before-test_goal_table_gitref_r545.txt`) → 고친 뒤 ALL PASS 12.
- 기존 시험 4개의 단언·픽스처를 새 계약(출처 = ref · 머리 출처 표지)에 맞춰 고쳤다 — `test_goal_table_gate.sh`(머리 단언 `file:` · ⓝ1/ⓣ 픽스처를 origin/main 에 커밋 · ⓝ1 은 «ref = NEW · 디스크 = OLD» 로 바꿔 새 계약을 직접 잰다) · `test_goal_check_ref.sh`(ⓔ3 쌍둥이는 디스크가 아니라 ref 가 정한다 · ⓔ4 체크아웃에 폴더가 없어도 rc0 · ⓔ3b/ⓔ4b ref 에 2개/0개 = ERROR) · `test_team_literal_paths.sh`(머리 sha10 정규화 — 픽스처 트리가 달라 commit sha 가 다른 것은 정상) · `scripts/test_ft_news_goal_block.py`(묶음 표지 헬퍼가 sha10 만 뽑는다). 4분면 대조 = `harness/evidence/r545/base-compare-matrix.txt`(base+base 0 · base+새시험 빨강 · 새코드+옛시험 빨강 · 새코드+새시험 0).
- 범위 밖: 공용 체크아웃(v6-realtime-live)을 main 에 맞추기(다른 팀 작업 폴더 · 병합 금지) · 원장 쓰기 경로 · origin fetch 자동화(읽는 쪽은 로컬 origin/main · 낡으면 머리 commit 으로 보인다) · 뉴스 자체 출처(`FT_LEDGER_PATH`) — 같은 파일이라 자동 반영 · `ft_weekly_review.py` 의 `team_in` 직접 호출(체크아웃 폴더 · 별 카드) · shell `ft-team-lib.sh` 무변경.
- 설치: 키트 4(`ft_goal_table.py` · `ft_goal_ledger.py` · `ft_goal_gate.py` · `ft_news_ledger_text.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 4 · 데몬 0(부르는 쪽이 매번 새로 읽음) · 홈 0 · 되돌림 = `.bak-r545`.
## 2026-10-20 — 임시 사본 정리가 «돌고 있는 시험 장비의 작업 폴더» 를 지우던 것 고침: cwd 사본은 붙잡고 lsof 실패면 삭제 0 · 등록 사본 24시간 문턱 복구 (r548 · 1.1.100)

- 사건: 10-20 하루 1회 정리(`ft-scratch-repo.sh --sweep`)가 등록 사본 `repo-c154bdd0`(주인 = 닫힌 v65 tester 74)을 지웠는데 그 폴더를 cwd 로 서버 세트(worker 8081 · caddy 8443)가 7시간 넘게 돌고 있었다(planner 83 알림 120245 · master 85 발주 120247 · 카드 r548).
- 뿌리(arch 109 실측): ①등록 사본은 tmux 목록에 주인이 없으면 «즉시» 후보 — cwd 를 묻지 않는다 ②cwd 검사는 TMPDIR `tmp.*` 에만 있었고 ③그 검사도 `lsof` 종료코드를 안 봐서 실패하면 «cwd 0개» 로 읽어 전부 지웠다(조용한 통과) ④`grep -q "^$d"` = 앞부분 글자 비교(`tmp.ab` 가 `tmp.abc` 를 붙잡음 · 폴더 경계 0).
- 고침 `kit/fable-team/bin/ft-scratch-repo.sh` `orphans()` (짝 `harness/bin` cmp0): ①`lsof -w -d cwd -Fpcn` **1회**를 등록 사본·tmp 둘 다에 쓴다(`cwd_holder()` · 폴더 또는 `<폴더>/` 로 시작 = 경계 비교 ⓔ) ②cwd 로 쓰이는 사본은 `add` 대신 `HOLD` (경로·pid·명령·주인) — 지우지 않고 붙잡는다 ③lsof rc≠0 또는 0줄 → 이번 정리 전체 생략 + 로그·stdout `ERROR lsof 실패 — 삭제 0` 1줄(등록 사본·tmp.* 포함) ④`--sweep` stdout `[장비 정리] 주인 <좌석> 사본 <경로> 에서 pid <n> <명령> 실행 중 — 삭제 보류` 최대 3줄 + `…외 N건` · 로그 `붙잡음 …` 줄 · 요약 줄에 `held=N` · `--report` 는 같은 사본을 «붙잡음 pid …» 칸으로 보인다.
- ★등록 사본 24시간 문턱 복구(판정 1920 문구 · r444 문턱 0 되돌림 · 보강 120262)★: 후보 = 주인 세션 없음 ∧ `now − 등록표 3열 ≥ FT_SCRATCH_AGE_MIN(기본 1440분)*60`(tmp 와 같은 값) · 3열이 숫자가 아니면 그 행 삭제 0 + stderr `ERROR 등록표 3열이 숫자 아님 — 삭제 0 (경로 … · 3열 '…')`. 머리 주석 `:10` 도 고침.
- 시험 `tests/test_scratch_sweep_live_cwd_r548.sh`(새 · 임시 저장소·가짜 tmux·가짜 lsof(PATH)·임시 TMPDIR · 실제 삭제는 임시 폴더 안에서만) ⓐ~ⓗ — 고치기 전 FAIL 14(`harness/evidence/r548/before-test_scratch_sweep_live_cwd_r548.txt` · `FT_SUT=<origin/main 판>` 대조) → 고친 뒤 ALL PASS 18(`after-…txt`). ⓕ 첫 --sweep 목록 보고 유지 · ⓐ cwd 사본 삭제 0 · ⓑ 로그/stdout 원문 · ⓒ cwd 아닌 사본·살아 있는 주인은 그대로 · ⓓ lsof rc≠0·0줄 = 삭제 0 + ERROR · ⓔ `tmp.ab` 만 삭제(폴더 경계) · ⓗ 1시간=삭제 0 / 25시간=삭제 / env 60분 / 3열 모름 = 삭제 0 + ERROR · ⓖ 기존 시험 2종 그대로 통과.
- ⓖ 기존 시험 변경 = «r444 즉시» 검사 **1줄**뿐: `tests/test_scratch_repo.sh` ⓞ 픽스처 `age_reg "$Y" 60` → `90000` · 이름 «즉시 후보(r444)» → «등록 25시간 → 후보(판정 1920 · r548 이 r444 문턱 0 을 되돌림)». 그 외 줄 diff 0 · 기존 두 시험의 PASS/FAIL 줄은 «고치기 전 판 / 고친 판» 두 번 다 동일(diff 0 · `harness/evidence/r548/g-changed-lines.txt`).
- 읽기 전용 실측: 실제 등록표에 새 판 `--report` = 후보 2개(tmp.*)·등록 사본 후보 0(주인 살아 있음) · 요약 `주인 없는 임시 사본 2개 0.00 GiB` · lsof rc=0(40 tmux 세션) — 삭제 0(`harness/evidence/r548/real-report-readonly.txt`).
- 설치: 키트 1(`ft-scratch-repo.sh` · 짝 bin cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · 데몬 0(ft-disk-alarm 이 매번 새로 부름) · 되돌림 = `.bak-r548`.
- 범위 밖: 이미 지운 `repo-c154bdd0` 되살리기(등록 사본은 sha 로 다시 만들 수 있다 · 서버 세트 정리는 v65 팀) · 주인 팀 직접 쪽지 길(planner 가 나눔) · `ft-disk-alarm` 쪽 변경(stdout 을 그대로 planner 로 넘김).

## 2026-10-20 — 팩 시험이 «실» 하네스 상태를 못 바꾸게: 공용 가드 도우미 + 전수 적용 (r541 · 1.1.97)

- 사건: r536 나노가 `test_autonomy_hooks_layout.sh` 를 BYZ 워크트리 cwd 에서 8회 돌리자, 그 시험이 일부러 `FT_ROOT` 를 비운 채 `ft-autonomy.sh on/approve-merge/off` 를 불러 데이터 루트 풀이(`ft-harness-root.sh` `ft_data_root` ②«cwd git 공용 루트의 `.fable-team/LIVE_ROOT`»)가 «실» 라이브 루트(v6-realtime-live)로 풀려 실 자율 상태에 씀 — 실 자율 ON 약 12분(13:29:46~13:41:54) · 실 자율 사건 번호 8칸 밀림(A10→A18) · 실 `autonomy-merge-approved` 에 가짜 병합 승인 8줄(arch 108 실측 · master 84 발주 119899 · r536 보고).
- 뿌리: 루트 풀이 3종(`ft_data_root`·`ft_repo_root`·`ft_comm_dir`)이 env 가 없으면 «호출자 cwd» 로 떨어지는데, 시험이 cwd 를 git 밖 임시 폴더로 옮기지 않았다. 도구(운영 경로가 씀)는 그대로 두고 «시험 쪽»에서 막는다.
- 새 도우미 `harness/tests/lib/real_state_guard.sh`(31줄) + 파이썬 짝 `harness/tests/scripts/real_state_guard.py`(200줄): `guard_begin` = ①시험 시작 전 cwd 기준 실 루트 3종(데이터·리포·우편함) 지문(파일 크기+mtime+sha · 우편함 줄 수+끝 seq) ②`mktemp -d`(git 밖)로 cd + `GIT_CEILING_DIRECTORIES` ③같은 시험을 자식으로 재실행(`RSG_ACTIVE=1` — 시험 본문의 `trap … EXIT` 를 덮지 않는다) ④`guard_end` = 지문 비교 → 시험 rc 는 그대로, 지문이 바뀌면 1 · stderr `REAL-STATE-GUARD PASS|FAIL|WARN` 1~2줄. 실 루트를 못 풀면(픽스처만 도는 시험) 비교 생략 PASS «실 루트 없음». WARN 은 «시험 밖에서 바뀔 수 있는» state 파일(라이브 좌석이 쓰는 것) · 우편함은 «모르는 이름(from/to)이 새 줄로 들어온 경우»만 FAIL.
- 적용: 목록 `harness/evidence/r541/tests-calling-cwd-root-tools.txt`(루트 풀이 도구 53개 중 하나라도 부르는 팩 시험 151 = 셸 127 · pytest 24 · 열 = 시험·도구·env 주입·최상위 cd) — 각 시험 «맨 위 1줄» 만 추가(셸 `. lib/real_state_guard.sh && guard_begin "$@"` · pytest `from real_state_guard import guard_begin_module`), 시험 본문 변경 0. 정적 목록은 «끼울 대상»만 정하고 안전 판정은 지문 비교가 한다(정적 grep 이 사건 시험을 놓친 실측).
- 시험 `harness/tests/test_real_state_guard_r541.sh`(새) ⓐ 도우미 없이 = 흉내 실 상태 바뀜(지금 꼴 재현) · ⓑ 도우미 = git 밖 cwd + 루트 풀이 ERROR + 흉내 실 상태 그대로 PASS 줄 3루트 · ⓑ4 시험 rc 전달 · ⓑ5 팩 밖 cwd = «실 루트 없음» · ⓒ/ⓒ2 일부러 바꾸면 FAIL 원문 · ⓓ1 시험 밖 변경 = WARN+PASS · ⓓ2/ⓓ3 우편함 이름 규칙 · ⓑp/ⓒp/ⓒs 파이썬 짝 · ⓕ 전수 목록 린트(목록 시험이 `guard_begin` 0 이면 FAIL · 목록 ≠ 지금 생성 결과면 FAIL — r540 병합 뒤 새 시험 1개를 잡아냄). after-fix ALL PASS(`harness/evidence/r541/after-fix.txt`).
- ⓔ base 대조: 대표 표본 21(셸 16 · pytest 5)을 «새 임시 cwd» 에서 base(origin/main 86bd129e 사본)와 나란히 — rc·통과·실패 수 전부 같고 PASS/FAIL 줄 diff = 0(남는 차이는 임시폴더·난수 sha 값뿐). 표본 중 FAIL 2건(`test_seat_handover` rc1 FAIL2 · `test_ft_tick_master_seat` rc44 FAIL44)은 base 에서도 같은 FAIL = 가드가 만든 것 아님(`harness/evidence/r541/base-compare-sample.txt`).
- 실사건 예비 측정(나노 몫): BYZ-Agents 워크트리 cwd 에서 사건 시험 1회 → ALL PASS · 실 `autonomy.log` 486→486 · `autonomy.json` sha 동일(mode=off·A18) · `autonomy-merge-approved/` 402→402 · 가드 PASS 줄 원문(`harness/evidence/r541/byz-cwd-real-state.txt`). 정식 실사건(목록 묶음 1회)은 master.
- 병합: 팩 main 86bd129e(r540 · 1.1.92) 위로 병합 — 충돌 0(자동). 이어서 r538 가지(PR157 · r527 1.1.93 포함) 위로 쌓고, 다시 r542 가지(PR160 · r543 1.1.95 포함) 위로 쌓음 — 충돌은 매번 CHANGES·manifest 뿐(기계 해소) · 번호는 r527=1.1.93 · r538=1.1.94 · r543=1.1.95 · r542=1.1.96 이 이미 쓰고 있어 **1.1.97** · 앞 네 항목 보존.
- 설치: 없음 — 시험·증거만(키트·LIVE_BIN·홈·launchd 변경 0 · manifest 는 번호만). 되돌림 = 이 커밋 revert(다음 시험 실행부터 원래대로).
- 범위 밖: 루트 풀이 도구 3종의 cwd 폴백 자체 · 오늘 밀린 실 사건 번호 A11~A18·가짜 승인 8줄 정리(planner·master 판단) · 팩 밖 BYZ `tests/`.
## 2026-10-20 — 회수 판정기에 «에이전트별 이름 집합»: 나노 닫기가 pi 좌석도 회수(쓰고 바로 닫기) (r542 · 1.1.96)

- 사건: 하드 룰 14 «opencode 워커는 쓰고 바로 닫는다» 장치는 프로세스 이름을 opencode 로만 찾아(`ft-opencode-reap.sh` `OC = {"opencode", ".opencode", "opencode-ai"}`) pi 나노를 닫을 때 pi 회수 0 — 오빠 지시 «나노워커 pi 전환»(aifp 팀장 쪽지 119906 · harness master 84 발주 119907)의 닫기 쪽. 오빠 표준승인(desk 인터뷰 119922 · 전역 `~/.claude/CLAUDE.md:65`) = pi 정리 kill 범위 «그 좌석이 띄운 pi 프로세스 나무만 · 남의 pi 0 · 못 끄면 닫기 실패».
- `ft-opencode-reap.sh`: `--agent opencode|pi`(기본 opencode = 지금 동작 그대로 · 인자 없이도 동작) · 이름 집합 표 1개(opencode = 지금 셋 그대로 · pi = `pi` 와 node 본문 경로 `pi-coding-agent/dist`) · 판정기 1곳 재사용(새 도구 0 · 파일 이름 그대로) · pid 파일·`REAPED … left=/rc=` 끝 줄 꼴 변경 0 · 조사 줄에 `agent=<에이전트>` 1칸 추가.
- ★pi 대상 = ①좌석 pane 나무 + pid 파일 기록분만 — 기록 없이 cwd 로만 찾은 부모 잃은 pi 는 `oc-cand … via=미확인 owner=주인 미확인` 조사 줄만(신호 0 · 승인 범위 «그 좌석이 띄운 것» 밖)★ · opencode 대상 규칙 변경 0(③·new 그대로).
- `ft-nano-close.sh`: 명부 `agent ∈ {opencode, pi}` 또는 pid 파일 → 회수 단계(:348-362 · :812-817 같은 자리)에 `--agent <그 값>` · 표기만 갈림(`OC-REAPED` / `PI-REAPED` · 실패 문구도 에이전트 값) · opencode 때 넘기는 인자 0 변경(`--agent` 는 pi 일 때만 붙는다 — 기존 기대값 그대로) · `- 리서치 닫힘:` 줄 꼴 그대로.
- 홈 훅 `opencode-reap-check.sh`: 같은 훅 하나가 두 에이전트(이름 집합) — 명령이 실제 실행한 에이전트만 보고(`[<agent>-reap-check] <agent> 고아 …` · 회수 명령에 `--agent <agent>`) · kill 0 그대로 · 글자로만 든 pi(`pip`·`api` 등) 대상 아님.
- 시험 `harness/tests/test_reap_agent_pi_r542.sh`(새 · 가짜 tmux·pi 스텁·임시 상태 폴더·실 프로세스는 이 시험이 띄운 스텁만) ⓐ~ⓖ — 고치기 전 FAIL 21(`harness/evidence/r542/before-test_reap_agent_pi_r542.txt`) → 고친 뒤 ALL PASS 45(`after-test_reap_agent_pi_r542.txt`). ⓖ = 기존 opencode 회수·닫기 시험 rc0 + 시험 폴더 base 대조 diff 0.
- 설치: 키트 2(`ft-opencode-reap.sh` · `ft-nano-close.sh` — 짝 bin cmp0) + 홈 훅 1(`opencode-reap-check.sh`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · 데몬 0 · 되돌림 = `.bak-r542`.
- 범위 밖: 나노 열기 쪽(r543) · 판정기 파일 이름 바꾸기 · pi 말고 다른 에이전트 · 기록 없는 부모 잃은 pi kill(승인 범위 밖 — 필요하면 새 결정).


## 2026-10-20 — ft-nano-spawn 일반화: 티어는 «기본값 공급자» · 검색 나노 기본 에이전트 pi (r543 · 1.1.95)

- 사건: chatbot master#10 이 `ft-nano-spawn.sh <카드> --agent pi --tier search` 로 리서치 나노를 열었는데 pi 가 아니라 opencode 좌석이 열렸고(#120064) opencode 무료 경로가 이 IP 에서 «abusive traffic» 으로 막혀 처리 0 · `--never-started` 로 닫음. 오빠 지시 «ft-nano-spawn.sh 일반화 업그레이드».
- 원인(실측): 티어 `case` 가 `--agent`/`--model` 을 무시하고 에이전트·모델·effort·fast 를 통째로 덮어쓴다 — `search) AGENT="opencode"` · `checker|tester` 는 codex/cmd/claude · `impl:2|3` 은 codex/cmd. `--agent pi --tier checker:1` 도 codex 로 열렸다.
- 고침 2가지(키트 `ft-nano-spawn.sh` · 추적본 `harness/bin` 같은 글자): ①`--agent` 를 명시하면 티어가 에이전트·모델·effort·fast 를 덮어쓰지 않는다(`AGENT_SET` · 티어 이름 검사와 ROLE 은 그대로) ②`--tier search` 기본 에이전트 = `FT_SEARCH_AGENT`(기본 `pi` → 모델은 에이전트별 기본 `FT_PI_MODEL`) · `FT_SEARCH_AGENT=opencode` 로 r286 옛 경로 복귀. 검색 나노 발주 문단·머리 usage 도 에이전트 이름·`pi` 포함으로.
- 시험: `test_nano_spawn_tier.sh` 43건 ALL PASS(신규 9: search 기본 pi · env 로 opencode 복귀 · 명시 agent 가 search/checker/impl 티어를 이김 · 명시 model 우선 · 모르는 티어는 명시 agent 여도 거절) — 고치기 전 FAIL 17(`harness/evidence/r543/before-fix.txt`) · 기존 spawn 시험 37(py)+2(sh) PASS · `test_nano_spawn_body_press.sh` 는 기준판과 같은 기존 FAIL 2(ⓒ node_modules · 이 변경 무관).
- 범위 밖: pi 닫기 회수(r542) · `skill/scripts/ft-nano-spawn.sh` 사본은 추적본과 319줄 갈라진 옛 판이라 이번에 안 건드림(별 정리) · 설치(키트 1 `ft-nano-spawn.sh`)는 하네스 master 가 `install.sh --apply`.

## 2026-10-20 — 설치기가 launchd 키트 템플릿의 실행 경로를 판 없는 루트 shim 으로 렌더 · 설치 검사가 판 고정 plist 를 DRIFT 로 (r538 · 1.1.94)

- 사건: `com.byz.ft-wt-sweep` plist 가 손 sed 렌더(`harness/evidence/r444/master-steps.md:11` «s|__FT_BIN__|<LIVE_BIN>|g»)로 판 붙은 라이브 경로(`live/1.1.16/bin`)에 고정돼 키트를 올려도 sweep 이 옛 판으로 돌았다(r535 고침이 launchd 경로로 안 돎 · master 84 손 재작성 뒤에도 `live/1.1.86` 고정 · 발주 119766 ②). `install.sh` 에 `__FT_BIN__` 치환 0 · 설치 검사에 판 고정 검사 0(arch 107 실측).
- `ft_plist_env.py`: `bin-list <키트>` = `__FT_BIN__` 템플릿 7개(launchd 6 + slack-mirror board-publish · 템플릿 Label ≠ 파일 이름 = ERROR) · `render-bin <템플릿> <루트> [<설치 plist>] [--need-exist]` = `__FT_BIN__` → `<루트>/.fable-team/bin`(판 없는 루트 shim · LIVE_BIN 을 따라감) · `__BYZ_ROOT__` → 루트 · 자리표시 잔재·plist 해석 실패·git 공용 루트 아님·(apply)루트 bin 도구 없음 = ERROR rc3. 설치 plist 를 주면 ★ProgramArguments 하나만★ 렌더본 것으로 바꾼다 — 머신별 env·주기는 설치본 그대로(실측: 설치본에만 있는 `FT_STALL_PENALTY_AUTO=0` · news-planner `FT_LEDGER_REPO`·`FT_NEWS_DIR`·`FT_NEWS_MODEL`·`FT_NEWS_MODE=html` 을 템플릿 통째 교체가 지웠을 것 · `harness/evidence/r538/real-diff-installed-vs-render.txt`).
- `install.sh` `launchd_sync`(plist_sync 뒤 · shim 단계 뒤): «설치된 라벨만» 렌더 → 설치본과 바이트 대조 → 다르면 `.bak-r538`(첫 원본) + `.bak-<version>`(직전) + 교체 + `launchctl bootout`·`bootstrap`(r464 재시도·원복 재사용 · kickstart 0 — 주기 job 을 지금 돌리지 않는다) · 요약 `LAUNCHD rendered=N changed=M restarted=K` · 미설치 라벨 = `SKIP launchd`(새로 깔지 않음) · 템플릿 밖 plist 손 0 · 워크트리 `--project` = `SKIP launchd` · `--dry-run` = 비교 줄만.
- `ft_live_install_check.py` `pinned_drift`: `~/Library/LaunchAgents/com.byz.*.plist` 실행 경로에 `/fable-team/live/<판>/bin/` 이 있고 그 판 ≠ 루트 LIVE_BIN 판 → `DRIFT launchd <라벨> pinned=<판>` + `HINT launchd bash <하네스>/install.sh --apply --project <루트>`(PENDING rc1).
- 시험 `test_install_launchd_render.sh`(새 · 임시 HOME·루트·키트 리포·가짜 launchctl · 실 launchd 0) ⓐ~ⓕ — 고치기 전 FAIL 15(`harness/evidence/r538/before-test_install_launchd_render.txt`) · 고친 뒤 ALL PASS 23. ⓖ 기존 install·install-check 시험 11 중 rc0 9 · rc1 2(`test_live_install` · `test_live_install_check` ⑥)는 팩 origin/main 8d5be256 에서도 같은 FAIL(`base-origin-main-preexisting.txt` · 이 가지 diff 밖 도구).
- 실측(읽기만): 실제 루트 `--dry-run` = `LAUNCHD rendered=5 changed=5 restarted=0` · head-lag·idle-wake 는 미설치 SKIP · plist cksum 불변(`real-dry-run-byz-root.txt`).
- 설치: `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · 이 설치가 첫 렌더(5 라벨 실행 경로 → `<루트>/.fable-team/bin/…` · bootout·bootstrap 5) · 되돌림 = `<plist>.bak-r538`.
- 범위 밖: 템플릿 밖 plist(ft-leak-reap · hermes 계열 · tunnel 류) · plist 주기·env 바꾸기 · 미설치 템플릿 새로 깔기 · 키트 밖 KakaoBot plist.
- r527(1.1.93 · r540 1.1.92 포함) 위에 병합 · 1.1.94 재번호: 충돌 CHANGES·manifest 2개뿐(기계 해소) · r540·r527 이 바꾼 파일과 이 가지 파일 겹침 0(install.sh·ft_plist_env·ft_live_install_check 무변경) · 시험 재실행 = `harness/evidence/r538/merge-r527-1.1.94.txt`.

## 2026-10-20 — 좌석 턴 판정기가 쉬는 동안 자동 압축된 좌석을 WORKING 으로 읽던 것 고침: 압축 요약 user 는 턴 시작 0 (r527 · 1.1.93)

- 사건: `ft-seat-status.sh turn 'byz-graphics-arch-claude#19'` = `WORKING 2026-10-19T20:42:30.877Z` — 마지막 턴 끝 뒤 기록 39개가 붙임·제목·모드 + `system/compact_boundary` 1 + `user`(isCompactSummary=true · 21:37Z) 1 뿐인데 판정식이 «turn_duration 뒤 user/assistant 1개 = WORKING» 이라 압축 요약 1줄을 새 턴으로 셈(arch 107 실측 · master 83 쪽지 119445 공통 원인 ② · tester 0·chatbot N1 같은 꼴). 뉴스·stall-scan·회수가 같은 판정기라 그 좌석을 깨우기·닫기·정지 감시에서 건너뜀.
- `ft_seat_turn.py`: `_opens_turn(r)` = user/assistant 중 `type=="user" and isCompactSummary` 제외 · 판정 자리 3곳 전부(`_window` 상태 전용 조기 반환 · 창 안 턴 끝 0 분기 · 턴 끝 뒤 훑기)에 같은 제외(DA② HOLD 1 반영) · compact_boundary 는 system 이라 원래 0 · 턴 끝 시각·REPORTED·PENDING 규칙 그대로 · `harness/bin` 사본 cmp0.
- 시험 새 `tests/scripts/test_seat_turn_compact.py` ⓐ IDLE+턴 끝 시각 ⓑ 요약 뒤 진짜 user = WORKING ⓒ 요약 뒤 assistant = WORKING ⓓ enqueue+요약 = PENDING ⓕ 첫 창 192B 에 요약만(상태 전용 조기 반환) → 창 넓혀 IDLE · 창 안 턴 끝 0 + 요약만 = UNKNOWN(두 모드) — 고치기 전 FAIL 4(`harness/evidence/r527/before-test_seat_turn_compact.txt`) → 후 6 passed. 기존 `test_seat_turn_batch.py` 옛 판 대조 기준 = origin/main → r504 착지 직전 `855d2797`(origin/main 이 이미 r504 판이라 ⓐ·ⓔ 가 «이미 고친 판» 단언으로 FAIL 2 · 고친 뒤 6 passed). 관련 시험 rc0 = `harness/evidence/r527/after-tests.txt`.
- 설치: 키트 1 → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · launchd 0 · 홈 0 · 되돌림 = `.bak-r527`.
- 범위 밖: pane 스피너 판정 · jsonl 고르기(newest_jsonl_of) · 압축 자체 막기 · isMeta 처리.
## 2026-10-20 — pi 를 하네스 에이전트로 허용: 이름 꼬리 · 열기 도구 · 준비 확인 · 승계 시작·도달 확인 (r540 · 1.1.92)

- 사건: 오빠 지시로 aifp 팀이 pi 좌석(deepseek-v4.1-flash-ultrafast)을 넣었는데 하네스가 세 곳에서 거절 — 이름 lint 꼬리(claude codex opencode cmd) · 열기 도구 `--agent` 검사·모델 표·`--effort` 분기 · `ft-tmux-spawn.sh` 준비 확인이 claude 글자(`ctx:`)만 봐 pi 좌석을 90초 뒤 kill(aifp 쪽지 119886·119914 · harness master 84 발주 119888·119912·119915). 오빠 확정(119940·119944): 후계 `aifp-pi-master-pi` 를 `ft-successor-open.sh --agent pi` 로 열고 기동·도달 확인까지 → 도달 확인이 claude 대화 기록만 읽어 pi 분기 추가.
- aifp 패치 14파일(기준 6e72a9ab · 지금 판에 `git apply` 그대로 OK): `ft-name-lint.sh` AGENTS 에 pi · `ft-role-spawn.sh`·`ft-successor-open.sh` `--agent` 에 pi · `ft-nano-spawn.sh` 모델 표 `pi) FT_PI_MODEL:-opengateway/deepseek/deepseek-v4.1-flash-ultrafast` · 세 도구 `--effort` 분기에 pi(tmuxc 가 `--thinking` 으로 바꿈) · `ft-tmux-spawn.sh` 열기 인자 `claude|cmd|pi` + 준비 확인 pi 분기 `FT_PI_READY_REGEX` · 정본 문서 2(SPEC-session-naming §2-A · main-team-governance §1) 에이전트 목록에 pi.
- 준비 확인 식 넓힘(나노 실측): aifp 식 `<모델> • <effort>` 는 pi 가 폭이 모자랄 때 오른쪽부터 자르고(pi `footer.js:231-237`) effort 없이 뜨면 `• thinking off` 라 정상 좌석을 kill → 둘째 갈래 = 왼쪽 통계 문맥 칸 `(\?|N%)/N[kM]`(`0.0%/1.0M`) 추가. 판정표 `harness/evidence/r540/ready-regex-table.txt`(라이브 149 · 폭 80 시작·잘림·thinking off MATCH · 라이브 claude·codex 화면 오탐 0).
- 도달 확인 pi 분기(`ft-reach-check.sh` 키트·`harness/comm` 짝 같은 블록): pi 좌석(= `FT_REACH_AGENT=pi` 또는 pane 자식 본체 `pi`)이면 `~/.pi/agent/sessions/--<cwd 앞 '/' 빼고 '/'·'\'·':'→'-'>--/*.jsonl`(pi session-manager 규칙 · 실측 폴더 5개 일치 · `FT_PI_SESSIONS_DIR` 로 바꿈) 중 `session_info.name == 좌석` 파일의 `message.role==user` 마커로 판정 · 좌석 파일 못 고르면 전수로 넓히지 않고 0 + 사유 · pi 기록 뿌리 없음 = UNVERIFIABLE 5. pi 는 첫 user 입력 전엔 파일을 안 만든다(session-manager `_persist`) — 폴더·파일 없음 = «아직 0» + 사유. claude 경로 출력 base 대조 diff 0.
- `ft-successor-open.sh`: 시작 확인이 pi 면 같은 폴더의 `session_info.name` 관측(tmuxc 부팅 문장 제출 뒤 파일이 생김) · 송신·ring 재확인에 `FT_REACH_AGENT=<agent>` 전달.
- 시험 `test_pi_agent_allow_r540.sh`(새 · 가짜 tmux/tmuxc/pgrep/mbox · 임시 HOME · `fixtures/r540` 화면 글자 · 실 좌석·실 pi·외부 호출 0) — 고치기 전 FAIL 25(`harness/evidence/r540/before-test_pi_agent_allow_r540.txt`) · 고친 뒤 ALL PASS 50. 승계 열기 ⓙ 는 실 `ft-send-verified.sh`·`ft-reach-check.sh` 로 돈다(OK + 도달 파일 · ring 0 / 기록 못 읽음 rc5 + [HIL] + 도달 파일 0). claude·codex·opencode·cmd 열기 출력 base 대조 127줄 diff 0(`base-compare-diff.txt`).
- 설치: 키트 6(`ft-name-lint.sh` · `ft-role-spawn.sh` · `ft-nano-spawn.sh` · `ft-successor-open.sh` · `ft-tmux-spawn.sh` · `ft-reach-check.sh`) + 홈 문서 1(`main-team-governance.md`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · 데몬 0 · 되돌림 = `.bak-r540`.
- 범위 밖: pi 닫기 회수(r542) · 검색 나노 기본 pi(r543) · pi 좌석 틱 · `ft-agent-ready.sh` pi 맞춤 · `ft_stall_detect.py:18` 정지 스캔 claude|codex(pi 정지 감지 별 요청) · `harness/comm/ft-reach-check.sh` 옛 드리프트(queue-operation 블록 없음 · 이 카드 전부터) · skill/scripts 옛 사본 드리프트(pi 줄만 같이 넣음).

## 2026-10-20 — 좌석 재개 명령 3곳 = 헤드룸 래퍼(`claude-hr.sh`) · resume 뒤 env 확인 1줄 · 래퍼 없으면 rc1 (r524 · 1.1.91)

- 사건: desk 26 이 `zombie-clean.sh resume 'byz-concierge-master-claude#6'` 으로 좌석을 다시 열자 날 `claude --resume <uuid> --model …` 로 떠 ANTHROPIC_BASE_URL 없음(프록시 8317 미경유 · 직결) → «session limit · resets 12pm» 정지(desk 26 쪽지 119405 · harness master 83 발주 119409). tmuxc 열기·fork 는 이미 래퍼 경유 — 키트에서 날 claude 를 여는 곳은 재개 3곳뿐(arch 107 실측).
- `zombie-clean.sh`: 래퍼 경로 1곳 `ZC_CLAUDE_HR`(기본 `$HOME/.headroom/claude-hr.sh`) · resume 열기 = `<래퍼> --dangerously-skip-permissions --resume <uuid> --model '<model>'`(`--dry-run` 은 `[dry] cmd=<같은 문자열>`) · 래퍼 없음·비실행 = `❌ 헤드룸 래퍼 없음: <경로>` rc1 · 세션 생성 0(직결 대체 0) · 연 뒤 ≤7초(`ZC_HR_WAIT_S`) 그 pane 자식 중 본체(comm = claude · 래퍼 bash 단계는 세지 않음)의 `ps eww` 에서 `HEADROOM ok <좌석> pid=<n> ANTHROPIC_BASE_URL=<값>` / `WARN HEADROOM_BYPASS <좌석> pid=<n>` / `WARN HEADROOM 확인 불가(7s)` 1줄 — kill 0 · rc0(래퍼 fail-open). restore: 대장 argv 첫 낱말이 `claude`·`…/claude` 면 그 낱말만 래퍼로(래퍼 없으면 rc1) · 이미 래퍼·codex 등은 그대로.
- `ft-resume-cmd.sh` ② 슬랙 «재개» 칸 = `cd <cwd> && ~/.headroom/claude-hr.sh --resume <uuid>`(`printf %q` 인용 유지 · 사람이 복사하는 줄이라 `~` 그대로) · `harness/bin` 사본 cmp0.
- 시험 `test_zc_resume_headroom.sh`(새 · 가짜 tmux/pgrep/ps · 임시 HOME 가짜 래퍼 · 실 claude·tmux·프록시 0 · GIT_* 0) ⓐ~ⓔ — 고치기 전 FAIL 20(`harness/evidence/r524/before-test_zc_resume_headroom.txt`) · 고친 뒤 ALL PASS 36. 기존 기대값 갱신 3: `test_resume_cmd.sh`(②) · `test_dead_seat_resume.sh`(ⓐ --from-live dry · 가짜 래퍼) · `test_zombie_clean_tmux_prune.sh`(T24c · 가짜 래퍼). 기존 7 시험 rc0 = `harness/evidence/r524/after-summary.txt`.
- 설치: 키트 2 → zombie-clean = `cp -p <키트>/zombie-clean/*.sh <키트>/zombie-clean/*.py ~/.claude/skills/zombie-clean/scripts/`(홈 사본의 R364 결속 판정기 누락도 이때 맞춰짐) · ft-resume-cmd = `install.sh --apply --project <루트>` → LIVE_BIN cmp0 · launchd 0 · 되돌림 = `.bak-r524`.
- 범위 밖: 재개 기록에 env·effort 칸 · codex 좌석 재개 · 직결 좌석 자동 재기동·kill · tmuxc(이미 정상) · 전역 ANTHROPIC_BASE_URL export 0.

## 2026-10-20 — 시험 임시 환경에 «공용 루트» 도우미: 자원 문지기 시험이 다시 회귀를 잡게 (r537 · 1.1.90)

- 사건: `test_resource_gate`(FAIL 9) · `test_resource_gate_pressure`(FAIL 5)가 팩 origin/main 에서도 RED(r522 나노 보고 · master 84 발주 119766). 좌석 여는 도구가 r459 뒤 공용 comm 폴더를 «먼저» 푸는데, 시험 임시 환경엔 공용 루트가 없어 자원 문지기에 닿기 전에 `ERROR comm 폴더를 못 풂` rc=3 으로 끝남 = r516 묶음 ③(공용 루트·comm·팀 명단 전제).
- `harness/tests/lib/fake_resource_env.sh`: `fake_comm_root <dir> [LIVE_BIN]` = 임시 git 리포 + `.fable-team/comm`·`state`·`LIVE_BIN` + `design/TEAMS.md` 최소 명단 → `FT_ROOT` export(ft_comm_dir·ft_data_root 가 git 을 부르지 않고 풂). 기존 `fake_resource_env` 무변경. pytest 판 = `tests/scripts/fake_resource_env.py` `fake_comm_root` + `conftest.py` 픽스처(명부 `seats.json` 도 심음 — `ft-nano-close.sh` R400).
- 묶음 ③ 셸 고침: resource_gate · cherry_gate_identical_head · penalty_spawn_gate · teamset_gitref · team_literal_paths · flag_off_scan · ft_land(= `fake_comm_root` 또는 임시 리포에 comm) · proposal_card · press_role_bts_gate(임시 리포 TEAMS.md) · live_install_check_tip · team_scaffold_empty_template(`--kit` 명시 · r426 꼴) · seat_handover(무인자 status 에 FT_ROOT) · spawn_gate_landing_branch(연쇄 통과). `test_resource_gate_pressure` H3 = 팩에 없는 BYZ `design/TEAMSET.md` 복사 → 같은 머리줄 최소 표(test_arch_required_gate 꼴). pytest: weekly_review(cwd = 임시 루트) · disk_census(명부).
- 시험: 묶음 ③ 셸 16 = 전 rc0 0 → 후 rc0 11(`harness/evidence/r537/before|after-bucket3-shell-rc.txt`) · pytest 2파일 19 failed → 0(47 passed). 전체(같은 바탕 5fb4b134): 셸 실패 53 → 42 · pytest 23 → 4 failed · «후에만 실패» 셸 0 · pytest 0(`compare.txt`). 단언 삭제·완화 0 · 변이 검출 그대로.
- 남은 묶음 ③ 안 다른 뿌리(범위 밖): `test_resource_gate_pressure` 감시자 줄 수(r534) · `test_seat_handover` guard·`test_team_move_roundtrip` ⓑ'(임시 bin 형제 누락 = ⑥ · r536) · `test_sheet_verify`(`_fake_mbox.sh` 옛 자리 = ⑤) · `test_team_scaffold_empty_template` ⓐ(옛 BYZ 틀 경로 문구 = ⑤) · `test_team_move_roundtrip` ⓒ(env 없이도 자기 위치로 풀림 — 시험 기대 결정 필요).
- r536(1.1.89 · r534·r522 조상) 병합 뒤 재번호 1.1.90: 충돌 CHANGES·manifest 2개뿐(기계 해소) · 함께 바꾼 시험 파일 0 · cwd = 새 임시 git 리포에서 23개 → `test_resource_gate_pressure` rc0 FAIL 0(r534 감시자 줄 수 + r537 H3) · r536 5개 rc0 · 남은 rc1 4 = 병합 전과 같은 FAIL 수 · 실 autonomy.log 486→486(`harness/evidence/r537/merge-r536-1.1.90.txt`).
- 설치: 없음(시험 파일만 · 키트 diff 0).

## 2026-10-20 — 시험 임시 bin 짝 누락(r516 묶음 ⑥) 5개 고침: 키트 bin 통째 복사 도우미 `tests/lib/kit_bin_copy.sh` + 부작용 스텁 (r536 · 1.1.89)

- 사건: r535 나노 보고 — `test_wt_clean_plan_self_check.sh` 가 팩 origin/main 에서도 FAIL 13(`harness/evidence/r535/preexisting-self-check-origin-main.txt`). arch 107 실측 = 시험이 임시 bin 에 생성기 `ft-nano-close.sh` 와 형제 몇 개만 손으로 복사하는데 생성기가 그 뒤 `ft-seat-reap.sh`·`ft-team-lib.sh` 등을 더 부르게 바뀌어 «No such file · CLOSE-FAIL reap left=? rc=127». 같은 꼴 = r516 분류표 묶음 ⑥ 5개.
- 새 `harness/tests/lib/kit_bin_copy.sh <임시 bin>`: 키트 `kit/fable-team/bin` 일반 파일 전부(설치와 같은 집합) cp -p → 부작용 도구 9개(`ft-seat-reap` · `ft-opencode-reap` · `ft-leak-reap` · `ft-docker-test-reap` · `ft-seat-retire` · `ft-tmux-kill|spawn|send|distill`)를 새 `harness/tests/stubs/kit-side-effect.sh` 로 덮음(호출 1줄 로그 · `left=0 rc=0` · exit 0 · 실제 kill·tmux·reap 0) · 출력 `KIT-BIN-COPY files=N stubbed=…`.
- 시험 5: `test_wt_clean_plan_self_check`·`test_nano_succession_index`·`test_autonomy_hooks_layout`·`test_evidence_inject_scan` = 손 복사 줄 → 도우미(각 시험의 기존 가짜 tmux·cherry·lint 스텁은 그대로 · self_check 는 «스텁 reap 호출 ≥1» 단언 추가) · `test_fake_resource_env` = 파이썬 모듈 경로 `$REPO/tests/scripts` → `$HERE/scripts`(모듈은 `harness/tests/scripts/`) · `test_evidence_inject_scan` 8 = BYZ 리포에만 있던 위반 실례(#887 run.py)를 바이트 그대로 사본 `harness/fixtures/inject_scan/run-887.py`(BYZ 554e5a4873 · blob a50d41b0) 로.
- 시험: 고치기 전 5개 rc=1(FAIL 7·4·13·6·2 · `harness/evidence/r536/before-fix.txt`) → 고친 뒤 5개 rc=0(`after-fix.txt`) · 전체 셸 전·후 비교 `compare.txt`.
- 설치: 없음 — 시험·픽스처만(키트·LIVE_BIN·홈·launchd 0). 되돌림 = 이 커밋 revert.
- 격리 고침(r534 위 재번호 때 발견): `test_autonomy_hooks_layout` 이 호출자 cwd 를 물려받아 BYZ 워크트리 안에서 돌리면 `ft_data_root` ②(cwd 공용 루트 `.fable-team/LIVE_ROOT`)를 따라 «실» 자율 상태에 on/off·approve-merge 를 썼다(2026-10-20 13:29~13:39 · A11~A18 · 끝이 on · `ft-autonomy.sh off` 1줄로 복구). 시험이 임시 MAIN 에 `LIVE_ROOT`=임시 라이브를 쓰고 `cd` 임시 워크트리 → BYZ cwd 에서 ALL PASS · 실 autonomy.log 줄 수 변화 0(`harness/evidence/r536/merge-r534-1.1.89.txt`).
- 범위 밖: 다른 묶음(①~⑤·⑦·⑧) · r535 시험 · 키트 코드.

## 2026-10-20 — 자원 감시자 디스크 기록표: 워크트리·큰 폴더를 1단계 폴더별 «증분» 측정 · 합 = 캐시 합 + «앎/전체» · 원인 도구 = 워크트리별 1시간 증가 (r534 · 1.1.88)

- 사건: 감시자 `disk-attrib.tsv` 의 `worktrees.total` 이 10-17 21:22 뒤 매회 TIMEOUT(393회 · 워크트리 443개 전체 `du -sk` 1회가 7초 상한에 걸림) · pytest 30·caches 79·claude.projects 50회도 TIMEOUT → 여유 342→238GiB(−104)인데 아는 칸 합 ≈ +6GiB(오빠 «디스크 한 100G 줄었는데?» · desk 27 쪽지 119645 → planner 83 119646 → master 84 발주 119648).
- 새 `ft-resource-du-lib.sh`(감시자가 source · 단독 실행 0 · 감시자 줄 수 ≤245 단정 때문에 형제 파일 — master 84 발주 119773): `inc_group` = 폴더 하나를 1단계 단위로 증분 측정. 한 틱 `FT_RES_WT_PER_TICK`(25)개 · 각 `run_capped du -sk`(7초 · nice 19 · 기존 잠금 그대로) · 순번 = 캐시 없음 → 잰 뒤 바뀜(2시간 안 mtime) → 캐시 오래된 순. 캐시 `du-cache.tsv` 줄 = `ts · <pfx>:<rel> · kb · 직전 ts · 직전 kb · 표식` + 바퀴 시작 `<pfx>#round`. 사라진 폴더 줄 제거 · 옛 통째 `worktrees.total` 캐시 줄 버림.
- 기록: 전부 알면 `<칸> <합KB>` · 모르는 폴더가 있으면 `<칸> PARTIAL <앎 합>`(숫자 칸이 아니라 증가 순위·경보에 안 섞임 — 부분 합을 새 숫자처럼 쓰지 않음) + `<칸>.known <앎>/<전체>`. 상한 넘긴 단위 = 그 단위만 `<pfx>:<rel> TIMEOUT` 1줄 + 폴더면 다음 틱부터 1단계 하위로 나눔(split · 깊이 `FT_RES_SPLIT_DEPTH` 3) · 못 나누면 `stale`(옛 값 보존 · 합·known 제외). 워크트리는 한 바퀴(모든 단위를 바퀴 시작 뒤 한 번씩) 끝난 틱에 `wt.top <이름> <KB>` 상위 5.
- `ft-resource-watch.sh` snapshot_disk: claude.projects · caches · pytest · worktrees(맨 끝 — 앞 칸이 남긴 시간까지 받음) = `inc_group` · 스냅샷 측정 예산 `FT_RES_SNAP_BUDGET_SEC`(55 · 남은 예산을 남은 칸 수로 나눔 · 예산으로 끊긴 du 는 TIMEOUT·split 표기 0 · 다음 틱 다시) · `FT_RES_DU_TTL_SEC`·`du_cached` 제거(통째 측정이 없어져 고아). 칸 이름(`worktrees.total`·`claude.projects`·`caches`·`pytest`)·count·recent2h·나머지 칸 그대로.
- `ft-resource-cause.sh disk`: `worktrees.total` 증가 때 «최근 60분 건드린 워크트리» 대신 `du-cache.tsv` `wt:` 줄의 1시간 증가 상위 3(잰 값 − 직전 값 · 직전 값 없는 단위는 그 워크트리가 1시간 안에 생겼을 때만 통째 · stale·split 제외) + 주인 좌석(기존 풀이 규칙 · 못 찾으면 «주인 미상») · 증가 없으면 `워크트리별 1시간 증가 없음(du-cache)`.
- 시험 새 `test_resource_watch_incremental_r534.sh`(가짜 du = 경로별 크기·시간 표 · 임시 HOME/TMPDIR/state · 외부 호출 0 · GIT_* 0) ⓐ~ⓖ — 고치기 전 FAIL 39(`harness/evidence/r534/before-fix.txt` · ⓐ worktrees.total=TIMEOUT) · 고친 뒤 PASS 55 · rc0(`after-fix.txt`). 기존: `test_resource_watch`(R323 단정을 폴더별 의미로 · 실 HOME 격리) · `test_resource_cause`(워크트리 풀이 = 캐시) · `test_resource_reclaim_preventive`(감시자 복사 때 du-lib 같이) · disk_alarm·reclaim·reclaim_pressure rc0 · `test_resource_gate_pressure` «감시자 줄 수 ≤245» PASS(origin/main 246줄 FAIL 해소) · gate 8·gate_pressure 4·fake_env 2 FAIL = 팩 origin/main 에서도 같음(comm 폴더 해석·python 추적 · 이 단위 밖)(`existing-tests.txt`). 실데이터 미리 보기(읽기만 · 임시 state): 틱 26~32초 · TIMEOUT 0 · 워크트리 75/434(`real-dryrun.txt`).
- 첫 바퀴 길이(틱당 25 · 10분 틱): 워크트리 434 ≈ 18틱(3시간) · claude.projects 2520 ≈ 101틱(17시간 — 그동안 `claude.projects PARTIAL`) · caches 100 ≈ 4틱 · pytest 1틱. 그 뒤는 새·바뀐 폴더가 다음 틱 맨 앞.
- r522(1.1.87) 병합 뒤: 감시자 263줄 → `du_line`·`du_lock` 을 `ft-resource-du-lib.sh` 로 옮기고(동작 변경 0) 증분 칸 순회를 1줄로 → 243줄 · `test_resource_gate_pressure.sh` «감시자 줄 수 ≤245» PASS(origin/main 6e72a9ab 은 265줄 FAIL) · r522 `test_resource_cpu_owner` ALL PASS 28 · 기록 `harness/evidence/r534/merge-r522-1.1.88.txt`.
- 설치: 키트 3(`ft-resource-watch.sh` · `ft-resource-du-lib.sh` · `ft-resource-cause.sh` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 3 · 감시자 launchd `com.byz.ft-resource-watch` 재기동(plist 0) · 홈 0 · 되돌림 = `.bak-r534`.
- 범위 밖: 워크트리 정리·삭제 · 디스크 경보 문턱 · −104GiB 원인 찾기(planner 읽기 전용) · 감시 주기 변경.

## 2026-10-20 — CPU 폭주 «주인» 한 줄 + 감시자 기록·planner 쪽지 1통 · 끄기 0 (r522 · 1.1.87)

- 사건: 08:4x `/usr/bin/yes` 여러 개가 CPU 100% — 오빠가 손으로 끔 · 누가 띄웠는지 사후 추적 자료 0(desk 26 쪽지 119295 · 자원 감시자는 디스크·메모리·swap 만 봄 · arch 106 실측).
- `ft-resource-cause.sh cpu`(새 모드): `LC_ALL=C ps -axo pid=,ppid=,tty=,etime=,pcpu=,comm=` 를 명령 이름(경로 뺀 이름 · 공백 든 이름 그대로)별로 묶어 «각 CPU ≥30% 인 것 ≥3개 ∧ 그중 가장 오래 ≥5분» 묶음만 → `cpu <명령>×<개수> CPU <합>% <분>분 · 주인 <세션>` (묶음마다 `; ` · CPU 합 큰 순). 주인 = 조상 pane 의 tmux 세션(mem 과 같은 걸음 · 40단) → 없으면 tty ↔ `#{pane_tty}` «<세션> (tty)» → 없으면 «미상»(추측 0) · 주인이 여럿이면 앞 3개 + «외 N». 해당 0 = 빈 출력 rc0 · ps 자료 0 = stderr ERROR rc4. 읽기 전용(프로세스 끄기·우선순위 변경 0). 시험 env `FT_RES_PS`·`FT_RES_TMUX`(가짜 출력 파일).
- `ft-resource-watch.sh` tick: 표본 뒤 · 문지기·동결 분기 «앞»에 `cpu_watch` 1회(상한 `FT_RES_CPU_CAP_SEC` 7초 · 넘거나 rc≠0 = 로그 ERROR · 동결 판정 영향 0). 출력 있으면 `state/runaway-cpu.log` 1줄(시각 + 줄) · 서명(명령·주인·개수 = CPU·분 뺀 줄)이 직전과 다르면 planner 명부(`FT_SEATS_JSON` · 기본 `seats-planner.json`) `_master` 에 `[CPU 폭주] <줄> · 끄기는 사람 판단 · kill 0` 1통 · 발신 성공 때만 서명 저장(`state/.runaway-cpu.sig` · 실패 = 다음 tick 재시도) · 폭주가 끝나면(빈 출력) 서명 지움 → 다음 폭주는 새 사건. `_master` 없음·우편함 못 풂·발신 실패 = 로그 ERROR(조용한 통과 0).
- 시험 `test_resource_cpu_owner.sh`(새 · 가짜 ps·tmux·센서·mbox · 임시 루트 · 외부 호출 0 · GIT_* 0) ⓐ 조상 pane(중간 zsh 경유) ⓑ ppid 1 · tty 대조 «(tty)» ⓒ ppid 1 · tty ?? → 주인 미상 ⓓ tick: 로그 1줄 + 쪽지 1통 · 같은 서명 다음 tick 쪽지 0 · 개수 바뀌면 1통 · `_master` 없음 ERROR · 원인 도구 실패 ERROR ⓔ 2개·4분 → 빈 출력·기록 0 ⓕ 가짜 kill·renice·pkill·killall 호출 0 + 코드(따옴표·주석 뺀)에 호출 0 — 고치기 전 FAIL 18(`harness/evidence/r522/before-fix.txt` · ⓐ usage rc2) · 고친 뒤 ALL PASS 28(`after-fix.txt`) · 기존 시험 base 대조 = `existing-tests.txt`.
- 설치: 키트 2(`ft-resource-cause.sh` · `ft-resource-watch.sh`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 감시자 launchd 재기동(RESTART 줄) · 홈 0 · plist 0 · 되돌림 = `.bak-r522`.
- 범위 밖: 자동 끄기·우선순위 변경 · CPU 를 동결·회수 조건에 넣기 · 명령 이름 허용 목록 · 08:4x 사건의 주인 찾기(자료 0).

## 2026-10-20 — 닫힌 나노 정리 계획이 밀리지 않게: sweep 시간 상한 안 여러 건 · 옛 판 계획 재생성 · 지운 크기·등록 없는 폴더 목록 (r535 · 1.1.86)

- 사건: 10-19 12:09~10-20 09:53 새 `.worktrees` 88개 ≈83GiB(planner 83 쪽지 119683). arch 107 읽기 전용 실측 — 대기 계획 18(막는 프로세스 0 이 17) · sweep 이 pass 당 1건(`FT_WT_SWEEP_MAX` 기본 1)이라 «이월 18~21» 상주 · 하네스 재설치마다 생성기 판이 바뀌어 옛 판 계획이 `.stale` 로 빠지고 다시 안 만들어짐(177) · `.hil` 57 · 등록 없는 폴더 59.
- `ft-wt-sweep.sh`: ①pass 1회 = 시간 상한 `FT_WT_SWEEP_BUDGET_SEC`(기본 90 · launchd 300 · 계획 1건 상한 120s 그대로) 안에서 막히지 않은 계획을 차례로 · 넘으면 «이월» · `FT_WT_SWEEP_MAX` 는 명시할 때만 건수 상한(기본 0 = 없음 · WAIT 는 안 셈) ②옛 판 계획 = 거부 전에 옆 생성기 `ft-nano-close.sh <seat> --replan <옛 계획>` 로 같은 좌석·같은 WT 새 계획 → 옛 파일 `.replanned` · `REPLAN` 1줄 · 같은 pass 에 실행(가드는 새 계획이 다시 건다) · 계보 세션 살아 있음·tmux 조회 실패 = WAIT(제자리) · 불가(WT 없음 · 가지 nano/* 아님 · --wt/--branch 계획) = 지금처럼 `.stale` + 사유 1줄 ③실행 직전 WT `du -sk`(`FT_WT_DU_SEC` 5 상한 · 그룹째 TERM · 넘김 = `?` · `<계획>.kb` 캐시) → cleaned 면 `.done` 끝 `# freed_kb=` · `<state>/wt-sweep.log` 폴더별 `freed seat= kb= wt=` + pass 줄 `… freed_kb=<합>` ④등록 없는 폴더(`<SCAN_ROOT>/.worktrees/*` 실폴더 중 `git worktree list` 에 없음) → `<state>/wt-orphans.tsv`(이름·mtime·KB · `FT_WT_ORPHAN_SCAN_SEC` 3600 간격 · du 합계 60s) 목록만 · 삭제 0 ⑤`.sh.hil` 수 → 요약 `hil_files N` · 처리 0. 요약 줄 꼬리 `freed_kb · replanned · hil_files · orphans`(값 있을 때만) · `--launchd` 로그 줄에 `replanned= hil_files= orphans= freed_kb=` 추가.
- `ft-nano-close.sh`: `--replan <옛 계획>` 진입점 — 굽힌 값 줄(SEAT·KEY·WT·PREFIX·LEDGER·FT_NANO_WIP·PLAN_ONLY·MAINREF)만 읽고 몸통은 지금 생성기 · 팀 env·드리프트·원장 해석·명부·종료조건·kill 전부 건너뜀 · rc 0 `PLANNED` · 4 WAIT · 1 REJECT 사유 1줄. 다른 경로 동작 0 변경.
- 시험 새 `test_wt_sweep_budget_replan_r535.sh`(임시 리포·워크트리 · 가짜 tmux·lsof·du·baton · 외부 호출 0 · GIT_* 0) ⓐ~ⓖ — 고치기 전 FAIL 30(`harness/evidence/r535/before-fix.txt`) · 고친 뒤 ALL PASS 50(`after-fix.txt`). `test_ft_wt_sweep_route_timeout.sh` ⓒ = MAX=1 명시 때 1건 · 기본 = 전부 · `test_wt_clean_two_stage.sh` ⓓ = 옛 판 → REPLAN(옛 몸통 실행 0 · 새 plan-ver 실행) + 재생성 불가 → STALE(변이 2 여전히 검출). 기존 시험 13개 rc0(`existing-tests.txt`) · `test_wt_clean_plan_self_check.sh` 는 팩 origin/main 코드에서도 FAILED 15(기존 RED · `preexisting-self-check-origin-main.txt` · 별도 단위 요청).
- 설치: 키트 2(`ft-wt-sweep.sh` · `ft-nano-close.sh` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · launchd 0 변경(`com.byz.ft-wt-sweep` 그대로) · 홈 0 · 되돌림 = `.bak-r535`.
- 범위 밖: 등록 없는 폴더·`.hil` 지우기(사람 경로) · 부모 잃은 시험 셸 끄기(kill = HIL) · 브랜치 삭제(HIL) · 보관본 크기 규칙(r443) · 디스크 측정(r534).

## 2026-10-20 — 오빠 큐 줄 = 번호·팀·보여준 시각 칸 + `ft-queue.sh shown|due|take|remind` · 틱이 보여준 지 1시간 넘은 대기 줄을 그 팀 master 에 [재질문] (r529 · 1.1.85)

- 사건: 오빠 큐 줄이 «언제 오빠께 보였는지» 기록이 없어 한 번 묻고 나면 아무도 다시 안 묻고, 오빠 값이 와도 그 팀이 줄을 꺼내 재개하는 길이 없다(오빠 09:2x «각팀 마스터 팀장이 큐를 보게하고 내결정 노출시간이 한시간 이상 지나면 다시 물어보고 팀장이 꺼내서 다시 진행가능해야함» · desk 26 쪽지 119482 → master 83 발주 119484 카드 ②).
- 큐 칸 셋 = 상태 칸 «뒤» `번호 | 팀 | 보여준 시각`(머리 이름으로 찾음 · 옛 7칸 줄은 셋 다 `-` 로 읽음 · 옛 줄 고쳐 쓰기 0 · 옛 머리 큐에 새 줄을 쓰면 머리·구분 행만 10칸으로). 파서 `ft_queue_state.py` 무변경(r528 시험 «상태 뒤 칸이 늘어도 그대로»).
- 새 `ft-queue.sh`(본체 `ft_queue.py` · `ft_queue_remind.py` — 200줄 한도로 나눔): `shown <qN> [--at]` 그 줄 «보여준 시각» 칸만 · `due [--team] [--min 60]` = 대기 ∧ (보여준 시각 ≤ 지금−60분 ∨ -) · 보류 ∧ 재확인 시각 지남(tag=재확인) · 끝줄 `QUEUE-DUE n= old=`(번호 없는 열린 옛 줄은 대상 밖 · 셈만) · `take <qN> --value --by --verdict` = 상태 `진행 — <master>` · 사유 끝 `오빠 값: … (판정 N)` · 출력 `RESUME <qN> team= kind= → …` · 대기·보류 줄만(이미 진행·완료 = REJECT) · `remind --rosters --mbox` = due 줄마다 그 팀 명부(`seats-<팀>.json` · `seats.json` 은 `_master` 의 `byz-<팀>-`) `_master` 에 `[재질문] qN · 보여준 지 N분 · <질문 첫 60자> · desk [인터뷰 요청] 로 다시` 1통 · 팀 `-`·명부 없는 팀 = planner `_master` · 같은 줄(번호·보여준 시각·tag) 60분 안 다시 0(`<상태>/queue-reask.json`) · 자율 ON = 쪽지 0 · `<상태>/queue-reask-morning.md` 아침 묶음 1줄(r291). 쓰기 줄 = ft-proxy-decide 와 같은 락(`<상태>/.proxy.lock`) · 한 번에 한 줄 · 같은 폴더 임시 파일 → rename · 실패 = ERROR rc≠0(조용한 통과 0) · mbox send 7초 + 재시도 1회.
- `ft-proxy-decide.sh`: QUEUE 줄 쓰기 = `ft-queue.sh add` 하나(번호 q<최대+1> · 팀 = `--team`(새 인자) → `--card` 경로 `design/[teams/]<팀>/indices/` → `-` · 보여준 시각 `-`) · 출력 `QUEUE … · 큐 줄 qN · 큐 파일 …`.
- `ft-tick.sh`: `queue_watch`(매 루프 `ft-queue.sh remind --rosters <명부 폴더> --mbox <MBOX>`) + `pass()` 호출 1줄 · `FT_TICK_QUEUE=0` 끔 · `FT_TICK_QUEUE_MIN`(60) · --dry-run = `DRY kind=queue-reask` 1줄.
- 시험 새 `test_queue_reask_r529.sh`(임시 큐·명부·가짜 mbox · `FT_NOW` · 외부 호출 0 · GIT_* 0) ⓐ~ⓗ — 고치기 전 FAIL 43(`harness/evidence/r529/before-fix.txt` · 같은 최종 시험을 팩 origin/main 코드에) · 고친 뒤 ALL PASS 52(`after-fix.txt`). `test_queue_state_r528.sh` ⓔ 기대 꼴 = 10칸 · 상태 칸 대기(7칸 단정을 r529 꼴로). 기존 시험 9개 rc0 · pytest decision_count 2파일 33 passed · ruff·shellcheck 0(`existing-tests.txt`). 정본 큐 사본 읽기 전용 미리 보기 `QUEUE-DUE n=0 old=30`(`real-queue-due-preview.txt` — 열린 옛 줄 30 은 번호가 없어 재질문 대상 밖 · 새 줄부터 적용).
- 설치: 키트 5(`ft-queue.sh` · `ft_queue.py` · `ft_queue_remind.py` · `ft-proxy-decide.sh` · `ft-tick.sh` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 5 · 틱 launchd kickstart 1회(plist 0) · 홈 0 · 되돌림 = `.bak-r529`.
- 범위 밖: desk 질문 도구가 `shown` 을 부르는 연결(desk 쪽 1줄 · master 가 설치 때 알림) · 묶음 질문(r165 — «답 반영» = `take`) · 열린 옛 줄 30 에 번호 붙이기·일괄 정리(r530 · 인터뷰 때 줄마다).
## 2026-10-20 — 일괄 보류 금지: 한 커밋에서 큐 줄·카드 상태를 2개 이상 «보류» 로 바꾸면 커밋 REJECT (r530 · 1.1.84)

- 사건: 10-18 전팀 정지 뒤 오빠 큐(`AUTONOMY-QUEUE.md`) 23줄에 같은 문장 «보류 — 10-18 전팀 정지(판정 2253) 뒤 오빠 대기 아님 · 재개 때 팀별 재확인» 이 한 커밋(BYZ d575bb1ace)으로 붙고 아무도 다시 안 꺼냄. 오빠 결정(desk 쪽지 119482) «일괄 보류 절대금지» → master 83 발주 119484 · 카드 r530.
- 새 `kit/fable-team/bin/ft_queue_bulk.py bulk-check --staged [--worktree] | --range A..B [--repo <dir>]`(harness/bin 짝 cmp0): 대상 = 큐(이름 `AUTONOMY-QUEUE.md`) 상태 칸(옛 «처리됨») + `design/**/indices/**/*.md` 카드 «- 상태:» 줄. 옛 값(없으면 새 줄) → 새 값이 «보류» 인 것만 셈 · ≥2 = rc1 `REJECT 일괄 보류 N줄(<큐>:<줄>,<카드>.md…) — 보류는 한 번에 한 줄 · 줄마다 사유·재확인 시각 · 전팀 정지는 줄 대신 ft-spawn-hold.sh 정지 파일(«일시정지»)` · 아니면 rc0 `OK 일괄 보류 <n>줄` · git 실패·인자 오류 = stderr ERROR rc2. 큐 칸 판정 = r528 `ft_queue_state.parse` 그대로(import) · 줄 짝 = 상태 칸 밖 칸 묶음 · 카드 이동(git mv · `-M`)은 옛 경로와 비교 · 풀기(보류 → 대기·진행·완료)는 안 셈. 읽기만.
- `kit/hooks/harness-freeze-gate.sh` 규칙 1 추가(새 홈 훅 0 · settings 등록 변경 0): 이미 잡은 «git commit 대상 저장소 + 대상 파일(스테이징 · -a 꼴이면 작업 트리도)» 에 큐·`/indices/` 가 있으면 `bulk-check --staged [--worktree]` → rc1 = exit 2 + stderr `🚫 [harness-freeze-gate] REJECT 일괄 보류 …` 1줄 · freeze 표식 유무와 무관(규칙별 독립). 판정기 = env `FT_QUEUE_BULK` · 아니면 대상 저장소 → JSON cwd 저장소 공용 루트 `.fable-team/LIVE_BIN`. 못 찾음·rc2 = 통과 + stderr WARN(fail-open) · 입력 JSON 깨짐 = 통과 + WARN(전엔 조용한 통과).
- BOOT 조항 43 1줄(스테이징 `harness/design/harness/staged-r530/COMM-GUIDE-BOOT.md` = 홈 BOOT + 1줄 · diff 1): 큐 상태 4 + 정지 종류 3 · 보류는 한 줄씩 · 일괄 보류 = 훅 REJECT · 대기 줄 1시간 재질문 `ft-queue.sh take`(r529).
- 시험 `test_queue_bulk_r530.sh`(새 · 임시 git 리포 · 큐 md + 카드 2장 · PreToolUse JSON · 외부 호출 0 · GIT_* 0) ⓐ 큐 2줄 → REJECT(줄 번호) ⓑ 1줄 → OK ⓒ 새 줄 2개 처음부터 보류 → REJECT ⓓ 카드 2장 → REJECT · 1장 → OK · 큐 1 + 카드 1 → REJECT ⓔ 풀기 3줄·카드 2장 → OK · 보류 카드 2장 git mv → OK ⓕ 훅 commit/cd/-a → exit 2 · 비커밋·따옴표 글자·1줄 → 0 · 판정기 없음·JSON 깨짐 → 0 + WARN ⓖ `--range` 같은 판정 · 없는 rev rc2 · 기존 `test_harness_freeze_gate.sh` rc0. 고치기 전 FAIL 27(`harness/evidence/r530/before-fix.txt`) · 고친 뒤 ALL PASS(`after-fix.txt`) · 뮤테이션 5종 전부 RED(`mutation.txt`) · 기존 5파일 rc0(`existing-tests.txt`) · BYZ 큐 이력 읽기 전용 재생: 사건 커밋 d575bb1ace = `REJECT 일괄 보류 23줄` · 나머지 OK(`real-queue-history.txt`).
- 설치: 키트 1(`ft_queue_bulk.py`) + 홈 훅 1(`harness-freeze-gate.sh`) → `install.sh --apply --project <루트>` → HOOKS bad=0 · 홈 훅 cmp0 · LIVE_BIN cmp0 1 · settings 변경 0 · BOOT = staged-r530 을 홈 `~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 로 cp+cmp(master) · 되돌림 = `.bak-r530`.
- 범위 밖: 지금 큐 23줄 풀기(desk 인터뷰 때 줄마다) · Edit/Write 단계 차단 · 정지 파일 자동 생성 · 훅 이름 바꾸기(r532).

## 2026-10-20 — 오빠 큐 상태 칸 = 대기·진행·보류·완료 넷 + 정지 종류 셋 · 어휘 정본 1장 + 린트 + 새 줄 «대기» (r528 · 1.1.83)

- 사건: 오빠 큐(`AUTONOMY-QUEUE.md`) 끝 칸 «처리됨» 이 손글 자유 문장 — 91줄 중 빈 칸 30 · «보류 — 10-18 전팀 정지(판정 2253) 뒤 … 재확인» 23줄 등 보류·대기·진행·완료가 섞여 읽힘(arch 107 실측). 오빠 결정(desk 쪽지 119482) «보류와 대기 진행 완료를 명확히 구분 … 일시정지·구현중정지·대기중정지» → master 83 발주 119484.
- 새 `kit/fable-team/bin/queue-states.tsv`(어휘 정본): 상태 4(대기 · 진행 — 누가 · 보류 — 사유 + «재확인 YYYY-MM-DD HH:MM» · 완료 — «판정 N» 또는 착지 sha) + 정지 종류 3(일시정지 — hold 번호 · 진행·대기에 · 구현중정지 — 멈춘 단계 · 진행에 · 대기중정지 · 대기에). 칸 꼴 `<상태>[ · <정지>][ — <덧말>]`.
- 새 `ft_queue_state.py parse|lint <큐>`: 판정기 하나 · parse = 행마다 JSON(줄 번호 · 머리 이름별 칸 · 상태 · 정지 · 덧말 · 재확인) — 칸이 늘어도 수정 0 · lint = 어휘 밖 줄 `ERR <줄> <사유> :: <칸>` + 끝줄 `QUEUE-STATE ERR=<n> OK=<m>` · rc 0/1 · 큐·어휘 읽기 실패 = stderr ERROR rc 2. 머리 «상태»·옛 «처리됨» 둘 다 같은 칸(이름 바꾸기 0). 읽기만.
- `ft-proxy-decide.sh`: QUEUE 새 줄 7칸 · 끝 칸 `대기` · 새 큐 파일 머리 7칸(`상태`).
- `ft_decision_count.py` autonomy_open: 상태 칸(옛 처리됨) 의 «열린 줄» = 빈 칸(옛) 또는 상태 «대기» — 안 고치면 새 줄의 `대기` 가 «처리됨 값 있음 = 닫힘» 으로 세여 결정 수가 줄어든다(카드 Issue ③ 같은 큐 읽는 도구).
- 시험 `test_queue_state_r528.sh`(새 · 임시 큐·FT_ROOT · 외부 호출 0 · GIT_* 0) ⓐ~ⓕ — 고치기 전 FAIL 23(판정기 파일 없음 · `harness/evidence/r528/before-fix.txt`) · 고친 뒤 ALL PASS(`after-fix.txt`). 기존: proxy-decide r188·queue_card_resolve·team_literal_paths2·decision_count_tables_ref rc0 · pytest decision_count 2파일 33 passed · `test_autonomy_core` FAIL 1 = BYZ `shared/config/external_call.py` 대조(r516 분류 ④ · 바탕 같음)(`existing-tests.txt`). 정본 큐 읽기 전용 미리 보기 `QUEUE-STATE ERR=89 OK=0`(`real-queue-lint-preview.txt`).
- 설치: 키트 4(`queue-states.tsv` · `ft_queue_state.py` · `ft-proxy-decide.sh` · `ft_decision_count.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 4 · launchd 0 · 홈 0 · 되돌림 = `.bak-r528`.
- 범위 밖: 지금 큐 줄 고쳐 쓰기(desk 인터뷰 때 줄마다) · 하네스 카드 «- 상태:» 어휘 · 시각·재질문(r529) · 일괄 보류 차단(r530).

## 2026-10-20 — 정지 스캔 종류 e = 명부 루프가 안 보는 tmux 라이브 좌석(교대 표시·명부 밖)의 조용한 정지 알림 (r525 · 1.1.82)

- 사건: 팀 개명(concierge→chatbot) 뒤 concierge master 6 행이 `role=stop-ready`·`_replaced_by` 로 표시됐는데 세션은 tmux 에 살아 이관 일을 쥔 채 컨텍스트 100% 로 멈춤 → 12시간+ 아무 틱도 못 봄(desk 26 쪽지 119421 · 오빠 «왜 자꾸 조용한 침묵 정지를 하냐고»). 원인 = `ft_stall_scan` 이 `load_teams` 현역 행만 훑음.
- `ft_stall_detect.py`: `off_roster_live(root, live, teams)` = tmux 라이브 − (현역 행 ∪ 팀 master) → (좌석, 계보 현역 master, `교대 표시인데 라이브`|`명부 밖`) · 계보 = `_replaced_by` 사슬 끝 좌석이 있는 명부의 `_master`(못 찾으면 처음 명부 · 자기 자신이면 None) · `agent_sessions(tmux, ps)` = ps 1회 + list-panes 1회로 pane 자신+자손에 claude|codex 가 도는 세션 · `ctx_pct` = `ft-claude-context.sh <좌석>` 7초 상한(실패·숫자 아님 = None · 추측 0) · `run(..., timeout=)` 인자.
- `ft_stall_scan.py`: 종류 e = 위 후보 ∧ agent 실행 중 ∧ IDLE ≥ `FT_STALL_E_IDLE_MIN`(기본 30) ∧ (ctx ≥ 90 ∨ [완료·휴식] 없음) → planner `_master` + 계보 현역 master(같으면 1통)에 `[정지] <좌석> 쉬는 <N>분 · <꼬리표> · 열린 일 · ctx <p>%|ctx ? · 깨우기/닫기/인계는 받는 쪽 판단` · 서명(좌석 → IDLE 시작 시각 · `state/stall-scan.e.json`)이 같으면 다음 실행 쪽지 0 · 로그 `act=e seat=… notify=…`(`to=` 꼴 아님 — 10분 가드가 받는 이 좌석을 막지 않게) · 요약 줄 `d=` 뒤 `e=` 칸(뉴스 `stall_cell` 은 앞 5칸만 — 무변경) · `stall=N` 에 e 포함. env 시험용 `FT_PS` · `FT_CTX_CMD`.
- 경계: 깨우기(Escape·ring)·kill·명부 쓰기·페널티(ft-penalty) 대상에 e 넣기 0 · attached·페널티 정지 중에도 알림은 감(알림만이라).
- 시험 새 `tests/scripts/test_ft_stall_scan_off_roster.py`(가짜 명부·tmux(pane_pid)·ps·ctx 스텁 · 외부 호출 0 · GIT_* 0) ⓐ 교대 표시 라이브 IDLE 45 → e 1 · planner+계보 master 2통 ⓑ 명부 밖 ctx 93 → planner 만 ⓒ 같은 서명 다음 실행(11분 뒤) 쪽지 0 · 요약 줄 e=1 ⓓ IDLE 25 → 0 ⓔ [완료·휴식] ∧ ctx 40 → 0 · ctx 95 → e 1 ⓕ 빈 셸 0 · 명부 밖 나노(codex) → e 1 «ctx ?» ⓖ send-keys·kill 0 · ring 0 · dry-run 쪽지 0. 고치기 전 7 FAIL → 7 passed · stall 관련 기존 6파일 72 passed(`test_summary_line…` 기대 꼴에 `e=0` 칸). 증거 `harness/evidence/r525/`(red-before · green-after · live-dry-run · live-candidates · install-dry-run · master-steps).
- 라이브 dry-run(쓰기·쪽지 0): `stall=1 … e=1 seats=43` · `e byz-planner-desk-claude#23 768 교대 표시인데 라이브 · 열린 일 · ctx 14%` · 후보 8(agent 6) — concierge 6·airag 8 은 [완료·휴식] ∧ ctx < 90 이라 0.
- 설치: 키트 2(`ft_stall_scan.py` · `ft_stall_detect.py` · harness/bin 짝 cmp0) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · launchd `com.byz.ft-stall-scan` kickstart 1회(plist 0) · 홈 0 · 되돌림 = `.bak-r525`.

## 2026-10-20 — 홈 훅 `bg-cpu-burner-gate.sh` = 시간 상한 없는 백그라운드 CPU 소모기 거절 (r523 · 1.1.81)

- 사건: 10-19 23:27Z v65 나노가 부하 재현 스크립트 `loadrep.sh` 안에서 `nice -n 19 yes > /dev/null &` 여러 개를 띄우고 정리는 `trap EXIT` 뿐 → 강제 종료로 trap 이 안 돌아 `yes` 고아 → CPU 100 · 오빠 손 kill(v65 215 쪽지 119303 → desk 119305 → master 83 발주 119306). «burner 0» 은 메모리 글뿐이라 못 막음.
- 새 홈 훅 `kit/hooks/bg-cpu-burner-gate.sh`(PreToolUse:Bash · 모든 리포 · `op-vault-develop-gate.sh` 꼴 = python3 본문 · fail-open): 명령 글자 + 그 명령이 실행하는 스크립트 파일 1단계(`bash|sh|zsh|dash|source|.` 다음 인자 · 첫 낱말이 경로 · cwd 기준 · ≤256KB · 바이너리 생략)를 따옴표·주석·heredoc 본문을 가린 뒤 조각낸다. 소모기 = 감싸개(env·nohup·nice·stdbuf·command·exec·time) 벗긴 첫 낱말 `yes` · `cat /dev/zero|/dev/urandom` · `dd if=/dev/zero|/dev/urandom`(count= 없음) · `while true|:|[ 1 ]|(( 1 ))` 루프(본문 sleep 이면 아님 — r448 영역). 백그라운드 = 파이프라인 끝 단독 `&`(`done &` 포함 · `2>&1`·`&>` 는 재지정) 또는 `run_in_background: true`. 면제 = burner 바로 앞 `timeout|gtimeout N` · N ≤ 600초 하나뿐(바깥 `timeout … bash x.sh` 는 안의 `&` 고아를 못 끄므로 면제 아님). 거절 = exit 2 + stderr `REJECT bg-cpu-burner <파일:줄|명령> — …` 1줄. 거절만 — kill·renice·실행 0 · 외부 프로세스 0.
- 등록: `settings-hooks.snippet.json` PreToolUse `Bash` 1항목(`$HOME/.claude/hooks/bg-cpu-burner-gate.sh`). 설치기는 kit/hooks 전부를 복사(r491) — settings 등록은 master.
- 시험 `test_bg_cpu_burner_gate.sh`(새 · 임시 폴더 · 실제 burner 실행 0 · 가짜 kill/pgrep/ps/pkill · GIT_* 0) ⓐ~ⓙ 65건 — 고치기 전 FAIL(훅 파일 없음 · `harness/evidence/r523/before-fix.txt`) · 고친 뒤 ALL PASS(`after-fix.txt`) · mutation 10종 전부 RED(`mutation.txt`) · 실제 스크립트 745개(kit·bin·tests·홈 훅·BYZ scripts)를 `bash <파일>` 로 넣어 거절 0(`real-scripts-scan.txt`).
- 기존 시험 1: `test_op_vault_develop_gate.sh` 의 «install.sh HOME_HOOKS 1토큰» 검사가 r491(HOME_HOOKS = kit/hooks find 목록) 뒤 base 에서도 FAIL 1 → 지금 꼴(find 목록 + 훅 파일 실재)로 고침 · rc0(`existing-tests.txt`).
- 설치: 키트 훅 1 → `install.sh --apply --project <루트>` → 홈 `~/.claude/hooks/bg-cpu-burner-gate.sh` cmp0 · settings.json PreToolUse Bash 등록 1 · LIVE_BIN 0 · launchd 0 · 되돌림 = `.bak-r523`.
- 범위 밖: 이미 떠 있는 burner 끄기(r522 = 사후 기록 · 끄기는 사람) · CPU 실측 · python/node 안 무한 루프 · 2단계 이상 스크립트 · `( … ) &`·`{ …; } &` 묶음 · `cat /dev/zero | gzip &` 처럼 burner 가 파이프라인 끝이 아닌 꼴.

## 2026-10-20 — 하네스 시험 «밖 RED» 셸 62 · pytest 104 를 원인 8묶음으로 분류 · 가장 큰 묶음(pytest 79) + 픽스처 미이관 묶음 고침 (r516 · 1.1.80)

- 사건: r509 끝선 «기존 시험 전체 rc0» 이관분 — 팩 main 에도 있는 밖 RED(셸 62 · pytest 104)가 나노 증거마다 «기존 RED 제외» 로 깔려 새 실패를 가렸다(harness master 83 발주 118693 · arch 106 카드화 · 판정 1395).
- 분류(바탕 9af3b78a · 셸 253 · pytest tests/scripts 직렬): ① slack 수신 시험 KIT 경로 이중 pytest 79 ② BYZ `tests/fixtures` 미이관 10 ③ 공용 루트·comm·팀 명단 전제 34 ④ BYZ 리포 전용 파일 전제 16(시험 자리 결정 = arch) ⑤ 옛 BYZ 배치 경로 6 ⑥ 시험 임시 bin 짝 누락 5(2개 r515 가 닿음) ⑦ 홈·라이브 실물 대조 7 ⑧ 낡은 대조·환경·개별 9 — 표 `harness/evidence/r516/red-buckets.md`.
- 시험(4 · 도구 0): ①`test_byz_slack_mbox_inbound.py`·`test_inbound_humans_and_install.py` `KIT = HERE.parents[1]/"harness"/kit` → `parents[1]/kit`(r386 이전 글자 치환이 harness/ 를 한 번 더 붙임) ②`test_team_literal_paths` goal_table = `fable-team/tests/fixtures`(test_goal_table_gate 와 같은 사본) · 가려 있던 2건: `test_mbox_guard` hold_env 에 `ft-harness-root.sh` 짝 · `test_issue_close_canon` 임시 리포 `.fable-team`(⑧ close-reason-check 가 cwd 리포를 공용 루트로).
- 픽스처(89 · 내용 0 변경): BYZ origin/main `6c22cefe01` 의 `tests/fixtures/{deferral,issue_classify,issue_close,seat_request,magazine}` → `harness/fixtures/`·`harness/tests/fixtures/magazine` · `mbox_guard` → `fable-team/tests/fixtures/`(시험이 읽는 자리 그대로).
- 시험: 같은 바탕 전·후 셸 실패 62→55 · pytest 104→23 failed · 후에만 실패 pytest 0 · 셸 «후에만» 1(`test_inbox_watch` = 두 판 단독 재실행 같은 RED · 팩 공용 루트 실물) · 흔들림 `test_cherry_gate_identical_head` ④ 1건(두 판 단독 재실행 없음) — 원문 `harness/evidence/r516/compare.txt`·`bucket-before-after.txt` · 합친 판(1.1.79 병합)에서 고친 시험 재확인 ② 7개 rc0 · pytest 4파일 109 passed. `test_deferral_lint` 남은 34 = ④(BYZ `.claude/hooks/deferral-lint-gate.sh`) · `test_team_literal_paths` 남은 4 = ③. 설치: 키트 diff 0(시험·픽스처·증거만) · 홈 0 · plist 0 · 되돌림 = 이 PR revert.

## 2026-10-20 — `ft-hil.sh --pending` = 파이썬 한 번의 훑기 · 같은 결과를 1초 안에 · 읽기 실패 rc 3 (r521 · 1.1.79)

- 사건: `--pending` 이 `/tmp/h<N>` 880개를 파일마다 `plan_of`(sed·head)·`done_rc`(grep)·`age_min`/`since_min`(stat·date) 하위 프로세스로 훑어 부하 17 에서 2.8~3.2초 · 부하 26~30 에서 4.35~4.68초 → `ft-decision-count` 1회 예산 5.0초(R303)에 붙어 rc4 «ft-hil.sh TimeoutExpired» 2회(§74 r517 · §77 r337 편차 · arch 106 실측).
- 새 `ft_hil_pending.py <HIL_DIR> [--each]`: 옛 pending() 과 같은 규칙 — 이름 h<숫자> · 일반 파일(링크 0) · 첫 `# ft-hil-entry plan=` 줄 값 있음 · `.superseded` 없음 · `.ran` 에 `^rc=[0-9]* ` 행 = 끝 · 없으면 중단/실행 중(1행 epoch · 숫자 아니면 `.ran` mtime) · `.ran` 없음 = 미실행(mtime) · 분 = 0 쪽으로 버림(셸 산술과 같음) · 이름순. 출력 꼴 바이트 같음(요약 1줄 · `--each` = `h<N> <분>` · 0개·폴더 없음 = 출력 0 rc 0).
- `ft-hil.sh` pending() 본문 → 같은 폴더 `ft_hil_pending.py` 호출 1줄. `plan_of`·`age_min`·`since_min`·`done_rc` 셸 함수는 목록·`--add` 가 그대로 쓴다.
- 바뀐 것 1: 읽기 실패(폴더·h 파일·`.ran` 권한 등) = stdout 0 · stderr `ERROR ft-hil --pending 읽기 실패: <경로>: <이유>` 1줄 · rc 3(옛 판은 그 파일을 건너뛰거나 0개로 조용히 rc 0). 결정 셈은 rc≠0 을 ReadError 로 드러낸다.
- 시험 `test_hil_pending_single_pass.sh`(새 · 임시 HIL_DIR · 외부 호출 0 · GIT_* 0) ⓐ 900개 1초 안 ⓑ 6종(미실행·실행 끝·실행 중·대체됨·옛 링크·표식 없음) + 가장자리 꼴 9종(1행 숫자 아님·`rc= `·`rc=0` 공백 없음·미래 시작 -2분·빈 표식·끝 개행 없음·폴더 h<N>·깨진 대체 링크·숫자 아닌 꼬리/0 앞자리) 과 900개에서 요약·`--each`·다른 인자가 옛 판(시험 안 복사본)과 바이트 같음 ⓒ 0개·폴더 없음 = 출력 0 rc0 ⓓ 권한 0(h 파일·`.ran`·폴더) = stdout 0 · stderr 1줄 · rc 3 — 고치기 전 FAIL 7(ⓐ 3.54초 · ⓓ 6건 조용한 0 · `harness/evidence/r521/before-fix.txt`) · 고친 뒤 ALL PASS(ⓐ 0.139초 · `after-fix.txt`) · 실 `/tmp`(h 363개) 읽기 전용 옛 판 대비 diff 0 · 1.54초 → 0.08~0.10초(`real-tmp-readonly.txt`).
- 기존 시험 픽스처 1: `test_tick_team_msg.sh` 가 가짜 bin 에 `ft-hil.sh` 만 복사 → 짝 `ft_hil_pending.py` 도 복사(고치기 전 ⓔ FAIL 2 → rc0). 운영 루트 shim 은 LIVE_BIN 사본을 `exec` 하므로 짝을 찾는다. 기존 시험 결과·base 대조 = `existing-tests.txt`.
- 설치: 키트 2(`ft-hil.sh` · 새 `ft_hil_pending.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 홈 0 · plist 0 · 되돌림 = `.bak-r521`.
- 범위 밖: 오래된 h 파일 지우기·옮기기(삭제 = 사람 판단) · 결정 셈 예산 5.0초(R303) · 7초 룰 변경 0.

## 2026-10-20 — nano-close reap 실패 뒤 «같은 close 재실행» 이 실제로 이어지게 + reap 1회 재시도 (r520 · 1.1.78)

- 사건: r519 나노 닫기 1차에서 reap 이 left=1(그 순간 돌던 `git status` 1개)로 CLOSE-FAIL — 안내는 «명부는 삭제됨 · 같은 close 재실행» 인데, 재실행은 RERUN 판별(명부에 좌석 없음 · 원장 닫힘 행 있음)에 닿기 «전» 카드 찾기(명부 index)에서 «카드 못 찾음»(팩 경로는 ⓐ 문구) REJECT → 그 좌석을 닫을 도구 경로 0(harness master 83 발주 119095 ① · arch 106 실측).
- `ft-nano-close.sh` 조기 재실행: 인자·명부·원장 결정 직후, 카드 찾기 «앞» — 명부에 행 없음(`jq has` rc 1 만) ∧ 원장에 «`<좌석>` 닫힘(ft-nano-close)» 행 1개 이상이면 «재실행 — 명부에 없고 원장 닫힘 행 있음: 검사 건너뛰고 남은 정리(reap·회수·태그·kill)만» → 카드·증거·cherry 검사 0 · reap(재시도 포함) → 세션 있으면 태그 해제 + kill → opencode 회수 → `CLOSED <좌석> (재실행 · 세션 kill|세션 없음 · 원장 행 그대로 · append 0)`. 명부·원장 쓰기 0 · 워크트리·브랜치 손대기 0. 워크트리 인자 = `--wt` › 원장 행 `wt=<절대경로>`(pack-wt·named-wt 꼴) › 없음(--shared-wt 는 늘 없음). tmux 조회 실패(서버 없음 외) = REJECT(fail-closed). 원장 행이 없는 좌석(처음 보는 좌석)은 이 길로 오지 않는다 — 기존 검사 그대로. `--plan-only` 대상 아님.
- reap 1회 재시도(`_seat_reap`): left≠0 ∨ rc≠0 이면 `FT_REAP_RETRY_SLEEP`(기본 3)초 뒤 1회만 다시 · 두 번째 결과로 판정 · 출력 «reap 재시도 1 — 1회째 left=… rc=…». 그래도 남으면 지금처럼 CLOSE-FAIL(무한 재시도 0). 정상 경로·재실행 경로 공용.
- 구조 이동(별 커밋): `_oc_close`·`OC_BIN`/`OC_PF` 정의를 위로(본문 그대로). 아래 옛 RERUN 분기(`RERUN=1 ∧ 원장 행` → append 생략)는 조기 재실행이 먼저 잡아 사실상 닿지 않지만 방어로 남김.
- 시험 `test_nano_close_rerun_early.sh`(새 · test_nano_close_pack_wt 꼴 픽스처 + 가짜 reap 모드 파일 · 외부 호출 0 · GIT_* env 0) ⓐ 1차 CLOSE-FAIL → 2차 재실행 CLOSED(원장 행 1 그대로 · 태그 해제·kill) · ⓐ' 세션도 없음 → CLOSED kill 0 · ⓑ 1회째 left=1·2회째 left=0 → 1차 CLOSED(reap 2회) · ⓒ 늘 left=1 → reap 정확히 2회 뒤 CLOSE-FAIL · ⓓ 명부·원장 행 둘 다 없음 → REJECT(재실행 0 · reap 0) · ⓔ 명부 행 있음 = 기존 경로(증거 검사 · reap 1회 · append 1) — 고치기 전 FAIL 14(`harness/evidence/r520/before-fix.txt` · ⓐ 2차 «카드 못 찾음» REJECT 재현) · 고친 뒤 ALL PASS(`after-fix.txt`) · 기존 nano-close 시험 9 + seat_reap_left0·opencode_reap·nano_team_env·pack_nano_worktree_place rc0(`existing-tests.txt`).
- 설치: 키트 1(`ft-nano-close.sh`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0 · plist 0 · 되돌림 = `.bak-r520`.
- 범위 밖: 명부 삭제와 reap 의 순서 바꾸기 · `ft-seat-close.sh` NOROW 동작 · 손 tmux kill.

## 2026-10-20 — 결정 인터뷰 N = 현역 좌석·도구가 보낸 «질문 표식» 미닫힘만 · 통보 0 · planner 답장 자동 닫힘 · 묵은 칸 (r337 · 1.1.77)

- 사건: planner 보고 첫 줄 「결정 인터뷰 N건」(판정 1804)의 분모가 «인박스 ②③ 분류 미닫힘» 이라 [완료]·[정지 레디]·[수령]·[회신] 통보가 섞이고, planner 가 쪽지로 답해도(`ft-inbox mark` 안 함) 원쪽지가 안 닫혀 하루 종일 28~31(10-17 22:1x · 실제 질문 [결정] 4). 팀 대기도 같은 꼴 — 07:33 라이브 1.1.75 「팀 대기 43건(가장 오래 byz-planner-arch-claude#7 1071분)」 의 가장 오래 = [완료·휴식] 통보(r2 ㉠) · 「(AUTONOMY-QUEUE 파일 없음)」 메모 매번(r2 ㉡).
- `ft_decision_kind.py`(새 · 분류 1곳): 본문 첫 줄 «머리»(앞 대괄호 묶음) → 질문표식 = `[결정]`·`[HIL]`·`[인터뷰 요청]`(«·» 변형 포함 · `[결정 대기 경보]` 같은 이름 겹침 제외) 또는 `[긴급]` + 첫 줄 «?»·«예/아니오»·«①…②» / 통보 = 통보 머리(`[완료…]`·`[정지 레디]`·`[수령]`·`[회신…]`·`[보고]` — 물음표가 있어도 0) 또는 표식 없음 / 묵음 = 24시간 넘은 질문. 본문 못 읽음 = ReadError rc4(분류 지어내기 0).
- `ft_inbox_core.obligation_closed(line, answered=frozenset())` 정본 술어 확장 + `answered_seqs(seat)`: 큐 주인 계보가 보낸 쪽지(mail_files 전부 · 계보 글자 선거름)의 «#N 확인/회신/수령/적용/답» 참조 seq = 닫힘 · 남의 좌석(desk·팀장) 참조 0(R326 «자기 큐만» 과 같은 방향) · 인자 없이 부르면 옛 식 그대로(test_inbox_waive ⓕ 전 조합 0). «답» 은 카드 4낱말 밖 — 실 planner 발신 «#117757 답» 꼴 실측으로 넣음.
- `ft_decision_count.py`: N = 질문표식 중 죽은 '#' 좌석이 아닌 것(죽은 좌석 질문 = «옛 좌석 미닫힘» 메모 · 실측 07:4x 37건 중 32건이 tmux 없는 좌석) · 팀 대기 = 현역 다른 팀 좌석 질문만 · ` · 묵은 M건`(M>0 일 때만 · 첫 줄 머리 «결정 인터뷰 N건 · 스크립트 M건» 불변 = planner-decision-line 훅·ft_news_ledger 그대로) · `--detail` = 현역 다른 팀 미닫힘 전부 + 이유 낱말(질문표식 → 묵음 → 통보 순) · AUTONOMY-QUEUE 자리에 파일 없음 = 0행 메모 0(리졸버 실패만 rc4). 199줄.
- 시험 `tests/scripts/test_decision_count_truth.py`(새 · 7) — 표본 10건(새 질문 3 · planner 옛 세대 회신 닫힘 1 · 25시간 질문 1 · 통보 5) 「결정 인터뷰 3건 · … · 묵은 1건」 · desk 회신 = 닫힘 아님 · [완료·휴식] 팀 대기 0 · 죽은 좌석 질문 메모 · 큐 파일 없음 메모 0 · 본문 없음 rc4 · 로그 3만 줄 + 900행 ≤ 2.5 s. 고치기 전 7 FAIL(`harness/evidence/r337/before.txt`). 기존 `test_decision_count.py` 고정물: row() 기본 본문 = [결정] 질문 · put() 이 본문 파일을 씀 · make_env 분리 — 단언 변경 0.
- 실 공용 루트 읽기 전용(`real-root-smoke.txt`): 라이브 1.1.76 「팀 대기 1건(가장 오래 byz-planner-desk-claude#26 0분) (옛 좌석 미닫힘 37) (AUTONOMY-QUEUE 파일 없음)」 → 이 판 「팀 대기 0건 · 묵은 8건 (옛 좌석 미닫힘 1)」 (desk [틱] 통보) · 2.6~3.4 s(예산 5 s).
- 설치: 키트 3(`ft_decision_count.py` · `ft_inbox_core.py` · `ft_decision_kind.py` 새) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 3 · 홈 0 · plist 0 · 되돌림 = `.bak-r337`.
- 범위 밖(따로 단위): `test_flag_off_scan.sh` ⓜ(ft-land → ft-sheet-events 루트 풀이 · 팩 체크아웃에 `.fable-team/LIVE_BIN` 없음) FAIL 3 — origin/main 77efe21b 판 파일로도 같음(`flag-off-scan-base-origin-main.txt`).

## 2026-10-20 — 상향 좌석 «▶내릴 것» 카드 상태 = 데이터 루트 · 공용 루트 · ref origin/main 세 자리 중 가장 앞선 것 (r518 · 1.1.76)

- 사건: 틱 `raised_watch` 의 판정기 `ft_raised.py card_state` 가 카드 실재를 `--root`(= 공용 루트 · 체크아웃 main 51881ba2e4 · 2026-09-23 · `design/teams/` 없음) 한 곳에서만 찾아, v6 라이브 워크트리 «진행» 에만 있는 v65 카드 2장의 상향 좌석을 «(카드 없음)» → master 에 «▶내릴 것» 오탐(v65 master 쪽지 119019 · 틱 쪽지 119017 · harness master 83 발주 119026 ② · arch 106 실측). r515·r517 과 같은 뿌리(공용 루트 체크아웃 옛 판을 정본처럼 읽음).
- `ft_raised.py card_state(root, card, data)`: 자리 3 = 데이터 루트(`ft_team_lib.data_root` · r515 — FT_ROOT → 공용 루트 LIVE_ROOT 1행 → 공용 루트) 체크아웃 · `root` 체크아웃 · ref `origin/main`(`git -C root cat-file --batch-check` 1회 · 7초 상한) · «완성 > 진행 > 대기» 중 처음 맞는 것 · 셋 다 0 = «없음». «내릴 것» 기준(완성·없음) 변경 0 · `ft-tick.sh` 호출 인자·출력 꼴 변경 0.
- 못 읽음 = rc2(조용한 «없음» 0): ref 못 읽음(리포 아님·origin 없음·7초 초과·batch-check 실패) · LIVE_ROOT 가 절대경로 폴더 아님 · `ft_team_lib` import 실패. LIVE_ROOT 파일 없음(FT_ROOT 도 없음) = 데이터 루트 = 공용 루트(r515 규칙)로 판정하고 «▶내릴 것» 줄 끝에 « · 못 본 자리: 데이터 루트(LIVE_ROOT 없음 <경로>)» — 카드 시험 입력 ⓓ 의 «경고 1줄» 을 stderr 가 아니라 줄 꼬리로 낸 편차: 틱이 `2>&1` 로 받고 rc0 이면 출력 전체를 목록으로 세므로(rc0 stderr 경고 = 가짜 좌석 1건 · 서명 흔들림) 목록이 없을 때는 표기도 0.
- `ft_team_lib` import 는 `check` 경로 안(지연) — `is-raised` 만 부르는 spawn 시험들의 임시 bin(ft_raised.py 만 복사)은 그대로 동작.
- 시험 `test_raised_card_state_three_places.sh`(새 · 임시 공용 루트 C(카드 폴더 없음) + LIVE_ROOT = 임시 데이터 루트 D + 임시 bare origin · 외부 호출 0 · GIT_* env 0) ⓐ~ⓕ 38 PASS(ⓕ = 틱 실경로 쪽지 0 · 진짜 완성 경보 1) · 고치기 전 FAIL 16(`harness/evidence/r518/before-fix.txt` · ⓐ 오탐·틱 쪽지 1 재현) · 변이(데이터 루트 자리 제거) FAIL 2(`mutation-no-data-root.txt`). 기존 시험 보정 1: `test_raised_seat.sh` — 판정 폴더 3곳(ck·dup·td)에 빈 커밋 + origin/main ref(ref 트리 0 → 판정은 디스크 그대로) · 임시 bin 에 `ft_team_lib.py` 복사 · 단언 변경 0. 실 공용 루트 읽기 전용: 라이브 1.1.74 «▶내릴 것 ft-v65-temp-m5-1943-r7a-fix3-r8-ghost-verdict-notice#0 … (카드 없음)» 1줄 → 이 판 0줄(`real-root-smoke.txt`).
- 설치: 키트 1(`ft_raised.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0 · plist 0(틱은 다음 실행부터 새 판) · 되돌림 = `.bak-r518`.
- 범위 밖: 공용 루트 체크아웃 갱신 · 명부 «카드 워크트리» 칸 · 같은 꼴(공용 루트 체크아웃을 정본처럼 읽는) 도구 전수 스캔(arch 제안 후보).

## 2026-10-20 — 하네스 팩 나노 작업 폴더 자리 = <팩>/.worktrees/<키> (r519 · 1.1.75)

- 사건: 팩 작업 폴더 자리를 정한 곳이 없어 r517 나노가 세션 스크래치(`/private/tmp/…/scratchpad/afp`)에 팩 워크트리를 만들었고, `ft-nano-close.sh` 팩 모드(r508 · `--wt` = 팩 `.worktrees/` 아래만)가 2회 REJECT(harness master 83 발주 119026 ①). 닫기 기준을 넓히지 않고 «만드는 자리» 를 정한다(arch 106).
- `ft-nano-spawn.sh`: `pack_wt_line <카드> <키> <브랜치>`(새) — 카드에 `- 설치: 있음`(하네스 카드)이면 첫 발주문 끝에 «★팩 작업 폴더 = `${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}/.worktrees/<키>` (`git -C <팩> worktree add … -b <브랜치> origin/main` · 세션 스크래치 0 — 닫기 = `nano-close --wt … --branch …`)★» 1줄 · dry-run 에도 `BODY+` 로 출력 · 그 밖 카드 = 출력 0.
- `ft-nano-close.sh`: `_pack_move_hint`(새) — ⓐ REJECT 대상 `--wt` 가 팩 «등록» 워크트리인데 표준 자리 밖이면 같은 REJECT 줄 끝에 « · 표준 자리 밖 — `mkdir -p <팩>/.worktrees && git -C <팩> worktree move <옛> <팩>/.worktrees/<키>` 뒤 같은 명령(--wt …)» (키 = `--branch` 의 `nano/` 뒤) · 판정(REJECT)·닫기 기준 변경 0 · 팩 미등록 폴더는 덧말 0. `mkdir -p` 는 팩 `.worktrees/` 가 없으면 `worktree move` 가 실패해서(시험 ⓓ 실측).
- 시험 `test_pack_nano_worktree_place.sh`(새 · 임시 리포 2개 + 가짜 tmux · spawn 은 함수 추출 · 외부 호출 0 · GIT_* env 0) ⓐ 하네스 카드 줄·기본 팩 경로 ⓑ 제품 카드 0줄 ⓒ 스크래치 꼴 등록 워크트리 REJECT 그대로 + 덧말 · 미등록 폴더 덧말 0 ⓓ 덧말 명령 «그대로» 실행 → 같은 명령 CLOSED(mode=pack-wt) = ALL PASS · 고치기 전 FAIL 10(`harness/evidence/r519/before.txt` · ⓓ CLOSED 는 그때도 PASS = 팩 모드 그대로).
- 설치: 키트 2(`ft-nano-spawn.sh` · `ft-nano-close.sh`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 홈 0 · plist 0 · 되돌림 = `.bak-r519`.

## 2026-10-20 — 결정 셈 planner 표(MERGE-QUEUE·FLAG-DECISIONS) = ref origin/main 명단 + ref 본문 (r517 · 1.1.74)

- 사건: `ft-decision-count.sh` 가 planner 표 자리를 «루트(공용 루트) 체크아웃의 `design/TEAMS.md`» 로 풀어, 공용 루트 체크아웃(main 51881ba2e4 · 2026-09-23 · 명단 없음)·v6 어느 cwd 에서 불러도 `ERROR … 팀 명단 없음 … design/TEAMS.md` rc4(planner 쪽지 118922 · harness master 83 발주 118925 · arch 106 실측). 발주의 «실패인데 rc 0» 은 재현 0 — 도구 rc = 4 · 0 은 `| tail` 파이프 끝 rc.
- `ft_team_lib.team_doc_ref(root, team, name, ref)` (새 · 셸 `ft_team_doc_ref` 의 ref 쪽 · 임시 파일 0): ref 명단 후보(`_cands_ref` · 명단 꼴 먼저)마다 `<ref>:<후보>/<name>` 이 ref 트리(`ls-tree`)에 있으면 `git show` 본문 · 모두 없음 = None · 명단 못 읽음·팀 없음·git 실패·리포 밖 후보(꼴3) = TeamPathError(조용한 None 0 · 체크아웃 명단·옛 경로 후퇴 0).
- `ft_decision_count.table()`: 자리 = env 파일(그대로) → `at`(AUTONOMY-QUEUE · r515 `planner_queue` 그대로) → 카드 워크트리 디스크(그 워크트리에 명단이 있을 때 · 미착지 최신 행 · 먼저) → ref 본문(`FT_TEAMS_REF` · 기본 origin/main). 표 «내용» 판정 규칙(칸·대기 셈·손상 rc4) 변경 0 · 못 읽음 = ReadError rc4 그대로. 파일 200줄 그대로(test_flag_off_scan 상한).
- 시험 `test_decision_count_tables_ref.sh`(새 · 임시 리포 체크아웃 = 옛 커밋(명단 없음) · origin/main = 새 꼴 명단 + `design/teams/planner` 표 · 외부 호출 0 · GIT_* env 0) ⓐ 공용 루트·다른 리포 cwd rc0 + 대기 1 · ⓐ2 카드 워크트리 표 먼저 ⓑ FLAG-DECISIONS ref 본문 · 머리 손상 변이 rc4 ⓒ ref 에 표 없음 = 메모 + rc0 ⓓ origin 없음 = rc4 «명단 ref 못 읽음» ⓔ env 지정 = 그 파일 = 17 PASS · 고치기 전 FAIL 12(`harness/evidence/r517/before-fix.txt`). 기존 시험 2개 보정(git 밖 임시 루트 → 표 자리 env 고정): `tests/scripts/test_decision_count.py` run() `FT_DECISION_FLAG_DECISIONS` · `test_flag_off_scan.sh` count() `FT_DECISION_MERGE_QUEUE`·`FT_DECISION_FLAG_DECISIONS`. 실 공용 루트·v6 cwd 읽기 전용 실행: 라이브 1.1.73 rc4 → 이 판 rc0(`harness/evidence/r517/real-root-smoke.txt`).
- 설치: 키트 2(`ft_decision_count.py` · `ft_team_lib.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 2 · 홈 0 · plist 0 · 되돌림 = `.bak-r517`.
- 범위 밖: 셈 분모(r337 — 실 MERGE-QUEUE 27행 중 «대기» 로 시작하는 행 0 · 상태값 «⏳ 아침 큐» 등) · 공용 루트 체크아웃 갱신 · `seats-planner.json` 위치 · 원장 VERDICTS 읽기.

## 2026-10-20 — 오빠 큐 자리 리졸버 1개 + card-start 카드 상대경로 cwd → ref 읽기 (r515 · 1.1.73)

- 사건: `ft-proxy-decide.sh` 가 오빠 큐(AUTONOMY-QUEUE) 줄을 «데이터 루트(LIVE_ROOT = v6-realtime-live 워크트리) 체크아웃의 옛 명단» 으로 푼 `design/planner/AUTONOMY-QUEUE.md` 에 씀(정본 = main `design/teams/planner/` · v6 가지엔 새 폴더 없음) · `--card` 상대경로를 cwd 에서만 찾아 «카드를 못 읽음» 으로 QUEUE(planner 쪽지 118583 · 05:55 loom l3c card-start 2회 · `v6-realtime-live/design/planner/AUTONOMY-QUEUE.md:63`) · 같은 큐를 읽는 `ft-autonomy.sh`·`ft_decision_count.py` 도 같은 옛 자리.
- `ft-team-lib.sh` `ft_planner_queue <루트>` (새 · 파이썬 짝 `ft_team_lib.planner_queue`): `FT_PLANNER_DIR` 있으면 그 폴더 · 없으면 ref(`FT_TEAMS_REF` · 기본 origin/main) 명단 꼴 planner 폴더가 루트에 실재하면 그 폴더 · 실재 0(이동 전 가지 체크아웃)이면 공용 루트 `.fable-team/state/planner/AUTONOMY-QUEUE.md` · ref 명단 못 읽음·공용 루트 못 풂 = ERROR rc1(옛 체크아웃 꼴·쌍둥이 후퇴 0 — `ft_team_in_ref` 는 실재 쌍둥이 1개면 옛 꼴을 돌려주므로 쓰지 않고 «명단 꼴 후보 1번» 만 본다). 파이썬 `ft_team_lib.data_root`(새 · 셸 `ft_data_root` 짝: FT_ROOT → 공용 루트 LIVE_ROOT 1행(절대경로 폴더 아니면 ERROR) → 공용 루트).
- 사용처 3: `ft-proxy-decide.sh` QUEUE = 리졸버(폴더는 쓸 때 만든다 · 판정 원장 VERDICTS 읽기는 그대로) · `ft-autonomy.sh` `queue_file` = 리졸버(status·off 의 큐 수·경로) · `ft_decision_count.py` AUTONOMY-QUEUE = `planner_queue(data_root(R))`(env `FT_DECISION_AUTONOMY_QUEUE` 우선 그대로 · 카드 워크트리 후보 0 · MERGE-QUEUE·FLAG-DECISIONS 그대로).
- card-start 카드: 절대경로 = 그 파일만(지금과 같음) · 상대경로 = cwd 에 있으면 그 파일 · 없으면 `git -C <루트> show <ref>:<경로>` 본문(임시 파일 0 · 변수) · 둘 다 없으면 QUEUE «카드를 못 읽음: <cwd 경로> · <ref>:<경로>».
- 시험 `test_proxy_decide_queue_card_resolve.sh`(새 · 임시 리포 main 새 꼴 + 옛 꼴 가지 워크트리 = 데이터 루트 · 외부 호출 0 · GIT_* env 0) ⓐ~ⓖ 31 PASS · 고치기 전 FAIL 10(`harness/evidence/r515/before-fix.txt` · ⓐ 옛 자리 쓰기 재현). 기존 시험 2개 보정: `test_team_literal_paths2.sh` 자율 3종(FT_TEAMS_REF=HEAD — 픽스처 origin/main ref 0) · `test_flag_off_scan.sh` 결정 셈(FT_DECISION_AUTONOMY_QUEUE — git 밖 루트).
- 설치: 키트 5(`ft-team-lib.sh` · `ft-proxy-decide.sh` · `ft-autonomy.sh` · `ft_decision_count.py` · `ft_team_lib.py`) → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 5 · 홈 0 · plist 0 · 되돌림 = `.bak-r515`.
- 범위 밖: v6 라이브 가지에 main 병합 · 옛 `design/planner/AUTONOMY-QUEUE.md` 기존 줄 이관(planner 손) · 큐 묶음 질문(r165) · 자율 중 질문 0(r291) · 셈 분모(r337) · nano-reopen 카드 읽기(cwd 그대로).

## 2026-10-20 — 하네스 시험 RED 8개를 «기존 RED» 로 두지 않고 원인 분류 → 시험 7 + 도구 1줄 (r509 · 1.1.72)

- 사건: 팩 origin/main 에서 RED 인 시험 8개(셸 6 · pytest 2)가 나노 증거마다 «기존 RED 제외» 로 밀려 왔다(harness master 82 발주 117070 · arch 105 분류 · 판정 1395). 분류 실측: 픽스처 누락 1 · 리포 분리·ref 명단 뒤 환경·배치 전제 5 · 낡은 대조 1 · 도구 결함 1.
- 시험(7 · 도구 0): ①`test_tick_line` — BYZ `tests/fixtures/tick_line/` 18파일을 `harness/fixtures/tick_line/` 로(시험 FX 경로 그대로 · `git show` · 내용 0 변경) · 픽스처에 가려 있던 14개 = 임시 bin 에 `ft-seat-status.sh` 만 복사(r504 판정 본문 `ft_seat_turn.py` → `ft_api_outage_util` 짝 누락) → `*.py` 같이 복사 ②`test_team_literal_paths2` 22개 — 린트 명단 = 시험이 만든 «전환 중» 명단(`FT_TEAMS_MD` · 팩엔 design/TEAMS.md 0) · 픽스처 리포에 origin/main ref · `FT_TEAMS_REF=HEAD`(R416 slots · r495 close 원장) · 제안서 판정 원장 = ref 트리(r492 — 옛 «v6 워크트리 폴더» 기대 폐기 · 두 꼴에 원장 = 추측 0 REJECT 단언 추가) · close 의 `ft-seat-reap.sh`(r448) 대역 · drift 키트 경로 = 팩 배치 · fail-closed 문구 = «ref 못 읽음» ③`test_ft_tick_master_seat` — `FT_TICK_RESUME=0`(죽은 좌석 감시는 R27 밖 · 실 tmux·자율 상태 읽기 0) ④`test_harness_root` ⓒ — 뉴스 틱 ⑥ 은 r484 부터 같은 bin 실 렌더러 → 가짜 렌더러 삭제 · 픽스처 `🔄` 줄 + `.fable-team/seats.json` · «ERROR 0» 단언이 Traceback 도 잡게 ⑤`test_news_tree_root` 대조 — «옛 판» = r489 직전 `86257c17` 고정(origin/main 은 이미 새 판) ⑥`test_team_tick_unify` ⓖ H2 = **시험** — r385 글자 치환이 `ft-tick-install.sh` 거부 패턴만 `harness/bin`·`harness/kit/fable-team/bin` 으로 바꾸고 시험은 옛 `scripts/fable-team-bin`(BYZ main 에도 없음) → 새 두 경로 거부 단언 ⑧`test_news_status_section.py` KIT = `harness/kit/fable-team/bin`.
- 도구(1줄): ⑦`ft_news_publish.py` `_KIT` = `harness-install/slack-mirror`(r385 뒤 없는 폴더) → `kit/slack-mirror`(bin·kit cmp0) · 설치본 없는 시험·개발 판에서 magazine_slack 못 찾던 결함 · 라이브는 `~/.hermes/scripts` 로 찾아 동작 변경 0.
- 시험: 대상 8개 고치기 전 FAIL 1·84·1·1·22·4 + pytest 2 → 뒤 전부 rc0(origin/main 93f3dcca 병합 판) · 원문 `harness/evidence/r509/tests-rc-target8.txt` · 기존 시험 전체(셸 246 + pytest · 부하로 85번째 뒤 정지 → 이어 실행) = 이 단위 밖 RED 셸 64개 중 62개 main 93f3dcca 와 같은 rc·FAIL 수 · 2개(goal_table_gate·wt_clean_two_stage)는 병합 판 재실행 rc0 · pytest 104 failed 전부 main 에도 있음(main 106 = 104 + 이 단위가 고친 2) · 내 판에만 있는 실패 0 — 원문 `harness/evidence/r509/baseline-compare.txt`·`tests-rc-all.txt` · 밖 RED 는 r481(7) 과 별도 고침 단위 후보. 설치: LIVE_BIN 키트 1(`ft_news_publish.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 이 커밋 revert(설치본 `.bak-r509`).

## 2026-10-20 — 범위 분류표: 낱말 금지(과금·키)는 문서 줄 아래 · 경로로 지정한 문서 금지만 위 (r514 · 1.1.71)

- 사건: 자율 범위 분류기 BYZ 내장표(`autonomy_scope_rules.py` · 위에서부터 첫 일치)에서 낱말 금지 줄(과금 `billing|credit|payment|pricing|toss|subscription` · 키 `credential`)이 문서 줄 `^(design|docs)/.*\.md$` 위에 있어, 이름에 그 낱말이 든 문서만 바꾼 PR 이 FORBID — BYZ PR 2143(`docs/architect/CFO_BILLING_SOVEREIGNTY_ARCHITECTURE.md` 1파일) → `SCOPE-REJECT FORBID kind=billing`(planner 쪽지 118375 · master 82 발주 118379 · arch 106 실측: BYZ origin/main design·docs 아래 .md 중 같은 꼴 398개).
- `kit/fable-team/bin/autonomy_scope_rules.py`(bin cmp0): billing 줄 → 경로 `^docs/architect/COST_BASE_TABLE\.md$`(문서 줄 위 그대로) + 낱말(문서 줄 아래 · code 줄 위) · key 줄 → 경로 `^secrets/|….env…|\.cred$`(위 그대로) + 낱말 `credential`(문서 줄 아래). ddl·deploy·deps·global-rule·docs·code 순서·정규식 그대로 · 분류기·팩 표 tsv 변경 0. 코드 파일은 문서 줄에 안 맞으니 지금처럼 낱말 줄에 걸린다.
- 시험 `test_scope_classify_keyword_docs.sh`(새 · 임시 리포 · 외부 호출 0 · GIT_* env 0): ⓐ 낱말 문서 → CLASS docs ⓑ `gateway/billing/x.py`·`design/billing/x.py`·`docs/payment.sh` → FORBID billing ⓒ 문서+코드 → FORBID billing(코드 경로) · 변이(문서만) → docs ⓓ COST_BASE_TABLE.md → billing · CLAUDE.md·`.claude/`·COMM-GUIDE → global-rule ⓔ `design/x/credential-rotation.md` → docs · `shared/credential_store.py`·`secrets/a.json`·`docs/x.cred` → key + 분류표 순서 검사 = 19 PASS · 고치기 전 FAIL 6(`harness/evidence/r514/before-fix.txt`). 기존 `test_autonomy_scope_classify.sh` f5(`design/billing-notes.md` → FORBID) 는 이 변경이 바꾸는 꼴 그대로라 f5 = 코드 경로 FORBID + f5b = 문서 docs 로 나눔. 실데이터 = BYZ origin/main 낱말 문서 398 → docs 398 · 그 밖 낱말 경로 1747 → code 0(`byz-main-paths.txt`).
- 설치: 키트 1 → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0 · plist 0 · 되돌림 = `.bak-r514`(분류표 줄 순서 원복).
- 범위 밖: «*.md 전부 docs»(원가 정본·규칙 문서까지 풀림) · 루트 *.md(지금처럼 code) · `.env` 경로 줄이 `x.environment.md` 같은 문서 이름에 맞는 꼴(실측 0 · 별 카드 후보) · 학습 키(--learned).

## 2026-10-20 — DA 용 codex 래퍼: 헤드룸 «건너뛰기» 헤더로 본문 접힘 0 (r513 · 1.1.70)

- 사건: codex 는 전역 `~/.codex/config.toml` `model_provider = "headroom"`(127.0.0.1:8790)을 타고, 헤드룸 0.33.0 은 큰 `/v1/responses` 요청 본문을 «캐시 참조»로 접는다(`proxy.log:3664` 1093262→934768 bytes). 원문 조회 `headroom_retrieve` 는 DA 의 `approval_policy = "never"` 가 거부(«MCP tool call requires approval, but approval policy is never») → DA 가 본문 대조 0 으로 «검증 불가» HOLD · 라운드 1회 소진(ops org-pick DA② r3 · arch 106 실측 · master 82 발주 118143).
- `kit/fable-team/bin/ft-da-codex.sh`(새): `--cwd <폴더> --prompt-file <파일> --out-dir <폴더> [--model gpt-6.1-sol] [--effort high]` → `codex exec --skip-git-repo-check -C <cwd> -c model=… -c model_reasoning_effort=… -c 'model_providers.headroom.http_headers={"x-headroom-bypass"="true"}' "<머리말>\n<프롬프트>" < /dev/null` 전경 실행(백그라운드 0). 경로(8790→8317)·계정 회전·모델 그대로 · 헤드룸은 `Responses passthrough reason=bypass_header mutation=disabled`(arch 106 실행 시험 `proxy.log:3677`). 출력 = `<out-dir>/da-<YYYYmmdd-HHMMSS>-<pid>.out` 실행마다 새 이름(있으면 `-<n>` 덧붙임 · 덮어쓰기 0 — 10-20 chatbot «판정 파일 덮어씀» 계열 차단) · stdout+stderr 함께(실행 헤더 `model:`/`provider:` 두 줄 보존) · 끝줄 `OUT <경로> rc=<n>` · rc = codex rc. 머리말 1줄 «파일은 sed -n 으로 400줄 이하씩 나눠 읽는다 · 본문을 못 봤으면 HOLD 대신 «검증 불가 — <파일:줄>» 로 적는다»(codex 자체 도구 출력 잘림 — 216 KB cat 중간 줄 UNREADABLE, 헤드룸과 무관). 프롬프트 파일 없음·빈 파일·`--cwd`/`--out-dir` 없음·모르는 인자 = rc2 + 사유(codex 0 · 출력 파일 0).
- 시험 `test_da_codex_wrapper.sh`(새 · PATH 앞 가짜 codex · 외부 호출 0 · 헤드룸 0 · GIT_* env 0): ⓐ 인자(bypass 헤더 · sol · high · `--skip-git-repo-check` · `-C` · stdin 0 바이트) ⓑ 새 파일 이름·두 번 실행 = 파일 2개·헤더 두 줄·끝줄 ⓒ 머리말 첫 줄 + 원문 둘째 줄 ⓓ `--model`/`--effort` 덮어쓰기 · 없음/빈 파일/`--cwd` 없음 rc2 ⓔ codex rc7 → 래퍼 rc7 + 파일 남김 · `&` 0 · 느린 codex 끝난 뒤 래퍼 종료 = 25 PASS(bash5 + /bin/bash 3.2) · 고치기 전 FAIL(`harness/evidence/r513/before-fix.txt`) · shellcheck rc0(래퍼) · tmp-trap-lint PASS.
- 설치: 키트 1 → `install.sh --apply --project <루트>` → LIVE_BIN cmp0 1 · 홈 0(지침 1줄 = 착지 뒤 arch 손) · plist 0 · 되돌림 = 래퍼 대신 옛 `codex exec` 1줄.
- 범위 밖: 헤드룸 설정·기동 인자 · 전역 `~/.codex/config.toml`(일반 codex 작업은 압축 그대로) · 승인 정책 완화 · 시간 상한 추가·변경 · DA 좌석 정의 파일.

## 2026-10-20 — 공용 루트 설치가 등록 워크트리의 연결 파일(shim) LIVE_BIN 도 새 판으로 (r512 · 1.1.69)

- 사건: `install.sh --apply --project <공용 루트>` 는 공용 루트 `.fable-team/LIVE_BIN` 만 바꾸고, 연결 파일은 «자기 워크트리 ../LIVE_BIN» 1줄을 읽어 자기 LIVE_BIN 을 가진 워크트리는 옛 판으로 돌았다(arch 106 실측 04:2x · 16곳 중 12곳 1.1.49~1.1.64 · v6-realtime-live 는 설치마다 master 손 보충 · master 82 발주 117810).
- `harness/install.sh`: 공용 루트 shim 단계 «뒤» `wt_shim_refresh` — `git worktree list --porcelain` 중 공용 루트 아님 ∧ `<wt>/.fable-team/LIVE_BIN` 실재 ∧ bin 에 머리 2줄 `# ft-root-bin-shim:` 파일 1개 이상인 워크트리마다 같은 설치본 `ft-root-bin-shim.sh --root <wt> --live <새 bin> --repo --path --ref`(같은 키트 트리) → LIVE_BIN 갱신 + 새 도구 이름 연결. 줄 = `REFRESHED wt-shim <wt> <옛> -> <새> · SHIM …` / `OK wt-shim <wt> (같음)` / `SKIP wt-shim <wt> (shim 아님|폴더 없음)` / `ERROR wt-shim <wt> rc=<n>: …` · 끝줄 `WT-SHIM refreshed=N skip=M fail=K` · K>0 = 다음 워크트리 계속 + 끝 `INSTALLED <v> · WT-SHIM ERROR — LIVE_BIN 전환은 끝났다 …` rc1(조용한 통과 0). dry-run = `PLAN wt-shim <wt> <옛> -> <새>` + `WT-SHIM plan=N skip=M` · 쓰기 0. 워크트리 `--project` 설치 = 순회 0. 옛 통째 사본 bin 은 손대지 않는다(이동 0 · install-check STALE-COPY 그대로).
- 카드와 다른 점 1: `--live-root` 는 워크트리에 LIVE_ROOT 파일이 «없을 때만» 공용 루트로 준다(있으면 인자 0 = 보존) — shim 도구는 인자가 없으면 라이브 bin/../.. 를 데이터 루트로 적기 때문.
- 시험 `test_install_worktree_shim.sh`(새 · 임시 리포 C + W1 shim · W2 옛 사본 · W3 없음 · 임시 HOME · 가짜 launchctl): ⓒ dry-run PLAN 1줄·쓰기 0 ⓐ W1 LIVE_BIN = B · 새 이름 연결 · LIVE_ROOT 보존 · `refreshed=1 skip=1 fail=0` ⓑ W2 바이트 그대로·stale 0·W3 변화 0 ⓔ 두 번째 `refreshed=0`·쓰기 0 · `--project W1` 순회 0 ⓕ 폴더 없는 워크트리 SKIP ⓓ W1 bin 읽기 전용 → `ERROR wt-shim W1 rc=3` + 끝 rc1 · 공용 루트 전환 끝 = 34 PASS(bash5 + /bin/bash 3.2) · 고치기 전 FAIL 16(`harness/evidence/r512/before-fix.txt`). 기존 install 시험 6 rc0 · `test_live_install.sh`·`test_harness_root.sh` ⓒ 는 base(origin/main) install.sh 로도 같은 FAIL(이 변경과 무관 · 원문 `tests-rc.txt`). 실 공용 루트 dry-run = `WT-SHIM plan=18 skip=0` · 옛 판 11(`dry-run-common-root.txt`).
- 설치: 설치기 1(키트 밖) → 다음 `install.sh --apply --project <공용 루트>` 부터 · LIVE_BIN 지도 cmp 대상 0 · 홈 0 · plist 0 · 되돌림 = 설치기 이전 판 + 워크트리 LIVE_BIN 1줄(REFRESHED 줄의 «옛» 값).
- 범위 밖: 옛 통째 사본 워크트리 정리 · 연결 파일이 공용 루트 LIVE_BIN 을 직접 읽게 바꾸기(별 카드 후보) · 다른 리포 루트.

## 2026-10-20 — nano-close --wt 팩 경로: 하네스 팩 나노의 ⑥·⑤·미커밋을 팩 리포 기준으로 대조 (r508 · 1.1.68)

- 사건: 하네스 팩 나노(작업 = `ai-feature-pack/.worktrees/<…>` · 카드 «세트:» = 팩 커밋)는 `ft-nano-close.sh` ⑥ 이 BYZ 쪽 같은 이름 워크트리(spawn base) HEAD 와 대조해 병합 뒤 항상 REJECT · `--wt` 명시 모드도 BYZ 등록 워크트리만 받아 팩 경로 거절 → 매번 `--suspended` 우회(r499·r502·r466 실사건 · harness master 82 발주 116983 · arch 105 실측).
- `ft-nano-close.sh`(kit↔bin cmp0): `--wt` ⓐ — BYZ 조건이 아니면 `FT_PACK_ROOT`(기본 `$HOME/Project/ai-feature-pack`)의 `.worktrees/` 아래 ∧ 그 리포 `worktree list` 등록이면 대조 리포 `SEAT_REPO` = 팩 · 카드 해석 뒤 머리 `- 설치: 있음`(하네스 카드) 아니면 지금 ⓐ REJECT 문구 + 덧말 «팩 경로는 하네스 카드(- 설치: 있음)만». ⓑ 브랜치·ⓔ 미커밋·⑥ 증거 줄(`--repo` = 팩 워크트리)·⑤ cherry(`--repo` = 팩 리포 · origin/main 재대조·fetch 포함)·feat fetch·base sha 조상 = `SEAT_REPO`(기본 `$ROOT` — 다른 경로 변화 0) · 팩 모드 feat 기본 = origin/main. 정리 계획 0 + `INFO 팩 워크트리 정리 = 별 경로` 1줄 · 원장 `mode=pack-wt wt=… branch=… repo=…`.
- 카드와 다른 점 2(실사건 꼴): ①pane cwd(ⓒ)는 BYZ 쪽 같은 좌석 표준 워크트리라 «--wt 또는 그 표준 워크트리» 를 받는다 ②spawn 이 BYZ 쪽에 같은 이름 워크트리를 만들어 «표준 전용 워크트리가 따로 있다» REJECT 가 늘 걸린다 — 팩 모드만 그 검사를 건너뛴다. `_fetch_remote_feat` 는 `${SEAT_REPO:-$ROOT}`(함수만 떼어 쓰는 `test_nano_feat_remote_ref.sh` 호환).
- 시험 `test_nano_close_pack_wt.sh`(새 · 임시 리포 R·P + P bare 원격 · 외부 호출 0) ⓐ 팩 경로 CLOSED(고치기 전 FAIL 8 · 뒤 PASS) ⓑ 제품 카드 → ⓐ REJECT ⓒ 미등록 폴더 → REJECT ⓓ 팩 미커밋 → ⓔ REJECT ⓔ 인자 없음 → BYZ HEAD 대조(변경 0) · 기존 `test_nano_close_*.sh` 8 rc0 · 관련 시험 7 = base 대비 새 FAIL 0(기존 RED 그대로). 증거 `harness/evidence/r508/`.
- 설치: 키트 1(`ft-nano-close.sh`) → LIVE_BIN cmp0 1 · 홈 0 · plist 0 · 되돌림 = `.bak-r508`.

## 2026-10-20 — push 게이트 새 가지 range = merge-base(origin/main, tip)..tip · 훅이 처음 키트에 들어옴 (r511 · 1.1.67)

- 사건: 문서 3파일 새 가지 첫 push 가 `PUSH_DENIED «range 에 제품코드»` → `FT_PUSH_DA6_OK` 우회 기록(v65 쪽지 117396 → planner 117419 → harness master 82 발주 117428). 원인: `pre-push:27-28` 새 가지(remote_sha 0)면 `range="$local_sha"` — `git diff --name-only <커밋>` 은 «그 커밋 ↔ 작업 트리» 라 미커밋 변경을 잡고(오탐) 올라가는 제품 커밋은 놓친다(누락 — 작업 트리가 깨끗하면 제품 커밋 가지도 통과). `:33` `2>/dev/null` 이 diff 실패를 «hits 없음 = 통과» 로 삼켰다.
- 훅이 처음 키트에 들어옴: `kit/fable-team/githooks/pre-push`(새 · 출발점 = 공용 루트 손 설치본 09-09 바이트 그대로 → 구조 커밋) — 설치하면(`install.sh --apply` GITHOOKS 줄) 공용 루트 판을 덮고 `pre-push.bak-<버전>` 을 남긴다. 정본 위치 = 팩 키트.
- 고침: 새 가지 `base=$(git merge-base origin/main "$local_sha")` · 비면 `PUSH_DENIED — 새 가지 기준(merge-base origin/main) 못 구함 — 거부 유지` rc1 · 있으면 `range="$base..$local_sha"` · diff rc≠0 = `PUSH_DENIED — range diff 실패 — 거부 유지` rc1(조용한 통과 0). 기존 가지 `remote..local`·`FT_PUSH_DA6_OK` 우회 기록·GATE_BRANCH·PRODUCT_PATHS 그대로.
- 시험 `test_pre_push_range.sh`(새 · 임시 bare origin + 클론 · stdin 직접 · push 0 · 가짜 bd): ⓐ 새 가지 문서 + 미커밋 gateway → 통과 ⓑ 새 가지 gateway 커밋 → 거부 + `range: <mb>..<tip>` · 우회 기록 ⓒ 기존 가지 문서 통과·제품 거부 ⓓ origin/main 없음·diff 실패 → 거부 ⓔ GATE_BRANCH 아님 → 검사 0 = 11 PASS(bash5 + /bin/bash 3.2) · 변이(옛 설치본) FAIL 7. shellcheck -S warning = 옛 줄 `:24` SC2034(local_ref·remote_ref) 만. 원문 = `harness/evidence/r511/tests-rc.txt`(고치기 전 = `before-fix.txt`). 기존 `test_evidence_log_gate.sh` ⓖ 기대값 = 키트 githooks 2개(`GITHOOKS copied=2`·2회째 `same=2`) + pre-push cmp0·실행 비트 1줄 · 병합 HEAD 재실행 = `merge-head-rc.txt`.
- 범위 밖: 다른 githooks(commit-msg·post-*·prepare-commit-msg) 키트 이관(같은 «손 설치» 꼴 — 별 카드 후보) · GATE_BRANCH 확장 · `--no-verify` 차단.

## 2026-10-20 — 뉴스 갈래 상한의 CLI 기동 고정비 = 잠정 3.5초 → 실측 p90 · 지도 실패 연속 3틱 = 고정 문구 «뉴스 지연» 1번 (r510 · 1.1.65)

- 사건: 부하 48~52 에서 뉴스 HTML 이 02:08 뒤 발행 0 — `/tmp/byz-ft-news-planner.log` «ERROR 지도 만들기 실패 — 발행 0: opencode run summary 실패(…): summary 상한 24s 초과(총 마감 70s)» 8회 연속(arch 105 자체 발견 · master 82 117315). 원인: 갈래 시도당 상한 `min(FIXED_S 3.5 + 7 × ceil(단위), 70)` 의 CLI 기동 고정비 3.5초가 «잠정값» — 부하 50 에서 `opencode run --standalone` 기동이 그보다 훨씬 길어 1차·재시도 둘 다 첫 출력 전에 상한 도달(성공 판에도 갈래 40~52초 = 재시도 성공이 이미 섞여 있었다).
- `ft_news_html_render.py`(kit↔bin cmp0): ①`_once` 가 stdout 첫 바이트 시각을 잰다(파이프 2개 읽기 스레드 · 프로세스가 끝나도 손주가 파이프를 쥐면 상한까지만 · 넘으면 묶음째 kill 그대로) ②시도마다 기동 기록 `<루트>/.fable-team/state/news-cli-startup.tsv`(env `FT_NEWS_STARTUP_LOG`)에 `시각\t갈래\t첫 출력까지 초` 1줄 · 시간 초과(출력 0) = `>상한`(하한값 — 다음 틱이 올려 잡는다) · 최근 20줄 · 쓰기 실패 = `WARN 기동 기록 못 씀 — 발행은 계속` ③`fixed_s()` = env `FT_NEWS_FIXED_S` › 기록 p90(nearest-rank) › 기록 3개 미만 = 잠정 3.5 · `cap_s(prompt, part, fixed)` = `min(fixed + 7 × ceil(단위), 70)` · 갈래 4개가 같은 값(호출 1회에 한 번 셈) ④`fixed ≥ 70` = stderr `WARN 기동 고정비 p90 <n>s ≥ 천장 70s — 갈래 상한 = 천장`. 천장 70초·재시도 1회(첫 출력 전만)·총 마감 70초 그대로(하드 룰 12 «CLI 기동 고정비를 따로 더하되 천장은 같다» 안 — 잠정값을 실측으로).
- `ft_news_html.py`(kit↔bin cmp0): «만듦» 줄에 `fixed=<값>s` · 틱의 지도 만들기 실패(모델 갈래 실패)가 연속 `FT_NEWS_DELAY_TICKS`(기본 3)틱이면 `publish_line` 으로 고정 문구 1번 «뉴스 지연 — 사유: <첫 실패 줄 120자> · 마지막 판 HH:MM(<직전 판 링크>) · 부하 <load1>»(정지 1건당 1번 · 발신 실패면 다음 틱 재시도 · 모델·판단·요약 0 · 상태 `<state>/news-delay.json`) · 다음 지도 발행 때 «뉴스 복구 HH:MM · 지연 N분»(N = 직전 판부터) · 지연 글을 안 냈던 짧은 정지는 조용히 지움. «재시도 대기» 틱은 셈 밖(시도 0).
- 시험: `test_news_html_cli_startup.py`(새) ⓐ 기록 0·2개 = 3.5 ⓑ 기록 10개 p90 = 4.5 · `FT_NEWS_FIXED_S=3.5` 이면 느린 갈래 두 시도 초과 · 실측 고정비면 성공 ⓒ p90 ≥ 70 = 상한 70 + WARN · 만듦 줄 `fixed=70.0s` ⓓ 시도마다 1줄·최근 20·시간 초과 `>1.8` 2줄·쓰기 실패 WARN + 발행 계속 ⓔ 고정비 60 이어도 총 마감 3초 안 · 재시도 0 ⓕ 실패 3틱 → 지연 글 1 · 4틱째 0 · 성공 → 복구 줄 1 · 2틱 정지 = 조용 = 9 passed · 변이(origin/main 판 2파일) FAIL 7. 기존 `test_news_html.sh`·`test_ledger_repo_sync.sh` rc0(픽스처 `oc` 에 기동 기록 tmp 격리 · 상한 대역 lambda 인자 1 추가). 원문 = `harness/evidence/r510/tests-rc.txt`.
- 설치: LIVE_BIN 키트 2(`ft_news_html_render.py` · `ft_news_html.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r510` 또는 env `FT_NEWS_FIXED_S=3.5`(옛 상한 · 지연 글은 `FT_NEWS_DELAY_TICKS` 를 크게).

## 2026-10-20 — 완성 이동의 정본 갱신 요청 쪽지 = 카드 팀 명부의 `_arch` 로(기본 v65 명부 고정 0) (r487 · 1.1.64)

- 사건: loom 카드 완성 이동(`design/teams/loom/indices/완성/loom-canon-plan-l1-l3.md`)의 «정본 갱신 요청» 쪽지 114386 이 v65 arch 264 에게 갔다(v65 arch 264 요청 114392 → harness arch 103 카드). 원인: `ft-index-move.sh:161` `SEATS="${FT_SEATS_JSON:-$ROOT/.fable-team/seats.json}"` — 주석은 «팀 현역 arch» 인데 env 가 없으면 기본 명부(= v65 `_label`)로 고정.
- `ft-index-move.sh`(kit↔bin cmp0): 쪽지 직전에 팀 해석 — 명단(카드 워크트리 `design/TEAMS.md`) 팀마다 `ft_team_has <팀> <카드 indices 폴더>/ indices/`(쌍둥이 둘 다) · 정확히 1팀 = 그 팀 · 명부 = `seats-<팀>.json`(v65 = `seats.json`) · `FT_SEATS_JSON` 명시가 이김. 0·2+ 팀 = `INFO 정본 쪽지 생략 — 팀 못 정함(명단 팀 N개 · <카드>)` · 명부 파일 없음 = `INFO 정본 쪽지 생략 — 팀 명부 없음(<팀>)` · 출력 `NOTIFIED 정본 갱신 요청 → <arch> (팀 <팀>[ · 명부 FT_SEATS_JSON])` · INFO(_arch 없음)·WARN(발신 실패) 줄에도 팀 글자. 이동·원장·종료코드 변경 0(게이트 아님) · 명부 쓰기 0 · v65 카드 수신자 그대로.
- 시험: `test_index_move_canon_route.sh`(새) ⓐ 팀 a 카드 → `seats-a.json` `A#1` · `V#1` 0 ⓑ `FT_SEATS_JSON` 명시 → `V#1` ⓒ 팀 b(명부 없음) → 쪽지 0 + INFO · 이동 rc0 ⓓ v65 카드 → `seats.json` `V#1` = 5 PASS(bash5 + /bin/bash 3.2) · 변이(origin/main 판) FAIL 4. 기존 `test_index_move_canon_landed.sh` 18·`canonize` 22·`rule_line` 17·`slack` 14 rc0 · shellcheck -S warning rc0. 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · 되돌림 = 설치본 `.bak-r487`. 원문 = `harness/evidence/r487/tests-rc.txt`.

## 2026-10-20 — nano-close --never-started: 발주를 한 번도 처리 못 한 나노(산출 0)를 «한 일 0» 4값으로 닫는다 (r506 · 1.1.63)

- 사건: loom g5a·g5b 정본 나노 #0 — 발주 116731 을 받고 처리 0 · `ft-nano-close.sh` 가 ①`--result` ②`--recv` ⑥증거 줄을 요구해 닫을 경로가 없었다(산출·회수 seq·증거 줄이 원래 없다). 좌석이 자원을 쥔 채 남는다(골 6).
- `ft-nano-never-started-check.sh`(새): ⓐ턴 0 — claude = 좌석명 jsonl 의 assistant(`<synthetic>` 제외) · opencode = opencode.db(`FT_OPENCODE_DB`) 읽기 전용 · session.directory == 워크트리 실경로(또는 아래) ∧ time_created ≥ `.worktree-info.json` created_at 의 assistant 메시지 · 세션→메시지 2단 질의 + 진행 처리기 7초 상한(통째 join 은 실 db 5GB 에서 7.3초 실측) · db 없음·잠김·스키마 다름·그 밖 에이전트 = 확인 못 함 ⓑbase(--base › 카드 base_sha › info base_sha) 위 커밋 0 ⓒ미커밋 0(`status -uall` · 노이즈 `.worktree-info.json`·`next-env.d.ts`·`tsconfig.json`·`.serena/project.yml` 제외) ⓓ발신 쪽지 0(mailbox.log.jsonl + .1) · `--successor-auto`(설계 r2 규칙 2·3): 같은 계보 더 큰 번호 좌석이 tmux 생존 ∧ pane toplevel == 워크트리 ∧ 명부 행 실재·`_replaced_by` 없음 → `SUCCESSOR <이름>` · ⓑⓒ 생략 · 못 셈 = `SUCCESSOR unknown` → 4값 전부.
- `ft-nano-close.sh --never-started "<사유>"`: ①② 면제 · ⑥ 자리 = 위 검사기 · ③ jsonl 없을 때 워크트리 mtime 후퇴 끔(공유 워크트리 후계 편집이 섞인다 · 유휴는 턴 0 이 대신) · 후계 있으면 ⑤ cherry·정리 계획 0 · 출력 `CLOSED <좌석> never-started «<사유>»` / `CLOSED <좌석> never-started (공유 워크트리 → 후계 <이름> · 워크트리 정리 0)` · 원장 ①② 칸 = 면제 표기 · 빈·여러 줄 사유·`--superseded-by`·`--suspended`·`--shared-wt` 동시 = usage 2 · 인자 없으면 불변 · 브랜치 삭제 0.
- 카드와 다른 점 1: 노이즈에 `.serena/project.yml` 추가(nano-close 기존 노이즈 · Serena activate 가 매번 고친다). 2: 검사기 인자 `--card`·`--comm`·`--seats` 추가(base_sha 출처 · 우편함 · 후계 명부).
- 시험 `test_nano_close_never_started.sh`(새) ⓐ~ⓝ(155 PASS) + 셀 수 없음 4 + usage 7 + 불변 · 기존 `test_nano_close*.sh` 7개 rc0 · `test_nano_close_suspended.sh` 숫자 검사의 `grep -n` 줄 번호(600) 오탐 제거(기대값 변경 0).
- 개정 r3 규칙 2b(`--landed-auto`): 후계가 없고 센 커밋이 0 이 아니면 `ft-landed-check.sh <리포> ${FT_NEVER_MAIN_REF:-origin/main} <가지> <키>`(7초 · perl alarm) rc0(ancestor·cherry·card)일 때 `LANDED <근거>` · 커밋 수만 생략(미커밋·턴·발신 그대로) · 같은 닫기(⑤·정리 계획 0) · 출력 `CLOSED <좌석> never-started (착지 가지 <근거> · 워크트리 정리 0)` · grep·no·판정 실패 = 적용 0. 0 커밋 가지는 늘 ancestor 라 2b 를 타지 않는다(기본 닫기·정리 계획 그대로).
- 실사건 실측(읽기 전용 검사기): loom #0 → r2 만으로는 `SUCCESSOR none`(후계 #1 이 먼저 닫힘) · `REJECT never-started: 커밋 8` → r3 뒤 `SUCCESSOR none · LANDED cherry · NEVER-STARTED ok turns=0 commits=skip(landed cherry) dirty=0 sent=0` rc0(1초).
- 설치: 키트 2(`ft-nano-close.sh` · `ft-nano-never-started-check.sh` 새) → LIVE_BIN cmp0 2 · 홈 0 · plist 0.

## 2026-10-20 — ft-tick shellcheck RED 고침: renamed_watch 명부 인자 = 배열+glob(ls 파싱 0) · SC1091 source 지시 (r507 · 1.1.62)

- 사건: 팩 시험 `test_ft_tick_passes_shellcheck`(shellcheck rc0 단정)가 RED 인 채로 r478·r479·r503 증거에 «기존 RED» 로 적혀 왔다(harness master 82 발주 116983 · arch 105 실측). 원인 2: ①`ft-tick.sh:444` `renamed_watch` 의 `$(ls "$(dirname "$SEATS")"/seats-*.json 2>/dev/null)` 따옴표 없는 명령 치환(SC2046 warning · r468 95fe73bb 가 넣은 줄 — 공백 있는 명부 이름이 쪼개진다) ②`:42` `. "$HERE/ft-harness-root.sh"` 의 SC1091(info) — info 도 shellcheck rc1 이라 ①만 고치면 시험이 계속 RED(카드 ⓐ 조건 실측).
- `ft-tick.sh`(kit↔bin cmp0): ①`local … f seatfiles=()` · `for f in "$(dirname "$SEATS")"/seats-*.json; do [ -e "$f" ] && seatfiles+=("$f"); done` → `"$RENAMED" watch "$MBOX" "$SEATS" ${seatfiles[@]+"${seatfiles[@]}"}`(bash 3.2 + `set -u` 빈 배열 안전 · 0개면 인자 0 — glob 글자 안 넘어감) ②`MBOX=…` 줄을 둘로 나눠 `[ -n "$MBOX" ] || { . …; }` 앞에 `# shellcheck source=/dev/null`(지시는 «다음 명령» 에만 걸려 한 줄 `a; b || {…}` 에선 `.` 에 안 닿음 · `source=ft-harness-root.sh` 는 -x 없이 여전히 SC1091 — 실측). 동작 변경 0.
- 시험: `test_ft_tick_renamed_args.sh`(새) — renamed_watch 함수만 떼어 가짜 RENAMED(argv JSON) · 명부 2개(`seats-a.json`·`seats-b c.json`) → 인자 2개 정확히 · 0개 → 인자 0 · bash5 + /bin/bash 3.2 = 6 PASS · 변이(origin/main 판) FAIL 3. `shellcheck ft-tick.sh` rc0 · `test_ft_news_ledger.py` 24 passed(shellcheck 시험 포함) · 틱 시험 `test_team_rename.sh` 86·`test_tick_shim_guard.sh` 26·`test_tick_team_msg.sh` 32·`test_board_publish_tick.sh` 14 rc0. origin/main 에서도 같은 수로 RED 인 시험 3(이 단위 밖 · 고침 단위 후보로 master 에 보고): `test_ft_tick_master_seat.sh` FAIL 4(dead_seat_watch `ERROR autonomy mode unreadable (none)`) · `test_tick_line.sh` FAIL 84(픽스처 `fixtures/tick_line/` 없음) · `test_team_tick_unify.sh` FAIL 1(ⓖ H2 `wt/scripts/fable-team-bin` 거부 안 됨). 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r507`. 원문 = `harness/evidence/r507/tests-rc.txt`.

## 2026-10-20 — 승계 은퇴 reap 이 press 서비스(gateway·worker)를 죽이던 결함 — reap 후보에서 서비스 나무 제외 (r505 · 1.1.61)

- 사건: v65 tester 72 은퇴 02:07:34 → 02:07:49 gateway·worker 동시 SIGTERM · tester 73 보고 «reap stopped=2 left=0» · press 회차 nf1·nf2 무효(v65 master 214 쪽지 116837). `ft-seat-retire.sh` 가 부르는 `ft-seat-reap.sh <구> --orphans-only` 의 후보 = uid 같음 ∧ ppid 1 ∧ exe ∉ PROTECT_EXE ∧ env FT_SEAT==좌석(②) — run.command 서비스는 nohup·& 로 떠 ppid 1 + 좌석 env 상속, venv 실행 파일 이름 `python` 은 PROTECT_EXE(`python3`) 밖이라 «감시 루프» 와 같은 모양으로 걸렸다.
- `ft-seat-reap.sh`: 조사마다 «서비스 나무» 를 만든다 — ⓐ`lsof -nP -iTCP -sTCP:LISTEN -Fp`(7 s 상한 · 실패 = rc 20 «조사 실패», rc 1 + stderr 0 만 LISTEN 0) 의 pid + 그 조상(ppid 사슬 · pid 1 앞까지) + 자손 → `service-listen` ⓑ명령 꼴 `SERVICE_RE`(`uvicorn|gunicorn|hypercorn` · `-m worker|gateway` · `next dev|start` · `next-server` · `run.command` · env `FT_REAP_SERVICE_RE` 로 덮기 · 정규식 오류 = rc 20) + 자손 → `service-cmd`. 후보(①②②b③)·자손 루프에서 서비스 나무는 빼고 앞 줄 `reap-skip pid=<n> why=service-listen|service-cmd cmd=<앞 100자>`(첫 조사에서 1회 · stopped·left 에 안 셈 · 끝 줄 형식 그대로). 모든 모드(은퇴 `--orphans-only` · seat-close · nano-close) 공통 — 서비스 정지는 `scripts/server/stop.command` 몫.
- 보호 exe 목록에 이름을 더하는 길은 안 썼다(venv 마다 python·python3·Python 으로 다시 샌다 · `ft-leak-reap.sh` PROTECT_EXE 변경 0). 파괴 경계: kill 대상을 줄이기만 한다(새 kill 0) · r448 루프 회수 그대로.
- 시험 `test_seat_reap_services.sh`(실프로세스 · 표식 r505fx-<pid> 고아만 · tmux 0): ⓐ venv python LISTEN 서비스(ppid 1 · FT_SEAT) 생존 + `why=service-listen` ⓑ LISTEN 없는 `python -m worker.x` 생존 + `why=service-cmd` ⓒ `bash -c 'while :; do sleep 1; done'` 정지 `stopped=1 left=0 rc=0` ⓓ 서비스 자식(bash sleep · FT_SEAT 상속) 닫기 경로에서도 생존 ⓔ `FT_REAP_SERVICE_RE` 덮기 → ⓑ 다시 후보 · 가짜 lsof rc2 → rc 20 + 아무것도 안 죽임 — 고치기 전 판 FAIL 9(서비스 `via=②` 로 정지 · 사건 재현) → 후 ALL PASS. 기존 `test_seat_reap_left0`·`test_seat_retire_keep`·`test_seat_retire_rosters`·`test_seat_close`·`test_nano_close_fail_closed` rc0 · `test_seat_retire` ⑧(`test_ft_tick_master_seat.sh` ft-tick ERROR 4)은 base 10a6a36b 에서도 같은 4 FAIL — 이 변경 무관(따로 보고). 증거 `harness/evidence/r505/`.

## 2026-10-20 — 좌석 턴 판정기 하나(`ft_seat_turn.py`) · 뉴스 HTML·지도 = 좌석별 하위 프로세스 0 (r504 · 1.1.60)

- 사건: 02:07 뉴스 지도에서 실좌석이 일하는 4팀(실통역·방·강의·계획)이 «확인 불가» — `ft_news_html.live_teams` 가 좌석마다 `bash ft-seat-status.sh turn <좌석>`(7초 · 재시도 1 · 풀 32)·`ft-news-tree.py seat_turn` 이 좌석마다 같은 셸(10초)을 부르고, 셸은 다시 좌석마다 폴더 jsonl 전부의 머리 1MB 를 읽고 파이썬을 띄웠다 → 부하 15~56 에서 상한 초과 + 동시 하위 프로세스 수십 개가 부하를 더 올림(arch 105 실측 · master 116770).
- `ft_seat_turn.py`(신설 · 122줄): `turn_of_file(path, tail_bytes, tail_start, master, status_only)` = `ft-seat-status.sh` heredoc 판정 본문을 그대로 옮김(동작 변경 0 · 판정 정본 = jsonl 턴 경계 그대로 · BOOT 18 덧말 0 — 판정기 위치만 모듈로) · `turns(seats, tmux, projects)` = r497 `find_jsonls` 1회(tmux list-panes 1회) + 좌석마다 꼬리만 읽기 · 못 찾음 = («?», «jsonl 없음») · 읽기 실패 = («?», «읽기 실패») · CLI `python3 ft_seat_turn.py <jsonl>` = 탭 5칸(env FT_SEAT_TAIL_BYTES·FT_SEAT_TAIL_START·MASTER·NEED_ENDS).
- `ft-seat-status.sh turn_of_file`: heredoc 대신 `python3 "$(dirname "$0")/ft_seat_turn.py"` — 출력 바이트 같음(시험 ⓔ: origin/main 판과 40석 × 5 플래그 바이트 대조).
- `ft_news_html.py live_teams`: `_turn`·`_turn_once`·ThreadPool·`SEAT_POOL` 삭제 → `_turns()` = `ft_seat_turn.turns` 1회(env `FT_TMUX`·`FT_CLAUDE_PROJECTS` = ft_model_swap 과 같음) · tmux list-panes 7초 초과 = 전 좌석 («?», «tmux 시간 초과») · 사유 칸 = «jsonl 없음 N석 · 읽기 실패 N석»(r490 `unknown_reason` 꼴 · «확인 불가 ≠ 쉼» 유지) · 298→281줄.
- `ft-news-tree.py seat_state`: 지도 1회에 `turns()` 한 번(살아 있는 명부 좌석 전부) 캐시 · UNKNOWN 과 «?»(jsonl 없음 — codex 등) 만 기존 `one` pane 판정(옛 turn 의 jsonl 없음 → pane 경로와 같음 · 10초 상한 그대로).
- 시험 `test_seat_turn_batch.py`(새) ⓐ~ⓔ + tmux 시간 초과 6 passed · 변이 1(PENDING→IDLE) = FAIL 3 · 기존 `test_ft_news_html.py` 38 · `test_ft_seat_turn_window.py` 8 · `test_ft_seat_codex.py` 10 · `test_kit_bin_sync.sh` · `test_news_html.sh` rc0. 기대 변경: `test_ft_news_html.py` r478c·r490 a·b 가 `_turn`(가짜 셸) 대신 `_turns` 를 바꿔치기 · r490 d(풀 32 시험) 삭제 — 풀이 없어졌다(대신 ⓑ «40석 < 7초 · list-panes 1 · seat-status 0»). 기존 실패(origin/main 과 같음): 셸 시험 5(tick_line 84 등) · pytest 3 — 원문 `harness/evidence/r504/tests-rc.txt`.
- 설치: LIVE_BIN 키트 4(`ft_seat_turn.py` 새 · `ft-seat-status.sh` · `ft-news-tree.py` · `ft_news_html.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 이 커밋 revert(설치본 `.bak-r504`). 범위 밖: `find_jsonls` 규칙 · 다른 호출처(틱·stall·reclaim)의 좌석별 `turn` 호출 · 판정 규칙 · `skill/scripts`·`comm` 의 옛 ft-seat-status 사본(이미 kit 와 다름).

## 2026-10-20 — 뉴스·매거진이 읽는 원장 사본을 매 회 origin/main 으로 전진 · 매거진 기본 원본 = 뉴스와 같은 사본·새 경로 (r503 · 1.1.59)

- 사건: desk 116740 → harness master 81 발주 116754 — 뉴스 사본 `.worktrees/news-ledger-main`(detached) 은 fetch·전진 주체가 없어 main 뒤 71커밋 · 01:50 원장 착지를 못 보고 «변화 없음» 3회(02:08 master 손 전진). 08:00 매거진은 기본값 `.worktrees/v6-realtime-live`(가지 위 · main 뒤 223) 의 옛 경로 `design/planner/PLAN-oppa-ledger.md`(마지막 10-19 18:55)를 읽는다 — 어느 쪽도 «낡았다» 신호 0. arch 105 실측(카드 Issue ①~⑤).
- `ft-ledger-repo-sync.sh <사본>`(새): 가지 위(symbolic-ref 성공) → `ERROR ledger 사본이 가지 <이름> 위 — 전진 0` rc3 · 추적 파일 미커밋 수정(`status --porcelain -uno`) → `ERROR ledger 사본 미커밋 추적 변경 N — 전진 0 (<첫 경로>)` rc3(미추적 = 뉴스 html 등은 깨끗함) · fetch = `fm_fetch`(ft-merge-lib · 7초 + 재시도 1) 실패 → `ERROR ledger 사본 fetch 실패: <첫 줄>` rc4 · 같으면 `SYNC up-to-date <10자>` · 아니면 `checkout --detach origin/main` → `SYNC <옛 10자>..<새 10자>` rc0 · 출력 1줄 · 삭제 0 · 되돌림 = `git -C <사본> checkout --detach <옛 sha>`.
- `ft_news_ledger.py`: `sync_repo()` — env `FT_LEDGER_REPO` 로 «명시된» 사본만 부름(기본 LIVE_ROOT 공용 체크아웃은 옮기지 않음) · 같은 틱 1회(`FT_LEDGER_SYNCED=1` · 자식도 물려받음) · `FT_LEDGER_SYNC` 로 대역 · 성공 = INFO `SYNC …` · 실패 = ERROR 로그 + `FT_LEDGER_SYNC_ERROR` · `_run` 시작에서 부르고 판 머리(lead) 앞에 «원장 사본 갱신 안 됨 — <사유>» · 발행은 지금 판으로 계속. `ft_news_html.py`: `tick` 이 그 사유를 지도 글 머리(`FT_NEWS_HEAD` 뒤)와 «변화 없음» 줄 꼬리에 싣는다 · CLI(`build`/`run`) 의 `_ledger_args` 도 `sync_repo()`.
- `magazine_from_news.sh`: 기본 `REPO=$ROOT/.worktrees/news-ledger-main` · `REL=design/teams/planner/PLAN-oppa-ledger.md`(뉴스와 같은 사본·경로) · 시작에서 `${FT_LEDGER_SYNC:-<LIVE_BIN>/ft-ledger-repo-sync.sh}` · 실패 → `ERROR magazine_from_news: 원장 사본 갱신 실패 — <출력>` exit 6(낡은 매거진 발행 0) · `FT_LEDGER_SYNCED=1` 이면 건너뜀.
- 시험: `test_ledger_repo_sync.sh`(새 · 임시 bare origin) ⓐ~ⓔ + usage + 공용 config 불변 rc0 · `test_ft_news_ledger.py` r503 4건(뉴스 sync rc3 → 발행 계속 + 머리 ERROR 줄 · 틱 1회·명시 사본만 · 매거진 sync rc3 → exit 6 / rc0 → 진행 · 매거진 기본값 = news-ledger-main + 새 경로) · `test_ft_news_html.py` r503 1건(지도 머리·«변화 없음» 줄 꼬리). 기존 기대 변경: 픽스처 원장 리포(가지 위 임시 리포)는 `FT_LEDGER_SYNCED=1` · 매거진 시험은 옛 경로 픽스처라 `FT_LEDGER_PATH` 명시 · `test_goal_table_gate.sh` 뉴스 호출 `FT_LEDGER_SYNCED=1`. 기존 RED 1(이 단위 밖): `test_ft_tick_passes_shellcheck` = SC2046 `bin/ft-tick.sh:444`(origin/main 과 diff 0). 설치: LIVE_BIN 키트 3 cmp0 + 홈 `~/.hermes/scripts/magazine_from_news.sh` cp+cmp 1 · plist 0(매거진 plist env 2칸은 카드 «지금 할 1줄») · 되돌림 = 설치본 `.bak-r503`. 범위 밖: `ft-weekly-review` 의 `FT_PLANNER_REPO=v6-realtime-live` · 사본 자동 생성. 원문 = `harness/evidence/r503/tests-rc.txt`.

## 2026-10-20 — 선제 회수가 launchd PATH 에서 tmux 를 못 찾아 «후보 0» 으로 조용히 끝나던 결함 (r502 · 1.1.58)

- 사건: harness arch 105 실측 01:5x — `.fable-team/state/reclaim.log` PREVENTIVE 줄 220개가 전부 `candidates=0` · 같은 시각 대화 셸 손 실행은 `candidates=23`. launchd `com.byz.ft-resource-watch`(plist env = `FT_RES_ROOT`·`FT_ROOT` 뿐)가 기본 PATH `/usr/bin:/bin:/usr/sbin:/sbin` 로 돌아 `/opt/homebrew/bin/tmux` 를 못 찾고, `tmux list-sessions … 2>/dev/null` 빈 출력을 «세션 0» 으로 읽었다 — 골 6 장치(압력 때 끝난 좌석 회수 · r500 압력 티어)가 설치 뒤 한 번도 자동으로 안 돌았다.
- `ft-resource-reclaim.sh`: ①머리(--on-reject 통과 분기 뒤)에서 `PATH="$PATH:${FT_RECLAIM_EXTRA_PATH:-/opt/homebrew/bin:/usr/local/bin}"` · `command -v tmux` 없으면 `ERROR tmux 없음(PATH=…)` rc4 ②`reclaim_core` 후보 수집: `tmux list-sessions` rc≠0 이면 stderr 를 다시 받아 `no server running` 만 세션 0 · 그 밖 `ERROR tmux list-sessions rc=<rc>: <stderr 첫 줄>` rc4(요약줄 0 → `ft-resource-preventive.sh` 가 stamp 0 + resource-watch.log `ERROR preventive rc=4 …` · 다음 틱 재시도). 닫기 직전 재확인(`fresh_att` 등)의 tmux 실패는 «후보 탈락» 그대로.
- `ft-resource-watch.sh`: set 직후 같은 PATH 덧붙임 1줄 — 표본·문지기·선제 회수 하위 호출 전부 같은 도구. plist(키트 밖 손 생성물) 수정 0.
- 카드와 다른 점 1: 카드는 PATH «머리» 에 붙이라 했으나 «끝» 에 덧붙인다 — 머리에 붙이면 대화 셸·시험에서 앞선 PATH 를 덮어(시험 가짜 `tmux`·`sysctl` 대역 폴더보다 `/opt/homebrew/bin` 이 먼저 → 시험이 실 tmux 서버를 부른다 · launchd 에서도 `/usr/bin` 의 python3·git 이 홈브루 것으로 바뀐다). 끝에 붙이면 없는 도구만 채운다(tmux·timeout/gtimeout). 시험 ⓓ 는 «PATH 끝 = EXTRA» 로 단언.
- 시험 `test_resource_reclaim_preventive.sh` r502 ⓐ(PATH=/usr/bin:/bin + EXTRA=가짜 tmux 폴더 → candidates=12)·ⓐ'(tmux 없음 → rc4)·ⓑ(list-sessions rc1 → ERROR rc4 · 요약줄·닫기 0 · 잠금 해제)·ⓑ'(preventive 보조 stamp 0 + ERROR 1줄)·ⓒ(no server running → candidates=0 rc0)·ⓓ(`env -i PATH=/usr/bin:/bin` tick → 선제 회수·표본이 받은 PATH 끝 = EXTRA · 미설정 = 홈브루 기본) + 변이 2(tmux 실패=세션 0 FAIL 5 · PATH 덧붙임 제거 FAIL 3) — 87 PASS · 기존 `test_resource_reclaim.sh` 107 · `_pressure.sh` 28 · `test_resource_watch.sh` 75 rc0. 설치: LIVE_BIN 키트 2 cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r502` 2 또는 `FT_RECLAIM=0`. 범위 밖: 다른 launchd 작업(ft-tick·뉴스·매거진) PATH 점검 · 회수 정책값 · r500 판정식. 원문 = `harness/evidence/r502/tests-rc.txt`.

## 2026-10-20 — 회수 압력 티어: swap ≥85% 면 착지 나노 idle 문턱 30→5분 · «병합 끝 나노» = 가지 착지 나노만 (r500 · 1.1.57)

- 사건: harness master 81 실측 115983 — swap 92% 인데 `ft-resource-reclaim` 이 «병합 끝 나노» 9~10석을 idle 30분 가드로 전부 SKIP(RECLAIMED 0) · spawn 문지기가 swap·rate 로 새 좌석을 막아 팀이 섰다. 같은 표에 방금 spawn 된 ops O3·O4(가지 미착지)도 «병합 끝 나노» 로 들어갔다 — 분류가 이름(`*-nano-*#0`)뿐. planner 80 대리 결정 115991.
- `ft-resource-reclaim.sh`: ①`measure_pressure`(한 실행 1번 · `FT_SWAPUSAGE`(시험) 또는 `sysctl -n vm.swapusage` used/total ≥ `FT_RECLAIM_PRESSURE_SWAP_PCT`(기본 85) · 측정 실패 = 압력 아님 + `WARN swap 측정 실패` 1줄) ②`idle_min_for`: 병합 끝 나노 ∧ (카드 완성/ ∨ 압력) → `DONE_IDLE_MIN`(5) ③분류: 이름 `*-nano-*#0` = «나노»(판정 전) → idle(착지 가정 문턱)·attached·보호 1차 거르기 통과분만 `landed_nano` — 가지 `nano/<키>` 또는 가장 큰 `-r<N>` · BYZ 루트와 팩 리포(`FT_PACK_ROOT`) 중 «가지가 있는 리포 전부» 가 `timeout 7 ft-landed-check.sh … origin/main` rc0 이어야 «병합 끝 나노» · 그 밖(grep·no·가지 없음·시간 초과·timeout 도구 없음) = «미병합 나노» → 닫기 0 · idle ≥ 30분이면 표 `HIL(승인 범위 밖: 미병합 나노 — 착지 판정 <근거>)` ④요약 줄 `RECLAIMED N …`·`PREVENTIVE …` 꼬리 `pressure=0|1 swap=<pct>%`(뉴스·감시자 파서는 앞머리만 읽어 영향 0). kit↔bin cmp0.
- 카드와 다른 점 1: 카드 §2 는 «BYZ 에 가지가 있으면 BYZ» 였으나, 하네스 나노는 BYZ 에 커밋 0 인 같은 이름 가지가 있어(이 좌석 실측: BYZ `nano/r500-…` = base c251017221 = main 조상) BYZ 만 보면 늘 ancestor(=착지) 로 읽힌다 → 두 리포 모두 rc0 일 때만 착지(fail-closed) · 시험 ⓖ.
- 시험 `test_resource_reclaim_pressure.sh`(새) ⓐ~ⓖ 28 PASS · 변이 2(압력 티어 제거 FAIL 3 · 착지 판정 제거 FAIL 8) · 기존 `test_resource_reclaim.sh` 107 · `_preventive.sh` 65 · `test_nano_spawn_teamset_cap.sh` 18 rc0. 기대 변경 2: attached 나노 표 종류 «병합 끝 나노» → «나노»(착지 판정 전에 거름) · PREVENTIVE 요약 줄 꼬리. 가짜 세계에 가짜 팩 리포(나노 a~h 가지 = main 조상) · `FT_SWAPUSAGE` 기본 10%(실 sysctl 0). 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · plist 0(선제 감시 600초) · 되돌림 = 이 커밋 revert(설치본 `.bak-r500`) 또는 env `FT_RECLAIM_PRESSURE_SWAP_PCT=101`. 범위 밖: 직전 세대·쉬는 역할 좌석 문턱 · `ft-resource-gate.sh` · nano-close 게이트. 원문 = `harness/evidence/r500/tests-rc.txt`.

## 2026-10-20 — 역할 좌석 모델 한도 → 틱이 대체 모델 후계를 자동으로 연다 + R146 모델별 복구 (r497 · 1.1.56)

- 사건: 00:12 harness arch 104(Fable 5.1) 가 «All credentials for model claude-fable-5-1 are cooling down … rate_limit_error» 합성 오류 턴(0초)으로 섰고 master 손 교대(arch 105 · Opus 5.5 · 쪽지 115865)까지 역할이 비었다. 같은 때 R146 은 ①복구 판정이 모델을 안 봐 다른 모델 좌석 하나가 일하자 «장애 끝 00:12 · 약 0분»(115762) + [재개](115763 — 같은 한도에 다시 막힘) ②감시가 틱 명부 1개뿐이라 seats-harness 등은 장애 쪽지 0.
- `ft_model_swap.py`(신설 · 180줄): 명부 «전체»(seats*.json)의 역할 칸(`_master`·`_arch`·`_desk`·`_da`·`_tester` … · `_hil_route` 제외) 현역 claude 좌석 ∧ tmux 생존 → jsonl 을 R146 `analyze` 로 판정(stuck ∧ rate_limit). jsonl 찾기 = `find_jsonls`(tmux pane cwd 인코딩 폴더 · 최근 2일 수정 파일만 · 머리 1MB 를 «한 번» 읽어 전 좌석 agentName/customTitle 대조) — 카드의 `ft-seat-status.sh jsonl`(좌석마다 폴더 jsonl 5989개 머리 전부)은 부하 30 실측 1회 10초라 7초 상한이면 역할 좌석 6석을 못 봤다 · 새 조회 = 실측 2.1초 · 역할 좌석 21/21 찾음 · arch 105 경로 seat-status 와 같음. 정지 < 3분(`FT_MODEL_SWAP_MIN`) 또는 `retry after` 해제 예상 ±3분 = WAIT · 오류 뒤 «같은 바탕 모델» 정상이 어느 좌석에든 있으면 RECOVERED(R146 [재개] 몫) · 이미 교대한 uuid·같은 계보 30분 = NOOP · 그 밖 = 대체 모델(`model-fallback.tsv` 다음 칸 · 그 모델도 최근 10분 같은 한도면 그다음 · 끝 = HIL) 로 `ft-successor-open.sh <구> <cwd> --name <베이스>#(최대+1) --agent claude --model <새> --ctx 1m --effort high --body-file <f>` 분리 실행(1회 1건 · 틱 안 막음 · 로그 `state/model-swap/<후계>.log`). 본문 첫 3줄 = 계보 최신 도달 파일(`state/successor/<베이스>#*.json` reached_at) seq 의 발주 본문 첫 3줄(골 원문) — 없으면 `HIL 골 원문 출처 없음`(교대 0 · fail-closed). 교대 직후 그 명부 `_master`·`_hil_route` 에 `[자동 교대] <구> -> <후계> · <구 모델> -> <새 모델> · 사유 한도`(오류 원문 0) · HIL 쪽지는 같은 uuid 1통. 상태 `state/model-swap/state.json`(손상 = ERROR · 교대 0). 옛 좌석 kill 0 · 원래 모델 복귀 0.
- `model-fallback.tsv`(신설): `claude-fable-5-1 → claude-opus-5-5[1m]` · `claude-opus-5-5 → claude-sonnet-5-5[1m]`(바탕 id = `[1m]` 떼고 비교).
- `ft_api_outage.py`: Cut 에 `model`(문구 `for model <id>`)·`eta`(retry after) · 정상 = (시각, 바탕 모델) — «장애 끝» 은 가장 최근 오류의 모델이 돌아온 때만(모델 미상 = 지금과 같음) · [재개] 는 제 모델이 돌아온 좌석만(아니면 stdout `SKIP 재개 … 복구 전`) · ft_model_swap 이 교대한 uuid(`--swap-state` · 기본 `<상태 폴더>/../model-swap/state.json`) 는 [재개] 0. 200줄 한도로 jsonl 읽기·판정 함수(`records`·`is_error`·`is_normal`·`epoch`)와 r497 보조(`model_of`·`eta_of`·`base_model`·`fallback_table`·`goal_source`·`jsonl_cwd`·`find_jsonls`·`next_name`·`read_table`)를 `ft_api_outage_util.py` 로. `CAUSES` rate_limit 에 «temporarily limiting requests|are cooling down» 추가.
- `ft-tick.sh`: `outage_watch` 뒤 `model_swap` — 명부가 `<루트>/.fable-team/seats.json` 일 때만(팀 틱 seats-<팀>.json 은 건너뜀 · 중복 교대 0) · PLAN·HIL·BUSY 줄은 틱 로그 · 실패 = ERROR 1줄 틱 계속 · `FT_MODEL_SWAP=0` 으로 끔 · `--dry-run` = `DRY kind=model-swap`.
- 시험: `test_model_swap.py` ⓐ~ⓘ + ⓑ2(jsonl 찾기: 3일 전 파일 무시 · 최신 파일 우선) + 틱 dry-run(공용 seats.json 만) + kit↔bin · `test_ft_api_outage.py` 틱 시험 2건 RED 수리(r459 뒤 comm 폴더 없는 임시 루트 → `FT_TICK_MBOX` 지정 · 기대값 변경 0). 설치: LIVE_BIN 키트 4(+ util 1) cmp0 · 홈 0 · plist 0(ft-tick 이 매번 부름) · 되돌림 = `.bak-r497` 또는 `FT_MODEL_SWAP=0`. 범위 밖: 원래 모델 복귀 · 옛 좌석 kill · 나노/codex/opencode 교대 · cliproxy 해제 시각 조회 · 팀 틱 5개 감시 통일. 원문 = `harness/evidence/r497/tests-rc.txt`.

## 2026-10-20 — 승계 후계 행이 옛 행의 `stop-ready` 를 물려받던 사슬을 끊음 (r499 · 1.1.55)

- 사건: harness master 81 발주 115727 — v65 arch 265 · chatbot arch 5 행이 현역(`_arch` 값)인데 role=stop-ready. arch 105 실측: `ft-seat-retire.sh` 가 후계 행을 «옛 role 글자» 로 만들어, 옛 행이 승계 «전에» 이미 stop-ready 였으면 후계도 stop-ready 로 태어난다(`_retired_role` 은 바꿀 때만 적어 비어 있음 → 다음 승계도 같은 값). v65 262→264→265 사슬 · master 손 정정 뒤 265→266 은 정상. 지금 명부 13 전수: loom `_arch`=arch 59 · ops `_arch`=arch 38 이 같은 꼴.
- `ft_roster_lib.py` 신설 3: `succ_role(o, cells, name)` = 옛 role(stop-ready 아니면 그 값) → 옛 `_retired_role` → 옮기는 역할 칸(`_master·_arch·_desk·_da·_tester·_pm` · keys 순) 이름 → 이름 토큰(`byz-<팀>-<역할>-<에이전트>#N`) · 다 없으면 stop-ready 그대로(추측 0) · `held_roles` · `fix_role`.
- `ft-seat-retire.sh`: 후계 행 생성·상속 모두 도출값 · 기존 후계 행이 stop-ready(∧ `_replaced_by` 없음)이면 도출값으로 고침 · 옛 행 `_retired_role` 은 지금처럼 «원래 role 이 stop-ready 가 아닐 때만»(없는 값 만들지 않음). 재실행(NOOP 자리)도 후계가 «역할 칸 값 ∧ role=stop-ready ∧ `_replaced_by` 없음» 이면 `.bak-retire-<ts>` 뒤 고치고 `FIXED <구> -> <후계> file=… … role stop-ready-><역할>` 1줄 rc0 · 그 밖은 출력 그대로. 승계 출력(RETIRED/FIXED) 첫 줄 꼬리에 ` role stop-ready-><역할>` 가 붙을 수 있다(정상 승계는 0). 200줄 상한 유지.
- 시험: `test_seat_retire_rosters.sh` r499ⓖ~ⓙ(+ ⓘ 대조 · ⓙ nano 음성) · 기존 ⓐ~ⓕ·r465 · `test_seat_close.sh` · `test_seat_retire_keep.sh` rc0. `test_seat_retire.sh` rc1 = ⑧ `test_ft_tick_master_seat.sh` 1건 — 변경 전 main(5779acde)과 PASS/FAIL 목록 동일(이 단위 밖). 설치: LIVE_BIN 키트 2(`ft-seat-retire.sh` · `ft_roster_lib.py`) cmp0 · 홈 0 · plist 0 · 되돌림 = 설치본 `.bak-r499`. 범위 밖: 역할 칸이 빈 값이 된 원인 · stop-ready 표기 주체(`ft-seat-close.sh`) · 역할 칸 값이 아닌 과거 행. 원문 = `harness/evidence/r499/tests-rc.txt`.

## 2026-10-20 — 뉴스 린트: 확인 불가 팀 «쉼» 판정이 부정 꼬리(«…지 않»·«아니»·«지 못») 문장은 통과 (r498 · 1.1.54)

- 사건: planner 뉴스 틱 발행 0(요청 115673) — `/tmp/byz-ft-news-planner.log` 2913~2915 «ERROR 린트 위반 2건 — 발행 0 (확인 불가 팀 lecture 에 쉼 단정 «lecture·planner·room은 상태를 확인할 수 없어서 쉰다거나 멈췄다고 단정하지 않습니다»)». r490 `unknown_problems` 가 «팀 이름 + 쉬·멈·정지·대기 글자» 만 봐서, 지시대로 «단정하지 않는다» 고 쓴 문장이 거꾸로 걸렸다.
- `ft_news_html_lint.py`: `NEGATED_TAIL`(24자 안 `지 않`·`지 못`·`아니`·`아닙`·`않습니다`·`않는다`·`않음`) · `CLAUSE_END`(`,`·`，`·`.`·줄바꿈·`며 ` — «고 » 로는 자르지 않는다: «멈췄다고 단정하지 않» 의 «다고» 가 잘린다) · `_rest_asserted(s)` = 쉼 글자 매치마다 «뒤» 같은 절에 부정 꼬리가 없으면 단정(하나라도 단정 = 위반). `unknown_problems` 는 `REST_SAID.search` → `_rest_asserted` 1곳만 · 출력 문구 그대로. kit↔bin 짝 cmp0.
- 시험 `test_ft_news_html.py` r498 ⓐⓑ 3문장 위반 0 · ⓒⓓ 4문장(부정이 쉼 글자 «앞» 다른 말·다른 절에 붙음) 위반 1씩 — `test_news_html.sh` 39 passed(기존 32 + 7) · 옛 판 ⓐⓑ 3/3 REJECT. 설치: LIVE_BIN 키트 1 cmp0 · 홈 0 · plist 0(틱이 매번 부름) · 되돌림 = 이 커밋 revert(설치본 `.bak-r498`). 범위 밖: 프롬프트 문구 · `ALL_STOP`·`APPROVAL_WAIT` · 갈래 시간 상한(important 50.6초 = 1차 상한 초과 + 재시도 성공 · 총 마감 70초 안 · 정상). 원문 = `harness/evidence/r498/tests-rc.txt`.

## 2026-10-20 — 팀 폴더 쌍둥이(옛 꼴 `design/<팀>/` + 새 꼴 `design/teams/<팀>/`)를 ERROR 대신 ref 트리로 가름 (r495 · 1.1.53)

- 사건: v65 master 213(요청 115538)이 뒤처진 체크아웃 `v6-realtime-live`(origin/main 뒤 192커밋 · `design/v65` tracked 17661 + `design/teams/v65` tracked 2)에서 `ft-goal-check` → «ERROR … v65 폴더 실재 후보 2개 — 정확히 1개여야 한다» rc4 · v65 골 틱이 섰다. ref(origin/main)는 `design/v65` 0 · `design/teams/v65` 13583 — 어느 쪽이 팀 폴더인지 이미 말하는데 판정기가 ref 트리를 안 봤다.
- `ft_team_lib.py team_in_ref` · 셸 `ft_team_in_ref <루트> <팀> [ref]`(신설 · 같은 규칙 · 같은 글자): 실재 1 = 그대로 · 쌍둥이 2 = `git ls-tree -d <ref> -- <후보>` 가 비어 있지 않은 쪽 — 1개 = 그것 + stderr `WARN TWIN-STALE <버린 후보> (ref 에 없음 · 체크아웃 ref 뒤 N커밋)` · 2개 = 명단 꼴 + `WARN TWIN-BOTH …` · 0개 = 기존 ERROR « (ref 에 둘 다 없음)» · 실재 0 = 기존 ERROR(SPARSE-HIDDEN 먼저). 읽기만(ls-tree·rev-list) — 폴더 이동·쓰기 0.
- `ft-goal-check.sh`: HITS 재구현 삭제 → `ft_team_in_ref` 1줄(«실재 0» 만 기존 ref 본문 경로 · 그 밖 실패 = ERROR rc4). 고른 폴더에 없는 정본은 그 파일만 `<ref>:<명단 꼴>/<파일>` 본문 + 출력 «끝» `NOTE 정본 = <ref> 본문(체크아웃 ref 뒤 N커밋): <파일…>` 1줄(첫 줄 = 판정 그대로) · ref 에도 없을 때만 REJECT 정본 부재. (`ft_team_doc_ref` 를 안 쓴 이유: 쌍둥이에서 «옛 꼴 실재 1개» 를 골라 옛 체크아웃 파일을 돌려준다.)
- `ft-nano-close.sh`: 원장은 «쓰는» 파일이라 ref 본문 대체 0 — 기존 «원장 파일 실재 정확히 1개» 규칙 유지(뒤처진 체크아웃 `v6-realtime-live` 는 지금도 옛 꼴 `design/v65/…/NANO-LEDGER` 에 쓴다 · 새 꼴엔 원장 0 → 카드 §4 대로 폴더 먼저 고르면 운영 닫기가 REJECT) · 원장이 쌍둥이 «둘 다» 에 있을 때만 `ft_team_in_ref` 로 가름(ref 에 둘 다 없음 = 기존 REJECT 후보 2개).
- 시험 기대 변경: `test_goal_check_ref.sh` ⓐ8 «쌍둥이 → ERROR»(r479) → «ref 한쪽 → GOAL-OK + WARN TWIN-STALE» — 이유: 전환기엔 뒤처진 체크아웃의 쌍둥이가 «정상 상태» 라 ERROR 는 v65 골 틱을 세웠고, 가름 근거(ref 트리)는 추측이 아니라 정본 조회다. ⓔ3(골 표 planner 쌍둥이)도 같은 판정기라 «ref 쪽 + WARN TWIN-STALE · 빈 새 꼴 = ERROR rc1» 로 바뀐다(옛 꼴 후퇴 0). 신규 ⓐ8b(TWIN-BOTH)·ⓐ8c(ref 둘 다 없음 ERROR)·ⓐ8d(새 꼴 원장 없음 → ref 본문 + NOTE) · `test_team_lib_twin.py` ⓐ~ⓓ(kit·bin · 셸·파이썬 같은 글자) · `test_nano_close_fail_closed.sh` ⓑ2. 설치: LIVE_BIN 키트 4 cmp0 · 홈 0 · plist 0 · 되돌림 = 이 커밋 revert(설치본 `.bak-r495`). 범위 밖: 폴더 실제 이동(planner) · `ft_goal_ledger` 골 표의 ref 본문 대체. 원문 = `harness/evidence/r495/tests-rc.txt`.

## 2026-10-20 — 새 워크트리 `.fable-team/bin` 첫 설치 길 = shim `--init` (r494 · 1.1.52)

- 사건: chatbot#8 tester 실음성 시험(P3)이 홈 훅 `press-runner-gate.sh` 의 «게이트가 없다 chatbot-main/.fable-team/bin/ft-press-gate.sh fail-closed(R106c)» deny 로 멈췄다(요청 115353). shim(`:25` 루트 bin 없음 ERROR)·설치기(`:42` REJECT)·훅(설치 안내 0) 셋 다 «bin 이 이미 있다» 전제라 새 워크트리는 어느 길로도 bin 을 못 얻는다 — 실측 `.worktrees/*/.fable-team` 313 중 bin 없음 306. master 손(`mkdir bin` + shim)으로 임시 해소.
- `ft-root-bin-shim.sh --init`: bin 없음 ∧ 루트가 «설치된 리포(공용 루트 `.fable-team/LIVE_BIN` 실재)의 git 워크트리 최상위» → 모든 검사 뒤 `mkdir` + `INIT <bin> (새 워크트리 · 공용 루트 …)` 줄 + 기존 흐름. LIVE_ROOT 기본 = 공용 루트 경로 그 자체(공용 루트 LIVE_ROOT 파일 값 복사 0 · master 115441). 공용 루트 자체·git 밖·워크트리 최상위 아님·설치 안 된 리포 = `ERROR --init 불가 — <사유>` rc3 · 생성 0. `--init` 없이 bin 없음 = 기존 ERROR + « (새 워크트리면 --init)». `--dry-run` = `PLAN init` 줄 · 쓰기 0. bin 있는 루트는 지금 흐름 그대로.
- `install.sh`: bin 없음 ∧ `--project` 가 git 워크트리 → dry-run `PLAN shim-init <워크트리>` · apply = 설치본 shim `--init`(LIVE_ROOT 기본 = 공용 루트 · rc≠0 = 그 자리에서 멈춤). 공용 루트·git 밖 bin 없음 = REJECT rc2 그대로. 프로젝트 폴더 없음 = REJECT rc2(쓰기 0).
- 홈 훅 `press-runner-gate.sh`: 게이트 없음 deny 문구 끝에 « · 설치(master) = bash <LIVE_BIN>/ft-root-bin-shim.sh --root <toplevel> --live <LIVE_BIN> --init»(LIVE_BIN = `git-common-dir` 부모의 `.fable-team/LIVE_BIN` 1줄 · 못 읽으면 글자 `<LIVE_BIN>`) · 판정 변경 0.
- `ft-nano-spawn.sh`: `git worktree add`(sparse 는 checkout 뒤) 직후 shim `--init` — 성공 = `SHIM n · MOVED m · UNKNOWN k (shim-init <워크트리>)` 1줄 · 실패 = `NOTE shim-init 실패: <사유>`(spawn 계속 · 조용한 통과 0) · dry-run `PLAN shim-init`.
- 시험 `harness/tests/test_root_bin_shim.sh` r494 절 ⓐ~ⓔ(임시 «설치된 리포» + `git worktree add` + git 밖 폴더 + 공용 루트 사본 + 설치 안 된 리포 · 외부 호출 0 · GIT_* 0) rc0 · 옛 shim 대입 19 FAIL. 설치: LIVE_BIN 키트 2(shim·nano-spawn) cmp0 + 홈 훅 1(`templates/hooks/press-runner-gate.sh` → `~/.claude/hooks/` cp+755) · 되돌림 = 이 커밋 revert(설치본 `.bak-r494`). 범위 밖: 기존 306 워크트리 일괄 설치(master 별 h) · baton wt-create 배선. 원문 = `harness/evidence/r494/tests-rc.txt`.

## 2026-10-20 — 공유 역할 좌석 승계: 은퇴가 «모든 명부»의 역할 칸(`_arch`·`_master`…)까지 후계로 · 재실행 보정 · 빈 역할 칸 채우기 (r465 · 1.1.51)

- 사건(v65 master 211 · 112532): 공유 arch 262→263 은퇴 뒤 `seats-lecture.json _arch` = 262 그대로 → `ft-seat-close 262` 가 «현역 역할 좌석» REJECT · retire 재실행은 NOOP · 명부 손 편집 0 이라 갈 길 0. 사례 2(112813): `close --verdict` 가 `_arch` 를 "" 로 비운 뒤 resume 한 좌석은 retire 가 `keys=[]` 로 끝나 칸이 빈 채 남음(planner 손 채움).
- **ft-seat-retire.sh**: 같은 폴더 다른 명부의 «값이 <구> 인 최상위 `_*` 문자열 칸 전부»(역할 + 라우팅)를 후계로(옛 r429 = 라우팅만). 출력 첫 줄 `… keys=[…] files=N roles=[<파일>:<칸>…] routes=[…]`(`roles=` 칸 추가). R282 ② «다른 명부에서 현역 → REJECT» 삭제(그 칸도 이번에 바뀐다) · close 의 현역 판정은 불변.
- **재실행(이미 은퇴)**: 남은 칸이 있으면 보정 `FIXED <구> -> <후계> file=… keys=[…] files=N roles=[…] routes=[…]` · 없으면 옛 `NOOP` 그대로(멱등).
- **빈 역할 칸 채우기**: 자기 명부에 옛 이름 칸 0 · 후계 행 실재 · 후계 이름의 역할 칸(`_master`·`_arch`·`_da`·`_tester`)이 "" 또는 없음 → 후계로 채우고 첫 줄 끝 ` FILLED <명부>:<칸>` · 그 칸이 살아 있는(tmux) 다른 좌석이면 `REJECT` rc1 쓰기 0 · 죽은 다른 좌석이면 채우지 않음(추측 0).
- 그대로: 전부 검증 뒤 쓰기(명부 하나 손상 = `ERROR` rc1 · 쓰기 0) · 바뀐 파일마다 `.bak-retire-<ts>` · tmp→교체 · 바꾸는 값 = «옛 → 후계» 치환뿐(행 삭제 0).
- **ft_roster_lib.py**(bin/kit 짝 cmp0): `scan_cells`·`apply_cells`(→ roles/routes 나눔)·`role_cell` 추가.
- **시험**: `test_seat_retire_rosters.sh` r465ⓐ~ⓕ(공유 arch files=3 · FIXED 보정·NOOP 멱등 · 손상 ERROR · 기존 REJECT 그대로(lint·rc3) · close «현역» REJECT 대조 1→0 · FILLED/살아 있는 좌석 REJECT/죽은 좌석 채우기 0) + 옛 ⓐⓑⓒ' 기대값을 새 계약으로(남의 `_master` 도 후계) · `test_seat_retire.sh` ③⑨⑬ 기대값(`roles=` 칸 · ⑬ REJECT→RETIRED). `test_seat_retire.sh` ⑧ 의 `test_ft_tick_master_seat.sh` rc4 는 origin/main 0051effd 에서도 같은 FAIL 4줄(선재 · 은퇴 도구 참조 0).
- 설치 뒤 실사건: 다음 공유 역할 좌석 승계 1건 → 모든 명부에서 값이 <옛 이름> 인 `_*` 칸 0 + `ft-seat-close <옛>` 통과.

## 2026-10-20 — 제안서 게이트 판정 원장 = ref(origin/main) 트리 · 표 행 꼴도 읽는다 (r492 · 1.1.50)

- 사건: feature#31 F-1509(main RED 수정) 카드 spawn 이 `REJECT 1509 ⓑ planner 원장 「1637 오빠 인터뷰」 줄에 … issues/1509 없음` — planner 는 링크를 main 에 올렸는데(33d5b75186) 게이트가 옛 라이브 체크아웃(`.worktrees/v6-realtime-live` · main 뒤 186커밋)에서, 줄머리 `N 오빠 인터뷰` 꼴로만 원장을 읽었다(실제 행 = 표 행 `| 1637 | 23:0x | (오빠 인터뷰 4) …`).
- `ft-proposal-gate.sh`: `GATE_VROOT` → `GATE_ROOT=${BYZ_ROOT:-<리포 루트>}` · `GATE_REF=${FT_TEAMS_REF:-origin/main}`. 원장 = 명단 `<ref>:design/TEAMS.md` 후보(명단 꼴·쌍둥이 · `_cands_ref`) 중 `<ref>` 트리에 `VERDICTS-planner-*.md` 가 있는 폴더 정확히 1개를 `git ls-tree`·`git show` 로 읽는다(체크아웃 파일 0 · 7초). 0·2+ 개·명단 못 읽음·`git show` 실패 = REJECT(후퇴 0). `FT_PLANNER_VERDICTS_DIR` 지정 시에만 폴더 파일 직접(시험용 그대로).
- 행 판정: 줄머리 `^N 오빠 인터뷰` 또는 표 행 `^| N | … (오빠 인터뷰` · 링크 검사·REJECT 문구 그대로.
- 카드 설계와 다른 점: 카드는 `team_in_ref`(디스크 실재 후보 1개)였지만 라이브 루트 체크아웃엔 옛 쌍둥이 `design/planner` 만 있고 ref 원장은 `design/teams/planner` 에만 있어(ref 의 design/planner 원장 0) 그대로면 실사건이 계속 REJECT — 폴더 선택도 ref 트리로 한다.
- 시험 `harness/tests/test_proposal_gate.sh` 새 절 ⓐ~ⓓ+ⓓb(임시 리포 + bare origin · 체크아웃은 원장 이전 커밋) 포함 ALL PASS rc0 · 옛 게이트 대조 4 FAIL · 실사건 읽기 전용 `--issue 1509` 새 `OK #1509 승인 ⓑ 판정 1637` / 옛 REJECT. 되돌림 = 이 커밋 revert(설치본 `.bak-r492`). 원문 = `harness/evidence/r492/tests-rc.txt`.

## 2026-10-20 — sparse 나노에서 남의 팀 폴더 = «SPARSE-HIDDEN <경로>» 로 원인을 말한다 + 발주문 광역 pytest 1줄 (r486 · 1.1.49)

- 사건: 나노 워크트리는 r444 ⑤ 로 자기 팀 design 만 체크아웃한다. 다른 팀 폴더를 읽는 시험(BYZ `test_v65_m5_lst_runaway*` → `team_in(root,'v65')`)이 그 안에서 «실패 10 + 수집 오류 2» 로 보여 chatbot K1 나노·arch·v65 arch 가 ~1시간(r468 에 이어 2회째 · 요청 114385).
- `ft_team_lib.py`: `SparseHidden(TeamPathError)` · 판별 = 디스크 없음 ∧ `core.sparseCheckout=true` ∧ `git ls-files --error-unmatch <상대경로>` rc0 · `team_root`(alt·꼴3 아님)·`team_in`·`team_in_ref`(실재 0) 에서. 메시지 `SPARSE-HIDDEN <경로> — 이 워크트리는 자기 팀 폴더만 체크아웃(r444) · 전체 사본 = ft-scratch-repo.sh <base> 에서 돌려라`. `team_cands_ref` 는 «실재 여부 무관» 그대로.
- `ft-team-lib.sh`: `ft_team_root` 같은 분기 · stderr 같은 글자 1줄 · rc1. `ft_team_cands`·`ft_team_cands_ref` 는 `FT_TEAM_SPARSE_CHECK=0`(→ `ft_team_doc_ref` 의 ref 본문 후퇴 그대로).
- `ft-nano-spawn.sh`: 발주문(BODY) 끝에 «★광역 pytest 금지 — … ft-scratch-repo.sh <base> 사본에서 · 도구는 SPARSE-HIDDEN <경로> 로 말한다(r486)★» · dry-run 은 PLAN 뒤 `BODY+…` 줄.
- BYZ 쪽: BYZ 시험은 팩 키트가 아니라 `tests/shared/ft_team_lib.py`(r405 사본)를 import 한다 — 같은 분기를 BYZ 가지 `nano/r486-nano-sparse-checkout-hides-other-te` 671b53b4 에 따로 둠(착지는 master 판단).
- 시험 새 `harness/tests/test_team_lib_sparse.py` 13 passed(옛 코드 대조 9 failed) · 기존 team/nano/goal 시험 11종 rc0 · 빨강 4종은 origin/main 과 실패 줄 동일(선재). 되돌림 = 이 절 커밋 revert(설치본 `.bak-r486`). 원문 = `harness/evidence/r486/tests-rc.txt`.

## 2026-10-20 — 홈 훅 설치 = kit/hooks 전부 + 실행 비트 · settings 등록 훅 전수 점검 (r491 · 1.1.48)

- 사건: 손으로 cp 한 홈 훅(`autonomy-merge-guard.sh`)이 664 로 들어와 전 좌석 매 Bash 마다 `/bin/sh: …: Permission denied`. 설치기는 홈 훅 3개만 복사하고 `cp -p → cmp`(내용)만 봐서 실행 비트를 확인하는 경로가 없었다.
- `harness/install.sh`: 홈 훅 목록 = `kit/hooks/` 일반 파일 전부(고정 3 → 자동 10) · 복사 뒤(또는 내용 같아도) 실행 비트 없으면 `chmod +x` + `HOOK <경로> chmod +x` 줄 · 요약 `HOOKS copied= same= chmod=` · dry-run HOOK 줄 `(exec)`. 새 `audit_registered_hooks <settings.json> <home>`(apply·dry-run 끝 둘 다): 등록 명령의 `…/hooks/…` 경로(`$HOME`·`${HOME}`·`~` 확장) 실재 + 명령 첫 낱말로 직접 실행되는 경로는 실행 비트 → `HOOKS registered=N ok=N bad=M` · 문제 = apply `ERROR HOOK-EXEC <경로> <없음|실행 비트 없음>` rc1 / dry-run `PENDING HOOK-EXEC …` rc0 · settings 없음 = registered=0 · JSON 깨짐 = rc1. `bash <경로>`·가드(`if [ -x …`) 로 부르는 경로는 실재만(644 여도 돈다 — 과차단 0). settings 쓰기 0 · 키트 밖 훅 chmod 0.
- `ft_live_install_check.py`(bin/kit 짝 cmp0): `hooks/*` 행 라이브 파일 실행 비트 없으면 `EXEC-BIT`(키트 모드 644 여도 · 옛 `MODE` 는 키트 100755 일 때만 봤다).
- 시험 `harness/tests/test_install_hook_check.sh` r491ⓐ~ⓔ 25칸(옛 판 15 빨강) · 실 홈 dry-run `HOOKS registered=29 ok=29 bad=0`. 기존 `test_live_install.sh`·`test_live_install_check.sh`·`test_live_install_check_tip.sh`·`test_harness_root.sh` 의 빨강은 origin/main 그대로(개수·문구 동일 — 선재). 원문 = `harness/evidence/r491/tests-rc.txt`.

## 2026-10-20 — 뉴스 지도: «확인 불가»(turn 시간 초과·실패) ≠ «쉬는 팀» · turn 재시도 1 · 풀 = 좌석 수 (r490 · 1.1.47)

- 22:04 뉴스(load 25~31)에서 chatbot 5석의 `ft-seat-status.sh turn` 이 7초 상한을 넘어 «?» 가 됐는데 `facts`·`bucket` 이 일하는 0 인 팀을 전부 «쉬는 팀» 에 넣어 일하는 챗봇팀이 «쉼» 으로 나갔다(오빠 «챗봇팀은 왜쉬어?»).
- `ft_news_html.py`: `_turn` = 첫 출력 전 실패 1회 재시도(7초 룰 · 시간 초과는 프로세스 묶음째 kill) · 풀 = min(좌석 수, 32) · 팀 칸 `unknown_reason` · `facts` 3분류(일하는 · 확인 불가 · 쉬는). `ft_news_html_render.py`: 3분류 bucket + «확인 불가» 블록 · 프롬프트 1줄. 틀 `news-team-map.html`: H2 «확인 불가» + chip. `ft_news_html_lint.py`: H2 5개 · 확인 불가 팀 이름 + 쉬/멈/정지/대기 단정 = 위반.
- 시험 `test_news_html.sh` 32 passed(새 ⓐ~ⓓ · 옛 판 RED 4) · 되돌림 = 이 절 커밋 revert(설치본 `.bak-r490`) · 단계 = `harness/evidence/r490/master-steps.md`.

## 2026-10-20 — 뉴스 ⑥ 트리: 루트·팀 폴더는 부르는 쪽이 넘긴다 — ref 임시본에서 git 128 고침 (r489 · 1.1.46)

- r484 뒤에도 ⑥ 트리가 비었다 — 공용 루트 체크아웃엔 v65 `NEWS-TREE.md` 가 없어 `ft_team_doc_ref` 가 `$TMPDIR/ft-team-doc.*` 임시본을 주는데, `ft-news-tree.py` 가 리포 루트(`git -C <트리 폴더> rev-parse`)·카드 폴더(`tree.parent/indices`)를 트리 파일 위치에서 유도해 `CalledProcessError 128`(arch 103 실측).
- `ft-news-tree.py`: `--root`·`--team-dir`(env `FT_NEWS_ROOT`·`FT_NEWS_TEAM_DIR`) · 카드 폴더 = `<팀 폴더>/indices` 실재 → ref(`FT_TEAMS_REF` · 기본 origin/main) 같은 상대 경로 `ls-tree` → 둘 다 없으면 줄에 `?(폴더 없음)`(rc0 · 말단 줄에 `?N`). 인자 없으면 옛 유도 그대로(출력 바이트 같음).
- `ft-news-tick.sh:56` = `--root "$ROOT" --team-dir "$(ft_team_cands_ref "$ROOT" v65 | head -1)"`(lib source 를 53행 앞으로 · 56행 위치 유지 = r484 린트·시험 그대로) · `ft-news-tick-cfo.sh:38` = `--team-dir "$CFO_DIR"`. 임시본 삭제 trap 그대로.
- 시험 새 `harness/tests/test_news_tree_root.sh` ⓐ~ⓓ + 틱 ⑥ 재현 + 옛 판 CalledProcessError 대조 23 PASS · 기존 4종 rc0 · 공용 루트 cwd ⑥ 절(새 키트 사본) rc0 62줄 Traceback 0. 원문 = `harness/evidence/r489/tests-rc.txt`.

## 2026-10-20 — 자율 ON 인터뷰 1회(기간 + 레벨 full|mid|each)로 범위 승인까지 함께 걸기 · 레벨 재발급 · 종류 학습 · 자율 상태 가드 (r466 · 1.1.45)

- `ft-autonomy.sh on --for <기간> --level <full|mid|each>` 한 줄(h)이 범위 승인까지 걸어 OFF 까지 병합 질문을 줄인다. 새 `ft-autonomy-level.sh`·`ft-autonomy-interview.sh`(인터뷰 답 → h 1줄) · 분류기를 표(`autonomy_scope_rules.py`·`scope-classes-pack.tsv`·`scope-ddl-record.tsv`)로 · 카드 이동(R100·이름 같음·양쪽 docs)은 docs 로 통과 · 첫 OFF 도달은 틱이 desk 에 [자율 인터뷰] 1통.
- 홈 훅 `autonomy-state-guard.sh`: 자율 ON = approve-merge 허용+로그 · OFF = deny · on/off 는 항상 deny. 시험 새 2 · 기존 15개 머리에 `FT_AUTONOMY_LEVEL=each`(--level 생략=full 이면 on 이 실 슬랙 게시라서).
- 되돌릴 땐 자율 OFF 상태에서(옛 판은 level 칸 승인 줄을 위변조로 읽음). 단계 = `harness/evidence/r466/master-steps.md`.

## 2026-10-20 — 키트 ft-mbox send/relay 도 보관 로그 mailbox.log.jsonl 에 1행 + send 자가 점검 WARN (r488 · 1.1.44)

- 라이브 `ft-mbox.sh send`(키트 단일 파일 `ft-mbox.py`)는 보낸 행을 `mailbox.jsonl` 에만 써서, recv 가 소비하면 그 쪽지의 레코드가 어디에도 남지 않았다(bodies 만) → `ft_da_hold_gate find_record` 등이 «쪽지 없음» 판정(실측 114380~114490 중 6건). 루트 모듈판 `mbox_guard._log_sent` 규칙 그대로 `ft-mbox.py send`(relay 는 send 경유)가 `_save` 직후 같은 잠금 안에서 `mailbox.log.jsonl` 에 1행 append · `FT_MBOX_LOG_MAX_BYTES`(기본 5MB) 초과 시 `.1` 회전 · 기록 실패는 stderr WARN(전송 rc 불변).
- `ft-mbox.sh` send/relay 끝에 그 seq 행이 로그에 정확히 1행인지 `grep -c` — 아니면 stderr `WARN sent-log <n> seq=<N> file=<경로>`(fail-open). skill/scripts 사본 2 동기화(cmp 0). 큐 꼴·recv 소비 규칙·루트 untracked 정본 변경 0.
- 시험 `harness/tests/test_ft_mbox_sent_log.sh` ⓐ~ⓕ(변이 포함) · 되돌림 = 이 절 커밋 revert(설치본은 `.bak-r488`).

## 2026-10-19 — 병합 줄 대조가 «팀 폴더 옛 꼴 글자만 바꾼 줄» 을 같은 줄로 센다 (r477 · 1.1.43)

- `ft_merge_lines.py` 가 줄 비교 전에 «main 이 더한 줄» 의 팀 폴더 옛 꼴(`design/<팀>/`)을 새 꼴(`design/teams/<팀>/`)로 정규화 — 명단 = `ft_team_lib.team_rows_ref`(`FT_TEAMS_REF` · 기본 origin/main) · 꼴2 팀만 · 한 방향(옛→새) · 접두 글자 치환만 · PASS 줄에 `PATHSUBST <n>줄`(0 = 칸 생략).
- 정규화는 main 이 더한 줄에만 적용한다 — 후보 줄까지 정규화하면 «새 꼴 → 옛 꼴» 역방향(카드 ⓓ 거절)이 통과한다(시험이 못 박음). 명단 못 읽음 = `WARN 명단 ref 못 읽음 — PATHSUBST 0` 1줄(stderr) + 옛 동작(정규화 0 · 추측 0 · 합성 픽스처는 WARN 0).
- 시험 새 `tests/test_merge_lines_pathsubst.sh` ⓐ~ⓕ ALL PASS · 기존 merge·land 시험 9종 ALL PASS(선재 빨강 2종은 origin/main 그대로) · 옛 판 RED(ⓐ → DENY) · 실사건: loom PR 1976 head 280b041aa5(M=75b386) 옛 판 DENY 83파일 → 새 판 DENY 2파일 + PATHSUBST 155줄(남은 2 = 명단 밖 `concierge` 재명명 팀 — 추측 0 규칙대로 거절 · `harness/evidence/r477/master-steps.md`).

## 2026-10-19 — 뉴스 HTML: top 갈래를 요약·중요한 일 2갈래로 쪼갬 · 상한 초과 = 첫 출력 전 실패 재시도 1 (r478e · 1.1.42)

- 첫 자동 틱이 부하(load 25~50)에서 `opencode run top 상한 38s 초과` — top(요약+중요한 일+근거) 한 호출이 max/high 에서 흔들림. 7초 룰대로 top → summary(요약+근거) · important(중요한 일) 2갈래로 쪼개 4갈래 병렬 · 시도당 상한 크기 비례 그대로 · 시도당 상한 초과 = 첫 출력 전 실패로 보고 총 마감 70초 안 재시도 1회.
- 시험 `test_news_html.sh` 28 passed(새 2: 한 갈래 부하 지연 → 전체 발행 0 · 초과 재시도 1). 실측(같은 입력 · load 15~50): high 최대 갈래 26.4/20.9초 · base 27.9/29.2초 · max 는 22~62초로 흔들림 → 권장 effort=high. 단계 = `harness/evidence/r478e/master-steps.md`.

## 2026-10-19 — 골 원장 판정기: 판정 키 = ref origin/main sha · 상태 = 공용 루트 1개 · 경과 = ref 기준 (r485 · 1.1.41)

- v65 master 가 자기 워크트리에서 `--touch` 해도 다음 틱(공용 루트 cwd)이 `REREAD-REQUIRED` — 원장 sha·상태 파일·커밋 경과를 전부 «cwd 의 git 루트» 에서 잡아 틱과 좌석이 다른 파일에 다른 키를 썼다.
- `ft-goal-check.sh`: 상태 = `${FT_ROOT:-ft_repo_root}/.fable-team/state/goal-read-ledger.json`(못 풀면 ERROR exit 4) · 원장·정본 sha = `$REF` 의 명단 꼴 경로 이력(체크아웃이 옛 꼴 폴더여도 같은 값 · ref 에 원장 없으면 ERROR) · touch 행에 `ref_sha` · 경과 = `rev-list <ref_sha>..$REF`(좌석 로컬 커밋은 안 셈) · `ref_sha` 없는 옛 꼴 행 = REREAD «다시 touch» · GOAL-READ 에 `ref= state=`. 체크아웃은 cited grep·NEXT 에만. 판정 세 조건(원장 갱신·TTL·경과)은 그대로.
- 시험 `test_goal_check_ref.sh` r485-⓪·ⓐ~ⓔ 12 + 기존 22 = fail=0. 이행·되돌림 = `harness/evidence/r485/master-steps.md`.

## 2026-10-20 — 뉴스 틱 ⑥ 완성 트리 복구: 도구는 $HERE(LIVE_BIN) 형제를 부른다 · shim 은 exec 만 (r484 · 1.1.40)

- 1.1.37 부터 뉴스 ⑥ 트리가 비었다 — `ft-news-tick.sh:56` 이 옛 라이브 워크트리 자리 `ft-news-tree.py` 를 `python3` 에 넘겼는데 그 자리는 r413 뒤 bash shim 이라 `SyntaxError: unmatched ')'`(v65 master 212 #114311).
- `ft-news-tick.sh` 도구 호출 8줄 + `ft-news-tick-cfo.sh:22` → `$HERE/…` · `WT` 는 제품 커밋 조회에만. 새 린트 `ft-shim-exec-lint.sh`(키트 bin 에 `python3|bash|sh "$X/.fable-team/bin/…"` 꼴 0 · `test_kit_bin_sync.sh` 가 부름). shim 생성기 변경 0.
- 시험 `test_root_bin_shim.sh` r484 ⓐ~ⓓ + 옛 꼴 SyntaxError 재현 대조 · 같은 파일 기존 RED 11건(r385 뒤 키트 기본 변경)도 `--repo·--path` 명시로 rc0. 단계 = `harness/evidence/r484/nano-steps.md`.

## 2026-10-19 — 뉴스 HTML: 일하는 팀 = 골 위 그림 카드 · 요약이 코드 판정(일하는 팀·자율)을 따른다 (r478d · 1.1.39)

- 오빠 2차 반려(«챗봇이 아래에 텍스트만») — 일하는 팀(라이브 좌석 실측)을 골 카드와 같은 그림 카드로 «골 6개» 위에 · 쉬는 팀은 맨 아래 목록.
- desk 실측 거짓 요약(«모든 팀 멈춤 · 승인 기다림») — 프롬프트에 코드 판정 facts(일하는/쉬는 팀 · `ft-autonomy.sh mode`) · 린트가 «일하는 팀 ≥1 인데 모두 멈춤» · «자율 OFF 아닌데 승인 기다림» 을 발행 0 으로 막는다.
- 시험 `test_news_html.sh` 26 passed. 단계 = `harness/evidence/r478d/master-steps.md`.

## 2026-10-19 — 뉴스 HTML «일하는 팀» = 라이브 좌석 실측 · 일하는 팀이 위 (r478c · 1.1.38)

- 오빠 반려(일하는 chatbot 이 쉬는 팀에) — 일하는/쉬는 팀 판정을 LLM 에서 코드로: 명부 팀별 tmux 좌석 + `ft-seat-status.sh turn` WORKING 수로 나누고 일하는 좌석 많은 순으로 위에 · LLM 은 팀별 설명 한 문장만. 라이브 좌석 판정이 없으면 발행 0.
- 시험 `test_news_html.sh` 24 passed · 라이브 1회: chatbot 일하는 팀 188행 < 쉬는 팀 195행. 단계 = `harness/evidence/r478c/master-steps.md`.

## 2026-10-19 — r479 골 읽기 판정기·골 표 원장도 «명단 = ref origin/main · 폴더 = 그 루트에 실재» (r479 · 1.1.37)

- `ft-goal-check.sh` 가 v65 폴더를 체크아웃 `design/TEAMS.md` 가 아니라 ref 명단(`FT_TEAMS_REF` · 기본 origin/main)으로 풀고, 그 루트에 실재하는 후보 1개를 쓴다(0개 = ref 본문 · 2개+ = ERROR). 공유 루트에 명단 파일이 없어 v65 master 에 매 틱 REJECT(rc=4)가 가던 일이 끝난다.
- `ft_goal_ledger.planner_dir`(골 표 원장 · 쪽지 가드 · 뉴스 골 표) 도 같은 규칙 — LIVE_ROOT 의 명단을 새 판으로 갈아도 옛 판 그대로여도 같은 원장을 찾는다.
- `ft_team_lib` 에 ref 판 3(`team_rows_ref` · `team_cands_ref` · `team_in_ref`) — 셸 `ft_team_cands_ref` 와 같은 규칙 · 기존 함수 동작 그대로. 단계 = `harness/evidence/r479/master-steps.md`.

## 2026-10-19 — 뉴스 HTML 모드 호출 쪼개기: 갈래 3개 병렬 · 크기 비례 상한 · stdin 차단 (r478b · 1.1.36)

- 첫 실제 틱이 `opencode run 총 마감 70s 초과`(max) — 원인 = 한 호출에 출력 전부(3~4.4K자) × max 생각 시간(실측 65.6초·130초+). 7초 룰대로 top·goals·teams 3갈래를 «그 갈래 입력만» 넣어 병렬 호출 · 시도당 상한 = 크기 비례(≤70) · stdin=/dev/null.
- 실측(같은 입력): base 30~44초 → 17.9초 · max 65.6~130초+ → 30.5초 · 린트 OK.
- 파일: `ft_news_html_render.py`·`ft_news_html.py`(bin·kit 짝) + 시험 `test_ft_news_html.py` · 단계 = `harness/evidence/r478b/master-steps.md`.

## 2026-10-19 — opencode 좌석 모델 = 세션 env `OPENCODE_CONFIG_CONTENT`: `--model` 플래그 0 · tmuxc 0.4.1 (r476 · 1.1.35)

카드 r476 · cfo 113325(정본화 나노 opencode 기동 실패 → claude 대체) · master 79 발주 113358 ①. opencode 2.0.32 TUI 최상위 플래그엔 `--model` 이 없고(`opencode run` 전용) tmuxc 가 `opencode --auto --model <ID>` 로 띄워 «Unrecognized flag: --model» 로 첫 줄에서 죽었습니다 — 정본화·리서치·검색 나노(opencode)가 전 팀에서 못 열렸습니다.

- **tmuxc 0.4.1**(`feature-pack/tmuxc`): `resolve_opencode_cmd`·`resolve_opencode_fork_cmd` 에서 `--model` 제거 · 새 `opencode_session_env` = `OPENCODE_CONFIG_CONTENT={"model":"<ID>"}`(python json 이스케이프 · `#variant` 글자 그대로) · `create_tmux_session` 이 추가 env 를 `new-session -e`(FT_SEAT 옆)로 심음 — open·fork 의 opencode+모델일 때만 · `--dry-run` 에 `env=` 줄 · 모델 미지정 = env 0(opencode 기본값) · 다른 agent 경로 변경 0 · 글로벌 `~/.config/opencode/opencode.json`·워크트리 파일 0.
- **ft-nano-spawn.sh**(bin·kit 짝): PLAN 줄에 `via=OPENCODE_CONFIG_CONTENT`(opencode 만).
- **시험** 새 `tmuxc/test/test_tmuxc_opencode_model.sh` ⓐ~ⓔ(가짜 opencode·tmux · 실 opencode·외부 호출 0) · `tmuxc/test/verify.sh` 의 opencode fork «`--model` 통과» 단언을 env 계약으로 교체.
- **실측**: 실 opencode 2.0.32 `run --standalone`(플래그 없이 env 만) → 세션 model 칸 = deepseek-v4.1-flash-free · 대조 glm-5.3-flash-free 도 일치(env 가 모델을 정함) · `#max`/`#high` 는 rc0 이나 variant 기록 0 → base ID 권고.
- **master 할 일**: `harness/evidence/r476/master-steps.md` — ★tmuxc `install.sh` 를 그대로 돌리지 않는다(팩 COMM-GUIDE-BOOT.md 가 라이브보다 옛 판 → 스킬 링크가 옛 판으로 바뀜)★ · 버전 폴더 복사 설치 + current 전환 · 실사건 opencode 좌석 1석.
- 범위 밖: tmuxc restore 스냅샷 opencode 분기(`--model` 합성 · 이제 argv 에 모델 없음 → 기본 모델로 복원) · 팩 COMM-GUIDE-BOOT.md 역반영.

## 2026-10-19 — 뉴스 HTML 모드: 팀 지도 HTML + 한 줄 · opencode 딥식 무료 비대화 1회 (r478 · 1.1.34)

카드 r478 · 오빠 확정 10-19 19:3x(desk 113404·113411·113414 «내용 좋다 html 만 발급 · 슬랙 한 줄 시간과 적정한 반복 · 스크립트로 agent-cli · 결과물·속도로 effort 결정 · 요약과 html 아웃풋»).

- `FT_NEWS_MODE=html` 이면 뉴스 틱이 원장·골 표·보드 스냅샷·[긴급] 머리·main 커밋을 묶어 `opencode run --standalone`(딥식 무료 · 70초 총 마감 · 첫 출력 전 실패만 재시도 1)에 넘기고, 내용 JSON 을 고정 틀(`templates/news-team-map.html` · 기준본과 같은 CSS·절)에 넣어 HTML 을 만든 뒤 린트 통과분만 슬랙 최상위 글 «[뉴스 HH:MM] 팀 지도 — 요약» + 요약 2줄 + HTML 첨부로 올린다. 변화 0 = 30분마다 한 줄(`FT_NEWS_REPEAT_MIN`) · 하루 첫 틱 = 지도 · 첨부 실패 = 글만 + rc3 + 다음 틱 재첨부.
- 새(bin·kit 짝): `ft_news_html.py`(build·run·publish·tick) · `ft_news_html_render.py`(프롬프트·호출·파싱·틀) · `ft_news_html_lint.py`(절 5·중요한 일 ≤7·골 6·번호 각주만·요약 ≤3줄·600B·시크릿 0) · `ft-news-effort-test.sh`(변형 비교표) · 틀 1 · `magazine_slack.upload_file(thread_ts=None, comment=)`.
- 모드 없음 = 옛 판 경로 그대로 · 되돌림 = plist env 줄 제거. 시험 새 `tests/test_news_html.sh` ⓐ~ⓗ · 증거 `harness/evidence/r478/`.

## 2026-10-19 — opencode 나노 = 읽고 모으기 · 쓰면 매번 완전히 닫기: `ft-opencode-reap.sh`(left=0) · nano-close 회수 · spawn `--tier search` · 나노 기본 모델 Sonnet 5.5 · Bash 직접 사용 알림 훅 (r286 · 1.1.33)

카드 r286 · 오빠 하네스 뉴스(desk#7 #100242 · master#56 #100251) · 판정 2035(opencode 정리 kill 표준승인 · 전역 하드 룰 2). Sonnet 5.5 가 Opus·sol 보다 처리 능력이 낫고, opencode 의 DeepSeek V4.1 Flash Free 가 1M 컨텍스트를 무료로 준다 — 단 opencode 는 메모리 문제가 있어 쓰면 매번 완전히 닫아야 합니다. 실측: opencode 가 `opencode serve` 자식(400MB+)을 띄우고 tmux 세션만 지우면 부모를 잃고 남으며, `serve --service` 는 ppid 1 · cwd $HOME 으로 뜨기도 합니다(공유 서비스 가능).

- **새 `ft-opencode-reap.sh <좌석> [--wt] [--record [--since]] [--apply] | --pid-file F [--apply]`**(bin·kit 짝): 대상 = ①좌석 pane 나무 안 opencode ③ppid 1 ∧ cwd ⊂ 좌석 워크트리(안쪽 다른 워크트리 제외) · pid 파일(`~/.claude/state/opencode/<좌석>.pids` · 시작 시각 lstart 같을 때만 — pid 재사용 오살 0) · `--record --since` 뒤 새로 뜬 부모 잃은 serve(new — 닫을 때 다른 opencode 가 살아 있으면 공유로 보고 `oc-skip`) · 그 자손 전부. 내 uid · 다른 tmux 세션 나무 · 자기 조상 제외. `--apply` = TERM → 3 s → (같은 lstart 만) KILL → 재조사 2회전 → `REAPED <좌석> n= left= rc=`(rc 0 = left 0 · 1 = 남음 · 20 = 조사 실패). 외부 호출 각 7 s.
- **ft-nano-close.sh**: 명부 agent=opencode 또는 pid 파일이 있으면 명부를 지우기 «앞» `--record` · 세션 kill «뒤» `--apply`(ABSENT 경로 포함) → `OC-REAPED <좌석> reap left=0 rc=0` · left≠0 ∨ rc≠0 = `CLOSE-FAIL … exit 1`(재실행 = pid 파일로 다시 회수). 리서치 닫힘 줄(R387)은 같은 결과(함수 `_oc_close` 하나).
- **ft-nano-spawn.sh**: `--tier search` = opencode + `${FT_OC_MODEL:-opencode/deepseek-v4.1-flash-free}` · `--agent opencode` 모델 없으면 같은 기본(옛 REJECT 대신) · impl 기본 `FT_IMPL_MODEL:-claude-sonnet-5-5[1m]` · checker/tester sonnet 칸 `claude-sonnet-5-5[1m]` · opencode 좌석은 열린 뒤 `--record --since` · 검색 나노 발주 문단(코드 수정·커밋 0).
- **새 홈 훅 `kit/hooks/opencode-reap-check.sh`**(PostToolUse · Bash): opencode 가 «명령 자리»에 있을 때만(echo·grep 인자·따옴표·heredoc 제외 · bash -c 재귀) 660 s 안에 시작한 부모 잃은 opencode 를 찾아 pid 파일 + `ft-opencode-reap.sh --pid-file … --apply` 1줄 알림 · kill 0 · 깨진 입력 = rc 1 + ERROR.
- **정본 사본** `harness/design/harness/staged-r286/`: 홈 `orchestration.md` 로스터(구현·추론·테스트 = claude-sonnet-5-5[1m] · 대량 서치 = opencode 나노 · arch·DA 행 변경 0) · `COMM-GUIDE-BOOT.md` 41항.
- **시험** 새 `tests/test_opencode_reap.sh` 50 PASS(남의 opencode 3종 생존 · TERM 무시 KILL · 신호 0 left=2 rc1 · pid 재사용 가드 · 공유 serve oc-skip · 훅 실행 자리 8종) · 새 `tests/test_nano_spawn_tier.sh` 25 · `test_nano_close_fail_closed.sh` ⓗ(record→apply 순서 · CLOSE-FAIL · pid 파일 재실행) · `test_nano_team_env.sh` 기대값 2(의도된 기본 모델) · `test_da_hold_gate.sh` 8b 추출 = `_oc_close`. 회귀 59 새 FAIL 0. 증거 `harness/evidence/r286/`.
- **master 할 일**: `evidence/r286/master-steps.md` — LIVE_BIN 3 cmp0 · 홈 훅 + settings PostToolUse 1줄 · 홈 정본 2 cp · 실사건 = `--tier search` 나노 1석 열고 닫아 `OC-REAPED … left=0` + ps 에 그 좌석 opencode 0.
- 범위 밖: 전역 CLAUDE.md «오케스트레이션» 절 모델 줄 · BYZ `.claude/rules/orchestration.md` · 공유 serve 자체의 메모리.

## 2026-10-19 — 팀 «이름» 바꾸기 도구 `ft-team-rename.sh`: 명단·폴더·명부·env·저장 참조를 한 번에 + 스냅샷 되돌림 + 옛 계보 우편 감시 (r468 · 1.1.32)

카드 r468 · master 78 발주 112808(오빠 «컨시어지 이름 잔존 없도록») · arch 101 실측 · 계획 `design/harness/PLAN-team-rename-concierge-to-chatbot-20261019.md` §3·§6. 기존 `ft-team-move.sh` 는 «같은 이름의 폴더 이동»(design/<팀> → design/teams/<팀>)만 알아, 팀 이름을 바꾸려면 명단 2·폴더·명부·env·틱 표·카드 본문·저장 참조 7종을 손으로 고쳐야 했고 되돌림 스냅샷이 없었습니다.

- **새 `ft-team-rename.sh` + `ft_team_rename.py`**(bin·kit 짝): 이동 도구의 Ctx·점유 판정·Snap·revert·명부 기준 워크트리(store_base)·walk/dump_like/write_text 를 import(복제 0 · 이동 파일 변경 0).
  - `--plan <옛> <새>` = 명단 2행 · 팀 폴더 파일 수 · 본문 치환 예상(패턴 2) · 명부 칸 4·행 수 · REF4~7 · env 파일 · 워크트리 받음/미전환 · BLOCK → `PLAN-END blockers=<n>` · 쓰기 0.
  - `--apply` = 선검사(새 이름 명단에 없음 · 옛 이름 있음 · 폴더 칸 `design/teams/<옛>/` 꼴 · 쌍둥이 `design/<옛>/` 잔존 = `REJECT 먼저 ft-team-move` · 목적지·새 명부·새 env 없음 · 스테이징 비움 · 작업 트리 깨끗 · pane cwd·lsof 점유 0 — 하나라도 걸리면 쓰기 0) → 스냅샷 `.fable-team/state/team-rename/<ts>-<옛>-<새>/` → `git mv` + TEAMS/TEAMSET 행(첫 칸) + 본문 치환 «`design/teams/<옛>/` · `byz-<옛>-`» 둘뿐 + TEAMS 각주 «옛 이름 <옛> → <새>(개명 <날짜> · 좌석 계보 byz-<옛>-* 는 은퇴)» → 한 커밋 → 명부 `seats-<옛>.json` → `seats-<새>.json`(+`.bak-rename-<ts>` · `_name`·`_label` 대소문자 따라 · 경로 칸 · `_doc` · `_renamed_from`·`_renamed_at` · 행 이름·`_master` 등 좌석 이름 불변 · 못 받은 워크트리 기준 행 = `_move_pending`) → nano-card-base·worktree-info·baton·추가 파일 → env `bin-<옛>/` → `bin-<새>/`(파일 이름 + 값: 명부 파일·나노 접두·워크트리 접두·활성 태그·원장 경로 새 꼴·틱 라벨 · 권한 유지) → `AFTER 옛 자리 잔여 <n>`.
  - 같은 `--apply` 를 개명 뒤 다시 = `RESYNC`(head-sync 로 받은 워크트리의 `_move_pending` 행·worktree-info 만 · git 변경 0).
  - `--verify <새>` = 명단·폴더·map-lint·명부 index·카드 기준선·팀 집합 + 옛 폴더·옛 명부·옛 env·옛 명단 행 잔존 = ERR · 잔여 «<옛>» 글자 = WARN 목록(각주·옛 좌석 이름 제외 · 다른 팀 이력 문서는 1줄 요약 · 제품 코드 폴더는 훑지 않음) → `VERIFY ERR=<n> WARN=<m>`.
  - `--revert <스냅샷>` = 만든 파일(새 명부·.bak-rename·새 env) 지움 → 이동 도구 revert(바이트 복원 sha256 + `git revert`).
- **ft-tick.sh** `renamed_watch`: 명부 `_renamed_from` 이 7일 안이면 옛 계보(byz-<옛>-* 최신 번호 좌석) `peek`(소비 0) → pending>0 이면 그 명부 `_master` 에 `[개명 우편]` 1줄 · 1시간 1번(`FT_TICK_RENAMED_SEC`) · 목록이 바뀔 때만(`renamed.sig`) · `FT_TICK_RENAMED=0` 으로 끔. 주석 1(R324 목록 concierge → chatbot).
- **team-tick-env.tsv**: concierge 행 → chatbot(명부·STATE_DIR·PIDFILE·STAMP) · 팀 틱 전 행 끌 감시에 `FT_TICK_RENAMED`(전 명부 스캔은 메인 틱 1개).
- **시험** 새 `tests/test_team_rename.sh` ⓐ~ⓖ 86 PASS(plan 쓰기 0 · REJECT 4종 쓰기 0 · 쌍둥이/옛 꼴 REJECT · apply 한 커밋·명부·env·저장 참조 · RESYNC · verify ERR 0·WARN 목록·변이 ERR · revert 뒤 파일·폴더 manifest 원본 동일 · watch 7일·중복 0 · 600/300 0) · `tests/test_team_tick_unify.sh` concierge → chatbot.
- 실 리포 읽기만: origin/main(a608fea5a0) 사본에서 `--plan concierge chatbot` = 폴더 71파일 · 본문 치환 예상 82+66 · 명부 행 17 · nano-card-base 12 · worktree-info 2 · env 6(이름 4) · `PLAN-END blockers=0`. 증거 `harness/evidence/r468/`.
- 범위 밖: 제품 코드·UI 글자 · 가지·워크트리 이름(보존) · 좌석 교대(successor-open) · launchd 팀 틱 신규 설치.

## 2026-10-19 — 슬랙 보고 도구 인자: reply 의 `--channel` 기본값(None)이 다른 서브명령 7개로 새던 것을 막는다 (r474 · 1.1.31)

카드 r474 · master 79 발주 113237·113489 · arch 102 실측. r414 의 `rpl.set_defaults(channel=None)` 은 reply 만 노렸지만, argparse `parents=[common]` 는 부모의 Action «객체» 를 자식이 공유하고 `set_defaults` 는 그 Action 의 `.default` 를 고치므로 start·progress·result·check·repair·update·attach 의 기본 채널까지 None 이 됐습니다 → 홈 설치(10-19 09:24) 뒤 뉴스 발행 `conversations.history channel_not_found` · 임시 우회 = 뉴스 plist env `FT_NEWS_POST_ARGS=--channel C0C6MJGRR89`. 기존 시험은 매 호출에 `--channel C1` 을 명시해 기본값을 못 봤습니다.

- **kit/slack-mirror/thread_post_args.py**: `--channel` 을 `common` 에서 빼 두 부모로 — `chan`(기본 CHANNEL · 서브명령 7개) / `chan_reply`(기본 None · reply). Action 공유가 없어져 `set_defaults` 삭제 · reply ∧ `--ts` ∧ None → CHANNEL 되돌림 줄 유지 · 그 밖 변경 0.
- **시험** 새 `tests/scripts/test_thread_post_args.py`(`PYTHONPATH=kit/slack-mirror:tests/scripts python3 -m pytest …`): ⓐ 서브명령 7개 기본 channel == CHANNEL ⓑ reply --thread = None ⓒ reply --ts = CHANNEL ⓓ 명시 `--channel C1` 9경우 전부 C1 · 같은 프로세스 reply 뒤 update 도 CHANNEL. RED = origin/main 판 8 FAIL(ⓐ 7 + 누수 1 · 전부 `channel=None`) → 고친 판 19 passed · 기존 `test_thread_post.py`·`test_thread_post_attach.py` 포함 45 passed · `tests/test_thread_reply_named.sh`(r414) ALL PASS.
- **master 할 일**: 착지 → `install.sh --apply --project <루트>` → 홈 `~/.hermes/scripts/thread_post_args.py` cmp0 → 실사건 1 = plist env 없이 뉴스 발행 1회(`conversations.history` ok · 뉴스 틱 로그 줄) → `com.byz.ft-news-planner.plist` 의 `FT_NEWS_POST_ARGS` 줄 제거(되돌림 = 줄 복구 · 파일 되돌림 = `.bak-r474`).
- 범위 밖: 등록부(r414) · 뉴스 발행 본체(r458) · 다른 kit 파일.

## 2026-10-19 — 틱 데몬 자리 규칙 3줄(코드 = LIVE_BIN · 데이터 = 공용 루트 · 정본 = ref origin/main): comm 을 공용 루트로 · shim 폴더 옛 사본 자가 검사 · 골·뉴스 틱 정본 ref 읽기 · 설치기 comm 동기화 + RESTART 줄 (r459 · 1.1.30)

카드 r459 · master 112539·112636 · arch 101 실측 · 골 6(메인 골 1 팀장 v65 master 가 틱 없이 36시간). 메인 틱이 10-18 09:53 부터 `skip … 에이전트 판정 불가(<v6>/.fable-team/comm/ft-agent-alive.sh 실행 실패)` 839회 — `ft_comm_dir` 가 데이터 루트 = LIVE_ROOT(옛 라이브 워크트리 v6-realtime-live)의 comm 으로 풀렸는데 거기엔 판정기가 없었습니다(진짜 우편함·판정기 = 공용 루트 comm). 10-19 09:04 shim 교체 뒤엔 «먼저 기동한» 틱 6개가 메모리의 옛 사본으로 shim 폴더의 `.py` 를 python3 로 읽어 SyntaxError 를 반복했고, goal-tick 은 글자 ROOT(v6)·뉴스 틱은 체크아웃 명단으로 v65 폴더를 못 풀어 ERROR(112632).

- **ft-harness-root.sh** `ft_comm_dir`: ①env `FT_MBOX_DIR`(comm 폴더 그 자체) ②env `FT_ROOT` ③`*/.fable-team/bin` 이면 `git -C` 공용 루트 ④cwd 공용 루트 — LIVE_ROOT 분기 제거 · comm 없음 = ERROR 그대로. `ft_data_root` 는 state 용 그대로(주석 «comm 은 쓰지 않는다»).
- **ft-tick.sh · ft-tick-team.sh**: 기동 1회 자가 검사 — 형제 `ft_raised.py` 첫 3줄에 `ft-root-bin-shim` 마커가 있으면 `ERROR shim 폴더에서 실행 — launchctl kickstart 로 LIVE_BIN 재기동` exit 3(옛 통째 사본이 조용히 돌지 못한다). MBOX·AGENT_ALIVE 기본 = 공용 루트 comm(ft_comm_dir).
- **ft-team-lib.sh** `ft_team_doc_ref <루트> <팀> <파일> [<ref>]`: 명단 = ref(origin/main) · 후보 폴더 중 실재 정확히 1개면 그 경로 · 0 이면 `git show <ref>:<명단 꼴 폴더>/<파일>` 본문을 임시 파일로(정리 = 부르는 쪽 · `ft_team_doc_tmp`) · 2+·ref 못 읽음·ref 에도 없음 = ERROR rc1. 읽기 전용(원장처럼 쓰는 파일은 `ft_team_file_ref`).
- **ft-goal-tick.sh**: 글자 ROOT 제거 → ROOT = `ft_repo_root`(env `FT_GOAL_TICK_ROOT` 시험용 유지) · 틱 프롬프트 = `ft_team_doc_ref` + trap 정리. **ft-news-tick.sh**: 글자 ROOT 제거(env `FT_NEWS_ROOT` → `ft_repo_root`) · NEWS-TREE.md = `ft_team_doc_ref`(`FT_NEWS_TREE` 우선 그대로). **ft-nano-close.sh**: 원장 0·2+ REJECT 문구를 헬퍼 ERROR 꼴(«실재 후보 N개 — 정확히 1개여야 한다(명단 … · 후보 …)») 하나로.
- **ft-tick-install.sh · ft-tick.plist**: 메인 plist `WorkingDirectory` = git 공용 루트 + env `FT_TICK_MBOX`·`FT_MBOX_DIR`·`FT_TICK_AGENT_ALIVE`(공용 루트 comm · `__COMM__`) — 팀 plist 와 같은 틀 · 공용 루트 comm 없음 = REJECT · dry-run + `FT_TICK_PRINT_PLIST=1` = 렌더본 출력.
- **install.sh**: ⓐ `comm_sync` — 팩 `harness/comm` 최상위 일반 파일(제외 = `mailbox*.jsonl`·`.mbox-seq`·`.mbox-guard.json`·`queues.conf`·`*.pyc` · 폴더 `bodies/`·`relay/` 는 대상 밖)을 `<공용 루트>/.fable-team/comm/` 에 cp -p · 덮기 전 `.bak-<버전>`(첫 원본 보존) · 삭제 0 · dry-run = `COMM <dst> <- <src>` 줄 + `COMM copied=N same=M` · 워크트리 `--project` = `SKIP comm`. ⓑ apply 끝 `ft_live_install_check.py --restart-scan` — 판정식 `restart_due`(R245 plist_items 에서 뽑은 함수 하나)로 «기동 < 스크립트(shim 이면 LIVE_BIN 지도·라이브 도구까지) mtime» 인 적재 데몬마다 `RESTART <label> — launchctl kickstart -k gui/<uid>/<label>` 줄(실행 0 · master 집행).
- **시험**: `test_harness_root.sh` r459 ⓐ~ⓔ 추가 · 새 `test_tick_shim_guard.sh` ⓐ~ⓒ · `test_nano_close_fail_closed.sh` ⓑⓒ 문구 갱신. 실 머신 읽기만: `install.sh --dry-run --project <BYZ 루트>` rc0 · `COMM copied=24 same=8`(루트 mbox.sh·ft_seat_bind.py 는 팩보다 뒤 — r408 미설치) · `--restart-scan` = 팀 틱 4 + 슬랙 수신 2 RESTART. 증거 `harness/evidence/r459/`.
- 범위 밖: state 폴더 통합(v6 ↔ 루트) · r458(뉴스 폴더 = 원장 리포 TEAMS.md · 뉴스 틱의 `WT=<루트>/.worktrees/v6-realtime-live` 도구 경로) · 루트 체크아웃 당기기.

## 2026-10-19 — 원장 뉴스가 «원장 정본 한 곳»(FT_LEDGER_REPO + 경로)에서만 sha·경로·뉴스 폴더를 푼다 + 뉴스·매거진 골 표 뒤 «팀별 완성 진행» 블록 (r458 · 1.1.29)

카드 r458 · master 112887·112904·112907·113018 · arch 101 실측. 10-18 08:43 뒤 뉴스 발행 0: 원장 경로는 원장 리포(LIVE_ROOT) 명단으로, 뉴스 폴더는 공용 루트(로컬 main 2만 커밋 뒤 · TEAMS.md 없음) 명단으로 풀어 `ERROR 팀 명단 없음` 2671회. 임시 처방(h182 · 원장 리포를 c-level-planning 으로) 뒤엔 `git show 실패: path design/teams/planner/… not in c7b4a5db8b` — 기준선(last.sha)은 옛 경로 리포 판, 경로는 새 경로라 «출처 2개».

- **출처 1개**: 뉴스 폴더 = `<루트>/<원장 경로의 폴더>/news`(원장 경로 = FT_LEDGER_PATH › 원장 리포 TEAMS.md 의 planner 폴더) · 폴더 없음 = `ERROR 뉴스 폴더 없음 <경로>`(폴백 0) · FT_NEWS_DIR 우선 그대로. 골 표·팀별 진행이 읽는 원장도 같은 값(FT_GOAL_A6_LEDGER › FT_LEDGER_REPO+FT_LEDGER_PATH › 원장 리포 planner 폴더).
- **기준선 판 검사**: 기준선 sha 판에 «같은 리포·같은 경로» 원장이 없으면 `기준선 <sha10> 판에 원장 정본 <경로> 이 없다 … 옛 경로 후퇴 0` ERROR(발행 0) — 옛 경로(design/planner/)·쌍둥이 경로로 읽지 않는다(#0 RULE · master 113018). 복구 = 원장을 정본 경로로 커밋 → 기준선을 그 판으로.
- **팀별 완성 진행**: `ft-goal-table.sh teams` = 원장 `## 팀별 완성 진행` 첫 표(팀 | 끝선 N/M | 마지막 착지 | 지금 하는 것) → 마커 `★팀별 완성 진행 (<원장 sha10>)★ … ★/팀별 완성 진행★`(≤1600B · «지금» 칸 24→16→8자). 표 없음·예산 초과·도구 실패 = 빈 글 + WARN — ★새 거절 게이트 0★(골 표 check 불변). 뉴스 첫 판 = 머리 → 골 표 → 팀별 진행 → lead(3500B 계산 포함 · 이어진 판엔 없음) · 매거진 뿌리 글·HTML 절 골 표 바로 뒤.
- **시험** `tests/test_goal_table_gate.sh` r458 16 PASS(ⓐ 루트 명단 없음 → 원장 리포 명단 · 폴더 없음 ERROR ⓑ FT_NEWS_DIR 우선 ⓒ teams 블록·표 없음 WARN rc0·check 불변 ⓓ 첫 판 순서·3500B·이어진 판 0 ⓔ 매거진 뿌리 글·HTML·무장이어도 거절 0 ⓕ 옛 경로 기준선·다른 리포 sha = 명확한 ERROR · 정본 판끼리 발행 · FT_LEDGER_PATH 한 값) · 전체 fail=0. RED: origin/main 판 10 FAIL · `check_base` 만 빼면 ⓕ 2 FAIL(실 오류 `exists on disk, but not in` 그대로 재현). ⓚ 픽스처 `tests/fixtures/goal_table/AUTONOMY-GOAL-A6-20261018.md` 가 팩에 없어 기존부터 FAIL → BYZ origin/main 판 복사.
- **범위 밖**: 원장을 새 경로 판으로 옮기기(planner 몫 · master 요청) · 공용 루트 main 당기기 · 세션 상태 스냅샷 낡음(ERROR 로그 · 발행은 막지 않음) · 팀 틱 «지금 하는 것» 자동 수집.

## 2026-10-19 — 자율 ON 병합 훅이 «오빠 승인 sha 위에 main 병합만 더한 head»(같은 변경 집합)를 재승인 없이 통과시킨다 (r462 · 1.1.28)

카드 r462 · ops master 33 [HIL] 112442 → planner 112456 → master 78 발주 112459. 훅 `autonomy-merge-guard.sh` 는 승인 파일 이름 == `--match-head-commit` sha 글자 일치만 봐서, 착지 직전 표준인 main 병합으로 head 가 바뀌면 «승인한 변경 집합은 그대로» 인데도 매번 오빠 재승인을 요구했습니다(ops PR 1960 왕복).

- **판정기 = 이미 있는 것 하나**: `ft_approval_equiv.py`(R247 ft-merge-land · r411 scope-approve CODE_EQUIV 가 쓰는 같은 판정기). 카드 처방의 새 `autonomy_equiv.py` 는 만들지 않았다 — 같은 판정식이 이미 함수(파일)로 빠져 있어 새 파일 = 중복.
- **훅**: 글자 일치 실패 시 승인 폴더의 sha 들(파일 1줄 == autonomy.log 줄 검사를 먼저 통과한 것만 · 최신순 · 7초 × 3 마감) 중 판정기 `EQUIV` rc0 인 것이 있으면 통과 + 훅 로그 `EQUIV <승인> -> <head>`. 없으면 기존 deny 사유 + `재승인 필요 — 승인 sha 와 같은 변경 집합 아님: <판정기 사유 원문>`(판정기를 못 돌렸으면 EQUIV 안내 1줄). 판정기 없음·rc3·시간 초과 = 통과 0(판정 1675 «병합 = 오빠 값» 불변).
- **`ft-autonomy.sh approve-merge`**: stdout `APPROVED …` 줄은 그대로, stderr 에 `EQUIV 허용 범위: …` 1줄(200줄 한도 안 · bin·kit cmp0). 기존 시험 2곳(`test_autonomy_kinds_1675` ⓑ OFF · `test_merge_land_off_approval` ④)의 `2>&1` 글자 일치 단언을 «첫 줄 == APPROVED …» 로 바꿈(1675 쪽은 EQUIV 줄 존재도 단언).
- **ops 실사건 실측**(BYZ 리포): 승인 45cd3c302b 는 head 6f66271305 의 조상이 «아니다»(가지를 89c8e21f13 로 다시 만든 뒤 main 병합) — 카드 Issue ③ «45cd 위» 와 다름. 그래도 판정기 rebase 모드 조건(main 6d4ccce32c ⊂ head · 자기 변경 diff 동일 · `merge-tree(45cd, 6d4c)` = head 트리 8b87f3a161)이 그 당시 main 기준으로 전부 참 → 이 훅이면 EQUIV 통과였다. 지금은 main 이 더 나가 같은 head 는 NOT-EQUIV(«PR head 도 지금 main 위가 아님») — main 을 한 번 더 병합하면 다시 EQUIV.
- **시험** `tests/test_autonomy_merge_equiv.sh`(새 · 13 PASS): ⓐ A 위 main 병합 → 통과 + 로그 ⓑ +가지 새 커밋 → deny(«일반 커밋 1») ⓒ A 를 조상으로 안 둔 다른 변경 → deny ⓓ H == A → 통과 · EQUIV 로그 0 ⓔ 승인 파일만(log 줄 없음) → H·A 둘 다 deny + 판정기 없음 → H deny · A 통과 + approve-merge stdout 불변·stderr 1줄. 고치기 전 훅(origin/main)으로 같은 시험 = fail 4(ⓐ·ⓑ·ⓒ·ⓓ로그).
- **범위 밖**: 자율 OFF 경로 · scope-approve code-max · PR 1960 착지 · 판정기 rebase 모드의 «지금 main ⊂ head» 조건 완화(ft-merge-land 와 공유라 따로).

## 2026-10-19 — 설치기 plist 교체가 «절반 상태» 로 멈추지 않는다 — bootstrap 재시도 · 실패면 직전 plist 원복 · LIVE_BIN 전환 뒤로 (r464 · 1.1.27)

카드 r464 · master 112557 카드A · 1.1.25 설치 실사고(1.1.25 폴더만 생기고 LIVE_BIN 1.1.24 · 슬랙 미러 bootout 된 채 · master 손 bootstrap pid 89173). `bootout` 은 launchd 가 프로세스 종료를 기다리는 비동기 동작이라 바로 `bootstrap` 하면 실패할 수 있고, 설치기는 그 실패를 `exit 1` 로 받아 «plist 는 새 것 · 미러는 내려감 · LIVE_BIN 은 옛 것» 을 남겼다 — 되돌림은 안내 글자뿐이었다.

- **교체**: 덮기 전 직전 사본 `<plist>.bak-<version>`(매 교체 · `.bak-r426` 첫 원본은 그대로) → bootout → bootstrap 1초 간격 최대 3회(7초 안) → kickstart → `PLIST applied <label> (retry=<n> · 되돌림 = <plist>.bak-<version> · kickstart)`.
- **실패**: bootstrap 3회 또는 kickstart 실패 → 직전 사본 원복 + bootstrap(같은 재시도) → `PLIST RESTORED <label> — 새 렌더본 적용 실패(<launchctl 출력 1줄>)` · 원복본 bootstrap 도 실패면 `ERROR: plist 원복본 bootstrap 도 실패 … 손 복구 = launchctl bootstrap gui/<uid> '<plist>'`.
- **순서**: plist 단계는 LIVE_BIN 전환·githooks «뒤». 실패해도 코드 전환은 끝나 있고 마지막 줄 `INSTALLED <version> · PLIST ERROR …` + rc1. 성공은 `INSTALLED <version> · PLIST ok`. dry-run 출력 불변.
- **시험** `tests/test_live_install_check_plist_env.sh` r464ⓐ~ⓔ 7줄 추가(39 PASS): ⓐ 1회 실패 뒤 retry=1 ⓑ 3회 실패 → 원복 cmp0 · RESTORED · rc1 · LIVE_BIN 새 버전 · `.bak-r426` 보존 ⓑ' 원복도 실패 → ERROR ⓒ 같음 → launchctl 0 ⓓ 되돌림 기준 = 직전 사본 ⓔ 재시도 ≤7초. 가짜 launchctl 스위치 `FT_FAKE_BOOTSTRAP_FAIL=<n>`. RED = 옛 설치기 위 5 FAIL.
- **범위 밖**: plist 템플릿 내용 · r457 공용 루트 분기.

## 2026-10-19 — 병합 줄 대조(`ft_merge_lines.py`)가 «다른 폴더로 옮긴 파일» 을 옮긴 곳에서 센다 — D 인데 같은 이름 1개면 이동 · 옛 경로 글자 1쌍 치환 (r461 · 1.1.26)

카드 r461 · master 112578·112657 · loom master 36 결정 요청 112574. 보호 집합의 키가 «파일 경로» 라서, 작은 카드를 다른 폴더로 옮기며 경로 글자 줄을 바꾸면 `diff -M` 유사도가 50% 밑으로 떨어져 «D(삭제) + A(새 파일)» 로 갈라지고 «S 가 삭제» 로 거절됐다. git 이 R 로 잡아도 main 이 더한 «옛 경로 글자 줄» 이 새 경로 글자로 바뀌면 «사라짐» 이었다.

- **규칙**(소실 판정 «전»): ①D 면 S 트리(`ls-tree -r`)에서 같은 basename 을 찾아 **정확히 1개**일 때만 그 파일을 옮긴 곳으로 본다 — 0개 = 기존 «S 가 삭제» · 2개 이상 = `S 가 삭제 · 같은 이름 후보 N개(추측 0)` ②옮긴 파일(R 또는 ①)은 main 줄마다 «그대로» 와 «옛 경로 → 새 경로 1쌍 치환» 중 많은 쪽으로 센다 ③포함 안 되면 `<새 경로> 로 이동했으나 main 이 더한 줄 N 개 없음` ④바이너리 D·R 은 기존 거절 그대로 · 같은 경로 줄 소실은 기존 «사라짐» 그대로.
- PASS 줄 = `PASS 보호 집합 N 파일 · F=… · 이동 인정 K; MOVED a -> b …(3개 + 외 N)`(한 줄 · ft-merge-gate 가 `ALLOW … · $OUT` 로 싣는다). DENY 첫 단어 불변.
- **시험** `tests/test_merge_lines_moved.sh`(새 · 13 PASS): 전제 2(ⓐ 가 실제 D+A · ⓕ2 가 실제 R) · ⓐ 3장·48장 이동 PASS · ⓑ 진짜 삭제 · ⓒ 이동+줄 2개 소실 · ⓓ 같은 이름 2개 · ⓔ 바이너리 이동 = DENY · ⓕ 큰 카드 R(같은 내용·경로 줄 치환) PASS · 같은 경로 줄 소실 «사라짐» 그대로. RED = `FT_MERGE_LINES=<옛 판>` 으로 6 FAIL(ⓐ·ⓐ48·ⓒ·ⓓ·ⓕ·ⓕ2).
- **실사건 실측(loom PR 1959 head 39a6d47bc0 · M=30cef9026e = 17:53 거절 당시 origin/main · 읽기만)**: 옛 판 DENY 15건(R 13 + D 2) → 새 판 DENY 14건. 살린 것 1(`대기/loom-789-u2b…` D → `완성/` 같은 내용). ★남은 14건은 경로 글자가 아니라 카드 본문 줄(base_sha·선행·상태·시험 줄)이 main 판과 다르다★ — main 이 F 이후 고친 카드 내용을 S 의 옮긴 카드가 안 가졌다(loom ⓐ «origin/main 판 복원» 이 같은 경로 파일만 덮어서 옮긴 카드는 빠짐). 이건 이동 규칙이 덮을 일이 아니라 진짜 «main 이 더한 줄 소실» 이다 → loom 쪽 처리 필요(아래 master-steps).
- **범위 밖**: `-M` 유사도 인자 · ft-merge-gate 다른 검사 · 병합 훅(r462).

## 2026-10-19 — `pipefail` 아래 `… | grep -q` 가 64 KB 넘는 입력에서 SIGPIPE(141)로 «찾았는데 실패» — 목록은 변수로 받은 뒤 here-string 으로 grep (1.1.25)

카드 r453 · master 111789·112300 · arch#99 실측(BYZ 루트 워크트리 308개 · porcelain 59,129 B · `ft-nano-close.sh --plan-only` 가 등록 워크트리를 «아니다» 로 REJECT → 판정 2367 정리 2곳 막힘). grep 이 찾고 먼저 닫으면 왼쪽(git·printf)이 아직 쓰는 중이라 SIGPIPE 를 받고 `pipefail` 이 141 을 파이프 결과로 올린다. 입력이 파이프 버퍼(실측 60 KB rc0 · 66 KB rc141)를 넘을 때만 나서 워크트리가 적을 땐 시험이 못 잡았다.

- **처방 편차**: 카드 처방 `printf '%s\n' "$_wl" | grep -qxF` 도 같은 141 이다(실측 300 KB · 3/3 rc141 · 시험 ⓐ 에 단언) — `printf` 도 파이프 왼쪽에서 쓰다가 SIGPIPE 를 받는다. 그래서 `grep … <<<"$변수"`(here-string · 파이프 0). 캡처 실패 = 빈 목록 = 기존 REJECT 그대로(fail-closed · 판정 기준 불변).
- **전수 린트**(키트 bin · `set -o pipefail` 파일 안 `| grep -q` · bin·kit 짝 cmp0):

| 파일:줄 | 왼쪽 입력 | 141 이면 | 처치 |
|---|---|---|---|
| `ft-nano-close.sh:376` `--plan-only` | `git worktree list --porcelain` | 등록 워크트리 REJECT(오판) | 고침 — `_wl` 캡처 + here-string |
| `ft-nano-close.sh:398` `--shared-wt` ⓑ | `git worktree list --porcelain` | ⓑ bad «등록 아님»(오판) | 고침 — here-string |
| `ft-nano-close.sh:410` `--wt` ⓐ | `printf "$_porc"`(같은 목록) | ⓐ bad «등록 아님»(오판) | 고침 — here-string |
| `ft-landed-check.sh:14` | `printf "$ch"`(`git cherry` · 가지 커밋 수에 비례) | `!` 로 뒤집혀 **미착지가 cherry(착지)** 로 읽힘 — fail-open | 고침 |
| `ft-index-move-canon.sh:107` | `printf "$CHANGED"`(`git diff --name-only` 범위) | 정본 있는데 «없음» REJECT | 고침 |
| `ft-scratch-repo.sh:65` | `printf "$cwds"`(`lsof` 전 프로세스 cwd · 실측 25,950 B) | **쓰는 중인 tmp 를 삭제 후보로** 올림 — fail-open | 고침 |
| `ft-launchd-check.sh:27` | `launchctl print-disabled`(실측 1,762 B) | — | 유지(작음) |
| `ft-resource-reclaim.sh:35-36` | 인자 문자열 `ONREJ` | — | 유지(인자 크기) |
| `ft-scratch-repo.sh:60` | tmux 세션 이름(실측 1,479 B) | — | 유지(작음) |
| `ft-wt-sweep.sh:189` | `.deleting` 표식 첫 줄들 | — | 유지(작음) |
| `ft-nano-close.sh:330` | `printf "$tmux_out" \| awk …exit` | rc 미사용(값만 씀) | 유지(무해) |

- **시험** `tests/test_nano_close_worktree_list_pipe.sh`(새 · 18 PASS): 임시 리포 + 긴 이름 등록 워크트리 452개(porcelain 162,697 B) · ⓐ 옛 꼴 git 파이프·printf 파이프 rc141 · here-string rc0 ⓑ `--plan-only` 목록 앞(v65-aaa)·맨 뒤(v65-zzz) → `PLANNED` ⓒ 미등록 → 기존 REJECT · 계획 0 ⓓ `--shared-wt` 등록 공유 워크트리(목록 앞) → ⓑ 오판 0 · 미등록 cwd → ⓑ bad 1줄. 고치기 전 `ft-nano-close.sh`(origin/main) 로 같은 시험 = FAILED 3(ⓑ v65-aaa REJECT · ⓓ 오판) — 맨 뒤 v65-zzz 는 옛 판도 통과(결함은 «앞쪽에서 찾을 때만»).
- **범위 밖**: 워크트리 수 줄이기(r444 sweep · 판정 1920) · `pipefail` 끄기. 라이브 BYZ porcelain 은 지금 62,091 B(경계 바로 아래 — 다시 넘으면 옛 판은 재발).

## 2026-10-19 — 설치기가 launchd plist(쪽지→슬랙 미러)를 git 공용 루트 설치에서만 갱신한다: 워크트리 `--project` 는 `SKIP plist-env` (r457)

카드 r457 · master 112171 · arch#100 실측. r426 의 plist 갱신이 `--project` 글자를 그대로 FT_ROOT·`--mailbox` 로 렌더해, r413 STALE-COPY 안내대로 워크트리(`.worktrees/v6-realtime-live`)를 `--project` 로 설치하자 미러 plist 가 우편함 없는 워크트리 경로로 교체됐습니다(1.1.24 설치 실사고 · master 복원). 설치기의 «프로젝트» 가 두 뜻(shim 을 둘 폴더 = 워크트리 가능 · launchd 가 볼 루트 = 공용 루트만)이었습니다.

- **install.sh**: `PROJECT` 확정 직후 `git rev-parse --path-format=absolute --git-common-dir` 로 공용 루트(`pwd -P` 정규화). `plist_sync` 첫 줄 — `--project` ≠ 공용 루트면 `SKIP plist-env <라벨> (--project 가 git 공용 루트 아님: 루트=<경로> — plist 는 루트 설치에서만)` 1줄 · 렌더·교체·launchctl 0(dry-run 같음). shim·훅·githooks 설치는 그대로. git 밖은 기존 흐름(렌더기 ERROR).
- **ft_plist_env.py** render(이중 방어 · 외부 호출 0): 루트에 `.git` 폴더가 없으면 `RenderError 루트가 git 공용 루트 아님(워크트리|.git 없음)` rc3. bin·kit 짝 cmp0.
- **ft_live_install_check.py**: `plist_root`(공용 루트 · git 밖이면 그대로) — plist-env 대조와 `HINT plist-env … --project` 둘 다 공용 루트. STALE-COPY HINT 는 워크트리 그대로. bin·kit 짝 cmp0.
- **시험**: `test_live_install_check_plist_env.sh` 픽스처 프로젝트를 git 리포로 + r457ⓐ~ⓔ(ⓐ 루트 OK 그대로 ⓑ 워크트리 dry-run·apply SKIP 1줄 · plist cmp 불변 · launchctl 0 · shim 설치 됨 ⓒ 렌더기 워크트리 rc3 · 루트 rc0 ⓓ install-check 워크트리 → 대조·HINT 공용 루트 ⓔ git 밖 install.sh rc1 · install-check rc3) — 32 PASS. 실 머신 dry-run(읽기만): 루트 `OK plist-env` · v6-realtime-live `SKIP plist-env` · plist cksum 불변. 증거 `harness/evidence/r457/`.
- 범위 밖: 템플릿 `--project __PROJECT__` 자리 · 미러 스크립트 · r413 HINT 문구. base 에서도 빨강인 `test_live_install.sh`·`test_live_install_check.sh` ⑥·`test_live_install_check_tip.sh` ⓕ 는 master-steps 에 기록(새 단위 후보).

## 2026-10-19 — 루트 3분리(r385 r3)·명부 폴더 raise(R231a) 뒤 빨강이던 팩 시험을 픽스처로 초록 · `ft-harness-info.sh seats` 는 comm 을 못 풀어도 목록·팀 명부 절을 찍는다 (1.1.23)

카드 r455a · master 111909 · arch#100 실측 · 판정 1395(«기존 RED» 변명 0). 도구 계약이 바뀌었는데(데이터 루트 = FT_ROOT → `.fable-team/LIVE_ROOT` → 옛 설치 꼴 · comm 폴더 필수 · 명부 폴더 없음 = raise · close 가 `ft-seat-reap.sh` 호출) 그 계약을 쓰는 시험 픽스처가 같은 단위에서 안 바뀌어 첫 줄 ERROR 로 끝나고 있었습니다.

- **키트 `ft-harness-info.sh` seats**(bin·kit 짝 cmp0): `ft_comm_dir` 실패 → `exit 1` 대신 `ALIVE` 비움 = ⚠ NOAGENT 표시 0(머리 주석 «판정기 없거나 판정 불가면 표시 0» 그대로) · 세션 목록·팀 명부 절은 그대로 찍는다. 다른 절 변경 0. 옛 판: comm 없는 git 리포에서 rc1 `ERROR` 1줄 · 새 판: rc0 명부 절 출력.
- **픽스처(단언 약화 0 · env·mkdir·스텁만)**: `test_role_spawn_name` `FT_ROOT=<임시 리포>` + `.fable-team/comm` · `test_graphics_install` ⑥ `FT_ROOT` + comm + 임시 ROOT 에 `origin/main` ref(R400 r3 명단 읽기) + 팩엔 `design/graphics/` 가 없어 조용히 실패하던 GOAL 복사를 «설치된 골 3줄로 시험용 GOAL» 로 · `test_graphics_690` ② 스텁 ALIVE 유/무 2케이스(무 = 외부 FT_ROOT·ALIVE 를 지워 판정 불가 경로 강제 · ERROR 줄 0 단언) · `test_proposal_gate_wiring` 14 create-pair 계약(FT_ROOT+comm · FT_ME · FT_ISSUES_SEATS) + 14c `FT_MBOX_CMD` 스텁 · `test_board_publish`·`_tick` `mkdir -p $T/ft/.fable-team` · `test_nano_team_env` 임시 bin 에 `ft-seat-reap.sh` 스텁(r448 · 실기계 프로세스 0).
- **`test_autonomy_preflight`**: 머리 주석 1줄(소요 ≈ 4분 · 120초 상한이면 rc=124 — 빨강 아님). 코드 0.
- **결과**(팩 루트 · GIT_* 0): role_spawn_name · proposal_gate_wiring · board_publish · board_publish_tick · nano_team_env · autonomy_preflight(600 s · 113 checks fail=0) · harness_info(덤 · 옛 rc2) rc0. 남은 빨강 = `test_graphics_install` ⑦ · `test_graphics_690` ⑦(라이브 governance·harness-map 정본이 staged 판으로 승격된 적 없음 — 카드 «판정 요청» · 시험 결함 아님) · `test_planner_nano_path` 하위 `test_nano_spawn_body_press`(r455b).
- **범위 밖(새 카드 후보)**: `test_team_literal_paths`(같은 comm 계약 + 골 표 정본 파일 없음) · `test_agent_alive_fg_judge`(BYZ 경로 목록 · 이식 누락) — 둘 다 base(ed8e118e)에서도 rc1.

## 2026-10-19 — `ft-inbox mark <seq>` 가 큐에 없는 쪽지도 우편함 파일(현행·로그·회전본)에서 찾아 적재 뒤 표시한다 (1.1.23)

카드 r430 · planner 증거 ②(110829) · EVAL I3 · arch#96. planner 가 `mark 110726` 류를 치면 `REJECT 대상 못 찾음(좌석 …)` 이 났습니다. ★실측(10-19): 원인은 카드 가정(«mark 가 mailbox.jsonl 만 본다»)이 아니었습니다 — 쪽지 조회 `mail_files()` 는 이미 현행 → `mailbox.log.jsonl` → 회전본(숫자 순)을 다 보고, mark 는 우편함이 아니라 «좌석 큐»(`state/inbox/<계보>.jsonl`)만 봅니다. 110726·110770·110796 은 send 때 큐 적재가 빠져(planner 큐 5994행에 없음 · 원본은 `mailbox.log.jsonl`) 큐에 행이 없었습니다★ — 같은 seq 를 임시 루트에서 `ingest` 하면 바로 들어갑니다.

- **`ft_inbox_core.find_seq(seq)`**(새): `mail_files()` 순서 첫 1건 → (파일 경로, 행) · 글자 선거름(`"seq": N`) 뒤에만 json 해석 — 5MB 회전본 끝 행 0.09 s. `find_mail` 은 그 래퍼(ingest 그대로).
- **`ft-inbox.py` locate**(mark·report 공통): 좌석 큐에 없는 숫자 seq 는 우편함 파일에서 찾아 ①수신 계보 = 호출 좌석 계보면 `ingest`(같은 행 꼴 · `INGEST …` 줄) 뒤 대상으로 삼고 ②남의 계보 앞 쪽지면 기존대로 REJECT(남의 큐·내 큐 쓰기 0) ③어디에도 없으면 기존 줄 뒤에 ` · 대상 못 찾음 seq=<n> (<N> 파일 조회)` rc1(조용한 통과 0).
- **mark 출력**: 기존 `OK <큐> seq=…` 다음에 숫자 대상이면 `MARKED seq=<n> file=<쪽지 원본 우편함 파일 이름>`(큐에만 있으면 `file=없음(큐만)`). 표식 저장 위치는 기존 그대로(좌석 큐 행 `mark`).
- **시험**: 새 `test_inbox_mark_rotated.sh` 23 PASS(ⓐ mailbox.jsonl ⓑ log.jsonl ⓒ 회전본 `.2`·`.10` 숫자 순 ⓓ 없음 rc1 + 문구 + 큐 불변 ⓔ 5MB ≤1 s ⓕ 600/300 0 ⓖ 남의 계보 앞 쪽지 rc1 · 재표시 적재 0) · 옛 코드에서 15 FAIL. 기존 `test_inbox*`·`test_ft_mbox_inbox_ingest`·`test_proposal_approve_inbox` rc0.
- **범위 밖**: send 때 적재가 왜 빠졌는지(적재 실패는 `WARN` 만 stderr · 실패 경로 관측은 실사건 때) · recv/peek 조회 범위 · 회전 정책 · stall-scan d 판정.

## 2026-10-19 — arch 가 죽은 «arch 상시» 팀의 교대 교착을 푼다: `ft-role-spawn --team <팀>` + arch 없음 REJECT·ERR 문구가 «있는 길» 명령 1줄을 적는다 (1.1.24 · 묶음 가지에 재적용)

카드 r437 · master 110967 · planner 110961(판정 2346). feature master#30 교대가 `REJECT 그 팀 arch 좌석 없음 — 먼저 arch 를 열어라(ft-role-spawn arch)` 로 막혔는데, 안내가 가리킨 `ft-role-spawn.sh` 는 v65 명부(seats.json)·v65 폴더에 고정돼 feature arch 를 못 열었습니다(CFO 선례와 같은 뿌리). 죽은 arch 의 자기 교대(successor-open)는 게이트가 이미 통과시키므로, 도구가 그 길을 정확히 적게 합니다. 게이트 판정 기준(R342)은 불변 · master 교대 예외 0.

- **ft-role-spawn.sh**: `--team <팀>`(기본 v65 = 동작 불변). 팀이면 명부 `seats-<팀>.json` · 인박스·README = `ft_team_in "$WT" <팀>` 폴더 · 이름 `byz-<팀>-<역할>-<에이전트>#N`(계보 하나) · 페널티 게이트 팀 = 그 팀. 명단 밖 팀·폴더 칸 오류·명부 없음·`<팀> SEATBELT-README.md 없음: <경로>`·인박스 없음 = REJECT(v65 로 조용한 대체 0 · #0 RULE). 명부 `_<역할>` 이 교체 대상 밖 좌석(죽은 arch · 행 없음)을 가리키면 REJECT + successor-open 명령 안내(두 arch 0). 빈 역할 키(`_master`·`_arch`·`_da`·`_tester`)는 새 좌석으로 채운다(팀 모드만).
- **ft_teamset.py** `arch_open_hint`(판정기 하나): arch 없음 사유 끝에 `→ 열기: …` 1줄 — 명부 `_arch` 에 이름 있음 = `ft-successor-open.sh '<그 arch>' <팀 워크트리> --name '<베이스>#N+1' --agent … --model … --body-file …` · 비었음 = `ft-role-spawn.sh arch --team <팀>`. 같은 문자열이 `ft-successor-open` REJECT(arch-live NO 줄)와 `ft-teamset-check` ERR 줄 둘 다에 실린다.
- **ft-successor-open.sh**: REJECT 머리 `먼저 arch 를 열어라(ft-role-spawn arch)` → `(아래 «→ 열기» 명령 · R437)`. **ft-teamset-check.sh**: 머리 주석에 ERR arch 줄 형식 1줄(동작 불변). bin·kit 짝 cmp0.
- **시험**: `test_role_spawn_team.sh` ⓐ~ⓖ ALL PASS(ⓐ 실제 명부 쓰기 = seats-feat.json·_arch 채움·seats.json 쓰기 0 · ⓑ v65 불변 · ⓒ README 없음 REJECT · ⓓ 명단 밖·_arch 충돌 REJECT · ⓔ successor-open 문구 2꼴 · arch 자기 교대 통과 불변 · ⓕ teamset-check ERR 2꼴 · ⓖ 600/300 0). 증거 `harness/evidence/r437/`.
- 범위 밖(기록만): 팀 폴더 SEATBELT-README 생성(`ft-team-upgrade` 몫 — feature 폴더엔 아직 없음 → 그때까지 feature arch 는 successor-open 경로) · 명부 `_arch` 가 죽은 좌석을 가리키는 행 자동 보정.

## 2026-10-19 — 정지 감시기가 정지 중인 팀에 «지금 spawn» 을 독촉하지 않는다: 명부 stop-ready 판정 · 정지 판정 실패를 정지 없음으로 읽지 않음 (1.1.23 묶음: r426·r427·r428·r429)

카드 r428 · 쪽지 110864(v65 «대기 카드 85장 · 지금 spawn»)·110865 · arch#96 실측 · EVAL I17. 오빠가 «정지 레디·팀장 하나만»(판정 2341·2342)을 건 v65 에 stall a 독촉이 나갔습니다. 실측: 정지는 쪽지 문장으로만 걸려 정지 파일 0(`hold=none`), 명부 master 행은 `role=stop-ready` 였는데 감시기는 master 의 role 을 보지 않았습니다. (감시기 파이썬은 R320b 부터 SPAWN_HOLD 를 `status --check` 로 이미 읽는다 — arch 실측의 «grep 0» 은 래퍼 `ft-stall-scan.sh` 만 본 값.)

- **ft_stall_detect.py**: `load_teams` 가 팀마다 `master_stop`(명부 `_master` 행 `role=stop-ready` · ft-seat-close R297 표기)을 싣는다. `policy_stop` — 유효 정지 글 = `SPAWN_HOLD 유효 · 정지 중(hold=<번호>) · 독촉 0` · 판정 불가 글은 모두 `ERROR` 로 시작 · ★`--check` 가 측정 실패(status rc4 «ERROR hold …»)를 rc3 으로 감싸 돌려주던 것을 «정지 없음» 으로 읽어 a 를 내던 구멍을 막는다(본문에 `ERROR hold` 가 있으면 판정 실패)★.
- **ft_stall_scan.py**: master 가 살아 있고 stop-ready 이며 유효 정지가 없으면 그 팀 a 대신 c 1건(`정지 레디(명부 role=stop-ready)인데 정지 파일 0 — ft-spawn-hold.sh set 필요 · 독촉 0`) + planner 쪽지 `[정지 파일 0] <팀> master <좌석> …` 1통(팀당 하루 1회 · 표식 `state/stall-scan.stopready-<YYYYMMDD>` · urgent 아님). 판정 실패면 출력에 `ERROR SPAWN_HOLD 판정 실패 … — a 독촉 0` 1줄. b·d·페널티·RESOURCE_FREEZE 무변경. bin·kit 짝 cmp0.
- **시험**: `tests/scripts/test_ft_stall_scan.py` r428 ⓐ~ⓔ(ⓐ 진짜 `ft-spawn-hold.sh set` 정지 파일 → a 0·c 1·master 쪽지 0·로그 `act=c … hold=2341`·파일 유지 ⓑ stop-ready → c 1·planner 1통·같은 날 2회째 0 ⓒ 정지 없음 → a 그대로(r409 선행 미판정 포함) ⓓ 해제 조건 측정 실패 → a 0·ERROR 1줄 ⓔ 600/300 0) — base 코드로 ⓐⓑⓓ RED · 53 passed. 증거 `harness/evidence/r428/`.
- 범위 밖: 정지 파일 자동 생성(정지는 사람·planner 의 `set`) · r409 선행 줄 판정 · b·d.

## 2026-10-19 — 승계 은퇴가 «모든 명부»의 라우팅 칸(`_hil_route`…)을 후계로 바꾼다 — planner 교대 뒤 손 갱신 0

카드 r429 · planner 증거 ① · EVAL I2 · arch#96 실측. `ft-seat-retire <구> <후계>` 는 «옛 이름이 값인 `_*` 칸 전부» 를 바꾼다고 돼 있었지만 고치는 파일은 자기 팀 명부 하나뿐이었습니다. planner master 이름은 모든 팀 명부의 `_hil_route`(사람 판정 요청이 가는 곳)에 들어 있어, planner 가 승계할 때마다 나머지 명부를 손으로 고쳐야 했고 그동안 [HIL] 쪽지가 은퇴 좌석에 쌓였습니다(mbox-guard forward 로 겨우 구제).

- **ft-seat-retire.sh**: 자기 팀 명부 은퇴 뒤 같은 폴더(루트 `.fable-team`)의 다른 `seats*.json` 전부에서 값이 <구> 인 «라우팅 칸»(`ROUTE` = `_hil_route`·`_planner`·`_desk_route` + 이름이 `_route` 로 끝나는 칸)만 <후계> 로 · 역할 칸(`_master`·`_arch`…)은 자기 팀 명부만. 전부 검증 뒤 쓰기 — 명부 하나라도 JSON 손상이면 `ERROR 명부 JSON 손상 [<파일>]` rc1 · 쓰기 0. 바뀐 파일마다 `.bak-retire-<ts>` · tmp→교체. 출력 첫 줄 끝에 ` files=<N> routes=[<파일>:<칸>…]`(앞부분 `RETIRED <구> -> <후계> file=… keys=[…]` 그대로).
- **R282 ② 판정 개정**: 옛 행이 어느 명부에도 없을 때의 «다른 명부에서 현역» REJECT 는 역할 칸만 본다(라우팅 칸에 옛 이름이 있는 건 이번에 바뀔 대상 — 막지 않음).
- **시험**: 새 `test_seat_retire_rosters.sh` ⓐ~ⓔ(files=3 · 남의 `_master` 불변 · R282 ② · 손상 1개 = 전부 0 · 600/300 0) · `test_seat_retire.sh` ③⑨ 첫 줄 기대값에 ` files=1 routes=[]`.
- 범위 밖(이름만): 명부 칸 이름 표준화 · `ft-tick-team.sh retarget_seat` 통합 · NOOP(이미 은퇴) 재실행 때 남은 라우팅 칸 쓸기.

## 2026-10-19 — tmux 세션이 이미 없는 «죽은 좌석» 명부 행을 `--verdict` 가 닫는다(CLOSED-DEAD) · 재개 기록은 보존 · `--reopen` 으로 되살린 좌석 복원

카드 r427 · master 증거 ⑫(110863) · EVAL I16 · planner 판정 2344. «팀장 하나만»(판정 2341)으로 feature 팀 13석을 `ft-seat-close --verdict` 로 닫으려 했더니 전부 `HELD … NORECORD 조회 불가: pane 식별 조회 불가` 였습니다. 그 좌석들은 tmux 세션이 이미 없어 pane 에서 대화 uuid 를 뽑을 수 없는데, 닫기 도구는 «살아 있는 좌석» 길만 있었고, 기록 실패 처리에서 기존 재개 기록을 `.stale-<ts>` 로 «무효화» 해 지웠습니다(byz-feature-da-codex#2).

- **ft-seat-close.sh**: `--verdict` 에서 `tmux has-session` 0 이면 죽은 좌석 분기 — `ft-seat-retire --record-only --verdict <번호> --keep-existing` → 명부 행 stop-ready + `_closed.dead=true`(role 은 stop-ready 그대로 — ft-tick resume_rows·seats-lint·stall 이 이 값으로 «재개 0» 을 판정하므로 새 role 값을 만들지 않음) · 그 좌석 값인 `_*` 칸 "" · kill 0 → `CLOSED-DEAD <좌석> record=<kept|new|NORECORD> handoff=<칸들|->` rc0 · 비운 칸이 있으면 «교대 0 · planner 1줄» 안내. NORECORD 여도 닫는다(죽은 좌석은 kill 할 것 0). 살아 있는 좌석 경로(HELD rc3)는 그대로.
- **ft-seat-close.sh --reopen <좌석>**: zombie-clean resume 으로 되살린 좌석(세션 있어야 함 · 없으면 REJECT)의 행을 role=`_closed_role`(없으면 active)·tick=`_closed_tick` 로 되돌리고 `_closed*` 제거 · 닫을 때 `_closed_from`(파일:칸) 에 적어 둔 칸이 지금도 "" 면 다시 그 좌석으로(그새 교대된 칸은 덮지 않음) → `REOPENED <좌석> roles=<칸들> role=<role>`. 재개 기록은 그대로.
- **ft-seat-retire.sh**: `--keep-existing`(`--record-only` 전용) — 기존 기록 있으면 새 시도 0 → `RESUME kept <경로>` · 없고 세션도 없으면 대화 기록 탐색 1회(`~/.claude/history.jsonl` 의 그 좌석 이름 줄 → project·sessionId → 그 jsonl 머리 64KB 에 `"agentName":"<좌석>"` «정확히 1개» · binding.source=`dead-agent-name`). 기록 실패(NORECORD)는 옛 기록을 건드리지 않는다(무효화 0 — 닫기 판정은 zombie-clean 이 binding `--expect` 로 다시 본다 · DA⑥ H1 개정) · 새 기록 «성공» 때만 옛 것을 `<경로>.prev-<ts>` 로.
- **시험**: `test_seat_close.sh` r427 ⓐ~ⓓ·ⓖ·ⓕ(진짜 retire · 가짜 tmux·HOME) · 새 `test_seat_retire_keep.sh` ①~⑧ · `test_seat_retire.sh` ⑨H1·⑩ⓓstale 기대값을 «보존» 으로 개정.
- 범위 밖(이름만): zombie-clean resume 이 `--reopen` 을 자동 호출 · 죽은 좌석 자동 수거 · `_*` 칸 교대 자동 선정(planner 결정) · codex 좌석의 죽은 뒤 기록 탐색(rollout).

## 2026-10-19 — 설치기가 쪽지→슬랙 미러 launchd plist 의 환경(FT_ROOT · inbox 경로)까지 템플릿에서 갱신하고, install-check 가 `PENDING plist-env` 를 센다 (버전 = master 착지 순)

카드 r426 · EVAL-new-harness-overnight-20261019 §3 I1 · arch#96 실측 · planner 판정 2344. 10-19 00:35~08:22 미러(`com.hermes.byz-mbox-slack-mirror`)가 FT_ROOT 없이 옛 워크트리 bin(`v6-realtime-live/.fable-team/bin/ft-inbox.sh`)을 불러 1분마다 exit1(917회) — 오빠 슬랙 수신 7시간 47분 정지. 설치기는 bin·hermes 스크립트만 바꾸고 plist 환경은 그대로였고, install-check 는 Label 적재만 봐서 «OK» 였다(사람이 08:22 손 수정 `.bak-ftroot-20261019`).

- **`kit/slack-mirror/com.hermes.byz-mbox-slack-mirror.plist.template`**: `EnvironmentVariables` 에 `<key>FT_ROOT</key><string>__ROOT__</string>` 1줄. `slack-mirror/install.sh` 는 `__ROOT__ = BYZ_ROOT` 치환 1칸 추가(처음 설치 경로도 같은 렌더).
- **`kit/fable-team/bin/ft_plist_env.py`(새 · bin 짝)**: 설치기 관리 라벨 표 `MANAGED`(지금 = 미러 1) · `render` = 템플릿 + 설치된 plist 의 머신별 값(`__PY__`·`--project/--seat/--channel/--mention/--repo`) 보존 + `__ROOT__`=프로젝트 루트 · `__INBOX_BIN__`=`<LIVE_BIN>/ft-inbox.sh` · `__MAILBOX__`=`<루트>/.fable-team/comm/mailbox.log.jsonl`. 루트·LIVE_BIN·설치값 없음 · 자리표시 잔재 · plist 해석 실패 · 렌더본 FT_ROOT≠루트 = `ERROR` rc3(조용한 통과 0).
- **`harness/install.sh`**: plist 절 — «설치된 것만» 렌더본과 cmp → 다르면 `--apply` = `.bak-r426`(첫 원본 보존) + 교체 + `launchctl bootout`·`bootstrap`·`kickstart -k`(변경 때만) · 같으면 쓰기 0 · `--dry-run` 은 `PENDING plist-env <라벨>` 줄만(rc0) · 미설치 = `SKIP`(새로 깔지 않음 · 처음 설치는 slack-mirror/install.sh). launchctl = `FT_LAUNCHCTL`(시험 주입).
- **`bin/ft_live_install_check.py`**(bin·kit 짝 cmp0): plist 행 중 관리 라벨은 설치본 = 렌더본 바이트 대조 → 아니면 `PENDING plist-env <라벨> (… FT_ROOT=<루트>)` + `HINT plist-env bash <하네스>/install.sh --apply --project <루트>`. 루트 = `--project` 또는 리포 공용 루트(shim 대조와 같음) · LIVE_BIN 없음 = ERROR rc3(`--project` 를 주라는 안내). `LIVE-MAP.tsv` 머리 설명 1줄 갱신.
- **카드 편차 2**: ①템플릿을 `kit/launchd/` 새 파일로 만들지 않고 이미 있던 `kit/slack-mirror/…plist.template` 을 고쳤다(arch 실측이 `kit/launchd/` 만 봄 · 같은 라벨 템플릿 2개 = 두 정본) · 자리표시는 기존 `__X__` 꼴 ②설치 적용은 `kickstart` 만으로는 launchd 가 plist 를 다시 읽지 않아 `bootout`→`bootstrap`→`kickstart -k`(slack-mirror/install.sh 와 같은 순서).
- **시험**: `tests/test_live_install_check_plist_env.sh` ⓐ~ⓔ 24 PASS(임시 HOME·가짜 launchctl · 실 등록 0). 기존 `test_live_install_check.sh`·`test_live_install_check_tip.sh` 는 base 에서 각 18·12 FAIL(r385 뒤 `--kit` 미전달 · shim 시험 r413 이 고친 것과 같은 꼴) → `chk()` 에 `--kit "$KD"` 1칸으로 1·2 FAIL 로 — 남은 3건은 이 카드 밖(아래). 증거 `harness/evidence/r426/`.
- **base 부터 남은 FAIL 3(기록만 · 고침 단위 필요)**: ①`test_live_install_check.sh` 린트 ⑥ «구현 범위가 scripts/harness-install/ 언급 + 없음 → REJECT» — `ft-index-lint.sh` 가 옛 키트 경로 언급을 더는 안 센다 ②③`test_live_install_check_tip.sh` ⓕ 2건 — `ft-index-move-install.sh` 가 검사 도구에 `--kit` 없이 `--repo` 만 넘겨 임시 리포 픽스처에서 «하네스 루트가 --repo 밖» ERROR.
- **master 절차**(착지 뒤): ①`bash <팩>/feature-pack/fable-team/harness/install.sh --dry-run --project /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` → `PENDING plist-env com.hermes.byz-mbox-slack-mirror` 1줄 확인(나노 실측 10-19: 의미 차이 = `--inbox-bin` 옛 워크트리 bin → `~/.claude/fable-team/live/<버전>/bin/ft-inbox.sh` 하나 · FT_ROOT 는 손 수정본과 같음) ②`--apply` → `PLIST applied …` · `~/Library/LaunchAgents/com.hermes.byz-mbox-slack-mirror.plist.bak-r426` 실재 ③`launchctl print gui/$UID/com.hermes.byz-mbox-slack-mirror` state=running ④`~/.hermes/logs/byz_mbox_slack_mirror.err` 꼬리 1분 관측 — 새 줄 0(특히 «FT_ROOT 없음»·ft-inbox 오류) ⑤`ft-live-install-check.sh --range <병합 전 main>..<착지 sha> --project <BYZ 루트>` → OK ⑥실사건 = 다음 planner 쪽지가 슬랙 채널에 미러됨(`.out` 1행). 되돌림 = `cp -p <plist>.bak-r426 <plist>` + bootout·bootstrap.

## 2026-10-19 — BYZ 리포 안 1Password(op) 볼트 명령은 develop 볼트 + develop 토큰 꼴만 — 홈 훅 `op-vault-develop-gate.sh` (1.1.22)

카드 r451 · master 111771 · desk 111757 · 오빠 «op 볼트는 무조건 develop 사용하라고 강력지침» «kskill은 슬랙 자동화용이다». 기본 `OP_SERVICE_ACCOUNT_TOKEN` 은 kskill(슬랙 자동화 전용) 볼트만 보여, 좌석이 그냥 `op item create` 를 치면 kskill 에 들어갔습니다(컨시어지 시연 계정 8개). 지침 줄(전역 하드 룰 15)은 이미 있어 이 단위는 «막는 장치» 입니다.

- **새 `kit/hooks/op-vault-develop-gate.sh`**(PreToolUse:Bash · 홈 훅): 명령을 구분자(`; && || | 개행 $( \``)로 나눠 실행 낱말이 `op` 이고 하위 명령이 `item create|edit|get|list|delete` · `document …` 이면 `--vault develop`/`--vault=develop`, `read` 면 모든 `op://` 참조의 볼트가 develop — 그리고 명령 글자에 `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"` 대입(앞 대입·`export`·`env` 꼴)이 있어야 통과. 아니면 exit 2 + stderr `REJECT op 볼트 = develop 만 — kskill 은 슬랙 자동화 전용(오빠 10-19) · 꼴: … (빠진 것: …)`. `op vault list`·`whoami`·`signin`·`account`·`--version`·`--help`·`item move` 등 볼트 선택이 아닌 명령은 통과. `bash -c "…"` 문자열 안도 검사, 따옴표 안 글자·grep 인자·커밋 메시지는 실행 아님.
- **범위 = BYZ 리포 안만**: `FT_ROOT`(있으면) 또는 cwd 의 origin URL 이 `…/byz-agents(.git)` 이거나 최상위에 `.claude/skills/byz-keys/`. ★공용 루트 체크아웃(옛 main)에는 byz-keys 가 없고 팩 리포에도 `.fable-team` 이 있어(10-19 실측) 파일 표식 하나로는 못 가린다 — origin URL 이 주 판별★. BYZ 밖(hermes 슬랙 자동화)은 통과.
- **fail-open**: 입력 JSON 못 읽음·파이썬 예외 = 통과 + stderr `WARN`(다른 홈 훅과 같은 꼴 · 거절만 하는 훅). 외부 호출 0(위반 후보일 때만 로컬 git 2회 · 각 5 s). ★토큰 값은 읽지도 찍지도 않는다(OP_* 환경값 접근 0 · 명령 글자만)★.
- **`harness/install.sh`** HOME_HOOKS 에 `op-vault-develop-gate.sh` 1토큰(→ `~/.claude/hooks/` cp -p → cmp) · **`templates/settings-hooks.snippet.json`** PreToolUse `Bash` 1항(`$HOME/.claude/hooks/op-vault-develop-gate.sh` — 홈 settings.json 등록 꼴 그대로 · 실제 등록은 master).
- **시험**: 새 `test_op_vault_develop_gate.sh` 49 PASS(ⓐ kskill 생성 REJECT + 안내 원문 ⓑ develop 볼트인데 토큰 0·기본 토큰 대입 REJECT ⓒ 올바른 꼴·`--vault=`·export·env·`op read op://develop` 통과 / op://kskill·document kskill REJECT ⓓ 볼트 인자 0 REJECT · 볼트 선택 아닌 7 명령 통과 ⓔ BYZ 밖·git 밖 통과 · 표식 없는 origin byz-agents 리포 REJECT · FT_ROOT=BYZ REJECT ⓕ `&&`·`;`·`|`·`$( )`·`bash -c`·절대경로 op REJECT · 따옴표/grep/커밋 메시지·tool≠Bash·못 읽음·빈 입력 통과 ⓖ 600/300 0 · 가짜 op 호출 0 · OP_ 환경값 접근 0 · 가짜 토큰 값 출력 0 · install/스니펫/권한/bash -n). 기존 `test_old_team_path_deny`·`test_install_hook_check`·`test_harness_freeze_gate` rc0.
- **범위 밖**: kskill 에 이미 생긴 시연 계정 8개의 develop 이전(ops · `op item move` 는 막지 않음) · hermes 쪽 op · 토큰 교체 · `skill/templates/settings-hooks.snippet.json`(이미 키트 사본과 다른 쌍둥이 · 이 단위 손대지 않음).

## 2026-10-19 — planner 앞 쪽지가 «조용히 아무도 안 받는» 상태를 소리 나게 한다: quiet 는 세션 안 감시와 한 쌍 (1.1.21)

카드 r408 · desk 110229 실측 · planner 110234 · master 110237 · arch#94. 판정 876 으로 planner `_master` 는 doorbell 을 받지 않고 세션 안 감시(`ft-inbox-watch.sh` + Monitor)로 받는데, 승계(#71→#72) 뒤 감시가 안 걸려도 send 는 `doorbell=quiet` 만 찍어 큐가 3~5분씩 쌓였습니다(수동 깨움 5회).

- **판정기 하나 `ft-mbox.sh watch-alive <좌석>`**(rc0 `OK watch` / rc3 `NO watch`): 감시 실체 = `ft-inbox-watch.sh` 가 exec 한 `python3 -u - <bin> <좌석>`(셸 이름은 프로세스에 안 남는다) · 끝 인자 정확 일치 ∧ `<bin>/ft-inbox-watch.sh` 실재 · 목록 `FT_PGREP`(시험) 또는 `pgrep -lf`.
- **send/relay**(키트 `ft-mbox.sh` · 좌석들이 쓰는 `comm/mbox.sh`): user_facing 좌석에 감시가 없으면 `doorbell=quiet(WATCH 없음)` + 하네스 master(`seats-harness.json` `_master`) 앞 `[긴급 · planner watch 없음] <좌석> · 감지 HH:MM · 계기 쪽지 #N · 시작: Monitor → bash <루트>/.fable-team/bin/ft-inbox-watch.sh <좌석>` 1통 · 같은 좌석 10분 1회(표식 `state/planner-watch-missing.<좌석>`) · 판정 불가 `quiet(WATCH 판정 불가)` · 오빠 pane 주입 0(876 불변) · 명시 `ring` 불변.
- **ft-teamset-check**: planner 팀 `_master` 감시 없음 → `ERR planner watch 없음(ft-inbox-watch.sh <좌석>)` rc1(`FT_TEAMSET_WATCH` 시험 대체).
- **시험**: `test_inbox_watch.sh` r408 절(ⓐ~ⓔ · comm·키트 두 경로 · 미끼 3 = 접두 좌석·시작 명령 실은 send·다른 bin) · 옛 코드에서 20 FAIL. 픽스처 2: `test_ft_mbox_inbox_ingest.sh` 변이 줄 글자 · `test_arch_required_gate.sh` 감시 판정 가짜.

## 2026-10-19 — design/ 아래 증거 로그(.log·.out·.nohup·guard/poller 로그)는 커밋도 착지도 안 된다 · 이미 들어간 614개는 index 에서만 뺀다 (1.1.20)

카드 r449 · master 111666 · 오빠 «아니 이 무의미한 파일을 왜 커밋하는데? 관리도 안되고 무식하게 아래로만 커지는 로그성파일인데». `.gitignore` 의 `*.log` 를 `git add -f` 가 뚫어 BYZ origin/main `design/` 아래에 로그성 파일이 쌓였습니다(실측 643bf03512: 판정식 614개 303.2 MB). add 단계는 `-f` 로 무력이라 index 단계·착지 단계 두 곳에 섭니다.

- **판정식 한 곳 `ft-evidence-lib.sh`**(새 · POSIX · source 전용): `design/` 아래 ①끝이 `.log·.out·.nohup·.stdout·.stderr·.pid` ②이름에 `guard·poller` 가 들고 끝이 `.jsonl·.jsonl.gz·.txt`. md·json·py·sh 는 이름에 guard·poller 가 있어도 아님(설계 문서 203·poller_intent.json 등 보존). 카드 문구의 «이름에 guard/poller 든 것 전부»는 md·py 까지 잡아 범위를 좁혔습니다 — 아래 «편차».
- **`kit/fable-team/githooks/pre-commit`**(새 · BYZ `.fable-team/githooks/pre-commit` 2307 B 를 키트로 올림 · v6 공유 index 차단·beads 위임 그대로): «증거 로그» 절 — `git diff --cached --name-only -z --no-renames --diff-filter=AM -- design` 중 판정식 → stderr `EVIDENCE-LOG-GATE: 증거 로그 <n> staged — git rm --cached <목록 ≤10> · 요약은 SUMMARY-*.md` exit 1. `commit --only`(임시 index)도 같다. 예외 = `BYZ_EVIDENCE_LOG_OK=<사람 승인 번호>` ∧ `<공용 루트>/.fable-team/state/evidence-log-ok.<번호>` 표식 둘 다. 판정식은 `<훅 폴더>/../LIVE_BIN` 의 bin(없으면 `../bin`) — 못 찾으면 design/ 이 staged 일 때만 REJECT(조용한 통과 0 · design/ 밖 커밋은 통과).
- **`ft-merge-land.sh`**: main 확인 직후 가지 diff(`M...S --diff-filter=AM --no-renames -- design`) 에 판정식 → `REJECT 증거 로그 <n> — git rm --cached 뒤 다시: <파일명…> (착지 0)`. 판정식 lib 못 읽으면 rc2 실행 0. 113줄(≤120).
- **`ft-evidence-untrack.sh [--dry-run] <리포 루트>`**(새): `git ls-files -z -- design | 판정식` → `git --literal-pathspecs rm --cached --pathspec-file-nul`(디스크 보존 · 이력 재작성 0 · 커밋은 부른 쪽) · 출력 `UNTRACK n=<n> MB=<m> dry=<0|1>`(크기 = index blob) · 미커밋 tracked 변경 있으면 REJECT «[wip] 먼저».
- **`harness/install.sh`**: `--apply` 가 LIVE_BIN 연결 «뒤» 에 `kit/fable-team/githooks/*` → `<프로젝트>/.fable-team/githooks/` cp -p → cmp(덮기 전 `<파일>.bak-<버전>` · 출력 `GITHOOKS copied= same=`) · dry-run `GITHOOK` 줄 · `core.hooksPath` 가 다른 곳이면 WARN. **LIVE-MAP**: `fable-team/githooks/*` skip 행(설치 = install.sh · 대조 = cmp 명령).
- **시험**: `test_evidence_log_gate.sh` 54 PASS(판정식 단위 18 · ⓐ add -f 5개 REJECT·커밋 0 · ⓐ' commit --only · ⓑ md·sh 통과 · ⓒ env/표식 4조합 · lib 없음 REJECT/design 밖 통과 · ⓓ 가지 diff z.out REJECT 1줄·요약 md 착지·untrack(D) 착지·lib 없는 설치 rc2 · ⓔ untrack dirty REJECT·dry-run 목록 = 판정식·적용 n=8·디스크 보존·.gitignore 뒤 status 0·D 커밋 훅 통과·멱등·usage · ⓔ' sparse-checkout 워크트리(cone 밖 포함 · BYZ 실측 첫 적용이 59/614 에서 실패 → `rm --cached --sparse`) · ⓖ install githooks cmp0·.bak·멱등·WARN · ⓕ 600/300·외부 호출·GIT_* env 0). `test_merge_land_state_dir.sh` 설치 묶음에 `ft-evidence-lib.sh`·`ft-harness-root.sh` 추가(base 에서 6 FAIL 이던 r385 뒤 누락 → ALL PASS). 증거 `harness/evidence/r449/`.
- **편차·범위 밖**: 판정식 614/303 MB vs 카드 955/361 MB — 차이 = 이름에 guard·poller 든 md·json·py·sh(설계 문서·도구 · 지우면 안 됨)와 이름 없는 `*.jsonl`(results·values 측정표 202개 — 원장이 가리킴). `test_live_install_check.sh`·`_tip.sh` 실패 19·13 은 base 와 같음(r385 뒤 픽스처 옛 경로 · 별 카드).

## 2026-10-19 — 좌석을 닫으면 그 좌석이 띄운 백그라운드 루프도 멈춘다(reap left=0 · 못 멈추면 CLOSE-FAIL) · 감시 루프는 상한·stop-file 래퍼 없이는 착지 0 · tmuxc 가 좌석 표식 FT_SEAT 를 심는다 (버전 = 착지 순서대로 master · r447 뒤) (1.1.19)

카드 r448 · master 111691 · 오빠 «이렇게 무식하고 멍청하게 쌓고있는건데». v65 tester67 이 띄운 `while … sleep 5 … >> guard.log` 루프 5개가 좌석 소멸 뒤 ppid 1 고아로 06:00~13:19 각 ~4,600줄을 쌓았습니다. 닫기 3종은 세션 kill 만 했고, 유출 안전망(ft-leak-reap)은 CPU ≥30 s 만 잡아 sleep 루프는 영원히 남았습니다.

- **새 `ft-seat-reap.sh <좌석> [--dry-run] [--wt <워크트리>] [--orphans-only]`**: 후보(내 uid) = ①tmux 세션 pane 자손 ②env `FT_SEAT=<좌석>`(ppid 무관) ②b argv `ft-bg-loop.sh --seat <좌석>` ③env 안 보임 ∧ ppid 1 ∧ cwd ⊂ 좌석 워크트리(`.git` 있는 폴더 · 안쪽 다른 워크트리 제외 · 다른 라이브 세션이 같은 워크트리를 쓰면 ③ 생략 `cwd=shared`) ∧ 명령에 sleep·while · 후보의 자식(via=자손). 제외 = 남의 FT_SEAT · 보호 exe(`ft-leak-reap.sh` PROTECT_EXE 를 그대로 읽음) · 자기 조상 · 다른 세션 pane 나무. TERM → 3 s → (시작 시각 같을 때만) KILL → 1 s → 재조사 2회전. 끝 줄 `reap <좌석> stopped=<n> left=<n> rc=<n>` · 조사 실패 rc 20(ft-leak-reap ① 계약) · 외부 호출 각 7 s.
- **닫기 3종**: `ft-seat-close.sh`(kill 앞 · 세션이 없어도) · `ft-nano-close.sh`(세션 kill·ABSENT 종료 앞 · `--wt <좌석 워크트리>`) · `ft-seat-retire.sh`(은퇴 뒤 `--orphans-only` — 살아 있는 옛 에이전트는 zombie-clean 몫) — left≠0 ∨ rc≠0 = `CLOSE-FAIL reap left=<n> rc=<n>` + exit 1(세션 보존) · 성공 줄 끝 `reap left=0 rc=0` · 상세 줄은 stderr · `FT_SEAT_REAP_BIN` 주입. bin·kit 짝 cmp0.
- **tmuxc `create_tmux_session`**: `tmux new-session … -e "FT_SEAT=<세션명>"` 1줄 — 카드의 «spawn 3종 뒤 `tmux set-environment`» 는 이미 뜬 셸·에이전트에 안 닿아(실측 `X=none` · `-e` 는 `X=<이름>`) spawn 3종 대신 세 경로가 모두 거치는 tmuxc 한 곳에 심었다(spawn 3종 변경 0).
- **새 `ft-bg-loop.sh --seat <좌석> --max-sec <n> --stop-file <경로> -- <명령>`**: 둘 다 필수 · 명령은 자기 프로세스 그룹 · 끝 줄 `bg-loop end reason=max-sec|stop-file|cmd-exit|signal sec=<n> rc=<n>` · TERM·INT·HUP 이면 그룹 정지.
- **새 `ft-bg-loop-lint.sh <파일|폴더>… | --range <A..B> [--repo]`**: `while` 루프(짝 done 줄까지) 안에 `sleep`+`>>` 가 있는데 앞에 `ft-bg-loop` 가 없으면 `ERR <파일>:<줄>` · `--range` = 가지가 추가·수정한 `design/**`·`tests/e2e/**` `*.sh` 만(옛 증거 범위 밖). **ft-merge-land.sh** 착지 게이트 1줄(ERR = 착지 0).
- **한계(기록)**: macOS 는 `/bin/sh`·`/bin/zsh`·`/bin/sleep` 같은 플랫폼 바이너리의 env 를 ps 로 숨긴다(brew bash·python·node 는 보임). 10-19 사건의 guard.sh 는 `#!/bin/zsh` + 공유 루트(v6-realtime-live) cwd 라 ②·③ 로는 안 잡힌다 — 그 꼴은 래퍼(②b argv)+린트로 막는다.
- **시험**: 새 `test_seat_reap_left0.sh` 55 PASS(3회 연속 · 실 tmux 세션 2 + 표식 고아 루프 · 끝에 잔존 프로세스·세션 0) · `test_nano_close_fail_closed.sh` ⓖ(reap left=1 → CLOSE-FAIL · kill 0 · --wt 전달) · 기존 닫기 시험은 reap 스텁. 기존 `test_seat_close`·`test_nano_close_*` 5·`test_merge_land*` 3·`test_leak_reap`·`test_successor_open`·`test_nano_spawn_reuse_info` rc0 · `test_seat_retire`(5 FAIL)·`test_merge_land_state_dir`(6 FAIL)·`test_role_spawn_name`(22 FAIL)는 origin/main 기준선과 같은 실패. 증거 `harness/evidence/r448/`.

## 2026-10-19 — 미완·정지 나노를 닫는 길: `ft-nano-close.sh --suspended "<사유>"` — ⑥ 만 면제 · 카드 «중단» 끝줄 · 브랜치 보존 (1.1.18)

카드 r450 · master 111726 · loom master 111718 «미완 나노 닫는 길이 있나». 팀 정지(판정 2365)로 구현 중 멈춘 loom #1442 나노는 시험 rc=1 이라 ⑥ 증거 줄로 못 닫고, 대체 카드가 없어 `--superseded-by` 도 못 써서 세션·워크트리를 쥔 채 멈춰 있었습니다(거짓 rc=0 금지).

- **ft-nano-close.sh**: 인자 `--suspended "<사유>"`(빈 값·여러 줄·`--superseded-by`·`--cherry-override` 동시 = usage 2) · ⑥ 자리 = 새 검사 · 실작업물 미커밋은 먼저 `[wip] nano close <좌석>` 커밋(실패 = REJECT) · ⑤ 에 `--override "suspended: <사유>"` · 원장 행 `suspended=1 reason=… set=…` · 출력 `CLOSED <좌석> suspended=1 reason=<사유> set=<HEAD>` · 브랜치 삭제 0 · 인자 없으면 동작 불변. bin·kit 짝 cmp0.
- **ft-nano-suspended-check.sh**(새): `<카드> --wt <워크트리> --reason "<사유>" [--apply]` — HEAD(브랜치 위 40hex)·미커밋 0 · `--apply` 면 카드 «## 상태» 끝에 `중단: <사유> · 세트 <HEAD> · <날짜> · 재개 = planner 발주 뒤 새 세션(브랜치 <이름> 보존)`(같은 세트면 0 · 멱등) · 출력 `SUSPENDED-OK card=… set=…`.
- **시험**: `test_nano_close_suspended.sh` ⓐ~ⓖ ALL PASS rc0(옛 close 로 돌리면 FAILED 17 — `evidence/r450/red-old-close.txt`) · 기존 `test_nano_close_*.sh` 5 rc0. 증거 `harness/evidence/r450/test.txt`.

## 2026-10-19 — 팀 폴더 옛 경로 재발 방지: 쌍둥이 공존이면 리졸버는 새 꼴 + WARN · 카드·문서 옛 글자 md 린트 · 옛 위치 카드는 spawn·lint·move·착지 REJECT · ft-team-move 쌍둥이 병합 이동 (1.1.17)

카드 r447 · master 111463 ②·111467 · arch#98 보고 `REPORT-team-path-oldpath-audit-20261019.md` §1·§2. main 은 팀 폴더를 `design/teams/<팀>/` 로 옮겼지만 concierge-main 은 이동 커밋을 받고도 옛 `design/concierge/`(37) 에서 계속 일해 새 폴더(45)와 공존했고, 경로 린트는 `*.sh *.py` 만 봐 카드·문서의 옛 글자와 옛 위치 카드는 아무도 막지 않았습니다.

- **`ft-team-lib.sh`**: `ft_team_root` 가 명단 새 꼴 ∧ 옛 꼴 폴더에 파일 실재면 새 꼴 반환 + stderr `WARN 옛 꼴 잔존 <N>파일 — ft-team-move.sh --apply <팀>` (`--alt` 불변 · 쌍둥이를 일부러 세는 `ft_team_cands*` 와 stderr 를 값으로 받는 `ft-team-map-lint.sh` 는 `FT_TEAM_TWIN_WARN=0`). 새 함수 `ft_old_form_team <경로>` · `ft_card_location_ok <카드>`(명단 = 카드가 든 리포 TEAMS.md · 명단 없으면 판정 생략) · `ft_old_form_added <리포> <base> <head>`(`diff -z` — 한글 경로 원문).
- **`ft-team-path-lint.sh --md <팀 폴더|파일>`**: `*.md` 본문 전부(주석·코드 블록 포함)에서 옛 꼴 `design/<팀>/` 글자 — 명단 새 꼴 팀 = `ERR <파일>:<줄>: …` rc1 · 전환 중(명단 옛 꼴) 팀 = INFO · 꼴3 팀 대상 아님. 기존 bin 검사 모드 불변.
- **`ft-index-lint.sh`·`ft-nano-spawn.sh`·`ft-index-move.sh`**: 카드 위치 옛 꼴(명단 새 꼴 팀) → `REJECT 카드 위치 옛 경로 — ft-team-move.sh --apply <팀> 뒤 다시` 1줄(nano-spawn 은 쌍둥이 해석 뒤 검사) · **`ft-merge-land.sh`**: 가지가 옛 꼴 위치에 새 파일을 만들면 착지 0. 넷 다 lib 이 있을 때만(lib 없이 복사해 쓰는 기존 시험 30여 개 · nano-spawn 116행 관례 · 설치본은 lib 항상 있음).
- **`ft-team-move.sh --plan|--apply <팀>`** + 새 **`ft_team_move_twin.py`**: 명단 새 꼴인데 옛 폴더에 추적 파일 남은 팀 = `PLAN-TWIN` 1줄 · `--apply` 가 병합 이동(유일본 `git mv` · 같은 이름 다른 내용 = 옛 쪽 내용 승 `git mv -f` · 본문 치환 뒤 같은 내용 = 옛 삭제) + 새 폴더 본문 옛 글자 치환 + 한 커밋 + 저장 참조 재작성 → `TWIN-MERGED <팀> MOVED <N> OVERWROTE <M> DROPPED-SAME <K>` · 미커밋 = `REJECT … [wip] 먼저` · `--revert` 로 원본 sha 복원 · `--verify` 에 쌍둥이 잔존 WARN.
- **시험**: 새 `test_team_path_oldpath_md.sh` ⓐ~ⓕ 63 PASS · `test_team_literal_paths2.sh` ⓔ 리졸버 값 캡처를 `2>/dev/null`(WARN 은 stderr) — 나머지 관련 29개 FAIL·PASS 개수 main 과 동일.
- **master 단계**: ①착지(r444 뒤) → `install.sh --apply` → LIVE_BIN cmp0 ②planner 1줄 뒤 concierge master 가 concierge-main 에서 `ft-team-move.sh --plan concierge` → `--apply concierge` 1회 → `git ls-tree HEAD design/concierge` 0 ③린트 실사건 1건(`ft-team-path-lint.sh --md <팀 폴더>` ERR 줄) ④arch: COMM-GUIDE-BOOT 14 «팀 폴더 경로» 절 1줄.
- 범위 밖(기록만): 팀 가지 main 병합·전환 집행(팀 master · planner 순번) · `ft-index-lint` 에 md 본문 검사 배선 · BYZ main 명단 기준 `ft-team-path-lint` «전환 끝 · 쌍둥이 후보 잔존(ft-nano-close·ft-nano-spawn)» ERR(이 카드 전부터 있음).

## 2026-10-19 — claude 좌석 전부 증류 경고 550k · 차단 600k 로 통일 (홈·BYZ 이원화 끝 · 승계 recv 차단선 550k 같이 이동) (1.1.16)

카드 r445 · master 111389 · 오빠 «전부 550k경고 600k 차단으로 가자. 1/3 줄이고». Fable 1M 창에서 400k 경고·450k 차단(키트==홈 훅)과 프로젝트 훅은 창의 절반도 못 쓰고 승계를 불렀습니다.

- **context-distill-gate.sh**(키트 템플릿): `WARN_DEFAULT, BLOCK_DEFAULT = 550_000, 600_000` · `RECV_DEFAULT = 550_000`(후계 도달 전 recv 차단선 = 경고선과 같이 이동) · 머리 주석 R445 1줄. 판정·allowlist·메시지 코드 불변(메시지는 값에서 계산).
- **ft-successor-open.sh**: 주석 6·104 «400k» → «550k»(값을 읽지 않음 · 동작 불변) · bin·kit 짝 cmp0.
- **문서 템플릿**: `templates/rules/orchestration.md` 증류 절 550k/600k + «전 프로젝트 공통» 1줄 · `CLAUDE.orchestration.snippet.md` 16행 550k/600k.
- **범위 밖**: codex(`~/.codex/config.toml` auto_compact 780k)·opencode(`opencode.json` compaction auto) 설정 변경 0 · `ft-mbox-bridge.sh:6`·`ft-index-gate.sh:12` 역사 수치 불변.
- **시험**: `test_distill_gate_550_600.sh`(인자 없이 호출 · ⓐ540k warn 0 ⓑ560k 경고 «550k·600k» ⓒ590k block 허용 ⓓ610k block exit2 ⓔ hard recv 560k 도달 파일 없음 차단/있음 허용·540k 허용·610k 일반 도구 차단 ⓕ BYZ 사본 cmp0 + 같은 케이스 ⓖ 600/300 s·codex/opencode 참조 0) ALL PASS rc0 · 옛 훅 RED 7 · 기존 `test_distill_recv_gate.sh`·`test_successor_open.sh` rc0. 증거 `harness/evidence/r445/`.

## 2026-10-19 — 공유 루트에서 나노를 닫으면 꼬리에 남던 «팀 명단 없음» ERROR·WARN 을 없앤다: 빈 석 계산도 명단 = ref · 폴더 = 그 루트 (1.1.15)

카드 r416 · v65#211 쪽지 110851 · master 110852 · arch#96 실측. v65 가 공유 루트 v6-realtime-live 에서 나노를 닫으면 닫기는 통과하는데 꼬리에 `ERROR v65 은 팀 명단(TEAMS.md)에 없다` · `ERROR v65 팀 폴더를 못 풀었다(design/TEAMS.md)` · `WARN ft-nano-slots 실패(rc=1) — 빈 석을 손으로 세라` 3줄이 남았습니다. 세 줄 전부 닫기 끝에 부르는 `ft-nano-slots.sh` 가 cwd 사본 `design/TEAMS.md`(옛 8행 · v65 행 없음)로 팀 폴더를 풀던 한 곳에서 나왔습니다.

- **ft-nano-slots.sh**: `ft_team_cands "$WT" v65` → `ft_team_cands_ref "$WT" v65 "${FT_TEAMS_REF:-origin/main}"`(R400 r3 nano-close · R406 spawn·lint 와 같은 함수). ref 못 읽음 = `ERROR v65 명단(<ref>:design/TEAMS.md)을 못 읽음` rc1 — cwd 명단으로 되돌아가지 않는다(#0 RULE). 실패 줄에 ref·루트를 적는다. `FT_INDEX_DIR` 주입 경로는 불변. bin·kit 짝 cmp0.
- **시험**: `test_nano_slots.sh` 케이스 4(ⓐ 옛 사본 + ref 명단 v65 → rc0·빈 석·v65 카드 후보 ⓑ ref 없음 → ERROR rc1·SLOTS 0 ⓒ FT_INDEX_DIR → 명단 호출 0 ⓓ FT_TEAMS_REF 로 ref 선택) · `test_nano_close_named_wt.sh` 통과 케이스에 꼬리 SLOTS 줄 있음·WARN·cwd 명단 ERROR 0 — 옛 코드로 돌리면 둘 다 RED(꼬리 3줄 재현). 증거 `harness/evidence/r416/`.
- 범위 밖(기록만): cwd 명단(`ft_team_in`/`ft_team_cands`)을 쓰는 나머지 라이브 도구 17개 — 공유 루트에서 같은 꼴이 관측되면 도구 하나 = 카드 하나.

## 2026-10-19 — 워크트리 «옛 bin 통째 사본» 을 알아보고 설치 명령을 말한다: drift-check 메시지 · install-check STALE-COPY 행 · seat-close REJECT 에 --verdict 경로 (1.1.14)

카드 r413 · v65 쪽지 110777 · master 110781 ②·110801 ③. 공유 루트 `v6-realtime-live/.fable-team/bin` 이 shim 이 아닌 옛 통째 사본(418 파일 · LIVE_BIN·해석기 없음)이라 그 cwd 의 nano-close 입구 drift-check 가 BYZ 옛 키트 경로를 찾다 «ERROR ref 에 경로가 없음 → main 키트와 다르다» 로 막혔고, 받는 쪽은 무엇을 할지 몰랐습니다.

- **`ft-live-bin-drift-check.sh`**: 해석기 호출 «앞» 에 `--bin` 이 `*/.fable-team/bin` ∧ `../LIVE_BIN` 없음 ∧ `ft-harness-root.sh` 없음 ∧ shim 표식 파일 0 ∧ 일반 파일 ≥1 이면 `ERROR 옛 설치 사본(shim 아님 · LIVE_BIN 없음): <bin> — bash <하네스>/install.sh --apply --project <루트>` rc3(하네스 = `FT_HARNESS_ROOT` · `../HARNESS_ROOT` · 못 풀면 `<하네스>/harness` 글자). 그 밖은 바이트 불변 · drift REJECT 우회 0.
- **`ft-live-install-check.sh` / `ft_live_install_check.py`**: `--project`(기본 리포 공용 루트)와 그 `.worktrees/*` 의 `.fable-team/bin` 중 LIVE_BIN 없음 ∧ shim 0 ∧ 파일 ≥1 → `STALE-COPY <bin> files=<n>` + `HINT <bin> bash <하네스>/install.sh --apply --project <워크트리>` · PENDING rc1(`--range` 도 같음 · 읽기만).
- **`ft-seat-close.sh`**: 현역 역할 좌석 REJECT 문구 끝에 ` · 후계 없이 닫으려면 --verdict <판정번호>(R400 · 사람 승인 1건)` (동작 불변).
- **시험**: `test_live_install_check_shim.sh` 새 절 r413ⓐ~ⓒ + 픽스처를 r385 뒤 인자(`--kit`·`--path`)로 갱신(base 에서도 9 FAIL 이던 기준선) · `test_seat_close.sh` ③ 에 문구 단언. 증거 `harness/evidence/r413/test.txt`·`test-r2.txt` · base 동일 실패 5종 `preexisting-fails.txt`.

## 2026-10-19 — 범위 분류기 «전역 규칙» 이 옛 라이브 설치 사본 경로 `scripts/harness-install/` 도 FORBID 한다 (1.1.13)

카드 r412 · arch#95 재현 · 판정 1395(떨어지는 시험 = 고침 단위). 팩 이전 때 «전역 규칙» 정규식에 새 경로 `harness/kit/` 만 넣고 옛 경로가 빠져, 머리 주석(「옛·새 경로 어느 쪽이든 맞으면 FORBID」)과 어긋났고 팩 시험 절 «scripts/harness-install/ → FORBID» 가 base 부터 FAIL 1(`rc=0 out=CLASS code`)이었습니다. r411 이 code 종류를 연 뒤에는 옛 설치 경로를 다시 들여오는 세트가 code 로 대리 승인될 수 있어 실사건 전에 막습니다.

- **`autonomy_scope_classify.py`**(bin·kit 짝 cmp0): `PATH_RULES` «전역 규칙» 같은 줄에 `|(^|/)scripts/harness-install/` 1 토큰 · 줄 수 200 불변. `src/x.py` → code 그대로(오탐 0).
- **시험**: 본문 변경 0 — `test_autonomy_scope_classify.sh` ALL PASS rc0 · `test_autonomy_scope.sh` fail=0 rc0. 증거 `harness/evidence/r412/test.txt`.

## 2026-10-19 — desk 보고 스레드 뿌리 ts 를 도구가 소유한다: `reply --thread <이름>` + 승계 본문 ts 손 복사 REJECT (1.1.12)

카드 r414 · master 110781 ① · desk#20 110779(오빠 «여기는 왜 매새지 안오냐» · «다음 증류 땐 자동으로»). 뿌리 ts(10-16)가 인계서 13장에 손으로 복사돼 이어졌고, 3일 된 스레드 답글은 채널 본문에 안 보였다.

- **`kit/slack-mirror/thread_post_update.py`**: `reply --thread <이름>` — 등록부 `<FT_ROOT>/.fable-team/state/slack-threads.json`(env `FT_SLACK_THREADS`) `{"<이름>": {channel, root_ts, date, history[]}}`. 없음 ∨ 날짜(KST) ≠ 오늘 ∨ 채널 다름 → 채널에 뿌리 글 `[<이름> 보고 <날짜>]` 1건 + 등록(옛 뿌리 history) → 답글. 본문 post_guard 검사는 뿌리 글 «전»(걸리면 뿌리·등록부 불변). 등록부 손상 = raise.
- **`thread_post_args.py`**: `--ts`·`--thread` 배타 필수(둘 다·둘 다 없음 = usage rc2) · `--thread` 는 `--channel` 생략 시 등록부 채널 · `--ts` 만 = 기존 동작(기본 채널) 불변.
- **`ft-successor-open.sh` ⓐ'**: 후계 이름 `*-desk-*`|`*-planner-*` 이고 본문에 `--ts <10자리>.<6자리>` → `REJECT 본문에 슬랙 ts 손 복사(--ts …) — byz_thread_post.py reply --thread <이름> 으로(r414)` · 열기 0.
- **카드 편차 2**: reply 인자는 실제 위치인 `thread_post_args.py` 를 고쳤다(설치 `~/.hermes/scripts` 3 파일) · 시험 가짜 전송은 `FT_SLACK_POST` 주입 대신 기존 `--slack-base` 로컬 가짜 서버(제품 코드에 시험 전용 경로 0).
- **시험** `tests/test_thread_reply_named.sh` ⓐ~ⓔ 11 PASS · 기존 `test_successor_open.sh`·`test_index_move_slack.sh` rc0 · pytest thread_post·post_guard 62 passed. 증거 `harness/evidence/r414/test.txt`.

## 2026-10-19 — 범위 사전 승인에 종류 code 를 연다: 시험 통과 세트만 · code-max 안 (1.1.11)

카드 r411 · 판정 2326(오빠 «자율 개선두건 진행») · planner 110362 · master 110379 ②. 자율 ON 중 코드 세트 병합이 «앞 착지가 main 을 옮김 → 다음 PR head 바뀜 → 승인 sha 어긋남 → 오빠 재승인 h» 로 줄줄이 멈췄습니다(#1933→#1934 · h104). `approve-scope` 종류가 docs·ff·revert 뿐이라 코드 세트는 매 sha 오빠 손 1줄이었습니다.

- **approve-scope**(오빠 `!` 전용 그대로): `--classes …,code --code-max <1~max>` — code 가 있으면 `--code-max` 필수(없음·0·max 초과 = REJECT) · code 없이 `--code-max` = REJECT · grant 줄·grants.audit·슬랙 1줄·출력에 `codemax=` 칸. 옛 grant 줄(codemax 없음)은 그대로 읽힘(code 0 = 닫힘). 기본값 불변(h119 code_merge=off) — 오빠가 code 를 적을 때만 열린다.
- **scope-approve `--card <카드.md>`**: 분류기가 `CLASS code` 면 ①카드 마지막 `세트: <A> · 시험: … rc=0 · 이슈: 0` ②`ft-nano-evidence-check.sh <카드> --repo ROOT --ancestor-of <sha>` rc0 ③A≠sha 면 `ft-approval-equiv.sh A <sha>` EQUIV — 셋 다일 때만 승인 줄(`approve-merge <sha> <A> <epoch>` 불변)을 쓴다. 그 밖 = `SCOPE-REJECT`(쓰기 0). code 건수(docs 와 별개) 도달 = 기존 «건수 도달» 과 같은 정지. 원장 5번째 칸 `evidence=<카드>@<A>` · 출력 `code=n/max`(+ `equiv=<A>`). 새 `ft-autonomy-scope-code.sh`(source 전용). 분류기 FORBID(DDL·배포·키·과금·의존·전역 규칙)는 code 에도 그대로.
- **시험**: `test_autonomy_scope.sh` 새 절 ⓐ~ⓔ(임시 origin+clone 실 git · 실 evidence-check·approval-equiv · 분류기만 스텁) + 기존 절 갱신(code REJECT → code-max 검사 · tamper 꼴) — 134 PASS.

## 2026-10-19 — freeze 훅이 «병합이 가져온 그대로» 인 하네스 파일은 세지 않는다: harness-freeze-gate MERGE_HEAD 대조 (1.1.10)

판정 2323 · 카드 r407 · v65 master#209 [HIL] 110183. 옛 가지에 origin/main 을 병합할 때 충돌을 손으로 풀고 `git commit` 하면, main 이 r386 에서 지운 하네스 877 파일이 staged «이름»으로 잡혀 REJECT 됐습니다(우리 손 0). 충돌 없는 병합은 git 이 커밋까지 끝내 훅을 안 타므로 같은 병합이 충돌 유무로 갈렸습니다.

- **`harness/kit/hooks/harness-freeze-gate.sh`**: MERGE_HEAD 가 있으면 HIT 경로마다 staged 상태(stage 0 블롭)와 MERGE_HEAD 상태를 대조해 같으면 제외 — 같은 블롭 · ★둘 다 없음(main 의 삭제 그대로)★ 포함. 작업 트리 diff(`-a` 등)에 든 경로 · 미해소(stage≠0) · git 을 못 읽음 = 제외 0(그대로 REJECT). 남은 HIT 만 «건드린 파일 N개» · 메시지 끝 `(병합 중 MERGE_HEAD 와 같은 상태(블롭·삭제) M개 제외)`. MERGE_HEAD 없으면 출력 바이트 불변. freeze 표식·4폴더 목록 불변.
- **카드 편차 1**: 카드는 «둘 다 못 읽으면 제외 0» 이었으나 실제 사건(110183)의 877 파일이 전부 main 쪽 삭제(D)라 그 규칙으로는 그대로 REJECT — 삭제는 «둘 다 없음 = 같은 상태» 로 제외한다. 손 삭제(MERGE_HEAD 에는 있는 파일)는 REJECT(시험 ⓓ).
- **시험** `test_harness_freeze_gate.sh` 새 절: ⓐ 충돌 손 해소 뒤 commit(추가·삭제 그대로) 통과 ⓑ 손댄 하네스 파일 1개만 REJECT + 제외 표기 ⓑ' 작업 트리만 손댐 + `-am` REJECT ⓓ 손 삭제 REJECT ⓒ MERGE_HEAD 없음 = 고치기 전 훅과 stderr 바이트 동일. 증거 `harness/evidence/r407/test.txt`(실사건 재현: 현행 훅 877개 REJECT → 새 훅 rc0).

## 2026-10-19 — 공유 루트 cwd 에서 v65·lecture 카드 spawn 이 «팀 명단 없음» 으로 끊기던 것을 고친다: 명단 = ref · 폴더 = 호출 워크트리 실재 1개 (1.1.9)

카드 r406 · planner 판정 2318 · master 110115 · arch#94 재현(`ERROR v65 은 팀 명단(TEAMS.md)에 없다 / REJECT … 선언된 정본 없음: /GOAL-LEDGER-v65.md`). 팀 폴더 전환은 main 에만 착지했는데 lint·spawn 이 «호출 워크트리의 design/TEAMS.md» 를 읽어, 명단이 옛 것인 공유 루트(feat/v6-realtime-live)에서 spawn 이 3회 REJECT 됐습니다.

- **lib**: `ft_team_file_ref <루트> <팀> <파일> [<ref>]` — `ft_team_cands_ref`(R400 r3) 후보 폴더 중 <파일> 이 «실재하는 정확히 1개» · 명단 못 읽음·후보 0·2+ = stderr ERROR(ref·후보 경로) rc1. `ft_team_has_ref` — `ft_team_has` 를 ref 명단으로(못 읽음 rc2). ref 기본 = `FT_TEAMS_REF` 또는 `origin/main`. `ft_team_in` 의미는 그대로(다른 도구 영향 0).
- **ft-index-lint.sh**: 기본 골 원장(`default_ledger`) = `ft_team_file_ref <ROOT> v65 GOAL-LEDGER-v65.md` (`FT_GOAL_LEDGER` 명시가 먼저) · 판정 원장 pathspec = ref 명단의 planner 꼴 + 쌍둥이(루트 상대).
- **ft-nano-spawn.sh**: 발주 본문 SEATBELT-README = `ft_team_file_ref <WT> v65 SEATBELT-README.md` (`FT_SEATBELT_README` 명시가 먼저 · 실재 0·2+ = REJECT) · planner 빈 카드 판정 = `ft_team_has_ref`.
- **시험**: 새 `test_team_roster_ref.sh`(ⓐ공유 루트 꼴 dry-run PLAN·lint OK ledger=꼴1 ⓑref 못 읽음 ⓒ후보 0 ⓓ후보 2 → REJECT ⓔ보통 워크트리 불변·명시 env 우선 · 옛 코드에서 13 FAIL). 픽스처 갱신: origin/main ref 없는 임시 리포는 `FT_TEAMS_REF=HEAD`, 발주 README 실재(dead_seat_resume·raised_seat·planner_nano_path·team_literal_paths2·nano_spawn_base_sha·branch_collision·rollback) · `test_nano_spawn_teamset_cap.sh` 픽스처에 `FT_ROOT`·comm 폴더(main 에서도 9 FAIL 이던 기준선).

## 2026-10-19 — 라이브 bin 의 ft-mbox 가 우편함을 못 찾던 것을 고친다: cwd 리포 루트 comm · doorbell 이 우편함을 명시 (1.1.8)

카드 r403 · master 109989(급) · planner 109978 · desk 109974. r385 라이브 bin 전환 뒤 `~/.claude/fable-team/live/<v>/bin/ft-mbox.sh` 는 스크립트 조상에 `.fable-team` 이 없어 어느 cwd 에서 불러도 `NO_MAILBOX_ROOT` rc2 였고, doorbell 이 그 경로로 `recv` 줄을 주입해 받는 좌석도 같은 실패가 났습니다.

- **루트 순서(`ft-mbox.py` · `ft-mbox.sh` `_mbox_dir`/`_seats_json` 같은 걸음)**: ①`FT_MBOX_DIR` ②스크립트 조상 `.fable-team`(옛 설치 꼴 · 불변) ③cwd `git rev-parse --git-common-dir` 부모의 `.fable-team/comm` 이 «이미 실재» 할 때만 ④`NO_MAILBOX_ROOT` rc2 + 「cwd 공용 루트 <경로> 에도 comm 없음」. 우편함 생성은 ①② 만(F4).
- **doorbell**: `[발주 #N] FT_MBOX_DIR=<이 send 가 쓴 comm 절대경로> bash <bin>/ft-mbox.sh recv <to> — …` — 받는 좌석 cwd 무관 · 머리 `[발주 #N]` 첫 토큰 불변(ft-send-verified 영향 0).
- **시험**: 새 `test_mbox_root_resolve.sh`(ⓐ명시 env ⓑcwd 워크트리→리포 루트 comm·sh/py 같은 루트 ⓒ/tmp→rc2·생성 0 ⓓdoorbell 줄 글자·/tmp 실행 READ ⓔ옛 꼴 불변).

## 2026-10-19 — 팀 폴더 이동 뒤 옛 경로에 새 파일을 만들지 못하게 막는다: old-team-path-new-file-gate (1.1.7)

판정 2294 ⓑ(planner 쪽지 109888 «옛 경로 새 파일 DENY») · 카드 r402. 12팀 폴더가 `design/teams/<팀>/`(꼴2)로 옮겨진 뒤에도 쌍둥이 역호환이 «읽기» 뿐 아니라 «쓰기» 까지 열려 있어, 옛 `design/<팀>/` 에 만든 카드·발주서가 두 폴더로 흩어졌습니다.

- **새 훅 `harness/kit/hooks/old-team-path-new-file-gate.sh`**(PreToolUse:Write|Edit|Bash): 대상 경로 = Write·Edit `file_path` · Bash 의 `>`·`>>` 대상과 `cp|mv|install|tee|touch` 마지막 인자(따옴표 밖). 대상이 «없는 파일» 이고, 그 경로가 속한 git 루트의 `design/TEAMS.md` 에서 그 팀 칸이 꼴2 이면 deny + `바른 경로: design/teams/<팀>/…` 1줄. 기존 파일 편집·읽기·리포 밖·꼴1 팀·꼴3 팀·명단 밖 폴더는 통과. 입력 파싱 실패·명단 없음·`ft-team-lib.sh` 못 찾음 = 허용 + stderr WARN 1줄(fail-open). 팀 이름 글자 0(`ft_team_rel` · `$FT_BIN` → `~/.claude/fable-team/live/*/bin` 최신).
- **설치**(`harness/install.sh`): 홈 훅 목록 `HOME_HOOKS`(harness-freeze-gate · old-team-path-new-file-gate)를 `<home>/.claude/hooks/` 로 cp -p → cmp(같으면 건너뜀) · dry-run 에 `HOOK` 줄 · apply 에 `HOOKS copied= same=` 줄. settings.json 등록은 별도(master).
- **시험**: 새 `test_old_team_path_deny.sh`(카드 ⓐ 6절 + 리포 밖·꼴3·절대경로·명단 밖 · Bash `>`/`>>`/tee/touch/mv deny · 읽기·따옴표 글자·옛→새 cp·기존 덮어쓰기·`>&2` 통과 · fail-open 3 · live 최신 lib).

## 2026-10-19 — 좌석 닫기 도구가 «못 닫고 CLOSED» 를 찍지 않는다: 원장 명단은 origin/main · 명부·원장 fail-closed · 다른 리포 좌석 안내 (1.1.6)

판정 2307 ①② · planner 109823(v65·lecture 나노 닫기가 원장 워크트리의 옛 TEAMS.md 때문에 REJECT) · 109839(airag 옛 판 nano-close 가 명부·원장 없이 «CLOSED» 출력 · 세션 잔존 — 1.1.4 도 같은 네 자리) · master 109876(다른 리포 좌석 닫기가 «NOROW ↔ 원장 루트 못 풂» 순환).

- **기본 원장 = «명단은 ref · 폴더는 원장 워크트리»**(`ft-nano-close`): `FT_NANO_LEDGER` 가 없으면 팀 명단을 `FT_TEAMS_REF`(기본 `origin/main`)의 `design/TEAMS.md` 에서 읽고, 명단 꼴·쌍둥이 후보 중 원장 파일이 실재하는 «정확히 1개» 만 씁니다(`INFO 원장 ← <경로> (명단 <ref>)`). 0개·2개·명단 못 읽음은 REJECT(후보 목록). 새 함수 `ft-team-lib.sh` `ft_team_cands_ref <루트> <팀> [<ref>]` — `ft_team_in`·`ft_team_cands` 변경 0.
- **fail-closed 4곳**(`ft-nano-close`): ①명부 파일 없음 ②원장 없음/쓰기 불가 → 입구 REJECT(tmux 조회·변경 전) ③명부 pop 실패 → REJECT(사건 원장 abort) ④원장 append 실패 → FAIL — 어느 경우도 «CLOSED» 줄 0. ★원장은 이미 있는 파일만 씁니다(첫 append 로 만들지 않음).★
- **다른 리포 좌석 안내**(`ft-seat-close`·`ft-seat-retire`): NOROW·원장 루트 실패·«행 없음» 안내에 `FT_ROOT=<그 설치본 루트> … --seats <그 루트>/.fable-team/seats.json` 한 줄(지금 인자로 채움 · 자동 탐색 0 · 동작 변경 0).
- **시험**: 새 `test_nano_close_fail_closed.sh`(ⓐ 명단 origin/main + 쌍둥이 1곳 → CLOSED ⓑ 후보 2 ⓒ 0 ⓓ ref 없음 ⓔ 명부 없음 ⓕ 명부 쓰기 실패 — 고치기 전 코드는 9 FAIL) · `test_seat_close.sh` ⓖ(FT_ROOT + --seats 다른 리포 → CLOSED-ROLE · 원장 그 루트) ⓗ(--seats 없이 → 안내 · rc3) · `test_nano_team_env.sh` 픽스처에 원장 파일 미리 생성 + 옛 이름 좌석 2회 원장 명시.

## 2026-10-19 — 판정 번호로 역할 좌석을 닫는다: ft-seat-close --verdict · ft-seat-retire --record-only --verdict (1.1.5)

planner 판정 2304(오빠 승인 1건)가 현역 역할 좌석 17석을 «재개 기록 → 명부 칸 비우기 → kill» 로 닫으라 했는데, 기존 도구로는 0석이었습니다(master #109747).
`ft-seat-close` 는 `_*` 칸 값(현역)을 거절했고, `ft-seat-retire --record-only` 는 `_replaced_by` 가 있어야만 기록했고, 다른 리포 좌석은 이 리포 명부에 행이 없었습니다.

- **`ft-seat-retire <구> --record-only --verdict <번호>`**: `_replaced_by`·R296 ⓑⓒ 없이 결속(`ft_seat_bind`)만으로 재개 기록(`retired_by = verdict <번호>`) · 행 없음은 R296 ⓐ(`_*` 칸 값이면 REJECT)만 · 명부 쓰기 0 · 출력 꼴 그대로(`RESUME ok` | `NORECORD`).
- **`ft-seat-close <좌석> --verdict <번호> --reason …`**: ⓪실행 세션 자신 REJECT ①재개 기록 실패 = `HELD` rc 3(명부 쓰기 0 · kill 0) ②행 있음 → stop-ready 표기 + `_closed.verdict` + 어느 명부든 값 == 좌석인 최상위 `_*` 칸을 `""`(파일마다 `.bak-close-<ts>` · tmp→mv) · 행 없음 = `NOROW` rc 3(kill 0 · 그 리포 루트에서 다시) ③계보 검사 건너뜀 → 태그 해제 → kill → `CLOSED-ROLE … kill=ok` + 원장 `<데이터 루트>/.fable-team/state/seat-close-verdict.log` 1행.
- **codex 좌석 재개 기록**(master #109793 — 실측 da-codex#4 «세션 파일 0개» HELD): 결속 판정기 `ft_seat_bind.bind` 가 claude 세션 파일이 0개일 때 pane 자손(깊이 ≤4) 중 실행 주체 codex 가 연 `~/.codex/sessions/**/rollout-*.jsonl` «정확히 1개» 로 결속(첫 줄 session_meta id == 파일명 끝 · 시작시각 ≤ mtime) · 기록 `engine=codex` · model = argv `-c model=` → rollout `turn_context` · `resume_cmd = codex <원래 인자> resume <id>`(zombie-clean resume 은 claude 기록만 받는다 — 변경 0 · `--expect` 변경 0).
- **`ft-nano-close` 카드 탐색**(master #109792 — r385#0 «⑥카드 못 찾음»): 명부 index 경로에 카드가 없으면 같은 `indices` 뿌리의 형제 폴더(대기·진행·완성)에서 같은 파일명이 정확히 1개일 때만 그 카드 + `INFO 카드 위치 ← <경로>` · 0·2+ 는 REJECT 그대로(`형제 N개`) · 명부 쓰기 0.
- `--verdict` 없는 호출은 동작 그대로 · **시험**: `test_seat_close.sh` ⓑ~ⓕ·usage(가짜 tmux · retire 스텁) · `test_seat_retire.sh` ⑮(현역 행·행 없음·`_*` 칸·결속 실패·usage) · ⑯(가짜 codex 트리: 정상·rollout 2개·0개·id 불일치) · `test_nano_close_named_wt.sh`(형제 1개 → CLOSED · 2개 → REJECT).

## 2026-10-19 — 설치본에서 보드 루트를 풀고, 하네스가 리포 밖일 때 범위 대조를 통과시킨다 (1.1.4)

1.1.3 설치본으로 전환한 뒤 실제 실행에서 두 곳이 막혔습니다(master #109675).
나노 닫기·spawn 이 «사건 원장 prepared 실패» 로 거절됐고(`ft_board_env.ft_root` 가 `git -C <설치본 bin>` — git 밖), 카드 완성 이동·착지가 `INSTALL ERROR` 로 막혔습니다(`ft-live-install-check --range … --repo <BYZ>` 가 «하네스 루트가 --repo 밖» 이면 항상 ERROR).

- **보드 루트**(`ft_board_env.ft_root`): `FT_ROOT`(그 값 그대로) → cwd git 공용 루트에 `.fable-team/LIVE_BIN` 실재 → 옛 설치 꼴(`*/.fable-team/bin`)일 때만 `git -C <bin>` 공용 루트 → RuntimeError(사유에 cwd·경로). 호출 12곳 변경 0.
- **범위 대조**(`ft_live_install_check.resolve_kit`): 하네스 루트가 `--repo` 밖이고 `--kit` 가 없을 때 — `--range A..B` 가 건드린(ACMR) 옛 하네스 경로(`scripts/fable-team-bin/` `scripts/harness-install/` `tools/comm-canonical/` `tests/harness/` `kit/` · 팩 꼴 `**/harness/kit/**`) 파일이 0 이면 `OK n=0 skip=0 (하네스 루트가 --repo 밖 · 범위에 하네스 파일 0)` rc0, 1개라도 있으면 ERROR(파일 목록) rc3. `--all` 은 ERROR 그대로.
- **시험**: `test_installed_root.sh` ⓔ 절(설치본 · cwd 리포/하위/git 밖/FT_ROOT/옛 꼴 · 설치본 `ft-sheet-events.sh` git 밖 ERROR · spawn 경로 key+prepare rc0 · 임시 HOME 쓰기 0) · 새 `test_install_check_repo_outside.sh`(하네스 0 → OK · `^..`·`--ref` 호출 꼴 · 하네스 1 → ERROR+파일명 · 팩 꼴 키트 1 → ERROR · 삭제만 → OK · `--all` → ERROR).

## 2026-10-19 — 설치본에서 «파일 위치 조상 탐색» 없이 루트·comm 을 푼다 (1.1.3)

1.1.2 설치본(`~/.claude/fable-team/live/1.1.2/bin` · git 밖)으로 LIVE_BIN 을 바꾸자 골 표가 «루트 없음» 으로 멈춰 쪽지 가드가 발주·보고를 막았고, LIVE_BIN 을 되돌렸습니다.
골 표 루트(`ft_goal_ledger.find_root`)와 형제 `../comm` 이 «이 파일 위치의 조상» 에 기대고 있었는데, 설치본은 `<버전>/{bin,templates,HARNESS_ROOT}` 뿐이라 둘 다 없었습니다.
(1.1.1 데이터 루트 해석기 · r386 팀 경로 지도 fallback 과 같은 «설치본 루트» 묶음입니다.)

- **골 표 루트**(`ft_goal_ledger.find_root`): `FT_ROOT` → cwd git 공용 루트에 `.fable-team/LIVE_BIN` 실재 → 옛 설치 꼴(`*/.fable-team/bin`)일 때만 파일 위치 조상 → ERROR.
- **comm**: 해석기에 `ft_comm_dir`(= `$(ft_data_root)/.fable-team/comm` · 옛 설치 꼴이면 옛 `$HERE/../comm` 과 같은 곳 · 없으면 ERROR) 1함수 추가 — 기존 함수 변경 0.
  쓰는 곳 17: harness-info · hil-ask · hil-answer · mbox-bridge(mbox·mbox-v2) · plan-handoff · tick · disk-alarm · issue-create-pair · launchd-check · magazine-check ·
  resource-reclaim · seat-live · secret-scan · spawn-hold · tick-team · send-verified · context-monitor(각 도구의 env 가 먼저).
- **데이터 루트 `../..`**: install-pending · seat-handover → `ft_data_root` · `ft_penalty.root` → 리포 공용 루트 순서(ft_repo_root 와 같음) · `ft_op_token.secrets_dir` → env → 옛 꼴 → cwd 리포의 `.fable-team/secrets` → ERROR.
- **시험**: `harness/tests/test_installed_root.sh`(설치본 · cwd 리포/하위/git 밖/FT_ROOT/옛 꼴 · tick·hil-ask mbox 경로 · git 밖 ERROR + 임시 HOME 쓰기 0 · 실제 BYZ cwd 골 표 rc0).

## 2026-10-19 — 설치·실행 위치 전환 준비: 팩에서 바로 설치하고 BYZ 하네스 폴더를 얼린다 (1.1.2)

1.1.1 로 도구가 git 밖 설치본에서도 데이터 루트를 풀게 됐지만, 키트 글자·설치 입구는 아직 BYZ 리포 안 옛 위치(`scripts/fable-team-bin` 등)를 전제했습니다.
이 판은 팩 하네스만으로 설치·대조가 되게 하고, 전환 동안 BYZ 쪽 하네스 커밋을 막는 장치를 더합니다(카드 r385 · LIVE_BIN 1줄 전환은 master).

- **경로 글자**: `harness/bin`·`harness/kit` 의 `scripts/fable-team-bin`·`scripts/harness-install`·`tools/comm-canonical` → `harness/bin`·`harness/kit`·`harness/comm`(주석·안내문 포함 0건).
- **설치**(`harness/install.sh --apply --project <루트>`): `--project` 필수(cwd 추론 0 · 없으면 rc2 쓰기 0) · 키트 `bin`·`templates` 를
  `<home>/.claude/fable-team/live/<version>/` 에 cp+cmp · `<version>/HARNESS_ROOT` 1줄(= `ft_harness_root` ② 지도) · 설치본 shim 으로 프로젝트 `LIVE_BIN`·`LIVE_ROOT`(있으면 보존) ·
  2회째 복사 0 · 끝에 «되돌림 1줄»(LIVE_BIN 이전 값) 출력.
- **대조**: `ft-live-install-check.sh --kit/--project` · 하네스 bin launchd 항목에 `WorkingDirectory`·`FT_ROOT` 없으면 `NOROOT` · shim·live-install `--repo/--path` 기본 = 하네스 코드 루트.
- **freeze 가드**(`harness/kit/hooks/harness-freeze-gate.sh` · PreToolUse:Bash): 대상 저장소 공용 루트에 `.fable-team/state/harness-freeze` 가 있으면
  `scripts/fable-team-bin`·`scripts/harness-install`·`tools/comm-canonical`·`tests/harness` 를 건드리는 커밋을 REJECT(카드 `design/harness` 는 r386 이전까지 BYZ 에서 커밋 — 막지 않음)(staged · `-a`/pathspec 이면 작업 트리도) · 표식 없으면 통과.
- **홈 훅 5**(autonomy-interview-gate · autonomy-merge-guard · gh-issue-author-guard · merge-head-gate · tracked-bin-call-gate): 옛 위치 후보 대신 루트 shim · LIVE_BIN · `$FT_HARNESS_ROOT/bin`.
  홈 적용분은 `harness/evidence/r385/home-hooks.patch`(+ freeze 가드 새 파일 · dry-run 원문 같은 폴더) — 적용은 master.
- **시험**: `harness/tests/test_harness_freeze_gate.sh`(표식 없음 통과 · staged/-a/--all/cd/-C/워크트리 REJECT · 4폴더 밖·메시지 글자 통과 · 해제).

## 2026-10-19 — 데이터 루트 해석기 2종: 설치본이 git 밖이어도 루트를 조용히 잘못 풀지 않는다 (1.1.1)

라이브 설치본을 `~/.claude/fable-team/live/<version>/bin`(git 밖)으로 옮기면, 키트 도구 35곳이 «자기 위치»(`git -C $HERE` 공용 루트 · `$HERE/../..`)로
데이터 루트를 풀다 `~/.claude/fable-team/live` 로 풀렸습니다 — 자율 상태·spawn 정지 파일·자원 표·press 허가를 못 보는 회귀입니다.
실측해 보니 루트가 두 종류였습니다: 리포 공용 루트(BYZ 메인 `.fable-team/state`)와 라이브 루트(`LIVE_ROOT` · v6 `.fable-team/state`).

- **해석기**(`harness/bin/ft-harness-root.sh` · 키트 짝 같음): `ft_repo_root` = 옛 설치 꼴(`*/.fable-team/bin`)이면 `git -C $HERE` 공용 루트(없으면 `$HERE/../..`)
  → cwd git 공용 루트(`.fable-team/` 있을 때) → ERROR · `ft_data_root` = `FT_ROOT` → cwd git 공용 루트의 `.fable-team/LIVE_ROOT` 1줄 → 옛 설치 꼴 `$HERE/../..` → ERROR.
  어느 쪽도 못 풀면 rc≠0 로 멈춥니다(조용한 후퇴 0). 각 도구의 기존 env(`FT_RES_ROOT`·`FT_SECRET_SCAN_ROOT`·`FT_ROOT`)는 그대로 우선.
- **리포 공용 루트 묶음**: spawn-hold · resource-gate/watch/sample/cause/reclaim · disk-alarm · disk-census · scratch-repo · secret-scan · fp-run ·
  issue-close-check · weekly_review · board-publish · sheet-publish/verify · gh-tank-comment-edit · gh-tank-edit-bak · idle-wake · measure-net ·
  seat-request · seat-live · seats-lint · tick-line · successor-open(자원 문지기 루트).
- **라이브 루트 묶음**: autonomy · autonomy-start · proxy-decide · resume-cmd · resume-attempt · press-gate · press-permit.
- **드리프트 입구**(nano-spawn · nano-close · tick): 설치 꼴에 `*/fable-team/live/*/bin` 추가 · `--repo` 생략 → drift-check 기본 = 하네스 코드 루트(`FT_HARNESS_ROOT` · `<버전>/HARNESS_ROOT`)의 키트.
- **launchd 템플릿** weekly-review · secret-scan: `WorkingDirectory` 로 cwd 루트를 준다.
- **시험**: `harness/tests/test_harness_root.sh`(git 밖 설치본 + cwd git 밖 → ERROR · 임시 HOME 쓰기 0 / cwd 워크트리 → 공용 루트·LIVE_ROOT / env · 옛 설치 꼴 회귀 0).

## 2026-10-18 — harness 합류: BYZ 하네스 6경로를 이력째 팩으로 (1.1.0)

하네스 실행 도구·키트·통신·카드 원장·시험·옛 증거가 BYZ-Agents 리포에만 있어 패치·버저닝·산출물 관리가 두 레포로 갈렸습니다.
6경로를 커밋 이력째 `harness/` 로 옮겼습니다(판정 2270 · BYZ 711199fd62 기준 · BYZ 삭제는 다음 단계).

- **레이아웃**(`harness/`): `bin/`(←`scripts/fable-team-bin` 227) · `kit/`(←`scripts/harness-install` 459) · `comm/`(←`tools/comm-canonical` 31) ·
  `design/harness/`(←`design/teams/harness` 756 · 옛 `design/harness` 이력 포함) · `tests/`(←`tests/harness` 224 + `tests/scripts` 하네스 시험·도우미 47) ·
  `evidence/state-v6/`(←`.fable-team/state/v6-*` 88). `skill/` 은 그대로 — 규칙·참조는 skill, 실행 도구는 harness.
- **버전**: `manifest.json` `version` 이 유일한 출처 — 이 절부터 0.1.0·1.0.3 어긋남을 1.1.0 으로 통일. 팀 폴더 틀 버전(`harness/kit/fable-team/templates/team/VERSION` 1.0.0)은 별개 의미라 그대로.
- **설치 입구**(`harness/install.sh`): manifest version 을 읽어 `~/.claude/fable-team/live/<version>/` 와 프로젝트 `LIVE_BIN`·`LIVE_ROOT` 계획을 출력(지금은 `--dry-run` 만 · 실제 설치는 다음 단계).
- **재배치 대조**(`harness/tests/test_pack_relocation.sh`): 경로 표 5행마다 BYZ 기준 sha 와 팩의 파일 수·sha256 목록이 같고 표 밖 파일 0 · 이력 커밋 수 대조.

## 2026-10-02 — 단일 세트 · 나노 생애 · 오래된 나노는 루트부터 (1.0.3)

BYZ-Agents v65 에서 09-25 카드를 재대조 없이 10-02 코드에 집행하고, 옛 sha worker 로 돌린 A/B 를 근거로 HEAD 를 덮어쓸 뻔했습니다(미랜딩 nano 277/590 · 나노 브랜치 221커밋 뒤처짐).

- **규칙**(`references/SEATBELT.md` §6-3): 단일 세트 시험 · 나노 생애 ①~⑤(최신 루트 병합→시험→이슈 확인→squash) · 랜딩 = 라이브 1회까지 · 방치 0.
- **스크립트** `scripts/ft-nano-freshness.sh`(읽기 전용): base·루트 뒤처짐·겹침 파일·미랜딩 패치·dirty → FRESH/STALE/STALE-OVERLAP/LANDED.

## 2026-10-02 — 워크트리 위생: Serena project.yml 커밋 금지

BYZ-Agents 의 모든 워크트리에서 Serena 가 `.serena/project.yml` 을 자동 갱신해 세션마다 modified 로 떴습니다.
추적 해제 + gitignore 를 BYZ 가 적용했고(4305b6925), 같은 규칙을 팩의 플레이북에 넣었습니다.

- **규칙**(`references/orchestration-playbook.md` «워크트리 위생»): project.yml 커밋 금지 · Serena 는 본인 워크트리 절대경로로 활성화.

## 2026-10-01 — checkpoint 계약: 시험·press 를 돌린 워커가 그 회차의 tester·checker

BYZ-Agents v65 에서 과금 랜딩이 폴리싱·완료 말풍선을 끊는 회귀를 냈는데, 측정 워커가 자기 측정 조건만 보고
6회차를 VALID 로 넘겼고 사용자가 화면을 보고 잡았습니다. 수정 범위가 넓고 시스템이 커서 «한 곳을 고치면 다른 곳이
끊기는» 일이 잦기 때문에, 랜딩마다 BTS 4축 + poller 고정 칸을 도구로 확인하는 계약을 팩에 넣었습니다.

- **계약**(`references/SEATBELT.md` §6-2): 시험·press 를 돌린 워커 = 그 회차 tester·checker. 회차마다 프로젝트가 선언한
  checkpoint 를 돌려 고정 칸 표를 보고에 첨부 · 경보(exit 3)면 VALID/완료 보고 금지 → 4축 정리 → arch(+DA) 처방 →
  같은 워커 수정 → 재실행.
- **도구**(`scripts/ft-checkpoint.sh`): 프로젝트 `.fable-team/checkpoint.json`(명령·경보 exit·필수 칸)을 실행 ·
  exit 0 정상 / 3 경보 / 4 표·칸·명령 실패 / 5 미설정(무음 통과 금지).
- **닫기 조건**(`scripts/ft-nano-close.sh` ④): press/시험 카드면 마지막 checkpoint 표 실재 + alarm=no. 미설정 프로젝트는 경고만.
- **적용**(`references/update.md`): 프로젝트별 checkpoint.json 예시 3줄.

## 2026-09-30 — 승계 6단계 + 지시 원장 트리 + 누락 전수 점검

사용자 지시(BYZ-Agents v65 master#86 작업 방법 공유)를 베이스에 반영했습니다. 승계 때 후계에 상태·할 일이
안 넘어가고, 범위 한정으로 닫힌 행 아래의 사용자 지시가 통째로 누락되던 문제(16건 중 8건)에 대한 규율입니다.

- **승계 6단계**: 스냅샷 커밋 → 후계 스폰 → 상태·할 일·컨텍스트 요약 mbox 재송신 → 후계 응답(골 대조) recv →
  뉴스·크론이 후계로 가는지 확인 → 구 좌석 유휴. 후계 발주문에도 6단계를 적습니다.
- **트리 = 골 원장 행 + 사용자 지시 원장 열린 항목**: 행을 범위 한정으로 닫을 땐 하위 지시 항목의 완성 전/후 이관 줄 필수.
- **승계 첫 일 누락 전수 점검**: 지시 × 카드 × 닫힘 sha 대조, «카드 없음 + 증거 없음» 맨 위.
- **설명은 사용자가 겪는 일로**, **아키텍처 영향 사건은 즉시 아키텍처 원장에 기록**.

반영 위치: `skill/SKILL.md`(운영 규율 5~7), `skill/templates/rules/orchestration.md`(컨텍스트 증류 절 — 프로젝트로 복사되는 정본),
`skill/references/context-management.md`(§2.5 승계 6단계).

## 2026-07-28 — 문제해결 표준 체인 + checker 4축 실측 규칙

역할 경계를 두 군데 조였습니다. 출처는 BYZ-Agents v6-realtime-live 커밋 `2216ffdc`(FB_Master#88 규율 업데이트).

- **문제해결 표준 체인**: `checker → 오케(Master) → architect → (DA) → 오케(Master) → impl`.
  checker는 실측·정리만 하고 판정을 붙이지 않습니다. 오케(Master)는 checker 정리에 의심 방향을 얹어
  architect에 넘기되 **그것이 관찰이지 판정이 아님을 명시**합니다. 원인 규명·설계 판정은 architect가
  하고 **DA 소환 여부도 architect가 정합니다**(DA는 architect에 회신). 최종본 라우팅은 다시 Master.
  - 오케(Master)가 **하지 않는 것 셋**: 원인 규명 / 수정 방향·위치 지정 / DA 직접 소환.
  - **DA 상시 대기 금지** — `DA approve loop` / `DA review`로 필요할 때만. 대기 유지 자체가 왕복과
    조건 증식을 만듭니다(실증: 조건 7항 증식 → 라이브 지연).
- **checker 4축 실측**: FE 콘솔 / poller·DOM / worker(서버 로그) / durable 저장소를 전부 봅니다.
  FE 미확인 전 "처리 실패" 판정 금지, poller·DOM 미확인 전 "출력 없음" 판정 금지, 복수 호출은 전부
  나열하고 실패 지표가 몇 번째인지 명시. **사용자가 눈으로 본 것과 분석이 어긋나면 분석이 틀린 것**
  — 그때는 안 본 축부터 봅니다.

반영 위치: `skill/SKILL.md`, `skill/references/rapid-iteration-loop.md`(정본 — 역할 체인·4축·안티패턴 11~13),
`skill/templates/rules/orchestration.md`, `skill/templates/session-prompts/{checker,architect,da-codex,da-cursor}.md`,
`skill/references/agent-templates/{ft-checker,ft-architect,ft-da,ft-da-cursor,ft-da-claude}.md.tpl`.

## 2026-07-11 — v3 업그레이드 (tmux 기반 전면 개편)

fable-team이 각 에이전트를 tmux 세션으로 직접 띄우고, 서로 메시지를 주고받고, 작업이 끝나면 스스로
정리하도록 구조를 전면 교체했습니다. 여기에 더해 세션 압축(증류) 시 모델의 확장 컨텍스트(1M)/추론
강도 설정이 유실되던 문제 수정, 전문가(fable-5) 브레인의 전체 구현 재검토, 대규모 동작 검증(23개
시나리오) 중 실측으로 발견한 버그 다수를 함께 처리했습니다.

- 요약 문서: [docs/artifact/2026-07-11-v3-upgrade-summary.html](docs/artifact/2026-07-11-v3-upgrade-summary.html)
- 설계 원문: [.fable-team/designs/roster-v3-design.md](.fable-team/designs/roster-v3-design.md)
- 구현 전체 검토 보고서: [.fable-team/state/v3-upgrade-design/implementation-review-fable5.md](.fable-team/state/v3-upgrade-design/implementation-review-fable5.md)
- 진행 원장(전 과정 기록): [.fable-team/state/state.md](.fable-team/state/state.md)
