import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import 'auth_widgets.dart';

enum LegalDoc { privacy, terms }

/// Bundled privacy policy / terms. The text is a DRAFT (see `legal_review_note`) and must be reviewed by a
/// lawyer before release.
class LegalPage extends StatelessWidget {
  const LegalPage(this.doc, {super.key});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final String prefix = doc == LegalDoc.privacy ? 'auth_legal_privacy' : 'auth_legal_terms';
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final List<int> sections = List<int>.generate(5, (int i) => i + 1);
    return Scaffold(
      appBar: AppBar(title: Text('${prefix}_title'.tr)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            NoticeBanner('legal_review_note'.tr, kind: NoticeKind.info),
            const SizedBox(height: 16),
            for (final int i in sections) ...<Widget>[
              Text('${prefix}_h$i'.tr, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('${prefix}_p$i'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary, height: 1.6)),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}
