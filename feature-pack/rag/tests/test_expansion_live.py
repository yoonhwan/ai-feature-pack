"""Opt-in installed-CLI P05 proof with real GPU embeddings and no model mocks."""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


def corpus():
    return {
        'policy.md': '''# ORION refund guide
ORION overview explains how customers request a refund for a damaged parcel. The overview connects the eligibility checks, the evidence requirements, and the submission procedure. Read [the receipts requirement](details.md#receipts) before sending the request.

## Eligibility
Customers should first check whether the purchase was made directly from the store and whether the delivered item is damaged. Keep the packaging and photograph the parcel before disposing of anything. Include the order number and delivery date when describing the damage. These details help the support team identify the correct purchase and distinguish delivery damage from ordinary wear.

## Submission
Send the refund request through the order support form. Explain what arrived, which part is damaged, and when the problem was noticed. Attach clear photographs of the product and its packaging. Keep a copy of the submitted request so that any later reply can be connected to the same case without repeating the entire history.
''',
        'details.md': '''# Refund evidence
## Receipts
A refund request requires the purchase receipt, the order identifier, and photographs of the damaged parcel. The receipt establishes which item was purchased and how much was paid. The order identifier connects the request to the store record.
## Photos
Provide photographs showing the package label and the damaged item. Images should show the damage clearly without hiding important details.
''',
        'support.md': '''# Support for refund requests
The customer support team reviews refund evidence and answers questions about receipts and damaged packages. Keep the order identifier available when contacting support about a refund. A clear description of delivery damage and readable purchase evidence helps the support team process the request.
''',
    }


@pytest.mark.integration
def test_real_gpu_cli_expansion_snapshot_budget_and_replay(tmp_path,key_bytes):
    revision=os.environ.get('AIRAG_EMBED_REVISION')
    if not revision:pytest.skip('set AIRAG_EMBED_REVISION to an explicit operator/probe declaration')
    cli=str(Path(sys.executable).with_name('ai-rag'));db=tmp_path/'live-expansion.db';trace=[]
    report={'status':'running','scope':'Real GPU installed CLI; structural/reference/semantic expansion and immutable replay','trace':trace}
    def call(*args,error=None):
        r,w=os.pipe();os.write(w,key_bytes);os.close(w)
        try:p=subprocess.run([cli,*args,'--key-fd',str(r)],cwd=tmp_path,pass_fds=(r,),capture_output=True,text=True,timeout=240)
        finally:os.close(r)
        env=json.loads(p.stdout);trace.append({'command':list(args),'exit_code':p.returncode,'response':env})
        if error:assert p.returncode==4 and env['error']['code']==error,env
        else:assert p.returncode==0 and env['ok'],env
        return env['data']
    try:
        call('init',str(db))
        cfg=tmp_path/'profile.json'
        cfg.write_text(json.dumps({'embedding':{'provider':'openai-compatible','endpoint':os.environ.get('AIRAG_EMBED_ENDPOINT','http://127.0.0.1:18811/v1'),'model':'byz-embed','revision':revision,'dimension':1024,'tokenizer_revision':'97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3','max_tokens':96,'timeout_s':60},'llm':{'provider':'byz-vllm','endpoint':os.environ.get('AIRAG_LLM_ENDPOINT','http://127.0.0.1:18002/v1'),'model':'byz-llm','weights_revision':os.environ.get('AIRAG_LLM_REVISION'),'context_length':24576,'timeout_s':90}}),encoding='utf-8')
        profile=call('manage','profile','--db',str(db),'--config',str(cfg))['profile_key']
        added={}
        for key,text in corpus().items():
            added[key]=call('add','--db',str(db),'--collection','refund','--source-key',key,'--request-id',key,'--profile-key',profile,'--media-type','text/markdown','--text',text)
        found=call('search','--db',str(db),'--collection','refund','--profile-key',profile,'--query','ORION overview','--top-k','1','--expand','--include-semantic','--semantic-neighbors','10','--min-similarity','0.3','--max-depth','2','--max-tokens','64000','--max-bytes','1048576')
        inline=found['expansion']
        assert found['results'][0]['source_key']=='policy.md'
        assert any(p['relation']=='references' for p in inline['evidence']['paths'])
        assert any(p['classification']=='inferred' for p in inline['evidence']['paths'])
        assert any(p['classification']=='structural' for p in inline['evidence']['paths'])
        assert {r['source_key'] for r in inline['evidence']['results']}==set(corpus())
        assert inline['usage']['tokens']<=64000 and inline['usage']['bytes']<=1048576
        separate=call('expand','--db',str(db),'--manifest-id',str(found['manifest_id']),'--relation','references','--max-depth','1','--max-tokens','64000')
        assert any(p['relation']=='references' for p in separate['evidence']['paths'])
        bounded=call('expand','--db',str(db),'--manifest-id',str(found['manifest_id']),'--max-chunks','1','--max-tokens','64000')
        assert bounded['truncated'] and bounded['usage']['chunks']==1
        call('delete','--db',str(db),'--collection','refund','--source-key','support.md','--request-id','delete-support','--expected-revision',added['support.md']['revision_token'])
        call('expand','--db',str(db),'--manifest-id',str(found['manifest_id']),error='STALE_SNAPSHOT')
        replay=call('fetch','expansion','--db',str(db),'--expansion-id',str(inline['expansion_id']))
        assert replay['historical'] and replay['evidence']==inline['evidence']
        assert replay['options']==inline['options']
        source=call('fetch','original','--db',str(db),'--collection','refund','--source-key','support.md','--revision-id',str(added['support.md']['revision_id']),'--include-bytes')
        assert base64.b64decode(source['content_base64']).decode()==corpus()['support.md']
        report['status']='passed'
    finally:
        output=Path(os.environ.get('AIRAG_P05_REPORT',str(tmp_path/'p05-live.json')))
        report['workdir']=str(tmp_path);report['command_count']=len(trace)
        output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
