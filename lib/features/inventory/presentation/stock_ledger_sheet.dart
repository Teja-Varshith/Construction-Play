import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/work_day.dart';
import '../domain/inventory.dart';

/// One material's story on the project: how much is left, how fast it is
/// used, what it cost, and every receipt and issue with the running balance.
Future<void> showStockLedger(
  BuildContext context, {
  required StockLine line,
  required bool seeMoney,
  required String Function(String? phaseId) phaseName,
  VoidCallback? onReorder,
  VoidCallback? onIssue,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 760),
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    minChildSize: 0.4,
    builder: (context, scroll) => _Ledger(
      line: line,
      seeMoney: seeMoney,
      phaseName: phaseName,
      onReorder: onReorder,
      onIssue: onIssue,
      scroll: scroll,
    ),
  ),
);

class _Ledger extends StatelessWidget {
  const _Ledger({
    required this.line,
    required this.seeMoney,
    required this.phaseName,
    required this.onReorder,
    required this.onIssue,
    required this.scroll,
  });

  final StockLine line;
  final bool seeMoney;
  final String Function(String? phaseId) phaseName;
  final VoidCallback? onReorder;
  final VoidCallback? onIssue;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final colors = context.statusColors;
    // Moves are newest first; the balance after each is built oldest first.
    final balances = List<double>.filled(l.moves.length, 0);
    var running = 0.0;
    for (var i = l.moves.length - 1; i >= 0; i--) {
      running += l.moves[i].inward ? l.moves[i].qty : -l.moves[i].qty;
      balances[i] = running;
    }
    final days = l.daysLeft;
    Widget fact(String label, String value, {Color? color}) => SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      ),
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l.material, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (l.low)
              _StatusPill(l.out ? 'Out of stock' : 'Running low', colors.bad)
            else if (l.received > 0)
              _StatusPill('In stock', colors.ok),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [
            fact('In stock', '${formatQty(l.inStock)} ${l.unit}', color: l.low ? colors.bad : null),
            fact('Lasts', days == null ? 'Not used lately' : '~${days.floor()} days', color: l.low ? colors.bad : null),
            fact('Used / day (${StockLine.usageWindowDays}d avg)', l.dailyUse <= 0 ? '—' : '${formatQty(l.dailyUse)} ${l.unit}'),
            fact('Received', '${formatQty(l.received)} ${l.unit}'),
            fact('Issued', '${formatQty(l.issued)} ${l.unit}'),
            fact('On order', l.onOrder <= 0 ? '—' : '${formatQty(l.onOrder)} ${l.unit}'),
            if (l.requested > 0) fact('Awaiting approval', '${formatQty(l.requested)} ${l.unit}'),
            if (seeMoney && l.avgRatePaise != null) fact('Average rate', '${Money.format(l.avgRatePaise!)} / ${l.unit}'),
            if (seeMoney && l.lastRatePaise != null) fact('Last rate', '${Money.format(l.lastRatePaise!)} / ${l.unit}'),
            if (seeMoney && l.valuePaise > 0) fact('Stock value', Money.compact(l.valuePaise)),
          ],
        ),
        if (onReorder != null || onIssue != null) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onReorder != null)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onReorder!();
                  },
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: Text(l.suggestedReorder > 0 ? 'Reorder ${formatQty(l.suggestedReorder)} ${l.unit}' : 'Reorder'),
                ),
              if (onIssue != null && l.inStock > 0)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onIssue!();
                  },
                  icon: const Icon(Icons.outbox_outlined, size: 18),
                  label: const Text('Issue to site'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text('Movements', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (l.moves.isEmpty)
          const Text('Nothing received or issued yet.', style: TextStyle(color: AppColors.muted))
        else
          for (var i = 0; i < l.moves.length; i++)
            _MoveRow(move: l.moves[i], balance: balances[i], unit: l.unit, seeMoney: seeMoney, phaseName: phaseName),
      ],
    );
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.move,
    required this.balance,
    required this.unit,
    required this.seeMoney,
    required this.phaseName,
  });

  final StockMove move;
  final double balance;
  final String unit;
  final bool seeMoney;
  final String Function(String? phaseId) phaseName;

  @override
  Widget build(BuildContext context) {
    final m = move;
    final colors = context.statusColors;
    final color = m.inward ? colors.ok : AppColors.muted;
    final phase = phaseName(m.phaseId);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(m.inward ? Icons.south_west : Icons.north_east, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.inward ? 'Received${m.party.isEmpty ? '' : ' from ${m.party}'}' : 'Issued${m.party.isEmpty ? '' : ' to ${m.party}'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    WorkDay.display(m.date),
                    m.number,
                    if (phase.isNotEmpty) phase,
                    if (seeMoney && m.ratePaise != null) '@ ${Money.format(m.ratePaise!)}',
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${m.inward ? '+' : '−'}${formatQty(m.qty)} $unit',
                style: TextStyle(fontWeight: FontWeight.w800, color: m.inward ? colors.ok : null),
              ),
              Text('Balance ${formatQty(balance)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(99)),
    child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
  );
}
