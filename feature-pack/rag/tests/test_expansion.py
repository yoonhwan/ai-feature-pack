"""Real SQLCipher/vec0 graph and budget tests; vectors are mathematical fixtures."""
from __future__ import annotations

import json
import struct
import uuid
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

import pytest

from airag import api,chunking,embeddings,expansion,normalize,profiles,relations,search,store
from airag.db import connect

REVISION='97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3'


def vec(*values):return struct.pack(f'{len(values)}f',*values)


@pytest.fixture
def db(tmp_path,key_bytes):
    con=connect.init_db(tmp_path/'graph.db',key_bytes)
    cfg=embeddings.EmbeddingSpaceConfig('openai-compatible','http://localhost:9999/v1','math-fixture','fixture-v1',4,tokenizer_revision=REVISION)
    con.execute('BEGIN IMMEDIATE');space,profile=profiles.register_space_and_profile(con,cfg,{});con.commit()
    embeddings.ensure_vec_space_table(con,space,4)
    yield con,cfg,space,profile
    con.close()


def publish(db,key,text,*,collection='docs',media='text/markdown',vector=None,profile=None,space=None,origin_uri=None):
    con,cfg,default_space,default_profile=db;profile=profile or default_profile;space=space or default_space
    nd=normalize.build_document(media,text.encode(),name=key)
    rows=[]
    for item,_ in nd.doc.iterate_items():
        if getattr(item,'label',None).value in ('title','section_header'):continue
        anchor=chunking._whole_item_anchor(nd.anchors[item.self_ref]);anchor['self_ref']=item.self_ref
        rows.append({'text':item.text,'token_count':1,'anchor':{'headings':[],'items':[anchor]}})
    accepted=store.add(con,store.AddRequest(uuid.uuid4().hex,collection,key,text.encode(),media,origin_uri),profile_key=profile)
    result=store.publish_generation_with_content(con,accepted['generation_id'],standard_md=nd.doc.export_to_markdown(),structured_json=nd.doc.export_to_dict(),chunk_rows=rows,space_id=space,vectors=[vector or vec(1,0,0,0) for _ in rows])
    ids=[r[0] for r in con.execute('SELECT chunk_id FROM chunks WHERE generation_id=? ORDER BY chunk_index',(result['generation_id'],))]
    return result,ids


def run_search(db,query='seed',*,keys=None,media_types=None,inline=None):
    con,cfg,space,profile=db
    return search.search(con,search.SearchQuery('docs',query,query,vec(1,0,0,0),space,profile,top_k=1,source_keys=keys,media_types=media_types),expansion_options=inline)


def test_original_links_exclude_code_and_preserve_offsets():
    text='한글 [real](a.md#part) and `[[source:hidden]]`\n```\n[x](secret)\n```\n[[source:b.md]]'
    refs=relations.text_references(text)
    assert [r[2]['value'] for r in refs]==['a.md#part','b.md']
    assert text[refs[0][0]:refs[0][1]]=='[real](a.md#part)'


def test_structural_edges_parent_child_and_original_node_locations(db):
    con,_,_,_=db
    _,ids=publish(db,'tree.md','# Root\nseed introduction\n## Child\nchild facts\n### Detail\ndetail facts\n## Other\nother facts')
    kinds={(a,b,k) for a,b,k in con.execute('SELECT from_chunk_id,to_chunk_id,relation FROM chunk_edges')}
    assert (ids[0],ids[1],'child') in kinds
    assert (ids[1],ids[0],'parent') in kinds
    assert (ids[1],ids[2],'child') in kinds
    assert (ids[0],ids[1],'next') in kinds
    found=run_search(db)
    result=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(max_depth=3,max_tokens=20000))
    assert {r['chunk_id'] for r in result['evidence']['results']}==set(ids)
    assert len(result['evidence']['results'])==len(set(ids))
    assert result['usage']['duplicates_skipped']>0
    assert all(r['original_ref']['revision_id']==r['revision_id'] for r in result['evidence']['results'])


def test_reference_resolution_uses_original_text_and_heading_fragment(db):
    con,_,_,_=db
    _,target=publish(db,'target.md','# Target\n## Info\nfirst detail\n## Info\nsecond detail')
    _,source=publish(db,'ref.md','seed [second](target.md#info-1)\n\n[[source:target.md]]')
    found=run_search(db)
    result=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(relations=('references',),max_depth=1,max_tokens=20000))
    paths=result['evidence']['paths']
    assert any(p['from_chunk_id']==source[0] and p['to_chunk_id']==target[1] for p in paths)
    assert paths[0]['classification']=='explicit_reference'
    assert paths[0]['provenance']['target_granularity']=='heading_entry'


def test_missing_unsafe_and_filtered_links_are_explicitly_unresolved(db):
    con,_,_,_=db
    publish(db,'visible.md','seed [missing](missing.md) [unsafe](javascript:bad) [[source:hidden.md]]')
    publish(db,'hidden.md','hidden facts')
    found=run_search(db,keys=['visible.md'])
    result=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(relations=('references',),max_tokens=20000))
    assert len(result['evidence']['results'])==1
    reasons={r['reason'] for r in result['evidence']['unresolved']}
    assert reasons=={'not_in_snapshot','unsupported_scheme'}


def test_explicit_reference_cycle_deduplicates_without_losing_provenance(db):
    con,_,_,_=db
    _,a=publish(db,'a.md','seed [[source:b.md]]')
    _,b=publish(db,'b.md','[[source:a.md]]')
    result=expansion.expand(con,run_search(db)['manifest_id'],expansion.ExpansionOptions(relations=('references',),max_depth=8,max_tokens=20000))
    assert {r['chunk_id'] for r in result['evidence']['results']}=={*a,*b}
    assert result['usage']['duplicates_skipped']==1
    assert not result['truncated']


def test_reply_to_resolves_original_conversation_ids(db):
    con,_,_,_=db
    content=json.dumps({'turns':[{'id':'t0','role':'user','text':'parent message'},{'id':'t1','role':'assistant','text':'seed reply','reply_to':'t0'}]})
    _,ids=publish(db,'chat',content,media=normalize.CONVERSATION_MEDIA_TYPE)
    result=expansion.expand(con,run_search(db)['manifest_id'],expansion.ExpansionOptions(relations=('reply_to',),max_tokens=20000))
    assert any(p['from_chunk_id']==ids[1] and p['to_chunk_id']==ids[0] and p['relation']=='reply_to' for p in result['evidence']['paths'])


@pytest.mark.parametrize('change',['update','delete','delete_restore','new_ready_source'])
def test_standalone_expansion_rejects_changed_snapshot_and_replay_stays_historical(db,change):
    con,_,_,profile=db
    added,_=publish(db,'a.md','seed alpha\n\nbeta')
    found=run_search(db);saved=expansion.expand(con,found['manifest_id'])
    if change=='update':store.update(con,store.UpdateRequest('changed','docs','a.md',added['revision_token'],b'pending change'),profile_key=profile)
    elif change in ('delete','delete_restore'):
        deleted=store.delete(con,store.DeleteRequest('delete','docs','a.md',added['revision_token']))
        if change=='delete_restore':store.restore(con,store.RestoreRequest('restore','docs','a.md',deleted['revision_token']))
    else:publish(db,'new.md','new facts')
    count=con.execute('SELECT COUNT(*) FROM expansion_manifests').fetchone()[0]
    with pytest.raises(expansion.ExpansionError) as error:expansion.expand(con,found['manifest_id'])
    assert error.value.code=='STALE_SNAPSHOT'
    assert con.execute('SELECT COUNT(*) FROM expansion_manifests').fetchone()[0]==count
    replay=expansion.replay(con,saved['expansion_id'])
    assert replay['historical'] and replay['evidence']==saved['evidence']


def test_filtered_out_changes_do_not_invalidate_snapshot(db):
    con,_,_,_=db
    publish(db,'a.md','seed alpha\n\nbeta')
    found=run_search(db,keys=['a.md'])
    publish(db,'outside.md','outside')
    assert expansion.expand(con,found['manifest_id'])['evidence']['results']


def test_semantic_edges_are_opt_in_and_scoped_before_top_k(db):
    con,cfg,space,profile=db
    _,a=publish(db,'a.md','seed alpha',vector=vec(1,0,0,0),media='text/plain')
    for i in range(8):publish(db,f'hidden{i}.md','hidden',vector=vec(1,0,0,0))
    _,b=publish(db,'b.md','allowed nearby',vector=vec(.9,.1,0,0),media='text/plain')
    publish(db,'other-collection','outside',collection='elsewhere',vector=vec(1,0,0,0),media='text/plain')
    con.execute('BEGIN IMMEDIATE');other_space,other_profile=profiles.register_space_and_profile(con,replace(cfg,revision='different'),{});con.commit()
    embeddings.ensure_vec_space_table(con,other_space,4)
    publish(db,'other-model','outside',profile=other_profile,space=other_space,vector=vec(1,0,0,0),media='text/plain')
    found=run_search(db,media_types=['text/plain'])
    plain=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(relations=()))
    assert len(plain['evidence']['results'])==1
    similar=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(relations=(),include_semantic=True,semantic_neighbors=1))
    assert {r['chunk_id'] for r in similar['evidence']['results']}=={*a,*b}
    assert similar['evidence']['paths'][0]['classification']=='inferred'
    assert similar['evidence']['paths'][0]['provenance']['space_id']==space


@pytest.mark.parametrize('option,value,reason',[('max_depth',0,'max_depth'),('max_chunks',1,'max_chunks'),('max_edges',1,'max_edges'),('max_bytes',64,'max_bytes')])
def test_all_expansion_bounds_are_enforced_and_reported(db,option,value,reason):
    con,_,_,_=db;publish(db,'a.md','seed alpha\n\nbeta\n\ngamma\n\ndelta')
    opts=replace(expansion.ExpansionOptions(max_depth=3,max_tokens=20000),**{option:value})
    result=expansion.expand(con,run_search(db)['manifest_id'],opts)
    assert result['truncated'] and reason in result['truncation_reasons']
    assert result['usage']['chunks']<=opts.max_chunks
    assert result['usage']['edges_examined']<=opts.max_edges
    assert result['usage']['bytes']<=opts.max_bytes
    assert result['usage']['tokens']<=opts.max_tokens


def test_token_budget_counts_complete_original_and_derived_evidence_json(db):
    con,_,_,profile=db;publish(db,'a.md','seed 한글 alpha\n\nlonger second paragraph with more facts')
    found=run_search(db)
    first=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(max_depth=0,max_tokens=20000))
    limit=first['usage']['tokens']
    bounded=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(max_depth=3,max_tokens=limit))
    counter=expansion.prepare_counter(con,profile)
    assert bounded['usage']['tokens']==counter.count(relations.compact(bounded['evidence']))<=limit
    assert bounded['usage']['bytes']==len(relations.compact(bounded['evidence']).encode())
    assert 'max_tokens' in bounded['truncation_reasons']
    assert len(bounded['evidence']['results'])==1


def test_invalid_seeds_and_tiny_budget_fail_without_writing_manifest(db):
    con,_,_,_=db;_,ids=publish(db,'a.md','seed alpha\n\nbeta')
    found=run_search(db)
    with pytest.raises(expansion.ExpansionError,match='parent search'):
        expansion.expand(con,found['manifest_id'],seed_chunk_ids=[ids[1]])
    with pytest.raises(expansion.ExpansionError,match='empty evidence'):
        expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(max_tokens=1))
    assert con.execute('SELECT COUNT(*) FROM expansion_manifests').fetchone()[0]==0


def test_inline_expansion_is_persisted_and_replayed_with_parent_search(db):
    con,_,_,_=db;publish(db,'a.md','seed alpha\n\nbeta')
    found=run_search(db,inline=expansion.ExpansionOptions())
    assert found['expansion']['mode']=='inline'
    replay=search.replay_manifest(con,found['manifest_id'])
    assert replay['expansion']['historical']
    assert replay['expansion']['evidence']==found['expansion']['evidence']
    with patch('airag.expansion.persist',side_effect=RuntimeError('write fault')):
        with pytest.raises(RuntimeError):run_search(db,inline=expansion.ExpansionOptions())
    assert con.execute('SELECT COUNT(*) FROM search_manifests').fetchone()[0]==1
    assert con.execute('SELECT COUNT(*) FROM expansion_manifests').fetchone()[0]==1


def test_graph_and_indices_roll_back_together_on_publication_failure(db):
    con,_,space,profile=db
    old,_=publish(db,'a.md','seed old')
    accepted=store.update(con,store.UpdateRequest('new','docs','a.md',old['revision_token'],b'new'),profile_key=profile)
    def fault(connection,generation):
        connection.execute('INSERT INTO generation_graphs(generation_id,version,created_at_ms) VALUES (?,?,?)',(generation,1,0))
        raise RuntimeError('graph publication failure')
    with patch('airag.relations.persist_generation',side_effect=fault):
        with pytest.raises(RuntimeError):store.publish_generation_with_content(con,accepted['generation_id'],standard_md='new',structured_json={},chunk_rows=[{'text':'new','token_count':1,'anchor':{}}],space_id=space,vectors=[vec(1,0,0,0)])
    assert con.execute('SELECT COUNT(*) FROM chunks WHERE generation_id=?',(accepted['generation_id'],)).fetchone()[0]==0
    assert con.execute('SELECT COUNT(*) FROM generation_graphs WHERE generation_id=?',(accepted['generation_id'],)).fetchone()[0]==0
    assert store.get_status(con,'docs','a.md')['ready_generation_id']==old['generation_id']


def test_inline_expansion_keeps_the_same_snapshot_during_concurrent_publish(db,tmp_path,key_bytes):
    con,_,space,profile=db
    old,ids=publish(db,'a.md','seed old\n\nretained neighbor')
    writer=connect.open_encrypted(tmp_path/'graph.db',key_bytes)
    lexical=search._bm25_candidates
    def publish_during_search(*args,**kwargs):
        result=lexical(*args,**kwargs)
        staged=store.update(writer,store.UpdateRequest('concurrent','docs','a.md',old['revision_token'],b'replacement'),profile_key=profile)
        embeddings.ensure_vec_space_table(writer,space,4)
        store.publish_generation_with_content(writer,staged['generation_id'],standard_md='replacement',structured_json={},chunk_rows=[{'text':'replacement','token_count':1,'anchor':{}}],space_id=space,vectors=[vec(1,0,0,0)])
        return result
    try:
        with patch('airag.search._bm25_candidates',side_effect=publish_during_search):found=run_search(db,inline=expansion.ExpansionOptions())
    finally:writer.close()
    assert {r['chunk_id'] for r in found['expansion']['evidence']['results']}==set(ids)
    assert all(r['generation_id']==old['generation_id'] for r in found['expansion']['evidence']['results'])
    with pytest.raises(expansion.ExpansionError,match='changed'):expansion.expand(con,found['manifest_id'])
    assert search.replay_manifest(con,found['manifest_id'])['expansion']['evidence']==found['expansion']['evidence']


def test_forged_cross_scope_structural_edge_cannot_consume_the_candidate_limit(db):
    con,_,_,_=db
    _,outside=publish(db,'outside','outside',collection='elsewhere')
    own,ids=publish(db,'a.md','seed own\n\nown neighbor')
    con.execute('INSERT INTO chunk_edges VALUES (?,?,?,?,?)',(own['generation_id'],ids[0],outside[0],'next','{}'))
    result=expansion.expand(con,run_search(db)['manifest_id'],expansion.ExpansionOptions(relations=('next',),max_edges=1))
    assert {r['chunk_id'] for r in result['evidence']['results']}==set(ids)
    assert result['usage']['edges_examined']==1


def test_generated_embedding_text_cannot_invent_reference_intents(db):
    con,_,space,profile=db
    accepted=store.add(con,store.AddRequest('generated','docs','a',b'original has no link'),profile_key=profile)
    result=store.publish_generation_with_content(con,accepted['generation_id'],standard_md='[[source:invented]]',structured_json={},chunk_rows=[{'text':'[[source:invented]]','token_count':1,'anchor':{}}],space_id=space,vectors=[vec(1,0,0,0)])
    assert con.execute('SELECT COUNT(*) FROM chunk_references WHERE generation_id=?',(result['generation_id'],)).fetchone()[0]==0


def test_ambiguous_conversation_ids_are_reported_not_arbitrarily_selected(db):
    con,_,_,_=db
    text=json.dumps({'turns':[{'id':'same','role':'user','text':'first'},{'id':'same','role':'user','text':'second'},{'id':'reply','role':'assistant','text':'seed answer','reply_to':'same'}]})
    publish(db,'chat',text,media=normalize.CONVERSATION_MEDIA_TYPE)
    result=expansion.expand(con,run_search(db)['manifest_id'],expansion.ExpansionOptions(relations=('reply_to',)))
    assert result['evidence']['unresolved'][0]['reason']=='ambiguous_turn_id'


def test_standalone_expansion_has_no_http_calls(db):
    con,_,_,profile=db;publish(db,'a.md','seed [[source:missing]]')
    found=run_search(db);expansion.prepare_counter(con,profile)
    with patch('urllib.request.urlopen',side_effect=AssertionError('network forbidden')):
        result=expansion.expand(con,found['manifest_id'],expansion.ExpansionOptions(include_semantic=True))
    assert result['evidence']['unresolved']


def test_page_table_sheet_and_frame_relations_use_observed_anchor_identity(db):
    con,_,space,profile=db
    accepted=store.add(con,store.AddRequest('locations','docs','locations',b'fixture'),profile_key=profile)
    rows=[]
    for i in range(3):
        item={'self_ref':'#/tables/0','kind':'document_location','locator':{'format':'pdf','provenance':[{'page_no':2}],'sheet':'Budget','frame':0},'text_origin':'extracted','matched_text':None}
        rows.append({'text':'seed' if i==0 else f'row {i}','token_count':1,'anchor':{'items':[item],'headings':[]}})
    result=store.publish_generation_with_content(con,accepted['generation_id'],standard_md='fixture',structured_json={'tables':[{'self_ref':'#/tables/0','label':'table'}]},chunk_rows=rows,space_id=space,vectors=[vec(1,0,0,0)]*3)
    kinds={r[0] for r in con.execute('SELECT DISTINCT relation FROM chunk_edges WHERE generation_id=?',(result['generation_id'],))}
    assert {'same_page','same_table','same_sheet'}<=kinds
    locators={tuple(r) for r in con.execute('SELECT kind,value FROM chunk_locators WHERE generation_id=?',(result['generation_id'],))}
    assert {('page','2'),('sheet','Budget'),('frame','0'),('node','#/tables/0')}<=locators


def test_conversation_link_resolves_to_registered_document(db):
    con,_,_,_=db
    _,target=publish(db,'details.md','detail information')
    publish(db,'chat',json.dumps({'turns':[{'id':'one','role':'user','text':'seed [[source:details.md]]'}]}),media=normalize.CONVERSATION_MEDIA_TYPE)
    result=expansion.expand(con,run_search(db)['manifest_id'],expansion.ExpansionOptions(relations=('references',)))
    assert result['evidence']['paths'][0]['to_chunk_id']==target[0]
    assert result['evidence']['paths'][0]['provenance']['source']['pointer']=='/turns/0/text'


def test_actual_docx_hyperlink_uses_observed_native_metadata(db):
    pytest.importorskip('docling')
    import io
    from docx import Document
    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn
    from docx.opc.constants import RELATIONSHIP_TYPE as RT
    from airag.document_adapters import DOCX
    con,_,space,profile=db
    _,target=publish(db,'guide.md','guide information',origin_uri='https://example.invalid/guide')
    d=Document();p=d.add_paragraph('seed ')
    link=OxmlElement('w:hyperlink');link.set(qn('r:id'),p.part.relate_to('https://example.invalid/guide',RT.HYPERLINK,is_external=True))
    run=OxmlElement('w:r');text=OxmlElement('w:t');text.text='seedguide';run.append(text);link.append(run);p._p.append(link)
    b=io.BytesIO();d.save(b)
    nd=normalize.build_document(DOCX,b.getvalue(),name='links.docx',config={'adapter':'documents_v1'})
    rows=[]
    for item,_ in nd.doc.iterate_items():
        if not getattr(item,'text',''):continue
        a=chunking._whole_item_anchor(nd.anchors[item.self_ref]);a['self_ref']=item.self_ref
        rows.append({'text':item.text,'token_count':1,'anchor':{'items':[a],'headings':[]}})
    accepted=store.add(con,store.AddRequest('docx-link','docs','links.docx',b.getvalue(),media_type=DOCX),profile_key=profile)
    published=store.publish_generation_with_content(con,accepted['generation_id'],standard_md=nd.doc.export_to_markdown(),structured_json=nd.doc.export_to_dict(),chunk_rows=rows,space_id=space,vectors=[vec(1,0,0,0)]*len(rows))
    assert con.execute('SELECT COUNT(*) FROM chunk_references WHERE generation_id=?',(published['generation_id'],)).fetchone()[0]>0
    result=expansion.expand(con,run_search(db,'seedguide')['manifest_id'],expansion.ExpansionOptions(relations=('references',)))
    assert any(p['to_chunk_id']==target[0] for p in result['evidence']['paths'])


def test_commonmark_parentheses_reference_definitions_and_crlf_positions():
    text='한글\r\n[x](folder(a).md "title")\r\n[ref][id]\r\n\r\n[id]: target.md#part\r\n\r\n    [[source:code]]\r\n\\[[source:escaped]]\r\n[[source:real]]'
    refs=relations.text_references(text)
    assert [r[2]['value'] for r in refs]==['folder(a).md','target.md#part','real']
    assert text[refs[0][0]:refs[0][1]]=='[x](folder(a).md "title")'
    assert text[refs[1][0]:refs[1][1]]=='[ref][id]'
    assert text[refs[2][0]:refs[2][1]]=='[[source:real]]'


def test_reference_uri_normalization_does_not_merge_reserved_paths_or_credentials():
    assert expansion._canonical_uri('https://EXAMPLE.test/%7Euser')=='https://example.test/~user'
    assert expansion._canonical_uri('https://example.test/a%2Fb')!=expansion._canonical_uri('https://example.test/a/b')
    assert expansion._canonical_uri('https://User:Secret@example.test/a')!=expansion._canonical_uri('https://user:secret@example.test/a')
    assert expansion._canonical_uri('file:///자료/문서.md')==expansion._canonical_uri('file:///%EC%9E%90%EB%A3%8C/%EB%AC%B8%EC%84%9C.md')
