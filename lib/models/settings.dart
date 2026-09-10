import '../providers/provider.dart';

enum ScreenTarget { home, lock }

enum FitMode { centerCrop, asIs, blurPad }

class Settings {
  final ProviderId providerId;
  final Set<ScreenTarget> screens;
  final FitMode fitMode;
  final bool wifiOnly;

  const Settings({
    this.providerId = ProviderId.stalenhag,
    this.screens = const {ScreenTarget.home, ScreenTarget.lock},
    this.fitMode = FitMode.centerCrop,
    this.wifiOnly = true,
  });

  Settings copyWith({
    ProviderId? providerId,
    Set<ScreenTarget>? screens,
    FitMode? fitMode,
    bool? wifiOnly,
  }) =>
      Settings(
        providerId: providerId ?? this.providerId,
        screens: screens ?? this.screens,
        fitMode: fitMode ?? this.fitMode,
        wifiOnly: wifiOnly ?? this.wifiOnly,
      );

  Map<String, dynamic> toJson() => {
        'providerId': providerId.name,
        'screens': screens.map((s) => s.name).toList(),
        'fitMode': fitMode.name,
        'wifiOnly': wifiOnly,
      };

  factory Settings.fromJson(Map<String, dynamic> json) {
    ProviderId? pid;
    for (final p in ProviderId.values) {
      if (p.name == json['providerId']) pid = p;
    }
    final screens = <ScreenTarget>{
      for (final name in (json['screens'] as List? ?? const []).cast<String>())
        for (final s in ScreenTarget.values)
          if (s.name == name) s,
    };
    FitMode? fit;
    for (final f in FitMode.values) {
      if (f.name == json['fitMode']) fit = f;
    }
    return Settings(
      providerId: pid ?? ProviderId.stalenhag,
      screens:
          screens.isEmpty ? const {ScreenTarget.home, ScreenTarget.lock} : screens,
      fitMode: fit ?? FitMode.centerCrop,
      wifiOnly: json['wifiOnly'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.providerId == providerId &&
      other.screens.length == screens.length &&
      other.screens.containsAll(screens) &&
      other.fitMode == fitMode &&
      other.wifiOnly == wifiOnly;

  @override
  int get hashCode => Object.hash(providerId, screens.length, fitMode, wifiOnly);
}
