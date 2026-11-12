import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_users_controller.dart';
import '../widgets/admin_widgets.dart';

/// Accounts (A-12): pharmacists and admins. Customers are not listed.
class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminUsersController c = Get.find<AdminUsersController>();
    return Scaffold(
      appBar: AppBar(title: Text('a_users_title'.tr)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(hint: 'a_users_search_hint'.tr, onChanged: c.search, onSubmitted: c.search),
          ),
          FilterChipBar<AccountRoleFilter>(
            values: AccountRoleFilter.values,
            selected: c.role,
            label: (AccountRoleFilter f) => 'a_users_filter_${f.name}'.tr,
            onSelected: c.setRole,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('a_users_privacy'.tr, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary)),
          ),
          Expanded(
            child: PagedListView<AccountSummary>(
              paged: c.paged,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              empty: EmptyState(icon: Icons.manage_accounts_outlined, title: 'a_users_empty'.tr, message: 'a_users_empty_hint'.tr),
              itemBuilder: (BuildContext context, AccountSummary a) => _AccountTile(c: c, account: a),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.c, required this.account});

  final AdminUsersController c;
  final AccountSummary account;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final AccountSummary a = account;
    final String? reason = a.suspendedReason;
    final bool isMe = a.id == c.myId;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  a.displayName.isEmpty ? '—' : a.displayName,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                label: a.suspended ? 'a_user_status_suspended'.tr : 'a_user_status_active'.tr,
                color: a.suspended ? AppColors.error : AppColors.success,
                icon: a.suspended ? Icons.block_rounded : Icons.check_circle_rounded,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StatusChip(
                label: (a.role == UserRole.admin ? 'role_admin' : 'role_pharmacist').tr,
                color: a.role == UserRole.admin ? AppColors.secondary : AppColors.primary,
                icon: a.role == UserRole.admin ? Icons.admin_panel_settings_outlined : Icons.badge_outlined,
              ),
              if (isMe) Text('a_user_you'.tr, style: t.labelMedium?.copyWith(color: p.textSecondary)),
            ],
          ),
          if ((a.phone ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(Icons.phone_outlined, size: 16, color: p.textSecondary),
                const SizedBox(width: 4),
                LtrText(a.phone!, style: t.bodySmall?.copyWith(color: p.textSecondary)),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: <Widget>[
                Icon(Icons.event_outlined, size: 16, color: p.textSecondary),
                const SizedBox(width: 4),
                Text('${'a_user_joined'.tr} ', style: t.bodySmall?.copyWith(color: p.textSecondary)),
                LtrText(Fmt.date(a.createdAt), style: t.bodySmall?.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          if (a.suspended && reason != null && reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            NoticeBanner(reason, kind: NoticeKind.warning, title: 'a_user_reason_shown'.tr),
          ],
          if (c.canChange(a)) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Obx(() => a.suspended
                  ? OutlinedButton.icon(
                      onPressed: c.submitting.value ? null : () => c.reactivate(a),
                      icon: const Icon(Icons.play_circle_outline_rounded),
                      label: Text('a_user_reactivate'.tr),
                    )
                  : OutlinedButton.icon(
                      onPressed: c.submitting.value ? null : () => c.suspend(a),
                      icon: const Icon(Icons.block_rounded, color: AppColors.error),
                      label: Text('a_user_suspend'.tr),
                    )),
            ),
          ],
        ],
      ),
    );
  }
}
