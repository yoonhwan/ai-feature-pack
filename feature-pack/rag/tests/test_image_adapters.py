from __future__ import annotations

import io
import struct
from dataclasses import asdict
from unittest.mock import patch

import pytest
from PIL import Image,ImageDraw

from airag import api,embeddings,llm_enrichment,store
from airag import image_adapters as images
from airag.db import connect


def shapes():
    im=Image.new('RGB',(384,256),'white');d=ImageDraw.Draw(im)
    d.ellipse((30,40,190,200),fill='red');d.rectangle((230,80,335,185),fill='blue')
    b=io.BytesIO();im.save(b,format='PNG');return b.getvalue()


def llm():
    return llm_enrichment.ChatCompletionConfig('byz-vllm','http://localhost:9999/v1','fixture-llm',None,24576)


def payload(content='{"description":"A red circle and a blue square.","tags":["shapes"]}'):
    return {'model':'fixture-llm','choices':[{'finish_reason':'stop','message':{'content':content}}]}


def test_vision_budgets_actual_multimodal_prompt_and_preserves_transform_provenance():
    with patch('airag.llm_enrichment._post_json',side_effect=[{'count':300},payload()]) as post:
        result=images.describe(Image.open(io.BytesIO(shapes())),llm())
    assert result['prompt_version']==images.VISION_PROMPT_VERSION
    assert result['metadata']['model_echoed']=='fixture-llm'
    body=post.call_args_list[0].args[2]
    assert body['add_generation_prompt'] and body['messages'][0]['content'][1]['type']=='image_url'
    assert result['input_image_size']==result['submitted_image_size']==[384,256]


@pytest.mark.parametrize('response',[{'count':True},{'count':25000}])
def test_invalid_or_oversized_vision_count_never_reaches_chat(response):
    with patch('airag.llm_enrichment._post_json',return_value=response) as post:
        with pytest.raises(store.ApiError):images.describe(Image.open(io.BytesIO(shapes())),llm())
    assert post.call_count==1


def test_malformed_vision_output_has_no_description_fallback():
    with patch('airag.llm_enrichment._post_json',side_effect=[{'count':300},payload('{"tags":[]}')]):
        with pytest.raises(store.ApiError):images.describe(Image.open(io.BytesIO(shapes())),llm())


def test_image_inference_is_labeled_in_search_and_failed_replacement_keeps_old_ready(tmp_path,key_bytes):
    pytest.importorskip('docling')
    con=connect.init_db(tmp_path/'images.db',key_bytes)
    cfg=embeddings.EmbeddingSpaceConfig('openai-compatible','http://localhost:9999/v1','fixture-embed','fixture-v1',4,tokenizer_revision='97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3')
    try:
        result=api.register_profile(con,{'embedding':asdict(cfg),'llm':asdict(llm()),'normalizer':{'adapter':'documents_v1','image_mode':'vision'}})
        assert result['ok'],result
        key=result['data']['profile_key']
        def group(cfg,units):return [llm_enrichment.SemanticGroup(list(units),'shapes',['shapes'])],{}
        def enrich(cfg,units,*,on_progress=None):
            if on_progress is not None:on_progress()
            return [llm_enrichment.UnitEnrichment(k,['shapes'],'shapes',v) for k,v in units.items()],{}
        with patch('airag.llm_enrichment._post_json',side_effect=[{'count':300},payload()]), \
             patch('airag.llm_enrichment.plan_semantic_groups',side_effect=group), \
             patch('airag.llm_enrichment.enrich_units',side_effect=enrich), \
             patch('airag.embeddings.embed_documents',side_effect=lambda cfg,texts,**kw:[struct.pack('4f',1,0,0,0) for _ in texts]), \
             patch('airag.embeddings.embed_query',return_value=struct.pack('4f',1,0,0,0)):
            added=api.add(con,'image-add','pictures','shapes',shapes(),media_type='image/png',profile_key=key)
            assert added['ok'],added
            found=api.search(con,'pictures','red circle',key)
            assert found['ok'],found
            hit=found['data']['results'][0]
            assert hit['contains_inference'] is True and hit['text_origins']==['inferred']
            assert hit['original_text_is_contiguous'] is False
        with patch('airag.image_adapters.describe',side_effect=store.ApiError('VISION_FAILURE','failed',retryable=False)):
            failed=api.update(con,'image-failure','pictures','shapes',added['data']['revision_token'],shapes(),media_type='image/png',profile_key=key,force_reprocess=True)
        assert not failed['ok']
        assert api.status(con,'pictures','shapes')['data']['ready_generation_id']==added['data']['generation_id']
    finally:con.close()


def test_transparent_pixels_are_composited_not_exposed_as_visible_content():
    image=Image.new('RGBA',(2,2),(255,0,0,0))
    assert images._rgb(image).getpixel((0,0))==(255,255,255)


def test_decoder_pixel_guard_is_a_structured_error():
    from airag import normalize
    with patch.object(Image,'MAX_IMAGE_PIXELS',10):
        with pytest.raises(store.ApiError,match='pixel'):
            normalize.build_document('image/png',shapes(),name='oversized',config={'adapter':'documents_v1','image_mode':'ocr'})
