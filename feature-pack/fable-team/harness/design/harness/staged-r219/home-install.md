# R219 홈 설치 절차 — 비밀 출력 판정기에 «diff·sed·awk·python/node -c·git diff/show» 모양 추가

> 집행 = master (랜딩 뒤). 훅 등록(`~/.claude/settings.json` PreToolUse Bash → `secret-output-guard.sh`)은 R135a 로 이미 걸려 있어 **건드리지 않는다**. 바뀌는 것은 `~/.claude/hooks/` 안 파일뿐이다.
> 새 파일이 2개(`ft_secret_targets.py` · `ft_secret_sinks.py`) 늘었다 — 판정기가 `import` 하므로 **같이 복사하지 않으면 판정기가 내부 오류(rc2)로 죽고 훅은 fail-open(전부 통과)** 이다. 판정기와 새 파일 2개를 한 번에 넣는다.

`SHA` = 랜딩 커밋 40자, `REPO` = 루트 체크아웃, `T=scripts/harness-install/fable-team/templates/hooks`, `H=~/.claude/hooks`.

1. **백업** — `for f in ft_secret_judge.py ft_secret_lex.py; do cp -p $H/$f $H/$f.bak-r219; done` (되돌림: `cp -p $H/ft_secret_judge.py.bak-r219 $H/ft_secret_judge.py && rm $H/ft_secret_targets.py $H/ft_secret_sinks.py`)
2. **랜딩 커밋에서 꺼내 복사** — `for f in ft_secret_judge.py ft_secret_targets.py ft_secret_sinks.py ft_secret_lex.py; do git -C $REPO show $SHA:$T/$f > $H/$f; done` (루트 체크아웃의 현재 파일이 아니라 커밋에서 꺼낸다 — R135a 와 같은 규칙)
3. **cmp** — 네 파일 모두 `git -C $REPO show $SHA:$T/<파일> | cmp - $H/<파일>` 이 0, 그리고 `$T/` ↔ `scripts/fable-team-bin/` ↔ `scripts/harness-install/fable-team/bin/` 사본이 같음(`pytest tests/scripts/test_ft_secret_judge.py::test_kit_copies_are_byte_identical`).
4. **컴파일** — `python3 -m py_compile $H/ft_secret_judge.py $H/ft_secret_targets.py $H/ft_secret_sinks.py`
5. **실제 훅에서 거절 확인(7줄)** — 줄마다 아래를 쳐서 `permissionDecision":"deny"` 1줄이 나오는지 본다(명령은 실행되지 않고 표준입력 글자일 뿐이다):
   `printf '%s' '{"tool_input":{"command":"<줄>"}}' | bash $H/secret-output-guard.sh`
   줄: `diff .env .env.example` · `sed -n 1,20p .env` · `awk -F= '{print}' secrets/x.cred` · `python3 -c 'import os; print(os.environ)'` · `python3 -c 'import os;print(dict(os.environ))'` · `git diff -- .env` · `git show HEAD:.env`
   (JSON 안 따옴표는 이스케이프한다.) 통과해야 하는 3줄은 출력이 비어야 한다: `cut -d= -f1 .env` · `wc -c .env` · `git diff --stat`.
6. **실패 시** — deny 가 안 나오고 stderr 에 `판정기 실패` 가 보이면 새 파일이 빠진 것이다(2번 재실행). 그래도 안 되면 위 되돌림 1줄.

원장 R219 행 처리 칸(master): 병합 sha · 위 5번 7줄 deny 출력 1회 확인 · 설치 백업 경로 `~/.claude/hooks/*.bak-r219`.
