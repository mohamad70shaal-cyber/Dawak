import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../data/models/medicine.dart';
import '../controllers/product_import_controller.dart';
import '../services/import_parser.dart';
import '../widgets/pharmacist_widgets.dart';

/// Import a price list from Excel / CSV into the pharmacy's list (P-29).
class ProductImportPage extends StatelessWidget {
  const ProductImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ProductImportController c = Get.find<ProductImportController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_import_title'.tr)),
      body: Obx(() {
        switch (c.step.value) {
          case ImportStep.pick:
            return _PickStep(c: c);
          case ImportStep.columns:
            return _ColumnsStep(c: c);
          case ImportStep.matching:
            return _ProgressStep(c: c, title: 'p_import_matching'.tr, onCancel: c.cancelMatching);
          case ImportStep.review:
            return _ReviewStep(c: c);
          case ImportStep.saving:
            return _ProgressStep(c: c, title: 'p_import_saving'.tr);
          case ImportStep.done:
            return _DoneStep(c: c);
        }
      }),
    );
  }
}

class _PickStep extends StatelessWidget {
  const _PickStep({required this.c});

  final ProductImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Icon(Icons.upload_file_rounded, size: 56, color: p.primaryText),
        const SizedBox(height: 12),
        Text('p_import_intro'.tr, style: t.bodyLarge),
        const SizedBox(height: 8),
        Text('p_import_formats'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
        const SizedBox(height: 16),
        NoticeBanner('p_import_note'.tr, kind: NoticeKind.info),
        Obx(() {
          final String? key = c.importError.value;
          if (key == null) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.only(top: 12), child: NoticeBanner(key.tr));
        }),
        const SizedBox(height: 24),
        AppButton(label: 'p_import_choose_file'.tr, icon: Icons.folder_open_rounded, onPressed: c.pickFile),
      ],
    );
  }
}

class _ColumnsStep extends StatelessWidget {
  const _ColumnsStep({required this.c});

  final ProductImportController c;

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
              Text('p_import_columns_intro'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
              const SizedBox(height: 16),
              Obx(() => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('p_import_has_header'.tr),
                    value: c.columns.value.hasHeader,
                    onChanged: c.setHasHeader,
                  )),
              const SizedBox(height: 8),
              Obx(() => _ColumnPicker(
                    label: 'p_import_name_column'.tr,
                    icon: Icons.medication_outlined,
                    table: c.table.value,
                    value: c.columns.value.nameColumn,
                    onChanged: c.setNameColumn,
                  )),
              const SizedBox(height: 12),
              Obx(() => _ColumnPicker(
                    label: 'p_import_price_column'.tr,
                    icon: Icons.payments_outlined,
                    table: c.table.value,
                    value: c.columns.value.priceColumn,
                    onChanged: c.setPriceColumn,
                  )),
              const SizedBox(height: 16),
              Obx(() {
                final String? key = c.importError.value;
                if (key != null) return NoticeBanner(key.tr);
                if (c.sameColumn) return NoticeBanner('p_import_err_same_column'.tr, kind: NoticeKind.warning);
                return const SizedBox.shrink();
              }),
              const SizedBox(height: 8),
              SectionCard(
                title: 'p_import_preview'.tr,
                icon: Icons.table_rows_outlined,
                child: Obx(() {
                  final List<ImportLine> shown = c.lines.take(5).toList();
                  if (shown.isEmpty) return Text('p_import_err_no_rows'.tr);
                  return Column(
                    children: <Widget>[
                      for (final ImportLine l in shown)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              LtrText(
                                l.price == null ? '—' : Fmt.money(l.price!, c.currency),
                                style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 8),
              Obx(() => Text(
                    'p_import_rows_summary'.trParams(<String, String>{'n': '${c.usableLines.length}', 'skipped': '${c.skippedNoPrice}'}),
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                  )),
            ],
          ),
        ),
        BottomActionBar(
          child: Obx(() => AppButton(
                label: 'p_import_match_action'.tr,
                icon: Icons.manage_search_rounded,
                loading: c.submitting.value,
                onPressed: c.canMatch ? c.startMatching : null,
              )),
        ),
      ],
    );
  }
}

class _ColumnPicker extends StatelessWidget {
  const _ColumnPicker({required this.label, required this.icon, required this.table, required this.value, required this.onChanged});

  final String label;
  final IconData icon;
  final SheetTable? table;
  final int value;
  final ValueChanged<int> onChanged;

  String _title(int col) {
    final String sample = table == null ? '' : table!.cell(0, col);
    final String head = 'p_import_column_n'.trParams(<String, String>{'n': '${col + 1}'});
    return sample.isEmpty ? head : '$head: $sample';
  }

  @override
  Widget build(BuildContext context) {
    final int count = table?.columnCount ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return DropdownButtonFormField<int>(
      value: value < count ? value : 0,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: <DropdownMenuItem<int>>[
        for (int i = 0; i < count; i++) DropdownMenuItem<int>(value: i, child: Text(_title(i), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (int? v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.c, required this.title, this.onCancel});

  final ProductImportController c;
  final String title;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(title, style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Obx(() => LinearProgressIndicator(value: c.progress.value <= 0 ? null : c.progress.value, minHeight: 8)),
            const SizedBox(height: 8),
            Obx(() => LtrText('${(c.progress.value * 100).round()}%', style: t.bodyMedium)),
            if (onCancel != null) ...<Widget>[
              const SizedBox(height: 24),
              TextButton(onPressed: onCancel, child: Text('cancel'.tr)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which rows the review list shows.
enum _Tab { review, matched, unmatched }

class _ReviewStep extends StatefulWidget {
  const _ReviewStep({required this.c});

  final ProductImportController c;

  @override
  State<_ReviewStep> createState() => _ReviewStepState();
}

class _ReviewStepState extends State<_ReviewStep> {
  late _Tab tab;

  @override
  void initState() {
    super.initState();
    final ProductImportController c = widget.c;
    tab = c.count(ImportRowKind.review) > 0 ? _Tab.review : (c.count(ImportRowKind.auto) > 0 ? _Tab.matched : _Tab.unmatched);
  }

  ImportRowKind _kind(_Tab t) {
    switch (t) {
      case _Tab.review:
        return ImportRowKind.review;
      case _Tab.matched:
        return ImportRowKind.auto;
      case _Tab.unmatched:
        return ImportRowKind.unmatched;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProductImportController c = widget.c;
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Obx(() => Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final _Tab x in _Tab.values)
                    ChoiceChip(
                      label: Text('p_import_tab_${x.name}'.trParams(<String, String>{'n': '${c.count(_kind(x))}'})),
                      selected: tab == x,
                      onSelected: (bool _) => setState(() => tab = x),
                    ),
                ],
              )),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(_hint(tab).tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
        ),
        if (tab == _Tab.matched)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton(onPressed: () => c.setAll(true), child: Text('p_import_select_all'.tr)),
                  TextButton(onPressed: () => c.setAll(false), child: Text('p_import_select_none'.tr)),
                ],
              ),
            ),
          ),
        Expanded(
          child: Obx(() {
            final List<ImportRow> shown = c.rows.where((ImportRow r) => r.kind == _kind(tab)).toList();
            if (shown.isEmpty) {
              return Center(child: Text('p_import_tab_empty'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: shown.length,
              itemBuilder: (BuildContext context, int i) => _RowTile(c: c, row: shown[i]),
            );
          }),
        ),
        BottomActionBar(
          child: Obx(() => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (c.undecidedCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'p_import_undecided'.trParams(<String, String>{'n': '${c.undecidedCount}'}),
                        style: t.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ),
                  AppButton(
                    label: 'p_import_save_action'.trParams(<String, String>{'n': '${c.readyCount}'}),
                    icon: Icons.check_rounded,
                    loading: c.submitting.value,
                    onPressed: c.readyCount > 0 ? c.save : null,
                  ),
                ],
              )),
        ),
      ],
    );
  }

  static String _hint(_Tab t) {
    switch (t) {
      case _Tab.review:
        return 'p_import_hint_review';
      case _Tab.matched:
        return 'p_import_hint_matched';
      case _Tab.unmatched:
        return 'p_import_hint_unmatched';
    }
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.c, required this.row});

  final ProductImportController c;
  final ImportRow row;

  Future<void> _pick() async {
    final List<({int value, String label, IconData? icon})> options = <({int value, String label, IconData? icon})>[
      for (int i = 0; i < row.matches.length; i++)
        (
          value: i,
          label: '${row.matches[i].medicine.displayName(isArabicNow())}'
              '${row.matches[i].medicine.specLine.isEmpty ? '' : ' · ${row.matches[i].medicine.specLine}'}'
              ' (${(row.matches[i].score * 100).round()}%)',
          icon: Icons.medication_outlined,
        ),
      (value: -1, label: 'p_import_skip_row'.tr, icon: Icons.block_rounded),
    ];
    final int? picked = await choiceSheet<int>(title: 'p_import_choose_title'.tr, options: options);
    if (picked == null) return;
    c.choose(row, picked < 0 ? null : row.matches[picked]);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Obx(() {
          final NameMatch? m = row.chosen.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'p_import_line'.trParams(<String, String>{'line': '${row.line.line}', 'name': row.line.name}),
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  LtrText(Fmt.money(row.line.price ?? 0, c.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              if (m != null)
                Row(
                  children: <Widget>[
                    Checkbox(value: row.included.value, onChanged: (bool? v) => c.toggle(row, v ?? false)),
                    Expanded(child: MedicineTitle(m.medicine)),
                    if (row.kind != ImportRowKind.unmatched) TextButton(onPressed: _pick, child: Text('change'.tr)),
                  ],
                )
              else if (row.matches.isEmpty)
                const StatusChipNone()
              else
                AppButton(
                  label: 'p_import_choose_action'.trParams(<String, String>{'n': '${row.matches.length}'}),
                  icon: Icons.touch_app_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: _pick,
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// "Not found in the catalogue" marker of an unmatched row (icon + text).
class StatusChipNone extends StatelessWidget {
  const StatusChipNone({super.key});

  @override
  Widget build(BuildContext context) =>
      StatusChip(label: 'p_import_not_found'.tr, color: AppColors.textSecondary, icon: Icons.search_off_rounded);
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.c});

  final ProductImportController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ImportResult? r = c.result.value;
    if (r == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
        const SizedBox(height: 12),
        Text('p_import_done_title'.trParams(<String, String>{'n': '${r.saved}'}), style: t.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        SectionCard(
          title: 'p_import_result'.tr,
          icon: Icons.summarize_outlined,
          child: Column(
            children: <Widget>[
              InfoRow(label: 'p_import_result_added'.tr, value: '${r.inserted}', ltr: true),
              InfoRow(label: 'p_import_result_updated'.tr, value: '${r.updated}', ltr: true),
              InfoRow(label: 'p_import_result_skipped'.tr, value: '${r.skipped + c.skippedNoPrice}', ltr: true),
              if (c.duplicates.value > 0) InfoRow(label: 'p_import_result_duplicates'.tr, value: '${c.duplicates.value}', ltr: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppButton(label: 'p_import_back_to_list'.tr, icon: Icons.list_alt_rounded, onPressed: () => Get.back<dynamic>()),
        const SizedBox(height: 8),
        AppButton(label: 'p_import_another'.tr, icon: Icons.upload_file_rounded, variant: AppButtonVariant.secondary, onPressed: c.importAnother),
      ],
    );
  }
}
