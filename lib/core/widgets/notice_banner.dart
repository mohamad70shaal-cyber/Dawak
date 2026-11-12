import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

enum NoticeKind { error, success, info, warning }

/// Inline message box with an icon (the meaning never depends on colour alone). Screen readers announce it
/// when it appears.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner(this.message, {super.key, this.kind = NoticeKind.error, this.title});

  final String message;
  final NoticeKind kind;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    switch (kind) {
      case NoticeKind.error:
        color = AppColors.error;
        icon = Icons.error_rounded;
      case NoticeKind.success:
        color = AppColors.success;
        icon = Icons.check_circle_rounded;
      case NoticeKind.info:
        color = AppColors.primary;
        icon = Icons.info_rounded;
      case NoticeKind.warning:
        color = AppColors.warning;
        icon = Icons.warning_amber_rounded;
    }
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.tint(color),
          borderRadius: BorderRadius.circular(AppDims.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title != null) Text(title!, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(message, style: t.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
