import 'package:flutter/material.dart';

import '../db/local_db.dart';
import '../models/inventory_item.dart';
import '../services/discount_service.dart';
import '../services/label_pdf_service.dart';
import '../utils/date_utils.dart';

class ItemDetailPage extends StatefulWidget {
  final String itemId;

  const ItemDetailPage({super.key, required this.itemId});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  InventoryItem? _item;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _item = LocalDb.getById(widget.itemId);
  }

  void _refresh() {
    setState(() {
      _item = LocalDb.getById(widget.itemId);
    });
  }

  Future<void> _delete() async {
    final it = _item;
    if (it == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${it.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok == true) {
      LocalDb.deleteById(it.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _generatePdf() async {
    final it = _item;
    if (it == null) return;

    setState(() => _working = true);
    try {
      final now = DateTime.now();
      final price = DiscountService.currentDiscountedPrice(item: it, now: now);
      final pct = DiscountService.currentDiscountPercent(item: it, now: now);

      final path = await LabelPdfService.generatePriceLabelPdf(
        item: it,
        now: now,
        currentPrice: price,
        discountPercent: pct,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = _item;
    if (it == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Item Detail')),
        body: const Center(child: Text('Item not found.')),
      );
    }

    final now = DateTime.now();
    final days = DateUtilsX.daysUntil(it.expiryDate, now);
    final currentPrice = DiscountService.currentDiscountedPrice(item: it, now: now);
    final pct = DiscountService.currentDiscountPercent(item: it, now: now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Detail'),
        actions: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              it.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Category: ${it.category}')),
                if (it.tag != null) Chip(label: Text('Tag: ${it.tag}')),
                Chip(
                  label: Text(
                    days < 0 ? 'Expired' : 'Days left: $days',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expiry Date: ${DateUtilsX.yyyyMmDd(it.expiryDate)}'),
                    const SizedBox(height: 6),
                    Text('Original Price: \$${it.originalPrice.toStringAsFixed(2)}'),
                    const SizedBox(height: 6),
                    Text(
                      'Current Price: \$${currentPrice.toStringAsFixed(2)}'
                      '${pct > 0 ? ' (${(pct * 100).round()}% off)' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),

            if (it.description != null && it.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Description', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(it.description!),
            ],

            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed: _working ? null : _generatePdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(_working ? 'Generating...' : 'Generate Price Label (PDF)'),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
