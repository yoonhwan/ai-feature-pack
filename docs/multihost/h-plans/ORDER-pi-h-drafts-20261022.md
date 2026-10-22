골 원문(오빠 2026-10-21): 「… byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … 두곳에 모두 tailscale 설치와 계정 연동으로 연결해 cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관해 작업하고 팀이나 나노 작업등을 분산 분해해서 운영하는 … 멀티 인스턴스(네트워크) 기능을 구축」 · 「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」
골의 어느 축: «두 곳 CLI 로 실제 운용» — OCI·mini 설치 h 초안 3장(트랙 1-2·1-3·2-1). 발주서 `docs/multihost/BRIEF-phase2-operate-20261022.md`.

# 발주 — pi: h 스크립트 초안 3장 (쓰고 바로 닫기)

작업 폴더: `/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan` · 산출은 `docs/multihost/h-plans/` 에만. 기존 `h-oci-tailscale-v2.sh`·`h-mini-ssh-key.sh` 의 틀(가림·rc 규칙·ssh ControlMaster)을 그대로 따른다. 하네스 소유 파일(feature-pack/fable-team·tmuxc·tmm 코드) 편집 0 · 이 스크립트는 «초안»이고 실행은 오빠 `!` 로만(너는 실행하지 않는다 · `bash -n` 까지).

## 사실 (실측 — 이걸로 쓴다, 추측 금지)
- mini: `byz@100.71.41.107` ssh OK · `~/.local/bin`(claude) 은 비로그인 ssh PATH 밖 → `bash -lc` 또는 절대경로 · brew=/opt/homebrew/bin · mini sudo 는 암호 필요 → brew·npm 사용자 설치만 · 이미 headroom 8790 + cliproxy 8317 가동.
- OCI: tailnet `aifp-oci-jarvis` 100.115.169.113 · 사용자 ubuntu · ufw 22번 «같은 IP 새 연결 30초 6회» 상한 → ControlMaster 1개 재사용 · tailnet 주소로만 · node 22 · python 3.10 · tmux 3.2a · aarch64 · claude·pi·codex·headroom·cliproxy 0.
- cliproxy 바이너리(OCI 용): 이 맥 scratchpad `/private/tmp/claude-501/-Users-yoonhwan-Project-ai-feature-pack--worktrees-multihost-plan/83ec5aea-03fd-46fe-a345-58c8273b933f/scratchpad/xbuild/cli-proxy-api-linux-arm64` sha256 `8d5f778176e4beeeaeb70534c921dfc87f1e25eaaba76a836daa2109af982848` (CGO 불필요 · 카탈로그 sonnet-5-5·haiku-5-5·gpt-6.1-sol 확인됨 · `measured-xbuild-cliproxy-20261022.md`). 올릴 때 sha256 재대조 필수.
- headroom: 0.33.0 aarch64 휠 · OCI python 3.10 → venv(`~/.venvs/headroom`) 고정 버전 `pip install headroom-ai==0.33.0` (mini 가동 인자 참고: `--port 8790 --anthropic-api-url http://127.0.0.1:8317 --compress-user-messages --no-code-aware --exclude-tools Bash`).
- 인증: D10 = 같은 계정 · ★1Password `develop` 볼트에서만★ `OP_SERVICE_ACCOUNT_TOKEN="$OP_SERVICE_ACCOUNT_TOKEN_DEVELOP" op … --vault develop` (kskill 금지) · 값 화면·로그 출력 0 · 원격 파일 0600.

## 3장 (각 장 = 한 줄 `! bash /tmp/h<N>` 로 도는 단일 스크립트 · 대화형 프롬프트 0 · 끝에 rc 와 «닫는 증거» 원문 출력)
1. `h-oci-infer-stack.sh` — OCI 에 cliproxy 바이너리(scp+sha256 대조) + headroom 0.33.0 venv + systemd 사용자 유닛 2개(`127.0.0.1` 바인드 · 8317 / 8790) + 인증·config 0600 배치 + 기동 확인(`/health`·`/v1/models` 에 3개 모델 보임). Linger=yes 확인(이미 yes). 실패 시 유닛 stop+원상(백업 후 교체).
2. `h-oci-cli-tools.sh` — OCI 에 claude·pi·codex(npm 사용자 prefix `~/.npm-global`) + tmuxc·tmm(이 리포 파일 복사 · 버전 대조) · `ANTHROPIC_BASE_URL=http://127.0.0.1:8317` 을 OCI 쪽 claude 래퍼에만(전역 export 금지) · 닫는 증거 = `claude -p "ping"`(timeout 7s 상한) rc=0 원문 + `tmuxc open` 좌석 1개 probe→닫기 원문.
3. `h-mini-ops.sh` — mini 에 tmm·pi(이 맥과 같은 버전) 사용자 설치 + 운용 1회: 이 맥에서 ssh 로 mini 의 기존 tmuxc 불러 좌석 1개 열기→probe(모델·헤드룸 경유 8790)→닫기 원문.

## 검증 (너가 하는 것까지)
- `bash -n` 3장 · 각 스크립트가 참조하는 파일·경로 `test -f`(없으면 초안 단계에서 발견) · `grep -nE 'read |sudo |\[Y/n\]'` 로 대화형 0 확인 · 비밀 값 echo 0 확인.
- 끝나면 파일 경로 3개 + 검증 결과 원문 3줄을 `aifp-multihost-master-claude#1` 에 mbox 로 보고하고 **닫는다**(pi 는 쓰고 바로 닫기 · 메모리 이슈).
