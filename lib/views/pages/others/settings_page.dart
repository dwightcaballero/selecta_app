import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/theme/app_theme.dart';
import 'package:selecta_ops/views/pages/others/changepassword_page.dart';
import 'package:selecta_ops/views/pages/others/changeusernamerole_page.dart';
import 'package:selecta_ops/views/pages/others/deleteaccount_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version} (Build ${info.buildNumber})';
        });
      }
    } catch (_) {}
  }

  Future<void> _setDarkMode(bool isDark) async {
    isDarkModeNotifier.value = isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(KConstants.themeModeKey, isDark);
  }

  Future<void> _setThemePreset(AppThemePreset preset) async {
    appThemePresetNotifier.value = preset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_theme_preset_key', preset.name);
  }

  Future<void> _setFontScale(double scale) async {
    appFontScaleNotifier.value = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_font_scale_key', scale);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section 1: Appearance ───────────────────────────────────────
            _buildSectionHeader('Appearance', Icons.palette_outlined),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  // Dark Mode Switch
                  ValueListenableBuilder<bool>(
                    valueListenable: isDarkModeNotifier,
                    builder: (context, isDark, _) {
                      return SwitchListTile.adaptive(
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha(25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                            color: colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Dark Mode',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        subtitle: Text(
                          isDark ? 'Comfortable for night & low light' : 'Clean high-contrast daytime mode',
                          style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                        ),
                        value: isDark,
                        onChanged: _setDarkMode,
                      );
                    },
                  ),
                  const Divider(height: 1),

                  // Brand Theme Palette Selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Color Palette',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Tap to preview',
                              style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<AppThemePreset>(
                          valueListenable: appThemePresetNotifier,
                          builder: (context, activePreset, _) {
                            return Column(
                              children: AppThemePreset.values.map((preset) {
                                final isSelected = activePreset == preset;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _setThemePreset(preset),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? colorScheme.primary.withAlpha(20)
                                            : colorScheme.surfaceContainerHighest.withAlpha(60),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withAlpha(100),
                                          width: isSelected ? 1.8 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: preset.primaryColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: preset.primaryColor.withAlpha(80),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  preset.label,
                                                  style: TextStyle(
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Text(
                                                  preset.description,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle_rounded,
                                              color: colorScheme.primary,
                                              size: 22,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Text Size / Scale Selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Text Size',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            ValueListenableBuilder<double>(
                              valueListenable: appFontScaleNotifier,
                              builder: (context, scale, _) {
                                final label = scale <= 0.92
                                    ? 'Compact (90%)'
                                    : (scale >= 1.1 ? 'Large (115%)' : 'Default (100%)');
                                return Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<double>(
                          valueListenable: appFontScaleNotifier,
                          builder: (context, scale, _) {
                            final currentVal = scale <= 0.92 ? 0.9 : (scale >= 1.1 ? 1.15 : 1.0);
                            return SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<double>(
                                segments: const [
                                  ButtonSegment<double>(
                                    value: 0.9,
                                    label: Text('Compact (90%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  ButtonSegment<double>(
                                    value: 1.0,
                                    label: Text('Default (100%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  ButtonSegment<double>(
                                    value: 1.15,
                                    label: Text('Large (115%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                selected: {currentVal},
                                onSelectionChanged: (val) => _setFontScale(val.first),
                                style: SegmentedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Scales text across all pages in the app for optimal reading comfort.',
                          style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Section 2: Account Security ────────────────────────────────
            _buildSectionHeader('Account & Security', Icons.security_rounded),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person_outline_rounded, color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('Change Username', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ChangeusernameRolePage()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_outline_rounded, color: colorScheme.primary, size: 20),
                    ),
                    title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ChangePasswordPage()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                    ),
                    title: const Text(
                      'Delete Account',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: Colors.red),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.red),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DeleteAccountPage()),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── App Version Footer ─────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Text(
                    'Selecta Ops',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Version $_appVersion',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant.withAlpha(180),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}