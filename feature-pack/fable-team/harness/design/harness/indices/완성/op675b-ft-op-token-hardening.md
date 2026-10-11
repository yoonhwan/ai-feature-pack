# 인덱스: ft-op-token 후속 다듬기 3 — 비JSON 응답 ERR 1줄 · --init 클립보드 항상 비움 · https 강제 (판정 675 보안 DA r1 비차단 권고 1~3 · arch#24)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 675 후속(보안 DA r1 `design/harness/DA-675-ft-op-token-r1-verdict.md` APPROVE · 비차단 권고 4)
- 상태: 대기
- 선행: 판정 675 본 세트 `0e82391b40` main 랜딩(이 카드는 랜딩 뒤 origin/main 에서 딴다)
- 시험 입력: 기존 `tests/harness/test_ft_op_token.py` 의 로컬 스텁 서버 + 임시 secrets — 실 Supabase 0
- 기준값(arch#24 실측 · 세트 `0e82391b40`): `ft_op_token.py:99` `json.loads(raw)` 가 200 비JSON 에서 JSONDecodeError 트레이스백(출력 계약 `ERR … 1줄` 깨짐 · 값 노출 0) · `ft-op-token.sh:13` 클립보드는 rc=0 일 때만 비움 · `read_conf`(`:63-65`) 는 URL 스킴 검사 없음.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 A / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」 — 이상 = 보안 DA r1 비차단 권고 · 검토 = 이 카드.
골의 축: A(모니터·검토) + C(도구 업그레이드).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
운영 계정 토큰 도구 `ft-op-token.sh`(판정 675)는 오빠 문책 건이라 보안 DA APPROVE 뒤 그대로 랜딩했다. DA 가 남긴 비차단 권고 셋을 작은 후속으로 닫는다. ①로그인 서버가 200 인데 본문이 JSON 이 아니면 지금은 파이썬 트레이스백이 나온다 — 다른 실패처럼 `ERR <email> http=200 msg=응답 JSON 아님` 1줄(본문 출력 0)로 끝내야 한다. ②`--init` 이 실패해도 클립보드에 비밀번호가 남는다 — macOS 유니버설 클립보드·기록 앱이 옮길 수 있으니 읽은 뒤 결과와 무관하게 비운다. ③설정 파일 URL 이 `https://` 가 아니면 비밀번호가 평문으로 갈 수 있다 — ERR 로 멈춘다.

## 사전검증
- 소환: 아니오(보안 DA r1 이 권고 문구까지 정함 · 구현 DA 생략 — arch 재현으로 닫음).
- 조사 근거: 위 «기준값»(세트 `0e82391b40` 행 번호) · DA 판정문 «비차단 권고» 1~3.
- 7초 룰 점검(판정 666): 외부 호출 1곳 그대로 — 상한 7 s · 재시도 1 · 600/300 s 0.

## 설계 (닫힌 목록)
1. `login()` 200 경로: `json.loads`·`.get` 을 `except (ValueError, AttributeError)` 로 감싸 `Fail(f"ERR {email} http=200 msg=응답 JSON 아님")` — 본문 출력 0 · 재시도 0.
2. `ft-op-token.sh --init`: `pbpaste | python …` 뒤 rc 와 무관하게 `printf '' | pbcopy`(성공·실패 모두).
3. `read_conf()`: `SUPABASE_URL` 이 `https://` 로 시작하지 않으면 `Fail(f"ERR {email} op-auth.conf SUPABASE_URL 은 https:// 만", 2)`. ★시험 스텁은 http 로컬 서버라★ 시험 전용 우회는 환경변수 `FT_OP_TOKEN_ALLOW_HTTP_LOOPBACK=1` 이고 호스트가 `127.0.0.1`·`localhost` 일 때만 허용(그 밖 http 는 항상 ERR).
4. 카드·도구 머리 주석 문구: 「총 상한 ≈ 14.5 s」 → 「1회 7 s(소켓 연산 기준) · 재시도 1」(DA 권고 4).

## 구현 범위 (닫힌 목록 · 나노)
기존 파일(수정): `scripts/harness-install/fable-team/bin/ft_op_token.py` · `scripts/harness-install/fable-team/bin/ft-op-token.sh` · `tests/harness/test_ft_op_token.py`.
시험 추가: T11 200 비JSON → ERR http=200 1줄 · 트레이스백 0 · 토큰 파일 그대로 T12 `--init` 실패(400) 뒤 클립보드 비었음(가짜 pbcopy 스텁 호출 기록) T13 SUPABASE_URL=http 예시 호스트(example.invalid) → exit 2 ERR · 루프백 우회 변수 없이 http 127.0.0.1 도 ERR · 변수 있으면 통과. 기존 T1~T10 그대로 PASS.
커밋은 자기 브랜치, **push 금지**. **금지**: 실 Supabase 호출 · 루트 `.fable-team/`·홈 쓰기 · ★secrets/·*.cred·토큰 파일 내용 출력 0 — 키 이름·존재·크기만(판정 676)★.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · ruff clean · arch 독립 재현.
- 카드 증거 줄: 세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/harness/test_ft_op_token.py rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#24 에 `[완료·휴식]` 1통.
- 랜딩 뒤 master 집행: PR → 병합 → 키트 설치(설치본 cmp) → `ft-op-token.sh --list` 1회(값 출력 0).

## 상태
- base_sha: 89d51ff559832ee73a5cf100774fdbd72b6ed417 (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#24 · 판정 675 보안 DA r1 비차단 권고 후속 · 본 세트 랜딩 뒤 spawn).
- 정본 영향: 하네스 키트 도구 1 수정.
- ★spawn 전 확인★: 구현 범위의 `ft_op_token.py`·`ft-op-token.sh` 는 675 랜딩 뒤에야 이 카드 줄기(`ops/main-base`)에 실재 → 그 전엔 ft-index-lint «경로 실재 0» REJECT 가 정상. 랜딩·ops 반입 뒤 spawn.
- 2026-10-09 14:07 — 대기→진행 · 좌석 byz-harness-nano-op675b-ft-op-token-hardening#0 (master#23 수동 이동 — spawn 의 인덱스 이동이 ops-guard cwd 때문에 실패)

## 결과
- 세트: 01225ca732c4c5dcd9a6343681ff9e3056bc136d · 시험: .venv/bin/python -m pytest --noconftest tests/harness/test_ft_op_token.py rc=0 · 이슈: 0
정본 영향 없음: 제품 정본 변경 없음 — 하네스 키트 ft-op-token 다듬기만 (arch 재현 #68933 · 판정서 §111).
- 2026-10-09 14:14 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§111
