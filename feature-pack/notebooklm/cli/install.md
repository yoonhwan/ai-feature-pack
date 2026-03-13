# NotebookLM CLI (`nlm`) 설치 가이드

## 설치 방법

### macOS

```bash
# 1. uv 설치 (Python 패키지 매니저)
curl -LsSf https://astral.sh/uv/install.sh | sh

# 2. nlm 설치
uv tool install notebooklm-mcp-cli

# 3. PATH 확인 (nlm이 안 보이면)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# 4. 확인
nlm --version
```

### 업데이트

```bash
uv tool upgrade notebooklm-mcp-cli
```

### 삭제

```bash
uv tool uninstall notebooklm-mcp-cli
```

## 패키지 정보

- **패키지명**: `notebooklm-mcp-cli`
- **설치 경로**: `~/.local/bin/nlm`
- **내부 venv**: `~/.local/share/uv/tools/notebooklm-mcp-cli/`
- **제작자**: jacob-bd
- **라이선스**: MIT

## MCP 서버 설정 (선택)

AI 도구에서 MCP 서버로 연동할 수도 있습니다:

```bash
nlm setup add claude-code      # Claude Code
nlm setup add claude-desktop   # Claude Desktop
nlm setup add cursor           # Cursor
nlm setup add gemini           # Gemini CLI
nlm setup list                 # 설정된 클라이언트 확인
```
