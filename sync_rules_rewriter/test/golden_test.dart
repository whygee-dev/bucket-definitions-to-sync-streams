import 'package:sync_rules_rewriter/sync_rules_rewriter.dart';
import 'package:test/test.dart';

void main() {
  test('simple', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  user_lists:
    parameters: SELECT request.user_id() as user_id
    data:
      - SELECT * FROM lists WHERE lists.owner_id = bucket.user_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM lists WHERE lists.owner_id = auth.user_id()
''',
    );
  });

  test('existing config', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT * FROM users

config:
  # preserved comment
  edition: 1
'''),
      '''
config:
  # preserved comment
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM users
''',
    );
  });

  test('existing stream', () {
    expect(
      syncRulesToSyncStreams('''
config:
  edition: 2
bucket_definitions:
  a:
    data: SELECT * FROM a
streams:
  b:
    query: SELECT * FROM b
'''),
      '''
config:
  edition: 3
streams:
  b:
    query: SELECT * FROM b
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM a
''',
    );
  });

  test('priorities from yaml', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    priority: 2
    data: SELECT * FROM a
  b:
    data: SELECT * FROM b
'''),
      '''
config:
  edition: 3
streams:
  # These Sync Streams have been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams_prio_2:
    priority: 2
    auto_subscribe: true
    queries:
      - SELECT * FROM a
  migrated_to_streams_prio_3:
    auto_subscribe: true
    queries:
      - SELECT * FROM b
''',
    );
  });

  test('priority from sql', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    parameters: SELECT 1 AS _priority, request.user_id() as user;
    data: SELECT * FROM a WHERE owner = bucket.user
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    priority: 1
    auto_subscribe: true
    queries:
      - SELECT * FROM a WHERE owner = auth.user_id()
''',
    );
  });

  test('multiple parameter queries', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  user_lists:
    parameters:
      - SELECT id as list_id FROM lists WHERE owner_id = request.user_id()
      - SELECT list_id FROM user_lists WHERE user_lists.user_id = request.user_id()
    data:
      - SELECT * FROM lists WHERE lists.id = bucket.list_id
      - SELECT * FROM todos WHERE todos.list_id = bucket.list_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    with:
      user_lists_param0: SELECT id AS list_id FROM lists WHERE owner_id = auth.user_id()
      user_lists_param1: SELECT list_id FROM user_lists WHERE user_lists.user_id = auth.user_id()
    queries:
      - "SELECT lists.* FROM lists,user_lists_param0 AS bucket0,user_lists_param1 AS bucket1 WHERE lists.id = bucket0.list_id OR lists.id = bucket1.list_id"
      - "SELECT todos.* FROM todos,user_lists_param0 AS bucket0,user_lists_param1 AS bucket1 WHERE todos.list_id = bucket0.list_id OR todos.list_id = bucket1.list_id"
''',
    );
  });

  test('yaml string syntax', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  owned_lists:
    parameters: |
        SELECT id as list_id FROM lists WHERE
           owner_id = request.user_id()
    data:
      - SELECT * FROM lists WHERE lists.id = bucket.list_id
      - SELECT * FROM todos WHERE todos.list_id = bucket.list_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    with:
      owned_lists_param: SELECT id AS list_id FROM lists WHERE owner_id = auth.user_id()
    queries:
      - "SELECT lists.* FROM lists,owned_lists_param AS bucket WHERE lists.id = bucket.list_id"
      - "SELECT todos.* FROM todos,owned_lists_param AS bucket WHERE todos.list_id = bucket.list_id"
''',
    );
  });

  test('merges multiple bucket definitions into a single stream', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  lists:
    data:
      - SELECT * FROM lists
  todos:
    data:
      - SELECT * FROM todos
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      # Translated from "lists" bucket definition.
      - SELECT * FROM lists
      # Translated from "todos" bucket definition.
      - SELECT * FROM todos
''',
    );
  });

  test('unquoted camelCase identifiers are not auto-quoted', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  user_lists:
    parameters: SELECT request.user_id() as userId
    data:
      - SELECT * FROM userLists WHERE userLists.ownerId = bucket.userId
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM userLists WHERE userLists.ownerId = auth.user_id()
''',
    );
  });

  test('explicitly quoted camelCase identifiers are preserved', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  user_lists:
    parameters: SELECT request.user_id() as userId
    data:
      - SELECT * FROM "userLists" WHERE "userLists"."ownerId" = bucket.userId
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM "userLists" WHERE "userLists"."ownerId" = auth.user_id()
''',
    );
  });

  test('SQL keywords used as identifiers are quoted', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "order", "group" FROM items
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - "SELECT \\"order\\", \\"group\\" FROM items"
''',
    );
  });

  test('identifiers with special characters are quoted', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT * FROM "user-lists"
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT * FROM "user-lists"
''',
    );
  });

  test('mixed quoting: only explicitly quoted parts are preserved', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "userLists".ownerId FROM "userLists"
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "userLists".ownerId FROM "userLists"
''',
    );
  });

  test('quoted entity with keyword column name preserves quotes', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "userLists"."order" FROM "userLists"
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "userLists"."order" FROM "userLists"
''',
    );
  });

  test('schema-qualified references preserve explicit quotes', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "other"."userLists"."ownerId" FROM "other"."userLists"
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "other"."userLists"."ownerId" FROM "other"."userLists"
''',
    );
  });

  test('quoted schema in table reference is preserved when alias is present', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "MySchema"."MyTable".id FROM "MySchema"."MyTable" t
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "MySchema"."MyTable".id FROM "MySchema"."MyTable" AS t
''',
    );
  });

  test('explicitly quoted table aliases are preserved', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "BarBaz".id FROM items AS "BarBaz"
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "BarBaz".id FROM items AS "BarBaz"
''',
    );
  });

  test('quoted select aliases are preserved', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT id AS "CreatedAt" FROM lists
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT id AS "CreatedAt" FROM lists
''',
    );
  });

  test('quoted unqualified references are preserved', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "ownerId" FROM lists WHERE "ownerId" = 1
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "ownerId" FROM lists WHERE "ownerId" = 1
''',
    );
  });

  test('quoted table qualifier on star column is preserved', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    data:
      - SELECT "BarBaz".* FROM items AS "BarBaz"
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    queries:
      - SELECT "BarBaz".* FROM items AS "BarBaz"
''',
    );
  });

  test(
      'quoted identifiers remain quoted when default table qualification is injected',
      () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    parameters:
      - SELECT id AS list_id FROM lists
    data:
      - SELECT "OwnerId" FROM "Items" AS "BarBaz" WHERE "OwnerId" = bucket.list_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    with:
      a_param: SELECT id AS list_id FROM lists
    queries:
      - "SELECT \\"BarBaz\\".\\"OwnerId\\" FROM \\"Items\\" AS \\"BarBaz\\",a_param AS bucket WHERE \\"BarBaz\\".\\"OwnerId\\" = bucket.list_id"
''',
    );
  });

  test('quoted alias remains quoted when * qualifier is injected', () {
    expect(
      syncRulesToSyncStreams('''
bucket_definitions:
  a:
    parameters:
      - SELECT id AS list_id FROM lists
    data:
      - SELECT * FROM items AS "BarBaz" WHERE id = bucket.list_id
'''),
      '''
config:
  edition: 3
streams:
  # This Sync Stream has been translated from bucket definitions. There may be more efficient ways to express these queries.
  # You can add additional queries to this list if you need them.
  # For details, see the documentation: https://docs.powersync.com/sync/streams/overview
  migrated_to_streams:
    auto_subscribe: true
    with:
      a_param: SELECT id AS list_id FROM lists
    queries:
      - "SELECT \\"BarBaz\\".* FROM items AS \\"BarBaz\\",a_param AS bucket WHERE \\"BarBaz\\".id = bucket.list_id"
''',
    );
  });
}
