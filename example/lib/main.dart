import 'package:flutter/material.dart';
import 'package:on_device_llm/on_device_llm.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MaterialApp(home: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _llm = OnDeviceLlm();
  String _response = '';
  String? _modelPath;
  String? _mmprojPath;
  String? _imagePath;
  bool _isModelLoaded = false;
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Future<void> _pickModel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _modelPath = result.files.single.path;
      });
    }
  }

  Future<void> _pickMmproj() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _mmprojPath = result.files.single.path;
      });
    }
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null) {
      setState(() {
        _imagePath = result.files.single.path;
      });
    }
  }

  Future<void> _loadModel() async {
    if (_modelPath == null) return;

    setState(() {
      _response = "Loading model...";
      _isModelLoaded = false;
    });

    // Simulate async load to not block UI completely (though FFI call is blocking on main isolate)
    // Ideally load should be in an isolate too, but for simplicity we keep it here.
    // To properly unblock UI, we'd need another isolate or use compute.
    // For now, we just delay to let UI render "Loading..."
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      bool success = _llm.load(_modelPath!, mmprojPath: _mmprojPath);
      setState(() {
        _isModelLoaded = success;
        _response = success ? "Model loaded successfully!" : "Failed to load model.";
      });
    } catch (e) {
      setState(() {
        _response = "Error loading model: $e";
      });
    }
  }

  Future<void> _generate() async {
    if (!_isModelLoaded) return;

    setState(() {
      _response = "Generating...";
    });

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      String result = _llm.generate(_promptController.text, imagePath: _imagePath);
      setState(() {
        _response = result;
      });
    } catch (e) {
      setState(() {
        _response = "Error generating: $e";
      });
    }
  }

  Future<void> _stream() async {
    if (!_isModelLoaded) return;

    setState(() {
      _response = "";
    });

    try {
      final stream = _llm.stream(_promptController.text, imagePath: _imagePath);
      stream.listen(
        (chunk) {
          setState(() {
            _response += chunk;
          });
          // Scroll to bottom
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        },
        onError: (e) {
          setState(() {
            _response += "\nError: $e";
          });
        },
        onDone: () {
          setState(() {
            _response += "\n[DONE]";
          });
        },
      );
    } catch (e) {
      setState(() {
        _response = "Error streaming: $e";
      });
    }
  }

  @override
  void dispose() {
    _llm.close();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On Device LLM')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             Text("Model: ${_modelPath ?? 'None'}"),
             ElevatedButton(onPressed: _pickModel, child: const Text("Pick Model")),
             Text("MMProj: ${_mmprojPath ?? 'None'}"),
             ElevatedButton(onPressed: _pickMmproj, child: const Text("Pick MMProj")),
             const SizedBox(height: 10),
             ElevatedButton(
               onPressed: _modelPath != null ? _loadModel : null,
               child: const Text("Load Model"),
             ),
             const Divider(),
             TextField(
               controller: _promptController,
               decoration: const InputDecoration(labelText: "Prompt"),
               maxLines: 3,
             ),
             Text("Image: ${_imagePath ?? 'None'}"),
             ElevatedButton(onPressed: _pickImage, child: const Text("Pick Image")),
             const SizedBox(height: 10),
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
               children: [
                 ElevatedButton(
                   onPressed: _isModelLoaded ? _generate : null,
                   child: const Text("Generate"),
                 ),
                 ElevatedButton(
                   onPressed: _isModelLoaded ? _stream : null,
                   child: const Text("Stream"),
                 ),
               ],
             ),
             const Divider(),
             Expanded(
               child: Container(
                 padding: const EdgeInsets.all(8.0),
                 color: Colors.grey[200],
                 child: SingleChildScrollView(
                   controller: _scrollController,
                   child: Text(_response),
                 ),
               ),
             ),
          ],
        ),
      ),
    );
  }
}
