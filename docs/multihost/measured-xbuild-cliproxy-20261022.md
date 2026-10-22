골 원문(오빠 2026-10-21): 「우리 tmm, tmuxc, tmux, fable-team을 멀티 pc,맥 지원 환경구성으로 업그레이드 … byz mac mini와 jarvis가 돌아가는 oci 클라우드 인스턴스 … tailscale … cli 레벨로 환경을 운용하고 브라우저가 가능한 환경은 테스트도 이관 … 멀티 인스턴스(네트워크) 기능을 구축」 · 「oci쪽에 headroom, cliproxy 부터 연결해줘야겠네.. hermes도 업데이트 지원하고」
골의 어느 축: «OCI CLI 운용 노드» — 발주서 트랙 1-1 (cliproxy 교차 빌드 시험) 의 닫는 증거.

# 실측 — cliproxy linux/arm64 교차 빌드 (2026-10-22, 이 맥 · 원격 영향 0)

## 결론
- **CGO 없이 된다**(`CGO_ENABLED=0`). 이전 문서의 «CGO → C 크로스 컴파일러 필요» 는 틀렸다 → zig·OCI 자체 빌드 불필요.
- 빌드 트리는 `~/.claude/jobs/ee330f7a/tmp/cpa-v804`(base d33f63f8 + 패치 3개: sonnet-5-5 · haiku-5-5/gpt-6.1-sol 카탈로그 · Claude idle 45s). `…/tmp/cpa`(HEAD 17a65ee5)는 다른 베이스라 카탈로그에 haiku-5-5·gpt-6.1-sol 이 없다 — 처음 시험 빌드를 거기서 했다가 대조로 걸러냄.

## 실측값
| 항목 | 값 |
|---|---|
| 명령 | `CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w …" -o <out> ./cmd/server` (go 1.25.7 → go.mod 1.26.0 툴체인 자동 사용) |
| 빌드 시간 | 9초(캐시 있음) |
| 산출 | ELF aarch64 정적 링크 · 62,062,754 B |
| sha256 | `8d5f778176e4beeeaeb70534c921dfc87f1e25eaaba76a836daa2109af982848` |
| 카탈로그 문자열 | sonnet-5-5=1 · haiku-5-5=1 · gpt-6.1-sol=3 (mini 에서 가동 중인 `8.0.4-haiku55-sonnet55-sol61` 와 같은 수) |
| 산출 위치(이 맥) | scratchpad `xbuild/cli-proxy-api-linux-arm64` — 설치 h 가 올릴 때 sha256 재대조 |

## 같이 확인한 mini 사실 (읽기 전용 ssh, 사용자 **byz@100.71.41.107**)
- 접속 OK(hostname BYZs-Mac-mini.local · macOS 26.5.1 · swap 여유 1.7GB).
- 이미 가동: headroom(8790, python3.14) · cli-proxy-api 8.0.4-haiku55-sonnet55-sol61(8317) · claude(`~/.local/bin`) · codex·node·tmux(brew).
- 없음: tmm · pi · tmuxc(PATH 에 없음 — `~/.claude/skills/tmuxc` 폴더는 있음) · 비로그인 ssh PATH 에 `~/.local/bin` 이 안 들어온다(원격 명령은 `bash -lc` 또는 절대경로).
- 주의: 파이 좌석이 `yoonhwan@…107` 로 시도해 «Permission denied» 라고 보고했다 — 사용자명이 틀렸을 뿐 키는 배포돼 있다.
