import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/notifiers.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/services/push_notification_service.dart';
import 'package:selecta_ops/views/pages/others/welcome_page.dart';
import 'package:selecta_ops/views/pages/store/store_change_password_page.dart';
import 'package:selecta_ops/views/pages/store/store_performance_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';

/// Store Account & Profile screen.
/// Displays store details, access to analytics, theme toggle, password update, and logout.
class StoreAccountPage extends StatefulWidget {
  const StoreAccountPage({super.key});

  @override
  State<StoreAccountPage> createState() => _StoreAccountPageState();
}

class _StoreAccountPageState extends State<StoreAccountPage> {
  Future<void> _logout() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF1E2430) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: const Text('Are you sure you want to sign out of your store account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = await KVariables.getUser();
      if (user != null && user.storeId.isNotEmpty) {
        await PushNotificationService().clearStoreTopic(user.storeId);
      }
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WelcomePage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Error signing out: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBorder = isDark ? const Color(0xFF384152) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF1E2430) : Colors.white;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;

        return Scaffold(
          appBar: const CustomAppbar(
            title: 'Store Account',
            subtitle: 'Profile & preferences',
            showBackButton: false,
          ),
          body: StreamBuilder<DocumentSnapshot>(
            stream: storeId.isNotEmpty
                ? FirebaseFirestore.instance.collection(HAPISTORE_COLLECTION_REF).doc(storeId).snapshots()
                : const Stream.empty(),
            builder: (context, storeDocSnapshot) {
              final storeData = storeDocSnapshot.data?.data() as Map<String, dynamic>?;
              final storeName = user.storeName.isNotEmpty ? user.storeName : (storeData?['storeName'] as String? ?? 'Store');
              final storeAddress = storeData?['storeAddress'] as String? ?? 'Address not specified';
              final storeContact = storeData?['storeContact'] as String? ?? 'No contact number';
              final dealerName = user.dealerName.isNotEmpty ? user.dealerName : 'Selecta Dealer';
              final username = user.username.isNotEmpty ? user.username : (storeData?['username'] as String? ?? '');

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                children: [
                  // Store Profile Header Card
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colorScheme.primary.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(Icons.storefront_rounded, size: 28, color: colorScheme.primary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    storeName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '@$username',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Divider(height: 1, color: cardBorder),
                        ),
                        _buildInfoRow(Icons.business_rounded, 'Dealer', dealerName, colorScheme, cardBorder),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.location_on_outlined, 'Address', storeAddress, colorScheme, cardBorder),
                        const SizedBox(height: 10),
                        _buildInfoRow(Icons.phone_outlined, 'Contact', storeContact, colorScheme, cardBorder),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Menu Options
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cardBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.analytics_outlined, color: Color(0xFF8B5CF6), size: 20),
                            ),
                            title: const Text('Store Analytics & Performance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('View purchasing volume, fill rate, and trends', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const StorePerformancePage()),
                              );
                            },
                          ),
                          Divider(height: 1, color: cardBorder),
                          ValueListenableBuilder<bool>(
                            valueListenable: isDarkModeNotifier,
                            builder: (context, darkVal, _) {
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: (darkVal ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6)).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    darkVal ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                                    color: darkVal ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6),
                                    size: 20,
                                  ),
                                ),
                                title: const Text('Dark Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                subtitle: Text(
                                  darkVal ? 'Dark theme enabled' : 'Light theme enabled',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                                trailing: Switch.adaptive(
                                  value: darkVal,
                                  onChanged: (val) async {
                                    isDarkModeNotifier.value = val;
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setBool(KConstants.themeModeKey, val);
                                  },
                                ),
                              );
                            },
                          ),
                          Divider(height: 1, color: cardBorder),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF3B82F6), size: 20),
                            ),
                            title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            subtitle: Text('Update your portal login password', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const StoreChangePasswordPage(isForced: false)),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sign Out Card
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cardBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
                        ),
                        title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('Log out of this device', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.red),
                        onTap: _logout,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  Center(
                    child: Text(
                      'Selecta Ops Store Ordering Portal • v1.0',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ColorScheme colorScheme, Color cardBorder) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 1),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
