"""Bounded expansion of an immutable search snapshot, without model calls.

Standalone expansion rejects changed snapshots. Replay reads saved evidence;
it does not traverse today's corpus. Budgets apply to canonical JSON of the
entire evidence payload, measured by the search profile's cached tokenizer.
"""
from __future__ import annotations

import json
import math
import posixpath
import re
import time
from collections import deque
from dataclasses import asdict, dataclass
from functools import lru_cache
from urllib.parse import quote, unquote, urljoin, urlsplit, urlunsplit

from airag import relations, search, store
from airag.db import vecext


class ExpansionError(store.ApiError):
    pass


@dataclass(frozen=True)
class ExpansionOptions:
    max_depth: int = 1
    max_chunks: int = 20
    max_tokens: int = 8000
    max_bytes: int = 262144
    max_edges: int = 256
    include_semantic: bool = False
    semantic_neighbors: int = 4
    min_similarity: float = 0.75
    relations: tuple[str, ...] = relations.STRUCTURAL_RELATIONS + relations.REFERENCE_RELATIONS

    def validate(self):
        for name,minimum,maximum in (('max_depth',0,8),('max_chunks',1,200),('max_tokens',1,64000),
                                     ('max_bytes',64,4194304),('max_edges',1,10000),('semantic_neighbors',1,20)):
            value=getattr(self,name)
            if isinstance(value,bool) or not isinstance(value,int) or not minimum<=value<=maximum:
                raise ExpansionError('VALIDATION_ERROR',f'{name} must be an integer in [{minimum}, {maximum}]',retryable=False)
        if not isinstance(self.include_semantic,bool):raise ExpansionError('VALIDATION_ERROR','include_semantic must be boolean',retryable=False)
        if isinstance(self.min_similarity,bool) or not isinstance(self.min_similarity,(int,float)) or not math.isfinite(self.min_similarity) or not -1<=self.min_similarity<=1:
            raise ExpansionError('VALIDATION_ERROR','min_similarity must be finite and in [-1, 1]',retryable=False)
        if not isinstance(self.relations,(list,tuple)) or len(self.relations)>20 or any(k not in relations.STRUCTURAL_RELATIONS+relations.REFERENCE_RELATIONS for k in self.relations):
            raise ExpansionError('VALIDATION_ERROR','unknown structural/reference relation',retryable=False)


@dataclass(frozen=True)
class TokenCounter:
    model: str
    revision: str
    tokenizer: object

    def count(self,text):
        return len(self.tokenizer.encode(text,add_special_tokens=False,truncation=False,verbose=False))


@lru_cache(maxsize=8)
def _local_tokenizer(model,revision):
    from transformers import AutoTokenizer
    try:
        return AutoTokenizer.from_pretrained(model,revision=revision,local_files_only=True,trust_remote_code=False)
    except (OSError,ValueError) as exc:
        raise ExpansionError('TOKENIZER_UNAVAILABLE','the captured tokenizer must be prepared locally before expansion',retryable=False) from exc


def prepare_counter(con,profile_key):
    if con.in_transaction:raise ExpansionError('INVALID_TRANSACTION','load the tokenizer before opening the read snapshot',retryable=False)
    row=con.execute('SELECT chunker_config FROM processing_profiles WHERE profile_key=?',(profile_key,)).fetchone()
    if row is None:raise ExpansionError('NOT_FOUND','processing profile not found',retryable=False)
    cfg=json.loads(row[0])
    if not all(isinstance(cfg.get(k),str) and cfg[k] for k in ('tokenizer_model','tokenizer_revision')):
        raise ExpansionError('TOKENIZER_UNAVAILABLE','profile lacks a captured tokenizer identity',retryable=False)
    return TokenCounter(cfg['tokenizer_model'],cfg['tokenizer_revision'],_local_tokenizer(cfg['tokenizer_model'],cfg['tokenizer_revision']))


def _id(value,name):
    if isinstance(value,bool) or not isinstance(value,int) or value<=0:
        raise ExpansionError('VALIDATION_ERROR',f'{name} must be a positive integer',retryable=False)
    return value


def _canonical_uri(value):
    parsed=urlsplit(value)
    user,sep,host=parsed.netloc.rpartition('@')
    authority=(user+sep if sep else '')+host.lower()
    path=quote(parsed.path,safe="/:@!$&'()*+,;=-._~%")
    def escape(match):
        char=chr(int(match[1],16))
        return char if char.isascii() and (char.isalnum() or char in '-._~') else '%'+match[1].upper()
    path=re.sub(r'%([0-9a-fA-F]{2})',escape,path)
    return urlunsplit((parsed.scheme.lower(),authority,path,parsed.query,''))


class SnapshotGraph:
    def __init__(self,con,snapshot,options):
        self.con=con;self.snapshot=snapshot;self.options=options
        self.generations={s['generation_id']:s for s in snapshot['sources']}
        self.allowed=relations.compact(sorted(self.generations))
        rows=con.execute('SELECT s.source_id,s.source_key,r.origin_uri,g.generation_id,g.revision_id FROM generations g JOIN source_revisions r ON r.revision_id=g.revision_id JOIN sources s ON s.source_id=r.source_id WHERE g.generation_id IN (SELECT value FROM json_each(?))',(self.allowed,)).fetchall()
        self.sources=[{'source_id':sid,'key':key,'uri':uri,'generation_id':gen,'revision_id':rev} for sid,key,uri,gen,rev in rows]
        self.by_key={s['key']:s for s in self.sources}
        self.by_generation={s['generation_id']:s for s in self.sources}

    def node(self,cid):
        row=self.con.execute('SELECT c.generation_id,g.error FROM chunks c LEFT JOIN generation_graphs g ON g.generation_id=c.generation_id WHERE c.chunk_id=? AND c.generation_id IN (SELECT value FROM json_each(?))',(cid,self.allowed)).fetchone()
        if row is None:return None
        if self.generations[row[0]]['graph_version']!=relations.GRAPH_VERSION:
            raise ExpansionError('GRAPH_UNAVAILABLE','generation graph is unavailable: '+(row[1] or 'unsupported version'),retryable=False)
        evidence=search._fetch_evidence(self.con,[search._FusedResult(cid,0.0,None,None,None,None)])[0]
        evidence['rrf_score']=None
        evidence['original_ref']={'command':'fetch original','collection':evidence['collection'],'source_key':evidence['source_key'],'source_id':evidence['source_id'],'revision_id':evidence['revision_id'],'content_hash':evidence['content_hash']}
        return evidence

    def _entry(self,generation,kind=None,value=None):
        if generation not in self.generations:return None
        if kind is None:
            row=self.con.execute('SELECT chunk_id FROM chunks WHERE generation_id=? ORDER BY chunk_index LIMIT 1',(generation,)).fetchone()
        else:
            row=self.con.execute('SELECT l.chunk_id FROM chunk_locators l JOIN chunks c ON c.chunk_id=l.chunk_id AND c.generation_id=l.generation_id WHERE l.generation_id=? AND l.kind=? AND l.value=? ORDER BY c.chunk_index LIMIT 1',(generation,kind,value)).fetchone()
        return row[0] if row else None

    def resolve(self,source_generation,target):
        origin=self.by_generation[source_generation]
        kind=target.get('kind');value=target.get('value');fragment='';candidates=[];locator_kind=None;locator_value=None
        if not isinstance(value,str) or not value:return None,'invalid_reference',{}
        if kind=='turn_id':
            if target.get('ambiguous'):return None,'ambiguous_turn_id',{}
            candidates=[origin];locator_kind='turn';locator_value=value
        elif kind=='source_key':
            if value in self.by_key:candidates=[self.by_key[value]]
        elif kind=='uri':
            try:
                uri=urlsplit(value);fragment=unquote(uri.fragment)
            except ValueError:return None,'invalid_uri',{}
            if uri.scheme not in ('','http','https','file','source'):
                return None,'unsupported_scheme',{}
            if uri.scheme=='source':
                key=unquote(uri.path)
                if key in self.by_key:candidates=[self.by_key[key]]
            elif not uri.scheme and not uri.netloc and not uri.path:
                candidates=[origin]
            else:
                keys=set()
                if not uri.scheme and not uri.netloc:
                    keys.add(posixpath.normpath(posixpath.join(posixpath.dirname(origin['key']),unquote(uri.path))))
                absolute=urljoin(origin['uri'],value) if origin['uri'] else value
                try:
                    wanted=_canonical_uri(absolute)
                    candidates=[s for s in self.sources if s['key'] in keys or s['uri'] and _canonical_uri(s['uri'])==wanted]
                except ValueError:return None,'invalid_uri',{}
        else:return None,'unsupported_reference_syntax',{}
        if len(candidates)>1:return None,'ambiguous_source',{}
        if not candidates:return None,'not_in_snapshot',{}
        if fragment:
            if fragment.startswith(('page=','sheet=','frame=','turn=')):
                locator_kind,locator_value=fragment.split('=',1)
            elif fragment.startswith('/'):
                locator_kind='node';locator_value='#'+fragment
            else:locator_kind='heading';locator_value=relations.heading_slug(fragment)
        selected=candidates[0]
        cid=self._entry(selected['generation_id'],locator_kind,locator_value)
        if cid is None:return None,'fragment_not_found' if locator_kind else 'no_searchable_chunks',{}
        return cid,None,{'target_source_id':selected['source_id'],'target_revision_id':selected['revision_id'],
                         'target_generation_id':selected['generation_id'],'target_granularity':(locator_kind or 'document')+'_entry',
                         'locator':locator_value}

    def neighbors(self,cid,generation,remaining):
        cap=remaining+1;output=[]
        selected=[k for k in relations.STRUCTURAL_RELATIONS if k in self.options.relations]
        if selected:
            placeholders=','.join('?' for _ in selected)
            order='CASE e.relation '+ ' '.join(f"WHEN '{k}' THEN {i}" for i,k in enumerate(relations.STRUCTURAL_RELATIONS))+' END'
            rows=self.con.execute('SELECT e.to_chunk_id,e.relation,e.provenance_json FROM chunk_edges e JOIN chunks c ON c.chunk_id=e.to_chunk_id AND c.generation_id=e.generation_id WHERE e.from_chunk_id=? AND e.generation_id=? AND c.generation_id IN (SELECT value FROM json_each(?)) AND e.relation IN ('+placeholders+') ORDER BY '+order+',e.to_chunk_id LIMIT ?',(cid,generation,self.allowed,*selected,cap)).fetchall()
            output.extend({'target':target,'relation':relation,'classification':'structural','provenance':json.loads(proof)} for target,relation,proof in rows)
        if len(output)>=cap:return output
        selected=[k for k in relations.REFERENCE_RELATIONS if k in self.options.relations]
        if selected:
            rows=self.con.execute('SELECT reference_id,relation,target_json,provenance_json FROM chunk_references WHERE from_chunk_id=? AND generation_id=? AND relation IN ('+','.join('?' for _ in selected)+') ORDER BY reference_id LIMIT ?',(cid,generation,*selected,cap-len(output))).fetchall()
            for rid,relation,raw,proof in rows:
                target=json.loads(raw);resolved,reason,details=self.resolve(generation,target)
                output.append({'target':resolved,'relation':relation,'classification':'explicit_reference',
                               'provenance':{'reference_id':rid,'intent':target,'source':json.loads(proof),**details},'unresolved_reason':reason})
        if self.options.include_semantic and len(output)<cap:
            table=search._vec_space_table_name(self.snapshot['space_id'])
            row=self.con.execute(f'SELECT embedding FROM {table} WHERE chunk_id=?',(cid,)).fetchone()
            if row is not None:
                limit=min(self.options.semantic_neighbors,cap-len(output))
                neighbors=self.con.execute(f'SELECT v.chunk_id,vec_distance_cosine(v.embedding,?) AS distance FROM {table} v JOIN chunks c ON c.chunk_id=v.chunk_id WHERE v.active=1 AND c.generation_id IN (SELECT value FROM json_each(?)) AND v.chunk_id<>? AND vec_distance_cosine(v.embedding,?)<=? ORDER BY distance,v.chunk_id LIMIT ?',(row[0],self.allowed,cid,row[0],1-self.options.min_similarity,limit)).fetchall()
                output.extend({'target':target,'relation':'similar','classification':'inferred','provenance':{'basis':'exact_cosine','space_id':self.snapshot['space_id'],'distance':distance,'similarity':1-distance}} for target,distance in neighbors)
        return output


def expand_snapshot(con,seeds,snapshot,options,counter):
    options.validate()
    if not con.in_transaction:raise ExpansionError('INVALID_TRANSACTION','expansion requires a read snapshot',retryable=False)
    graph=SnapshotGraph(con,snapshot,options)
    payload={'results':[],'paths':[],'unresolved':[]}
    reasons=set();queue=deque();visited=set();examined=0;duplicates=0
    def measure(value):
        raw=relations.compact(value)
        return len(raw.encode('utf-8')),counter.count(raw)
    size,tokens=measure(payload)
    if size>options.max_bytes or tokens>options.max_tokens:
        raise ExpansionError('BUDGET_TOO_SMALL','budget cannot hold an empty evidence payload',retryable=False)
    def accept(candidate):
        nonlocal payload,size,tokens
        raw=relations.compact(candidate);bytes_=len(raw.encode('utf-8'))
        if bytes_>options.max_bytes:reasons.add('max_bytes');return False
        tokens_=counter.count(raw)
        if tokens_>options.max_tokens:reasons.add('max_tokens');return False
        payload=candidate;size=bytes_;tokens=tokens_;return True
    seed_budget=False
    for seed in seeds:
        cid=_id(seed.get('chunk_id'),'seed_chunk_id')
        if cid in visited:continue
        if len(visited)>=options.max_chunks:reasons.add('max_chunks');seed_budget=True;break
        node=graph.node(cid)
        if node is None:raise ExpansionError('SEED_NOT_IN_SNAPSHOT','seed is outside the captured search snapshot',retryable=False)
        for key in ('rrf_score','bm25_rank','bm25_score','vec_rank','vec_distance'):node[key]=seed.get(key)
        node.update(expansion_depth=0,seed_chunk_id=cid)
        if not accept({**payload,'results':payload['results']+[node]}):seed_budget=True;break
        visited.add(cid);queue.append((cid,node['generation_id'],0,cid))
    stop=seed_budget
    while queue and not stop:
        cid,generation,depth,seed=queue.popleft()
        for neighbor in graph.neighbors(cid,generation,options.max_edges-examined):
            if examined>=options.max_edges:reasons.add('max_edges');stop=True;break
            examined+=1
            target=neighbor['target']
            if target is None:
                issue={'from_chunk_id':cid,'relation':neighbor['relation'],'reason':neighbor['unresolved_reason'],'provenance':neighbor['provenance']}
                if not accept({**payload,'unresolved':payload['unresolved']+[issue]}):stop=True;break
                continue
            if target in visited:duplicates+=1;continue
            if depth>=options.max_depth:reasons.add('max_depth');continue
            if len(visited)>=options.max_chunks:reasons.add('max_chunks');stop=True;break
            node=graph.node(target)
            if node is None:raise ExpansionError('SCOPE_MISMATCH','candidate escaped the captured snapshot',retryable=False)
            node.update(expansion_depth=depth+1,seed_chunk_id=seed)
            path={'seed_chunk_id':seed,'from_chunk_id':cid,'to_chunk_id':target,'depth':depth+1,
                  'relation':neighbor['relation'],'classification':neighbor['classification'],'provenance':neighbor['provenance']}
            if not accept({**payload,'results':payload['results']+[node],'paths':payload['paths']+[path]}):stop=True;break
            visited.add(target);queue.append((target,node['generation_id'],depth+1,seed))
    option_values=asdict(options);option_values['relations']=list(options.relations)
    return {'historical':False,'policy':'reject_stale','snapshot':{'fingerprint':snapshot['fingerprint'],'source_count':len(snapshot['sources']),'version':snapshot['version']},
            'scope':{'collection':snapshot['collection'],'space_id':snapshot['space_id'],**snapshot['scope']},
            'graph_version':relations.GRAPH_VERSION,'options':option_values,'evidence':payload,
            'usage':{'chunks':len(visited),'tokens':tokens,'bytes':size,'edges_examined':examined,'duplicates_skipped':duplicates,
                     'tokenizer_model':counter.model,'tokenizer_revision':counter.revision,
                     'accounting':'canonical compact JSON of evidence only; UTF-8, sorted keys, no tokenizer special tokens'},
            'truncated':bool(reasons),'truncation_reasons':sorted(reasons),
            'seed_count':len(seeds),'included_seed_count':sum(n['expansion_depth']==0 for n in payload['results'])}


def persist(con,search_manifest_id,response,*,inline=False):
    if not con.in_transaction:raise ExpansionError('INVALID_TRANSACTION','manifest persistence requires a write transaction',retryable=False)
    result={**response,'search_manifest_id':search_manifest_id,'mode':'inline' if inline else 'standalone'}
    cur=con.execute('INSERT INTO expansion_manifests(search_manifest_id,inline,response_json,created_at_ms) VALUES (?,?,?,?)',(search_manifest_id,int(inline),relations.compact(result),int(time.time()*1000)))
    return {**result,'expansion_id':cur.lastrowid}


def _manifest(con,manifest_id):
    row=con.execute('SELECT profile_key,space_id,filters_json,results_json FROM search_manifests WHERE manifest_id=?',(manifest_id,)).fetchone()
    if row is None:raise ExpansionError('NOT_FOUND','search manifest not found',retryable=False)
    return row[0],row[1],json.loads(row[2]),json.loads(row[3])


def expand(con,manifest_id,options=None,*,seed_chunk_ids=None):
    manifest_id=_id(manifest_id,'manifest_id');options=options or ExpansionOptions();options.validate()
    initial=_manifest(con,manifest_id)
    if initial[2].get('snapshot',{}).get('version')!=1:
        raise ExpansionError('LEGACY_MANIFEST','create a new search; this manifest lacks a verifiable state snapshot',retryable=False)
    if seed_chunk_ids is not None:
        if not isinstance(seed_chunk_ids,(list,tuple)) or not seed_chunk_ids or len(seed_chunk_ids)>200:
            raise ExpansionError('VALIDATION_ERROR','seed_chunk_ids must be a nonempty list of at most 200 IDs',retryable=False)
        for cid in seed_chunk_ids:_id(cid,'seed_chunk_id')
    counter=prepare_counter(con,initial[0])
    if not vecext.try_load_vec0(con):raise ExpansionError('VEC0_UNAVAILABLE','sqlite_vec could not be loaded',retryable=False)
    con.execute('BEGIN')
    try:
        profile,space,filters,seeds=_manifest(con,manifest_id)
        if profile!=initial[0]:raise ExpansionError('STALE_SNAPSHOT','manifest identity changed',retryable=False)
        search._validate_profile_matches_space(con,profile,space)
        captured=filters['snapshot']
        scope=search.validate_scope(**captured['scope'])
        eligible=search._resolve_eligible_sources(con,captured['collection'],space,**scope)
        current=search.snapshot_state(eligible,captured['collection'],space,scope)
        if current!=captured:raise ExpansionError('STALE_SNAPSHOT','searchable sources or their state changed; run a new search',retryable=False)
        if seed_chunk_ids is not None:
            selected=set(seed_chunk_ids)
            if not selected<={s['chunk_id'] for s in seeds}:raise ExpansionError('INVALID_SEED','seeds must be results of the parent search',retryable=False)
            seeds=[s for s in seeds if s['chunk_id'] in selected]
        result=expand_snapshot(con,seeds,current,options,counter)
        con.rollback()
    except Exception:
        con.rollback();raise
    con.execute('BEGIN IMMEDIATE')
    try:
        result=persist(con,manifest_id,result)
        con.commit();return result
    except Exception:
        con.rollback();raise


def replay(con,expansion_id):
    expansion_id=_id(expansion_id,'expansion_id')
    row=con.execute('SELECT response_json,created_at_ms FROM expansion_manifests WHERE expansion_id=?',(expansion_id,)).fetchone()
    if row is None:raise ExpansionError('NOT_FOUND','expansion manifest not found',retryable=False)
    return {**json.loads(row[0]),'expansion_id':expansion_id,'historical':True,'created_at_ms':row[1]}
