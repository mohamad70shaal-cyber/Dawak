// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/core/services/locale_service.dart';
import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:dawak/features/pharmacist/controllers/pharmacy_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';
import 'pharmacist_fixtures.dart';

void main() {
  late AppHarness h;
  late int closed;

  setUp(() async {
    h = await AppHarness.create();
    closed = 0;
  });
  tearDown(() => h.dispose());

  PharmacySettingsController make() => PharmacySettingsController(close: () => closed++)..onInit();

  /// The controller validates its forms, so (field-less) Forms must be mounted for `currentState`.
  Future<void> mountForms(WidgetTester tester, PharmacySettingsController c) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: <Widget>[
            Form(key: c.profileForm, child: const SizedBox()),
            Form(key: c.contactForm, child: const SizedBox()),
            Form(key: c.passwordForm, child: const SizedBox()),
          ]),
        ),
      ));

  /// `update_my_pharmacy` as the database does it for the owner: stores the given fields and returns the row.
  void ownerUpdates() {
    h.api.rpcs['update_my_pharmacy'] = (Map<String, dynamic> p) {
      final Map<String, dynamic> row = h.api.tables['pharmacies']!.firstWhere((Map<String, dynamic> r) => r['id'] == p['p_pharmacy_id']);
      const Map<String, String> columns = <String, String>{
        'p_name': 'name',
        'p_phone': 'phone',
        'p_address_line': 'address_line',
        'p_neighborhood': 'neighborhood',
        'p_city': 'city',
        'p_directions': 'directions',
        'p_opening_hours': 'opening_hours',
        'p_show_phone_publicly': 'show_phone_publicly',
        'p_is_listed': 'is_listed',
        'p_latitude': 'latitude',
        'p_longitude': 'longitude',
      };
      columns.forEach((String param, String column) {
        if (p.containsKey(param)) row[column] = p[param];
      });
      return Map<String, dynamic>.from(row);
    };
  }

  group('as the owner', () {
    setUp(() => signInMember(h));

    test('only the owner can edit; the forms start with the stored data', () {
      final PharmacySettingsController c = make();
      expect(c.canEdit, isTrue);
      expect(c.name.text, 'صيدلية الشفاء');
      expect(c.phone.text, '+963911111111');
      expect(c.city.text, 'دمشق');
      expect(c.isListed.value, isTrue);
      expect(c.showPhonePublicly.value, isTrue);
    });

    test('fillForms discards unsaved edits', () {
      final PharmacySettingsController c = make();
      c.name.text = 'شيء آخر';
      c.isListed.value = false;
      c.fillForms();
      expect(c.name.text, 'صيدلية الشفاء');
      expect(c.isListed.value, isTrue);
    });

    testWidgets('saving the profile sends the trimmed name and the visibility, updates the session and closes', (WidgetTester tester) async {
      ownerUpdates();
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.name.text = '  صيدلية النور  ';
      c.isListed.value = false;

      expect(await c.saveProfile(), isTrue);

      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_name': 'صيدلية النور', 'p_is_listed': false});
      expect(h.session.pharmacy!.name, 'صيدلية النور');
      expect(h.session.pharmacy!.isListed, isFalse);
      expect(closed, 1);
    });

    testWidgets('saving the contact details cleans the phone number and sends every field', (WidgetTester tester) async {
      ownerUpdates();
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.phone.text = '0933 123 456';
      c.showPhonePublicly.value = false;
      c.addressLine.text = 'شارع الجلاء';
      c.neighborhood.text = 'المزة';
      c.city.text = 'دمشق';
      c.directions.text = 'مقابل المدرسة';

      expect(await c.saveContact(), isTrue);

      expect(h.api.rpcLog.single.params, <String, dynamic>{
        'p_pharmacy_id': 'ph-1',
        'p_phone': '0933123456',
        'p_show_phone_publicly': false,
        'p_address_line': 'شارع الجلاء',
        'p_neighborhood': 'المزة',
        'p_city': 'دمشق',
        'p_directions': 'مقابل المدرسة',
      });
    });

    test('the location screen starts with the stored position', () {
      final PharmacySettingsController c = make();
      expect(c.location.point.value?.latitude, 33.5130);
      expect(c.location.point.value?.longitude, 36.2765);
    });

    testWidgets('saving the location sends the chosen position, updates the session and closes', (WidgetTester tester) async {
      ownerUpdates();
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      h.gps.position = const GeoPoint(33.4999, 36.3111);
      expect(await c.location.useCurrent(), isTrue);

      expect(await c.saveLocation(), isTrue);

      expect(h.api.rpcLog.single.params, <String, dynamic>{'p_pharmacy_id': 'ph-1', 'p_latitude': 33.4999, 'p_longitude': 36.3111});
      expect(h.session.pharmacy!.location?.latitude, 33.4999);
      expect(closed, 1);
    });

    testWidgets('saving the location with no position chosen sends nothing', (WidgetTester tester) async {
      ownerUpdates();
      h.api.tables['pharmacies']!.first['latitude'] = null;
      h.api.tables['pharmacies']!.first['longitude'] = null;
      await h.session.refresh(navigateOnChange: false);
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      expect(c.location.point.value, isNull);

      expect(await c.saveLocation(), isFalse);

      expect(h.api.rpcCount('update_my_pharmacy'), 0);
      expect(closed, 0);
    });

    testWidgets('a refusal from the server keeps the screen open and shows the failure', (WidgetTester tester) async {
      h.api.rpcs['update_my_pharmacy'] = (Map<String, dynamic> p) => throw const AppFailure('forbidden');
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.name.text = 'اسم جديد';

      expect(await c.saveProfile(), isFalse);

      expect(c.failure.value?.code, 'forbidden');
      expect(closed, 0);
      expect(c.name.text, 'اسم جديد', reason: 'the typed text is not lost');
    });

    testWidgets('opening hours: all days closed or an inverted day is refused before anything is sent', (WidgetTester tester) async {
      ownerUpdates();
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      for (int d = 0; d < 7; d++) {
        c.setDayOpen(d, false);
      }
      expect(await c.saveHours(), isFalse);
      expect(c.hoursError.value, 'p_reg_hours_none_open'.tr);

      c.setDayOpen(0, true);
      c.setDayTime(0, from: true, value: '20:00');
      c.setDayTime(0, from: false, value: '08:00');
      expect(await c.saveHours(), isFalse);
      expect(c.hoursError.value, 'p_reg_hours_invalid'.tr);
      expect(h.api.rpcCount('update_my_pharmacy'), 0);
    });

    testWidgets('valid opening hours are sent as the full week', (WidgetTester tester) async {
      ownerUpdates();
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.setDayOpen(6, true); // Friday
      c.setDayTime(6, from: true, value: '10:00');
      c.setDayTime(6, from: false, value: '14:00');

      expect(await c.saveHours(), isTrue);

      final List<dynamic> days = (h.api.rpcLog.single.params['p_opening_hours'] as Map<String, dynamic>)['days'] as List<dynamic>;
      expect(days, hasLength(7));
      final Map<String, dynamic> friday = days.cast<Map<String, dynamic>>().firstWhere((Map<String, dynamic> d) => d['day'] == 6);
      expect(friday['open'], isTrue);
      expect(friday['from'], '10:00');
      expect(friday['to'], '14:00');
    });

    testWidgets('changing the password stores it, clears the fields and closes', (WidgetTester tester) async {
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.newPassword.text = 'NewPassw0rd!';
      c.confirmPassword.text = 'NewPassw0rd!';

      expect(await c.changePassword(), isTrue);

      expect(c.newPassword.text, '');
      expect(c.confirmPassword.text, '');
      expect(closed, 1);
    });

    testWidgets('a failed password change keeps what was typed', (WidgetTester tester) async {
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.newPassword.text = 'NewPassw0rd!';
      c.confirmPassword.text = 'NewPassw0rd!';
      h.auth.nextFailure = const AppFailure('network');

      expect(await c.changePassword(), isFalse);

      expect(c.newPassword.text, 'NewPassw0rd!');
      expect(closed, 0);
      expect(c.failure.value?.code, 'network');
    });

    testWidgets('toggling the language switches the app and stores it on the profile', (WidgetTester tester) async {
      final PharmacySettingsController c = make();
      final bool before = Get.find<LocaleService>().isArabic;
      await c.toggleLanguage();
      expect(Get.find<LocaleService>().isArabic, !before);
      expect(h.api.tables['profiles']!.single['locale'], Get.find<LocaleService>().locale.value.languageCode);
    });

    test('signing out ends the session', () async {
      final PharmacySettingsController c = make();
      await c.signOut();
      expect(h.session.signedIn, isFalse);
    });
  });

  group('as a manager', () {
    setUp(() => signInMember(h, memberRole: 'manager'));

    test('can see the settings but not change the pharmacy', () {
      final PharmacySettingsController c = make();
      expect(c.canManage, isTrue);
      expect(c.canEdit, isFalse);
    });

    testWidgets('nothing is sent when a manager tries to save', (WidgetTester tester) async {
      ownerUpdates();
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.name.text = 'اسم جديد';
      expect(await c.saveProfile(), isFalse);
      expect(await c.saveContact(), isFalse);
      expect(await c.saveHours(), isFalse);
      c.location.setInitial(const GeoPoint(33.5, 36.3));
      expect(await c.saveLocation(), isFalse);
      expect(h.api.rpcCount('update_my_pharmacy'), 0);
    });

    test('the hours editor ignores changes', () {
      final PharmacySettingsController c = make();
      final bool fridayBefore = c.hours.value.days[6].open;
      c.setDayOpen(6, !fridayBefore);
      expect(c.hours.value.days[6].open, fridayBefore);
    });

    testWidgets('a manager can still change their own password', (WidgetTester tester) async {
      final PharmacySettingsController c = make();
      await mountForms(tester, c);
      c.newPassword.text = 'NewPassw0rd!';
      c.confirmPassword.text = 'NewPassw0rd!';
      expect(await c.changePassword(), isTrue);
    });
  });

  group('as a cashier', () {
    setUp(() => signInMember(h, memberRole: 'cashier'));

    test('cannot manage or edit', () {
      final PharmacySettingsController c = make();
      expect(c.canManage, isFalse);
      expect(c.canEdit, isFalse);
      expect(c.role, MemberRole.cashier);
    });
  });
}
