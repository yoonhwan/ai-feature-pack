# 실측 — OCI 다음 순서 (P5a 착수 전 확인 · hermes 현황 · 콘솔 손 · 키/게이트) — 2026-10-21 23:4x KST

읽기 전용 조회만(연결 1개 재사용 · 전용 키). 원격 쓰기 0 · 비밀값 0(환경 변수는 «이름»만).

## 1. ★정정★ hermes 는 이미 «관리 서비스» 다 — D11 의 전제가 틀렸다

| 항목 | 실측 |
|---|---|
| 관리 방식 | **systemd 사용자 서비스** `hermes-gateway.service` — loaded · **active (running)** · **enabled** |
| 부팅 유지 | `Linger=yes` (로그인 없이도 부팅 때 올라옴) |
| 같은 방식의 이웃 | `cloudflared-jarvis.service` (Cloudflare Tunnel for <DOMAIN>) — 역시 enabled·active |
| 실행 명령 | `…/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace` (사용자 ubuntu · 작업폴더 `~/.hermes`) |
| 버전 | **Hermes Agent v0.15.1 (2026.5.29)** |
| 시작 시각 | 2026-07-28 03:24 (≈ 85일 연속) · 포트 `127.0.0.1:8644` (프로세스 pid 733651 이 리슨) |
| 환경 변수 이름 | `HERMES_HOME` `VIRTUAL_ENV` 등 12개(값 미조회) — systemd 가 넣는 `INVOCATION_ID`·`JOURNAL_STREAM` 가 보여 «유닛으로 뜸» 확인 |
| 하위 프로세스 | 브라우저 자동화 `agent-browser-linux-arm64` (hermes 가 필요할 때 띄움) — 환경 변수 이름에 DISCORD_* 다수 = 디스코드 게이트웨이 용도 |

**의미**: 앞선 pi 조사(«hermes 전용 systemd 유닛 없음 — 프로세스로만»)는 **시스템 유닛만 보고 사용자 유닛(`systemctl --user`)을 안 본 오류**였다. D11(«hermes 를 관리 서비스로 옮기기 — 잠깐 끊김»)의 전제가 사라진다 → **옮길 일이 없다.** 업데이트·재시작 경로는 이미 있다: `systemctl --user restart hermes-gateway`, 업데이트는 hermes 자체 명령(버전 고정 뒤 별도 계획). §8.1 단계 1 의 «기록» 은 위 표로 끝난다.

## 2. P5a 착수 전 확인 — headroom · cliproxy 리눅스 arm64

| 항목 | 이 맥(현역) | OCI 로 가져갈 때 | 판정 |
|---|---|---|---|
| headroom-ai | 0.33.0 (Python 3.12.12, venv `~/.headroom-venv`) | PyPI 최신 0.41.0 — **`manylinux_2_28_aarch64` 휠 있음** (cp310-abi3 → OCI 의 python 3.10.12 에서 설치 가능) | 가능. 단 **같은 0.33.0 으로 고정**해야 함(이 맥과 동작 일치) — 0.33.0 휠의 aarch64 존재는 설치 전 `pip download --only-binary` 로 확인(조회) |
| cliproxy | 현역 실행 파일 `~/.cli-proxy-api/bin/cli-proxy-api` = **로컬 패치 빌드 `8.0.4-haiku55-sonnet55-sol61`** (임베디드 모델 카탈로그에 sonnet-5-5·haiku-5-5·gpt-6.1-sol 직접 추가) | 공식 릴리스 `CLIProxyAPI_7.2.10_linux_aarch64.tar.gz` 있음(8.0.x 도 동일 형식 예상 — 8.0.4 태그는 미조회) | **공식 바이너리를 그대로 쓰면 안 된다** — 카탈로그에 sonnet-5-5 가 없어 `400 unknown provider for model claude-sonnet-5-5`(스킬 함정 #18·#20). OCI 용은 **패치 빌드를 `GOOS=linux GOARCH=arm64` 로 교차 빌드**해 올려야 함 |
| Go 툴체인 | — | OCI 에 go 없음(node·python3 만) | 교차 빌드는 이 맥에서 하고 바이너리만 전송 → OCI 에 go 설치 불필요 |
| 상주 방식 | launchd (`com.cliproxy.api` · `com.headroom.proxy`) | systemd 사용자 유닛 + linger(이미 yes) | 가능(hermes 와 같은 방식) |
| 구독 인증 파일 | 이 맥 | D10 = 같은 계정(오빠 결정) — op develop 볼트에서만 내려받아 0600 | 값 이동 h 는 따로(출력 0) |

⇒ P5a 순서(안): ① 이 맥에서 패치 소스로 linux/arm64 교차 빌드(스킬 절차 #18) + headroom 0.33.0 휠 aarch64 확인 ② OCI 에 바이너리·venv 설치(오빠 승인 h) ③ 인증 파일 배치(op develop) ④ systemd 사용자 유닛 2개 enable ⑤ health(루프백)만 확인. **지금은 ① 의 «어느 소스·어느 패치 커밋인지» 확인이 선행** — 스킬 문서에 빌드 절차는 있으나 소스 위치를 이번에 조회하지 않았다(다음 조회 항목).

## 3. 오빠 콘솔 손 (Tailscale 관리 화면 · 2건 · 쉬운 말)

접속: 브라우저에서 `login.tailscale.com/admin/machines` (<OWNER-EMAIL> 로그인).
1. **키 만료 끄기** — 목록에서 `aifp-oci-jarvis` 줄 오른쪽 «…» 메뉴 → **Disable key expiry**. (서버는 사람이 없으니 키가 만료되면 조용히 끊깁니다. 끄면 안 끊깁니다. 1회로 끝.)
2. **접근 규칙(ACL)** — 왼쪽 **Access controls** 탭. 지금은 건드리지 않아도 됩니다(처음엔 «전체 허용» 상태). «우리 기계끼리 ssh 만» 규칙(D4)은 `tag:aifp` 를 쓰는데, 이 태그는 먼저 같은 화면의 `tagOwners` 에 정의해야 하고, 정의 전에 기계에 태그를 걸면 실패합니다. → **설계 순서: ①키 만료 끄기만 먼저 ②ACL 은 K1·K2 실제 사용 직전에 한 번에(제가 붙여넣을 JSON 을 드립니다).**

## 4. P1 ③ K1·K2 키 + `aifp-gate` 설치 h — 아직 만들 수 없다 (이유)

- `aifp-gate`(원격 입구 스크립트)는 **설계만 있고 구현이 없다**(P1 ③ 은 «설치 h» 이지만 설치할 실물이 아직 없음). 코드 구현은 하네스 번호 직렬(1.1.x)이라 하네스(master)와 카드 번호 조율이 먼저다(설계 §13 조율 줄).
- 또 하나: **허브가 mini 로 확정(D2)** 되어 K2(허브→원격) 개인키는 **mini 에 만들어야** 한다. 지금 h84 가 이 맥에 만든 `id_ed25519_aifp_op` 는 «이 맥이 허브일 때» 의 가정이었다 → mini 허브 전환 시 키 위치 정리가 필요(이 맥은 허브가 아니라 원격 `book` 역할).
- 그래서 지금 할 수 있는 것은 **키 생성 h 만**(실물 설치 제외)인데, 허브 이전(mini)과 맞물려 한 번에 정하는 편이 낫다 → 허브 이전 계획 + 키 위치를 arch#1 이 정리한 뒤 h 를 만든다.

## 5. 다음 조회 목록 (읽기 전용 · 대기)
1. cliproxy 패치 빌드의 소스 위치·교차 빌드 가능 여부(스킬 #18 절차 대조)
2. headroom 0.33.0 의 aarch64 휠 다운로드 가능 여부(`pip download --only-binary=:all: --no-deps headroom-ai==0.33.0 --platform manylinux_2_28_aarch64`)
3. hermes 업데이트 절차(공식 명령·롤백) — 서비스 재시작 시 디스코드 게이트웨이 끊김 길이

## 6. 후속 조회 결과 (2026-10-21 23:5x KST · 읽기 전용)

### 6-1. ★mini 에는 이미 추론 스택이 돌고 있다 — P5a 의 모델이 달라진다
| 항목 | mini (byz) 실측 |
|---|---|
| cliproxy | `~/.cli-proxy-api/bin/cli-proxy-api` (62.5 MB, 10-08 14:20) — launchd `com.cliproxy.api` 가동 · `127.0.0.1:8317` 리슨 |
| headroom | `~/.headroom-venv` · **headroom-ai 0.33.0**(이 맥과 같은 버전) — launchd `com.headroom.proxy` 가동 · `127.0.0.1:8790` 리슨 |
| 근거 | 스킬 함정 #20: «AINA(<SSH-USER>@<HOST>)도 같은 날 동일 바이너리로 교체» — 이 맥의 패치 빌드를 이미 배포해 둔 기계 |

⇒ **OCI 는 새로 만드는 쪽, mini 는 이미 있는 쪽.** mini 가 허브(D2)이므로 «허브가 추론 스택을 이미 가진다»는 이득. OCI 에 같은 스택을 두는 이유(구독 한도 분산·OCI 좌석이 로컬 프록시로 호출)가 D10(같은 계정 확정)과 맞물린다 — 한도는 어차피 한 계정이므로 OCI 스택은 «지연·경로» 이득이지 «한도» 이득이 아니다.

### 6-2. cliproxy 교차 빌드 (OCI 용 linux/arm64)
| 항목 | 값 |
|---|---|
| 빌드 트리 | `~/.claude/jobs/ee330f7a/tmp/cpa` (git 17a65ee5 · go.mod 1.26.0 = 로컬 go1.26.0 일치) · 패치 3개(`patch-catalog-sonnet-5-5` · `patch-catalog-haiku-5-5-full` · `patch-claude-idle-conn-timeout`) 보관 |
| 운영 빌드 플래그 | `-ldflags="-s -w -X main.Version=8.0.4-haiku55-sonnet55-sol61 -X main.Commit=d33f63f8-haiku55-idle -X main.BuildDate=2026-10-08"` · **CGO_ENABLED=1** · darwin/arm64 |
| 교차 빌드의 걸림돌 | **CGO 사용 파일 24개** — 단 대부분 `examples/plugin/*`(빌드 대상 아님). 서버 경로에서는 `internal/pluginhost/*_unix.go` 가 `import "C"` → `GOOS=linux GOARCH=arm64` 교차 빌드에는 **리눅스 arm64 C 크로스 컴파일러**(예: zig cc 또는 `aarch64-linux-gnu-gcc`)가 필요하거나, 플러그인 호스트를 빼는 빌드 태그가 있어야 함 |
| 판정 | 교차 빌드는 «가능 가능성 높음, 미검증» — **가장 안전한 길 = OCI 자체에서 빌드**(go 1.26 설치 필요, OCI 에 go 없음) 또는 **zig cc 교차 빌드**. 실제 빌드는 쓰기이므로 승인 후 별도 단계(시험은 이 맥 /tmp 에서 `go build` 만 — 원격 영향 0) |
| 대안 | 공식 릴리스 `CLIProxyAPI_7.2.10_linux_aarch64.tar.gz`(7.2.x)는 카탈로그에 sonnet-5-5 가 없어 400 — 쓰려면 패치 필요 |

### 6-3. headroom 0.33.0 aarch64
`headroom_ai-0.33.0-cp310-abi3-manylinux_2_28_aarch64.whl` **존재**(PyPI JSON) · requires_python >=3.10 → OCI python 3.10.12 호환. → **0.33.0 고정 설치 가능.**

### 6-4. hermes 업데이트 절차 (OCI)
| 항목 | 값 |
|---|---|
| 설치 방식 | git 체크아웃 `~/.hermes/hermes-agent` (origin = NousResearch/hermes-agent · HEAD 46b2afc56) + venv |
| 공식 업데이트 | `hermes update` — git pull + 의존 재설치. 옵션: `--check`(설치 없이 가능 여부만 조회) · `--backup`/`--no-backup` · `--yes` · `--branch` · `--force` |
| 백업 | `hermes backup`(홈 폴더 zip) · 복원 `hermes import` · 점검 `hermes doctor` |
| 재시작 | 유닛 `Restart=always` · `RestartSec=5` · `ExecStart=… gateway run --replace` → `systemctl --user restart hermes-gateway` 하면 **약 5초 + 기동 시간** 끊김 |
| 권고 순서 | ① `hermes update --check`(읽기) → ② `hermes backup` → ③ `hermes update --yes` → ④ `systemctl --user restart hermes-gateway` → ⑤ `hermes doctor` · 롤백 = `git checkout <이전 해시>` + 재시작 또는 `hermes import` |
