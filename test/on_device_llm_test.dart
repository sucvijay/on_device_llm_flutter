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

class StubOnDeviceLlm extends OnDeviceLlm {
  StubOnDeviceLlm(this.output);

  final String output;

  @override
  Future<String?> generate(String prompt) async => output;
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

  test('load returns false for non-gguf model path', () async {
    final onDeviceLlmPlugin = OnDeviceLlm();
    expect(await onDeviceLlmPlugin.load('/tmp/model.bin'), isFalse);
  });

  test('streamGenerate yields chunked response', () async {
    final onDeviceLlmPlugin = StubOnDeviceLlm('hello world');
    expect(
      onDeviceLlmPlugin.streamGenerate('hi', chunkSize: 5),
      emitsInOrder(<String>['hello', ' worl', 'd', emitsDone]),
    );
  });

  test('streamGenerate throws for invalid chunk size', () {
    final onDeviceLlmPlugin = StubOnDeviceLlm('hello world');
    expect(
      () => onDeviceLlmPlugin.streamGenerate('hi', chunkSize: 0),
      throwsArgumentError,
    );
  });
}
