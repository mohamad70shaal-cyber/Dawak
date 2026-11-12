import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/medicine_search_controller.dart';
import '../widgets/customer_widgets.dart';
import '../widgets/search_filter_widgets.dart';

/// Search results (C-11): paged list for the current query and filters.
class SearchResultsPage extends StatelessWidget {
  const SearchResultsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MedicineSearchController c = Get.find<MedicineSearchController>();
    return Scaffold(
      appBar: AppBar(title: Text('c_results_title'.tr)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SearchField(controller: c.text, hint: 'c_search_hint'.tr, onChanged: c.runSearch, onSubmitted: c.runSearch),
                ),
                const SizedBox(width: 8),
                FilterButton(controller: c),
              ],
            ),
          ),
          ActiveFilterChips(controller: c),
          Expanded(
            child: Obx(() {
              if (!c.hasQuery) {
                return EmptyState(icon: Icons.search_rounded, title: 'c_search_min_title'.tr, message: 'c_search_min_hint'.tr);
              }
              return PagedListView<Medicine>(
                paged: c.results,
                empty: EmptyState(icon: Icons.search_off_rounded, title: 'c_no_results'.tr, message: 'c_no_results_hint'.tr),
                itemBuilder: (BuildContext context, Medicine m) =>
                    MedicineTile(medicine: m, onTap: () => Get.toNamed<dynamic>(AppRoutes.medicine(m.id))),
              );
            }),
          ),
        ],
      ),
    );
  }
}
