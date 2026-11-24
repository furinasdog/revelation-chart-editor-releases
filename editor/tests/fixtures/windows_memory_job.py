"""Run a local Windows test and its children under a 2 GiB commit limit."""
import ctypes as c
from ctypes import wintypes as w
import subprocess
import sys


class BasicLimits(c.Structure):
    _fields_ = [
        ("process_time", c.c_int64), ("job_time", c.c_int64), ("flags", w.DWORD),
        ("min_working_set", c.c_size_t), ("max_working_set", c.c_size_t), ("active_processes", w.DWORD),
        ("affinity", c.c_size_t), ("priority", w.DWORD), ("scheduling", w.DWORD),
    ]


class Counters(c.Structure):
    _fields_ = [(name, c.c_uint64) for name in (
        "reads", "writes", "other", "read_bytes", "written_bytes", "other_bytes")]


class ExtendedLimits(c.Structure):
    _fields_ = [
        ("basic", BasicLimits), ("io", Counters), ("process_limit", c.c_size_t),
        ("job_limit", c.c_size_t), ("peak_process", c.c_size_t), ("peak_job", c.c_size_t),
    ]


def main():
    kernel = c.WinDLL("kernel32", use_last_error=True)
    ntdll = c.WinDLL("ntdll")
    kernel.CreateJobObjectW.argtypes = (c.c_void_p, w.LPCWSTR)
    kernel.CreateJobObjectW.restype = w.HANDLE
    for name in ("SetInformationJobObject", "QueryInformationJobObject"):
        getattr(kernel, name).argtypes = (w.HANDLE, w.INT, c.c_void_p, w.DWORD) + (
            (c.POINTER(w.DWORD),) if name.startswith("Query") else ())
    kernel.AssignProcessToJobObject.argtypes = (w.HANDLE, w.HANDLE)
    kernel.CloseHandle.argtypes = (w.HANDLE,)
    ntdll.NtResumeProcess.argtypes = (w.HANDLE,)
    job = kernel.CreateJobObjectW(None, None)
    if not job:
        raise c.WinError(c.get_last_error())
    child = None
    try:
        limits = ExtendedLimits()
        limits.basic.flags = 0x200 | 0x2000  # JOB_MEMORY | KILL_ON_JOB_CLOSE
        limits.job_limit = 2 * 1024**3
        if not kernel.SetInformationJobObject(job, 9, c.byref(limits), c.sizeof(limits)):
            raise c.WinError(c.get_last_error())
        child = subprocess.Popen(sys.argv[1:], creationflags=4)  # CREATE_SUSPENDED
        if not kernel.AssignProcessToJobObject(job, int(child._handle)):
            raise c.WinError(c.get_last_error())
        if ntdll.NtResumeProcess(int(child._handle)):
            raise RuntimeError("Could not start the limited child.")
        result = child.wait(timeout=220)
        if not kernel.QueryInformationJobObject(job, 9, c.byref(limits), c.sizeof(limits), None):
            raise c.WinError(c.get_last_error())
        print(f"WINDOWS_JOB limit={limits.job_limit} peak_commit={limits.peak_job} exit={result}", flush=True)
        return result
    finally:
        if child is not None and child.poll() is None:
            child.kill()
        kernel.CloseHandle(job)


if __name__ == "__main__":
    raise SystemExit(main())
