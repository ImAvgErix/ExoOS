"""
Windows accessibility backend via pywinauto (no Cua required).

Install: pip install pywinauto
Gives real UIA element listing + click/type by automation element on Windows.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional
from .backends import ActionBackend, DeliveryResult


class PywinautoBackend(ActionBackend):
    name = "pywinauto"

    def __init__(self):
        self._desktop = None
        self._ready = False
        try:
            from pywinauto import Desktop
            self._desktop = Desktop(backend="uia")
            self._ready = True
        except Exception:
            self._ready = False

    def available(self) -> bool:
        return self._ready

    def list_windows(self) -> List[Dict[str, Any]]:
        if not self._ready:
            return []
        out = []
        try:
            for w in self._desktop.windows():
                try:
                    out.append({
                        "title": w.window_text(),
                        "handle": int(w.handle),
                        "pid": int(w.process_id()),
                        "class_name": w.class_name(),
                        "visible": bool(w.is_visible()),
                    })
                except Exception:
                    continue
        except Exception:
            pass
        return out

    def get_window_state(self, pid: int, window_id: Optional[int] = None) -> Dict[str, Any]:
        if not self._ready:
            return {"ok": False, "error": "pywinauto not available"}
        elements = []
        try:
            from pywinauto import Desktop
            targets = []
            for w in self._desktop.windows():
                try:
                    if int(w.process_id()) != int(pid):
                        continue
                    if window_id is not None and int(w.handle) != int(window_id):
                        continue
                    targets.append(w)
                except Exception:
                    continue
            if not targets:
                return {"ok": False, "error": f"no window for pid={pid}", "elements": []}
            root = targets[0]
            # Walk descendants (bounded)
            try:
                desc = root.descendants()
            except Exception:
                desc = []
            for i, el in enumerate(desc[:120]):
                try:
                    name = ""
                    try:
                        name = el.window_text() or ""
                    except Exception:
                        pass
                    ctrl = ""
                    try:
                        ctrl = el.element_info.control_type or ""
                    except Exception:
                        try:
                            ctrl = el.friendly_class_name()
                        except Exception:
                            pass
                    rect = None
                    try:
                        r = el.rectangle()
                        rect = [int(r.left), int(r.top), int(r.right), int(r.bottom)]
                    except Exception:
                        pass
                    elements.append({
                        "element_index": i,
                        "name": name,
                        "role": ctrl,
                        "bbox": rect,
                        "actions": ["click", "type"] if ctrl else [],
                    })
                except Exception:
                    continue
            return {"ok": True, "elements": elements, "pid": pid, "window_id": window_id}
        except Exception as e:
            return {"ok": False, "error": str(e), "elements": []}

    def _find_element(self, pid: int, element_index: int, window_id: Optional[int] = None):
        state = self.get_window_state(pid, window_id)
        # Need live element — re-walk
        for w in self._desktop.windows():
            try:
                if int(w.process_id()) != int(pid):
                    continue
                if window_id is not None and int(w.handle) != int(window_id):
                    continue
                desc = w.descendants()
                if 0 <= element_index < len(desc):
                    return desc[element_index]
            except Exception:
                continue
        return None

    def click(self, x: Optional[int] = None, y: Optional[int] = None, button: str = "left",
              pid: Optional[int] = None, window_id: Optional[int] = None,
              element_index: Optional[int] = None, **kwargs) -> DeliveryResult:
        if not self._ready:
            return DeliveryResult(False, "pywinauto", "not available")
        try:
            if pid is not None and element_index is not None:
                el = self._find_element(pid, element_index, window_id)
                if el is None:
                    return DeliveryResult(False, "pywinauto", "element not found")
                el.click_input()
                return DeliveryResult(True, "pywinauto", f"clicked element_index={element_index}", element_index=element_index)
            if x is not None and y is not None:
                from pywinauto import mouse
                mouse.click(button=button, coords=(int(x), int(y)))
                return DeliveryResult(True, "pywinauto", f"coords=({x},{y})")
            return DeliveryResult(False, "pywinauto", "need element_index or x/y")
        except Exception as e:
            return DeliveryResult(False, "pywinauto", str(e))

    def type_text(self, text: str, **kwargs) -> DeliveryResult:
        if not self._ready:
            return DeliveryResult(False, "pywinauto", "not available")
        try:
            pid = kwargs.get("pid")
            element_index = kwargs.get("element_index")
            window_id = kwargs.get("window_id")
            if pid is not None and element_index is not None:
                el = self._find_element(pid, int(element_index), window_id)
                if el is not None:
                    try:
                        el.set_focus()
                    except Exception:
                        pass
                    el.type_keys(text, with_spaces=True, pause=0.02)
                    return DeliveryResult(True, "pywinauto", "typed into element")
            # fallback: send keys to foreground
            from pywinauto import keyboard
            keyboard.send_keys(text, with_spaces=True, pause=0.02)
            return DeliveryResult(True, "pywinauto", "typed to focus")
        except Exception as e:
            return DeliveryResult(False, "pywinauto", str(e))
