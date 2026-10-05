import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// The app's one font, bundled in `assets/fonts` (SIL Open Font License).
const kFontFamily = 'PlusJakartaSans';

/// Brand palette: a friendly royal blue on soft blue-grey, a deep navy for
/// navigation, and warm amber used sparingly for things that need attention.
/// Every colour in the app should come from here or from [StatusColors].
class AppColors {
  AppColors._();

  /// Brand blue: primary buttons, links, selection.
  static const blue = Color(0xFF3557D6);
  static const blueSoft = Color(0xFFEEF2FF);

  /// Navigation sidebar.
  static const navy = Color(0xFF111A35);
  static const navyRaised = Color(0xFF1C2747);
  static const navyText = Color(0xFFB7C0DA);

  /// Headings and main text.
  static const ink = Color(0xFF101828);

  /// Body text that is secondary but still read (descriptions, notes).
  static const inkSoft = Color(0xFF344054);

  /// Labels, captions, helper text.
  static const muted = Color(0xFF667085);

  /// Placeholder-level text and inactive icons.
  static const subtle = Color(0xFF98A2B3);

  /// Page background behind white cards.
  static const concrete = Color(0xFFF4F6FB);

  /// Quiet fills inside cards (table headers, quotes, inactive chips).
  static const surfaceAlt = Color(0xFFF7F8FC);

  /// Card borders and dividers.
  static const line = Color(0xFFE6E9F1);

  /// Empty part of bars and meters.
  static const track = Color(0xFFE9EDF5);
  static const amber = Color(0xFFE0A100);
}

/// Shared corner radii so every surface feels like one system.
class AppRadius {
  AppRadius._();

  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;

  static BorderRadius get card => BorderRadius.circular(md);
}

/// A soft, low shadow for raised surfaces (cards on hover, sheets).
const appSoftShadow = [
  BoxShadow(color: Color(0x0F101828), blurRadius: 24, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x08101828), blurRadius: 4, offset: Offset(0, 1)),
];

/// The resting shadow of a card: barely there, just lifts it off the page.
const appCardShadow = [BoxShadow(color: Color(0x0A101828), blurRadius: 3, offset: Offset(0, 1))];

/// Green / amber / red used for project health and statuses. Kept separate
/// from the brand accent.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.ok,
    required this.okSoft,
    required this.warn,
    required this.warnSoft,
    required this.bad,
    required this.badSoft,
  });

  final Color ok, okSoft, warn, warnSoft, bad, badSoft;

  static const light = StatusColors(
    ok: Color(0xFF12855A),
    okSoft: Color(0xFFE7F7EF),
    warn: Color(0xFFB66A00),
    warnSoft: Color(0xFFFFF4DF),
    bad: Color(0xFFD23B2E),
    badSoft: Color(0xFFFDECEA),
  );

  static const dark = StatusColors(
    ok: Color(0xFF6CC592),
    okSoft: Color(0xFF173026),
    warn: Color(0xFFE3AE55),
    warnSoft: Color(0xFF342812),
    bad: Color(0xFFEE857C),
    badSoft: Color(0xFF3A1C1A),
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension StatusColorsX on BuildContext {
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          primary: AppColors.blue,
          surface: Colors.white,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.muted,
          outline: AppColors.line,
          outlineVariant: AppColors.line,
          secondaryContainer: AppColors.blueSoft,
          onSecondaryContainer: AppColors.blue,
        ),
        scaffold: AppColors.concrete,
        status: StatusColors.light,
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.dark,
          primary: const Color(0xFF8DA4FF),
          surface: const Color(0xFF1A2033),
        ),
        scaffold: const Color(0xFF111522),
        status: StatusColors.dark,
      );

  static ThemeData _build(ColorScheme scheme, {required Color scaffold, required StatusColors status}) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: kFontFamily,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
    final dark = scheme.brightness == Brightness.dark;
    final outline = dark ? scheme.outlineVariant : AppColors.line;
    final muted = dark ? scheme.onSurfaceVariant : AppColors.muted;
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2));
    final t = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface, fontFamily: kFontFamily);
    final text = t.copyWith(
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6, fontSize: 28),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 23),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, fontSize: 19),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1, fontSize: 15.5),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 1.45),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12.5, color: muted),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: 0),
      labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: muted),
      labelSmall: t.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
    );
    final buttonText = text.labelLarge!;
    const transitions = FadeForwardsPageTransitionsBuilder();
    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      extensions: [status],
      textTheme: text,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: transitions,
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: transitions,
          TargetPlatform.windows: transitions,
          TargetPlatform.linux: transitions,
          TargetPlatform.fuchsia: transitions,
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: outline,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card, side: BorderSide(color: outline)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TextStyle(color: dark ? muted : AppColors.subtle, fontWeight: FontWeight.w500),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: rounded,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: const Size(64, 44), shape: rounded, textStyle: buttonText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: rounded,
          backgroundColor: scheme.surface,
          foregroundColor: dark ? scheme.onSurface : AppColors.inkSoft,
          side: BorderSide(color: dark ? scheme.outline : const Color(0xFFD5DAE5)),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: rounded, textStyle: buttonText.copyWith(fontWeight: FontWeight.w700)),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: rounded)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: buttonText.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
          selectedBackgroundColor: dark ? scheme.primaryContainer : AppColors.blueSoft,
          selectedForegroundColor: scheme.primary,
          side: BorderSide(color: outline),
          shape: rounded,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        side: BorderSide(color: outline),
        backgroundColor: scheme.surface,
        selectedColor: dark ? scheme.primaryContainer : AppColors.blueSoft,
        labelStyle: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w600, fontSize: 13, color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700, fontSize: 13, color: scheme.primary),
        checkmarkColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: status.bad,
        textStyle: const TextStyle(fontFamily: kFontFamily, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        titleTextStyle: text.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: dark ? scheme.outline : const Color(0xFFD0D5DD),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: const Color(0x33101828),
        textStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: outline),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: muted,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outline,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        labelStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: dark ? scheme.primaryContainer : AppColors.blueSoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : muted, size: 23),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: kFontFamily,
            fontSize: 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? scheme.primary : muted,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md + 2)),
        extendedTextStyle: buttonText,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: dark ? scheme.surfaceContainerHighest : AppColors.track,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(AppRadius.sm - 2)),
        textStyle: const TextStyle(fontFamily: kFontFamily, color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        waitDuration: const Duration(milliseconds: 350),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(fontFamily: kFontFamily, color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
      ),
    );
  }
}
