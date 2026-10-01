"""Persist observed structure and original-source reference intent at publication.

No model/tokenizer/network dependency: v4 migrations can backfill this graph
from retained originals, Docling structures and chunk anchors atomically.
Cross-source targets are resolved later against the search snapshot.
"""
from __future__ import annotations

import heapq
import html
from bisect import bisect_left, bisect_right
import json
import re
import time
import unicodedata
from collections import defaultdict

GRAPH_VERSION = 1
STRUCTURAL_RELATIONS = ('next','previous','parent','child','same_section','same_table','same_page','same_sheet','same_turn')
REFERENCE_RELATIONS = ('references','reply_to')
MAX_REFERENCES = 10000
MAX_EDGES = 1000000


class GraphLimitError(ValueError):
    pass


def compact(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'),allow_nan=False)


def heading_slug(text):
    return re.sub(r'\s+','-',re.sub(r'[^\w\s-]','',unicodedata.normalize('NFKC',text).casefold()).strip())


def source_nodes(structured):
    nodes={}
    for value in structured.values():
        values=value if isinstance(value,list) else [value]
        for node in values:
            if isinstance(node,dict) and isinstance(node.get('self_ref'),str):nodes[node['self_ref']]=node
    return nodes


def node_contexts(structured):
    nodes=source_nodes(structured);contexts={};visiting=set()
    def walk(ref,path,depth):
        if depth>128 or ref in visiting:raise GraphLimitError('normalized structure is cyclic or exceeds the depth bound')
        node=nodes.get(ref)
        if node is None:return
        visiting.add(ref)
        headings=[]
        for child in node.get('children',[]):
            cr=child.get('$ref') if isinstance(child,dict) else None
            cn=nodes.get(cr,{})
            label=cn.get('label')
            if label in ('title','section_header'):
                level=0 if label=='title' else cn.get('level',1)
                if not isinstance(level,int):level=1
                while headings and headings[-1][0]>=level:headings.pop()
                headings.append((level,cr))
            current=path+tuple(r for _,r in headings)
            contexts[cr]=current
            if cn.get('children'):
                walk(cr,current if current and current[-1]==cr else current+(cr,),depth+1)
        visiting.remove(ref)
    walk('#/body',('$document',),0)
    return nodes,contexts


def text_references(text):
    """CommonMark links plus literal source-key directives with original offsets.

    Marko supplies source spans in its newline-normalized buffer. Translate
    only collapsed CRLF boundaries back to original Python character offsets.
    Code/HTML spans suppress source-key directives; translations are never input.
    """
    if '[' not in text and '<' not in text:return []
    import marko
    from marko.inline import Link
    removed=[m.start()-i for i,m in enumerate(re.finditer(r'\r\n',text))]
    normalized_length=len(text)-len(removed)
    def original(span):
        start,end=span
        if not 0<=start<=end<=normalized_length:raise GraphLimitError('cannot map reference source span')
        return start+bisect_left(removed,start),end+bisect_left(removed,end)
    links=[];excluded=[]
    try:
        document=marko.parse(text)
    except RecursionError as exc:
        raise GraphLimitError('reference parser exceeds nesting bound') from exc
    pending=[(document,0)]
    while pending:
        node,depth=pending.pop()
        if depth>128:raise GraphLimitError('reference syntax exceeds nesting bound')
        span=getattr(node,'source_span',None)
        if type(node).__name__ in ('CodeBlock','FencedCode','CodeSpan','HTMLBlock','InlineHTML'):
            if span is not None:excluded.append(original(span))
            continue
        if isinstance(node,Link):
            if span is None:raise GraphLimitError('link parser did not preserve source location')
            start,end=original(span)
            links.append((start,end,{'kind':'uri','value':html.unescape(node.dest)}))
        children=getattr(node,'children',None)
        if isinstance(children,list):pending.extend((c,depth+1) for c in reversed(children))
        if len(links)>MAX_REFERENCES:raise GraphLimitError('source exceeds reference-intent bound')
    excluded.sort();merged=[]
    for start,end in excluded:
        if merged and start<=merged[-1][1]:merged[-1]=(merged[-1][0],max(end,merged[-1][1]))
        else:merged.append((start,end))
    excluded_starts=[x[0] for x in merged]
    directives=[]
    for match in re.finditer(r'\[\[source:([^\]\r\n]{1,2048})\]\]',text):
        start,end=match.span();index=bisect_right(excluded_starts,start)-1
        if index>=0 and merged[index][1]>start:continue
        i=start-1
        while i>=0 and text[i]=='\\':i-=1
        if (start-i-1)%2:continue
        value=match[1].strip()
        if value:directives.append((start,end,{'kind':'source_key','value':value}))
        if len(directives)>MAX_REFERENCES:raise GraphLimitError('source exceeds reference-intent bound')
    starts=[x[0] for x in directives]
    output=list(directives)
    for link in links:
        index=bisect_right(starts,link[0])-1
        if index>=0 and directives[index][1]>=link[1]:continue
        output.append(link)
    if len(output)>MAX_REFERENCES:raise GraphLimitError('source exceeds reference-intent bound')
    return sorted(output,key=lambda x:(x[0],x[1]))


def persist_generation(con,generation_id):
    if not con.in_transaction:raise ValueError('graph publication requires the caller transaction')
    if con.execute('SELECT 1 FROM generation_graphs WHERE generation_id=?',(generation_id,)).fetchone():
        raise ValueError('generation graph is already immutable')
    row=con.execute('SELECT r.content_bytes,r.media_type,s.source_key,r.origin_uri,n.structured_json FROM generations g JOIN source_revisions r ON r.revision_id=g.revision_id JOIN sources s ON s.source_id=r.source_id LEFT JOIN normalized_documents n ON n.generation_id=g.generation_id WHERE g.generation_id=?',(generation_id,)).fetchone()
    if row is None:raise ValueError('generation not found')
    content,media,source_key,origin_uri,raw=row
    structured=json.loads(raw) if raw else {}
    nodes,contexts=node_contexts(structured)
    chunks=con.execute('SELECT chunk_id,chunk_index,text,anchor_json FROM chunks WHERE generation_id=? ORDER BY chunk_index',(generation_id,)).fetchall()
    edges={};groups=defaultdict(list);chunk_refs=defaultdict(set);spans=[];turns=defaultdict(set);intents=[];locators=set()
    heading_slugs={};used=set()
    for ref in contexts:
        node=nodes.get(ref,{})
        if node.get('label') in ('title','section_header'):
            base=heading_slug(node.get('text',''));value=base;n=1
            while value in used:value=f'{base}-{n}';n+=1
            used.add(value);heading_slugs[ref]=value
    anchors={}
    def edge(a,b,kind,proof):
        if a==b:return
        key=(a,b,kind)
        edges.setdefault(key,[])
        if proof not in edges[key]:edges[key].append(proof)
        if len(edges)>MAX_EDGES:raise GraphLimitError('source exceeds structural edge bound')
    for before,after in zip(chunks,chunks[1:]):
        proof={'basis':'generation_chunk_order','from_index':before[1],'to_index':after[1]}
        edge(before[0],after[0],'next',proof);edge(after[0],before[0],'previous',proof)
    for cid,index,text,raw_anchor in chunks:
        anchor=json.loads(raw_anchor) if raw_anchor else {}
        if not isinstance(anchor,dict):anchor={}
        anchors[cid]=anchor
        paths=set()
        for item in anchor.get('items',[]):
            if not isinstance(item,dict):continue
            ref=item.get('self_ref')
            if isinstance(ref,str):
                chunk_refs[ref].add(cid)
                paths.add(contexts.get(ref,('$document',)))
                locators.add((cid,'node',ref))
                for heading in contexts.get(ref,()):
                    if heading in heading_slugs:locators.add((cid,'heading',heading_slugs[heading]))
                if nodes.get(ref,{}).get('label')=='table':groups[('same_table',ref)].append(cid)
            if item.get('kind')=='text_span' and isinstance(item.get('start'),int) and isinstance(item.get('end'),int):
                spans.append((item['start'],item['end'],cid))
            if item.get('kind')=='conversation_turn':
                pointer=item.get('pointer','')
                match=re.fullmatch(r'/turns/(\d+)/(?:text|role)',pointer)
                if match:
                    turn=match[1];groups[('same_turn',turn)].append(cid)
                    if pointer.endswith('/text'):
                        turns[int(turn)].add(cid)
                        if isinstance(item.get('turn_id'),str):locators.add((cid,'turn',item['turn_id']))
            locator=item.get('locator') or {}
            if not isinstance(locator,dict):continue
            if 'section' in locator:paths.add(('$document','$source_section:'+str(locator['section'])))
            if 'sheet' in locator:
                groups[('same_sheet',str(locator['sheet']))].append(cid);locators.add((cid,'sheet',str(locator['sheet'])))
            if 'frame' in locator:
                groups[('same_page','frame:'+str(locator['frame']))].append(cid);locators.add((cid,'frame',str(locator['frame'])))
            for prov in locator.get('provenance',[]):
                if isinstance(prov,dict) and 'page_no' in prov and locator.get('format')=='pdf':
                    groups[('same_page','page:'+str(prov['page_no']))].append(cid);locators.add((cid,'page',str(prov['page_no'])))
        if len(paths)>1:paths.discard(('$document',))
        for path in paths or {('$document',)}:groups[('same_section',path)].append(cid)
    representatives={}
    for (kind,key),ids in groups.items():
        ids=list(dict.fromkeys(ids))
        proof={'basis':kind,'group':list(key) if isinstance(key,tuple) else key}
        for a,b in zip(ids,ids[1:]):edge(a,b,kind,proof);edge(b,a,kind,proof)
        if kind=='same_section' and ids:representatives[key]=ids[0]
    for path,child in representatives.items():
        for length in range(len(path)-1,0,-1):
            parent_path=path[:length]
            if parent_path in representatives:
                parent=representatives[parent_path]
                proof={'basis':'section_hierarchy','parent_path':list(parent_path),'child_path':list(path),'representatives':'first chunk directly associated with each section'}
                edge(parent,child,'child',proof);edge(child,parent,'parent',proof);break
    def intent(cid,relation,target,proof):
        intents.append((generation_id,cid,relation,compact(target),compact(proof)))
        if len(intents)>MAX_EDGES:raise GraphLimitError('source exceeds attached reference bound')
    if media in ('text/plain','text/markdown'):
        text=content.decode('utf-8')
        refs=text_references(text)
        ordered=sorted(set(spans));cursor=0;active={};heap=[]
        for start,end,target in refs:
            while cursor<len(ordered) and ordered[cursor][0]<end:
                lo,hi,cid=ordered[cursor];active[cursor]=(lo,hi,cid);heapq.heappush(heap,(hi,cursor));cursor+=1
            while heap and heap[0][0]<=start:
                _,key=heapq.heappop(heap);active.pop(key,None)
            owners={cid for lo,hi,cid in active.values() if lo<end and hi>start}
            if not owners and len(chunks)==1 and chunks[0][2]==text:owners={chunks[0][0]}
            for cid in sorted(owners):
                intent(cid,'references',target,{'basis':'original_source_link','start':start,'end':end,'unit':'char','source_key':source_key,'origin_uri':origin_uri})
    for ref,node in nodes.items():
        href=node.get('hyperlink')
        if isinstance(href,str) and href:
            for cid in sorted(chunk_refs.get(ref,())):
                intent(cid,'references',{'kind':'uri','value':href},{'basis':'docling_hyperlink','source_ref':ref,'source_key':source_key,'origin_uri':origin_uri})
    if media=='application/x-airag-conversation+json':
        payload=json.loads(content)
        counts=defaultdict(int)
        for turn in payload.get('turns',[]):
            if isinstance(turn,dict) and isinstance(turn.get('id'),str):counts[turn['id']]+=1
        for i,turn in enumerate(payload.get('turns',[])):
            if isinstance(turn,dict) and isinstance(turn.get('text'),str):
                for start,end,target in text_references(turn['text']):
                    for cid in sorted(turns.get(i,())):
                        intent(cid,'references',target,{'basis':'original_conversation_link','pointer':f'/turns/{i}/text',
                                                       'start':start,'end':end,'unit':'char','source_key':source_key,'origin_uri':origin_uri})
            if isinstance(turn,dict) and 'reply_to' in turn:
                value=turn['reply_to']
                target={'kind':'turn_id','value':value,'source_key':source_key,'ambiguous':isinstance(value,str) and counts[value]>1}
                for cid in sorted(turns.get(i,())):intent(cid,'reply_to',target,{'basis':'original_reply_to','pointer':f'/turns/{i}/reply_to','source_key':source_key})
    con.execute('INSERT INTO generation_graphs(generation_id,version,created_at_ms) VALUES (?,?,?)',(generation_id,GRAPH_VERSION,int(time.time()*1000)))
    con.executemany('INSERT INTO chunk_edges VALUES (?,?,?,?,?)',[(generation_id,a,b,kind,compact({'witnesses':proofs})) for (a,b,kind),proofs in sorted(edges.items())])
    con.executemany('INSERT INTO chunk_references(generation_id,from_chunk_id,relation,target_json,provenance_json) VALUES (?,?,?,?,?)',list(dict.fromkeys(intents)))
    con.executemany('INSERT INTO chunk_locators VALUES (?,?,?,?)',[(generation_id,cid,kind,value) for cid,kind,value in sorted(locators)])
