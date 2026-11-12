import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/medicine.dart';
import '../../../data/repositories/medicine_repository.dart';

/// Which catalogue entries the list shows.
enum MedicineFilter {
  all,
  pending,
  approved,
  rejected,
  archived;

  /// The `catalog_status` to ask for, or null for every status.
  String? get status => this == MedicineFilter.all ? null : name;
}

/// The medicine catalogue as administrators manage it (A-07): search, status filter, proposals waiting for review.
/// The editor and the review actions are on the details screen (A-08).
class AdminMedicinesController extends BaseController {
  AdminMedicinesController({MedicineRepository? medicines, Future<Object?> Function(String route)? open})
      : _medicines = medicines ?? Get.find<MedicineRepository>(),
        _open = open ?? ((String r) async=> Get.toNamed<Object?>(r)) {
    paged = Paged<Medicine>(
      fetch: (int offset, int limit) => _medicines.adminList(status: filter.value.status, text: _text, limit: limit, offset: offset),
      pageSize: 30,
    );
  }

  final MedicineRepository _medicines;
  final Future<Object?> Function(String route) _open;

  late final Paged<Medicine> paged;
  final Rx<MedicineFilter> filter = MedicineFilter.all.obs;

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
  void setFilter(MedicineFilter f) {
    if (filter.value == f) {
      paged.reload(silent: true);
      return;
    }
    filter.value = f;
    paged.reload();
  }

  Future<void> refreshList() => paged.reload(silent: true);

  Future<void> openMedicine(Medicine m) async {
    await _open(AppRoutes.adminMedicine(m.id));
  }

  Future<void> openNew() async {
    await _open(AppRoutes.adminMedicineNew);
  }

  Future<void> openImport() async {
    await _open(AppRoutes.adminMedicineImport);
  }
}
