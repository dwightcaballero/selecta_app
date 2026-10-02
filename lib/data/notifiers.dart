import 'package:flutter/widgets.dart';
import 'package:selecta_ops/theme/app_theme.dart';

ValueNotifier<int> selectedPageNotifier = ValueNotifier(0);
ValueNotifier<bool> isDarkModeNotifier = ValueNotifier(false);
ValueNotifier<AppThemePreset> appThemePresetNotifier = ValueNotifier(AppThemePreset.classicTeal);
ValueNotifier<double> appFontScaleNotifier = ValueNotifier(1.0);
ValueNotifier<bool> dashboardNeedsRefreshNotifier = ValueNotifier(false);
