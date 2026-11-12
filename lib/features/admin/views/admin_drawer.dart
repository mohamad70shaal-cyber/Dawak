import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ltr_text.dart';
import '../controllers/admin_account_controller.dart';

/// The admin drawer: the screens that are not tabs (categories, accounts, audit log), language and sign-out.
class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

  void _go(BuildContext context, String route) {
    Navigator.of(context).pop();
    Get.toNamed<dynamic>(route);
  }

  Future<void> _signOut(BuildContext context, AdminAccountController c) async {
    Navigator.of(context).pop();
    final bool ok = await confirmDialog(
      title: 'a_signout_title'.tr,
      message: 'a_signout_message'.tr,
      confirmLabel: 'a_signout'.tr,
    );
    if (ok) await c.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final AdminAccountController c = Get.find<AdminAccountController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: p.softPrimary,
                    child: Icon(Icons.admin_panel_settings_rounded, color: p.primaryText),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(c.name.isEmpty ? 'role_admin'.tr : c.name, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (c.email.isNotEmpty) LtrText(c.email, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('role_admin'.tr, style: t.labelMedium?.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text('a_categories_title'.tr),
              onTap: () => _go(context, AppRoutes.adminCategories),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: Text('a_users_title'.tr),
              onTap: () => _go(context, AppRoutes.adminUsers),
            ),
            ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: Text('a_audit_title'.tr),
              onTap: () => _go(context, AppRoutes.adminAuditLogs),
            ),
            const Divider(height: 1),
            Obx(() => ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text('language'.tr),
                  subtitle: Text((c.isArabic ? 'language_ar' : 'language_en').tr),
                  onTap: c.toggleLanguage,
                )),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.error),
              title: Text('a_signout'.tr),
              onTap: () => _signOut(context, c),
            ),
          ],
        ),
      ),
    );
  }
}
