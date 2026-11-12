import 'package:dawak/data/models/enums.dart';
import 'package:dawak/data/models/pharmacy.dart';
import 'package:dawak/data/models/profile.dart';

/// Row maps shaped like PostgREST/RPC output, used to seed [FakeApiClient].
class Fx {
  const Fx._();

  static Map<String, dynamic> profileRow(String id, {String role = 'customer', String status = 'active', String name = 'Test User', String? reason}) =>
      <String, dynamic>{
        'id': id,
        'role': role,
        'account_status': status,
        'display_name': name,
        'phone': null,
        'locale': 'ar',
        'suspended_reason': reason,
        'created_at': '2026-10-01T10:00:00Z',
      };

  static Map<String, dynamic> pharmacyRow(String id, {String owner = 'owner-1', String status = 'approved', String currency = 'SYP', String name = 'صيدلية الشفاء', double latitude = 33.5130, double longitude = 36.2765}) =>
      <String, dynamic>{
        'id': id,
        'owner_id': owner,
        'name': name,
        'phone': '+963911111111',
        'show_phone_publicly': true,
        'address_line': 'شارع بغداد',
        'neighborhood': 'المزة',
        'city': 'دمشق',
        'directions': '',
        'latitude': latitude,
        'longitude': longitude,
        'opening_hours': <String, dynamic>{'days': <Map<String, dynamic>>[]},
        'currency': currency,
        'approval_status': status,
        'is_listed': true,
        'created_at': '2026-10-01T10:00:00Z',
      };

  static Map<String, dynamic> memberRow(String pharmacyId, String userId, {String role = 'owner'}) =>
      <String, dynamic>{'pharmacy_id': pharmacyId, 'user_id': userId, 'role': role, 'status': 'active'};

  static Map<String, dynamic> medicineRow(String id, {String ar = 'بنادول', String en = 'Panadol', String strength = '500mg', String form = 'أقراص'}) =>
      <String, dynamic>{
        'id': id,
        'name_ar': ar,
        'name_en': en,
        'strength': strength,
        'dosage_form': form,
        'catalog_status': 'approved',
      };

  /// A row of a pharmacy's list: the medicine, its price, whether it is available and when it was last confirmed.
  static Map<String, dynamic> productRow(String id, String pharmacyId, Map<String, dynamic> medicine,
          {double price = 5000, bool available = true, DateTime? confirmedAt}) =>
      <String, dynamic>{
        'id': id,
        'pharmacy_id': pharmacyId,
        'medicine_id': medicine['id'],
        'medicines': medicine,
        'price': price,
        'is_available': available,
        'confirmed_at': (confirmedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// `get_medicine_pharmacies` row.
  static Map<String, dynamic> offerRow(String pharmacyId, String productId,
          {String name = 'صيدلية الشفاء', double price = 5000, double? distanceKm, String freshness = 'recent', DateTime? confirmedAt}) =>
      <String, dynamic>{
        'pharmacy_id': pharmacyId,
        'pharmacy_name': name,
        'city': 'دمشق',
        'neighborhood': 'المزة',
        'address_line': 'شارع بغداد',
        'phone': '+963911111111',
        'currency': 'SYP',
        'latitude': 33.5130,
        'longitude': 36.2765,
        'distance_km': distanceKm,
        'product_id': productId,
        'price': price,
        'freshness': freshness,
        'confirmed_at': (confirmedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };

  /// An offer inside an availability request (`offers` of `get_availability_request`).
  static Map<String, dynamic> requestOfferRow(String pharmacyId,
          {String name = 'صيدلية الشفاء', double price = 5000, double? distanceKm = 0.4, String? productId = 'prod-1'}) =>
      <String, dynamic>{
        'pharmacy_id': pharmacyId,
        'name': name,
        'city': 'دمشق',
        'neighborhood': 'المزة',
        'address_line': 'شارع بغداد',
        'phone': '+963911111111',
        'currency': 'SYP',
        'latitude': 33.5130,
        'longitude': 36.2765,
        'distance_km': distanceKm,
        'price': price,
        'product_id': productId,
        'answered_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// `create_availability_request` / `get_availability_request` / `expand_…` / `close_…` result.
  static Map<String, dynamic> requestJson(String id,
          {String status = 'open', int step = 1, bool exhausted = false, int notified = 3, int answered = 0, int unavailable = 0,
          List<Map<String, dynamic>> offers = const <Map<String, dynamic>>[], Map<String, dynamic>? medicine}) =>
      <String, dynamic>{
        'id': id,
        'status': status,
        'step': step,
        'radius_km': const <int, double>{1: 1, 2: 3, 3: 5, 4: 10}[step],
        'radius_exhausted': exhausted || step >= 4,
        'medicine': medicine ?? medicineRow('med-1'),
        'notified': notified,
        'answered': answered,
        'unavailable': unavailable,
        'offers': offers,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 60)).toIso8601String(),
        'seconds_left': 3600,
      };

  /// `list_pharmacy_availability_requests` row.
  static Map<String, dynamic> inboxRow(String requestId,
          {String medicineId = 'med-1', String status = 'open', String? answer, double? answerPrice, double? distanceKm = 0.6, double? listedPrice, bool? listedAvailable}) =>
      <String, dynamic>{
        'request_id': requestId,
        'medicine_id': medicineId,
        'name_ar': 'بنادول',
        'name_en': 'Panadol',
        'strength': '500mg',
        'dosage_form': 'أقراص',
        'request_status': status,
        'distance_km': distanceKm,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now().toUtc().add(const Duration(minutes: 55)).toIso8601String(),
        'answer': answer,
        'answer_price': answerPrice,
        'answered_at': answer == null ? null : DateTime.now().toUtc().toIso8601String(),
        'listed_price': listedPrice,
        'listed_available': listedAvailable,
      };

  static Map<String, dynamic> orderRow(String id, String customerId, String pharmacyId,
          {String status = 'pending', String ref = 'DWK-ABCDE12345', List<Map<String, dynamic>>? items, double subtotal = 10000}) =>
      <String, dynamic>{
        'id': id,
        'public_ref': ref,
        'customer_id': customerId,
        'pharmacy_id': pharmacyId,
        'status': status,
        'currency': 'SYP',
        'subtotal': subtotal,
        'pharmacy_name': 'صيدلية الشفاء',
        'pharmacy_address': 'شارع بغداد، المزة، دمشق',
        'pharmacy_phone': '+963911111111',
        'customer_name': 'زبون',
        'created_at': '2026-10-10T09:00:00Z',
        'order_items': items ??
            <Map<String, dynamic>>[
              <String, dynamic>{'id': 'oi-1', 'line_no': 1, 'product_id': 'prod-1', 'medicine_name': 'بنادول', 'strength': '500mg', 'quantity': 2, 'unit_price': 5000},
            ],
      };

  static Map<String, dynamic> saleJson(String id, {String invoice = 'INV-000001', double total = 10000}) => <String, dynamic>{
        'id': id,
        'invoice_no': invoice,
        'order_id': null,
        'currency': 'SYP',
        'subtotal': total,
        'discount_amount': 0,
        'total': total,
        'created_at': '2026-10-10T09:30:00Z',
        'cashier_name': 'أمين الصندوق',
        'pharmacy': <String, dynamic>{'id': 'ph-1', 'name': 'صيدلية الشفاء', 'phone': '+963911111111', 'address_line': 'شارع بغداد', 'neighborhood': 'المزة', 'city': 'دمشق'},
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'si-1', 'line_no': 1, 'product_id': 'prod-1', 'name': 'بنادول', 'strength': '500mg', 'quantity': 2, 'unit_price': 5000, 'line_total': 10000},
        ],
      };

  static Profile profile({String id = 'user-1', UserRole role = UserRole.customer, bool suspended = false}) =>
      Profile.fromJson(profileRow(id, role: role.name, status: suspended ? 'suspended' : 'active'));

  static Pharmacy pharmacy({String id = 'ph-1', ApprovalStatus status = ApprovalStatus.approved, MemberRole role = MemberRole.owner}) =>
      Pharmacy.fromJson(pharmacyRow(id, status: status.name), memberRole: role);
}
