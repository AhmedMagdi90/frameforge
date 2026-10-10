import 'dart:io';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/project_library.dart';
import '../theme.dart';
import 'editor_screen.dart';
import 'ai_studio_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.library});
  final ProjectLibrary library;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<VideoProject>? _projects;
  String? _error;
  bool _creating = false;
  @override
  void initState() { super.initState(); _reload(); }
  Future<void> _reload() async {
    try {
      final values = await widget.library.list();
      if (mounted) setState(() { _projects = values; _error = null; });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read your projects. $error');
    }
  }
  Future<void> _open(VideoProject project) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      EditorScreen(project: project, library: widget.library)));
    await _reload();
  }
  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final project = await widget.library.create();
      if (mounted) await _open(project);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create project: $error')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
  Future<void> _delete(VideoProject project) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete this project?'),
      content: Text('“${project.name}” and its imported media and exports will be removed from this app.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep project')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (confirmed != true) return;
    try { await widget.library.delete(project.id); await _reload(); }
    catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete project: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960),
      child: RefreshIndicator(onRefresh: _reload, child: ListView(padding: const EdgeInsets.all(24), children: [
        Row(children: [const BrandMark(), const SizedBox(width: 12),
          const Text('frameforge', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -1)),
          const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(30)),
            child: Row(children: [const Icon(Icons.lock_outline_rounded, size: 13, color: mint),
              if (MediaQuery.sizeOf(context).width >= 400) ...[const SizedBox(width: 6),
                const Text('On your device', style: TextStyle(fontSize: 11, color: muted))]])),
        ]),
        const SizedBox(height: 42),
        const Text('Make every\nframe yours.', style: TextStyle(fontSize: 43, height: 1.08,
          fontWeight: FontWeight.w700, letterSpacing: -1.8)),
        const SizedBox(height: 14),
        const Text('A little footage. A big idea.\nYour next story starts here.', style: TextStyle(color: muted, fontSize: 15, height: 1.55)),
        const SizedBox(height: 28),
        InkWell(onTap: _creating ? null : _create, borderRadius: BorderRadius.circular(22),
          child: Container(padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFFB9ACFF), Color(0xFF8E82E8)])),
            child: Row(children: [Container(width: 52, height: 52,
              decoration: BoxDecoration(color: ink.withOpacity(.12), borderRadius: BorderRadius.circular(16)),
              child: _creating ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(color: ink))
                : const Icon(Icons.add_rounded, color: ink, size: 30)),
              const SizedBox(width: 18), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('New project', style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700)),
                  SizedBox(height: 4), Text('Turn your clips into a story', style: TextStyle(color: Color(0xFF393157), fontSize: 13))])),
              const Icon(Icons.arrow_forward_rounded, color: ink),
            ]))),
        const SizedBox(height: 18),
        Card(child: ListTile(contentPadding: const EdgeInsets.all(18),
          leading: const Icon(Icons.auto_awesome_rounded, color: mint),
          title: const Text('Create with AI', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Describe an idea. Generate a narrated video.'),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AiStudioScreen(library: widget.library)));
            await _reload();
          })),
        const SizedBox(height: 18),
        const Wrap(spacing: 18, runSpacing: 12, children: [
          _Feature(icon: Icons.content_cut_rounded, label: 'Precise edits'),
          _Feature(icon: Icons.music_note_rounded, label: 'Your sound'),
          _Feature(icon: Icons.text_fields_rounded, label: 'Tell your story'),
        ]),
        const SizedBox(height: 38),
        Row(children: [const Text('Your projects', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const Spacer(), Text('${_projects?.length ?? 0} drafts', style: const TextStyle(color: muted, fontSize: 12))]),
        const SizedBox(height: 18),
        if (_error != null) ...[Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          TextButton(onPressed: _reload, child: const Text('Try again'))]
        else if (_projects == null) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else if (_projects!.isEmpty) Container(padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
          child: const Column(children: [Icon(Icons.movie_creation_outlined, color: muted, size: 36),
            SizedBox(height: 14), Text('A blank canvas, endless possibilities.', textAlign: TextAlign.center),
            SizedBox(height: 7), Text('Create a project to bring your clips together.', textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12))]))
        else ..._projects!.map((project) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16)),
          child: ListTile(contentPadding: const EdgeInsets.only(left: 10, right: 4, top: 5, bottom: 5),
            onTap: () => _open(project),
            leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 60, height: 60,
              child: project.clips.isNotEmpty && project.clips.first.thumbnailPath != null
                ? Image.file(File(project.clips.first.thumbnailPath!), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.movie_outlined, color: violet))
                : const ColoredBox(color: elevated, child: Icon(Icons.movie_outlined, color: violet)))),
            title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${formatTime(project.durationMs)}  ·  ${project.clips.length} clips  ·  ${project.ratio.label}',
              style: const TextStyle(color: muted, fontSize: 12)),
            trailing: IconButton(tooltip: 'Delete project', onPressed: () => _delete(project),
              icon: const Icon(Icons.more_horiz_rounded, color: muted)),
          )))),
        const SizedBox(height: 24),
        const Text('Made for your ideas. Saved on your device.', textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 11)),
      ])),
    ))),
  );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 15, color: mint), const SizedBox(width: 5), Text(label, style: const TextStyle(color: muted, fontSize: 11)),
  ]);
}
