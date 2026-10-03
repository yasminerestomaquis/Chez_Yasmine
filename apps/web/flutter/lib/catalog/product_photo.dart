import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'catalog_repository.dart';
import 'product_photo_service.dart';

/// Photo d'un produit, lisible hors ligne. Remplace les anciens
/// `FutureBuilder` + `Image.network` : copie locale d'abord, URL signée
/// seulement si l'appareil est en ligne et qu'aucune copie n'existe,
/// [fallback] (icône de remplacement) sinon.
class ProductPhoto extends StatefulWidget {
  const ProductPhoto({
    super.key,
    required this.repository,
    required this.productId,
    required this.imageId,
    required this.backgroundColor,
    required this.fallback,
    this.fit = BoxFit.contain,
    this.cacheWidth,
  });

  final CatalogRepository repository;
  final String productId;
  final String imageId;
  final Color backgroundColor;
  final Widget fallback;
  final BoxFit fit;

  /// Largeur de décodage : une vignette de 48 px n'a pas besoin de décoder
  /// les 400 px de la copie stockée.
  final int? cacheWidth;

  @override
  State<ProductPhoto> createState() => _ProductPhotoState();
}

class _ProductPhotoState extends State<ProductPhoto> {
  late Future<Uint8List?> _bytes;
  Uint8List? _initial;

  ProductPhotoService get _service => ProductPhotoService.instance;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ProductPhoto old) {
    super.didUpdateWidget(old);
    if (old.imageId != widget.imageId || old.productId != widget.productId) _resolve();
  }

  void _resolve() {
    _initial = _service.peek(widget.repository.establishmentId, widget.imageId);
    _bytes = _initial != null
        ? Future.value(_initial)
        : _service.load(widget.repository, widget.productId, widget.imageId);
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.enabled) return _networkImage();
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      initialData: _initial,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done && snapshot.data == null) {
          return ColoredBox(color: widget.backgroundColor);
        }
        final bytes = snapshot.data;
        if (bytes == null) return widget.fallback;
        return ColoredBox(
          color: widget.backgroundColor,
          child: Image.memory(
            bytes,
            fit: widget.fit,
            cacheWidth: widget.cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.fallback,
          ),
        );
      },
    );
  }

  // Plateformes sans IndexedDB : comportement historique, affichage réseau.
  Widget _networkImage() {
    return FutureBuilder<String>(
      future: widget.repository.getImageUrl(widget.productId, widget.imageId, variant: 'small'),
      builder: (context, snapshot) {
        if (snapshot.hasError) return widget.fallback;
        if (!snapshot.hasData) return ColoredBox(color: widget.backgroundColor);
        return ColoredBox(
          color: widget.backgroundColor,
          child: Image.network(snapshot.data!, fit: widget.fit, cacheWidth: widget.cacheWidth),
        );
      },
    );
  }
}
