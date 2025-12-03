import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sphere_with_drive/auth_service.dart';
import 'package:sphere_with_drive/models.dart';

class DriveService with ChangeNotifier {
  AuthService _authService; // Not final anymore
  final String _sphereRootFolderName = "SnapSphere Photos";
  String? _snapSphereRootId;
  AuthService get authService => _authService;

  List<Sphere> _spheres = [];
  bool _isLoading = false;

  List<Sphere> get spheres => _spheres;
  bool get isLoading => _isLoading;

  DriveService(this._authService) {
    _initListeners();
    if (_authService.isAuthenticated) {
      _initialize();
    }
  }

  void update(AuthService newAuthService) {
    if (_authService != newAuthService) {
      _authService.removeListener(_onAuthChange);
      _authService = newAuthService;
      _initListeners();
      // If auth state changed, re-init
      _onAuthChange();
    }
  }

  void _initListeners() {
    _authService.addListener(_onAuthChange);
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    if (_authService.isAuthenticated) {
      // Only re-initialize if we don't have a root ID yet or if API changed
      if (_snapSphereRootId == null) {
        _initialize();
      }
    } else {
      _spheres = [];
      _snapSphereRootId = null;
      notifyListeners();
    }
  }

  drive.DriveApi? get _driveApi => _authService.driveApi;

  // --- Core Initialization ---

  Future<void> _initialize() async {
    if (_driveApi == null) return;
    await _ensureRootFolderExists();
    await fetchSpheres();
  }

  // Create a shareable view-only link for a file/sphere
  Future<String?> createShareableLink(String fileId) async {
    try {
      await _driveApi!.permissions.create(
        drive.Permission.fromJson({
          "role": "writer", // allow editing
          "type": "anyone",
          "allowFileDiscovery": false, // anyone with link
        }),
        fileId,
      );

      final file = await _driveApi!.files.get(fileId, $fields: 'webViewLink');
      return (file as drive.File).webViewLink;
    } catch (e) {
      print('Error creating shareable link: $e');
      return null;
    }
  }

  // ---- DELETE FILE ----
  Future<void> deleteFile(String fileId) async {
    try {
      await _driveApi!.files.delete(fileId);
      print(_spheres.where((sphere) => sphere.id == fileId));

      print('Deleted: $fileId');
    } catch (e) {
      print('Error deleting file: $e');
    }
  }

  Future<void> deleteFolder(String folderId) async {
    try {
      // The `files.delete` method requires the ID of the file or folder to delete.
      _driveApi!.files.delete(folderId);
    } catch (e) {
      print('Error deleting folder: $e');
    }
  }

  /// Ensures the main "SnapSphere Photos" folder exists in the user's Drive.
  Future<void> _ensureRootFolderExists() async {
    print('DEBUG: _ensureRootFolderExists started');
    if (_driveApi == null) {
      print('DEBUG: _ensureRootFolderExists - Drive API is null');
      return;
    }
    if (_snapSphereRootId != null) {
      print(
        'DEBUG: _ensureRootFolderExists - Root ID already exists: $_snapSphereRootId',
      );
      return;
    }

    try {
      print(
        'DEBUG: _ensureRootFolderExists - Searching for folder: $_sphereRootFolderName',
      );
      // Search for the root folder
      final fileList = await _driveApi!.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and name='$_sphereRootFolderName' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        // Found the existing folder
        _snapSphereRootId = fileList.files!.first.id;
        print(
          'DEBUG: Found existing SnapSphere Root Folder: $_snapSphereRootId',
        );
      } else {
        print('DEBUG: Root folder not found, creating new one...');
        // Create the root folder if it doesn't exist
        final drive.File folder = drive.File();
        folder.name = _sphereRootFolderName;
        folder.mimeType = 'application/vnd.google-apps.folder';

        final createdFile = await _driveApi!.files.create(folder);
        _snapSphereRootId = createdFile.id;
        print(
          'DEBUG: SnapSphere Root Folder created with ID: $_snapSphereRootId',
        );
      }
    } catch (e) {
      print('ERROR: _ensureRootFolderExists failed: $e');
      _authService.setError('Failed to access Google Drive root folder: $e');
    }
  }

  // --- Sphere (Folder) Management ---

  Future<void> fetchSpheres() async {
    if (_driveApi == null || _snapSphereRootId == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      // Query for folders AND shortcuts inside the root folder
      final fileList = await _driveApi!.files.list(
        q: "(mimeType='application/vnd.google-apps.folder' or mimeType='application/vnd.google-apps.shortcut') and '$_snapSphereRootId' in parents and trashed=false",
        spaces: 'drive',
        $fields:
            'files(id, name, createdTime, owners, mimeType, shortcutDetails)',
      );

      List<Sphere> loadedSpheres = [];

      if (fileList.files != null) {
        for (var file in fileList.files!) {
          if (file.mimeType == 'application/vnd.google-apps.shortcut') {
            // Handle Shortcut: Resolve the target folder
            final targetId = file.shortcutDetails?.targetId;
            if (targetId != null) {
              try {
                // Fetch the actual target folder details
                final target =
                    await _driveApi!.files.get(
                          targetId,
                          $fields: 'id, name, createdTime, owners, mimeType',
                        )
                        as drive.File;

                // Only add if it's a folder
                if (target.mimeType == 'application/vnd.google-apps.folder') {
                  loadedSpheres.add(
                    Sphere(
                      id: target.id!,
                      name: target.name!, // Use target's name
                      ownerEmail:
                          target.owners?.first.emailAddress ?? 'Unknown',
                      createdAt:
                          target.createdTime?.toLocal() ?? DateTime.now(),
                    ),
                  );
                }
              } catch (e) {
                print('Could not resolve shortcut target $targetId: $e');
              }
            }
          } else {
            // Handle Regular Folder
            loadedSpheres.add(
              Sphere(
                id: file.id!,
                name: file.name!,
                ownerEmail: file.owners?.first.emailAddress ?? 'Unknown',
                createdAt: file.createdTime?.toLocal() ?? DateTime.now(),
              ),
            );
          }
        }
      }

      _spheres = loadedSpheres;
      // Remove duplicates just in case (e.g. multiple shortcuts to same folder)
      final ids = <String>{};
      _spheres.retainWhere((x) => ids.add(x.id));

      _spheres.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      print('Error fetching spheres: $e');
      _authService.setError('Failed to fetch photo albums from Drive.');
      _spheres = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<drive.File?> joinSphereFromLink(String link) async {
    try {
      // Extract the folder ID
      String? fileId;
      final RegExp regExp = RegExp(r'[-\w]{25,}');

      final match = regExp.firstMatch(link);
      if (match != null) {
        fileId = match.group(0);
      } else if (link.length > 20) {
        fileId = link;
      }

      if (fileId == null) throw Exception('Invalid Google Drive link');

      // 1. Check if we already have this sphere in our list
      if (_spheres.any((s) => s.id == fileId)) {
        print('Already joined this sphere.');
        return await _driveApi!.files.get(
              fileId,
              $fields: 'id,name,mimeType,webViewLink',
            )
            as drive.File;
      }

      // 2. Fetch target to verify it exists and get name
      final targetFile =
          await _driveApi!.files.get(
                fileId,
                $fields: 'id,name,mimeType,webViewLink',
              )
              as drive.File;

      if (targetFile.mimeType != 'application/vnd.google-apps.folder') {
        throw Exception('Link is not a folder.');
      }

      // 3. Create a Shortcut in our SnapSphere root folder
      // Check if shortcut already exists (to avoid duplicates if _spheres check failed)
      final existingShortcuts = await _driveApi!.files.list(
        q: "mimeType='application/vnd.google-apps.shortcut' and '$_snapSphereRootId' in parents and trashed=false",
        $fields: 'files(id, shortcutDetails)',
      );

      bool shortcutExists =
          existingShortcuts.files?.any(
            (f) => f.shortcutDetails?.targetId == fileId,
          ) ??
          false;

      if (!shortcutExists) {
        final shortcut = drive.File();
        shortcut.name = targetFile.name;
        shortcut.mimeType = 'application/vnd.google-apps.shortcut';
        shortcut.parents = [_snapSphereRootId!];
        shortcut.shortcutDetails = drive.FileShortcutDetails()
          ..targetId = fileId;

        await _driveApi!.files.create(shortcut);
        print('Created shortcut for sphere: ${targetFile.name}');
      }

      // 4. Refresh list
      await fetchSpheres();

      return targetFile;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        print('⚠️ File not found or permission denied.');
        _authService.setError(
          'Sphere not found or access denied. Ask the owner to share it with you.',
        );
        return null;
      } else {
        print('Error joining sphere (API): $e');
        _authService.setError('Failed to join Sphere: ${e.message}');
        return null;
      }
    } catch (e) {
      print('Error joining sphere: $e');
      _authService.setError('Failed to join Sphere.');
      return null;
    }
  }

  Future<bool> createSphere(String name) async {
    if (_driveApi == null) {
      print('DEBUG: createSphere - Drive API is null');
      return false;
    }

    // Robustness: Ensure root folder exists before creating sphere
    if (_snapSphereRootId == null) {
      print(
        'DEBUG: createSphere - Root ID is null, attempting to create/find it...',
      );
      await _ensureRootFolderExists();
      if (_snapSphereRootId == null) {
        print('DEBUG: createSphere - Failed to get Root ID');
        _authService.setError('Failed to initialize SnapSphere folder.');
        return false;
      }
    }

    _isLoading = true;
    notifyListeners();

    try {
      print('DEBUG: createSphere - Creating folder: $name');
      final folder = drive.File();
      folder.name = name;
      folder.mimeType = 'application/vnd.google-apps.folder';
      folder.parents = [_snapSphereRootId!]; // Put inside the root folder

      print('DEBUG: createSphere - Sending API request...');
      await _driveApi!.files.create(folder);
      print('DEBUG: createSphere - API request success');

      // Refresh the list
      print('DEBUG: createSphere - Fetching spheres...');
      await fetchSpheres();
      print('DEBUG: createSphere - Done');
      return true;
    } catch (e) {
      print('DEBUG: createSphere - Error: $e');
      _authService.setError('Failed to create new photo album.');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- Photo (File) Management ---

  Future<List<DriveFile>> fetchPhotos(String sphereId) async {
    if (_driveApi == null) return [];

    try {
      final fileList = await _driveApi!.files.list(
        q: "mimeType contains 'image/' and '$sphereId' in parents and trashed=false",
        spaces: 'drive',
        $fields:
            'files(id, name, mimeType, webContentLink, imageMediaMetadata, thumbnailLink)',
      );
      return fileList.files
              ?.map(
                (file) => DriveFile.fromGoogleApi(
                  file.id!,
                  file.name!,
                  file.mimeType!,
                  file.webContentLink,
                  file.thumbnailLink,
                ),
              )
              .toList() ??
          [];
    } catch (e) {
      print('Error fetching photos: $e');
      return [];
    }
  }

  Future<bool> uploadPhoto(String sphereId, File imageFile) async {
    if (_driveApi == null) return false;

    try {
      final file = drive.File();
      file.name = imageFile.path
          .split('/')
          .last; // Use the file name as the Drive name
      file.parents = [sphereId]; // Put inside the specific sphere folder

      final result = await _driveApi!.files.create(
        file,
        uploadMedia: drive.Media(imageFile.openRead(), imageFile.lengthSync()),
      );

      return result.id != null;
    } catch (e) {
      print('Error uploading file: $e');
      _authService.setError('Failed to upload photo to Drive.');
      return false;
    }
  }

  String filePath = "";
  Future<bool> downloadAndSavePhoto(DriveFile file) async {
    if (_driveApi == null || _authService.httpClient == null) return false;

    // 1. Get permission
    bool hasPermission = false;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+
        final photos = await Permission.photos.request();
        // Check for videos too if needed, but for now just photos
        hasPermission = photos.isGranted || photos.isLimited;
      } else {
        // Android < 13
        final storage = await Permission.storage.request();
        hasPermission = storage.isGranted;
      }
    } else {
      // iOS etc.
      hasPermission = await Permission.photos.request().isGranted;
    }

    if (!hasPermission) {
      _authService.setError('Permission denied. Cannot save photo.');
      return false;
    }

    try {
      // 2. Download the file using the authenticated HTTP client
      final response = await _authService.httpClient!.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/files/${file.id}?alt=media',
        ),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Download failed with status: ${response.statusCode} ${response.body}',
        );
      }

      // 3. Save to Gallery using gal
      try {
        await Gal.putImageBytes(response.bodyBytes, name: file.name);

        print('Image saved to gallery successfully');
        filePath = "Gallery"; // Just for UI feedback
        return true;
      } catch (saveError) {
        print('Error saving to gallery: $saveError');
        return false;
      }
    } catch (e) {
      print('Error downloading photo: $e');
      _authService.setError('Failed to download photo from Drive.');
      return false;
    }
  }

  Future getFilePath(DriveFile file) async {
    return filePath;
  }
}
