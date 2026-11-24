# file-manager-ios

[Fossify File Manager](https://github.com/FossifyOrg/File-Manager) re-created for iOS in SwiftUI, browsing the app's own folder ("Internal", also visible in the Files app) plus any folders added from other locations (iCloud Drive, On My iPhone, USB drives, file providers).

    idl build -c release     # -> build/release/FossifyFileManager.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyFileManager

Ported: files/recents/storage tabs with breadcrumbs, storage picker, home folder, favorites, recursive search, list/grid per folder with column count and pinch zoom, sorting per folder, hidden items; multi-select actions (delete, properties with hashes, rename/batch rename, share, hide/unhide, copy path, open with, open as, copy/move with conflict handling, compress/decompress zips); create file/folder; storage analysis by type with per-type file lists; text editor with search, save, save as, print and pinch zoom; zip browser; saving files shared to the app; colors, font size, date format, password protection and every applicable setting.

Differences forced by iOS: apps only reach their own folder and folders the user adds, so there is no device-wide storage, SD card/OTG or root access, and recents/storage analysis scan those folders; files open in QuickLook (text in the editor, zips in the zip browser) instead of another app's intent; no launcher shortcuts, "set as" wallpaper/ringtone, file picker/ringtone picker roles, "press back twice to exit" or in-app language switch; file type icons are SF Symbols; password-protected zips aren't supported (ZIPFoundation, the zip library used, has no encryption).

Zips use [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) 0.9 (MIT), vendored in `Sources/Vendor/ZIPFoundation`.

GPL-3.0, like the original.
