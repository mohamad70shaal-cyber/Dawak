import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';

export '../../../core/widgets/notice_banner.dart';

/// Scrollable page for auth forms: back arrow, title, subtitle, then [children].
class AuthFormScaffold extends StatelessWidget {
  const AuthFormScaffold({super.key, required this.title, this.subtitle, required this.children, this.showBack = true});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: showBack),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppDims.pagePadding + 8, 8, AppDims.pagePadding + 8, 32),
              children: <Widget>[
                Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(subtitle!, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
                ],
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
