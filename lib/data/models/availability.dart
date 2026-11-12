import 'enums.dart';
import 'json_utils.dart';
import 'medicine.dart';
import 'pharmacy.dart';

/// A pharmacy that answered "available" to a customer's request (only these are ever shown to the customer).
class AvailabilityOffer {
  const AvailabilityOffer({
    required this.pharmacy,
    required this.price,
    required this.currency,
    this.productId,
    this.answeredAt,
  });

  /// Name, address, phone (when public), position and the distance from where the customer asked.
  final PublicPharmacy pharmacy;
  final double price;
  final String currency;

  /// The pharmacy's list row for this medicine (null only if the row was deleted afterwards): lets the customer
  /// reserve it like any other listed product.
  final String? productId;
  final DateTime? answeredAt;

  double? get distanceKm => pharmacy.distanceKm;

  factory AvailabilityOffer.fromJson(Map<String, dynamic> j) => AvailabilityOffer(
        pharmacy: PublicPharmacy.fromJson(<String, dynamic>{
          'id': j['pharmacy_id'],
          'name': j['name'],
          'city': j['city'],
          'neighborhood': j['neighborhood'],
          'address_line': j['address_line'],
          'phone': j['phone'],
          'currency': j['currency'],
          'latitude': j['latitude'],
          'longitude': j['longitude'],
          'distance_km': j['distance_km'],
        }),
        price: J.number(j['price']),
        currency: J.str(j['currency'], 'SYP'),
        productId: J.strOrNull(j['product_id']),
        answeredAt: J.date(j['answered_at']),
      );
}

/// A customer's "ask the pharmacies nearby" request with everything the results screen needs
/// (`create_availability_request`, `get_availability_request`, `expand_…`, `close_…`).
class AvailabilityRequest {
  const AvailabilityRequest({
    required this.id,
    required this.status,
    required this.step,
    required this.radiusKm,
    required this.radiusExhausted,
    required this.medicine,
    required this.notified,
    required this.answered,
    required this.unavailable,
    required this.offers,
    this.createdAt,
    this.expiresAt,
    this.secondsLeft = 0,
  });

  final String id;
  final RequestStatus status;

  /// 1..4 → 1, 3, 5, 10 km.
  final int step;
  final double radiusKm;

  /// True at the largest radius: "search further" is no longer possible.
  final bool radiusExhausted;
  final Medicine medicine;

  /// Pharmacies asked so far / that answered / that said "unavailable".
  final int notified;
  final int answered;
  final int unavailable;
  final List<AvailabilityOffer> offers;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int secondsLeft;

  bool get isOpen => status.isOpen;

  bool get hasOffers => offers.isNotEmpty;

  /// Pharmacies asked that have not answered yet.
  int get waiting => (notified - answered) < 0 ? 0 : notified - answered;

  /// Nobody in range at all (a real answer for the customer: no pharmacy near enough, not "waiting").
  bool get nobodyInRange => notified == 0 && radiusExhausted;

  /// Everybody asked said no and there is nowhere further to look.
  bool get allSaidNo => notified > 0 && answered == notified && !hasOffers && radiusExhausted;

  bool get canSearchFurther => isOpen && !radiusExhausted;

  /// The radii of the steps, in km (`private.request_radius_km`).
  static const List<double> radiiKm = <double>[1, 3, 5, 10];

  /// The radius "search further" would widen to; null at the largest radius.
  double? get nextRadiusKm => radiusExhausted || step >= radiiKm.length ? null : radiiKm[step < 1 ? 1 : step];

  factory AvailabilityRequest.fromJson(Map<String, dynamic> j) => AvailabilityRequest(
        id: J.str(j['id']),
        status: RequestStatus.parse(J.strOrNull(j['status'])),
        step: J.integer(j['step'], 1),
        radiusKm: J.number(j['radius_km'], 1),
        radiusExhausted: J.boolean(j['radius_exhausted']),
        medicine: Medicine.fromJson(J.map(j['medicine'])),
        notified: J.integer(j['notified']),
        answered: J.integer(j['answered']),
        unavailable: J.integer(j['unavailable']),
        offers: J.list(j['offers']).map(AvailabilityOffer.fromJson).toList(),
        createdAt: J.date(j['created_at']),
        expiresAt: J.date(j['expires_at']),
        secondsLeft: J.integer(j['seconds_left']),
      );
}

/// A row of the customer's request history (`list_my_availability_requests`).
class AvailabilityRequestSummary {
  const AvailabilityRequestSummary({
    required this.id,
    required this.medicine,
    required this.status,
    required this.offersCount,
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final Medicine medicine;
  final RequestStatus status;
  final int offersCount;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  factory AvailabilityRequestSummary.fromJson(Map<String, dynamic> j) => AvailabilityRequestSummary(
        id: J.str(j['id']),
        medicine: Medicine.fromJson(<String, dynamic>{...j, 'id': j['medicine_id']}),
        status: RequestStatus.parse(J.strOrNull(j['status'])),
        offersCount: J.integer(j['offers_count']),
        createdAt: J.date(j['created_at']),
        expiresAt: J.date(j['expires_at']),
      );
}

/// A request in the pharmacist's inbox. It never says who asked or from where: only the medicine and the distance.
class InboxRequest {
  const InboxRequest({
    required this.requestId,
    required this.medicine,
    required this.status,
    this.distanceKm,
    this.createdAt,
    this.expiresAt,
    this.answer,
    this.answerPrice,
    this.answeredAt,
    this.listedPrice,
    this.listedAvailable,
  });

  final String requestId;
  final Medicine medicine;
  final RequestStatus status;
  final double? distanceKm;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// This pharmacy's own answer so far (null = not answered).
  final RequestAnswer? answer;
  final double? answerPrice;
  final DateTime? answeredAt;

  /// The pharmacy's own list entry for this medicine: used to pre-fill the price. Null when not listed yet.
  final double? listedPrice;
  final bool? listedAvailable;

  bool get isOpen => status.isOpen;

  bool get isAnswered => answer != null;

  /// Needs the pharmacist's attention.
  bool get isWaiting => isOpen && !isAnswered;

  /// Time left, or null when the request is not open any more.
  Duration? remaining({DateTime? now}) {
    final DateTime? end = expiresAt;
    if (end == null || !isOpen) return null;
    final Duration d = end.difference(now ?? DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  factory InboxRequest.fromJson(Map<String, dynamic> j) => InboxRequest(
        requestId: J.str(j['request_id']),
        medicine: Medicine.fromJson(<String, dynamic>{...j, 'id': j['medicine_id']}),
        status: RequestStatus.parse(J.strOrNull(j['request_status'])),
        distanceKm: J.numberOrNull(j['distance_km']),
        createdAt: J.date(j['created_at']),
        expiresAt: J.date(j['expires_at']),
        answer: RequestAnswer.parse(J.strOrNull(j['answer'])),
        answerPrice: J.numberOrNull(j['answer_price']),
        answeredAt: J.date(j['answered_at']),
        listedPrice: J.numberOrNull(j['listed_price']),
        listedAvailable: j['listed_available'] == null ? null : J.boolean(j['listed_available']),
      );
}
