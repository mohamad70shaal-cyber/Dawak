import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/sales_repository.dart';
import '../services/pharmacist_nav.dart';
import '../services/receipt_service.dart';

enum SalesRange { all, today, week, month, custom }

/// Sales history (P-48), with invoice-number search (P-49) and date filters (P-50). Cashiers only receive their own sales
/// (the database filters them); owners and managers see every sale.
class SalesHistoryController extends BaseController {
  SalesHistoryController({SalesRepository? sales, SessionService? session, DateTime Function()? clock, Future<Object?> Function(String route)? open})
      : _sales = sales ?? Get.find<SalesRepository>(),
        _session = session ?? Get.find<SessionService>(),
        _clock = clock ?? DateTime.now,
        _open = open ?? ((String r)async => Get.toNamed<Object?>(r)) {
    paged = Paged<SaleSummary>(
      fetch: (int offset, int limit) {
        final ({DateTime? from, DateTime? to}) r = window;
        return _sales.history(pharmacyId, from: r.from, to: r.to, invoiceQuery: _query, limit: limit, offset: offset);
      },
      pageSize: 30,
    );
  }

  final SalesRepository _sales;
  final SessionService _session;
  final DateTime Function() _clock;
  final Future<Object?> Function(String route) _open;

  late final Paged<SaleSummary> paged;
  final Rx<SalesRange> range = SalesRange.all.obs;

  String _query = '';
  DateTime? _customFrom;
  DateTime? _customTo;

  String get pharmacyId => _session.pharmacy?.id ?? '';

  bool get isCashier => !_session.snapshot.canManagePharmacy;

  DateTime? get customFrom => _customFrom;
  DateTime? get customTo => _customTo;

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

  /// `[from, to)` for the current chip, in device-local midnights (null = unbounded). The week starts on Saturday.
  ({DateTime? from, DateTime? to}) get window {
    final DateTime n = _clock();
    final DateTime today = DateTime(n.year, n.month, n.day);
    final DateTime tomorrow = DateTime(n.year, n.month, n.day + 1);
    switch (range.value) {
      case SalesRange.all:
        return (from: null, to: null);
      case SalesRange.today:
        return (from: today, to: tomorrow);
      case SalesRange.week:
        return (from: today.subtract(Duration(days: (today.weekday + 1) % 7)), to: tomorrow);
      case SalesRange.month:
        return (from: DateTime(n.year, n.month, 1), to: tomorrow);
      case SalesRange.custom:
        final DateTime f = _customFrom ?? today;
        final DateTime t = _customTo ?? today;
        return (from: f, to: DateTime(t.year, t.month, t.day + 1));
    }
  }

  void search(String text) {
    final String t = text.trim();
    if (t == _query) return;
    _query = t;
    paged.reload();
  }

  void select(SalesRange r) {
    if (r == SalesRange.custom || range.value == r) return;
    range.value = r;
    paged.reload();
  }

  /// False when the dates are reversed.
  bool setCustom(DateTime from, DateTime to) {
    final DateTime f = DateTime(from.year, from.month, from.day);
    final DateTime t = DateTime(to.year, to.month, to.day);
    if (f.isAfter(t)) return false;
    _customFrom = f;
    _customTo = t;
    range.value = SalesRange.custom;
    paged.reload();
    return true;
  }

  Future<void> openSale(SaleSummary s) async {
    await _open(AppRoutes.sale(s.id));
  }
}

/// A completed sale with its receipt (P-43 / P-51), plus PDF share and print (P-44, P-45, P-52).
class SaleDetailsController extends BaseController {
  SaleDetailsController({String? saleId, SalesRepository? sales, ReceiptService? receipts, void Function(String route)? open})
      : _saleId = saleId,
        _sales = sales ?? Get.find<SalesRepository>(),
        _receipts = receipts ?? Get.find<ReceiptService>(),
        _open = open ?? ((String r) => Get.toNamed<dynamic>(r));

  final String? _saleId;
  final SalesRepository _sales;
  final ReceiptService _receipts;
  final void Function(String route) _open;

  final Rxn<Sale> sale = Rxn<Sale>();
  final RxBool working = false.obs;

  String get id => _saleId ?? Get.parameters['id'] ?? Get.parameters['saleId'] ?? '';

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  Future<void> refresh({bool silent = false}) => load(() async {
        sale.value = await _sales.getSale(id);
      }, silent: silent);

  Future<bool> sharePdf() => _output(() => _receipts.share(sale.value!));

  Future<bool> printReceipt() => _output(() => _receipts.printReceipt(sale.value!));

  Future<bool> _output(Future<void> Function() job) async {
    if (sale.value == null || working.value) return false;
    working.value = true;
    try {
      await job();
      return true;
    } catch (_) {
      AppToast.error('p_receipt_failed'.tr);
      return false;
    } finally {
      working.value = false;
    }
  }

  /// A sale that came from a reservation links back to that order.
  void openOrder() {
    final String? o = sale.value?.orderId;
    if (o != null) _open(AppRoutes.pharmacistOrder(o));
  }
}

/// "Sale completed" screen (P-42, P-46). It loads the sale by id, so it also works after an app restart.
class PosCompletedController extends BaseController {
  PosCompletedController({String? saleId, SalesRepository? sales, void Function()? startNew, void Function(String route)? open})
      : _saleId = saleId,
        _sales = sales ?? Get.find<SalesRepository>(),
        _startNew = startNew ?? PharmacistNav.openPos,
        _open = open ?? ((String r) => Get.toNamed<dynamic>(r));

  final String? _saleId;
  final SalesRepository _sales;
  final void Function() _startNew;
  final void Function(String route) _open;

  final Rxn<Sale> sale = Rxn<Sale>();

  String get id => _saleId ?? Get.parameters['saleId'] ?? '';

  @override
  void onReady() {
    super.onReady();
    refresh();
  }

  Future<void> refresh() => load(() async {
        sale.value = await _sales.getSale(id);
      });

  void openReceipt() => _open(AppRoutes.sale(id));

  /// The basket was emptied when the sale was confirmed; this goes back to the counter.
  void newSale() => _startNew();
}
