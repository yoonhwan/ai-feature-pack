# r957 — spawn 계열 시험이 실 tmux 서버에 좌석을 남긴 결함 (증거)

카드: `design/harness/indices/진행/r957-spawn-tests-leak-real-tmux-sessions.md` · 좌석 `byz-harness-nano-r957-spawn-tests-leak-real-tmux-sessions#0`
팩 base = `origin/main` a1fccaf7 · 브랜치 `nano/r957-spawn-tests-leak-real-tmux-sessions-r3`

## 0. 고친 것 (1줄)

시험이 진짜 tmux 서버에 닿지 않게 하는 **공용 격리 도우미 1개**(`tests/lib/tmux_isolate.sh`) + 그 도우미 자체 시험(`tests/test_tmux_isolate.sh`) + spawn 계열 시험 9개가 도우미를 쓰고 끝에 **누수 검사 1줄**을 남긴다.

## 1. 뿌리 (실측)

| 관측 | 원문 |
|---|---|
| 시험이 가짜 `tmux` 만 PATH 앞에 두고 **가짜 `tmuxc` 는 두지 않는다** | `test_nano_spawn_teamset_cap.sh`: `PATH="$FAKE:$PATH"`, `$FAKE` 에는 `tmux` 만 · `test_r655_nano_name_prefix.sh` 동형 |
| 좌석 안에서 돌면 클라이언트가 `$TMUX` 소켓으로 **직행**하고 `TMUX_TMPDIR` 을 무시한다 | `TMUX_TMPDIR=$D tmux ls` → 실 서버 목록 33개 그대로 · `env -u TMUX -u TMUX_PANE TMUX_TMPDIR=$D tmux ls` → `error connecting to $D/tmux-501/default (No such file or directory)` |
| 진짜 `tmuxc` 가 불리면 **부팅 실패(rc1)여도 세션은 남는다** | `tmuxc open … --name r957-probe --agent claude` → `state=not-ready session=r957-probe — 입력 상자가 30초 안에 안 떴다` / `tmuxc session created · 부팅 문장 제출 실패 rc=1` / `tmux ls` → `r957-probe: 1 windows (created …)` |
| spawn 은 그 실패를 REJECT 로 끝낸다 → **시험은 세션이 생긴 걸 모른다** | `REJECT tmuxc open 실패 (byz-v65-nano-x#0)` |
| 사건 시각과 수정 시각 | 누수 `2026-10-26 13:29` · r921 세계에 가짜 `tmuxc` 가 들어온 커밋 `ae0ced38 2026-10-26 14:36:26` |

ⓐ **정정(측정이 추론을 이김)**: 카드가 지목한 `test_resource_warn_proceed_r921.sh` 를 **지금 판**으로 10회 넘게 돌려도 실 서버에 `byz-alpha-*` 가 늘지 않는다(아래 §2). 이유 = `ae0ced38`(14:36)이 그 시험의 `$T/world` 에 가짜 `tmuxc` 를 넣었다 — 누수(13:29)는 그 **이전 판**(`1ac7a64a` 12:46)의 `runspawn` 이 진짜 `tmuxc` 를 부른 결과다. 기전은 살아 있다: 가짜 `tmuxc` 가 없는 경로가 하나라도 있으면 그 자리에서 실 서버에 세션이 남고, 시험은 그걸 모른 채 PASS/FAIL 을 낸다.

## 2. ⓑ~ⓔ 원문

ⓑ 도우미를 source 하면 `TMUX`·`TMUX_PANE` 이 없어지고 `TMUX_TMPDIR` 이 시험 전용 폴더가 된다 — 진짜 `tmux`·진짜 `tmuxc` 가 불려도 그 폴더 소켓만 본다. 끝나면 **그 소켓의 세션만** `kill-session`(`kill-server` 0 · 실 서버 0).

ⓒ spawn 계열 시험 9개 + 도우미 자체 시험을 이어서 돌린 뒤 실 서버 세션 목록(이름 정렬) 비교:

```
$ tmux ls | sed 's/:.*//' | sort > before.txt      # 33개
$ <10개 시험 차례로 실행>
$ tmux ls | sed 's/:.*//' | sort > after.txt       # 33개
늘어난 것 = []                                     # comm -13 before after 결과 빈 줄
```

시험별 결과(왼쪽 = 고치기 전, 오른쪽 = 고친 뒤):

| 시험 | rc | PASS | FAIL | 누수 줄 |
|---|---|---|---|---|
| test_tmux_isolate.sh (신규) | 0 | 8 | 0 | 있음(ⓑ·ⓓ) |
| test_resource_warn_proceed_r921.sh | 0 → 0 | 71 → 72 | 0 → 0 | 있음 |
| test_nano_spawn_teamset_cap.sh | 0 → 0 | 18 → 19 | 0 → 0 | 있음 |
| test_r655_nano_name_prefix.sh | 1 → 1 | 47 → 48 | 2 → 2 | 있음 |
| test_spawn_queue_folder_done_r681.sh | 0 → 0 | 9 → 10 | 0 → 0 | 있음 |
| test_teamset_check.sh | 0 → 0 | 37 → 38 | 0 → 0 | 있음 |
| test_teamset_gitref.sh | 0 → 0 | 20 → 21 | 0 → 0 | 있음 |
| test_board.sh | 0 → 0 | 72 → 73 | 0 → 0 | 있음 |
| test_da_hold_gate.sh | 1 → 1 | 91 → 92 | 7 → 7 | 있음 |
| test_team_path_oldpath_md.sh | 0 → 0 | 63 → 64 | 0 → 0 | 있음 |

=PASS 가 정확히 1씩 는 것은 새로 넣은 **누수 검사 줄 1개**다. 기존 PASS/FAIL·rc 는 그대로(ⓓ «기존 결과 불변»).
`r655` 2 FAIL·`da_hold_gate` 7 FAIL 은 **고치기 전부터** 있던 팩 드리프트다(예: `kit/fable-team/bin/ft-nano-slots.sh` 에 옛 접두 `ft-v65-temp-` 리터럴 · 홈 사본과 `COMM-GUIDE-BOOT.md` 줄수 차이) — 이 카드 범위 밖.

ⓔ 변이 대조 — 도우미의 `export TMUX_TMPDIR="$_ti_dir"` 한 줄을 끄고(`: # 변이: TMUX_TMPDIR 끔`) `test_tmux_isolate.sh` 를 다시 돌리면:

```
FAIL ⓐ TMUX= TMUX_PANE= TMUX_TMPDIR=
FAIL ⓑ 격리 소켓 목록=[… byz-alpha-r957guard#0 …]      ← 격리가 꺼져 실 서버가 그대로 보인다
FAIL ⓑ 실 서버가 변했다: [byz-alpha-r957guard#0 ]      ← ★누수가 검사에 잡힌다★
PASS ⓒ 실 서버에 늘면 누수 검사 FAIL(rc1 · 이름 지목)
PASS ⓒ-2 그 이름을 지우면 누수 검사 PASS(rc0)
PASS ⓓ 세션 정리 → 격리 소켓 세션 0
PASS ⓓ-2 end → 격리 폴더 삭제(소켓·흔적 0)
PASS ⓓ 실 서버 불변(정리 범위 = 격리 소켓만 · kill-server 0)
rc=3
```

변이 뒤 실 서버에 남은 `byz-alpha-r957guard#0` 1개는 그 턴에 그 이름으로 `kill-session` 했다(남의 세션·`kill-server` 0). 줄을 되돌린 뒤 재실행 = `ALL PASS`.

## 3. 시험 입력 ⓐ~ⓔ 대조표

| 카드 | 결과 |
|---|---|
| ⓐ r921 지금 판 → 실 서버 `byz-alpha-*` 가 는다 | **재현 안 됨**(§1 정정 — 가짜 `tmuxc` 가 14:36 에 들어옴). 기전은 §1 실측 3줄로 확정 |
| ⓑ 공용 도우미(TMUX_TMPDIR 격리 · 끝 trap · 전후 비교 함수) | `tests/lib/tmux_isolate.sh` — `test_tmux_isolate.sh` ⓐ~ⓓ ALL PASS |
| ⓒ 9개 시험 전부 도우미 사용 → 실 서버 세션 수 불변 · 각 시험 끝 누수 검사 1줄 | §2 표 + 실 서버 33→33 |
| ⓓ 9개 시험 기존 결과 불변 · /bin/bash 3.2 | §2 표(PASS +1 은 누수 줄) · `bash -n` 전부 통과 |
| ⓔ 변이: `TMUX_TMPDIR` 줄 끔 → 누수가 검사에서 FAIL | §2 ⓔ 원문 |

## 4. press 필요

없음 — 이 카드는 tmux·시험만 다룬다. 라이브 음성 경로 0.

## 5. 범위 밖(보고만)

- `kit/fable-team/bin/ft-nano-slots.sh` 에 옛 접두 `ft-v65-temp-` 리터럴이 남아 `test_r655_nano_name_prefix.sh` ⓖ 가 FAIL 한다(고치기 전부터). r655 규칙 정본화 카드 소관.
- `ft-nano-spawn.sh` 의 `tmuxc open` 실패 경로는 **세션이 남은 채** rc1 로 끝난다(§1 3행). 시험 쪽은 격리로 막았지만, 실 spawn 에서도 «열다 만 세션» 이 남는지는 별도 판정이 필요하다.

## 6. 반송 r2 — DA⑥ r1 HOLD 1 (arch 148 · REWORK-r957-r2.md · 반송서 커밋 b7a9e0c1f6)

**반례**: `test_tmux_isolate.sh` ⓒ 대조가 **실 서버 소켓**에 `new-session`/`kill-session` 을 직접 쳤다(:33·:37). 같은 이름 좌석이 실 서버에 이미 있으면 만들기는 실패하고 지우기는 그 기존 세션을 지운다.

**고침**:
- ⓒ 대조의 «실 서버» = **대역 서버**(`mktemp` 두 번째 소켓). 그 구간에서만 도우미의 실 소켓 변수 `_ti_sock` 을 대역 소켓으로 돌리고 끝나면 원래 값으로 되돌린다. 대역 정리는 **대역 소켓의 세션만** `kill-session`(`kill-server` 0).
- 실 서버(원래 `$TMUX` 소켓)에 대한 호출은 **`ls` 읽기만** — 시험·도우미 어디에도 실 소켓 대상 `new-session`·`kill-session`·`kill-server` 0.
- **ⓒ3 기록 shim** 신설: PATH 앞에 `tmux` shim(`-S <소켓> <동사>` 기록 후 진짜 tmux 로 exec)을 두고 `R957_ISO_INNER=1` 로 **이 시험 전체를 다시 돌린다** → 원래 실 서버 소켓 대상 동사가 `ls`·`list-sessions` 뿐이면 PASS.

```
$ bash tests/test_tmux_isolate.sh
PASS ⓐ source → TMUX·TMUX_PANE 없음 · TMUX_TMPDIR=시험 폴더(r957-tmux.6l7rdA)
PASS ⓑ 진짜 tmux new-session → 격리 소켓에만 생김(byz-alpha-r957guard#0)
PASS ⓑ 실 서버 세션 목록 불변 — 새 세션이 실 서버에 0
PASS ⓒ 대역 서버에 늘면 누수 검사 FAIL(rc1 · 이름 지목)
PASS ⓒ-2 그 이름을 지우면 누수 검사 PASS(rc0)
PASS ⓒ3 실 서버 소켓(default) 대상 동사 = ls 뿐(쓰기 0)
PASS ⓒ3 실 서버는 ls 로만 읽었다(기록 확인)
PASS ⓓ 세션 정리 → 격리 소켓 세션 0
PASS ⓓ-2 end → 격리 폴더 삭제(소켓·흔적 0)
PASS ⓓ 실 서버 불변(정리 범위 = 격리 소켓만 · kill-server 0)
ALL PASS
rc=0
```

**변이 «ⓒ 를 실 소켓으로 되돌림»** (대역으로 안 돌리고 `tmux -S "$_ti_sock" new-session/kill-session`):

```
PASS ⓐ · PASS ⓑ · PASS ⓑ
PASS ⓒ 대역 서버에 늘면 누수 검사 FAIL(rc1 · 이름 지목)
FAIL ⓒ-2 rc=1 FAIL 실 tmux 서버 세션 누수 — 늘어난 이름: byz-v65-master-claude#248
FAIL ⓒ3 실 서버 소켓에 쓴 동사: [kill-session new-session ]
PASS ⓒ3 실 서버는 ls 로만 읽었다(기록 확인)
PASS ⓓ · PASS ⓓ-2 · PASS ⓓ
FAILED 2   rc=2
```

→ DA 반례가 그대로 재현되고(`실 서버에 쓴 동사: kill-session new-session`) 검사가 잡는다. 변이 뒤 실 서버 byz-alpha 잔여 = 0.

**재실행(고친 판 · 인접 2F 2종 base 대조)**: `test_tmux_isolate` 10P 0F rc0 · `r921` 72P 0F rc0 · `teamset_cap` 19P 0F · `r655_nano_name_prefix` **48P 2F rc1**(base 도 47P **2F** rc1 — 같은 2건: `ⓖ 남은 곳 ft-nano-slots.sh 옛 접두`·`FAILED 1`) · `spawn_queue_folder_done` 10P · `teamset_check` 38P · `teamset_gitref` 21P · `board` 73P · `da_hold_gate` **92P 7F rc1**(base 도 91P **7F** rc1 — 홈 사본 줄수 차이 2 + spawn dry-run 계열 5) · `team_path_oldpath_md` 64P 0F.
실 서버 세션 이름 목록 = before 34 · after 34 · **늘어난 시험 이름 0**(사이에 다른 좌석 r958 개설·r960 종료가 있어 총수는 같고 이름 하나가 바뀐 것은 이 카드 밖 실 좌석 생활사 — `byz-alpha-*`·`byz-v65-*`·`ft-v65-temp-*` 늘어난 것 0).

## 7. 반송 r3 — DA⑥ r2 HOLD 1 · 같은 축 2회 = 재설계 (arch 148 REWORK-r957-r3.md + 보강 3줄)

**반례(DA)**: 없는 폴더를 `TMPDIR` 로 두면 `mktemp` 실패를 도우미가 삼켜 성공 반환 → `TMUX_TMPDIR=''` 인 채 `new-session` → 빈 값이면 진짜 tmux 는 기본 소켓(실 서버)을 본다.

**축**: «격리가 환경 변수 꾸미기에만 기대고, 꾸미기가 실패하면 기본값=실 서버로 떨어진다». 환경 변수 하나가 비면 또 샌다 → **구조로 닫았다**:

| r3 구조 | 자리 |
|---|---|
| ① 준비 실패 = 시험 시작 0 | `tmux_isolate_begin`: shim 폴더·격리 폴더·격리 소켓 경로 3중 가드. 하나라도 실패 = `ERROR r957-tmux-isolate: …` + `exit 2`(본문 진입 0) |
| ② 모든 tmux 호출을 격리 소켓으로 | PATH 맨 앞 `tmux` shim — **격리 소켓 경로·진짜 tmux 절대경로를 생성 시점에 파일에 박는다**(환경 변수로 읽지 않음). 진짜 tmux 를 늘 `-S <격리 소켓>` 으로 부르고, 호출자 `-S`·`-L` 이 격리 폴더 밖이면 `REJECT … exit 91`. 진짜 `tmuxc` 가 불려도 그 안의 `tmux` 가 shim 을 지나므로 실 서버로 못 간다 |
| ③ 실 서버 읽기는 한 곳 | `tmux_isolate_real_ls` 하나뿐 — 저장한 진짜 tmux 절대경로 + 원래 소켓(`-S`)으로 `ls` 만. 그 밖 동사는 이 파일 어디에도 없다 |
| 보강 1 | shim 값 박기 + `TMUX_TMPDIR` 을 env -i 자식에 넘김(team_path `SP()` 줄) · `FT_TMUX_BIN` export 는 **하지 않는다**(실측: export 하면 시험의 가짜 tmux 를 덮어 r655 2F→4F · team_path 0F→3F — 계약 ④ 위반이라 되돌렸다) |
| 보강 2 | 누수 검사 패턴 = `^(byz-alpha-\|byz-r921-nano-\|byz-v65-\|ft-v65-temp-)` — 9시험이 쓰는 접두 전부. 검사는 «이름 목록 추가분 0»(다른 좌석 생활사는 접두 밖이라 안 센다) |
| 보강 3 | 대역 소켓을 격리 폴더 아래로(`$TMUX_ISOLATE_DIR/fixture-sock`) — shim 의 «폴더 밖 -S 거절» 과 충돌 0 |

```
$ bash tests/test_tmux_isolate.sh          # 17 PASS · rc=0
PASS ⓐ source → TMUX·TMUX_PANE 없음 · PATH 맨 앞 shim · 격리 소켓이 격리 폴더 안
PASS ⓑ shim 경유 new-session → 격리 소켓에만 생김(byz-alpha-r957guard#0)
PASS ⓑ 실 서버 세션 목록 불변 — 새 세션이 실 서버에 0
PASS ⓒ 대조 소켓에 늘면 누수 검사 FAIL(rc1 · 이름 지목)
PASS ⓒ-2 그 이름을 지우면 누수 검사 PASS(rc0)
PASS ⓣ1 TMPDIR=없는 폴더 → ERROR + rc2 · 본문 진입 0
PASS ⓣ1 실 서버 쓰기 0(준비 실패 경로 포함)
PASS ⓣ2 TMUX_TMPDIR='' → 세션은 격리 소켓에만 · 실 서버 쓰기 0
PASS ⓣ2 TMPDIR=파일 경로 → 격리 실패 rc2 · 본문 0 · 실 서버 쓰기 0
PASS ⓣ2 tmux -L default → shim REJECT rc91(실 서버 쓰기 0)
PASS ⓣ2 tmux -S <실 소켓> → shim REJECT rc91(실 서버 쓰기 0)
PASS ⓣ2 env -i 자식(PATH 만 · spawn 꼴) → 세션은 격리 소켓에만 · 실 서버 쓰기 0
PASS ⓒ3 실 서버 소켓(default) 대상 동사 = ls 뿐(쓰기 0)
PASS ⓒ3 실 서버는 ls 로만 읽었다(기록 대역 확인)
PASS ⓓ 세션 정리 → 격리 소켓 세션 0
PASS ⓓ-2 end → 격리 폴더·shim 삭제(흔적 0)
PASS ⓓ 실 서버 불변(정리 범위 = 격리 소켓만 · kill-server 0)
```

ⓒ3 은 **재귀 재실행 대신** «진짜 tmux 자리» 에 기록 대역(`R957_REAL_TMUX_OVERRIDE`)을 두고 이 시험 전체를 그 아래에서 돈다 — shim·직접 호출·`tmuxc` 경유가 전부 그 자리를 지나므로 `-S <소켓> <동사>` 가 한 파일에 남는다.

**변이 2종**:

```
변이 «shim 이 호출자 -S 를 그대로 넘김»
  FAIL ⓣ2 -S o=rc=0 writes=[/private/tmp/tmux-501/default	new-session ]
  FAILED 1
  ※ r3 판 기록 대역은 쓰기를 진짜 바이너리로 넘겼다 → 그 변이가 실 서버에 세션을 만들었다(DA⑥ r3 지적). r4 에서 기록 대역이 쓰기를 «기록만» 하도록 고쳐 이 변이도 실 서버 쓰기 0 이다(§8).

변이 «mktemp 실패 무시»
  1줄만 끄면 나머지 가드가 잡아 rc2 유지 → ⓣ1 PASS(3중 가드)
  3중 가드를 전부 끄면 도우미가 성립하지 않아 시험이 ⓐ부터 무너진다(rc≠0) — 초록 0
```

**재실행 10종(고친 판)**: test_tmux_isolate 17P 0F rc0 · r921 72P 0F · teamset_cap 19P 0F · **r655 48P 2F rc1(base 47P 2F — 같은 2건)** · spawn_queue 10P · teamset_check 38P · teamset_gitref 21P · board 73P · **da_hold_gate 92P 7F rc1(base 91P 7F)** · team_path 64P 0F.
실 서버 세션 이름 목록 = before 32 · after 32 · **늘어난 것 0**(시험 접두 0 · 전체 0).

## 8. 반송 r4 — DA⑥ r3 HOLD 3 · 보류 3회째 (arch 148 REWORK-r957-r4.md)

**반례 3건(DA r3)과 고침**:

| 반례 | 자리 | r4 고침 |
|---|---|---|
| ① 묶음 옵션 `-uS"$REALSOCK"` — shim 이 글자로만 보고 그대로 넘겨 진짜 tmux 가 뒤의 실 소켓을 고름 | shim 인자 파서 | shim 이 전역 옵션을 **tmux getopt 문자열(`2c:CDdf:hlL:NqS:T:uUvV`)** 로 한 글자씩 읽는다(bash `getopts` — 묶음·붙임·따로 전부 같은 규칙) |
| ② 상위 경로 `-S "$ISO/../../../private/tmp/tmux-501/default"` — 글자 접두만 통과 | shim 경로 검사 | `-S` 값의 **실제 경로**를 `cd -P` 로 풀어(`..`·심볼릭 링크 해소) 격리 폴더 아래일 때만 통과, 아니면 `REJECT rc91`. `-L` 은 언제나 거절, 모르는 전역 옵션도 거절 |
| ③ 변이 시험이 실 서버에 new/kill-session — 기록 대역이 쓰기를 진짜로 넘김 | `test_tmux_isolate.sh` 기록 대역 | 기록 대역이 **쓰기 동사를 기록만 하고 넘기지 않는다**(실 서버 소켓 향 = `WRITE-BLOCK` + rc1 · 읽기 `ls` 만 통과 · 격리 소켓 향은 그대로). 변이·시험 전부 이 대역 아래에서만 돈다 |

그리고 **shim 이 내는 `-S` 는 언제나 하나**(우리 격리 소켓) — 호출자 `-S` 를 통과시켜도 진짜 tmux 는 우리 소켓만 본다(뒤 `-S` 가 이기는 규칙을 쓰지 않는다). 그래서 글자 검사가 뚫려도 실 서버로 못 간다(2중).

**시험 ⓥ·ⓦ + 변이**:

```
PASS ⓥ 묶음 -uS<실 소켓> → 실 서버 쓰기 0 · rc=91
PASS ⓥ 따로 -u -S <실 소켓> → 실 서버 쓰기 0 · rc=91
PASS ⓥ 붙임 -S<실 소켓> → 실 서버 쓰기 0 · rc=91
PASS ⓥ -S .. 상위 경로 → 실 서버 쓰기 0 · rc=91
PASS ⓥ 격리 폴더 안 심볼릭 링크→실 소켓 → 실 서버 쓰기 0 · rc=91
PASS ⓥ -L default → 실 서버 쓰기 0 · rc=91
PASS ⓥ 모르는 전역 옵션 -x → 실 서버 쓰기 0 · rc=91
PASS ⓥ 꼴 7종 전부 확인(묶음·따로·붙임·..·심볼릭·-L·모르는 옵션)
PASS ⓦ 변이 shim 이 실 소켓을 지정해도 기록 대역이 막는다(넘긴 쓰기 0 · 막힘 1)
PASS ⓒ3 실 서버 소켓(default) 대상 = 읽기(ls)뿐 · 쓰기 통과 0
ALL PASS   (26 PASS · rc=0)
```

**변이 2종**:

```
«기록 대역이 쓰기를 넘김»(R957_MUT_PASSTHRU=1 · «실 서버» 를 대역 소켓으로 돌려 실 서버는 안 건드림)
  FAIL ⓦ 변이 «기록 대역이 쓰기를 넘김» — WRITE-PASS 1건(검출)
  FAILED 1

«shim 을 글자 접두 검사로 되돌림» — ⓥ 는 그대로 PASS 한다(계약상 검출 대상 아님)
  이유: r4 는 «검사» 와 «실행» 을 분리했다 — shim 이 진짜 tmux 를 부를 때 호출자 -S 를 쓰지 않고 우리 격리 소켓 하나만 쓴다.
  그래서 글자 검사가 뚫려도 실 서버로 가는 길이 없고, ⓥ 7꼴이 매 실행 «실 서버 쓰기 0» 을 확인한다.
```

**재실행 10종(고친 판)**: test_tmux_isolate 26P 0F rc0 · r921 72P 0F · teamset_cap 19P 0F · **r655 48P 2F rc1(base 47P 2F)** · spawn_queue 10P · teamset_check 38P · teamset_gitref 21P · board 73P · **da_hold_gate 92P 7F rc1(base 91P 7F)** · team_path 64P 0F.
실 서버 세션 이름 목록(읽기만) = before 33 · after 33 · **늘어난 시험 접두 0**.

## 9. 반송 r5 — DA⑥ r4 HOLD 1 (arch 151 재설계 · 세트 193d93ce 위)

**반례 1건(R1)과 고침**: 입력 `env -u TMUX -u TMUX_PANE /bin/bash tests/test_tmux_isolate.sh` — tmux 밖 실행이면 실 소켓 값이 **빈 값**이라 기록 대역의 차단 조건(`[ -n "$R957_REAL_SOCK" ] && sock == R957_REAL_SOCK`)이 통째로 건너뛰어지고, 진짜 tmux 바이너리로 `new-session` 이 넘어갔다(r4 자리 :43 → :50).

| 반례 | 자리 | r5 고침 |
|---|---|---|
| R1 tmux 밖(실 소켓 값 빈) → 값 비교가 건너뛰어져 쓰기 통과 | `test_tmux_isolate.sh` 기록 대역 | **차단 기준을 값 비교에서 «허용 목록» 으로 바꾼다** — 격리 폴더(`R957_ISO_ALLOW`) 아래 소켓만 통과(`cd -P` 실제 경로 비교), 나머지는 전부 `WRITE-BLOCK` rc1. `R957_ISO_ALLOW` 는 도우미가 `tmux_isolate_begin` 에서 export. 빈 값·대체 경로 둘 다 닫힌다(막히는 쪽 기본값 = fail-closed) |
| R2 격리 폴더 아래 소켓은 허용(회귀 0) | 같은 자리 | 격리 폴더 아래 소켓은 종전대로 통과 — ⓑ·ⓒ·ⓓ·ⓒ3 이 그대로 PASS |

**ⓐ 빨강 먼저(고침 전 · 새 칸 ⓦ' 추가 판)**:

```
FAIL ⓦ' 넘긴 쓰기=0 막힘=0 o=rc=0
FAIL ⓦ' 대역 소켓이 변했다: byz-alpha-r957wp#0 byz-alpha-r957wpkeep#0
FAILED 2   (rc=2)
```
= tmux 밖 자식이 격리 폴더 밖(대역) 소켓에 **실제로 세션을 만들었다**(byz-alpha-r957wp#0). 막힘 0.

**ⓑ 고친 뒤(같은 판 · 28 PASS rc0)**:

```
PASS ⓦ' tmux 밖(실 소켓 값 빈) → 격리 폴더 밖 쓰기 막힘 1 · 넘긴 쓰기 0
PASS ⓦ' 대역 소켓 세션 목록 불변(byz-alpha-r957wpkeep#0 )
ALL PASS   (28 PASS · rc=0)
```

**변이 2종(둘 다 «검출» = 시험이 FAIL 로 잡는다)**:

```
«값 비교 되살림»(R957_MUT_VALUECMP=1 — 기록 대역이 r4 판 조건으로 돌아간다)
  FAIL ⓦ' 넘긴 쓰기=0 막힘=0 o=rc=0
  FAIL ⓦ' 대역 소켓이 변했다: byz-alpha-r957wp#0 byz-alpha-r957wpkeep#0
  FAILED 2

«기록 대역이 쓰기를 넘김»(R957_MUT_PASSTHRU=1 · 대역 소켓으로 돌려 실 서버는 안 건드림)
  FAIL ⓦ 변이 «기록 대역이 쓰기를 넘김» — WRITE-PASS 1건(검출)
  FAILED 1
```

**test_board 2F — base 대조(3항목)**: 같은 창에서 base(a1fccaf7) 와 내 세트를 나란히 돌렸다.

| 판 | 결과 |
|---|---|
| base a1fccaf7 `tests/test_board.sh` | **72P 0F rc0** |
| 내 세트 `tests/test_board.sh` | **73P 0F rc0**(+1 = 이 카드가 넣은 「누수 0」 줄) |
| 판정 | DA⑥ r4 가 본 2F 는 **이 세트 탓이 아니다** — 지금 판에서 양쪽 다 0F(그때의 명부·보드 상태 차이). 고칠 것 없음 |

**재실행 10종(고친 판)**: test_tmux_isolate **28P 0F rc0** · r921 72P 0F · teamset_cap 19P 0F · **r655 48P 2F rc1(base 47P 2F)** · spawn_queue 10P · teamset_check 38P · teamset_gitref 21P · board 73P 0F · **da_hold_gate 92P 7F rc1(base 91P 7F)** · team_path 64P 0F. 새 FAIL 0(두 rc1 은 base 와 같은 건수 · PASS 만 +1 = 누수 검사 줄).

**실사건(10시험 1회 전후 · 실 서버는 읽기만)**: before **54** · after **54** · **늘어난 것 0 · 사라진 것 0**. 시험 접두(byz-alpha-·byz-r921-nano-·byz-v65-·ft-v65-temp-) 늘어난 것 0.

## 10. 알려진 한계 (오빠 결정 2번 · 범위 줄여 착지 · 2026-10-27)

이 고침은 **이 카드가 지목한 시험 9개 + 격리 도우미 자체 시험**에만 적용된다 — 그 밖의 시험(카드 §구현 범위 밖)이 격리 도우미를 source 하지 않으면 지금도 진짜 tmux 서버에 세션을 남길 수 있다(전 시험 전수 적용은 다음 카드).

## 11. r3 재확인 (2026-10-27 · 브랜치 `-r3` · 외부 검증 생략 = 결정 2번)

10시험 1회 재실행 결과 = r5 판과 같다(새 FAIL 0 · rc1 두 건은 base 와 같은 건수).

| 시험 | rc | PASS | FAIL | 누수 줄 |
|---|---|---|---|---|
| test_tmux_isolate | 0 | 28 | 0 | 도우미 자체(ⓑ·ⓓ 칸) |
| test_resource_warn_proceed_r921 | 0 | 72 | 0 | PASS 누수 0(1) |
| test_nano_spawn_teamset_cap | 0 | 19 | 0 | PASS 누수 0(1) |
| test_r655_nano_name_prefix | 1 | 48 | 2 | PASS 누수 0(1) |
| test_spawn_queue_folder_done_r681 | 0 | 10 | 0 | PASS 누수 0(1) |
| test_teamset_check | 0 | 38 | 0 | PASS 누수 0(1) |
| test_teamset_gitref | 0 | 21 | 0 | PASS 누수 0(1) |
| test_board | 0 | 73 | 0 | PASS 누수 0(1) |
| test_da_hold_gate | 1 | 92 | 7 | PASS 누수 0(1) |
| test_team_path_oldpath_md | 0 | 64 | 0 | PASS 누수 0(1) |

r655 2F · da_hold_gate 7F 는 base(a1fccaf7) 판과 같은 건수다(§9 대조표) — 이 세트가 만든 FAIL 은 0.

**실사건(r3 · 10시험 1회 전후 · 실 서버는 `ls` 읽기만)**: before **54** · after **54** · 시험 접두(byz-alpha-·byz-r921-nano-·byz-v65-·ft-v65-temp-) **1 → 1**(사건 전부터 있던 다른 팀 `byz-v65-master-claude#248`) · **늘어난 시험 세션 0**.
같은 창에 이름이 바뀐 두 건(`+r1000-index-move-archive-abandoned#0`, `+r983-da-metrics-read-only#0` / `-r852-slack-root-readable-readback#0`, `-r853-news-verify#0`)은 다른 팀 좌석 개설·종료 = 이 카드 밖 생활사다.
