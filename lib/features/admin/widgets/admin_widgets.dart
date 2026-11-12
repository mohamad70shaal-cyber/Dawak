import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/chips.dart';

/// The translation of [key], or [fallback] when the table has none (codes that grow on the server, e.g. new report categories).
String trOr(String key, String fallback) {
  final String t = key.tr;
  return t == key ? fallback : t;
}

/// True unless the app currently runs in English.
bool isArabicNow() => Get.locale?.languageCode != 'en';

/// A row of single-choice chips that scrolls sideways. The selected value is read from [selected] (reactive).
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({super.key, required this.values, required this.selected, required this.label, required this.onSelected});

  final List<T> values;
  final Rx<T> selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Obx(() {
        final T current = selected.value;
        return ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: <Widget>[
            for (final T v in values)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(label(v)),
                  selected: current == v,
                  onSelected: (bool _) => onSelected(v),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Figures in two columns.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final double w = (box.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[for (final Widget c in children) SizedBox(width: w, child: c)],
      );
    });
  }
}

/// Status of a catalogue entry: `pending`, `approved`, `rejected` or `archived`.
class CatalogStatusChip extends StatelessWidget {
  const CatalogStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'pending':
        return StatusChip(label: 'a_catalog_pending'.tr, color: AppColors.warning, icon: Icons.hourglass_top_rounded);
      case 'rejected':
        return StatusChip(label: 'a_catalog_rejected'.tr, color: AppColors.error, icon: Icons.cancel_rounded);
      case 'archived':
        return StatusChip(label: 'a_catalog_archived'.tr, color: AppColors.textSecondary, icon: Icons.inventory_2_outlined);
      default:
        return StatusChip(label: 'a_catalog_approved'.tr, color: AppColors.success, icon: Icons.verified_rounded);
    }
  }
}

/// Status of a user report: `open`, `in_review`, `resolved` or `dismissed`.
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'in_review':
        return StatusChip(label: 'a_report_status_in_review'.tr, color: AppColors.primary, icon: Icons.visibility_rounded);
      case 'resolved':
        return StatusChip(label: 'a_report_status_resolved'.tr, color: AppColors.success, icon: Icons.task_alt_rounded);
      case 'dismissed':
        return StatusChip(label: 'a_report_status_dismissed'.tr, color: AppColors.textSecondary, icon: Icons.block_rounded);
      default:
        return StatusChip(label: 'a_report_status_open'.tr, color: AppColors.warning, icon: Icons.flag_rounded);
    }
  }
}

/// Small bold heading above a group of cards.
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}
