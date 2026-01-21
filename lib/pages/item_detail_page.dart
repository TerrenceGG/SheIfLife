import 'dart:io';

import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models/inventory_item.dart';
import '../services/discount_service.dart';
import '../utils/date_utils.dart';

// 用于跳转到编辑页（复用 AddItemPage）
import 'add_item_page.dart';

class ItemDetailPage extends StatelessWidget {
  final String itemId;

  const ItemDetailPage({super.key, required this.itemId});

  Future<void> _confirmAndDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete item?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    await LocalDb.deleteById(itemId);

    if (context.mounted) {
      Navigator.of(context).pop(true); // 返回列表页，并提示“需要刷新”
    }
  }

  Future<void> _goEdit(BuildContext context, InventoryItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddItemPage(initialItem: item),
      ),
    );

    // 如果编辑页保存后 pop(true)，这里可以选择立即返回列表并刷新
    if (changed == true && context.mounted) {
      Navigator.of(context).pop(true); // 告诉上一级“数据变了”
    }
  }

  // -----------------------
  // UI helpers 
  // -----------------------
  Widget _sectionCard({
    required BuildContext context,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  Widget _kvRow(
    BuildContext context, {
    required String label,
    required String value,
    bool dimLabel = true,
  }) {
    final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: dimLabel ? Theme.of(context).hintColor : null,
        );
    final valueStyle = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: labelStyle),
          ),
          Expanded(
            child: Text(value, style: valueStyle),
          ),
        ],
      ),
    );
  }

  Widget _statusChip({
    required BuildContext context,
    required int days,
  }) {
    // 风格：右侧胶囊
    final bool expired = days < 0;
    final bool expiring = !expired && days <= 30;

    final String text = expired
        ? 'Expired'
        : (expiring ? 'Expiring' : 'Fresh');

    IconData icon = expired
        ? Icons.error_outline
        : (expiring ? Icons.schedule_outlined : Icons.check_circle_outline);

    // 颜色不写死（跟随主题），只做语义区分：
    // expired 用 error，expiring 用 primaryContainer，fresh 用 secondaryContainer
    Color? bg;
    Color? fg;
    if (expired) {
      bg = Theme.of(context).colorScheme.errorContainer;
      fg = Theme.of(context).colorScheme.onErrorContainer;
    } else if (expiring) {
      bg = Theme.of(context).colorScheme.primaryContainer;
      fg = Theme.of(context).colorScheme.onPrimaryContainer;
    } else {
      bg = Theme.of(context).colorScheme.secondaryContainer;
      fg = Theme.of(context).colorScheme.onSecondaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final InventoryItem? item = LocalDb.getById(itemId);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Item Detail')),
        body: const Center(child: Text('Item not found.')),
      );
    }

    final now = DateTime.now();
    final days = DateUtilsX.daysUntil(item.expiryDate, now);
    final price = DiscountService.currentDiscountedPrice(item: item, now: now);
    final pct = DiscountService.currentDiscountPercent(item: item, now: now);

    final hasPhoto = (item.photoPath != null) &&
        item.photoPath!.trim().isNotEmpty &&
        File(item.photoPath!).existsSync();

    final tag = (item.tag ?? '').trim();
    final desc = (item.description ?? '').trim();
    final barcode = (item.barcode ?? '').trim();

    final String expiryText = DateUtilsX.yyyyMmDd(item.expiryDate);
    final String daysText = days < 0 ? 'Expired ${days.abs()} day(s) ago' : '$days day(s) left';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Detail'),
        actions: [
          // 编辑按钮
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _goEdit(context, item),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _confirmAndDelete(context),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),

      // 底部固定操作区
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                offset: const Offset(0, -2),
                color: Colors.black.withValues(alpha: 0.06),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _goEdit(context, item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmAndDelete(context),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ),
      ),

      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96), // 给底部操作栏留空间
        children: [
          // -----------------------
          // 顶部“卡片头”：头像 + 名称/分类 + 右侧状态胶囊
          // -----------------------
          _sectionCard(
            context: context,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧圆形图（类似列表页风格）
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    image: hasPhoto
                        ? DecorationImage(
                            image: FileImage(File(item.photoPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: !hasPhoto
                      ? Icon(
                          Icons.inventory_2_outlined,
                          color: Theme.of(context).hintColor,
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // 中间文字
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Category: ${item.category}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).hintColor,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        daysText,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),

                // 右侧状态胶囊
                _statusChip(context: context, days: days),
              ],
            ),
          ),

          // -----------------------
          // 价格卡片：Original / Current（Current 绿色强调）
          // -----------------------
          _sectionCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Price',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                _kvRow(
                  context,
                  label: 'Original',
                  value: '\$${item.originalPrice.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        'Current',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).hintColor,
                            ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '\$${price.toStringAsFixed(2)}'
                        '${pct > 0 ? ' (${(pct * 100).round()}% off)' : ''}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // -----------------------
          // 详情卡片：Expiry / Barcode / Tag
          // -----------------------
          _sectionCard(
            context: context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                _kvRow(context, label: 'Expiry', value: expiryText),
                if (barcode.isNotEmpty) _kvRow(context, label: 'Barcode', value: barcode),
                if (tag.isNotEmpty) _kvRow(context, label: 'Tag', value: tag),
              ],
            ),
          ),

          // -----------------------
          // 描述卡片（有才显示）
          // -----------------------
          if (desc.isNotEmpty)
            _sectionCard(
              context: context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(desc),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
