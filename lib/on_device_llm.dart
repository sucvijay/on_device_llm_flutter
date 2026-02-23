import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

// Typedefs
typedef LoadModelC = Bool Function(Pointer<Utf8> modelPath, Pointer<Utf8> mmprojPath);
typedef LoadModelDart = bool Function(Pointer<Utf8> modelPath, Pointer<Utf8> mmprojPath);

typedef GenerateC = Pointer<Utf8> Function(Pointer<Utf8> prompt, Pointer<Utf8> imagePath);
typedef GenerateDart = Pointer<Utf8> Function(Pointer<Utf8> prompt, Pointer<Utf8> imagePath);

typedef StreamCallbackC = Void Function(Pointer<Utf8> chunk);
typedef StreamC = Void Function(Pointer<Utf8> prompt, Pointer<Utf8> imagePath, Pointer<NativeFunction<StreamCallbackC>> callback);
typedef StreamDart = void Function(Pointer<Utf8> prompt, Pointer<Utf8> imagePath, Pointer<NativeFunction<StreamCallbackC>> callback);

typedef CloseC = Void Function();
typedef CloseDart = void Function();

// Global variable for Isolate communication
SendPort? _isolateSendPort;

// Static callback function for FFI
void _onStreamChunk(Pointer<Utf8> chunk) {
  if (_isolateSendPort != null) {
    final str = chunk.toDartString();
    _isolateSendPort!.send(str);
  }
}

class OnDeviceLlm {
  late DynamicLibrary _lib;
  late LoadModelDart _loadModel;
  late GenerateDart _generate;
  late StreamDart _stream;
  late CloseDart _close;

  OnDeviceLlm() {
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libon_device_llm.so');
    } else if (Platform.isIOS) {
      _lib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('Platform not supported');
    }

    _loadModel = _lib.lookupFunction<LoadModelC, LoadModelDart>('flutter_load_model');
    _generate = _lib.lookupFunction<GenerateC, GenerateDart>('flutter_generate');
    // _stream is used in Isolate, but we can lookup here too if needed
    _close = _lib.lookupFunction<CloseC, CloseDart>('flutter_close');
  }

  bool load(String modelPath, {String? mmprojPath}) {
    final modelPathPtr = modelPath.toNativeUtf8();
    final mmprojPathPtr = (mmprojPath ?? "").toNativeUtf8();

    final result = _loadModel(modelPathPtr, mmprojPathPtr);

    calloc.free(modelPathPtr);
    calloc.free(mmprojPathPtr);

    return result;
  }

  String generate(String prompt, {String? imagePath}) {
    final promptPtr = prompt.toNativeUtf8();
    final imagePathPtr = (imagePath ?? "").toNativeUtf8();

    final resultPtr = _generate(promptPtr, imagePathPtr);
    final result = resultPtr.toDartString();

    calloc.free(promptPtr);
    calloc.free(imagePathPtr);

    return result;
  }

  Stream<String> stream(String prompt, {String? imagePath}) {
    final controller = StreamController<String>();
    final receivePort = ReceivePort();

    receivePort.listen((message) {
      if (message is String) {
        controller.add(message);
      } else if (message == 'DONE') {
        controller.close();
        receivePort.close();
      }
    });

    Isolate.spawn(_streamIsolateEntry, _StreamIsolateArgs(
      prompt,
      imagePath,
      receivePort.sendPort,
      Platform.isAndroid ? 'libon_device_llm.so' : 'PROCESS'
    ));

    return controller.stream;
  }

  void close() {
    _close();
  }
}

class _StreamIsolateArgs {
  final String prompt;
  final String? imagePath;
  final SendPort sendPort;
  final String libPath;

  _StreamIsolateArgs(this.prompt, this.imagePath, this.sendPort, this.libPath);
}

void _streamIsolateEntry(_StreamIsolateArgs args) {
  _isolateSendPort = args.sendPort;

  DynamicLibrary lib;
  if (args.libPath == 'PROCESS') {
    lib = DynamicLibrary.process();
  } else {
    lib = DynamicLibrary.open(args.libPath);
  }

  final streamFunc = lib.lookupFunction<StreamC, StreamDart>('flutter_stream');

  final promptPtr = args.prompt.toNativeUtf8();
  final imagePathPtr = (args.imagePath ?? "").toNativeUtf8();

  final callback = Pointer.fromFunction<StreamCallbackC>(_onStreamChunk);

  streamFunc(promptPtr, imagePathPtr, callback);

  args.sendPort.send('DONE');

  calloc.free(promptPtr);
  calloc.free(imagePathPtr);
}
