# obsidian-cli 설치

## 설치

```bash
brew install yakitrak/yakitrak/obsidian-cli
```

## 검증

```bash
obsidian-cli --version
# 예상 출력: obsidian-cli version v0.2.3 (이상)
```

## 기본 볼트 설정

```bash
obsidian-cli set-default "{{VAULT_NAME}}"
# 검증
obsidian-cli print-default
```

## 볼트 이름 찾기

Obsidian이 추적하는 볼트 목록:
```bash
cat ~/Library/Application\ Support/obsidian/obsidian.json
```
볼트 이름 = 폴더 이름 (경로의 마지막 부분).
