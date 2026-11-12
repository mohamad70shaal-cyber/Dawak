import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/services/session_service.dart';
import '../../../data/models/dashboard.dart';
import '../../../data/repositories/dashboard_repository.dart';
import '../pharmacist_tabs.dart';
import 'products_controller.dart';

enum DashRange { today, week, last10, month, custom }

/// Owner/manager dashboard (P-10 … P-20). Figures come from completed sales only (the server computes them).
/// The four period cards are fixed (today, week since Saturday, last 10 days, month); the date chips choose the
/// range of the trend chart, the best sellers and the transaction count.
class DashboardController extends BaseController {
  DashboardController({DashboardRepository? dashboard, SessionService? session, DateTime Function()? clock})
      : _dashboard = dashboard ?? Get.find<DashboardRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _clock = clock ?? DateTime.now;

  final DashboardRepository _dashboard;
  final SessionService _session;
  final DateTime Function() _clock;

  final Rx<DashRange> range = DashRange.last10.obs;
  final Rxn<DashboardData> data = Rxn<DashboardData>();

  DateTime? _customFrom;
  DateTime? _customTo;
  int _generation = 0;

  String get pharmacyId => _session.pharmacy?.id ?? '';

  String get currency => data.value?.currency ?? _session.pharmacy?.currency ?? 'SYP';

  /// Longest range the server accepts.
  static const int maxDays = 366;

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  DateTime _today() {
    final DateTime n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  /// The calendar days the current chip stands for. The week starts on Saturday.
  ({DateTime from, DateTime to}) get currentRange {
    final DateTime today = _today();
    switch (range.value) {
      case DashRange.today:
        return (from: today, to: today);
      case DashRange.week:
        final int sinceSaturday = (today.weekday + 1) % 7;
        return (from: today.subtract(Duration(days: sinceSaturday)), to: today);
      case DashRange.last10:
        return (from: today.subtract(const Duration(days: 9)), to: today);
      case DashRange.month:
        return (from: DateTime(today.year, today.month, 1), to: today);
      case DashRange.custom:
        return (from: _customFrom ?? today, to: _customTo ?? today);
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final int gen = ++_generation;
    final ({DateTime from, DateTime to}) r = currentRange;
    await load(() async {
      final DashboardData d = await _dashboard.load(pharmacyId, from: r.from, to: r.to);
      if (gen != _generation) return;
      data.value = d;
    }, silent: silent);
  }

  void select(DashRange r) {
    if (r == DashRange.custom) return; // custom needs dates: use setCustom
    if (range.value == r && data.value != null) return;
    range.value = r;
    refresh(silent: data.value != null);
  }

  /// Returns false (and changes nothing) when the dates are reversed or span more than a year.
  Future<bool> setCustom(DateTime from, DateTime to) async {
    final DateTime f = DateTime(from.year, from.month, from.day);
    final DateTime t = DateTime(to.year, to.month, to.day);
    if (f.isAfter(t) || t.difference(f).inDays >= maxDays) return false;
    _customFrom = f;
    _customTo = t;
    range.value = DashRange.custom;
    await refresh(silent: data.value != null);
    return true;
  }

  // ---- the medicine list card (P-18) ----------------------------------------------------------------------

  /// Opens the "my medicines" tab.
  void openList() => PharmacistTabs.go(PharmacistTab.products);

  /// Opens the "my medicines" tab filtered to available items that were not confirmed for a week.
  void openStale() {
    if (Get.isRegistered<ProductsController>()) Get.find<ProductsController>().setFilter(ProductFilter.stale);
    PharmacistTabs.go(PharmacistTab.products);
  }

  /// "My list is still correct": confirms every available medicine (asks first), then re-reads the figures.
  Future<void> confirmList() async {
    if (!Get.isRegistered<ProductsController>()) return;
    final int? n = await Get.find<ProductsController>().confirmListing();
    if (n != null) await refresh(silent: true);
  }

  DateTime? get customFrom => _customFrom;
  DateTime? get customTo => _customTo;
}
