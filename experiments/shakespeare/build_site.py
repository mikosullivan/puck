#!/usr/bin/env python3
"""Build a static website from the Shakespeare database into the data directory."""
import json
import os
import sqlite3

SETTINGS_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'settings.json')

settings  = json.load(open(SETTINGS_PATH))
DATA_DIR  = settings['data']
DB_PATH   = os.path.join(DATA_DIR, 'shakespeare.db')
SITE_DIR  = os.path.join(DATA_DIR, 'site')

conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row


def records(class_name):
    rows = conn.execute(
        "select record_pk, bucket from current_records where class = ?",
        (class_name,)
    ).fetchall()
    return [{'pk': r['record_pk'], **json.loads(r['bucket'])} for r in rows]


def write_text(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    print('  wrote', os.path.relpath(path, SITE_DIR))


def write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)
    print('  wrote', os.path.relpath(path, SITE_DIR))


# ------------------------------------------------------------------
# HTML site stylesheet
# ------------------------------------------------------------------

SITE_CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: Georgia, serif; background: #faf8f3; color: #222; }
a { color: #5a3e1b; }
a:hover { color: #a0522d; }

header { background: #2c1a0e; color: #f5e6c8; padding: 1.2rem 2rem; }
header h1 { font-size: 1.4rem; font-weight: normal; letter-spacing: .05em; }
header h1 a { color: inherit; text-decoration: none; }

nav { font-size: .85rem; margin-top: .3rem; }
nav a { color: #c8a97e; text-decoration: none; }
nav a:hover { text-decoration: underline; }
nav span { color: #7a6040; margin: 0 .4rem; }

main { max-width: 960px; margin: 2rem auto; padding: 0 1.5rem; }

h2 { font-size: 1.6rem; font-weight: normal; margin-bottom: 1.5rem; color: #3a2510; }

/* play grid */
.play-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 1.5rem; }
.play-card { text-decoration: none; color: inherit; }
.play-card img { width: 100%; aspect-ratio: 3/4; object-fit: cover; border-radius: 4px; display: block; }
.play-card .no-image { width: 100%; aspect-ratio: 3/4; background: #e8dcc8; border-radius: 4px;
    display: flex; align-items: center; justify-content: center; color: #9a8060; font-size: .8rem; }
.play-card .title { margin-top: .5rem; font-size: .95rem; line-height: 1.3; }
.play-card:hover .title { text-decoration: underline; }

/* play detail */
.play-detail { display: grid; grid-template-columns: 220px 1fr; gap: 2rem; align-items: start; }
.play-detail img { width: 100%; border-radius: 4px; }
.play-detail .no-image { width: 100%; aspect-ratio: 3/4; background: #e8dcc8; border-radius: 4px;
    display: flex; align-items: center; justify-content: center; color: #9a8060; }
.play-info h2 { margin-bottom: .3rem; }
.play-info .long-title { font-size: 1rem; color: #7a6040; margin-bottom: 1rem; }
.play-info h3 { font-size: 1rem; color: #5a3e1b; margin: 1.2rem 0 .4rem; }
.play-info ul { list-style: none; }
.play-info ul li { margin-bottom: .4rem; }
.play-info .links { font-size: .85rem; color: #7a6040; margin-top: 1.5rem; line-height: 2; }
.play-info .links a { color: #5a3e1b; display: inline-block; margin-right: 1rem; }

/* playwright grid */
.pw-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 1.5rem; margin-top: 2rem; }
.pw-card { text-align: center; text-decoration: none; color: inherit; }
.pw-card img { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 50%; display: block; }
.pw-card .no-image { width: 100%; aspect-ratio: 1; background: #e8dcc8; border-radius: 50%;
    display: flex; align-items: center; justify-content: center; color: #9a8060; font-size: .75rem; }
.pw-card .name { margin-top: .5rem; font-size: .9rem; line-height: 1.3; }
.pw-card:hover .name { text-decoration: underline; }

@media (max-width: 600px) {
    .play-detail { grid-template-columns: 1fr; }
}
"""

# ------------------------------------------------------------------
# XML play stylesheet
# ------------------------------------------------------------------

PLAY_XML_CSS = """\
/* ----------------------------------------------------------------
   Shakespeare play XML stylesheet
   Applied via <?xml-stylesheet?> processing instruction.
   Targets the Unotate XML format where text is wrapped in
   <word> and <punctuation> elements.
---------------------------------------------------------------- */

/* reset */
* { box-sizing: border-box; }

/* hide metadata elements */
statistics,
scenelanguage,
scenepersonae,
personae persaliases { display: none }

/* ---- page chrome ---- */
play {
    display: block;
    font-family: Georgia, serif;
    background: #ffffff;
    color: #222;
    max-width: 780px;
    margin: 0 auto;
    padding: 2rem 1.5rem 4rem;
}

/* ---- play header ---- */
title {
    display: block;
    font-size: 1.9rem;
    font-weight: normal;
    color: #2c1a0e;
    margin-bottom: .4rem;
    line-height: 1.2;
}

playwright {
    display: block;
    font-size: 1rem;
    color: #7a6040;
    margin-bottom: .2rem;
}

pubdate {
    display: block;
    font-size: .85rem;
    color: #9a8060;
    margin-bottom: 2.5rem;
}

/* ---- dramatis personae ---- */
personae {
    display: block;
    border: 1px solid #d8c8a8;
    border-radius: 4px;
    padding: 1.2rem 1.5rem;
    margin-bottom: 3rem;
    background: #f3ede0;
}

personae::before {
    content: "Dramatis Personae";
    display: block;
    font-size: .75rem;
    letter-spacing: .12em;
    text-transform: uppercase;
    color: #9a8060;
    margin-bottom: 1rem;
}

persona {
    display: block;
    margin-bottom: .35rem;
    font-size: .95rem;
}

persname { display: inline }

/* ---- acts ---- */
act {
    display: block;
    margin-bottom: 3rem;
}

acttitle {
    display: block;
    font-size: 1.1rem;
    letter-spacing: .1em;
    text-transform: uppercase;
    color: #9a8060;
    border-bottom: 1px solid #d8c8a8;
    padding-bottom: .4rem;
    margin-bottom: 2rem;
}

/* ---- scenes ---- */
scene {
    display: block;
    margin-bottom: 2.5rem;
}

scenetitle {
    display: block;
    font-size: .85rem;
    letter-spacing: .1em;
    text-transform: uppercase;
    color: #b09060;
    margin-bottom: .4rem;
}

scenelocation {
    display: block;
    font-style: italic;
    color: #7a6040;
    font-size: .9rem;
    margin-bottom: .2rem;
}

scenetime {
    display: block;
    font-size: .8rem;
    color: #9a8060;
    margin-bottom: 1.2rem;
}

/* ---- stage directions ---- */
stagedir {
    display: block;
    font-style: italic;
    color: #7a6040;
    margin: .6rem 0 .6rem 2rem;
    font-size: .9rem;
}

dir { display: inline }

/* ---- speeches ---- */
speech {
    display: block;
    margin-bottom: .8rem;
}

speaker {
    display: block;
    font-weight: bold;
    font-size: .8rem;
    letter-spacing: .06em;
    color: #3a2510;
    margin-bottom: .15rem;
}

line {
    display: block;
    padding-left: 2rem;
    line-height: 1.6;
}

/* ---- inline text ---- */
word, punctuation { display: inline }
"""


def page(title, breadcrumb, body, root='./'):
    nav_home = f'<a href="{root}index.html">Home</a>'
    nav = (f'<nav>{nav_home}{"".join("<span>›</span>" + b for b in breadcrumb)}</nav>'
           if breadcrumb else f'<nav>{nav_home}</nav>')
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} — Shakespeare</title>
<style>{SITE_CSS}</style>
</head>
<body>
<header>
  <h1><a href="{root}index.html">Shakespeare</a></h1>
  {nav}
</header>
<main>
{body}
</main>
</body>
</html>"""


def pw_name(pw):
    n = pw.get('name', {})
    parts = [n.get('given', ''), n.get('middle', ''), n.get('surname', '')]
    return ' '.join(p for p in parts if p)


def is_shakespeare(pw):
    return pw.get('id') == 'shakespeare'


def sort_playwrights(pws):
    return sorted(pws, key=lambda pw: (0 if is_shakespeare(pw) else 1, pw_name(pw)))


def build():
    plays       = records('unotate.com/play')
    playwrights = records('unotate.com/playwright')
    joins       = records('unotate.com/play-playwright')

    pw_by_pk   = {pw['pk']: pw for pw in playwrights}
    play_by_pk = {p['pk']: p  for p  in plays}

    play_pws = {}
    for j in joins:
        play_pws.setdefault(j['play'], []).append(j['playwright'])

    pw_plays = {}
    for j in joins:
        pw_plays.setdefault(j['playwright'], []).append(j['play'])

    # shared XML stylesheet
    write_text(os.path.join(SITE_DIR, 'play.css'), PLAY_XML_CSS)

    # ------------------------------------------------------------------
    # index
    # ------------------------------------------------------------------
    cards = []
    for p in sorted(plays, key=lambda x: x['title']['short']):
        img = (f'<img src="{p["main_image"]}" alt="{p["title"]["short"]}">'
               if p.get('main_image') else '<div class="no-image">no image</div>')
        cards.append(
            f'<a class="play-card" href="plays/{p["id"]}/index.html">'
            f'{img}<div class="title">{p["title"]["short"]}</div></a>'
        )
    body = f'<h2>Plays</h2><div class="play-grid">{"".join(cards)}</div>'

    shakespeare = next((pw for pw in playwrights if is_shakespeare(pw)), None)
    other_pws   = sorted((pw for pw in playwrights if not is_shakespeare(pw)), key=pw_name)

    def pw_card(pw, href):
        img = (f'<img src="{pw["image_url"]}" alt="{pw_name(pw)}">'
               if pw.get('image_url') else '<div class="no-image">no image</div>')
        return (f'<a class="pw-card" href="{href}">'
                f'{img}<div class="name">{pw_name(pw)}</div></a>')

    body += '<h2 style="margin-top:2.5rem">Playwright</h2>'
    if shakespeare:
        body += (f'<div class="pw-grid" style="max-width:200px">'
                 f'{pw_card(shakespeare, "playwrights/shakespeare/index.html")}'
                 f'</div>')

    if other_pws:
        other_cards = ''.join(
            pw_card(pw, f'playwrights/{pw["id"]}/index.html') for pw in other_pws
        )
        body += '<h2 style="margin-top:2rem;font-size:1.1rem">Other Playwrights</h2>'
        body += f'<div class="pw-grid">{other_cards}</div>'

    write_text(os.path.join(SITE_DIR, 'index.html'), page('Shakespeare', [], body))

    # ------------------------------------------------------------------
    # play pages + XML files
    # ------------------------------------------------------------------
    for p in plays:
        pws = sort_playwrights([pw_by_pk[pk] for pk in play_pws.get(p['pk'], []) if pk in pw_by_pk])
        pw_links = ', '.join(
            f'<a href="../../playwrights/{pw["id"]}/index.html">{pw_name(pw)}</a>'
            for pw in pws
        )

        img = (f'<img src="{p["main_image"]}" alt="{p["title"]["short"]}">'
               if p.get('main_image') else '<div class="no-image">no image</div>')

        info = f'<h2>{p["title"]["short"]}</h2>'
        short = p['title']['short']
        long_ = p['title']['long']
        if long_ != short:
            info += f'<p class="long-title">{long_}</p>'
        if pw_links:
            info += f'<h3>Playwright{"s" if len(pws) > 1 else ""}</h3><p>{pw_links}</p>'

        links = ''
        if p.get('page'):
            links += f'<a href="{p["page"]}" target="_blank">View on Unotate ↗</a>'
        if p.get('xml'):
            links += f'<a href="play.xml">Read the play (XML) ↗</a>'
        if links:
            info += f'<div class="links">{links}</div>'

        body = (f'<div class="play-detail">'
                f'<div>{img}</div>'
                f'<div class="play-info">{info}</div>'
                f'</div>')

        write_text(
            os.path.join(SITE_DIR, 'plays', p['id'], 'index.html'),
            page(short, [short], body, root='../../')
        )

        # write XML with stylesheet PI injected after the XML declaration
        if p.get('xml'):
            file_pk = p['xml']
            xml_bytes = conn.execute(
                'select content from file_chunks where file_pk = ?', (file_pk,)
            ).fetchone()[0]
            xml_text = xml_bytes.decode('utf-8')
            pi = '<?xml-stylesheet type="text/css" href="../../play.css"?>\n'
            # insert PI after the <?xml ...?> declaration if present
            if xml_text.startswith('<?xml'):
                end = xml_text.index('?>') + 2
                xml_text = xml_text[:end] + '\n' + pi + xml_text[end:]
            else:
                xml_text = pi + xml_text
            write_text(
                os.path.join(SITE_DIR, 'plays', p['id'], 'play.xml'),
                xml_text
            )

    # ------------------------------------------------------------------
    # playwright pages
    # ------------------------------------------------------------------
    for pw in playwrights:
        name = pw_name(pw)
        img  = (f'<img src="{pw["image_url"]}" alt="{name}" style="width:160px;border-radius:4px">'
                if pw.get('image_url') else '')

        their_plays = [play_by_pk[pk] for pk in pw_plays.get(pw['pk'], []) if pk in play_by_pk]
        play_items  = ''.join(
            f'<li><a href="../../plays/{p["id"]}/index.html">{p["title"]["short"]}</a></li>'
            for p in sorted(their_plays, key=lambda x: x['title']['short'])
        )

        body = (f'<div class="play-detail">'
                f'<div>{img}</div>'
                f'<div class="play-info">'
                f'<h2>{name}</h2>'
                f'{"<h3>Plays</h3><ul>" + play_items + "</ul>" if play_items else ""}'
                f'</div></div>')

        write_text(
            os.path.join(SITE_DIR, 'playwrights', pw['id'], 'index.html'),
            page(name, [name], body, root='../../')
        )


build()
conn.close()
print()
print('site:', SITE_DIR)
