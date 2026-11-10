# r484 나노 단계 · 세트 1cb194fa840e677fc24aa543c2b850c91cad5cad

## test_root_bin_shim.sh (rc=0)
```
PASS r484 ⑥ 절 사본 생성
PASS r484 픽스처: 워크트리 ft-news-tree.py = bash shim
PASS r484 ⓐ ⑥ 절 아래 트리 줄 ≥1
PASS r484 ⓐ stderr SyntaxError 0
PASS r484 대조: 옛 호출 꼴 = SyntaxError 재현
PASS r484 ⓑ 옛 줄 → 린트 rc1 (rc=1)
PASS r484 ⓑ REJECT 파일:줄 원문
PASS r484 ⓒ 키트 bin 전수 린트 (rc=0)
PASS r484 ⓒ OK 0건
PASS r484 ⓓ bash <shim> 직접 실행 = 트리 줄
PASS r484 ⓓ SyntaxError 0
== fail=0
```

## test_kit_bin_sync.sh (rc=0)
```
PASS dirs exist
PASS tracked bin ⊂ kit bin (bytes+mode)
PASS shim-exec lint: OK 0건
PASS control: identical → 0
PASS control: missing detected
PASS control: byte diff detected
PASS control: mode diff detected
ALL PASS
```

## 기존 RED (origin/main 3ca1e15f · 이 카드 전)
- test_root_bin_shim.sh fail=11 → 600ece71 (--repo·--path) 뒤 fail=0
- ft-tmp-trap-lint.sh test_root_bin_shim.sh:8 REJECT(cd+mktemp 감싼 꼴을 린트가 못 읽음 · 기존 줄 · 범위 밖)

## 남은 것(master)
- 착지 → install.sh --apply → LIVE_BIN cmp0 2 → 실사건 bash <LIVE_BIN>/ft-news-tick.sh ⑥ 트리 줄≥1 · SyntaxError 0
