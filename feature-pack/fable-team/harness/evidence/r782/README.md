# r782 — ft-da-codex.sh 건너뛰기 머리는 설정에 `[model_providers.headroom]` 절이 있을 때만

## 원인 (arch 129 실측)
래퍼가 `-c model_providers.headroom.http_headers={"x-headroom-bypass"="true"}` 를 **늘** 실었다.
~/.codex/config.toml 에서 헤드룸 provider 절이 빠진 뒤(10-22 헤드룸 off · cliproxy 직결) codex 가
`Error loading config.toml: model_providers.headroom: provider name must not be empty` rc=1 → 전 팀 DA 정지.

## 고침 (kit/fable-team/bin/ft-da-codex.sh)
```bash
cfg="${CODEX_HOME:-$HOME/.codex}/config.toml"
bypass=()
if [ -f "$cfg" ] && grep -q '^\[model_providers\.headroom\]' "$cfg" 2>/dev/null; then
  bypass=(-c "$BYPASS")
else
  echo "INFO 헤드룸 provider 없음($cfg) → 건너뛰기 머리 0" >&2
fi
```
판정 = **줄 시작 글자 일치만**(`grep -q '^\[model_providers\.headroom\]'`) — 주석 줄·`[model_providers.headroomx]`·
다른 provider 절은 절로 읽지 않는다. 머리는 r513 이유(DA 승인정책 never → 접힌 본문 못 되받음) 유지 —
헤드룸이 다시 켜지면 그대로 다시 실린다.

## 시험 원문 (harness/tests/test_da_codex_wrapper.sh)

| 카드 | 무슨 값 | 원문 줄(로그) |
|---|---|---|
| ⓐ 빨강 먼저 | 절 없는 설정 + 가짜 codex 흉내 → 지금 판 rc1 | `red-old-wrapper.log`: `FAIL HR-ⓐ rc=1`, `FAILED=10` (rc=10) |
| ⓑ 후판 | 절 없음 → 머리 인자 0 · rc0 · stderr INFO 1줄 · 출력 파일엔 INFO 0 | `green-fixed-wrapper.log`: `PASS HR-ⓑ 절 없음 → 머리 인자 0` · `PASS HR-ⓑ stderr INFO 1줄` · `PASS HR-ⓑ 출력 파일에 INFO 0` |
| ⓒ | 절 있음 → 머리 인자 있음(지금과 같음 · r513 이유 유지) · INFO 0 | `PASS HR-ⓒ 절 있음 → 머리 인자 있음 rc0` · `PASS HR-ⓒ 절 있으면 INFO 0` |
| ⓓ | CODEX_HOME 미설정 = $HOME/.codex/config.toml · 설정 파일 없음 = 머리 0 | `PASS HR-ⓓ CODEX_HOME 미설정 · 설정 없음 → 머리 0 rc0` · `PASS HR-ⓓ $HOME/.codex/config.toml 절 있음 → 머리 있음` |
| ⓔ | 판정 = 줄 시작 글자 일치만 | `PASS HR-ⓔ 주석 줄 → 머리 0` · `PASS HR-ⓔ [model_providers.headroomx] → 머리 0` · `PASS HR-ⓔ 다른 provider 절 → 머리 0` · `PASS HR-ⓔ 줄 시작 절(주석 달림) → 머리 있음` |
| ⓕ | 모델·effort·-C·stdin /dev/null·새 출력 파일명·끝줄 `OUT <경로> rc=<n>` 유지 | `PASS HR-ⓕ 인자 … 유지` · `PASS HR-ⓕ 출력 파일 새 이름` · `PASS HR-ⓕ 실행마다 새 파일(덮어쓰기 0)` |
| ⓖ 변이 | 조건 삭제(늘 실음) → ⓑ FAIL · 늘 뺌 → ⓒ FAIL | `mutant-always-header.log`: `FAIL HR-ⓑ 절 없는데 머리 인자 있음` (rc=10) · `mutant-never-header.log`: `FAIL HR-ⓒ rc=0 머리=n` (rc=6) |
| ⓗ | 실 ~/.codex 읽기·쓰기 0 | `PASS HR-ⓗ HOME·CODEX_HOME 모두 임시` · `PASS HR-ⓗ 래퍼 config.toml 쓰기 0` · `PASS HR-ⓗ 실 ~/.codex/config.toml 불변` |

## 실행 값
```
(빨강) FT_DA_WRAPPER_MUTANT_CHECK=0 DA_CODEX_TOOL=<HEAD 판 래퍼> bash test_da_codex_wrapper.sh   → rc=10 · FAILED=10
(초록) bash test_da_codex_wrapper.sh                                                             → rc=0 · ALL PASS · PASS 49
```
로그 = 같은 폴더 `red-old-wrapper.log` · `green-fixed-wrapper.log` · `mutant-always-header.log` · `mutant-never-header.log` · `change.diff`

## 범위 밖 (손대지 않음)
- ~/.codex/config.toml(사람 설정) · 헤드룸 경로 재개 · 다른 DA 래퍼(cursor 등) · 문서(COMM-GUIDE-BOOT §42 는 r513 기록)
- 실사건 1(설치 뒤 라이브 래퍼로 아무 팀 DA 1회)은 master 소관 — press 불요(단위·시험만으로 닫힘)
