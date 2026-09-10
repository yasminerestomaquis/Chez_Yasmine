/// Formate un montant en séparant les milliers par une espace (ex. 147000 → "147 000").
/// Utilisé pour tout affichage de prix/montant — jamais pour un champ éditable
/// (le texte d'un `TextEditingController` doit rester un nombre brut parsable).
String formatAmount(num value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return rounded < 0 ? '-$buffer' : buffer.toString();
}
