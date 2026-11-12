import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/products_controller.dart';
import '../widgets/pharmacist_widgets.dart';

/// "My medicines" tab (P-21): search, availability and category filters, the list and the add / import / confirm
/// actions (owners and managers).
class ProductsTab extends StatelessWidget {
  const ProductsTab({super.key});

  static String _filterLabel(ProductFilter f) => 'p_filter_${f.name}'.tr;

  @override
  Widget build(BuildContext context) {
    final ProductsController c = Get.find<ProductsController>();
    return Scaffold(
      floatingActionButton: c.canManage
          ? FloatingActionButton.extended(
              onPressed: c.openAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text('p_product_add'.tr),
            )
          : null,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: <Widget>[
                Expanded(child: SearchField(hint: 'p_products_search_hint'.tr, onChanged: c.search, onSubmitted: c.search)),
                if (c.canManage)
                  IconButton(
                    tooltip: 'p_import_title'.tr,
                    onPressed: c.openImport,
                    icon: const Icon(Icons.upload_file_rounded),
                  ),
                if (c.canManage)
                  IconButton(
                    tooltip: 'p_confirm_list_action'.tr,
                    onPressed: c.confirmListing,
                    icon: const Icon(Icons.fact_check_outlined),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Obx(() => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  children: <Widget>[
                    for (final ProductFilter f in ProductFilter.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(_filterLabel(f)),
                          selected: c.filter.value == f,
                          onSelected: (bool _) => c.setFilter(f),
                        ),
                      ),
                    for (final MedicineCategory cat in c.categories)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FilterChip(
                          label: Text(cat.name(isArabicNow())),
                          selected: c.categoryId.value == cat.id,
                          onSelected: (bool _) => c.setCategory(cat.id),
                        ),
                      ),
                  ],
                )),
          ),
          Expanded(
            child: PagedListView<PharmacyProduct>(
              paged: c.paged,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              empty: EmptyState(
                icon: Icons.medication_outlined,
                title: 'p_products_empty'.tr,
                message: c.canManage ? 'p_products_empty_hint'.tr : 'p_products_empty_cashier'.tr,
                actionLabel: c.canManage ? 'p_product_add'.tr : null,
                onAction: c.canManage ? c.openAdd : null,
              ),
              itemBuilder: (BuildContext context, PharmacyProduct p) => ProductTile(
                product: p,
                currency: c.currency,
                onTap: () => c.openProduct(p),
                onToggleAvailable: c.canManage ? (bool v) => c.setAvailable(p, v) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
