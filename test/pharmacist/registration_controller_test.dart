// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/app/routes/app_routes.dart';
import 'package:dawak/core/errors/app_failure.dart';
import 'package:dawak/data/models/geo.dart';
import 'package:dawak/data/models/pharmacy.dart';
import 'package:dawak/features/pharmacist/controllers/pharmacy_registration_controller.dart';
import 'package:dawak/features/pharmacist/controllers/pharmacy_status_controller.dart';
import 'package:dawak/features/pharmacist/services/license_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
  late AppHarness h;
  late List<String> opened;
  late List<String> offAll;

  setUp(() async {
    h = await AppHarness.create();
    opened = <String>[];
    offAll = <String>[];
  });
  tearDown(() => h.dispose());

  PickedLicense pdf({String name = 'licence.pdf', int size = 2048}) =>
      PickedLicense(name: name, bytes: List<int>.filled(size, 1), contentType: 'application/pdf');

  PharmacyRegistrationController make({LicensePicker? picker}) => PharmacyRegistrationController(
        picker: picker ?? (() async => pdf()),
        open: opened.add,
        offAll: (String route, {Object? arguments}) => offAll.add(route),
      )..onInit();

  /// A new pharmacist without a pharmacy yet.
  Future<void> signInNewPharmacist() async {
    h.signInAs('u1', role: 'pharmacist');
    await h.session.restore();
  }

  const GeoPoint shop = GeoPoint(33.5138, 36.2765);

  void fillAll(PharmacyRegistrationController c) {
    c.name.text = 'صيدلية الأمل';
    c.phone.text = '0933 123 456';
    c.city.text = 'دمشق';
    c.neighborhood.text = 'المزة';
    c.addressLine.text = 'شارع الجلاء، بناء 4';
    c.location.setInitial(shop);
  }

  /// Makes `register_pharmacy` behave like the database: the pharmacy and its owner membership now exist.
  void registerCreatesPharmacy() {
    h.api.rpcs['register_pharmacy'] = (Map<String, dynamic> p) {
      final Map<String, dynamic> row = Fx.pharmacyRow('ph-new', owner: 'u1', status: 'pending');
      (h.api.tables['pharmacies'] ??= <Map<String, dynamic>>[]).add(row);
      (h.api.tables['pharmacy_members'] ??= <Map<String, dynamic>>[]).add(Fx.memberRow('ph-new', 'u1'));
      return row;
    };
  }

  group('licence step', () {
    test('a valid file is accepted and clears the error', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      c.licenseError.value = 'old';
      await c.pickLicense();
      expect(c.picked.value?.name, 'licence.pdf');
      expect(c.licenseError.value, isNull);
      expect(c.hasLicense, isTrue);
    });

    test('cancelling the chooser changes nothing', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make(picker: () async => null);
      await c.pickLicense();
      expect(c.picked.value, isNull);
      expect(c.licenseError.value, isNull);
    });

    test('an unsupported type is refused', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c =
          make(picker: () async => PickedLicense(name: 'licence.docx', bytes: List<int>.filled(10, 1), contentType: 'application/octet-stream'));
      await c.pickLicense();
      expect(c.picked.value, isNull);
      expect(c.licenseError.value, 'p_reg_license_bad_type'.tr);
    });

    test('a file over 5 MB is refused', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make(picker: () async => pdf(size: LicenseFiles.maxBytes + 1));
      await c.pickLicense();
      expect(c.picked.value, isNull);
      expect(c.licenseError.value, 'err_file_too_large'.tr);
    });

    test('an empty file is refused', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make(picker: () async => pdf(size: 0));
      await c.pickLicense();
      expect(c.picked.value, isNull);
      expect(c.licenseError.value, 'p_reg_license_pick_failed'.tr);
    });

    test('a chooser that throws shows the failure text instead of crashing', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make(picker: () async => throw StateError('plugin'));
      await c.pickLicense();
      expect(c.licenseError.value, 'p_reg_license_pick_failed'.tr);
    });

    test('continuing without a file stays on the step; with a file it opens the information step', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      c.continueFromLicense();
      expect(opened, isEmpty);
      expect(c.licenseError.value, 'p_reg_license_required'.tr);
      await c.pickLicense();
      c.continueFromLicense();
      expect(opened, <String>[AppRoutes.pharmacyRegisterInfo]);
    });

    test('the allowed file types are PDF, JPG, JPEG and PNG, whatever the letter case', () {
      expect(LicenseFiles.contentTypeFor('a.PDF'), 'application/pdf');
      expect(LicenseFiles.contentTypeFor('a.jpeg'), 'image/jpeg');
      expect(LicenseFiles.contentTypeFor('a.Png'), 'image/png');
      expect(LicenseFiles.contentTypeFor('a.gif'), isNull);
      expect(LicenseFiles.contentTypeFor('noextension'), isNull);
      expect(LicenseFiles.contentTypeFor('trailingdot.'), isNull);
    });
  });

  group('shop location (address step)', () {
    Future<PharmacyRegistrationController> onAddressStep(WidgetTester tester) async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Form(key: c.addressForm, child: const SizedBox()))));
      return c;
    }

    testWidgets('continuing without a location stays on the step and says the location is required', (WidgetTester tester) async {
      final PharmacyRegistrationController c = await onAddressStep(tester);
      c.continueFromAddress();
      expect(opened, isEmpty);
      expect(c.locationError.value, 'p_loc_required'.tr);
    });

    testWidgets('with a location the step opens the hours step and clears the error', (WidgetTester tester) async {
      final PharmacyRegistrationController c = await onAddressStep(tester);
      c.continueFromAddress();
      expect(await c.location.useCurrent(), isTrue);
      expect(c.location.point.value?.latitude, 33.5102);
      c.continueFromAddress();
      expect(opened, <String>[AppRoutes.pharmacyRegisterHours]);
      expect(c.locationError.value, isNull);
    });

    testWidgets('a position pasted from a map link is accepted too', (WidgetTester tester) async {
      final PharmacyRegistrationController c = await onAddressStep(tester);
      c.location.paste.text = 'https://www.google.com/maps/@33.5001,36.3002,17z';
      expect(c.location.usePasted(), isTrue);
      c.continueFromAddress();
      expect(opened, <String>[AppRoutes.pharmacyRegisterHours]);
      expect(c.buildDraft().location?.longitude, 36.3002);
    });

    test('a missing location sends the wizard back to the address step even when the text fields are fine', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      await c.pickLicense();
      fillAll(c);
      expect(c.firstInvalidStep(), isNull);
      c.location.setInitial(null);
      expect(c.firstInvalidStep(), AppRoutes.pharmacyRegisterAddress);
    });

    test('nothing is uploaded or sent without a location', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      final PharmacyRegistrationController c = make();
      fillAll(c);
      await c.pickLicense();
      c.location.setInitial(null);
      expect(await c.submitApplication(), isFalse);
      expect(opened.last, AppRoutes.pharmacyRegisterAddress);
      expect(h.files.uploaded, isEmpty);
      expect(h.api.rpcCount('register_pharmacy'), 0);
    });
  });

  group('opening hours', () {
    test('the default week is open every day except Friday', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      expect(c.hours.value.days.length, 7);
      expect(c.hours.value.days.where((DayHours d) => d.open).length, 6);
      expect(c.hours.value.days[6].open, isFalse);
      expect(c.validateHours(), isNull);
    });

    test('a week with every day closed is refused', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      for (int d = 0; d < 7; d++) {
        c.setDayOpen(d, false);
      }
      expect(c.validateHours(), 'p_reg_hours_none_open'.tr);
    });

    test('an open day must close after it opens', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      c.setDayTime(2, from: true, value: '18:00');
      c.setDayTime(2, from: false, value: '09:00');
      expect(c.validateHours(), 'p_reg_hours_invalid'.tr);
      c.setDayTime(2, from: false, value: '22:00');
      expect(c.validateHours(), isNull);
    });

    test('a closed day with odd times does not matter', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      c.setDayTime(6, from: true, value: '18:00');
      c.setDayTime(6, from: false, value: '09:00');
      expect(PharmacyRegistrationController.dayIsValid(c.hours.value.days[6]), isTrue);
    });
  });

  group('submitting a new application', () {
    test('uploads the licence, files the application and moves to the pending screen', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      final PharmacyRegistrationController c = make();
      fillAll(c);
      await c.pickLicense();
      c.currency.value = 'USD';
      c.showPhonePublicly.value = false;

      expect(await c.submitApplication(), isTrue);

      expect(h.files.uploaded, <String>['u1/licence.pdf']);
      final Map<String, dynamic> p = h.api.rpcLog.single.params;
      expect(h.api.rpcLog.single.fn, 'register_pharmacy');
      expect(p['p_name'], 'صيدلية الأمل');
      expect(p['p_phone'], '0933123456', reason: 'spaces are removed');
      expect(p['p_city'], 'دمشق');
      expect(p['p_currency'], 'USD');
      expect(p['p_license_path'], 'u1/licence.pdf');
      expect(p['p_latitude'], 33.5138);
      expect(p['p_longitude'], 36.2765);
      expect(p['p_show_phone_publicly'], false);
      expect((p['p_opening_hours'] as Map<String, dynamic>)['days'], hasLength(7));
      expect(offAll, <String>[AppRoutes.statusPending]);
    });

    test('nothing is sent while a step is incomplete; the wizard is sent back to that step', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      final PharmacyRegistrationController c = make();
      await c.pickLicense();
      // no name, phone or address
      expect(await c.submitApplication(), isFalse);
      expect(opened.last, AppRoutes.pharmacyRegisterInfo);
      expect(h.files.uploaded, isEmpty);
      expect(h.api.rpcCount('register_pharmacy'), 0);

      c.name.text = 'صيدلية الأمل';
      c.phone.text = '0933123456';
      expect(await c.submitApplication(), isFalse);
      expect(opened.last, AppRoutes.pharmacyRegisterAddress);
    });

    test('without a licence the wizard goes back to the first step', () async {
      await signInNewPharmacist();
      final PharmacyRegistrationController c = make();
      fillAll(c);
      expect(c.firstInvalidStep(), AppRoutes.pharmacyRegister);
    });

    test('invalid hours stop the submission on the hours step', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      final PharmacyRegistrationController c = make();
      fillAll(c);
      await c.pickLicense();
      for (int d = 0; d < 7; d++) {
        c.setDayOpen(d, false);
      }
      expect(await c.submitApplication(), isFalse);
      expect(c.hoursError.value, 'p_reg_hours_none_open'.tr);
      expect(h.files.uploaded, isEmpty);
    });

    test('a failed upload reaches the user, sends nothing and can be retried', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      final PharmacyRegistrationController c = make();
      fillAll(c);
      await c.pickLicense();
      h.files.nextFailure = const AppFailure('network');

      expect(await c.submitApplication(), isFalse);
      expect(c.failure.value?.code, 'network');
      expect(h.api.rpcCount('register_pharmacy'), 0);

      expect(await c.submitApplication(), isTrue);
      expect(h.files.uploaded, <String>['u1/licence.pdf']);
    });

    test('a retry after the application call failed does not upload the licence twice', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      final PharmacyRegistrationController c = make();
      fillAll(c);
      await c.pickLicense();
      h.api.failNext('rpc:register_pharmacy', const AppFailure('network'));

      expect(await c.submitApplication(), isFalse);
      expect(h.files.uploaded.length, 1);

      expect(await c.submitApplication(), isTrue);
      expect(h.files.uploaded.length, 1, reason: 'the uploaded path is reused');
      expect(h.api.calls.where((String l) => l == 'rpc:register_pharmacy').length, 2);
    });

    test('choosing another file after an upload uploads the new one', () async {
      await signInNewPharmacist();
      registerCreatesPharmacy();
      int n = 0;
      final PharmacyRegistrationController c = make(picker: () async => pdf(name: 'licence${++n}.pdf'));
      fillAll(c);
      await c.pickLicense();
      h.api.failNext('rpc:register_pharmacy', const AppFailure('network'));
      await c.submitApplication();
      await c.pickLicense();

      expect(await c.submitApplication(), isTrue);
      expect(h.files.uploaded, <String>['u1/licence1.pdf', 'u1/licence2.pdf']);
      expect(h.api.rpcLog.last.params['p_license_path'], 'u1/licence2.pdf');
    });

    test('a server refusal keeps the user on the wizard', () async {
      await signInNewPharmacist();
      h.api.rpcs['register_pharmacy'] = (Map<String, dynamic> p) => throw const AppFailure('invalid_input');
      final PharmacyRegistrationController c = make();
      fillAll(c);
      await c.pickLicense();
      expect(await c.submitApplication(), isFalse);
      expect(offAll, isEmpty);
      expect(c.failure.value?.code, 'invalid_input');
    });
  });

  group('resubmitting a rejected application', () {
    Future<void> signInRejected() async {
      final Map<String, dynamic> row = Fx.pharmacyRow('ph-1', owner: 'u1', status: 'rejected', currency: 'USD');
      row['license_document_path'] = 'u1/old.pdf';
      row['status_reason'] = 'الترخيص غير واضح';
      h.signInAs('u1', role: 'pharmacist', pharmacy: row);
      await h.session.restore();
    }

    test('the wizard opens prefilled and the currency is locked', () async {
      await signInRejected();
      final PharmacyRegistrationController c = make();
      expect(c.isResubmission, isTrue);
      expect(c.name.text, 'صيدلية الشفاء');
      expect(c.currency.value, 'USD');
      expect(c.existingLicensePath.value, 'u1/old.pdf');
      expect(c.hasLicense, isTrue);
      c.setCurrency('SYP');
      expect(c.currency.value, 'USD');
    });

    test('the wizard starts with the position the pharmacy already has', () async {
      await signInRejected();
      final PharmacyRegistrationController c = make();
      expect(c.location.point.value?.latitude, 33.5130);
      expect(c.location.point.value?.longitude, 36.2765);
    });

    test('a pharmacy registered before locations existed must choose one before resubmitting', () async {
      await signInRejected();
      h.api.tables['pharmacies']!.first['latitude'] = null;
      h.api.tables['pharmacies']!.first['longitude'] = null;
      await h.session.refresh(navigateOnChange: false);
      h.api.rpcs['resubmit_pharmacy'] = (Map<String, dynamic> p) => h.api.tables['pharmacies']!.first;
      final PharmacyRegistrationController c = make();
      expect(c.location.point.value, isNull);

      expect(await c.submitApplication(), isFalse);
      expect(opened.last, AppRoutes.pharmacyRegisterAddress);
      expect(h.api.rpcCount('resubmit_pharmacy'), 0);

      c.location.setInitial(shop);
      expect(await c.submitApplication(), isTrue);
      expect(h.api.rpcLog.single.params['p_latitude'], 33.5138);
    });

    test('keeping the old licence resubmits without uploading', () async {
      await signInRejected();
      h.api.rpcs['resubmit_pharmacy'] = (Map<String, dynamic> p) {
        h.api.tables['pharmacies']!.first['approval_status'] = 'pending';
        return h.api.tables['pharmacies']!.first;
      };
      final PharmacyRegistrationController c = make();
      c.name.text = 'صيدلية الشفاء الجديدة';

      expect(await c.submitApplication(), isTrue);

      expect(h.files.uploaded, isEmpty);
      final Map<String, dynamic> p = h.api.rpcLog.single.params;
      expect(h.api.rpcLog.single.fn, 'resubmit_pharmacy');
      expect(p['p_pharmacy_id'], 'ph-1');
      expect(p['p_name'], 'صيدلية الشفاء الجديدة');
      expect(p['p_license_path'], 'u1/old.pdf');
      expect(p.containsKey('p_currency'), isFalse, reason: 'resubmit_pharmacy has no currency parameter');
      expect(offAll, <String>[AppRoutes.statusPending]);
    });

    test('a new licence replaces the old one', () async {
      await signInRejected();
      h.api.rpcs['resubmit_pharmacy'] = (Map<String, dynamic> p) {
        h.api.tables['pharmacies']!.first['approval_status'] = 'pending';
        return h.api.tables['pharmacies']!.first;
      };
      final PharmacyRegistrationController c = make(picker: () async => pdf(name: 'new.pdf'));
      await c.pickLicense();
      expect(await c.submitApplication(), isTrue);
      expect(h.api.rpcLog.single.params['p_license_path'], 'u1/new.pdf');
    });
  });

  group('PharmacyStatusController', () {
    test('shows the reason of a rejection, or nothing when there is none', () async {
      final Map<String, dynamic> row = Fx.pharmacyRow('ph-1', owner: 'u1', status: 'rejected');
      row['status_reason'] = '  الترخيص منتهي  ';
      h.signInAs('u1', role: 'pharmacist', pharmacy: row);
      await h.session.restore();
      expect(PharmacyStatusController().reason, 'الترخيص منتهي');

      row['status_reason'] = '   ';
      await h.session.refresh(navigateOnChange: false);
      final PharmacyStatusController c = PharmacyStatusController()..onInit();
      expect(c.reason, isNull);
    });

    test('refreshing picks up a decision and the session navigates', () async {
      h.signInAs('u1', role: 'pharmacist', pharmacy: Fx.pharmacyRow('ph-1', owner: 'u1', status: 'pending'));
      await h.session.restore();
      final PharmacyStatusController c = PharmacyStatusController()..onInit();
      expect(c.pharmacy.value?.status.name, 'pending');

      h.api.tables['pharmacies']!.first['approval_status'] = 'approved';
      await c.refreshNow();
      await Future<void>.delayed(Duration.zero);

      expect(h.navigated.last, AppRoutes.pharmacistDashboard);
      expect(c.pharmacy.value?.status.name, 'approved');
      expect(c.refreshing.value, isFalse);
    });

    test('refreshing with no decision yet keeps the user here', () async {
      h.signInAs('u1', role: 'pharmacist', pharmacy: Fx.pharmacyRow('ph-1', owner: 'u1', status: 'pending'));
      await h.session.restore();
      final PharmacyStatusController c = PharmacyStatusController()..onInit();
      await c.refreshNow();
      expect(h.navigated, isEmpty);
      expect(c.refreshing.value, isFalse);
    });

    test('a rejected pharmacy opens the wizard to edit and resubmit', () async {
      h.signInAs('u1', role: 'pharmacist', pharmacy: Fx.pharmacyRow('ph-1', owner: 'u1', status: 'rejected'));
      await h.session.restore();
      final List<String> routes = <String>[];
      PharmacyStatusController(open: routes.add).editAndResubmit();
      expect(routes, <String>[AppRoutes.pharmacyRegister]);
    });
  });
}
