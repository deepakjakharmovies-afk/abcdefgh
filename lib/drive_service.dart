import 'dart:io';

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
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
      // Query for all folders (Spheres) inside the root folder
      final fileList = await _driveApi!.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and '$_snapSphereRootId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name, createdTime, owners)',
      );
      _spheres =
          fileList.files
              ?.map(
                (file) => Sphere(
                  id: file.id!,
                  name: file.name!,
                  ownerEmail: file.owners?.first.emailAddress ?? 'Unknown',
                  createdAt: file.createdTime?.toLocal() ?? DateTime.now(),
                ),
              )
              .toList() ??
          [];

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
      // Extract the folder ID (handles both folder & file links)
      final RegExp regExp = RegExp(r'[-\w]{25,}');
      final match = regExp.firstMatch(link);
      if (match == null) throw Exception('Invalid Google Drive link');

      final fileId = match.group(0)!;

      // Try to fetch it normally
      try {
        final file = await _driveApi!.files.get(
          fileId,
          $fields: 'id,name,mimeType,webViewLink',
        );
        // print('✅ Joined sphere: ${file.name}');
        return file as drive.File;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status == 404) {
          print('⚠️ File not found. Trying to fix permissions...');
        } else {
          rethrow;
        }
      }

      // If it failed (404), attempt to create a public permission
      try {
        await _driveApi!.permissions.create(
          drive.Permission.fromJson({
            'type': 'anyone',
            'role': 'reader', // or 'writer' if you want uploads
          }),
          fileId,
        );
        print('🔓 Made folder public, retrying...');

        final file = await _driveApi!.files.get(
          fileId,
          $fields: 'id,name,mimeType,webViewLink',
        );
        // print('✅ Joined after making public: ${file.name}');
        return file as drive.File;
      } catch (e) {
        print('❌ Could not make folder public: $e');
        rethrow;
      }
    } catch (e) {
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
    if (await Permission.storage.request().isDenied) {
      _authService.setError('Storage permission denied.');
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

      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        _authService.setError('Cannot access external storage.');
        return false;
      }

      // 3. Save to a temporary location
      filePath = '${directory.path}/${file.name}';
      final saveFile = File(filePath);
      await saveFile.writeAsBytes(response.bodyBytes);

      // In a real Flutter app, you'd use a package like image_gallery_saver
      // to save it directly to the native photo gallery. Since we removed
      // that dependency due to build errors, we'll just log success.
      print('File downloaded successfully to: $filePath');

      return true;
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
