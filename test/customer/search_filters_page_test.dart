import 'package:dawak/core/widgets/app_button.dart';
import 'package:dawak/data/models/medicine.dart';
import 'package:dawak/features/customer/controllers/medicine_search_controller.dart';
import 'package:dawak/features/customer/views/search_filters_page.dart';
import 'package:dawak/features/customer/widgets/customer_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/harness.dart';

void main() {
  late AppHarness h;
  late MedicineSearchController c;

  setUp(() async {
    h = await AppHarness.create();
    c = MedicineSearchController();
    Get.put<MedicineSearchController>(c);
  });

  tearDown(() {
    Get.delete<MedicineSearchController>();
    h.dispose();
  });

  testWidgets('shows CircularProgressIndicator while categories are loading', (WidgetTester tester) async {
    c.categoriesLoading.value = true;
    c.categoriesLoaded.value = false;
    c.categoriesFailed.value = false;

    await tester.pumpWidget(const GetMaterialApp(home: SearchFiltersPage()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(InlineNotice), findsNothing);
  });

  testWidgets('shows category chips when loading succeeds', (WidgetTester tester) async {
    c.categoriesLoading.value = false;
    c.categoriesLoaded.value = true;
    c.categoriesFailed.value = false;
    c.categories.assignAll(<MedicineCategory>[
      MedicineCategory.fromJson(<String, dynamic>{
        'id': 'cat-1',
        'name_ar': 'مسكنات',
        'name_en': 'Pain relief',
        'sort_order': 1,
        'is_active': true,
      }),
    ]);

    await tester.pumpWidget(const GetMaterialApp(home: SearchFiltersPage()));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(InlineNotice), findsNothing);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text('Pain relief'), findsOneWidget);
  });

  testWidgets('shows error notice with retry button when loading fails, and tapping retry reloads', (WidgetTester tester) async {
    h.api.tables['medicine_categories'] = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'cat-1', 'name_ar': 'مسكنات', 'name_en': 'Pain relief', 'sort_order': 1, 'is_active': true},
    ];
    c.categoriesLoading.value = false;
    c.categoriesLoaded.value = false;
    c.categoriesFailed.value = true;

    await tester.pumpWidget(const GetMaterialApp(home: SearchFiltersPage()));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'retry'.tr), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'retry'.tr));
    await tester.pumpAndSettle();

    expect(c.categoriesLoaded.value, isTrue);
    expect(c.categoriesFailed.value, isFalse);
    expect(find.byType(InlineNotice), findsNothing);
    expect(find.text('Pain relief'), findsOneWidget);
  });
}
