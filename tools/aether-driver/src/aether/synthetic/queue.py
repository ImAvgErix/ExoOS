"""
Per-cursor inject queues — parallel agent slots without interleaving mid-action.
Each cursor has its own worker thread and serial queue.
"""
from __future__ import annotations
import queue
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional


@dataclass
class Job:
    fn: Callable
    args: tuple
    kwargs: dict
    result_box: list
    event: threading.Event


class CursorQueue:
    def __init__(self, cursor_id: str):
        self.cursor_id = cursor_id
        self._q: queue.Queue = queue.Queue()
        self._thread = threading.Thread(target=self._run, name=f"aether-cursor-{cursor_id}", daemon=True)
        self._alive = True
        self._thread.start()
        self.processed = 0

    def _run(self) -> None:
        while self._alive:
            try:
                job: Job = self._q.get(timeout=0.2)
            except queue.Empty:
                continue
            try:
                result = job.fn(*job.args, **job.kwargs)
                job.result_box.append(result)
            except Exception as e:
                job.result_box.append(e)
            finally:
                job.event.set()
                self.processed += 1
                self._q.task_done()

    def submit(self, fn: Callable, *args, timeout: float = 30.0, **kwargs) -> Any:
        box: list = []
        ev = threading.Event()
        self._q.put(Job(fn=fn, args=args, kwargs=kwargs, result_box=box, event=ev))
        if not ev.wait(timeout):
            raise TimeoutError(f"cursor queue {self.cursor_id} timeout")
        if not box:
            return None
        if isinstance(box[0], Exception):
            raise box[0]
        return box[0]

    def stop(self) -> None:
        self._alive = False


class QueueHub:
    def __init__(self):
        self._lock = threading.Lock()
        self._queues: Dict[str, CursorQueue] = {}

    def get(self, cursor_id: str = "main") -> CursorQueue:
        with self._lock:
            if cursor_id not in self._queues:
                self._queues[cursor_id] = CursorQueue(cursor_id)
            return self._queues[cursor_id]

    def stats(self) -> Dict[str, Any]:
        with self._lock:
            return {
                cid: {"processed": q.processed, "pending": q._q.qsize()}
                for cid, q in self._queues.items()
            }
