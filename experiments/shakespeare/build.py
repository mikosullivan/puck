#!/usr/bin/env python3
import hashlib
import json
import os
import re
import sqlite3
import uuid
from urllib.request import urlopen

SETTINGS_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'settings.json')
API_BASE = 'https://www.unotate.com/api'

SCHEMA_SQL = open(
    os.path.join(os.path.dirname(__file__), '..', '..', 'lib', 'mikobase', 'engine', 'schema.sql')
).read()

PLAY_CLASS_BUCKET = {
    "name": "unotate.com/play",
    "fields": {
        "id":      {"class": "string", "required": True, "unique": True},
        "title":   {
            "class": "hash",
            "of": "string",
            "required": True,
            "fields": {
                "long":  {"required": True, "collapse": True},
                "short": {"collapse": True}
            }
        },
        "xml_url": {"class": "url"},
        "xml":     {"class": "mikobase.com/dbfile"}
    }
}

PLAY_PLAYWRIGHT_CLASS_BUCKET = {
    "name": "unotate.com/play-playwright",
    "fields": {
        "play":       {"class": "mikobase.com/reference", "allowed_class": "unotate.com/play"},
        "playwright": {"class": "mikobase.com/reference", "allowed_class": "unotate.com/playwright"}
    },
    "join": ["play", "playwright"]
}

PLAYWRIGHT_CLASS_BUCKET = {
    "name": "unotate.com/playwright",
    "fields": {
        "name": {
            "class": "hash",
            "of": "string",
            "required": True,
            "default": {"collapse": True},
            "fields": {
                "surname": {"required": True},
                "middle":  {},
                "given":   {"required": True}
            }
        },
        "id":        {"class": "string", "required": True, "unique": True},
        "image_url": {"class": "url"}
    }
}


def gen_pk():
    return str(uuid.uuid4())


def fetch_json(url):
    with urlopen(url) as resp:
        return json.loads(resp.read())


def fetch_html(url):
    with urlopen(url) as resp:
        return resp.read().decode('utf-8')


def og_image(html):
    m = re.search(r'<meta property="og:image" content="([^"]+)"', html)
    return m.group(1) if m else None


def insert_record(conn, class_name, bucket):
    pk = gen_pk()
    conn.execute("insert into records(record_pk) values(?)", (pk,))
    conn.execute(
        "insert into records_history(record_pk, class, bucket, custom_classes) values(?,?,?,?)",
        (pk, class_name, json.dumps(bucket, ensure_ascii=False), '{}')
    )
    return pk


def update_record(conn, pk, new_bucket):
    conn.execute(
        "insert into records_history(record_pk, class, bucket, custom_classes)"
        " select record_pk, class, ?, custom_classes from current_records where record_pk = ?",
        (json.dumps(new_bucket, ensure_ascii=False), pk)
    )


def store_file(conn, content):
    sha256  = hashlib.sha256(content).hexdigest()
    file_pk = gen_pk()
    conn.execute(
        "insert into files(file_pk, size, sha256) values(?,?,?)",
        (file_pk, len(content), sha256)
    )
    conn.execute(
        "insert into file_chunks(file_pk, chunk_index, content, last) values(?,?,?,1)",
        (file_pk, 0, content)
    )
    return file_pk


def split_name(full_name):
    parts = full_name.strip().rsplit(' ', 1)
    if len(parts) == 1:
        return '', parts[0]
    return parts[0], parts[1]


def get_pk(conn, class_name, id_value):
    row = conn.execute(
        "select record_pk from current_records where class = ? and json_extract(bucket, '$.id') = ?",
        (class_name, id_value)
    ).fetchone()
    return row[0] if row else None


def print_records(conn):
    rows = conn.execute(
        "select bucket, class from current_records order by class, updated_at"
    ).fetchall()
    current_class = None
    for bucket_json, class_name in rows:
        if class_name != current_class:
            if current_class is not None:
                print()
            print(class_name)
            print('=' * 60)
            current_class = class_name
        print(json.dumps(json.loads(bucket_json), ensure_ascii=False, indent=4))
        print()


# ------------------------------------------------------------------
# phase 1: initial build
# ------------------------------------------------------------------

def phase_build(conn, settings):
    print('=== phase 1: build ===')

    insert_record(conn, 'mikobase.com/record/class', PLAY_CLASS_BUCKET)
    insert_record(conn, 'mikobase.com/record/class', PLAYWRIGHT_CLASS_BUCKET)
    insert_record(conn, 'mikobase.com/record/class', PLAY_PLAYWRIGHT_CLASS_BUCKET)

    playwrights = fetch_json(API_BASE + '/playwrights/')
    for slug, pw in playwrights.items():
        detail    = fetch_json(pw['api'])
        full_name = detail.get('name', '') or ''
        given, surname = split_name(full_name)
        image_url = detail.get('image') or None
        bucket = {"name": {"given": given, "surname": surname}, "id": slug}
        if image_url:
            bucket["image_url"] = image_url
        insert_record(conn, 'unotate.com/playwright', bucket)

    html = fetch_html('https://www.unotate.com/api/plays/')
    xml_urls = {
        m.group(1): 'https://www.unotate.com/shakespeare/' + m.group(1) + '//xml'
        for m in re.finditer(r'href="/shakespeare/([^/]+)//xml"', html)
    }

    play_details = {}
    for play_id in settings.get('plays', []):
        detail = fetch_json(API_BASE + '/plays/' + play_id + '/')
        title  = detail.get('title', {})
        bucket = {
            "id":    play_id,
            "title": {"long": title.get('long', ''), "short": title.get('short', '')}
        }
        if play_id in xml_urls:
            xml_url = xml_urls[play_id]
            bucket["xml_url"] = xml_url
            print('  fetching XML for', play_id, '...')
            xml_content = urlopen(xml_url).read()
            bucket["xml"] = store_file(conn, xml_content)
        insert_record(conn, 'unotate.com/play', bucket)
        play_details[play_id] = detail

    for play_id, detail in play_details.items():
        play_pk = get_pk(conn, 'unotate.com/play', play_id)
        for pw_id in detail.get('playwrights', {}).keys():
            playwright_pk = get_pk(conn, 'unotate.com/playwright', pw_id)
            if play_pk and playwright_pk:
                insert_record(conn, 'unotate.com/play-playwright', {
                    "play":       play_pk,
                    "playwright": playwright_pk
                })

    conn.commit()
    print()


# ------------------------------------------------------------------
# phase 2: refactor — add page and main_image to plays
# ------------------------------------------------------------------

def phase_add_play_urls(conn, settings):
    print('=== phase 2: add page and main_image to plays ===')

    # update the class definition
    class_pk, class_bucket_json = conn.execute(
        "select record_pk, bucket from current_records"
        " where class = 'mikobase.com/record/class'"
        " and json_extract(bucket, '$.name') = 'unotate.com/play'"
    ).fetchone()
    class_bucket = json.loads(class_bucket_json)
    class_bucket['fields']['page']       = {'class': 'url', 'required': True}
    class_bucket['fields']['main_image'] = {'class': 'url'}
    update_record(conn, class_pk, class_bucket)
    print('  updated unotate.com/play class definition')

    # update each play record
    for play_id in settings.get('plays', []):
        api_data  = fetch_json(API_BASE + '/plays/' + play_id + '/')
        page_url  = api_data.get('page')
        if not page_url:
            print(f'  {play_id}: no page in API, skipping')
            continue

        image_url = og_image(fetch_html(page_url))

        play_pk, play_bucket_json = conn.execute(
            "select record_pk, bucket from current_records"
            " where class = 'unotate.com/play'"
            " and json_extract(bucket, '$.id') = ?",
            (play_id,)
        ).fetchone()
        play_bucket = json.loads(play_bucket_json)
        play_bucket['page'] = page_url
        if image_url:
            play_bucket['main_image'] = image_url
        update_record(conn, play_pk, play_bucket)
        print(f'  {play_id}: page and main_image added')

    conn.commit()
    print()


# ------------------------------------------------------------------

def main():
    with open(SETTINGS_PATH) as f:
        settings = json.load(f)

    db_path = os.path.join(settings['data'], 'shakespeare.db')
    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    conn.execute("pragma foreign_keys = on")
    conn.executescript(SCHEMA_SQL)

    phase_build(conn, settings)
    phase_add_play_urls(conn, settings)

    print('=== final records ===')
    print()
    print_records(conn)

    conn.close()


if __name__ == '__main__':
    main()
