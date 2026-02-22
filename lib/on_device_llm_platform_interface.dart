import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'on_device_llm_method_channel.dart';

abstract class OnDeviceLlmPlatform extends PlatformInterface {
  /// Constructs a OnDeviceLlmPlatform.
  OnDeviceLlmPlatform() : super(token: _token);

  static final Object _token = Object();

  static OnDeviceLlmPlatform _instance = MethodChannelOnDeviceLlm();

  /// The default instance of [OnDeviceLlmPlatform] to use.
  ///
  /// Defaults to [MethodChannelOnDeviceLlm].
  static OnDeviceLlmPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [OnDeviceLlmPlatform] when
  /// they register themselves.
  static set instance(OnDeviceLlmPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
