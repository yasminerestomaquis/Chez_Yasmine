import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import 'catalog_repository.dart';
import 'models.dart';

/// Formulaire de création/édition d'un produit, avec le sélecteur photo natif
/// requis par le prompt maître §18 : prendre une photo, choisir dans la
/// galerie, importer un fichier, ou utiliser l'image générique.
class ProductFormPage extends StatefulWidget {
  const ProductFormPage({super.key, required this.repository, required this.categories, this.existing});

  final CatalogRepository repository;
  final List<Category> categories;
  final Product? existing;

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _referenceController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _unitController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _salePriceController;
  late final TextEditingController _vatRateController;
  late final TextEditingController _minStockController;
  late final TextEditingController _initialStockController;
  String? _categoryId;
  bool _isSubmitting = false;

  Uint8List? _pickedImageBytes;
  String _pickedFilename = 'photo.jpg';
  String _pickedContentType = 'image/jpeg';

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameController = TextEditingController(text: p?.name ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _referenceController = TextEditingController(text: p?.reference ?? '');
    _barcodeController = TextEditingController(text: p?.barcode ?? '');
    _unitController = TextEditingController(text: p?.unit ?? '');
    _purchasePriceController = TextEditingController(text: p?.purchasePrice?.toString() ?? '');
    _salePriceController = TextEditingController(text: p?.salePrice.toString() ?? '');
    _vatRateController = TextEditingController(text: p?.vatRate?.toString() ?? '');
    _minStockController = TextEditingController(text: p?.minStock?.toString() ?? '');
    _initialStockController = TextEditingController(text: '0');
    _categoryId = p?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _referenceController.dispose();
    _barcodeController.dispose();
    _unitController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _vatRateController.dispose();
    _minStockController.dispose();
    _initialStockController.dispose();
    super.dispose();
  }

  Future<void> _pickFromCamera() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImageBytes = bytes;
      _pickedFilename = file.name;
      _pickedContentType = file.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImageBytes = bytes;
      _pickedFilename = file.name;
      _pickedContentType = file.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _pickFromFile() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImageBytes = bytes;
      _pickedFilename = file.name;
      _pickedContentType = _guessContentType(file.extension);
    });
  }

  Future<void> _useGenericImage() async {
    final data = await rootBundle.load('assets/generic_product.png');
    setState(() {
      _pickedImageBytes = data.buffer.asUint8List();
      _pickedFilename = 'generic_product.png';
      _pickedContentType = 'image/png';
    });
  }

  String _guessContentType(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  double? _parseNumber(String text) => text.trim().isEmpty ? null : double.tryParse(text.trim().replaceAll(',', '.'));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        if (_categoryId != null) 'categoryId': _categoryId,
        if (_descriptionController.text.trim().isNotEmpty) 'description': _descriptionController.text.trim(),
        if (_referenceController.text.trim().isNotEmpty) 'reference': _referenceController.text.trim(),
        if (_barcodeController.text.trim().isNotEmpty) 'barcode': _barcodeController.text.trim(),
        if (_unitController.text.trim().isNotEmpty) 'unit': _unitController.text.trim(),
        if (_parseNumber(_purchasePriceController.text) != null) 'purchasePrice': _parseNumber(_purchasePriceController.text),
        'salePrice': _parseNumber(_salePriceController.text),
        if (_parseNumber(_vatRateController.text) != null) 'vatRate': _parseNumber(_vatRateController.text),
        if (_parseNumber(_minStockController.text) != null) 'minStock': _parseNumber(_minStockController.text),
        if (!_isEditing) 'stockQuantity': _parseNumber(_initialStockController.text) ?? 0,
      };

      final product = _isEditing
          ? await widget.repository.updateProduct(widget.existing!.id, payload)
          : await widget.repository.createProduct(payload);

      if (_pickedImageBytes != null) {
        await widget.repository.uploadProductImage(product.id, _pickedImageBytes!, _pickedFilename, _pickedContentType);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Modifier le produit' : 'Nouveau produit')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PhotoPicker(
              bytes: _pickedImageBytes,
              onCamera: _pickFromCamera,
              onGallery: _pickFromGallery,
              onFile: _pickFromFile,
              onGeneric: _useGenericImage,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nom *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _referenceController, decoration: const InputDecoration(labelText: 'Référence'))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _barcodeController, decoration: const InputDecoration(labelText: 'Code-barres'))),
            ]),
            const SizedBox(height: 12),
            TextFormField(controller: _unitController, decoration: const InputDecoration(labelText: 'Unité (ex : bouteille, portion)')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _purchasePriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Prix d'achat"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _salePriceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Prix de vente (FCFA) *'),
                  validator: (v) => _parseNumber(v ?? '') == null ? 'Requis' : null,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _vatRateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'TVA (%)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _minStockController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Stock minimum'),
                ),
              ),
            ]),
            if (!_isEditing) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _initialStockController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Stock initial'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isEditing ? 'Enregistrer' : 'Créer le produit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.bytes,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onGeneric,
  });

  final Uint8List? bytes;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final VoidCallback onGeneric;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 160,
          width: 160,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes != null
              ? Image.memory(bytes!, fit: BoxFit.cover)
              : const Icon(Icons.image_outlined, size: 48),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(onPressed: onCamera, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Prendre une photo')),
            OutlinedButton.icon(onPressed: onGallery, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choisir dans la galerie')),
            OutlinedButton.icon(onPressed: onFile, icon: const Icon(Icons.folder_open_outlined), label: const Text('Importer un fichier')),
            OutlinedButton.icon(onPressed: onGeneric, icon: const Icon(Icons.image_outlined), label: const Text("Image générique")),
          ],
        ),
      ],
    );
  }
}
