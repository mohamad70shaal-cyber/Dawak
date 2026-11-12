import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../controllers/medicine_search_controller.dart';
import 'customer_widgets.dart';

/// Filter button with the number of active filters.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.controller});

  final MedicineSearchController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() => IconButton.filledTonal(
          tooltip: 'filter'.tr,
          onPressed: () {
            controller.beginFilterEdit();
            Get.toNamed<dynamic>(AppRoutes.searchFilters);
          },
          icon: Badge(
            isLabelVisible: controller.filterCount > 0,
            label: Text('${controller.filterCount}'),
            child: const Icon(Icons.tune_rounded),
          ),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ));
  }
}

/// Removable chips for the filters that are currently active.
class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({super.key, required this.controller});

  final MedicineSearchController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String? cat = controller.categoryId.value;
      final String? form = controller.dosageForm.value;
      if (cat == null && form == null) return const SizedBox.shrink();
      final String catName = controller.categoryName(cat, isArabicNow());
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              if (cat != null)
                InputChip(
                  label: Text(catName.isEmpty ? 'c_filter_category'.tr : catName),
                  deleteButtonTooltipMessage: 'remove'.tr,
                  onDeleted: controller.removeCategoryFilter,
                ),
              if (form != null)
                InputChip(
                  label: Text(form),
                  deleteButtonTooltipMessage: 'remove'.tr,
                  onDeleted: controller.removeFormFilter,
                ),
            ],
          ),
        ),
      );
    });
  }
}
