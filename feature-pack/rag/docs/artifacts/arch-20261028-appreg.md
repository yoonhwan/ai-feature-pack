최신 fable-team 하네스를 이식하고 기존 AIRAG 증거를 재대조한 뒤, Claude Opus 5.5 HELM·Sonnet 5.5 Master/Nano·GPT-6.1 Sol DA 완성 루프로 AIRAG를 운영 가능한 상태까지 닫는다.
A03 닫는 증거: 「Sonnet 5.5 Nano 구현·GPT-6.1 Sol DA 루프」 — C12(consumer 상시 서비스 회복) · C13(KakaoBot 통합 보고서 published 칸).
골의 어느 축인가: A03 — C12. «launchd 아래 op read 권한 창» 막힘을 푸는 재설계 1장(발주 #3385 · aifp-airag-master-claude#9).

(architect aifp-airag-arch-claude#2 · Opus 5.5 · 2026-10-28 · 기준 HEAD c11f9dc · macOS 15.0.1 · op 2.32.1 · 구현·운영 변경·push 0)

# consumer 를 «상주 프로세스 1개»로 — 권한 창 0회

## 0. 결론
1. **추천 = 안 A «상주 1개 + R-H»**. 5분마다 새로 뜨는 틱을 없앤다. KakaoBot 처럼 상주 프로세스 1개가 기동 때 키를 1회 읽고, 300초마다 패스를 돈다. op 자식은 격리 HOME(R-H)으로 1Password 폴더를 아예 열지 않는다.
2. **권한 창 = 0회 · 오빠 클릭 = 0 · 오빠 터미널 명령 = 0.** «폴더 권한 1회»조차 필요 없다. 창은 op 가 보호 폴더를 열 때만 뜨는데, A 는 그 열기 자체를 없앤다.
3. **오빠 방향의 해석(1줄 확인 요청)**: macOS 에서 로그인 뒤 자동 기동하는 경로는 전부 launchd 가 띄운다(로그인 항목·SMAppService 포함). KakaoBot 도 launchd `KeepAlive` 상주다(§1 F1). 그래서 «launchd 데몬 폐기»를 «5분 틱 폐기 → KakaoBot 꼴 상주 1개»로 읽었다.
4. **R-H 커밋 82a5b73 = 채택**(조건 3개 · §5). 안 A 의 핵심 부품이다.
5. **앱 번들 + 허용 1회(안 B)는 폴백 2순위로 둔다.** 허용이 다음 기동까지 이어지는지는 클릭 1회 없이 검증할 수 없다. 계약(클릭 시험 금지)상 사전 판정이 불가능하다.

## 1. 사실 (이번 조사 · 읽기만)
| # | 관측 | 근거 |
|---|---|---|
| F1 | KakaoBot = launchd `RunAtLoad`+`KeepAlive`+`ThrottleInterval 30` 상주. wrapper 가 기동 때 `op read` 로 키를 1회 읽어 stdin 으로 넘김. 실패하면 프로세스 안에서 지수 backoff 뒤 종료 | `KakaoBot/deploy/launchd/local.kakaoroombot.supervisor.plist` · `krb-launchd-wrapper.sh` |
| F2 | KakaoBot 서비스는 지금 적재 안 됨(`Could not find service`) | `launchctl print`(읽기) |
| F3 | consumer 는 지금도 미적재 · plist = `StartInterval 300`+`RunAtLoad` · 환경 PATH 만 | `launchctl print` · plist 읽기 |
| F4 | tick.py = «한 번 호출 = 한 패스, 루프·sleep 없음» · 패스마다 op 를 3회 부름(키 3개 · 3병렬) | tick.py 첫 docstring · `load_keys` |
| F5 | 격리 폴더 `~/.config/airag/op-home` 존재(0700 · 10-18 R-H 시험 때 생성) | `ls -ld` |
| F6 | R-H 터미널 시험: T0 AppData 1·AllFiles 1 → T1(HOME 격리) AppData 0·AllFiles 0·PROMPTING 0·rc 0·격리 폴더 사용 1 | `oprh-20261018-104235.txt` |
| F7 | swap 4.1G/5.1G 사용(여유 0.99G) | `sysctl vm.swapusage` |
| F8 | `/usr/bin/sandbox-exec` 있음(폐기 예정 API 이나 15.0.1 에서 실행 파일 존재) | `ls -l` |
| F9 | **이번 좌석의 실수 1건**: `op --version` 을 1회 실행했다. 120초 안에 안 끝나 중단했다. 그 구간 TCC 로그에 op 요청·PROMPTING 0줄 | `log show --last 8m`(읽기) |

F9 의 뜻: 이 좌석에서 op 가 버전 출력도 못 하고 멈출 수 있다. 시험 스크립트는 반드시 `timeout 10.5` 로 감싼다(7초 룰 상한 그대로).

## 2. 안 비교 (3안)
| 안 | 방법 | 설계상 권한 창 | 오빠 클릭 | 터미널만으로 사전 판정 | 변경량 | 메모리 | 판단 |
|---|---|---|---|---|---|---|---|
| **A 상주 + R-H** | launchd `KeepAlive` 상주 1개(`airag-serve`) · 기동 때 키 1회 읽기(op 자식 HOME=op-home) · 300초 루프 | **0** — 보호 폴더 열기 0 | **0** | **가능**(§4 S0·S1) | serve 진입점 1개 + plist 1장 + 시험 · R-H 재사용 | 상주 python 1개(수십 MB 예상 · 실측 필요) · op 호출은 기동 때만(지금 하루 864회 → 기동 횟수) | **추천** |
| C 상주 + R-SDK | A 와 같은 상주 · 키 읽기만 `onepassword-sdk` in-process(op 바이너리 0) | **0** — op 자체가 없음 | **0** | 가능(op 프로세스 0 · AppData 요청 0 확인) | 키 로더 교체 + 의존성 1개 + 런타임 재설치(네트워크) | 네이티브 라이브러리 적재 · 기동 때만 | **폴백 1순위**(S1 실패 시) |
| B 앱 번들 + 허용 1회 | `AIRAG.app`(임시 서명 · 인증서 0개) 을 로그인 항목으로 · 책임 주체를 번들로 만들어 «허용» 1회 | **1회**(최초) · 이후 0 인지는 미확인 | **1** | **불가** — 허용이 이어지는지 보려면 클릭이 필요 | 번들·서명·등록 · 번들 안 실행 파일이 바뀌면 다시 묻을 수 있음(임시 서명 = cdhash 묶임 · 미확인) | 작음 | **폴백 2순위** · 오빠가 «앱 번들»을 꼭 원할 때만 |

공통: 어떤 안이든 5분 틱 plist(`com.airag.consumer`)는 다시 적재하지 않는다. 상주와 틱이 동시에 돌면 패스가 두 번 돈다(§6 K7).

## 3. 안 A 구조
```
launchd (RunAtLoad · KeepAlive · ThrottleInterval 30)
  └─ airag-serve (python 상주 1개)
       ├─ 기동 1회: load_keys() → op ×3 (자식 HOME=~/.config/airag/op-home) → 키는 이 프로세스 메모리에만
       ├─ 루프: 300초마다 _pass_child(키는 stdin) → 값 없는 로그 1줄
       └─ 실패: 키 오류·연속 패스 실패 N회 → 프로세스 안에서 backoff → 종료 → launchd 가 천천히 재기동
```
구현 메모(Nano 몫 · 이 문서는 지시만):
- tick.py 의 `load_keys`·`_pass_child`·로그 함수를 그대로 쓴다. 새 진입점 `serve` 1개가 «키 1회 + 루프»만 맡는다.
- 루프 간격 300초(지금 `StartInterval` 과 같음). 잠자기 뒤 깨어나면 바로 1패스.
- 실패 정책은 KakaoBot wrapper 꼴: 실패 횟수를 상태 파일(일반 파일)에 세고, 프로세스 안에서 `30초 × 2^(n-1)`(상한 있음) 쉰 뒤 종료. launchd `KeepAlive` 로 빠른 무한 재기동을 하지 않는다.
- 키 교체 대응: 패스가 키 오류 코드로 실패하면 프로세스를 끝낸다 → 재기동 때 새 키를 읽는다.
- 동시 실행 방지: tick.py 의 기존 `fcntl` 잠금을 serve 에도 건다.
- plist 는 새 라벨 1장(예: `com.airag.serve`) · 운영 적재는 «다음 승인 건».

## 4. «권한 창 0회 반복» 판정표 — 터미널 로그 전용 · 클릭 0 · 창 0 (사전 약속)
**왜 새 시험이 필요한가**: oprh T1 의 «AppData 0» 은 Ghostty 에 저장된 허용이 결과를 가렸을 수 있다(astra 지적). 그래서 TCC 와 무관한 탐지기로 «op 가 보호 폴더를 열려고 시도했는가» 자체를 센다.

**탐지기**: `sandbox-exec` 프로파일 = 기본 허용 + `~/Library/Group Containers`·`~/Library/Containers` 의 읽기·쓰기만 거부(거부는 커널 로그 `Sandbox: op(<pid>) deny(1) file-read…` 로 남음). 이 거부는 Ghostty 허용과 무관하다.

Nano 가 터미널(자기 좌석 Bash = Ghostty→tmux 자리)에서 직접 돌린다. 오빠 손 0. 각 호출은 `timeout 10.5` · 값은 «64자 hex 여부» 1비트만 남긴다.
- **S0 기준**: 탐지기 아래 `op read <키 1개>` · HOME = 실제 홈
- **S1 판정**: 탐지기 아래 같은 호출 · HOME = op-home
- 집계: 구간별 `log show --predicate 'sender=="Sandbox"'` 의 op deny 줄 수 · TCC op AppData/AllFiles 줄 수 · PROMPTING 줄 수 · rc · 형식 통과 · op-home 아래 `.config/op` 사용 1비트

| 결과 | 읽는 법 | 다음 |
|---|---|---|
| **S0 deny ≥1 · S1 deny 0 · S1 rc 0·형식 통과·격리 사용 1 · 모든 구간 PROMPTING 0** | 탐지기가 작동하고, R-H 아래 op 는 보호 폴더를 열려고 하지 않는다 → launchd 아래서도 요청이 없다 | **안 A 채택** → R-H 회귀 + serve 구현 → DA |
| S0 deny 0 | 탐지기가 이 시도를 못 본다(또는 op 가 TCC 검사에서 먼저 막힘) → 판정 불가 | **안 C 로**(launchd 확인 시험은 하지 않음) |
| S1 deny ≥1 | op 가 HOME 말고 다른 방법으로 홈을 찾는다 | **안 C 로** |
| S1 rc≠0 이고 S0 rc 0 | 격리 HOME 이 서비스 계정 읽기를 깨뜨림 | **안 C 로** |
| S0 rc≠0 | 거부 자체로 op 가 실패 — 판정엔 지장 없음(deny 줄 수만 씀) | S1 표대로 |
| 어느 구간이든 timeout | F9 와 같은 멈춤 — 네트워크·데몬 문제로 판정 불가 | 1회만 다시 · 또 멈추면 master 에 보고 |
| 어느 구간이든 PROMPTING ≥1 | 터미널 자리도 창 — 전제 깨짐 | 즉시 중단 · master 보고 |

**운영 합격선(다음 승인 건 · 사전 약속)**: 상주 적재 뒤 ①첫 패스 + 이어서 3패스 `status=ok` ②`launchctl kickstart -k` 재기동 1회 뒤 다시 1패스 ok ③그 전 구간 TCC 로그에 op AppData 요청 0·PROMPTING 0. ②가 «반복 0»의 증거다(새 프로세스에서도 창 0). PROMPTING 1줄이라도 나오면 즉시 bootout(HIL 도구) · 재시도 0.

## 5. R-H 커밋 82a5b73 처분 = 채택
이유: 비밀 사본 0 · plist 0 · 코드 37줄 · 터미널 시험 통과(F6) · 안 A·C 어느 쪽이든 키 읽기 경로에 해가 없다.
채택 조건(셋 다 충족 전엔 wip 그대로):
1. 기존 tick 회귀 green — `test_tick.py`·`_tick_component.py`·`test_tick_probe.py`·`test_tick_store_keys.py`·`test_tick_op_home.py`(+ 인계서의 «9 파일» 나머지 · [확인 필요: 9 파일 목록 정본]) · 시험 1개 70초·회차 7분 상한.
2. §4 S0·S1 이 «안 A 채택» 줄.
3. DA(GPT-6.1 Sol) APPROVE.
고칠 점 1개: 설계(10-18)는 «틱은 폴더를 만들지 않고 검사만»이었는데 구현은 없으면 만든다. 상주 방식에선 기동 때 1회 생성이라 그대로 두어도 된다 — DA 질문 Q3 으로 넘긴다.
wip 해제: 회귀 green 뒤 새 커밋으로 표시한다(이력 재작성 0).

## 6. 반례 집합 (동작 반례만)
| # | 반례 | 막는 장치 | 판정 근거 |
|---|---|---|---|
| K1 | 상주가 죽고 `KeepAlive` 재기동 → op 재호출 → 창 반복 | R-H(요청 0) + 프로세스 안 backoff | §4 합격선 ② |
| K2 | 로그인·재부팅 뒤 첫 기동(launchd 아래 첫 실행)에서 창 | R-H | §4 S1 + 합격선 ① |
| K3 | 1Password 쪽 키 교체 → 상주가 옛 키로 패스 계속 실패 | 키 오류 → 종료 → 재기동 때 재읽기 | 단위 시험(가짜 op 로 키 바꿈) |
| K4 | op 가 `getpwuid` 등으로 진짜 홈을 찾아 보호 폴더 접근 | — | §4 S1 deny ≥1 → 안 C |
| K5 | Homebrew 가 op 를 새 버전으로 바꿈 → 동작 변화로 창 재발 | 기동 로그에 op 버전 기록 · 버전이 바뀌면 S1 재시험 안내 1줄 | 시험(버전 기록 줄) |
| K6 | 패스는 계속 실패하는데 상주는 살아 있음 → 조용히 멈춘 서비스 | 연속 실패 N회 → 종료(backoff) · 로그 status | 단위 시험 |
| K7 | 옛 틱 plist 와 상주가 같이 적재 → 패스 이중 실행 | `fcntl` 잠금 · 설치 절차에서 옛 라벨 적재 0 확인 | 단위 시험(동시 2개 → 1개만 패스) |
| K8 | op-home 아래 op 캐시 데몬이 남아 메모리 차지(swap 여유 0.99G) | 키 읽기 뒤 op 자식 정리 확인 | 시험(키 읽기 뒤 op 프로세스 0) |

## 7. DA 에 넘길 질문
1. Q1: §4 탐지기(sandbox-exec 거부 로그)가 TCC AppData 검사보다 먼저, 또는 독립적으로 기록되는가? S0 가 0 일 때 «판정 불가»로 두는 사전 약속이 충분한가?
2. Q2: S1 deny 0 을 «launchd 아래 요청 0»으로 일반화해도 되는가? 반례가 있으면 그 경로를 적어 달라.
3. Q3: R-H 구현이 폴더를 «없으면 생성»하는 것이 상주 방식에서 안전한가(심링크 경쟁·권한 0700 검사 순서)?
4. Q4: 상주 프로세스가 키를 메모리에 오래 두는 것의 노출면 — `ps -E`·코어 덤프·자식 환경 전달 경로가 지금 틱보다 넓어지는가?
5. Q5: 안 A 가 실패해 안 C(SDK)로 갈 때, SDK 네이티브 코드가 Group Containers 를 여는지 같은 탐지기로 가를 수 있는가?

## 8. 오빠 손
- 클릭 0 · 권한 창 0 · 터미널 명령 0(S0·S1 은 Nano 가 자기 좌석에서 돌림).
- 승인 1건: 운영 적재(새 plist 적재·옛 라벨 정리)는 «다음 승인 건»으로 master 가 올린다.
- 확인 1줄: §0-3 해석(«launchd 폐기» = «5분 틱 폐기 → KakaoBot 꼴 상주 1개»)이 맞는가.

## 9. 하지 않은 것
op 실행 1회(F9 · 실수 · 중단) 외 op 실행 0 · launchctl 변경 0 · plist·runtime.json·설치본·DB 변경 0 · 값 출력 0 · push 0 · 서브에이전트 0. 쓴 파일 = 이 문서 1장.
