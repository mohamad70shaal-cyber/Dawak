// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/availability.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/features/customer/controllers/home_controller.dart';
import 'package:dawak/features/customer/controllers/my_requests_controller.dart';
import 'package:dawak/features/customer/services/customer_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';
import 'customer_fixtures.dart';

void main() {
  late AppHarness h;
  setUp(() async {
    h = await AppHarness.create();
    h.signInAs('c1');
    await h.session.restore();
  });
  tearDown(() => h.dispose());

  List<Map<String, dynamic>> serveHistory(List<Map<String, dynamic>> rows) {
    h.api.rpcs['list_my_availability_requests'] = paged(rows);
    return rows;
  }

  group('MyRequestsController', () {
    test('lists the requests as the server returns them (newest first)', () async {
      serveHistory(<Map<String, dynamic>>[
        summaryRow('r3', offers: 2),
        summaryRow('r2', status: 'expired'),
        summaryRow('r1', status: 'closed'),
      ]);
      final MyRequestsController c = MyRequestsController()..onInit();
      await c.reload();
      expect(c.paged.items.map((AvailabilityRequestSummary s) => s.id), <String>['r3', 'r2', 'r1']);
      expect(c.paged.status.value, ViewStatus.ready);
      expect(c.paged.items.first.offersCount, 2);
    });

    test('no requests gives the empty state', () async {
      serveHistory(<Map<String, dynamic>>[]);
      final MyRequestsController c = MyRequestsController()..onInit();
      await c.reload();
      expect(c.paged.status.value, ViewStatus.empty);
    });

    test('a failure gives the error state with its code', () async {
      h.api.rpcs['list_my_availability_requests'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final MyRequestsController c = MyRequestsController()..onInit();
      await c.reload();
      expect(c.paged.status.value, ViewStatus.error);
      expect(c.paged.failure.value?.code, 'network');
    });

    test('the list is paged: the second page starts where the first one ended', () async {
      serveHistory(<Map<String, dynamic>>[for (int i = 1; i <= 25; i++) summaryRow('r$i')]);
      final MyRequestsController c = MyRequestsController()..onInit();
      await c.reload();
      expect(c.paged.items.length, 20);
      expect(c.paged.hasMore.value, isTrue);
      await c.paged.loadMore();
      expect(c.paged.items.length, 25);
      expect(c.paged.hasMore.value, isFalse);
      expect(h.api.rpcLog.map((e) => e.params['p_offset']).toList(), <Object?>[0, 20]);
    });

    test('refreshList shows what changed on the server without emptying the screen first', () async {
      final List<Map<String, dynamic>> rows = serveHistory(<Map<String, dynamic>>[summaryRow('r1')]);
      final MyRequestsController c = MyRequestsController()..onInit();
      await c.reload();
      rows[0] = summaryRow('r1', status: 'closed');
      final Future<void> refreshing = c.refreshList();
      expect(c.paged.status.value, ViewStatus.ready, reason: 'the old list stays on screen meanwhile');
      await refreshing;
      expect(c.paged.items.single.status, RequestStatus.closed);
    });
  });

  group('HomeController: the open requests card', () {
    setUp(() => h.api.rpcs['list_my_availability_requests'] = paged(<Map<String, dynamic>>[]));

    test('shows only the requests that are still open among the latest few', () async {
      serveHistory(<Map<String, dynamic>>[
        summaryRow('r4', offers: 1),
        summaryRow('r3', status: 'closed'),
        summaryRow('r2', status: 'expired'),
        summaryRow('r1'),
      ]);
      final HomeController c = HomeController()..onInit();
      await c.reload();
      expect(c.status.value, ViewStatus.ready);
      expect(c.openRequests.map((AvailabilityRequestSummary s) => s.id), <String>['r4', 'r1']);
      expect(h.api.rpcLog.last.params['p_limit'], 5);
    });

    test('no open request: the card has nothing to show', () async {
      serveHistory(<Map<String, dynamic>>[summaryRow('r1', status: 'closed')]);
      final HomeController c = HomeController()..onInit();
      await c.reload();
      expect(c.openRequests, isEmpty);
    });

    test('the card is an extra: if reading the requests fails the home screen still loads', () async {
      h.api.rpcs['list_my_availability_requests'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      final HomeController c = HomeController()..onInit();
      await c.reload();
      expect(c.status.value, ViewStatus.ready);
      expect(c.openRequests, isEmpty);
    });

    test('a silent refresh replaces the list', () async {
      final List<Map<String, dynamic>> rows = serveHistory(<Map<String, dynamic>>[summaryRow('r1')]);
      final HomeController c = HomeController()..onInit();
      await c.reload();
      expect(c.openRequests.length, 1);
      rows[0] = summaryRow('r1', status: 'closed');
      await c.refreshSilently();
      expect(c.openRequests, isEmpty);
    });
  });

  group('CustomerRefresh.requestsChanged', () {
    test('re-reads the history and the home card when they exist', () async {
      serveHistory(<Map<String, dynamic>>[summaryRow('r1')]);
      final MyRequestsController list = Get.put<MyRequestsController>(MyRequestsController());
      final HomeController home = Get.put<HomeController>(HomeController());
      await list.reload();
      await home.reload();
      final int before = h.api.rpcCount('list_my_availability_requests');
      CustomerRefresh.requestsChanged();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.api.rpcCount('list_my_availability_requests') - before, greaterThanOrEqualTo(2), reason: 'one read for the history, one for the home card');
    });

    test('does nothing (and does not fail) when no list is open', () {
      expect(CustomerRefresh.requestsChanged, returnsNormally);
    });
  });
}
