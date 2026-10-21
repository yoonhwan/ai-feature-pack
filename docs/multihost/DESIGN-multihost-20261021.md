「너는 ai-feature-pack 전용 팀의 팀장이다. 팀 구성, 역할 분배, 작업 우선순위를 네가 알아서 판단하고 진행해라. 사용자에게는 되돌리기 어려운 결정이나 승인이 필요한 것만 물어봐라.」 (2026-10-20 aifp 팀장 발주 원문)
「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli  레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
골의 어느 축: 멀티 호스트 운용 기획 — 닫는 증거 = 이 문서 + DA 판정 + 오빠 결정 목록(§14) 커밋 sha.

# 멀티 호스트 설계 — tmuxc · tmm · fable-team (r3, 2026-10-21)

작성 근거: `00-BRIEF.md` + 조사표 4건(`scout-tmuxc/tmm/ft/linux.md`) + `hosts-facts.md` + `research-nano-1.md`(우편함 잠금 지도·sshd 옵션·tailscale 플래그) + 이 워크트리 소스 직접 확인. 코드·원격·설치 0. 표시: **[실측]** 확인함 / **[가정]** 설치 후 확인 필요.
r3 변경: DA 판정 r2-1 의 HOLD 6건(질문 1·2·3·4·5·7) 해소. 대조표는 §15.

## 0. 한 줄 결론과 원칙

- **결론**: «허브 1대(우편함·명부의 단일 쓰기 지점) + 원격 호스트는 ssh 로 tmux 를 부리는 구조». 새 서버·브로커 0, 기존 파일 우편함과 `flock` 을 쓰되 **원격 수신은 «임대(claim)→확인(ack)» 두 단계**로 바꾼다(§3). 첫 단계는 설치 없이 읽기 전용으로 증명한다.
- **스위치**: `.fable-team/hosts.json` 이 **없거나 `local` 한 줄뿐이면** 모든 코드 경로가 지금과 같다. 새 코드는 전부 `if [ -n "$HOST" ] && [ "$HOST" != local ]` 뒤에만 둔다. 새 필드(`host`·`gen`·`mid`·`lease`)는 **멀티 모드에서만 기록**되므로 단일 모드 파일에는 생기지 않는다.
- **7초 룰**: 배경 호출(우편함 send/claim/ack·스풀 flush·probe)은 `ConnectTimeout=5` + `timeout 7` + 재시도 1회. **화면 경로(tmm 스캔·attach 전 확인)는 재시도 0 · 7초 불변**(하드 룰 12: 실시간 경로는 쪼개고 늘리지 않는다) — 실패는 `UNREACHABLE` 행으로 보이고 다음 새로고침이 다음 시도다. 크기를 아는 배치(git clone/fetch)만 `min(고정비+7×크기비,70초)`.
- **금지**: 임의 설치·원격 쓰기. 설치는 `/tmp/h<N>` 한 줄 스크립트로 오빠께 드린다.

## 1. 호스트 모델 (①)

`.fable-team/hosts.json` (git 추적 안 함 · 호스트마다 «이름 → 접속·능력·상태»):

| 필드 | 뜻 |
|---|---|
| `name` | 짧은 이름(`book`·`mini`·`oci`). 좌석 이름 충돌 방지 접두사로도 쓴다 |
| `addr` | MagicDNS 이름 또는 100.x (비밀 아님) |
| `os` / `arch` | darwin·linux / arm64·aarch64 |
| `caps` | `browser`(크롬+CDP 가능) · `audio`(BlackHole 등 오디오 E2E 가능) · `heavy`(메모리 ≥16GB) |
| `mem_gb` | 배치 판단용 (oci = 24GB **[실측]**) |
| `root` | 그 호스트의 저장소 경로 |
| `state` | `active` · `draining`(새 좌석 금지) · `revoked`(허브 접근 거절) · `retired`(라우팅 제외, 기록 보존) — §11·§12 |

노드 3개 **확정(r2 · 실측 `hosts-facts.md` §3b)** — `mac-mobile-test`(100.92.216.120)는 **이 맥 자신**이다. **별칭 `mac-mobile-test` 는 문서·코드·hosts.json 어디에도 쓰지 않는다**(`aifp-<name>` 별칭만).

| name | 정체 | addr | caps | 상태 |
|---|---|---|---|---|
| `book` | 이 MacBook-Pro.local | 100.92.216.120 | browser·audio | Tailscale **켜짐(online)** · 메모리 여유 ≈1GB(swap 6.1/7.0GB) **[실측]** |
| `mini` | BYZ Mac mini = tailnet 이름 `byzs-mac-mini` | 100.71.41.107 (user yoonhwan) | browser·audio 추정 **[미확인 — ssh 키 미배포로 실측 PENDING]** | **망 online(ping 12ms) · ssh 인증 없음**(`Permission denied (publickey…)`) |
| `oci` | jarvis OCI = ssh 별칭 `oci` | ubuntu@168.107.44.128 · Ubuntu 22.04 aarch64 · 4 vCPU · 24GB(여유 22.5GB) · 디스크 여유 73G · systemd · 무암호 sudo | heavy (브라우저 없음) | tmux **3.2a**·bash 5.1·python 3.10·node 22 있음 / claude·pi·codex·headroom·tailscale **없음** **[실측]** |

→ **새로 Tailscale 을 설치할 곳 = OCI 한 곳**. **mini 는 «ssh 키 배포 1회(사람 손)»가 선행**. 브라우저 가능 호스트 = Mac 두 대. jarvis 서비스(8080)는 내려가 있는 것으로 보이나 범위 밖(§14 D7).
- 설계 영향: 원격 tmux 는 **3.2a 기준**으로 시험 · 원격 python 3.10 문법 호환 · OCI 에서 좌석을 돌리려면 CLI 설치 선행(P5, 키 귀속 = D6).

## 2. 전송층 (②) — 추천: **일반 ssh over Tailscale**

| 안 | 장 | 단 |
|---|---|---|
| **A. ssh over Tailscale(추천)** | oci 는 지금도 `BatchMode` ssh 가 된다 **[실측]** → P0 가 설치 없이 시작. 인증이 OpenSSH 하나(키). `ControlMaster` 로 연결 재사용 | 키 관리를 우리가 한다(§10) |
| B. Tailscale SSH | 키 불필요, ACL 로 통제 | 인증 경로가 둘(ACL+ssh)로 늘고 콘솔 설정 의존. 장애 시 폴백이 없다 |
| C. mosh | 끊김에 강한 대화형 | 스크립트 호출에 부적합, UDP 추가 |
| D. tmux 소켓 포워딩 | 원격 tmux 를 로컬처럼 | 소켓 권한·macOS↔Linux 경로 문제, 디버깅 난해 |

→ **A**. 실행 규약: `ssh -o BatchMode=yes -o ConnectTimeout=5 -o ControlMaster=auto -o ControlPersist=60 <별칭> <cmd>`. 별칭은 용도별 2개(§10 K1·K2) — 호출부는 별칭만 보므로 나중에 B 로 바꿔도 영향 없음.

## 3. 우편함 (③) — 추천: **허브 단일 파일 + 원격 «투입 / 임대·확인»**

현 구조: `mailbox.jsonl` 한 파일 + `fcntl.flock` + LIFO + per-`to` ring + consume-on-read **[실측 `ft-mbox.py`]**. 단 **현 `recv` 는 원자적이지 않다**: 조회 잠금(`ft-mbox.py` L592)과 삭제 잠금(L607 → `_consume` L582)이 분리돼 있고 그 사이(L593–605)에 두 recv 가 같은 seq 를 표시할 수 있다(이중 표시 · 유실은 아님) **[실측 research-nano-1 §1.2 · DA 반례 `concurrent_recv_READ_count=2`]**. 그러므로 «flock 그대로 소비 원자성 유지»는 성립하지 않으며, 원격 수신은 아래처럼 **새 계약**으로 만든다.

| 안 | 정합성 | 비용 |
|---|---|---|
| **A. 허브 단일 + 원격 투입 / 임대·확인(추천)** | 원격 send 는 `send.op` 한 잠금(L454–503) 안에서 mid 중복 검사까지 끝낸다. 원격 수신은 claim(한 잠금 안에서 «고르기+임대 표시»)→ack(한 잠금 안에서 삭제) → 단절·확인 유실에도 재전달 + 수신측 seq 중복 제거 | 허브 다운 시 원격 송수신 멈춤 → 스풀(§3.3) |
| B. 호스트별 shard + 병합 | 허브 독립 | 병합 때 중복·순서 뒤집힘·consume-on-read 깨짐 → 회귀·정합 위험 최고 |
| C. 브로커(Redis 등) | 네트워크 정합 | 새 의존 한 점 + 기존 의미 재구현 |

### 3.1 원격 send (원격 좌석 → 누구에게든)
- 원격 `ft-mbox.sh` 는 `FT_HUB` 환경이 있을 때만 허브 모드. `ssh aifp-hub send <to> <from> --gen <g> --mid <mid> --no-evict` + **본문은 stdin**(명령줄·로그에 안 남김). 받는 쪽은 허브의 `ft-hub-gate`(§10 K1 강제 명령)다.
- `mid = <host>-<gen>-<uuid4>` 는 **원격이 스풀에 쓰기 «전»에** 만든다(같은 메시지는 재전송해도 같은 mid).
- 허브 `send.op` 의 **같은 잠금 안**에서: ①`mid-index.jsonl` 에 mid 가 있으면 `DUP seq=<s>` 를 돌려주고 끝(성공 취급 · 가드·쿨다운보다 먼저 판정) ②없으면 행에 `mid` 필드를 넣어 append + `mid-index.jsonl` 에 `{mid, seq, ts}` append. 기록과 enqueue 가 한 잠금이라 «행은 있는데 mid 기록은 없는» 순간이 없다.
- **mid 보존 기간 = 14일**(`BODIES_TTL_DAYS` 와 같은 값 · 같은 청소 주기 `_prune_bodies`). 원격 스풀 수명은 **7일**로 그보다 짧게 둔다 → 스풀에서 나올 수 있는 모든 재전송이 mid 창 안에 든다. 7일 넘은 스풀은 보내지 않고 `~/.ft-spool/expired/` 로 옮겨 보고.
- **ring 포화**: 지금 send 는 받는 좌석 큐가 `MAX_PER_TO`(10) 를 넘으면 가장 오래된 것을 버리고 `DROPPED` 를 센다(L485–490). 원격발 send 는 `--no-evict` 로 **버리지 않고 `RING_FULL` 로 거절** → 원격은 스풀에 남기고 받는 좌석에 doorbell 만 울린다. 허브 로컬발 send 의 기존 동작(버리고 센다)은 그대로.

### 3.2 원격 recv (원격 좌석이 받기)
- `ssh aifp-hub claim <me> --gen <g> --lease 60`: **한 잠금 안에서** `to==me` 이고 임대가 없거나(또는 만료된) 행을 골라 `lease={id, until, gen}` 을 행에 적고 저장한 뒤 행과 `lease_id` 를 돌려준다. 행은 **지우지 않는다**.
- 원격은 받은 행을 표시하고 seq 를 `~/.ft-spool/seen-<me>` 에 적은 뒤 `ssh aifp-hub ack <me> <lease_id> --gen <g>` → 허브가 **한 잠금 안에서** 그 lease_id 행만 삭제.
- **단절 시나리오**: (a) claim 응답이 원격에 못 닿음 → ack 없음 → 60초 뒤 임대 만료 → 다음 claim 이 다시 준다(유실 0). (b) 표시는 했는데 ack 가 유실 → 같은 행이 다시 오지만 `seen-<me>` 에 seq 가 있어 **표시하지 않고 ack 만** 보낸다(중복 표시 0). (c) 동시 claim 둘 → 잠금 하나 안에서 임대를 적으므로 두 번째는 그 행을 못 고른다.
- 허브 로컬 recv 경로: 행에 `lease` 필드가 있고 만료 전이면 건너뛴다(필드는 멀티 모드에서만 생기므로 단일 모드 출력 불변). **현 로컬 recv 의 L592/L607 분리 결함은 멀티 호스트와 별개인 기존 결함** → 별도 카드(조회+삭제를 한 잠금으로 합치기 · 동시성이 없을 때 출력 바이트 동일)로 하네스에 올린다. 이 설계의 원격 경로는 그 결함에 기대지 않는다.
- relay 전문(L65 옛 `ssh hub cat`): `ssh aifp-hub body <me> <seq> --gen <g>` — 게이트가 `mailbox.log.jsonl`(보낸 행의 추가 전용 사본)에서 그 seq 의 `to==me` 를 확인한 뒤에만 `bodies/<seq>.txt` 를 준다. 임의 경로 `cat` 은 없다.
- `ring`(doorbell 재울림)은 큐를 건드리지 않으므로(`ft-mbox.sh` L337–339, 우편함 잠금 0회) 수신 좌석의 `host` 로 tmux send-keys 를 보내는 전송로만 바뀐다(§3.4).

### 3.3 스풀 (원격 → 허브 불통일 때)
- 원격 `~/.ft-spool/<mid>.msg`(본문+`ts_origin`+to/from/gen). 쓰기 순서: mid 생성 → 스풀 파일 원자 쓰기(`.tmp`→rename) → 전송 시도 → `QUEUED`·`DUP` 면 스풀 파일 삭제.
- **flush 순서 = `ts_origin` 오름차순, 하나씩, 첫 실패에서 멈춤**(`BLOCKED`(가드)·`RING_FULL`·불통이면 남은 것을 다음 틱으로 · `STALE_GEN`/`HOST_REVOKED` 면 `~/.ft-spool/stale/` 로 옮기고 멈춤). 같은 수신자에 대한 생성 순서가 허브 도착 순서와 같다.
- 허브는 도착 시점에 seq 를 매긴다 → recv 의 LIFO 는 «허브 도착 순». 행에 `spooled:1`·`ts_origin` 이 있으면 표시에 `(지연 N초)` 를 붙인다(필드 없는 단일 모드는 표시 불변).
- 발신 가드(`RATE_N` 5건/60초 등)는 그대로 적용 — flush 가 막히면 다음 틱에 이어간다(가드 우회 0).

### 3.4 doorbell
- 지금은 `pane_of()` 가 로컬 `tmux list-panes` 로 pane 을 찾고 `send-keys` **[실측 ft-mbox.sh:28-31]**. 수신 좌석 `host` 가 원격이면 `host_tmux <host> list-panes/send-keys`(§7). 실패해도 본문은 큐에 있으므로 non-fatal(현재 계약과 동일).

## 4. 명부와 라우팅 (④)

- `seats.json` 항목에 **선택 필드** `"host": "oci"`, `"gen": 3`, `"status": "live|reserved|evicted"` 추가(없으면 `local`·세대 검사 안 함). 기존 파일은 한 글자도 안 바뀐다 **[실측: 현 스키마에 host 없음]**.
- 허브의 `seats.json` 이 단일 정본. 원격은 사본을 갖지 않는다. 원격 좌석은 자기 `gen` 을 생성 때 받은 env `FT_SEAT_GEN` 으로 안다(`create_tmux_session` 의 `-e` 주입 — 지금 `FT_SEAT` 를 심는 자리, tmuxc L62).
- **세션 이름은 호스트 간 전역 유일**(tmm·ft 가 이름을 유일 키로 씀 **[실측 scout-tmm]**). 같은 이름의 두 세대가 동시에 «권한»을 갖지 못하게 하는 장치는 §11 의 `gen` 이고, `ft-name-lint` 의 host 간 중복 검사는 «사후 보고»용 보조다.
- 라우팅 함수: `host_of <session>` → seats.json `host`(없으면 `local`). 모든 `tmux`/`pgrep` 호출부는 이 값으로 §7 디스패치를 탄다.

## 5. 워크트리·깃 (⑤)

- 정본은 공유 원격(origin). 원격 호스트는 **자기 디스크에 clone**하고 나노 가지는 거기서 만든다. `git -C $ROOT worktree add` 가 로컬 경로를 가정하는 지점 **[실측 ft-nano-spawn.sh:95,137-140]** 은 `--host` 일 때 `ssh aifp-<host> git -C <root> …` 로 대체.
- 결과 회수는 **git push 한 길**. 원격 나노는 완료 시 가지를 origin 에 push → 허브가 `git ls-remote` 로 sha 확인 후 랜딩. (파일 직접 복사 0)
- `ft-nano-close` 의 HEAD 검사 **[실측 :30-38,104-105]** 는 `--host` 일 때 원격 `git rev-parse HEAD` 가 `git ls-remote origin <branch>` 와 같은지로 대체. 다르면 닫지 않는다(미푸시 유실 방지).
- `.env`·심링크·비밀은 **전송하지 않는다**. 원격은 env 주입(op develop → 그 호스트 로컬 서비스 토큰)으로만 얻는다(§10).
- 원격 가지 정리는 지금 규칙(브랜치 삭제 HIL, 워크트리 정리 = nano-close 경로)을 그대로 따른다.

## 6. tmm HOST 열 (⑥)

- **켜짐 조건**: hosts.json 에 `active` 호스트가 2개 이상일 때만 열이 생긴다. 1개면 행 문자열이 **바이트 동일**.
- 행 키: 멀티일 때 `host<US>session`(0x1f), `{2}` 소비처(preview·attach·cursor·`TMM_CUR`)가 분해 후 호출 **[실측 scout-tmm]**. 단일 모드에선 기존 문자열 그대로.
- 표시: 행 맨 앞 2~3자 약칭, 폭 ≤58 규칙 준수 — 넘치면 좁은 폭에선 헤더에만.
- 스캔: 호스트당 **ssh 1회 일괄**(`ft-host-probe --scan` 한 명령이 세션 목록+capture-pane+pgrep 결과를 함께 출력 · §10 K2 허용 목록 안), 호스트끼리 병렬, 호스트별 `timeout 7` · **재시도 0**(§0) → 실패 시 `HOST<TAB><TAB>UNREACHABLE` 행(침묵 누락 금지).
- **dead 뷰 오판 방지**: `dead_tsv`(tmm:843)·`tmm-dead-scan.py:131` 의 «살아 있나» 판정은 로컬 한정 → 원격이 UNREACHABLE 이면 «죽음»이 아니라 «모름». 모든 호스트의 live 이름 합집합으로 제외.
- 캐시 키: `tmm:96` 의 `socket_path` 키에 host 를 포함.

## 7. tmuxc `--host` 디스패치 (⑦)

- 현재 `core/bin/tmuxc` 는 호출부가 직접 `tmux …`/`pgrep …` 를 부른다(`\btmux ` 60곳 **[실측 grep -c]**). **순수 구조 변경 커밋 먼저**(Tidy First): 모든 호출을 `host_tmux ARGS…` / `host_sh CMD…` 함수로 감싼다.
  - `HOST` 가 비었거나 `local`: **`tmux "$@"`(exec 아님)** — 함수가 tmux 의 종료코드를 그대로 돌려주고 호출자로 **복귀**한다. 예: `create_tmux_session`(tmuxc L53–66)은 `prepare_color_environment`(`tmux set-environment`) → `tmux new-session … || return 1` → `tmux set -wu …` 를 차례로 부르고, `cmd_open` 은 그 뒤 `inject_message` 로 이어간다(L705–706) — 감싼 뒤에도 같은 순서·같은 `|| return 1`·같은 `2>/dev/null || true` 가 그대로 남는다. `host_sh` 도 같다(`"$@"`).
  - 그 외: `ssh aifp-<host> tmux "$@"`(인자는 `printf %q` 인용 · 원격 게이트가 다시 분해 §10). 종료코드는 ssh 가 원격 명령 코드를 전달하는 것을 그대로 쓰고, ssh 자체 실패(255)는 `UNREACHABLE` 로 바꿔 보고.
  - 기존에 의도적으로 프로세스를 끝내는 `exec` 호출(`tmuxc:391` serena 실행 줄)은 감싸지 않는다(tmux 호출이 아님).
- 표면: `tmuxc --host oci open|send|kill|list|attach` + 환경 `TMUXC_HOST`. `attach`(tmuxc L1833 `tmux attach -t`)만 `ssh -t aifp-<host> tmux attach -t …`(K2 의 `pty` 허용 · §10). `list -a` 는 호스트 팬아웃 + host 열.
- **스냅샷 경로는 바꾸지 않는다**: `SNAP_DIR="${TMUXC_SNAPSHOT_DIR:-$HOME/.tmuxc/snapshots}"`(tmuxc L957) 그대로. 원격 호스트의 스냅샷은 «원격에서 실행된 tmuxc 가 원격 홈에 쓴다»로 자연히 분리되므로 허브 쪽 하위 폴더가 필요 없다. 복원 때 `tmuxc-snapshot.py:552` 의 `host` 필드로 거르는 것은 **멀티 모드에서만**, 그리고 `host` 필드가 없는 과거 파일은 «local» 로 취급 → 단일 모드의 저장 위치·과거 파일 탐색(`ls -1t "$SNAP_DIR"/snapshot-*.json` L1128 · `latest.json` L1191·L1611) 불변.
- 홈 의존 경로(`~/.claude.json`·serena bridges·`claude-hr.sh`)는 원격 명령이 원격 홈을 보므로 디스패치만 되면 별도 작업 없음 — 단 원격에 같은 스크립트가 설치돼 있어야 한다(P5).

## 8. Linux 이식 (⑧)

조사 **[scout-linux]** 의 «진짜 깨지는 곳»(호스트가 linux 일 때만 필요, 맥 단일은 무영향):

| 위치 | 고침 |
|---|---|
| `ft-nano-spawn.sh:148` `sed -i ''` | `sed -i.bak` 후 .bak 삭제 (양쪽 호환) |
| `ft-nano-close.sh:125,226,232` · `ft-mbox.sh:78,79` unguarded `stat -f` | 기존 가드 패턴 `stat -f … \|\| stat -c …` 로 통일 |
| `ft-press-gate.sh:91,143` BSD `date -r/-j` | `date -d` 폴백 (tmm:346-347 의 기존 가드 패턴 재사용) |
| `tmuxc:391` `/opt/homebrew/bin/uvx`, `ft-nano-close.sh:52` lsof/tmux 경로 | `command -v` |
| `ft-tick*` launchd | **systemd user unit** `ft-tick.service/.timer` + `loginctl enable-linger`. 설치 스크립트는 OS 분기 |
| `tmm-dead-scan.py:139` `lsof -c` | Linux lsof 플래그 확인 후 분기 **[가정]** |

원칙: 맥에서의 동작은 «가드 추가»로만 바뀐다(기존 맥 분기 문자열 유지). 시험: `test/` 에 맥 결과 불변 스냅샷.

## 9. 브라우저 필요한 시험의 이관 (⑨)

- `caps: browser` 호스트가 시험 실행 호스트. 시험 나노는 거기서 열리고(§5) 러너·크롬·CDP 는 **그 호스트 로컬**에서 돈다(원격 CDP 를 허브로 끌어오지 않는다).
- 오디오 E2E(BlackHole)는 호스트당 시스템 전역 1개 → «오디오 press 순차» 규칙을 «**호스트별 순차**»로 일반화. 서로 다른 호스트면 동시 가능.
- 포트: `38301~38399` 슬롯 규칙을 호스트마다 독립 적용. **포트 포워딩(`ssh -L`)은 쓰지 않는다**(r2 L120 삭제) — 모든 키가 `restrict` 로 포워딩을 막는다(§10). 결과는 원격에서 만든 스크린샷·로그를 git push 로 회수해 본다. 허브에서 원격 화면을 «라이브로» 봐야 할 일이 생기면 그때 별도 키(포워딩 전용)를 추가할지 결정한다(§14 D8).
- 측정 조작 금지(임의 Redis·DOM 주입) 규칙은 원격에서도 동일 — 기존 e2e 러너·trusted 클릭 그대로.
- `mini` 를 브라우저 시험 호스트로 쓰는 것은 ssh 키 배포 후 P0 재실측(메모리·chrome·상시 가동)을 보고 정한다.

## 10. 보안 (⑩) — 키 2종, 용도·방향·허용 동작을 분리

| 키 | 방향·인증 주체 | authorized_keys 줄 (받는 쪽) | 허용 동작 (정확 목록 — 그 밖은 거절) |
|---|---|---|---|
| **K1 우편함 키** `id_ed25519_aifp_mbox_<host>` | 원격 → 허브. 주체 = «그 원격 호스트» (키 1개 = 호스트 1개, 게이트에 `--host` 고정 + 출발지 tailnet IP 고정) | 허브: `restrict,from="<그 호스트 100.x>",command="<허브 root>/…/ft-hub-gate --host <host>" ssh-ed25519 …` | `send`(본문 stdin) · `claim` · `ack` · `body`(자기 앞 seq 의 전문만 §3.2) · `ping`. PTY·포워딩·임의 명령 0 |
| **K2 조작 키** `id_ed25519_aifp_op` | 허브 → 원격. 주체 = «허브» | 원격: `restrict,pty,from="<허브 100.x>",command="ft-remote-gate" ssh-ed25519 …` (`restrict,pty,command=` 는 sshd.8 L700–701 공식 예시 조합 **[실측 research-nano-1 §2.1]**) | `tmux` 하위 명령 {new-session, has-session, list-sessions, list-panes, capture-pane, send-keys, set-environment, set, kill-session, attach-session} · `git -C <root>` {clone, fetch, worktree add/list, rev-parse, status, push} · `ft-host-probe`(--scan·--residue) · `ft-remote-gate spool-export` · (P6) 기존 e2e 러너 진입점 1개. `pty` 는 `attach-session` 때만 의미가 있고, 포워딩은 `restrict` 가 계속 막는다 |

- 게이트는 `SSH_ORIGINAL_COMMAND`(sshd.8 L525–527)를 python `shlex` 로 분해해 위 목록과 «정확히» 맞을 때만 실행한다. 셸 해석 0(메타문자·`;`·`$(...)` 는 그대로 문자열이라 목록과 안 맞아 거절). 로그는 **동작 이름만**(인자·본문 0).
- 키 회수: 각 줄에 `expiry-time`(sshd.8 L547–551)을 두지 않고, 회수는 §11 의 `state=revoked`(허브 게이트가 즉시 거절)로 한다 — 원격 `authorized_keys` 정리는 철수 잔재(§12)로 HIL.
- P0 는 지금 있는 `ssh oci`(ubuntu 기본 키)로 읽기 명령만 쓴다. K1·K2 는 P1 에서 만든다.
- 오빠가 사람 손으로 들어가는 접속(개인 키)은 이 두 키와 별개이고 이 설계가 건드리지 않는다.

| 비밀 | 저장 | 새는 길 차단 |
|---|---|---|
| Tailscale 인증키 | **1Password `develop` 볼트** (kskill 금지) | 설치 h 스크립트가 `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op read … > <0600 임시파일>` → `tailscale up --auth-key=file:<경로>` (**지원 확인 · tailscale 1.102.2 help 원문 [실측 research-nano-1 §3]**) → 임시파일 삭제. 명령줄·쪽지·pane 출력 0. 1회용·단기 만료 키 |
| ssh 개인키 K1·K2 | 만든 호스트 `~/.ssh` (0600), 공개키만 상대에 등록 | 위 표 |
| 서비스 토큰 | op develop → 호스트 로컬 env | 워크트리로 복사 0 |

- `tailscale up` 은 «플래그 완전 집합»을 요구하고 `--accept-dns` 기본값이 true, `--timeout` 기본 0(무한) **[실측 research-nano-1 §3.1]** → 설치 h 는 호스트별 프로파일 한 벌(`--hostname`·`--advertise-tags=tag:aifp`·`--accept-dns=false`·`--timeout=60s`)을 매번 전체로 넘긴다. 원격 ssh 위에서 `--force-reauth` 금지(help 경고 원문).
- Tailscale ACL: 좌석 호스트 `tag:aifp`, 허용은 `tag:aifp ↔ tag:aifp` 의 22/tcp 만. ACL 편집은 콘솔(사람) **[결정 D4]**. 서버 노드 키 만료 비활성은 콘솔 설정 **[가정]**.
- 로그: ssh `-v` 금지. 쪽지 본문에 비밀 금지 규칙은 기존 그대로.

## 11. 실패 모드 (⑪) — 세대(`gen`)로 옛 좌석 권한을 끊는다

| 사건 | 동작 | 복구 |
|---|---|---|
| 원격→허브 망 끊김 | 원격 send 는 스풀(§3.3)에 쌓고 «지연됨» 출력. claim 은 «허브 불통» 표시 | 재연결 시 flush(mid 로 멱등) |
| 허브→원격 망 끊김 | 그 호스트 좌석 행을 **UNREACHABLE**(죽음 아님). doorbell 실패는 non-fatal | 접속 복구 후 자동 정상 |
| claim 뒤 단절·ack 유실 | 임대 만료(60초) 후 재전달 · 수신측 `seen` 으로 중복 표시 0 (§3.2) | 자동 |
| 원격 호스트 다운 | tmux 서버째 사라짐 → 좌석 UNREACHABLE | 아래 evict 절차(사람 승인) |
| split-brain(같은 좌석 이름이 두 곳에서 살아남) | **자동 재spawn 금지**. 아래 절차로만 새 세대를 만든다 | 아래 |

**evict → 새 세대 절차** (허브 `seats.json` 잠금 한 번 안에서 ①②, 순서 고정):
1. `host-evict <host>`(HIL): `hosts[host].state = revoked` · 그 호스트의 모든 좌석 `status = evicted` · 그 좌석들 앞 행의 **만료 전 임대를 해제**(옛 세대가 들고 간 것을 새 세대가 다시 받을 수 있게).
2. `seat-reserve <name> --host <new>`: `gen = 옛 gen + 1`, `status = reserved` 를 **같은 잠금 안에서** 적는다 → 같은 이름을 두 곳이 동시에 예약할 수 없다. spawn 은 `reserved` 좌석에만 하고 `FT_SEAT_GEN=<새 gen>` 을 심은 뒤 `live` 로 바꾼다.
3. **허브 게이트 검사(K1 의 모든 동작)**: `hosts[호출 호스트].state == active|draining` ∧ `seats[seat].host == 호출 호스트` ∧ `seats[seat].gen == 요청 gen` ∧ `status == live`. 하나라도 어긋나면 `HOST_REVOKED`/`STALE_GEN`(rc 6).
4. **옛 세대가 돌아오면**: 그 프로세스의 send·claim·ack·스풀 flush 는 전부 3에서 거절된다. send·flush 본문은 enqueue 하지 않고 허브 `quarantine/<host>-<gen>-<mid>.json` 에 **보존**(삭제 0) → master 에 1줄 보고. 옛 세대는 새 세대 앞 행을 claim 할 수 없다(gen 불일치). 허브의 doorbell 은 seats.json 의 새 host 로만 울린다.
5. 옛 호스트의 tmux 세션·프로세스는 «권한 없는 잔재»로 남고, 정리는 §12 잔재 목록 → HIL. `ft-name-lint` 의 host 간 중복 검사는 이 잔재를 «보고»할 뿐 차단 장치가 아니다(차단은 3).
6. 같은 호스트를 다시 쓰려면 `host-readmit <host>`(HIL) → `state = active`. 옛 좌석은 `evicted` 그대로라 되살아나지 않는다(새로 reserve).

| 사건 | 동작 | 복구 |
|---|---|---|
| 명부↔실제 tmux 불일치 | 허브 `seats.json` 정본 + 호스트별 `last_seen`. 판정 근거는 «그 호스트에 직접 물은 결과»만 | `ft-host-probe.sh` 재실행 |
| 원격 작업 유실 | 원격 나노는 완료 전 중간 push 정례화(`nano close` 가 push 확인 못 하면 닫기 실패) | §5 |

**의존 한 점 (Tailscale)**: 코디네이터 장애 시 이미 맺어진 연결은 대체로 유지되나 신규 연결·키 갱신은 막힌다 **[가정 · 설치 후 장애 시험 필요]**. 최소 저하 모드 = **단일 호스트 모드로 후퇴**(§12 철수 절차 → 지금과 동일). oci 는 공인 IP ssh 가 이미 되므로 tailnet 없이도 oci 만은 유지 가능 **[가정 — K1·K2 의 `from=` 이 tailnet IP 라 이 우회에는 별도 줄 필요]**, 맥은 NAT 뒤라 불가. «Tailscale 없으면 분산이 멈추지만 허브 단독 운용은 영향 0».

## 12. 되돌림 — 한 호스트 철수 순서 (DA 헌장 5)

설정을 먼저 지우지 않는다. **기록 → 차단 → 인계 → 조사 → 라우팅 제거** 순서이고, 각 단계는 허브에서 실행한다.

1. **보존**: `ft-host-retire.sh <host> --record` → `.fable-team/state/host-retire/<host>-<ts>.json` 에 hosts.json 항목 전체(addr·user·root·os), 그 호스트 좌석 목록(name·gen·status), 허브의 그 좌석들 앞 대기 행(seq·from·임대 여부), 그리고 접속되면 원격 쪽 목록(tmux 세션·`.worktrees/*`·가지·systemd/launchd 유닛·`~/.ft-spool` 개수·`FT_HUB` 설정 위치·authorized_keys 의 aifp 줄)을 적는다. 불통이면 원격 칸은 `UNKNOWN` 으로 적고 계속.
2. **신규 작업 차단**: `state = draining` → spawn·reserve 가 그 호스트를 거절.
3. **옛 세대 권한 차단**: §11 의 `host-evict`(`state = revoked`) → 그 순간부터 그 호스트의 send·claim·ack·flush 가 허브에서 거절된다.
4. **미처리 메시지 인계/격리**: 그 좌석들 앞 대기 행 → 새 세대로 reserve 된 좌석이면 그대로 두어 새 세대가 받고, 아니면 `quarantine/<host>-retire-<ts>.jsonl` 로 **옮겨 보존**(삭제 0). 원격 스풀은 접속되면 K2 `ft-remote-gate spool-export` 로 받아 같은 quarantine 에 넣고, 불통이면 1의 기록에 `UNKNOWN` 으로 남긴다(돌아오면 3에 의해 거절·격리됨).
5. **잔재 조사**: 1의 기록을 근거로 `ft-host-probe.sh --residue <host>`(읽기 전용, 접속될 때). 삭제(원격 tmux kill·워크트리·유닛 중지·`FT_HUB` 해제·authorized_keys 줄 제거)는 목록을 오빠께 보이고 기존 HIL(`/tmp/h<N>`). 불통 호스트는 1의 기록으로 나중에 조사.
6. **라우팅 제거**: `state = retired`(hosts.json 줄은 남긴다 — 기록용, 라우팅·tmm 열·probe 에서 제외). 줄 삭제는 5가 끝난 뒤에만.

**완료 선언 조건**: 1의 기록 파일 존재 ∧ `state == retired` ∧ quarantine 건수 보고 ∧ 5의 잔재 목록(또는 `UNKNOWN` 사유) 보고. 설정 삭제만으로는 완료가 아니다.
**전체 철수**(단일 호스트로 후퇴): 모든 원격 호스트에 1~6 → 그 뒤 `hosts.json` 삭제 + 허브 `FT_HUB` 미설정 → 단일 모드 코드 경로(§0 스위치). `lease`·`mid` 필드가 남은 행은 recv 가 그대로 처리한다(만료된 임대는 무시).

## 13. 단계와 닫는 증거 (⑫)

모든 닫는 명령은 **파이프 없이** 결과 파일로 쓰고 종료코드를 그대로 찍는다(`| tee` 가 실패를 가리는 문제 제거). 성공 = 출력 마지막 줄 `rc=0`. 스크립트 이름의 경로는 `feature-pack/fable-team/skill/scripts/`(= `S/`)·`feature-pack/fable-team/test/`(= `T/`)·`feature-pack/tmuxc/test/`·`feature-pack/tmm/test/` 이고, 표의 스크립트는 그 단계에서 «새로 만드는» 것이다.

| 단계 | 내용 | 사람 손 | 닫는 명령 (1줄) | 실패 기준 |
|---|---|---|---|---|
| **P0 읽기 전용** | `S/ft-host-probe.sh`(신규): hosts.json 각 호스트에 ssh 로 `uname -m; tmux -V; git --version; bash --version; free/vm_stat; command -v chrome node` 만 실행 → 호스트별 1행 TSV(`name status …`). status ∈ `OK`·`PENDING_NOAUTH`(ssh 가 publickey 로 거절)·`UNREACHABLE`. 설치·원격 쓰기 0 | 없음 | `bash feature-pack/fable-team/skill/scripts/ft-host-probe.sh --all --expect 'book=OK oci=OK mini=PENDING_NOAUTH' --out docs/multihost/probe-p0.tsv; echo "rc=$?"` | rc≠0 (0 = 모든 호스트가 기대 status · 3 = 하나라도 다름 · 4 = hosts.json 없음/형식 오류). 필수 호스트 = book·oci. mini 는 P1② 전까지 `PENDING_NOAUTH` 가 «정답»이고 OK 도 UNREACHABLE 도 실패 |
| P1 망·접속 | ① OCI 에만 Tailscale 설치·로그인 ② mini 에 이 맥 공개키 1줄 배포 ③ K1·K2 생성·등록 ④ ACL 태그·키 만료 끄기 | **오빠: ①OCI 로그인 승인 ②mini 에서 `! bash /tmp/h<N>` ④ACL 콘솔** | `bash feature-pack/fable-team/skill/scripts/ft-host-probe.sh --all --via tailnet --keys --expect 'book=OK oci=OK mini=OK' --out docs/multihost/probe-p1.tsv; echo "rc=$?"` | rc≠0. `--via tailnet` = 100.x 주소로만 접속 + `tailscale status --json` 에 세 노드 online. `--keys` = K1 로 허브 `ping` 성공 ∧ K1 로 `tmux list-sessions` 시도가 **거절**됨 ∧ K2 로 `ssh -L` 시도가 **거절**됨 |
| P2 tmuxc 디스패치(구조 변경만) | `host_tmux`/`host_sh` 감싸기 (§7, exec 없음) | 없음 | `bash feature-pack/tmuxc/test/host-dispatch-golden.sh; echo "rc=$?"` | rc≠0. 이 시험은 tmux·pgrep·ps 를 «argv+순서 기록» 스텁으로 바꾸고 대표 명령(open·send·kill·list·capture·attach·snapshot save/restore)을 감싸기 «전» 커밋과 «후» 커밋에서 각각 실행해 **①호출 순서 ②각 호출 argv ③tmuxc 종료코드 ④stdout·stderr ⑤스냅샷 저장 경로와 `latest.json` 대상**을 비교. 하나라도 다르면 실패. «전» 골든 파일은 Tidy 커밋 직전에 따로 커밋 |
| P3 우편함 허브 모드 | `host`·`gen` 필드, K1 게이트, send(mid·`--no-evict`)·claim·ack·body, 스풀, 원격 doorbell | 없음 | `bash feature-pack/fable-team/test/mbox-hub-fault.sh --n 200 --transport shim,ssh:oci --out docs/multihost/p3-mbox.tsv; echo "rc=$?"` | rc≠0. **격리 우편함**(임시 `FT_MBOX_DIR` · 제품 우편함·제품 Redis 쓰기 0). 정상 왕복 N=200 에 더해 장애 순서 8종 각각: F1 동시 claim 2 · F2 claim 직후 단절(ack 전) · F3 ack 응답 유실 · F4 같은 mid 3회 재전송 · F5 ring 포화 중 flush(`RING_FULL` → 스풀 유지) · F6 가드 `BLOCKED` 중 flush 순서 · F7 evict 뒤 옛 gen 의 send·claim·ack·flush(전부 `STALE_GEN`/`HOST_REVOKED` + quarantine 보존) · F8 허브 다운 중 send→복구 후 flush. 기대: 유실 0 · 수신측 중복 표시 0 · 수신자별 생성 순서 = 표시 순서 · F7 거절 100% · 단일 모드(hosts.json 없음) recv/send 출력 바이트 동일 |
| P4 tmm HOST 열 | 일괄 스캔·UNREACHABLE·dead 오판 방지 | 없음 | `bash feature-pack/tmm/test/host-col.sh --out docs/multihost/p4-tmm.tsv; echo "rc=$?"` | rc≠0. ①호스트 1개: 행 출력이 기존 골든(`feature-pack/tmm/test/golden`)과 `cmp` 동일 ②호스트 2개 중 하나를 응답 없는 스텁(블랙홀)으로 두고 첫 화면까지 **7초 이내**(화면 경로 재시도 0 · §0) · 막힌 호스트는 `UNREACHABLE` 행 · dead 뷰에 그 호스트 좌석 0 |
| P5 원격 나노·Linux | `ft-nano-spawn/close --host`, §8 수정, systemd tick, 원격 스크립트 설치 | **오빠: OCI 설치 h** | `bash feature-pack/fable-team/test/nano-remote-roundtrip.sh --host oci --out docs/multihost/p5-nano.tsv; echo "rc=$?"` | rc≠0. 원격 나노 1개 spawn(reserve→live, `FT_SEAT_GEN` 확인) → 빈 커밋 push → close. 허브 `git ls-remote` sha = 원격 HEAD · close 뒤 `ft-host-probe --residue oci` 의 그 좌석 tmux 세션 0 · 맥 쪽 §8 불변 스냅샷 동일 |
| P6 브라우저 시험 이관 | caps 라우팅, 호스트별 오디오 순차 | mini ssh 키 배포(P1②) 후 P0 재실측 | `bash feature-pack/fable-team/test/remote-e2e.sh --host mini --runner '<기존 러너 진입점>' --out docs/multihost/p6-e2e.log; echo "rc=$?"` | rc≠0. 러너 진입점은 **P6 착수 때 대상 프로젝트 정본에서 복붙**(지금 모름 — 추측해서 적지 않음). trusted 클릭 경로만 · 측정 조작 0 · 결과 로그 git push 로 회수 |

**조율**: `ft-*` 와 fable-team 은 BYZ 하네스 번호 직렬(1.1.x) → P3 이후 구현은 착수 전 하네스(master)와 카드 번호를 먼저 받는다. §3.2 의 «로컬 recv 잠금 분리» 결함 카드도 하네스로 올린다. 이 문서는 문서만.

## 14. 오빠 결정 목록 (인터뷰용, 쉬운 말 3줄)

| # | 결정 | 3줄 |
|---|---|---|
| D2 | 허브(우편함 본거지) | ①지금은 이 맥북인데 메모리 여유가 1GB 입니다. ②Mac mini 처럼 항상 켜 두는 기계가 허브가 되면 맥북을 닫아도 연락이 끊기지 않습니다. ③추천: Mac mini(D3 의 키 배포 뒤 메모리·상시 가동을 재 본 다음), 안 되면 맥북 유지. |
| D3 | Mac mini ssh 키 배포 | ①Mac mini 는 망에는 붙어 있는데 ssh 로 들어갈 열쇠가 없어 지금은 못 들어갑니다. ②Mac mini 에서 «이 맥 공개키 1줄 추가»를 오빠가 한 번 해 주셔야 합니다(한 줄 스크립트 `! bash /tmp/h<N>` 를 드립니다). ③해야 메모리·브라우저 가능 여부를 재서 허브·시험 호스트로 쓸지 정합니다. |
| D4 | OCI Tailscale 설치·접근 규칙 | ①새로 설치하는 곳은 OCI 한 곳이고 로그인 승인(브라우저)은 오빠 손이 필요합니다. ②같은 계정 tailnet 에 넣고, 서버는 키 만료를 꺼서 조용히 끊기지 않게 합니다. ③접근 규칙(ACL)은 «우리 기계끼리 ssh 만» 으로 시작해도 될까요? 추천: 예. |
| D5 | 전송 방식 | ①추천은 일반 ssh(Tailscale 위). 이미 oci 에서 되고 문제 생기면 원인 찾기 쉽습니다. ②Tailscale SSH 는 키가 필요 없지만 콘솔 설정에 기대게 됩니다. ③나중에 바꿔도 호출부는 안 바뀌게 설계했습니다. |
| D6 | 원격(OCI)으로 먼저 보낼 일·CLI 설치 귀속 | ①추천: 메모리 큰 pi/opencode 나노(쓰고 닫는 일회성)와 읽기 전용 조사. ②브라우저 시험은 P6 에서 Mac mini 로. ③OCI 에는 claude·pi·codex 가 없어 설치가 먼저인데, 그 로그인·키를 누구 자격으로 둘지(op develop 볼트 경유 추천)는 오빠 결정입니다. 마스터·설계 좌석은 허브에 둡니다. |
| D7 | jarvis 서비스(8080) | ①OCI 의 jarvis 서비스는 지금 내려가 있는 것으로 보입니다. ②이번 작업 범위에는 «살리기»를 넣지 않았습니다. ③범위에 넣을지만 알려 주세요(추천: 넣지 않음). |
| D8 | 원격 브라우저 화면을 허브에서 라이브로 보기 | ①보안을 위해 원격 기계로 «포트 터널»을 여는 기능은 기본으로 막아 두었습니다. ②대신 원격에서 찍은 스크린샷·로그를 가져와 봅니다. ③라이브로 봐야 할 일이 생기면 그때 터널 전용 열쇠를 하나 더 만들지 정하면 됩니다(추천: 지금은 안 만듦). |

## 15. r3 — DA r2-1 HOLD 해소 대조표

r3 줄 지도: §0 L10–15 · §3 L53–85(3.1 L63 · 3.2 L70 · 3.3 L78 · 3.4 L84) · §4 L87–92 · §7 L111–119 · §9 L136–142 · §10 L144–164 · §11 L166–189 · §12 L191–203 · §13 L205–219 · §14 L221–231.

| 질문 | r2 지적(옛 줄) | r3 해소 위치 | 요지 |
|---|---|---|---|
| 1 회귀 | L93–95 `exec tmux` 가 호출자를 끝냄 · L98 스냅샷 기본 경로 변경 | §7 첫 항목(`tmux "$@"` exec 아님 · `create_tmux_session` L53–66 순서 보존) · §7 «스냅샷 경로는 바꾸지 않는다» · §13 P2 | 함수가 복귀·종료코드 전달 · `SNAP_DIR` L957 그대로 · 과거 파일은 host 없음=local · P2 가 호출 순서·argv·종료코드·출력·저장 위치 5가지를 전/후 비교 |
| 2 우편함 | L53·57·63 «flock 그대로 소비 원자성» · L62 mid 만으로 recv 장애 미해결 · L141·182 스풀 순서·ring 포화 미명세 | §3 첫 문단(현 recv 분리 결함 명시) · §3.1(mid 를 send 잠금 안에서 · 보존 14일 > 스풀 7일 · `--no-evict`/`RING_FULL`) · §3.2(claim→ack · 단절 (a)(b)(c) · 수신측 `seen`) · §3.3(flush 순서·첫 실패 정지·지연 표시) · §13 P3 F1–F8 | 원격 수신은 임대·확인 두 단계 · 로컬 결함은 별도 카드 |
| 3 evict 뒤 옛 세대 | L143–145 lint→사람 정지로 수습 · L69–72 세대 구분 없음 | §4(`gen`·`status`·`FT_SEAT_GEN`) · §11 evict 절차 1–6 · §13 P3 F7 | 허브 게이트가 host·gen·status 로 옛 세대의 send·claim·ack·flush 를 즉시 거절 · 새 세대는 같은 잠금 안 원자 예약 · 옛 본문은 quarantine 보존 · lint 는 보고용 |
| 4 restrict↔ssh -t·-L | L129 `restrict` 가 PTY·포워딩을 막아 L97 `ssh -t`·L120 `ssh -L` 과 모순 · L129 넓은 명령 목록 vs L135 send/recv 둘 · L65 전문 읽기 | §10 키 2종 표(K1 우편함 = restrict·PTY 0 · K2 조작 = `restrict,pty` · 정확 허용 목록 · 인증 주체·`from=`) · §9(`ssh -L` 삭제 → D8) · §3.2 `body` 동작 | 우편함 권한과 호스트 조작 권한을 다른 키로 분리 · attach 는 K2 의 pty 로 동작 · 포워딩은 모든 키에서 막힘 · 전문 읽기는 자기 앞 seq 만 |
| 5 철수 순서 | L152 hosts.json 접속 정보를 먼저 지움 · tick·FT_HUB·스풀·pending 상태 미정 | §12 1–6 단계 + 완료 선언 조건 + 전체 철수 | 기록→draining→revoked→인계/격리→잔재 조사→retired(줄 보존) · 불통 호스트는 기록으로 나중에 · 삭제는 HIL |
| 7 닫는 명령 | L158 `\| tee` 가 실패 코드를 가림 · PENDING 기준 미분리 · L159–164 문장형 | §13 표(단계마다 명령 1줄 + 실패 기준 칸 · 파이프 0 · `echo "rc=$?"`) · P0 의 status 3종·필수 호스트·종료코드 표 · P3 장애 8종 · P4 7초·재시도 0 · §0 화면 경로 재시도 0 | 모든 단계가 실행 가능한 명령 + 기계 판정 기준 |
| 6 의존 한 점 | PASS | §11 마지막 문단 유지 + oci 공인 IP 우회에 `from=` 줄 필요 [가정] 추가 | — |

남은 [가정] (설치 후 확인): Tailscale 코디네이터 장애 시 기존 연결 유지 · 서버 노드 키 만료 비활성 콘솔 설정 · Linux `lsof -c` 플래그 · K2 `restrict,pty,command=` 의 Linux(OpenSSH 8.9, Ubuntu 22.04) 동작 — P1 `--keys` 시험이 이 마지막 것을 실측한다.
