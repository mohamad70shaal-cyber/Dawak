import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/enums.dart';
import '../../../data/repositories/availability_repository.dart';
import 'pharmacist_badge_controller.dart';

/// Answers one customer request (P-33): "available" with a price, or "unavailable". The price is pre-filled from the
/// pharmacy's own list; an answer can be changed while the request is open. Owners and managers: the answer also updates
/// the pharmacy's list (server side). Cashiers: the answer only answers.
class AvailabilityAnswerController extends BaseController {
  AvailabilityAnswerController({
    String? requestId,
    Object? initial,
    AvailabilityRepository? availability,
    SessionService? session,
    void Function()? close,
  })  : _requestId = requestId,
        _initial = initial,
        _availability = availability ?? Get.find<AvailabilityRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _close = close ?? (() => Get.back<dynamic>(result: true));

  final String? _requestId;
  final Object? _initial;
  final AvailabilityRepository _availability;
  final SessionService _session;
  final void Function() _close;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController price = TextEditingController();
  final Rxn<InboxRequest> request = Rxn<InboxRequest>();

  String get id => _requestId ?? Get.parameters['id'] ?? '';

  String get pharmacyId => _session.pharmacy?.id ?? '';

  String get currency => _session.pharmacy?.currency ?? 'SYP';

  /// Owners and managers: their answers also update the pharmacy's list.
  bool get updatesList => _session.snapshot.canManagePharmacy;

  /// False once the request was closed or expired: it can be read but no longer answered.
  bool get canAnswer {
    final InboxRequest? r = request.value;
    if (r == null || !r.isOpen) return false;
    final Duration? left = r.remaining();
    return left == null || left > Duration.zero;
  }

  @override
  void onInit() {
    super.onInit();
    final Object? seed = _initial ?? Get.arguments;
    if (seed is InboxRequest && seed.requestId == id) {
      _set(seed);
      status.value = ViewStatus.ready;
    }
  }

  @override
  void onReady() {
    super.onReady();
    refresh(silent: request.value != null);
  }

  @override
  void onClose() {
    price.dispose();
    super.onClose();
  }

  /// The inbox is the only source (the pharmacy cannot read the request tables), so the request is found in it by id.
  Future<void> refresh({bool silent = false}) => load(() async {
        final List<InboxRequest> list = await _availability.inbox(pharmacyId, onlyOpen: false, limit: 50);
        InboxRequest? found;
        for (final InboxRequest r in list) {
          if (r.requestId == id) found = r;
        }
        if (found == null) {
          if (request.value != null && silent) return; // keep what the inbox showed
          throw const AppFailure('not_found');
        }
        _set(found);
      }, silent: silent);

  void _set(InboxRequest r) {
    final bool first = request.value == null;
    request.value = r;
    // Do not overwrite a price the pharmacist is typing.
    if (first || price.text.isEmpty) {
      final double? p = r.answer == RequestAnswer.available ? r.answerPrice : r.listedPrice;
      if (p != null) price.text = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString();
    }
  }

  Future<bool> answerAvailable() async {
    final InboxRequest? r = request.value;
    if (r == null || submitting.value || !canAnswer) return false;
    if (!(form.currentState?.validate() ?? false)) return false;
    final double? value = Validators.parseDecimal(price.text);
    if (value == null || value <= 0) return false;
    return _send(r, available: true, price: value);
  }

  Future<bool> answerUnavailable() async {
    final InboxRequest? r = request.value;
    if (r == null || submitting.value || !canAnswer) return false;
    return _send(r, available: false);
  }

  Future<bool> _send(InboxRequest r, {required bool available, double? price}) async {
    final bool? ok = await submit<bool>(() async {
      await _availability.answer(pharmacyId: pharmacyId, requestId: r.requestId, available: available, price: price);
      return true;
    });
    if (ok == null) {
      final AppFailure? f = failure.value;
      if (f != null && (f.code == 'request_closed' || f.code == 'not_found')) await refresh(silent: true);
      return false;
    }
    AppToast.success((available ? 'p_req_answered_available' : 'p_req_answered_unavailable').tr);
    if (Get.isRegistered<PharmacistBadgeController>()) {
      Get.find<PharmacistBadgeController>().refreshRequests();
    }
    _close();
    return true;
  }
}
