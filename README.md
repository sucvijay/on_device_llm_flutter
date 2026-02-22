# on_device_llm

Android-only on-device llama.cpp runner for GGUF models.

```dart
final llm = OnDeviceLlm();

final loaded = await llm.load(
  '/data/user/0/.../model.gguf',
  mmprojPath: '/data/user/0/.../mmproj.gguf',
);

if (loaded) {
  final response = await llm.generate('Write a short haiku about Flutter.');

  await for (final chunk in llm.streamGenerate('Describe this image.')) {
    // chunked streaming output
  }

  await llm.close();
}
```
