from dataclasses import replace
import json
import sqlite3
import threading
import time
from unittest.mock import patch

import pytest
from airag import embeddings, llm_enrichment as llm, pipeline, processing, provider_metrics
from airag.db import connect


def config(revision='weights-r1'):
    return pipeline.PipelineConfig(
        embeddings.EmbeddingSpaceConfig('openai-compatible','http://localhost:9/v1','fixture','rev',4,
            tokenizer_revision='97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3'),
        1,llm.ChatCompletionConfig('byz-vllm','http://localhost:9/v1','fixture',revision,24576))


def grouped(cfg, units):
    return [llm.SemanticGroup(list(units),'summary',['fixture'])], {'prompt_version':cfg.group_prompt_version}


def enriched(cfg, units, **kwargs):
    return [llm.UnitEnrichment(uid,['fixture'],'summary',text) for uid,text in units.items()], {'prompt_version':cfg.enrich_prompt_version}


def test_parallel_bound_order_and_db_owner_thread(tmp_path):
    con=connect.init_db(tmp_path/'encrypted.db', b'c'*32)
    cache=processing.ResultCache(con,config())
    owner=threading.get_ident();renew_threads=[];active=0;peak=0;lock=threading.Lock();barrier=threading.Barrier(2)
    def group(cfg, units):
        nonlocal active,peak
        uid=next(iter(units))
        with lock:active+=1;peak=max(peak,active)
        if uid in ('chunk-0','chunk-4'):barrier.wait(timeout=2)
        time.sleep(.04 if uid=='chunk-0' else .01)
        with lock:active-=1
        return grouped(cfg,units)
    windows=[(i,{f'chunk-{i}':f'PRIVATE_FIXTURE_{i}'}) for i in (0,4,8,12)]
    with patch.object(llm,'plan_semantic_groups',side_effect=group),patch.object(llm,'enrich_units',side_effect=enriched):
        result=processing.run_windows(windows,config(),lambda:renew_threads.append(threading.get_ident()),concurrency=2,cache=cache,heartbeat_s=.005)
    assert [i for i,_ in result]==[0,4,8,12]
    assert peak==2 and set(renew_threads)=={owner}
    assert con.execute('SELECT count(*) FROM airag_processing_cache_v1').fetchone()[0]==4
    con.close()
    assert b'PRIVATE_FIXTURE' not in (tmp_path/'encrypted.db').read_bytes()


def test_persistent_cache_reuse_and_context_model_invalidation(tmp_path):
    path=tmp_path/'encrypted.db';con=connect.init_db(path,b'c'*32)
    windows=[(0,{'chunk-0':'content with heading'})]
    with patch.object(llm,'plan_semantic_groups',side_effect=grouped),patch.object(llm,'enrich_units',side_effect=enriched):
        processing.run_windows(windows,config(),lambda:None,cache=processing.ResultCache(con,config()))
    con.close();con=connect.open_encrypted(path,b'c'*32)
    cache=processing.ResultCache(con,config())
    with patch.object(llm,'plan_semantic_groups',side_effect=AssertionError('cache missed')):
        replay=processing.run_windows(windows,config(),lambda:None,concurrency=2,cache=cache)
    assert replay[0][1][-1]['cache_hit'] is True
    assert replay[0][1][-1]['http_calls']==[]
    assert cache.get(0,{'chunk-0':'content with another heading'}) is None
    assert processing.ResultCache(con,config('weights-r2')).get(*windows[0]) is None
    assert cache.get(4,{'chunk-4':'content with heading'}) is None
    con.close()


def test_corrupted_cache_is_not_used(tmp_path):
    con=connect.init_db(tmp_path/'encrypted.db',b'c'*32);cache=processing.ResultCache(con,config())
    window=(0,{'chunk-0':'fixture'})
    with patch.object(llm,'plan_semantic_groups',side_effect=grouped),patch.object(llm,'enrich_units',side_effect=enriched):
        processing.run_windows([window],config(),lambda:None,cache=cache)
    con.execute("UPDATE airag_processing_cache_v1 SET payload='{}'")
    assert cache.get(*window) is None
    with patch.object(llm,'plan_semantic_groups',side_effect=grouped) as provider,patch.object(llm,'enrich_units',side_effect=enriched):
        result=processing.run_windows([window],config(),lambda:None,cache=cache)
    assert provider.call_count==1 and not result[0][1][-1]['cache_hit']
    con.close()


def test_unversioned_model_does_not_use_persistent_cache():
    con=sqlite3.connect(':memory:',isolation_level=None);cache=processing.ResultCache(con,config(None))
    assert not cache.enabled
    assert con.execute("SELECT 1 FROM sqlite_master WHERE name='airag_processing_cache_v1'").fetchone() is None
    con.close()


def test_parallel_failure_returns_no_partial_results():
    def group(cfg,units):
        if 'chunk-4' in units:raise llm.LLMError('PROVIDER_BAD_RESPONSE','fixture',retryable=False)
        return grouped(cfg,units)
    with patch.object(llm,'plan_semantic_groups',side_effect=group),patch.object(llm,'enrich_units',side_effect=enriched):
        with pytest.raises(llm.LLMError):
            processing.run_windows([(0,{'chunk-0':'a'}),(4,{'chunk-4':'b'})],config(),lambda:None,concurrency=2,heartbeat_s=.001)


def test_metrics_keep_only_timing_and_numeric_usage():
    @provider_metrics.timed_request
    def request(cfg,path,body):
        return {'choices':[{'content':'RESPONSE_SECRET'}], 'usage':{'prompt_tokens':12,'completion_tokens':4,'prompt_tokens_details':{'cached_tokens':8},'other':'SECRET'}}
    with provider_metrics.capture() as calls:request(None,'/chat/completions',{'text':'INPUT_SECRET'})
    assert calls[0]['prompt_tokens']==12 and calls[0]['cached_prompt_tokens']==8
    assert calls[0]['completion_tokens']==4
    assert 'SECRET' not in json.dumps(calls)


def test_lost_claim_does_not_commit_worker_results():
    begun=threading.Event();writes=[]
    class Cache:
        def get(self,*args):return None
        def put(self,*args):writes.append(args)
    def group(cfg,units):
        begun.set()
        return grouped(cfg,units)
    def renew():
        if begun.is_set():raise RuntimeError('claim_lost')
    with patch.object(llm,'plan_semantic_groups',side_effect=group),patch.object(llm,'enrich_units',side_effect=enriched):
        with pytest.raises(RuntimeError,match='claim_lost'):
            processing.run_windows([(0,{'chunk-0':'a'}),(4,{'chunk-4':'b'})],config(),renew,concurrency=2,cache=Cache(),heartbeat_s=.001)
    assert writes==[]


def test_successful_units_survive_failed_attempt_without_caching_failed_unit(tmp_path):
    con=connect.init_db(tmp_path/'encrypted.db',b'c'*32);cache=processing.ResultCache(con,config())
    windows=[(0,{'chunk-0':'a'}),(4,{'chunk-4':'b'})]
    saved=threading.Event()
    original_put=cache.put
    def put(*args):
        original_put(*args);saved.set()
    cache.put=put
    def group(cfg,units):
        if 'chunk-4' in units:
            assert saved.wait(timeout=2)
            raise llm.LLMError('PROVIDER_BAD_RESPONSE','fixture',retryable=False)
        return grouped(cfg,units)
    with patch.object(llm,'plan_semantic_groups',side_effect=group),patch.object(llm,'enrich_units',side_effect=enriched):
        with pytest.raises(llm.LLMError):processing.run_windows(windows,config(),lambda:None,concurrency=2,cache=cache,heartbeat_s=.001)
    assert cache.get(*windows[0]) is not None and cache.get(*windows[1]) is None
    with patch.object(llm,'plan_semantic_groups',side_effect=grouped) as provider,patch.object(llm,'enrich_units',side_effect=enriched):
        result=processing.run_windows(windows,config(),lambda:None,concurrency=2,cache=cache)
    assert provider.call_count==1 and result[0][1][-1]['cache_hit']
    con.close()
