
import 'on_device_llm_platform_interface.dart';

class OnDeviceLlm {
  Future<String?> getPlatformVersion() {
    return OnDeviceLlmPlatform.instance.getPlatformVersion();
  }
}
