「너는 ai-feature-pack 전용 팀의 팀장이다. 팀 구성, 역할 분배, 작업 우선순위를 네가 알아서 판단하고 진행해라. 사용자에게는 되돌리기 어려운 결정이나 승인이 필요한 것만 물어봐라.」 (2026-10-20 aifp 팀장 발주 원문)
「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli  레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
골의 어느 축: 멀티 호스트 운용 기획 — 닫는 증거 = 이 문서 + DA 판정 + 오빠 결정 목록(§14) 커밋 sha.

# 멀티 호스트 설계 — tmuxc · tmm · fable-team (r8, 2026-10-21)

작성 근거: `00-BRIEF.md` + 조사표 4건(`scout-*.md`) + `hosts-facts.md` + `research-nano-1.md`(우편함 잠금 지도·sshd·tailscale) + `research-nano-2.md`(tmux/pgrep/ps/lsof 호출 전수 124+14건) + 소스 직접 확인. 코드·원격·설치 0. 표시: **[실측]** 확인함 / **[가정]** 설치 후 확인 필요.
r4 변경(하드 룰 14 — HOLD 2회 연속이라 재설계): r3 의 «원격이 허브 큐 행을 네트워크 너머로 임대·소비»를 버리고 **«소비는 언제나 로컬, 네트워크는 배달만»** 으로 바꿨다(§3). 원격 조작도 tmux 호출 단위가 아니라 **tmuxc 명령 단위**로 넘긴다(§7). 오빠 추가 요구 2건 반영: 두 맥의 브라우저·BlackHole·마이크 점검(발주 #2998 → §1·§9·§13 P0·P6) · OCI 에 headroom·cliproxy 를 claude 보다 먼저 + hermes 업데이트 경로(발주 #3009 → §8.1·§13 P5a). DA r3-1 H1~H6 대조표는 §15.
r5 변경(DA r4-1 — 구조 유지, «소유권 이전·회수 경계 완성»): 이전 선형화 = 옛 호스트 fence(§11) · 결과 모르는 것은 `hold/`(자동 재배달 0) · export 두 단계 확인(§12) · 장애 범위 = 프로세스 종료까지(§3.6) · 순서 = 큐 커밋 번호(§3.5, 벽시계 0) · K1/K2 동사표·PTY 거절 구분(§10) · 마이크 확정 회차(P6). 대조표 §15.
r6 변경(DA r5-1 — 프로세스 종료 범위·모름=사람 처분은 유지): **evict 때 미처리분 자동 이관을 뺐다** — 그 호스트 앞 미처리는 전부 `quarantine/`, 새 좌석은 빈 큐, 처분은 사람(§3.8·§11·D12). fence·재조정·export 2단계·`hold/`·`recovered/` 삭제, 대신 recv 세대 필터(§3.3). P1 포워딩 시험은 실제 연결 1회. 대조표 §15.
r7 변경(DA r6-1 — 구조 유지, 국소 4건): 로컬 `mailbox.jsonl` 범위 명시 + 세대 올릴 때 옛 행 격리(§3.1·§11-2) · route 수신 대상 상태 검사(§10.3 ⑤) · evict 진행 기록·재실행·완료 전 차단·원자 교체(§11-1) · 처분 계획의 재전송 mid 고정·늦은 성공 표시의 정본 갱신(§3.4·§11-3). 대조표 §15.
r8 변경(DA r7-1 — 최소 변경 3건): 격리는 «그 호스트 안»에서만 + JSONL 은 임시 파일 완성→원자 교체(§11-2) · 처분의 고정 단위 = 원본 mid 의 처분 기록(첫 부작용 전 기록 · 재계획도 같은 new_mid) · 처분 재실행 기한 = 처분 기록 생성 + 7일(밖이면 새 전송 0, 사람에게 반환) · 보관함 항목 = 디렉터리 1개(표식이 함께 움직임)(§11-3·§3.4). 대조표 §15.

## 0. 한 줄 결론과 원칙

- **결론**: «허브 1대 = 명부·라우팅·세대 차단의 단일 지점» + «각 호스트 = 자기 좌석 앞 우편함의 주인». 메시지는 **받는 좌석이 사는 호스트에 단 한 벌** 존재하고, 소비(recv)는 그 호스트 안에서 기존처럼 로컬로 일어난다. 네트워크를 건너는 것은 «배달(deliver)» 하나뿐이고, 배달은 «한 파일의 원자적 생성»이라 mid 중복 판정과 저장이 같은 동작이다.
- **스위치**: `.fable-team/hosts.json` 이 **없거나 `local` 한 줄뿐이면** 모든 코드 경로가 지금과 같다. 새 디렉터리(`inbound/`·`outbound/`)·새 필드(`host`·`gen`·`mid`)·새 잠금(`seats.lock`)은 멀티 모드에서만 생긴다. 단일 모드에서는 `mailbox.jsonl` 의 send/recv/peek 코드 경로와 출력이 바이트 동일.
- **7초 룰**: 배경 호출(route·deliver·probe)은 `ConnectTimeout=5` + 시도당 `timeout 7` + 재시도 1회. **화면 경로(tmm 스캔·preview)는 재시도 0 · 7초 불변**(하드 룰 12) — 실패는 `UNREACHABLE` 행, 다음 새로고침이 다음 시도. 크기를 아는 배치(git clone/fetch)만 `min(고정비+7×크기비,70초)`. **잠금 안에서는 네트워크 호출을 하지 않는다**(잠금 보유 시간 = 로컬 파일 작업뿐).
- **금지**: 임의 설치·원격 쓰기. 설치는 `/tmp/h<N>` 한 줄 스크립트로 오빠께 드린다. 헤드룸 프록시 주소(`ANTHROPIC_BASE_URL`)는 OCI 에서도 전역 export 금지(하드 룰 4 · 프로젝트 레벨 fail-open 래퍼만).

## 1. 호스트 모델 (①)

`.fable-team/hosts.json` (git 추적 안 함 · 허브에만 정본):

| 필드 | 뜻 |
|---|---|
| `name` | 짧은 이름(`book`·`mini`·`oci`) |
| `addr` | MagicDNS 이름 또는 100.x (비밀 아님) |
| `os` / `arch` | darwin·linux / arm64·aarch64 |
| `caps` | `browser` = Chrome 설치 + CDP 기동 가능(평소 9222 리스너 0 이 정상 — 러너가 띄운다) · `audio` = BlackHole 장치 ∧ SwitchAudioSource ∧ 마이크 권한 확인 **셋 다 참**일 때만 · `heavy` = 메모리 ≥16GB · `infer` = 그 호스트 로컬 headroom(8790)+cliproxy(8317) 건강 |
| `mem_gb` | 배치 판단용 |
| `root` | 그 호스트의 저장소 경로 |
| `state` | `active` · `draining`(새 좌석 금지) · `revoked`(그 호스트발 요청 거절) · `retired`(라우팅 제외, 기록 보존) — §11·§12 |

노드 3개 확정(r2 · `hosts-facts.md` §3b). `mac-mobile-test`(100.92.216.120)는 **이 맥 자신**이며 그 별칭은 어디에도 쓰지 않는다(`aifp-<name>` 별칭만).

| name | 정체 | addr | caps (실측 근거) | 상태 |
|---|---|---|---|---|
| `book` | 이 MacBook-Pro.local | 100.92.216.120 | browser·audio 후보 — Chrome 있음 · BlackHole 2/16/64ch 드라이버·장치 있음 · SwitchAudioSource 있음 · 9222 리스너 없음(정상) · 마이크 권한(TCC) 읽기 거부 → `MIC_UNVERIFIED` **[실측 master 2026-10-21 #2998]** · infer(로컬 launchd 스택) | Tailscale 켜짐 · 메모리 여유 ≈1GB(swap 6.1/7.0GB) **[실측]** |
| `mini` | BYZ Mac mini = tailnet `byzs-mac-mini` | 100.71.41.107 (user yoonhwan) | 같은 항목 전부 **[PENDING — D3 키 배포 뒤 P0 재실측]** | 망 online(ping 12ms) · ssh 인증 없음 |
| `oci` | jarvis OCI = ssh 별칭 `oci` | ubuntu@168.107.44.128 · Ubuntu 22.04 aarch64 · 4 vCPU · 24GB(여유 22.5GB) · 디스크 여유 73G · systemd · 무암호 sudo | heavy (브라우저 없음 · infer 없음) | tmux 3.2a·bash 5.1·python 3.10·node 22 있음 / claude·pi·codex·headroom·cliproxy·tailscale·tmuxc·tmm **없음** · hermes 가 `127.0.0.1:8644` 에 **systemd 유닛 없이 프로세스로만** 떠 있음 **[실측 hosts-facts L13·L36·L53–54]** |

→ 새로 Tailscale 을 설치할 곳 = OCI 한 곳. mini 는 ssh 키 배포 1회(사람 손) 선행. 브라우저·오디오 시험 후보 = Mac 두 대. jarvis 서비스(8080)는 범위 밖(§14 D7).
- 설계 영향: 원격 tmux 3.2a 기준 시험 · 원격 python 3.10 호환 · OCI 에서 무엇이든 돌리려면 tmuxc·ft-mbox·게이트 설치 선행(P3 부터 사람 손 h) · OCI 에서 에이전트 CLI 를 돌리려면 추론 스택(§8.1)이 그보다 먼저.

## 2. 전송층 (②) — 추천: **일반 ssh over Tailscale**

| 안 | 장 | 단 |
|---|---|---|
| **A. ssh over Tailscale(추천)** | oci 는 지금도 `BatchMode` ssh 가 된다 **[실측]** → P0 가 설치 없이 시작. 인증이 OpenSSH 하나(키). `ControlMaster` 로 연결 재사용 | 키 관리를 우리가 한다(§10) |
| B. Tailscale SSH | 키 불필요, ACL 로 통제 | 인증 경로가 둘로 늘고 콘솔 설정 의존 |
| C. mosh | 끊김에 강한 대화형 | 스크립트 호출에 부적합 |
| D. tmux 소켓 포워딩 | 원격 tmux 를 로컬처럼 | 소켓 권한·경로 문제, 디버깅 난해 |

→ **A**. 실행 규약: `ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPersist=60 <별칭> aifp-gate <동사>` — 원격에서 실행되는 것은 언제나 **고정 진입점 `aifp-gate` 하나**(§10). 인자는 명령줄이 아니라 stdin 의 JSON 한 줄로 보낸다(§10.2).

## 3. 우편함 (③) — 추천: **받는 호스트가 주인(수신 호스트 소유) + 허브 경유 배달**

### 3.0 왜 바꿨나 — r3 구조의 공통 원인과 «shard 위험» 전제 재검토
- r3 는 원격 좌석이 허브 `mailbox.jsonl` 의 행을 ssh 너머에서 임대(claim)·확인(ack)했다. DA r3-1 의 H1(mid·enqueue 두 파일 원자성)·H2(표시·seen)·H3(로컬 recv·ring 축출과 원격 임대의 경합)·H4(검사 통과 뒤 evict) 는 전부 «같은 행을 네트워크 양쪽이 동시에 만진다»에서 나왔다.
- r2 가 버린 «B. 호스트별 shard + 병합»의 위험(중복·순서 뒤집힘·consume-on-read 깨짐)은 **«여러 호스트에 사본을 두고 나중에 합친다»** 는 전제에서만 생긴다. 여기서 고르는 것은 그것이 아니라 **«메시지마다 주인 호스트가 정확히 하나»**(수신 좌석의 호스트)인 분할이다 — 사본·병합 단계가 없으므로 그 위험의 전제가 성립하지 않는다.
- 그래서 r4 는: **소비는 그 메시지의 주인 호스트 안에서만**, 네트워크는 «주인 호스트에 파일 하나를 만들어 주는 배달»만 한다.

### 3.1 저장 단위 — «메시지 = 파일 하나, 상태 = 디렉터리»
- 멀티 모드에서 **호스트를 건너온 메시지**는 받는 호스트의 `<FT_MBOX_DIR>/inbound/<mid>.msg` 파일 하나(JSON: `mid·seq·to·to_gen·from·from_host·from_gen·spool_seq·out_seq·ts_origin·body`)로 존재한다. 같은 호스트 안의 메시지(로컬→로컬)는 지금처럼 `mailbox.jsonl` 에 그대로 간다(ring 축출 포함 기존 동작 불변). **멀티 모드에서 이 로컬 경로를 쓰는 것은 «허브 좌석 → 허브 좌석»뿐이다** — 원격 호스트의 ft-mbox 는 `FT_HUB` 가 있으면 같은 호스트 좌석끼리도 허브 route 로 보내므로(§3.4) 원격 `mailbox.jsonl` 에는 새 행이 생기지 않는다. 남아 있던 옛 행·무세대 행은 «세대를 올리기 전 격리»(§11-2)로 처리한다(JSONL 형식은 바꾸지 않는다).
- 한 메시지는 언제나 **정확히 한 디렉터리**에 있고, 상태 이동은 같은 파일시스템 안의 `rename` 하나다.

| 위치 | 디렉터리 | 뜻 | 시간 청소 |
|---|---|---|---|
| 발신 원격 | `spool/` → `spool-done/` | 보낼 것 → 허브가 `QUEUED`/`DUP` 확인함 | `spool-done/` 만 |
| 허브 | `outbound/<host>/` → `routed-done/` | 배달할 것 → 받는 호스트가 `QUEUED`/`DUP` 확인함 | `routed-done/` 만 |
| 허브 | `quarantine/` → `disposed/` | 자동으로 보내지 않는 것(사유 기록: `evicted`·`delivery_unknown`·`late_delivered`·`reboot_unknown`) → 사람이 처분함 | `disposed/` 만 |
- **보관함 항목 = 디렉터리 1개**: `quarantine/<mid>/` 안에 `msg`(본문)·`late`(늦은 성공 표식, 있을 때)·`disp.json`(처분 기록, §11-3)이 함께 있고, 처분은 그 디렉터리를 `disposed/<mid>/` 로 **rename 1회** — 표식과 기록이 본문과 따로 움직이는 순간이 없다. 보관함에 **넣는** 것(evict 의 outbound 이동·route 의 `QUARANTINED`·허브 isolate)은 ①`quarantine/.tmp-<mid>/` 만들기 ②원본 파일을 그 안 `msg` 로 rename(또는 새로 쓰기) ③디렉터리를 `quarantine/<mid>/` 로 rename 의 3단계이고, 모든 보관함 작업은 시작할 때 남은 `.tmp-*` 를 먼저 마저 끝낸다(③만 남았으면 rename, 비었으면 삭제).
| 받는 호스트 | `inbound/` → `consumed/` | 미소비 → 소비됨 | `consumed/` 만 |
- **청소는 «-done/»·`disposed/`·`consumed/` 묘비만, 14일**(`BODIES_TTL_DAYS`). `spool/`·`outbound/`·`quarantine/` 처럼 «아직 끝나지 않은» 상태는 시간으로 지우지 않는다 — 만료되면 보고만 한다.
- `mid = <발신 host>-<발신 gen>-<uuid4>` 는 발신 쪽이 스풀에 쓰기 «전»에 만든다(재전송해도 같은 mid).
- **r6 에서 없앤 것**: r5 의 `hold/`·`recovered/`·`exported/`·`exported-done/`·`fenced/` — 전부 «옛 호스트 미소비분을 새 세대로 자동 이관»하기 위한 상태였다(§3.8).

### 3.2 deliver — 받는 호스트에 파일 하나 만들기
받는 호스트의 `aifp-gate inbox deliver`(stdin = 메시지 JSON)가 **우편함 잠금(`mailbox.lock`, 기존 `_locked` 와 같은 파일) 안에서**:
1. `inbound/`·`consumed/` 에 `<mid>.msg` 가 있으면 `DUP` 반환(성공 취급). 가드보다 먼저.
2. 받는 좌석·세대(`to`+`to_gen`) 앞 `inbound/` 미소비 건수가 `MAX_PER_TO`(10) 이상이면 `RING_FULL` — **버리지 않는다**.
3. 그 호스트의 `.seq` 카운터에서 seq 를 받아 본문에 넣고 `inbound/.tmp/<mid>` 쓰기 → **`link(.tmp/<mid>, inbound/<mid>.msg)`**(대상이 있으면 실패 = DUP) → `.tmp` 삭제 → `QUEUED seq=<s>` → 잠금 해제 → 로컬 doorbell(non-fatal).
- **중단 지점별 결과(프로세스 종료 범위 · §3.6)**: link 전 = 아무것도 안 보임 → 재전송 → 정상. link 후 응답 전 = 재전송이 1에서 `DUP`. 카운터만 오른 중단 = seq 하나 빔(무해). `.tmp` 잔재는 다음 deliver 가 지운다. **파일 존재 자체가 mid 기록**.
- **재전송 기한 < 묘비 수명 (같은 호스트 안에서만 필요하고, 같은 호스트 안에서만 성립)**: 허브는 한 메시지를 «처음 `outbound/<host>/` 에 들어간 그 호스트»로만 보낸다(다른 호스트로 옮기지 않는다 · §3.8). 재전송은 진입 + 7일 안에서만, 그 호스트의 `consumed/` 묘비는 소비(≥ link ≥ 진입) + 14일까지 → 마감이 언제나 먼저 온다. 7일이 지나도 확인을 못 받은 것은 `quarantine/`(사유 `delivery_unknown`)으로 옮기고 다시 보내지 않는다. 기준 시각은 outbound 파일의 `entered_at`(link 때 1회 기록)·스풀 파일의 `committed_at`(커밋 때 1회 기록)이며, 재시도·시도 횟수 갱신은 이 값을 바꾸지 않는다(시도 횟수는 별도 `<mid>.tries` 파일).

### 3.3 recv — 언제나 로컬, 자기 세대 것만
- 멀티 모드 recv 는 기존 `mailbox.jsonl` 경로(코드 그대로) **+** `inbound/` 경로를 합쳐 seq 내림차순(LIFO)으로 보인다. `inbound/` 경로는 **우편함 잠금 안에서** `to == me ∧ to_gen == $FT_SEAT_GEN` 인 파일만 하나씩 `rename(inbound/<mid>.msg → consumed/<mid>.msg)` 하고, 성공한 것만 잠금 해제 뒤 출력한다. 같은 좌석을 두 recv 가 동시에 불러도 잠금과 rename 이 «한 쪽만 성공».
- **다른 세대 파일은 소비하지 않는다**: `to_gen` 이 자기 세대와 다르면 건너뛰고 끝에 `다른 세대 쪽지 N통 — ft-host why <host>` 한 줄만 붙인다. 같은 이름 좌석을 같은 호스트에 다시 만들어도(세대 +1) 옛 세대 앞으로 왔던 파일·늦게 도착한 옛 배달이 새 세대에 섞이지 않는다(r5 N2 의 ABA 를 표식 없이 막는다). `FT_SEAT_GEN` 이 없는 recv(사람이 손으로 부름)는 `inbound/` 를 소비하지 않고 목록만 보인다. `mailbox.jsonl` 행에는 세대가 없으므로 이 필터가 닿지 않는다 — 대신 같은 이름의 세대를 올리는 유일한 경로(`seat-reserve`)가 그 이름 앞 JSONL 행을 먼저 격리한다(§11-2). 그래서 새 세대가 live 가 될 때 그 이름 앞 JSONL 행은 «새 세대 이후에 온 것»뿐이다.
- **보장 범위(명시)**: 정상 배달·재전송·프로세스 종료에 대해 «한 메시지는 한 호스트에서 한 좌석 세대가 한 번만 소비한다». **`quarantine/` 에 들어간 것은 이 보장 밖**이고, 사람이 «다시 보내기»를 고르면 **새 mid 의 새 메시지**(`resent_from=<옛 mid>` 표시)로 나간다 — 옛 것과 같은 메시지로 취급하지 않는다. 터미널 표시의 exactly-once 는 약속하지 않는다(rename 뒤 출력 전 종료 시 `recv <me> --replay [<mid>|--since N분]`, 14일). 이 범위는 지금 단일 호스트의 consume-on-read(L607→L608)와 같고 다시 보기만큼 더 강하다.
- **로컬 경합 없음**: 허브 로컬 send 의 ring 축출(L485–490)과 `_consume`(L575–582)은 `mailbox.jsonl` 만 다룬다. 기존 로컬 recv 의 «조회 L592 / 삭제 L607 분리» 결함은 `mailbox.jsonl` 에만 있는 기존 결함 → 별도 카드(선행 의존 아님).
- relay 전문: 호스트 간 메시지는 본문 전체가 파일 안. 표시는 700자에서 자르고 `consumed/<mid>.msg` 경로를 준다.

### 3.4 배달 경로 — 허브 경유 별 모양(star)
| 발신 위치 → 수신 좌석 위치 | 경로 |
|---|---|
| 허브 → 허브 | 기존 `mailbox.jsonl`(불변) |
| 원격 X → 어디든 | X 의 `spool/` → K1 `aifp-gate route`(허브) → 허브가 판정: 수신 좌석이 허브면 허브 `inbound/` 에 deliver(§3.2), 원격 Y 면 허브 `outbound/Y/<mid>.msg` 에 link(그 시점 `seats[to].gen` 을 `to_gen` 으로 고정) |
| 허브 → 원격 Y | 허브 `outbound/Y/<mid>.msg` 에 link(같은 방식) |
| 허브 `outbound/Y/` → Y | forwarder 가 K2 `aifp-gate inbox deliver` → `QUEUED`/`DUP` 면 `rename(outbound/Y/<mid> → routed-done/<mid>)`. 그 rename 이 실패하면(그 사이 §11 evict 가 옮김) **허브 우편함 잠금 안에서 그 mid 의 지금 위치를 찾아** 그 항목 디렉터리 안에 `late` 표식을 만든다 — 위치가 `quarantine/<mid>/` 이든 이미 처분된 `disposed/<mid>/` 든 그 자리에 붙이고, **항목을 새로 만들거나 되살리지 않는다**. 표식은 디렉터리 안에 있으므로 처분 rename 과 함께 움직인다 |
- **route 중복 판정(허브)**: 허브 우편함 잠금 안에서 `inbound/`·`consumed/`·`outbound/*/`·`routed-done/`·`quarantine/`·`disposed/` 에 `<mid>` 가 있으면 `DUP`. 발신 스풀 재전송(커밋 + 7일 안)은 언제나 허브 묘비(route 이후 생성 + 14일) 안에 든다.
- 원격 X 의 좌석끼리 보내는 쪽지도 허브를 거친다. 허브 다운 때 원격 좌석은 이미 배달된 자기 `inbound/` 를 계속 읽고, 발신은 `spool/` 에 쌓인다.

### 3.5 순서 보장 범위 — «같은 세대 쌍 · 큐 커밋 순서» (벽시계 0)
- **보장**: 같은 (발신 좌석·세대 → 수신 좌석·세대) 쌍에서, 수신 호스트의 seq 는 발신 스풀(허브발이면 허브 `outbound/`)의 **커밋 순서**와 같은 순서로 증가한다. 세대가 바뀌면(evict·재생성) 새 쌍이다. `quarantine/` 에 들어간 메시지는 배달되지 않았으므로 순서에 끼지 않고, 사람이 다시 보내면 그때 커밋된 새 메시지로 순서에 든다. 서로 다른 발신자 사이 순서·«생성 순서»·시계 순서는 약속하지 않는다. 표시는 지금과 같은 LIFO(L593).
- **번호**: 발신 호스트 `spool.seq`·허브 `out.seq` 카운터(잠금 안 `os.replace`)로 `spool_seq`·`out_seq`. 정렬은 이 번호로만 — `ts_origin` 은 «(지연 N초)» 표시에만.
- **보내는 쪽은 하나뿐**: 원격 flusher·허브 forwarder(받는 호스트별)는 `flush.lock`·`fwd-<Y>.lock` 을 non-blocking 으로 잡아 1개만 돈다. 즉시 전송·틱·재시작이 같은 잠금을 거친다. 놓은 뒤 큐가 비지 않았으면 다시 잡고 이어간다. 이 잠금들은 우편함·명부 잠금이 아니라 §0 «잠금 안 네트워크 0» 대상이 아니다.
- **멈춤 규칙**: 같은 수신 좌석 앞에서 첫 실패(`RING_FULL`·`BLOCKED`·불통)가 나면 그 좌석 앞 나머지는 멈춘다(다른 좌석은 계속). `STALE_GEN`/`HOST_REVOKED` 면 원격 `stale/`.

### 3.6 장애 범위 — «프로세스 종료까지» (r5 에서 DA 수용)
- 원자성·중복 0 약속은 **프로세스 종료(크래시·kill·ssh 끊김)** 에 대한 것이다. 같은 파일시스템 안 `link`·`rename` 의 원자적 가시성에 기댄다. **머신 장애(전원·커널 패닉) 뒤의 내구성은 약속하지 않는다**(기존 `_next_seq` 도 `fsync` 없음, `ft-mbox.py` L274–286).
- 머신 장애가 있었던 호스트(probe 의 boot-id 가 바뀜)는: 허브가 그 호스트 앞 `outbound/` 중 **한 번이라도 전송을 시도한 것**을 `quarantine/`(사유 `reboot_unknown`)으로 옮기고, 시도 0 인 것만 계속 보낸다(시도 횟수는 전송 «전»에 outbound 파일에 기록).

### 3.7 doorbell
- 배달이 끝난 호스트가 **자기 로컬에서** 울린다(deliver 의 마지막 단계). 허브가 원격 pane 에 send-keys 를 직접 보내지 않는다. `ring`(재발주, `ft-mbox.sh` L337–339, 큐·잠금 0)은 수신 좌석 호스트의 `aifp-gate inbox ring <seat> [seq]` 로 보낸다.

### 3.8 왜 «자동 이관»을 뺐나 (r6 결정)
- DA r5-1 의 N1(묘비 만료 뒤 부재를 «배달 안 됨»으로 오판)·N2(fence 해제 ABA)·N3(hold 복귀 뒤 순서)·N4(예약 전 export 결정)는 전부 «evict 된 호스트의 미소비분을 재조정·fence·export 로 새 세대에 자동으로 넘기는» 한 기능에서 나왔다.
- evict 는 원래 사람 승인(HIL)이 필요한 드문 사건이다. 그 드문 사건 하나를 자동화하려고 fence 표식·묘비 수명 계약·export 2단계·recovered 결정·hold 복귀 순서가 생겼다.
- r6: **evict 하면 그 호스트 앞 미처리 쪽지는 전부 `quarantine/`, 새 좌석은 빈 큐로 시작**. 처분(버림 / 새 메시지로 다시 보내기)은 사람(master 또는 오빠 · §14 D12). 없어지는 것과 남는 것:

| 항목 | r5 | r6 |
|---|---|---|
| fence 표식·`inbox fence/status` | 필요 | **없음** (세대 필터 §3.3 가 대신) |
| 재조정(«목록에 없음 = 배달 안 됨») | 필요 → N1 | **없음** |
| export 2단계·`recovered/`·`exported*/`·ACK | 필요 → N1·N4 | **없음** (옛 호스트 미소비분은 잔재 목록에만 · §12) |
| `hold/` 복귀 → 새 세대 배달 | 있음 → N3 | **없음** (`quarantine/` 는 배달하지 않음) |
| 묘비 수명 계약 | 호스트 간 체인 | **같은 호스트 안**만(§3.2) |
| 사람 비용 | evict 때 hold 만 처분 | evict 때 그 호스트 앞 미처리 전부 처분(드문 사건 · 대개 수 통) |

## 4. 명부와 라우팅 (④)

- `seats.json` 항목에 선택 필드 `"host"`, `"gen"`, `"status": "reserved|live|evicted"` (없으면 `local`·세대 검사 안 함). 기존 파일은 한 글자도 안 바뀐다 **[실측: 현 스키마에 host 없음]**.
- 허브의 `seats.json`·`hosts.json` 이 단일 정본(원격은 사본 없음). 멀티 모드에서 둘을 쓰는 모든 코드(spawn·close·role-spawn·evict·route·forwarder)는 **`seats.lock`** 을 잡는다 — 읽고 판정만 하는 쪽은 `LOCK_SH`, 바꾸는 쪽은 `LOCK_EX`. 지금 `ft-nano-spawn.sh` 는 seats.json 을 잠금 없이 쓴다 **[실측 L41·L167]** → 단일 모드는 그대로 두고 멀티 모드에서만 잠금.
- **잠금 순서 고정**: `seats.lock` → `mailbox.lock`(역순 금지). 둘 다 `flock` 이라 프로세스가 죽으면 자동 해제. 잠금 안에서 네트워크 0(§0).
- 원격 좌석은 자기 `gen` 을 생성 때 받은 env `FT_SEAT_GEN` 으로 안다 — tmuxc `open` 에 선택 플래그 `--seat-env K=V` 를 추가해 `create_tmux_session` 의 `-e` 인자(tmuxc L62, 지금 `FT_SEAT` 를 심는 자리)로 넘긴다. 플래그가 없으면 동작 불변.
- 세션 이름은 호스트 간 전역 유일. 같은 이름 두 세대의 «권한»을 가르는 것은 §11 의 `gen` 이고, `ft-name-lint` 의 host 간 중복 검사는 사후 보고용이다.
- 라우팅 함수 `host_of <seat>` = seats.json `host`(없으면 `local`) — route·forwarder·tmuxc `--host` 기본값이 이 값을 쓴다.

## 5. 워크트리·깃 (⑤)

- 정본은 공유 원격(origin). 원격 호스트는 자기 디스크에 clone 하고 나노 가지는 거기서 만든다. `ft-nano-spawn` 의 로컬 `git -C $ROOT worktree add` **[실측 :95,137-140]** 는 `--host` 일 때 K2 `aifp-gate git worktree-add <branch>`(경로는 원격 게이트가 자기 `root` 로 정한다 · §10)로 대체.
- 결과 회수는 **git push 한 길**. 허브가 `git ls-remote` 로 sha 확인 후 랜딩.
- `ft-nano-close` 의 HEAD 검사 **[실측 :30-38,104-105]** 는 `--host` 일 때 K2 `aifp-gate git rev-parse <worktree>` 결과가 `git ls-remote origin <branch>` 와 같은지로 대체. 다르면 닫지 않는다.
- `.env`·심링크·비밀은 전송하지 않는다(§10). 원격 가지 정리는 지금 규칙 그대로(브랜치 삭제 HIL).

## 6. tmm HOST 열 (⑥)

- **켜짐 조건**: hosts.json 에 `active` 호스트가 2개 이상일 때만. 1개면 행 문자열 바이트 동일.
- **원격 행은 원격 tmm 이 만든다**: tmm 의 행 생성(`cmd_rows`, tmm L443)은 `list-sessions`+`list-panes -a`×2+좌석당 `capture-pane`+`show-environment` 를 로컬 서버에 부른다 **[실측 research-nano-2 §6-7]** → 이것을 ssh 로 하나씩 옮기지 않고, 원격에 설치된 tmm 의 비대화 진입점 `tmm rows --tsv`(P4 에서 추가 · `cmd_rows` 그대로 호출)를 K2 `aifp-gate rows` 로 **호스트당 1회** 부른다. dead 목록도 같은 호출에 싣는다(원격의 `pgrep`·`ps`·`lsof` 는 원격 안에서 돈다).
- 허브 tmm 은 받은 행 앞에 2~3자 호스트 약칭을 붙여 합친다. 행 키는 멀티일 때 `host<US>session`(0x1f) — `{2}` 소비처가 분해 **[실측 scout-tmm]**. 폭 ≤58.
- 호스트별 병렬 · `timeout 7` · 재시도 0 → 실패 시 `HOST<TAB><TAB>UNREACHABLE` 행. dead 뷰는 UNREACHABLE 호스트를 «모름»으로(죽음 아님).
- 행 위 동작: tmm 은 이미 send/kill/probe/model/fork/open/save 7곳을 tmuxc 로 위임한다 **[실측 research-nano-2 §6-9]** → 원격 행이면 `tmuxc --host <h> …` 로 위임(§7). preview 는 K2 `aifp-gate pane-capture <seat> <줄수>`. attach 는 허브 tmux 에 새 창을 열고 그 안에서 `ssh -t aifp-<h>-op aifp-gate attach <seat>`. `switch-client`·`detach-client`·`list-clients`·`select-pane` 은 허브 화면(오빠 클라이언트) 조작이라 원격으로 보내지 않는다. 위임 실패 시의 tmux 직접 폴백(tmm L1443·L1470)은 원격 행에서 쓰지 않는다(오류 표시).
- 캐시 키(`tmm:96` `socket_path`)에 host 포함.

## 7. tmuxc `--host` 디스패치 (⑦) — tmuxc «명령 단위»로 넘긴다

- r3 는 tmuxc 안의 tmux 호출 하나하나를 `host_tmux` 로 감쌌다. 실측 호출은 tmuxc 47·tmm 74·seat-scan 3 = tmux 124건 + pgrep 8·ps 4·lsof 2 이고, 그중 `ps eww`(tmuxc:732)·`pgrep -P` 는 원격 프로세스 표에 적용할 수 없는 로컬 전용 조회다 **[실측 research-nano-2 §0·§6-2·§6-10]**. 호출 단위 원격화는 허용 목록이 이 124+14건을 따라가야 하고 프로세스 조회가 깨진다 → 버린다.
- **r4**: `tmuxc` 의 맨 앞(`main()` tmuxc L1823 진입 직후)에서만 `--host <h>` 또는 `TMUXC_HOST` 를 본다.
  - 없거나 `local`: **그 뒤 코드 한 줄도 바뀌지 않는다**(인자 분기 추가뿐). tmux·pgrep·ps·lsof 호출, `exec` 없음, 스냅샷 경로 `SNAP_DIR`(L957)·과거 파일 탐색(L1128)·`latest.json`(L1191·L1611) 전부 그대로.
  - `<h>`: `ssh aifp-<h>-op aifp-gate tmuxc` 에 stdin JSON `{"argv": ["<하위 명령>", …]}` 을 보내고, 원격 게이트가 **원격에 설치된 tmuxc** 를 그 argv 로 `execve`(셸 0) → stdout/stderr/종료코드를 그대로 돌려받는다. ssh 자체 실패(255)는 `UNREACHABLE`(rc 7)로 바꿔 보고.
- 그래서 원격의 tmux·pgrep·ps·lsof·홈 경로(`~/.tmuxc/snapshots`·`~/.claude.json`·serena bridges)는 전부 **원격 tmuxc 가 원격 안에서** 쓴다 — 원격 스냅샷은 원격 홈에 저장되고, 허브의 스냅샷 경로는 손대지 않는다.
- 표면: `tmuxc --host oci open|send|list|kill|probe|model|msg|ask|submit|save|restore|fork`. `attach` 만 `ssh -t aifp-<h>-op aifp-gate attach <seat>`(PTY). `clean`(대량 정리)은 원격으로 넘기지 않는다(잔재는 §12 HIL). `list -a` 는 호스트 팬아웃 + host 열.

## 8. Linux 이식 (⑧)

조사 **[scout-linux]** 의 «진짜 깨지는 곳»(호스트가 linux 일 때만 · 맥 단일 무영향). r4 에서는 tmuxc·tmm·ft-mbox 가 원격 안에서 통째로 돌므로 이 목록이 **원격 실행의 전제 조건**이 된다:

| 위치 | 고침 |
|---|---|
| `ft-nano-spawn.sh:148` `sed -i ''` | `sed -i.bak` 후 .bak 삭제 |
| `ft-nano-close.sh:125,226,232` · `ft-mbox.sh:78,79` unguarded `stat -f` | `stat -f … \|\| stat -c …` 가드 |
| `ft-press-gate.sh:91,143` BSD `date -r/-j` | `date -d` 폴백 (tmm:346-347 패턴) |
| `tmuxc:391` `/opt/homebrew/bin/uvx`, `ft-nano-close.sh:52` lsof/tmux 경로 | `command -v` |
| `ft-tick*` launchd | systemd user unit + `loginctl enable-linger` |
| `tmm-dead-scan.py:139` `lsof -c` | Linux lsof 플래그 확인 후 분기 **[가정]** |
| `tmuxc:732` `ps eww` (headroom 경유 확인) | Linux `ps eww` 동작 확인 — 다르면 `/proc/<pid>/environ` 분기 **[가정]** |

원칙: 맥 동작은 가드 추가로만 바뀐다. 시험: `test/` 에 맥 결과 불변 스냅샷.

### 8.1 OCI 추론 스택 (headroom·cliproxy) + hermes 업데이트 경로 (발주 #3009)
오빠 지시 원문: 「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」. OCI 는 둘 다 없다 **[실측 hosts-facts L13·L36]** → **claude·pi·codex 설치(P5b) 보다 먼저** OCI 로컬에 추론 스택을 둔다(P5a).

| 항목 | 이 맥(지금) | OCI (설계) |
|---|---|---|
| 실행 단위 | launchd (headroom 8790 · cliproxy 8317) | **systemd user unit** `aifp-headroom.service`·`aifp-cliproxy.service` + `loginctl enable-linger`(비로그인 유지) · 둘 다 `127.0.0.1` 바인드(tailnet·공인 IP 노출 0) |
| 바이너리 | 맥 빌드 | linux/arm64 빌드 — 설치 h 가 버전 고정(이 맥과 같은 버전·같은 임베디드 모델 카탈로그) **[가정 — arm64 빌드 존재 여부 P5a 착수 전 확인]** |
| 인증 파일(구독 auth) | 이 맥 로컬 | **OCI 에 두는 것 자체가 비밀 표면 증가 → 오빠 결정 D10**. 둔다면: op develop 볼트에서 설치 h 가 0600 파일로만 내려놓음 · 출력 0 · 경로는 OCI 홈 밖으로 복사 0 |
| 계정 한도 | 이 맥 스택이 씀 | 같은 계정 auth 를 두 호스트가 쓰면 **한도(usage limit)를 나눠 쓴다** → 동시 사용 시 503 `usage_limit_reached` 가 양쪽에 같이 온다(troubleshoot 09-23 계열). D10 에 «별도 계정/같은 계정» 선택을 함께 둔다 |
| claude 연결 | 프로젝트 레벨 fail-open 래퍼(`claude-hr.sh` · 하드 룰 4) | 같은 방식 — OCI 에서도 `ANTHROPIC_BASE_URL` 전역 export 0. 래퍼가 `127.0.0.1:8790` health 실패 시 직결로 fail-open |
| 건강 확인 | 기존 doctor | `aifp-gate probe --caps` 가 OCI 의 두 포트 health(읽기)를 `infer` caps 로 보고 |

**hermes**: OCI `127.0.0.1:8644` 에 hermes 가 **systemd 유닛 없이 프로세스로만** 떠 있어 업데이트·재기동 경로가 없다 **[실측 hosts-facts L53–54]**.
1. (P0, 읽기 전용) 그 프로세스의 실행 파일·인자·작업 폴더·설치 방식(git checkout / pip / 바이너리)·버전만 기록(`ps -o args=`·`readlink /proc/<pid>/exe`·`/proc/<pid>/cwd` · 환경변수는 읽지 않음).
2. (P5a, 사람 승인) 기록한 시작 명령을 그대로 옮긴 systemd user unit `aifp-hermes.service` 를 만들고 **지금 프로세스를 끄고 유닛으로 다시 띄운다** — 실행 중 서비스 정지 = 인프라 조작이라 HIL(§14 D11 · `/tmp/h<N>`). 끊기는 시간 = 정지~유닛 기동 사이.
3. 업데이트 = 1에서 확인한 설치 방식대로 «버전 받기 → `systemctl --user restart aifp-hermes` → 8644 health» 를 한 h 스크립트로. 실패 시 이전 버전으로 되돌림(설치 방식별 되돌림을 그 스크립트에 함께).
- 이 맥의 Hermes 게이트웨이(launchd)는 이번 범위 밖(바꾸지 않는다).

## 9. 브라우저·오디오 시험의 이관 (⑨)

- `caps` 에 `browser`(·`audio`) 가 있는 호스트가 시험 실행 호스트. 시험 나노는 거기서 열리고 러너·크롬·CDP·BlackHole 은 **그 호스트 로컬**에서 돈다.
- 오디오 E2E(BlackHole)는 호스트당 시스템 전역 1개 → «오디오 press 순차»를 «호스트별 순차»로 일반화. 서로 다른 호스트면 동시 가능.
- 포트 `38301~38399` 슬롯 규칙은 호스트마다 독립. **포트 포워딩(`ssh -L`)은 쓰지 않는다** — 모든 키가 `restrict` 로 막는다(§10). 결과는 원격에서 만든 스크린샷·로그를 git push 로 회수. 라이브로 봐야 하면 §14 D8.
- 측정 조작 금지(임의 Redis·DOM 주입)는 원격에서도 동일 — 기존 e2e 러너·trusted 클릭(`Input.dispatchMouseEvent`) 그대로.
- 마이크 권한(TCC)은 사용자 DB 를 프로그램이 읽을 수 없다 **[실측 book: 읽기 거부]** → 판정은 «실제 녹음 시험이 소리를 받았나»(P6) 또는 사람 확인(§14 D9).

## 10. 보안 (⑩) — 키 2종 · 고정 진입점 1개 · 동사별 인증

### 10.1 키
| 키 | 방향 · 인증 주체 | 받는 쪽 authorized_keys 줄 |
|---|---|---|
| **K1 우편함 키** `id_ed25519_aifp_mbox_<host>` | 원격 → 허브. 주체 = «그 원격 호스트»(키 1개 = 호스트 1개) | 허브: `restrict,from="<그 호스트 100.x>",command="<허브 설치 경로>/aifp-gate --role hub --caller <host>" ssh-ed25519 …` |
| **K2 조작 키** `id_ed25519_aifp_op` | 허브 → 원격. 주체 = «허브»(개인키는 허브에만) | 원격: `restrict,pty,from="<허브 100.x>",command="<원격 설치 경로>/aifp-gate --role remote" ssh-ed25519 …` (`restrict,pty,command=` = sshd.8 L700–701 공식 예시 **[실측 research-nano-1 §2.1]**) |
- `restrict` 가 포워딩·agent·X11 을 막는다(L662–668). K1 은 PTY 도 없다. K2 의 `pty` 는 `attach`·`pty-check` 에서만 쓰인다.
- 원격 좌석(옛 세대 포함)은 K2 개인키를 갖지 않으므로 다른 호스트를 조작할 수 없고, K1 으로는 허브에 아래 두 동사만 부를 수 있다.

### 10.2 argv 프레이밍 — 셸 인용을 쓰지 않는다
- `SSH_ORIGINAL_COMMAND`(sshd.8 L525–527)에서는 **동사 이름만** 읽는다. 형식 `aifp-gate <동사>` (토큰 2개, 동사는 `[a-z-]+`). **`attach` 만** 세 번째 토큰으로 좌석 이름(`NAME_RE` = `^[A-Za-z0-9._#-]+$`, `ft-mbox.py` L25 와 같은 규칙)을 받는다 — 공백·따옴표·`$` 가 없는 문자 집합이라 분해 모호성이 없다. `pty-check` 는 인자가 없다.
- 그 밖의 인자와 본문은 **stdin 의 JSON 한 줄**(`{"argv":[…],"body":"…"}`). 여러 줄 본문·따옴표·`$'…'` 모두 JSON 문자열로 그대로 왕복한다 — r3 의 `printf %q` ↔ `shlex` 불일치가 생길 자리가 없다.
- 게이트는 동사별 스키마로 argv 를 검사하고 `execve`(인자 목록, 셸 0)로만 실행한다. 로그는 동사 이름·호출 호스트·rc 만(인자·본문 0).
- **거절의 두 종류를 구분한다**: ①**동사 거절** = 게이트가 stdout 첫 줄 `REJECT verb=<동사>` + rc 2 (sshd 는 명령을 실행했음) ②**PTY 거절** = sshd 가 `restrict`(pty 없음) 때문에 PTY 요청을 거절 — 클라이언트 stderr 에 `PTY allocation request failed` 가 찍히고 **명령은 tty 없이 실행된다**. 시험은 둘을 따로 본다(§13 P1).

### 10.3 동사별 허용·인증 표 (이 표가 정확한 허용 목록 — 밖이면 동사 거절)
| 키 | 동사 | 허용 인자 | 인증 검사 (허브 쪽은 `seats.lock` SH 안에서) |
|---|---|---|---|
| K1 | `ping` | stdin JSON 을 그대로 되돌림(argv 왕복 시험용) | `hosts[caller].state ∈ {active, draining}` |
| K1 | `route` | 메시지 JSON(`mid·from·from_gen·to·spool_seq·body·ts_origin`) | ①`hosts[caller].state ∈ {active, draining}` ②`seats[from].host == caller` ③`seats[from].gen == from_gen` ④`seats[from].status == live` ⑤(**처음 보는 mid 에만** — DUP 판정이 먼저이고, 이미 받은 mid 는 상태와 무관하게 `DUP`) `seats[to].status == live` ∧ `hosts[seats[to].host].state ∈ {active, draining}` ∧ 그 호스트의 evict 기록이 없거나 `done` — 아니면 대상 상태별로: `reserved` → `TARGET_NOT_LIVE`(발신 스풀에 남겨 재시도) · `evicted` 또는 그 호스트 `revoked`/evict 진행 중 → 허브 `quarantine/`(사유 `target_evicted`)에 넣고 `QUARANTINED`(발신 쪽은 성공 처리 → `spool-done/`) · 명부에 없음 → `TARGET_UNKNOWN`(스풀 `stale/`). 허브 로컬 좌석이 원격 좌석에게 보내는 outbound link 도 같은 검사 — **검사와 enqueue(허브 inbound deliver 또는 outbound link)를 같은 SH 구간 안에서** 끝낸다(§11) |
| K2 | `ping` | stdin JSON 을 그대로 되돌림 | 주체 = 허브(키 보유자) |
| K2 | `pty-check` | 없음 · tty 이름(`tty` 출력)을 돌려줌 | 〃 |
| K2 | `tmuxc` | argv[0] ∈ {open, send, list, kill, probe, model, msg, ask, submit, save, restore, fork}, 나머지는 원격 tmuxc 가 검사 | 〃 · 권한 판정(누구를 열고 닫나·HIL)은 허브 쪽 기존 규칙 |
| K2 | `attach` | 좌석 이름 1개(NAME_RE) · PTY | 〃 · `tmux attach-session -t =<seat>` 고정 |
| K2 | `pane-capture` | 좌석 이름 + 줄 수(정수 ≤2000) | 〃 · `tmux capture-pane -p -t =<seat> -S -<n>` 고정 |
| K2 | `rows` | 없음 | 〃 · 원격 `tmm rows --tsv` |
| K2 | `inbox` | {deliver(stdin 메시지) · ring <seat> [seq] · count <seat> · list <seat\|--spool>(읽기 전용 · 잔재 목록용) · isolate <seat>(§11-2 · 그 호스트 안에서만 격리 · 허브로 본문 전송 0) · list --isolated(읽기 전용)} | 〃 · deliver §3.2 · list §12 · isolate §11-2 |
| K2 | `git` | {clone, fetch, worktree-add <branch>, worktree-list, rev-parse <worktree>, status <worktree>, push <worktree> <branch>} — 경로는 원격 게이트가 자기 `root` 기준으로 정함 | 〃 |
| K2 | `probe` | {--caps, --scan, --residue, --boot-id} (전부 읽기 전용) | 〃 |
| K2 | `e2e` | (P6) 원격 설정 파일에 등록된 러너 진입점 1개 + 인자 | 〃 |
- 원격 tmuxc 내부의 tmux 하위 명령(research-nano-2 의 124건)은 게이트를 지나지 않는다(원격 안에서 원격 tmuxc 가 부른다).
- 추론 스택·hermes 의 설치·재기동은 게이트 동사가 아니다 — 사람 승인 h 스크립트(§8.1)로만.

### 10.4 비밀
| 비밀 | 저장 | 새는 길 차단 |
|---|---|---|
| Tailscale 인증키 | **1Password `develop` 볼트** (kskill 금지) | 설치 h 가 `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op read … > <0600 임시파일>` → `tailscale up --auth-key=file:<경로>`(지원 확인 · 1.102.2 **[실측 research-nano-1 §3]**) → 임시파일 삭제. 명령줄·쪽지·pane 출력 0. 1회용·단기 만료 키 |
| ssh 개인키 K1·K2 | 만든 호스트 `~/.ssh` (0600), 공개키만 상대에 | §10.1 |
| 추론 스택 auth 파일(OCI) | D10 승인 시에만 · op develop → OCI 0600 | 출력 0 · 쪽지·로그 0 · 워크트리 복사 0 |
| 서비스 토큰 | op develop → 호스트 로컬 env | 워크트리로 복사 0 |
- `tailscale up` 은 플래그 «완전 집합»·`--accept-dns` 기본 true **[실측]** → 호스트별 프로파일 한 벌(`--hostname`·`--advertise-tags=tag:aifp`·`--accept-dns=false`)을 매번 전체로. 원격 ssh 위 `--force-reauth` 금지. **시간 상한(7초 룰)**: 단계 ① `tailscale up … --timeout=7s`(재시도 1회) → 상태가 `NeedsLogin`/`NeedsMachineAuth` 면 ② 사람이 콘솔에서 승인(외부 호출 아님 · 사람 대기) → ③ `tailscale status --json` 1회 7초씩 30초 간격 확인(각 시도 재시도 1회). 인증키가 사전 승인 키면 ②가 없다.
- ACL: 좌석 호스트 `tag:aifp`, 허용 `tag:aifp ↔ tag:aifp` 22/tcp 만. 콘솔 편집 = 사람 **[결정 D4]**. 서버 노드 키 만료 비활성 = 콘솔 **[가정]**.
- 로그: ssh `-v` 금지. 쪽지 본문 비밀 금지 규칙 그대로.

## 11. 실패 모드 (⑪) — 세대 차단을 «검사와 커밋이 같은 잠금 구간»으로

| 사건 | 동작 | 복구 |
|---|---|---|
| 원격→허브 끊김 | 원격 send 는 스풀에 쌓고 «지연됨». 원격 recv 는 자기 `inbound/` 를 계속 읽음 | 재연결 시 flush(mid 멱등) |
| 허브→원격 끊김 | 그 호스트 좌석 UNREACHABLE(죽음 아님). `outbound/<h>/` 에 쌓임 | 복구 후 forwarder 가 이어 보냄 |
| deliver 응답 유실 | 재전송 → `DUP` → 성공 처리 (§3.2) | 자동 |
| 원격 호스트 다운 | 그 호스트 좌석 UNREACHABLE · 그 `inbound/` 미소비분은 호스트 안에 보존 | 아래 evict(사람 승인) |
| 명부↔실제 tmux 불일치 | 판정 근거는 «그 호스트에 직접 물은 결과»(`probe --scan`)만 | probe 재실행 |
| 원격 작업 유실 | 원격 나노는 중간 push 정례화(push 확인 못 하면 닫기 실패) | §5 |
| OCI 추론 스택 다운 | `infer` caps 꺼짐 → OCI 좌석의 claude 래퍼가 직결로 fail-open · 새 OCI 좌석 배치 보류 | systemd 가 재기동 · 반복 실패면 [HIL] |

**선형화 지점은 하나 — 허브 enqueue**: `host-evict` 의 `seats.lock` EX 커밋. 그 전에 검사를 통과한 route 는 enqueue 까지 끝났고(SH 가 enqueue 끝까지 유지 · 잠금 구간 안 네트워크 0), 그 뒤의 route 는 `HOST_REVOKED`. r5 의 «수신 소유권 이전 선형화(fence)»는 소유권을 옮기지 않으므로 필요 없다(§3.8).

**evict → 새 세대** (허브 · 순서 고정):
1. `host-evict <host>`(HIL) — **재실행 가능한 단계 진행**: 기록 파일 `.fable-team/state/evict/<host>.json`(쓰기는 언제나 `.tmp` → `os.replace`)의 `phase` 를 따라간다.
   - ⓐ `phase=started` 기록 → ⓑ `seats.lock` EX 안에서 `hosts[host].state = revoked`·그 호스트 좌석 `status = evicted` 를 **hosts.json·seats.json 각각 `.tmp` → `os.replace`** 로 저장(프로세스 종료 시에도 두 파일은 옛 내용 또는 새 내용 중 하나로 파싱 가능) → `phase=state_written` → ⓒ 같은 EX 안에서 우편함 잠금을 잡고 `outbound/<host>/` 의 파일을 하나씩 `quarantine/` 로 rename(사유 `evicted` · `.tries` 가 있으면 `delivery_unknown` 도) → 비면 `phase=done`.
   - **중단 뒤**: 같은 명령을 다시 실행하면 기록의 `phase` 부터 이어간다 — ⓑ 는 같은 값을 다시 써도 같고, ⓒ 는 남은 파일만 옮긴다(이미 옮긴 것은 출처에 없다). 기록이 `done` 이 아니면 그 호스트는 «evict 진행 중»: route 는 그 호스트 좌석 앞 새 mid 를 `QUARANTINED` 로 받고(§10.3 ⑤), forwarder 는 `revoked` 라 보내지 않으며, **reserve·retire·readmit 는 `EVICT_INCOMPLETE` 로 거절**한다. ft-host·tmm 은 «evict 중단됨 → 다시 실행» 한 줄을 보인다.
   - forwarder 는 매 전송 직전에 SH 로 상태를 다시 보므로 ⓑ 뒤로 그 호스트 앞 새 전송은 시작되지 않는다. 이미 시작된 전송이 뒤늦게 성공하면 §3.4 의 `late` 표식이 붙는다(어느 쪽이든 새 호스트로는 가지 않는다).
2. `seat-reserve <name> --host <new>`: 조건 = 옛 호스트 evict 기록 `done`. 진행도 기록(`.fable-team/state/reserve/<name>-<gen>.json`, `.tmp`→`os.replace`)을 따른다 — ⓐ `seats.lock` EX 안에서 `gen = 옛 gen + 1`, `status = reserved` 저장 → ⓑ **옛 행 격리 — 그 호스트 안에서만**: 새 호스트와 옛 호스트(접속되면) 각각에서, **그 호스트의 우편함 잠금 안에서** ①`to == <name>` 행을 그 호스트의 `quarantine-local/local-<host>-<seq>.json` 으로 쓴다(같은 파일시스템 · `.tmp` → link, 있으면 건너뜀) ②나머지 행 전부를 `mailbox.jsonl.tmp` 에 끝까지 쓴 뒤 **`os.replace(mailbox.jsonl.tmp, mailbox.jsonl)`** — 기존 `_save`(open «w» 후 쓰기, `ft-mbox.py` L309–313)는 쓰지 않는다. 중단 지점별: ① 중 = 다음 실행이 이어서 · ①과 ② 사이 = 격리본과 원본 행이 둘 다 있음(재실행이 ②를 마저 함 · 새 세대는 아직 live 아님) · ② 중 = 원본 JSONL 그대로(다른 좌석 행 손실 0). 원격(K2 `inbox isolate <seat>`)도 같은 절차를 그 원격 안에서 하고, **허브로는 건수·seq 목록만** 돌려준다(본문 전송 0 → 응답이 끊겨도 원본은 원격에 남는다). 허브는 이 목록을 잔재로 보여 준다(§12 · `inbox list --isolated`). 허브 자신의 행은 허브 `quarantine/` 에 같은 방식(같은 파일시스템)으로 넣어 §11-3 처분 대상이 된다. 원격 `quarantine-local/` 은 처분 계약(§11-3) 밖의 잔재 — 필요하면 사람이 내용을 보고 새 쪽지로 보낸다(중복 방지 약속 없음) → ⓒ spawn 이 `--seat-env FT_SEAT_GEN=<gen>` 으로 열고 `live`. **새 세대는 빈 큐로 시작**한다. 같은 이름을 두 곳이 동시에 예약할 수 없다. inbound 쪽 옛 세대 파일은 recv 세대 필터(§3.3)가 소비하지 않는다.
3. **quarantine 처분**(사람 · §14 D12): 건별 «버림» 또는 «다시 보내기». **고정 단위 = 원본 mid 의 처분 기록 `quarantine/<mid>/disp.json`** (계획 파일이 아니다).
   - 계획: `ft-host plan dispose <mid> --resend|--drop` 은 `disp.json` 이 **있으면 그 값(action·new_mid)을 그대로** 보이고 «이미 시작된 처분 — 마무리만»이라고 쓴다. 없으면 제안값(다시 보내기면 새 `new_mid` 1개)과 계획 시점의 `late` 유무를 계획 파일에 적는다. 어느 쪽이든 `! bash /tmp/h<N>` 한 줄.
   - 실행(허브 우편함 잠금 안 · 순서 고정): ⓐ `disposed/<mid>/` 가 있으면 `ALREADY` 로 끝 ⓑ `disp.json` 이 **없으면**: 계획 뒤 `late` 가 새로 생겼으면 `LATE_CHANGED` 로 멈춤(아직 부작용 0이라 재계획이 안전) · 아니면 계획의 action·new_mid 로 `disp.json` 을 **첫 부작용 전에** 만든다(`created_at` 1회 기록, link 로 만들어 이미 있으면 기존 것을 씀) ⓒ `disp.json` 이 **있으면 그 new_mid 만** 쓴다 — 재계획·`LATE_CHANGED` 뒤의 재실행도 다른 new_mid 를 만들지 않는다. 이미 시작된 처분에 `late` 가 생긴 경우는 멈추지 않고 마무리하되 결과에 «다시 보낸 뒤 옛 기계 배달도 확인됨 — 받는 쪽 중복 가능»을 남긴다 ⓓ **기한**: 지금 시각 > `disp.created_at` + 7일 이면 새 전송을 하지 않고 `DISP_EXPIRED` 로 사람에게 돌려준다(«완료로 표시» 또는 «중복 감수하고 새 처분» 중 사람 선택 · 후자는 새 원본 처분으로 기록) ⓔ 다시 보내기면 new_mid 로 enqueue(`resent_from=<옛 mid>` · DUP 면 이미 보낸 것) ⓕ `rename(quarantine/<mid>/ → disposed/<mid>/)` — `late`·`disp.json` 이 함께 이동.
   - **왜 7일이면 충분한가**: new_mid 의 첫 enqueue 는 ⓓ 때문에 `created_at` + 7일 안에서만 일어난다. 그 enqueue 의 허브 묘비(`outbound`→`routed-done`)와 수신 묘비(`consumed`)는 enqueue 뒤 14일 이상 있으므로, 기한 안의 모든 재실행은 그 묘비에 걸려 DUP 가 된다. 기한 밖에서는 전송 자체를 안 하므로 묘비가 지워져도 다시 소비될 길이 없다. `quarantine/<mid>/`(그 안의 `disp.json` 포함)는 시간 청소 대상이 아니다(§3.1).
   - `late`·`delivery_unknown` 이 붙은 것은 받는 쪽 표시에 «옛 기계에 이미 갔을 수 있음». `disposed/<mid>/` 는 14일 묘비 · route 중복 판정에 계속 쓰임.
4. **옛 세대가 돌아오면**: K1 `route`·`ping` 이 `HOST_REVOKED`(rc 6) — 원격 스풀은 `stale/`. 옛 세대는 K2 키가 없어 다른 호스트를 만질 수 없다. 옛 호스트 `inbound/` 의 옛 세대 앞 파일은 옛 세대가 소비할 수도 있으나 그 호스트 안의 일이고 새 세대와 섞이지 않는다.
5. 옛 tmux 세션·프로세스와 옛 호스트 `inbound/`·`spool/` 은 «권한 없는 잔재» → §12 잔재 목록 → HIL. `ft-name-lint` 중복 검사는 보고용.
6. 같은 호스트 재사용: `host-readmit <host>`(HIL) → `state = active`. 옛 좌석은 `evicted` 그대로(새로 reserve).

**의존 한 점 (Tailscale)**: 코디네이터 장애 시 기존 연결은 대체로 유지, 신규 연결·키 갱신은 막힘 **[가정 · 설치 후 장애 시험]**. 최소 저하 = 단일 호스트로 후퇴(§12). r4 에선 허브가 끊겨도 각 원격 좌석은 이미 배달된 자기 쪽지를 계속 읽는다. oci 공인 IP 우회는 K1·K2 의 `from=` 이 tailnet IP 라 별도 줄 필요 **[가정]**. 맥은 NAT 뒤라 불가.

## 12. 되돌림 — 한 호스트 철수 순서 (DA 헌장 5 · r3 에서 PASS, r4 저장 구조에 맞춤)

**기록 → 차단 → 인계 → 조사 → 라우팅 제거**. 허브에서 실행.
1. **보존**: `ft-host-retire.sh <host> --record` → `.fable-team/state/host-retire/<host>-<ts>.json` 에 hosts.json 항목 전체, 그 호스트 좌석(name·gen·status), 허브 `outbound/<host>/` 건수·mid, 접속되면 원격 쪽(tmux 세션·`.worktrees/*`·가지·systemd/launchd 유닛(추론 스택·hermes 포함)·스풀·`inbound/` 미소비 건수·`FT_HUB` 설정 위치·authorized_keys 의 aifp 줄). 불통이면 원격 칸 `UNKNOWN`.
2. **신규 작업 차단**: `state = draining`.
3. **옛 세대 권한 차단**: §11 `host-evict`(`state = revoked`).
4. **미처리 메시지 격리**: §11-1 에서 허브 `outbound/<host>/` 는 이미 `quarantine/` 로 갔다. 원격 쪽(`inbound/` 미소비분·`spool/` 미전송분)은 **옮기지 않는다** — 접속되면 K2 `inbox list <seat>`·`inbox list --spool`(읽기 전용)로 목록·본문 요약만 1의 기록에 넣고, 필요한 것은 사람이 quarantine 처분과 같은 방식(새 메시지로 다시 보내기)으로 처리. 불통이면 1의 기록에 `UNKNOWN`.
5. **잔재 조사**: `aifp-gate probe --residue`(읽기 전용). 삭제(유닛 중지·auth 파일 삭제 포함)는 목록을 오빠께 보이고 기존 HIL(`/tmp/h<N>`).
6. **라우팅 제거**: `state = retired`(줄은 남김). 줄 삭제는 5가 끝난 뒤에만.

**완료 선언 조건**: 기록 파일 존재 ∧ `state == retired` ∧ 보고 3가지 — `quarantine/` 미처분 건수(사유별) · 원격 미소비/미전송 목록(또는 `UNKNOWN`) · 잔재 목록. 불통 호스트는 «retired(UNKNOWN)» 으로 선언하고 목록을 함께 남긴다.
**전체 철수**: 모든 원격에 1~6 → `hosts.json` 삭제 + 허브 `FT_HUB` 미설정 → 단일 모드. 허브 `inbound/` 는 단일 모드 recv 가 읽지 않으므로(멀티 모드에서만 합침) 철수 완료 조건에 «허브 `inbound/` 미소비 0» 을 넣는다.

## 13. 단계와 닫는 증거 (⑫)

닫는 명령은 **파이프 없이** 결과 파일로 쓰고 종료코드를 찍는다. 성공 = 출력 마지막 줄 `rc=0`. 표의 스크립트는 그 단계에서 새로 만든다(경로 `feature-pack/…`).

| 단계 | 내용 | 사람 손 | 닫는 명령 (1줄) | 실패 기준 |
|---|---|---|---|---|
| **P0 읽기 전용** | `ft-host-probe.sh`(신규, 허브에서 실행): 각 호스트에 지금 있는 ssh 로 읽기 명령만 — 공통: `uname -m; tmux -V; git --version; bash --version; free/vm_stat; command -v node python3`. **darwin 추가 5항목**: ①Chrome `test -d "/Applications/Google Chrome.app"` + 버전 ②CDP `lsof -nP -iTCP:9222 -sTCP:LISTEN`(없으면 `CDP_IDLE`=정상 · 있으면 pid·cwd) ③BlackHole `system_profiler SPAudioDataType` 장치 이름·채널 + `/Library/Audio/Plug-Ins/HAL` 드라이버 ④`command -v SwitchAudioSource` + `SwitchAudioSource -a -t input`·`-t output`(읽기만 · `-s` 전환 0) ⑤마이크: TCC 읽기 거부가 정상 → `MIC_UNVERIFIED`(실패 아님). **linux(oci) 추가**: 8790·8317 리스너 유무 · hermes(8644) 프로세스의 실행 파일·인자·cwd·설치 방식·버전(환경변수 0). 호스트별 1행 TSV | 없음 | `bash feature-pack/fable-team/skill/scripts/ft-host-probe.sh --all --expect 'book=OK oci=OK mini=PENDING_NOAUTH' --expect-caps 'book=chrome:OK,blackhole:OK,sas:OK,mic:MIC_UNVERIFIED' --out docs/multihost/probe-p0.tsv; echo "rc=$?"` | rc≠0 (0 = 기대와 전부 일치 · 3 = 하나라도 다름 · 4 = hosts.json 없음/형식 오류). 필수 = book·oci. mini 는 P1② 전까지 `PENDING_NOAUTH` 가 정답(OK·UNREACHABLE 둘 다 실패)이고 caps 검사 생략. oci 의 hermes 기록 칸이 비면 실패 |
| P1 망·접속 | ① OCI 에만 Tailscale(§10.4 단계 ①②③) ② mini 에 이 맥 공개키 1줄 ③ K1·K2 생성·등록, 원격에 `aifp-gate` 설치 ④ ACL·키 만료 | **오빠: ①승인 ②mini 에서 `! bash /tmp/h<N>` ③설치 h ④ACL 콘솔** | `bash feature-pack/fable-team/skill/scripts/ft-host-probe.sh --all --via tailnet --keys --expect 'book=OK oci=OK mini=OK' --out docs/multihost/probe-p1.tsv; echo "rc=$?"` | rc≠0. `--keys` 7항목(키×동사×결과) 전부 기대와 같음: **K1** ①`ping` 에 여러 줄·따옴표·`$'…'` JSON → 바이트 동일 왕복 ②`aifp-gate tmuxc` → **동사 거절**(stdout `REJECT verb=tmuxc`, rc 2) ③`ssh -tt … aifp-gate ping` → **PTY 거절**(stderr `PTY allocation request failed`) **이면서** 왕복은 성공(동사 거절 아님) · **K2** ④`ping` 바이트 동일 왕복 ⑤`ssh -tt … aifp-gate pty-check` → `/dev/pts/*` 또는 `/dev/ttys*` ⑥`aifp-gate shell` 같은 표 밖 동사 → 동사 거절 ⑦포워딩 거절 — `timeout 7` 안에서: 빈 로컬 포트 P 를 고른 뒤 `ssh -N -o ExitOnForwardFailure=no -L 127.0.0.1:P:127.0.0.1:22 aifp-<h>-op` 를 이 시험이 백그라운드로 띄우고, 1초 뒤 **로컬 P 로 실제 TCP 연결 1회**(python `socket.create_connection`, 3초 상한)를 만들어 원격 direct-tcpip 요청을 일으킨다 → 그 ssh 의 stderr 에 `open failed: administratively prohibited` 가 찍히고 연결은 즉시 닫힘(데이터 0)이면 통과 → 이 시험이 띄운 ssh 프로세스만 종료. 그리고 `tailscale status --json` 에 세 노드 online |
| P2 tmuxc 디스패치 | `main()` 앞단 `--host`/`TMUXC_HOST` 분기 + `open --seat-env` (§7) | 없음 | `bash feature-pack/tmuxc/test/host-dispatch-golden.sh; echo "rc=$?"` | rc≠0. ①단일 모드: 가짜 tmux/pgrep/ps(기존 `test_tmuxc_opencode_model.sh` 방식)로 대표 명령(open·send·kill·list·capture·attach·save/restore)을 분기 «전»·«후» 커밋에서 실행해 호출 순서·argv·종료코드·stdout/stderr·스냅샷 경로/`latest.json` 5가지 동일 ②`--host` 모드: ssh 를 가짜로 바꿔 stdin JSON argv 가 원래 argv 와 같고(여러 줄 본문 포함) rc 가 전달되며 ssh 255 → rc 7 |
| P3 우편함 멀티 모드 | `inbound/`·`outbound/`·`quarantine/`·deliver·route·forwarder·recv 합침(세대 필터)·`--replay`·`seats.lock`·스풀 | **오빠: oci 에 ft-mbox·게이트 설치 h** | `bash feature-pack/fable-team/test/mbox-multihost-fault.sh --n 200 --transport shim,ssh:oci --out docs/multihost/p3-mbox.tsv; echo "rc=$?"` | rc≠0. **격리 우편함**(임시 `FT_MBOX_DIR` · 제품 우편함·제품 Redis 쓰기 0). **장애 범위 = 프로세스 종료**(§3.6 · 전원 차단 시험 없음). 정상 왕복 N=200 + 장애 16종 — 배달: F1 deliver 의 link 직전·직후·응답 전 프로세스 종료 → 재전송 후 파일 1개 · F2 같은 mid 3회 재전송 → 1개 · F3 같은 좌석 recv 2개 동시 → 각 mid 한 쪽만 · F4 rename 뒤 출력 전 종료 → `--replay` 복원 · F5 로컬 ring 포화가 `inbound/` 불변 · F6 `RING_FULL` → 버림 0·그 좌석만 정지 · F7 7일 넘게 확인 못 받은 outbound → `quarantine/`(delivery_unknown)·재전송 0 · 순서: F8 같은 쌍 A·B·C 를 같은 ts_origin·시계 역행·동시 발신 2프로세스·forwarder 강제 종료 후 재시작 4변형으로 → 수신 seq 순 = 커밋 번호 순, 표시 = 역순 · 세대: F9 route 가 SH 를 잡은 채 evict → evict 는 그 enqueue 뒤 커밋 · F10 evict 뒤 옛 gen route·ping·flush → 전부 거절 · evict(r6): F11 evict 시 그 호스트 앞 outbound(시도 0 / 시도 ≥1) → 전부 `quarantine/`(사유 표시) · 새 세대 큐 0 · 새 호스트 배달 0 · F12 evict 직전 시작한 deliver 가 뒤늦게 성공 → quarantine 항목에 `late_delivered` · 새 호스트 배달 0 · F13 같은 호스트에 같은 이름 새 세대 → 옛 세대 앞 `inbound/` 파일·늦게 온 옛 배달·**그 이름 앞 `mailbox.jsonl` 옛 행(무세대)** 을 새 세대 recv(`FT_SEAT_GEN` 있음/없음 둘 다)가 소비 0 · JSONL 옛 행은 **그 호스트의** 격리 위치(허브 = `quarantine/`, 원격 = `quarantine-local/`) 한 벌 · 원격 isolate 응답 단절 → 원격 원본·격리본 보존, 허브엔 목록만 · **JSONL 재작성 도중 종료(①/② 사이, ② 중) → 다른 좌석 행 전부 보존** · 재실행해도 한 벌 · F14 evict 뒤 발신 스풀 재전송 → `quarantine/`·`disposed/` 로 DUP · F15 «다시 보내기» → 새 mid·`resent_from` 표시로 새 세대가 1회 소비, 옛 mid 는 `disposed/` · F16 boot-id 변경 → 시도 ≥1 outbound 만 `quarantine/`(reboot_unknown), 시도 0 은 계속 · 청소: F17 시간 청소기를 14일 앞당겨 돌려도 `spool/`·`outbound/`·`quarantine/` 파일 수 불변 · r7: F18 evict 완료~새 reserve 사이 정상 발신자의 새 mid route → `QUARANTINED`(target_evicted)·`outbound/<옛 host>/` 새 파일 0 · reserved 대상 → `TARGET_NOT_LIVE` 후 live 뒤 1회 배달 · 이미 받은 mid 재전송은 대상 상태와 무관하게 DUP · F19 evict 를 ⓐ 기록 직후·ⓑ hosts 교체 직후·seats 교체 직후·ⓒ 각 rename 직후에 각각 종료 → hosts.json·seats.json 파싱 가능 · 그 사이 reserve·retire·readmit 는 `EVICT_INCOMPLETE` · 재실행으로 `done` · outbound 남은 파일 0 · quarantine 중복 0 · F20 (복합) 다시 보내기 n1 enqueue 직후 종료 → 원본에 `late` 도착 → 재계획 → 재실행 → **새 메시지는 n1 한 통**(n2 생성 0) · `late` 가 처분 이동 «전»에 생기고 rename 직후 종료 → `disposed/<mid>/late` 보존·ALREADY 재개 · 처분 전 `late` 생김 → `LATE_CHANGED`(부작용 0) · F21 처분 기록 생성·n1 enqueue 후 종료 → 시간을 15일 앞당겨 청소기 실행(n1 묘비 소실) → 같은 계획 재실행 → `DISP_EXPIRED`·새 전송 0 · 그리고 단일 모드(hosts.json 없음) send/recv/peek 출력 바이트 동일 |
| P4 tmm HOST 열 | `tmm rows --tsv`, K2 `rows`·`pane-capture`, 합치기·UNREACHABLE·dead 오판 방지 | 없음 (P3 설치에 포함) | `bash feature-pack/tmm/test/host-col.sh --out docs/multihost/p4-tmm.tsv; echo "rc=$?"` | rc≠0. ①호스트 1개: 행 출력이 기존 골든(`feature-pack/tmm/test/golden`)과 `cmp` 동일 ②호스트 2개 중 하나를 응답 없는 스텁으로 두고 첫 화면까지 **7초 이내**(재시도 0) · 그 호스트는 `UNREACHABLE` 행 · dead 뷰에 그 호스트 좌석 0 |
| **P5a OCI 추론 스택 + hermes** (§8.1) | headroom(8790)·cliproxy(8317) systemd user unit · 127.0.0.1 바인드 · 버전 고정 · hermes 를 유닛으로 옮기고 업데이트 h | **오빠: D10(auth 귀속) · D11(hermes 재기동) · 설치 h** | `bash feature-pack/fable-team/test/oci-infer-health.sh --host oci --out docs/multihost/p5a-infer.tsv; echo "rc=$?"` | rc≠0. ①`systemctl --user is-active` 세 유닛 전부 `active` ∧ `loginctl show-user` linger=yes ②8790·8317·8644 health 각 7초 이내 응답 ③8790·8317 이 `127.0.0.1` 에만 바인드(tailnet·공인 IP 리스너 0) ④작은 요청 1회가 cliproxy 경유로 성공(본문·키 출력 0) ⑤OCI 전역 셸 설정에 `ANTHROPIC_BASE_URL` 0 ⑥hermes 업데이트 h 를 «같은 버전 재설치»로 1회 돌려 재기동 뒤 8644 health 복귀 |
| **P5b 원격 나노·Linux** | `ft-nano-spawn/close --host`(reserve→K2 git/tmuxc→live), §8 수정, systemd tick, 원격 tmuxc·tmm·CLI 설치(P5a 뒤) | **오빠: OCI 설치 h · D6** | `bash feature-pack/fable-team/test/nano-remote-roundtrip.sh --host oci --out docs/multihost/p5b-nano.tsv; echo "rc=$?"` | rc≠0. 착수 조건 P5a rc=0. 원격 나노 1개 spawn(`FT_SEAT_GEN` 확인 · claude 가 OCI 로컬 headroom 경유 — `ps eww` 또는 `/proc/<pid>/environ` 로 확인) → K2 `attach` 로 PTY 접속 확인 → 빈 커밋 push → close. 허브 `git ls-remote` sha = 원격 HEAD · close 뒤 `probe --residue oci` 의 그 좌석 tmux 세션 0 · 원격 스냅샷이 원격 `~/.tmuxc/snapshots` 에 생기고 허브 `SNAP_DIR` 변화 0 · 맥 §8 불변 스냅샷 동일 |
| P6 브라우저·오디오 시험 이관 | caps 라우팅, 호스트별 오디오 순차 · **마이크 확정 회차** | mini 키 배포(P1②) 후 P0 재실측 · D9 | `bash feature-pack/fable-team/test/remote-e2e.sh --host mini --runner '<기존 러너 진입점>' --out docs/multihost/p6-e2e.log; echo "rc=$?"` | rc≠0. **착수 조건**: 그 호스트 P0 caps `chrome=OK ∧ blackhole=OK ∧ sas=OK ∧ mic ∈ {MIC_UNVERIFIED, MIC_OK}` 아니면 착수 0. **① 마이크 확정 회차**(mic=MIC_UNVERIFIED 일 때만 · 같은 스크립트가 먼저 실행): 기존 러너 1회를 trusted 클릭(`Input.dispatchMouseEvent`)으로 돌려 «녹음 바이트 > 0 ∧ 무음 아님»이면 그 호스트 caps 를 `mic=MIC_OK` 로 기록하고 ②로 · 아니면 «클릭이 trusted 인가»를 먼저 확인한 뒤 1회 더 · 그래도 실패면 rc 5 + D9 의 사람 확인 요청(설정 화면 확인 후 다시 실행) — 이 회차 결과는 정식 판정에 쓰지 않는다. **② 정식 판정**: 같은 러너 1회 · 녹음·전송 바이트 > 0 ∧ STT 결과 비지 않음 · 러너 전후 `SwitchAudioSource -c -t input`·`-t output` 값 동일 · 같은 호스트 오디오 시험 동시 2건이면 실패 · 측정 조작 0. 러너 진입점은 P6 착수 때 대상 프로젝트 정본에서 복붙(지금 추측해 적지 않음) |

**조율**: `ft-*`·fable-team 은 BYZ 하네스 번호 직렬(1.1.x) → P3 이후 구현은 착수 전 하네스(master)와 카드 번호를 먼저 받는다. «로컬 recv 잠금 분리» 기존 결함 카드(§3.3)도 하네스로. 추론 스택 운영 절차는 `headroom-cliproxy` 스킬 정본과 맞춘다. 이 문서는 문서만.

## 14. 오빠 결정 목록 (인터뷰용, 쉬운 말 3줄)

| # | 결정 | 3줄 |
|---|---|---|
| D2 | 허브(명부·연락 본거지) | ①지금은 이 맥북인데 메모리 여유가 1GB 입니다. ②Mac mini 처럼 항상 켜 두는 기계가 허브가 되면 맥북을 닫아도 연락이 끊기지 않습니다. ③추천: Mac mini(D3 키 배포 뒤 메모리·상시 가동을 재 본 다음), 안 되면 맥북 유지. |
| D3 | Mac mini ssh 키 배포 | ①Mac mini 는 망에는 붙어 있는데 ssh 열쇠가 없어 못 들어갑니다. ②Mac mini 에서 «이 맥 공개키 1줄 추가»를 오빠가 한 번 해 주셔야 합니다(`! bash /tmp/h<N>` 를 드립니다). ③해야 메모리·브라우저·BlackHole 을 재서 허브·시험 기계로 쓸지 정합니다. |
| D4 | OCI Tailscale 설치·접근 규칙 | ①새로 설치하는 곳은 OCI 한 곳이고 승인은 오빠 손이 필요합니다. ②같은 계정 tailnet 에 넣고, 서버는 키 만료를 꺼서 조용히 끊기지 않게 합니다. ③접근 규칙은 «우리 기계끼리 ssh 만» 으로 시작해도 될까요? 추천: 예. |
| D5 | 전송 방식 | ①추천은 일반 ssh(Tailscale 위). 이미 oci 에서 되고 원인 찾기 쉽습니다. ②Tailscale SSH 는 키가 필요 없지만 콘솔 설정에 기댑니다. ③나중에 바꿔도 호출부는 안 바뀌게 설계했습니다. |
| D6 | 원격(OCI)으로 먼저 보낼 일·CLI 설치 귀속 | ①추천: 메모리 큰 pi/opencode 나노(쓰고 닫는 일회성)와 읽기 전용 조사. ②브라우저 시험은 Mac mini 로. ③OCI 에는 claude·pi·codex 가 없어 설치가 먼저인데, 그 로그인·키를 누구 자격으로 둘지(op develop 볼트 경유 추천)는 오빠 결정입니다. |
| D7 | jarvis 서비스(8080) | ①OCI 의 jarvis 서비스는 지금 내려가 있는 것으로 보입니다. ②이번 범위에 «살리기»는 없습니다. ③넣을지만 알려 주세요(추천: 넣지 않음). |
| D8 | 원격 브라우저 화면을 허브에서 라이브로 보기 | ①보안을 위해 원격 기계로 «포트 터널»은 기본으로 막았습니다. ②대신 원격에서 찍은 스크린샷·로그를 가져와 봅니다. ③라이브로 봐야 할 때 터널 전용 열쇠를 하나 더 만들지 정하면 됩니다(추천: 지금은 안 만듦). |
| D9 | 마이크 권한 확인 방식 (두 맥) | ①맥은 마이크 권한 목록을 프로그램이 못 읽게 막아 둡니다. ②그래서 정식 시험 전에 «마이크 확인용 녹음»을 한 번 돌려 소리가 들어오면 확인된 것으로 칩니다. ③추천: 이 방식(오빠 손 0) — 두 번 연속 소리가 안 들어올 때만 오빠께 각 맥 설정 화면 확인을 부탁드립니다. |
| D10 | OCI 추론 스택의 구독 인증 파일 | ①OCI 에 헤드룸·cliproxy 를 두려면 구독 로그인 파일을 OCI 에도 놓아야 해서, 비밀이 놓이는 기계가 하나 늘어납니다. ②이 맥과 같은 계정을 쓰면 사용 한도를 나눠 써서 한쪽이 많이 쓰면 둘 다 막힐 수 있습니다. ③어느 계정을 OCI 에 둘지(같은 계정/별도 계정) 골라 주세요 — 추천: 별도 계정, 파일은 op develop 볼트에서만 내려받기. |
| D11 | OCI hermes 를 관리 서비스로 옮기기 | ①OCI 의 hermes 는 지금 «그냥 켜 둔 프로그램»이라 업데이트·재시작 방법이 없습니다. ②관리 서비스로 옮기려면 한 번 껐다가 다시 켜야 해서 잠깐 끊깁니다. ③옮겨도 될까요? 추천: 예(끊김은 몇 초, 옮긴 뒤엔 업데이트 한 줄로 가능). |
| D12 | 기계를 내보낼 때 남은 쪽지 처리 | ①기계 하나를 내보내면(드문 일, 오빠 승인) 그 기계 앞으로 가던 쪽지는 자동으로 옮기지 않고 «보관함»에 모읍니다. ②새로 연 좌석은 빈 우편함으로 시작하고, 보관함 쪽지는 «버림» 또는 «새로 다시 보내기»로 처리합니다. ③처리를 누가 할지 골라 주세요 — 추천: 팀 master 가 처리하고 «옛 기계에 이미 갔을 수 있음» 표시가 붙은 것만 오빠께 묻기. |

## 15. r8 — DA r7-1 대조표 (N1~N3 · 최소 변경)

r8 줄 지도: §3.1 보관함 디렉터리 단위 L73 · §3.4 늦은 성공 표식 L100 · §10.3 inbox isolate L234 · §11-2 그 호스트 안 격리·원자 교체 L271 · §11-3 처분 기록·기한 L272 (실행 순서 L274 · 7일 근거 L275) · P3 L305 (F13·F20·F21).

유지한 것: r6 구조 전체(자동 이관 없음·세대 필터) · r7 의 route 대상 검사·evict 진행 기록 · 장애 범위 = 프로세스 종료 · 결과 모름 = 사람 처분. DA r7-1 에서 Q1·2·4·6 PASS. 새 기능 0 — 기존 단계의 «위치·단위·기한»만 바꿨다.

| 지적 (r7-1) | 반례 | r8 해소 (DA 최소안 채택) · 위치 | 시험 |
|---|---|---|---|
| N1 원격→허브 hard link 불가 · JSONL 삭제 중단 시 다른 행 손실 (`existing_save_fault_unrelated_B_lost=True`) | isolate 가 다른 파일시스템으로 link · `_save` truncate 중단 | 격리는 **그 호스트 안에서만**(원격 = `quarantine-local/`, 허브 = `quarantine/`) · 허브로는 건수·seq 목록만(본문 전송 0 → 단절에도 원본 보존) · JSONL 은 우편함 잠금 안 **`.tmp` 완성 → `os.replace`**, 기존 `_save` 미사용 · 중단 지점별 결과 명시 · 원격 격리본은 잔재(처분 계약 밖) (§11-2 ⓑ · §10.3 isolate) | P3 F13(원격 격리 위치·응답 단절·JSONL 재작성 중 종료 시 다른 행 보존) |
| N2 enqueue 후 중단 + `late` → 강제 재계획 → new_mid 변경 두 통 (`late_changed_replan_resend_count=2`) | 고정 단위가 계획 파일 | 고정 단위 = **원본 mid 의 처분 기록 `disp.json`** · 첫 부작용 전에 생성(link · 있으면 기존 것) · 재계획·재실행은 기록의 new_mid 만 · `LATE_CHANGED` 는 기록 생성 전(부작용 0)에만 멈춤, 시작된 처분은 마무리 + «중복 가능» 결과 (§11-3 ⓑⓒ) | P3 F20(복합: enqueue→종료→late→재계획→재실행 = n1 한 통) |
| N3 14일 묘비 청소 뒤 같은 계획 재실행 → 재소비 (`late_same_plan_mid_is_new_to_dedup=True`) | 처분 재실행 기한 없음 | **불변 기한 선택**: `disp.created_at` + 7일 밖이면 새 전송 0, `DISP_EXPIRED` 로 사람에게 반환 · 기한 안 재실행은 첫 enqueue 묘비(≥14일)에 걸려 DUP — 부등식을 §11-3 «왜 7일이면 충분한가»에 명시 · `quarantine/<mid>/` 는 시간 청소 대상 아님 | P3 F21(15일 시계 앞당김·청소 후 재실행 = 전송 0) |
| (메모) `late` 표식이 처분 이동과 따로 놀 수 있음 | 표식 먼저 → 이동 → 중단 | 보관함 항목 = **디렉터리 1개**(`msg`·`late`·`disp.json`) · 처분 = 디렉터리 rename 1회 → 표식·기록이 함께 이동 (§3.1 · §3.4) | P3 F20 |

운영 문서(`DESIGN-multihost-ops-ux-20261021.md` «계획 계약»)도 같은 계약(처분 기록이 고정 단위 · 7일 기한 · 원격 격리본은 잔재)으로 맞췄다.

이전 판정 대조(요약): r2-1 → r3 · r3-1 → r4 구조 · r4-1 → r5 · r5-1 → r6(자동 이관 제거) · r6-1 → r7(JSONL 범위·route 대상·evict 재개·처분 mid) · r7-1 → r8(위 3건). 오빠 추가 요구: #2998 → §1·§9·P0·P6·D9 / #3009 → §8.1·P5a·D10·D11.

남은 [가정] (설치 후 확인): Tailscale 코디네이터 장애 시 기존 연결 유지 · 서버 노드 키 만료 비활성 · Linux `lsof -c`·`ps eww` · `restrict,pty,command=` 의 Ubuntu 22.04(OpenSSH 8.9) 동작 — P1 `--keys` 가 실측 · 같은 파일시스템 안 `link`·`rename`(디렉터리 포함)·`os.replace` 의 APFS/ext4 원자적 가시성 — APFS 는 §16 실측 A 로 확인(디렉터리 새 이름 rename 중간 상태는 A2 대기), ext4 는 P3 F1·F13·F19·F20 이 실측(머신 장애 내구성은 범위 밖) · headroom/cliproxy linux/arm64 빌드 존재 — P5a 착수 전 확인.

## 16. 실측 증거 — 가정이 실측으로 바뀐 것 (실측 A · `measured-a-fs.md` · APFS · 이 맥 로컬 1회 실행)

구조 변경 0. 아래는 r8 이 기대는 파일시스템 가정을 실측 A 결과로 대조한 것이다. ext4(OCI)·원격·전원 차단은 실측 A 범위 밖이다.

| 설계가 기대는 연산 (r8 줄) | 실측 A 항목 · 수치 | 판정 | 설계 영향 |
|---|---|---|---|
| 파일 `.tmp` 완성 → `os.replace` — hosts/seats 저장(L268), evict·reserve 진행 기록(L267·L271), JSONL 재작성(L271 ②), 카운터(L106) | 1-1: 30,068 관찰 중 missing/empty/torn 0 · 1-6 원자: SIGKILL 200/200 부분 상태 0 | **[실측] 확인** | 없음 |
| `link(tmp, 새 이름)` — deliver(L83)·보관함 격리 파일(L271 ①) | 1-2: 이미 있는 이름이면 EEXIST 200/200 · link→replace 1000회 이상 0 | **[실측] 확인** — 설계는 link 를 «없는 이름 만들기 + 있으면 DUP» 로만 쓴다(L83 «대상이 있으면 실패 = DUP») | 없음. 덮어쓰기용으로 쓰는 곳 0 |
| 기존 `_save` 꼴(open «w» 후 쓰기) | 1-6 비원자: `truncated` 직후 SIGKILL 100/100 torn · 보존행 median 58/500 | **[반증]** — DA r7-1 N1 반례가 실측으로 재현 | r8 은 이미 이 경로를 쓰지 않는다(L271 «기존 `_save` … 는 쓰지 않는다»). 단일 모드의 기존 `_save` 는 범위 밖 기존 결함 → 하네스 카드 근거 |
| 디렉터리 «같은 이름 교체»·2단 swap | 1-3: 비어 있지 않은 대상 위 rename ENOTEMPTY 200/200 · 2단 swap 부재 창 68.1% · 부분 목록 35/158,935(≈0.02%) | **[반증]** | **r8 은 이 연산을 쓰지 않는다** — 디렉터리 rename 은 전부 «없는 새 이름»으로만: `quarantine/.tmp-<mid>/ → quarantine/<mid>/`(L73 ③) · `quarantine/<mid>/ → disposed/<mid>/`(L274 ⓕ, 직전 ⓐ 가 `disposed/<mid>/` 존재를 먼저 봐 `ALREADY`). 대상이 우연히 있으면 ENOTEMPTY 로 **실패**하지 덮어쓰지 않는다(1-3) — 안전한 쪽 |
| 디렉터리 rename **새 이름으로** 1회의 중간 상태 | 실측 없음 | **[실측 A2 대기]** | 공백으로 명시. A2 는 «관찰자 프로세스가 새 이름 rename 1000회 동안 출처·대상 동시 부재/동시 존재·부분 목록»을 센다 |
| 디렉터리 fsync | 1-4: 가능 · median 22.9 µs (파일 `F_FULLFSYNC` 7.7 ms·p95 50 ms) | **[실측] 확인** | 보장 범위는 프로세스 종료(§3.6)라 필수 아님 · 붙여도 비용 ≈ 0 → 구현 때 link·rename 뒤에 붙여도 됨. `F_FULLFSYNC` 는 쓰지 않는다 |
| 기존 로컬 recv 동시 2개 | 1-5: 이중 소비 15/100 · 유실 0 (`ft-mbox.py` L585–615 조회·소비 잠금 분리) | **[반증]** — 기존 결함 | r8 의 호스트 간 경로는 rename 소비(L88)라 이 함수를 쓰지 않는다. 기존 결함 카드(§3.3)의 근거 수치로만 쓴다 |
| 같은 디렉터리를 바꾸는 중의 목록(readdir) | 1-3: 동시 rename 중 부분 목록 ≈0.02% | **[실측] 주의** | 목록을 보고 판정하는 곳: recv 의 `inbound/` 훑기(L88) · evict 의 «outbound 가 비면 done»(L268). 둘 다 우편함 잠금 안이고, **그 디렉터리를 바꾸는 다른 작업도 전부 같은 잠금 안**이면 동시 변경이 없어 부분 목록의 전제가 없다. 확인 결과 L100 의 forwarder 성공 rename(`outbound → routed-done`)만 잠금 여부가 적혀 있지 않았다 → **구현 규칙: 그 rename 도 허브 우편함 잠금 안**(잠금 안 네트워크 0 규칙과 충돌 없음 — 배달 응답을 받은 «뒤» 로컬 rename 1회). recv 쪽은 놓친 파일이 다음 recv 에 잡힐 뿐 유실이 아니다 |

정리: r8 이 쓰는 파일 연산은 전부 실측으로 확인됐고, 반증된 두 가지(디렉터리 같은 이름 교체·2단 swap, 비원자 `_save`)는 r8 에서 쓰지 않는다. 남은 공백은 «새 이름 디렉터리 rename 중간 상태»(실측 A2) 하나와 ext4(OCI, P3 착수 때)다.
