# INSTALL — ctx-waste

## 1. 요구사항

- `python3` 3.8 이상 (표준 라이브러리만 사용, pip 설치 없음)
- macOS 또는 Linux
- Claude Code를 쓴다면 자동으로 잡힌다 (`~/.claude/projects/**/*.jsonl`)

## 2. 설치

```bash
git clone https://github.com/yoonhwan/ai-feature-pack.git
cd ai-feature-pack/feature-pack/ctx-waste
bash install.sh
```

`install.sh` 가 하는 일은 하나다. `bin/ctx-waste` 를 `~/.local/bin/ctx-waste` 로 심링크.

경로를 바꾸고 싶으면:

```bash
CTX_WASTE_BIN_DIR="$HOME/bin" bash install.sh
```

## 3. 확인

```bash
ctx-waste --hours 1              # English (default)
ctx-waste --hours 1 --lang ko    # 한국어
ctx-waste --runtime all          # 데이터 있는 런타임 전부 상세
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
ctx-waste --request ~/.cli-proxy-api/logs/error-v1-messages-2026-11-06T092812-*.log
```

프록시를 안 쓴다면 이 옵션은 생략해도 된다. 나머지 6개 섹션은 혼자 동작한다.

## 6. 트러블슈팅

| 증상 | 원인 / 조치 |
|---|---|
| `고유 요청 0건` | 그 시간대에 세션 기록이 없다. `--hours 24` 로 늘린다 |
| `[3] 손익분기 계산 불가` | 평균 컨텍스트가 예산보다 작다. 낭비가 없다는 뜻이므로 `--budget` 을 낮춰 본다 |
| `--request` 가 무시된다 | 로그가 요청 본문을 담고 있지 않다. `=== REQUEST BODY ===` 마커 또는 순수 JSON 본문 필요 |
| 세션 수가 이상하게 많다 | 서브에이전트도 세션으로 센다. 정상 |
