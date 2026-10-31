import 'dart:ffi';

final _kernel = DynamicLibrary.open('kernel32.dll');
final _allocate = _kernel
    .lookupFunction<
      Pointer<Void> Function(Uint32, UintPtr),
      Pointer<Void> Function(int, int)
    >('LocalAlloc');
final _free = _kernel
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('LocalFree');
final _getMemory = DynamicLibrary.open('psapi.dll')
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, int)
    >('GetProcessMemoryInfo');

/// Private committed bytes, including allocations not resident in the working
/// set reported by ProcessInfo.currentRss. Windows desktop targets are 64-bit.
class WindowsProcessMemory {
  // PROCESS_MEMORY_COUNTERS_EX: two DWORDs followed by nine SIZE_T fields.
  final Pointer<Void> _counters = _allocate(0, 80);

  int get privateBytes => _readCounter(9);

  int get peakCommitBytes => _readCounter(8);

  int _readCounter(int index) {
    if (_getMemory(-1, _counters, 80) == 0) {
      throw StateError('GetProcessMemoryInfo failed');
    }
    return _counters.cast<Uint64>()[index];
  }

  void dispose() => _free(_counters);
}
