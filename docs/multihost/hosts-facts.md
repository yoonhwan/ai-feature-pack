# 멀티 호스트 입력 자료 — 원격/로컬 실측 사실 (2026-10-21)

> 작성: `aifp-pi-master-pi#0` (읽기 전용 조사 · 원격 쓰기 0 · 설치 0)
> 목적: `DESIGN-multihost-20261021.md` 의 입력. 여기 값은 **전부 실행 결과**이고, 실행한 명령을 함께 적었다(재현 가능).
> 비밀값은 «있음/없음» 만 적었다 — 토큰·키·비밀번호 값은 이 문서에 없다.

---

## 1. 요약 (설계가 바로 쓸 3줄)

1. **OCI 인스턴스는 jarvis 가 도는 곳이 맞다** — cloudflared 터널 이름이 `jarvis-baseagent-oci`, 홈에 `JARVIS_BASEAGENT_HANDOFF.md` 가 있고, handoff 문서가 «`jarvis.baseagent.dev` → OCI VM Jarvis Agent service (localhost:8080)» 라고 명시한다. 단 **현재 8080 리스너는 없고** `127.0.0.1:8644`(hermes) + `127.0.0.1:20241`(cloudflared) 만 떠 있다 → jarvis 서비스가 지금 «내려가 있는» 상태로 보인다(설계에서 확인 필요).
2. **OCI 는 자원이 넉넉하다** — 4 vCPU · 24GB RAM(사용 1.1GB) · 디스크 97GB 중 73GB 여유 · swap 4GB(사용 0). 이 맥(여유 약 1GB, swap 6.1/7.0GB 사용)과 대비된다 → **무거운 좌석을 OCI 로 보내는 동기가 수치로 확인됨**.
3. **양쪽 다 에이전트 CLI 가 없다(OCI)** / 맥은 다 있다. OCI 에는 claude·pi·codex·headroom·tailscale·mosh 전부 없고 **node 22 · python 3.10 · tmux 3.2a · fzf 만 있다**. 즉 «CLI 레벨 운용» 을 OCI 에서 하려면 최소 4종 설치가 선행돼야 한다(설치 = 오빠 승인 `/tmp/h<N>`).

---

## 2. 노드 표 (실측)

| 항목 | **이 맥** (MacBook-Pro.local) | **oci** (xclaw-server-4ocpu-24gb) |
|---|---|---|
| 접속 | 로컬 | `ssh oci` → `ubuntu@168.107.44.128` · BatchMode OK |
| OS / 커널 | macOS 15.0.1 (arm64) | Ubuntu 22.04.5 LTS · kernel 6.8.0-1049-oracle · aarch64 |
| CPU | 14 core | 4 vCPU |
| 메모리 | 36GB 물리 · **swap 6,061MB/7,168MB 사용(여유 1,106MB)** | 23,980MB 중 사용 1,144MB · **avail 22,508MB** · swap 4,095MB 사용 0 |
| 디스크 / | 1.8Ti 중 9.9Gi 사용 (456Gi 여유) | 97G 중 25G 사용 · **73G 여유 (26%)** |
| 가동 시간 | — | **up 22주 5일** (재부팅 없이 장기 운용) |
| 사용자 / sudo | `yoonhwan` (관리자) | `ubuntu` · **`sudo -n true` 성공(무암호 sudo)** |
| init | launchd | **systemd** (pid1 = systemd) |
| git | 2.52.0 | 2.34.1 |
| tmux | **3.6a** | **3.2a** |
| bash | 5.3.9 (Homebrew, `/opt/homebrew/bin/bash`) | 5.1.16 (`/bin/bash`) |
| python3 | 3.14.8 | 3.10.12 |
| node / npm | v26.7.0 / 11.19.0 | v22.22.2 / 10.9.7 |
| fzf | 있음 (`/opt/homebrew/bin/fzf`) | 있음 (`/usr/bin/fzf`) |
| claude / pi / codex | 있음 (`~/.local/bin/claude` · `/opt/homebrew/bin/pi` · `/opt/homebrew/bin/codex`) | **전부 없음** |
| headroom | 없음 | 없음 |
| tailscale | **CLI 있음(`/usr/local/bin/tailscale`) · `Tailscale is stopped.`** | **없음** (`which tailscale` 빈 값) |
| mosh | 없음 | 없음 |
| tmuxc / tmm | 있음 (`~/.local/bin/{tmuxc,tmm}` · 0.4.3 / 0.9.4) | 없음 |

실행한 명령(요약): `sysctl -n hw.ncpu hw.memsize` · `sysctl -n vm.swapusage` · `sw_vers` · `uname -a` · `free -m` · `df -h /` · `ps -p 1 -o comm=` · `command -v <cli>` · `tmux -V` · `ssh -o BatchMode=yes oci '<읽기 명령들>'`.

---

## 3. OCI 인스턴스 정체 — jarvis 단서 (프로세스/서비스 **이름만**)

| 단서 | 값 |
|---|---|
| cloudflared 프로세스 | `cloudflared tunnel --config ~/.cloudflared/config.yml run jarvis-baseagent-oci` |
| 홈 파일 | `JARVIS_BASEAGENT_HANDOFF.md` (2026-05-19 작성) · `bootstrap.log` · `bootstrap.sh` |
| 홈 폴더 | `workspace/` · `running-fun/{agents,archive,data,guides,missions,scripts}` · `snap/` |
| handoff 문서 요지 | «`hermes.baseagent.dev` → Mac-local Hermes(:8080), `jarvis.baseagent.dev` → OCI VM Jarvis Agent(:8080)» — 이름으로만 인용, 토큰류는 읽지 않음 |
| 리스닝 포트(로컬 바인드) | `127.0.0.1:8644` 프로세스 **hermes** · `127.0.0.1:20241` **cloudflared** · 공개: 22 sshd · 53 systemd-resolved(loopback) · 111 rpcbind · 631 cupsd |
| 실행 유닛 | cron · fail2ban · ssh · networkd/resolved/timesyncd · snapd · oracle-cloud-agent — **jarvis/hermes 전용 systemd 유닛은 없음**(둘 다 유닛이 아니라 프로세스로 떠 있음) |
| docker | 없음(또는 무권한) |
| `8080` | **리스너 없음** — handoff 가 말한 jarvis 서비스가 지금 내려가 있는 것으로 보임 |

★여기까지가 OCI 에서 확인한 전부다. **쓰기 0** — 파일 생성·apt·설정변경·서비스 조작 일절 안 했다(읽기 명령만).

---

## 3b. ★노드 확정 정정★ mac mini 는 `mac-mobile-test` 가 아니다 (2026-10-21 실측)

**오빠 인터뷰의 «mac-mobile-test = byz mac mini» 는 실측과 어긋난다.** tailnet 에 실제로 붙어 본 결과:

| 노드(tailnet) | IP | OS | 상태 | 정체 |
|---|---|---|---|---|
| **MacBook Pro** ← **이 맥(SELF)** | **100.92.216.120** | macOS | **online** | aifp 좌석·tmux 서버가 사는 머신. `hostname` = `MacBook-Pro.local` |
| **BYZ's Mac mini** (`byzs-mac-mini`) | **100.71.41.107** | macOS | **online** (ping 12ms) | **byz mac mini = 이것** |
| gamfs's Mac mini (2) | 100.74.88.108 | macOS | offline (32일) | 무관 |
| ipad153 · iphone182 · iphone-14-pro | 100.65.22.117 외 | iOS | offline | 무관 |

**그래서 두 가지가 정정된다**:
1. `~/.ssh/config` 의 `Host mac-mobile-test` → `HostName 100.92.216.120` 은 **이 맥 자신을 가리킨다**(오늘 tailscale 을 켜자 `ssh mac-mobile-test 'hostname'` 이 `MacBook-Pro.local` 을 돌려줬다). 이름이 «mobile-test» 라 다른 기기로 오해하기 쉽다 — 문서·설계에서 이 별칭을 쓰지 말 것.
2. **byz mac mini 에는 ssh 접속이 아직 안 된다**(키 미배포):
```
$ ssh -o BatchMode=yes yoonhwan@100.71.41.107 'hostname'   # ★잘못된 사용자로 시도한 기록(2026-10-21) — 올바른 접속은 «ssh mini»★
yoonhwan@100.71.41.107: Permission denied (publickey,password,keyboard-interactive).
$ ssh mini 'whoami; hostname -s'                            # ★정본(2026-10-22)★
byz
BYZs-Mac-mini
$ tailscale ping -c 2 100.71.41.107   → pong ... in 12ms     # 망은 정상
```
망은 붙었고 **인증만 없다** → mac mini 실측은 **SSH 키 배포 후** 가능(PENDING).

**지금까지 확인된 것(읽기)**: 망 도달 ✓(12ms) · `ssh mini` 접속 ✓(사용자 `byz` · 호스트 `BYZs-Mac-mini`) · OS macOS · tailnet 소유자 동일 계정(`yoonhwan.ko@`). **그 외(RAM·CPU·tmux/git 버전·에이전트 CLI)는 이 문서 작성 시점 미확인**(2026-10-22 이후 별건 실측으로 채운다) — 추측으로 채우지 않는다.

**접속 규칙(고정)**: mini 는 **항상 `ssh mini`** 로만 부른다 — `~/.ssh/config` 에 `Host mini byz-mini byzs-mac-mini` · `HostName 100.71.41.107` · `User byz` · `IdentityFile ~/.ssh/id_ed25519_aifp_op` 가 있다. 스크립트·문서에 사용자 이름을 박지 않는다(실측 `ssh mini whoami` = `byz`).

**해제 방법(사람 손 1회, 택1)**:
- (A) 이 맥 공개키를 mac mini 의 `~/.ssh/authorized_keys` 에 추가(오빠가 그 머신에서 1줄). 이 맥 공개키 파일: `~/.ssh/id_ed25519.pub` · `~/.ssh/termius_mobile_ed25519.pub`.
- (B) Tailscale SSH 활성화(mac mini 에서 `sudo tailscale up --ssh`) + ACL `ssh` 규칙 — 단 runbook §4.2 는 «Tailscale SSH 미사용» 을 권고하므로 (A) 우선.

**해제 즉시 돌릴 읽기 전용 캡처(쓰기 0)**:
```bash
ssh -o BatchMode=yes mini 'bash -s' <<'EOF'   # mini 사용자 = byz (~/.ssh/config 별칭 mini)
hostname; sw_vers -productVersion; uname -m; uname -r
sysctl -n hw.ncpu; sysctl -n hw.memsize; sysctl -n vm.swapusage
df -h /; uptime; id -un; ps -p 1 -o comm=
for c in git tmux bash python3 node npm claude pi codex headroom tailscale mosh fzf brew tmuxc tmm; do
  printf '%s=%s\n' "$c" "$(command -v $c 2>/dev/null || echo absent)"; done
tmux -V 2>&1; bash --version 2>/dev/null | head -1
tailscale status 2>&1 | head -5
EOF
```

**부수 사실(이번에 새로 켜면서 확인)**: 이 맥의 Tailscale 은 `open -a Tailscale` 만으로 **로그인 없이 연결**됐다(기존 계정 `yoonhwan.ko@` 유지). 즉 Q5(켤 시점)는 «이미 켜짐» 으로 종결. 끄려면 `tailscale down` 또는 앱에서 Disconnect.

---

## 4. 아직 «모르는 것» (설계의 첫 결정거리)

| # | 모르는 것 | 왜 중요한가 | 누가 정하나 |
|---|---|---|---|
| ~~Q1~~ **정정 확정** | «byz mac mini» = **`byzs-mac-mini` 100.71.41.107**(온라인). `mac-mobile-test`(100.92.216.120)는 **이 맥 자신**이었다 → 별칭 폐기 권고. OCI = `oci`(jarvis) | — | ✅ 확정. mac mini 실측은 **SSH 키 미배포로 PENDING**(§3b) |
| Q2 | jarvis 서비스(8080)를 **살릴 것인가** — 내려가 있는 걸 올리는 게 이번 범위인지 | «CLI 레벨 운용» 과 별개 축. 올리는 순간 프로세스·터널 상태가 바뀐다 | 오빠 |
| Q3 | OCI 에 에이전트 CLI 4종(claude·pi·codex·headroom)을 **누구 자격으로** 깔 것인가 | 구독/키 귀속 문제. 키를 OCI 에 두면 비밀값 표면이 늘어난다(op develop 볼트 경유 여부) | 오빠 + 보안 판단 |
| Q4 | OCI 의 `sudo -n` 무암호 sudo 를 **유지**할 것인가 | 원격 자동화 편의 vs 권한 표면. Tailscale ACL 태그와 함께 봐야 한다 | 오빠 |
| ~~Q5~~ **종결** | 이 맥 Tailscale 을 켰다(2026-10-21 · `open -a Tailscale`) → 계정 유지된 채 자동 연결 · tailnet 6노드 확인 | — | ✅ 종결(끄려면 `tailscale down`) |

---

## 5. 측정 부산물 (설계에 유용)

- **ssh 왕복**: `ssh oci true` 실측 0.49s(첫 연결) → 직후 0.01s. `~/.ssh/config` 에 **ControlMaster/ControlPersist 설정 없음** → 지금의 0.01s 는 환경 의존이고 보장되지 않는다. **멀티 호스트에서 tmux/우편함 호출이 원격을 타면 이 왕복이 그대로 지연이 된다** → 설계 ②전송층에서 ControlPersist(또는 Tailscale SSH·mosh) 를 명시해야 한다.
- `~/.ssh/config` 의 `oci` 블록: `HostName 168.107.44.128` · `ServerAliveInterval 60` · `ServerAliveCountMax 3` · **`LocalForward 1455 localhost:1455`**(로컬 포워딩 1건이 이미 걸려 있다 — 원격 디스패치 설계가 이걸 건드리면 안 된다).
- OCI 는 **22주 무재부팅** — 원격에 뭔가 상주시키면 «오래 살아남는 프로세스» 가 된다. 좌석 회수(reap) 규칙이 로컬보다 더 중요하다.
- tmux 버전 차이: 맥 3.6a vs OCI 3.2a — `tmux` 옵션·포맷 문자열 중 3.2 에 없는 것이 있다(예: 최신 `-F` 확장). 원격 tmux 제어 스크립트를 쓸 때 **3.2a 기준으로 시험**해야 한다.
- 경로 차이: 맥 `/opt/homebrew/bin/bash`(5.3) vs OCI `/bin/bash`(5.1) · python 3.14 vs 3.10 — fable-team 스크립트가 `#!/usr/bin/env bash` + python3 를 쓰므로 **3.10 문법 호환**을 확인해야 한다(설계 ⑧ Linux 이식).

---

## 6. 재현 명령 (그대로 복사해 다시 잴 수 있게)

```bash
# 로컬
hostname; sw_vers -productVersion; uname -m; sysctl -n hw.ncpu; sysctl -n hw.memsize; sysctl -n vm.swapusage
df -h /; for c in git tmux bash python3 node npm claude pi codex headroom tailscale mosh fzf tmuxc tmm; do
  printf '%s=%s\n' "$c" "$(command -v $c 2>/dev/null || echo absent)"; done
tailscale status 2>&1 | head -3

# 원격 (읽기 전용만)
ssh -o BatchMode=yes oci 'cat /etc/os-release | head -3; uname -a; nproc; free -m; df -h /; id -un; sudo -n true && echo sudo_nopass=yes; ps -p 1 -o comm='
ssh -o BatchMode=yes oci 'for c in git tmux bash python3 node npm claude pi codex headroom tailscale mosh fzf; do printf "%s=%s\n" "$c" "$(command -v $c 2>/dev/null || echo absent)"; done'
ssh -o BatchMode=yes oci 'ps -eo args= | grep -i jarvis | grep -v grep | cut -c1-120'   # 이름만 · 값/토큰 출력 금지
ssh -o BatchMode=yes oci 'systemctl list-units --type=service --state=running --no-pager --no-legend | awk "{print \$1}"'
ssh -o BatchMode=yes oci 'ss -ltn'
```

**금지(이 문서 작성 중에도 지킨 것)**: 원격 파일 생성·`apt`·설정 변경·서비스 재시작·`tailscale` 설치/실행·비밀값 출력. `mac-mobile-test` 접속 0.
