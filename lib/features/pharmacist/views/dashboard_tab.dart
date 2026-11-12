import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/bar_chart.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/dashboard.dart';
import '../controllers/dashboard_controller.dart';
import '../pharmacist_tabs.dart';

/// Dashboard tab (P-10): money figures, trend, best sellers, the state of the medicine list and recent orders.
class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController c = Get.find<DashboardController>();
    return AsyncStateView.of(
      c,
      onRetry: c.refresh,
      builder: (BuildContext context) => RefreshIndicator(
        onRefresh: () => c.refresh(silent: true),
        child: Obx(() {
          final DashboardData? d = c.data.value;
          if (d == null) return const SizedBox.shrink();
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _PeriodCards(d: d),
              const SizedBox(height: 16),
              _RangeChips(c: c),
              const SizedBox(height: 12),
              _TrendCard(c: c, d: d),
              const SizedBox(height: 12),
              _AlertsRow(d: d),
              const SizedBox(height: 12),
              _BestSellers(d: d),
              const SizedBox(height: 12),
              _ListStatus(c: c, d: d),
              const SizedBox(height: 12),
              _RecentOrders(d: d),
            ],
          );
        }),
      ),
    );
  }
}

class _PeriodCards extends StatelessWidget {
  const _PeriodCards({required this.d});

  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      StatCard(label: 'p_dash_today'.tr, value: Fmt.money(d.today.total, d.currency), icon: Icons.today_rounded, caption: 'p_dash_sales_count'.trParams(<String, String>{'n': '${d.today.count}'})),
      StatCard(label: 'p_dash_week'.tr, value: Fmt.money(d.week.total, d.currency), icon: Icons.date_range_rounded, color: AppColors.secondary, caption: 'p_dash_sales_count'.trParams(<String, String>{'n': '${d.week.count}'})),
      StatCard(label: 'p_dash_10days'.tr, value: Fmt.money(d.last10Days.total, d.currency), icon: Icons.calendar_view_week_rounded, caption: 'p_dash_sales_count'.trParams(<String, String>{'n': '${d.last10Days.count}'})),
      StatCard(label: 'p_dash_month'.tr, value: Fmt.money(d.month.total, d.currency), icon: Icons.calendar_month_rounded, color: AppColors.secondary, caption: 'p_dash_sales_count'.trParams(<String, String>{'n': '${d.month.count}'})),
    ];
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final double w = (box.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[for (final Widget c in cards) SizedBox(width: w, child: c)],
      );
    });
  }
}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.c});

  final DashboardController c;

  Future<void> _pickCustom(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: DateTimeRange(start: c.currentRange.from, end: c.currentRange.to),
    );
    if (r != null) await c.setCustom(r.start, r.end);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final DashRange cur = c.range.value;
      Widget chip(String label, DashRange r, {VoidCallback? onTap}) => ChoiceChip(
            label: Text(label),
            selected: cur == r,
            onSelected: (bool _) => onTap != null ? onTap() : c.select(r),
          );
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: <Widget>[
          chip('today'.tr, DashRange.today),
          chip('this_week'.tr, DashRange.week),
          chip('last_10_days'.tr, DashRange.last10),
          chip('this_month'.tr, DashRange.month),
          chip(
            cur == DashRange.custom && c.customFrom != null
                ? '${Fmt.date(c.customFrom)} – ${Fmt.date(c.customTo)}'
                : 'custom_range'.tr,
            DashRange.custom,
            onTap: () => _pickCustom(context),
          ),
        ],
      );
    });
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.c, required this.d});

  final DashboardController c;
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final List<DailyPoint> series = d.dailySeries;
    return SectionCard(
      title: 'p_dash_trend'.tr,
      icon: Icons.show_chart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('p_dash_range_total'.tr, style: t.labelMedium?.copyWith(color: p.textSecondary)),
                    LtrText(Fmt.money(d.range.total, d.currency), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('p_dash_transactions'.tr, style: t.labelMedium?.copyWith(color: p.textSecondary)),
                  Text('${d.range.count}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (series.isEmpty || d.range.count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('p_dash_no_sales'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary))),
            )
          else
            BarChart(
              values: series.map((DailyPoint e) => e.total).toList(),
              labels: series.map((DailyPoint e) => '${e.day.day}/${e.day.month}').toList(),
              valueFormatter: (double v) => Fmt.number(v),
              semanticsLabel: 'p_dash_chart_label'.trParams(<String, String>{'days': '${series.length}', 'total': Fmt.money(d.range.total, d.currency)}),
            ),
        ],
      ),
    );
  }
}

class _AlertsRow extends StatelessWidget {
  const _AlertsRow({required this.d});

  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _AlertTile(
            icon: Icons.pending_actions_rounded,
            color: AppColors.warning,
            label: 'p_dash_pending_orders'.tr,
            count: d.pendingOrdersCount,
            onTap: () => PharmacistTabs.go(PharmacistTab.orders),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _AlertTile(
            icon: Icons.mark_chat_unread_outlined,
            color: AppColors.primary,
            label: 'p_dash_open_requests'.tr,
            count: d.openRequestsCount,
            onTap: () => Get.toNamed<dynamic>(AppRoutes.pharmacistRequests),
          ),
        ),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.icon, required this.color, required this.label, required this.count, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$label: $count',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
            Text('$count', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _BestSellers extends StatelessWidget {
  const _BestSellers({required this.d});

  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return SectionCard(
      title: 'p_dash_best'.tr,
      icon: Icons.emoji_events_rounded,
      child: d.bestSellers.isEmpty
          ? Text('p_dash_no_sales'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary))
          : Column(
              children: <Widget>[
                for (int i = 0; i < d.bestSellers.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: 28, child: Text('${i + 1}', style: t.titleSmall?.copyWith(color: p.textSecondary))),
                        Expanded(child: Text(d.bestSellers[i].name, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text('p_dash_units'.trParams(<String, String>{'n': '${d.bestSellers[i].quantity}'}), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                            LtrText(Fmt.money(d.bestSellers[i].revenue, d.currency), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// "My medicines": how many are available / unavailable and how many were not confirmed for a week (P-18).
class _ListStatus extends StatelessWidget {
  const _ListStatus({required this.c, required this.d});

  final DashboardController c;
  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final ListingSummary l = d.listing;
    return SectionCard(
      title: 'p_dash_list_title'.tr,
      icon: Icons.medication_outlined,
      trailing: TextButton(onPressed: c.openList, child: Text('view_all'.tr)),
      child: l.total == 0
          ? Text('p_dash_list_empty'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    StatusChip(
                      label: 'p_dash_list_available'.trParams(<String, String>{'n': '${l.available}'}),
                      color: AppColors.success,
                      icon: Icons.check_circle_rounded,
                    ),
                    StatusChip(
                      label: 'p_dash_list_unavailable'.trParams(<String, String>{'n': '${l.unavailable}'}),
                      color: AppColors.textSecondary,
                      icon: Icons.remove_circle_outline_rounded,
                    ),
                  ],
                ),
                if (l.stale > 0) ...<Widget>[
                  const SizedBox(height: 12),
                  NoticeBanner('p_dash_list_stale'.trParams(<String, String>{'n': '${l.stale}'}), kind: NoticeKind.warning),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppButton(
                          label: 'p_dash_list_confirm'.tr,
                          icon: Icons.fact_check_outlined,
                          onPressed: c.confirmList,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: c.openStale, child: Text('p_dash_list_review'.tr)),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.d});

  final DashboardData d;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return SectionCard(
      title: 'p_dash_recent_orders'.tr,
      icon: Icons.receipt_long_rounded,
      trailing: TextButton(onPressed: () => PharmacistTabs.go(PharmacistTab.orders), child: Text('view_all'.tr)),
      child: d.recentOrders.isEmpty
          ? Text('p_dash_no_orders'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary))
          : Column(
              children: <Widget>[
                for (final RecentOrder o in d.recentOrders)
                  InkWell(
                    onTap: () => Get.toNamed<dynamic>(AppRoutes.pharmacistOrder(o.id)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                LtrText(o.publicRef, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                Text(o.customerName.isEmpty ? Fmt.dateTime(o.createdAt) : '${o.customerName} · ${Fmt.dateTime(o.createdAt)}',
                                    style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              OrderStatusChip(o.status),
                              const SizedBox(height: 4),
                              LtrText(Fmt.money(o.subtotal, o.currency), style: t.bodySmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
