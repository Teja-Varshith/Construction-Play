/// Builds a stable, readable id from a label ("Tender / Quotation" becomes
/// "tender-quotation"), unique among [taken].
///
/// Ids never change after creation, so labels can be renamed freely without
/// breaking stored data.
String slugId(String label, Iterable<String> taken) {
  var base = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'item';
  if (base.length > 40) base = base.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  final used = taken.toSet();
  if (!used.contains(base)) return base;
  var n = 2;
  while (used.contains('$base-$n')) {
    n++;
  }
  return '$base-$n';
}
