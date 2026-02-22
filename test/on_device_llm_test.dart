import 'package:flutter_test/flutter_test.dart';
import 'package:on_device_llm/on_device_llm.dart';
import 'package:on_device_llm/on_device_llm_platform_interface.dart';
import 'package:on_device_llm/on_device_llm_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockOnDeviceLlmPlatform
    with MockPlatformInterfaceMixin
    implements OnDeviceLlmPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final OnDeviceLlmPlatform initialPlatform = OnDeviceLlmPlatform.instance;

  test('$MethodChannelOnDeviceLlm is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelOnDeviceLlm>());
  });

  test('getPlatformVersion', () async {
    OnDeviceLlm onDeviceLlmPlugin = OnDeviceLlm();
    MockOnDeviceLlmPlatform fakePlatform = MockOnDeviceLlmPlatform();
    OnDeviceLlmPlatform.instance = fakePlatform;

    expect(await onDeviceLlmPlugin.getPlatformVersion(), '42');
  });
}
