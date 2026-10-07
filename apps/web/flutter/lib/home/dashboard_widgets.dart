import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Teinte d'une vignette du tableau de bord : dégradé doux (début → fin) et
/// couleur d'accent (pastille d'icône, filigrane). Purement visuel.
class DashTone {
  const DashTone(this.start, this.end, this.accent);

  final Color start;
  final Color end;
  final Color accent;

  static const green = DashTone(
    Color(0xFFEFFAF1),
    Color(0xFFC8ECCF),
    Color(0xFF1E9E3A),
  );
  static const blue = DashTone(
    Color(0xFFEFF7FE),
    Color(0xFFC9E3FA),
    Color(0xFF1F8FE0),
  );
  static const orange = DashTone(
    Color(0xFFFFF5E8),
    Color(0xFFFFDDB5),
    Color(0xFFF97316),
  );
  static const red = DashTone(
    Color(0xFFFFF0F0),
    Color(0xFFFAD0D3),
    Color(0xFFE03A3E),
  );
  static const purple = DashTone(
    Color(0xFFF6F0FD),
    Color(0xFFDCCFF4),
    Color(0xFF7A3FC9),
  );
  static const teal = DashTone(
    Color(0xFFEBF9F6),
    Color(0xFFC6EDE4),
    Color(0xFF12A38A),
  );

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [start, end],
  );
}

/// Pastille ronde pleine avec icône blanche.
class DashBadge extends StatelessWidget {
  const DashBadge({
    super.key,
    required this.icon,
    required this.tone,
    this.size = 40,
  });

  final IconData icon;
  final DashTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(tone.accent, Colors.white, 0.22)!,
            tone.accent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: tone.accent.withValues(alpha: 0.30),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}

/// Vignette de statistique : dégradé, pastille d'icône, désignation, valeur.
///
/// - [large] : carte pleine largeur (Total ventes) ;
/// - [compact] : carte étroite (3 par ligne) — pastille et images en haut,
///   désignation puis valeur en dessous, pour que les longues désignations
///   (« Boissons sans Gbêlê - Mobile Money ») restent entièrement lisibles ;
/// - [images] : petites illustrations (assets) affichées à droite ;
/// - [watermark] : grande icône estompée en fond.
class DashStatCard extends StatelessWidget {
  const DashStatCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.label,
    required this.value,
    this.large = false,
    this.compact = false,
    this.images = const [],
    this.watermark,
    this.labelSuffixIcon,
  });

  final DashTone tone;
  final IconData icon;
  final String label;
  final String value;
  final bool large;
  final bool compact;
  final List<String> images;
  final IconData? watermark;
  final IconData? labelSuffixIcon;

  Widget _image(String asset, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover),
  );

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: large ? 14 : (compact ? 11.5 : 13),
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
      height: 1.25,
    );
    final valueStyle = TextStyle(
      fontSize: large ? 34 : (compact ? 17 : 24),
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.1,
    );
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: Text(label, softWrap: true, style: labelStyle)),
        if (labelSuffixIcon != null) ...[
          const SizedBox(width: 6),
          Icon(labelSuffixIcon, size: 16, color: tone.accent),
        ],
      ],
    );
    final valueWidget = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value, style: valueStyle),
    );

    final Widget content;
    if (compact) {
      final imageSize = images.length <= 1 ? 38.0 : 22.0;
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashBadge(icon: icon, tone: tone, size: 32),
              const Spacer(),
              for (var i = 0; i < images.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                _image(images[i], imageSize),
              ],
            ],
          ),
          const SizedBox(height: 8),
          labelWidget,
          const SizedBox(height: 4),
          valueWidget,
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashBadge(icon: icon, tone: tone, size: large ? 46 : 40),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: labelWidget,
                ),
              ),
            ],
          ),
          SizedBox(height: large ? 8 : 6),
          Padding(
            padding: EdgeInsets.only(left: large ? 0 : 52),
            child: valueWidget,
          ),
        ],
      );
    }

    final rightInset = !compact && images.isNotEmpty ? 70.0 : 0.0;
    return Container(
      decoration: BoxDecoration(
        gradient: tone.gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.accent.withValues(alpha: 0.14)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (watermark != null)
            Positioned(
              right: -8,
              bottom: -12,
              child: Icon(
                watermark,
                size: large ? 120 : 76,
                color: tone.accent.withValues(alpha: 0.14),
              ),
            ),
          if (!compact && images.isNotEmpty)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final a in images) _image(a, 56)],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 14,
              compact ? 10 : 14,
              (compact ? 10 : 14) + rightInset,
              compact ? 10 : 14,
            ),
            child: content,
          ),
        ],
      ),
    );
  }
}

/// Titre de rubrique : icône, intitulé en capitales, filet qui s'étire.
class DashSectionTitle extends StatelessWidget {
  const DashSectionTitle({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Icon(icon, size: 20, color: AppColors.greenDark),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppColors.greenDark,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.green.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tuile cliquable (action rapide ou module) : pastille colorée + libellé.
/// Disposition en ligne quand la tuile est large, en colonne quand elle est
/// étroite (4 actions rapides côte à côte sur un téléphone).
class DashTile extends StatelessWidget {
  const DashTile({
    super.key,
    required this.tone,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final DashTone tone;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: tone.gradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tone.accent.withValues(alpha: 0.14)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 130;
              const style = TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              );
              if (wide) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      DashBadge(icon: icon, tone: tone, size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: style,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DashBadge(icon: icon, tone: tone, size: 32),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, style: style.copyWith(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
