# Feature Pack: obsidian-cli

> 에이전트 자율 설치 프롬프트. 이 문서를 에이전트에게 전달하면 자동으로 설치합니다.

## 개요

Obsidian 볼트(Markdown 노트)를 CLI로 완전 관리:
- 📋 조회 (list, print)
- 🔍 검색 (search, search-content, grep)
- ✏️ 생성 (create, daily)
- 📝 수정 (overwrite, append, frontmatter)
- 🗑️ 삭제 (delete)
- 📦 이동 + 위키링크 자동 업데이트 (move)

## Prerequisites

- macOS
- Homebrew (`brew --version`으로 확인)
- Obsidian 앱 설치 및 볼트 1개 이상 생성

## Step 1: CLI 설치

```bash
brew install yakitrak/yakitrak/obsidian-cli
```

검증:
```bash
obsidian-cli --version
# 예상: obsidian-cli version v0.2.3+
```

## Step 2: 기본 볼트 설정

사용자에게 볼트 이름을 확인합니다:
```bash
# Obsidian이 추적하는 볼트 목록 확인
cat ~/Library/Application\ Support/obsidian/obsidian.json
```

기본 볼트 설정:
```bash
obsidian-cli set-default "{{VAULT_NAME}}"
```

검증:
```bash
obsidian-cli print-default
# 예상: Default vault name: {{VAULT_NAME}}
#        Default vault path: {{VAULT_PATH}}
```

## Step 3: 스킬 설치

`skill/SKILL.md` 파일을 OpenClaw 스킬 경로에 복사:

```bash
# OpenClaw 공식 스킬에 이미 obsidian 스킬이 포함되어 있는지 확인
ls /opt/homebrew/lib/node_modules/openclaw/skills/obsidian/SKILL.md

# 있으면 → 별도 복사 불필요 (공식 스킬 사용)
# 없으면 → 워크스페이스 스킬 폴더에 복사
mkdir -p {{WORKSPACE}}/skills/obsidian/
cp skill/SKILL.md {{WORKSPACE}}/skills/obsidian/SKILL.md
```

## Step 4: OpenClaw 설정 (TOOLS.md)

`config/tools-section.md` 내용을 참고하여 `{{WORKSPACE}}/TOOLS.md`에 Obsidian CLI 섹션 추가.

주요 내용:
- 바이너리 경로
- 기본 볼트 이름/경로
- 핵심 명령어 (list, print, create, delete, move, frontmatter)

## Step 5: Obsidian 앱 설정 (선택)

`obsidian/setup.md` 참고:
- Daily notes 플러그인 활성화 (Core plugins)
- 권장 Community plugins: Dataview, Templater, Calendar

## Step 6: 설치 검증

`test/verify.md`의 CRUD 테스트 실행:

```bash
# 1. Create
obsidian-cli create "_test/verify" --content "# Test Note"

# 2. Read
obsidian-cli print "_test/verify"

# 3. Update
obsidian-cli create "_test/verify" --content "# Updated" --overwrite

# 4. Delete
obsidian-cli delete "_test/verify"

# 5. 정리
VAULT_PATH=$(obsidian-cli print-default --path-only 2>/dev/null || obsidian-cli print-default | grep -o '/.*')
rm -rf "$VAULT_PATH/_test"
```

모든 단계 exit code 0이면 설치 완료.

## Troubleshooting

| 증상 | 원인 | 해결 |
|------|------|------|
| `brew: command not found` | Homebrew 미설치 | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| `Cannot find note in vault` | 기본 볼트 미설정 | `obsidian-cli set-default "볼트명"` |
| search-content non-interactive 미작동 | CLI 제한 | `grep -r "검색어" $(obsidian-cli print-default --path-only)` 사용 |
| create 후 Obsidian 미반영 | iCloud 동기화 지연 | 수 초 대기, Obsidian 앱에서 새로고침 |

## Placeholder 정리

| Placeholder | 설명 | 질문 예시 |
|-------------|------|----------|
| `{{VAULT_NAME}}` | Obsidian 볼트 이름 (폴더명) | "사용할 Obsidian 볼트 이름이 뭔가요?" |
| `{{VAULT_PATH}}` | 볼트 전체 경로 | (set-default 후 자동 확인) |
| `{{WORKSPACE}}` | OpenClaw 워크스페이스 경로 | (기본: `~/.openclaw/workspace`) |

## 설치 완료 후

사용 예시:
```bash
# 노트 생성
obsidian-cli create "Projects/새프로젝트" --content "# 프로젝트 노트"

# 노트 읽기
obsidian-cli print "Projects/새프로젝트"

# 데일리 노트
obsidian-cli daily

# 노트 이동 (위키링크 자동 업데이트)
obsidian-cli move "old/note" "Archive/note"
```

에이전트가 직접 `.md` 파일을 `read`/`write`/`edit` 도구로 수정하는 것도 가능합니다. Obsidian이 파일 변경을 자동 감지합니다.
