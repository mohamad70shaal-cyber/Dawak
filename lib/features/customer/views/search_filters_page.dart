import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../data/models/medicine.dart';
import '../controllers/medicine_search_controller.dart';
import '../widgets/customer_widgets.dart';

/// Search filters (C-12): category and dosage form. Edits a draft; "Apply" activates it.
class SearchFiltersPage extends StatelessWidget {
  const SearchFiltersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MedicineSearchController c = Get.find<MedicineSearchController>();
    return Scaffold(
      appBar: AppBar(title: Text('c_filters_title'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionTitle('c_filter_category'.tr),
          Obx(() {
            if (c.categoriesLoading.value || (!c.categoriesLoaded.value && !c.categoriesFailed.value)) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (c.categoriesFailed.value) {
              return InlineNotice(
                'c_filter_categories_failed'.tr,
                tone: NoticeTone.warning,
                action: AppButton(
                  label: 'retry'.tr,
                  expand: false,
                  variant: AppButtonVariant.secondary,
                  onPressed: c.reloadCategories,
                ),
              );
            }
            final bool ar = isArabicNow();
            final String? sel = c.draftCategoryId.value;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(label: Text('all'.tr), selected: sel == null, onSelected: (_) => c.draftCategoryId.value = null),
                for (final MedicineCategory cat in c.categories)
                  ChoiceChip(label: Text(cat.name(ar)), selected: sel == cat.id, onSelected: (_) => c.draftCategoryId.value = cat.id),
              ],
            );
          }),
          const SizedBox(height: 24),
          SectionTitle('c_filter_form'.tr),
          Obx(() {
            final String? sel = c.draftDosageForm.value;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(label: Text('all'.tr), selected: sel == null, onSelected: (_) => c.draftDosageForm.value = null),
                for (final DosageFormOption f in MedicineSearchController.dosageForms)
                  ChoiceChip(label: Text(f.labelKey.tr), selected: sel == f.value, onSelected: (_) => c.draftDosageForm.value = f.value),
              ],
            );
          }),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        child: Row(
          children: <Widget>[
            Expanded(child: AppButton(label: 'c_filters_reset'.tr, variant: AppButtonVariant.secondary, onPressed: c.clearDraft)),
            const SizedBox(width: 12),
            Expanded(
              child: AppButton(
                label: 'apply'.tr,
                onPressed: () async {
                  Get.back<dynamic>();
                  await c.applyFilters();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
