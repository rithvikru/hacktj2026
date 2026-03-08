from __future__ import annotations

import logging
import multiprocessing as mp
import os
import threading
from concurrent.futures import Future, ProcessPoolExecutor

from serving.storage.room_store import RoomStore
from serving.workers.reconstruct_room import run_reconstruction_job

logger = logging.getLogger(__name__)

_executor: ProcessPoolExecutor | None = None
_lock = threading.RLock()
_inflight: dict[str, Future[None]] = {}


def enqueue_reconstruction(room_id: str) -> bool:
    with _lock:
        future = _inflight.get(room_id)
        if future is not None and not future.done():
            return False

        executor = _get_executor()
        future = executor.submit(run_reconstruction_job, room_id)
        _inflight[room_id] = future
        future.add_done_callback(lambda job_future, job_room_id=room_id: _finalize_job(job_room_id, job_future))
        return True


def shutdown_reconstruction_queue() -> None:
    global _executor
    with _lock:
        executor = _executor
        _executor = None
        _inflight.clear()
    if executor is not None:
        executor.shutdown(wait=False, cancel_futures=True)


def _get_executor() -> ProcessPoolExecutor:
    global _executor
    if _executor is None:
        max_workers = max(1, int(os.getenv("HACKTJ2026_RECON_WORKERS", "1")))
        start_method = os.getenv("HACKTJ2026_RECON_START_METHOD", "spawn")
        _executor = ProcessPoolExecutor(
            max_workers=max_workers,
            mp_context=mp.get_context(start_method),
        )
    return _executor


def _finalize_job(room_id: str, future: Future[None]) -> None:
    with _lock:
        _inflight.pop(room_id, None)

    exception = future.exception()
    if exception is None:
        return

    logger.exception("Reconstruction worker crashed for room %s", room_id, exc_info=exception)
    store = RoomStore()
    room = store.get(room_id)
    if room is not None:
        store.update(
            room_id,
            reconstruction_status="failed",
            reconstruction_assets={"error": str(exception)},
        )
