"""
Aether Smart Controller v1.1

Everything practical for higher accuracy + speed:
  - Cua a11y hands when available
  - Local OpenCV+OCR grounding
  - Observation cache (continuous perception)
  - UI memory of successful targets
  - smart_click / smart_type with verify + retry
  - smart_scroll / smart_drag / smart_hotkey
  - Batched actions (one observe, many acts)
  - Region-aware verification
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple, Union

from .perception import PerceptionEngine
from .backends import ActionBackend, CuaBackend, LocalBackend, get_best_backend, DeliveryResult
from .memory import UIMemory
from .safety import SafetyGate, SafetyConfig
from .clipboard import get_clipboard, set_clipboard
from .config import AetherConfig
from .actionlog import ActionLog
from .macros import MacroStore
from .annotate import annotate_to_base64

try:
    from .browser import BrowserEngineSync
    HAS_BROWSER = True
except ImportError:
    HAS_BROWSER = False


@dataclass
class Target:
    kind: str
    label: str
    bbox: Optional[List[int]] = None
    x: Optional[int] = None
    y: Optional[int] = None
    confidence: float = 0.5
    source: str = ""
    pid: Optional[int] = None
    window_id: Optional[int] = None
    element_index: Optional[int] = None
    meta: Dict[str, Any] = field(default_factory=dict)

    @property
    def center(self) -> Optional[Tuple[int, int]]:
        if self.x is not None and self.y is not None:
            return (self.x, self.y)
        if self.bbox and len(self.bbox) == 4:
            x1, y1, x2, y2 = self.bbox
            return ((x1 + x2) // 2, (y1 + y2) // 2)
        return None

    @property
    def is_a11y(self) -> bool:
        return self.kind == "a11y" and self.pid is not None and self.element_index is not None


@dataclass
class ActionOutcome:
    success: bool
    verified: bool
    message: str
    attempts: int = 1
    target: Optional[Target] = None
    pre_obs_id: Optional[str] = None
    post_obs_id: Optional[str] = None
    elapsed: float = 0.0
    backend: str = "local"
    from_memory: bool = False


def _score_match(query: str, text: str, base: float = 0.5) -> float:
    q = query.lower().strip()
    t = (text or "").lower().strip()
    if not q or not t:
        return 0.0
    if q == t:
        return min(1.0, base + 0.4)
    if q in t:
        return min(1.0, base + 0.25)
    if t in q:
        return min(1.0, base + 0.12)
    qt, tt = set(q.split()), set(t.split())
    if qt and tt:
        overlap = len(qt & tt) / max(len(qt), 1)
        if overlap >= 0.5:
            return min(1.0, base + 0.15 * overlap)
    return 0.0


def _parse_cua_tree(state: Dict[str, Any], pid: int, window_id: Optional[int]) -> List[Target]:
    targets: List[Target] = []
    elements = []
    if isinstance(state, dict):
        for key in ("elements", "tree", "nodes", "data", "accessibility"):
            val = state.get(key)
            if isinstance(val, list):
                elements = val
                break
    for i, el in enumerate(elements):
        if not isinstance(el, dict):
            continue
        idx = el.get("element_index", el.get("index", el.get("id", i)))
        try:
            idx = int(idx)
        except Exception:
            idx = i
        name = el.get("name") or el.get("title") or el.get("label") or el.get("value") or el.get("role") or ""
        role = el.get("role") or el.get("type") or ""
        label = f"{name}".strip() or f"{role}".strip() or f"element-{idx}"
        bbox = el.get("bbox") or el.get("bounds") or el.get("frame")
        if isinstance(bbox, dict):
            bbox = [
                int(bbox.get("x", bbox.get("left", 0))),
                int(bbox.get("y", bbox.get("top", 0))),
                int(bbox.get("x", 0) + bbox.get("width", 0)),
                int(bbox.get("y", 0) + bbox.get("height", 0)),
            ]
        actions = el.get("actions") or []
        conf = 0.55
        if any(a in str(actions).lower() for a in ("press", "click", "axpress")):
            conf = 0.7
        if role and any(r in str(role).lower() for r in ("button", "link", "textfield", "checkbox")):
            conf = max(conf, 0.65)
        t = Target(
            kind="a11y", label=label,
            bbox=bbox if isinstance(bbox, list) and len(bbox) == 4 else None,
            confidence=conf, source="cua-a11y",
            pid=pid, window_id=window_id, element_index=idx,
            meta={"role": role, "actions": actions},
        )
        if t.bbox and t.center:
            t.x, t.y = t.center
        targets.append(t)
    return targets


class SmartController:
    def __init__(
        self,
        prefer_cua: bool = False,
        max_retries: int = 3,
        verify: bool = True,
        similarity_threshold: float = 0.97,
        cache_ttl: float = 0.35,
    ):
        self.perception = PerceptionEngine(use_ocr=True)
        self.perception.set_cache_ttl(cache_ttl)
        self.prefer_cua = prefer_cua
        self.backend: ActionBackend = get_best_backend(prefer_cua=prefer_cua, prefer_synthetic=True)
        self.local_fallback = LocalBackend()
        self.max_retries = max_retries
        self.verify = verify
        self.similarity_threshold = similarity_threshold
        self.memory = UIMemory()
        self.safety = SafetyGate(SafetyConfig(
            max_actions_per_minute=90,
            max_clicks_per_minute=45,
        ))
        self._focus_pid: Optional[int] = None
        self._focus_window_id: Optional[int] = None
        self._browser = None
        self._metrics = {"clicks": 0, "types": 0, "batches": 0, "memory_hits": 0, "waits": 0, "fills": 0}
        self.log = ActionLog(enabled=True)
        self.macros = MacroStore()

    @property
    def backend_name(self) -> str:
        return self.backend.name

    def _get_browser(self):
        if not HAS_BROWSER:
            return None
        if self._browser is None:
            self._browser = BrowserEngineSync(headless=False)
            self._browser.start()
        return self._browser

    # ── Eyes ────────────────────────────────────────────────────────

    def observe(self, use_cache: bool = False, **kwargs) -> Dict[str, Any]:
        if use_cache:
            return self.perception.observe_cached(**kwargs)
        return self.perception.observe(**kwargs)

    def list_windows(self) -> List[Dict[str, Any]]:
        return self.backend.list_windows()

    def focus_window(self, pid: int, window_id: Optional[int] = None) -> Dict[str, Any]:
        self._focus_pid = pid
        self._focus_window_id = window_id
        state = {}
        if isinstance(self.backend, CuaBackend):
            state = self.backend.get_window_state(pid, window_id)
        return {"ok": True, "pid": pid, "window_id": window_id,
                "state_keys": list(state.keys()) if isinstance(state, dict) else []}

    def find_targets(
        self,
        query: str,
        obs: Optional[Dict] = None,
        min_confidence: float = 0.3,
        use_cua_a11y: bool = True,
        use_memory: bool = True,
    ) -> List[Target]:
        targets: List[Target] = []

        # Memory boost
        if use_memory:
            hit = self.memory.lookup(query, self._focus_pid)
            if hit:
                self._metrics["memory_hits"] += 1
                targets.append(Target(
                    kind=hit.kind or "memory",
                    label=hit.label,
                    bbox=hit.bbox,
                    x=hit.x, y=hit.y,
                    confidence=min(0.92, 0.55 + hit.score * 0.4),
                    source="memory",
                    pid=hit.pid, window_id=hit.window_id,
                    element_index=hit.element_index,
                ))

        if use_cua_a11y and self._focus_pid is not None and hasattr(self.backend, "get_window_state"):
            try:
                state = self.backend.get_window_state(self._focus_pid, self._focus_window_id)
                for t in _parse_cua_tree(state, self._focus_pid, self._focus_window_id):
                    # tag source with backend
                    t.source = f"{self.backend.name}-a11y"
                    t.kind = "a11y"
                    score = _score_match(query, t.label, base=t.confidence)
                    if score >= min_confidence:
                        t.confidence = score
                        targets.append(t)
            except Exception:
                pass

        if obs is None:
            obs = self.observe(modes=["ocr", "vision"], include_image=False, use_cache=True)

        for item in obs.get("vision", {}).get("ocr", []):
            text = (item.get("text") or "").strip()
            conf = float(item.get("confidence", 0.5))
            score = _score_match(query, text, base=conf)
            if score < min_confidence:
                continue
            bbox = item.get("bbox")
            t = Target(kind="ocr", label=text, bbox=bbox, confidence=score, source="ocr", meta=item)
            if t.center:
                t.x, t.y = t.center
            targets.append(t)

        for el in obs.get("vision", {}).get("elements", []):
            label = (el.get("label") or "").strip()
            conf = float(el.get("confidence", 0.5))
            source = el.get("source") or "vision"
            if source == "fused":
                conf = min(1.0, conf + 0.05)
            score = _score_match(query, label, base=conf)
            if score < min_confidence:
                continue
            if label in ("button", "input", "icon", "region") and query.strip():
                if query.lower() not in label and label not in query.lower():
                    continue
            bbox = el.get("bbox")
            t = Target(kind="element", label=label, bbox=bbox, confidence=score, source=source, meta=el)
            if t.center:
                t.x, t.y = t.center
            targets.append(t)

        targets.sort(key=lambda t: (t.confidence + (0.1 if t.is_a11y else 0) + (0.06 if t.source == "memory" else 0)), reverse=True)
        # de-dupe by approximate center
        seen = set()
        uniq = []
        for t in targets:
            c = t.center or (-1, -1)
            key = (c[0] // 8, c[1] // 8, (t.label or "")[:24])
            if key in seen:
                continue
            seen.add(key)
            uniq.append(t)
        return uniq

    # ── Delivery ────────────────────────────────────────────────────

    def _deliver_click(self, target: Optional[Target] = None, x: Optional[int] = None,
                       y: Optional[int] = None, button: str = "left") -> DeliveryResult:
        if target and target.is_a11y and target.element_index is not None and hasattr(self.backend, "click"):
            res = self.backend.click(pid=target.pid, window_id=target.window_id,
                                     element_index=target.element_index, button=button)
            if res.ok:
                return res
        cx, cy = x, y
        if target and target.center:
            cx, cy = target.center
        if cx is None or cy is None:
            return DeliveryResult(False, self.backend.name, "no coordinates")
        res = self.backend.click(
            x=int(cx), y=int(cy), button=button,
            pid=getattr(target, "pid", None) if target else self._focus_pid,
            window_id=getattr(target, "window_id", None) if target else self._focus_window_id,
        )
        if res.ok:
            return res
        if self.backend.name != "local":
            return self.local_fallback.click(x=int(cx), y=int(cy), button=button)
        return res

    def _deliver_type(self, text: str, clear: bool = False, target: Optional[Target] = None) -> DeliveryResult:
        kwargs: Dict[str, Any] = {"clear": clear}
        if target and target.is_a11y:
            kwargs.update(pid=target.pid, window_id=target.window_id, element_index=target.element_index)
        elif self._focus_pid is not None:
            kwargs.update(pid=self._focus_pid, window_id=self._focus_window_id)
        res = self.backend.type_text(text, **kwargs)
        if res.ok:
            return res
        if self.backend.name != "local":
            return self.local_fallback.type_text(text, clear=clear)
        return res

    def _verify_change(self, pre: Dict, post: Dict) -> bool:
        diff = post.get("diff") or {}
        if not diff or diff.get("available") is False:
            return True
        sim = diff.get("similarity")
        if sim is None:
            return True
        return float(sim) < self.similarity_threshold

    # ── Smart actions ───────────────────────────────────────────────

    def smart_click(self, query: Optional[str] = None, x: Optional[int] = None,
                    y: Optional[int] = None, button: str = "left",
                    require_change: bool = False) -> ActionOutcome:
        t0 = time.time()
        ok_s, why = self.safety.check("click", text=query or "")
        if not ok_s:
            return ActionOutcome(False, False, why, elapsed=0.0, backend=self.backend_name)
        self._metrics["clicks"] += 1
        pre = self.observe(modes=["ocr", "vision", "diff"], include_image=False, use_cache=False)
        pre_id = pre.get("obs_id")
        targets: List[Target] = []
        if query:
            targets = self.find_targets(query, obs=pre)
        if x is not None and y is not None:
            targets.append(Target(kind="coords", label=f"({x},{y})", x=x, y=y, confidence=0.55, source="coords"))
        if not targets:
            if query:
                self.memory.record_failure(query, self._focus_pid)
            return ActionOutcome(False, False, f"No targets for {query!r}",
                                 elapsed=time.time()-t0, backend=self.backend_name)

        last_msg = ""
        for attempt, target in enumerate(targets[: self.max_retries + 1], start=1):
            delivery = self._deliver_click(target=target, button=button)
            time.sleep(0.18)
            post = self.observe(modes=["diff", "ocr"], include_image=False, use_cache=False)
            post_id = post.get("obs_id")
            changed = self._verify_change(pre, post) if self.verify else True
            if delivery.ok and (not self.verify or changed or not require_change):
                if query:
                    self.memory.record_success(query, target)
                self.log.record("click", query=query, label=target.label, backend=delivery.backend, success=True)
                if self.macros.is_recording():
                    self.macros.add("click", query=query)
                how = f"a11y#{target.element_index}" if target.is_a11y else f"({target.x},{target.y})"
                return ActionOutcome(
                    True, bool(changed),
                    f"Clicked '{target.label}' via {how} conf={target.confidence:.2f}",
                    attempts=attempt, target=target, pre_obs_id=pre_id, post_obs_id=post_id,
                    elapsed=time.time()-t0, backend=delivery.backend,
                    from_memory=(target.source == "memory"),
                )
            last_msg = f"Attempt {attempt} '{target.label}' ok={delivery.ok} changed={changed}"
            pre = post
        if query:
            self.memory.record_failure(query, self._focus_pid)
        return ActionOutcome(False, False, last_msg or "all attempts failed",
                             attempts=min(len(targets), self.max_retries+1),
                             pre_obs_id=pre_id, elapsed=time.time()-t0, backend=self.backend_name)

    def smart_type(self, text: str, query: Optional[str] = None, clear: bool = False) -> ActionOutcome:
        t0 = time.time()
        self._metrics["types"] += 1
        focus_target = None
        if query:
            click_out = self.smart_click(query=query, require_change=False)
            if not click_out.success:
                return ActionOutcome(False, False, f"Focus failed for '{query}': {click_out.message}",
                                     elapsed=time.time()-t0, backend=self.backend_name)
            focus_target = click_out.target
            time.sleep(0.1)
        pre = self.observe(modes=["diff"], include_image=False, use_cache=False)
        delivery = self._deliver_type(text, clear=clear, target=focus_target)
        time.sleep(0.12)
        post = self.observe(modes=["diff"], include_image=False, use_cache=False)
        changed = self._verify_change(pre, post) if self.verify else True
        return ActionOutcome(delivery.ok, changed, f"Typed {len(text)} chars ({delivery.backend})",
                             attempts=1, target=focus_target,
                             pre_obs_id=pre.get("obs_id"), post_obs_id=post.get("obs_id"),
                             elapsed=time.time()-t0, backend=delivery.backend)

    def smart_scroll(self, dy: int = 600, dx: int = 0, query: Optional[str] = None) -> ActionOutcome:
        t0 = time.time()
        if query:
            self.smart_click(query=query, require_change=False)
            time.sleep(0.1)
        pre = self.observe(modes=["diff"], include_image=False, use_cache=False)
        # Prefer local for scroll (universal)
        try:
            r = self.local_fallback.engine.scroll(dx=dx, dy=dy)
            ok = getattr(r, "success", True)
        except Exception as e:
            return ActionOutcome(False, False, str(e), elapsed=time.time()-t0, backend="local")
        time.sleep(0.15)
        post = self.observe(modes=["diff"], include_image=False, use_cache=False)
        changed = self._verify_change(pre, post)
        return ActionOutcome(ok, changed, f"Scrolled dx={dx} dy={dy}", elapsed=time.time()-t0, backend="local")

    def smart_drag(self, start_query: Optional[str] = None, end_query: Optional[str] = None,
                   start: Optional[List[int]] = None, end: Optional[List[int]] = None,
                   duration: float = 0.35) -> ActionOutcome:
        t0 = time.time()
        sxy = start
        exy = end
        if start_query:
            ts = self.find_targets(start_query)
            if not ts or not ts[0].center:
                return ActionOutcome(False, False, f"No start target for {start_query!r}",
                                     elapsed=time.time()-t0, backend=self.backend_name)
            sxy = list(ts[0].center)
        if end_query:
            te = self.find_targets(end_query)
            if not te or not te[0].center:
                return ActionOutcome(False, False, f"No end target for {end_query!r}",
                                     elapsed=time.time()-t0, backend=self.backend_name)
            exy = list(te[0].center)
        if not sxy or not exy or len(sxy) < 2 or len(exy) < 2:
            return ActionOutcome(False, False, "Need start and end", elapsed=time.time()-t0, backend=self.backend_name)
        pre = self.observe(modes=["diff"], include_image=False, use_cache=False)
        try:
            r = self.local_fallback.engine.drag((int(sxy[0]), int(sxy[1])), (int(exy[0]), int(exy[1])), duration=duration)
            ok = getattr(r, "success", True)
        except Exception as e:
            return ActionOutcome(False, False, str(e), elapsed=time.time()-t0, backend="local")
        time.sleep(0.15)
        post = self.observe(modes=["diff"], include_image=False, use_cache=False)
        changed = self._verify_change(pre, post)
        return ActionOutcome(ok, changed, f"Dragged {sxy} → {exy}", elapsed=time.time()-t0, backend="local")

    def smart_hotkey(self, keys: List[str]) -> ActionOutcome:
        t0 = time.time()
        r = self.backend.hotkey(keys) if hasattr(self.backend, "hotkey") else self.local_fallback.hotkey(keys)
        if not r.ok and self.backend.name != "local":
            r = self.local_fallback.hotkey(keys)
        return ActionOutcome(r.ok, True, r.message or f"hotkey {keys}", elapsed=time.time()-t0, backend=r.backend)

    def batch(self, actions: List[Dict[str, Any]], stop_on_failure: bool = True) -> Dict[str, Any]:
        """
        Execute a list of actions quickly.
        Each action: {"op": "click"|"type"|"scroll"|"hotkey"|"wait", ...params}
        Shares memory and avoids redundant full observes when possible.
        """
        t0 = time.time()
        self._metrics["batches"] += 1
        results = []
        for i, act in enumerate(actions):
            op = (act.get("op") or act.get("action") or "").lower()
            try:
                if op == "click":
                    out = self.smart_click(
                        query=act.get("query"), x=act.get("x"), y=act.get("y"),
                        button=act.get("button", "left"),
                        require_change=act.get("require_change", False),
                    )
                elif op == "type":
                    out = self.smart_type(text=act.get("text", ""), query=act.get("query"), clear=act.get("clear", False))
                elif op == "scroll":
                    out = self.smart_scroll(dy=act.get("dy", 600), dx=act.get("dx", 0), query=act.get("query"))
                elif op == "hotkey":
                    out = self.smart_hotkey(act.get("keys") or [])
                elif op == "drag":
                    out = self.smart_drag(
                        start_query=act.get("start_query"), end_query=act.get("end_query"),
                        start=act.get("start"), end=act.get("end"),
                        duration=act.get("duration", 0.35),
                    )
                elif op == "wait":
                    time.sleep(float(act.get("seconds", 0.5)))
                    out = ActionOutcome(True, True, f"waited {act.get('seconds', 0.5)}s", backend=self.backend_name)
                elif op == "observe":
                    obs = self.observe(include_image=act.get("include_image", False))
                    results.append({"index": i, "op": op, "success": True, "obs_id": obs.get("obs_id")})
                    continue
                else:
                    out = ActionOutcome(False, False, f"unknown op {op}", backend=self.backend_name)
                entry = {
                    "index": i, "op": op, "success": out.success, "verified": out.verified,
                    "message": out.message, "backend": out.backend, "elapsed": round(out.elapsed, 3),
                }
                results.append(entry)
                if stop_on_failure and not out.success:
                    break
            except Exception as e:
                results.append({"index": i, "op": op, "success": False, "message": str(e)})
                if stop_on_failure:
                    break
        ok = all(r.get("success") for r in results) if results else False
        return {"ok": ok, "count": len(results), "elapsed": round(time.time() - t0, 3), "results": results}

    def do(self, goal: str, max_steps: int = 8) -> Dict[str, Any]:
        history = []
        for step in range(max_steps):
            out = self.smart_click(query=goal, require_change=False)
            history.append({"step": step, "success": out.success, "message": out.message, "backend": out.backend})
            if out.success:
                return {"ok": True, "steps": history, "final": out.message}
            if "No targets" in out.message:
                break
        return {"ok": False, "steps": history, "final": "exhausted"}

    def wait_until(
        self,
        query: Optional[str] = None,
        text_contains: Optional[str] = None,
        timeout: float = 15.0,
        poll: float = 0.45,
    ) -> ActionOutcome:
        """Wait until a target appears (OCR/grounding) or text is visible."""
        t0 = time.time()
        self._metrics["waits"] += 1
        needle = (text_contains or query or "").strip()
        if not needle:
            return ActionOutcome(False, False, "need query or text_contains", elapsed=0, backend=self.backend_name)
        while time.time() - t0 < timeout:
            obs = self.observe(modes=["ocr", "vision"], include_image=False, use_cache=False)
            targets = self.find_targets(needle, obs=obs, use_memory=False)
            if targets and targets[0].confidence >= 0.4:
                return ActionOutcome(
                    True, True,
                    f"Found '{targets[0].label}' conf={targets[0].confidence:.2f}",
                    target=targets[0], elapsed=time.time() - t0, backend=self.backend_name,
                )
            # also scan raw OCR join
            ocr_text = " ".join(
                (i.get("text") or "") for i in obs.get("vision", {}).get("ocr", [])
            ).lower()
            if needle.lower() in ocr_text:
                return ActionOutcome(True, True, f"Text visible: {needle}", elapsed=time.time() - t0, backend=self.backend_name)
            time.sleep(poll)
        return ActionOutcome(False, False, f"Timeout waiting for '{needle}'", elapsed=time.time() - t0, backend=self.backend_name)

    def smart_fill(self, fields: Dict[str, str], submit: Optional[str] = None, clear: bool = True) -> Dict[str, Any]:
        """
        Fill a form: fields = {"Email": "a@b.com", "Password": "x"}.
        Optionally click submit query after.
        """
        t0 = time.time()
        self._metrics["fills"] += 1
        results = []
        for label, value in fields.items():
            out = self.smart_type(text=str(value), query=str(label), clear=clear)
            results.append({"field": label, "success": out.success, "message": out.message, "elapsed": round(out.elapsed, 3)})
            if not out.success:
                return {"ok": False, "results": results, "elapsed": round(time.time() - t0, 3)}
            time.sleep(0.08)
        if submit:
            out = self.smart_click(query=submit)
            results.append({"field": f"submit:{submit}", "success": out.success, "message": out.message})
            return {"ok": out.success, "results": results, "elapsed": round(time.time() - t0, 3)}
        return {"ok": True, "results": results, "elapsed": round(time.time() - t0, 3)}

    def clipboard_get(self) -> Dict[str, Any]:
        ok, val = get_clipboard()
        return {"ok": ok, "text": val if ok else "", "error": None if ok else val}

    def clipboard_set(self, text: str) -> Dict[str, Any]:
        ok, msg = set_clipboard(text)
        return {"ok": ok, "message": msg}

    def kill_switch(self, armed: bool = True) -> Dict[str, Any]:
        if armed:
            self.safety.arm_kill_switch()
        else:
            self.safety.disarm_kill_switch()
        return {"kill_switch": self.safety.config.kill_switch}


    def observe_annotated(self, max_labels: int = 30, max_image_side: int = 1280) -> Dict[str, Any]:
        """Observe and return screenshot with grounded boxes drawn (debug eyes)."""
        obs = self.observe(modes=["vision", "ocr"], include_image=True, max_image_side=max_image_side, use_cache=False)
        elements = obs.get("vision", {}).get("elements", []) or []
        # Try to annotate from raw if available; else return elements only
        annotated = None
        try:
            # re-capture for pixels
            img = self.perception._capture(monitor=1)
            if img is not None:
                annotated = annotate_to_base64(img, elements, quality=65)
        except Exception:
            annotated = None
        return {
            "obs_id": obs.get("obs_id"),
            "elements": elements[:max_labels],
            "annotated_screenshot_base64": annotated,
            "element_count": len(elements),
        }

    def recent_actions(self, n: int = 20) -> List[Dict[str, Any]]:
        return self.log.tail(n)


    def smart_focus(self, title: Optional[str] = None, pid: Optional[int] = None) -> Dict[str, Any]:
        """Focus a window by title substring or pid; sets a11y context for subsequent clicks."""
        windows = self.list_windows()
        match = None
        if pid is not None:
            for w in windows:
                if int(w.get("pid") or w.get("handle") or -1) == int(pid) or int(w.get("pid") or -1) == int(pid):
                    match = w
                    break
        if match is None and title:
            t = title.lower()
            for w in windows:
                wt = str(w.get("title") or w.get("name") or "").lower()
                if t in wt:
                    match = w
                    break
        if match is None:
            return {"ok": False, "error": "window not found", "windows": windows[:12]}
        wpid = match.get("pid") or match.get("process_id")
        wid = match.get("window_id") or match.get("handle")
        try:
            wpid = int(wpid) if wpid is not None else None
        except Exception:
            wpid = None
        try:
            wid = int(wid) if wid is not None else None
        except Exception:
            wid = None
        if wpid is not None:
            self.focus_window(wpid, wid)
        # Try raise via hotkey/backend best-effort
        try:
            if hasattr(self.local_fallback, "engine") and self.local_fallback.engine:
                # alt-tab is unreliable; just set focus context
                pass
        except Exception:
            pass
        if self.macros.is_recording():
            self.macros.add("focus", title=title, pid=wpid, window_id=wid)
        return {"ok": True, "pid": wpid, "window_id": wid, "title": match.get("title") or match.get("name")}

    def wait_gone(self, query: str, timeout: float = 15.0, poll: float = 0.45) -> ActionOutcome:
        """Wait until a target/text disappears from the screen."""
        t0 = time.time()
        self._metrics["waits"] = self._metrics.get("waits", 0) + 1
        while time.time() - t0 < timeout:
            obs = self.observe(modes=["ocr", "vision"], include_image=False, use_cache=False)
            targets = self.find_targets(query, obs=obs, use_memory=False)
            ocr_text = " ".join((i.get("text") or "") for i in obs.get("vision", {}).get("ocr", [])).lower()
            still = (targets and targets[0].confidence >= 0.45) or (query.lower() in ocr_text)
            if not still:
                return ActionOutcome(True, True, f"Gone: {query}", elapsed=time.time() - t0, backend=self.backend_name)
            time.sleep(poll)
        return ActionOutcome(False, False, f"Still present: {query}", elapsed=time.time() - t0, backend=self.backend_name)

    def wait_change(self, timeout: float = 10.0, poll: float = 0.35, threshold: Optional[float] = None) -> ActionOutcome:
        """Wait until the screen changes vs the current frame."""
        t0 = time.time()
        thr = threshold if threshold is not None else self.similarity_threshold
        pre = self.observe(modes=["diff"], include_image=False, use_cache=False)
        while time.time() - t0 < timeout:
            time.sleep(poll)
            post = self.observe(modes=["diff"], include_image=False, use_cache=False)
            if self._verify_change(pre, post):
                return ActionOutcome(True, True, "Screen changed", elapsed=time.time() - t0, backend=self.backend_name)
        return ActionOutcome(False, False, "No change detected", elapsed=time.time() - t0, backend=self.backend_name)

    def compact_observe(self, include_ocr: bool = True, max_ocr: int = 40, max_elements: int = 30) -> Dict[str, Any]:
        """Token-efficient observation for LLM agents (no big screenshot by default)."""
        modes = ["vision"]
        if include_ocr:
            modes.append("ocr")
        obs = self.observe(modes=modes, include_image=False, use_cache=False)
        ocr = (obs.get("vision") or {}).get("ocr") or []
        els = (obs.get("vision") or {}).get("elements") or []
        return {
            "obs_id": obs.get("obs_id"),
            "backend": self.backend_name,
            "focus_pid": self._focus_pid,
            "ocr": [{"text": i.get("text"), "conf": i.get("confidence"), "bbox": i.get("bbox")} for i in ocr[:max_ocr]],
            "elements": [
                {"label": e.get("label"), "kind": e.get("kind"), "conf": e.get("confidence"),
                 "bbox": e.get("bbox"), "source": e.get("source")}
                for e in els[:max_elements]
            ],
            "ocr_count": len(ocr),
            "element_count": len(els),
        }

    def macro_start(self) -> Dict[str, Any]:
        self.macros.start()
        return {"ok": True, "recording": True}

    def macro_stop(self, save_as: Optional[str] = None) -> Dict[str, Any]:
        actions = self.macros.stop()
        path = None
        if save_as:
            path = str(self.macros.save(save_as, actions))
        return {"ok": True, "count": len(actions), "actions": actions, "saved": path}

    def macro_play(self, name: str, stop_on_failure: bool = True) -> Dict[str, Any]:
        actions = self.macros.load(name)
        # Map focus ops
        mapped = []
        for a in actions:
            op = a.get("op")
            if op == "focus":
                self.smart_focus(title=a.get("title"), pid=a.get("pid"))
                mapped.append({"op": "wait", "seconds": 0.2})
            else:
                mapped.append(a)
        return self.batch(mapped, stop_on_failure=stop_on_failure)

    def macro_list(self) -> List[str]:
        return self.macros.list()


    def list_cursors(self) -> List[Dict[str, Any]]:
        if hasattr(self.backend, "list_cursors"):
            return self.backend.list_cursors()
        return []

    def create_cursor(self, cursor_id: str) -> Dict[str, Any]:
        if hasattr(self.backend, "create_cursor"):
            return self.backend.create_cursor(cursor_id)
        return {"ok": False, "error": "backend does not support multi-cursor"}

    def queue_stats(self) -> Dict[str, Any]:
        if hasattr(self.backend, "queue_stats"):
            return self.backend.queue_stats()
        return {}


    def status(self) -> Dict[str, Any]:
        cua_ok = isinstance(self.backend, CuaBackend)
        return {
            "version": "1.1.0",
            "backend": self.backend_name,
            "backend_class": type(self.backend).__name__,
            "cua_active": cua_ok,
            "verify": self.verify,
            "max_retries": self.max_retries,
            "focus_pid": self._focus_pid,
            "focus_window_id": self._focus_window_id,
            "browser": HAS_BROWSER,
            "memory": self.memory.stats(),
            "safety": self.safety.stats(),
            "macro_recording": self.macros.is_recording(),
            "queues": self.queue_stats() if hasattr(self, "queue_stats") else {},
            "macros": self.macros.list(),
            "metrics": dict(self._metrics),
            "cache_ttl": getattr(self.perception, "_obs_cache_ttl", None),
            "capabilities": {
                "a11y_element_clicks": cua_ok,
                "background_hands": cua_ok,
                "local_ui_grounding": True,
                "ocr_grounding": True,
                "frame_diff_verify": True,
                "auto_retry": True,
                "ui_memory": True,
                "observation_cache": True,
                "batch_actions": True,
                "wait_until": True,
                "smart_fill": True,
                "clipboard": True,
                "kill_switch": True,
                "pywinauto_windows": True,
                "action_log": True,
                "observe_annotated": True,
                "cdp_attach": True,
                "smart_focus": True,
                "wait_gone": True,
                "wait_change": True,
                "compact_observe": True,
                "macros": True,
                "synthetic_hands": True,
                "virtual_cursors": True,
                "uia_invoke": True,
                "ax_mac": True,
                "parallel_cursor_queues": True,
                "smart_scroll_drag": True,
                "windows_browser_spaces": HAS_BROWSER,
            },
        }
