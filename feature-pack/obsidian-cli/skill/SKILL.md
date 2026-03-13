---
name: obsidian
description: Work with Obsidian vaults (plain Markdown notes) and automate via obsidian-cli.
homepage: https://help.obsidian.md
metadata:
  openclaw:
    emoji: "💎"
    requires:
      bins: ["obsidian-cli"]
    install:
      - id: brew
        kind: brew
        formula: yakitrak/yakitrak/obsidian-cli
        bins: ["obsidian-cli"]
        label: Install obsidian-cli (brew)
---

# Obsidian

Obsidian vault = a normal folder on disk.

## Vault Structure

- Notes: `*.md` (plain text Markdown)
- Config: `.obsidian/` (workspace + plugin settings; don't touch from scripts)
- Canvases: `*.canvas` (JSON)
- Attachments: images/PDFs/etc. (Obsidian settings에서 지정한 폴더)

## Find the Active Vault

Obsidian desktop tracks vaults here:
```
~/Library/Application Support/obsidian/obsidian.json
```

Fast check:
```bash
obsidian-cli print-default           # 이름 + 경로
obsidian-cli print-default --path-only  # 경로만
```

## When to Use This Skill

- Obsidian 노트 조회/검색/생성/수정/삭제/이동
- 데일리 노트 생성
- frontmatter 조회/수정
- 노트 이름변경 + 위키링크 자동 업데이트

## obsidian-cli Commands

### 볼트 설정
```bash
obsidian-cli set-default "vault-name"      # 기본 볼트 지정
obsidian-cli print-default                 # 기본 볼트 확인
obsidian-cli print-default --path-only     # 경로만
```

### 조회 (Read)
```bash
obsidian-cli list                          # 볼트 루트 목록
obsidian-cli list "Folder"                 # 특정 폴더 목록
obsidian-cli print "path/note"             # 노트 내용 읽기
```

### 검색 (Search)
```bash
obsidian-cli search "query"                # 노트 이름 퍼지 검색 (인터랙티브)
obsidian-cli search-content "query"        # 노트 내용 검색 (인터랙티브)
```

> ⚠️ search/search-content는 인터랙티브 모드. 에이전트 환경에서는 `grep -r` 또는 `list` + `print` 조합 사용.

### 생성 (Create)
```bash
obsidian-cli create "Folder/Note" --content "내용"       # 노트 생성 (폴더 자동 생성)
obsidian-cli create "Folder/Note" --content "내용" --open # 생성 후 Obsidian에서 열기
obsidian-cli daily                                        # 데일리 노트 생성/열기
```

### 수정 (Update)
```bash
# 덮어쓰기
obsidian-cli create "path/note" --content "새 내용" --overwrite

# 추가 (append)
obsidian-cli create "path/note" --content "추가 내용" --append

# Frontmatter
obsidian-cli frontmatter "path/note" --print                           # 조회
obsidian-cli frontmatter "path/note" --edit --key "status" --value "done"  # 수정
obsidian-cli frontmatter "path/note" --delete --key "draft"            # 키 삭제
```

> 💡 직접 파일 편집도 가능: `.md` 파일을 `read`/`write`/`edit` 도구로 수정 → Obsidian 자동 감지

### 이동/이름변경 (Move)
```bash
obsidian-cli move "old/path/note" "new/path/note"    # 위키링크 자동 업데이트!
```

### 삭제 (Delete)
```bash
obsidian-cli delete "path/note"
```

### 열기 (Open)
```bash
obsidian-cli open "path/note"              # Obsidian 앱에서 열기
```

## Decision Flow

```
노트 작업 요청
├── 조회/읽기 → obsidian-cli print / list
├── 검색 → grep -r (에이전트) 또는 search-content (인터랙티브)
├── 생성 → obsidian-cli create --content
├── 수정 → create --overwrite / --append / frontmatter --edit
├── 이동 → obsidian-cli move (위키링크 자동 업데이트)
├── 삭제 → obsidian-cli delete
└── 직접 편집 → read/write/edit 도구로 .md 파일 수정
```

## Troubleshooting

| 증상 | 원인 | 해결 |
|------|------|------|
| `Cannot find note in vault` | 기본 볼트 미설정 또는 노트 경로 오류 | `set-default` 확인, 경로에 `.md` 빼기 |
| search-content 미작동 | non-interactive 환경 | `grep -r` 또는 `list`+`print` 사용 |
| create 후 Obsidian 미감지 | iCloud 동기화 지연 | 수 초 대기 후 확인 |
| URI handler 오류 | Obsidian 앱 미실행 | Obsidian 앱 실행 후 재시도 |

## Best Practices

1. **볼트 경로 하드코딩 금지** — `print-default --path-only`로 동적 참조
2. **이동 시 반드시 `move` 사용** — `mv`는 위키링크 깨짐
3. **`.obsidian/` 폴더 건드리지 않기** — 플러그인/설정 충돌 위험
4. **대량 작업 시 직접 파일 편집** — CLI보다 `read`/`write` 도구가 빠름
5. **폴더 생성은 create와 함께** — `create "New/Folder/Note"` 하면 폴더 자동 생성
