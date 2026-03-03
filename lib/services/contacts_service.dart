import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/contact.dart';

/// Service that persists the contact list to a JSON file on disk.
class ContactsService {
  static const _fileName = 'contacts.json';
  static const _uuid = Uuid();
  List<Contact> _contacts = [];

  /// Currently loaded contacts (read-only).
  List<Contact> get contacts => List.unmodifiable(_contacts);

  // ── Persistence ────────────────────────────────────────────────

  Future<String> _filePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/terminalphone');
    if (!await dir.exists()) await dir.create(recursive: true);
    return '${dir.path}/$_fileName';
  }

  /// Load contacts from disk.
  Future<List<Contact>> load() async {
    try {
      final path = await _filePath();
      final file = File(path);
      if (!await file.exists()) {
        _contacts = [];
        return _contacts;
      }
      final json = await file.readAsString();
      final list = (jsonDecode(json) as List)
          .map((e) => Contact.fromJson(e as Map<String, dynamic>))
          .toList();
      _contacts = list;
    } catch (e) {
      debugPrint('ContactsService: failed to load contacts: $e');
      _contacts = [];
    }
    return _contacts;
  }

  /// Save the current list to disk.
  Future<void> _save() async {
    try {
      final path = await _filePath();
      final json = jsonEncode(_contacts.map((c) => c.toJson()).toList());
      await File(path).writeAsString(json);
    } catch (e) {
      debugPrint('ContactsService: failed to save contacts: $e');
    }
  }

  // ── CRUD ───────────────────────────────────────────────────────

  /// Add a new contact. Returns the created [Contact].
  Future<Contact> add({
    required String alias,
    required String onionAddress,
    String sharedSecret = '',
  }) async {
    final contact = Contact(
      id: _uuid.v4(),
      alias: alias,
      onionAddress: _normalise(onionAddress),
      sharedSecret: sharedSecret,
      createdAt: DateTime.now(),
    );
    _contacts.add(contact);
    await _save();
    return contact;
  }

  /// Update an existing contact.
  Future<void> update(Contact updated) async {
    final idx = _contacts.indexWhere((c) => c.id == updated.id);
    if (idx == -1) return;
    _contacts[idx] = updated;
    await _save();
  }

  /// Delete a contact by id.
  Future<void> delete(String id) async {
    _contacts.removeWhere((c) => c.id == id);
    await _save();
  }

  // ── Look-ups ───────────────────────────────────────────────────

  /// Find a contact by its onion address (exact match).
  Contact? findByOnion(String onionAddress) {
    final normalised = _normalise(onionAddress);
    try {
      return _contacts.firstWhere((c) => c.onionAddress == normalised);
    } catch (_) {
      return null;
    }
  }

  /// Find a contact by its id.
  Contact? findById(String id) {
    try {
      return _contacts.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Check whether an onion address previously belonged to a different
  /// contact (i.e. someone changed their hidden service address).
  Contact? findByPreviousOnion(String onionAddress) {
    final normalised = _normalise(onionAddress);
    try {
      return _contacts.firstWhere(
        (c) => c.previousOnionAddress == normalised,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Address-change helpers ─────────────────────────────────────

  /// Record that [contactId] now has a new onion address.
  /// The old address is saved in [previousOnionAddress].
  Future<void> updateOnionAddress(
    String contactId,
    String newOnionAddress,
  ) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    final old = _contacts[idx];
    _contacts[idx] = old.copyWith(
      previousOnionAddress: old.onionAddress,
      onionAddress: _normalise(newOnionAddress),
      addressChanged: true,
    );
    await _save();
  }

  /// Acknowledge the address change (user has seen the warning).
  Future<void> acknowledgeAddressChange(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    _contacts[idx] = _contacts[idx].copyWith(addressChanged: false);
    await _save();
  }

  /// Mark a successful contact.
  Future<void> markContacted(String contactId) async {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx == -1) return;
    _contacts[idx] = _contacts[idx].copyWith(
      lastContactedAt: DateTime.now(),
    );
    await _save();
  }

  // ── Helpers ────────────────────────────────────────────────────

  /// Normalise an onion address (lower-case, strip scheme/trailing slashes).
  static String _normalise(String addr) => addr
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'/$'), '');
}
