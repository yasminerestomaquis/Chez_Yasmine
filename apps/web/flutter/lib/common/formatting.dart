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

/// Formate un montant décimal avec virgule française, milliers séparés par
/// une espace comme `formatAmount` (ex. 3333.333 → "3 333,33"). Utilisé pour
/// le prix au litre et la quantité d'une ligne à prix de référence variable
/// (ex. Gbêlê) : contrairement à `formatAmount`, ne doit jamais arrondir à
/// l'entier — une quantité de 0,03 L affichée "0" serait trompeuse (voir
/// `CartPanel`).
String formatDecimalAmount(num value, {int decimals = 2}) {
  final isNegative = value < 0;
  // `toStringAsFixed` sur la valeur complète (plutôt que floor + reste)
  // gère seule la retenue d'arrondi (ex. 3333.999 -> "3334.00", pas "3333.00").
  final fixed = value.abs().toStringAsFixed(decimals);
  final dotIndex = fixed.indexOf('.');
  final integerPart = int.parse(fixed.substring(0, dotIndex));
  final fractional = fixed.substring(dotIndex + 1);
  final result = '${formatAmount(integerPart)},$fractional';
  return isNegative ? '-$result' : result;
}

/// « il y a X » à partir d'un instant passé (ex. dernière connexion d'un
/// membre — voir `lib/users/users_page.dart`). Pas de dépendance à `intl`
/// pour un besoin aussi simple.
String formatRelativeTime(DateTime since) {
  final diff = DateTime.now().difference(since);
  if (diff.inSeconds < 60) return "à l'instant";
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return 'il y a $m minute${m > 1 ? 's' : ''}';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return 'il y a $h heure${h > 1 ? 's' : ''}';
  }
  final d = diff.inDays;
  return 'il y a $d jour${d > 1 ? 's' : ''}';
}
