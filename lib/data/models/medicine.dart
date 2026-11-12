import 'enums.dart';
import 'json_utils.dart';
import 'pharmacy.dart';

class MedicineCategory {
  const MedicineCategory({required this.id, required this.nameAr, this.nameEn, this.sortOrder = 0, this.isActive = true});

  final String id;
  final String nameAr;
  final String? nameEn;
  final int sortOrder;
  final bool isActive;

  /// Name in the current language, falling back to the other one.
  String name(bool arabic) {
    final String? en = nameEn;
    if (arabic) return nameAr.isNotEmpty ? nameAr : (en ?? '');
    return (en != null && en.isNotEmpty) ? en : nameAr;
  }

  factory MedicineCategory.fromJson(Map<String, dynamic> j) => MedicineCategory(
        id: J.str(j['id']),
        nameAr: J.str(j['name_ar']),
        nameEn: J.strOrNull(j['name_en']),
        sortOrder: J.integer(j['sort_order']),
        isActive: J.boolean(j['is_active'], true),
      );
}

/// A medicine of the shared catalogue.
class Medicine {
  const Medicine({
    required this.id,
    this.nameAr,
    this.nameEn,
    this.brandName,
    this.activeIngredient,
    this.strength,
    this.dosageForm,
    this.packageDescription,
    this.categoryId,
    this.pharmacyCount = 0,
    this.catalogStatus = 'approved',
    this.createdAt,
  });

  final String id;
  final String? nameAr;
  final String? nameEn;
  final String? brandName;
  final String? activeIngredient;
  final String? strength;
  final String? dosageForm;
  final String? packageDescription;
  final String? categoryId;

  /// Number of listed pharmacies that confirmed the medicine as available within the last 30 days (search results only).
  final int pharmacyCount;
  final String catalogStatus;
  final DateTime? createdAt;

  /// Display name in the current language with a sensible fallback.
  String displayName(bool arabic) {
    final String ar = (nameAr ?? '').trim();
    final String en = (nameEn ?? '').trim();
    if (arabic) return ar.isNotEmpty ? ar : en;
    return en.isNotEmpty ? en : ar;
  }

  /// The "other" language name, shown as a subtitle when it differs.
  String secondaryName(bool arabic) {
    final String ar = (nameAr ?? '').trim();
    final String en = (nameEn ?? '').trim();
    final String primary = displayName(arabic);
    final String other = arabic ? en : ar;
    return other == primary ? '' : other;
  }

  /// "500mg · أقراص · علبة 20 قرص"
  String get specLine => <String?>[strength, dosageForm, packageDescription]
      .where((String? s) => s != null && s.trim().isNotEmpty)
      .map((String? s) => s!.trim())
      .join(' · ');

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: J.str(j['id'] ?? j['medicine_id']),
        nameAr: J.strOrNull(j['name_ar']),
        nameEn: J.strOrNull(j['name_en']),
        brandName: J.strOrNull(j['brand_name']),
        activeIngredient: J.strOrNull(j['active_ingredient']),
        strength: J.strOrNull(j['strength']),
        dosageForm: J.strOrNull(j['dosage_form']),
        packageDescription: J.strOrNull(j['package_description']),
        categoryId: J.strOrNull(j['category_id']),
        pharmacyCount: J.integer(j['pharmacy_count']),
        catalogStatus: J.str(j['catalog_status'], 'approved'),
        createdAt: J.date(j['created_at']),
      );
}

/// Input for proposing a new medicine (pharmacist) or editing/creating one (admin).
class MedicineDraft {
  const MedicineDraft({
    this.nameAr,
    this.nameEn,
    this.brandName,
    this.activeIngredient,
    this.strength,
    this.dosageForm,
    this.packageDescription,
    this.categoryId,
  });

  final String? nameAr;
  final String? nameEn;
  final String? brandName;
  final String? activeIngredient;
  final String? strength;
  final String? dosageForm;
  final String? packageDescription;
  final String? categoryId;

  Map<String, dynamic> toRow() => <String, dynamic>{
        'name_ar': _n(nameAr),
        'name_en': _n(nameEn),
        'brand_name': _n(brandName),
        'active_ingredient': _n(activeIngredient),
        'strength': _n(strength),
        'dosage_form': _n(dosageForm),
        'package_description': _n(packageDescription),
        'category_id': categoryId,
      };

  static String? _n(String? s) {
    final String? t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// One row of a pharmacy's own list: a catalogue medicine the pharmacy says it has, with its price.
/// There are no quantities: "available" is the pharmacist's word, `confirmedAt` says when it was last confirmed.
class PharmacyProduct {
  const PharmacyProduct({
    required this.id,
    required this.pharmacyId,
    required this.medicine,
    required this.price,
    required this.isAvailable,
    this.confirmedAt,
  });

  final String id;
  final String pharmacyId;
  final Medicine medicine;
  final double price;
  final bool isAvailable;
  final DateTime? confirmedAt;

  /// Days after which the app asks the pharmacist to confirm again (`private.cfg_int('fresh_days')`).
  static const int freshDays = 7;

  /// Mirrors `private.listing_freshness`.
  Freshness freshness({DateTime? now}) {
    final DateTime ref = now ?? DateTime.now();
    final DateTime? c = confirmedAt;
    if (c == null) return Freshness.old;
    return c.isBefore(ref.subtract(const Duration(days: freshDays))) ? Freshness.old : Freshness.recent;
  }

  /// Marked available but not confirmed for a week: shown with a "confirm" hint.
  bool isStale({DateTime? now}) => isAvailable && freshness(now: now) == Freshness.old;

  /// `medicines(...)` is the embedded relation of `select('*, medicines(*)')`.
  factory PharmacyProduct.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> med = J.map(j['medicines']);
    if (med['id'] == null) med['id'] = j['medicine_id'];
    return PharmacyProduct(
      id: J.str(j['id']),
      pharmacyId: J.str(j['pharmacy_id']),
      medicine: Medicine.fromJson(med),
      price: J.number(j['price']),
      isAvailable: J.boolean(j['is_available'], true),
      confirmedAt: J.date(j['confirmed_at']),
    );
  }
}

/// One pharmacy's confirmed offer for a medicine, as customers see it (`get_medicine_pharmacies`).
class MedicineOffer {
  const MedicineOffer({
    required this.pharmacy,
    required this.productId,
    required this.price,
    required this.currency,
    required this.freshness,
    this.confirmedAt,
  });

  /// Carries the address, phone (when public), position and, when the search was located, `distanceKm`.
  final PublicPharmacy pharmacy;
  final String productId;
  final double price;
  final String currency;
  final Freshness freshness;
  final DateTime? confirmedAt;

  double? get distanceKm => pharmacy.distanceKm;

  factory MedicineOffer.fromJson(Map<String, dynamic> j) => MedicineOffer(
        pharmacy: PublicPharmacy.fromJson(<String, dynamic>{
          'id': j['pharmacy_id'],
          'name': j['pharmacy_name'],
          'city': j['city'],
          'neighborhood': j['neighborhood'],
          'address_line': j['address_line'],
          'phone': j['phone'],
          'currency': j['currency'],
          'latitude': j['latitude'],
          'longitude': j['longitude'],
          'distance_km': j['distance_km'],
        }),
        productId: J.str(j['product_id']),
        price: J.number(j['price']),
        currency: J.str(j['currency'], 'SYP'),
        freshness: Freshness.parse(J.strOrNull(j['freshness'])),
        confirmedAt: J.date(j['confirmed_at']),
      );
}

/// One product in a pharmacy's public catalogue (`get_public_pharmacy_products`): only available, recently
/// confirmed rows are returned.
class PublicProduct {
  const PublicProduct({
    required this.productId,
    required this.medicine,
    required this.price,
    required this.currency,
    required this.freshness,
    this.confirmedAt,
  });

  final String productId;
  final Medicine medicine;
  final double price;
  final String currency;
  final Freshness freshness;
  final DateTime? confirmedAt;

  factory PublicProduct.fromJson(Map<String, dynamic> j) => PublicProduct(
        productId: J.str(j['product_id']),
        medicine: Medicine.fromJson(<String, dynamic>{...j, 'id': j['medicine_id']}),
        price: J.number(j['price']),
        currency: J.str(j['currency'], 'SYP'),
        freshness: Freshness.parse(J.strOrNull(j['freshness'])),
        confirmedAt: J.date(j['confirmed_at']),
      );
}

/// One medicine-name suggestion for an imported spreadsheet row (`match_medicine_names`).
class NameMatch {
  const NameMatch({required this.index, required this.medicine, required this.score});

  /// 1-based position of the name in the list that was sent.
  final int index;
  final Medicine medicine;

  /// Trigram word similarity, 0..1.
  final double score;

  factory NameMatch.fromJson(Map<String, dynamic> j) => NameMatch(
        index: J.integer(j['idx']),
        medicine: Medicine.fromJson(<String, dynamic>{...j, 'id': j['medicine_id']}),
        score: J.number(j['score']),
      );
}

/// Outcome of `bulk_upsert_pharmacy_products`.
class ImportResult {
  const ImportResult({required this.inserted, required this.updated, required this.skipped});

  final int inserted;
  final int updated;
  final int skipped;

  int get saved => inserted + updated;

  ImportResult operator +(ImportResult o) =>
      ImportResult(inserted: inserted + o.inserted, updated: updated + o.updated, skipped: skipped + o.skipped);

  static const ImportResult zero = ImportResult(inserted: 0, updated: 0, skipped: 0);

  factory ImportResult.fromJson(Object? raw) {
    final Map<String, dynamic> j = J.map(raw);
    return ImportResult(inserted: J.integer(j['inserted']), updated: J.integer(j['updated']), skipped: J.integer(j['skipped']));
  }
}
