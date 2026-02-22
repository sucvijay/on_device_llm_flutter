import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'on_device_llm_platform_interface.dart';

class OnDeviceLlm {
  OnDeviceLlm({DynamicLibrary? dynamicLibrary}) : _dynamicLibrary = dynamicLibrary;

  final DynamicLibrary? _dynamicLibrary;
  DynamicLibrary? _resolvedDynamicLibrary;

  DynamicLibrary get _library => _resolvedDynamicLibrary ??= _dynamicLibrary ?? _openLibrary();

  int Function(Pointer<Utf8>, Pointer<Utf8>) get _loadModelNative =>
      _library.lookupFunction<
        Uint8 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)
      >('flutter_load_model');
  Pointer<Utf8> Function(Pointer<Utf8>) get _generateNative =>
      _library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('flutter_generate');
  void Function() get _closeNative =>
      _library.lookupFunction<Void Function(), void Function()>('flutter_free');

  static DynamicLibrary _openLibrary() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('OnDeviceLlm currently supports Android only.');
    }
    return DynamicLibrary.open('libllama.so');
  }

  Future<String?> getPlatformVersion() {
    return OnDeviceLlmPlatform.instance.getPlatformVersion();
  }

  Future<bool> load(String modelPath, {String? mmprojPath}) async {
    if (!modelPath.toLowerCase().endsWith('.gguf')) {
      return false;
    }

    final modelPathPtr = modelPath.toNativeUtf8();
    final mmprojPathPtr = (mmprojPath == null || mmprojPath.isEmpty)
        ? nullptr
        : mmprojPath.toNativeUtf8();

    try {
      return _loadModelNative(modelPathPtr, mmprojPathPtr) != 0;
    } finally {
      malloc.free(modelPathPtr);
      if (mmprojPathPtr != nullptr) {
        malloc.free(mmprojPathPtr);
      }
    }
  }

  Future<String?> generate(String prompt) async {
    final promptPtr = prompt.toNativeUtf8();
    try {
      final resultPtr = _generateNative(promptPtr);
      if (resultPtr == nullptr) {
        return null;
      }
      return resultPtr.toDartString();
    } finally {
      malloc.free(promptPtr);
    }
  }

  Stream<String> streamGenerate(String prompt, {int chunkSize = 32}) async* {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be greater than 0');
    }
    final output = await generate(prompt);
    if (output == null || output.isEmpty) {
      return;
    }

    for (var i = 0; i < output.length; i += chunkSize) {
      final end = (i + chunkSize < output.length) ? i + chunkSize : output.length;
      yield output.substring(i, end);
    }
  }

  Future<void> close() async {
    _closeNative();
  }
}
