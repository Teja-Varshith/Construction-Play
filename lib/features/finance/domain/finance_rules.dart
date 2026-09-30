import '../../../core/utils/work_day.dart';
import 'expense.dart';

/// What one expense adds to its project's stored totals. Used for both the
/// transactional deltas and the from-source recalculation, so the two agree.
class ExpenseTotals {
  const ExpenseTotals(this.spentPaise, this.pendingCount, this.pendingPaise);

  final int spentPaise;
  final int pendingCount;
  final int pendingPaise;

  static const zero = ExpenseTotals(0, 0, 0);

  factory ExpenseTotals.of(ExpenseStatus? status, int amountPaise) =>
      switch (status) {
        ExpenseStatus.approved => ExpenseTotals(amountPaise, 0, 0),
        ExpenseStatus.pending => ExpenseTotals(0, 1, amountPaise),
        _ => zero,
      };

  factory ExpenseTotals.sum(Iterable<Expense> expenses) => expenses.fold(
    zero,
    (sum, e) => sum + ExpenseTotals.of(e.status, e.amountPaise),
  );

  ExpenseTotals operator +(ExpenseTotals o) => ExpenseTotals(
    spentPaise + o.spentPaise,
    pendingCount + o.pendingCount,
    pendingPaise + o.pendingPaise,
  );

  ExpenseTotals operator -(ExpenseTotals o) => ExpenseTotals(
    spentPaise - o.spentPaise,
    pendingCount - o.pendingCount,
    pendingPaise - o.pendingPaise,
  );
}

/// A warning shown before submit, and the flag stored on the expense.
class ExpenseWarning {
  const ExpenseWarning(this.flag, this.message);

  final ExpenseFlag flag;
  final String message;
}

/// Duplicate and split-bill checks, run against the project's other expenses.
class ExpenseChecks {
  ExpenseChecks._();

  /// Expenses from the same payee and category within this many days are
  /// looked at together for split bills (48 hours either side).
  static const splitWindowDays = 2;

  static List<ExpenseWarning> check({
    required String? id,
    required int amountPaise,
    required String categoryId,
    required String payee,
    required String date,
    required String? billHash,
    required int thresholdPaise,
    required List<Expense> existing,
  }) {
    final others = existing
        .where((e) => e.id != id && e.status != ExpenseStatus.voided)
        .toList();
    final payeeKey = Expense.normalisePayee(payee);
    final day = WorkDay.tryParse(date);
    final warnings = <ExpenseWarning>[];

    if (billHash != null) {
      final same = others.where((e) => e.billHash == billHash).firstOrNull;
      if (same != null) {
        warnings.add(
          ExpenseWarning(
            ExpenseFlag.duplicateBill,
            'This bill photo was already used for ${same.payee} on ${WorkDay.display(same.date)}.',
          ),
        );
      }
    }

    final lookalike = others
        .where(
          (e) =>
              e.payeeKey == payeeKey &&
              e.amountPaise == amountPaise &&
              e.date == date,
        )
        .firstOrNull;
    if (lookalike != null) {
      warnings.add(
        const ExpenseWarning(
          ExpenseFlag.possibleDuplicate,
          'An expense with the same payee, amount and date already exists.',
        ),
      );
    }

    if (day != null && amountPaise <= thresholdPaise && payeeKey.isNotEmpty) {
      final nearby = others.where((e) {
        final other = WorkDay.tryParse(e.date);
        return other != null &&
            e.payeeKey == payeeKey &&
            e.categoryId == categoryId &&
            e.amountPaise <= thresholdPaise &&
            other.difference(day).inDays.abs() <= splitWindowDays;
      }).toList();
      final combined = nearby.fold(amountPaise, (s, e) => s + e.amountPaise);
      if (nearby.isNotEmpty && combined > thresholdPaise) {
        warnings.add(
          ExpenseWarning(
            ExpenseFlag.possibleSplit,
            'Together with ${nearby.length} other bill${nearby.length == 1 ? '' : 's'} from this payee within 48 hours, this is above the approval limit.',
          ),
        );
      }
    }
    return warnings;
  }
}

/// One row of the budget-against-actual view.
class CategorySpend {
  const CategorySpend({
    required this.categoryId,
    required this.plannedPaise,
    required this.spentPaise,
    required this.pendingPaise,
    this.originalPaise,
  });

  final String categoryId;
  final int plannedPaise;
  final int? originalPaise;
  final int spentPaise;
  final int pendingPaise;

  bool get unbudgeted => plannedPaise == 0 && spentPaise > 0;

  /// Null when there is no budget, so nothing is ever divided by zero.
  double? get usedPct =>
      plannedPaise <= 0 ? null : spentPaise / plannedPaise * 100;
}

class FinanceAlert {
  const FinanceAlert(this.message, {this.severe = false});

  final String message;
  final bool severe;
}

/// Everything the Money tab shows, derived from source records at read time.
class FinanceSummary {
  const FinanceSummary({
    required this.categories,
    required this.budgetPaise,
    required this.originalBudgetPaise,
    required this.spentPaise,
    required this.pendingCount,
    required this.pendingPaise,
    required this.last30DaysPaise,
    required this.forecastPaise,
    required this.alerts,
  });

  final List<CategorySpend> categories;
  final int budgetPaise;
  final int originalBudgetPaise;
  final int spentPaise;
  final int pendingCount;
  final int pendingPaise;
  final int last30DaysPaise;

  /// Null until the project is at least [minProgressForForecast] % complete.
  final int? forecastPaise;
  final List<FinanceAlert> alerts;

  static const minProgressForForecast = 10.0;

  double? get usedPct => budgetPaise <= 0 ? null : spentPaise / budgetPaise * 100;

  factory FinanceSummary.calculate({
    required List<Expense> expenses,
    required List<BudgetLine> budget,
    required double actualPct,
    required String today,
    String Function(String categoryId)? labelOf,
  }) {
    final label = labelOf ?? (id) => id;
    final plan = {for (final b in budget) b.categoryId: b};
    final ids = <String>{
      ...budget.where((b) => b.plannedPaise > 0).map((b) => b.categoryId),
      ...expenses
          .where((e) => e.isApproved || e.isPending)
          .map((e) => e.categoryId),
    };
    int sumWhere(bool Function(Expense e) test) =>
        expenses.where(test).fold(0, (s, e) => s + e.amountPaise);

    final categories = [
      for (final id in ids)
        CategorySpend(
          categoryId: id,
          plannedPaise: plan[id]?.plannedPaise ?? 0,
          originalPaise: plan[id]?.originalPaise,
          spentPaise: sumWhere((e) => e.isApproved && e.categoryId == id),
          pendingPaise: sumWhere((e) => e.isPending && e.categoryId == id),
        ),
    ]..sort((a, b) => b.spentPaise.compareTo(a.spentPaise));

    final totals = ExpenseTotals.sum(expenses);
    final budgetPaise = budget.fold(0, (s, b) => s + b.plannedPaise);
    final original = budget.fold(
      0,
      (s, b) => s + (b.originalPaise ?? b.plannedPaise),
    );
    final todayDate = WorkDay.tryParse(today);
    final last30 = todayDate == null
        ? 0
        : sumWhere((e) {
            final d = WorkDay.tryParse(e.date);
            return e.isApproved &&
                d != null &&
                !d.isAfter(todayDate) &&
                todayDate.difference(d).inDays < 30;
          });
    final forecast = actualPct >= minProgressForForecast
        ? (totals.spentPaise * 100 / actualPct).round()
        : null;

    final alerts = <FinanceAlert>[];
    for (final c in categories) {
      final used = c.usedPct;
      if (c.unbudgeted) {
        alerts.add(
          FinanceAlert('${label(c.categoryId)}: spend with no budget set', severe: true),
        );
      } else if (used != null && used >= 100) {
        alerts.add(
          FinanceAlert('${label(c.categoryId)} is over budget (${used.toStringAsFixed(0)}%)', severe: true),
        );
      } else if (used != null && used >= 80) {
        alerts.add(
          FinanceAlert('${label(c.categoryId)} has used ${used.toStringAsFixed(0)}% of its budget'),
        );
      }
    }
    final used = budgetPaise <= 0 ? null : totals.spentPaise / budgetPaise * 100;
    if (used != null && used - actualPct > 15) {
      alerts.add(
        FinanceAlert(
          'Spending is ahead of progress: ${used.toStringAsFixed(0)}% of budget used for ${actualPct.toStringAsFixed(0)}% of the work.',
          severe: true,
        ),
      );
    }
    if (forecast != null && budgetPaise > 0 && forecast > budgetPaise) {
      alerts.add(
        FinanceAlert('At the current rate the project will finish over budget.'),
      );
    }

    return FinanceSummary(
      categories: categories,
      budgetPaise: budgetPaise,
      originalBudgetPaise: original,
      spentPaise: totals.spentPaise,
      pendingCount: totals.pendingCount,
      pendingPaise: totals.pendingPaise,
      last30DaysPaise: last30,
      forecastPaise: forecast,
      alerts: alerts,
    );
  }
}
