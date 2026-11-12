import 'package:flutter/material.dart';

/// Text that always runs left-to-right (phone numbers, order codes, prices, e-mail) inside Arabic screens.
/// With [alignEnd] it sits at the reading-end edge of its box (the left in RTL layouts is *not* what is
/// wanted for numbers in a label/value row: they hug the end side like the rest of the value column).
class LtrText extends StatelessWidget {
  const LtrText(this.text, {super.key, this.style, this.alignEnd = false, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final bool alignEnd;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final Widget t = Directionality(
      textDirection: TextDirection.ltr,
      child: Text(text, style: style, maxLines: maxLines, overflow: overflow, textAlign: TextAlign.start),
    );
    if (!alignEnd) return t;
    return Align(alignment: AlignmentDirectional.centerEnd, child: t);
  }
}
