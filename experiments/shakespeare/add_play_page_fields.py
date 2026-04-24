#!/usr/bin/env python3
"""
Add 'page' and 'main_image' fields to existing play records,
and update the play class definition to declare those fields.
"""
import json
import os
import re
import sys
from urllib.request import urlopen

SETTINGS_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'settings.json')
API_BASE = 'https://www.unotate.com/api'

settings = json.load(open(SETTINGS_PATH))
DB_PATH  = os.path.join(settings['data'], 'shakespeare.db')
PLAY_IDS = settings['plays']

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'lib'))
import mikobase.engine.sqlite as mb


def fetch_json(url):
    with urlopen(url) as r:
        return json.loads(r.read().decode('utf-8'))


def fetch_html(url):
    with urlopen(url) as r:
        return r.read().decode('utf-8')


def og_image(html):
    m = re.search(r'<meta property="og:image" content="([^"]+)"', html)
    return m.group(1) if m else None


with mb.connect(DB_PATH, 'rw') as engine:

    # --- 1. Update the play class definition ---
    class_records = list(engine.q0({
        'action': 'select',
        'class':  'mikobase.com/record/class',
    }))
    play_class = next(
        (r for r in class_records if r['bucket'].get('name') == 'unotate.com/play'),
        None
    )
    if play_class is None:
        print('ERROR: unotate.com/play class record not found')
        sys.exit(1)

    new_bucket = dict(play_class['bucket'])
    new_bucket['fields']['page'] = {'class': 'url', 'required': True}
    new_bucket['fields']['main_image'] = {'class': 'url'}

    result = engine.q0({
        'action': 'update',
        'pk':     play_class['pk'],
        'bucket': new_bucket,
    })
    if not result['success']:
        print('ERROR updating play class:', result['errors'])
        sys.exit(1)
    print('Updated unotate.com/play class definition')

    # --- 2. Update each play record ---
    for play_id in PLAY_IDS:
        api_url  = f'{API_BASE}/plays/{play_id}/'
        api_data = fetch_json(api_url)
        page_url = api_data.get('page')
        if not page_url:
            print(f'  {play_id}: no page URL in API response, skipping')
            continue

        html      = fetch_html(page_url)
        image_url = og_image(html)

        play_records = list(engine.q0({'action': 'select', 'class': 'unotate.com/play'}))
        play_record  = next(
            (r for r in play_records if r['bucket'].get('id') == play_id),
            None
        )
        if play_record is None:
            print(f'  {play_id}: record not found in DB, skipping')
            continue

        updated_bucket = dict(play_record['bucket'])
        updated_bucket['page'] = page_url
        if image_url:
            updated_bucket['main_image'] = image_url

        result = engine.q0({
            'action': 'update',
            'pk':     play_record['pk'],
            'bucket': updated_bucket,
        })
        if result['success']:
            print(f'  {play_id}: page={page_url}  main_image={image_url}')
        else:
            print(f'  {play_id}: ERROR', result['errors'])
