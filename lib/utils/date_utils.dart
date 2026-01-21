class DateUtilsX {
  /// 返回 a 到 b 的“整天差”（以日期为准，忽略小时分钟）
  /// - 如果 expiryDate 是今天：返回 0
  /// - 明天：返回 1
  /// - 昨天：返回 -1
  static int daysUntil(DateTime expiryDate, DateTime now) {
    final d1 = DateTime(now.year, now.month, now.day);
    final d2 = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return d2.difference(d1).inDays;
  }

  static String yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
