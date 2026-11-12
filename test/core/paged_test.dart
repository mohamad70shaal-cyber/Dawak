import 'dart:async';

import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/base/paged.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<int> range(int from, int count) => List<int>.generate(count, (int i) => from + i);

  test('first page, then more until a short page', () async {
    final List<int> data = range(0, 45);
    final Paged<int> p = Paged<int>(fetch: (int o, int l) async => data.skip(o).take(l).toList(), pageSize: 20);
    await p.reload();
    expect(p.items.length, 20);
    expect(p.hasMore.value, isTrue);
    expect(p.status.value, ViewStatus.ready);
    await p.loadMore();
    await p.loadMore();
    expect(p.items.length, 45);
    expect(p.hasMore.value, isFalse);
    await p.loadMore();
    expect(p.items.length, 45);
  });

  test('empty result gives the empty state', () async {
    final Paged<int> p = Paged<int>(fetch: (int o, int l) async => <int>[]);
    await p.reload();
    expect(p.status.value, ViewStatus.empty);
  });

  test('failure gives the error state and a retry works', () async {
    int calls = 0;
    final Paged<int> p = Paged<int>(fetch: (int o, int l) async {
      if (calls++ == 0) throw const AppFailure('network');
      return <int>[1];
    });
    await p.reload();
    expect(p.status.value, ViewStatus.error);
    expect(p.failure.value?.code, 'network');
    await p.reload();
    expect(p.status.value, ViewStatus.ready);
    expect(p.failure.value, isNull);
  });

  test('silent reload keeps items when it fails', () async {
    bool fail = false;
    final Paged<int> p = Paged<int>(fetch: (int o, int l) async {
      if (fail) throw const AppFailure('network');
      return <int>[1, 2];
    });
    await p.reload();
    fail = true;
    await p.reload(silent: true);
    expect(p.items, <int>[1, 2]);
    expect(p.status.value, ViewStatus.ready);
  });

  test('a newer reload wins over a slow older request', () async {
    final List<Completer<List<String>>> gates = <Completer<List<String>>>[];
    final Paged<String> p = Paged<String>(fetch: (int o, int l) {
      final Completer<List<String>> c = Completer<List<String>>();
      gates.add(c);
      return c.future;
    });
    final Future<void> first = p.reload();
    final Future<void> second = p.reload();
    gates[1].complete(<String>['new']);
    await second;
    gates[0].complete(<String>['old']);
    await first;
    expect(p.items, <String>['new']);
  });

  test('loadMore failure keeps the list and allows another try', () async {
    int call = 0;
    final Paged<int> p = Paged<int>(pageSize: 2, fetch: (int o, int l) async {
      call++;
      if (call == 2) throw const AppFailure('network');
      return <int>[o, o + 1];
    });
    await p.reload();
    await p.loadMore();
    expect(p.items.length, 2);
    expect(p.hasMore.value, isTrue);
    await p.loadMore();
    expect(p.items.length, 4);
  });
}
