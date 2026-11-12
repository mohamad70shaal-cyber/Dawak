import 'dart:io';

import 'package:dawak/app/routes/app_pages.dart';
import 'package:dawak/app/routes/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Route audit: AppRoutes, AppPages and docs/screen_registry.md describe the same set of screens, every page is
/// guarded, and a static path is never shadowed by a parameterised sibling. (tool/static_checks.py runs the same
/// checks without the Flutter SDK.)
void main() {
  final List<GetPage<dynamic>> pages = AppPages.pages;
  final List<String> names = pages.map((GetPage<dynamic> p) => p.name).toList();

  test('every AppRoutes pattern has exactly one page', () {
    for (final String r in AppRoutes.all) {
      expect(names.where((String n) => n == r).length, 1, reason: r);
    }
  });

  test('every page is a declared route', () {
    for (final String n in names) {
      expect(AppRoutes.all, contains(n));
    }
  });

  test('every page carries the guard middleware', () {
    for (final GetPage<dynamic> p in pages) {
      expect(p.middlewares, isNotNull, reason: p.name);
      expect(p.middlewares!, isNotEmpty, reason: p.name);
    }
  });

  test('static paths are registered before parameterised paths that would match them', () {
    for (int i = 0; i < names.length; i++) {
      if (!names[i].contains(':')) continue;
      final RegExp rx = RegExp('^${names[i].replaceAll(RegExp(r':[A-Za-z]+'), '[^/]+')}\$');
      for (int j = i + 1; j < names.length; j++) {
        if (!names[j].contains(':')) {
          expect(rx.hasMatch(names[j]), isFalse, reason: '${names[j]} is shadowed by ${names[i]}');
        }
      }
    }
  });

  test('the registry document lists every route and nothing else', () {
    final String doc = File('docs/screen_registry.md').readAsStringSync();
    final Set<String> inDoc = <String>{};
    for (final String line in doc.split('\n').where((String l) => l.startsWith('|'))) {
      inDoc.addAll(RegExp(r'`(/[^`\s]*)`').allMatches(line).map((RegExpMatch m) => m.group(1)!));
    }
    for (final String r in AppRoutes.all) {
      expect(inDoc, contains(r), reason: 'not documented: $r');
    }
    for (final String d in inDoc) {
      expect(AppRoutes.all, contains(d), reason: 'documented but unknown: $d');
    }
  });

  test('route builders produce paths that match their patterns', () {
    final Map<String, String> samples = <String, String>{
      AppRoutes.medicineDetails: AppRoutes.medicine('a b'),
      AppRoutes.medicinePharmacies: AppRoutes.medicineOffers('1'),
      AppRoutes.pharmacyDetails: AppRoutes.pharmacy('1'),
      AppRoutes.pharmacyContact: AppRoutes.pharmacyContactOf('1'),
      AppRoutes.customerOrderDetails: AppRoutes.customerOrder('1'),
      AppRoutes.customerOrderTracking: AppRoutes.customerOrderTrack('1'),
      AppRoutes.customerOrderCancel: AppRoutes.customerOrderCancelOf('1'),
      AppRoutes.productDetails: AppRoutes.product('1'),
      AppRoutes.productEdit: AppRoutes.productEditOf('1'),
      AppRoutes.customerRequestDetails: AppRoutes.customerRequest('1'),
      AppRoutes.pharmacistRequestDetails: AppRoutes.pharmacistRequest('1'),
      AppRoutes.posCompleted: AppRoutes.posCompletedOf('1'),
      AppRoutes.saleDetails: AppRoutes.sale('1'),
      AppRoutes.pharmacistOrderDetails: AppRoutes.pharmacistOrder('1'),
      AppRoutes.orderHandover: AppRoutes.orderHandoverOf('1'),
      AppRoutes.adminPharmacyDetails: AppRoutes.adminPharmacy('1'),
      AppRoutes.adminMedicineDetails: AppRoutes.adminMedicine('1'),
      AppRoutes.adminReportDetails: AppRoutes.adminReport('1'),
    };
    samples.forEach((String pattern, String path) {
      final RegExp rx = RegExp('^${pattern.replaceAll(RegExp(r':[A-Za-z]+'), '[^/]+')}\$');
      expect(rx.hasMatch(path), isTrue, reason: '$path vs $pattern');
    });
  });
}
