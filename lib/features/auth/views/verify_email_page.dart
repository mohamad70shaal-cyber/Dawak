import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/ltr_text.dart';
import '../controllers/verify_email_controller.dart';

class VerifyEmailPage extends GetView<VerifyEmailController> {
  const VerifyEmailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(color: p.softPrimary, shape: BoxShape.circle),
                    child: Icon(Icons.mark_email_unread_rounded, size: 56, color: p.primaryText),
                  ),
                  const SizedBox(height: 24),
                  Text('auth_verify_title'.tr, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Text('auth_verify_body'.tr, style: t.bodyLarge?.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
                  if (controller.email.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    LtrText(controller.email, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 32),
                  AppButton(label: 'auth_go_to_login'.tr, onPressed: () => Get.offAllNamed<dynamic>(controller.kind.loginRoute)),
                  const SizedBox(height: 12),
                  Obx(() => AppButton(
                        label: 'auth_resend_confirmation'.tr,
                        variant: AppButtonVariant.secondary,
                        loading: controller.submitting.value,
                        onPressed: controller.email.isEmpty ? null : controller.resend,
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
