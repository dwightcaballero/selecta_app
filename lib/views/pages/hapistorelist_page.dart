import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/hapistore_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class HapiStoreListPage extends StatefulWidget {
  const HapiStoreListPage({super.key});

  @override
  State<HapiStoreListPage> createState() => _HapiStoreListPageState();
}

class _HapiStoreListPageState extends State<HapiStoreListPage> {
  final HapiStoreService db = HapiStoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;
  bool _isDealer = true;

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void prefetchData() async {
    _isDealer = await KVariables.getIsDealer();
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _searchQuery = text.trim().toUpperCase();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Hapi Stores', subtitle: 'Store Directory & Contacts'),
      floatingActionButton: _isDealer
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HapiStorePage(hapiStoreID: '', hapistore: Hapistore.empty()),
                  ),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Store',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      body: Column(
        children: [
          // 1. Search Bar
          _buildSearchBar(),

          // 2. Stores Stream List
          Expanded(child: _buildStoreListView()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search by store name...',
          hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }

  Widget _buildStoreListView() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getListHapiStoreSearch(_searchQuery),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data?.docs ?? [];
        if (allDocs.isEmpty) {
          return _searchQuery.isNotEmpty ? _buildNoSearchResultsState() : _buildEmptyState();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: allDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final hapistore = allDocs[index].data() as Hapistore;
            final hapistoreID = allDocs[index].id;
            return _buildStoreCard(hapistoreID: hapistoreID, hapistore: hapistore);
          },
        );
      },
    );
  }

  Widget _buildStoreCard({required String hapistoreID, required Hapistore hapistore}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isDealer
            ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HapiStorePage(hapiStoreID: hapistoreID, hapistore: hapistore),
                  ),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hapistore.storeName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hapistore.storeContact.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(hapistore.storeContact, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                    if (hapistore.storeAddress.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              hapistore.storeAddress,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_isDealer) ...[const SizedBox(width: 6), Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.store_mall_directory_outlined, color: Colors.blue, size: 50),
            ),
            const SizedBox(height: 16),
            const Text('No Hapi Stores Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Add stores to start managing deliveries, orders, and credit settlements.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('No stores matching "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          SizedBox(height: 8),
          Text('Unable to load stores list'),
        ],
      ),
    );
  }
}
