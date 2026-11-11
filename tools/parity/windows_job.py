"""Own a Windows test's descendants without touching unrelated processes."""
import ctypes
from ctypes import wintypes
import time


class WindowsJob:
    def __init__(self, process):
        class Basic(ctypes.Structure):
            _fields_ = [("process_time", ctypes.c_int64), ("job_time", ctypes.c_int64),
                        ("flags", wintypes.DWORD), ("minimum", ctypes.c_size_t),
                        ("maximum", ctypes.c_size_t), ("active", wintypes.DWORD),
                        ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD),
                        ("scheduling", wintypes.DWORD)]

        class IO(ctypes.Structure):
            _fields_ = [(name, ctypes.c_uint64) for name in
                        ("read_ops", "write_ops", "other_ops", "read_bytes", "write_bytes", "other_bytes")]

        class Extended(ctypes.Structure):
            _fields_ = [("basic", Basic), ("io", IO), ("process_memory", ctypes.c_size_t),
                        ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t),
                        ("peak_job", ctypes.c_size_t)]

        self.api = ctypes.WinDLL("kernel32", use_last_error=True)
        self.api.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        self.api.CreateJobObjectW.restype = wintypes.HANDLE
        self.api.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        self.api.SetInformationJobObject.restype = wintypes.BOOL
        self.api.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        self.api.AssignProcessToJobObject.restype = wintypes.BOOL
        self.api.QueryInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.c_void_p]
        self.api.QueryInformationJobObject.restype = wintypes.BOOL
        self.api.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self.api.OpenProcess.restype = wintypes.HANDLE
        self.api.IsProcessInJob.argtypes = [wintypes.HANDLE, wintypes.HANDLE, ctypes.POINTER(wintypes.BOOL)]
        self.api.IsProcessInJob.restype = wintypes.BOOL
        self.api.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
        self.api.TerminateProcess.restype = wintypes.BOOL
        self.api.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        self.api.WaitForSingleObject.restype = wintypes.DWORD
        self.api.CloseHandle.argtypes = [wintypes.HANDLE]
        self.api.CloseHandle.restype = wintypes.BOOL
        self.handle = self.api.CreateJobObjectW(None, None)
        if not self.handle:
            raise ctypes.WinError(ctypes.get_last_error())
        try:
            info = Extended()
            info.basic.flags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if not self.api.SetInformationJobObject(self.handle, 9, ctypes.byref(info), ctypes.sizeof(info)):
                raise ctypes.WinError(ctypes.get_last_error())
            if not self.api.AssignProcessToJobObject(self.handle, wintypes.HANDLE(int(process._handle))):
                # A very short command may finish before assignment. It has no
                # live process to own; long-running test commands must be owned.
                if process.poll() is None:
                    raise ctypes.WinError(ctypes.get_last_error())
        except BaseException:
            self.close()
            raise

    def _process_ids(self, deadline):
        capacity = 64
        while True:
            class Members(ctypes.Structure):
                _fields_ = [("assigned", wintypes.DWORD), ("count", wintypes.DWORD),
                            ("pids", ctypes.c_size_t * capacity)]
            info = Members()
            ok = self.api.QueryInformationJobObject(self.handle, 3, ctypes.byref(info), ctypes.sizeof(info), None)
            if ok and info.count == info.assigned:
                return list(info.pids[:info.count])
            if not ok and ctypes.get_last_error() != 234:  # ERROR_MORE_DATA
                raise ctypes.WinError(ctypes.get_last_error())
            if time.monotonic() >= deadline:
                raise TimeoutError("Windows test job membership did not settle")
            capacity = max(capacity * 2, info.assigned)

    def terminate(self, timeout=5.0):
        """Stop and join every owned member before its inherited log can be reused.

        TerminateJobObject removes members from its PID list before their
        termination is complete. Pin each member handle and terminate/wait it
        individually instead, then enumerate again for children created during
        shutdown. Keep KILL_ON_JOB_CLOSE as containment if any API/wait fails.
        """
        deadline = time.monotonic() + timeout
        while True:
            pids = self._process_ids(deadline)
            if not pids:
                return
            if time.monotonic() >= deadline:
                raise TimeoutError("Windows test job processes did not terminate")
            handles = []
            try:
                for pid in pids:
                    handle = self.api.OpenProcess(0x101001, False, pid)  # SYNCHRONIZE | QUERY_LIMITED_INFORMATION | TERMINATE
                    if not handle:
                        if ctypes.get_last_error() == 87:  # exited before OpenProcess
                            continue
                        raise ctypes.WinError(ctypes.get_last_error())
                    handles.append(handle)
                    owned = wintypes.BOOL()
                    if not self.api.IsProcessInJob(handle, self.handle, ctypes.byref(owned)):
                        raise ctypes.WinError(ctypes.get_last_error())
                    if not owned.value:  # PID was reused outside this job
                        self.api.CloseHandle(handles.pop())
                for handle in handles:
                    state = self.api.WaitForSingleObject(handle, 0)
                    if state == 0:
                        continue
                    if state != 258:
                        raise ctypes.WinError(ctypes.get_last_error())
                    if not self.api.TerminateProcess(handle, 1):
                        error = ctypes.get_last_error()
                        # ERROR_ACCESS_DENIED can accompany a process that
                        # is exiting, but it is not proof of completion. Wait
                        # only this pinned owned handle within the SAME budget.
                        wait_state = self.api.WaitForSingleObject(handle, 0)
                        if error == 5 and wait_state == 258:  # WAIT_TIMEOUT only
                            wait_ms = max(0, int((deadline - time.monotonic()) * 1000))
                            wait_state = self.api.WaitForSingleObject(handle, wait_ms)
                        if wait_state != 0:  # WAIT_OBJECT_0 is completion proof
                            raise ctypes.WinError(error)
                for handle in handles:
                    remaining = max(0, int((deadline - time.monotonic()) * 1000))
                    state = self.api.WaitForSingleObject(handle, remaining)
                    if state == 258:  # WAIT_TIMEOUT: cleanup is not complete
                        raise TimeoutError("Windows test job process did not terminate")
                    if state != 0:
                        raise ctypes.WinError(ctypes.get_last_error())
            finally:
                for handle in handles:
                    self.api.CloseHandle(handle)

    def close(self):
        if self.handle:
            try:
                self.terminate()
            finally:
                self.api.CloseHandle(self.handle)
                self.handle = None
