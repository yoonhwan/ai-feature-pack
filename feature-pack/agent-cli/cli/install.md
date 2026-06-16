# 에이전트 CLI 설치 (macOS · Linux · WSL)

agent-cli는 **기존에 설치·인증된** 에이전트 CLI를 호출한다. 본 팩은 CLI를 설치하지 않으며, 아래는 참고용. **최소 1개만 있으면 동작**(나머지는 자동 SKIP).

> 먼저 환경부터 파악: `bash scripts/detect-env.sh` → 내 환경에서 뭘 바로 쓸 수 있는지 + 설치 힌트를 알려준다.

## 런타임 (공통 필수)

- `perl`, `python3` — macOS 기본 내장. **WSL/Ubuntu에 없으면**: `sudo apt update && sudo apt install -y perl python3`
- Node.js(+npm) — claude/codex/gemini 설치에 필요. WSL은 `nvm` 권장: `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash` → `nvm install --lts`

## CLI 설치

| CLI | macOS | Linux / WSL | 인증 | 비대화 진입점 |
|-----|-------|-------------|------|--------------|
| **claude** | `npm i -g @anthropic-ai/claude-code` | 동일(npm) | 로그인(OAuth) / `ANTHROPIC_API_KEY` | `claude -p` |
| **codex** | `npm i -g @openai/codex` | 동일(npm) | ChatGPT 로그인 / `OPENAI_API_KEY` | `codex exec` |
| **gemini** | `brew install gemini-cli` 또는 npm | `npm i -g @google/gemini-cli` | Google 로그인 / API 키 | `gemini -p` |
| **opencode** | `brew install opencode` | `curl -fsSL https://opencode.ai/install \| bash` (또는 npm) | provider별 키/OAuth | `opencode run` |
| **cursor-agent** | `curl https://cursor.com/install \| bash` | 동일(Linux 빌드) | Cursor 로그인 | `cursor-agent -p` |

> 버전·설치법은 빠르게 바뀌니 각 공식 문서 우선. 설치 후 `command -v <cli>`로 PATH 확인.

## WSL 전용 주의 ⚠️

1. **OAuth 로그인**: 브라우저가 Windows 쪽에서 열린다. 자동으로 안 뜨면 터미널에 출력된 **URL을 수동 복붙**해 인증.
2. **cursor-agent**: Windows측 Cursor 설치에 의존하는 경우가 있어 **WSL PATH에 없을 수 있음** → 없으면 selftest가 자동 SKIP(정상).
3. **작업 위치**: WSL 네이티브 FS(`~/`)에서 실행. `/mnt/c/...`는 느리고 권한 이슈 발생.
4. **`brew` 금지/불필요**: WSL에선 `apt`/`npm`/`curl` 사용(Linuxbrew도 되지만 무겁다).

## 인증 빠른 점검

```bash
claude -p "ping" --output-format json </dev/null            # is_error:false 면 OK
codex exec --skip-git-repo-check "ping" </dev/null
gemini -p "ping" --approval-mode yolo -o json </dev/null
opencode run -m "<provider/model>" "ping"
cursor-agent -p -f --output-format json "ping" </dev/null
```

미인증/미설치면 selftest에서 ⚠️/SKIP으로 표시된다(스크립트는 정상).
