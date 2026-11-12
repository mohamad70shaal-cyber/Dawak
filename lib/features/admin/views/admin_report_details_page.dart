import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_report_details_controller.dart';
import '../widgets/admin_widgets.dart';
import 'admin_reports_tab.dart';

/// Report review (A-11): the report in full, a link to what it is about, and the decision buttons.
class AdminReportDetailsPage extends StatelessWidget {
  const AdminReportDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final AdminReportDetailsController c = Get.find<AdminReportDetailsController>(tag: id);
    return Scaffold(
      appBar: AppBar(title: Text('a_report_details'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: () => c.refresh(silent: true),
          child: Obx(() {
            final UserReport? r = c.report.value;
            if (r == null) return const SizedBox.shrink();
            return _Body(c: c, r: r);
          }),
        ),
      ),
      bottomNavigationBar: Obx(() {
        if (c.report.value == null) return const SizedBox.shrink();
        final Widget? bar = _actions(c);
        return bar == null ? const SizedBox.shrink() : BottomActionBar(child: bar);
      }),
    );
  }

  Widget? _actions(AdminReportDetailsController c) {
    final bool busy = c.submitting.value;
    if (!c.canResolve) return null;
    final Widget decide = Row(
      children: <Widget>[
        Expanded(child: AppButton(label: 'a_report_dismiss'.tr, variant: AppButtonVariant.secondary, onPressed: busy ? null : c.dismiss)),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: AppButton(label: 'a_report_resolve'.tr, icon: Icons.task_alt_rounded, loading: busy, onPressed: c.resolve)),
      ],
    );
    if (!c.canStartReview) return decide;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AppButton(label: 'a_report_start_review'.tr, icon: Icons.visibility_rounded, variant: AppButtonVariant.text, onPressed: busy ? null : c.startReview),
        const SizedBox(height: 4),
        decide,
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c, required this.r});

  final AdminReportDetailsController c;
  final UserReport r;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String? note = r.resolutionNote;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Obx(() => c.notice.value == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(c.notice.value!, kind: NoticeKind.warning))),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text(reportCategoryLabel(r.category), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 8),
                  ReportStatusChip(r.status),
                ],
              ),
              const SizedBox(height: 12),
              Text(r.description, style: t.bodyLarge),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'a_report_about'.tr,
          icon: Icons.sell_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InfoRow(label: 'a_report_target'.tr, value: reportTargetLabel(r.targetType)),
              InfoRow(label: 'a_report_sent'.tr, value: Fmt.dateTime(r.createdAt), ltr: true),
              if (c.targetRoute != null) ...<Widget>[
                const SizedBox(height: 8),
                AppButton(
                  label: (r.targetType == 'pharmacy' ? 'a_report_open_pharmacy' : 'a_report_open_medicine').tr,
                  icon: Icons.open_in_new_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: c.openTarget,
                ),
              ],
            ],
          ),
        ),
        if (note != null && note.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: 'a_report_note_title'.tr,
            icon: Icons.sticky_note_2_outlined,
            child: Text(note, style: t.bodyMedium?.copyWith(color: p.text)),
          ),
        ],
      ],
    );
  }
}
