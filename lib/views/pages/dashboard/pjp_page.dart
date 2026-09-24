import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';

class PjpPage extends StatefulWidget {
  const PjpPage({super.key});

  @override
  State<PjpPage> createState() => _PjpPageState();
}

class _PjpPageState extends State<PjpPage> {
  final HapiStoreService db = HapiStoreService();

  static const List<String> _weekdayNames = [
    PjpScheduleDays.monday,
    PjpScheduleDays.tuesday,
    PjpScheduleDays.wednesday,
    PjpScheduleDays.thursday,
    PjpScheduleDays.friday,
    PjpScheduleDays.saturday,
    PjpScheduleDays.sunday,
  ];

  List<String> _editableStoreIDs = [];
  Map<String, Hapistore> _editableStoresById = {};
  bool _isDealer = true;
  bool _isEditing = false;
  bool _isSaving = false;
  Set<String> _originalStoreIDs = {};
  late String _selectedDay;

  @override
  void initState() {
    super.initState();
    // DateTime.weekday is 1 (Monday) .. 7 (Sunday), matching _weekdayNames indices.
    _selectedDay = _weekdayNames[DateTime.now().weekday - 1];
    _prefetchData();
  }

  void _prefetchData() async {
    _isDealer = await KVariables.getIsDealer();
    if (mounted) setState(() {});
  }

  // Stores without a pjpSequence yet are appended alphabetically after the sequenced ones.
  List<QueryDocumentSnapshot> _sortedDocs(List<QueryDocumentSnapshot> docs) {
    final sorted = [...docs];
    sorted.sort((a, b) {
      final seqA = (a.data() as Hapistore).pjpSequence;
      final seqB = (b.data() as Hapistore).pjpSequence;
      if (seqA != null && seqB != null) return seqA.compareTo(seqB);
      if (seqA != null) return -1;
      if (seqB != null) return 1;
      return (a.data() as Hapistore).storeName.compareTo((b.data() as Hapistore).storeName);
    });
    return sorted;
  }

  void _onDayChanged(String? day) {
    if (day == null || day == _selectedDay) return;
    setState(() {
      _selectedDay = day;
      _isEditing = false;
      _editableStoreIDs = [];
      _editableStoresById = {};
    });
  }

  void _startEditing(List<QueryDocumentSnapshot> docs) {
    setState(() {
      _isEditing = true;
      _editableStoreIDs = docs.map((doc) => doc.id).toList();
      _originalStoreIDs = _editableStoreIDs.toSet();
      _editableStoresById = {for (final doc in docs) doc.id: doc.data() as Hapistore};
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editableStoreIDs = [];
      _originalStoreIDs = {};
      _editableStoresById = {};
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final id = _editableStoreIDs.removeAt(oldIndex);
      _editableStoreIDs.insert(newIndex, id);
    });
  }

  void _removeStore(String hapiStoreID) {
    setState(() {
      _editableStoreIDs.remove(hapiStoreID);
    });
  }

  Future<void> _showAddStorePicker() async {
    final selected = await showModalBottomSheet<MapEntry<String, Hapistore>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddStoreSheet(db: db, excludedStoreIDs: _editableStoreIDs.toSet()),
    );

    if (selected != null) {
      setState(() {
        _editableStoreIDs.add(selected.key);
        _editableStoresById[selected.key] = selected.value;
      });
    }
  }

  Future<void> _saveOrder() async {
    setState(() => _isSaving = true);
    try {
      final removedStoreIDs = _originalStoreIDs.difference(_editableStoreIDs.toSet()).toList();
      await db.updatePjpSequenceOrder(_selectedDay, _editableStoreIDs, removedHapiStoreIDs: removedStoreIDs);
      final storeNames = _editableStoreIDs.map((id) => _editableStoresById[id]?.storeName ?? id).join(', ');
      Helperfunctions.logTransaction('PJP Resequence - $_selectedDay', 'New order: $storeNames', LogAction.update);
      if (!mounted) return;
      ShowMessage.success(context, 'Successfully updated PJP sequence for $_selectedDay!');
      setState(() {
        _isEditing = false;
        _editableStoreIDs = [];
        _originalStoreIDs = {};
        _editableStoresById = {};
      });
    } catch (e) {
      if (!mounted) return;
      ShowMessage.error(context, 'Failed to save PJP sequence');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildDayDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedDay,
        decoration: InputDecoration(
          labelText: 'PJP Day',
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _weekdayNames.map((day) => DropdownMenuItem(value: day, child: Text(day))).toList(),
        onChanged: (_isEditing) ? null : _onDayChanged,
      ),
    );
  }

  Widget _buildStoreTile({required int index, required String hapiStoreID, required Hapistore hapistore}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey(hapiStoreID),
      elevation: 0,
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(
                '${index + 1}',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
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
                  if (hapistore.storeAddress.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      hapistore.storeAddress,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (_isEditing) ...[
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                tooltip: 'Remove from $_selectedDay',
                onPressed: () => _removeStore(hapiStoreID),
              ),
              Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
            ],
          ],
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
              child: const Icon(Icons.event_note_outlined, color: Colors.blue, size: 50),
            ),
            const SizedBox(height: 16),
            Text('No Stores Scheduled for $_selectedDay', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Assign a PJP schedule to stores to see them here.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
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
          Text('Unable to load PJP schedule'),
        ],
      ),
    );
  }

  Widget _buildEditingList() {
    if (_editableStoreIDs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            'No stores yet for $_selectedDay. Tap the add-store icon above to include some.',
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _editableStoreIDs.length,
      onReorderItem: _onReorder,
      itemBuilder: (context, index) {
        final hapiStoreID = _editableStoreIDs[index];
        final hapistore = _editableStoresById[hapiStoreID]!;
        return _buildStoreTile(index: index, hapiStoreID: hapiStoreID, hapistore: hapistore);
      },
    );
  }

  Widget _buildBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getListHapiStoresByPjpScheduleAsStream(_selectedDay),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _buildErrorState();
        if (snapshot.connectionState == ConnectionState.waiting && !_isEditing) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = _sortedDocs(snapshot.data?.docs ?? []);

        if (_isEditing) {
          return _buildEditingList();
        }

        if (docs.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final hapiStoreID = docs[index].id;
            final hapistore = docs[index].data() as Hapistore;
            return _buildStoreTile(index: index, hapiStoreID: hapiStoreID, hapistore: hapistore);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Permanent Journey Plan',
        actions: [
          if (!_isEditing && _isDealer)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: 'Rearrange stores',
              onPressed: () async {
                final snapshot = await db.getListHapiStoresByPjpScheduleAsStream(_selectedDay).first;
                if (!mounted) return;
                _startEditing(_sortedDocs(snapshot.docs));
              },
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.add_business_outlined, color: Colors.white),
              tooltip: 'Add store to $_selectedDay',
              onPressed: _showAddStorePicker,
            ),
        ],
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveOrder,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, color: Colors.white),
              label: Text(
                _isSaving ? 'Saving...' : 'Save Order',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      body: Column(
        children: [
          _buildDayDropdown(),
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Drag stores to reorder, or tap the add-store icon to include more stores for $_selectedDay.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton(onPressed: _isSaving ? null : _cancelEditing, child: const Text('Cancel')),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

class _AddStoreSheet extends StatefulWidget {
  const _AddStoreSheet({required this.db, required this.excludedStoreIDs});

  final HapiStoreService db;
  final Set<String> excludedStoreIDs;

  @override
  State<_AddStoreSheet> createState() => _AddStoreSheetState();
}

class _AddStoreSheetState extends State<_AddStoreSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Store', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                onChanged: (value) => setState(() => _searchQuery = value.trim().toUpperCase()),
                decoration: InputDecoration(
                  hintText: 'Search by store name...',
                  prefixIcon: const Icon(Icons.search),
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
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: widget.db.getListHapiStoreSearch(_searchQuery),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('Unable to load stores'));
                    }
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = (snapshot.data?.docs ?? []).where((doc) => !widget.excludedStoreIDs.contains(doc.id)).toList();
                    if (docs.isEmpty) {
                      return const Center(child: Text('No stores found'));
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final hapiStoreID = docs[index].id;
                        final hapistore = docs[index].data() as Hapistore;
                        return ListTile(
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(hapistore.storeName),
                          subtitle: hapistore.pjpSchedule != null ? Text('Currently scheduled: ${hapistore.pjpSchedule}') : null,
                          onTap: () => Navigator.pop(context, MapEntry(hapiStoreID, hapistore)),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
