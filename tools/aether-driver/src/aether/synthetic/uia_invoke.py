"""
Windows UIA invoke patterns — click/toggle/expand via accessibility, not coords.
Best-effort background-friendly actions when pywinauto/comtypes UIA is available.
"""
from __future__ import annotations
from typing import Any, Dict, Optional, Tuple


def invoke_element(pid: int, element_index: int, window_id: Optional[int] = None) -> Tuple[bool, str]:
    try:
        from pywinauto import Desktop
    except Exception as e:
        return False, f"pywinauto missing: {e}"
    try:
        desktop = Desktop(backend="uia")
        target_win = None
        for w in desktop.windows():
            try:
                if int(w.process_id()) != int(pid):
                    continue
                if window_id is not None and int(w.handle) != int(window_id):
                    continue
                target_win = w
                break
            except Exception:
                continue
        if target_win is None:
            return False, "window not found"
        desc = target_win.descendants()
        if element_index < 0 or element_index >= len(desc):
            return False, "element_index out of range"
        el = desc[element_index]
        # Prefer invoke / toggle / select patterns over click_input (more background-friendly)
        for method in ("invoke", "toggle", "select", "click", "click_input"):
            fn = getattr(el, method, None)
            if callable(fn):
                try:
                    fn()
                    return True, f"uia:{method}"
                except Exception:
                    continue
        # Legacy get_value / set_focus + type path not here
        return False, "no invoke/toggle/select/click on element"
    except Exception as e:
        return False, str(e)


def set_value(pid: int, element_index: int, value: str, window_id: Optional[int] = None) -> Tuple[bool, str]:
    try:
        from pywinauto import Desktop
        desktop = Desktop(backend="uia")
        for w in desktop.windows():
            try:
                if int(w.process_id()) != int(pid):
                    continue
                if window_id is not None and int(w.handle) != int(window_id):
                    continue
                desc = w.descendants()
                el = desc[element_index]
                for method in ("set_edit_text", "set_text", "type_keys"):
                    fn = getattr(el, method, None)
                    if callable(fn):
                        try:
                            if method == "type_keys":
                                fn(value, with_spaces=True)
                            else:
                                fn(value)
                            return True, f"uia:{method}"
                        except Exception:
                            continue
            except Exception:
                continue
        return False, "set_value failed"
    except Exception as e:
        return False, str(e)
