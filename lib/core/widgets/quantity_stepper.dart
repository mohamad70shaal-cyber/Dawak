import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';

/// − [value] + control with 48 dp touch targets. Buttons disable at [min] / [max].
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 999,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final bool canDec = enabled && value > min;
    final bool canInc = enabled && value < max;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'qty_decrease'.tr,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: canDec ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded),
          ),
          Semantics(
            label: '${'qty'.tr}: $value',
            excludeSemantics: true,
            child: SizedBox(
              width: 40,
              child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(
            tooltip: 'qty_increase'.tr,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: canInc ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
