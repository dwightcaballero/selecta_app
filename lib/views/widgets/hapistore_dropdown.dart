import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';

/// Reusable store selector field with form validation and instant virtualized picker.
class HapistorePickerField extends StatefulWidget {
  const HapistorePickerField({
    super.key,
    required this.controller,
    this.label = 'Hapi Store',
    this.enabled = true,
    this.validator,
    this.onChanged,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? Function(String?)? validator;
  final VoidCallback? onChanged;
  final AutovalidateMode autovalidateMode;

  @override
  State<HapistorePickerField> createState() => _HapistorePickerFieldState();
}

class _HapistorePickerFieldState extends State<HapistorePickerField> {
  final HapiStoreService _dbHS = HapiStoreService();
  List<Hapistore> _stores = [];
  bool _isLoading = false;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _initStores();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _initStores() {
    final cached = HapiStoreService.cachedStores;
    if (cached != null && cached.isNotEmpty) {
      _stores = cached;
    } else {
      _isLoading = true;
    }

    _subscription = _dbHS.getListHapiStoresAsStream().listen(
      (snapshot) {
        if (!mounted) return;
        final list = snapshot.docs.map((doc) {
          final data = doc.data();
          if (data is Hapistore) return data;
          return Hapistore.fromJson(data as Map<String, Object?>);
        }).toList();
        setState(() {
          _stores = list;
          _isLoading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      },
    );
  }

  Future<void> _openPicker(FormFieldState<String> fieldState) async {
    final selected = await showModalBottomSheet<Hapistore>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StorePickerModal(
        stores: _stores,
        isLoading: _isLoading,
        selectedStoreName: widget.controller.text,
      ),
    );

    if (selected != null) {
      widget.controller.text = selected.storeName;
      fieldState.didChange(selected.storeName);
      if (widget.onChanged != null) {
        widget.onChanged!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FormField<String>(
      initialValue: widget.controller.text,
      validator: widget.validator,
      autovalidateMode: widget.autovalidateMode,
      enabled: widget.enabled,
      builder: (FormFieldState<String> fieldState) {
        if (fieldState.value != widget.controller.text) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && fieldState.value != widget.controller.text) {
              fieldState.didChange(widget.controller.text);
            }
          });
        }

        final hasError = fieldState.hasError;
        final value = widget.controller.text;
        final hasSelection = value.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: widget.enabled ? () => _openPicker(fieldState) : null,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.label,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasSelection && widget.enabled)
                        IconButton(
                          tooltip: 'Clear store',
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            widget.controller.clear();
                            fieldState.didChange('');
                            if (widget.onChanged != null) {
                              widget.onChanged!();
                            }
                          },
                        ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: widget.enabled ? null : colorScheme.onSurface.withValues(alpha: 0.38),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: hasError ? colorScheme.error : colorScheme.outline,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.error),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colorScheme.error, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  enabled: widget.enabled,
                ),
                isEmpty: false,
                child: Text(
                  value.isEmpty ? 'Tap to choose a store' : value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: value.isEmpty ? FontWeight.normal : FontWeight.w600,
                    color: !widget.enabled
                        ? colorScheme.onSurface.withValues(alpha: 0.38)
                        : (value.isEmpty ? colorScheme.onSurfaceVariant : colorScheme.onSurface),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  fieldState.errorText ?? '',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Virtualized, instant modal bottom sheet for searching and selecting stores.
class StorePickerModal extends StatefulWidget {
  const StorePickerModal({
    super.key,
    required this.stores,
    required this.isLoading,
    required this.selectedStoreName,
  });

  final List<Hapistore> stores;
  final bool isLoading;
  final String selectedStoreName;

  @override
  State<StorePickerModal> createState() => _StorePickerModalState();
}

class _StorePickerModalState extends State<StorePickerModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final query = _searchQuery.trim().toLowerCase();
    final filteredStores = query.isEmpty
        ? widget.stores
        : widget.stores.where((store) {
            final nameMatch = store.storeName.toLowerCase().contains(query);
            final addressMatch = store.storeAddress.toLowerCase().contains(query);
            final contactMatch = store.storeContact.toLowerCase().contains(query);
            return nameMatch || addressMatch || contactMatch;
          }).toList();

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Store',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${widget.stores.length} total stores available',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search store name or address...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

                const Divider(height: 1),

                // List of stores
                Expanded(
                  child: widget.isLoading && widget.stores.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : filteredStores.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 48,
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      query.isEmpty ? 'No stores found' : 'No stores matching "$query"',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              itemCount: filteredStores.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                              itemBuilder: (context, index) {
                                final store = filteredStores[index];
                                final isSelected = store.storeName == widget.selectedStoreName;

                                return ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  selected: isSelected,
                                  selectedTileColor: colorScheme.primary.withValues(alpha: 0.08),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                                    child: Icon(
                                      Icons.storefront_outlined,
                                      size: 18,
                                      color: isSelected ? Colors.white : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  title: Text(
                                    store.storeName,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 14,
                                      color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: store.storeAddress.isNotEmpty
                                      ? Text(
                                          store.storeAddress,
                                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : (store.storeContact.isNotEmpty
                                          ? Text(
                                              'Contact: ${store.storeContact}',
                                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                            )
                                          : null),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle_rounded, color: colorScheme.primary, size: 20)
                                      : null,
                                  onTap: () => Navigator.pop(context, store),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function maintaining backwards compatibility.
Widget hapistoreDropdown(
  TextEditingController dropdownHapiStore, {
  VoidCallback? onChanged,
  bool enabled = true,
  String? Function(String?)? validator,
  String label = 'Hapi Store',
}) {
  return HapistorePickerField(
    controller: dropdownHapiStore,
    onChanged: onChanged,
    enabled: enabled,
    validator: validator,
    label: label,
  );
}
