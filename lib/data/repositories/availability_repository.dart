import '../datasources/api_client.dart';
import '../models/availability.dart';
import '../models/geo.dart';
import '../models/json_utils.dart';

/// "Ask the pharmacies nearby": the customer's requests and the pharmacist's inbox. Every call is an RPC; the tables
/// behind it have no client access, so pharmacies never see who asked or from where.
class AvailabilityRepository {
  AvailabilityRepository(this._api);

  final ApiClient _api;

  // ---- customer ------------------------------------------------------------------------------------------

  /// Starts a request (or returns the customer's still-open request for the same medicine and place). The server asks
  /// the pharmacies within 1 km first and widens by itself. [idempotencyKey] makes a retry harmless.
  Future<AvailabilityRequest> create({required String medicineId, required GeoPoint from, required String idempotencyKey}) async {
    final dynamic r = await _api.rpc('create_availability_request', <String, dynamic>{
      'p_medicine_id': medicineId,
      'p_latitude': from.latitude,
      'p_longitude': from.longitude,
      'p_idempotency_key': idempotencyKey,
    });
    return AvailabilityRequest.fromJson(J.map(r));
  }

  /// Polled by the results screen; the server also applies the widening and expiry rules on every read.
  Future<AvailabilityRequest> get(String requestId) async =>
      AvailabilityRequest.fromJson(J.map(await _api.rpc('get_availability_request', <String, dynamic>{'p_request_id': requestId})));

  /// "Search further": widens the radius by one step (1 → 3 → 5 → 10 km). `invalid_transition` at the largest radius,
  /// `request_closed` when the customer already closed it.
  Future<AvailabilityRequest> expand(String requestId) async =>
      AvailabilityRequest.fromJson(J.map(await _api.rpc('expand_availability_request', <String, dynamic>{'p_request_id': requestId})));

  Future<AvailabilityRequest> close(String requestId) async =>
      AvailabilityRequest.fromJson(J.map(await _api.rpc('close_availability_request', <String, dynamic>{'p_request_id': requestId})));

  Future<List<AvailabilityRequestSummary>> mine({int limit = 20, int offset = 0}) async {
    final dynamic r = await _api.rpc('list_my_availability_requests', <String, dynamic>{'p_limit': limit, 'p_offset': offset});
    return J.list(r).map(AvailabilityRequestSummary.fromJson).toList();
  }

  // ---- pharmacy ------------------------------------------------------------------------------------------

  /// Requests waiting for this pharmacy's answer (badge on the pharmacist tabs).
  Future<int> openCount(String pharmacyId) async {
    final dynamic r = await _api.rpc('count_pharmacy_availability_requests', <String, dynamic>{'p_pharmacy_id': pharmacyId});
    return J.integer(r);
  }

  /// [onlyOpen] = the live inbox (unanswered first); otherwise the last seven days including closed ones.
  Future<List<InboxRequest>> inbox(String pharmacyId, {bool onlyOpen = true, int limit = 30, int offset = 0}) async {
    final dynamic r = await _api.rpc('list_pharmacy_availability_requests', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_only_open': onlyOpen,
      'p_limit': limit,
      'p_offset': offset,
    });
    return J.list(r).map(InboxRequest.fromJson).toList();
  }

  /// "Available" needs a price; "unavailable" sends none. May be repeated while the request is open. Answers of owners and
  /// managers also update the pharmacy's list; a cashier's answer only answers.
  Future<void> answer({required String pharmacyId, required String requestId, required bool available, double? price}) async {
    await _api.rpc('answer_availability_request', <String, dynamic>{
      'p_pharmacy_id': pharmacyId,
      'p_request_id': requestId,
      'p_available': available,
      'p_price': available ? price : null,
    });
  }
}
