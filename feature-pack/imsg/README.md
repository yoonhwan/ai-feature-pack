# iMessage Feature Pack

macOS Messages.app을 터미널에서 제어하는 CLI + OpenClaw 스킬 패키지.

## 무엇을 할 수 있나요?

- **대화 목록 조회** — 최근 iMessage/SMS 대화 목록
- **메시지 히스토리** — 특정 대화의 과거 메시지 조회 (날짜 필터, 첨부파일 포함)
- **메시지 전송** — 텍스트 + 첨부파일(이미지, 문서 등) 전송
- **실시간 수신 감시** — 새 메시지 도착 시 스트림 출력
- **🔔 에이전트 알림 채널** — 다른 에이전트, 코딩 도구, 크론에서 iMessage로 알림 전송

## 알림 채널 활용 (핵심 차별점)

```bash
# 빌드 완료 알림
imsg send --to "+821050046707" --text "✅ 빌드 완료: MyApp v2.1.0"

# 크론 에러 알림
imsg send --to "+821050046707" --text "🔴 서버 다운 감지: api.example.com"

# CI/CD 파이프라인 결과
imsg send --to "+821050046707" --text "PR #42 머지 완료" --file ./report.pdf
```

어떤 CLI 도구, 스크립트, 에이전트에서든 `imsg send` 한 줄로 iMessage 알림 전송 가능.

## 요구사항

- macOS + Messages.app (iCloud 계정 로그인)
- 터미널 Full Disk Access 권한
- Messages.app Automation 권한

## 설치

`INSTALL.md`를 에이전트에게 전달하면 자율 설치됩니다.
