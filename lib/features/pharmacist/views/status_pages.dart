import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../data/models/pharmacy.dart';
import '../controllers/pharmacy_status_controller.dart';

class _StatusFrame extends StatelessWidget {
  const _StatusFrame({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.children,
    required this.actions,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 72, color: iconColor),
                  const SizedBox(height: 20),
                  Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(message, style: t.bodyLarge?.copyWith(color: context.palette.textSecondary), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  ...children,
                  const SizedBox(height: 24),
                  for (final Widget a in actions) ...<Widget>[a, const SizedBox(height: 12)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pharmacyCard(Pharmacy? p) {
  if (p == null) return const SizedBox.shrink();
  return AppCard(
    child: Column(
      children: <Widget>[
        InfoRow(label: 'p_reg_name'.tr, value: p.name),
        InfoRow(label: 'p_reg_city'.tr, value: p.city),
        InfoRow(label: 'p_status_submitted'.tr, value: Fmt.dateTime(p.submittedAt)),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(alignment: AlignmentDirectional.centerStart, child: ApprovalChip(p.status)),
        ),
      ],
    ),
  );
}

/// P-07: the application is with the admins.
class PharmacyPendingPage extends StatelessWidget {
  const PharmacyPendingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyStatusController c = Get.find<PharmacyStatusController>();
    return Obx(() => _StatusFrame(
          icon: Icons.hourglass_top_rounded,
          iconColor: AppColors.warning,
          title: 'p_status_pending_title'.tr,
          message: 'p_status_pending_body'.tr,
          children: <Widget>[
            _pharmacyCard(c.pharmacy.value),
            const SizedBox(height: 12),
            NoticeBanner('p_status_auto_refresh'.tr, kind: NoticeKind.info),
          ],
          actions: <Widget>[
            AppButton(
              label: 'p_status_refresh'.tr,
              icon: Icons.refresh_rounded,
              loading: c.refreshing.value,
              onPressed: c.refreshNow,
            ),
            AppButton(label: 'auth_sign_out'.tr, variant: AppButtonVariant.secondary, onPressed: c.signOut),
          ],
        ));
  }
}

/// P-08: the application was rejected; the reason is shown and the form can be corrected and resent.
class PharmacyRejectedPage extends StatelessWidget {
  const PharmacyRejectedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyStatusController c = Get.find<PharmacyStatusController>();
    return Obx(() {
      final String? reason = c.reason;
      return _StatusFrame(
        icon: Icons.cancel_rounded,
        iconColor: AppColors.error,
        title: 'p_status_rejected_title'.tr,
        message: 'p_status_rejected_body'.tr,
        children: <Widget>[
          NoticeBanner(reason ?? 'p_status_no_reason'.tr, title: 'p_status_reason'.tr),
          const SizedBox(height: 12),
          _pharmacyCard(c.pharmacy.value),
        ],
        actions: <Widget>[
          AppButton(label: 'p_status_edit_resubmit'.tr, icon: Icons.edit_rounded, onPressed: c.editAndResubmit),
          AppButton(label: 'auth_sign_out'.tr, variant: AppButtonVariant.secondary, onPressed: c.signOut),
        ],
      );
    });
  }
}

/// P-09: an approved pharmacy was suspended by the administration.
class PharmacySuspendedPage extends StatelessWidget {
  const PharmacySuspendedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyStatusController c = Get.find<PharmacyStatusController>();
    return Obx(() {
      final String? reason = c.reason;
      return _StatusFrame(
        icon: Icons.pause_circle_rounded,
        iconColor: AppColors.error,
        title: 'p_status_suspended_title'.tr,
        message: 'p_status_suspended_body'.tr,
        children: <Widget>[
          if (reason != null) NoticeBanner(reason, title: 'p_status_reason'.tr),
          const SizedBox(height: 12),
          Text('auth_support_contact'.tr, textAlign: TextAlign.center),
          LtrText(Env.supportEmail),
        ],
        actions: <Widget>[
          AppButton(label: 'p_status_refresh'.tr, icon: Icons.refresh_rounded, loading: c.refreshing.value, onPressed: c.refreshNow),
          AppButton(label: 'auth_sign_out'.tr, variant: AppButtonVariant.secondary, onPressed: c.signOut),
        ],
      );
    });
  }
}
