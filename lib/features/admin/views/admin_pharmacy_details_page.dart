import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pharmacy.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_pharmacy_details_controller.dart';

/// Application and pharmacy details (A-04, A-05): everything needed to decide, the licence document and the review buttons.
class AdminPharmacyDetailsPage extends StatelessWidget {
  const AdminPharmacyDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final AdminPharmacyDetailsController c = Get.find<AdminPharmacyDetailsController>(tag: id);
    return Scaffold(
      appBar: AppBar(title: Text('a_pharmacy_details'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: () => c.refresh(silent: true),
          child: Obx(() {
            final PharmacyApplication? a = c.application.value;
            if (a == null) return const SizedBox.shrink();
            return _Body(c: c, app: a);
          }),
        ),
      ),
      bottomNavigationBar: Obx(() {
        if (c.application.value == null) return const SizedBox.shrink();
        final Widget? bar = _actions(c);
        return bar == null ? const SizedBox.shrink() : BottomActionBar(child: bar);
      }),
    );
  }

  Widget? _actions(AdminPharmacyDetailsController c) {
    final bool busy = c.submitting.value;
    if (c.canApprove) {
      return Row(
        children: <Widget>[
          Expanded(child: AppButton(label: 'a_pharmacy_reject'.tr, variant: AppButtonVariant.danger, onPressed: busy ? null : c.reject)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: AppButton(label: 'a_pharmacy_approve'.tr, icon: Icons.verified_rounded, loading: busy, onPressed: c.approve)),
        ],
      );
    }
    if (c.canSuspend) {
      return AppButton(label: 'a_pharmacy_suspend'.tr, icon: Icons.pause_circle_outline_rounded, variant: AppButtonVariant.danger, loading: busy, onPressed: c.suspend);
    }
    if (c.canReinstate) {
      return AppButton(label: 'a_pharmacy_reinstate'.tr, icon: Icons.play_circle_outline_rounded, loading: busy, onPressed: c.reinstate);
    }
    return null;
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c, required this.app});

  final AdminPharmacyDetailsController c;
  final PharmacyApplication app;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Pharmacy ph = app.pharmacy;
    final String? reason = ph.statusReason;
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
                  Expanded(child: Text(ph.name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 8),
                  ApprovalChip(ph.status),
                ],
              ),
              if (ph.status != ApprovalStatus.pending) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    StatusChip(
                      label: ph.isListed ? 'a_ph_listed'.tr : 'a_ph_unlisted'.tr,
                      color: ph.isListed ? AppColors.success : AppColors.warning,
                      icon: ph.isListed ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    ),
                  ],
                ),
              ],
              if (reason != null && reason.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                NoticeBanner(reason, kind: NoticeKind.warning, title: 'a_ph_reason'.tr),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'a_ph_section_pharmacy'.tr,
          icon: Icons.local_pharmacy_outlined,
          child: Column(
            children: <Widget>[
              InfoRow(label: 'a_ph_phone'.tr, value: ph.phone, ltr: true),
              InfoRow(label: 'a_ph_phone_public'.tr, value: (ph.showPhonePublicly ? 'yes' : 'no').tr),
              InfoRow(label: 'a_ph_city'.tr, value: ph.city),
              InfoRow(label: 'a_ph_neighborhood'.tr, value: ph.neighborhood.isEmpty ? '—' : ph.neighborhood),
              InfoRow(label: 'a_ph_address'.tr, value: ph.addressLine.isEmpty ? '—' : ph.addressLine),
              if (ph.directions.isNotEmpty) InfoRow(label: 'a_ph_directions'.tr, value: ph.directions),
              InfoRow(label: 'a_ph_currency'.tr, value: ph.currency == 'USD' ? 'currency_usd_name'.tr : 'currency_syp_name'.tr),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'a_ph_section_owner'.tr,
          icon: Icons.person_outline_rounded,
          child: Column(
            children: <Widget>[
              InfoRow(label: 'a_ph_owner_name'.tr, value: app.ownerName.isEmpty ? '—' : app.ownerName),
              InfoRow(label: 'a_ph_owner_phone'.tr, value: (app.ownerPhone ?? '').isEmpty ? '—' : app.ownerPhone!, ltr: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'a_ph_section_license'.tr,
          icon: Icons.description_outlined,
          child: c.hasLicense
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('a_ph_license_hint'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
                    const SizedBox(height: 12),
                    Obx(() => AppButton(
                          label: 'a_ph_license_view'.tr,
                          icon: Icons.open_in_new_rounded,
                          variant: AppButtonVariant.secondary,
                          loading: c.submitting.value,
                          onPressed: c.viewLicense,
                        )),
                  ],
                )
              : NoticeBanner('a_ph_license_missing'.tr, kind: NoticeKind.warning),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'a_ph_section_dates'.tr,
          icon: Icons.event_note_outlined,
          child: Column(
            children: <Widget>[
              InfoRow(label: 'a_ph_submitted'.tr, value: Fmt.dateTime(ph.submittedAt ?? ph.createdAt), ltr: true),
              InfoRow(label: 'a_ph_reviewed'.tr, value: Fmt.dateTime(ph.reviewedAt), ltr: true),
            ],
          ),
        ),
      ],
    );
  }
}
