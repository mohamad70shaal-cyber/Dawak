import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_audit_logs_controller.dart';
import '../widgets/admin_widgets.dart';

/// Audit log viewer (A-13): read-only, newest first.
class AdminAuditLogsPage extends StatelessWidget {
  const AdminAuditLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminAuditLogsController c = Get.find<AdminAuditLogsController>();
    return Scaffold(
      appBar: AppBar(title: Text('a_audit_title'.tr)),
      body: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          FilterChipBar<AuditGroup>(
            values: AuditGroup.values,
            selected: c.group,
            label: (AuditGroup g) => 'a_audit_group_${g.name}'.tr,
            onSelected: c.setGroup,
          ),
          Expanded(
            child: PagedListView<AuditLogEntry>(
              paged: c.paged,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              empty: EmptyState(icon: Icons.history_edu_outlined, title: 'a_audit_empty'.tr, message: 'a_audit_empty_hint'.tr),
              itemBuilder: (BuildContext context, AuditLogEntry e) => _EntryTile(c: c, entry: e),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.c, required this.entry});

  final AdminAuditLogsController c;
  final AuditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final AuditLogEntry e = entry;
    final String reason = c.reasonOf(e);
    final String id = e.entityId ?? '';
    final String shortId = id.length > 8 ? id.substring(0, 8) : id;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.fiber_manual_record, size: 10, color: p.primaryText),
              const SizedBox(width: 8),
              Expanded(child: Text(trOr('a_audit_${e.action}', e.action), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 4),
          Obx(() {
            final String who = c.actorName(e);
            return Text(
              who.isEmpty ? 'a_audit_system'.tr : '${'a_audit_by'.tr} $who',
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            );
          }),
          if (reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(reason, style: t.bodyMedium),
          ],
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: LtrText(
                  shortId.isEmpty ? e.entityType : '${e.entityType} · $shortId',
                  style: t.labelSmall?.copyWith(color: p.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              LtrText(Fmt.dateTime(e.createdAt), style: t.labelSmall?.copyWith(color: p.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
