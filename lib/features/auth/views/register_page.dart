import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../auth_kind.dart';
import '../controllers/register_controller.dart';
import 'auth_widgets.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage(this.kind, {super.key});

  final AuthKind kind;

  @override
  Widget build(BuildContext context) {
    final RegisterController c = Get.find<RegisterController>(tag: kind.name);
    final TextTheme t = Theme.of(context).textTheme;
    return AuthFormScaffold(
      title: 'auth_register_title_${kind.name}'.tr,
      subtitle: 'auth_register_subtitle_${kind.name}'.tr,
      children: <Widget>[
        Form(
          key: c.form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppTextField(
                label: 'auth_full_name'.tr,
                controller: c.name,
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.name],
                prefixIcon: Icons.person_outline_rounded,
                validator: Validators.length(min: 2, max: 80),
              ),
              const SizedBox(height: 16),
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
                textInputAction: TextInputAction.next,
                autofillHints: const <String>[AutofillHints.newPassword],
                prefixIcon: Icons.lock_outline_rounded,
                helper: 'auth_password_hint'.tr,
                validator: Validators.password,
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'auth_confirm_password'.tr,
                controller: c.confirm,
                obscure: true,
                ltr: true,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.lock_reset_rounded,
                validator: Validators.confirmPassword(() => c.password.text),
                onSubmitted: (_) => c.register(),
              ),
              const SizedBox(height: 16),
              Obx(() => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: c.acceptedTerms.value,
                    onChanged: (bool? v) {
                      c.acceptedTerms.value = v ?? false;
                      if (c.acceptedTerms.value) c.termsError.value = false;
                    },
                    title: Text.rich(
                      TextSpan(
                        style: t.bodyMedium,
                        children: <InlineSpan>[
                          TextSpan(text: '${'auth_accept_prefix'.tr} '),
                          TextSpan(
                            text: 'auth_terms'.tr,
                            style: TextStyle(color: context.palette.primaryText, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()..onTap = () => Get.toNamed<dynamic>(AppRoutes.legalTerms),
                          ),
                          TextSpan(text: ' ${'auth_and'.tr} '),
                          TextSpan(
                            text: 'auth_privacy'.tr,
                            style: TextStyle(color: context.palette.primaryText, decoration: TextDecoration.underline),
                            recognizer: TapGestureRecognizer()..onTap = () => Get.toNamed<dynamic>(AppRoutes.legalPrivacy),
                          ),
                        ],
                      ),
                    ),
                  )),
              Obx(() => c.termsError.value
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: <Widget>[
                        const Icon(Icons.error_rounded, size: 16, color: AppColors.error),
                        const SizedBox(width: 6),
                        Expanded(child: Text('auth_accept_required'.tr, style: t.bodySmall?.copyWith(color: AppColors.error))),
                      ]),
                    )
                  : const SizedBox.shrink()),
              const SizedBox(height: 8),
              Obx(() => AppButton(label: 'auth_create_account'.tr, loading: c.submitting.value, onPressed: c.register)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Flexible(child: Text('auth_have_account'.tr)),
                  TextButton(
                    onPressed: () => Get.offNamed<dynamic>(kind.loginRoute),
                    child: Text('auth_login'.tr),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
