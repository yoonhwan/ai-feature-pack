"""Opt-in P-04 GPU checks; fixtures/models are explicitly prepared beforehand."""
from __future__ import annotations

import base64
import os

import pytest

from airag import api
from airag.db import connect
from airag.document_adapters import DOCX,XLSX
from test_document_adapters import config,docx_bytes,xlsx_bytes,pdf_bytes,image_bytes,sample,pdf_config,hwp_config
from test_image_adapters import shapes


def case(name):
    if name=='pdf':return 'application/pdf',pdf_bytes(),pdf_config(),'Coffee inventory','Coffee'
    if name=='docx':return DOCX,docx_bytes()[0],config(),'Coffee inventory','Coffee'
    if name=='xlsx':return XLSX,xlsx_bytes(),config(),'Coffee bean count','Beans'
    if name=='hwp':return 'application/x-hwp',sample('표.hwp'),hwp_config(),'ABC 123','ABC'
    if name=='hwpx':return 'application/hwp+zip',sample('SimpleTable.hwpx'),config(),'Numbers in the table','5'
    if name=='hwpx_text':return 'application/hwp+zip',sample('sample1.hwpx'),config(),'수학에 대한 내용','수학'
    if name=='mixed_pdf':return 'application/pdf',pdf_bytes(mixed=True),pdf_config(),'고양이는 무엇을 많이 하나요?','고양이'
    if name=='ocr':return 'image/png',image_bytes()[0],config(image_mode='ocr'),'고양이는 무엇을 많이 하나요?','고양이'
    return 'image/png',shapes(),config(image_mode='vision'),'Which red geometric shape is visible?','red'


@pytest.mark.integration
@pytest.mark.parametrize('kind',['pdf','docx','xlsx','hwp','hwpx','hwpx_text','mixed_pdf','ocr','vision'])
def test_actual_document_gpu_roundtrip(kind,tmp_path,key_bytes):
    revision=os.environ.get('AIRAG_EMBED_REVISION')
    if not revision:pytest.skip('set AIRAG_EMBED_REVISION to an explicit operator/probe declaration')
    media,content,normalizer,query,expected=case(kind)
    con=connect.init_db(tmp_path/'live-document.db',key_bytes)
    try:
        profile=api.register_profile(con,{
            'embedding':{'provider':'openai-compatible','endpoint':os.environ.get('AIRAG_EMBED_ENDPOINT','http://127.0.0.1:18811/v1'),'model':'byz-embed','revision':revision,'dimension':1024,'tokenizer_revision':'97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3','timeout_s':60},
            'llm':{'provider':'byz-vllm','endpoint':os.environ.get('AIRAG_LLM_ENDPOINT','http://127.0.0.1:18002/v1'),'model':'byz-llm','weights_revision':os.environ.get('AIRAG_LLM_REVISION'),'context_length':24576,'timeout_s':90},
            'normalizer':normalizer,
        })
        assert profile['ok'],profile
        key=profile['data']['profile_key']
        added=api.add(con,'add-'+kind,kind,kind,content,media_type=media,profile_key=key)
        assert added['ok'] and added['data']['searchable'],added
        found=api.search(con,kind,query,key)
        assert found['ok'] and found['data']['results'],found
        evidence=found['data']['results']
        assert expected.lower() in ''.join(''.join(x['original_text'] for x in evidence).split()).lower()
        original=api.fetch_original(con,kind,kind,include_bytes=True)
        assert original['ok'] and base64.b64decode(original['data']['content_base64'])==content
        if kind=='vision':
            assert evidence[0]['contains_inference'] and not evidence[0]['original_text_is_contiguous']
        if kind=='ocr':assert 'ocr' in evidence[0]['text_origins']
        manifest=api.fetch_manifest(con,found['data']['manifest_id'])
        assert manifest['ok'] and manifest['data']['results']==evidence
    finally:con.close()
