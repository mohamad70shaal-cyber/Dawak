import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/ltr_text.dart';

class _FullPageMessage extends StatelessWidget {
  const _FullPageMessage({required this.icon, required this.iconColor, required this.title, required this.message, required this.actions, this.extra});

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> actions;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 72, color: iconColor),
                  const SizedBox(height: 20),
                  Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text(message, style: t.bodyLarge?.copyWith(color: context.palette.textSecondary), textAlign: TextAlign.center),
                  if (extra != null) ...<Widget>[const SizedBox(height: 12), extra!],
                  const SizedBox(height: 32),
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

/// A suspended account. The only way forward is to sign out (or contact support).
class AccountSuspendedPage extends StatelessWidget {
  const AccountSuspendedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionService session = Get.find<SessionService>();
    final String? reason = session.profile?.suspendedReason;
    return _FullPageMessage(
      icon: Icons.block_rounded,
      iconColor: AppColors.error,
      title: 'auth_suspended_title'.tr,
      message: 'auth_suspended_body'.tr,
      extra: Column(
        children: <Widget>[
          if (reason != null && reason.isNotEmpty) Text('${'auth_suspended_reason'.tr}: $reason', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('auth_support_contact'.tr, textAlign: TextAlign.center),
          LtrText(Env.supportEmail),
        ],
      ),
      actions: <Widget>[AppButton(label: 'auth_sign_out'.tr, onPressed: session.signOut)],
    );
  }
}

/// A signed-in user opened an area that belongs to another role.
class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionService session = Get.find<SessionService>();
    return _FullPageMessage(
      icon: Icons.lock_outline_rounded,
      iconColor: AppColors.warning,
      title: 'auth_denied_title'.tr,
      message: 'auth_denied_body'.tr,
      actions: <Widget>[
        AppButton(label: 'go_home'.tr, onPressed: () => Get.offAllNamed<dynamic>(session.homeRoute)),
        AppButton(label: 'auth_sign_out'.tr, variant: AppButtonVariant.secondary, onPressed: session.signOut),
      ],
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SessionService session = Get.find<SessionService>();
    return _FullPageMessage(
      icon: Icons.search_off_rounded,
      iconColor: context.palette.primaryText,
      title: 'page_not_found_title'.tr,
      message: 'page_not_found_message'.tr,
      actions: <Widget>[
        AppButton(
          label: 'go_home'.tr,
          onPressed: () => Get.offAllNamed<dynamic>(session.signedIn ? session.homeRoute : AppRoutes.welcome),
        ),
      ],
    );
  }
}
