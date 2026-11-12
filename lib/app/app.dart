import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import '../core/i18n/app_translations.dart';
import '../core/services/locale_service.dart';
import '../core/widgets/app_toast.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';

class DawakApp extends StatelessWidget {
  const DawakApp({super.key});

  @override
  Widget build(BuildContext context) {
    final LocaleService locale = Get.find<LocaleService>();
    return GetMaterialApp(
      title: 'Dawak',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      translations: AppTranslations(),
      locale: locale.locale.value,
      fallbackLocale: LocaleService.arabic,
      supportedLocales: LocaleService.supported,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scaffoldMessengerKey: scaffoldMessengerKey,
      initialRoute: AppRoutes.splash,
      getPages: AppPages.pages,
      unknownRoute: AppPages.unknown,
      builder: (BuildContext context, Widget? child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.85,
        maxScaleFactor: 1.4,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
