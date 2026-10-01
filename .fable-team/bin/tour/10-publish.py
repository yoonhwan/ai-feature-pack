#!/usr/bin/env python3
"""Tour 10: publish reviewed pending windows one at a time with live elapsed updates."""
from pathlib import Path
import runpy
import os
from notebook import Cell,ask,run_notebook
from sample_output import search_output

HERE=Path(__file__).resolve().parent
PYTHON=str(Path.home()/'.local/share/airag/runtime/bin/python')
initialize=runpy.run_path(str(HERE/'03-initialize.py'))
operations=initialize['operations']


def command(action,*args):return [PYTHON,str(HERE/'reviewed_index.py'),action,*args]


def preflight(response,context):
    data=response['data']
    print(f'  저장된 사건: {data["stored_events"]}건 · 수집 끝: {data["through_offset"]:,}바이트')
    print(f'  검색 가능: {data["indexed"]}개 · 대기: {data["pending"]}개 · 실패: {data["failed"]}개')
    print('  모델 연결: '+', '.join(x['service']+' 정상' for x in data['providers']))
    print('\n해설: 09번 승인 범위의 수집 완료를 대조했습니다. 추가 수집은 하지 않습니다.')


def published(response,context):
    data=response['data'];context['published_complete']=data['complete']
    print(f'  이번 처리: {data["attempted"]}개 · 소요 {data["seconds"]}초')
    print(f'  검색 가능: {data["indexed"]}개 · 남은 창: {data["pending"]}개 · 실패: {data["failed"]}개')
    print(f'  새 대화 수집: {data["new_events"]}건')
    metrics=data.get('performance',{})
    if metrics.get('available'):
        print(f'  병렬도: {metrics["concurrency"]} · 처리 결과 캐시: {metrics["result_cache_hits"]}/{metrics["semantic_windows"]}')
        print(f'  보강 처리 구간: {metrics["elapsed_seconds"]:.1f}초 · 생성 요청: {metrics["generation_calls"]}회 · 출력: {metrics["completion_tokens"]}토큰')
        print(f'  정규화: {metrics.get("normalize_seconds",0):.2f}초 · 청크: {metrics.get("source_chunk_seconds",0):.2f}초 · 임베딩: {metrics.get("embedding_seconds",0):.2f}초')
        print(f'  토큰 수 확인: {metrics["tokenize_calls"]}회 / {metrics["tokenize_api_seconds_sum"]:.2f}초')
        if metrics['prompt_tokens']:
            print(f'  서버 입력 KV 캐시: {100*metrics["cached_prompt_tokens"]/metrics["prompt_tokens"]:.1f}%')
        else:
            print('  이번 처리의 새 모델 입력: 없음')


    print('\n해설: 완료된 창은 즉시 검색할 수 있으며, 재시작하면 남은 창부터 처리합니다.')


def question(context,automatic):
    default=context.get('query','백업은 언제 실행하나요?')
    if not automatic:
        value=ask(f'검색할 질문 [Enter = {default}] > ')
        if value.lower() in ('종료','q','quit','exit'):raise SystemExit(0)
        default=value or default
    context['query']=default


def searched(response,context):
    context['hits']=len(response['data'].get('results',[]))
    search_output(response['data'])


def final(response,context):
    data=response['data']
    print(f'  검색 가능한 창: {data["indexed"]}개 · 대기: {data["pending"]}개 · 실패: {data["failed"]}개')
    print(f'  저장된 사건: {data["stored_events"]}건 · 사용 가능한 기억: {data["visible_memories"]}개')
    context['outcome']='reviewed_snapshot_indexed_and_searched' if data['complete'] and context.get('hits',0)>0 else 'results_require_review'
    print('\n해설: 이번에는 승인 범위의 검색 발행까지 확인합니다.')
    print('      새 범위의 기억 추출과 상시 수집은 아직 별도 단계입니다. 기존 감사 gap 1건도 유지됩니다.')


if __name__=='__main__':
    cells=[
        Cell('운영 키 자동 연결','1Password에서 기존 키를 전달합니다.',[PYTHON,str(HERE/'operations_check.py'),'keys'],operations['show_keys'],initialize['keys'],ready=lambda r,c:r['data']['ready']),
        Cell('수집 완료·대기 창 확인','09번 승인 범위와 실제 원장 체크포인트, 모델 연결을 확인합니다.',command('preflight'),preflight),
        Cell('대기 창 검색 발행','Enter/실행은 한 창, 전체실행은 남은 창을 연속 처리합니다. 창마다 결과를 표시하고 오류 시 멈춥니다. 모델 처리에는 시간이 걸립니다.',command('publish'),published,
             ready=lambda r,c:r['data']['complete'],allow_auto_repeat=True,timeout_s=900,heartbeat_s=15),
        Cell('확장된 범위에서 검색','질문을 입력해 실제 근거를 찾아봅니다.',lambda c:command('search',c.get('query','백업은 언제 실행하나요?')),searched,question),
        Cell('전체 발행 상태 확인','발행 대기와 실패가 남아 있는지 확인합니다.',command('status'),final),
    ]
    raise SystemExit(run_notebook('10-publish','10 · 개선된 병렬 색인과 검색',cells,
        introduction='기존 완료 창을 보존하고 남은 창만 처리합니다. 독립 묶음 2개 병렬 + 암호화 결과 캐시를 사용합니다.\n색인 결과에서 실제 모델 요청 수·캐시 적중·구간별 시간을 확인하세요.',
        context={'env':{**os.environ,'AIRAG_LLM_CONCURRENCY':'2','AIRAG_PROCESSING_CACHE':'1'}}))
