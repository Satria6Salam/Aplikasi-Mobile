/// Urutan hasil pencarian.
enum SearchSort { newest, oldest, highest, lowest }

/// Kriteria pencarian transaksi lintas periode.
///
/// [query] dipecah per kata; SETIAP kata harus cocok di salah satu dari
/// nama toko, cabang, alamat, catatan, atau nama barang. Jadi
/// "telur indomaret" menemukan struk Indomaret yang memuat telur.
class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.from,
    this.to,
    this.minTotal,
    this.maxTotal,
    this.categoryIds = const <int>{},
    this.sort = SearchSort.newest,
  });

  final String query;

  /// Batas tanggal (inklusif). Hanya tanggalnya yang dipakai.
  final DateTime? from;
  final DateTime? to;

  /// Batas total struk (inklusif).
  final double? minTotal;
  final double? maxTotal;

  /// Kategori utama transaksi, atau kategori salah satu barangnya.
  final Set<int> categoryIds;
  final SearchSort sort;

  /// Kata-kata pencarian (tanpa spasi berlebih).
  List<String> get tokens => query
      .trim()
      .split(RegExp(r'\s+'))
      .where((String t) => t.isNotEmpty)
      .toList();

  bool get hasQuery => tokens.isNotEmpty;
  bool get hasDateRange => from != null || to != null;
  bool get hasTotalRange => minTotal != null || maxTotal != null;
  bool get hasCategories => categoryIds.isNotEmpty;

  /// Jumlah kelompok filter yang aktif (tanggal, total, kategori).
  int get activeFilterCount => <bool>[
        hasDateRange,
        hasTotalRange,
        hasCategories
      ].where((bool active) => active).length;

  /// True bila tidak ada kata kunci maupun filter sama sekali.
  bool get isEmpty => !hasQuery && activeFilterCount == 0;

  TransactionFilter withQuery(String value) => _copy(query: value);

  TransactionFilter withSort(SearchSort value) => _copy(sort: value);

  TransactionFilter withDateRange(DateTime? from, DateTime? to) =>
      TransactionFilter(
        query: query,
        from: from,
        to: to,
        minTotal: minTotal,
        maxTotal: maxTotal,
        categoryIds: categoryIds,
        sort: sort,
      );

  TransactionFilter withTotalRange(double? min, double? max) =>
      TransactionFilter(
        query: query,
        from: from,
        to: to,
        minTotal: min,
        maxTotal: max,
        categoryIds: categoryIds,
        sort: sort,
      );

  TransactionFilter withCategories(Set<int> ids) => _copy(categoryIds: ids);

  /// Menghapus semua filter tetapi mempertahankan kata kunci dan urutan.
  TransactionFilter clearedFilters() =>
      TransactionFilter(query: query, sort: sort);

  TransactionFilter _copy({
    String? query,
    Set<int>? categoryIds,
    SearchSort? sort,
  }) {
    return TransactionFilter(
      query: query ?? this.query,
      from: from,
      to: to,
      minTotal: minTotal,
      maxTotal: maxTotal,
      categoryIds: categoryIds ?? this.categoryIds,
      sort: sort ?? this.sort,
    );
  }
}
