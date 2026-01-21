import '../models/inventory_item.dart';
import '../utils/date_utils.dart';

/// V0：规则引擎（通用零售默认策略）
/// - 先用可解释规则替代“真 AI”
/// - 后续 V2 可把这里替换为 AI 输出的 stages
class DiscountService {
  /// 最低价保护（V0 没有成本价，先用绝对底价）
  static const double absoluteMinPrice = 0.99;

  /// 价格尾数规则：默认让价格变成 xx.99（零售常见）
  /// 例：4.20 -> 3.99, 10.01 -> 9.99
  static double roundToNinetyNine(double price) {
    if (price <= absoluteMinPrice) return absoluteMinPrice;

    final floored = price.floorToDouble();
    final candidate = floored + 0.99;

    // 如果 price 本身正好在 floored+0.99 之下，candidate 会略大于 price（不想“涨价”）
    // 那就退一步到 (floored-1)+0.99
    if (candidate > price) {
      final down = (floored - 1) + 0.99;
      return down < absoluteMinPrice ? absoluteMinPrice : down;
    }
    return candidate;
  }

  /// 通用零售：按 category 返回默认折扣百分比（0~1）
  /// daysToExpire: 距到期还剩多少天
  static double discountPercentByCategory({
    required String category,
    required int daysToExpire,
  }) {
    final cat = category.trim();

    // 高损耗：Fresh
    if (cat == 'Fresh') {
      if (daysToExpire <= 2) return 0.50;
      if (daysToExpire <= 7) return 0.35;
      if (daysToExpire <= 14) return 0.20;
      if (daysToExpire <= 30) return 0.10;
      return 0.00;
    }

    // 中损耗：Packaged
    if (cat == 'Packaged') {
      if (daysToExpire <= 2) return 0.30;
      if (daysToExpire <= 7) return 0.20;
      if (daysToExpire <= 14) return 0.10;
      if (daysToExpire <= 30) return 0.05;
      return 0.00;
    }

    // 低损耗：NonFood
    if (cat == 'NonFood') {
      if (daysToExpire <= 2) return 0.20;
      if (daysToExpire <= 7) return 0.10;
      if (daysToExpire <= 14) return 0.05;
      if (daysToExpire <= 30) return 0.00;
      return 0.00;
    }

    // 未知分类：保守策略
    if (daysToExpire <= 2) return 0.20;
    if (daysToExpire <= 7) return 0.10;
    if (daysToExpire <= 14) return 0.05;
    return 0.00;
  }

  /// 计算“当前折扣后价格”
  /// - 使用 category + daysToExpire 来决定折扣
  /// - 进行 .99 尾数取整
  /// - 做最低价保护
  static double currentDiscountedPrice({
    required InventoryItem item,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();

    final daysToExpire = DateUtilsX.daysUntil(item.expiryDate, t);
    final p = discountPercentByCategory(
      category: item.category,
      daysToExpire: daysToExpire,
    );

    // 已过期：按最低价显示（也可改为原价并标红，这里 V0 简化）
    if (daysToExpire < 0) return absoluteMinPrice;

    final raw = item.originalPrice * (1.0 - p);
    final rounded = roundToNinetyNine(raw);

    if (rounded < absoluteMinPrice) return absoluteMinPrice;
    return rounded;
  }

  /// 当前折扣百分比（给 UI 用）
  static double currentDiscountPercent({
    required InventoryItem item,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final daysToExpire = DateUtilsX.daysUntil(item.expiryDate, t);

    if (daysToExpire < 0) return 0.0;

    return discountPercentByCategory(
      category: item.category,
      daysToExpire: daysToExpire,
    );
  }
}
