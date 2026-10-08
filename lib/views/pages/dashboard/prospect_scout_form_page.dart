import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:selecta_ops/controllers/prospect_scout_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/map_tile_style.dart';
import 'package:selecta_ops/models/prospect_scout.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/full_screen_location_picker_dialog.dart';
import 'package:selecta_ops/views/widgets/map_style_switcher_button.dart';

class ProspectScoutFormPage extends StatefulWidget {
  final ProspectScout? prospect;
  final String? prospectId;
  final LatLng? initialLocation;

  const ProspectScoutFormPage({super.key, this.prospect, this.prospectId, this.initialLocation});

  @override
  State<ProspectScoutFormPage> createState() => _ProspectScoutFormPageState();
}

class _ProspectScoutFormPageState extends State<ProspectScoutFormPage> {
  final _formKey = GlobalKey<FormState>();
  final ProspectScoutController _controller = ProspectScoutController();
  final MapController _miniMapController = MapController();
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _nameController;
  late TextEditingController _contactPersonController;
  late TextEditingController _contactPhoneController;
  late TextEditingController _notesController;
  late TextEditingController _latController;
  late TextEditingController _lngController;

  File? _storePhotoFile;
  String? _existingImageUrl;

  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  bool _isSaving = false;
  bool _isMiniMapReady = false;
  MapTileStyle _mapStyle = MapTileStyle.standard;

  // Assessment answers
  bool _isAccessible = true;
  bool _isStoreBig = false;
  bool _hasCompetitorFreezer = false;
  final Set<String> _selectedCompetitorColors = {};
  String _selectedStatus = ProspectStatus.scouted;
  String _scoutedBy = '';

  bool get _isEditing => widget.prospect != null && widget.prospectId != null;

  @override
  void initState() {
    super.initState();
    final p = widget.prospect;

    _nameController = TextEditingController(text: p?.storeName ?? '');
    _contactPersonController = TextEditingController(text: p?.contactPerson ?? '');
    _contactPhoneController = TextEditingController(text: p?.contactPhone ?? '');
    _notesController = TextEditingController(text: p?.notes ?? '');
    _existingImageUrl = p?.imageUrl;

    if (p != null) {
      _latitude = p.latitude;
      _longitude = p.longitude;
      _isAccessible = p.isAccessible;
      _isStoreBig = p.isStoreBig;
      _hasCompetitorFreezer = p.hasCompetitorFreezer;
      _selectedCompetitorColors.addAll(p.competitorColors);
      _selectedStatus = p.status;
      _scoutedBy = p.scoutedBy ?? '';
    } else if (widget.initialLocation != null) {
      _latitude = widget.initialLocation!.latitude;
      _longitude = widget.initialLocation!.longitude;
    }

    _latController = TextEditingController(text: _latitude != null ? _latitude!.toStringAsFixed(6) : '');
    _lngController = TextEditingController(text: _longitude != null ? _longitude!.toStringAsFixed(6) : '');

    _initUserData();

    // If new prospect and no location passed, auto-fetch GPS
    if (!_isEditing && _latitude == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _getCurrentLocation();
      });
    }
  }

  Future<void> _initUserData() async {
    final user = await _controller.getCurrentUser();
    if (mounted && _scoutedBy.isEmpty) {
      setState(() {
        _scoutedBy = user?.username ?? 'Salesman';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactPersonController.dispose();
    _contactPhoneController.dispose();
    _notesController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _miniMapController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final pos = await _controller.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _latController.text = pos.latitude.toStringAsFixed(6);
        _lngController.text = pos.longitude.toStringAsFixed(6);
        _isLocating = false;
      });

      if (_isMiniMapReady) {
        try {
          _miniMapController.move(LatLng(pos.latitude, pos.longitude), 16);
        } catch (_) {}
      }
      ShowMessage.success(context, 'Current GPS location acquired successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLocating = false);
      ShowMessage.error(context, 'Failed to fetch GPS location: $e');
    }
  }

  Future<void> _openFullScreenLocationPicker() async {
    final initialPos = (_latitude != null && _longitude != null && _latitude != 0.0)
        ? LatLng(_latitude!, _longitude!)
        : const LatLng(14.599512, 120.984222);

    final LatLng? pickedLocation = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (ctx) => FullScreenLocationPickerDialog(
          initialLocation: initialPos,
          initialMapStyle: _mapStyle,
        ),
      ),
    );

    if (pickedLocation != null && mounted) {
      setState(() {
        _latitude = pickedLocation.latitude;
        _longitude = pickedLocation.longitude;
        _latController.text = pickedLocation.latitude.toStringAsFixed(6);
        _lngController.text = pickedLocation.longitude.toStringAsFixed(6);
      });

      if (_isMiniMapReady) {
        try {
          _miniMapController.move(pickedLocation, 16);
        } catch (_) {}
      }

      ShowMessage.success(context, 'Store location adjusted & pinned!');
    }
  }

  int get _computedQualityScore {
    int score = 0;
    if (_isAccessible) score++;
    if (_isStoreBig) score++;
    if (_hasCompetitorFreezer) score++;
    return score;
  }

  String get _computedQualityLabel {
    switch (_computedQualityScore) {
      case 3:
        return 'High Potential (3/3)';
      case 2:
        return 'Good Prospect (2/3)';
      case 1:
        return 'Fair Prospect (1/3)';
      default:
        return 'Low Potential (0/3)';
    }
  }

  Color get _computedQualityColor {
    switch (_computedQualityScore) {
      case 3:
        return const Color(0xFF10B981);
      case 2:
        return const Color(0xFF0284C7);
      case 1:
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFFEF4444);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _storePhotoFile = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to capture photo: $e');
      }
    }
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Capture Store Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFFEF4444)),
                title: const Text('Take Photo with Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF0284C7)),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProspect() async {
    if (_latitude == null || _longitude == null || _latitude == 0.0) {
      ShowMessage.error(context, 'Please capture or enter valid GPS coordinates.');
      return;
    }

    final storeName = _nameController.text.trim();

    setState(() => _isSaving = true);
    try {
      String? finalImageUrl = _existingImageUrl;
      if (_storePhotoFile != null) {
        finalImageUrl = await Helperfunctions.saveImage(context, _storePhotoFile!);
      }

      final scout = ProspectScout(
        id: widget.prospectId,
        storeName: storeName.isEmpty ? 'Unnamed Prospect' : storeName,
        latitude: _latitude!,
        longitude: _longitude!,
        isAccessible: _isAccessible,
        isStoreBig: _isStoreBig,
        hasCompetitorFreezer: _hasCompetitorFreezer,
        competitorColors: _hasCompetitorFreezer ? _selectedCompetitorColors.toList() : [],
        status: _selectedStatus,
        notes: _notesController.text.trim(),
        contactPerson: _contactPersonController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        imageUrl: finalImageUrl,
        scoutedBy: _scoutedBy.isNotEmpty ? _scoutedBy : 'Salesman',
      );

      if (_isEditing) {
        await _controller.updateProspect(widget.prospectId!, scout);
        if (!mounted) return;
        ShowMessage.success(context, 'Prospect updated successfully');
      } else {
        await _controller.saveProspect(scout);
        if (!mounted) return;
        ShowMessage.success(context, 'New prospect scouted and saved successfully');
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ShowMessage.error(context, 'Failed to save prospect: $e');
    }
  }

  Future<void> _deleteProspect() async {
    if (widget.prospectId == null) return;

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete Prospect',
      message: 'Are you sure you want to delete this prospect? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
      icon: Icons.delete_outline,
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _controller.deleteProspect(widget.prospectId!);
      if (!mounted) return;
      ShowMessage.success(context, 'Prospect deleted');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ShowMessage.error(context, 'Failed to delete prospect: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: CustomAppbar(
        title: _isEditing ? 'Edit Prospect' : 'Scout New Store',
        subtitle: _isEditing ? 'Update assessment and status' : 'Record store location and prospect assessment',
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Delete Prospect',
              onPressed: _isSaving ? null : _deleteProspect,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Prospect Scorecard Banner
              _buildScorecardBanner(colorScheme, isDark),

              const SizedBox(height: 16),

              // 2. GPS Location & Pin Card
              _buildLocationCard(colorScheme, isDark),

              const SizedBox(height: 16),

              // 3. Store Identity Card
              _buildStoreIdentityCard(colorScheme, isDark),

              const SizedBox(height: 16),

              // 4. Store Photo Card
              _buildStorePhotoCard(colorScheme, isDark),

              const SizedBox(height: 16),

              // 5. Assessment Questions Card
              _buildAssessmentCard(colorScheme, isDark),

              const SizedBox(height: 16),

              // 5. Status & Conversion Pipeline
              _buildStatusCard(colorScheme, isDark),

              const SizedBox(height: 24),

              // Save Action Button
              FilledButton.icon(
                style: KButtonStyle.save,
                onPressed: _isSaving ? null : _saveProspect,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isSaving ? 'Saving Record...' : (_isEditing ? 'Update Prospect Record' : 'Save Prospect Record'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),

              if (_isEditing) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50.0),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSaving ? null : _deleteProspect,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete This Prospect', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScorecardBanner(ColorScheme colorScheme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _computedQualityColor.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _computedQualityColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _computedQualityColor,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: _computedQualityColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: const Icon(Icons.analytics_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _computedQualityLabel,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _computedQualityColor),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _computedQualityScore == 3
                      ? 'Optimal prospect! Open visibility, good capital capacity, and existing ice cream freezer ready for Selecta swap.'
                      : _computedQualityScore == 2
                      ? 'Promising candidate meeting 2 out of 3 key criteria.'
                      : _computedQualityScore == 1
                      ? 'Moderate candidate. Review visibility or capital before engagement.'
                      : 'High risk or low visibility. Consider prioritizing other stores.',
                  style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(ColorScheme colorScheme, bool isDark) {
    final hasCoord = _latitude != null && _longitude != null && _latitude != 0.0;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
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
                Icon(Icons.location_on_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Store GPS Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isLocating ? null : _getCurrentLocation,
                    icon: _isLocating
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded, size: 16),
                    label: Text(_isLocating ? 'Locating...' : 'Get Current GPS', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _openFullScreenLocationPicker,
                    icon: const Icon(Icons.pin_drop_rounded, size: 16),
                    label: const Text('Pin on Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Latitude',
                      prefixIcon: const Icon(Icons.explore_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _lngController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Longitude',
                      prefixIcon: const Icon(Icons.explore_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mini Map Preview with style switcher & interactive tap to full-screen
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 175,
                width: double.infinity,
                child: hasCoord
                    ? Stack(
                        children: [
                          FlutterMap(
                            mapController: _miniMapController,
                            options: MapOptions(
                              initialCenter: LatLng(_latitude!, _longitude!),
                              initialZoom: 16,
                              interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
                              onTap: (tapPosition, point) {
                                _openFullScreenLocationPicker();
                              },
                              onMapReady: () {
                                _isMiniMapReady = true;
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: _mapStyle.url,
                                userAgentPackageName: 'selecta_ops',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(_latitude!, _longitude!),
                                    width: 44,
                                    height: 44,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: !_hasCompetitorFreezer
                                            ? const Color(0xFF0F172A)
                                            : (_selectedCompetitorColors.length <= 1
                                                ? CompetitorBrandColor.toColor(_selectedCompetitorColors.isNotEmpty ? _selectedCompetitorColors.first : 'Blue')
                                                : null),
                                        gradient: _hasCompetitorFreezer && _selectedCompetitorColors.length > 1
                                            ? LinearGradient(
                                                colors: _selectedCompetitorColors.map((c) => CompetitorBrandColor.toColor(c)).toList(),
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              )
                                            : null,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _hasCompetitorFreezer && _selectedCompetitorColors.length == 1 && _selectedCompetitorColors.first.toLowerCase() == 'white'
                                              ? Colors.grey.shade400
                                              : Colors.white,
                                          width: 2.5,
                                        ),
                                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                                      ),
                                      child: Center(
                                        child: Icon(
                                          _hasCompetitorFreezer ? Icons.icecream_rounded : Icons.storefront_rounded,
                                          color: _hasCompetitorFreezer && _selectedCompetitorColors.length == 1 && _selectedCompetitorColors.first.toLowerCase() == 'white'
                                              ? const Color(0xFF1E293B)
                                              : Colors.white,
                                          size: 22,
                                          shadows: _hasCompetitorFreezer && _selectedCompetitorColors.length > 1
                                              ? const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1))]
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Floating map style switcher button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: MapStyleSwitcherButton(
                              currentStyle: _mapStyle,
                              onStyleChanged: (newStyle) => setState(() => _mapStyle = newStyle),
                            ),
                          ),
                          // Floating Tap-to-Adjust Banner
                          Positioned(
                            bottom: 8,
                            left: 8,
                            right: 8,
                            child: InkWell(
                              onTap: _openFullScreenLocationPicker,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.open_in_full_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 6),
                                    Text(
                                      'Tap to fine-tune exact store position',
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.map_outlined, size: 36, color: colorScheme.outline),
                              const SizedBox(height: 8),
                              Text(
                                'Set Store Location',
                                style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "Get GPS" or "Pin on Map" to locate the prospect',
                                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11.5),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.tonalIcon(
                                onPressed: _openFullScreenLocationPicker,
                                icon: const Icon(Icons.pin_drop_rounded, size: 15),
                                label: const Text('Pin on Map Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            if (hasCoord)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Salesman across the street? Tap "Pin on Map" to target the exact store.',
                  style: TextStyle(fontSize: 11, color: colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreIdentityCard(ColorScheme colorScheme, bool isDark) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
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
                Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Store Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Store Name (Optional)',
                hintText: 'e.g. Aling Nena Sari-Sari Store',
                helperText: 'Leave blank if store has no signage (will save as "Unnamed Prospect")',
                prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _contactPersonController,
                    decoration: InputDecoration(
                      labelText: 'Owner / Contact Person',
                      hintText: 'e.g. Maria Santos',
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _contactPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'e.g. 09171234567',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Field Notes & Observations (Optional)',
                hintText: 'e.g. Near elementary school gate, busy pedestrian area, owner was friendly',
                prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.person_pin_circle_outlined, size: 16, color: colorScheme.outline),
                const SizedBox(width: 6),
                Text('Scouted by: $_scoutedBy', style: TextStyle(fontSize: 12, color: colorScheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorePhotoCard(ColorScheme colorScheme, bool isDark) {
    final hasPhoto = _storePhotoFile != null || (_existingImageUrl != null && _existingImageUrl!.isNotEmpty);

    return Card(
      elevation: 0,
      color: colorScheme.surface,
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
                Icon(Icons.photo_camera_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Store Front / Freezer Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                if (hasPhoto)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    tooltip: 'Remove photo',
                    onPressed: () {
                      setState(() {
                        _storePhotoFile = null;
                        _existingImageUrl = null;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Capture store facade, signboard, or competitor freezer as reference.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (hasPhoto) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: _storePhotoFile != null
                      ? Image.file(_storePhotoFile!, fit: BoxFit.cover)
                      : Image.network(
                          _existingImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, _, _) => Container(
                            color: colorScheme.surfaceContainerHighest,
                            child: const Center(child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey)),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _showPhotoSourceDialog,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retake / Change Photo'),
              ),
            ] else ...[
              InkWell(
                onTap: _showPhotoSourceDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to Take or Upload Store Photo',
                        style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text('Optional photo for field verification', style: TextStyle(color: colorScheme.outline, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssessmentCard(ColorScheme colorScheme, bool isDark) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
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
                Icon(Icons.quiz_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Prospect Assessment Questions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Answer these questions to determine store viability and replacement opportunity.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 24),

            // Question 1: Accessibility & Storefront Visibility
            _buildQuestionHeader(
              number: '1',
              question: 'Is the store accessible with clear visibility?',
              explanation:
                  'No grills in front or has open space so customers clearly see what is inside the store. Hidden freezers lead to low sales.',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildChoiceChip(
                    label: 'Yes (Accessible)',
                    icon: Icons.visibility_outlined,
                    selected: _isAccessible,
                    selectedColor: const Color(0xFF10B981),
                    onTap: () => setState(() => _isAccessible = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildChoiceChip(
                    label: 'No (Grills/Blocked)',
                    icon: Icons.visibility_off_outlined,
                    selected: !_isAccessible,
                    selectedColor: const Color(0xFFEF4444),
                    onTap: () => setState(() => _isAccessible = false),
                  ),
                ),
              ],
            ),

            const Divider(height: 28),

            // Question 2: Store Size & Capital Capacity
            _buildQuestionHeader(
              number: '2',
              question: 'Is the store Big or Small?',
              explanation: 'Helps determine if the store can afford the initial starting package capital for a Selecta freezer.',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildChoiceChip(
                    label: 'Big Store',
                    icon: Icons.store_rounded,
                    selected: _isStoreBig,
                    selectedColor: const Color(0xFF0284C7),
                    onTap: () => setState(() => _isStoreBig = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildChoiceChip(
                    label: 'Small Store',
                    icon: Icons.storefront_outlined,
                    selected: !_isStoreBig,
                    selectedColor: const Color(0xFFF59E0B),
                    onTap: () => setState(() => _isStoreBig = false),
                  ),
                ),
              ],
            ),

            const Divider(height: 28),

            // Question 3: Competitor Freezer Presence
            _buildQuestionHeader(
              number: '3',
              question: 'Does the store have other ice cream brands?',
              explanation:
                  'Advantageous! An existing freezer proves ice cream customer demand, making a replacement with our Selecta brand and better service feasible.',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildChoiceChip(
                    label: 'Yes (Has Competitor)',
                    icon: Icons.kitchen_rounded,
                    selected: _hasCompetitorFreezer,
                    selectedColor: const Color(0xFF8B5CF6),
                    onTap: () => setState(() => _hasCompetitorFreezer = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildChoiceChip(
                    label: 'No Competitor (?)',
                    icon: Icons.help_outline_rounded,
                    selected: !_hasCompetitorFreezer,
                    selectedColor: Colors.grey.shade600,
                    onTap: () => setState(() {
                      _hasCompetitorFreezer = false;
                      _selectedCompetitorColors.clear();
                    }),
                  ),
                ),
              ],
            ),

            // Competitor Color Selection (if Yes)
            if (_hasCompetitorFreezer) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.palette_outlined, size: 18),
                        const SizedBox(width: 6),
                        const Text('Competitor Brand Color(s):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const Spacer(),
                        Text('(Select up to 5)', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to toggle all competitor freezer colors found in this store:',
                      style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CompetitorBrandColor.all.map((colorName) {
                        final isSelected = _selectedCompetitorColors.contains(colorName);
                        final brandColor = CompetitorBrandColor.toColor(colorName);
                        final textColor = CompetitorBrandColor.toTextColor(colorName);
                        final isWhite = colorName == CompetitorBrandColor.white;

                        return FilterChip(
                          avatar: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: brandColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: isWhite ? Colors.grey.shade400 : Colors.white, width: 1.5),
                            ),
                          ),
                          label: Text(
                            colorName,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? textColor : null),
                          ),
                          selected: isSelected,
                          selectedColor: brandColor,
                          checkmarkColor: textColor,
                          side: BorderSide(
                            color: isSelected ? (isWhite ? Colors.grey.shade400 : brandColor) : colorScheme.outlineVariant,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedCompetitorColors.add(colorName);
                              } else {
                                _selectedCompetitorColors.remove(colorName);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    if (_selectedCompetitorColors.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Note: Select at least one color if competitor freezer is present.',
                          style: TextStyle(fontSize: 11, color: colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionHeader({required String number, required String question, required String explanation, required ColorScheme colorScheme}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(6)),
              child: Text(
                number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(question, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(explanation, style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, height: 1.25)),
        ),
      ],
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? selectedColor : Theme.of(context).colorScheme.outlineVariant, width: selected ? 2.0 : 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? selectedColor : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12.5, fontWeight: selected ? FontWeight.bold : FontWeight.w500, color: selected ? selectedColor : null),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme colorScheme, bool isDark) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
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
                Icon(Icons.timeline_rounded, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text('Prospect Status Pipeline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Track progress from initial field discovery to active merchant engagement.',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: ProspectStatus.all.map((status) {
                final isSelected = _selectedStatus == status;
                final statusColor = ProspectStatus.statusColor(status);
                final statusIcon = ProspectStatus.statusIcon(status);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _selectedStatus = status),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? statusColor.withValues(alpha: 0.16) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? statusColor : colorScheme.outlineVariant, width: isSelected ? 2.0 : 1.0),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, color: isSelected ? statusColor : colorScheme.outline, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? statusColor : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
