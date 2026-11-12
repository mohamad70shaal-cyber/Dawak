import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_dashboard_controller.dart';
import '../widgets/admin_widgets.dart';

/// Dashboard tab (A-02): what needs attention first, then the platform in numbers.
class AdminDashboardTab extends StatelessWidget {
  const AdminDashboardTab({super.key});

  static String _n(int v) => Fmt.number(v);

  @override
  Widget build(BuildContext context) {
    final AdminDashboardController c = Get.find<AdminDashboardController>();
    return AsyncStateView.of(
      c,
      onRetry: c.refresh,
      builder: (BuildContext context) => RefreshIndicator(
        onRefresh: () => c.refresh(silent: true),
        child: Obx(() {
          final AdminMetrics? m = c.metrics.value;
          if (m == null) return const SizedBox.shrink();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _Attention(c: c, m: m),
              const SizedBox(height: 16),
              SectionCard(
                title: 'a_dash_pharmacies'.tr,
                icon: Icons.local_pharmacy_outlined,
                trailing: TextButton(onPressed: c.openAllPharmacies, child: Text('view_all'.tr)),
                child: StatGrid(children: <Widget>[
                  StatCard(label: 'a_dash_ph_approved'.tr, value: _n(m.approvedPharmacies), icon: Icons.verified_rounded, color: AppColors.success),
                  StatCard(label: 'a_dash_ph_pending'.tr, value: _n(m.pendingPharmacies), icon: Icons.hourglass_top_rounded, color: AppColors.warning),
                  StatCard(label: 'a_dash_ph_suspended'.tr, value: _n(m.suspendedPharmacies), icon: Icons.pause_circle_rounded, color: AppColors.error),
                  StatCard(label: 'a_dash_ph_rejected'.tr, value: _n(m.rejectedPharmacies), icon: Icons.cancel_rounded, color: AppColors.error),
                ]),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'a_dash_users'.tr,
                icon: Icons.groups_outlined,
                child: StatGrid(children: <Widget>[
                  StatCard(label: 'a_dash_customers'.tr, value: _n(m.customers), icon: Icons.person_outline_rounded),
                  StatCard(label: 'a_dash_pharmacists'.tr, value: _n(m.pharmacists), icon: Icons.badge_outlined, color: AppColors.secondary),
                  StatCard(label: 'a_dash_suspended_users'.tr, value: _n(m.suspendedUsers), icon: Icons.person_off_outlined, color: AppColors.error),
                ]),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'a_dash_catalogue'.tr,
                icon: Icons.medication_outlined,
                trailing: TextButton(onPressed: c.openApprovedMedicines, child: Text('view_all'.tr)),
                child: StatGrid(children: <Widget>[
                  StatCard(label: 'a_dash_med_approved'.tr, value: _n(m.approvedMedicines), icon: Icons.verified_rounded, color: AppColors.success),
                  StatCard(label: 'a_dash_med_pending'.tr, value: _n(m.pendingMedicines), icon: Icons.hourglass_top_rounded, color: AppColors.warning),
                ]),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'a_dash_activity'.tr,
                icon: Icons.insights_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('a_dash_activity_hint'.tr, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary)),
                    const SizedBox(height: 12),
                    StatGrid(children: <Widget>[
                      StatCard(label: 'a_dash_orders'.tr, value: _n(m.orders30d), icon: Icons.inventory_2_outlined),
                      StatCard(label: 'a_dash_orders_completed'.tr, value: _n(m.completedOrders30d), icon: Icons.task_alt_rounded, color: AppColors.success),
                      StatCard(label: 'a_dash_orders_lost'.tr, value: _n(m.cancelledOrRejected30d), icon: Icons.block_rounded, color: AppColors.error),
                      StatCard(label: 'a_dash_sales'.tr, value: _n(m.sales30d), icon: Icons.point_of_sale_rounded, color: AppColors.secondary),
                    ]),
                    if (m.orders30d > 0) ...<Widget>[
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(child: Text('a_dash_completion'.tr, style: Theme.of(context).textTheme.bodyMedium)),
                          LtrText('${(c.completionRate * 100).round()}%', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({required this.c, required this.m});

  final AdminDashboardController c;
  final AdminMetrics m;

  @override
  Widget build(BuildContext context) {
    if (c.needsAttention == 0) {
      return NoticeBanner('a_dash_all_clear'.tr, kind: NoticeKind.success);
    }
    return SectionCard(
      title: 'a_dash_attention'.tr,
      icon: Icons.notifications_active_outlined,
      child: Column(
        children: <Widget>[
          if (m.pendingPharmacies > 0)
            _Row(icon: Icons.local_pharmacy_outlined, label: 'a_dash_attn_pharmacies'.tr, count: m.pendingPharmacies, onTap: c.openPendingPharmacies),
          if (m.pendingMedicines > 0)
            _Row(icon: Icons.medication_outlined, label: 'a_dash_attn_medicines'.tr, count: m.pendingMedicines, onTap: c.openPendingMedicines),
          if (m.openReports > 0) _Row(icon: Icons.flag_outlined, label: 'a_dash_attn_reports'.tr, count: m.openReports, onTap: c.openOpenReports),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.count, required this.onTap});

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Semantics(
      button: true,
      label: '$label: $count',
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: p.primaryText),
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.tint(AppColors.warning, alpha: 0.2), borderRadius: BorderRadius.circular(20)),
              child: LtrText('$count', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, textDirection: TextDirection.ltr), 
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
