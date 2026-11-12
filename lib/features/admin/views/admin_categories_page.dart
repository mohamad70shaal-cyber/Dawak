import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/admin_categories_controller.dart';

/// Category management (A-09).
class AdminCategoriesPage extends StatelessWidget {
  const AdminCategoriesPage({super.key});

  Future<void> _openForm(AdminCategoriesController c) async {
    await Get.bottomSheet<void>(
      _CategoryForm(c: c),
      isScrollControlled: true,
      backgroundColor: Get.theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AdminCategoriesController c = Get.find<AdminCategoriesController>();
    return Scaffold(
      appBar: AppBar(title: Text('a_categories_title'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          c.startNew();
          _openForm(c);
        },
        icon: const Icon(Icons.add_rounded),
        label: Text('a_category_add'.tr),
      ),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        empty: EmptyState(icon: Icons.category_outlined, title: 'a_categories_empty'.tr, message: 'a_categories_empty_hint'.tr),
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: () => c.refresh(silent: true),
          child: Obx(() => ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: c.categories.length,
                separatorBuilder: (BuildContext _, int __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int i) {
                  final MedicineCategory cat = c.categories[i];
                  return _CategoryTile(
                    category: cat,
                    onEdit: () {
                      c.startEdit(cat);
                      _openForm(c);
                    },
                    onToggle: () => c.toggleActive(cat),
                  );
                },
              )),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onEdit, required this.onToggle});

  final MedicineCategory category;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String? en = category.nameEn;
    return AppCard(
      onTap: onEdit,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(category.nameAr, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (en != null && en.isNotEmpty) LtrText(en, style: t.bodySmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    StatusChip(
                      label: (category.isActive ? 'a_category_on' : 'a_category_off').tr,
                      color: category.isActive ? AppColors.success : AppColors.textSecondary,
                      icon: category.isActive ? Icons.check_circle_rounded : Icons.pause_circle_outline_rounded,
                    ),
                    Text('${'a_category_order'.tr}: ', style: t.labelSmall?.copyWith(color: p.textSecondary)),
                    LtrText('${category.sortOrder}', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: category.isActive, onChanged: (bool _) => onToggle()),
        ],
      ),
    );
  }
}

class _CategoryForm extends StatelessWidget {
  const _CategoryForm({required this.c});

  final AdminCategoriesController c;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: c.form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Obx(() => Text((c.editing.value == null ? 'a_category_add' : 'a_category_edit').tr, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(height: 16),
              Obx(() => c.notice.value == null
                  ? const SizedBox.shrink()
                  : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(c.notice.value!, kind: NoticeKind.error))),
              AppTextField(label: 'a_category_name_ar'.tr, controller: c.nameAr, maxLength: 80, textInputAction: TextInputAction.next, validator: c.nameArRule),
              const SizedBox(height: 12),
              AppTextField(label: 'a_category_name_en'.tr, controller: c.nameEn, ltr: true, maxLength: 80, textInputAction: TextInputAction.next, validator: c.nameEnRule),
              const SizedBox(height: 12),
              AppTextField(
                label: 'a_category_order'.tr,
                helper: 'a_category_order_hint'.tr,
                controller: c.sortOrder,
                ltr: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                validator: c.sortRule,
              ),
              const SizedBox(height: 8),
              Obx(() => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('a_category_active'.tr),
                    subtitle: Text('a_category_active_hint'.tr),
                    value: c.isActive.value,
                    onChanged: (bool v) => c.isActive.value = v,
                  )),
              const SizedBox(height: 12),
              Obx(() => AppButton(
                    label: 'save'.tr,
                    icon: Icons.check_rounded,
                    loading: c.submitting.value,
                    onPressed: () async {
                      if (await c.save()) Get.back<void>();
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
