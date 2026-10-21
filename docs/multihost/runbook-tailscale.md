# Runbook 초안 — Tailscale 설치·계정 연동 (Linux OCI aarch64 / macOS)

> 작성: `aifp-pi-master-pi#0` (2026-10-21) · **초안이다. 실행 0.**
> 실행은 오케가 `/tmp/h<N>` 한 줄 스크립트로 오빠 승인을 받아 한다.
> `🧑 사람 손` = 브라우저 승인·GUI 조작처럼 에이전트가 대신 못 하는 단계.

---

## 0. 이 문서의 규칙

1. **설치·`tailscale up`·ACL 변경은 이 문서에서 하지 않는다.** 여기 적힌 것은 «무엇을 어떤 순서로» 이며, 실제 실행은 승인 뒤 `/tmp/h<N>`.
2. **인증키(authkey)를 쓰면 보관은 `op` develop 볼트** — 하드 룰 15: `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op … --vault develop`. 값은 출력·커밋·로그에 남기지 않는다.
3. 비밀값이 화면에 보이면 **«있음» 만 보고**하고 값은 옮겨 적지 않는다.
4. `mac-mobile-test`(<TS-IP:book>)는 이 runbook 대상이 **아니다**(정체 확인 중).
5. 노드 확정(Q1: «byz mac mini» 가 어느 노드인지)이 오빠 인터뷰로 정해지기 전에는 **설치 대상 호스트를 확정하지 않는다**.

---

## 1. 목표 상태

```
[ 이 맥 MacBook-Pro.local ] ──tailnet── [ OCI <OCI-HOSTNAME> ]
        (tailscale stopped)                  (tailscale 미설치)
                    └──── 둘 다 tailnet 안, ACL 태그로만 서로 접근 ────┘
```

- 접속은 **공인 IP 22번을 열지 않는다** — tailnet 인터페이스(`tailscale0` / `100.x`)로만.
- 지금 `oci` 는 `<OCI-PUBLIC-IP>`(공인) 로 붙고 있다. tailnet 이 붙으면 `ssh oci-tail` 같은 별칭을 따로 두고 **공인 경로는 유지**(당장 끊지 않는다 — 실패 대비 롤백 경로).

---

## 2. Linux (OCI · Ubuntu 22.04 · aarch64)

### 2.1 설치 — 공식 apt 저장소 (권장) 🧑 사람 손 없음(단 sudo 필요)

```bash
# 1) 패키지 서명키·저장소 등록 (Ubuntu 22.04 = jammy)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list

# 2) 설치 (이미 존재하는 패키지 목록만 갱신 — 업그레이드는 하지 않는다)
sudo apt-get update
sudo apt-get install -y tailscale

# 3) 확인
tailscale version
systemctl is-enabled tailscaled && systemctl is-active tailscaled
```

- 대안(원라이너): `curl -fsSL https://tailscale.com/install.sh | sh` — 편하지만 **스크립트를 그대로 실행**하는 방식이라 우리 규칙상 1안(패키지 저장소)을 우선한다.
- aarch64: Ubuntu jammy 저장소가 `arm64` 를 제공한다(별도 빌드 불필요).
- ★이 인스턴스는 22주 무재부팅 상태다★ 설치 후 `tailscaled` 가 상주 프로세스로 추가된다 → 실패 시 회수 절차(§5)를 먼저 읽고 실행할 것.

### 2.2 로그인 — 두 방식 중 택1

| 방식 | 절차 | 장점 | 단점 |
|---|---|---|---|
| **A. 브라우저 승인** (기본·권장 첫 연결) | `sudo tailscale up --hostname=<이름> --ssh=false` → 출력된 URL 을 🧑 사람이 브라우저에서 열어 로그인·승인 | 인증키를 만들·보관하지 않는다(비밀값 표면 0) | 🧑 사람 손 1회 필요, URL 만료(보통 수 분) |
| **B. 인증키(authkey)** | `op` develop 볼트에서 키를 꺼내 `sudo tailscale up --authkey=…` (**값은 셸 변수로만**, 히스토리·로그 금지) | 무인 자동화·재설치 반복에 유리 | 키가 비밀값 → 볼트 보관·회전 책임 생김 |

**권고**: OCI 는 **A(브라우저 승인) 1회**로 붙이고, 재설치·자동화가 반복될 때만 B 로 전환한다. B 를 쓸 경우 키는 **reusable=false · ephemeral=false · tag 지정(`tag:oci`)** 로 만들고 만료를 짧게(예: 24h) 둔다.

### 2.3 마무리 확인 (읽기만)

```bash
tailscale status            # 자기 노드 + peer 보이면 성공
tailscale ip -4             # 100.x 주소
ip -4 addr show tailscale0 | head -3
ss -ltn | grep -c ':22 '    # sshd 는 그대로 (공인 접속 유지)
```

---

## 3. macOS — ★노드가 셋이다(실측 정정 2026-10-21)

| 노드 | tailnet IP | 상태 | 이 runbook 에서 할 일 |
|---|---|---|---|
| **이 맥** `MacBook-Pro.local` | **<TS-IP:book>** | online(오늘 켬 · 계정 유지) | 이미 망 안 → **확인만**. 설치 0 |
| **byz mac mini** `byzs-mac-mini` | **<TS-IP:mini>** | online · ping 12ms | 이미 망 안 → **확인만**(설치 0) 단 **ssh 키 미배포 = 차단** |
| 무관 | <OTHER-DEVICE> <TS-IP:mini2> · iOS 3대 | offline | 건드리지 않음 |

★주의★ `~/.ssh/config` 의 `Host mac-mobile-test`(`HostName <TS-IP:book>`)는 **이 맥 자신**을 가리킨다(실측: `ssh mac-mobile-test 'hostname'` → `MacBook-Pro.local`). «mobile-test 라는 별도 기기» 로 오해한 채 설계하지 말 것 — 이 별칭은 쓰지 않는 것을 권고.

**mac mini 확인 2줄(읽기만)**:
```bash
tailscale status | grep -i byzs-mac-mini
ssh -o BatchMode=yes <SSH-USER>@<HOST> 'hostname; tailscale status | head -3'   # 지금은 Permission denied(publickey)
```
**차단 해제(사람 손 1회 · 택1)** — (A) 이 맥 공개키를 mac mini `~/.ssh/authorized_keys` 에 추가(권고) · (B) mac mini 에 `sudo tailscale up --ssh` + ACL `ssh` 규칙(runbook §4.2 는 Tailscale SSH 미사용을 권고하므로 A 우선).

### 3. macOS (이 맥 · MacBook-Pro.local · 15.0.1 arm64)### 3. macOS (이 맥 · MacBook-Pro.local · 15.0.1 arm64)

### 3.1 현재 상태 (실측)

- `/Applications/Tailscale.app` 설치돼 있고, CLI 는 심(`/usr/local/bin/tailscale` → 앱 내부 바이너리)으로 잡혀 있다. `tailscale version` = **1.102.2**.
- **동시에 Homebrew formula `tailscale` 1.92.5 도 설치돼 있다**(OSS `tailscaled` 계열). → **두 설치가 공존**하는 상태다. `tailscale status` 는 `Tailscale is stopped.`
- 이 맥은 `sudo -n` 무암호가 **아니다**(sudo 에 암호 필요) → 원격 자동화로 서비스 조작 불가(🧑 사람 손 필요).

### 3.2 어느 쪽을 쓸지 (먼저 정한다 — 둘 다 쓰면 tailscaled 가 충돌한다)

| 선택 | 명령 | 특징 |
|---|---|---|
| **A. App Store 앱 유지**(권장) | GUI 에서 «Connect» 🧑 / CLI `tailscale up` | 이미 설치·로그인 이력 있음. 메뉴바 GUI 로 상태 확인 쉬움. **CLI 는 앱이 켜져 있어야 동작** |
| B. Homebrew OSS 로 통일 | `brew services start tailscale` (root daemon) + `tailscale up` | 완전 CLI/스크립트 친화. 단 **앱과 공존 불가** — 앱 제거 또는 비활성 필요 |

**권고 = A**. 이유: 이미 앱이 깔려 있고 CLI 심이 잡혀 있으며, 이 맥의 tailscale 사용 목적이 «좌석·파일 공유» 이지 데몬 자동화가 아니다. B 로 가려면 앱을 지우는 **되돌리기 어려운 결정**이 선행돼야 하므로 오빠 판정 사항.

### 3.3 켜기 (A 기준) — ★2026-10-21 에 이미 켰다★

`open -a Tailscale` 한 번으로 **로그인 없이** 연결됐다(기존 계정 `<OWNER-EMAIL>` 유지 · 6노드 확인). 다시 켤 일이 생기면 같은 명령이면 된다. 끄기 = `tailscale down` 또는 앱 Disconnect.


```bash
# 1) 앱이 실행 중인지 확인 (실행 중 아니면 먼저 연다)  🧑 사람 손
open -a Tailscale
# 2) 로그인/연결
tailscale up --hostname=<이름>
# 3) 확인
tailscale status | head -5
```

- 이미 계정 로그인 이력이 있으면 `tailscale up` 이 곧바로 연결된다(브라우저 승인 생략될 수 있음).
- 회사/개인 계정이 섞이면 `tailscale switch <account>` 로 계정을 고른다.

---

## 4. 호스트명 규칙 · ACL · 태그 (제안)

### 4.1 호스트명 (MagicDNS 이름)

```
aifp-mac-<역할>      예: aifp-mac-main       (이 맥: 좌석·tmux 서버가 사는 곳)
aifp-oci-<역할>      예: aifp-oci-jarvis     (OCI: jarvis/헤비 좌석)
byz-mac-mini         (오빠가 말한 «byz mac mini» — Q1 확정 뒤에만)
```

- 규칙: **소문자·숫자·`-` 만**, 15자 이내 권장, «역할» 을 이름에 넣는다(tmm HOST 열·좌석 이름과 대조하기 쉽게).
- 기존 이름(`<OCI-HOSTNAME>`)은 **바꾸지 않는다** — `tailscale up --hostname=` 로 tailnet 이름만 새로 준다(호스트 자체 hostname 변경은 다른 스크립트를 깬다).

### 4.2 태그 · ACL 초안

```jsonc
// tailnet policy (초안 — 적용은 오빠 계정 소유자만 가능)
{
  "tagOwners": {
    "tag:aifp-mac":  ["autogroup:admin"],
    "tag:aifp-oci":  ["autogroup:admin"]
  },
  "acls": [
    // ① 에이전트끼리: ssh + tmux 관련 포트만
    { "action": "accept", "src": ["tag:aifp-mac"], "dst": ["tag:aifp-oci:22"] },
    { "action": "accept", "src": ["tag:aifp-oci"], "dst": ["tag:aifp-mac:22"] },
    // ② 사람(오빠)은 전부
    { "action": "accept", "src": ["autogroup:admin"], "dst": ["tag:aifp-mac:*", "tag:aifp-oci:*"] },
    // ③ 기본은 전면 거부 (위 두 줄이 허용 목록)
    { "action": "accept", "src": ["*"], "dst": ["*:*"] }   // ← 이 줄은 «지금 기본값 유지» 용. 좁히려면 삭제
  ],
  "ssh": [
    // Tailscale SSH 는 «쓰지 않는 것» 을 권고(기존 sshd·ssh config 를 그대로 두는 편이 롤백이 쉽다)
  ]
}
```

- **Tailscale SSH(`--ssh`)는 끄는 것을 권고** — 이미 `~/.ssh/config` 에 `oci` 별칭·키·`LocalForward 1455` 가 걸려 있고, Tailscale SSH 를 켜면 인증 경로가 이중화돼 장애 때 원인 파악이 어려워진다.
- 태그를 붙이면 그 노드는 **key expiry 자동 해제 여부**를 정해야 한다(장기 무인 노드는 expiry disable 검토).

---

## 5. 실패 모드 · 롤백 (설치 전에 읽는다)

| 상황 | 증상 | 롤백/복구 |
|---|---|---|
| `tailscale up` 후 ssh 가 끊김(OCI) | 공인 IP 접속은 계속 살아 있어야 정상 — 만약 ACL 로 22 를 막았다면 tailnet 밖에서 못 들어온다 | **공인 22 를 먼저 닫지 않는다**(이 runbook 은 닫지 않는다). 잠겼으면 OCI 콘솔(VNC/시리얼)로 들어가 `tailscale down` |
| 두 설치 공존(mac) | `tailscale` CLI 가 어느 데몬에 붙는지 애매 · status 가 엉뚱 | 앱 기준으로 통일(§3.2 A), brew 쪽은 `brew services stop tailscale` 후 필요 시 `brew uninstall`(🧑 승인) |
| tailscaled 가 OCI 에 상주 | 22주 무재부팅 인스턴스에 프로세스·유닛이 추가됨 | `sudo systemctl stop tailscaled && sudo systemctl disable tailscaled` (설치 자체는 유지) |
| 인증키 유출 의심 | 키로 노드가 추가될 수 있음 | Tailscale admin 에서 **키 revoke** → `op` develop 볼트 항목 회전 → 노드 목록에서 의심 노드 제거 🧑 |
| MagicDNS 로 이름이 안 풀림 | `ssh aifp-oci-jarvis` 실패 | `tailscale ip -4` 로 100.x 주소를 먼저 쓰고, 이름 해석은 나중에(설계 ②전송층에서 이름 의존 금지) |

---

## 6. 실행 계획 (누가 무엇을 — 아직 실행 0)

| # | 단계 | 실행 주체 | 사람 손 | 되돌리기 |
|---|---|---|---|---|
| 1 | Q1 노드 확정(«byz mac mini» 정체) | 오빠 인터뷰 | 🧑 결정 | — |
| 2 | OCI: apt 저장소 등록 + `apt-get install tailscale` | 오케 `/tmp/h<N>` (오빠 승인) | — | `apt remove tailscale` |
| 3 | OCI: `tailscale up --hostname=aifp-oci-jarvis` (방식 A) | 오케 `/tmp/h<N>` | 🧑 브라우저 승인 1회 | `tailscale down` |
| 4 | Mac: `open -a Tailscale` + `tailscale up --hostname=aifp-mac-main` | 오빠 GUI/CLI | 🧑 승인 | `tailscale down` |
| 5 | 태그·ACL 적용 | 오빠(Tailscale admin) | 🧑 | 정책 이전 리비전 복원 |
| 6 | 검증(읽기만): `tailscale status` · `ssh` 왕복 · `ssh oci true` 지연 측정 | 나(pi) | — | — |

**검증에 쓸 읽기 명령(6단계)**

```bash
tailscale status | head -10
tailscale ping <peer> -c 3
ssh -o BatchMode=yes aifp-oci-jarvis 'tailscale status | head -3'   # 이름이 풀릴 때만
/usr/bin/time -p ssh -o BatchMode=yes oci true                      # 왕복 지연(현재 0.49s/0.01s 혼재)
```

---

## 7. 이 문서가 «하지 않은 것»

- 설치·업로드·`apt`·`systemctl` 실행 0
- `tailscale up` 0 · 인증키 발급/조회 0
- ACL 변경 0
- `mac-mobile-test` 접속 0
- 어떤 비밀값도 읽거나 적지 않음
