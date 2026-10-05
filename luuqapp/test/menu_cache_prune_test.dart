import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:luuqapp/menu/menu_cache.dart';

void main() {
  late Directory directory;
  late MenuCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('luuq_menu_prune_');
    cache = MenuCache(rootDirectory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<List<String>> folders() async => [
    for (final entity in directory.listSync())
      if (entity is Directory)
        entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
  ]..sort();

  test('pruneOtherScopes keeps only the current scope folder', () async {
    final wheel = {
      'wheel': <String, dynamic>{'values': <String, dynamic>{}},
    };
    await cache.writePendingConfig('profile:old', wheel);
    await cache.writePendingConfig('profile:new', wheel);
    await cache.writePendingConfig('legacy:abc', wheel);
    final unrelated = Directory('${directory.path}/not-a-scope');
    await unrelated.create();
    expect(await folders(), hasLength(4));

    await cache.pruneOtherScopes('profile:new');

    final left = await folders();
    expect(left, hasLength(2));
    expect(left, contains('not-a-scope'));
    expect((await cache.readPendingConfig('profile:new')).keys, ['wheel']);
    expect(await cache.readPendingConfig('profile:old'), isEmpty);
  });
}
