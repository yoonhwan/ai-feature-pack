#!/bin/bash
# PreToolUse hook — 파괴적/비가역 Bash 명령 차단 (HIL 강제)
# 신설 2026-06-09: FB_MR#8 세션을 HIL 없이 kill한 사고 재발방지.
# 데이터/인프라/세션 등 복구 불가 삭제를 시스템 레벨에서 차단한다.
# exit 2 = PreToolUse deny (stderr 메시지가 Claude에 피드백됨).

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('tool_input',{}).get('command',''))
except Exception:
    print('')" 2>/dev/null)

# 파괴/비가역 패턴 (대소문자 무시)
# 2026-07-11 예외: tmux kill-session은 하드블록에서 제외(사용자 명시 표준승인 —
# "tmux,tmuxc는 컨트롤해도됨", cmux 메모리 고갈 방지 위한 상시 세션 정리 목적).
# kill-server(전체 서버 종료, 모든 세션 동시 파괴)는 그대로 차단 유지. R44: push 는 원격 ref 를 덮거나 지우는 꼴(+ref · :ref · --delete/-d · --mirror)도 force 와 같이 차단. r591: -f 도 옵션 자리(앞 공백)만 — 이름 끝 -f 오탐.
PATTERN='tmux kill-server|rm -[rf][rf]|rm -[rf] +-[rf]|gcloud [a-z0-9 _-]*(delete|destroy)|DROP +(TABLE|DATABASE|SCHEMA)|TRUNCATE +TABLE|dropdb|terraform +destroy|kubectl +delete|git +push[^&|;]*(--force|[[:space:]]-f\b|--mirror|--delete|[[:space:]]-d\b|[[:space:]]\+[^[:space:]]|[[:space:]]:[^[:space:]])|git +worktree +remove|git +branch +-D|supabase [a-z0-9 _-]*delete|kill -9|pkill'

# ── 판정 466: «글자로만 들어 있는» 파괴 명령은 통과, «실행되는» 파괴 명령만 차단 ──
# 명령을 구간(; && || | & 개행)으로 나눠 글 싱크(echo·printf·정본 mbox 송신·git commit·grep·대입·cat/tee heredoc
# 본문)의 인자 글자만 PATTERN 에서 뺀다. 나머지 구간은 원문 그대로(따옴표 안 포함) PATTERN — bash -c·psql -c 도 그대로 차단.
# 예외 자격 없음(실행 소비자·치환·파일 쓰기 뒤 소비·파이프 소비·파싱 실패) = 명령 전체에 PATTERN (이전 동작, fail-closed).
# 판정기 = 같은 폴더 block-destructive-judge.py (판정 466 · 없거나 실패하면 아래 || 로 명령 전체에 PATTERN — fail-closed)
JUDGE="$(dirname "${BASH_SOURCE[0]}")/block-destructive-judge.py"
judge() { python3 "$JUDGE" "$@"; }
EFFECTIVE=$(judge "$CMD" "$INPUT" 2>/dev/null) || EFFECTIVE=$CMD

# R115: git 전역 옵션(-C·-c·--git-dir·--work-tree·--no-pager 등 `-` 로 시작하는 낱말과 그 값)을 걷은 사본 NORM 에도 PATTERN.
# 판정기가 따옴표를 풀어 `-C '/a b'` 의 값이 쪼개지므로 값 모양을 따지지 않고 «옵션 시작 ~ 파괴 하위명령» 사이를 접는다.
# 검사 대상이 EFFECTIVE «또는» NORM 이라 차단만 늘고 통과는 늘지 않는다.
NORM=$(printf '%s' "$EFFECTIVE" | LC_ALL=C sed -E 's/git[[:space:]]+-[^;&|]*[[:space:]](worktree[[:space:]]+remove|branch[[:space:]]+-[Dd]|push)/git \1/g') || NORM=$EFFECTIVE
if printf '%s\n%s' "$EFFECTIVE" "$NORM" | grep -qiE "$PATTERN"; then
  printf '🚫 파괴적/비가역 명령 차단 — HIL(사람 승인) 필수\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '데이터/인프라/세션을 복구 불가하게 삭제할 수 있습니다. yoonhwan 오빠의 명시 승인을 받은 뒤에만 진행하세요. (정당한 경우 사용자가 직접 ! 로 실행하거나 승인)\n' >&2
  exit 2
fi

# INJECT-BEGIN
# ── R63b 측정 조작 차단 (오빠 절대지침 2026-10-09 · BOOT 20 · 전역 하드 룰 11) ───
# 명령줄에서 직접 치는 임의 Redis 쓰기(redis-cli + 상태 생성 동사)와 말풍선 재생 URL(/dev/bubble-replay)을 실행 전에 막는다.
# ★EFFECTIVE 를 본다★ — STAGE 처럼 $CMD 를 보면 쪽지 본문·grep 패턴 글자로 막힌다(판정 466 이 고친 오탐 15건/일).
# 검색(git grep·rg·ag)·게시(gh pr/issue) 구간과 페이지 파일 경로는 검사 사본 CHK 에서 뺀다 — arch 재현 오탐 7건(r1). EFFECTIVE 자체는 불변.
# Redis 는 «명령 자리의 동사»만: redis-cli 뒤 옵션(값 0~1개)만 오고 첫 토큰이 동사 + 인자 1개 이상 (`GET set`·`CONFIG SET` 은 안 맞는다).
INJECT_VERBS='SET|SETEX|SETNX|MSET|HSET|HMSET|HSETNX|XADD|PUBLISH|LPUSH|RPUSH|SADD|ZADD|APPEND|INCR|INCRBY'
INJECT_SKIP='(^|[[:space:];&|(])(git[[:space:]]+grep|rg|ag|gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|edit|view))([[:space:]][^;&|]*|$)'
INJECT_REDIS="redis-cli([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]*)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+['\"]?($INJECT_VERBS)['\"]?[[:space:]]+[^[:space:]]"
INJECT_PATTERN="$INJECT_REDIS|/dev/bubble-replay"
# X7: 쓰기 동사가 argv 밖(파이프 수신·stdin 리다이렉트·xargs·동사 자리 치환)으로 들어오는 꼴. 정규식 안 백틱은 \` 로 이스케이프(안 하면 대입 순간 명령 치환 → 전 명령 차단).
# stdin 리다이렉트는 '<' 가 든 따옴표 인자(GET '<k>')를 Q 로 비운 사본 CHK_R 에서만 본다(DA x7 r1 Q2).
INJECT_STDIN='redis-cli[^;&|]*<'
INJECT_PATTERN="$INJECT_PATTERN|(^|[^|])[|][[:space:]]*([^|;&]*[[:space:]])?redis-cli|xargs[^;&|]*redis-cli|redis-cli([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]*)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+([\$][(]|\`)"
# 실행 치환($( )·백틱·<( )·>( ))이 하나라도 있으면 검색·게시 예외 0 — 셸이 «실행»하는 구간이라 글자가 아니다(DA r1 Q2).
INJ_SRC=$(judge --inject "$CMD" "$INPUT" 2>/dev/null) || INJ_SRC=$EFFECTIVE   # 판정 595: 게시 싱크의 따옴표 heredoc 본문은 글자(실행 경로는 EFFECTIVE 와 같이 전체 검사)
case "$INJ_SRC" in
  *'$('*|*'`'*|*'<('*|*'>('*) INJECT_SED='s#app/dev/bubble-replay##g' ;;
  *) INJECT_SED="s#$INJECT_SKIP#\\1#g; s#app/dev/bubble-replay##g" ;;
esac
# 따옴표·역슬래시 제거 — 셸 단어 이어붙임(redis-''cli·S""ET)을 한 단어로 본다(DA r2 Q2). 검색·게시 제거(sed)가 먼저라 따옴표 안 검색 패턴은 이미 빠진 뒤.
# 줄 잇기 — 끝이 \ 또는 | 인 줄은 다음 줄과 한 줄로(셸은 그렇게 실행한다 · grep 은 줄 단위 · DA x7 r1 Q1).
INJ_J=$(printf '%s\n' "$INJ_SRC" | awk '{ if (sub(/\\$/, " ") || sub(/[|][[:space:]]*$/, "| ")) printf "%s", $0; else print }') || INJ_J=$INJ_SRC
CHK=$(printf '%s' "$INJ_J" | LC_ALL=C sed -E "$INJECT_SED" | LC_ALL=C tr -d "\\\\'\"") || CHK=$INJ_J
# R108: xargs 꼴(X7)에서 redis-cli 옵션 뒤 «첫 토큰»이 읽기 동사면 그 일치만 XARGSREAD 로 바꾼다(옵션 값 규칙은 고정 목록 · 모르는 옵션·$·백틱·{}·동사 없음·쓰기 동사는 그대로 차단 · 파이썬 실패면 CHK 불변).
INJECT_READ_VERBS='HKEYS|HGET|HGETALL|HMGET|HLEN|HSTRLEN|HEXISTS|GET|MGET|STRLEN|TYPE|TTL|PTTL|EXISTS|SCAN|HSCAN|SSCAN|ZSCAN|KEYS|XLEN|XRANGE|XREVRANGE|XINFO|LLEN|LRANGE|SMEMBERS|SCARD|SISMEMBER|ZRANGE|ZCARD|ZSCORE|DBSIZE|INFO|MEMORY USAGE|OBJECT ENCODING'
CHK_X=$(python3 -c '
import re,sys
s,rv=sys.argv[1],set(sys.argv[2].split("|"))
VAL=set("-h -p -s -a -u -n -r -i -d --user --pass --pattern --count --type".split())
FLAG=set("-c -e -x -3 --raw --no-raw --scan --no-auth-warning --tls --insecure --csv".split())
OK=re.compile(r"^[A-Za-z0-9_.:@/%+=,-]+$")
def verb_end(t):
    i=0
    while i<len(t) and t[i][0].startswith("-"):
        o=t[i][0]
        if not OK.match(o): return 0
        if o.split("=")[0] in VAL and "=" in o or o in FLAG: i+=1; continue
        if o not in VAL or i+1>=len(t) or not OK.match(t[i+1][0]): return 0
        i+=2
    if i>=len(t): return 0
    v=t[i][0].upper()
    if v in rv: return t[i][1]
    return t[i+1][1] if i+1<len(t) and v+" "+t[i+1][0].upper() in rv else 0
def swapped(x,cons):
    # xargs 치환 옵션(-I/-J R · -IR · -iR · --replace=R · 인자 없는 -i/--replace={}) 의 R 이 첫 토큰~동사 끝에 있으면 stdin 값이 동사를 바꾼다
    R,i=[],0
    while i<len(x):
        t=x[i]; n=x[i+1] if i+1<len(x) else ""
        if t.startswith("--replace="): R.append(t[10:])
        elif t=="--replace": R+=["{}"]+([n] if n.lower()!="redis-cli" else [])
        elif t[:1]=="-" and t[:2]!="--":
            for k,ch in enumerate(t[1:],1):   # 결합 단축 옵션(-tIGET·-tI GET·-ti)을 풀어 읽는다 — 값을 받는 옵션은 나머지 글자가 값
                a=t[k+1:]
                if ch in "IJ": R.append(a or n); i+=0 if a else 1; break
                if ch=="i": R+=[a or "{}"]+([] if a or n.lower()=="redis-cli" else [n]); break
                if ch in "nPLsEdalCe": break
        i+=1
    return any(not q or q in cons or q in "redis-cli" for q in R)
o,p=[],0
for m in re.finditer(r"xargs(?:(?!redis-cli)[^;&|\n])*redis-cli",s,re.I):
    r=s[m.end():]; c=re.search(r"[;&|\n]",r); r=r[:c.start()] if c else r
    e=verb_end([(x.group(),x.end()) for x in re.finditer(r"\S+",r)])
    if e and swapped(m.group().split(),r[:e]): e=0
    if e: o+=[s[p:m.start()],"XARGSREAD"]; p=m.end()+e
sys.stdout.write("".join(o)+s[p:])' "$CHK" "$INJECT_READ_VERBS") && CHK=$CHK_X
# 비우는 것은 «redis-cli 가 안 든» 따옴표 구간뿐 — bash -c "redis-cli < f"·os.system('redis-cli < f') 는 실행 코드라 남긴다(DA x7 r2 Q1 · 표지 \001).
INJ_MARK=$(printf '\001')
CHK_R=$(printf '%s' "$INJ_J" | LC_ALL=C sed -E "s/[Rr][Ee][Dd][Ii][Ss]-[Cc][Ll][Ii]/$INJ_MARK/g; s/'[^'$INJ_MARK]*<[^'$INJ_MARK]*'/Q/g; s/\"[^\"$INJ_MARK]*<[^\"$INJ_MARK]*\"/Q/g; s/$INJ_MARK/redis-cli/g; $INJECT_SED" | LC_ALL=C tr -d "\\\\'\"") || CHK_R=$CHK
if printf '%s' "$CHK" | grep -qiE "$INJECT_PATTERN" || printf '%s' "$CHK_R" | grep -qiE "$INJECT_STDIN"; then
  printf '🚫 측정 조작 차단 — 임의 Redis 쓰기·말풍선 DOM 주입(오빠 절대지침 · BOOT 20 · 전역 하드 룰 11)\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '측정은 trusted 클릭 + 기존 e2e 러너(tests/e2e/realtime_multi_e2e.py)만. 정당한 운영 쓰기는 파일에 쓰고 사람이 ! 로 실행하세요.\n' >&2
  exit 2
fi
# INJECT-END

# ── 스테이징 오염 차단 (신설 2026-09-16, CFO 트랙 규율 F17) ──────────────────
# 같은 워크트리를 여러 세션이 동시에 쓰면 `git add .`/`-A` 가 "남이 만든 파일"까지
# 자기 커밋에 싣는다. 2026-09-15 하루에 세 번 났고, 한 번은 코드 3파일이 다른 세션의
# 문서 커밋에 섞여 구조/문서 혼합(Tidy First 위반)까지 갔다.
# ★파괴적이지 않지만 되돌리기 어렵다★ — 공유 브랜치라 히스토리 재정리가 위험하다.
# ★이 훅이 막지 못하는 것★: `git add <디렉토리>/` 형태. 그것도 같은 사고를 내지만
# 의도적인 경우가 많아 차단하지 않는다 — 그건 사람이 판단한다.
# ★알려진 오탐(허용)★: 명령문 안에 문자열로 들어 있기만 해도 차단된다(문서·echo·주석 포함).
#   위 파괴 패턴도 같은 성질이고(`rm -rf` 를 문장에 쓰면 차단), 이 훅의 관행이다.
#   ★정교하게 파싱하지 않는 이유★: 판정기를 촘촘하게 만들수록 예외 목록이 자라고,
#   예외가 자라면 그 판정기는 결국 아무것도 안 막는다(2026-09-15 CFO 트랙에서 배운 것).
#   막히면 우회하지 말고 파일에 써서 실행하거나 사람이 직접 실행한다.
#   ★글 싱크 닫힌 목록으로 바꾼 이유(판정 466)★: 쪽지 본문·echo·heredoc 으로 쓰는 시험 파일·grep 패턴의 «글자»가 하루 15건 넘게
#   오탐이었고 실제 파괴는 0 이었다. 예외 목록이 아니라 «6종 싱크 + 나머지 전부 이전 규칙»이라 목록 자체를 늘리는 것도 판정 사항이다.
# ★경계를 요구한다★ — 뒤에 공백이나 줄끝이 와야 「전체 스테이징」이다.
#   2026-09-16 실측 오탐: 경계가 없으면 숨김 폴더로 시작하는 경로(.claude/… .github/… 등)의
#   맨 앞 점이 「전체」로 오인돼 정당한 경로 지정까지 막았다. 구현 좌석이 그 자리에서 걸렸다.
STAGE_PATTERN='git +add +(\.([[:space:]]|$)|-A([[:space:]]|$)|--all([[:space:]]|$))'
if printf '%s' "$CMD" | grep -qE "$STAGE_PATTERN"; then
  printf '🚫 git add . / -A 차단 — 스테이징 오염 방지 (CFO 규율 F17)\n' >&2
  printf '명령: %s\n' "$CMD" >&2
  printf '같은 워크트리를 다른 세션이 동시에 쓰고 있으면 남의 파일까지 커밋에 실립니다.\n' >&2
  printf '대신: (1) git status 로 스테이징에 내가 안 만진 파일이 있는지 보고 (2) git add <내 파일 경로들> 로 경로를 지정하세요.\n' >&2
  printf '그래도 섞이면 "섞였다"고 보고하고, 히스토리 재정리는 하지 마세요(공유 브랜치).\n' >&2
  exit 2
fi
exit 0
