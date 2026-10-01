from __future__ import annotations

import json
import struct
from unittest.mock import patch

import pytest

from airag import api,embeddings,expansion,profiles,relations,search,store
from airag.db import connect,schema


def legacy_v4(path,key):
    con=connect._open_non_mutating(path,key,allow_create=True)
    connect._enable_wal(con)
    con.execute('BEGIN IMMEDIATE')
    schema.create_base_tables(con);schema.create_v2_tables(con);schema.create_v3_tables(con);schema.create_v4_tables(con)
    con.execute("INSERT INTO db_meta VALUES ('engine','airag')")
    con.execute('INSERT INTO schema_migrations VALUES (4,0)')
    cfg=embeddings.EmbeddingSpaceConfig('openai-compatible','http://localhost:9999/v1','fixture','v1',4,tokenizer_revision='97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3')
    space,profile=profiles.register_space_and_profile(con,cfg,{})
    con.commit()
    receipt=store.add(con,store.AddRequest('original-request','docs','original',b'alpha\n\nbeta',explicit_profile_key=profile),profile_key=profile)
    table=embeddings.ensure_vec_space_table(con,space,4)
    con.execute('BEGIN IMMEDIATE')
    gid=receipt['generation_id'];sid=receipt['source_id']
    con.execute('INSERT INTO normalized_documents VALUES (?,?,?,0)',(gid,'alpha\n\nbeta','{}'))
    con.execute("INSERT INTO chunks(generation_id,chunk_index,text,token_count,anchor_json,created_at_ms) VALUES (?,0,'alpha',1,'{}',0)",(gid,))
    con.execute("INSERT INTO chunks(generation_id,chunk_index,text,token_count,anchor_json,created_at_ms) VALUES (?,1,'beta',1,'{}',0)",(gid,))
    for cid,text,vector in ((1,'alpha',struct.pack('4f',1,0,0,0)),(2,'beta',struct.pack('4f',0,1,0,0))):
        con.execute('INSERT INTO fts_chunks(rowid,text,chunk_id,source_id,collection_id) VALUES (?,?,?,?,1)',(cid,text,cid,sid))
        con.execute(f'INSERT INTO {table}(chunk_id,embedding,source_id,collection_id,generation_id,active) VALUES (?,?,?,1,?,1)',(cid,vector,sid,gid))
    con.execute("UPDATE generations SET status='ready' WHERE generation_id=?",(gid,))
    con.execute('UPDATE sources SET ready_generation_id=?,state_version=2 WHERE source_id=?',(gid,sid))
    final={'source_id':sid,'revision_id':receipt['revision_id'],'generation_id':gid,'revision_token':store.encode_revision_token(sid,2),'state_version':2,'status':'ready','searchable':True,'chunk_count':2,'processing_status':'ready'}
    con.execute("UPDATE jobs SET status='done',final_response_json=? WHERE job_id=?",(json.dumps(final),receipt['job_id']))
    old_result=[{'chunk_id':1,'generation_id':gid,'revision_id':receipt['revision_id'],'original_text':'alpha'}]
    con.execute('INSERT INTO search_manifests(collection_id,query_text,profile_key,space_id,filters_json,eligible_json,results_json,created_at_ms) VALUES (1,?,?,?,?,?,?,0)',('alpha',profile,space,'{}','{}',json.dumps(old_result)))
    ledger=con.execute('SELECT response_json FROM request_ledger').fetchone()[0]
    con.commit();con.close()
    return gid,profile,ledger,old_result


def test_v4_graph_backfill_preserves_originals_receipts_and_legacy_manifest(tmp_path,key_bytes):
    path=tmp_path/'old.db';gid,profile,ledger,old=legacy_v4(path,key_bytes)
    con=connect.open_encrypted(path,key_bytes)
    try:
        assert connect.read_schema_version(con)==5
        assert con.execute('SELECT content_bytes FROM source_revisions').fetchone()[0]==b'alpha\n\nbeta'
        assert con.execute('SELECT response_json FROM request_ledger').fetchone()[0]==ledger
        replayed=api.add(con,'original-request','docs','original',b'alpha\n\nbeta',profile_key=profile)
        assert replayed['ok'] and replayed['data']['revision_token']==store.encode_revision_token(1,2)
        assert con.execute('SELECT COUNT(*) FROM jobs').fetchone()[0]==1
        assert con.execute('SELECT version FROM generation_graphs WHERE generation_id=?',(gid,)).fetchone()[0]==1
        assert con.execute("SELECT COUNT(*) FROM chunk_edges WHERE relation='next'").fetchone()[0]==1
        assert search.replay_manifest(con,1)['results']==old
        fresh=search.search(con,search.SearchQuery('docs','alpha','alpha',struct.pack('4f',1,0,0,0),1,profile,top_k=1))
        assert fresh['results'][0]['embedded_text']=='alpha'
        with pytest.raises(expansion.ExpansionError) as e:expansion.expand(con,1)
        assert e.value.code=='LEGACY_MANIFEST'
    finally:con.close()


def test_failed_backfill_rolls_back_schema_upgrade(tmp_path,key_bytes):
    path=tmp_path/'old.db';legacy_v4(path,key_bytes)
    with patch('airag.relations.persist_generation',side_effect=RuntimeError('injected migration failure')):
        with pytest.raises(RuntimeError):connect.open_encrypted(path,key_bytes)
    con=connect._open_non_mutating(path,key_bytes,allow_create=False)
    try:
        assert schema._read_schema_version(con)==4
        assert con.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='chunk_edges'").fetchone()[0]==0
        assert con.execute('SELECT COUNT(*) FROM chunks').fetchone()[0]==2
    finally:con.close()


def test_new_graph_limits_do_not_make_old_source_data_inaccessible(tmp_path,key_bytes):
    path=tmp_path/'old.db';gid,profile,ledger,old=legacy_v4(path,key_bytes)
    with patch('airag.relations.persist_generation',side_effect=relations.GraphLimitError('legacy graph exceeds bound')):
        con=connect.open_encrypted(path,key_bytes)
    try:
        assert connect.read_schema_version(con)==5
        assert con.execute('SELECT version,error FROM generation_graphs').fetchone()==(0,'legacy graph exceeds bound')
        assert search.replay_manifest(con,1)['results']==old
        assert store.fetch_original(con,'docs','original',include_bytes=True)['byte_length']==len(b'alpha\n\nbeta')
        fresh=search.search(con,search.SearchQuery('docs','alpha','alpha',struct.pack('4f',1,0,0,0),1,profile,top_k=1))
        assert fresh['results'][0]['embedded_text']=='alpha'
        with pytest.raises(expansion.ExpansionError,match='exceeds bound'):expansion.expand(con,fresh['manifest_id'])
    finally:con.close()
