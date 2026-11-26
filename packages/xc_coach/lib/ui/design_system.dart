import 'package:flutter/material.dart';

export 'design_components.dart';

/// Shared visual language for the Giulia training computer.
///
/// Calm and technical: a warm, desaturated ground, one turquoise accent, and
/// colour otherwise only where it carries a meaning (left, right, warning).
abstract final class GiuliaTokens {
  static const spacingXs = 4.0;
  static const spacingS = 8.0;
  static const spacingM = 16.0;
  static const spacingL = 24.0;
  static const spacingXl = 32.0;
  static const spacingXxl = 48.0;

  static const radiusS = 6.0;
  static const radiusM = 10.0;
  static const radiusL = 12.0;

  /// Cards and chart containers.
  static const radiusCard = radiusL;

  /// Buttons, inputs, segmented controls.
  static const radiusButton = radiusM;

  static const surface0 = Color(0xFFF6F5F1);
  static const surface1 = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFFAF9F6);
  static const surface3 = Color(0xFFEFEDE7);

  /// Hairlines between areas; cards are told apart by this, not by shadow.
  static const border = Color(0xFFE5E2DA);
  static const borderStrong = Color(0xFFD3CFC5);

  static const textPrimary = Color(0xFF15222E);
  static const textSecondary = Color(0xFF4B5763);
  static const textMuted = Color(0xFF7D8690);

  /// The GIULIA turquoise. Dark enough for white text on a filled button.
  static const accent = Color(0xFF0B7C7A);
  static const accentSoft = Color(0xFFDCEFEE);
  static const aqua = accent;
  static const aquaSoft = accentSoft;
  static const success = Color(0xFF1E7F5C);
  static const warning = Color(0xFFB0701A);
  static const error = Color(0xFFC23B32);

  /// Herzfrequenz, überall dieselbe Farbe.
  static const heartRate = Color(0xFFD62839);

  static const metricXl = 80.0;
  static const metricL = 42.0;
  static const metricM = 26.0;

  /// Hero, primary and secondary metric sizes; units run at [unitRatio].
  static const metricHero = 88.0;
  static const metricPrimary = 40.0;
  static const metricSecondary = 24.0;
  static const unitRatio = .38;

  /// Readable measure for running text and metric groups on wide screens.
  static const maxTextWidth = 640.0;
  static const maxContentWidth = 1180.0;

  static const iconS = 16.0;
  static const iconM = 20.0;
  static const iconL = 28.0;

  /// The product's typeface — in one place, for one reason.
  ///
  /// Roboto rather than the platform font: a test report has to set the same
  /// line identically on an iPhone, on an Android tablet and on paper. With
  /// each platform's own font it does not — the same zone table wraps on one
  /// device and not on the other. Flutter ships Roboto on every target.
  ///
  /// Which typeface matters less than that there is **one**. Before this
  /// token, `bodyLarge` and its relatives carried the family while the title
  /// and label styles built in `copyWith` did not, so on the device a heading
  /// and the paragraph under it stood in two different typefaces.
  static const fontFamily = 'Roboto';

  /// Left and right, as the two poles of one diverging scale.
  ///
  /// Warm against cool, so the middle of the bar reads as "neither side":
  /// coral red for the left, a clear blue for the right. Neither is the
  /// GIULIA turquoise, so side colour is never mistaken for emphasis. Both
  /// clear 3:1 against white and stay apart under protanopia.
  static const sideLeft = Color(0xFFD9503F);
  static const sideRight = Color(0xFF2F6DB3);

  /// The neutral of that scale. Grey rather than a light blue, because a
  /// tinted track leans towards one side before a value is drawn on it.
  static const sideNeutral = Color(0xFFE6E3DC);

  static const chartGrid = Color(0xFFECE9E2);
  static const chartLine = accent;
  static const chartReference = Color(0xFF8A9199);
  static const chartTooltip = Color(0xFFFFFFFF);
}

/// Die drei Arbeitsumgebungen.
///
/// ## Warum das nicht dasselbe Aussehen für alle ist
///
/// Weil dieselben Karten mit denselben Radien, denselben Abständen und nur
/// anderen Überschriften trotz getrennter Navigation wieder wie **eine**
/// Anwendung wirken. Die Verwandtschaft soll man sehen — Marke, Farben,
/// Diagramme, Bausteine —, die Arbeitsumgebung nicht verwechseln.
///
/// | Produkt | Charakter |
/// |---|---|
/// | Ercolina | sportlich, direkt, grossflächig |
/// | Coach | dicht, analytisch, effizient |
/// | LaLa | präzise, klinisch, dokumentierend |
///
/// Das ist keine Geschmacksfrage, sondern folgt der Nutzung: Der Athlet liest
/// im Stehen und mit feuchten Händen wenige grosse Zahlen. Die Trainerin
/// vergleicht acht Menschen und will viel auf einem Bildschirm. Die
/// Diagnostikerin dokumentiert und braucht Werte, die untereinander
/// ausgerichtet sind.
enum ProductMode {
  ercolina,
  coach,
  lala;

  GiuliaDensity get density => switch (this) {
    // Grossflächig: wenig Elemente, viel Luft, runde Karten.
    ercolina => const GiuliaDensity(
      pagePadding: GiuliaTokens.spacingL,
      cardPadding: GiuliaTokens.spacingL,
      cardRadius: GiuliaTokens.radiusL,
      cardGap: GiuliaTokens.spacingM,
      sectionGap: GiuliaTokens.spacingXl,
      textScale: 1,
    ),
    // Dicht: mehr Zeilen je Bildschirm, kantigere Karten, engere Abstände.
    coach => const GiuliaDensity(
      pagePadding: GiuliaTokens.spacingM,
      cardPadding: 14,
      cardRadius: GiuliaTokens.radiusS,
      cardGap: GiuliaTokens.spacingS,
      sectionGap: GiuliaTokens.spacingL,
      textScale: .94,
    ),
    // Klinisch: sachliche Abstände und Ziffern, die untereinander stehen —
    // in einer Messwertspalte darf keine Zahl gegenüber der darüber
    // verrutschen.
    lala => const GiuliaDensity(
      pagePadding: 20,
      cardPadding: 18,
      cardRadius: GiuliaTokens.radiusM,
      cardGap: GiuliaTokens.spacingS,
      sectionGap: GiuliaTokens.spacingL,
      textScale: .97,
      tabularFigures: true,
    ),
  };
}

/// Wie eng ein Produkt arbeitet.
class GiuliaDensity {
  const GiuliaDensity({
    required this.pagePadding,
    required this.cardPadding,
    required this.cardRadius,
    required this.cardGap,
    required this.sectionGap,
    required this.textScale,
    this.tabularFigures = false,
  });

  /// Rand einer Seite.
  final double pagePadding;

  /// Innenabstand einer Karte.
  final double cardPadding;

  final double cardRadius;

  /// Abstand zwischen zwei Karten.
  final double cardGap;

  /// Abstand zwischen zwei Abschnitten.
  final double sectionGap;

  /// Faktor auf die Schriftgrössen.
  final double textScale;

  /// Ob Ziffern gleich breit gesetzt werden.
  final bool tabularFigures;

  /// Die Dichte, in der dieser Teil der Anwendung läuft.
  static GiuliaDensity of(BuildContext context) =>
      GiuliaProductScope.of(context).density;

  EdgeInsets get pageInsets => EdgeInsets.fromLTRB(
    pagePadding,
    pagePadding,
    pagePadding,
    pagePadding * 1.5,
  );
}

/// Trägt das laufende Produkt durch den Baum.
///
/// Damit die Bausteine — Karte, Abschnittsüberschrift — sich anpassen, ohne
/// dass jeder Bildschirm das Produkt kennt.
class GiuliaProductScope extends InheritedWidget {
  const GiuliaProductScope({
    super.key,
    required this.mode,
    required super.child,
  });

  final ProductMode mode;

  GiuliaDensity get density => mode.density;

  /// Ohne Bereich gilt Ercolina: die grosszügigste Variante. Ein Bildschirm
  /// ohne Produktangabe ist eher ein Test oder ein Bildschirmfoto, und dort
  /// ist Luft das kleinere Übel.
  static GiuliaProductScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GiuliaProductScope>() ??
      const GiuliaProductScope(
        mode: ProductMode.ercolina,
        child: SizedBox.shrink(),
      );

  @override
  bool updateShouldNotify(GiuliaProductScope oldWidget) =>
      oldWidget.mode != mode;
}

ThemeData giuliaLightTheme({ProductMode mode = ProductMode.ercolina}) {
  const colors = ColorScheme.light(
    primary: GiuliaTokens.accent,
    onPrimary: Colors.white,
    primaryContainer: GiuliaTokens.accentSoft,
    onPrimaryContainer: GiuliaTokens.textPrimary,
    secondary: GiuliaTokens.sideRight,
    secondaryContainer: GiuliaTokens.surface3,
    surface: GiuliaTokens.surface1,
    onSurface: GiuliaTokens.textPrimary,
    outline: GiuliaTokens.borderStrong,
    outlineVariant: GiuliaTokens.border,
    error: GiuliaTokens.error,
  );
  final text = Typography.material2021().black
      .apply(
        bodyColor: GiuliaTokens.textPrimary,
        displayColor: GiuliaTokens.textPrimary,
      )
      .copyWith(
        // Measured values: strong but not black-heavy, tight tracking, so a
        // large number reads as an instrument rather than a poster.
        displayLarge: const TextStyle(
          fontSize: GiuliaTokens.metricXl,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.5,
          height: .96,
        ),
        displayMedium: const TextStyle(
          fontSize: 54,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        displaySmall: const TextStyle(
          fontSize: GiuliaTokens.metricL,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
        headlineLarge: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        // Defined because three screens already ask for it. Without an entry
        // here they silently fall through to the Material default, which is a
        // different size and colour than everything around them.
        headlineSmall: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        titleSmall: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        bodyLarge: const TextStyle(
          fontSize: 16,
          height: 1.45,
          color: GiuliaTokens.textSecondary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          height: 1.42,
          color: GiuliaTokens.textSecondary,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.4,
          color: GiuliaTokens.textMuted,
        ),
        labelLarge: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: .1,
        ),
        labelMedium: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: .8,
          color: GiuliaTokens.textMuted,
        ),
        labelSmall: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: .6,
          color: GiuliaTokens.textMuted,
        ),
      )
      // Last, and family only: `apply` without colour arguments leaves the
      // colours set above untouched. Placed before the `copyWith`, every
      // style rebuilt there would lose the family again — which is precisely
      // the defect this call repairs.
      .apply(fontFamily: GiuliaTokens.fontFamily);
  // Die Dichte des Produkts wirkt auf die Schrift: Coach setzt kleiner, weil
  // eine Trainerin acht Menschen nebeneinander liest; LaLa setzt Ziffern
  // gleich breit, damit eine Messwertspalte eine Spalte bleibt.
  final density = mode.density;
  final scaled = density.textScale == 1
      ? text
      : _scaleText(text, density.textScale);
  final typed = density.tabularFigures ? _tabular(scaled) : scaled;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colors,
    scaffoldBackgroundColor: GiuliaTokens.surface0,
    textTheme: typed,
    dividerTheme: const DividerThemeData(
      color: GiuliaTokens.border,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: GiuliaTokens.surface1,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusCard),
        side: const BorderSide(color: GiuliaTokens.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: GiuliaTokens.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GiuliaTokens.textPrimary,
        side: const BorderSide(color: GiuliaTokens.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: GiuliaTokens.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GiuliaTokens.radiusButton),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GiuliaTokens.surface1,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? GiuliaTokens.accent
              : GiuliaTokens.textMuted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: GiuliaTokens.surface1,
      indicatorColor: GiuliaTokens.accentSoft,
      useIndicator: true,
      groupAlignment: -1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: GiuliaTokens.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusL),
        side: const BorderSide(color: GiuliaTokens.border),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: GiuliaTokens.surface1,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: GiuliaTokens.surface1,
      showDragHandle: true,
      dragHandleColor: GiuliaTokens.textMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GiuliaTokens.radiusL),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: GiuliaTokens.surface2,
      selectedColor: GiuliaTokens.surface3,
      disabledColor: GiuliaTokens.surface2.withValues(alpha: .55),
      side: const BorderSide(color: GiuliaTokens.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      labelStyle: typed.labelLarge?.copyWith(color: GiuliaTokens.textSecondary),
      secondaryLabelStyle: typed.labelLarge?.copyWith(
        color: GiuliaTokens.accent,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GiuliaTokens.textPrimary,
      contentTextStyle: typed.bodyMedium?.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: GiuliaTokens.textPrimary,
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
      ),
      textStyle: typed.bodySmall?.copyWith(color: Colors.white),
      waitDuration: const Duration(milliseconds: 450),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: GiuliaTokens.accent,
      linearTrackColor: GiuliaTokens.surface3,
      circularTrackColor: GiuliaTokens.surface3,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GiuliaTokens.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        borderSide: const BorderSide(color: GiuliaTokens.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        borderSide: const BorderSide(color: GiuliaTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        borderSide: const BorderSide(color: GiuliaTokens.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        borderSide: const BorderSide(color: GiuliaTokens.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GiuliaTokens.radiusS),
        borderSide: const BorderSide(color: GiuliaTokens.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

/// Compatibility entry point retained while existing integrations migrate.
/// The application itself is deliberately light; this no longer creates a
/// dark theme.
/// Verkleinert eine Schrifttafel gleichmässig.
TextTheme _scaleText(TextTheme text, double factor) {
  TextStyle? scale(TextStyle? style) => style?.fontSize == null
      ? style
      : style!.copyWith(fontSize: style.fontSize! * factor);
  return text.copyWith(
    displayLarge: scale(text.displayLarge),
    displayMedium: scale(text.displayMedium),
    displaySmall: scale(text.displaySmall),
    headlineLarge: scale(text.headlineLarge),
    headlineMedium: scale(text.headlineMedium),
    headlineSmall: scale(text.headlineSmall),
    titleLarge: scale(text.titleLarge),
    titleMedium: scale(text.titleMedium),
    titleSmall: scale(text.titleSmall),
    bodyLarge: scale(text.bodyLarge),
    bodyMedium: scale(text.bodyMedium),
    bodySmall: scale(text.bodySmall),
    labelLarge: scale(text.labelLarge),
    labelMedium: scale(text.labelMedium),
    labelSmall: scale(text.labelSmall),
  );
}

/// Gleich breite Ziffern für Zahlen, die untereinander stehen.
TextTheme _tabular(TextTheme text) {
  const feature = [FontFeature.tabularFigures()];
  TextStyle? fixed(TextStyle? style) => style?.copyWith(fontFeatures: feature);
  return text.copyWith(
    titleLarge: fixed(text.titleLarge),
    titleMedium: fixed(text.titleMedium),
    titleSmall: fixed(text.titleSmall),
    bodyLarge: fixed(text.bodyLarge),
    bodyMedium: fixed(text.bodyMedium),
    bodySmall: fixed(text.bodySmall),
    labelLarge: fixed(text.labelLarge),
    labelMedium: fixed(text.labelMedium),
  );
}

ThemeData giuliaDarkTheme({ProductMode mode = ProductMode.ercolina}) =>
    giuliaLightTheme(mode: mode);

/// The colour of a training zone, by its place in the model.
///
/// Not a fixed list of six. Zone models differ — three zones, five, seven —
/// and a fixed list either runs out or hands the same colour to two zones that
/// mean different things. Here the colour is a *position on an intensity
/// ramp*, so the third of five and the fourth of seven both land where they
/// belong: the reader learns the ramp once and reads every model with it.
///
/// The ramp runs calm-blue → green → yellow → orange → red: the order a coach
/// already carries in their head.
///
/// It deliberately does **not** try to be monotonic in lightness. A green to
/// red ramp cannot be — yellow sits between them and is lighter than both —
/// and forcing it would produce a muddy green and a washed-out red. What the
/// ramp does guarantee is that neighbouring zones stay far enough apart to be
/// told apart; the zone's name and its ordinal carry the meaning when colour
/// is unavailable, which is why both are always printed next to the band.
Color giuliaZoneColour(int ordinal, int zoneCount) {
  const ramp = <Color>[
    Color(0xFF3C7CB4), // Regeneration — deliberately not green: it is rest.
    Color(0xFF2E8B57), // extensive aerobic
    Color(0xFF6FA82B), // aerobic
    Color(0xFFD1A017), // intensive aerobic
    Color(0xFFE0722A), // development
    Color(0xFFC1272D), // peak
  ];
  if (zoneCount <= 1) return ramp[1];
  final position = (ordinal.clamp(0, zoneCount - 1)) / (zoneCount - 1);
  final scaled = position * (ramp.length - 1);
  final lower = scaled.floor();
  final upper = (lower + 1).clamp(0, ramp.length - 1);
  return Color.lerp(ramp[lower], ramp[upper], scaled - lower)!;
}

/// The same colour, as a background a dark text still reads on.
///
/// The alpha is the whole design of this function. Too low and the band is a
/// smudge that adds nothing; too high and the zone name needs white text,
/// which then fails on the pale zones. At this value the ramp is unmistakable
/// across a room and every band still carries [GiuliaTokens.textPrimary] at a
/// contrast ratio above 7:1.
Color giuliaZoneTint(int ordinal, int zoneCount) => Color.alphaBlend(
  giuliaZoneColour(ordinal, zoneCount).withValues(alpha: .26),
  GiuliaTokens.surface1,
);

class GiuliaPanel extends StatelessWidget {
  const GiuliaPanel({
    super.key,
    required this.child,
    this.padding,
    this.tone = GiuliaTokens.surface1,
    this.onTap,
  });
  final Widget child;

  /// Innenabstand. Null folgt der Dichte des Produkts — und das ist der
  /// Normalfall: Eine Karte, die überall gleich viel Luft hat, ist der Grund,
  /// warum drei Produkte wie eines aussehen.
  final EdgeInsets? padding;
  final Color tone;

  /// Macht die Karte anfassbar. Gesetzt heisst: Die ganze Fläche ist das
  /// Ziel, nicht ein Pfeil in der Ecke — auf einem Gerät, das man mit
  /// feuchten Händen bedient, ist das der Unterschied zwischen «geht» und
  /// «geht meistens».
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final density = GiuliaDensity.of(context);
    final radius = BorderRadius.circular(density.cardRadius);
    final decorated = Container(
      padding: padding ?? EdgeInsets.all(density.cardPadding),
      // Told apart by surface and hairline only: shadows make every card
      // shout equally loud.
      decoration: BoxDecoration(
        color: onTap == null ? tone : null,
        borderRadius: radius,
        border: Border.all(color: GiuliaTokens.border),
      ),
      child: child,
    );
    if (onTap == null) return decorated;
    return Material(
      color: tone,
      borderRadius: radius,
      child: InkWell(borderRadius: radius, onTap: onTap, child: decorated),
    );
  }
}

class GiuliaEmptyState extends StatelessWidget {
  const GiuliaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: GiuliaTokens.textMuted),
            const SizedBox(height: GiuliaTokens.spacingM),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: GiuliaTokens.spacingS),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: GiuliaTokens.spacingL),
              action!,
            ],
          ],
        ),
      ),
    ),
  );
}

/// Ein konsistenter Zustand für laufende Arbeit.
///
/// Kleine, lokale Aktionen dürfen weiterhin einen kompakten
/// [CircularProgressIndicator] verwenden. Dieser Baustein ist für eine ganze
/// Inhaltsfläche gedacht und hält deren visuelle Hierarchie stabil, bis echte
/// Daten vorliegen.
class GiuliaLoadingState extends StatelessWidget {
  const GiuliaLoadingState({
    super.key,
    this.title = 'Daten werden geladen',
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) => GiuliaPanel(
    child: Semantics(
      liveRegion: true,
      label: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GiuliaTokens.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: GiuliaTokens.iconM,
                  height: GiuliaTokens.iconM,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: GiuliaTokens.spacingM),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: GiuliaTokens.spacingS),
              Padding(
                padding: const EdgeInsets.only(
                  left: GiuliaTokens.iconM + GiuliaTokens.spacingM,
                ),
                child: Text(
                  description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Fehlerzustand mit genau einer verständlichen nächsten Handlung.
class GiuliaErrorState extends StatelessWidget {
  const GiuliaErrorState({
    super.key,
    required this.title,
    required this.description,
    this.onRetry,
    this.retryLabel = 'Erneut versuchen',
  });

  final String title;
  final String description;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => GiuliaEmptyState(
    icon: Icons.error_outline,
    title: title,
    description: description,
    action: onRetry == null
        ? null
        : FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(retryLabel),
          ),
  );
}

/// Platzhalter, der die spätere Geometrie erhält, ohne Daten vorzutäuschen.
///
/// Er trägt absichtlich weder Text noch Diagrammlinien: Ein Skeleton zeigt
/// nur, *wo* Inhalt erscheinen wird, nie *welcher* Inhalt angeblich bereits
/// bekannt ist.
class GiuliaSkeleton extends StatelessWidget {
  const GiuliaSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = GiuliaTokens.radiusS,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: GiuliaTokens.surface3.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// Consistent visual frame for charts. It deliberately has no data model: the
/// analysis layer supplies measured, decimated points when available.
class GiuliaChartFrame extends StatelessWidget {
  const GiuliaChartFrame({
    super.key,
    required this.title,
    required this.series,
    required this.emptyMessage,
    this.height = 220,
  });

  final String title;
  final String series;
  final String emptyMessage;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    decoration: BoxDecoration(
      color: GiuliaTokens.surface1,
      border: Border.all(color: GiuliaTokens.border),
      borderRadius: BorderRadius.circular(GiuliaTokens.radiusM),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            Container(width: 18, height: 2, color: GiuliaTokens.chartLine),
            const SizedBox(width: 6),
            Text(series, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: CustomPaint(
            painter: const _ChartGridPainter(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class GiuliaStatusLabel extends StatelessWidget {
  const GiuliaStatusLabel({
    super.key,
    required this.label,
    required this.value,
    this.status = GiuliaTokens.textMuted,
  });

  final String label;
  final String value;
  final Color status;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: status, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      // Both texts must be able to give way: this label is used in narrow
      // side panels where a long value would otherwise overflow the row.
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
      const SizedBox(width: 16),
      // The value takes the rest of the row and may use two lines.
      //
      // It used to share the row with a `Spacer`, which claimed a third of the
      // width for nothing and cut «Radergometrie ab 120 W · 20 W / 3 min» down
      // to «Raderg…». A truncated value is worse than a wrapped one: the
      // reader cannot tell whether the rest would have changed the meaning.
      Expanded(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

class _ChartGridPainter extends CustomPainter {
  const _ChartGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GiuliaTokens.chartGrid
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    for (var index = 1; index < 6; index++) {
      final x = size.width * index / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartGridPainter oldDelegate) => false;
}

/// Small rounded label. Was private to the shell; promoted because the athlete
/// page and the two test screens all need the same one, and three private
/// copies would drift apart.
class GiuliaChip extends StatelessWidget {
  const GiuliaChip(this.label, {super.key, this.tone});

  final String label;

  /// Accent colour of the text. Null keeps the neutral, secondary tone.
  final Color? tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: tone == null
          ? GiuliaTokens.surface2
          : tone!.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
      border: tone == null
          ? null
          : Border.all(color: tone!.withValues(alpha: .32)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: tone ?? GiuliaTokens.textSecondary,
      ),
    ),
  );
}

/// Says where a test's numbers came from.
///
/// This badge exists because "measured" and "entered by hand" are different
/// statements about the same number, and the application shows both kinds side
/// by side. Never inferred from the presence of a device: a test entered by
/// hand on a day the Ercolina happened to be connected is still a manual test.
class GiuliaSourceBadge extends StatelessWidget {
  const GiuliaSourceBadge({super.key, required this.measured});

  final bool measured;

  @override
  Widget build(BuildContext context) => GiuliaChip(
    measured ? 'GEMESSEN' : 'EINGETRAGEN',
    tone: measured ? GiuliaTokens.accent : GiuliaTokens.textMuted,
  );
}

/// Heading of a block, with an optional real action on the right.
///
/// The shell used to draw the action as coloured text that did nothing. Here
/// the action is a widget, so a caller either supplies something tappable or
/// nothing at all.
class GiuliaSectionHeader extends StatelessWidget {
  const GiuliaSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title.toUpperCase(), style: text.labelMedium),
              if (subtitle != null) ...[
                const SizedBox(height: GiuliaTokens.spacingXs),
                Text(subtitle!, style: text.bodySmall),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}
