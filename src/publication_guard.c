/* Original, deliberately small Windows .Call guard. Owns no database state.
 * Read handles live in the parent R process until explicit close or finalizer.
 * A copier/helper exit cannot release these handles during SQL COMMIT. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#ifdef __TINYC__
/* TinyCC's compact SDK omits winnls.h. Win32's documented declaration. */
WINBASEAPI int WINAPI MultiByteToWideChar(UINT,DWORD,LPCCH,int,LPWSTR,int);
#define CP_UTF8 65001
#define MB_ERR_INVALID_CHARS 8
#else
#include <winnls.h>
#endif
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <Rconfig.h>
/* TinyCC's enum ABI is int; its parser predates the equivalent C23 spelling.
 * Do not modify installed R headers. No R structure layout is used here. */
#ifdef __TINYC__
#undef HAVE_ENUM_BASE_TYPE
/* Complex values are never passed, returned or accessed by this shim. */
#define R_LEGACY_RCOMPLEX
#endif
#include <Rinternals.h>
typedef char brohn_boolean_must_be_int[(sizeof(Rboolean) == sizeof(int)) ? 1 : -1];

#define GUARD_MAGIC 0x42524f48U
typedef struct {
  HANDLE handle;
  wchar_t *path;
  DWORD volume;
  uint64_t index;
  uint64_t bytes;
} GuardFile;
typedef struct { unsigned int magic; int count; GuardFile *files; } Guard;

static void release_guard(SEXP pointer) {
  Guard *guard = (Guard *) R_ExternalPtrAddr(pointer);
  int i;
  if (!guard) return;
  if (guard->magic != GUARD_MAGIC) return;
  for (i = 0; i < guard->count; ++i) {
    if (guard->files[i].handle && guard->files[i].handle != INVALID_HANDLE_VALUE)
      CloseHandle(guard->files[i].handle);
    free(guard->files[i].path);
  }
  free(guard->files); guard->magic = 0; free(guard);
  R_ClearExternalPtr(pointer);
}

static uint64_t decimal(const char *value, int *ok) {
  uint64_t result = 0; const unsigned char *p = (const unsigned char *) value;
  if (!*p) { *ok = 0; return 0; }
  for (; *p; ++p) {
    if (*p < '0' || *p > '9' || result > (UINT64_MAX - (*p - '0')) / 10) {
      *ok = 0; return 0;
    }
    result = result * 10 + (*p - '0');
  }
  return result;
}

static int matching(HANDLE handle, GuardFile *file) {
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(handle, &info)) return 0;
  if (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) return 0;
  return info.dwVolumeSerialNumber == file->volume &&
    (((uint64_t) info.nFileIndexHigh << 32) | info.nFileIndexLow) == file->index &&
    (((uint64_t) info.nFileSizeHigh << 32) | info.nFileSizeLow) == file->bytes;
}

static Guard *owned(SEXP pointer) {
  Guard *guard;
  if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != Rf_install("brohn-publication-native/1.0"))
    Rf_error("A parent-owned publication guard is required.");
  guard = (Guard *) R_ExternalPtrAddr(pointer);
  if (!guard || guard->magic != GUARD_MAGIC) Rf_error("The parent publication guard is closed.");
  return guard;
}

__declspec(dllexport) SEXP brohn_guard_open(SEXP paths, SEXP volumes, SEXP indexes, SEXP sizes) {
  int count, i;
  Guard *guard;
  SEXP pointer;
  if (TYPEOF(paths) != STRSXP || TYPEOF(volumes) != STRSXP || TYPEOF(indexes) != STRSXP || TYPEOF(sizes) != STRSXP)
    Rf_error("Native guard identities must be exact character vectors.");
  count = Rf_length(paths);
  if (count < 1 || count > 1024 || Rf_length(volumes) != count || Rf_length(indexes) != count || Rf_length(sizes) != count)
    Rf_error("Native guard identity counts differ or exceed their bound.");
  guard = (Guard *) calloc(1, sizeof(Guard));
  if (!guard) Rf_error("Cannot allocate publication guard.");
  guard->files = (GuardFile *) calloc(count, sizeof(GuardFile));
  if (!guard->files) { free(guard); Rf_error("Cannot allocate publication handles."); }
  guard->magic = GUARD_MAGIC; guard->count = count;
  pointer = PROTECT(R_MakeExternalPtr(guard, Rf_install("brohn-publication-native/1.0"), R_NilValue));
  R_RegisterCFinalizerEx(pointer, release_guard, TRUE);
  for (i = 0; i < count; ++i) {
    GuardFile *file = &guard->files[i];
    const char *path; int chars, ok = 1; uint64_t volume;
    if (STRING_ELT(paths, i) == NA_STRING || STRING_ELT(volumes, i) == NA_STRING ||
        STRING_ELT(indexes, i) == NA_STRING || STRING_ELT(sizes, i) == NA_STRING) {
      release_guard(pointer); Rf_error("Missing native publication identity.");
    }
    path = Rf_translateCharUTF8(STRING_ELT(paths, i));
    chars = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (chars < 2 || chars > 32768) { release_guard(pointer); Rf_error("Invalid native publication path."); }
    file->path = (wchar_t *) calloc(chars, sizeof(wchar_t));
    if (!file->path || !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, file->path, chars)) {
      release_guard(pointer); Rf_error("Cannot encode native publication path.");
    }
    volume = decimal(CHAR(STRING_ELT(volumes, i)), &ok);
    file->index = decimal(CHAR(STRING_ELT(indexes, i)), &ok);
    file->bytes = decimal(CHAR(STRING_ELT(sizes, i)), &ok);
    if (!ok || volume > UINT32_MAX || file->bytes > 4ULL * 1024 * 1024 * 1024) {
      release_guard(pointer); Rf_error("Invalid exact native publication identity.");
    }
    file->volume = (DWORD) volume;
    file->handle = CreateFileW(file->path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    if (file->handle == INVALID_HANDLE_VALUE || !matching(file->handle, file)) {
      release_guard(pointer); Rf_error("Cannot retain the verified file identity in the parent R process.");
    }
  }
  UNPROTECT(1); return pointer;
}

__declspec(dllexport) SEXP brohn_guard_check(SEXP pointer) {
  Guard *guard = owned(pointer); int i;
  for (i = 0; i < guard->count; ++i) {
    GuardFile *file = &guard->files[i];
    HANDLE current = CreateFileW(file->path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    int valid = current != INVALID_HANDLE_VALUE && matching(current, file) && matching(file->handle, file);
    if (current != INVALID_HANDLE_VALUE) CloseHandle(current);
    if (!valid) Rf_error("A parent-held publication path or identity changed.");
  }
  return Rf_ScalarLogical(1);
}

__declspec(dllexport) SEXP brohn_guard_close(SEXP pointer) {
  if (TYPEOF(pointer) != EXTPTRSXP || R_ExternalPtrTag(pointer) != Rf_install("brohn-publication-native/1.0"))
    Rf_error("An owned native publication pointer is required.");
  release_guard(pointer); return Rf_ScalarLogical(1);
}
