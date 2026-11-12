import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/platform.dart';
import '../controllers/notifications_controller.dart';

/// Notification centre (C-26).
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final NotificationsController c = Get.find<NotificationsController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('c_notifications_title'.tr)),
      body: PagedListView<AppNotification>(
        paged: c.paged,
        empty: EmptyState(icon: Icons.notifications_none_rounded, title: 'c_notifications_empty'.tr, message: 'c_notifications_empty_hint'.tr),
        itemBuilder: (BuildContext context, AppNotification n) {
          final String text = c.textFor(n);
          return Semantics(
            button: true,
            label: '${n.isUnread ? '${'c_unread'.tr}: ' : ''}$text',
            excludeSemantics: true,
            child: AppCard(
              onTap: () => c.openNotification(n),
              child: Row(
                children: <Widget>[
                  Icon(n.isUnread ? Icons.mark_email_unread_rounded : Icons.mark_email_read_outlined, color: n.isUnread ? p.primaryText : p.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(text, style: t.bodyMedium?.copyWith(fontWeight: n.isUnread ? FontWeight.w700 : FontWeight.w400)),
                        const SizedBox(height: 2),
                        Text(Fmt.dateTime(n.createdAt), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
