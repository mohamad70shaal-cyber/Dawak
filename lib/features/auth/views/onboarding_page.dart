import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../controllers/onboarding_controller.dart';

class OnboardingPage extends GetView<OnboardingController> {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: controller.finish, child: Text('skip'.tr)),
            ),
            Expanded(
              child: PageView.builder(
                controller: controller.pager,
                onPageChanged: controller.onPageChanged,
                itemCount: OnboardingController.pages.length,
                itemBuilder: (BuildContext context, int i) {
                  final OnboardingPageData d = OnboardingController.pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(color: p.softPrimary, shape: BoxShape.circle),
                          child: Icon(d.icon, size: 72, color: p.primaryText),
                        ),
                        const SizedBox(height: 32),
                        Text(d.titleKey.tr, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(d.messageKey.tr, style: t.bodyLarge?.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            Obx(() => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (int i = 0; i < OnboardingController.pages.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: controller.page.value == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: controller.page.value == i ? p.primaryText : p.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                )),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Obx(() => SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: controller.next,
                      child: Text(controller.isLast ? 'auth_get_started'.tr : 'next'.tr),
                    ),
                  )),
            ),
          ],
        ),
      ),
    );
  }
}
