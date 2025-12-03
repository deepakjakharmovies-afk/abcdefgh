import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sphere_with_drive/auth_service.dart';
import 'package:sphere_with_drive/drive_service.dart';
import 'package:sphere_with_drive/gridveiw.dart'; // Retained for navigation
import 'package:google_fonts/google_fonts.dart';

// The data models are now in models.dart, so we'll remove the local Trip class
// and use the DriveService data structure.

// --- 1. Home Screen (Main App Shell) ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Listen for errors from AuthService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      authService.addListener(_onError);
    });
  }

  @override
  void dispose() {
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.removeListener(_onError);
    super.dispose();
  }

  void _onError() {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authService.errorMessage!),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      // Clear the error so it doesn't show again immediately (optional, depending on AuthService implementation)
      // authService.setError(null); // Assuming we can clear it or it clears itself on next action
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/snapsphere_logo.png',
              height: 32,
              errorBuilder: (c, e, s) =>
                  const Icon(Icons.camera, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              'SnapSphere',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => Provider.of<DriveService>(
              context,
              listen: false,
            ).fetchSpheres(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: authService.signOut,
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF121212), Color(0xFF1E1E2C)],
          ),
        ),
        child: const SphereGridView(),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'join',
              onPressed: () => _joinShereDialog(context),
              icon: const Icon(Icons.group_add_rounded),
              label: const Text('Join'),
              backgroundColor: const Color(0xFF2C2C2C),
              foregroundColor: Colors.white,
            ),
            const SizedBox(width: 16),
            FloatingActionButton.extended(
              heroTag: 'create',
              onPressed: () => _showCreateSphereDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New Sphere'),
              backgroundColor: Colors.indigoAccent,
              foregroundColor: Colors.white,
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _joinShereDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const joinShereDialog());
  }

  void _showCreateSphereDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const CreateSphereDialog());
  }
}

final link = TextEditingController();

class joinShereDialog extends StatelessWidget {
  const joinShereDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Join a Sphere"),
      content: TextField(
        controller: link,
        decoration: const InputDecoration(labelText: 'Enter Sphere Code'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),

          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);

            final result = await Provider.of<DriveService>(
              context,
              listen: false,
            ).joinSphereFromLink(link.text.trim());

            navigator.pop();

            if (result != null) {
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('Successfully joined: ${result.name}')),
              );
            }
          },
          child: const Text('Join'),
        ),
      ],
    );
  }
}

class CreateLinkDiloge extends StatefulWidget {
  final String? link;
  const CreateLinkDiloge.CreateLinkDialog({super.key, this.link});

  @override
  State<CreateLinkDiloge> createState() => _CreateLinkDilogeState();
}

void _whattodo(BuildContext context, String folderId) {
  showDialog(
    context: context,
    builder: (ctx) => WhatTOdo(folderId: folderId),
  );
}

void _showlinkShareableLinkDialog(BuildContext context, String? link) {
  showDialog(
    context: context,
    builder: (ctx) => CreateLinkDiloge.CreateLinkDialog(link: link),
  );
}

class _CreateLinkDilogeState extends State<CreateLinkDiloge> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("shareable Link"),
      content: SelectableText(widget.link.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close"),
        ),
      ],
    );
  }
}
// --- 2. List View of Spheres (Drive Folders) ---

class SphereGridView extends StatelessWidget {
  const SphereGridView({super.key});

  @override
  Widget build(BuildContext context) {
    final driveService = Provider.of<DriveService>(context);

    if (driveService.isLoading && driveService.spheres.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (driveService.spheres.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              'No SnapSpheres yet',
              style: GoogleFonts.outfit(fontSize: 20, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create or join one to get started!',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        16,
        100,
        16,
        100,
      ), // Top padding for AppBar
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: driveService.spheres.length,
      itemBuilder: (context, index) {
        final sphere = driveService.spheres[index];
        return GestureDetector(
          onLongPress: () => _whattodo(context, sphere.id),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PhotoGridScreen(sphere: sphere),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF252525),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF2C2C2C), const Color(0xFF252525)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.folder_open_rounded,
                        size: 48,
                        color: Colors.indigoAccent.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sphere.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sphere.ownerEmail,
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class WhatTOdo extends StatelessWidget {
  final String folderId;
  const WhatTOdo({super.key, required this.folderId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("What do you want to do?"),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            onPressed: () async {
              final link = await Provider.of<DriveService>(
                context,
                listen: false,
              ).createShareableLink(folderId);
              if (link != null) {
                _showlinkShareableLinkDialog(context, link);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to create shareable link.'),
                  ),
                );
              }
            },
            child: Text("link"),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<DriveService>(
                context,
                listen: false,
              ).deleteFolder(folderId);
              Navigator.pop(context);
            },
            child: Text("delete"),
          ),

          // fatchspheres(,
        ],
      ),
    );
  }
}

// --- 3. Create Sphere Dialog ---

class CreateSphereDialog extends StatefulWidget {
  const CreateSphereDialog({super.key});

  @override
  State<CreateSphereDialog> createState() => _CreateSphereDialogState();
}

class _CreateSphereDialogState extends State<CreateSphereDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isCreating = false;

  Future<void> _createSphere() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    final driveService = Provider.of<DriveService>(context, listen: false);
    final success = await driveService.createSphere(name);

    setState(() => _isCreating = false);

    if (success) {
      Navigator.pop(context); // Close dialog
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New SnapSphere'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Sphere Name (Drive Folder Name)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isCreating ? null : _createSphere,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
