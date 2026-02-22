import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'on_device_llm_platform_interface.dart';

/// An implementation of [OnDeviceLlmPlatform] that uses method channels.
class MethodChannelOnDeviceLlm extends OnDeviceLlmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('on_device_llm');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
