import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../controllers/customer_location.dart';
import 'customer_widgets.dart';

/// One line (or notice) that tells the customer where the distances come from:
/// reading the position, a failure with what to do about it, "no position yet" with a button, or "sorted nearest first".
/// Rebuilds by itself when [location] changes.
class LocationNotice extends StatelessWidget {
  const LocationNotice({
    super.key,
    required this.location,
    required this.located,
    required this.onUseLocation,
    required this.sortedKey,
    required this.unlocatedKey,
  });

  final CustomerLocation location;

  /// True when what is on screen was computed from the customer's position.
  final bool located;

  /// "Use my location": read the position again and refresh what is on screen.
  final VoidCallback onUseLocation;

  /// Translation keys of the two texts that depend on the screen.
  final String sortedKey;
  final String unlocatedKey;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Obx(() {
      final String? error = location.error.value;
      if (location.locating.value) {
        return Row(
          children: <Widget>[
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 10),
            Expanded(child: Text('c_locating'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary))),
          ],
        );
      }
      if (error != null) {
        return InlineNotice(
          error,
          tone: NoticeTone.warning,
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              AppButton(label: 'c_use_my_location'.tr, icon: Icons.my_location_rounded, variant: AppButtonVariant.secondary, expand: false, onPressed: onUseLocation),
              if (location.needsSettings.value)
                AppButton(label: 'c_open_settings'.tr, icon: Icons.settings_rounded, variant: AppButtonVariant.text, expand: false, onPressed: location.openSettings),
            ],
          ),
        );
      }
      if (!located) {
        return InlineNotice(
          unlocatedKey.tr,
          action: AppButton(label: 'c_use_my_location'.tr, icon: Icons.my_location_rounded, variant: AppButtonVariant.secondary, expand: false, onPressed: onUseLocation),
        );
      }
      return Row(
        children: <Widget>[
          Icon(Icons.near_me_rounded, size: 18, color: p.primaryText),
          const SizedBox(width: 8),
          Expanded(child: Text(sortedKey.tr, style: t.bodySmall?.copyWith(color: p.textSecondary))),
        ],
      );
    });
  }
}
