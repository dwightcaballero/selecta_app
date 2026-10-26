import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/pages/others/welcome_page.dart';
import 'package:selecta_ops/views/pages/store/store_change_password_page.dart';
import 'package:selecta_ops/views/pages/store/store_performance_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Store Account & Profile screen.
/// Displays store details, access to analytics, password update, and logout.
class StoreAccountPage extends StatefulWidget {
  const StoreAccountPage({super.key});

  @override
  State<StoreAccountPage> createState() => _StoreAccountPageState();
}

class _StoreAccountPageState extends State<StoreAccountPage> {
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out of your store account?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
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
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<Users?>(
      future: KVariables.getUser(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? Users.empty();
        final storeId = user.storeId;

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Account'),
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
                padding: const EdgeInsets.all(16),
                children: [
                  // Store Profile Header Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
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
                                    const SizedBox(height: 2),
                                    Text(
                                      '@$username',
                                      style: TextStyle(fontSize: 13, color: colorScheme.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(Icons.business_rounded, 'Dealer', dealerName, colorScheme),
                          const SizedBox(height: 10),
                          _buildInfoRow(Icons.location_on_outlined, 'Address', storeAddress, colorScheme),
                          const SizedBox(height: 10),
                          _buildInfoRow(Icons.phone_outlined, 'Contact', storeContact, colorScheme),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Menu Options
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: const Text('Store Analytics & Performance', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('View purchasing volume, fill rate, and trends'),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const StorePerformancePage()),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.lock_outline_rounded),
                          title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Update your portal login password'),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
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
                  const SizedBox(height: 20),

                  // Sign Out Card
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.red),
                      title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Log out of this device'),
                      onTap: _logout,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Center(
                    child: Text(
                      'Selecta Ops Store Ordering Portal • v1.0',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
