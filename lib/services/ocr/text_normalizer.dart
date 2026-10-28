/// Text normalization and abbreviation expansion utilities for retail OCR and catalog matching.
class TextNormalizer {
  /// Known abbreviation mapping to full canonical names in the ice cream / retail domain.
  static const Map<String, String> commonAbbreviations = {
    'corn': 'cornetto',
    'cornet': 'cornetto',
    'mag': 'magnum',
    'magn': 'magnum',
    'wh': 'white',
    'wht': 'white',
    'choc': 'chocolate',
    'choco': 'chocolate',
    'str': 'strawberry',
    'stwb': 'strawberry',
    'straw': 'strawberry',
    'van': 'vanilla',
    'ck': 'cookies',
    'cook': 'cookies',
    'crm': 'cream',
    'dbl': 'double',
    'alm': 'almond',
    'car': 'caramel',
    'man': 'mango',
    'ube': 'ube',
    'tub': 'tub',
    'pnt': 'pint',
    'cup': 'cup',
    'cups': 'cup',
    'cs': 'case',
    'bx': 'box',
    'pc': 'piece',
    'pcs': 'pieces',
    'clas': 'classic',
    'class': 'classic',
    'slct': 'selecta',
    'slcta': 'selecta',
  };

  /// Normalizes a raw string: lowercased, punctuation stripped, whitespace trimmed.
  static String normalize(String input) {
    if (input.isEmpty) return '';
    var text = input.toLowerCase();

    // Remove ellipses and trailing periods common in truncated OCR lines
    text = text.replaceAll(RegExp(r'\.{2,}'), ' ');
    // Strip punctuation except spaces and alphanumeric characters
    text = text.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    // Collapse multiple whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  /// Normalizes text and expands known abbreviations into full words.
  static String normalizeAndExpand(String input) {
    final cleaned = normalize(input);
    if (cleaned.isEmpty) return '';

    final tokens = cleaned.split(' ');
    final expandedTokens = tokens.map((t) {
      return commonAbbreviations[t] ?? t;
    }).toList();

    return expandedTokens.join(' ');
  }

  /// Calculates token set similarity (Jaccard similarity of words) between two strings.
  static double tokenSetSimilarity(String s1, String s2) {
    final set1 = normalizeAndExpand(s1).split(' ').where((w) => w.isNotEmpty).toSet();
    final set2 = normalizeAndExpand(s2).split(' ').where((w) => w.isNotEmpty).toSet();

    if (set1.isEmpty && set2.isEmpty) return 1.0;
    if (set1.isEmpty || set2.isEmpty) return 0.0;

    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;
    return intersection / union;
  }

  /// Jaro-Winkler string similarity (0.0 to 1.0).
  static double jaroWinkler(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final maxDist = (s1.length > s2.length ? s1.length : s2.length) ~/ 2 - 1;
    final s1Matches = List<bool>.filled(s1.length, false);
    final s2Matches = List<bool>.filled(s2.length, false);

    int matches = 0;
    for (int i = 0; i < s1.length; i++) {
      final start = (0 > i - maxDist) ? 0 : i - maxDist;
      final end = (i + maxDist + 1 < s2.length) ? i + maxDist + 1 : s2.length;

      for (int j = start; j < end; j++) {
        if (s2Matches[j]) continue;
        if (s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    int transpositions = 0;
    int k = 0;
    for (int i = 0; i < s1.length; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    final jaro = ((matches / s1.length) +
            (matches / s2.length) +
            ((matches - transpositions / 2.0) / matches)) /
        3.0;

    // Winkler prefix bonus
    int prefix = 0;
    final maxPrefix = 4;
    final minLen = s1.length < s2.length ? s1.length : s2.length;
    for (int i = 0; i < minLen && i < maxPrefix; i++) {
      if (s1[i] == s2[i]) {
        prefix++;
      } else {
        break;
      }
    }

    return jaro + (prefix * 0.1 * (1.0 - jaro));
  }

  /// Combined matching score combining token overlap and Jaro-Winkler character similarity.
  static double combinedSimilarity(String query, String target) {
    final normQuery = normalizeAndExpand(query);
    final normTarget = normalizeAndExpand(target);

    if (normQuery == normTarget) return 1.0;
    if (normTarget.contains(normQuery) || normQuery.contains(normTarget)) {
      final lenRatio = (normQuery.length < normTarget.length)
          ? normQuery.length / normTarget.length
          : normTarget.length / normQuery.length;
      if (lenRatio >= 0.5) {
        return 0.85 + (0.15 * lenRatio);
      }
    }

    final tokenScore = tokenSetSimilarity(query, target);
    final jwScore = jaroWinkler(normQuery, normTarget);

    // Weighted 60% token similarity + 40% Jaro-Winkler character similarity
    return (tokenScore * 0.6) + (jwScore * 0.4);
  }
}
