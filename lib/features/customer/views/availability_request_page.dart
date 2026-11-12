import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/availability.dart';
import '../controllers/availability_request_controller.dart';
import '../widgets/cart_actions.dart';
import '../widgets/customer_widgets.dart';
import '../widgets/pharmacy_answer_card.dart';

/// "Ask the pharmacies nearby" results (C-29). The screen reads the server every few seconds while the request is open;
/// the answers of the pharmacies that have the medicine appear as they arrive, nearest first.
class AvailabilityRequestPage extends StatelessWidget {
  const AvailabilityRequestPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final String targetId = id.isNotEmpty ? id : (Get.parameters['id'] ?? '');
    final AvailabilityRequestController c = Get.isRegistered<AvailabilityRequestController>(tag: targetId)
        ? Get.find<AvailabilityRequestController>(tag: targetId)
        : Get.put<AvailabilityRequestController>(AvailabilityRequestController(targetId), tag: targetId);
    return Scaffold(
      appBar: AppBar(title: Text('c_req_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: c.refreshSilently,
          child: Obx(() {
            final AvailabilityRequest? r = c.request.value;
            if (r == null) return const SizedBox.shrink();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _Header(request: r, remaining: c.remaining),
                if (c.offline.value) ...<Widget>[
                  const SizedBox(height: 12),
                  InlineNotice('c_req_offline'.tr, tone: NoticeTone.warning),
                ],
                if (c.grewTo.value != null) ...<Widget>[
                  const SizedBox(height: 12),
                  InlineNotice(
                    'c_req_grew'.trParams(<String, String>{'km': Fmt.number(c.grewTo.value!)}),
                    action: AppButton(label: 'ok'.tr, variant: AppButtonVariant.text, expand: false, onPressed: c.dismissGrowth),
                  ),
                ],
                const SizedBox(height: 12),
                _PhaseMessage(phase: c.phase, request: r),
                if (r.hasOffers) ...<Widget>[
                  const SizedBox(height: 16),
                  SectionTitle('c_req_offers_title'.trParams(<String, String>{'n': '${r.offers.length}'})),
                  for (final AvailabilityOffer o in r.offers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PharmacyAnswerCard(
                        pharmacy: o.pharmacy,
                        price: o.price,
                        currency: o.currency,
                        answeredAt: o.answeredAt,
                        onOpenPharmacy: () => c.openPharmacy(o),
                        onReserve: c.lineFor(o) == null ? null : () => reserveOffer(c.cart, c.targetFor(o), c.lineFor(o)!),
                      ),
                    ),
                  InlineNotice('c_req_offers_note'.tr),
                ],
                const SizedBox(height: 16),
                if (r.canSearchFurther)
                  AppButton(
                    label: 'c_req_search_further'.trParams(<String, String>{'km': Fmt.number(r.nextRadiusKm ?? r.radiusKm)}),
                    icon: Icons.zoom_out_map_rounded,
                    variant: AppButtonVariant.secondary,
                    loading: c.submitting.value,
                    onPressed: c.expand,
                  ),
                if (r.isOpen) ...<Widget>[
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'c_req_close'.tr,
                    icon: Icons.close_rounded,
                    variant: AppButtonVariant.text,
                    onPressed: c.submitting.value ? null : c.closeRequest,
                  ),
                ] else
                  AppButton(label: 'c_req_ask_again'.tr, icon: Icons.radar_rounded, onPressed: c.openMedicine),
                const SizedBox(height: 8),
                InlineNotice('c_disclaimer'.tr),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.request, required this.remaining});

  final AvailabilityRequest request;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final bool ar = isArabicNow();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String second = request.medicine.secondaryName(ar);
    final String spec = request.medicine.specLine;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: Text(request.medicine.displayName(ar), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Flexible(child: RequestStatusChip(request.status)),
            ],
          ),
          if (second.isNotEmpty) Text(second, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
          if (spec.isNotEmpty) Text(spec, style: t.bodySmall?.copyWith(color: p.textSecondary)),
          const SizedBox(height: 12),
          InfoRow(label: 'c_req_radius'.tr, value: 'c_req_radius_value'.trParams(<String, String>{'km': Fmt.number(request.radiusKm)})),
          InfoRow(
            label: 'c_req_progress'.tr,
            value: 'c_req_progress_value'.trParams(<String, String>{'asked': '${request.notified}', 'answered': '${request.answered}'}),
          ),
          if (remaining != null) InfoRow(label: 'c_req_time_left'.tr, value: remainingText(remaining!)),
        ],
      ),
    );
  }
}

/// The one sentence that says where the request stands.
class _PhaseMessage extends StatelessWidget {
  const _PhaseMessage({required this.phase, required this.request});

  final RequestPhase phase;
  final AvailabilityRequest request;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    switch (phase) {
      case RequestPhase.waiting:
        return Row(
          children: <Widget>[
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'c_req_phase_waiting'.trParams(<String, String>{'km': Fmt.number(request.radiusKm)}),
                style: t.bodyMedium?.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        );
      case RequestPhase.hasOffers:
        if (request.waiting == 0) return const SizedBox.shrink();
        return Text(
          'c_req_still_waiting'.trParams(<String, String>{'n': '${request.waiting}'}),
          style: t.bodySmall?.copyWith(color: p.textSecondary),
        );
      case RequestPhase.nobodyInRange:
        return InlineNotice('c_req_nobody'.tr, tone: NoticeTone.warning);
      case RequestPhase.allSaidNo:
        return InlineNotice('c_req_all_no'.tr, tone: NoticeTone.warning);
      case RequestPhase.expired:
        return InlineNotice(request.hasOffers ? 'c_req_expired_with_offers'.tr : 'c_req_expired'.tr, tone: NoticeTone.warning);
      case RequestPhase.closed:
        return InlineNotice('c_req_closed'.tr);
    }
  }
}
