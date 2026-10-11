# 인덱스: 운영 계정 토큰 «수동 복사» 폐지 — `ft-op-token.sh <email>` 가 저장된 cred 로 매번 새 access_token 발급 (판정 675 · 오빠 문책 10-09 「토큰 안된다 매번 이렇게 멍청하게 해야되냐」 · planner#16 #68339 → 하네스 master#22 #68340)
<!-- ledger: design/harness/GOAL-harness.md -->
- Issue: 없음 → 판정 675
- 상태: 대기
- 선행: 없음 (planner 가 1회 설정 중인 cred 파일이 있으면 그대로 읽는다 — 형식 아래 «기준값»)
- 시험 입력: 가짜 Supabase(로컬 `http.server` 스텁 · 200/400/500/지연 응답) + 임시 secrets 폴더 — 실 Supabase 호출 0
- 기준값(arch#24 실측 · 읽기 전용): ①planner 1회 설정 스크립트 `/tmp/opcred.sh`(추적 밖) = 클립보드 비밀번호 → `POST <URL>/auth/v1/token?grant_type=password`(헤더 `apikey`=publishable key · urlopen timeout=7 · 재시도 0) → `.fable-team/secrets/<계정>.cred` = JSON `{"email","password"}`(+ 기존 `byztest910.cred` 는 `"org"` 키도 있음) · 토큰 파일 = access_token 원문 한 줄(개행 없음) · 계정 표 하드코딩 2행(developer.ts → `byz_admin_token_dev` · admin.ts → `byz_org_admin_token_dev`) · URL·publishable key 하드코딩. ②`.fable-team/secrets/` = 0700 · 파일 0600 · `.gitignore` 173행 `.fable-team/` 로 추적 밖. ③추적 코드에서 토큰 파일 이름을 읽는 곳 0(좌석이 손으로 `cat`) — 바꿀 호출부 없음.

## 골 원문 (항상 이 3줄)
내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용하는것.

## 골좌표
하네스 GOAL 표 A / 닫는 증거(정본 복붙): 「이상 1건 = Issue 1건(team:shared-harness) + 검토 코멘트」 — 이상 = 오빠 문책(판정 675) · 검토 = 이 카드 + 판정서.
골의 축: A(모니터·오빠 요청) + C(도구 업그레이드·설치 — 좌석이 만료 토큰 대신 이 도구를 부른다).

## 배경 (한 단락 — 나노워커가 이 파일만 읽고 착수 가능해야 함)
운영(dev = 라이브 prod) 계정 토큰은 약 1시간이면 만료된다. 지금까지는 만료될 때마다 오빠가 콘솔에서 토큰을 복사해 좌석에 넘겨 왔다. 판정 675 의 오빠 문책 「토큰 안된다 매번 이렇게 멍청하게 해야되냐」가 그 결과다(멍청한짓 원장 0행 · 64분 정지). 사람 손은 «계정마다 비밀번호 1회 저장» 한 번으로 끝나야 한다. 그 뒤는 도구가 저장된 cred 로 매번 새 토큰을 발급한다. planner 가 임시 스크립트 `/tmp/opcred.sh` 로 1회 설정을 시작했다. 이 카드는 그 스크립트를 정식 하네스 도구로 옮긴다. 하드코딩된 URL·키·계정 표는 secrets 쪽 설정 파일로 빼고, 7초 룰(판정 666)과 실패 이유 출력을 더한다.

## 사전검증
- 소환: 아니오(설계 DA 생략 — 기존 임시 스크립트의 정식화이고 설계 선택지가 «password grant vs refresh_token» 하나뿐이라 아래 설계 2 에 근거를 적는다). ★구현 DA 예 1회 — 보안 점검(Claude Opus · 기존 `byz-harness-da-claude#0`) · bounded 10+10 · 2 HOLD 면 arch 서명★.
- 조사 근거: 위 «기준값» ①~③ (`/tmp/opcred.sh` 읽기 · secrets 폴더 권한 · `git grep` 호출부 0).
- 7초 룰 점검(판정 666): 외부 호출 1곳(Supabase auth) — 상한 7 s · 재시도 1회 · 600/300 s 상한 0.

## 설계 (닫힌 목록)
1. **도구** `ft-op-token.sh` (키트 = 하네스 설치 키트 bin 폴더 · 설치본 = 루트 `.fable-team/bin/` · 본체는 같은 이름 `.py` 1개 — 셸은 얇은 진입점):
   - `ft-op-token.sh <email>` = cred 로 password grant → 새 access_token → 토큰 파일 원자 교체(같은 폴더 tmp + `os.replace` · umask 077 · 0600) → stdout 1줄 `OK <email> exp=<KST HH:MM> (<N>분) file=<토큰 파일 이름>` · exit 0.
   - 실패 = stdout 1줄 `ERR <email> http=<코드|net> msg=<응답 앞 200자 · 토큰·비밀번호 패턴 마스킹>` · exit 1 · ★토큰 파일은 안 건드린다(옛 토큰 보존)★. cred·설정 없음 = `ERR <email> 설정 없음: <파일 이름> — ft-op-token.sh --init <email> 1회` · exit 2.
   - `ft-op-token.sh --init <email>` = 1회 설정(= `/tmp/opcred.sh` 대체): 비밀번호를 클립보드(`pbpaste`)에서 1회 읽기 → 로그인 성공일 때만 cred 저장 + 토큰 저장 → 클립보드 비움 → 위 OK 줄. 실패면 cred 를 쓰지 않는다. (`!` 모드는 대화형 입력 불가 — 클립보드 1회가 유일한 사람 손.)
   - `ft-op-token.sh --list` = 계정 표의 email · 토큰 파일 · 남은 분(만료면 `만료`) — 토큰 원문 0.
2. **발급 방식 = password grant**(refresh_token 아님): Supabase refresh_token 은 한 번 쓰면 바뀌는 회전형이라 좌석 둘이 동시에 갱신하면 한쪽이 무효가 된다. password grant 는 동시 호출에 안전하고 planner 가 이미 cred 를 그 형식으로 저장했다. 대가 = 비밀번호 평문이 0600 파일에 있음 → 설계 5 보안 줄.
3. **설정 파일**(추적 밖 · `.fable-team/secrets/` · 0600): `op-auth.conf` = `SUPABASE_URL=` · `SUPABASE_PUBLISHABLE_KEY=` 2줄 · `op-accounts.tsv` = `email<TAB>cred 파일<TAB>토큰 파일` (기존 2계정 행 + byztest910 행). ★추적 파일에 URL·키·이메일 0★ — 키트·시험·카드 어디에도 값을 적지 않는다(시험은 가짜 값). `--init` 은 계정 표에 없는 email 이면 `ERR 계정 표에 없음` 으로 끝낸다(표 추가는 사람이 1줄 · 자동 추가 0).
4. **7초 룰**: `urllib.request.urlopen(timeout=7)` · 재시도 1회 = 네트워크 오류·타임아웃·5xx 일 때만(4xx = 비밀번호·계정 문제 → 재시도 0 · 바로 ERR) · 재시도 사이 대기 0.5 s · 총 상한 ≈ 14.5 s.
5. **보안**: 비밀번호는 argv·환경변수·로그·stdout 에 절대 안 나간다(파이썬이 cred 파일을 직접 읽음 · `--init` 은 `pbpaste` 출력을 파이프로 파이썬 stdin 에 넘김) · 토큰 원문 출력 0(만료 계산은 JWT payload 디코드만) · 실패 msg 는 `eyJ…`·`sb_…`·`"password"` 값 패턴 마스킹 뒤 200자 · secrets 폴더가 0700 아니거나 파일이 0600 아니면 ERR(권한을 고치는 대신 알림 — 조용한 수정 0).
6. **좌석 안내**: ①`~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md` 에 1줄(번호는 마지막 다음): 「운영 계정 토큰이 만료되면 사람에게 복사를 청하지 않는다 — `bash <루트>/.fable-team/bin/ft-op-token.sh <email>` 로 새로 받는다(cred 없으면 `--init` 1회만 사람 손 · 판정 675)」 → 스테이징 사본 + master cp. ②카드 템플릿 = `design/harness/TESTER-BRIEF-TEMPLATE.md` 에 같은 뜻 1줄(운영 계정을 쓰는 시험 절에). ③(판정 676) ①·② 두 곳 모두 같은 줄에 「좌석 조사·시험에서 secrets/·*.cred·토큰 파일 내용 출력 0 — 키 이름·존재·크기만(cut -d= -f1 · wc -c · test -s)」 문구를 함께 넣는다 — ★JSON cred 는 `=` 가 없어 `cut -d= -f1` 이 줄 전체를 찍는다(arch#24 실측 노출 원인) → JSON 은 `python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))))' <파일>` 로 키 이름만★.
7. **수동 경로 폐지 목록**: 추적 문서·스킬·홈 스킬에서 «콘솔·클립보드로 토큰을 받아 오라»는 안내를 `git grep`·`grep -r ~/.claude/skills` 로 찾아 표 1장(`design/harness/staged-675/MANUAL-TOKEN-PATHS.md` · 파일:행 · 현 문구 · 바꿀 문구). ★옛 기록(완성 카드·DA 판정문·스냅샷)은 바꾸지 않는다 — 현역 안내만 바꿀 후보★. 바꾸는 것은 이 카드 범위 밖(목록만 · master/arch 가 골라 별 단위).
8. 200줄 규칙 · 새 파일은 하네스 설치 목록(키트의 install 목록)에 추가.

## 구현 범위 (닫힌 목록 · 나노)
기존 근거 파일(읽기): `scripts/harness-install/fable-team/bin/ft-nano-spawn.sh`(키트 bin 폴더 위치 확인용) · `design/harness/TESTER-BRIEF-TEMPLATE.md` · 홈 ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md(읽기만) · /tmp/opcred.sh(읽기만 · 값 복사 금지).
아래는 전부 «새로 만든다»:
1. 키트 bin 폴더에 ft-op-token.sh + ft_op_token.py (설계 1~5) · 키트 설치 목록에 두 파일 추가.
2. 스테이징 design/harness/staged-675/COMM-GUIDE-BOOT.md (현 홈 정본 사본 + 설계 6① 1줄만) · `design/harness/TESTER-BRIEF-TEMPLATE.md` 에 설계 6② 1줄(추적 파일 직접 수정).
3. design/harness/staged-675/MANUAL-TOKEN-PATHS.md (설계 7).
4. 설정 예시 design/harness/staged-675/op-auth.conf.example · op-accounts.tsv.example — ★가짜 값만★.
5. 시험 tests/harness/test_ft_op_token.py (실 Supabase 0 · 로컬 스텁 서버 + 임시 secrets): T1 200 → 토큰 파일 교체·0600·stdout OK 줄에 토큰 원문 없음 T2 400 → ERR http=400 · 재시도 0 · 토큰 파일 그대로 T3 500 → 재시도 1회 뒤 ERR · 호출 2회 T4 8초 지연 → 7초 타임아웃 → 재시도 → ERR http=net · 총 15초 이내 T5 cred 없음 → exit 2 + `--init` 안내 T6 `--init`(가짜 pbpaste = PATH 앞 스텁) 성공 → cred·토큰 0600 · 실패 → cred 미작성 T7 stdout·stderr 전체에 비밀번호·토큰 원문 0(grep) T8 secrets 폴더 0755 → ERR T9 `--list` 만료 계산 T10 키트 두 파일·설정 예시 두 파일에 실 URL·키·실 이메일 문자열 0(패턴 = 호스트 `supabase.co` · 키 접두 `sb_publishable_` · 도메인 `@byourz.com` · 시험 파일 자신은 검사 대상에서 뺀다).
6. (판정 676) 재발 방지: 이 나노의 조사·시험 자체도 「좌석 조사·시험에서 secrets/·*.cred·토큰 파일 내용 출력 0 — 키 이름·존재·크기만(cut -d= -f1 · wc -c · test -s)」 — JSON 파일은 위 설계 6③ 의 키 이름 방식만. 시험 T7 에 «도구·시험 출력 어디에도 cred·토큰 내용 0» 유지.
커밋은 자기 브랜치, **push 금지**. **금지**: 실 Supabase 호출 · 루트 `.fable-team/`·홈 `~/.claude/` 쓰기(설치는 master) · 실 cred·토큰 파일 읽기 · 값 출력.

## 완료 조건 (닫힘 판정 기준 — ops 수락 판정문)
- 위 시험 rc=0 · ruff clean · arch 독립 재현 · ★구현 DA(Claude Opus · 보안) APPROVE 또는 2 HOLD 뒤 arch 서명★.
- (판정 676) 좌석 조사·시험에서 secrets/·*.cred·토큰 파일 내용 출력 0 — 키 이름·존재·크기만(cut -d= -f1 · wc -c · test -s · JSON 은 키 이름만) · BOOT·TESTER 템플릿 줄에 같은 문구.
- 카드 증거 줄: 세트: <40hex> · 시험: .venv/bin/python -m pytest --noconftest tests/harness/test_ft_op_token.py rc=0 · 이슈: 0.
- 루트 지침: 완료 그 턴에 증거 줄 + arch#24 에 `[완료·휴식]` 1통.
- ★랜딩 뒤 master 집행★: PR → 병합 → 키트 설치(설치본 cmp) → `op-auth.conf`·`op-accounts.tsv` 를 루트 secrets 에 손으로 1회 작성(값 = /tmp/opcred.sh 의 URL·키·계정 표 · 0600 · 출력 0) → 기존 cred 파일 이름을 표에 맞춤(`developer-ts.cred`·`admin-ts.cred`) → `ft-op-token.sh <각 email>` 실발급 1회씩 OK 줄 → BOOT 스테이징 cp+cmp → `/tmp/opcred.sh` 삭제 안내(planner) → planner#16 에 「토큰 수동 복사 끝 · 좌석은 ft-op-token.sh」 1줄.

## 상태
- base_sha: d0344ea0ce43e39adccdd319be740fc17565f12c (spawn 2026-10-09)
- 2026-10-09 — 대기/ 생성 (byz-harness-arch-claude#24 · 판정 675 · master#22 #68340).
- 정본 영향: COMM-GUIDE-BOOT 1줄 · TESTER-BRIEF-TEMPLATE 1줄 · 하네스 키트 새 도구 1.
- 2026-10-09 12:49 — 대기→진행 · 좌석 byz-harness-nano-op675-ft-op-token-auto-issue#0

## 결과
- 세트: 0e82391b40d3de67f33b378524fe6edca360be39 · 시험: .venv/bin/python -m pytest --noconftest tests/harness/test_ft_op_token.py rc=0 · 이슈: 0
정본 영향 없음: 제품 정본(docs/architect) 변경 없음 — 하네스 키트 새 도구 2·홈 BOOT 22·23조항·TESTER 템플릿 1줄(구현 DA APPROVE `b1fce39930` · arch 재현 #68387).
- 2026-10-09 13:01 — 진행→완성 · DA design/harness/OPS-VERDICTS-20261006.md#§109
