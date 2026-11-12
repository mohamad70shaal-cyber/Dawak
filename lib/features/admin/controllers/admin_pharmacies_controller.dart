import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/pharmacy_repository.dart';

/// Which pharmacies the list shows. [all] is every status.
enum PharmacyFilter {
  pending,
  approved,
  suspended,
  rejected,
  all;

  /// The `approval_status` to ask for, or null for every status.
  String? get status => this == PharmacyFilter.all ? null : name;
}

/// Pharmacy applications and the list of all pharmacies (A-03, A-06). Opening one goes to its details (A-04),
/// where the review actions live; the lists refresh themselves through `AdminRefresh` when something changed.
class AdminPharmaciesController extends BaseController {
  AdminPharmaciesController({PharmacyRepository? pharmacies, Future<Object?> Function(String route)? open})
      : _pharmacies = pharmacies ?? Get.find<PharmacyRepository>(),
        _open = open ?? ((String r)async => Get.toNamed<Object?>(r)) {
    paged = Paged<PharmacyApplication>(
      fetch: (int offset, int limit) => _pharmacies.adminList(status: filter.value.status, text: _text, limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  final PharmacyRepository _pharmacies;
  final Future<Object?> Function(String route) _open;

  late final Paged<PharmacyApplication> paged;
  final Rx<PharmacyFilter> filter = PharmacyFilter.pending.obs;

  String _text = '';

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onReady() {
    super.onReady();
    paged.reload();
  }

  void search(String text) {
    final String t = text.trim();
    if (t == _text) return;
    _text = t;
    paged.reload();
  }

  /// Choosing the filter that is already active just re-reads the list (it may be stale).
  void setFilter(PharmacyFilter f) {
    if (filter.value == f) {
      paged.reload(silent: true);
      return;
    }
    filter.value = f;
    paged.reload();
  }

  Future<void> refreshList() => paged.reload(silent: true);

  Future<void> openDetails(PharmacyApplication a) async {
    await _open(AppRoutes.adminPharmacy(a.pharmacy.id));
  }
}
