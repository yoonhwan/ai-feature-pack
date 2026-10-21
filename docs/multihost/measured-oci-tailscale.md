# 실측 — OCI Tailscale 설치·로그인 결과와 «공인 22 거부» 원인 (2026-10-21 23:1x KST)

읽기 전용 조회만 했다(이 맥 → OCI, 전용 키 + 연결 1개). 원격 쓰기 0. 비밀값 0.

## 1. 결과 (h83 설치·로그인)

| 항목 | 값 | 판정 |
|---|---|---|
| 설치 | tailscale 1.104.2 (apt, jammy, arm64) | 완료 |
| 서비스 | tailscaled active · enabled | 완료 |
| tailnet 이름·주소 | `aifp-oci-jarvis` <TS-IP:oci> · 계정 <OWNER-EMAIL> | 완료 (오빠가 Mac mini 브라우저로 승인) |
| 설정 | RunSSH=false · CorpDNS=false (h83 의 `--ssh=false --accept-dns=false` 그대로) | 의도대로 |
| 경로 | `tailscale ping` 5 ms, 직접 경로(<OCI-PUBLIC-IP>:41641) | 양호 |
| tailnet 주소로 ssh | 성공 (전용 키 `oci_chuncheon`, IdentitiesOnly) · 연결 재사용 시 0.09~0.38초 | 완료 |
| 공인 22 | 지금 정상 | — |
| 서버 상태 | 가동 22주 5일 · 여유 메모리 22.4 GB · sshd 22 리스너 2(v4/v6) | 이상 없음 |

h83 의 종료 코드는 rc=4 였지만(로그인 승인 확인이 5분을 넘김) **실제로는 로그인이 끝난 상태**였다. 마무리 확인(tailnet 주소 ssh 왕복)은 이 문서의 표로 대신했다.

남은 콘솔 손(오빠, Tailscale admin → Machines): `aifp-oci-jarvis` 의 «Disable key expiry» · 태그·ACL(tagOwners 정의 뒤).

## 2. «공인 22 Connection refused» 원인 — 확정

| 가설 | 증거 | 판정 |
|---|---|---|
| fail2ban 이 이 맥 IP 를 차단 | `fail2ban.log` 에 이 맥 IP 의 Found/Ban/Unban 0건 · sshd 실패 로그 0건 | **반증** |
| tailscale up 이 방화벽을 건드림 | `tailscale up` 은 22 를 닫는 규칙을 넣지 않음(ts-input 은 tailscale0·41641/udp 허용, 100.64/10 외부 유입 차단) | 무관 |
| **ufw `limit` 규칙** | `22/tcp LIMIT IN` — iptables: 같은 IP 의 NEW 연결이 **30초 안에 6번 이상**이면 `[UFW LIMIT BLOCK]` 로그 후 `REJECT --reject-with icmp-port-unreachable` (= 클라이언트에는 «Connection refused»). ufw.log 에 이 맥 IP 의 `LIMIT BLOCK` 이 11:55~11:59 UTC 18건, 14:07~14:12 UTC 19건 — h83 이 돈 두 구간과 정확히 겹침 | **확정** |

원인 = h83(v1) 이 단계마다 **새 ssh 연결**을 열어(사전점검·설치·버전·상태 폴링 7초 간격…) 30초 안에 6회를 넘겼고, 그동안 같은 IP(이 맥)의 22 접속이 전부 거부됐다. desk(#133090) 가 본 실패도 같은 구간이다. 창은 «마지막 새 연결 후 30초»라 연결 시도를 멈추면 자동으로 풀린다.

## 3. 설계에 주는 사실 (구조 변경 아님)

1. OCI 의 22 는 **새 연결 6회/30초** 상한이 있다 → 호스트 점검·포워더·tmuxc `--host`·tmm 스캔은 **연결 1개를 재사용**(`ControlMaster=auto`, 설계 §2 에 이미 있음)해야 하고, **재시도·병렬 팬아웃도 이 상한을 합산**해야 한다.
2. 거부된 뒤 계속 두드리면 창이 늘어난다 → 점검 스크립트는 22 가 닫혀 있으면 더 두드리지 않고 멈춘다(`h-oci-tailscale-v2.sh` rc=6).
3. tailnet 경로(100.x)는 ufw limit 의 대상이 아니다(`ts-input` 이 tailscale0 를 먼저 허용) → Tailscale 이 붙은 뒤의 운영 경로는 tailnet 주소를 쓰는 편이 안전하다. 공인 22 는 비상 경로로 둔다.
4. 이전 판단(fail2ban 자기 차단 가능성, #3059 직후 보고)은 **틀렸다** — 증거로 철회한다.

## 4. 재현·확인 명령 (모두 읽기 전용)

```
ssh -i ~/.ssh/oci_chuncheon -o IdentitiesOnly=yes <SSH-USER>@<HOST> 'sudo ufw status verbose | grep 22; sudo grep "LIMIT BLOCK" /var/log/ufw.log | tail'
tailscale ping -c 2 <TS-IP:oci>
```
