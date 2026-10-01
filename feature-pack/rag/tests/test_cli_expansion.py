"""Installed CLI graph flow using an explicitly synthetic local HTTP provider."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from test_cli_processing import provider


def test_cli_inline_standalone_filters_replay_and_stale_rejection(tmp_path,key_bytes,provider):
    cli=str(Path(sys.executable).with_name('ai-rag'));db=tmp_path/'expand.db'
    def call(*args,error=None):
        r,w=os.pipe();os.write(w,key_bytes);os.close(w)
        try:p=subprocess.run([cli,*args,'--key-fd',str(r)],cwd=tmp_path,pass_fds=(r,),capture_output=True,text=True,timeout=45)
        finally:os.close(r)
        env=json.loads(p.stdout)
        if error:
            assert p.returncode==4 and env['error']['code']==error,env
        else:assert p.returncode==0 and env['ok'],env
        return env
    call('init',str(db))
    cfg=tmp_path/'profile.json'
    cfg.write_text(json.dumps({'embedding':{'provider':'openai-compatible','endpoint':provider,'model':'fixture-embed','revision':'fixture-v1','dimension':4,'tokenizer_revision':'97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3'},'llm':{'provider':'byz-vllm','endpoint':provider,'model':'fixture-llm','weights_revision':None,'context_length':24576}}),encoding='utf-8')
    profile=call('manage','profile','--db',str(db),'--config',str(cfg))['data']['profile_key']
    added={}
    for key,text in [('main.md','Start [[source:details.md]]'),('details.md','Support details.'),('extra.md','Another passage.')]:
        added[key]=call('add','--db',str(db),'--collection','docs','--source-key',key,'--request-id',key,'--profile-key',profile,'--text',text)['data']
    found=call('search','--db',str(db),'--collection','docs','--query','cats','--profile-key',profile,'--top-k','1','--expand','--relation','references','--max-tokens','20000')['data']
    assert {r['source_key'] for r in found['expansion']['evidence']['results']}=={'main.md','details.md'}
    separate=call('expand','--db',str(db),'--manifest-id',str(found['manifest_id']),'--include-semantic','--semantic-neighbors','3','--max-tokens','20000')['data']
    assert {r['source_key'] for r in separate['evidence']['results']}==set(added)
    assert any(p['classification']=='inferred' for p in separate['evidence']['paths'])
    scoped=call('search','--db',str(db),'--collection','docs','--query','cats','--profile-key',profile,'--source-key','main.md','--expand','--relation','references')['data']
    assert len(scoped['expansion']['evidence']['results'])==1
    assert scoped['expansion']['evidence']['unresolved'][0]['reason']=='not_in_snapshot'
    call('search','--db',str(db),'--collection','docs','--query','cats','--profile-key',profile,'--max-depth','1',error='VALIDATION_ERROR')
    call('delete','--db',str(db),'--collection','docs','--source-key','details.md','--request-id','delete','--expected-revision',added['details.md']['revision_token'])
    call('expand','--db',str(db),'--manifest-id',str(found['manifest_id']),error='STALE_SNAPSHOT')
    replay=call('fetch','expansion','--db',str(db),'--expansion-id',str(separate['expansion_id']))['data']
    assert replay['historical'] and replay['evidence']==separate['evidence']
    original=call('fetch','manifest','--db',str(db),'--manifest-id',str(found['manifest_id']))['data']
    assert original['expansion']['historical'] and original['expansion']['evidence']==found['expansion']['evidence']
