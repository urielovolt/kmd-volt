import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/autofill_service.dart';
import '../core/database/database_service.dart';
import '../core/models/entry_model.dart';
import '../core/models/group_model.dart';

class VaultProvider extends ChangeNotifier {
  final _db = DatabaseService.instance;

  List<GroupModel> _groups = [];
  List<EntryModel> _entries = [];
  List<EntryModel> _searchResults = [];
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;

  List<GroupModel> get groups => _groups;
  List<EntryModel> get entries => _entries;
  List<EntryModel> get searchResults => _searchResults;
  List<EntryModel> get favorites =>
      _entries.where((e) => e.isFavorite).toList();
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadAll() async {
    _isLoading = true;
    notifyListeners();

    try {
      _groups = await _db.getGroups();
      _entries = await _db.getEntries();
      _error = null;
    } catch (e) {
      _error = 'Error al cargar el vault';
    }

    _isLoading = false;
    notifyListeners();

    // Sync entries to Android autofill service
    if (_entries.isNotEmpty) {
      AutofillService.syncEntries(_entries);
    }
  }

  Future<List<EntryModel>> getEntriesForGroup(String groupId) async {
    return _entries.where((e) => e.groupId == groupId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  int entryCountForGroup(String groupId) =>
      _entries.where((e) => e.groupId == groupId).length;

  // ─── Search ──────────────────────────────────────────────────────────────────

  Future<void> search(String query) async {
    _searchQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
    } else {
      _searchResults = await _db.searchEntries(query);
    }
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults = [];
    notifyListeners();
  }

  // ─── Groups ──────────────────────────────────────────────────────────────────

  Future<void> addGroup(GroupModel group) async {
    await _db.insertGroup(group);
    _groups.add(group);
    notifyListeners();
  }

  Future<void> updateGroup(GroupModel group) async {
    await _db.updateGroup(group);
    final idx = _groups.indexWhere((g) => g.id == group.id);
    if (idx >= 0) _groups[idx] = group;
    notifyListeners();
  }

  Future<void> deleteGroup(String groupId) async {
    await _db.deleteGroup(groupId);
    _groups.removeWhere((g) => g.id == groupId);
    _entries.removeWhere((e) => e.groupId == groupId);
    notifyListeners();
  }

  // ─── Entries ─────────────────────────────────────────────────────────────────

  Future<void> addEntry(EntryModel entry) async {
    await _db.insertEntry(entry);
    _entries.insert(0, entry);
    notifyListeners();
    AutofillService.syncEntries(_entries);
  }

  Future<void> updateEntry(EntryModel entry) async {
    await _db.updateEntry(entry);
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) _entries[idx] = entry;
    notifyListeners();
    AutofillService.syncEntries(_entries);
  }

  Future<void> deleteEntry(String id) async {
    await _db.deleteEntry(id);
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    AutofillService.syncEntries(_entries);
  }

  Future<void> toggleFavorite(EntryModel entry) async {
    final updated = entry.copyWith(isFavorite: !entry.isFavorite);
    await updateEntry(updated);
  }

  // ─── Backup ──────────────────────────────────────────────────────────────────

  Future<String> exportToJson(Uint8List vaultKey) async {
    final data = await _db.exportVault(vaultKey);
    return jsonEncode(data);
  }

  Future<void> importFromJson(String json, Uint8List vaultKey) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    await _db.importVault(data, vaultKey);
    await loadAll();
  }

  void clear() {
    _groups = [];
    _entries = [];
    _searchResults = [];
    notifyListeners();
    AutofillService.lockVault();
  }
}
