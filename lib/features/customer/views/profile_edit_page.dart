import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../controllers/customer_profile_controller.dart';

/// Edit profile (C-25): display name and phone. The e-mail address is shown but cannot be changed here.
class ProfileEditPage extends StatelessWidget {
  const ProfileEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    final CustomerProfileController c = Get.find<CustomerProfileController>();
    return Scaffold(
      appBar: AppBar(title: Text('c_profile_edit'.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Form(
              key: c.form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AppTextField(
                    label: 'c_name'.tr,
                    controller: c.name,
                    prefixIcon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                    maxLength: 60,
                    validator: Validators.length(min: 2, max: 60),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'c_phone'.tr,
                    helper: 'optional'.tr,
                    controller: c.phone,
                    ltr: true,
                    keyboardType: TextInputType.phone,
                    prefixIcon: Icons.phone_outlined,
                    textInputAction: TextInputAction.done,
                    validator: Validators.optionalPhone,
                    onSubmitted: (_) => c.save(),
                  ),
                  const SizedBox(height: 16),
                  InfoRow(label: 'c_email'.tr, value: c.email, ltr: true),
                  Text('c_email_fixed'.tr, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 24),
                  Obx(() => AppButton(label: 'save'.tr, icon: Icons.check_rounded, loading: c.submitting.value, onPressed: c.save)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
