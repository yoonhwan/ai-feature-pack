model: claude-opus-5-5[1m] (세션 시스템 표기 · 1M 창)
provider: Anthropic (Claude Code · 좌석 byz-harness-da-claude#0)

# 판정 675 ft-op-token 구현 보안 DA r1 — 2026-10-09 · 세트 0e82391b40d3de67f33b378524fe6edca360be39

- 발주: harness-master#23 #68388 (bounded 10+10 · 2 HOLD 중단)
- 골 축: 하네스 원문 1(업그레이드·커밋·push·반영) — 오빠 문책 「토큰 안된다 매번 이렇게 멍청하게 해야되냐」를 저장 cred 자동 발급으로 해소한다.
- 대상: `nano/op675-ft-op-token-auto-issue` (wt `.worktrees/harness-op675-ft-op-token-auto-issue`) — `scripts/harness-install/fable-team/bin/ft-op-token.sh`(16줄) · `ft_op_token.py`(195줄) · `tests/harness/test_ft_op_token.py` · `design/teams/harness/staged-675/*` · 카드 설계 1~8.
- 실측: 시험 `.venv/bin/python -m pytest -q tests/harness/test_ft_op_token.py` → **11 passed (20.35 s)** · 스텁 서버를 쓰고 실 Supabase 호출 0. 변경 파일 전체 grep(`supabase.co`·`sb_publishable_`·`sb_secret_`·`@byourz.com`·`eyJhbGci`) 결과 0건. `.fable-team/secrets` 는 `drwx------` 이고 내용은 열지 않았다(판정 676). 코드 수정 0.

## 판정 — APPROVE (차단 0 · 비차단 권고 4)

### ① 비밀 원문 노출 — 통과
- 비밀번호 경로: `--init` 은 `pbpaste | python` stdin(`ft-op-token.sh:11` · `ft_op_token.py:147`)으로 받고, 평시는 파이썬이 cred 파일을 직접 읽는다(`:154-155`). argv 에는 email 만 있다(`ps` 노출 0). 환경변수 경로도 0이다.
- 토큰: 출력은 `ok_line`(`:129-134`)의 exp·파일 이름뿐이다. `--list`(`:166-174`)도 남은 분만 낸다.
- 실패 줄: HTTPError 본문은 `mask()`(`:79-84`)를 거친다 — JWT·`sb_`·`"password"` 패턴을 지우고, 비밀번호 리터럴을 치환한 뒤 200자로 자른다. 네트워크 오류도 같다(`:109`). 시험 t2 는 서버가 비밀번호와 JWT 를 되돌려 주는 400 을 쓰는데, `assert_no_secret`(시험 `:102-104`)이 stdout·stderr 둘 다에서 0 을 확인했다.
- 트레이스백(arch 관찰 1): 200 비JSON 응답이면 `json.loads`(`:99`)의 JSONDecodeError 가 `main` 의 `except Fail`(`:189`) 밖으로 나간다. 메시지에는 위치만 있고 응답 본문은 없다. JSON 이지만 dict 가 아닌 응답이면 AttributeError 인데, 이것도 타입 이름뿐이다. 트레이스백의 소스 줄에도 값이 없다 → 값 노출 0 에 동의한다. 다만 비차단 권고 ①을 본다.
- 임시 파일: `atomic_write`(`:121-126`)는 같은 secrets 폴더 안의 `mkstemp`(0600 · umask 077 `:178`)를 쓴다. 쓰기 도중 예외가 나면 `.tmp-*` 가 남을 수 있지만, 0700 폴더 안이라 밖으로 노출되지 않는다.

### ② cred 권한·경로·추적 — 통과
- 경로: 설치본은 `.fable-team/bin/../secrets` = `.fable-team/secrets`(`:35-37`), 키트 경로는 `scripts/harness-install/fable-team/secrets` 다. 둘 다 `.gitignore:52-53·168` `secrets/`·`secrets` 에 걸린다(`git check-ignore -v` 실측).
- 권한: 폴더 0700·파일 0600 이 아니면 ERR 로 멈춘다. 고치지 않고 알리기만 한다(`:44-51`) — 조용한 수정 0. 새로 쓰는 파일은 0600 이다(시험 t6 `:154`).

### ③ 7초 + 재시도 1 — 통과
- `urlopen(timeout=7.0)`(`:97`) · `MAX_RETRIES=1` · 4xx 는 즉시 Fail(`:106-107`) · 재시도는 5xx·네트워크·타임아웃만(`:108`) · 대기 0.5 s. 600/300 s 0. 시험 t3(5xx 재시도 1회)·t4(7 s 타임아웃 → 재시도 → net ERR) 통과.
- 재시도 시 비밀 노출: 같은 HTTPS 요청 본문을 메모리에서 다시 보낼 뿐이라 로그·출력 추가 0. POST 리다이렉트는 urllib 이 307/308 에서 HTTPError 를 내고 301/302/303 에서는 본문을 버린 GET 으로 바꾼다. 그래서 다른 호스트로 본문이 넘어가는 경로가 없다.

### ④ `--init` 경로 — 통과(권고 ②)
- 입력 에코 0: tty 입력이 없다(클립보드 → 파이프). 실패하면 cred 를 쓰지 않는다(`:156` login 성공 뒤에만 `:157-161` · 시험 t6b). 표에 없는 email 은 거부한다(`:140-141` · 시험 t6c). 클립보드는 성공일 때만 비운다(`ft-op-token.sh:13`).

### ⑤ 예시 파일 실값 — 통과
- `op-auth.conf.example` = `example-project.example.invalid`·`fake-publishable-key-example` · `op-accounts.tsv.example` = `@example.test` · 시험 = `tester@example.test`/`Pw-fake-12345`. 시험 t10 과 위 grep 이 모두 0건이다.

## 비차단 권고 (arch 관찰 2건 판단 포함 · 고칠지는 arch/master 선택)
1. **200 비JSON 트레이스백**(관찰 1): 노출은 0이지만 출력 계약(`ERR <email> http=… msg=…` 1줄)이 깨진다. `--init` 에서는 rc≠0 이라 클립보드도 남는다. `:99` 를 `except (ValueError, AttributeError)` → `Fail(f"ERR {email} http=200 msg=응답 JSON 아님")`(본문 출력 0)으로 감싸기를 권한다. #0 RULE 상 «raise» 는 이미 지켜지므로 차단 사유는 아니다.
2. **`--init` 실패 시 클립보드 잔류**(관찰 2): ★비우기를 권한다★ — `pbpaste` 를 읽은 뒤 rc 와 무관하게 `printf '' | pbcopy`. 이유: macOS 유니버설 클립보드·클립보드 기록 앱이 평문 비밀번호를 다른 기기·기록으로 옮길 수 있다. 비밀번호가 틀렸으면 다시 복사해야 하므로 남겨 둘 이득이 없다. 네트워크 실패면 다시 복사 1회가 비용이다. opcred 와 같다는 사실은 «기존에도 있던 노출»일 뿐 유지 근거가 아니다.
3. **https 강제**: `read_conf`(`:63-65`)에 `SUPABASE_URL` 이 `https://` 로 시작하지 않으면 ERR 1줄을 넣기를 권한다. 사람이 쓰는 0600 설정이라 가능성은 낮지만, http 오기입 1회면 비밀번호가 평문으로 전송된다.
4. **총 상한 표현**: urllib `timeout` 은 소켓 연산별 상한이다(DNS 조회는 제외). 카드 설계 4 의 「총 상한 ≈ 14.5 s」는 일반 경로 기준이며, 느리게 흘리는 응답이면 넘을 수 있다. 실 Supabase 에서는 무시할 수준이다. 카드 문구를 「1회 7 s(소켓 연산 기준)」로 적으면 정확하다.

## 범위 밖 메모
- 카드 설계 8 「새 파일은 하네스 설치 목록에 추가」 — 세트 diff 에 설치 목록 변경 파일이 보이지 않는다. 보안 축이 아니라 판정하지 않았다. master 가 설치 «전»에 확인할 것.

APPROVE
