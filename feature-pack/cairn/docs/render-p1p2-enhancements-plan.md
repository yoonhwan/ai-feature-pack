# cairn 뷰어 P1/P2 후속 개선 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** cairn 웹 뷰어에 의존위반 soft-warn·MS 편집·칸반 드래그·접기·진행률·주말음영·zoom-fit·담당자필터 8종을 추가한다.

**Architecture:** 전 항목 프론트엔드(`docs/plan-view.template.html`) 전용. 편집은 P0의 `apply_ops`(set/set-ms/remove-milestone) op만 재사용 — 서버 코드 무변경. soft-warn·필터는 클라이언트 계산·표시 전용(원장·validate 무변경).

**Tech Stack:** 순수 HTML/CSS/JS 템플릿(mermaid CDN), Python 생성기(`core/cairn.py`의 `build_view_html`/`to_view`), pytest.

## Global Constraints

- 편집 = ops 체인지셋만(`pushSet`/`ops.push`) — 뷰JSON 역매핑·전체직렬화 금지.
- 저장 = 싱크 버튼 → `web_save` → `transaction()` 1회. 신규 서버 쓰기 경로 0.
- `execution_ref`/`branch`는 어떤 편집도 건드리지 않음(읽기전용).
- soft-warn은 **클라 계산·표시 전용** — 원장 validate 호출 금지, 스키마 무변경.
- 편집 UI는 `CAN_EDIT`(serve+http)일 때만 활성. 정적 `file://`는 읽기전용 유지.
- 대상 파일: `feature-pack/cairn/docs/plan-view.template.html` (별도 명시 없으면 이 파일).
- 데이터 블록 마커 `const plan = ` / `// ==== 데이터 끝 ====` 를 절대 훼손하지 말 것(`build_view_html` 치환 전제).

## 공통 검증 절차 (매 태스크 끝에서 실행)

```bash
WT=/Users/yoonhwan/Project/ai-feature-pack/.worktrees/cairn-p1p2/feature-pack/cairn
# ① JS 문법
~/.cairn/venv/bin/python - << 'PY'
import re,subprocess,shutil
html=open("$WT/docs/plan-view.template.html".replace("$WT","%s"%__import__("os").environ.get("WT","")) ) if False else open("/Users/yoonhwan/Project/ai-feature-pack/.worktrees/cairn-p1p2/feature-pack/cairn/docs/plan-view.template.html").read()
scripts=re.findall(r"<script>(.*?)</script>", html, re.S)
js="\n".join(s for s in scripts if "renderSchedule" in s or "const plan" in s)
open("/tmp/_c.js","w").write(js)
print("node --check rc=",subprocess.run([shutil.which("node"),"--check","/tmp/_c.js"],capture_output=True,text=True).returncode)
PY
# ② 렌더 스모크(요소 임베드) — 각 태스크의 확인 문자열로 grep
# ③ 백엔드 무변경 회귀
cd "$WT/test" && PYTHONPATH=../core ~/.cairn/venv/bin/python -m pytest -q 2>&1 | tail -3   # 235 passed 유지
```

단순화를 위해 각 태스크는 아래 스모크 헬퍼를 쓴다(schedule 예제 렌더 후 문자열 존재 확인):

```bash
render_check(){  # 사용: render_check "찾을문자열1" "찾을문자열2" ...
  cd /Users/yoonhwan/Project/ai-feature-pack/.worktrees/cairn-p1p2/feature-pack/cairn
  ~/.cairn/venv/bin/python - "$@" << 'PY'
import sys; sys.path.insert(0,"core"); import cairn
data=cairn.load_plan(cairn.Path("docs/examples/schedule-plan.example.yaml"))
html=cairn.build_view_html(data,"q3-launch",token="TOK",base_hash="H")
ok=all(m in html for m in sys.argv[1:])
print("RENDER_CHECK", "OK" if ok else "FAIL", [m for m in sys.argv[1:] if m not in html])
assert ok
PY
}
```

---

### Task 1: 드래그 의존위반 soft-warn

**Files:**
- Modify: `docs/plan-view.template.html` (CSS `.sg-today` 블록 뒤, JS `renderSchedule`/`wireDrag`)

**Interfaces:**
- Consumes: `allTasks()`, `SCHED`, `wireDrag`의 mouseup 훅, `renderSchedule` 말미.
- Produces: `computeViolations()→Set<tid>`, `markViolations()`, `toast(msg)` — Task 없음(내부용).

- [ ] **Step 1: CSS 추가** — `.sg-drag-tip{...}` 정의 바로 뒤에 삽입:

```css
  .sg-bar.dep-violation{outline:2px dashed #d9822b;outline-offset:-1px}
  .sg-toast{position:fixed;left:50%;bottom:32px;transform:translateX(-50%);z-index:60;
    background:var(--panel);border:1px solid #d9822b;color:var(--text);border-radius:8px;
    padding:8px 16px;font-size:13px;box-shadow:0 6px 20px rgba(0,0,0,.4);display:none}
```

- [ ] **Step 2: 계산·표시 함수 추가** — `_clearDepHl` 함수 정의 바로 앞에 삽입:

```javascript
function computeViolations(){
  const v=new Set(), byId={}; allTasks().forEach(t=>byId[t.id]=t);
  allTasks().forEach(t=>{
    const s=t.start; if(!s)return;
    (t.dep||[]).forEach(pid=>{ const p=byId[pid];
      if(p&&p.due&&new Date(p.due)>new Date(s)) v.add(t.id); });
  });
  return v;
}
function markViolations(){
  const sc=document.getElementById("ganttscroll"); if(!sc)return new Set();
  sc.querySelectorAll(".sg-bar.dep-violation").forEach(b=>b.classList.remove("dep-violation"));
  const v=computeViolations();
  v.forEach(tid=>{ const r=sc.querySelector(`.sg-row[data-tid="${tid}"]`);
    const b=r&&r.querySelector(".sg-bar"); if(b)b.classList.add("dep-violation"); });
  return v;
}
function toast(msg){
  let t=document.getElementById("sgToast");
  if(!t){t=document.createElement("div");t.id="sgToast";t.className="sg-toast";document.body.appendChild(t);}
  t.textContent=msg; t.style.display="block"; clearTimeout(t._t);
  t._t=setTimeout(()=>{t.style.display="none";},3000);
}
```

- [ ] **Step 3: renderSchedule 말미에 markViolations 호출** — `renderSchedule` 함수의 `wireSchedule();` 바로 뒤에 `markViolations();` 추가.

- [ ] **Step 4: 드래그 종료 시 신규 위반 토스트** — `wireDrag`의 mouseup 콜백 마지막 줄 `markDirty(); renderSchedule(); fixupSchedule();` 를 아래로 교체:

```javascript
    markDirty(); renderSchedule(); fixupSchedule();
    const v=computeViolations();
    if(v.has(d.t.id)) toast(`⚠ ${d.t.id}: 선행이 이후에 끝남 — soft(저장은 됩니다)`);
```

- [ ] **Step 5: 검증**

```bash
render_check "dep-violation" "computeViolations" "sg-toast"
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 6: Commit**

```bash
git add feature-pack/cairn/docs/plan-view.template.html
git commit -m "[기능] 간트 드래그 의존위반 soft-warn — 클라 계산·주황 점선·토스트(저장 허용)"
```

---

### Task 2: 마일스톤 필드편집 다이얼로그 (set-ms UI)

**Files:**
- Modify: `docs/plan-view.template.html` (섹션행 마크업·`renderTree` MS 행·body click 위임·다이얼로그 함수군)

**Interfaces:**
- Consumes: `pushSet`, `ops`, `dlg`, `STATUS_MS`, `plan.milestones`, `markDirty`, `renderAll`, `refreshSchedIfActive`, `EDIT.pid`.
- Produces: `openMilestone(mid)`, `saveMsForm()`, `deleteMilestone()`.

- [ ] **Step 1: 마일스톤 행에 data-mid 부여** — 간트 섹션행(`renderSchedule` 내 `<div class="sg-row section">`)과 트리 MS 행에 `data-mid="${m.id}"` 추가. 간트 섹션행:

```javascript
    rows+=`<div class="sg-row section" data-mid="${m.id}"><div class="sg-label sec"><span class="badge ${mstat}">${m.id}</span> ${esc(m.name)}</div><div class="sg-track">${msMark}</div></div>`;
```

트리 뷰의 마일스톤 헤더 행(`renderTree` 내)에도 동일하게 `data-mid` 추가(해당 줄 확인 후 삽입).

- [ ] **Step 2: body click 위임에 MS 분기** — `document.body.addEventListener("click",...)` 안, `const el=e.target.closest("[data-tid]");` 앞에 삽입:

```javascript
  const mel=e.target.closest("[data-mid]");
  if(mel && !e.target.closest("[data-tid]")){ openMilestone(mel.dataset.mid); return; }
```

- [ ] **Step 3: 다이얼로그 함수 추가** — `deleteTask` 함수 정의 바로 뒤에 삽입:

```javascript
function openMilestone(mid){
  const m=plan.milestones.find(x=>x.id===mid); if(!m)return;
  if(!CAN_EDIT){ return; }   // 읽기전용: MS 편집 UI 없음
  const row=(k,v)=>`<div class="mrow"><span class="mk">${k}</span><span class="mv">${v}</span></div>`;
  const inp=(id,v,type)=>`<input class="fedit" id="${id}" type="${type||'text'}" value="${_av(v)}">`;
  const opt=STATUS_MS.map(s=>`<option value="${s}"${s===m.status?' selected':''}>${s}</option>`).join("");
  const empty=(m.tasks||[]).length===0;
  const body=row("상태",`<select class="fedit" id="m_status">${opt}</select>`)
    +row("이름",inp("m_name",m.name))
    +row("start",inp("m_start",m.start||"","date"))
    +row("end",inp("m_end",m.end||"","date"))
    +row("선행(depends_on)",inp("m_dep",(m.dep||m.depends_on||[]).join(", "))+`<span class="fhint">쉼표 구분 ms id</span>`);
  const foot=`<div class="modalfoot">`+
    (empty?`<button class="mbtn danger" id="m_del">마일스톤 삭제</button>`:`<span class="fhint">태스크가 있어 삭제 불가</span>`)+
    `<span style="flex:1"></span><button class="mbtn" data-close="1">취소</button><button class="mbtn primary" id="m_save">확인</button></div>`;
  dlg.innerHTML=`<div class="modalhead"><div><span class="tid">${m.id}</span> · 마일스톤</div>`+
    `<button class="mclose" data-close="1">✕</button></div><div class="modalname">${esc(m.name)}</div>`+body+foot;
  dlg._ms=m; dlg._task=null; dlg.showModal();
}
function saveMsForm(){
  const m=dlg._ms; if(!m)return; const g=id=>dlg.querySelector(id);
  const pushMs=(field,value)=>ops.push({op:"set-ms",target:[EDIT.pid,m.id],field,value});
  const name=g("#m_name").value.trim(); if(name&&name!==m.name){ pushMs("name",name); m.name=name; }
  const st=g("#m_status").value; if(st!==m.status){ pushMs("status",st); m.status=st; }
  const setOpt=(field,key,raw)=>{ const cur=m[key]||"", nv=(raw||"").trim();
    if(nv!==cur){ pushMs(field,nv); if(nv)m[key]=nv; else delete m[key]; } };
  setOpt("start","start",g("#m_start").value); setOpt("end","end",g("#m_end").value);
  const depCur=(m.dep||m.depends_on||[]).join(", "), depNv=g("#m_dep").value;
  if(depNv.trim()!==depCur.trim()){ const arr=depNv.split(",").map(s=>s.trim()).filter(Boolean);
    pushMs("depends_on",arr); m.dep=arr; }
  markDirty(); dlg.close(); renderAll(); refreshSchedIfActive();
}
function deleteMilestone(){
  const m=dlg._ms; if(!m)return;
  if((m.tasks||[]).length){ alert("태스크가 있어 삭제할 수 없습니다"); return; }
  if(!confirm(`마일스톤 ${m.id} 삭제?`))return;
  ops.push({op:"remove-milestone",target:[EDIT.pid,m.id]});
  plan.milestones=plan.milestones.filter(x=>x.id!==m.id);
  markDirty(); dlg.close(); renderAll(); refreshSchedIfActive();
}
```

- [ ] **Step 4: dlg click 리스너에 MS 저장/삭제** — `dlg.addEventListener("click",...)` 안, `if(e.target.id==="f_save")` 앞에 삽입:

```javascript
  if(e.target.id==="m_save"){ saveMsForm(); return; }
  if(e.target.id==="m_del"){ deleteMilestone(); return; }
```

- [ ] **Step 5: 검증**

```bash
render_check "openMilestone" "set-ms" 'data-mid'
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 6: Commit**

```bash
git commit -am "[기능] 마일스톤 필드편집 다이얼로그 — set-ms/remove-milestone op(백엔드 기존 재사용)"
```

---

### Task 3: 칸반 status 드래그

**Files:**
- Modify: `docs/plan-view.template.html` (`renderKanban` 카드/컬럼 마크업 + 드래그 와이어)

**Interfaces:**
- Consumes: `renderKanban`, `pushSet`, `TASKMAP`, `markDirty`, `renderAll`, `refreshSchedIfActive`, `CAN_EDIT`, `SLABEL`.
- Produces: `wireKanbanDrag()`.

- [ ] **Step 1: 카드에 draggable, 컬럼에 data-col** — `renderKanban`에서 컬럼 컨테이너에 `data-col="${key}"`, 카드에 `${CAN_EDIT?'draggable="true"':''}` 추가. (컬럼 렌더 루프의 컬럼 div와 `kcard` div 수정.)

- [ ] **Step 2: 드래그 와이어 함수 추가** — `renderKanban` 함수 정의 바로 뒤에 삽입:

```javascript
function wireKanbanDrag(){
  if(!CAN_EDIT)return;
  const root=document.getElementById("kanban"); if(!root)return;
  root.querySelectorAll(".kcard[draggable]").forEach(c=>{
    c.addEventListener("dragstart",e=>{ e.dataTransfer.setData("text/plain",c.dataset.tid); c.style.opacity=".5"; });
    c.addEventListener("dragend",()=>{ c.style.opacity=""; });
  });
  root.querySelectorAll("[data-col]").forEach(col=>{
    col.addEventListener("dragover",e=>{ e.preventDefault(); col.classList.add("kdrop"); });
    col.addEventListener("dragleave",()=>col.classList.remove("kdrop"));
    col.addEventListener("drop",e=>{ e.preventDefault(); col.classList.remove("kdrop");
      const tid=e.dataTransfer.getData("text/plain"), t=TASKMAP[tid], ns=col.dataset.col;
      if(!t||t.s===ns)return;
      pushSet(t,"status",ns); t.s=ns;
      markDirty(); renderAll(); refreshSchedIfActive();
    });
  });
}
```

- [ ] **Step 3: renderKanban 말미에서 호출** — `renderKanban` 함수 마지막(`innerHTML` 대입 뒤)에 `wireKanbanDrag();` 추가.

- [ ] **Step 4: CSS** — `.sg-toast` 정의 뒤에 삽입:

```css
  .kanban [data-col].kdrop{outline:2px dashed var(--accent);outline-offset:-4px;border-radius:12px}
```
(칸반 컬럼 selector는 실제 클래스에 맞춰 조정.)

- [ ] **Step 5: 검증**

```bash
render_check "wireKanbanDrag" 'data-col'
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 6: Commit**

```bash
git commit -am "[기능] 칸반 status 드래그 — 카드 컬럼 이동=set status op(간트 드래그와 동일 인프라)"
```

---

### Task 4: 마일스톤 접기/펼치기

**Files:**
- Modify: `docs/plan-view.template.html` (`renderTree`·`renderSchedule` MS 행 + 토글)

**Interfaces:**
- Consumes: `renderTree`, `renderSchedule`, `plan.milestones`.
- Produces: `collapsed:Set<mid>`, `toggleCollapse(mid)`.

- [ ] **Step 1: 상태 + 토글 함수** — `renderAll` 정의 앞에 삽입:

```javascript
const collapsed=new Set();
function toggleCollapse(mid){ collapsed.has(mid)?collapsed.delete(mid):collapsed.add(mid); renderAll(); refreshSchedIfActive(); }
```

- [ ] **Step 2: MS 헤더에 토글 아이콘** — 트리·간트 MS 헤더 라벨 앞에 `<span class="ctog" data-tog="${m.id}">${collapsed.has(m.id)?'▸':'▾'}</span>` 삽입.

- [ ] **Step 3: 접힘 시 task 렌더 skip** — `renderTree`·`renderSchedule`의 `m.tasks.forEach(...)` 를 `if(!collapsed.has(m.id)) m.tasks.forEach(...)` 로 감싼다(간트는 요약바 유지, task 행/바만 skip).

- [ ] **Step 4: 토글 클릭 위임** — body click 리스너 최상단(`if(_dragMoved)` 다음)에 삽입:

```javascript
  const tog=e.target.closest("[data-tog]");
  if(tog){ toggleCollapse(tog.dataset.tog); return; }
```

- [ ] **Step 5: 검증**

```bash
render_check "toggleCollapse" 'data-tog'
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 6: Commit**

```bash
git commit -am "[기능] 마일스톤 접기/펼치기 — 트리·간트 공통(세션 메모리 collapsed Set)"
```

---

### Task 5: 마일스톤 진행률 채움바

**Files:**
- Modify: `docs/plan-view.template.html` (`msProgress` 헬퍼 + 간트 요약바 채움 + 섹션행 라벨)

**Interfaces:**
- Consumes: `plan.milestones`, `renderSchedule` MS 마크업, `renderTree`(기존 완료율 로직).
- Produces: `msProgress(m)→{done,total,pct}`.

- [ ] **Step 1: 헬퍼 추가** — `allTasks` 정의 뒤에 삽입:

```javascript
function msProgress(m){ const total=(m.tasks||[]).length, done=(m.tasks||[]).filter(t=>t.s==="done"||t.status==="done").length;
  return {done,total,pct:total?Math.round(done/total*100):0}; }
```

- [ ] **Step 2: 간트 요약바 채움 오버레이 + 라벨** — `renderSchedule`의 `msMark`(요약 바) 생성 후, 섹션행 라벨에 `(done/total)` 추가하고, 요약바 안에 채움 div:

```javascript
    const pr=msProgress(m);
    if(m.start && m.start!==(m.end||m.start)){
      msMark=`<div class="sg-msbar" style="left:${dayX(m.start)}px;width:${(dcount(new Date(m.start),new Date(m.end||m.start))+1)*PX}px" title="${esc(m.name)} ${pr.done}/${pr.total}"><div class="sg-msbar-fill" style="width:${pr.pct}%"></div></div>`;
    }
    // 섹션행 라벨 끝에 ` (pr.done/pr.total)` 텍스트 추가
```
(다이아몬드 케이스는 채움 생략. 섹션행 라벨 문자열에 `(${pr.done}/${pr.total})` 삽입.)

- [ ] **Step 3: CSS** — `.sg-msbar` 정의 뒤에 삽입:

```css
  .sg-msbar-fill{height:100%;border-radius:4px;background:var(--accent);opacity:1}
```

- [ ] **Step 4: 검증**

```bash
render_check "msProgress" "sg-msbar-fill"
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 5: Commit**

```bash
git commit -am "[기능] 마일스톤 진행률 채움바 — 완료율% 간트 요약바 오버레이 + (done/total) 라벨"
```

---

### Task 6: 주말 음영

**Files:**
- Modify: `docs/plan-view.template.html` (`renderSchedule` 축 행 + CSS)

**Interfaces:**
- Consumes: `renderSchedule`의 `min`/`days`/`PX`/`dayX`.
- Produces: 없음(렌더 부산물).

- [ ] **Step 1: 주말 음영 div 생성** — `renderSchedule`의 `ticks` 생성 루프 뒤에 삽입:

```javascript
  let weekends="";
  for(let i=0;i<=days;i+=7){   // min이 월요일 → 토=+5, 일=+6
    const satX=(i+5)*PX;
    weekends+=`<div class="sg-weekend" style="left:${satX}px;width:${2*PX}px"></div>`;
  }
```
그리고 축 행 `sg-axis`의 `sg-track` 안에 `${weekends}` 를 `${ticks}` 앞에 넣는다. (음영이 틱 아래로 가도록 z-index CSS로 보정.)

- [ ] **Step 2: CSS** — `.sg-tick` 정의 근처에 삽입:

```css
  .sg-weekend{position:absolute;top:0;bottom:0;background:var(--muted);opacity:.06;z-index:0;pointer-events:none}
```

- [ ] **Step 3: 검증**

```bash
render_check "sg-weekend"
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 4: Commit**

```bash
git commit -am "[기능] 간트 주말 음영 — 월요일 정렬 전제, 주 단위 토·일 반투명"
```

---

### Task 7: zoom-to-fit + 프리셋 + 뷰포트 앵커

**Files:**
- Modify: `docs/plan-view.template.html` (`renderSchedule` 툴바 + `wireSchedule` + `zoomTo` 헬퍼)

**Interfaces:**
- Consumes: `SG`, `renderSchedule`, `fixupSchedule`, `scheduleBounds`, `#ganttscroll`, `LABELW`.
- Produces: `zoomTo(px)`, `fitZoom()`.

- [ ] **Step 1: zoomTo/fitZoom 헬퍼** — `wireSchedule` 정의 앞에 삽입:

```javascript
function _centerDate(){   // 현재 뷰포트 중앙의 날짜(줌 앵커)
  const sc=document.getElementById("ganttscroll"); if(!sc||!SG.min)return null;
  const centerX=sc.scrollLeft+sc.clientWidth/2-LABELW;
  const d=new Date(SG.min); d.setDate(d.getDate()+Math.round(centerX/SG.px)); return d;
}
function zoomTo(px){
  const anchor=_centerDate();
  SG.px=Math.max(2,Math.min(60,px)); renderSchedule(); fixupSchedule();
  if(anchor){ const sc=document.getElementById("ganttscroll");
    const x=LABELW+dcount(SG.min,anchor)*SG.px; sc.scrollLeft=x-sc.clientWidth/2; }
}
function fitZoom(){ const {days}=scheduleBounds(); const sc=document.getElementById("ganttscroll");
  if(sc) zoomTo(Math.floor((sc.clientWidth-LABELW)/Math.max(1,days))); }
```

- [ ] **Step 2: 툴바 버튼 추가** — `renderSchedule`의 `sg-toolbar` 문자열에 `gZoomIn` 뒤로 삽입:

```javascript
'<button id="gFit" title="전체 맞춤">맞춤</button><button id="gWk">주</button><button id="gMo">월</button><button id="gQt">분기</button>'+
```

- [ ] **Step 3: 기존 ＋/－ 를 zoomTo 경유로 + 프리셋 wire** — `wireSchedule`의 zoom 핸들러를 교체하고 프리셋 추가:

```javascript
  document.getElementById("gZoomIn").onclick=()=>zoomTo(SG.px+6);
  document.getElementById("gZoomOut").onclick=()=>zoomTo(SG.px-6);
  document.getElementById("gFit").onclick=fitZoom;
  document.getElementById("gWk").onclick=()=>zoomTo(28);
  document.getElementById("gMo").onclick=()=>zoomTo(10);
  document.getElementById("gQt").onclick=()=>zoomTo(5);
```

- [ ] **Step 4: 검증**

```bash
render_check "zoomTo" "fitZoom" 'id="gFit"'
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 5: Commit**

```bash
git commit -am "[기능] 간트 zoom-to-fit + 주/월/분기 프리셋 + 뷰포트중앙 앵커 유지"
```

---

### Task 8: 담당자 필터

**Files:**
- Modify: `docs/plan-view.template.html` (헤더/툴바 필터 UI + 필터 적용)

**Interfaces:**
- Consumes: `allTasks`, `renderAll`, `refreshSchedIfActive`, 각 뷰의 카드/행/바 요소.
- Produces: `assigneeFilter:string|null`, `applyFilter()`, `buildFilterUI()`.

- [ ] **Step 1: 상태 + 적용 함수** — `renderAll` 정의 뒤에 삽입:

```javascript
let assigneeFilter=null;
function applyFilter(){
  const dim=(el,on)=>el&&(el.style.opacity=on?"":".25");
  const match=t=>!assigneeFilter||(t.assignees||[]).includes(assigneeFilter);
  document.querySelectorAll("[data-tid]").forEach(el=>{
    const t=TASKMAP[el.dataset.tid]; dim(el, t?match(t):true);
  });
}
```

- [ ] **Step 2: 필터 드롭다운 UI** — `editbar` 다음(또는 헤더)에 필터 select를 항상 렌더. 스크립트에서 담당자 목록 수집 후 채운다. `initEdit`와 무관(읽기전용도 필터 가능) — 별도 `buildFilterUI()` 를 `renderAll()` 호출 뒤(최초)에 실행:

```javascript
function buildFilterUI(){
  const people=[...new Set(allTasks().flatMap(t=>t.assignees||[]))].sort();
  let host=document.getElementById("filterHost");
  if(!host)return;
  host.innerHTML=`담당자 <select id="fAssignee"><option value="">전체</option>`+
    people.map(p=>`<option value="${_av(p)}">${esc(p)}</option>`).join("")+`</select>`;
  document.getElementById("fAssignee").onchange=e=>{ assigneeFilter=e.target.value||null; applyFilter(); };
}
```
그리고 뷰 컨테이너 근처에 `<span id="filterHost" class="filter-host"></span>` HTML 추가, `initEdit()` 호출 부근에 `buildFilterUI();` 추가. `applyFilter()` 를 `renderAll` 끝과 `refreshActiveTab` 끝에서 호출(재렌더 후 필터 유지).

- [ ] **Step 3: CSS** — 임의 위치:

```css
  .filter-host{padding:8px 24px;font-size:13px;color:var(--muted)}
  .filter-host select{background:var(--bg);border:1px solid var(--border);color:var(--text);border-radius:6px;padding:3px 8px}
```

- [ ] **Step 4: 검증**

```bash
render_check "assigneeFilter" "buildFilterUI" 'id="filterHost"'
# node --check rc=0, pytest 235 passed
```

- [ ] **Step 5: Commit**

```bash
git commit -am "[기능] 담당자 필터 — 비매칭 태스크 흐림(전 뷰 공통, assignee 매칭)"
```

---

## 최종 검증 (전 태스크 후)

- [ ] `pytest -q` → 235 passed(백엔드 무변경 증명).
- [ ] `node --check` rc=0.
- [ ] 실제 `cairn render --serve` 로 8종 육안 확인(리뷰어): soft-warn 토스트·MS 다이얼로그 저장·칸반 드래그·접기·진행률·주말음영·fit/프리셋·필터.
- [ ] soft-warn이 원장 `validate`를 호출하지 않음을 코드리뷰로 확인(불변규칙).
- [ ] push + PR(base main).

## Self-Review 결과

- **스펙 커버리지:** 설계 §1~§8 → Task 1~8 1:1 매핑. §9 우선순위 순서 반영(soft-warn·MS편집 먼저).
- **Placeholder:** 각 Step에 실제 코드/명령 포함. CSS selector 일부는 "실제 클래스에 맞춰 조정" 주석 — 구현자가 해당 줄 확인 후 삽입(칸반 컬럼 클래스는 렌더 코드에 존재).
- **타입 일관성:** `pushSet(t,field,value)`·`ops.push({op,target,...})`·`msProgress(m)` 시그니처 태스크 간 일치. `zoomTo(px)`·`applyFilter()` 재사용 일관.
