import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../auth_kind.dart';
import '../controllers/login_controller.dart';
import 'auth_widgets.dart';

class LoginPage extends StatelessWidget {
  const LoginPage(this.kind, {super.key});

  final AuthKind kind;

  @override
  Widget build(BuildContext context) {
    final LoginController c = Get.find<LoginController>(tag: kind.name);
    final String title = 'auth_login_title_${kind.name}'.tr;
    return AuthFormScaffold(
      title: title,
      subtitle: 'auth_login_subtitle_${kind.name}'.tr,
      children: <Widget>[
        Form(
          key: c.form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Obx(() {
                final String? n = c.notice.value;
                final AppFailure? f = c.failure.value;
                final String? text = n ?? (f == null ? null : failureText(f));
                if (text == null) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(bottom: 16), child: NoticeBanner(text));
              }),
              AppTextField(
                label: 'auth_email'.tr,
                controller: c.email,
                ltr: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.email],
                prefixIcon: Icons.mail_outline_rounded,
                validator: Validators.email,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'auth_password'.tr,
                controller: c.password,
                obscure: true,
                ltr: true,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.password],
                prefixIcon: Icons.lock_outline_rounded,
                validator: (String? v) => (v ?? '').isEmpty ? 'val_required'.tr : null,
                onSubmitted: (_) => c.signIn(),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => Get.toNamed<dynamic>(AppRoutes.passwordReset),
                  child: Text('auth_forgot_password'.tr),
                ),
              ),
              const SizedBox(height: 8),
              Obx(() => AppButton(label: 'auth_login'.tr, loading: c.submitting.value, onPressed: c.signIn)),
              Obx(() => c.needsConfirmation
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppButton(
                        label: 'auth_resend_confirmation'.tr,
                        variant: AppButtonVariant.secondary,
                        onPressed: c.submitting.value ? null : c.resendConfirmation,
                      ),
                    )
                  : const SizedBox.shrink()),
              if (kind != AuthKind.admin) ...<Widget>[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(child: Text('auth_no_account'.tr)),
                    TextButton(
                      onPressed: () => Get.toNamed<dynamic>(kind.registerRoute),
                      child: Text('auth_create_account'.tr),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
