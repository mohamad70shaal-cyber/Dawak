import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';

/// App mark: gradient tile with a capsule icon, optionally with the wordmark and tagline.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72, this.showWordmark = false, this.onDark = false});

  final double size;
  final bool showWordmark;

  /// True on the dark splash/welcome background (wordmark in white).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final Color fg = onDark ? AppColors.onPrimary : context.palette.text;
    final Color sub = onDark ? AppColors.onPrimary.withValues(alpha: 0.75) : context.palette.textSecondary;
    final Widget mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.primary, AppColors.secondary],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(Icons.medication_rounded, color: AppColors.onPrimary, size: size * 0.58),
    );
    if (!showWordmark) return Semantics(label: 'app_name'.tr, image: true, child: mark);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        mark,
        const SizedBox(height: 16),
        Text('app_name'.tr, style: t.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('app_tagline'.tr, style: t.titleSmall?.copyWith(color: sub)),
      ],
    );
  }
}
