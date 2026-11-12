import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../pharmacist/services/import_parser.dart';
import '../controllers/admin_medicine_import_controller.dart';

/// Admin import wizard: load Excel / CSV, map columns, preview rows, bulk-create (A-16).
class AdminMedicineImportPage extends StatelessWidget {
  const AdminMedicineImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminMedicineImportController c = Get.find<AdminMedicineImportController>();
    return Scaffold(
      appBar: AppBar(title: Text('a_import_title'.tr)),
      body: Obx(() {
        switch (c.step.value) {
          case AdminImportStep.pick:
            return _PickStep(c: c);
          case AdminImportStep.columns:
            return _ColumnsStep(c: c);
          case AdminImportStep.preview:
            return _PreviewStep(c: c);
          case AdminImportStep.saving:
            return _SavingStep(c: c);
          case AdminImportStep.done:
            return _DoneStep(c: c);
        }
      }),
    );
  }
}

// ---- Step 1: pick file ------------------------------------------------------------------

class _PickStep extends StatelessWidget {
  const _PickStep({required this.c});

  final AdminMedicineImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Icon(Icons.upload_file_rounded, size: 56, color: p.primaryText),
        const SizedBox(height: 12),
        Text('a_import_intro'.tr, style: t.bodyLarge),
        const SizedBox(height: 8),
        Text('a_import_formats'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 16),
        NoticeBanner('a_import_note'.tr, kind: NoticeKind.info),
        Obx(() {
          final String? key = c.importError.value;
          if (key == null) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 12), child: NoticeBanner(key.tr));
        }),
        const SizedBox(height: 24),
        AppButton(label: 'a_import_choose_file'.tr, icon: Icons.folder_open_rounded, onPressed: c.pickFile),
      ],
    );
  }
}

// ---- Step 2: columns --------------------------------------------------------------------

class _ColumnsStep extends StatelessWidget {
  const _ColumnsStep({required this.c});

  final AdminMedicineImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Obx(() => Row(
                    children: <Widget>[
                      const Icon(Icons.description_outlined),
                      const SizedBox(width: 8),
                      Expanded(child: LtrText(c.fileName.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall)),
                      TextButton(onPressed: c.backToFile, child: Text('change'.tr)),
                    ],
                  )),
              const SizedBox(height: 8),
              Text('a_import_columns_intro'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
              const SizedBox(height: 16),
              Obx(() => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('a_import_has_header'.tr),
                    value: c.columns.value.hasHeader,
                    onChanged: c.setHasHeader,
                  )),
              const SizedBox(height: 8),
              // Required: Arabic name column
              Obx(() => _ColPicker(
                    label: 'a_import_col_name_ar'.tr,
                    icon: Icons.medication_outlined,
                    table: c.table.value,
                    value: c.columns.value.nameColumn,
                    onChanged: c.setNameColumn,
                    includeNone: false,
                  )),
              const SizedBox(height: 12),
              // Optional: English name column
              Obx(() => _ColPicker(
                    label: 'a_import_col_name_en'.tr,
                    icon: Icons.translate_rounded,
                    table: c.table.value,
                    value: c.nameEnColumn.value,
                    onChanged: c.setNameEnColumn,
                    includeNone: true,
                  )),
              const SizedBox(height: 12),
              // Optional: strength
              Obx(() => _ColPicker(
                    label: 'a_import_col_strength'.tr,
                    icon: Icons.science_outlined,
                    table: c.table.value,
                    value: c.strengthColumn.value,
                    onChanged: c.setStrengthColumn,
                    includeNone: true,
                  )),
              const SizedBox(height: 12),
              // Optional: dosage form
              Obx(() => _ColPicker(
                    label: 'a_import_col_dosage'.tr,
                    icon: Icons.medication_liquid_outlined,
                    table: c.table.value,
                    value: c.dosageFormColumn.value,
                    onChanged: c.setDosageFormColumn,
                    includeNone: true,
                  )),
              const SizedBox(height: 16),
              Obx(() {
                final String? key = c.importError.value;
                if (key != null) return NoticeBanner(key.tr);
                return const SizedBox.shrink();
              }),
              const SizedBox(height: 8),
              // Mini-preview of first 5 rows
              SectionCard(
                title: 'a_import_preview'.tr,
                icon: Icons.table_rows_outlined,
                child: Obx(() {
                  final List<AdminImportRow> shown = c.rows.take(5).toList();
                  if (shown.isEmpty) return Text('a_import_err_no_rows'.tr);
                  return Column(
                    children: <Widget>[
                      for (final AdminImportRow r in shown)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: Text(r.line.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 8),
              Obx(() => Text(
                    'a_import_rows_total'.trParams(<String, String>{'n': '${c.rows.length}'}),
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  )),
            ],
          ),
        ),
        BottomActionBar(
          child: Obx(() => AppButton(
                label: 'a_import_preview_action'.tr,
                icon: Icons.preview_rounded,
                loading: c.submitting.value,
                onPressed: c.hasRows ? c.startPreview : null,
              )),
        ),
      ],
    );
  }
}

class _ColPicker extends StatelessWidget {
  const _ColPicker({
    required this.label,
    required this.icon,
    required this.table,
    required this.value,
    required this.onChanged,
    required this.includeNone,
  });

  final String label;
  final IconData icon;
  final SheetTable? table;
  final int value;
  final ValueChanged<int> onChanged;
  final bool includeNone;

  String _title(int col) {
    if (col < 0) return 'a_import_col_none'.tr;
    final String sample = table == null ? '' : table!.cell(0, col);
    final String head = 'a_import_column_n'.trParams(<String, String>{'n': '${col + 1}'});
    return sample.isEmpty ? head : '$head: $sample';
  }

  @override
  Widget build(BuildContext context) {
    final int count = table?.columnCount ?? 0;
    if (count == 0) return const SizedBox.shrink();
    final int clamped = value < 0 ? -1 : (value < count ? value : 0);
    return DropdownButtonFormField<int>(
      value: clamped,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: <DropdownMenuItem<int>>[
        if (includeNone) DropdownMenuItem<int>(value: -1, child: Text('a_import_col_none'.tr, maxLines: 1, overflow: TextOverflow.ellipsis)),
        for (int i = 0; i < count; i++) DropdownMenuItem<int>(value: i, child: Text(_title(i), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (int? v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ---- Step 3: preview (review rows) -------------------------------------------------------

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.c});

  final AdminMedicineImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Obx(() => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'a_import_rows_total'.trParams(<String, String>{'n': '${c.includedCount}'}),
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextButton(onPressed: () => c.setAll(true), child: Text('a_import_select_all'.tr)),
                      TextButton(onPressed: () => c.setAll(false), child: Text('a_import_select_none'.tr)),
                    ],
                  ),
                ],
              )),
        ),
        Expanded(
          child: Obx(() {
            if (c.rows.isEmpty) {
              return Center(child: Text('a_import_err_no_rows'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: c.rows.length,
              itemBuilder: (BuildContext context, int i) => _RowTile(c: c, row: c.rows[i]),
            );
          }),
        ),
        BottomActionBar(
          child: Obx(() => AppButton(
                label: 'a_import_confirm'.trParams(<String, String>{'n': '${c.includedCount}'}),
                icon: Icons.check_rounded,
                loading: c.submitting.value,
                onPressed: c.includedCount > 0 ? c.save : null,
              )),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.c, required this.row});

  final AdminMedicineImportController c;
  final AdminImportRow row;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Obx(() => Row(
              children: <Widget>[
                Checkbox(value: row.include.value, onChanged: (bool? v) => c.toggleRow(row, v ?? false)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(row.line.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('a_import_row_line'.trParams(<String, String>{'n': '${row.line.line}'}), style: t.bodySmall?.copyWith(color: context.palette.textSecondary)),
                    ],
                  ),
                ),
              ],
            )),
      ),
    );
  }
}

// ---- Step 4: saving ---------------------------------------------------------------------

class _SavingStep extends StatelessWidget {
  const _SavingStep({required this.c});

  final AdminMedicineImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('a_import_saving'.tr, style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Obx(() => LinearProgressIndicator(value: c.progress.value <= 0 ? null : c.progress.value, minHeight: 8)),
            const SizedBox(height: 8),
            Obx(() => LtrText('${(c.progress.value * 100).round()}%', style: t.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

// ---- Step 5: done -----------------------------------------------------------------------

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.c});

  final AdminMedicineImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AdminImportResult? r = c.result.value;
    if (r == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
        const SizedBox(height: 12),
        Text('a_import_done_title'.trParams(<String, String>{'n': '${r.created}'}), style: t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SectionCard(
          title: 'a_import_result'.tr,
          icon: Icons.summarize_outlined,
          child: Column(
            children: <Widget>[
              InfoRow(label: 'a_import_result_created'.tr, value: '${r.created}', ltr: true),
              InfoRow(label: 'a_import_result_skipped'.tr, value: '${r.skipped}', ltr: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(label: 'a_import_back_to_list'.tr, icon: Icons.list_alt_rounded, onPressed: () => Get.back<dynamic>()),
        const SizedBox(height: 8),
        AppButton(label: 'a_import_another'.tr, icon: Icons.upload_file_rounded, variant: AppButtonVariant.secondary, onPressed: c.importAnother),
      ],
    );
  }
}

