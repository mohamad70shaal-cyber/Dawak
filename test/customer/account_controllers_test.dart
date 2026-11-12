// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/core/services/locale_service.dart';
import 'package:dawak/data/models/platform.dart';
import 'package:dawak/features/customer/controllers/customer_profile_controller.dart';
import 'package:dawak/features/customer/controllers/notification_badge_controller.dart';
import 'package:dawak/features/customer/controllers/notifications_controller.dart';
import 'package:dawak/features/customer/controllers/support_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';

Future<void> mountForm(WidgetTester tester, GlobalKey<FormState> key, {Widget child = const SizedBox()}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: key, child: child))));
}

void main() {
  late AppHarness h;
  setUp(() async {
    h = await AppHarness.create();
    h.signInAs('c1');
    await h.session.restore();
  });
  tearDown(() => h.dispose());

  group('CustomerProfileController', () {
    testWidgets('fills the form from the profile and saves the changes', (WidgetTester tester) async {
      int saved = 0;
      final CustomerProfileController c = CustomerProfileController(onSaved: () => saved++)..onInit();
      await mountForm(tester, c.form);
      expect(c.name.text, 'Test c1');
      c.name.text = '  أحمد  ';
      c.phone.text = '0911 222 333';
      expect(await c.save(), isTrue);
      expect(saved, 1);
      final Map<String, dynamic> row = h.api.tables['profiles']!.single;
      expect(row['display_name'], 'أحمد');
      expect(row['phone'], isNotNull);
      expect(h.session.profile?.displayName, 'أحمد', reason: 'the session profile is refreshed');
    });

    testWidgets('an empty phone clears it', (WidgetTester tester) async {
      h.api.tables['profiles']!.single['phone'] = '+963911111111';
      final CustomerProfileController c = CustomerProfileController(onSaved: () {})..onInit();
      await mountForm(tester, c.form);
      c.phone.text = '';
      await c.save();
      expect(h.api.tables['profiles']!.single['phone'], isNull);
    });

    testWidgets('a rejected save keeps the form and does not close the page', (WidgetTester tester) async {
      int saved = 0;
      final CustomerProfileController c = CustomerProfileController(onSaved: () => saved++)..onInit();
      await mountForm(tester, c.form);
      c.name.text = 'اسم جديد';
      h.api.failNext('update:profiles', const AppFailure('network'));
      expect(await c.save(), isFalse);
      expect(saved, 0);
      expect(c.name.text, 'اسم جديد');
      expect(c.failure.value?.code, 'network');
    });

    test('fillForm discards edits', () {
      final CustomerProfileController c = CustomerProfileController(onSaved: () {})..onInit();
      c.name.text = 'شيء آخر';
      c.fillForm();
      expect(c.name.text, 'Test c1');
    });

    testWidgets('toggling the language switches the app and stores it on the profile', (WidgetTester tester) async {
      final CustomerProfileController c = CustomerProfileController(onSaved: () {})..onInit();
      final bool before = Get.find<LocaleService>().isArabic;
      await c.toggleLanguage();
      expect(Get.find<LocaleService>().isArabic, !before);
      expect(h.api.tables['profiles']!.single['locale'], Get.find<LocaleService>().locale.value.languageCode);
    });

    testWidgets('a failing profile copy of the language does not undo the device setting', (WidgetTester tester) async {
      final CustomerProfileController c = CustomerProfileController(onSaved: () {})..onInit();
      final bool before = Get.find<LocaleService>().isArabic;
      h.api.failNext('update:profiles', const AppFailure('network'));
      await c.toggleLanguage();
      expect(Get.find<LocaleService>().isArabic, !before);
    });

    test('signing out ends the session and goes to the welcome screen', () async {
      final CustomerProfileController c = CustomerProfileController(onSaved: () {})..onInit();
      await c.signOut();
      expect(h.session.signedIn, isFalse);
      expect(h.navigated.last, AppRoutes.welcome);
    });
  });

  group('SupportController', () {
    testWidgets('sends the report with its category, target type and trimmed text', (WidgetTester tester) async {
      final SupportController c = SupportController()..onInit();
      await mountForm(tester, c.form);
      c.selectCategory(SupportController.categories[2]);
      c.description.text = '  الصيدلية لم ترد على طلبي  ';
      expect(await c.send(), isTrue);
      final Map<String, dynamic> row = h.api.tables['user_reports']!.single;
      expect(row['target_type'], 'order');
      expect(row['category'], 'order_problem');
      expect(row['description'], 'الصيدلية لم ترد على طلبي');
      expect(c.sent.value, isTrue);
      expect(c.description.text, isEmpty);
      c.writeAnother();
      expect(c.sent.value, isFalse);
    });

    testWidgets('a failed send keeps the text and does not claim success', (WidgetTester tester) async {
      final SupportController c = SupportController()..onInit();
      await mountForm(tester, c.form);
      c.description.text = 'مشكلة في التطبيق عند الدفع';
      h.api.failNext('insert:user_reports', const AppFailure('rate_limited'));
      expect(await c.send(), isFalse);
      expect(c.sent.value, isFalse);
      expect(c.description.text, 'مشكلة في التطبيق عند الدفع');
      expect(c.failure.value?.code, 'rate_limited');
    });

    testWidgets('an invalid form (validator) stops before the server', (WidgetTester tester) async {
      final SupportController c = SupportController()..onInit();
      await mountForm(
        tester,
        c.form,
        child: TextFormField(controller: c.description, validator: (String? v) => (v ?? '').trim().length < SupportController.descriptionMin ? 'short' : null),
      );
      c.description.text = 'abc';
      expect(await c.send(), isFalse);
      expect(h.api.calls.where((String l) => l == 'insert:user_reports'), isEmpty);
    });

    test('every category is a valid report target and has a stable code', () {
      const Set<String> targets = <String>{'pharmacy', 'medicine', 'order', 'app', 'other'};
      for (final ReportCategory r in SupportController.categories) {
        expect(targets, contains(r.targetType));
        expect(r.code.length, inInclusiveRange(2, 60));
        expect(r.labelKey, 'c_report_${r.code}');
      }
    });
  });

  group('NotificationsController', () {
    void seed() {
      h.api.tables['notifications'] = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'n1',
          'kind': 'order_accepted',
          'entity_type': 'order',
          'entity_id': 'o1',
          'params': <String, dynamic>{'ref': 'DWK-ABCDE12345'},
          'read_at': null,
          'created_at': '2026-10-10T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'n2',
          'kind': 'something_new',
          'entity_type': null,
          'entity_id': null,
          'params': <String, dynamic>{},
          'read_at': '2026-10-09T10:00:00Z',
          'created_at': '2026-10-09T09:00:00Z',
        },
      ];
    }

    test('lists notifications newest first and texts come from the translation table', () async {
      seed();
      final NotificationsController c = NotificationsController(open: (String r) {})..onInit();
      await c.paged.reload();
      expect(c.paged.items.map((AppNotification n) => n.id), <String>['n1', 'n2']);
      expect(c.textFor(c.paged.items.first), contains('DWK-ABCDE12345'));
      expect(c.textFor(c.paged.items.last), 'notif_generic'.tr, reason: 'unknown kinds fall back to the generic text');
    });

    test('opening an unread order notification marks it read, lowers the badge and opens the order', () async {
      seed();
      final NotificationBadgeController badge = Get.put<NotificationBadgeController>(NotificationBadgeController());
      await badge.refreshCount();
      expect(badge.unread.value, 1);
      final List<String> opened = <String>[];
      final NotificationsController c = NotificationsController(open: opened.add)..onInit();
      await c.paged.reload();
      await c.openNotification(c.paged.items.first);
      expect(h.api.tables['notifications']!.first['read_at'], isNotNull);
      expect(c.paged.items.first.isUnread, isFalse);
      expect(badge.unread.value, 0);
      expect(opened, <String>[AppRoutes.customerOrder('o1')]);
    });

    test('a notification that is not about an order only marks as read', () async {
      seed();
      final List<String> opened = <String>[];
      final NotificationsController c = NotificationsController(open: opened.add)..onInit();
      await c.paged.reload();
      await c.openNotification(c.paged.items.last);
      expect(opened, isEmpty);
    });

    test('when marking as read fails the notification stays unread but the order still opens', () async {
      seed();
      final List<String> opened = <String>[];
      final NotificationsController c = NotificationsController(open: opened.add)..onInit();
      await c.paged.reload();
      h.api.failNext('update:notifications', const AppFailure('network'));
      await c.openNotification(c.paged.items.first);
      expect(c.paged.items.first.isUnread, isTrue);
      expect(opened.length, 1);
    });

    test('empty and failing lists have their own states', () async {
      final NotificationsController c = NotificationsController(open: (String r) {})..onInit();
      await c.paged.reload();
      expect(c.paged.items, isEmpty);
      h.api.failNext('select:notifications', const AppFailure('network'));
      await c.paged.reload();
      expect(c.paged.failure.value?.code, 'network');
    });
  });
}
