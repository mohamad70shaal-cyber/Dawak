import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/enums.dart';
import '../controllers/availability_answer_controller.dart';
import '../controllers/availability_inbox_controller.dart';
import '../widgets/order_widgets.dart';
import '../widgets/pharmacist_widgets.dart';

/// "Your answer so far" chip of a request: waiting, available (with the price), unavailable, or closed.
class RequestAnswerChip extends StatelessWidget {
  const RequestAnswerChip(this.request, {super.key, required this.currency});

  final InboxRequest request;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (!request.isOpen) return RequestStatusChip(request.status);
    switch (request.answer) {
      case RequestAnswer.available:
        final double? price = request.answerPrice;
        return StatusChip(
          label: price == null ? 'p_req_you_available'.tr : 'p_req_you_available_price'.trParams(<String, String>{'price': Fmt.money(price, currency)}),
          color: AppColors.success,
          icon: Icons.check_circle_rounded,
        );
      case RequestAnswer.unavailable:
        return StatusChip(label: 'p_req_you_unavailable'.tr, color: AppColors.textSecondary, icon: Icons.remove_circle_outline_rounded);
      case null:
        return StatusChip(label: 'p_req_waiting_you'.tr, color: AppColors.warning, icon: Icons.hourglass_top_rounded);
    }
  }
}

/// Requests inbox (P-32).
class AvailabilityInboxPage extends StatelessWidget {
  const AvailabilityInboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AvailabilityInboxController c = Get.find<AvailabilityInboxController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('p_req_inbox_title'.tr)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Obx(() => Wrap(
                  spacing: 8,
                  children: <Widget>[
                    ChoiceChip(label: Text('p_req_filter_open'.tr), selected: c.onlyOpen.value, onSelected: (bool _) => c.setOnlyOpen(true)),
                    ChoiceChip(label: Text('p_req_filter_week'.tr), selected: !c.onlyOpen.value, onSelected: (bool _) => c.setOnlyOpen(false)),
                  ],
                )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('p_req_inbox_hint'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
          ),
          Expanded(
            child: PagedListView<InboxRequest>(
              paged: c.paged,
              empty: EmptyState(icon: Icons.mark_chat_unread_outlined, title: 'p_req_empty'.tr, message: 'p_req_empty_hint'.tr),
              itemBuilder: (BuildContext context, InboxRequest r) => _RequestTile(c: c, r: r),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.c, required this.r});

  final AvailabilityInboxController c;
  final InboxRequest r;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Duration? left = r.remaining();
    final String currency = c.currencyOrDefault;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: '${r.medicine.displayName(isArabicNow())}, ${Fmt.distance(r.distanceKm)}',
        excludeSemantics: true,
        child: AppCard(
          onTap: () => c.openRequest(r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MedicineTitle(r.medicine),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  RequestAnswerChip(r, currency: currency),
                  if (r.distanceKm != null)
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(Icons.near_me_outlined, size: 16, color: p.textSecondary),
                      const SizedBox(width: 4),
                      LtrText(Fmt.distance(r.distanceKm), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                    ]),
                  if (left != null)
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(Icons.timer_outlined, size: 16, color: p.textSecondary),
                      const SizedBox(width: 4),
                      Text('p_req_time_left'.trParams(<String, String>{'t': remainingText(left)}), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                    ]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Answer one request (P-33).
class AvailabilityAnswerPage extends StatelessWidget {
  const AvailabilityAnswerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final AvailabilityAnswerController c = Get.find<AvailabilityAnswerController>(tag: id);
    return Scaffold(
      appBar: AppBar(title: Text('p_req_answer_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: () => c.refresh(silent: true),
          child: Obx(() {
            final InboxRequest? r = c.request.value;
            if (r == null) return const SizedBox.shrink();
            return _Body(c: c, r: r);
          }),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c, required this.r});

  final AvailabilityAnswerController c;
  final InboxRequest r;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Duration? left = r.remaining();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('p_req_question'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
              const SizedBox(height: 6),
              MedicineTitle(r.medicine, big: true),
              const SizedBox(height: 12),
              RequestAnswerChip(r, currency: c.currency),
              const SizedBox(height: 8),
              if (r.distanceKm != null) InfoRow(label: 'p_req_distance'.tr, value: Fmt.distance(r.distanceKm), ltr: true),
              if (left != null) InfoRow(label: 'p_req_remaining'.tr, value: remainingText(left)),
              if (r.listedPrice != null) InfoRow(label: 'p_req_listed_price'.tr, value: Fmt.money(r.listedPrice!, c.currency), ltr: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NoticeBanner('p_req_privacy'.tr, kind: NoticeKind.info),
        if (!c.canAnswer) ...<Widget>[
          const SizedBox(height: 12),
          NoticeBanner('p_req_closed_note'.tr, kind: NoticeKind.warning),
        ] else ...<Widget>[
          if (!c.updatesList) ...<Widget>[
            const SizedBox(height: 12),
            NoticeBanner('p_req_cashier_note'.tr, kind: NoticeKind.info),
          ],
          const SizedBox(height: 16),
          Form(
            key: c.form,
            child: AppTextField(
              label: 'p_req_price_label'.tr,
              helper: 'p_req_price_hint'.tr,
              controller: c.price,
              ltr: true,
              prefixIcon: Icons.payments_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              validator: (String? v) => Validators.price(v, allowZero: false),
            ),
          ),
          const SizedBox(height: 16),
          Obx(() => AppButton(
                label: 'p_req_answer_available'.tr,
                icon: Icons.check_circle_outline_rounded,
                loading: c.submitting.value,
                onPressed: c.answerAvailable,
              )),
          const SizedBox(height: 8),
          Obx(() => AppButton(
                label: 'p_req_answer_unavailable'.tr,
                icon: Icons.remove_circle_outline_rounded,
                variant: AppButtonVariant.secondary,
                loading: c.submitting.value,
                onPressed: c.answerUnavailable,
              )),
          const SizedBox(height: 12),
          Text('p_req_change_note'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
        ],
      ],
    );
  }
}
