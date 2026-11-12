import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import 'ltr_text.dart';

/// Rounded surface with a border; tappable when [onTap] is given.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.color});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final BorderRadius radius = BorderRadius.circular(AppDims.radiusMd);
    return Material(
      color: color ?? p.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A titled block of content inside a screen.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.icon});

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[Icon(icon, size: 20, color: context.palette.primaryText), const SizedBox(width: 8)],
              Expanded(child: Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A figure with a caption (dashboard tiles). [value] is shown left-to-right so digits and currency stay intact.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color = AppColors.primary, this.caption});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.tint(color, alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: p.isDark ? p.text : color),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: t.labelMedium?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: LtrText(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (caption != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(caption!, style: t.labelSmall?.copyWith(color: p.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Label ........ value" row for details screens. Use [ltr] for phone numbers, codes and amounts.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.ltr = false, this.bold = false});

  final String label;
  final String value;
  final bool ltr;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final TextStyle? valueStyle = t.bodyMedium?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 4, child: Text(label, style: t.bodyMedium?.copyWith(color: p.textSecondary))),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: ltr
                ? LtrText(value, style: valueStyle, alignEnd: true)
                : Text(value, style: valueStyle, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Sticky bar for the main action of a screen (checkout, confirm). Keeps clear of the system gesture area.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    return Material(
      color: p.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: child),
      ),
    );
  }
}
