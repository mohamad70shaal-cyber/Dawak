// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/base/base_controller.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/availability.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/features/pharmacist/controllers/availability_answer_controller.dart';
import 'package:dawak/features/pharmacist/controllers/availability_inbox_controller.dart';
import 'package:dawak/features/pharmacist/controllers/pharmacist_badge_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

void main() {
  late AppHarness h;

  setUp(() async {
    h = await AppHarness.create();
  });
  tearDown(() => h.dispose());

  /// `list_pharmacy_availability_requests` answers from [rows]; "only open" hides closed and expired ones like the server.
  void serveInbox(List<Map<String, dynamic>> rows) {
    h.api.rpcs['list_pharmacy_availability_requests'] = (Map<String, dynamic> p) {
      final bool onlyOpen = p['p_only_open'] == true;
      return rows.where((Map<String, dynamic> r) => !onlyOpen || r['request_status'] == 'open').toList();
    };
  }

  InboxRequest inboxItem(String id, {String status = 'open', RequestAnswer? answer, double? answerPrice, double? listedPrice}) =>
      InboxRequest.fromJson(Fx.inboxRow(id,
          status: status, answer: answer?.name, answerPrice: answerPrice, listedPrice: listedPrice, listedAvailable: listedPrice == null ? null : true));

  group('AvailabilityInboxController', () {
    setUp(() => signInMember(h));

    AvailabilityInboxController make({OpenWithArguments? open, Duration poll = Duration.zero}) =>
        AvailabilityInboxController(open: open, pollInterval: poll)..onInit();

    test('loads the open requests of the pharmacy, a page at a time', () async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1'), Fx.inboxRow('r2', answer: 'available', answerPrice: 5000)]);
      final AvailabilityInboxController c = make();
      await c.paged.reload();
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_only_open': true, 'p_limit': 30, 'p_offset': 0});
      expect(c.paged.items.map((InboxRequest r) => r.requestId), <String>['r1', 'r2']);
    });

    test('only unanswered open requests count as waiting', () async {
      serveInbox(<Map<String, dynamic>>[
        Fx.inboxRow('r1'),
        Fx.inboxRow('r2'),
        Fx.inboxRow('r3', answer: 'unavailable'),
      ]);
      final AvailabilityInboxController c = make();
      await c.paged.reload();
      expect(c.waitingCount, 2);
    });

    test('switching to "last 7 days" reloads with the other filter; choosing the same one does nothing', () async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1'), Fx.inboxRow('r2', status: 'closed')]);
      final AvailabilityInboxController c = make();
      await c.paged.reload();
      expect(c.paged.items.length, 1);

      await c.setOnlyOpen(false);
      expect(h.api.rpcLog.last.params['p_only_open'], false);
      expect(c.paged.items.length, 2);

      final int calls = h.api.rpcCount('list_pharmacy_availability_requests');
      await c.setOnlyOpen(false);
      expect(h.api.rpcCount('list_pharmacy_availability_requests'), calls);
    });

    test('an empty inbox is an empty state, not an error', () async {
      serveInbox(<Map<String, dynamic>>[]);
      final AvailabilityInboxController c = make();
      await c.paged.reload();
      expect(c.paged.status.value, ViewStatus.empty);
    });

    test('opening a request hands the tapped row to the answer screen and re-reads the list afterwards', () async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1')]);
      final List<({String route, Object? args})> opened = <({String route, Object? args})>[];
      final AvailabilityInboxController c = make(open: (String route, {Object? arguments}) async {
        opened.add((route: route, args: arguments));
        return true;
      });
      await c.paged.reload();
      final InboxRequest tapped = c.paged.items.single;

      await c.openRequest(tapped);

      expect(opened.single.route, AppRoutes.pharmacistRequest('r1'));
      expect(opened.single.args, same(tapped));
      expect(h.api.rpcCount('list_pharmacy_availability_requests'), 2);
    });

    test('a refresh keeps the shell badge in step with the list', () async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1'), Fx.inboxRow('r2')]);
      final PharmacistBadgeController badge = Get.put(PharmacistBadgeController(requestsInterval: Duration.zero));
      final AvailabilityInboxController c = make();
      await c.paged.reload();
      await c.refreshSilently();
      expect(badge.openRequests.value, 2);
    });

    test('the badge is left alone while the "last 7 days" list is shown', () async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1'), Fx.inboxRow('r2')]);
      final PharmacistBadgeController badge = Get.put(PharmacistBadgeController(requestsInterval: Duration.zero));
      badge.setOpenRequests(7);
      final AvailabilityInboxController c = make();
      await c.setOnlyOpen(false);
      await c.refreshSilently();
      expect(badge.openRequests.value, 7);
    });

    test('a failed background refresh keeps the list that is on screen', () async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1')]);
      final AvailabilityInboxController c = make();
      await c.paged.reload();
      h.api.rpcs['list_pharmacy_availability_requests'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      await c.refreshSilently();
      expect(c.paged.items.length, 1);
      expect(c.paged.status.value, ViewStatus.ready);
    });

    testWidgets('while the screen is open the list refreshes by itself; closing it stops the timer', (WidgetTester tester) async {
      serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1')]);
      final AvailabilityInboxController c = make(poll: const Duration(seconds: 20));
      c.onReady();
      await tester.pump();
      final int first = h.api.rpcCount('list_pharmacy_availability_requests');

      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      expect(h.api.rpcCount('list_pharmacy_availability_requests'), greaterThan(first));

      c.onClose();
      final int after = h.api.rpcCount('list_pharmacy_availability_requests');
      await tester.pump(const Duration(seconds: 60));
      expect(h.api.rpcCount('list_pharmacy_availability_requests'), after);
    });
  });

  group('PharmacistBadgeController (requests)', () {
    setUp(() => signInMember(h));

    test('reads the number of requests waiting for this pharmacy', () async {
      h.api.rpcs['count_pharmacy_availability_requests'] = (Map<String, dynamic> p) => 4;
      final PharmacistBadgeController badge = PharmacistBadgeController(requestsInterval: Duration.zero);
      await badge.refreshRequests();
      expect(badge.openRequests.value, 4);
      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1'});
    });

    test('a failed count keeps the last value', () async {
      h.api.rpcs['count_pharmacy_availability_requests'] = (Map<String, dynamic> p) => 4;
      final PharmacistBadgeController badge = PharmacistBadgeController(requestsInterval: Duration.zero);
      await badge.refreshRequests();
      h.api.rpcs['count_pharmacy_availability_requests'] = (Map<String, dynamic> p) => throw const AppFailure('network');
      await badge.refreshRequests();
      expect(badge.openRequests.value, 4);
    });

    test('the inbox can set the exact number; it never goes below zero', () {
      final PharmacistBadgeController badge = PharmacistBadgeController(requestsInterval: Duration.zero);
      badge.setOpenRequests(3);
      expect(badge.openRequests.value, 3);
      badge.setOpenRequests(-2);
      expect(badge.openRequests.value, 0);
    });
  });

  group('PharmacistBadgeController without a pharmacy', () {
    test('without a pharmacy nothing is asked', () async {
      h.signInAs('u2', role: 'customer');
      await h.session.restore();
      final PharmacistBadgeController badge = PharmacistBadgeController(requestsInterval: Duration.zero);
      await badge.refreshRequests();
      expect(h.api.rpcCount('count_pharmacy_availability_requests'), 0);
    });
  });

  group('AvailabilityAnswerController', () {
    /// The controller validates its form, so a (field-less) Form must be mounted for `form.currentState`.
    Future<void> mount(WidgetTester tester, GlobalKey<FormState> key) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: key, child: const SizedBox()))));

    AvailabilityAnswerController make(String id, {Object? initial, void Function()? close}) =>
        AvailabilityAnswerController(requestId: id, initial: initial, close: close ?? () {})..onInit();

    void answerSucceeds() => h.api.rpcs['answer_availability_request'] = (Map<String, dynamic> p) => <String, dynamic>{};

    group('as the owner', () {
      setUp(() => signInMember(h));

      test('the row that was tapped is shown at once, with the price from the pharmacy list', () {
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000));
        expect(c.status.value, ViewStatus.ready);
        expect(c.request.value?.requestId, 'r1');
        expect(c.price.text, '5000');
        expect(c.updatesList, isTrue);
        expect(c.canAnswer, isTrue);
      });

      test('a row that belongs to another request is ignored', () {
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('other', listedPrice: 5000));
        expect(c.request.value, isNull);
        expect(c.price.text, '');
      });

      test('an earlier "available" answer pre-fills its own price; an earlier "unavailable" falls back to the list price', () {
        final AvailabilityAnswerController a =
            make('r1', initial: inboxItem('r1', answer: RequestAnswer.available, answerPrice: 4200, listedPrice: 5000));
        expect(a.price.text, '4200');
        final AvailabilityAnswerController b =
            make('r1', initial: inboxItem('r1', answer: RequestAnswer.unavailable, listedPrice: 5000));
        expect(b.price.text, '5000');
      });

      test('a medicine that is not in the list yet leaves the price empty; decimals are kept', () {
        expect(make('r1', initial: inboxItem('r1')).price.text, '');
        expect(make('r1', initial: inboxItem('r1', listedPrice: 2500.5)).price.text, '2500.5');
      });

      test('without a seed the request is found in the inbox of the last seven days', () async {
        serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r0'), Fx.inboxRow('r1', listedPrice: 3000, listedAvailable: true)]);
        final AvailabilityAnswerController c = make('r1');
        await c.refresh();
        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_only_open': false, 'p_limit': 50, 'p_offset': 0});
        expect(c.request.value?.requestId, 'r1');
        expect(c.price.text, '3000');
        expect(c.status.value, ViewStatus.ready);
      });

      test('a request that is not in the inbox is a not_found failure', () async {
        serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r0')]);
        final AvailabilityAnswerController c = make('r1');
        await c.refresh();
        expect(c.failure.value?.code, 'not_found');
      });

      test('a silent refresh that no longer finds the request keeps what the inbox showed', () async {
        serveInbox(<Map<String, dynamic>>[]);
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000));
        await c.refresh(silent: true);
        expect(c.request.value?.requestId, 'r1');
        expect(c.failure.value, isNull);
      });

      test('a refresh never overwrites a price that is being typed', () async {
        serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1', listedPrice: 3000, listedAvailable: true)]);
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000));
        c.price.text = '7000';
        await c.refresh(silent: true);
        expect(c.price.text, '7000');
      });

      test('a closed or expired request can be read but not answered', () {
        expect(make('r1', initial: inboxItem('r1', status: 'closed')).canAnswer, isFalse);
        expect(make('r1', initial: inboxItem('r1', status: 'expired')).canAnswer, isFalse);
        final Map<String, dynamic> pastRow = Fx.inboxRow('r1')..['expires_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String();
        expect(make('r1', initial: InboxRequest.fromJson(pastRow)).canAnswer, isFalse);
      });

      testWidgets('"available" sends the price, closes the screen and refreshes the shell badge', (WidgetTester tester) async {
        answerSucceeds();
        h.api.rpcs['count_pharmacy_availability_requests'] = (Map<String, dynamic> p) => 1;
        final PharmacistBadgeController badge = Get.put(PharmacistBadgeController(requestsInterval: Duration.zero));
        int closed = 0;
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000), close: () => closed++);
        await mount(tester, c.form);
        c.price.text = '5500';

        expect(await c.answerAvailable(), isTrue);

        final ({String fn, Map<String, dynamic> params}) call = h.api.rpcLog.firstWhere((e) => e.fn == 'answer_availability_request');
        expect(call.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_request_id': 'r1', 'p_available': true, 'p_price': 5500});
        expect(closed, 1);
        await tester.pump();
        expect(badge.openRequests.value, 1);
      });

      testWidgets('"available" without a usable price sends nothing', (WidgetTester tester) async {
        answerSucceeds();
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1'));
        await mount(tester, c.form);
        for (final String text in <String>['', '0', 'abc']) {
          c.price.text = text;
          expect(await c.answerAvailable(), isFalse, reason: 'price "$text"');
        }
        expect(h.api.rpcCount('answer_availability_request'), 0);
      });

      testWidgets('"unavailable" sends no price', (WidgetTester tester) async {
        answerSucceeds();
        int closed = 0;
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000), close: () => closed++);
        await mount(tester, c.form);

        expect(await c.answerUnavailable(), isTrue);

        expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_request_id': 'r1', 'p_available': false, 'p_price': null});
        expect(closed, 1);
      });

      testWidgets('an answer can be changed while the request is open', (WidgetTester tester) async {
        answerSucceeds();
        final AvailabilityAnswerController c =
            make('r1', initial: inboxItem('r1', answer: RequestAnswer.unavailable, listedPrice: 5000));
        await mount(tester, c.form);
        expect(c.canAnswer, isTrue);
        expect(await c.answerAvailable(), isTrue);
        expect(h.api.rpcLog.single.params['p_available'], true);
      });

      testWidgets('nothing is sent for a request that is already closed', (WidgetTester tester) async {
        answerSucceeds();
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', status: 'closed', listedPrice: 5000));
        await mount(tester, c.form);
        expect(await c.answerAvailable(), isFalse);
        expect(await c.answerUnavailable(), isFalse);
        expect(h.api.rpcCount('answer_availability_request'), 0);
      });

      testWidgets('request_closed keeps the screen open and re-reads the request, which is then no longer answerable', (WidgetTester tester) async {
        h.api.rpcs['answer_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('request_closed');
        serveInbox(<Map<String, dynamic>>[Fx.inboxRow('r1', status: 'closed')]);
        int closed = 0;
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000), close: () => closed++);
        await mount(tester, c.form);

        expect(await c.answerUnavailable(), isFalse);
        await tester.pump();

        expect(closed, 0);
        expect(c.failure.value?.code, 'request_closed');
        expect(c.request.value?.status, RequestStatus.closed);
        expect(c.canAnswer, isFalse);
      });

      testWidgets('another failure keeps the screen open and the typed price', (WidgetTester tester) async {
        h.api.rpcs['answer_availability_request'] = (Map<String, dynamic> p) => throw const AppFailure('network');
        int closed = 0;
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000), close: () => closed++);
        await mount(tester, c.form);
        c.price.text = '6100';

        expect(await c.answerAvailable(), isFalse);

        expect(closed, 0);
        expect(c.price.text, '6100');
        expect(c.failure.value?.code, 'network');
      });
    });

    group('as a cashier', () {
      setUp(() => signInMember(h, memberRole: 'cashier'));

      test('a cashier can answer, but the answer does not update the list', () {
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000));
        expect(c.updatesList, isFalse);
        expect(c.canAnswer, isTrue);
      });

      testWidgets('a cashier\'s answer is sent like any other (the server decides what it changes)', (WidgetTester tester) async {
        answerSucceeds();
        final AvailabilityAnswerController c = make('r1', initial: inboxItem('r1', listedPrice: 5000));
        await mount(tester, c.form);
        expect(await c.answerAvailable(), isTrue);
        expect(h.api.rpcLog.single.params['p_price'], 5000);
      });
    });
  });
}
