import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onion_talkie/services/connection_service_native.dart';

void main() {
  test(
    'ConnectionServiceNative should ignore secondary connections when active',
    () async {
      final service = ConnectionServiceNative();

      // 1. Start listening on ephemeral port
      await service.listen(port: 0);
      final port = service.serverSocketPort!;

      // 2. Establish first connection
      final socket1 = await Socket.connect('127.0.0.1', port);

      // Send valid protocol data to promote socket1
      socket1.write('ID:test_user\n');
      await socket1.flush();

      // Wait for the service to recognize it's connected
      await Future.delayed(const Duration(milliseconds: 100));
      expect(service.isConnected, isTrue);

      // 3. Attempt second connection
      final socket2 = await Socket.connect('127.0.0.1', port);

      // Wait a bit
      await Future.delayed(const Duration(milliseconds: 100));

      // socket2 should have been destroyed by the service
      bool socket2Closed = false;
      socket2.listen(
        (_) {},
        onDone: () => socket2Closed = true,
        onError: (_) => socket2Closed = true,
      );

      // Give it time to receive the close event
      await Future.delayed(const Duration(milliseconds: 100));
      // Cleanup
      await service.disconnect();
      await socket1.close();
      await socket2.close();

      expect(socket2Closed, isTrue);
    },
  );
}
