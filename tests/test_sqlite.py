import os
import tempfile
import pytest
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))

import mikobase.engine.sqlite as mb


@pytest.fixture
def db(tmp_path):
    path = str(tmp_path / 'test.db')
    with mb.connect(path, 'rw') as engine:
        yield engine


# ------------------------------------------------------------------
# connection
# ------------------------------------------------------------------

# rw mode connects and can execute queries
def test_connect_rw(tmp_path):
    result = False
    with mb.connect(str(tmp_path / 'test.db'), 'rw') as engine:
        result = engine.q0({'action': 'select'}).success
    assert result

# r mode connects and can execute queries
def test_connect_r(tmp_path):
    path = str(tmp_path / 'test.db')
    with mb.connect(path, 'rw'):
        pass
    result = False
    with mb.connect(path, 'r') as engine:
        result = engine.q0({'action': 'select'}).success
    assert result

# wr is accepted and normalized to rw
def test_connect_wr_normalized(tmp_path):
    result = False
    with mb.connect(str(tmp_path / 'test.db'), 'wr') as engine:
        result = engine.q0({'action': 'select'}).success
    assert result

# mode string is case-insensitive
def test_connect_case_insensitive(tmp_path):
    result = False
    with mb.connect(str(tmp_path / 'test.db'), 'RW') as engine:
        result = engine.q0({'action': 'select'}).success
    assert result

# unrecognized mode raises ValueError
def test_connect_invalid_mode(tmp_path):
    with pytest.raises(ValueError):
        with mb.connect(str(tmp_path / 'test.db'), 'x'):
            pass

# surrounding whitespace in the mode string is rejected
def test_connect_whitespace_rejected(tmp_path):
    with pytest.raises(ValueError):
        with mb.connect(str(tmp_path / 'test.db'), ' rw'):
            pass

# connecting to a new database creates all required tables
def test_connect_initializes_schema(tmp_path):
    import sqlite3
    path = str(tmp_path / 'test.db')
    with mb.connect(path, 'rw'):
        pass
    conn = sqlite3.connect(path)
    tables = {r[0] for r in conn.execute("select name from sqlite_master where type='table'").fetchall()}
    conn.close()
    assert 'records'         in tables
    assert 'records_history' in tables
    assert 'files'           in tables
    assert 'file_chunks'     in tables

# reconnecting to an existing database does not reset its data
def test_connect_idempotent(tmp_path):
    path = str(tmp_path / 'test.db')
    with mb.connect(path, 'rw') as engine:
        engine.q0({'action': 'create', 'bucket': {'x': 1}})
    with mb.connect(path, 'rw') as engine:
        result = engine.q0({'action': 'select'})
        records = list(result)
        assert len(records) == 1


# ------------------------------------------------------------------
# create
# ------------------------------------------------------------------

# create returns success and a pk
def test_create_basic(db):
    result = db.q0({'action': 'create', 'class': 'foo.com/thing', 'bucket': {'name': 'Alpha'}})
    assert result['success']
    assert 'pk' in result['results']

# omitting class defaults to mikobase.com/record
def test_create_default_class(db):
    result = db.q0({'action': 'create', 'bucket': {'x': 1}})
    assert result['success']
    pk = result['results']['pk']
    row = list(db.record_by_pk(pk))
    assert row[0]['class'] == 'mikobase.com/record'

# create without a bucket is an error
def test_create_missing_bucket(db):
    result = db.q0({'action': 'create', 'class': 'foo.com/thing'})
    assert not result['success']
    assert result['errors'][0]['id'] == 'invalid_request'

# bucket must be a JSON object, not a scalar or array
def test_create_bucket_not_object(db):
    result = db.q0({'action': 'create', 'bucket': 'not a dict'})
    assert not result['success']

# create on an r-mode connection is rejected
def test_create_read_only(tmp_path):
    path = str(tmp_path / 'test.db')
    with mb.connect(path, 'rw'):
        pass
    with mb.connect(path, 'r') as engine:
        result = engine.q0({'action': 'create', 'bucket': {'x': 1}})
        assert not result['success']
        assert result['errors'][0]['id'] == 'read-only-connection'


# ------------------------------------------------------------------
# select
# ------------------------------------------------------------------

# unfiltered select returns all active records and correct count
def test_select_all(db):
    db.q0({'action': 'create', 'class': 'foo.com/a', 'bucket': {'n': 1}})
    db.q0({'action': 'create', 'class': 'foo.com/a', 'bucket': {'n': 2}})
    result = db.q0({'action': 'select'})
    assert result.success
    records = list(result)
    assert len(records) == 2
    assert result.count == 2

# select by pk returns the matching record with correct fields
def test_select_by_pk(db):
    r = db.q0({'action': 'create', 'class': 'foo.com/a', 'bucket': {'val': 42}})
    pk = r['results']['pk']
    result = db.q0({'action': 'select', 'pk': pk})
    records = list(result)
    assert len(records) == 1
    assert records[0]['pk'] == pk
    assert records[0]['bucket']['val'] == 42

# select by unknown pk returns success with empty results
def test_select_by_pk_not_found(db):
    result = db.q0({'action': 'select', 'pk': 'no-such-pk'})
    assert result.success
    assert list(result) == []

# select by class returns only records of that class
def test_select_by_class(db):
    db.q0({'action': 'create', 'class': 'foo.com/cat', 'bucket': {'name': 'Felix'}})
    db.q0({'action': 'create', 'class': 'foo.com/dog', 'bucket': {'name': 'Rex'}})
    result = db.q0({'action': 'select', 'class': 'foo.com/cat'})
    records = list(result)
    assert len(records) == 1
    assert records[0]['bucket']['name'] == 'Felix'

# class may be an array to select records matching any of the given classes
def test_select_classes_array(db):
    db.q0({'action': 'create', 'class': 'foo.com/cat',  'bucket': {'name': 'Felix'}})
    db.q0({'action': 'create', 'class': 'foo.com/dog',  'bucket': {'name': 'Rex'}})
    db.q0({'action': 'create', 'class': 'foo.com/bird', 'bucket': {'name': 'Tweety'}})
    result = db.q0({'action': 'select', 'class': ['foo.com/cat', 'foo.com/dog']})
    assert len(list(result)) == 2

# using both class and classes together produces a redundant_fields warning
def test_select_class_and_classes_warning(db):
    result = db.q0({'action': 'select', 'class': 'foo.com/a', 'classes': ['foo.com/b']})
    assert result.success
    assert any(w['id'] == 'redundant_fields' for w in result.warnings)

# selecting by a parent class includes records of subclasses
def test_select_class_inheritance(db):
    db.q0({'action': 'create', 'class': 'mikobase.com/record/class',
           'bucket': {'name': 'zoo.com/animal'}})
    db.q0({'action': 'create', 'class': 'mikobase.com/record/class',
           'bucket': {'name': 'zoo.com/dog', 'inherits': 'zoo.com/animal'}})
    db.q0({'action': 'create', 'class': 'zoo.com/animal', 'bucket': {'species': 'cat'}})
    db.q0({'action': 'create', 'class': 'zoo.com/dog',    'bucket': {'species': 'dog'}})
    db.q0({'action': 'create', 'class': 'foo.com/other',  'bucket': {'species': 'fish'}})
    result = db.q0({'action': 'select', 'class': 'zoo.com/animal'})
    records = list(result)
    assert len(records) == 2
    species = {r['bucket']['species'] for r in records}
    assert species == {'cat', 'dog'}

# limit caps the number of records returned
def test_select_limit_offset(db):
    for i in range(5):
        db.q0({'action': 'create', 'class': 'foo.com/n', 'bucket': {'i': i}})
    result = db.q0({'action': 'select', 'class': 'foo.com/n', 'limit': 2})
    assert len(list(result)) == 2

# each record has exactly the expected top-level fields
def test_select_record_shape(db):
    r = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'k': 'v'}})
    pk = r['results']['pk']
    record = list(db.record_by_pk(pk))[0]
    assert set(record.keys()) == {'pk', 'class', 'updated_at', 'bucket', 'custom_classes'}
    assert record['class'] == 'foo.com/x'
    assert record['bucket'] == {'k': 'v'}


# ------------------------------------------------------------------
# update
# ------------------------------------------------------------------

# update replaces the bucket
def test_update_bucket(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'v': 1}})
    pk = r['results']['pk']
    db.q0({'action': 'update', 'pk': pk, 'bucket': {'v': 2}})
    record = list(db.record_by_pk(pk))[0]
    assert record['bucket']['v'] == 2

# updating only the class preserves the existing bucket
def test_update_class(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'v': 1}})
    pk = r['results']['pk']
    db.q0({'action': 'update', 'pk': pk, 'class': 'foo.com/y'})
    record = list(db.record_by_pk(pk))[0]
    assert record['class'] == 'foo.com/y'
    assert record['bucket']['v'] == 1

# updating a nonexistent pk returns record_not_found
def test_update_not_found(db):
    result = db.q0({'action': 'update', 'pk': 'no-such', 'bucket': {'x': 1}})
    assert not result['success']
    assert result['errors'][0]['id'] == 'record_not_found'

# update without pk is an error
def test_update_missing_pk(db):
    result = db.q0({'action': 'update', 'bucket': {'x': 1}})
    assert not result['success']

# update with neither bucket nor class is an error
def test_update_nothing_to_change(db):
    result = db.q0({'action': 'update', 'pk': 'x'})
    assert not result['success']


# ------------------------------------------------------------------
# delete
# ------------------------------------------------------------------

# delete removes a record from active results
def test_delete(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'v': 1}})
    pk = r['results']['pk']
    result = db.q0({'action': 'delete', 'pk': pk})
    assert result['success']
    assert result['results']['deleted'] is True
    assert list(db.record_by_pk(pk)) == []

# deleting a nonexistent pk returns record_not_found
def test_delete_not_found(db):
    result = db.q0({'action': 'delete', 'pk': 'no-such'})
    assert not result['success']
    assert result['errors'][0]['id'] == 'record_not_found'

# deleting an already-deleted record returns record_deleted
def test_delete_already_deleted(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {}})
    pk = r['results']['pk']
    db.q0({'action': 'delete', 'pk': pk})
    result = db.q0({'action': 'delete', 'pk': pk})
    assert not result['success']
    assert result['errors'][0]['id'] == 'record_deleted'

# if_exists: true on an already-deleted record returns success with deleted: false
def test_delete_if_exists_idempotent(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {}})
    pk = r['results']['pk']
    db.q0({'action': 'delete', 'pk': pk})
    result = db.q0({'action': 'delete', 'pk': pk, 'if_exists': True})
    assert result['success']
    assert result['results']['deleted'] is False

# if_exists: true on a nonexistent pk returns success with deleted: false
def test_delete_if_exists_nonexistent(db):
    result = db.q0({'action': 'delete', 'pk': 'no-such', 'if_exists': True})
    assert result['success']
    assert result['results']['deleted'] is False

# deleted records do not appear in select results
def test_deleted_excluded_from_select(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'v': 1}})
    pk = r['results']['pk']
    db.q0({'action': 'delete', 'pk': pk})
    result = db.q0({'action': 'select', 'class': 'foo.com/x'})
    assert list(result) == []


# ------------------------------------------------------------------
# schema import / export
# ------------------------------------------------------------------

# imported class definitions are retrievable via export_schema
def test_import_and_export_schema(db):
    schema = {
        'classes': {
            'test.com/person': {
                'fields': {
                    'name': {'class': 'string', 'required': True}
                }
            }
        }
    }
    result = db.import_schema(schema)
    assert result['success']
    exported = db.export_schema()
    assert 'test.com/person' in exported['classes']

# importing a class whose name already exists is an error
def test_import_schema_duplicate_name(db):
    schema = {'classes': {'test.com/thing': {'fields': {}}}}
    db.import_schema(schema)
    result = db.import_schema(schema)
    assert not result['success']


# ------------------------------------------------------------------
# convenience methods
# ------------------------------------------------------------------

# record_by_pk returns the record matching the given pk
def test_record_by_pk(db):
    r  = db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'z': 99}})
    pk = r['results']['pk']
    result = db.record_by_pk(pk)
    records = list(result)
    assert len(records) == 1
    assert records[0]['bucket']['z'] == 99

# by_class returns all active records of the given class
def test_by_class(db):
    db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'a': 1}})
    db.q0({'action': 'create', 'class': 'foo.com/x', 'bucket': {'a': 2}})
    db.q0({'action': 'create', 'class': 'foo.com/y', 'bucket': {'a': 3}})
    records = list(db.by_class('foo.com/x'))
    assert len(records) == 2
