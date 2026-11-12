import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/admin_medicines_controller.dart';
import '../widgets/admin_widgets.dart';

/// Medicines tab (A-07): search and filter the catalogue, review proposals, add an entry.
class AdminMedicinesTab extends StatelessWidget {
  const AdminMedicinesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminMedicinesController c = Get.find<AdminMedicinesController>();
    return Scaffold(
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          FloatingActionButton.small(
            heroTag: 'fab_import',
            onPressed: c.openImport,
            tooltip: 'a_import_import'.tr,
            child: const Icon(Icons.upload_file_rounded),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'fab_add',
            onPressed: c.openNew,
            icon: const Icon(Icons.add_rounded),
            label: Text('a_medicine_add'.tr),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(hint: 'a_medicines_search_hint'.tr, onChanged: c.search, onSubmitted: c.search),
          ),
          FilterChipBar<MedicineFilter>(
            values: MedicineFilter.values,
            selected: c.filter,
            label: (MedicineFilter f) => 'a_med_filter_${f.name}'.tr,
            onSelected: c.setFilter,
          ),
          Expanded(
            child: PagedListView<Medicine>(
              paged: c.paged,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              empty: Obx(() => EmptyState(
                    icon: Icons.medication_outlined,
                    title: 'a_medicines_empty'.tr,
                    message: 'a_medicines_empty_${c.filter.value.name}'.tr,
                  )),
              itemBuilder: (BuildContext context, Medicine m) => AdminMedicineTile(medicine: m, onTap: () => c.openMedicine(m)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A catalogue row: names in both languages, strength and form, and the review status.
class AdminMedicineTile extends StatelessWidget {
  const AdminMedicineTile({super.key, required this.medicine, required this.onTap});

  final Medicine medicine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final bool ar = isArabicNow();
    final String second = medicine.secondaryName(ar);
    return Semantics(
      button: true,
      label: '${medicine.displayName(ar)}, ${medicine.specLine}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(medicine.displayName(ar), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (second.isNotEmpty) Text(second, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (medicine.specLine.isNotEmpty) Text(medicine.specLine, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CatalogStatusChip(medicine.catalogStatus),
          ],
        ),
      ),
    );
  }
}
