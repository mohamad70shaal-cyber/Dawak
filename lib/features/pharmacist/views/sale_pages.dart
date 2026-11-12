import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/sale.dart';
import '../controllers/sales_controllers.dart';

/// "Sale completed" (P-42).
class PosCompletedPage extends StatelessWidget {
  const PosCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['saleId'] ?? '';
    final PosCompletedController c = Get.find<PosCompletedController>(tag: id);
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('p_sale_done_title'.tr), automaticallyImplyLeading: false),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => Obx(() {
          final Sale? s = c.sale.value;
          if (s == null) return const SizedBox.shrink();
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.check_circle_rounded, size: 80, color: AppColors.success),
                    const SizedBox(height: 16),
                    Text('p_sale_done_heading'.tr, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    LtrText(s.invoiceNo, style: t.titleMedium?.copyWith(color: pal.textSecondary)),
                    const SizedBox(height: 16),
                    LtrText(Fmt.money(s.total, s.currency), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                    if (s.hasDiscount) ...<Widget>[
                      const SizedBox(height: 4),
                      Text('p_sale_discount_given'.trParams(<String, String>{'amount': Fmt.money(s.discountAmount, s.currency)}), style: t.bodyMedium?.copyWith(color: pal.textSecondary)),
                    ],
                    const SizedBox(height: 8),
                    Text('p_sale_done_cash'.tr, style: t.bodyMedium?.copyWith(color: pal.textSecondary)),
                    const SizedBox(height: 32),
                    AppButton(label: 'p_sale_new'.tr, icon: Icons.add_shopping_cart_rounded, onPressed: c.newSale),
                    const SizedBox(height: 12),
                    AppButton(label: 'p_sale_view_receipt'.tr, icon: Icons.receipt_long_rounded, variant: AppButtonVariant.secondary, onPressed: c.openReceipt),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Receipt / sale details (P-43, P-51) with PDF share and print (P-44, P-45, P-52).
class SaleDetailsPage extends StatelessWidget {
  const SaleDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final SaleDetailsController c = Get.find<SaleDetailsController>(tag: id);
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('p_sale_details'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => Obx(() {
          final Sale? s = c.sale.value;
          if (s == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(child: Text(s.pharmacyName, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center)),
                    if (s.pharmacyAddress.isNotEmpty) Center(child: Text(s.pharmacyAddress, style: t.bodySmall?.copyWith(color: pal.textSecondary), textAlign: TextAlign.center)),
                    if ((s.pharmacyPhone ?? '').isNotEmpty) Center(child: LtrText(s.pharmacyPhone!, style: t.bodySmall?.copyWith(color: pal.textSecondary))),
                    const Divider(height: 24),
                    InfoRow(label: 'p_receipt_invoice'.tr, value: s.invoiceNo, ltr: true, bold: true),
                    InfoRow(label: 'p_receipt_date'.tr, value: Fmt.dateTime(s.createdAt), ltr: true),
                    if (s.cashierName.isNotEmpty) InfoRow(label: 'p_receipt_cashier'.tr, value: s.cashierName),
                    if (s.isFromOrder)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ActionChip(
                            avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                            label: Text('p_sale_from_order'.tr),
                            onPressed: c.openOrder,
                          ),
                        ),
                      ),
                    const Divider(height: 24),
                    for (final SaleItem i in s.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(i.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  if ((i.strength ?? '').isNotEmpty) Text(i.strength!, style: t.bodySmall?.copyWith(color: pal.textSecondary)),
                                  LtrText('${Fmt.money(i.unitPrice, s.currency)} × ${i.quantity}', style: t.bodySmall?.copyWith(color: pal.textSecondary)),
                                ],
                              ),
                            ),
                            LtrText(Fmt.money(i.lineTotal, s.currency), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    const Divider(height: 24),
                    InfoRow(label: 'p_receipt_subtotal'.tr, value: Fmt.money(s.subtotal, s.currency), ltr: true),
                    if (s.hasDiscount) InfoRow(label: 'p_receipt_discount'.tr, value: '-${Fmt.money(s.discountAmount, s.currency)}', ltr: true),
                    InfoRow(label: 'p_receipt_grand_total'.tr, value: Fmt.money(s.total, s.currency), ltr: true, bold: true),
                    const SizedBox(height: 8),
                    Center(child: Text('p_receipt_cash'.tr, style: t.bodySmall?.copyWith(color: pal.textSecondary))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Obx(() => AppButton(label: 'p_receipt_share'.tr, icon: Icons.ios_share_rounded, loading: c.working.value, onPressed: c.sharePdf)),
              const SizedBox(height: 8),
              Obx(() => AppButton(label: 'p_receipt_print'.tr, icon: Icons.print_rounded, variant: AppButtonVariant.secondary, loading: c.working.value, onPressed: c.printReceipt)),
            ],
          );
        }),
      ),
    );
  }
}

/// Sales history (P-48).
class SalesHistoryPage extends StatelessWidget {
  const SalesHistoryPage({super.key});

  Future<void> _pickCustom(BuildContext context, SalesHistoryController c) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: c.customFrom != null && c.customTo != null ? DateTimeRange(start: c.customFrom!, end: c.customTo!) : null,
    );
    if (r != null) c.setCustom(r.start, r.end);
  }

  @override
  Widget build(BuildContext context) {
    final SalesHistoryController c = Get.find<SalesHistoryController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette pal = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('p_sales_title'.tr)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(hint: 'p_sales_search_hint'.tr, onChanged: c.search, onSubmitted: c.search),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Obx(() {
              final SalesRange cur = c.range.value;
              Widget chip(String label, SalesRange r, {VoidCallback? onTap}) => ChoiceChip(
                    label: Text(label),
                    selected: cur == r,
                    onSelected: (bool _) => onTap != null ? onTap() : c.select(r),
                  );
              return Wrap(
                spacing: 8,
                children: <Widget>[
                  chip('all'.tr, SalesRange.all),
                  chip('today'.tr, SalesRange.today),
                  chip('this_week'.tr, SalesRange.week),
                  chip('this_month'.tr, SalesRange.month),
                  chip(
                    cur == SalesRange.custom && c.customFrom != null ? '${Fmt.date(c.customFrom)} – ${Fmt.date(c.customTo)}' : 'custom_range'.tr,
                    SalesRange.custom,
                    onTap: () => _pickCustom(context, c),
                  ),
                ],
              );
            }),
          ),
          if (c.isCashier)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('p_sales_cashier_note'.tr, style: t.bodySmall?.copyWith(color: pal.textSecondary)),
            ),
          Expanded(
            child: PagedListView<SaleSummary>(
              paged: c.paged,
              empty: EmptyState(icon: Icons.receipt_long_outlined, title: 'p_sales_empty'.tr, message: 'p_sales_empty_hint'.tr),
              itemBuilder: (BuildContext context, SaleSummary s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  onTap: () => c.openSale(s),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            LtrText(s.invoiceNo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(Fmt.dateTime(s.createdAt), style: t.bodySmall?.copyWith(color: pal.textSecondary)),
                            if (s.orderId != null || s.discountAmount > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: <Widget>[
                                    if (s.orderId != null) StatusChip(label: 'p_sale_from_order'.tr, color: AppColors.primary, icon: Icons.inventory_2_outlined),
                                    if (s.discountAmount > 0) StatusChip(label: 'p_sale_has_discount'.tr, color: AppColors.warning, icon: Icons.percent_rounded),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      LtrText(Fmt.money(s.total, s.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
