def to_item(row):
    """조직 1행.

    org_code 는 담지 않는다 — 20260823000001_org_code.sql 이 운영 Supabase에 미적용이라
    select 시 column does not exist(42703)로 500이 된다(LOOM_DOMAIN#8 실측, 2026-09-09).
    적용 후 별건으로 추가한다.
    """
    return row
