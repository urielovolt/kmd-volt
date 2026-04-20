/// Maps iconCode string keys to SVG asset paths for group icons.
/// Use these keys in GroupModel.iconCode.
const Map<String, String> kGroupSvgIcons = {
  // Default group codes
  'lock':   'assets/icons/groups/icon_general.svg',
  'people': 'assets/icons/groups/icon_redes_social.svg',
  'email':  'assets/icons/groups/icon_correos.svg',
  'bank':   'assets/icons/groups/icon_bancos.svg',
  'work':   'assets/icons/groups/icon_trabajo.svg',

  // Named aliases (for future groups / icon picker)
  'general': 'assets/icons/groups/icon_general.svg',
  'social':  'assets/icons/groups/icon_redes_social.svg',
  'correos': 'assets/icons/groups/icon_correos.svg',
  'bancos':  'assets/icons/groups/icon_bancos.svg',
  'trabajo': 'assets/icons/groups/icon_trabajo.svg',
};

/// Fallback asset path when iconCode is unknown.
const String kGroupIconFallback = 'assets/icons/groups/icon_general.svg';

/// Returns the SVG asset path for [code], or a fallback if not found.
String groupSvgFromCode(String? code) {
  if (code == null) return kGroupIconFallback;
  return kGroupSvgIcons[code] ?? kGroupIconFallback;
}
