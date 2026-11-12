import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/base/shell_controller.dart';
import '../../../core/services/locale_service.dart';

class OnboardingPageData {
  const OnboardingPageData({required this.icon, required this.titleKey, required this.messageKey});

  final IconData icon;
  final String titleKey;
  final String messageKey;
}

class OnboardingController extends GetxController {
  OnboardingController({LocaleService? locale, OffAll? offAll})
      : _locale = locale ?? Get.find<LocaleService>(),
        _offAll = offAll ?? defaultOffAll;

  final LocaleService _locale;
  final OffAll _offAll;

  static const List<OnboardingPageData> pages = <OnboardingPageData>[
    OnboardingPageData(icon: Icons.travel_explore_rounded, titleKey: 'auth_onb1_title', messageKey: 'auth_onb1_body'),
    OnboardingPageData(icon: Icons.bookmark_added_rounded, titleKey: 'auth_onb2_title', messageKey: 'auth_onb2_body'),
    OnboardingPageData(icon: Icons.local_pharmacy_rounded, titleKey: 'auth_onb3_title', messageKey: 'auth_onb3_body'),
  ];

  final RxInt page = 0.obs;
  final PageController pager = PageController();

  bool get isLast => page.value == pages.length - 1;

  void onPageChanged(int i) => page.value = i;

  Future<void> next() async {
    if (isLast) {
      await finish();
    } else {
      await pager.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> finish() async {
    await _locale.markOnboardingDone();
    _offAll(AppRoutes.welcome);
  }

  @override
  void onClose() {
    pager.dispose();
    super.onClose();
  }
}
