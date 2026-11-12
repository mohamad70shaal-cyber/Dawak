import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/base/base_controller.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/brand_logo.dart';
import '../controllers/splash_controller.dart';

class SplashPage extends GetView<SplashController> {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[AppColors.heroStart, AppColors.heroMiddle, AppColors.heroEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Obx(() {
            final bool failed = controller.status.value == ViewStatus.error;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const BrandLogo(size: 96, showWordmark: true, onDark: true),
                const SizedBox(height: 40),
                if (!failed)
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.onPrimary))
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: <Widget>[
                        Text(
                          failureText(controller.failure.value!),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onPrimary),
                        ),
                        const SizedBox(height: 16),
                        AppButton(label: 'retry'.tr, onPressed: controller.start, expand: false),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: controller.signOutAndRestart,
                          child: Text('auth_sign_in_again'.tr, style: const TextStyle(color: AppColors.onPrimary)),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
