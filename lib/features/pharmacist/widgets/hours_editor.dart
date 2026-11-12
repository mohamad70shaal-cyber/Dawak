import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../data/models/pharmacy.dart';

/// Seven rows (Saturday first): an open/closed switch and, when open, the opening and closing time.
/// Used by the registration wizard (P-06) and by the hours settings (P-69). All changes go through the callbacks.
class HoursEditor extends StatelessWidget {
  const HoursEditor({super.key, required this.hours, required this.onToggle, required this.onTime});

  final Rx<OpeningHours> hours;
  final void Function(int day, bool open) onToggle;

  /// [value] is `HH:mm`.
  final void Function(int day, {required bool from, required String value}) onTime;

  static String dayName(int day) => 'p_day_$day'.tr;

  static TimeOfDay parse(String hhmm) {
    final List<String> parts = hhmm.split(':');
    final int h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
    final int m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  static String format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(BuildContext context, DayHours d, {required bool from}) async {
    final TimeOfDay? t = await showTimePicker(context: context, initialTime: parse(from ? d.from : d.to));
    if (t != null) onTime(d.day, from: from, value: format(t));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Obx(() {
      final List<DayHours> days = hours.value.days;
      return Column(
        children: <Widget>[
          for (final DayHours d in days)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(dayName(d.day), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                        Text(d.open ? 'p_hours_open'.tr : 'p_hours_closed'.tr, style: t.labelMedium?.copyWith(color: p.textSecondary)),
                        const SizedBox(width: 8),
                        Switch(
                          value: d.open,
                          onChanged: (bool v) => onToggle(d.day, v),
                        ),
                      ],
                    ),
                    if (d.open)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _TimeButton(label: 'p_hours_from'.tr, value: d.from, onTap: () => _pick(context, d, from: true)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeButton(label: 'p_hours_to'.tr, value: d.to, onTap: () => _pick(context, d, from: false)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label),
            LtrText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
