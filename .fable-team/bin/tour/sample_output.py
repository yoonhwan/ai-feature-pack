def status_output(data):
    print('현재 샘플')
    for label, key in [('검색 가능한 창', 'indexed'), ('최근 활성 창', 'active'),
                       ('이전 검색 창', 'older_searchable'), ('사용 가능한 기억', 'visible_memories'),
                       ('실패', 'failed'), ('처리 대기', 'pending'), ('검증된 백업 수', 'backup_count')]:
        print(f'  {label:14} {data.get(key, "확인 필요")}')
    print('\n해설: 최근 활성 창은 대화에 우선 넣는 범위입니다.')
    print('      이전 창도 보관 기간 안에서는 검색할 수 있습니다.')
    if data.get('gaps'):
        print(f'      감사 gap {data["gaps"]}건은 거부 사유가 기록된 입력입니다.')
    if any(not row.get('complete_through_current_snapshot', True)
           for row in data.get('collector_sources', [])):
        print('      이 투어는 고정된 검증 샘플입니다. 이후 새 세션 로그는 아직 수집하지 않았습니다.')

def find_text(value):
    if not isinstance(value, dict):
        return ''
    for key in ('text', 'translation_en', 'original_text', 'content', 'snippet'):
        text = value.get(key)
        if isinstance(text, str) and text.strip():
            return text
    for key in ('chunk', 'result', 'evidence'):
        nested = value.get(key)
        if isinstance(nested, dict):
            text = find_text(nested)
            if text:
                return text
    return ''

def search_output(data):
    history = data.get('conversation', data)
    hits = history.get('results', [])
    print(f'검색 결과: {len(hits)}건')
    for index, hit in enumerate(hits[:3], 1):
        text = ' '.join(find_text(hit).split())
        print(f'\n  [{index}] {text[:420] + ("…" if len(text) > 420 else "") if text else "본문은 raw에서 확인하세요."}')
        anchors = hit.get('message_anchors') or []
        if anchors:
            anchor = anchors[0]
            turn_id = anchor.get('turn_id') if isinstance(anchor, dict) else None
            if turn_id:
                print(f'      근거 메시지: {turn_id}')
        elif hit.get('source_key'):
            print(f'      출처: {hit["source_key"]}')
    print('\n해설: 이것은 과거 근거를 찾은 검색 결과입니다. 새로 생성한 답변은 아닙니다.')
    print('      영어 번역 청크가 표시될 수 있으며, 원문 연결 정보는 raw로 볼 수 있습니다.')
    if not hits:
        print('      결과가 없으면 더 짧은 핵심어로 재실행해 보세요.')
