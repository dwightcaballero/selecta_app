import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class HapiStorePage extends StatefulWidget {
  const HapiStorePage({super.key, required this.hapiStoreID, required this.hapistore});

  final String hapiStoreID;
  final Hapistore hapistore;

  @override
  State<HapiStorePage> createState() => _HapiStorePageState();
}

class _HapiStorePageState extends State<HapiStorePage> {
  static const String monday = 'Monday';
  static const String tuesday = 'Tuesday';
  static const String wednesday = 'Wednesday';
  static const String thursday = 'Thursday';
  static const String friday = 'Friday';
  static const String saturday = 'Saturday';
  static const String sunday = 'Sunday';

  static const List<String> _pjpScheduleDays = [monday, tuesday, wednesday, thursday, friday, saturday, sunday];

  final HapiStoreService db = HapiStoreService();
  late TextEditingController txtAddress;
  late TextEditingController txtContact;
  late TextEditingController txtName;
  late TextEditingController txtLatitude;
  late TextEditingController txtLongitude;
  double? _latitude;
  double? _longitude;
  bool _isLocating = false;
  final MapController _mapController = MapController();
  DateTime? _selectedOpeningDate;
  String? _selectedPjpSchedule;

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    txtName.dispose();
    txtContact.dispose();
    txtAddress.dispose();
    txtLatitude.dispose();
    txtLongitude.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    txtName = TextEditingController(text: widget.hapistore.storeName);
    txtAddress = TextEditingController(text: widget.hapistore.storeAddress);
    txtContact = TextEditingController(text: widget.hapistore.storeContact);
    _latitude = widget.hapistore.latitude;
    _longitude = widget.hapistore.longitude;
    txtLatitude = TextEditingController(
      text: _latitude != null ? _latitude!.toStringAsFixed(6) : '',
    );
    txtLongitude = TextEditingController(
      text: _longitude != null ? _longitude!.toStringAsFixed(6) : '',
    );
    _selectedOpeningDate = widget.hapistore.openingDate?.toDate();
    _selectedPjpSchedule = _pjpScheduleDays.contains(widget.hapistore.pjpSchedule) ? widget.hapistore.pjpSchedule : null;
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedOpeningDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedOpeningDate = dateTime;
      });
    }
  }

  void onClearDate() {
    setState(() {
      _selectedOpeningDate = null;
    });
  }

  void _updateCoordinates(double lat, double lng) {
    setState(() {
      _latitude = lat;
      _longitude = lng;
      txtLatitude.text = lat.toStringAsFixed(6);
      txtLongitude.text = lng.toStringAsFixed(6);
    });
  }

  void _onManualCoordinateChanged() {
    final lat = double.tryParse(txtLatitude.text.trim());
    final lng = double.tryParse(txtLongitude.text.trim());
    if (lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
      setState(() {
        _latitude = lat;
        _longitude = lng;
      });
      _mapController.move(LatLng(lat, lng), 15.0);
    } else if (txtLatitude.text.trim().isEmpty && txtLongitude.text.trim().isEmpty) {
      setState(() {
        _latitude = null;
        _longitude = null;
      });
    }
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      txtLatitude.clear();
      txtLongitude.clear();
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ShowMessage.error(context, 'Location services are disabled. Please enable GPS.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ShowMessage.error(context, 'Location permission denied.');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ShowMessage.error(context, 'Location permission is permanently denied. Please allow it in settings.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      _updateCoordinates(position.latitude, position.longitude);
      _mapController.move(LatLng(position.latitude, position.longitude), 16.0);

      if (mounted) {
        ShowMessage.success(context, 'Location acquired: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to get location: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void onSave() {
    if (_formKey.currentState!.validate()) {
      final lat = double.tryParse(txtLatitude.text.trim());
      final lng = double.tryParse(txtLongitude.text.trim());
      Hapistore newHs = Hapistore(
        storeName: txtName.text.trim().toUpperCase(),
        storeAddress: txtAddress.text.trim(),
        storeContact: txtContact.text.trim(),
        openingDate: _selectedOpeningDate != null ? Timestamp.fromDate(_selectedOpeningDate!) : null,
        pjpSchedule: _selectedPjpSchedule,
        latitude: lat,
        longitude: lng,
      );
      db.addHapiStore(newHs);
      Helperfunctions.logCreate(newHs.storeName, newHs.toJson());
      ShowMessage.success(context, 'Successfully created Hapi Store [${newHs.storeName}]!');
      Navigator.pop(context);
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onUpdate() {
    if (_formKey.currentState!.validate()) {
      final lat = double.tryParse(txtLatitude.text.trim());
      final lng = double.tryParse(txtLongitude.text.trim());
      Hapistore updatedHS = widget.hapistore.copyWith(
        storeName: txtName.text.trim().toUpperCase(),
        storeAddress: txtAddress.text.trim(),
        storeContact: txtContact.text.trim(),
        openingDate: _selectedOpeningDate != null ? Timestamp.fromDate(_selectedOpeningDate!) : null,
        clearOpeningDate: _selectedOpeningDate == null,
        pjpSchedule: _selectedPjpSchedule,
        latitude: lat,
        longitude: lng,
        clearLocation: lat == null || lng == null,
      );
      db.updateHapiStore(widget.hapiStoreID, updatedHS);
      Helperfunctions.logUpdate(updatedHS.storeName, widget.hapistore.toJson(), updatedHS.toJson());
      ShowMessage.success(context, 'Successfully updated Hapi Store [${updatedHS.storeName}]!');
      Navigator.pop(context);
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onDelete() {
    db.deleteHapiStore(widget.hapiStoreID);
    Helperfunctions.logDelete(widget.hapistore.storeName, widget.hapistore.toJson());
    ShowMessage.success(context, 'Successfully deleted Hapi Store [${widget.hapistore.storeName}]!');
    Navigator.pop(context);
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStoreDetailsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Store Information',
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          // Store Name
          TextFormField(
            controller: txtName,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Store Name',
              hintText: 'e.g. DWIGHT MINI STORE',
              prefixIcon: Icon(Icons.store_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Store Name should not be blank';
              return null;
            },
          ),

          // Contact Number
          TextFormField(
            controller: txtContact,
            maxLength: 11,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Contact Number',
              hintText: '09XXXXXXXXX',
              counterText: '',
              prefixIcon: Icon(Icons.phone_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Contact Number should not be blank';
              if (value.trim().length != 11) return 'Contact Number should consist of 11 digits';
              return null;
            },
          ),

          // Store Address
          TextFormField(
            controller: txtAddress,
            keyboardType: TextInputType.streetAddress,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Store Address',
              hintText: 'e.g. Purok 14, Saavedra Village, Bago Aplaya...',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.location_on_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Address should not be blank';
              return null;
            },
          ),

          // Opening Date
          _buildDatePickerField(label: 'Opening Date', selectedDate: _selectedOpeningDate, onTap: onChangeDate, onClear: onClearDate),

          DropdownButtonFormField<String>(
            initialValue: _selectedPjpSchedule,
            decoration: InputDecoration(
              labelText: 'PJP Schedule',
              prefixIcon: Icon(Icons.calendar_view_week_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            items: _pjpScheduleDays.map((day) => DropdownMenuItem(value: day, child: Text(day))).toList(),
            onChanged: (value) {
              setState(() {
                _selectedPjpSchedule = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField({required String label, required DateTime? selectedDate, required VoidCallback onTap, VoidCallback? onClear}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black54),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  Text(
                    selectedDate != null ? Helperfunctions.formatDateForDisplay(selectedDate) : 'Select Date',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                      color: selectedDate != null ? null : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selectedDate != null && onClear != null)
              IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: onClear, padding: EdgeInsets.zero, constraints: const BoxConstraints())
            else
              Icon(Icons.edit_calendar_outlined, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isUpdating = widget.hapiStoreID.isNotEmpty;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: isUpdating
            ? Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.delete,
                          message: 'Are you sure you want to delete [${widget.hapistore.storeName}]?',
                          isDestructive: true,
                          icon: Icons.delete_outline,
                          confirmText: 'Delete',
                        );
                        if (confirmed) onDelete();
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50.0),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.update,
                          message: 'Save changes to store [${txtName.text.trim().toUpperCase()}]?',
                          icon: Icons.check_circle_outline,
                          confirmText: 'Update',
                        );
                        if (confirmed) onUpdate();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Update Store', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () async {
                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: ConfirmTitle.save,
                    message: 'Save new store [${txtName.text.trim().toUpperCase()}]?',
                    icon: Icons.save_outlined,
                    confirmText: 'Save',
                  );
                  if (confirmed) onSave();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Store', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  Widget _buildLocationCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final LatLng mapCenter = _latitude != null && _longitude != null
        ? LatLng(_latitude!, _longitude!)
        : const LatLng(7.0731, 125.6128); // Davao default center for Selecta operations

    return _buildSectionCard(
      title: 'Store Location & Coordinates',
      icon: Icons.map_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Button to get current user location
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isLocating ? null : _getCurrentLocation,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isLocating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.my_location_rounded, size: 20),
                  label: Text(
                    _isLocating ? 'Detecting Location...' : 'Get My Location',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _clearLocation,
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  tooltip: 'Clear location',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Map preview container with OpenStreetMap
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: mapCenter,
                    initialZoom: _latitude != null ? 16.0 : 13.0,
                    onTap: (_, point) {
                      _updateCoordinates(point.latitude, point.longitude);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.selecta.selecta_app',
                    ),
                    if (_latitude != null && _longitude != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_latitude!, _longitude!),
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _latitude != null && _longitude != null
                          ? 'Pinned: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)} (Tap map to move)'
                          : 'Tap anywhere on the map or use "Get My Location" to pin',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Manual Latitude & Longitude Inputs
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: txtLatitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: 'Latitude',
                    hintText: 'e.g. 7.073100',
                    prefixIcon: Icon(Icons.explore_outlined, size: 18, color: colorScheme.primary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => _onManualCoordinateChanged(),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return null;
                    final parsed = double.tryParse(val.trim());
                    if (parsed == null || parsed < -90 || parsed > 90) {
                      return 'Invalid latitude (-90 to 90)';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: txtLongitude,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: 'Longitude',
                    hintText: 'e.g. 125.612800',
                    prefixIcon: Icon(Icons.explore_outlined, size: 18, color: colorScheme.primary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (_) => _onManualCoordinateChanged(),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return null;
                    final parsed = double.tryParse(val.trim());
                    if (parsed == null || parsed < -180 || parsed > 180) {
                      return 'Invalid longitude (-180 to 180)';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Hapi Store', subtitle: widget.hapiStoreID.isEmpty ? 'New Store Record' : widget.hapistore.storeName),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              // 1. Store Details Card
              _buildStoreDetailsCard(),

              // 2. Store Location & Map Card
              _buildLocationCard(),
            ],
          ),
        ),
      ),
    );
  }
}
