최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — C12(consumer 상시 서비스 회복) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 — C12. 안 B(AIRAG.app) 구현 DA 1회차 REJECT 의 동작 반례 R1~R4 수정 설계 1장.

# AIRAG.app 수정 설계 1회차 (arch-20261029-appB-fix-r1)

- 작성: aifp-airag-arch-claude#2 (Opus 5.5) · 발주 #3513 (aifp-airag-master-claude#9) · 2026-10-29
- 입력: 판정서 `da-20261029-appB-r1.md`(19e2107e) · 구현 4be48d7d · 시험 3d32521d · 설계 정본 `arch-20261029-appB.md`
- 동결 집합: R1~R4. 이 밖의 새 반례는 새 카드로 센다. 이 카드의 DA 호출은 3회 중 1회를 썼고, 다음 판정이 2회째다.

## 0. 결론

| 반례 | 고치는 곳 | 방식 (추천) | tick.py 변경 |
|---|---|---|---|
| R1 서명 키 재사용 | `build.sh` | **(§10 보정 · 안 1D)** 키체인 비밀번호를 1Password `develop` 볼트 항목에 둔다(평문 파일 0). 서명 직전 `op read` 로 읽어 `security -i` 표준 입력으로만 해제한다. 해제 실패면 codesign 을 부르지 않는다. | 없음 |
| R2 손자 생존 | `AIRAG.swift` | tick 을 그룹장으로 둔 프로세스 그룹 전체에 신호를 보낸다. 그룹이 빌 때까지 «패스 끝» 으로 치지 않는다. | 없음 |
| R3 75초 | `AIRAG.swift` | `--once` 는 기동 시각 기준 절대 마감 3개(종료 신호 45초, 강제 종료 52초, 포기 57초)로 돈다. | 없음 |
| R4 경로 검사 누락 | `AIRAG.swift` | 경로 검사를 `main` 맨 앞에서 한 번 한다. `--once` 는 잘못된 위치면 tick 을 돌리지 않고 종료 코드 78 로 끝낸다. | 없음 |

- tick.py 를 바꾸지 않는다. 그래서 R-H(82a5b73) 는 영향이 없고 R-H 회귀 대상도 아니다.
- 오빠 결정 필요: 없음. 오빠 답 «op developer» 에 따라 R1 은 §10 의 안 1D 로 바꿨다(발주 #3517). §3-3·§3-4 의 1A 는 기록으로만 남기고 구현하지 않는다.

## 1. 실측 사실 (이번 설계의 근거)

앱 실행, 키체인 쓰기, op 실행은 0회다. 아래 실측은 scratchpad 의 임시 실행 파일과 `/bin/sh sleep` 으로만 했다.

| # | 사실 | 근거 |
|---|---|---|
| M1 | Foundation `Process` 는 macOS 에서 자식을 새 프로세스 그룹의 장으로 띄운다. 자식 pgid 는 자식 pid 와 같고, 세션은 부모와 같다. | `child pgid == child pid` 출력 (scratchpad `pg/main.swift`) |
| M2 | 그룹장 pid 하나에만 SIGTERM 을 보내고 회수하면 손자가 남는다. 이것이 R2 의 실측 재현이다. | 변형 A: `group alive = true` |
| M3 | 같은 상황에서 `kill(-pgid, SIGTERM)` 을 보내면 0.37초 안에 그룹이 비고 `kill(-pgid,0)` 이 ESRCH 를 돌려준다. | 변형 B: `group alive = false 0.37s` |
| M4 | 이 맥에서는 일반 사용자가 다른 사용자(root 포함) 프로세스의 명령 인자를 볼 수 있다. 그래서 `security unlock-keychain -p <비밀번호>` 는 다른 로컬 사용자에게 값이 보이는 경로다. | `ps -axo user,args` 에 root 프로세스 인자 표시 |
| M5 | `security -i` 는 표준 입력으로 받은 명령의 실패를 종료 코드로 돌려준다. 없는 키체인을 해제하면 rc 50 이 나오고, 직접 호출해도 rc 50 이 나온다. | `security -i rc=50`, `direct rc=50` |
| M6 | `~/Library/Keychains` 에 airag 키체인은 0개다. `make-identity` 는 아직 한 번도 돌지 않았다. 그래서 R1 수정에 옮길 기존 상태가 없다. | `grep -c airag` = 0 |
| M7 | tick 의 키 읽기는 3개를 3개 작업자로 동시에 읽는다. 키 하나는 최대 21초라서 op 구간은 최대 21초다. | `tick.py:434-435`, `OP_CALL_DEADLINE_S` |
| M8 | 패스 자식의 상태 파일 쓰기는 임시 파일, fsync, `os.replace` 순서다. 흔적 파일은 한 세대(.prev)를 남긴다. 그래서 그룹 SIGKILL 로 반쯤 쓰인 파일이 남지 않는다. | `operations.py:223-244`, `_pass_trace.py:133` |
| M9 | 옛 launchd 안도 같은 의미였다. launchd 는 `AbandonProcessGroup` 의 기본값 false 에서 잡이 끝날 때 잡의 프로세스 그룹을 정리한다. 그룹 전체 종료는 운영이 이미 전제하던 동작이다. | launchd.plist(5) 의 AbandonProcessGroup 정의 [확인 필요: 이 맥 man 페이지 원문 대조] |

## 2. 공통 구조: 실제 프로세스 연결부를 시험 구역으로 옮긴다

판정서는 변이 «`kill(pid,sig)` 를 빈 함수로» 가 73/73 으로 살아남았다고 적었다. 원인은 실제 신호 연결부가 `#if !AIRAG_TEST` 안에 있어 시험이 컴파일하지 않는 데 있다.

- 1구역(시험이 컴파일함)에 `LiveProcessOps` 를 둔다. AppKit 을 쓰지 않는다. 담당은 아래 넷이다.
  - `spawn(executable, arguments, environment, stderrPath, onExit) -> Int32?`: Foundation `Process` 로 띄운다. 띄운 직후 `getpgid(pid)` 를 확인한다. 값이 pid 와 다르고 -1(이미 끝남)도 아니면, 그 pid 에 SIGKILL 을 보내고 nil 을 돌려준다(M1 이 깨진 Foundation 변경에 대한 막이).
  - `signalGroup(pgid, sig)`: `kill(-pgid, sig)` 만 한다.
  - `groupAlive(pgid) -> Bool`: `kill(-pgid, 0) == 0 || errno == EPERM`.
  - 시계와 예약은 지금처럼 주입한다.
- 앱(2구역)은 `makeLiveController(settings:schedule:)` 한 줄로 제어기를 만든다. 이 팩토리도 1구역에 두고, 시험이 같은 팩토리를 실제 `/bin/sh` 자식으로 부른다.
- tick 은 지금처럼 Foundation `Process` 로 직접 띄운다. 셸, launchctl, `open`, posix_spawn 직접 호출로 바꾸지 않는다. 그래서 권한 책임 주체 경로(K1)는 4be48d7d 와 같다.
- pgid 재사용 위험은 없다. POSIX 는 그 번호의 프로세스 그룹이 남아 있는 동안 같은 번호를 새 pid 로 주지 않는다. 그룹장을 회수한 뒤에도 그룹원이 남아 있으면 번호가 보존된다.

## 3. R1: 같은 서명 키를 재부팅 뒤에도 쓰게 하기

> 보정(발주 #3517): 구현 기준은 §10 의 안 1D 다. 이 절의 1A(0600 파일)는 오빠 결정으로 대체됐다. §3-1 요구와 «해제 실패면 codesign 0» 은 그대로 유효하다.

### 3-1. 요구

- 재부팅이나 잠금 뒤 `build.sh build` 가 같은 개인키와 인증서로 서명한다. 그래야 지정 요건(번들 ID + 인증서 잎 해시)이 같고 TCC 허용이 유지된다(K3).
- 어떤 경로에서도 GUI 창(키체인 접근, 잠금 해제)을 띄우지 않는다(K6).
- 값(비밀번호, 키)이 화면, 로그, 명령 인자에 나오지 않는다(M4).

### 3-2. 선택지

| 안 | 보관 | 해제 | 비밀 사본 | GUI 창 위험 | 오빠 손 |
|---|---|---|---|---|---|
| **1A (추천)** | 전용 키체인 + 비밀번호 파일 `~/.config/airag/sign/keychain.pass` (0600, 소유자 본인, 심링크 거부) | 서명 직전 `printf 'unlock-keychain -p %s %s\n' … \| security -i` (표준 입력, M5 로 rc 판정) | 있음: 파일 1개 | 낮음: 해제 실패면 codesign 호출 0 | `make-identity` 1회 |
| 1B | 전용 키체인 + 비밀번호를 로그인 키체인의 일반 암호 항목으로 저장 (`-T /usr/bin/security`) | `security find-generic-password -w` 출력을 같은 표준 입력 경로로 넘긴다 | 로그인 키체인 안 | 중간: 항목 ACL 이나 partition 이 어긋나면 로그인 키체인 접근 창이 뜰 수 있다 [확인 필요] | `make-identity` 1회 |
| 1C | 서명 신원을 로그인 키체인에 직접 넣는다 | 로그인 때 자동 해제 | 없음 | 중간: `set-key-partition-list` 에 로그인 비밀번호가 1회 필요하다. 실패하면 codesign 이 창을 띄운다 | 실제 터미널에서 로그인 비밀번호 1회 입력 (`!` 한 줄로 못 함) |

- 버리는 안: 매 빌드마다 키체인이나 인증서를 새로 만드는 방식. K3 의 «같은 신원» 을 깬다(판정서 R1 «고쳐야 할 동작»).
- 버리는 안: 개인키 p12 파일 + 매 빌드 임시 키체인. 비밀 사본이 1A 보다 크고(개인키 자체), `create-keychain` 이 사용자 키체인 검색 목록을 매번 바꾼다.

### 3-3. 비밀 사본(1A 의 파일)의 위험과 필요성

- 필요성: 키체인은 재부팅하면 잠긴다. 비밀번호를 어디에도 두지 않으면 같은 키를 다시 쓸 길이 없다(R1 그대로). 오빠께 매번 입력을 받으려면 값을 한 번 보여 드려야 하는데, 이는 «값 출력 0» 과 충돌한다.
- 이 파일로 얻는 것은 «AIRAG Local Signing» 신원으로 서명하는 능력뿐이다. 서명하면 지정 요건이 같아져 1Password 그룹 컨테이너 허용을 물려받을 수 있다.
- 같은 사용자 권한의 공격자는 이미 같은 일을 더 쉽게 한다. 앱은 사용자 쓰기 가능한 `~/.local/share/airag/runtime` 의 python 과 tick 코드를 실행하고, `app.json` 으로 실행 파일도 바꿀 수 있다(판정서 O1). 그래서 파일 1개가 늘리는 공격면은 같은 사용자 범위 안에서 0 에 가깝다.
- 다른 로컬 사용자: 0600 이라 못 읽는다. 명령 인자로는 넘기지 않는다(M4). 남는 노출은 디스크를 물리적으로 읽는 경우다. FileVault 가 꺼져 있어(앞 설계 G 사실) 그 경우에는 이 파일 말고도 모든 사용자 파일이 노출된다.
- 그래서 1A 를 추천한다. 1B 는 비밀을 평문 파일에서 빼지만 GUI 창 위험을 만든다. 1C 는 비밀 사본이 없지만 오빠 손(실제 터미널, 로그인 비밀번호)이 필요하고 오빠의 주 키체인을 바꾼다.

### 3-4. 1A 동작 (build.sh)

1. `make_identity`
   1. 키체인 파일이나 비밀번호 파일 중 하나라도 있으면 거부한다(지금처럼, 대상만 둘로).
   2. `umask 077` 을 건다. 비밀번호를 만든 뒤 같은 폴더의 임시 파일(O_EXCL)에 쓰고 `mv` 로 확정한다. 키체인보다 파일을 먼저 확정한다.
   3. 키체인 생성, 해제, import, partition-list 단계는 지금과 같다. 단, `-p`/`-P`/`-k` 로 값을 넘기는 세 곳 모두 `security -i` 표준 입력으로 옮긴다(M4).
   4. 어느 단계든 실패하면 만든 키체인과 비밀번호 파일을 함께 지우고 실패로 끝낸다. 반쪽 상태(키체인만 있음, 파일만 있음)를 남기지 않는다.
2. `sign_app` (신원이 `-` 가 아닐 때)
   1. 비밀번호 파일을 검사한다: 일반 파일, 소유자 본인, 0600, 심링크 아님, 64바이트 이하.
   2. `security -i` 표준 입력으로 `unlock-keychain` 을 보낸다. stdout·stderr 는 버리고 rc 만 본다.
   3. rc 가 0 이 아니면 고정 문구 `build.sh: signing keychain locked and could not be unlocked` 를 내고 끝낸다. codesign 을 부르지 않는다. 잠긴 키체인에 codesign 을 부르면 잠금 해제 창이 뜰 수 있기 때문이다 [확인 필요: 실측하지 않음. 그래서 호출 자체를 막는다].
   4. codesign 에 `--keychain` 을 붙여 그 키체인만 찾게 한다(지금과 같음).
3. 키체인 파일은 있는데 비밀번호 파일이 없는 경우(옛 상태)는 «복구 불가» 다. 고정 문구로 «신원을 새로 만들어야 하고, 그러면 TCC 허용을 1회 다시 받아야 한다» 를 알린다. 지우기는 HIL 이다. M6 에 따라 지금은 이 상태가 없다.
4. 비밀번호를 담는 변수는 `set +x` 구간에서만 쓴다. 어떤 출력에도 넣지 않는다.

## 4. R2: 실행 중인 작업 전체의 수명을 정지·재시작에 묶기

### 4-1. 선택지

| 안 | 내용 | R2 를 닫나 | 비용 |
|---|---|---|---|
| **G1 (추천)** | 앱이 tick 의 프로세스 그룹 전체에 신호를 보낸다. 그룹이 빌 때까지 «패스 끝» 으로 치지 않는다. | 닫는다. M2·M3 가 실측 근거다. | 앱 파일 1개와 시험 파일 1개 |
| G2 | tick 에 SIGTERM 처리를 넣는다. 예외로 바꿔 `subprocess.run` 이 자식을 죽이게 하고, «stopped» 로그 줄을 남긴다. | 혼자서는 못 닫는다. tick 이 SIGKILL 을 받거나 처리 전에 죽으면 손자가 남고, `_pass_child` 의 자식까지는 닿지 않는다. | tick.py 변경, R-H 회귀 9파일 재실행, 82a5b73 위에 덧댐 |
| G1+G2 | 둘 다 | 닫는다. 추가로 정지 시 로그 줄이 남는다. | G2 비용 전부 |

- G1 을 고른다. G2 가 더하는 것은 «정지됨» 로그 줄 하나뿐이다. 앱은 정지 상태를 자기 메뉴에 이미 표시한다. 그래서 tick 을 건드릴 이유가 부족하다. G2 는 오빠가 로그 줄을 원하실 때 새 카드로 연다.
- 그룹 전체 종료는 옛 launchd 안의 기본 동작과 같다(M9). 패스 자식이 SIGTERM·SIGKILL 을 받아도 상태 파일이 반쯤 남지 않는다(M8).

### 4-2. 제어기 상태 (PassController)

상태에 `draining`(그룹 정리 중) 하나를 더한다. `pid` 는 그룹 번호(pgid)로 쓴다. M1 에 따라 그룹 번호는 tick pid 와 같다.

```text
stopped ──start──▶ running ──tick 종료──▶ draining ──그룹 빔──▶ waiting(5분) ──▶ running
   ▲                  │                       │
   │                  └──stop: SIGTERM(그룹)──▶│ stopping: 유예 10초 뒤 SIGKILL(그룹)
   └──────────────── 그룹 빔 (stop 이 요청된 경우) ◀┘
```

1. tick(그룹장) 이 끝나면 곧바로 `groupAlive` 를 본다.
   - 비었으면 지금처럼 끝 처리를 한다.
   - 남았으면 그룹장이 없는 고아 손자다. 바로 그룹에 SIGTERM 을 보내고, 유예 뒤 SIGKILL 을 보낸다.
2. `draining` 동안 0.2초마다 `groupAlive` 를 본다. 비면 끝 처리를 한다.
3. 정지 요청이면 그룹에 SIGTERM 을 보내고, `killGrace`(10초) 뒤 그룹에 SIGKILL 을 보낸다. 강제 종료 예약은 tick 이 끝나도 취소하지 않는다. 그룹이 빌 때만 취소한다. 지금 코드의 `passFinished` 가 그룹장 종료만으로 예약을 지우는 것이 R2 의 직접 원인이다.
4. 시작 버튼은 `state == .stopped` 이고 그룹이 빈 뒤에만 켠다. 앞 패스 정리 전 재시작이 생길 수 없다.
5. SIGKILL 뒤 5초가 지나도 그룹이 남으면(커널 대기 상태 등) `cleanupFailed` 로 표시한다. 아이콘은 빨강, 문구는 «앞 패스 정리 실패, 앱을 다시 여세요» 이고, 시작은 꺼 둔다. 0.2초 확인은 계속한다. 그룹이 비면 정상으로 돌아온다.
6. 앱 종료(`applicationShouldTerminate`) 는 그룹이 빌 때까지 `.terminateLater` 로 기다린다. 지금은 pid 하나만 본다.

### 4-3. 그룹을 벗어나는 손자

`setsid` 나 `setpgid` 로 그룹을 바꾸는 손자는 이 방식으로 잡히지 않는다. tick 과 `_pass_child` 는 그런 호출을 하지 않는다(`start_new_session`, `process_group` 사용 0). op 가 캐시용 상주 프로세스를 따로 띄우는지는 확인하지 않았다 [확인 필요]. §7 h 단계에 «패스 끝난 뒤 op 프로세스 0개» 확인 줄을 넣는다. 남으면 동결 집합 밖의 새 카드다.

## 5. R3·R4: `--once` 의 전체 마감 1개와 공통 경로 검사

### 5-1. `main` 순서

```text
main
 ├─ 1. settings = loadSettings()
 ├─ 2. path = checkAppPath(Bundle.main.bundlePath, home)      ← 모드를 나누기 전 (R4)
 ├─ 3. --once 이면 → runOnce(settings, path, start: 기동 시각)
 └─ 4. 아니면 → AppDelegate(settings, path)  (메뉴 경고는 지금과 같음, 패스는 계속 돈다)
```

### 5-2. `runOnce` 판단표 (순수 함수 `onceAction(now, start, path, leaderExited, groupAlive, phase)`)

| 조건 | 동작 | 종료 코드 | `app.once.log` result |
|---|---|---|---|
| path ≠ ok | tick 을 띄우지 않는다 | 78 | `wrong_location` 또는 `translocated` |
| spawn 실패 | — | 69 | `launch_failed` |
| 그룹장 종료 + 그룹 빔 | — | tick 종료 코드 | `tick_exit` |
| 그룹장 종료 + 그룹 남음 | 바로 그룹 SIGTERM, 아래 마감 그대로 | 아래 결과 | 아래 결과 |
| 기동 +45초 | 그룹 SIGTERM | — | — |
| 기동 +52초 | 그룹 SIGKILL | — | — |
| 기동 +57초까지 그룹 빔 | — | 124 | `deadline` |
| 기동 +57초에 그룹 남음 | 포기하고 끝 | 125 | `deadline_dirty` |

- 마감 셋은 모두 «기동 시각 + 상수» 의 절대 시각이다. 대기는 매번 `마감 − 지금` 으로 계산한다. 상대 대기를 이어 붙이는 코드가 없어진다. 판정서 R3 의 65+5+5 구조가 여기서 사라진다.
- 최대 앱 내부 시간은 57초다. `open -W` 기동 비용을 더해도 70초 상한 안에 13초 여유가 있다.
- 45초 근거: op 구간 최대 21초(M7)에 패스 시간 24초 이상이 남는다. 정상 패스 시간은 [확인 필요: 운영 로그 10-13~10-18 에 ok 줄이 없어 실측값 없음]. 45초 안에 끝나지 않으면 h 판정은 «판정 불가» 다(설계 §5 판정표 그대로).
- 창 없는 모드의 실패·경고 방식:
  - stderr 에 고정 단어 1줄을 쓴다(`AIRAG once: wrong_location` 등).
  - `<logDir>/app.once.log` 에 값 없는 JSON 1줄을 덮어쓴다: `{"ts","result","code","elapsed_s"}`. 권한 0600, `O_NOFOLLOW` 다.
  - h 스크립트는 `open -W` 의 종료 코드를 믿지 않고 이 파일을 읽는다. `open -W` 가 앱 종료 코드를 전하는지는 [확인 필요] 다.
- `--once` 는 잘못된 위치에서 거부한다. 메뉴 모드는 경고만 하고 계속 돈다. 이유는 둘이다. `--once` 는 시험과 점검에만 쓰인다. 다른 사본에서 돈 결과는 허용 귀속을 엉뚱한 사본에 남겨 시험을 오염시킨다.

## 6. 신호 연결부를 시험이 잡게 하는 법

앱은 띄우지 않는다. 자식은 `/bin/sh` 와 `sleep` 뿐이다. 시험 실행 파일이 자기 자신을 다시 부르는 경로는 0 이다(10-28 forkbomb 교훈). 시험 하나의 실제 대기는 3초 이하다. 시험 실행은 지금처럼 `timeout 70` 아래에서 한다.

| 시험 | 가짜 tick | 단언 | 죽이는 변이 |
|---|---|---|---|
| T-pg | `sh -c 'sleep 30'` | 띄운 직후 `getpgid(pid) == pid` | Foundation 동작 변화(M1) |
| T-stop | `sh -c 'sleep 30 & sleep 30'` | 정지 뒤 3초 안에 `groupAlive == false`, 시작은 그 뒤에만 켜짐 | 신호 함수 빈 함수, `kill(-pgid)` 대신 `kill(pid)` |
| T-kill | `sh -c 'trap "" TERM; sleep 30 & sleep 30'` (killGrace 0.5초로 줄임) | SIGKILL 단계 뒤 그룹 빔 | SIGKILL 단계 삭제, 강제 종료 예약을 그룹장 종료 때 취소 |
| T-orphan | `sh -c 'sleep 30 & exit 0'` | 그룹장 종료 뒤 `draining` 을 거쳐 그룹이 빈 다음에만 `waiting` | 그룹장 종료만으로 끝 처리(지금 코드) |
| T-once | `sh -c 'trap "" TERM; sleep 30'` + 마감 축소판(4.5초, 5.2초, 5.7초) | 6초 안에 종료, result `deadline`, 그룹 빔 | 상대 대기 연결(R3), SIGKILL 삭제 |
| T-path | 순수 `onceAction` | path ≠ ok 이면 spawn 호출 0, 코드 78 | 경로 검사를 모드 분기 뒤로 옮김(R4) |

- 제어기는 실제 `LiveProcessOps` 와 주입 시계로 만든다. 시험은 예약 큐를 손으로 돌리고, 그 사이 실제 시간 50ms 씩 기다린다. 고정 sleep 반복은 쓰지 않는다. 조건이 맞으면 바로 빠져나오는 상한 3초 대기만 쓴다.
- 각 시험은 끝에 자기 그룹에 SIGKILL 을 보내 남는 `sleep` 이 0 이 되게 한다.
- 남는 공백: 2구역의 `makeLiveController(...)` 한 줄 호출은 시험이 컴파일하지 않는다. «알려진 한계» 1줄로 둔다. 연결부의 실제 동작은 모두 1구역에 있어 변이 대상이 시험 안에 들어온다.

## 7. 구현 카드 (Nano 몫)

| 순서 | 카드 | 파일 | 닫는 반례 | 시험 |
|---|---|---|---|---|
| 1 | N1 그룹 수명 | `macos/AIRAG/AIRAG.swift`, `macos/AIRAGTests/main.swift` | R2 (+판정서 변이 공백) | T-pg, T-stop, T-kill, T-orphan + 기존 73개 |
| 2 | N2 `--once` 마감·공통 경로 | 같은 두 파일 (N1 위에서) | R3, R4 | T-once, T-path |
| 1′ | N3 서명 키 보관·해제 (§10 안 1D 기준) | `macos/build.sh`, 새 `macos/tests/build_sign_test.sh` | R1 | 아래 목록 + §10-6 |

- N1 → N2 는 같은 파일이라 한 Nano 가 차례로 한다. N3 은 다른 Nano 가 동시에 한다.
- N3 시험은 `PATH` 앞에 `security`, `codesign`, `openssl` 가짜를 두고 `HOME` 을 임시 폴더로 바꿔서 돈다. 실제 키체인 쓰기는 0이다. 단언은 아래 다섯이다.
  1. 가짜들이 기록한 모든 명령 인자에 비밀번호 문자열이 0회 나온다.
  2. 순서는 해제 다음 codesign 이다.
  3. 해제 rc ≠ 0 이면 codesign 호출이 0회다.
  4. `make-identity` 가 중간에 실패하면 키체인과 비밀번호 파일이 모두 남지 않는다.
  5. stdout·stderr 에 비밀번호가 0회 나온다.
- 변이 확인(N3): 해제 단계 삭제, `-p` 를 인자로 되돌림, 실패 뒤 codesign 진행. 셋 다 시험이 죽어야 한다.
- 회차 시간: N1+N2 시험 합계 20초 이하가 목표다. 한 회차 7분 상한 안에 든다.
- tick.py 와 R-H(82a5b73)는 건드리지 않는다. R-H 회귀 재실행은 필요 없다.
- h 단계 보강(앞 설계 카드 5의 h-A 계획 파일에 더함, 실행은 master 의 `ft-hil.sh --add` 한 줄):
  1. `security lock-keychain <airag 키체인>` 으로 잠근 뒤 다시 빌드한다. 기대: 창 0, 서명 성공, `codesign -d -r-` 지정 요건이 잠그기 전과 같다. 재부팅 없이 R1 을 확인하는 단계다.
  2. `--once` 가 끝난 뒤 `ps -axo pid,pgid,comm` 에서 op 프로세스 0개, `app.once.log` 의 result 1줄을 확인한다.

## 8. 동결 반례 대조와 DA 2회차 질문

| 반례 | 이 설계에서 닫는 위치 | 2회차에 볼 증거 |
|---|---|---|
| R1 | §10 (안 1D) | N3 시험 §10-6 단언 + 변이 사망. h-S1 인증서 만들기, h 단계 1의 잠금 뒤 재서명 (오빠 1줄씩) |
| R2 | §2, §4-2 | T-stop·T-kill·T-orphan 통과. 판정서의 «`kill` 빈 함수» 변이 사망 |
| R3 | §5-2 | T-once 6초 안 종료. 코드에 상대 대기 연결 0 |
| R4 | §5-1 | T-path. `main` 에서 경로 검사가 모드 분기보다 앞 |

DA 2회차 질문 (R1~R4 안에서만):

1. R1: `security -i` 표준 입력 경로가 비밀번호를 명령 인자, stdout, stderr 어디에도 남기지 않는가. 해제 실패 뒤 codesign 으로 가는 경로가 0 인가.
2. R1: `make-identity` 가 중간에 실패할 때 반쪽 상태(키체인만 있음, 비밀번호 파일만 있음)를 남기는 경로가 있는가.
3. R2: 그룹장 종료, 정지 요청, 강제 종료 예약의 순서를 어떻게 섞어도 그룹이 비기 전에 시작이 켜지거나 다음 패스가 예약되는 경로가 있는가.
4. R2: 신호 연결부, 그룹 확인, pgid 확인 중 하나를 바꿔도 시험이 통과하는 변이가 남는가.
5. R3: `--once` 의 어떤 경로든 기동 뒤 57초를 넘겨 머무는가. 상대 대기가 남았는가.
6. R4: `--once` 가 잘못된 위치에서 tick 을 띄우는 경로가 남았는가.

## 9. 알려진 한계 (반례 아님)

- O1: `app.json` 의 `python` 재지정은 허용 목록이 없다. 같은 사용자의 설정 변경이라 거부 기준으로 삼지 않는다(판정서 범위 밖 1).
- 2구역의 `makeLiveController(...)` 호출 한 줄은 시험이 컴파일하지 않는다(§6).
- 그룹을 스스로 벗어나는 손자(`setsid`)는 잡지 못한다. op 의 상주 프로세스 여부는 h 단계 2에서 확인한다(§4-3).
- M1(Foundation 의 새 그룹 생성)은 문서화된 계약이 아니라 실측이다. T-pg 와 spawn 직후 확인이 바뀐 동작을 잡는다.

## 10. §3 보정: 안 1D (1Password develop 볼트 보관 · 발주 #3517)

오빠 결정 원문: «op developer». 키체인 비밀번호를 1Password `develop` 볼트에 둔다. 평문 파일은 0개다(하드 룰 15: develop 볼트, 토큰 `OP_SERVICE_ACCOUNT_TOKEN_DEVELOP`, kskill 토큰 금지). R2~R4 는 바뀌지 않는다. 이 절도 설계만 담았고 op 실행은 0회다.

### 10-1. 비밀번호는 op 가 만든다 (값이 build.sh 를 거쳐 들어가지 않는다)

- `make-identity` 는 비밀번호를 스스로 만들지 않는다. `op item create --vault develop --category password --generate-password=32,letters,digits` 로 1Password 가 만들게 한다. 그러면 값을 명령 인자나 템플릿 파일로 넘길 일이 없다.
- 항목 규칙(값 아님, 출력 가능):
  - 제목: `airag-sign-keychain-<LocalHostName>`. 키체인은 이 맥 전용이라 맥 이름을 붙인다.
  - 태그: `airag`.
  - 필드: 기본 `password` 1개.
- 항목 ID 는 비밀이 아니다. `~/.config/airag/sign/op-item-id` (일반 파일, 0600, 심링크 거부)에 적는다. 이후 읽기는 제목이 아니라 ID 로 한다: `op://develop/<ID>/password`. 제목이 겹치거나 바뀌어도 흔들리지 않는다.
- `op item create` 의 표준 출력에는 값이 들어 있다. 그래서 `--format json` 출력을 변수에 담지 않고 `python3 -I -c` 로 바로 넘겨 `id` 만 꺼낸다. 값은 파이프 안에만 머문다.

### 10-2. make-identity 순서 (볼트 저장 = 마지막 직전 · 반쪽 상태 0)

| 단계 | 동작 | 실패하면 |
|---|---|---|
| 1 | 상태 판정 (아래 표). `timeout`·`op`·`openssl`·`python3` 존재와 토큰 비어 있지 않음을 확인한다. 값은 보지 않고 길이만 본다. | 고정 rc, 아무것도 만들지 않음 |
| 2 | `op whoami` 로 사전 점검(7초 룰 포장) | rc 31/34, 아무것도 만들지 않음 |
| 3 | openssl 로 키·인증서·p12 를 mktemp 폴더(0700)에 만든다. p12 암호는 위의 볼트 비밀번호가 아니라 1회용이다. 이 폴더는 trap 으로 지운다. | 폴더만 지움, 볼트·키체인 0 |
| 4 | **볼트 저장** (`op item create`, 10-1) → ID 파일 확정 → 곧바로 `op read` 로 되읽어 형식 `^[A-Za-z0-9]{32}$` 확인 | 저장 실패 = rc 33, 키체인 0. 되읽기 실패 = rc 34, 키체인 0 (ID 파일은 남겨 «이어서» 로 감) |
| 5 | 키체인 생성·해제·import·partition-list. 비밀번호는 전부 `security -i` 표준 입력으로만 넘긴다. | 이 실행이 만든 키체인 파일만 지운다(같은 실행의 롤백). ID 파일과 볼트 항목은 남긴다. rc 35 |

상태 판정 (단계 1):

| 키체인 파일 | ID 파일 | make-identity |
|---|---|---|
| 없음 | 없음 | 단계 2~5 전부 |
| 없음 | 있음 | «이어서»: 단계 4 의 생성은 건너뛰고, 같은 ID 로 되읽은 뒤 단계 3·5 만 한다. 볼트 항목이 2개가 되지 않는다. |
| 있음 | 있음 | 거부: `identity_exists` (rc 36) |
| 있음 | 없음 | 거부: `identity_state_invalid` (rc 36). 옛 1A·4be48d7d 상태다. M6 에 따라 지금은 0 이다. |

- 볼트 항목은 롤백하지 않는다. 볼트 쪽 삭제는 오빠 데이터 삭제라서 HIL 이다. 대신 «이어서» 가 남은 항목을 다시 써서 고아 항목이 생기지 않게 한다.
- 단계 5 의 롤백은 같은 실행이 몇 초 전에 만든 우리 키체인 파일 1개만 대상이다. `security delete-keychain` 대신 검색 목록에서 빼고 그 파일만 지운다 [확인 필요: `create-keychain` 이 검색 목록에 추가하는지 Nano 가 man 원문으로 확인].

### 10-3. 서명 때 (sign_app)

1. ID 파일 검사: 일반 파일, 0600, 소유자 본인, 심링크 아님, 26자 영숫자.
2. `op read "op://develop/$ID/password"` 를 7초 룰로 감싸 부른다(10-4). 출력은 `$(...)` 변수 1개에만 담는다. 형식이 `^[A-Za-z0-9]{32}$` 가 아니면 rc 34 다.
3. `printf 'unlock-keychain -p %s %s\n' "$pw" "$KC" | security -i >/dev/null 2>&1`. `printf` 는 bash 내장이라 명령 인자 목록(ps)에 값이 나오지 않는다(M4). rc 는 M5 로 판정한다.
4. 해제 rc ≠ 0 이면 rc 35 로 끝낸다. codesign 호출은 0 이다.
5. `unset pw` 한 뒤 codesign 을 부른다(지금과 같은 `--keychain`).

### 10-4. op 호출 포장 (F9 · 하드 룰 12 · TCC 창)

모든 op 호출(`whoami`, `item create`, `read`)은 함수 `op_call` 하나로만 간다.

- 시간: 시도 1회 `timeout 10.5`, 출력 없이 시간 초과일 때만 1회 재시도, 합계 21초 이하. tick 의 `OP_ATTEMPT_TIMEOUT_S`·`OP_CALL_DEADLINE_S` 와 같은 값이다. 시험용 축소는 환경변수 `AIRAG_OP_ATTEMPT_S` 로만 하고, 10.5 를 넘는 값은 무시한다.
- 환경: 아래 셋을 그 명령 앞의 셸 대입으로만 준다. `env VAR=값 op …` 처럼 쓰면 토큰이 `env` 의 명령 인자에 나오므로 쓰지 않는다(M4).
  - `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP"`
  - `HOME=~/.config/airag/op-home`: R-H 폴더다. 0700, 소유자 본인, 심링크 아님이어야 하고, 없으면 0700 으로 만든다.
  - `OP_CACHE=false` [확인 필요: op 2.32.1 의 변수 이름]
- TCC 창: R-H 터미널 시험 T1 에서 op-home 아래 op 는 AppData 요청 0, PROMPTING 0 이었다. 실행 위치도 Ghostty(허용됨) 아래 `!` 한 줄이다. 그래서 창이 뜰 가능성은 낮다. 그래도 뜨면 h 판정은 «실패» 다. R-H 가 이 경로에서 깨졌다는 뜻이고, 새 카드로 연다.
- F9: 앞 설계에서 `op --version` 이 120초 멈췄다. 원인은 확인하지 못했다 [확인 필요]. 이 포장의 timeout 이 멈춤을 21초 안에 끊는다.
- 앱 쪽 확인: AIRAG.app 은 서명용 op 를 부르지 않는다. 현재 `AIRAG.swift` 에서 op 가 나오는 곳은 주석 2줄뿐이다(:3, :260). tick 의 소비자 키 `op read` 는 원래 있던 경로이고, 이 비밀번호와 관계가 없다. 서명 비밀번호를 읽는 곳은 build.sh 하나다.

### 10-5. 고정 실패 문구와 rc

출력 형식은 `build.sh: <code>` 1줄과, op 가 원인이면 다음 줄에 `op command: <값 없는 명령 모양>`, `op error: <원문>` 이다(하드 룰 15 의 «명령·오류 원문 보고»). 원문에 비밀번호나 토큰 문자열이 들어 있으면 그 줄을 `op error: [값 포함, 원문 비공개]` 로 바꾼다.

| rc | code | 언제 | codesign |
|---|---|---|---|
| 31 | `op_unavailable` | op 또는 timeout 이 없음 / 시간 초과 2회 | 0 |
| 32 | `op_token_missing` | `OP_SERVICE_ACCOUNT_TOKEN_DEVELOP` 이 비었음 (op 호출 0) | 0 |
| 33 | `op_store_failed` | `item create` 실패 (권한 없음, 볼트 없음, 네트워크) | — |
| 34 | `op_read_failed` | `read`·`whoami` 실패, 빈 값, 형식 불일치 | 0 |
| 35 | `keychain_unlock_failed` | `security -i` 해제 rc ≠ 0, 또는 단계 5 실패 | 0 |
| 36 | `identity_exists` / `identity_state_invalid` | 10-2 상태 표의 거부 두 줄 | 0 |

### 10-6. N3 시험 (가짜 `op`·`security`·`codesign`·`openssl` 을 PATH 앞에 둠 · HOME 은 임시 폴더)

- 가짜 `op` 는 `item create` 때 알려진 32자 값을 만들어 JSON 으로 내보낸다. `read` 때는 같은 값을 돌려준다. 받은 명령 인자는 기록하고, 값은 기록하지 않는다. 가짜 `security` 는 `-i` 표준 입력에서 «기대 값으로 해제가 왔는지» 만 예/아니오로 기록한다.

| # | 단언 |
|---|---|
| A1 | 실행 뒤 비밀번호가 0회 나온다: 모든 가짜의 인자 기록, build.sh 의 stdout·stderr, 임시 HOME·빌드 폴더·TMPDIR 의 모든 파일 |
| A2 | 토큰 문자열도 A1 의 모든 곳에 0회 나온다. 대입으로 넘겨 인자 기록에 없어야 한다. |
| A3 | `item create` 가 실패하면(가짜 rc 1) `security create-keychain` 호출 0, 키체인 파일 0, ID 파일 0, rc 33 |
| A4 | `read` 가 실패하거나 시간 초과면(`AIRAG_OP_ATTEMPT_S=0.3`) codesign 호출 0, rc 34. 시간 초과는 재시도 1회 뒤 끝난다. |
| A5 | 호출 순서: `whoami` → openssl → `item create` → `read` → `security create-keychain`. 볼트 저장이 키체인 생성 바로 앞이다. |
| A6 | 단계 5 실패 → 키체인 파일 0, ID 파일 남음, rc 35. 다시 부르면 «이어서»로 `item create` 호출 0, 키체인 생성 성공 |
| A7 | 토큰이 비면 op 호출 0, rc 32 |
| A8 | 해제 rc ≠ 0 이면 codesign 0, rc 35 (1A 의 단언 3 유지) |

변이 확인(셋 다 시험이 죽어야 한다): `printf | security -i` 를 `security unlock-keychain -p` 로 바꿈 → A1, 볼트 저장을 키체인 생성 뒤로 옮김 → A3·A5, `op_call` 의 timeout 제거 → A4.

시험 1개 대기는 가짜라 1초 이하다. 실제 op 와 키체인은 0이다.

### 10-7. 오빠 손 (h-S1 · 인증서 만들기 1번)

실행은 master 의 `ft-hil.sh --add` 가 준 `! bash /tmp/h<N>` 한 줄이다. 내용은 `build.sh make-identity` 후 `security find-identity -v -p codesigning <airag 키체인>` 의 «개수» 만 출력하는 것이다.

| 결과 | 판정 | 다음 |
|---|---|---|
| rc 0, 신원 1개, 창 0 | 통과 | 빌드·설치 h 로 간다 |
| rc 33 + `op error` 가 권한 없음 | 막힘 | 서비스 계정에 develop 쓰기 권한이 없다는 뜻이다. master 가 아래 선택지로 오빠 인터뷰를 연다. |
| rc 31·34 (시간 초과, 네트워크) | 판정 불가 | 같은 h 를 1회만 다시 한다. 또 같으면 원문을 master 에 보낸다. |
| 1Password·키체인·TCC 창이 뜸 | 실패 | 오빠는 «허용 안 함» 을 누르신다. 새 카드로 연다(R-H 경로가 깨짐). |
| rc 35·36 | 실패 | 원문 1줄을 master 에 보낸다. 이어서 다시 실행하면 볼트 항목을 다시 쓴다. |

쓰기 권한이 없을 때(rc 33 권한) master 에 보낼 선택지:

1. 오빠가 1Password 관리 화면에서 그 서비스 계정에 develop 볼트 쓰기 권한을 준다. 추천이다. 결정이 그대로 지켜진다.
2. 오빠가 1Password 앱에서 항목 1개를 손으로 만들고(제목 규칙 10-1, 비밀번호 생성 32자) ID 를 알려 준다. build.sh 는 «이어서» 로 키체인만 만든다. 쓰기 권한이 필요 없다.
3. 1A(0600 파일)로 되돌린다. 오빠 결정을 바꾸는 일이라 오빠 답이 필요하다.

쓰기 권한 유무는 지금 확인할 수 없다. 확인하려면 op 를 실행해야 하는데, 이번 발주가 금한다 [확인 필요: h-S1 결과로 판정].
