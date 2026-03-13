# 설치 검증: obsidian-cli CRUD 테스트

## 1. 사전 확인

```bash
# CLI 설치 확인
obsidian-cli --version
# 예상: obsidian-cli version v0.2.3+

# 기본 볼트 확인
obsidian-cli print-default
# 예상: 볼트 이름 + 경로 출력
```

## 2. Create (생성)

```bash
obsidian-cli create "_test/verify-note" --content "# Verify Test
Created: $(date '+%Y-%m-%d %H:%M:%S')
This is a verification test note."
```

**예상 결과**: exit code 0, 에러 없음

## 3. Read (조회)

```bash
# 목록 조회
obsidian-cli list "_test"

# 내용 읽기
obsidian-cli print "_test/verify-note"
```

**예상 결과**: 생성한 노트 내용 출력

## 4. Update (수정)

```bash
# 덮어쓰기
obsidian-cli create "_test/verify-note" --content "# Updated Note
Updated: $(date '+%Y-%m-%d %H:%M:%S')" --overwrite

# append
obsidian-cli create "_test/verify-note" --content "
## Appended Section
This was appended." --append

# 확인
obsidian-cli print "_test/verify-note"
```

**예상 결과**: 업데이트 + 추가된 내용 모두 출력

## 5. Delete (삭제)

```bash
obsidian-cli delete "_test/verify-note"
```

**예상 결과**: `Deleted note: ...` 메시지

## 6. 정리

```bash
# _test 폴더 정리 (볼트에서 직접)
VAULT_PATH=$(obsidian-cli print-default --path-only 2>/dev/null || obsidian-cli print-default | grep -o '/.*')
rm -rf "$VAULT_PATH/_test"
```

## 검증 완료 기준

- [ ] CLI 버전 출력 확인
- [ ] 기본 볼트 설정 확인
- [ ] Create: 노트 생성 성공
- [ ] Read: list + print 정상 출력
- [ ] Update: overwrite + append 정상
- [ ] Delete: 노트 삭제 확인
