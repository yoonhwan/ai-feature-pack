# INSTALL — ctx-burn

## 1. 요구사항

- `python3` 3.8 이상 (표준 라이브러리만 사용, pip 설치 없음)
- macOS 또는 Linux
- Claude Code를 쓴다면 자동으로 잡힌다 (`~/.claude/projects/**/*.jsonl`)

## 2. 설치

```bash
git clone https://github.com/yoonhwan/ai-feature-pack.git
cd ai-feature-pack/feature-pack/ctx-burn
bash install.sh
```

`install.sh` 가 하는 일은 하나다. `bin/ctx-burn` 를 `~/.local/bin/ctx-burn` 로 심링크.

경로를 바꾸고 싶으면:

```bash
CTX_WASTE_BIN_DIR="$HOME/bin" bash install.sh
```

## 3. 확인

```bash
ctx-burn --hours 1              # English (default)
ctx-burn --hours 1 --lang ko    # 한국어
ctx-burn --runtime all          # 데이터 있는 런타임 전부 상세
```

검사 대상 런타임은 자동 감지된다: `claude` `codex` `pi` `opencode` `hermes` `openclaw` `commandcode`.
없는 런타임은 `installed=no` 로만 표시되고 오류가 되지 않는다.

`command not found` 면 PATH에 `~/.local/bin` 이 없는 것이다. 셸 rc에 추가:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## 4. 제거

```bash
bash uninstall.sh
```

심링크만 지운다. 세션 로그·설정은 건드리지 않는다.

## 5. 프록시 로그까지 보려면 (선택)

툴 정의 크기까지 계산하려면 요청 본문이 담긴 로그가 필요하다.
CLIProxyAPI를 쓴다면 `~/.cli-proxy-api/logs/error-v1-messages-*.log` 가 그 역할을 한다.

```bash
ctx-burn --request ~/.cli-proxy-api/logs/error-v1-messages-2026-11-06T092812-*.log
```

프록시를 안 쓴다면 이 옵션은 생략해도 된다. 나머지 6개 섹션은 혼자 동작한다.

## 6. 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| `고유 요청 0건` | 그 시간대에 세션 기록이 없다. `--hours 24` 로 늘린다 |
| `[3] 손익분기 계산 불가` | 평균 컨텍스트가 예산보다 작다. 낭비가 없다는 뜻이므로 `--budget` 을 낮춰 본다 |
| `--request` 가 무시된다 | 로그가 요청 본문을 담고 있지 않다. `=== REQUEST BODY ===` 마커 또는 순수 JSON 본문 필요 |
| 세션 수가 이상하게 많다 | 서브에이전트도 세션으로 센다. 정상 |

## 7. 에이전트에게 맡기기 (사람이 직접 안 해도 됨)

아래 블록을 쓰는 코딩 에이전트(Claude Code·Codex·pi·opencode 등)에 그대로 붙여넣으면
설치·실행·해석까지 스스로 한다. 이 툴이 읽기 전용이라 실행 자체에 위험이 없다.

```text
ctx-burn 를 이 프로젝트에 설치하고 돌린 뒤 결과를 해석해줘.
https://github.com/yoonhwan/ai-feature-pack/tree/main/feature-pack/ctx-burn

1. 클론 후 feature-pack/ctx-burn/install.sh 실행 (~/.local/bin/ctx-burn 심링크)
2. 이 프로젝트 루트에서 ctx-burn --hours 6 실행 (한국어면 --lang ko)
3. 출력에서 캐시 전면 재작성 비중 · 요청당 평균 컨텍스트 · 4KB 넘는 자동 로드 파일 top3 만 보고
4. 재작성 비중이 20% 넘으면 로컬 로그로 원인(리줌 크기·세션 동시 시작·계정 전환)을 찾아 근거 줄과 함께 제시
5. 4KB 넘는 자동 로드 파일은 guides/로 옮기고 1KB 다이제스트를 남기는 안을 제안
6. 설정을 바꾸기 전에는 나에게 물어봐. 툴 자체는 읽기 전용이라 실행은 안전하다
```
