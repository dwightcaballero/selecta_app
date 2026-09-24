import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/pages/dashboard/pjp_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class PjpListPage extends StatefulWidget {
  const PjpListPage({super.key});

  @override
  State<PjpListPage> createState() => _PjpListPageState();
}

class _PjpListPageState extends State<PjpListPage> {
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

  void _changeDay(int offset) {
    if (_isEditing) return;
    final currentIndex = _weekdayNames.indexOf(_selectedDay);
    if (currentIndex == -1) return;
    final newIndex = (currentIndex + offset) % _weekdayNames.length;
    final normalizedIndex = newIndex < 0 ? newIndex + _weekdayNames.length : newIndex;
    _onDayChanged(_weekdayNames[normalizedIndex]);
  }

  Future<void> _showDayPicker() async {
    if (_isEditing) return;
    final todayName = _weekdayNames[DateTime.now().weekday - 1];

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Select PJP Day', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const Divider(),
                ..._weekdayNames.map((day) {
                  final isSelected = day == _selectedDay;
                  final isToday = day == todayName;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.calendar_today_outlined,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                    title: Row(
                      children: [
                        Text(
                          day,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              'Today',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: isSelected ? Icon(Icons.check, color: colorScheme.primary) : null,
                    onTap: () => Navigator.pop(context, day),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && selected != _selectedDay) {
      _onDayChanged(selected);
    }
  }

  Widget _buildDayNavigator() {
    final colorScheme = Theme.of(context).colorScheme;
    final todayName = _weekdayNames[DateTime.now().weekday - 1];
    final isToday = _selectedDay == todayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous Day', onPressed: _isEditing ? null : () => _changeDay(-1)),
            InkWell(
              onTap: _isEditing ? null : _showDayPicker,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(_selectedDay, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          'Today',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.primary),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, size: 20, color: colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next Day', onPressed: _isEditing ? null : () => _changeDay(1)),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreTile({required int index, required String hapiStoreID, required Hapistore hapistore}) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isCompletedToday;
    final bool isCompletedThisWeek;
    if (hapistore.lastPjpVisit != null) {
      final visit = hapistore.lastPjpVisit!.toDate();
      final now = DateTime.now();
      isCompletedToday = visit.year == now.year && visit.month == now.month && visit.day == now.day;
      isCompletedThisWeek = Helperfunctions.isSameWeek(visit, now);
    } else {
      isCompletedToday = false;
      isCompletedThisWeek = false;
    }

    final bool isDone = isCompletedThisWeek;

    final cardBorder = isDone
        ? BorderSide(color: Colors.green.shade400, width: 1.5)
        : BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6));

    final cardColor = isDone ? Colors.green.withValues(alpha: 0.04) : colorScheme.surface;

    return Card(
      key: ValueKey(hapiStoreID),
      elevation: 0,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: cardBorder),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isEditing ? null : () => _navigateToStoreVisit(hapiStoreID, hapistore),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDone ? Colors.green.withValues(alpha: 0.15) : colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 20, color: Colors.green)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hapistore.storeName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isDone) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                            child: const Text(
                              'Done',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                          ),
                        ],
                      ],
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
                    if (isDone && hapistore.lastPjpVisit != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        isCompletedToday
                            ? 'Visited today at ${DateFormat('h:mm a').format(hapistore.lastPjpVisit!.toDate())}'
                            : 'Visited on ${DateFormat('EEE, MMM d • h:mm a').format(hapistore.lastPjpVisit!.toDate())}',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w500),
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
              ] else ...[
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToStoreVisit(String hapiStoreID, Hapistore hapistore) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PjpPage(hapiStoreID: hapiStoreID, initialHapistore: hapistore, selectedDay: _selectedDay),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
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
          _buildDayNavigator(),
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
