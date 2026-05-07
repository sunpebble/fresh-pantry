/// 将 raw 名字标准化为 cache key:trim、小写、空白折叠为单空格。
String normalizeCacheKey(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
