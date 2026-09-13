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
