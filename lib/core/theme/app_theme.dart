import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Brand colours: blueprint blue on concrete grey, with hi-vis amber used
/// sparingly for things that need attention.
class AppColors {
  AppColors._();

  static const blue = Color(0xFF1E4F8A);
  static const ink = Color(0xFF16202A);
  static const concrete = Color(0xFFF4F6F9);
  static const amber = Color(0xFFD99A0E);
  static const line = Color(0xFFE3E8EE);
  static const muted = Color(0xFF5E6B78);
}

/// Shared corner radii so every surface feels like one system.
class AppRadius {
  AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;

  static BorderRadius get card => BorderRadius.circular(md);
}

/// A soft, low shadow for raised surfaces (hovered cards, the sidebar).
const appSoftShadow = [
  BoxShadow(color: Color(0x0F16202A), blurRadius: 18, offset: Offset(0, 6)),
  BoxShadow(color: Color(0x0816202A), blurRadius: 3, offset: Offset(0, 1)),
];

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
    ok: Color(0xFF2E7D4F),
    okSoft: Color(0xFFE3F2E8),
    warn: Color(0xFFB7791F),
    warnSoft: Color(0xFFFBF0DC),
    bad: Color(0xFFB83A32),
    badSoft: Color(0xFFF8E3E1),
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
        ),
        scaffold: Colors.white,
        status: StatusColors.light,
      );

  static ThemeData dark() => _build(
        ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.dark,
          primary: const Color(0xFF7FAEE3),
          surface: const Color(0xFF1A2128),
        ),
        scaffold: const Color(0xFF12171C),
        status: StatusColors.dark,
      );

  static ThemeData _build(ColorScheme scheme, {required Color scaffold, required StatusColors status}) {
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
    final dark = scheme.brightness == Brightness.dark;
    final outline = dark ? scheme.outlineVariant : AppColors.line;
    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2));
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    const transitions = FadeForwardsPageTransitionsBuilder();
    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      extensions: [status],
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
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
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          minimumSize: const Size(64, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: rounded,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: rounded,
          side: BorderSide(color: outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: rounded,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: rounded)),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        side: BorderSide(color: outline),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: outline),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: dark ? scheme.onSurfaceVariant : AppColors.muted,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outline,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.primary : AppColors.muted,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.primary : AppColors.muted,
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: dark ? scheme.surfaceContainerHighest : const Color(0xFFE6EBF0),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        waitDuration: const Duration(milliseconds: 350),
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm + 2)),
      ),
    );
  }
}
