import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/services/session_service.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../data/models/profile.dart';
import '../controllers/customer_profile_controller.dart';
import '../controllers/notification_badge_controller.dart';

/// Profile tab (C-24). Tab content only.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final CustomerProfileController c = Get.find<CustomerProfileController>();

    final NotificationBadgeController badge =
        Get.find<NotificationBadgeController>();

    final SessionService session = Get.find<SessionService>();

    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Profile Information
        Obx(() {
          final bool _ = session.state.value.signedIn;

          final Profile? pr = c.profile;
          final String phone = pr?.phone ?? '';

          return AppCard(
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 28,
                  backgroundColor: p.softPrimary,
                  child: Icon(
                    Icons.person_rounded,
                    color: p.primaryText,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        pr?.displayName ?? '',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      LtrText(
                        c.email,
                        style: t.bodySmall?.copyWith(
                          color: p.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty)
                        LtrText(
                          phone,
                          style: t.bodySmall?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 16),

        // Account Settings
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('c_profile_edit'.tr),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  textDirection: TextDirection.ltr,
                ),
                onTap: () {
                  c.fillForm();
                  Get.toNamed<dynamic>(AppRoutes.customerProfileEdit);
                },
              ),

              const Divider(height: 1),

              ListTile(
                leading: const Icon(Icons.radar_rounded),
                title: Text('c_requests_title'.tr),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  textDirection: TextDirection.ltr,
                ),
                onTap: () {
                  Get.toNamed<dynamic>(AppRoutes.customerRequests);
                },
              ),

              const Divider(height: 1),

              // Language
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text('language'.tr),
                subtitle: Text(
                  Get.locale?.languageCode == 'en'
                      ? 'language_en'.tr
                      : 'language_ar'.tr,
                ),
                trailing: Text(
                  'c_switch_language'.tr,
                  style: t.labelLarge?.copyWith(
                    color: p.primaryText,
                  ),
                ),
                onTap: c.toggleLanguage,
              ),

              const Divider(height: 1),

              // Notifications
              ListTile(
                leading: Obx(
                  () => Badge(
                    isLabelVisible: badge.unread.value > 0,
                    label: Text('${badge.unread.value}'),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                    ),
                  ),
                ),
                title: Text('c_notifications_title'.tr),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  textDirection: TextDirection.ltr,
                ),
                onTap: () async {
                  await Get.toNamed<dynamic>(
                    AppRoutes.customerNotifications,
                  );

                  badge.refreshCount();
                },
              ),

              const Divider(height: 1),

              // Help
              ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: Text('c_help_title'.tr),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  textDirection: TextDirection.ltr,
                ),
                onTap: () {
                  Get.toNamed<dynamic>(AppRoutes.customerHelp);
                },
              ),

              const Divider(height: 1),

              // Privacy
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text('c_privacy'.tr),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  textDirection: TextDirection.ltr,
                ),
                onTap: () {
                  Get.toNamed<dynamic>(AppRoutes.legalPrivacy);
                },
              ),

              const Divider(height: 1),

              // Terms
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('c_terms'.tr),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  textDirection: TextDirection.ltr,
                ),
                onTap: () {
                  Get.toNamed<dynamic>(AppRoutes.legalTerms);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sign Out
        AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(
              Icons.logout_rounded,
              color: AppColors.error,
            ),
            title: Text('c_sign_out'.tr),
            onTap: () async {
              final bool ok = await confirmDialog(
                title: 'c_sign_out'.tr,
                message: 'c_sign_out_message'.tr,
                confirmLabel: 'c_sign_out'.tr,
                destructive: true,
              );

              if (ok) {
                await c.signOut();
              }
            },
          ),
        ),
      ],
    );
  }
}
