import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/base/paged.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/admin_repository.dart';

/// Groups of audit actions for the filter chips.
enum AuditGroup {
  all(null),
  pharmacies(<String>[
    'pharmacy_registered',
    'pharmacy_resubmitted',
    'pharmacy_updated',
    'pharmacy_approve',
    'pharmacy_reject',
    'pharmacy_suspend',
    'pharmacy_reinstate',
  ]),
  accounts(<String>['account_suspended', 'account_active']),
  catalogue(<String>['medicine_approve', 'medicine_reject', 'medicine_archive']),
  reports(<String>['report_in_review', 'report_resolved', 'report_dismissed']),
  inventory(<String>[
    'product_added',
    'product_updated',
    'listing_confirmed',
    'products_imported',
    'sale_discount',
  ]);

  const AuditGroup(this.actions);

  /// The action names of the group; null = every action.
  final List<String>? actions;
}

/// The audit log (A-13): who did what and when, newest first, read-only. Names of the people behind the entries are
/// looked up in one extra query per page (customers are not visible to administrators, so some entries show no name).
class AdminAuditLogsController extends BaseController {
  AdminAuditLogsController({AdminRepository? admin}) : _admin = admin ?? Get.find<AdminRepository>() {
    paged = Paged<AuditLogEntry>(
      fetch: (int offset, int limit) async {
        final List<AuditLogEntry> page = await _admin.auditLog(actions: group.value.actions, limit: limit, offset: offset);
        await _resolveNames(page);
        return page;
      },
      pageSize: 40,
    );
  }

  final AdminRepository _admin;

  late final Paged<AuditLogEntry> paged;
  final Rx<AuditGroup> group = AuditGroup.all.obs;

  /// actor id → display name, for the entries loaded so far.
  final RxMap<String, String> names = <String, String>{}.obs;

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

  void setGroup(AuditGroup g) {
    if (group.value == g) return;
    group.value = g;
    paged.reload();
  }

  /// Ids already asked for (also the ones that came back without a name), so a page is never looked up twice.
  final Set<String> _asked = <String>{};

  Future<void> _resolveNames(List<AuditLogEntry> page) async {
    final List<String> missing = page
        .map((AuditLogEntry e) => e.actorId ?? '')
        .where((String id) => id.isNotEmpty && !_asked.contains(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    try {
      names.addAll(await _admin.names(missing));
      _asked.addAll(missing);
    } catch (_) {
      // The names are a convenience: without them the entry shows only the action. Asked again with the next page.
    }
  }

  /// Who did it: the name when known, otherwise nothing (the system, or a customer the admin cannot see).
  String actorName(AuditLogEntry e) {
    final String? id = e.actorId;
    return id == null ? '' : (names[id] ?? '');
  }

  /// The reason the entry carries, when it has one.
  String reasonOf(AuditLogEntry e) {
    final Object? r = e.details['reason'];
    return r is String ? r.trim() : '';
  }
}
