import 'package:flutter/material.dart';

/// N° de commande proposés pour un produit — réponse de
/// `GET .../losses/order-numbers/:productId` et `GET .../products/:id/order-numbers`.
class OrderNumberChoices {
  const OrderNumberChoices({required this.required, required this.options, this.defaultOrderNumber});

  /// Vrai pour un produit à prix par casier (Bières, Vins, Sucreries) : champ obligatoire.
  final bool required;
  final List<int> options;

  /// Commande du dernier lot actif (ou récent) du produit.
  final int? defaultOrderNumber;

  factory OrderNumberChoices.fromJson(Map<String, dynamic> json) => OrderNumberChoices(
        required: json['required'] as bool? ?? false,
        options: (json['options'] as List<dynamic>? ?? const []).map((e) => (e as num).toInt()).toList(),
        defaultOrderNumber: (json['defaultOrderNumber'] as num?)?.toInt(),
      );
}

/// Champ « N° de la commande », affiché seulement pour les produits concernés
/// (demande utilisateur du 2026-09-20) et obligatoire. Valeur par défaut :
/// dernière commande active du produit (`initialValue` l'emporte, pour la
/// modification d'une perte). Sans réseau, retombe sur une saisie numérique.
class OrderNumberField extends StatefulWidget {
  const OrderNumberField({
    super.key,
    required this.productId,
    required this.loader,
    required this.onChanged,
    this.initialValue,
  });

  final String? productId;
  final Future<OrderNumberChoices> Function(String productId) loader;
  final ValueChanged<int?> onChanged;
  final int? initialValue;

  @override
  State<OrderNumberField> createState() => _OrderNumberFieldState();
}

class _OrderNumberFieldState extends State<OrderNumberField> {
  OrderNumberChoices? _choices;
  bool _failed = false;
  bool _loading = false;
  int? _value;
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrderNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) _load();
  }

  Future<void> _load() async {
    final productId = widget.productId;
    _loadedFor = productId;
    if (productId == null) {
      setState(() {
        _choices = null;
        _failed = false;
        _value = null;
      });
      widget.onChanged(null);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
      _choices = null;
      _value = null;
    });
    widget.onChanged(null);
    try {
      final choices = await widget.loader(productId);
      if (!mounted || _loadedFor != productId) return;
      final initial = widget.initialValue;
      final value = choices.required
          ? (initial != null && choices.options.contains(initial) ? initial : choices.defaultOrderNumber)
          : null;
      setState(() {
        _choices = choices;
        _value = value;
        _loading = false;
      });
      widget.onChanged(value);
    } catch (_) {
      if (!mounted || _loadedFor != productId) return;
      setState(() {
        _failed = true;
        _loading = false;
        _value = widget.initialValue;
      });
      widget.onChanged(widget.initialValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.productId == null) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
    }
    if (_failed) {
      // Hors ligne : liste indisponible, saisie libre (le serveur valide au rejeu).
      return TextFormField(
        initialValue: _value?.toString(),
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'N° de la commande *'),
        onChanged: (v) => widget.onChanged(int.tryParse(v.trim())),
        validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'N° de la commande obligatoire' : null,
      );
    }
    final choices = _choices;
    if (choices == null || !choices.required) return const SizedBox.shrink();
    return DropdownButtonFormField<int>(
      key: ValueKey('order-$_loadedFor-$_value'),
      initialValue: _value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'N° de la commande *'),
      items: choices.options.map((n) => DropdownMenuItem(value: n, child: Text('Commande n°$n'))).toList(),
      onChanged: (v) {
        setState(() => _value = v);
        widget.onChanged(v);
      },
      validator: (v) => v == null ? 'N° de la commande obligatoire' : null,
    );
  }
}
