# Obsidian 앱 설정

## 필수 설정

### 1. Obsidian 설치
```bash
# 공식 사이트에서 다운로드
open https://obsidian.md
```

### 2. 볼트 생성/열기
Obsidian 앱에서 볼트(폴더) 생성 또는 기존 폴더를 볼트로 열기.

### 3. obsidian-cli 기본 볼트 연결
```bash
obsidian-cli set-default "{{VAULT_NAME}}"
obsidian-cli print-default  # 검증
```

## 선택 설정

### Community Plugins (권장)
- **Dataview**: 노트 쿼리/테이블 생성
- **Templater**: 노트 템플릿 자동화
- **Calendar**: 데일리 노트 캘린더 뷰

### Daily Note 설정
Obsidian Settings → Core plugins → Daily notes → 활성화
- Date format: `YYYY-MM-DD`
- New file location: `Daily/`

## 볼트 경로 참고

| 위치 | 경로 예시 | 특징 |
|------|----------|------|
| iCloud | `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/볼트명` | 기기 간 동기화 |
| 로컬 | `~/Documents/볼트명` | 빠른 접근, 동기화 없음 |
| Dropbox | `~/Dropbox/볼트명` | Dropbox 동기화 |
