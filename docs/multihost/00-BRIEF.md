「너는 ai-feature-pack 전용 팀의 팀장이다. 팀 구성, 역할 분배, 작업 우선순위를 네가 알아서 판단하고 진행해라. 사용자에게는 되돌리기 어려운 결정이나 승인이 필요한 것만 물어봐라.」 (2026-10-20 aifp 팀장 발주 원문)
「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 계획 기획팀 발주. 우선 byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스가 있는데 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli  레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 tmm, tmuxc, fable-team에 멀티 인스턴스(네트워크) 기능을 구축하는 기획, da 팀 발주. 필요 나노워커도 선투입」 (오빠 2026-10-21)
골의 어느 축: 멀티 호스트 운용 기획 — 닫는 증거 = `docs/multihost/DESIGN-multihost-20261021.md` 초안 + DA 판정 + 오빠 결정 목록(AskUserQuestion 용 3줄씩) 커밋 sha.

# 멀티 호스트 기획 지시서 (aifp-worker-master-claude#1 → aifp-multihost-arch-claude#0)

## 네 일
설계 문서 1장 `docs/multihost/DESIGN-multihost-20261021.md` (이 워크트리 `.worktrees/multihost-plan`, 가지 `docs/multihost-plan-20261021`). 코드 수정 0 · 원격 호스트 쓰기 0 · 설치 0. 큰 한 방이 아니라 «단계» 로 쪼갠다(첫 단계는 읽기 전용으로 증명 가능한 것).

## 이미 실측한 사실 (2026-10-21, 내가 직접 확인)
| 노드 | 정체 | 사실 |
|---|---|---|
| 이 머신 | `MacBook-Pro.local` | aifp 작업·tmux 서버·모든 좌석이 여기. Tailscale CLI(`/usr/local/bin/tailscale`) 설치돼 있으나 «Tailscale is stopped». 메모리 swap 6.1/7.0GB 사용 — 여유 1GB |
| `oci` | ubuntu@168.107.44.128, Linux aarch64, 호스트명 `xclaw-server-4ocpu-24gb` | ssh 접속됨(BatchMode), tmux 있음, **tailscale 없음**. 이 인스턴스가 jarvis 가 도는 곳인지 **미확인** |
| `mac-mobile-test` | 100.92.216.120 (= 이미 Tailscale 대역) | 이미 망 안에 있는 Mac. BYZ Mac mini 인지 **미확인** |
- 오빠가 말한 «byz mac mini» 가 위 어느 것인지 지금은 모른다 → 설계에 «노드 확정» 을 첫 결정으로 넣어라(내가 오빠께 인터뷰로 묻는다).
- 단일 호스트 결합점 조사 4건(pi 읽기 전용 나노가 만든 표 · 인용 5곳은 내가 소스와 대조해 맞음): `docs/multihost/scout-tmuxc.md` · `scout-tmm.md` · `scout-ft.md` · `scout-linux.md`(Linux 이식 · 작성 중이면 곧 생김).
- 핵심 결합: 파일 우편함 `ft-mbox.py`(flock) · 상태 디렉터리 `ft-lib.sh` · 나노 워크트리 `ft-nano-spawn/close` · tmux 호출이 전부 로컬 소켓(tmuxc `core/bin/tmuxc`) · `pgrep/ps` 로컬 · 스냅샷 `~/.tmuxc/snapshots` · launchd + `/opt/homebrew/bin/bash`(맥 전용).
- `tmuxc-snapshot.py:552` 가 이미 `socket.gethostname()` 을 기록하지만 아무도 안 쓴다 → 출발점.

## 설계에 반드시 담을 12칸
①호스트 모델(이름·역할·능력: 브라우저 가능 여부 · 메모리) ②전송층 비교(ssh over Tailscale / Tailscale SSH / mosh / tmux 소켓 포워딩) + 추천 1개 ③우편함(파일 flock → 원격 enqueue / 호스트별 shard + 병합 / 브로커) 장단과 추천 ④`seats.json` 의 `host` 필드와 라우팅 ⑤워크트리·깃(공유 원격 기준, 원격 호스트에서 clone/fetch) ⑥tmm HOST 열 ⑦tmuxc `--host` 디스패치 래퍼 ⑧Linux 이식(launchd→systemd, Homebrew 경로) ⑨브라우저 필요한 시험의 이관 방식 ⑩보안(Tailscale ACL·태그·인증키 보관은 op develop 볼트 · 비밀값 출력 0) ⑪실패 모드(망 끊김·호스트 다운 때 좌석/우편함 정합 · split-brain) ⑫단계별 닫는 증거 + 오빠 결정 목록.

## 반드시 지킬 것
- ★호스트가 1개일 때 지금 동작이 «문자 단위로 불변» 이어야 한다★(회귀 0). 멀티 호스트는 켜는 스위치.
- 사람 손이 필요한 건 설계에 명시: Tailscale 로그인 승인(브라우저), OCI·Mac 설치. 설치는 내가 `/tmp/h<N>` 한 줄 스크립트로 만들어 오빠께 드린다 — 너는 임의 설치 금지.
- 하네스(BYZ) 소유 파일은 건드리지 않는다. fable-team 은 번호 직렬(1.1.x)이라 구현 단계에서 하네스와 먼저 조율 — 설계는 문서만.
- 메모리: 이 머신이 빠듯하다. 무거운 좌석을 원격으로 보내 분산하는 것이 이 기능의 동기 중 하나다.
- 결정은 글에 쓰지 말고 «오빠 결정 목록» 칸에 쉬운 말 3줄로. 내가 인터뷰로 묻는다. 하위 좌석은 AskUserQuestion 금지.

## 끝나면
설계 초안 커밋 → 나에게 mbox 1줄(sha + 오빠 결정 N건). 그 뒤 내가 DA 좌석을 열어 심사한다(`01-DA-CHARTER.md`).
