# 에이전트 CLI 설치 (선택)

cross-cli는 **기존에 설치·인증된** 에이전트 CLI를 호출한다. 본 팩은 CLI를 설치하지 않으며, 아래는 참고용이다. 최소 1개만 있으면 동작한다(나머지는 SKIP).

| CLI | 설치(예시) | 인증 | 비대화 진입점 |
|-----|-----------|------|--------------|
| **claude** (Claude Code) | `npm i -g @anthropic-ai/claude-code` | `claude` 로그인(또는 `ANTHROPIC_API_KEY`) | `claude -p` |
| **codex** (OpenAI Codex) | `npm i -g @openai/codex` | ChatGPT 로그인 / API 키 | `codex exec` |
| **gemini** (Gemini CLI) | `brew install gemini-cli` (또는 npm) | Google 로그인 / API 키 | `gemini -p` |
| **opencode** | `brew install opencode` (또는 공식 스크립트) | provider별(키/OAuth) | `opencode run` |
| **cursor-agent** | Cursor 공식 CLI 설치 | Cursor 로그인 | `cursor-agent -p` |

> 버전·설치법은 각 공식 문서를 따른다(빠르게 바뀜). 설치 후 `command -v <cli>`로 PATH 확인.

## 인증 확인 (빠른 점검)

```bash
claude -p "ping" --output-format json </dev/null            # is_error:false 면 OK
codex exec --skip-git-repo-check "ping" </dev/null
gemini -p "ping" --approval-mode yolo -o json </dev/null
opencode run -m "<provider/model>" "ping"
cursor-agent -p -f --output-format json "ping" </dev/null
```

미인증이면 해당 CLI는 cross-cli selftest에서 ⚠️/❌로 표시된다(스크립트는 정상).
