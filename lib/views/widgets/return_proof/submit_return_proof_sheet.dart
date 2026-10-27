import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/dto/endofday_dto.dart';
import 'package:selecta_ops/models/return_proof.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/services/return_proof_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

/// Modal bottom sheet allowing salesmen to capture and submit proof of return for a store.
class SubmitReturnProofSheet extends StatefulWidget {
  final StoreReturnProofSummary storeSummary;
  final DateTime date;
  final VoidCallback onSubmitted;

  const SubmitReturnProofSheet({
    super.key,
    required this.storeSummary,
    required this.date,
    required this.onSubmitted,
  });

  @override
  State<SubmitReturnProofSheet> createState() => _SubmitReturnProofSheetState();
}

class _SubmitReturnProofSheetState extends State<SubmitReturnProofSheet> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _notesController = TextEditingController();
  final ReturnProofService _returnProofService = ReturnProofService();

  File? _capturedImage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (picked != null && mounted) {
        setState(() {
          _capturedImage = File(picked.path);
        });
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'SubmitReturnProofSheet',
        action: 'Capture Camera Photo',
        error: e,
        stackTrace: s,
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to open camera: $e');
      }
    }
  }

  Future<String> _uploadProofImage(File file) async {
    final rawBytes = await file.readAsBytes();
    final compressedBytes = await Helperfunctions.compressImageBytes(rawBytes);

    final dayKey = ReturnProofService.buildDayKey(widget.date).replaceAll('-', '');
    final sanitizedStore = widget.storeSummary.storeName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = 'proof_of_return/$dayKey/$sanitizedStore/$timestamp.jpg';

    final ref = FirebaseStorage.instance.ref().child(filePath);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      cacheControl: 'public, max-age=31536000',
    );

    await ref.putData(compressedBytes, metadata).timeout(const Duration(seconds: 30));
    return await ref.getDownloadURL().timeout(const Duration(seconds: 20));
  }

  Future<void> _submit() async {
    if (_capturedImage == null) {
      ShowMessage.error(context, 'Please capture a photo proof of the returned items.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final downloadUrl = await _uploadProofImage(_capturedImage!);
      final currentUser = authService.value.currentUser;
      final submittedByName = currentUser?.displayName ?? currentUser?.email ?? 'Salesman';

      await _returnProofService.submitProof(
        storeName: widget.storeSummary.storeName,
        date: widget.date,
        deliveriesWithIds: widget.storeSummary.deliveriesWithIds,
        imageUrl: downloadUrl,
        notes: _notesController.text.trim(),
        submittedBy: submittedByName,
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Proof of return submitted for ${widget.storeSummary.storeName}!');
      widget.onSubmitted();
      Navigator.pop(context, true);
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'SubmitReturnProofSheet',
        action: 'Submit Return Proof',
        error: e,
        stackTrace: s,
        extraData: {'store': widget.storeSummary.storeName},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to submit proof: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = <ReturnProofItem>[];
    for (final entry in widget.storeSummary.deliveriesWithIds) {
      items.addAll(ReturnProofService.extractReturnItemsFromDelivery(entry.value, entry.key));
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_return_rounded, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submit Proof of Return',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.storeSummary.storeName,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Rejection banner if previous submission was rejected
            if (widget.storeSummary.isRejected && widget.storeSummary.rejectReason != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withAlpha(60)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Previous submission rejected: ${widget.storeSummary.rejectReason}',
                        style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Return items summary list
            Text(
              'Returned Products (${items.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(100),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: colorScheme.outlineVariant.withAlpha(60),
                ),
                itemBuilder: (context, index) {
                  final it = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            it.productName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(40),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${it.returnedQuantity} units',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Camera photo capture section
            Text(
              'Return Proof Photo (Camera Only)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_capturedImage == null) ...[
              InkWell(
                onTap: _takePhoto,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(100),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.primary.withAlpha(120),
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_rounded, size: 40, color: colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        'Take Photo of Returned Goods',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Exactly 1 photo required (no gallery upload)',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _capturedImage!,
                      width: double.infinity,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                        tooltip: 'Retake Photo',
                        onPressed: _takePhoto,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Notes
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes / Reason for Return (Optional)',
                hintText: 'e.g., Damaged box, expired stock, store closed',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // Submit button
            AsyncFilledButton.icon(
              onPressed: _capturedImage == null || _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(_isSubmitting ? 'Uploading & Submitting...' : 'Submit Proof to Warehouse'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
