「너는 ai-feature-pack 전용 팀의 팀장이다. 팀 구성, 역할 분배, 작업 우선순위를 네가 알아서 판단하고 진행해라. 사용자에게는 되돌리기 어려운 결정이나 승인이 필요한 것만 물어봐라.」 (2026-10-20 aifp 팀장 발주 원문)
「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli  레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
골의 어느 축: 멀티 호스트 운용 기획 — 닫는 증거 = 이 문서 초안 + DA 판정 + 오빠 결정 목록(§13) 커밋 sha.

# 멀티 호스트 설계 — tmuxc · tmm · fable-team (초안 r1, 2026-10-21)

작성 근거: `00-BRIEF.md` + 조사표 4건(`scout-tmuxc/tmm/ft/linux.md`, 소스 대조 완료) + 이 워크트리 소스 직접 확인(`ft-mbox.sh` doorbell·`ft-mbox.py` flock·`seats.json.example`). 코드·원격·설치 0. 표시: **[실측]** 확인함 / **[가정]** 설치 후 확인 필요.

## 0. 한 줄 결론과 원칙

- **결론**: «허브 1대(우편함·명부의 단일 쓰기 지점) + 원격 호스트는 ssh 로 tmux 를 부리는 구조». 새 서버·브로커 0, 기존 파일 우편함과 `flock` 을 그대로 쓴다. 첫 단계는 설치 없이 읽기 전용으로 증명한다.
- **스위치**: `.fable-team/hosts.json` 이 **없거나 `local` 한 줄뿐이면** 모든 코드 경로가 지금과 같다. 새 코드는 전부 `if [ -n "$HOST" ] && [ "$HOST" != local ]` 뒤에만 둔다.
- **7초 룰**: 모든 ssh 호출 `ConnectTimeout=5` + `timeout 7` + 재시도 1회. 크기를 아는 배치(git clone/fetch)만 `min(고정비+7×크기비,70초)`.
- **금지**: 임의 설치·원격 쓰기. 설치는 `/tmp/h<N>` 한 줄 스크립트로 오빠께 드린다.

## 1. 호스트 모델 (①)

`.fable-team/hosts.json` (git 추적 안 함 · 호스트마다 «이름 → 접속·능력»):

| 필드 | 뜻 |
|---|---|
| `name` | 짧은 이름(`book`·`mini`·`oci`). 좌석 이름 충돌 방지 접두사로도 쓴다 |
| `addr` | MagicDNS 이름 또는 100.x (비밀 아님) |
| `os` / `arch` | darwin·linux / arm64·aarch64 |
| `caps` | `browser`(크롬+CDP 가능) · `audio`(BlackHole 등 오디오 E2E 가능) · `heavy`(메모리 ≥16GB) |
| `mem_gb` | 배치 판단용 (oci = 24GB **[실측]** 호스트명 `xclaw-server-4ocpu-24gb`) |
| `root` | 그 호스트의 저장소 경로 |

노드 3개 **정정 확정(r2 · 실측 `hosts-facts.md` §3b, 2026-10-21)** — r1 의 «mini = `mac-mobile-test`» 는 틀렸다. `mac-mobile-test`(100.92.216.120)는 **이 맥 자신**이다. **별칭 `mac-mobile-test` 는 문서·코드·hosts.json 어디에도 쓰지 않는다**(`aifp-<name>` 별칭만).

| name | 정체 | addr | caps | 상태 |
|---|---|---|---|---|
| `book` | 이 MacBook-Pro.local (= 옛 별칭 mac-mobile-test) | 100.92.216.120 | browser·audio | Tailscale **켜짐(online)** · 메모리 여유 ≈1GB(swap 6.1/7.0GB) **[실측]** |
| `mini` | BYZ Mac mini = tailnet 이름 `byzs-mac-mini` | 100.71.41.107 (user yoonhwan) | browser·audio 추정 · 메모리·CLI **[미확인 — ssh 키 미배포로 실측 PENDING]** | **망 online(ping 12ms) · ssh 인증 없음**(`Permission denied (publickey…)`) |
| `oci` | jarvis OCI = ssh 별칭 `oci` | ubuntu@168.107.44.128 · Ubuntu 22.04 aarch64 · 4 vCPU · 24GB(여유 22.5GB) · 디스크 여유 73G · systemd · 무암호 sudo | heavy (브라우저 없음) | tmux **3.2a**·bash 5.1·python 3.10·node 22 있음 / claude·pi·codex·headroom·tailscale **없음** **[실측]** |

→ **새로 Tailscale 을 설치할 곳 = OCI 한 곳**(맥북은 이미 켜짐, mini 는 이미 망 안). **mini 는 설치가 아니라 «ssh 키 배포 1회(사람 손)»가 선행**돼야 접속·실측이 된다. 브라우저 가능 호스트 = Mac 두 대(`book`·`mini`). jarvis 서비스(8080)가 현재 내려가 있는 것으로 보이나 이번 범위 밖(§14 D7).
- 설계 영향: 원격 tmux 는 **3.2a 기준**으로 시험(맥 3.6a 와 다름) · 원격 python 3.10 문법 호환 · 에이전트 CLI 가 OCI 에 없으므로 «OCI 에서 좌석을 돌리려면» 설치 선행(P5, 키 귀속 = D6).

## 2. 전송층 (②) — 추천: **일반 ssh over Tailscale**

| 안 | 장 | 단 |
|---|---|---|
| **A. ssh over Tailscale(추천)** | oci 는 지금도 `BatchMode` ssh 가 된다 **[실측]** → P0 가 설치 없이 시작. 인증이 OpenSSH 하나(키). `ControlMaster` 로 연결 재사용 | 키 관리를 우리가 한다 |
| B. Tailscale SSH | 키 불필요, ACL 로 통제 | 인증 경로가 둘(ACL+ssh)로 늘고 콘솔 설정 의존 **[가정]**. 장애 시 폴백이 없다 |
| C. mosh | 끊김에 강한 대화형 | 스크립트 호출(명령 1회 실행)에 부적합, UDP 추가 |
| D. tmux 소켓 포워딩 | 원격 tmux 를 로컬처럼 | 소켓 권한·macOS↔Linux 경로 문제, 디버깅 난해 |

→ **A**. 실행 규약: `ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPersist=60 <addr> <cmd>`. 접속 정의는 `~/.ssh/config` 의 `Host aifp-<name>` 별칭 하나로 모은다(전용 키 `id_ed25519_aifp`). 나중에 B 로 바꿔도 호출부는 `aifp-<name>` 별칭만 보므로 영향 없음.

## 3. 우편함 (③) — 추천: **허브 단일 파일 + 원격 «ssh 투입/수령»**

현 구조: `mailbox.jsonl` 한 파일 + `fcntl.flock` + LIFO + per-`to` ring + consume-on-read **[실측 `ft-mbox.py`]**. 이 보장(순서·중복 방지)은 **파일이 하나일 때만** 성립한다. 그래서 파일을 쪼개지 않는다.

| 안 | 정합성 | 비용 |
|---|---|---|
| **A. 허브 단일 + 원격 enqueue(추천)** | `flock` 그대로 → 순서·소비 원자성 유지 | 허브 다운 시 원격 송수신 멈춤 → **스풀**로 완화(§11) |
| B. 호스트별 shard + 병합 | 허브 독립 | 병합 때 중복·순서 뒤집힘·consume-on-read 깨짐 → **회귀·정합 위험 최고** |
| C. 브로커(Redis 등) | 네트워크 정합 | 새 의존 한 점 + 기존 `ft-mbox.py` 의미 재구현 |

동작:
- **send(원격 좌석 → 어디든)**: 원격의 `ft-mbox.sh` 가 «허브 모드»(`FT_HUB=aifp-hub` 환경 있을 때만)면 `ssh hub FT_MBOX_DIR=… ft-mbox.sh send …` 로 위임. 본문은 stdin(명령줄·로그에 안 남김). 메시지에 `mid=<host>-<uuid>` 를 붙여 허브에서 **멱등 거부**(재전송 중복 0).
- **recv(원격 좌석)**: `ssh hub ft-mbox.sh recv <me>` 가 허브 파일에서 소비 → 출력만 원격 pane 에 도착. 소비는 허브에서 일어나므로 중복 수령 불가.
- **doorbell**: 지금은 `pane_of()` 가 **로컬** `tmux list-panes` 로 pane 을 찾고 `send-keys` **[실측 ft-mbox.sh:28-31]**. 수신 좌석의 `host` 가 원격이면 `host_tmux <host> list-panes/send-keys` (§7 디스패치) 로 울린다. 실패해도 본문은 이미 큐에 있으므로 non-fatal(현재 계약과 동일).
- **relay 본문 디렉터리** `/tmp/mbox`(`FT_MBOX_RELAY_DIR`)는 호스트 로컬. 원격 수신자에게는 본문을 인라인(700자 이하) 또는 `ssh hub cat` 경로 지시문으로 전달.

## 4. 명부와 라우팅 (④)

- `seats.json` 항목에 **선택 필드** `"host": "oci"` 추가(없으면 `local`). 기존 파일은 한 글자도 안 바뀐다 **[실측: 현 스키마에 host 없음]**.
- 허브의 `seats.json` 이 단일 정본. 원격은 읽기 전용 사본이 필요 없다(원격 좌석은 허브에 묻는다).
- **세션 이름은 호스트 간 전역 유일**. 이유: tmm·ft 가 이름을 유일 키로 쓴다 **[실측 scout-tmm: `=NAME`·dead_row·tabcur]**. 규칙 `byz-<팀>-<역할>-<에이전트>#N` 은 그대로 두고, 같은 이름이 두 호스트에 생기는 것을 `ft-name-lint` 에 **host 간 충돌 검사**로 추가(구현 단계).
- 라우팅 함수 하나: `host_of <session>` → seats.json `host` (없으면 `local`). 모든 `tmux`/`pgrep` 호출부는 이 값으로 §7 디스패치를 탄다.

## 5. 워크트리·깃 (⑤)

- 정본은 공유 원격(origin). 원격 호스트는 **자기 디스크에 clone**하고 나노 가지는 거기서 만든다. `git -C $ROOT worktree add` 가 로컬 경로를 가정하는 지점 **[실측 ft-nano-spawn.sh:95,137-140]** 은 `--host` 일 때 `ssh <host> git -C <root> …` 로 대체.
- 결과 회수는 **git push 한 길**. 원격 나노는 완료 시 가지를 origin 에 push → 허브가 `git ls-remote` 로 sha 확인 후 랜딩. (파일 직접 복사 0)
- `ft-nano-close` 의 `$ROOT/.worktrees/v65-*`·HEAD 검사 **[실측 :30-38,104-105]** 는 `--host` 일 때 `ssh <host> git rev-parse HEAD` 가 `git ls-remote origin <branch>` 와 같은지로 대체. 같지 않으면 닫지 않는다(미푸시 작업 유실 방지).
- `.env`·심링크·비밀은 **전송하지 않는다**. 원격은 env 주입(op develop → 그 호스트 로컬 서비스 토큰)으로만 얻는다(§10).
- 원격 가지 정리는 지금 규칙(브랜치 삭제 HIL, 워크트리 정리 = nano-close 경로)을 그대로 따른다.

## 6. tmm HOST 열 (⑥)

- **켜짐 조건**: hosts.json 에 호스트가 2개 이상일 때만 열이 생긴다. 1개면 행 문자열이 **바이트 동일**(회귀 0).
- 행 키: 지금 field 2 = 세션명. 멀티일 때 `host<US>session`(0x1f)로 바꾸고 `{2}` 소비처(preview·attach·cursor·`TMM_CUR`)가 분해 후 호출 **[실측 scout-tmm]**. 단일 모드에선 `host` 가 비어 기존 문자열 그대로.
- 표시: 행 맨 앞 **2~3자 약칭**(`hu`·`oc`), 폭 ≤58 규칙 준수 **[실측 AGENTS.md 언급, scout-tmm]** — 약칭이 넘치면 좁은 폭에선 헤더에만 표시.
- 스캔: 호스트당 **ssh 1회 일괄**(세션 목록 + capture-pane + pgrep 결과를 원격 쉘이 한 번에 내놓음), 호스트끼리 병렬, 느린 호스트가 판을 막지 않게 `timeout 7` → 실패 시 `HOST<TAB><TAB>UNREACHABLE` 행(침묵 누락 금지).
- **dead 뷰 오판 방지**: `dead_tsv`(tmm:843)·`tmm-dead-scan.py:131` 의 «살아 있나» 판정은 로컬 한정이라, 원격 호스트가 UNREACHABLE 이면 «죽음»이 아니라 «모름»으로 표시. 모든 호스트의 live 이름 합집합으로 제외.
- 캐시 키: `tmm:96` 의 `socket_path` 키에 host 를 포함.

## 7. tmuxc `--host` 디스패치 (⑦)

- 현재 `core/bin/tmuxc` 는 호출부가 직접 `tmux …`/`pgrep …` 를 부른다(조사표 약 30곳). **순수 구조 변경 커밋 먼저**(Tidy First): 모든 호출을 `host_tmux ARGS…` / `host_sh CMD` 함수로 감싼다.
  - `HOST` 가 비었거나 `local`: `exec tmux "$@"` — **인자열이 이전과 같다**.
  - 그 외: `ssh <별칭> tmux "$@"` (인자는 `printf %q` 로 인용).
- 회귀 증명: `tmux`/`pgrep`/`ps` 를 argv 기록 스텁으로 바꾸고, 대표 명령(open·send·kill·list·capture·attach·snapshot) 실행 시 **전/후 argv 기록 diff = 0**. 이것이 P2 의 닫는 증거.
- 표면: `tmuxc --host oci open|send|kill|list|attach` + 환경 `TMUXC_HOST`. `attach` 만 `ssh -t`. `list -a` 는 호스트 팬아웃 + host 열.
- 스냅샷: `SNAP_DIR` 은 호스트별 하위(`~/.tmuxc/snapshots/<host>/`), `tmuxc-snapshot.py:552` 가 이미 기록하는 `gethostname()` 을 처음으로 소비해 복원 시 host 로 필터.
- 홈 의존 경로(`~/.claude.json`·`serena bridges`·`claude-hr.sh`)는 «원격에서 실행되는 명령은 원격 홈을 본다»가 자연 성립하므로 디스패치만 되면 별도 작업 없음 — 단 원격에 같은 스크립트가 **설치돼 있어야** 한다(P5).

## 8. Linux 이식 (⑧)

조사 **[scout-linux]** 의 «진짜 깨지는 곳» 이 정확히 이 목록(구현 단계에서 호스트가 linux 인 경우에만 필요, 맥 단일은 무영향):

| 위치 | 고침 |
|---|---|
| `ft-nano-spawn.sh:148` `sed -i ''` | `sed -i.bak` 후 .bak 삭제 (양쪽 호환) |
| `ft-nano-close.sh:125,226,232` · `ft-mbox.sh:78,79` unguarded `stat -f` | 기존 가드 패턴 `stat -f … \|\| stat -c …` 로 통일 |
| `ft-press-gate.sh:91,143` BSD `date -r/-j` | `date -d` 폴백 (tmm:346-347 의 기존 가드 패턴 재사용) |
| `tmuxc:391` `/opt/homebrew/bin/uvx`, `ft-nano-close.sh:52` lsof/tmux 경로 | `command -v` |
| `ft-tick*` launchd | **systemd user unit** `ft-tick.service/.timer` + `loginctl enable-linger`(비로그인 유지). 설치 스크립트는 OS 분기 |
| `tmm-dead-scan.py:139` `lsof -c` | Linux lsof 플래그 확인 후 분기 **[가정]** |

원칙: 맥에서의 동작은 «가드 추가»로만 바뀐다(기존 맥 분기 문자열 유지). 테스트: `test/` 에 맥 결과 불변 스냅샷.

## 9. 브라우저 필요한 시험의 이관 (⑨)

- `caps: browser` 호스트가 시험 실행 호스트. 시험 나노는 거기서 열리고(§5 방식) 러너·크롬·CDP 는 **그 호스트 로컬**에서 돈다(원격 CDP 를 허브로 끌어오지 않는다 — 지연·보안).
- 오디오 E2E(BlackHole)는 **호스트당 시스템 전역 1개** → 지금의 «오디오 press 순차» 규칙을 «**호스트별 순차**»로 일반화. 서로 다른 호스트면 동시 가능 — 이것이 분산의 이득.
- 포트: 지금의 `38301~38399` 슬롯 규칙을 호스트마다 독립 적용(호스트 간 충돌 없음). 허브에서 봐야 할 때만 `ssh -L` 임시 포워딩.
- 결과 증거(스크린샷·로그)는 원격 `docs/…` 에 쓰고 git push 로 회수. 측정 조작 금지(임의 Redis·DOM 주입) 규칙은 원격에서도 동일 — 기존 e2e 러너 그대로.
- Mac mini(`mini`)를 브라우저 시험 호스트로 쓰는 것은 **ssh 키 배포 후 P0 실측(메모리·chrome·상시 가동)을 보고** 정한다. 그 전엔 `book` 이 유일한 브라우저 후보지만 메모리가 빠듯하다.

## 10. 보안 (⑩)

| 비밀 | 저장 | 새는 길 차단 |
|---|---|---|
| Tailscale 인증키(auth key) | **1Password `develop` 볼트** (kskill 금지) | 설치 h 스크립트가 `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op read` 로 읽어 **파일/표준입력**으로만 `tailscale up` 에 전달(`--auth-key=file:` 지원 여부 설치 전 확인 **[가정]**). 명령줄·쪽지·pane 출력 0. 1회용·단기 만료 키 |
| ssh 개인키 `id_ed25519_aifp` | 각 호스트 `~/.ssh` (0600), 공개키만 상대에 등록 | 원격 `authorized_keys` 에 `restrict` + `command="ft-remote-gate"` 로 **허용 명령 목록**(tmux·git·ft-* 만) |
| 서비스 토큰 | op develop → 호스트 로컬 env | 워크트리로 복사 0 |

- Tailscale ACL: 좌석 호스트에 `tag:aifp`, 허용은 `tag:aifp ↔ tag:aifp` 의 22/tcp 만. 오빠 개인 기기는 별도 태그. ACL 편집은 콘솔(사람) **[결정 D3]**.
- 서버 노드는 **키 만료 비활성**(만료되면 조용히 끊김) — 콘솔 설정 **[가정]**.
- 로그: ssh `-v` 금지, `ft-remote-gate` 가 명령 **이름만** 기록(인자·본문 0). 쪽지 본문에 비밀 금지 규칙은 기존 그대로.
- 원격 호스트는 «남의 기계처럼» 취급: 허브 쓰기 권한(우편함)은 §3 의 send/recv 두 명령으로만 열린다.

## 11. 실패 모드 (⑪)

| 사건 | 동작 | 복구 |
|---|---|---|
| 원격→허브 망 끊김 | 원격 `ft-mbox send` 는 **로컬 스풀**(`~/.ft-spool/*.msg`, mid 포함)에 쌓고 «지연됨» 출력. recv 는 «허브 불통» 표시 | 재연결 시 스풀 flush(허브가 mid 로 멱등 거부) |
| 허브→원격 망 끊김 | 해당 호스트 좌석 행을 **UNREACHABLE** 로 표시(죽음 아님). doorbell 실패는 non-fatal | 접속 복구 후 자동 정상 |
| 원격 호스트 다운 | tmux 서버째 사라짐. 좌석은 UNREACHABLE→(호스트 재기동 후 tmux 없음) | 사람이 `host-evict <host>`(HIL) 로 명부에서 «불통 좌석» 해제 후 재개/재spawn |
| **split-brain**(같은 좌석 이름이 두 곳에서 살아남) | **자동 재spawn 금지**: UNREACHABLE 좌석의 이름은 `host-evict` 전까지 예약 → 다른 호스트에 같은 이름을 못 만든다 | evict 후에만 새 호스트에 생성. 옛 호스트 복귀 시 `ft-name-lint` 가 중복 탐지 → 옛 쪽 정지(HIL) |
| 명부↔실제 tmux 불일치 | 허브 `seats.json` 정본 + 호스트별 `last_seen`. 판정 근거는 «그 호스트에 직접 물은 결과»만, 캐시 신뢰 안 함 | `ft-host-probe.sh` 재실행 |
| 원격 작업 유실 | 원격 나노는 완료 전 중간 push 를 정례화(`nano close` 가 push 확인 못 하면 닫기 실패) | §5 |

**의존 한 점 (Tailscale)**: 코디네이터 장애 시 **이미 맺어진 WireGuard 연결은 대체로 유지**되지만 신규 연결·키 갱신은 막힌다 **[가정, 일반 동작 · 설치 후 장애 시험 필요]**. 최소 저하 모드 = **단일 호스트 모드로 후퇴**(hosts.json 에서 원격 제거 → 지금과 동일). oci 는 공인 IP ssh 가 이미 되므로(P0 가 이 경로로 증명) tailnet 없이도 oci 만은 유지 가능, 맥은 NAT 뒤라 불가. 즉 «Tailscale 없으면 분산이 멈추지만 허브 단독 운용은 영향 0».

## 12. 되돌림 (DA 헌장 5)

한 호스트 제거: `hosts.json` 에서 줄 삭제 → 그 호스트 좌석은 `host-evict` 후 정리 → 원격 잔재 목록 `ft-host-probe.sh --residue <host>`(읽기 전용): ①tmux 세션 ②`.worktrees/*` ③systemd/launchd 유닛 ④`~/.ft-spool` ⑤authorized_keys 항목. 삭제는 목록을 오빠께 보이고 HIL(`/tmp/h<N>`). 전체 철수 = `hosts.json` 삭제 + 허브 `FT_HUB` 미설정 → 바이트 단위 현재 동작.

## 13. 단계와 닫는 증거 (⑫)

| 단계 | 내용 | 사람 손 | 닫는 증거(명령 1줄) |
|---|---|---|---|
| **P0 읽기 전용** | `ft-host-probe.sh`(신규, 읽기 전용): hosts.json 각 호스트에 ssh 로 `uname -m; tmux -V; git --version; bash --version; free/vm_stat; command -v chrome node` 만 실행해 표 출력. 설치·쓰기 0. 노드 확정 입력 | 없음(oci·book 은 지금 가능, **mini 는 P1② 전까지 `PENDING(no-auth)` 행**) | `bash ft-host-probe.sh --all \| tee` 가 호스트별 1행·종료코드 0 (불통 호스트는 `UNREACHABLE` 행 + 비0) |
| P1 망·접속 | ① **OCI 에만** Tailscale 설치·로그인(book 켜짐·mini 망 안은 이미 완료) ② **mini 에 이 맥 공개키 1줄 배포**(`~/.ssh/authorized_keys`, 전용 키 `id_ed25519_aifp.pub` 권장) ③ ACL 태그·키 만료 끄기 | **오빠: ①OCI 브라우저 로그인 승인 ②mini 에서 공개키 1줄(`! bash /tmp/h<N>`) ③ACL 콘솔** | `tailscale status` 에 book·mini·oci 3노드 online · `ssh -o BatchMode=yes aifp-mini true` rc=0 · `ssh -o BatchMode=yes aifp-oci true` rc=0 (tailnet 주소로) |
| P2 tmuxc 디스패치(구조 변경만) | `host_tmux`/`host_sh` 감싸기, 로컬 경로 argv 불변 | 없음 | argv 기록 스텁 전/후 diff = 0 (골든 테스트 1개) |
| P3 우편함 허브 모드 | `host` 필드, `FT_HUB` 위임 send/recv, 스풀·mid 멱등, doorbell 원격 | 없음 | **격리 우편함 픽스처**(제품 키·제품 우편함 쓰기 0)로 허브↔oci 왕복 N=200: 유실 0·중복 0·순서 보존 |
| P4 tmm HOST 열 | 일괄 스캔·UNREACHABLE·dead 오판 방지 | 없음 | 호스트 1개: 행 출력 `cmp` 동일 · 2개: host 열 + 한 호스트 차단해도 판이 7초 내 응답 |
| P5 원격 나노·Linux | `ft-nano-spawn/close --host`, §8 수정, systemd tick, 원격 스크립트 설치 | **오빠: OCI/맥 설치 h** | 원격 나노 1개 spawn→push→close, 허브에서 `ls-remote` sha 일치 |
| P6 브라우저 시험 이관 | caps 라우팅, 호스트별 오디오 순차 | mini ssh 키 배포 완료(P1②) 후 mini 실측 확인 | 원격 e2e 러너 1회 통과(기존 러너, trusted 클릭) |

**조율**: `ft-*` 와 fable-team 은 BYZ 하네스 번호 직렬(1.1.x) → P3 이후 구현은 착수 전 하네스(master)와 카드 번호를 먼저 받는다. 이 문서는 문서만.

## 14. 오빠 결정 목록 (인터뷰용, 쉬운 말 3줄)

| # | 결정 | 3줄 |
|---|---|---|
| D2 | 허브(우편함 본거지) | ①지금은 이 맥북인데 메모리 여유가 1GB 입니다. ②Mac mini(`mini`)처럼 항상 켜 두는 기계가 허브가 되면 맥북을 닫아도 연락이 끊기지 않습니다. ③추천: Mac mini(D3 의 키 배포 뒤 메모리·상시 가동을 재 본 다음), 안 되면 맥북 유지. |
| D3 | Mac mini ssh 키 배포 | ①Mac mini(`byzs-mac-mini`)는 망에는 붙어 있는데 ssh 로 들어갈 열쇠가 없어 지금은 못 들어갑니다. ②Mac mini 에서 «이 맥 공개키 1줄 추가»를 오빠가 한 번 해 주셔야 합니다(제가 한 줄 스크립트 `! bash /tmp/h<N>` 를 드립니다). ③해야 메모리·브라우저 가능 여부를 재서 허브·시험 호스트로 쓸지 정합니다. |
| D4 | OCI Tailscale 설치·접근 규칙 | ①새로 설치하는 곳은 OCI 한 곳이고 로그인 승인(브라우저)은 오빠 손이 필요합니다. ②같은 계정(yoonhwan.ko@) tailnet 에 넣고, 서버는 키 만료를 꺼서 조용히 끊기지 않게 합니다. ③접근 규칙(ACL)은 «우리 기계끼리 ssh 만» 으로 시작해도 될까요? 추천: 예. |
| D5 | 전송 방식 | ①추천은 일반 ssh(Tailscale 위). 이미 oci 에서 되고 문제 생기면 원인 찾기 쉽습니다. ②Tailscale SSH 는 키가 필요 없지만 콘솔 설정에 기대게 됩니다. ③나중에 바꿔도 호출부는 안 바뀌게 설계했습니다. |
| D6 | 원격(OCI)으로 먼저 보낼 일·CLI 설치 귀속 | ①추천: 메모리 큰 pi/opencode 나노(쓰고 닫는 일회성)와 읽기 전용 조사. ②브라우저 시험은 P6 에서 Mac mini 로. ③OCI 에는 claude·pi·codex 가 없어 설치가 먼저인데, 그 로그인·키를 누구 자격으로 둘지(op develop 볼트 경유 추천)는 오빠 결정입니다. 마스터·아키 같은 핵심 좌석은 허브에 둡니다. |
| D7 | jarvis 서비스(8080) | ①OCI 의 jarvis 서비스는 지금 내려가 있는 것으로 보입니다. ②이번 멀티 호스트 작업 범위에는 «살리기»를 넣지 않았습니다. ③범위에 넣을지만 알려 주세요(추천: 넣지 않음). |

## 15. DA 헌장 7문항 자가 점검 (심사 전 예상 약점)

1. 회귀: 스위치(hosts.json 없음) + P2 argv diff=0 / 약점: `ft-name-lint` host 충돌 검사 추가는 단일 호스트에서 무동작이어야 함 → 구현 시 시험.
2. 우편함: 단일 파일 유지, mid 멱등 / 약점: 스풀 flush 순서 — LIFO·ring 과 스풀 재전송이 만날 때 시각 의미 — P3 시험 항목.
3. split-brain: 이름 예약 + 자동 재spawn 금지 / 약점: `host-evict` 가 사람 손(의도).
4. 비밀: op develop + restrict 키 / 약점: `--auth-key=file:` 지원 **[가정]**.
5. 되돌림: §12.
6. 의존 한 점: §11 마지막 문단 **[가정]**.
7. 단계: P0 는 설치 0 / 약점: P0 가 ssh 접속을 하므로 «원격 쓰기 0»이지만 `ControlPersist` 소켓은 로컬 `/tmp` 에 생김(로컬 잔재, 정리 대상).
