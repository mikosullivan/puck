import json
import os
import sqlite3
import uuid
from contextlib import contextmanager

from mikobase.engine.base import BaseEngine

_SCHEMA_SQL = open(os.path.join(os.path.dirname(__file__), 'schema.sql')).read()


def _gen_pk():
    return str(uuid.uuid4())


def _ok(results=None):
    r = {'success': True}
    if results is not None:
        r['results'] = results
    return r


def _err(error_id, details=None):
    return {'success': False, 'errors': [{'id': error_id, 'details': details or {}}]}


def _resolve_allowed_classes(field_def):
    """Merge allowed_class / allowed_classes into a single unique list."""
    merged = []
    seen = set()
    for key in ('allowed_class', 'allowed_classes'):
        v = field_def.get(key)
        if v is None:
            continue
        items = [v] if isinstance(v, str) else list(v)
        for item in items:
            if item not in seen:
                seen.add(item)
                merged.append(item)
    return merged


def _normalize_class_bucket(bucket):
    """Normalize allowed_class / allowed_classes in every field definition."""
    fields = bucket.get('fields')
    if not fields:
        return bucket
    new_fields = {}
    for fname, fdef in fields.items():
        if not isinstance(fdef, dict) or ('allowed_class' not in fdef and 'allowed_classes' not in fdef):
            new_fields[fname] = fdef
            continue
        resolved = _resolve_allowed_classes(fdef)
        new_fdef = {k: v for k, v in fdef.items() if k not in ('allowed_class', 'allowed_classes')}
        new_fdef['allowed_classes'] = resolved
        new_fields[fname] = new_fdef
    return {**bucket, 'fields': new_fields}


def _normalize_mode(mode):
    if not isinstance(mode, str) or mode != mode.strip():
        return None, _err('invalid-mode', {'mode': mode})
    low = mode.lower()
    if low in ('rw', 'wr'):
        return 'rw', None
    if low == 'r':
        return 'r', None
    return None, _err('invalid-mode', {'mode': mode})


def _schema_exists(conn):
    row = conn.execute(
        "select name from sqlite_master where type='table' and name='records'"
    ).fetchone()
    return row is not None


def _init_schema(conn):
    conn.executescript(_SCHEMA_SQL)


def _row_to_record(row):
    # Columns: record_pk, class, updated_at, bucket, custom_classes
    return {
        'pk':             row[0],
        'class':          row[1],
        'updated_at':     row[2],
        'bucket':         json.loads(row[3]),
        'custom_classes': json.loads(row[4]),
    }


def _history_row_to_record(row):
    # Columns: instance_pk, record_pk, updated_at, active, bucket, class, custom_classes
    bucket_json = row[4]
    cc_json     = row[6]
    return {
        'instance_pk':    row[0],
        'pk':             row[1],
        'updated_at':     row[2],
        'active':         bool(row[3]),
        'class':          row[5],
        'bucket':         json.loads(bucket_json) if bucket_json else None,
        'custom_classes': json.loads(cc_json) if cc_json else {},
    }


class _SelectResult:
    def __init__(self, cursor, warnings=None, row_mapper=None):
        self.success     = True
        self.errors      = []
        self.warnings    = warnings or []
        self.count       = 0
        self._cursor     = cursor
        self._row_mapper = row_mapper if row_mapper is not None else _row_to_record

    def __iter__(self):
        for row in self._cursor:
            self.count += 1
            yield self._row_mapper(row)


class _SelectError:
    def __init__(self, errors):
        self.success  = False
        self.errors   = errors
        self.warnings = []
        self.count    = 0

    def __iter__(self):
        return iter([])


class SqliteEngine(BaseEngine):

    def __init__(self, conn, mode, cutoff=None):
        self._conn   = conn
        self._mode   = mode
        self._cutoff = cutoff

    # ------------------------------------------------------------------
    # q0 dispatch
    # ------------------------------------------------------------------

    def q0(self, query):
        try:
            if not isinstance(query, dict):
                return _err('invalid_request', {'message': 'query must be a JSON object'})
            action = query.get('action')
            if action == 'select':
                return self._q_select(query)
            if action == 'create':
                return self._q_create(query)
            if action == 'update':
                return self._q_update(query)
            if action == 'delete':
                return self._q_delete(query)
            return _err('invalid_request', {'message': 'missing or unknown action: ' + repr(action)})
        except Exception as exc:
            return _err('invalid_request', {'message': str(exc)})

    # ------------------------------------------------------------------
    # select
    # ------------------------------------------------------------------

    def _source(self):
        """Return (sql_fragment, params) for the active-record source."""
        if self._cutoff is None:
            return 'current_records', []
        sql = (
            '(WITH _ranked AS ('
            '  SELECT *, ROW_NUMBER() OVER ('
            '    PARTITION BY record_pk ORDER BY updated_at DESC, instance_pk DESC'
            '  ) AS row_num FROM records_history WHERE updated_at <= ?'
            ') SELECT record_pk, class, updated_at, bucket, custom_classes'
            '  FROM _ranked WHERE row_num = 1 AND active = 1) AS _hist'
        )
        return sql, [self._cutoff]

    def _q_select(self, query):
        if query.get('history'):
            return self._q_select_history(query)
        try:
            warnings = []

            # class / classes
            has_class   = 'class'   in query
            has_classes = 'classes' in query
            if has_class and has_classes:
                warnings.append({'id': 'redundant_fields', 'details': {'fields': ['class', 'classes']}})

            class_names = []
            if has_class:
                v = query['class']
                class_names += [v] if isinstance(v, str) else list(v)
            if has_classes:
                v = query['classes']
                class_names += [v] if isinstance(v, str) else list(v)
            seen, unique_classes = set(), []
            for n in class_names:
                if n not in seen:
                    seen.add(n)
                    unique_classes.append(n)
            class_names = unique_classes

            pk = query.get('pk')

            source, source_params = self._source()

            # Build the core SQL
            if class_names:
                # Seed the CTE with all requested class names, then traverse
                # stored class definitions to find subclasses. Class resolution
                # always uses current_records, not the historical source.
                seed = ' UNION ALL '.join('SELECT ?' for _ in class_names)
                sql = (
                    'WITH RECURSIVE _sub(name) AS ('
                    '  ' + seed +
                    '  UNION ALL'
                    '  SELECT json_extract(cr.bucket, \'$.name\')'
                    '  FROM current_records cr'
                    '  JOIN _sub s ON json_extract(cr.bucket, \'$.inherits\') = s.name'
                    '  WHERE cr.class = \'mikobase.com/record/class\''
                    ')'
                    ' SELECT record_pk, class, updated_at, bucket, custom_classes'
                    ' FROM ' + source +
                    ' WHERE class IN (SELECT name FROM _sub)'
                )
                params = list(class_names) + source_params
                if pk is not None:
                    sql += ' AND record_pk = ?'
                    params.append(pk)
            elif pk is not None:
                sql = (
                    'SELECT record_pk, class, updated_at, bucket, custom_classes'
                    ' FROM ' + source + ' WHERE record_pk = ?'
                )
                params = source_params + [pk]
            else:
                sql = (
                    'SELECT record_pk, class, updated_at, bucket, custom_classes'
                    ' FROM ' + source
                )
                params = source_params

            # sort / sorts
            has_sort  = 'sort'  in query
            has_sorts = 'sorts' in query
            if has_sort and has_sorts:
                warnings.append({'id': 'redundant_fields', 'details': {'fields': ['sort', 'sorts']}})

            sort_paths = []
            if has_sort:
                sort_paths.append(query['sort'])
            if has_sorts:
                sort_paths += query['sorts']

            order_cols = []
            for path in sort_paths:
                keys = [k for k in path if isinstance(k, str)]
                qual = path[-1] if path and isinstance(path[-1], dict) else {}
                if keys:
                    col = "json_extract(bucket, '$." + '.'.join(keys) + "')"
                    direction = 'DESC' if qual.get('reverse') else 'ASC'
                    order_cols.append(col + ' IS NULL, ' + col + ' ' + direction)

            if order_cols:
                sql += ' ORDER BY ' + ', '.join(order_cols)

            # limit / offset
            limit  = query.get('limit')
            offset = query.get('offset')
            if limit is not None:
                sql   += ' LIMIT ?'
                params.append(limit)
            if offset is not None:
                sql   += ' OFFSET ?'
                params.append(offset)

            cursor = self._conn.execute(sql, params)
            return _SelectResult(cursor, warnings)

        except Exception as exc:
            return _SelectError([{'id': 'invalid_request', 'details': {'message': str(exc)}}])

    def _q_select_history(self, query):
        try:
            warnings = []

            # class / classes — same merging logic as regular select
            has_class   = 'class'   in query
            has_classes = 'classes' in query
            if has_class and has_classes:
                warnings.append({'id': 'redundant_fields', 'details': {'fields': ['class', 'classes']}})

            class_names = []
            if has_class:
                v = query['class']
                class_names += [v] if isinstance(v, str) else list(v)
            if has_classes:
                v = query['classes']
                class_names += [v] if isinstance(v, str) else list(v)
            seen, unique_classes = set(), []
            for n in class_names:
                if n not in seen:
                    seen.add(n)
                    unique_classes.append(n)
            class_names = unique_classes

            pk = query.get('pk')

            cte_sql    = ''
            cte_params = []
            where      = []
            where_params = []

            if class_names:
                seed = ' UNION ALL '.join('SELECT ?' for _ in class_names)
                cte_sql = (
                    'WITH RECURSIVE _sub(name) AS ('
                    '  ' + seed +
                    '  UNION ALL'
                    '  SELECT json_extract(cr.bucket, \'$.name\')'
                    '  FROM current_records cr'
                    '  JOIN _sub s ON json_extract(cr.bucket, \'$.inherits\') = s.name'
                    '  WHERE cr.class = \'mikobase.com/record/class\''
                    ') '
                )
                cte_params = list(class_names)
                where.append('rh.class IN (SELECT name FROM _sub)')

            if pk is not None:
                where.append('rh.record_pk = ?')
                where_params.append(pk)

            if self._cutoff is not None:
                where.append('rh.updated_at <= ?')
                where_params.append(self._cutoff)

            sql = (
                cte_sql +
                'SELECT rh.instance_pk, rh.record_pk, rh.updated_at, rh.active,'
                '       rh.bucket, rh.class, rh.custom_classes'
                ' FROM records_history rh'
            )
            if where:
                sql += ' WHERE ' + ' AND '.join(where)
            sql += ' ORDER BY rh.record_pk, rh.updated_at, rh.instance_pk'

            params = cte_params + where_params

            limit  = query.get('limit')
            offset = query.get('offset')
            if limit is not None:
                sql   += ' LIMIT ?'
                params.append(limit)
            if offset is not None:
                sql   += ' OFFSET ?'
                params.append(offset)

            cursor = self._conn.execute(sql, params)
            return _SelectResult(cursor, warnings, row_mapper=_history_row_to_record)

        except Exception as exc:
            return _SelectError([{'id': 'invalid_request', 'details': {'message': str(exc)}}])

    # ------------------------------------------------------------------
    # create
    # ------------------------------------------------------------------

    def _check_writable(self):
        if self._mode == 'r' or self._cutoff is not None:
            return _err('read-only-connection', {})
        return None

    def _q_create(self, query):
        err = self._check_writable()
        if err:
            return err

        bucket = query.get('bucket')
        if bucket is None:
            return _err('invalid_request', {'message': "'bucket' is required"})
        if not isinstance(bucket, dict):
            return _err('invalid_request', {'message': "'bucket' must be a JSON object"})

        class_name     = query.get('class') or 'mikobase.com/record'
        custom_classes = query.get('custom_classes') or {}
        pk             = _gen_pk()

        try:
            self._conn.execute('BEGIN')
            self._conn.execute('INSERT INTO records(record_pk) VALUES(?)', (pk,))
            self._conn.execute(
                'INSERT INTO records_history(record_pk, class, bucket, custom_classes)'
                ' VALUES(?,?,?,?)',
                (pk, class_name,
                 json.dumps(bucket, ensure_ascii=False),
                 json.dumps(custom_classes))
            )
            self._conn.execute('COMMIT')
            return _ok({'pk': pk})
        except Exception as exc:
            try:
                self._conn.execute('ROLLBACK')
            except Exception:
                pass
            return _err('invalid_request', {'message': str(exc)})

    # ------------------------------------------------------------------
    # update
    # ------------------------------------------------------------------

    def _q_update(self, query):
        err = self._check_writable()
        if err:
            return err

        pk = query.get('pk')
        if pk is None:
            return _err('invalid_request', {'message': "'pk' is required"})

        new_bucket = query.get('bucket')
        new_class  = query.get('class')
        if new_bucket is None and new_class is None:
            return _err('invalid_request', {'message': "one of 'bucket' or 'class' is required"})
        if new_bucket is not None and not isinstance(new_bucket, dict):
            return _err('invalid_request', {'message': "'bucket' must be a JSON object"})

        try:
            self._conn.execute('BEGIN')

            row = self._conn.execute(
                'SELECT class, bucket, custom_classes FROM current_records WHERE record_pk = ?',
                (pk,)
            ).fetchone()

            if row is None:
                self._conn.execute('ROLLBACK')
                exists = self._conn.execute(
                    'SELECT 1 FROM records WHERE record_pk = ?', (pk,)
                ).fetchone()
                return _err('record_deleted' if exists else 'record_not_found', {'pk': pk})

            final_class  = new_class  if new_class  is not None else row[0]
            final_bucket = new_bucket if new_bucket is not None else json.loads(row[1])
            final_cc     = query.get('custom_classes', json.loads(row[2]) if row[2] else {})

            self._conn.execute(
                'INSERT INTO records_history(record_pk, class, bucket, custom_classes)'
                ' VALUES(?,?,?,?)',
                (pk, final_class,
                 json.dumps(final_bucket, ensure_ascii=False),
                 json.dumps(final_cc))
            )
            self._conn.execute('COMMIT')
            return _ok({'pk': pk})
        except Exception as exc:
            try:
                self._conn.execute('ROLLBACK')
            except Exception:
                pass
            return _err('invalid_request', {'message': str(exc)})

    # ------------------------------------------------------------------
    # delete
    # ------------------------------------------------------------------

    def _q_delete(self, query):
        err = self._check_writable()
        if err:
            return err

        pk = query.get('pk')
        if pk is None:
            return _err('invalid_request', {'message': "'pk' is required"})

        if_exists = query.get('if_exists', False)

        try:
            self._conn.execute('BEGIN')

            active = self._conn.execute(
                'SELECT 1 FROM current_records WHERE record_pk = ?', (pk,)
            ).fetchone()

            if active is None:
                self._conn.execute('ROLLBACK')
                if if_exists:
                    return _ok({'pk': pk, 'deleted': False})
                exists = self._conn.execute(
                    'SELECT 1 FROM records WHERE record_pk = ?', (pk,)
                ).fetchone()
                return _err('record_deleted' if exists else 'record_not_found', {'pk': pk})

            self._conn.execute(
                'INSERT INTO records_history(record_pk, active, bucket, class, custom_classes)'
                ' VALUES(?, 0, NULL, NULL, NULL)',
                (pk,)
            )
            self._conn.execute('COMMIT')
            return _ok({'pk': pk, 'deleted': True})
        except Exception as exc:
            try:
                self._conn.execute('ROLLBACK')
            except Exception:
                pass
            return _err('invalid_request', {'message': str(exc)})

    # ------------------------------------------------------------------
    # schema import / export
    # ------------------------------------------------------------------

    def import_schema(self, schema):
        err = self._check_writable()
        if err:
            return err
        try:
            classes = schema.get('classes', {})
            for name, defn in classes.items():
                bucket = dict(defn)
                bucket['name'] = name
                bucket = _normalize_class_bucket(bucket)
                result = self.q0({'action': 'create', 'class': 'mikobase.com/record/class', 'bucket': bucket})
                if not result['success']:
                    return result
            return _ok()
        except Exception as exc:
            return _err('invalid_request', {'message': str(exc)})

    def import_schema_file(self, path):
        with open(path) as f:
            schema = json.load(f)
        return self.import_schema(schema)

    def export_schema(self):
        rows = self._conn.execute(
            "SELECT bucket FROM current_records WHERE class = 'mikobase.com/record/class'"
        ).fetchall()
        classes = {}
        for (bucket_json,) in rows:
            bucket = json.loads(bucket_json)
            name   = bucket.pop('name', None)
            if name:
                classes[name] = bucket
        return {'classes': classes}

    def export_schema_file(self, path):
        schema = self.export_schema()
        with open(path, 'w') as f:
            json.dump(schema, f, ensure_ascii=False, indent=4)


@contextmanager
def connect(path, mode, cutoff=None):
    normalized, err = _normalize_mode(mode)
    if err:
        raise ValueError('invalid connection mode: ' + repr(mode))

    conn = sqlite3.connect(path, isolation_level=None, check_same_thread=False)
    conn.execute('PRAGMA foreign_keys = ON')

    if normalized == 'rw':
        conn.execute('PRAGMA locking_mode = EXCLUSIVE')
        # Materialize the exclusive lock immediately
        conn.execute('BEGIN EXCLUSIVE')
        conn.execute('COMMIT')
    else:
        conn.execute('PRAGMA query_only = ON')

    if not _schema_exists(conn):
        _init_schema(conn)

    engine = SqliteEngine(conn, normalized, cutoff)
    try:
        yield engine
    except Exception:
        try:
            conn.execute('ROLLBACK')
        except Exception:
            pass
        raise
    finally:
        conn.close()
