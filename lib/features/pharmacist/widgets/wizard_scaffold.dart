import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/cards.dart';

/// Frame of the four registration steps: title, "step n of 4" with a progress bar, a scrolling body and the
/// action bar pinned to the bottom.
class WizardScaffold extends StatelessWidget {
  const WizardScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.body,
    required this.bottom,
    this.actions,
    this.canGoBack = true,
  });

  static const int steps = 4;

  final int step;
  final String title;
  final Widget body;
  final Widget bottom;
  final List<Widget>? actions;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: canGoBack,
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'p_reg_step'.trParams(<String, String>{'n': '$step', 'total': '$steps'}),
                  style: t.labelMedium?.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: step / steps, minHeight: 6),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: body,
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomActionBar(child: bottom),
    );
  }
}
