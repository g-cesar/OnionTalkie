import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact.dart';
import '../services/contacts_service.dart';

/// Singleton provider for the [ContactsService].
final contactsServiceProvider = Provider<ContactsService>((ref) {
  return ContactsService();
});

/// StateNotifier that exposes the contacts list and keeps it in sync
/// with the persisted JSON file.
class ContactsNotifier extends StateNotifier<List<Contact>> {
  final ContactsService _service;

  ContactsNotifier(this._service) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    state = await _service.load();
  }

  /// Reload from disk.
  Future<void> refresh() async {
    state = await _service.load();
  }

  /// Add a new contact.
  Future<Contact> add({
    required String alias,
    required String onionAddress,
    String sharedSecret = '',
    String availability = '',
  }) async {
    final contact = await _service.add(
      alias: alias,
      onionAddress: onionAddress,
      sharedSecret: sharedSecret,
      availability: availability,
    );
    state = _service.contacts;
    return contact;
  }

  /// Update an existing contact.
  Future<void> update(Contact contact) async {
    await _service.update(contact);
    state = _service.contacts;
  }

  /// Delete a contact.
  Future<void> delete(String id) async {
    await _service.delete(id);
    state = _service.contacts;
  }

  /// Update a contact's onion address (address-change flow).
  Future<void> updateOnionAddress(String contactId, String newAddress) async {
    await _service.updateOnionAddress(contactId, newAddress);
    state = _service.contacts;
  }

  /// Acknowledge an address change.
  Future<void> acknowledgeAddressChange(String contactId) async {
    await _service.acknowledgeAddressChange(contactId);
    state = _service.contacts;
  }

  /// Mark a contact as successfully contacted.
  Future<void> markContacted(String contactId) async {
    await _service.markContacted(contactId);
    state = _service.contacts;
  }

  // ── Look-ups (delegate to service) ────────────────────────────

  Contact? findByOnion(String onionAddress) =>
      _service.findByOnion(onionAddress);

  Contact? findById(String id) => _service.findById(id);

  Contact? findByPreviousOnion(String onionAddress) =>
      _service.findByPreviousOnion(onionAddress);
}

/// The main contacts provider.
final contactsProvider = StateNotifierProvider<ContactsNotifier, List<Contact>>(
  (ref) {
    final service = ref.watch(contactsServiceProvider);
    return ContactsNotifier(service);
  },
);
