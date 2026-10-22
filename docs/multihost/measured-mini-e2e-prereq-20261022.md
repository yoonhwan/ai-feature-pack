# mini(byz Mac mini) e2e 시험 이관 사전조건 — 읽기 전용 실측 (2026-10-22)

> 작성: `aifp-pi-master-pi#0` · 발주 #3116 · 접속은 **`ssh mini`** 만(사용자 이름·IP 미사용)
> 규칙: 원격 쓰기 0 · 앱 실행 0(Chrome 띄우지 않음 · 경로·버전만) · 비밀값 출력 0 · 상한 70초
> 맥 러너 정본 = `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/tests/e2e/realtime_multi_e2e.py` (읽기만)

## 요약 — 막힌 항목 4 / 준비된 4

| # | 항목 | 결과 | 한 줄 판정 |
|---|---|---|---|
| 1 | BYZ 리포 | ❌ **없음** | mini `~/Project` 에 `ai-feature-pack` 만 · `realtime_multi_e2e.py` 못 찾음 |
| 2 | Chrome | ⚠️ **부분** | 155.0.8059.85 설치·실행 중(29 프로세스)이나 **CDP 9333·9222 리스너 0** |
| 3 | BlackHole·출력장치 | ✅ **있음(값 확인 불가)** | `BlackHole2ch.driver` 존재 + 장치 목록에 `BlackHole 2ch`·`Multi-Output Device` · **현재 선택값은 못 봄**(SwitchAudioSource 없음) |
| 4 | 런타임 | ⚠️ **부분** | python 3.9.6 / pip pytest·requests·playwright ✓ · **websockets 없음** · node 25.8.1·uv 0.11.0·brew 7.0.10 ✓ (`bash -lc` 에서만 PATH) |
| 5 | 자원 | ✅ | 디스크 59Gi 여유(69% 사용) · swap 319MB/2048MB · 메모리 free 22,810 pages(16KB=약 356MB free) — **e2e 1회엔 충분, 상주 좌석엔 빠듯** |
| 6 | 러너 서비스 주소 | ✅ **정본에서 추출** | env 8종 + CDP **9333**(9222 아님) · FE 3015 · gateway 8080 — 아래 표 |
| 7 | 마이크 권한 | ❓ **못 봄** | TCC.db 존재하나 읽기 불가 → **MIC_UNVERIFIED 유지(mini 터미널 앞 확인)** |
| 8 | 화면 상태 | ✅ | 콘솔 사용자 `byz` · `sleep 1 (sleep prevented by powerd)` · `displaysleep 0` → **화면 안 잠듦** |

---

## 1. BYZ 리포 — ❌ 없음

```
$ ssh mini 'ls -1 ~/Project'
ai-feature-pack
$ ssh mini 'find ~ -maxdepth 4 -name realtime_multi_e2e.py 2>/dev/null'
(출력 없음)
$ ssh mini "ls -d ~/Project/*/BYZ-Agents ~/Project/BYZ-Agents 2>/dev/null"
(출력 없음)
```
- 이 맥 정본: `/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents` · 진입점 `tests/e2e/realtime_multi_e2e.py`
- **러너를 돌리려면 mini 에 BYZ-Agents clone(또는 rsync)이 선행**돼야 한다. 이건 «원격 쓰기» 라 이번 범위 밖(오빠 승인 h 필요).
- 러너가 `.worktrees/v6-realtime-live` 를 cwd 로 쓰는 래퍼(`mr_preflight.sh:WT=…/.worktrees/v6-realtime-live`)도 있어 **워크트리까지 필요**하다.

## 2. Chrome — ⚠️ 설치·실행 중이나 CDP 없음

```
$ ssh mini '"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --version'
Google Chrome 155.0.8059.85
$ ssh mini "pgrep -f 'Google Chrome' | wc -l"            → 29
$ ssh mini "pgrep -af 'remote-debugging-port' | grep -c 'Google Chrome'" → 0
$ ssh mini 'lsof -nP -iTCP:9222 -sTCP:LISTEN | wc -l'    → 0
$ ssh mini 'lsof -nP -iTCP:9333 -sTCP:LISTEN | wc -l'    → 0        # ★러너가 쓰는 포트도 비어 있다★
```
- ★러너의 CDP 포트는 **9333**(`cdp_helper.py:21 CDP_PORT=int(os.environ.get("CDP_PORT","9333"))`)★ — 9222 가 아니다.
- 현재 떠 있는 Chrome 29 프로세스는 **디버깅 포트 없이** 뜬 상태 → 러너가 붙을 수 없다.
- README 하드룰: **headed Chrome 필수 · `--headless` 금지 · `--user-data-dir=/tmp/chrome-byz-debug` · Playwright context 금지**.
- 기동 명령(README §1.2 원문, **실행은 이관 승인 뒤**):
```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9333 --no-first-run --no-default-browser-check \
  --user-data-dir=/tmp/chrome-byz-debug \
  "http://localhost:8080/static/realtime.html?debug" \
  "http://localhost:8080/static/lecture.html?debug"
```

## 3. BlackHole·오디오 — ✅ 장치 있음, 현재 선택값은 ❓

```
$ ssh mini 'ls -d /Library/Audio/Plug-Ins/HAL/BlackHole*.driver'
/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver
$ ssh mini 'system_profiler SPAudioDataType | grep …'
TFG27Q14P2:      (모니터)
BlackHole 2ch:
Mac mini Speakers:
Multi-Output Device:
$ ssh mini 'command -v SwitchAudioSource'
(없음)
```
- **드라이버·장치·Multi-Output Device 까지 존재** ✓
- **현재 입력/출력 선택값은 못 봄** — `SwitchAudioSource` 미설치(brew 설치 = 원격 쓰기라 이번 범위 밖). 대안: `system_profiler SPAudioDataType` 의 «Default Output Device» 항목을 다음 회차에 파싱하거나, 사람이 System Settings 에서 확인.
- README 하드룰: Output·Input 둘 다 `BlackHole 2ch`(또는 Multi-Output) + Chrome 탭 🔒 mic **Allow** + 드롭다운 `BlackHole 2ch`.

## 4. 런타임 — ⚠️ `websockets` 없음

`bash -lc`(로그인 셸) 기준 — **비로그인 ssh 에서는 node·brew·uv 가 PATH 에 없다**(아래 주의).

| 항목 | 값 |
|---|---|
| python3 | 3.9.6 (`/usr/bin/python3`) · **맥(3.14.8)·OCI(3.10.12)와 다르다** |
| pip3 | 21.2.4 |
| node / npm | v25.8.1 / (`/opt/homebrew/bin`) |
| uv | 0.11.0 (Homebrew) |
| brew | 7.0.10 (`/opt/homebrew/bin/brew`) |
| git · tmux | `/usr/bin/git` · `/opt/homebrew/bin/tmux`(3.7) |
| fzf | **없음**(`bash -lc` PATH 기준 — tmuxc/tmm 설치 시 필요) |
| python 모듈 | pytest ✓ · requests ✓ · playwright ✓ · **websockets ❌** · aiohttp ❌ · selenium ❌ |

- 러너의 3rd-party import 실측: `websockets` · `jwt` · `tests`(리포 내부 패키지). → **mini 에 `websockets` 설치 필요**(pip, 사용자 영역).
- ★PATH 주의★ `ssh mini 'node --version'`(비로그인)은 `absent`, `ssh mini 'bash -lc "node --version"'` 은 `v25.8.1`. **자동화 스크립트는 `bash -lc` 로 감싸야** brew/node/uv 를 본다(오늘 실측).

## 5. 자원 — ✅ e2e 1회 가능 / 상주 좌석은 빠듯

```
$ ssh mini 'df -h ~ | tail -1'
/dev/disk2s5   228Gi   131Gi    59Gi    69%    2.1M  620M    0%   /System/Volumes/Data
$ ssh mini 'vm_stat | head -5'
Pages free: 22810.  (page size 16384 → free ≈ 356MB)
Pages active: 396183.  inactive: 358829.  speculative: 38017.
$ ssh mini 'sysctl -n vm.swapusage'
total = 2048.00M  used = 319.69M  free = 1728.31M  (encrypted)
```
- 디스크 59Gi 여유(러너 로그·스냅샷 감당 가능) · swap 사용 320MB(압박 낮음) · **free 페이지 ~356MB(작음)** — Chrome 29 프로세스가 이미 떠 있는 상태라 e2e 1회는 되겠지만 «상주 좌석 + e2e 동시» 는 위험.

## 6. 러너가 붙는 서비스 주소 — ✅ 정본에서 추출(env 이름만)

`realtime_multi_e2e.py` / `cdp_helper.py` 에서 읽은 **환경변수·기본값**(값이 아니라 이름·기본 포트):

| env | 기본 | 쓰임 |
|---|---|---|
| `BYZ_WEB_PORT` | `3015` | dev web(FE) 포트 — `BYZ_WEB_BASE` 없을 때 `http://localhost:3015` |
| `BYZ_WEB_BASE` | (빈 값) | FE 절대 URL — 있으면 이것이 우선 |
| `BYZ_GATEWAY_PORT` | `8080` | gateway 포트 — `BYZ_GATEWAY_BASE` 없을 때 `http://localhost:8080` |
| `BYZ_GATEWAY_BASE` | (빈 값) | gateway 절대 URL(우선) |
| `CDP_PORT` | **`9333`** | Chrome CDP 포트 |
| `BYZ_WORKER_LOG` | `/tmp/byz-worker.log` | 워커 로그 경로 |
| `BYZ_E2E_ROOM_ID` | (빈 값) | 룸 고정 |
| `BYZ_E2E_JWT_SECRET` | (빈 값) | 인증(★비밀 — 값은 이 문서에 없다) |
| `BYZ_BTS_DOM_JSONL` · `BYZ_CAPTURE_BROWSER_CONSOLE` · `BYZ_BTS_PRESERVE_WINDOWS` | 선택 | BTS 산출·콘솔 캡처 옵션 |

- 또 하나의 함정(README/`mr_preflight.sh` 주석): **러너 기본 `WEB_PORT=3015` 는 nextjs-redesign 잔재**이고 실제 web 은 `:3001` 인 경우가 있다 → `BYZ_WEB_PORT` 를 **명시**해야 home 클릭 무한 MISS 를 피한다.

**mini 에서 그 주소에 닿는 방법 후보 2**
1. **이 맥 tailnet 주소로 직접**(권고): 미니가 이 맥의 FE(3001/3015)·gateway(8080)를 tailnet 으로 호출 —
   `BYZ_WEB_BASE=http://100.92.216.120:<FE포트>` · `BYZ_GATEWAY_BASE=http://100.92.216.120:8080`.
   전제: 이 맥의 해당 포트가 **127.0.0.1 바인드면 안 되고** tailnet 인터페이스에서도 들어와야 한다(현재 바인드 확인 필요 — 다음 회차 실측). 브라우저는 mini 것이므로 **Chrome 만 mini, 서버는 이 맥** 조합이 된다.
2. **mini 로컬 기동**: mini 에서 FE+gateway+worker 를 직접 띄우고 `localhost:3015/8080` 사용.
   전제: BYZ-Agents clone + node 25 + 의존성 설치 + **메모리 여유(현재 free ~356MB)** — 이 맥의 대형 스택을 mini 에 올리는 것이라 자원이 빠듯하다.

## 7. 마이크 권한 — ❓ 못 봄(MIC_UNVERIFIED 유지)

- `~/Library/Application Support/com.apple.TCC/TCC.db` **존재**하나 TCC DB 는 SIP 로 보호돼 일반 읽기 불가. `tccutil` 은 발주 금지(쓰기 성격) → **읽기만으로 판정 불가**.
- 결론: **MIC_UNVERIFIED 유지** — mini 터미널 앞(사람)에서 `System Settings → Privacy → Microphone` 에 터미널/Chrome 이 켜져 있는지 확인해야 한다.

## 8. 화면 상태 — ✅ 잠기지 않음

```
$ ssh mini 'stat -f%Su /dev/console'
byz
$ ssh mini 'pmset -g | grep -E " sleep| displaysleep"'
 sleep                1 (sleep prevented by powerd)
 displaysleep         0
```
- 콘솔 로그인 사용자 = `byz` ✓(headed Chrome 을 띄울 수 있는 세션) · `displaysleep 0` → **화면 안 꺼짐** · 시스템 sleep 은 `powerd` 가 막고 있음.

---

## 이관을 위해 «남은 선행» (전부 원격 쓰기 → 오빠 승인 h 필요)

1. BYZ-Agents clone(+`v6-realtime-live` 워크트리) — mini 디스크 59Gi 여유로 가능
2. python `websockets` 설치(사용자 영역) · 필요 시 `SwitchAudioSource`(brew) — 후자는 «선택값 실측» 용
3. Chrome 을 `--remote-debugging-port=9333` + 전용 user-data-dir 로 재기동(현재 29 프로세스 정리 필요 → **사람 손/승인**)
4. 오디오 출력·입력 = `BlackHole 2ch`(또는 Multi-Output) + Chrome 탭 mic Allow — **사람 손**
5. 마이크 TCC 권한 확인 — **사람 손**
6. 서버를 어디에 둘지 결정(위 후보 1 vs 2) — **오빠 결정**

## 이 문서가 하지 않은 것

- 원격 쓰기 0(파일 생성·설치·설정 변경 없음) · 앱 실행 0(Chrome 미기동) · `tccutil` 0 · 비밀값 출력 0(`BYZ_E2E_JWT_SECRET` 은 «이름» 만 적었다)
- 접속은 `ssh mini` 만 · 사용자 이름·IP 하드코딩 0
