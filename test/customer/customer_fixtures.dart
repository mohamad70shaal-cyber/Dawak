import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/data/models/order.dart';

import '../support/fake_api.dart';

/// A row of `get_public_pharmacy_products` as the database returns it (only available rows are ever returned).
Map<String, dynamic> catalogueRow(
  String productId,
  String medicineId, {
  String ar = 'بنادول',
  String en = 'Panadol',
  double price = 5000,
  String freshness = 'recent',
  String? confirmedAt = '2026-10-10T09:00:00Z',
  String currency = 'SYP',
}) =>
    <String, dynamic>{
      'product_id': productId,
      'medicine_id': medicineId,
      'name_ar': ar,
      'name_en': en,
      'strength': '500mg',
      'dosage_form': 'أقراص',
      'price': price,
      'currency': currency,
      'freshness': freshness,
      'confirmed_at': confirmedAt,
    };

PublicProduct product(
  String productId, {
  String medicineId = 'med-1',
  double price = 5000,
  String freshness = 'recent',
}) =>
    PublicProduct.fromJson(catalogueRow(productId, medicineId, price: price, freshness: freshness));

/// A row of `search_medicines`.
Map<String, dynamic> searchRow(String id, {String ar = 'بنادول', String en = 'Panadol', int pharmacies = 2}) => <String, dynamic>{
      'id': id,
      'name_ar': ar,
      'name_en': en,
      'strength': '500mg',
      'dosage_form': 'أقراص',
      'pharmacy_count': pharmacies,
    };

Map<String, dynamic> publicPharmacyRow(String id, {String name = 'صيدلية الشفاء', String currency = 'SYP'}) => <String, dynamic>{
      'id': id,
      'name': name,
      'city': 'دمشق',
      'neighborhood': 'المزة',
      'address_line': 'شارع بغداد',
      'phone': '+963911111111',
      'directions': 'مقابل المدرسة',
      'currency': currency,
      'opening_hours': <String, dynamic>{'days': <Map<String, dynamic>>[]},
    };

/// Serves a list as an RPC that honours `p_offset` / `p_limit` like the real functions.
RpcHandler paged(List<Map<String, dynamic>> rows) => (Map<String, dynamic> p) {
      final int offset = (p['p_offset'] as int?) ?? 0;
      final int limit = (p['p_limit'] as int?) ?? 20;
      return rows.skip(offset).take(limit).toList();
    };

/// Registers `get_public_pharmacy_products` for one pharmacy; [rows] can be replaced by the test later.
List<Map<String, dynamic>> serveCatalogue(FakeApiClient api, List<Map<String, dynamic>> rows) {
  api.rpcs['get_public_pharmacy_products'] = paged(rows);
  return rows;
}

Order order(String id, {String status = 'pending'}) => Order.fromJson(<String, dynamic>{
      'id': id,
      'public_ref': 'DWK-ABCDE12345',
      'customer_id': 'c1',
      'pharmacy_id': 'ph-1',
      'status': status,
      'currency': 'SYP',
      'subtotal': 10000,
      'created_at': '2026-10-10T09:00:00Z',
      'items': <Map<String, dynamic>>[],
    });

/// A row of `list_my_availability_requests`.
Map<String, dynamic> summaryRow(String id, {String status = 'open', int offers = 0, String medicineId = 'med-1', String ar = 'بنادول', String en = 'Panadol'}) =>
    <String, dynamic>{
      'id': id,
      'medicine_id': medicineId,
      'name_ar': ar,
      'name_en': en,
      'strength': '500mg',
      'dosage_form': 'أقراص',
      'status': status,
      'offers_count': offers,
      'created_at': '2026-10-10T09:00:00Z',
      'expires_at': '2026-10-10T10:00:00Z',
    };
