import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/product_edit_controller.dart';
import '../widgets/pharmacist_widgets.dart';

/// Edit the price and the availability of a list row (P-27).
class ProductEditPage extends StatelessWidget {
  const ProductEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ProductEditController c = Get.find<ProductEditController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_product_edit'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: c.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Obx(() {
                  final PharmacyProduct? p = c.product.value;
                  return p == null ? const SizedBox.shrink() : AppCard(child: MedicineTitle(p.medicine));
                }),
                const SizedBox(height: 12),
                NoticeBanner('p_edit_catalogue_note'.tr, kind: NoticeKind.info),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'p_product_price'.tr,
                  controller: c.price,
                  ltr: true,
                  prefixIcon: Icons.payments_outlined,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  validator: (String? v) => Validators.price(v, allowZero: false),
                ),
                const SizedBox(height: 8),
                Text('p_edit_price_hint'.tr, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                Obx(() => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('p_product_available_switch'.tr),
                      subtitle: Text((c.available.value ? 'p_product_available_on_hint' : 'p_product_available_off_hint').tr),
                      value: c.available.value,
                      onChanged: (bool v) => c.available.value = v,
                    )),
                const SizedBox(height: 24),
                Obx(() => AppButton(label: 'save'.tr, icon: Icons.check_rounded, loading: c.submitting.value, onPressed: c.save)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
