import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/product_add_controller.dart';
import '../widgets/pharmacist_widgets.dart';

/// Add a catalogue medicine to the pharmacy (P-25).
class ProductAddPage extends StatelessWidget {
  const ProductAddPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ProductAddController c = Get.find<ProductAddController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_product_add'.tr)),
      body: Obx(() => c.selected.value == null ? _Picker(c: c) : _FormView(c: c, medicine: c.selected.value!)),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({required this.c});

  final ProductAddController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: SearchField(hint: 'p_add_search_hint'.tr, autofocus: true, onChanged: c.search, onSubmitted: c.search),
        ),
        Expanded(
          child: Obx(() {
            if (c.searching.value) return const Center(child: CircularProgressIndicator());
            final f = c.searchFailure.value;
            if (f != null) return ErrorState(failure: f);
            if (!c.searched.value) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.search_rounded, size: 48, color: p.textSecondary),
                    const SizedBox(height: 12),
                    Text('p_add_search_prompt'.tr, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
                    const SizedBox(height: 16),
                    AppButton(label: 'p_propose_open'.tr, icon: Icons.add_circle_outline_rounded, variant: AppButtonVariant.secondary, expand: false, onPressed: c.proposeNew),
                  ],
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                for (final Medicine m in c.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(onTap: () => c.choose(m), child: MedicineTitle(m)),
                  ),
                if (c.results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('p_add_no_results'.tr, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
                  ),
                const SizedBox(height: 8),
                AppButton(label: 'p_propose_open'.tr, icon: Icons.add_circle_outline_rounded, variant: AppButtonVariant.secondary, onPressed: c.proposeNew),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView({required this.c, required this.medicine});

  final ProductAddController c;
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Form(
        key: c.form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppCard(
              child: Row(
                children: <Widget>[
                  Expanded(child: MedicineTitle(medicine)),
                  TextButton(onPressed: c.clearChoice, child: Text('change'.tr)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Obx(() {
              final String? existing = c.existingProductId.value;
              if (existing == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    NoticeBanner('p_product_exists'.tr, kind: NoticeKind.warning),
                    const SizedBox(height: 8),
                    AppButton(label: 'p_product_open_existing'.tr, variant: AppButtonVariant.secondary, onPressed: c.openExisting),
                  ],
                ),
              );
            }),
            AppTextField(
              label: 'p_product_price_label'.trParams(<String, String>{'currency': c.currency == 'USD' ? 'currency_usd'.tr : 'currency_syp'.tr}),
              controller: c.price,
              ltr: true,
              prefixIcon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              validator: (String? v) => Validators.price(v, allowZero: false),
            ),
            const SizedBox(height: 24),
            Obx(() => AppButton(
                  label: 'p_product_add_action'.tr,
                  icon: Icons.check_rounded,
                  loading: c.submitting.value,
                  onPressed: c.save,
                )),
          ],
        ),
      ),
    );
  }
}
