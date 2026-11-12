import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../controllers/password_reset_controller.dart';
import 'auth_widgets.dart';

class PasswordResetPage extends GetView<PasswordResetController> {
  const PasswordResetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.sent.value) {
        return AuthFormScaffold(
          title: 'auth_reset_sent_title'.tr,
          children: <Widget>[
            NoticeBanner('auth_reset_sent_body'.tr, kind: NoticeKind.success),
            const SizedBox(height: 24),
            AppButton(label: 'auth_back_to_login'.tr, onPressed: () => Get.offNamed<dynamic>(AppRoutes.login)),
          ],
        );
      }
      return AuthFormScaffold(
        title: 'auth_reset_title'.tr,
        subtitle: 'auth_reset_subtitle'.tr,
        children: <Widget>[
          Form(
            key: controller.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTextField(
                  label: 'auth_email'.tr,
                  controller: controller.email,
                  ltr: true,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.mail_outline_rounded,
                  validator: Validators.email,
                  onSubmitted: (_) => controller.send(),
                ),
                const SizedBox(height: 24),
                AppButton(label: 'auth_send_reset_link'.tr, loading: controller.submitting.value, onPressed: controller.send),
              ],
            ),
          ),
        ],
      );
    });
  }
}
