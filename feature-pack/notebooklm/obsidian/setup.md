# Obsidian ↔ NotebookLM 연동 가이드

## 개요

Obsidian 볼트의 마크다운 문서를 NotebookLM 소스로 활용하여:
- 볼트 전체를 대상으로 AI Q&A
- 문서 기반 팟캐스트/리포트 자동 생성
- 프로젝트 지식베이스 구축

## 연동 방식

NotebookLM과 Obsidian은 직접 플러그인 연동이 아닌 **CLI 기반 파일 업로드** 방식으로 연동합니다.

### Step 1: 전용 노트북 생성

```bash
nlm notebook create "My Obsidian Vault"
# 출력된 notebook_id를 별칭으로 설정
nlm alias set vault <notebook_id>
```

### Step 2: 문서 업로드

```bash
# 개별 파일
nlm source add vault --file "~/path/to/vault/파일명.md" --wait

# 특정 폴더의 모든 md 파일
find "~/path/to/vault/Projects" -name "*.md" -maxdepth 2 | while read f; do
  echo "Adding: $f"
  nlm source add vault --file "$f" --wait
  sleep 1  # 레이트리밋 방지
done

# 소스 확인
nlm source list vault
```

### Step 3: Q&A

```bash
nlm query notebook vault "프로젝트 아키텍처 설명해줘"
nlm query notebook vault "지난주 결정사항 정리해줘"
```

## 활용 시나리오

### 프로젝트 문서 Q&A
```bash
# 프로젝트 문서만 모아서 노트북 생성
nlm notebook create "BaseAgent Docs"
nlm alias set baseagent <id>

# 프로젝트 핸드오프/설계 문서 업로드
find ~/Project/Agent/BaseAgent/docs -name "*.md" | while read f; do
  nlm source add baseagent --file "$f" --wait
  sleep 1
done

# Q&A
nlm query notebook baseagent "현재 아키텍처 구조는?"
```

### 학습 노트 → 스터디 자료
```bash
# 학습 노트 업로드
nlm notebook create "AI Study"
nlm alias set study <id>
nlm source add study --file "~/vault/Learning/LangGraph.md" --wait
nlm source add study --file "~/vault/Learning/RAG-Patterns.md" --wait

# 퀴즈 & 플래시카드 생성
nlm quiz create study --confirm
nlm flashcards create study --confirm
```

### 회의록 → 팟캐스트
```bash
# 회의록 모아서 팟캐스트
nlm notebook create "Weekly Meetings"
nlm alias set meetings <id>
find ~/vault/Meetings -name "2026-03-*.md" | while read f; do
  nlm source add meetings --file "$f" --wait
  sleep 1
done

# 오디오 요약 생성
nlm audio create meetings --confirm
# 1~5분 대기
nlm studio status meetings
nlm download audio meetings <artifact_id> -o weekly-summary.mp3
```

## 소스 동기화 (수동)

Obsidian 파일을 수정한 후 NotebookLM에 반영하려면:
1. 기존 소스 삭제: `nlm source delete <notebook_id> <source_id> --confirm`
2. 수정된 파일 재업로드: `nlm source add <notebook_id> --file "파일.md" --wait`

> Drive 소스는 `nlm sync`로 자동 동기화 가능하지만,
> 로컬 파일은 수동 재업로드가 필요합니다.

## 제한사항

- NotebookLM 무료 계정: 소스 50개/노트북, 일 50 쿼리
- 파일 크기 제한: 약 500KB/소스 (대용량 파일은 분할)
- 이미지 포함 md: 텍스트만 추출됨 (이미지 무시)
- 실시간 동기화 없음: 파일 수정 시 수동 재업로드 필요
