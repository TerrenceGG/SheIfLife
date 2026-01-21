import 'dart:io';

import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models/inventory_item.dart';
import '../services/discount_service.dart';
import '../utils/date_utils.dart';
import 'add_item_page.dart';
import 'item_detail_page.dart';

class ItemListPage extends StatefulWidget {
  const ItemListPage({super.key});

  @override
  State<ItemListPage> createState() => _ItemListPageState();
}

class _ItemListPageState extends State<ItemListPage> {
  bool _showOnlyExpiring = true; // 默认显示 <=30 天
  String? _selectedCategory; // null = All

  final TextEditingController _searchCtrl = TextEditingController();
  String _keyword = '';

  List<InventoryItem> _loadItems() {
    final now = DateTime.now();
    final items = LocalDb.getAllItems().toList();

    // Category 过滤（All 时不筛）
    final filteredByCategory = (_selectedCategory == null)
        ? items
        : items.where((it) => it.category == _selectedCategory).toList();

    // keyword 过滤（支持 name/tag/category/desc/barcode）
    final kw = _keyword.trim().toLowerCase();
    final filteredByKeyword = kw.isEmpty
        ? filteredByCategory
        : filteredByCategory.where((it) {
            final name = it.name.toLowerCase();
            final tag = (it.tag ?? '').toLowerCase();
            final cat = it.category.toLowerCase();
            final desc = (it.description ?? '').toLowerCase();
            final barcode = (it.barcode ?? '').toLowerCase();
            return name.contains(kw) ||
                tag.contains(kw) ||
                cat.contains(kw) ||
                desc.contains(kw) ||
                barcode.contains(kw);
          }).toList();

    // 排序：越临近到期越靠前
    filteredByKeyword.sort((a, b) {
      final da = DateUtilsX.daysUntil(a.expiryDate, now);
      final db = DateUtilsX.daysUntil(b.expiryDate, now);
      return da.compareTo(db);
    });

    if (_showOnlyExpiring) {
      return filteredByKeyword.where((it) {
        final d = DateUtilsX.daysUntil(it.expiryDate, now);
        return d <= 30; // 包含已过期（d<0）也会显示
      }).toList();
    }

    return filteredByKeyword;
  }

  List<String> _allCategories() {
    final all = LocalDb.getAllItems();
    final set = <String>{};
    for (final it in all) {
      final c = it.category.trim();
      if (c.isNotEmpty) set.add(c);
    }
    final categories = set.toList()..sort();
    return categories;
  }

  Future<void> _goAdd() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddItemPage()),
    );
    if (changed == true) {
      setState(() {}); // 只有真的保存了才刷新
    }
  }

  Future<void> _goDetail(InventoryItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ItemDetailPage(itemId: item.id)),
    );
    if (changed == true) {
      setState(() {}); // 删除/编辑后会 pop(true)，这里刷新
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _leadingThumbCircle(InventoryItem it) {
    final path = it.photoPath;
    if (path != null && path.trim().isNotEmpty) {
      final f = File(path);
      if (f.existsSync()) {
        return Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: FileImage(f),
              fit: BoxFit.cover,
            ),
          ),
        );
      }
    }

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: Theme.of(context).hintColor,
      ),
    );
  }

  Widget _statusChip({
    required BuildContext context,
    required int days,
  }) {
    final expired = days < 0;
    final expiring = !expired && days <= 30;

    final text = expired ? 'Expired' : (expiring ? 'Expiring' : 'Fresh');
    final icon = expired
        ? Icons.error_outline
        : (expiring ? Icons.schedule_outlined : Icons.check_circle_outline);

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

  Widget _itemCard({
    required BuildContext context,
    required InventoryItem it,
    required bool isNarrow,
  }) {
    final now = DateTime.now();
    final days = DateUtilsX.daysUntil(it.expiryDate, now);

    final discounted = DiscountService.currentDiscountedPrice(
      item: it,
      now: now,
    );
    final pct = DiscountService.currentDiscountPercent(
      item: it,
      now: now,
    );

    // 两行信息：Category / Days left
    final categoryLine = 'Category: ${it.category}';
    final daysLine = days < 0 ? 'Expired' : 'Days left: $days';

    // 价格：小号灰字
    final priceLine = 'Price: \$${it.originalPrice.toStringAsFixed(2)} → '
        '\$${discounted.toStringAsFixed(2)}'
        '${pct > 0 ? ' (${(pct * 100).round()}% off)' : ''}';

    // 轻微背景提示（可选，保持很克制，主要靠 chip 表达状态）
    final bool expired = days < 0;
    final bool soon = days >= 0 && days <= 30;

    // 三种状态都给不同底色：Expired / Expiring / Normal
    final cs = Theme.of(context).colorScheme;
    final Color tint = expired
        ? cs.errorContainer.withAlpha(77)        // 0.30 * 255 ≈ 77
        : (soon
            ? cs.primaryContainer.withAlpha(56)  // 0.22 * 255 ≈ 56
            : cs.surfaceContainerHighest.withAlpha(140)); // 0.55 * 255 ≈ 140

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: isNarrow ? 12 : 14,
        vertical: 8,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _goDetail(it),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: tint, 
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _leadingThumbCircle(it),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题 + 右箭头
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            it.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          color: Theme.of(context).hintColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    Text(
                      categoryLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                    const SizedBox(height: 4),

                    // 第二行：Days left + 右侧 chip
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            daysLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _statusChip(context: context, days: days),
                      ],
                    ),

                    const SizedBox(height: 6),
                    Text(
                      priceLine,
                      maxLines: isNarrow ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).hintColor,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _loadItems();
    final categories = _allCategories();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 760;
        final searchWidth = isNarrow ? 160.0 : 260.0;

        final Widget listArea = items.isEmpty
            ? const Center(child: Text('No items yet. Click + to add.'))
            : ListView.builder(
                itemCount: items.length,
                padding: const EdgeInsets.only(top: 8, bottom: 90),
                itemBuilder: (context, index) {
                  final it = items[index];
                  return _itemCard(context: context, it: it, isNarrow: isNarrow);
                },
              );

        return Scaffold(
          appBar: AppBar(
            title: const Text('SheIfLife v0.2'),
            actions: [
              // 搜索框
              SizedBox(
                width: searchWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _keyword.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _keyword = '');
                              },
                            ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _keyword = v),
                  ),
                ),
              ),

              // 到期过滤开关
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Text('Expiring ≤30d'),
                    Switch(
                      value: _showOnlyExpiring,
                      onChanged: (v) => setState(() => _showOnlyExpiring = v),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 手机窄屏：左侧导航做成 Drawer，默认隐藏
          drawer: isNarrow
              ? Drawer(
                  child: SafeArea(
                    child: _LeftNav(
                      categories: categories,
                      selectedCategory: _selectedCategory,
                      onSelectAll: () {
                        setState(() => _selectedCategory = null);
                        Navigator.of(context).pop();
                      },
                      onSelectCategory: (c) {
                        setState(() => _selectedCategory = c);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                )
              : null,

          floatingActionButton: FloatingActionButton(
            onPressed: _goAdd,
            child: const Icon(Icons.add),
          ),

          // 宽屏：左侧导航常驻；窄屏：只显示列表
          body: isNarrow
              ? listArea
              : Row(
                  children: [
                    SizedBox(
                      width: 220,
                      child: _LeftNav(
                        categories: categories,
                        selectedCategory: _selectedCategory,
                        onSelectAll: () => setState(() => _selectedCategory = null),
                        onSelectCategory: (c) => setState(() => _selectedCategory = c),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: listArea),
                  ],
                ),
        );
      },
    );
  }
}

class _LeftNav extends StatelessWidget {
  final List<String> categories;
  final String? selectedCategory;
  final VoidCallback onSelectAll;
  final ValueChanged<String> onSelectCategory;

  const _LeftNav({
    required this.categories,
    required this.selectedCategory,
    required this.onSelectAll,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          Text('产品', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _NavItem(
            title: 'All',
            selected: selectedCategory == null,
            icon: Icons.list_alt_outlined,
            onTap: onSelectAll,
          ),
          const SizedBox(height: 12),
          Text('Category', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          if (categories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No categories yet.'),
            )
          else
            ...categories.map(
              (c) => _NavItem(
                title: c,
                selected: selectedCategory == c,
                icon: Icons.category_outlined,
                onTap: () => onSelectCategory(c),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String title;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  const _NavItem({
    required this.title,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Theme.of(context).colorScheme.primary : null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? Theme.of(context).colorScheme.primary.withAlpha(26) // 0.10*255≈26
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
