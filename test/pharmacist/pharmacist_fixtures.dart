// UNRUN: written without the Flutter SDK; verify with flutter test.
import 'package:dawak/data/models/medicine.dart';

import '../support/fixtures.dart';
import '../support/harness.dart';

/// Signs in a pharmacy member and loads the session. Defaults to the owner of the approved pharmacy `ph-1` (SYP).
Future<void> signInMember(
  AppHarness h, {
  String memberRole = 'owner',
  String currency = 'SYP',
  String pharmacyStatus = 'approved',
}) async {
  h.signInAs(
    'u1',
    role: 'pharmacist',
    pharmacy: Fx.pharmacyRow('ph-1', owner: memberRole == 'owner' ? 'u1' : 'owner-x', status: pharmacyStatus, currency: currency),
    memberRole: memberRole,
  );
  await h.session.restore();
}

/// A `pharmacy_products` row with its embedded medicine, ready for `api.tables['pharmacy_products']`.
Map<String, dynamic> listRow(
  String id, {
  String ar = 'بنادول',
  String en = 'Panadol',
  double price = 5000,
  bool available = true,
  DateTime? confirmedAt,
  String? categoryId,
}) {
  final Map<String, dynamic> med = Fx.medicineRow('med-$id', ar: ar, en: en);
  if (categoryId != null) med['category_id'] = categoryId;
  return Fx.productRow(id, 'ph-1', med, price: price, available: available, confirmedAt: confirmedAt);
}

/// The same row as a model.
PharmacyProduct listItem(
  String id, {
  String ar = 'بنادول',
  String en = 'Panadol',
  double price = 5000,
  bool available = true,
  DateTime? confirmedAt,
}) =>
    PharmacyProduct.fromJson(listRow(id, ar: ar, en: en, price: price, available: available, confirmedAt: confirmedAt));

void seedList(AppHarness h, List<Map<String, dynamic>> rows) => h.api.tables['pharmacy_products'] = rows;

/// Seeds [rows] so that the list order of the screens (newest `updated_at` first) equals the order given here.
void seedOrdered(AppHarness h, List<Map<String, dynamic>> rows) {
  for (int i = 0; i < rows.length; i++) {
    rows[i]['updated_at'] = DateTime.utc(2026, 10, 10, 12).subtract(Duration(minutes: i)).toIso8601String();
  }
  h.api.tables['pharmacy_products'] = rows;
}
