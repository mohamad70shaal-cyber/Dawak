import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_reports_controller.dart';
import '../widgets/admin_widgets.dart';

/// Reports tab (A-10): what users reported, newest first; the open ones by default.
class AdminReportsTab extends StatelessWidget {
  const AdminReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminReportsController c = Get.find<AdminReportsController>();
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        FilterChipBar<ReportFilter>(
          values: ReportFilter.values,
          selected: c.filter,
          label: (ReportFilter f) => 'a_report_filter_${f.name}'.tr,
          onSelected: c.setFilter,
        ),
        Expanded(
          child: PagedListView<UserReport>(
            paged: c.paged,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            empty: Obx(() => EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'a_reports_empty'.tr,
                  message: 'a_reports_empty_${c.filter.value.name}'.tr,
                )),
            itemBuilder: (BuildContext context, UserReport r) => ReportTile(report: r, onTap: () => c.openReport(r)),
          ),
        ),
      ],
    );
  }
}

/// A report row: category, a few lines of the description, what it is about and its status.
class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, required this.onTap});

  final UserReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String category = reportCategoryLabel(report.category);
    return Semantics(
      button: true,
      label: '$category, ${report.description}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: Text(category, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                ReportStatusChip(report.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(report.description, style: t.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(Icons.sell_outlined, size: 16, color: p.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text(reportTargetLabel(report.targetType), style: t.bodySmall?.copyWith(color: p.textSecondary))),
                LtrText(Fmt.dateTime(report.createdAt), style: t.labelSmall?.copyWith(color: p.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The category as the reporter chose it (a code such as `order_problem`), in words; unknown codes are shown as sent.
String reportCategoryLabel(String category) => trOr('a_report_cat_$category', category);

String reportTargetLabel(String targetType) => trOr('a_report_target_$targetType', targetType);
