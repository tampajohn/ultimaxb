"""Process locks for an offline world operation or the complete runner lifetime."""
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import stat


class WorldBusy(RuntimeError):
    pass


@contextmanager
def file_lock(path):
    """Never unlink lock files: waiters must continue to refer to the same inode."""
    path = Path(path)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise ValueError('World lock must be a regular, unlinked file')
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise WorldBusy('World is running or another world operation holds its lock') from None
        yield
    finally:
        os.close(fd)


@contextmanager
def runner_lock(data):
    with file_lock(Path(data) / '.ultima-world.lock'):
        yield


@contextmanager
def offline_lock(data):
    """Also interlock with standalone processes started outside our runner."""
    data = Path(data)
    with runner_lock(data):
        with file_lock(data / 'spacetime.pid'):
            yield
