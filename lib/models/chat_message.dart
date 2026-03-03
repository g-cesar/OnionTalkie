/// Type of chat message.
enum MessageType {
  text,
  system,
}

/// Direction of the message.
enum MessageDirection {
  sent,
  received,
}

/// Represents a single chat message in a call.
class ChatMessage {
  final String id;
  final MessageType type;
  final MessageDirection direction;
  final String content;
  final DateTime timestamp;
  final int? payloadBytes;

  const ChatMessage({
    required this.id,
    required this.type,
    required this.direction,
    required this.content,
    required this.timestamp,
    this.payloadBytes,
  });
}
