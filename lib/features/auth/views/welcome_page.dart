import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/brand_logo.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final LocaleService locale = Get.find<LocaleService>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[AppColors.heroStart, AppColors.heroMiddle, AppColors.heroEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: <Widget>[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Obx(() => TextButton.icon(
                        onPressed: locale.toggle,
                        icon: const Icon(Icons.language_rounded, color: AppColors.onPrimary),
                        label: Text(
                          locale.isArabic ? 'language_en'.tr : 'language_ar'.tr,
                          style: const TextStyle(color: AppColors.onPrimary),
                        ),
                      )),
                ),
                const Spacer(flex: 2),
                const BrandLogo(size: 104, showWordmark: true, onDark: true),
                const Spacer(flex: 3),
                AppButton(label: 'auth_login'.tr, onPressed: () => Get.toNamed<dynamic>(AppRoutes.login)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onPrimary,
                      side: const BorderSide(color: AppColors.onPrimary),
                    ),
                    onPressed: () => Get.toNamed<dynamic>(AppRoutes.register),
                    child: Text('auth_create_account'.tr),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Get.toNamed<dynamic>(AppRoutes.pharmacistLogin),
                  child: Text('auth_i_am_pharmacist'.tr, style: const TextStyle(color: AppColors.onPrimary)),
                ),
                TextButton(
                  onPressed: () => Get.toNamed<dynamic>(AppRoutes.adminLogin),
                  child: Text(
                    'auth_admin_sign_in'.tr,
                    style: TextStyle(color: AppColors.onPrimary.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
