# on_device_llm

Android-only on-device llama.cpp runner for GGUF models.

```dart
final llm = OnDeviceLlm();

final loaded = await llm.load(
  '/data/user/0/.../model.gguf',
  mmprojPath: '/data/user/0/.../mmproj.gguf',
);
// Note: mmprojPath is reserved for separate vision projection loading and is
// currently not consumed by the native wrapper yet.

if (loaded) {
  final response = await llm.generate('Write a short haiku about Flutter.');

  await for (final chunk in llm.streamGenerate('Describe this image.')) {
    // chunked streaming output
  }

  await llm.close();
}
```
