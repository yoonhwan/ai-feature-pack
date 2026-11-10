# ORDER — P10 사실 수집 (ft-harness-arch#3 → ft-harness-nano#1 · 2026-10-05 · 읽기 전용)

> 골 원문(GOAL-harness.md 복붙):
> 내부 하네스, 내부 스킬스를 모니터하고 요청을 사용자에게 받아 해당 부분 바로 확인 검토하고. 실제 하네스와 스킬스를 업그레이드하고 레포에 커밋 푸시하며 전 환경에 물리적 컴퓨팅 환경에도 설치하도록 배포 발행(슬랙) 수신해 반영되 업그레이드.
> 하네스 스킬 관리 오케는 메인오케들과 위성오케들에게 개선요청을 직접받아 등록관리하고 사용자와 협의해 개선하는 축도 필요함.
> 정말 많은 양의 이슈와 테스트, 그리고 큰 병렬적인 메인 플랜(메인 기획)을 얼마나 잘 수행해내느냐에 핵심이 달려 있는 거예요. 지금 이 골(Goal)들은 그 세부 항목들을 다 잘 처리해서, 결국엔 그 루트인 큰일을 얼마나 별개로 쪼개서 동시에 아주 잘 해결하느냐에 달려 있는 거죠. 이게 기획에 반영되어야 해요.
> 골의 축: 표 A(모니터·오빠 요청 → Issue) · 표 B(접수·협의) · 원문 7(많은 이슈를 쪼개 동시에). 이 발주 = 상위 ORDER-issue-manager-slack-tmm-20261005.md 할 일 1(사실).

## 규칙 (HARD)
- **읽기 전용**: `gh` 는 `list`·`view`·`api GET` 만 · 서버·launchd·슬랙·tmm 설정 변경 0 · 커밋 0(ops).
- **시크릿 0**: 토큰·webhook URL·채널 ID 값 0. 파일 경로·변수 이름·개수만.
- 줄마다 **[사실] 출처**(명령 그대로 또는 `파일:줄`) · 못 보면 **[추측]**.
- 산출 1장: `design/teams/harness/issue-improvement/FACTS-P10-20261005.md` · 끝나면 mbox 로 arch 에 「완료 · 줄 수 · [추측] 수」 3줄. 상한 10분 · 명령 출력은 40줄씩.

## 1. GitHub 열린 Issue 현황
```bash
cd /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops; unset GH_TOKEN
gh issue list --state open --limit 200 --json number,title,labels,createdAt,updatedAt,assignees > /tmp/p10-issues.json
python3 - <<'EOF'
import json,collections,datetime
d=json.load(open('/tmp/p10-issues.json'));now=datetime.datetime.now(datetime.timezone.utc)
print('open',len(d))
lab=collections.Counter(l['name'] for i in d for l in i['labels']);print('labels',lab.most_common(40))
age=[(now-datetime.datetime.fromisoformat(i['createdAt'].replace('Z','+00:00'))).days for i in d]
print('age days: min',min(age),'median',sorted(age)[len(age)//2],'max',max(age),'>30d',sum(a>30 for a in age))
print('no team label',sum(not any(l['name'].startswith('team:') for l in i['labels']) for i in d))
print('priority-ish labels',[k for k in lab if any(w in k.lower() for w in ('p0','p1','p2','prio','urgent','live'))])
print('assigned',sum(bool(i['assignees']) for i in d))
EOF
gh label list --limit 100 | cut -c1-60
```
적을 것: 열린 수 · 라벨 축(team·type·phase·status) 분포 · 나이 · 우선순위 라벨 존재 여부 · 담당 지정 수.

## 2. issue-manager 의 현재 루프
```bash
ls design/issues/ design/issue-manager/ 2>/dev/null | head -30
find design -iname '*LOOP-LEDGER*' -o -iname '*issue-manager*' | head -20
cat /Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.fable-team/seats-issues.json | python3 -c "import json,sys;d=json.load(sys.stdin);[print(k,v.get('role'),v.get('model'),v.get('_session'),v.get('tick')) for k,v in d.items() if not k.startswith('_')];print({k:v for k,v in d.items() if k.startswith('_')})"
tmux list-sessions -F '#{session_name}' | grep -iE 'issue|repro'
ls ~/Library/LaunchAgents | grep -iE 'issue|repro'
grep -rn "gh issue\|Issue 생성\|배분\|랜딩\|close" $(find design -iname '*LOOP-LEDGER*' | head -2) 2>/dev/null | head -40
```
적을 것: 좌석 실재(세션·tick) · 주기 실행 장치 있나 · LOOP-LEDGER 에서 「가져오기→해결→완성→기록」 전부 한 실례 N건 vs 「등록·배분만」 N건(Issue 번호로).

## 3. tmm 이 지금 하는 일
```bash
ls ~/.tmm/ ~/.tmm/current/ 2>/dev/null | head -30
tmm h 2>&1 | head -60 ; tmm --help 2>&1 | head -40
grep -rn "tmm" ~/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md design/teams/harness/issue-improvement/SPEC-session-naming-20261005.md | head -15
cat ~/.tmm/categories 2>/dev/null | head -30
```
적을 것: 명령 목록 · 탭/그룹 키(팀과 연결 여부) · 질문(AskUserQuestion) 보이기 · 알림 · 한계(인터랙션 가능한 것/아닌 것).

## 4. 슬랙 현황
```bash
ls ~/Library/LaunchAgents | grep -iE 'slack|mirror|inbound|hermes'
launchctl list | grep -iE 'slack|mirror|inbound|hermes' 
ls scripts/harness-install/slack-mirror/ ; grep -n "channel\|post\|inbound\|answer" scripts/harness-install/slack-mirror/*.sh 2>/dev/null | grep -v "xox\|http" | head -20
grep -rln "슬랙\|slack" design/teams/harness/*.md design/teams/harness/issue-improvement/*.md design/planner/*.md | head -20
grep -n "슬랙\|slack" design/teams/harness/issue-improvement/MERGED-20261005.md design/teams/harness/DESIGN-slack-inbound-820.md | cut -c1-200 | head -30
gh issue view 820 --json title,state,labels | head -20
ls ~/.hermes/channel_roles 2>/dev/null | head; grep -n "slack" ~/.hermes/config.yaml 2>/dev/null | grep -viE "token|secret|key|hook" | head -10
```
적을 것: 3 데몬 로드 여부(bootout) · hermes 가 슬랙에 올리는 것(채널 이름만) · 지금 실제로 슬랙에 올라가는 글 종류 · 슬랙 «수신(인바운드)»에 기대는 조각 목록(#820 · P1 질문 원장 · MERGED C3 · 표 C 배포 수신 · jarvis) 각 1줄 + 출처.
