"""Bounded OCR and configured vision, with distinct observed/inferred provenance."""
from __future__ import annotations

import base64
import csv
import hashlib
import io
import json
import subprocess
from functools import lru_cache

from airag import llm_enrichment
from airag.document_adapters import DocumentError, _anchor
from airag.normalize import NormalizedDocument

VISION_PROMPT_VERSION = 'airag.image_description.v1'
VISION_PROMPT = ('Describe only what is visibly supported by this image. Do not invent identities, intentions or events. '
                 'Return ONLY one JSON object with description (a concise factual English description) and tags '
                 '(one to five short strings). This is inferred visual interpretation, not verbatim source text.')


def _png(image):
    output = io.BytesIO()
    image.save(output, format='PNG')
    return output.getvalue()


def _rgb(image):
    from PIL import Image
    if image.mode in ('RGBA','LA') or 'transparency' in image.info:
        background=Image.new('RGBA',image.size,'white')
        background.alpha_composite(image.convert('RGBA'))
        return background.convert('RGB')
    return image.convert('RGB')


@lru_cache(maxsize=4)
def _easy_reader(languages, model_path):
    if not model_path:
        raise ValueError('EasyOCR requires an explicitly prepared ocr_model_path')
    import easyocr
    return easyocr.Reader(list(languages), gpu=False, model_storage_directory=model_path, download_enabled=False, verbose=False)


def recognize(image, cfg):
    if cfg['ocr_engine']=='easyocr':
        import numpy as np
        raw = _easy_reader(tuple(cfg['ocr_languages']), cfg['ocr_model_path']).readtext(np.array(image.convert('RGB')))
        return [{'text':text,'polygon':[[float(x),float(y)] for x,y in box],'confidence':float(confidence)}
                for box,text,confidence in raw if text.strip()]
    languages = '+'.join({'ko':'kor','en':'eng'}[x] for x in cfg['ocr_languages'])
    command=['tesseract','stdin','stdout','-l',languages,'--psm',str(cfg['tesseract_psm'])]
    if cfg['tessdata_path']:command+=['--tessdata-dir',cfg['tessdata_path']]
    result = subprocess.run(command+['tsv'], input=_png(image),
                            capture_output=True, timeout=cfg['timeout_s'])
    if result.returncode:
        raise DocumentError('OCR_FAILED', 'Tesseract failed; check configured languages and executable', retryable=False)
    groups = {}
    for word in csv.DictReader(io.StringIO(result.stdout.decode('utf-8')), delimiter='\t', quoting=csv.QUOTE_NONE):
        text = word.get('text','').strip()
        if not text or float(word['conf']) < 0:
            continue
        group = groups.setdefault((word['block_num'],word['par_num'],word['line_num']),[])
        group.append(word)
    output=[]
    for words in groups.values():
        left=min(int(w['left']) for w in words);top=min(int(w['top']) for w in words)
        right=max(int(w['left'])+int(w['width']) for w in words);bottom=max(int(w['top'])+int(w['height']) for w in words)
        output.append({'text':' '.join(w['text'] for w in words),'bbox':[left,top,right,bottom],
                       'confidence':sum(float(w['conf']) for w in words)/(100*len(words))})
    return output


def describe(image, cfg):
    if cfg is None:
        raise DocumentError('VISION_PROVIDER_REQUIRED','vision requires an explicitly captured LLM provider configuration',retryable=False)
    llm_enrichment.validate_config(cfg)
    rendered = _rgb(image).copy()
    rendered.thumbnail((1536,1536))
    encoded = base64.b64encode(_png(rendered)).decode()
    messages=[{'role':'user','content':[{'type':'text','text':VISION_PROMPT},
               {'type':'image_url','image_url':{'url':'data:image/png;base64,'+encoded}}]}]
    tokens=llm_enrichment._post_json(cfg,'/tokenize',{'model':cfg.model,'messages':messages,'add_generation_prompt':True},base=llm_enrichment._root_endpoint(cfg))
    count=tokens.get('count')
    if isinstance(count,bool) or not isinstance(count,int) or count<0:
        raise DocumentError('PROVIDER_BAD_RESPONSE','vision tokenize response lacks a valid count',retryable=False)
    if count+cfg.max_tokens>cfg.context_length:
        raise DocumentError('PROMPT_TOO_LONG','vision input and reserved output exceed model context',retryable=False)
    response=llm_enrichment._post_json(cfg,'/chat/completions',{'model':cfg.model,'messages':messages,'max_tokens':cfg.max_tokens,'temperature':0})
    content,meta=llm_enrichment._validate_response_envelope(cfg,response)
    parsed=llm_enrichment._parse_strict_json_content(content)
    if not isinstance(parsed,dict) or not isinstance(parsed.get('description'),str) or not parsed['description'].strip():
        raise DocumentError('PROVIDER_BAD_RESPONSE','vision description is missing',retryable=False)
    tags=llm_enrichment._validate_tags('image',parsed.get('tags'))
    return {'description':parsed['description'],'tags':tags,'metadata':meta,'prompt_version':VISION_PROMPT_VERSION,
            'input_image_size':list(image.size),'submitted_image_size':list(rendered.size),'transform':'Alpha composited on white; RGB PNG; fit within 1536x1536 without upscaling'}


def build_image(content, name, cfg, vision, heartbeat=None, media_type=None):
    from PIL import Image
    from docling_core.types.doc import DoclingDocument, DocItemLabel
    doc=DoclingDocument(name=name);anchors={};frames=[]
    try:
        opened=Image.open(io.BytesIO(content))
    except Image.DecompressionBombError as exc:
        raise DocumentError('IMAGE_TOO_LARGE','image decoder rejected excessive pixel dimensions',retryable=False) from exc
    with opened as source:
        expected={'image/png':'PNG','image/jpeg':'JPEG','image/tiff':'TIFF','image/bmp':'BMP'}
        if media_type is not None and source.format!=expected[media_type]:
            raise DocumentError('MEDIA_TYPE_MISMATCH','declared image media type differs from decoded format',retryable=False)
        count=getattr(source,'n_frames',1)
        if count>cfg['max_pages']:
            raise ValueError('image exceeds configured frame limit')
        for index in range(count):
            if heartbeat: heartbeat()
            source.seek(index)
            if source.width*source.height>cfg['max_image_pixels']:
                raise ValueError('decoded image exceeds pixel bound')
            image=_rgb(source)
            frame={'frame':index,'size':list(image.size),'rendering':'RGB; alpha composited on white','ocr':[],'vision':None}
            if 'ocr' in cfg['image_mode']:
                frame['ocr']=recognize(image,cfg)
                for line in frame['ocr']:
                    item=doc.add_text(DocItemLabel.TEXT,line['text'])
                    loc={'format':'image','frame':index,'coordinate_unit':'pixel',
                         **{k:v for k,v in line.items() if k!='text'}}
                    anchors[item.self_ref]=_anchor(item.text,loc,origin='ocr',granularity='image_region')
            if 'vision' in cfg['image_mode']:
                if heartbeat: heartbeat()
                frame['vision']=describe(image,vision)
                item=doc.add_text(DocItemLabel.TEXT,frame['vision']['description'])
                anchors[item.self_ref]=_anchor(item.text,{'format':'image','frame':index,'size':list(image.size),
                                                        'prompt_version':VISION_PROMPT_VERSION},origin='inferred',granularity='image')
            frames.append(frame)
    return NormalizedDocument(doc,anchors,{'adapter':'image_v1','mode':cfg['image_mode'],'ocr_engine':cfg['ocr_engine'],
        'tesseract_psm':cfg['tesseract_psm'] if cfg['ocr_engine']=='tesseract' else None,
        'ocr_languages':cfg['ocr_languages'],'model_fingerprints':cfg['model_fingerprints'],'original_sha256':hashlib.sha256(content).hexdigest(),'frames':frames,
        'temporary_files':'Image bytes and Tesseract stdin/stdout remain in memory; EasyOCR receives in-memory pixels',
        'warnings':['OCR is recognized text; vision descriptions are inference, not verbatim original text']})
