"""Clipboard helpers (cross-platform best-effort)."""
from __future__ import annotations
from typing import Tuple

def get_clipboard() -> Tuple[bool, str]:
    try:
        import pyperclip
        return True, pyperclip.paste() or ""
    except Exception:
        pass
    try:
        from tkinter import Tk
        r = Tk()
        r.withdraw()
        text = r.clipboard_get()
        r.destroy()
        return True, text
    except Exception as e:
        return False, str(e)

def set_clipboard(text: str) -> Tuple[bool, str]:
    try:
        import pyperclip
        pyperclip.copy(text)
        return True, "ok"
    except Exception:
        pass
    try:
        from tkinter import Tk
        r = Tk()
        r.withdraw()
        r.clipboard_clear()
        r.clipboard_append(text)
        r.update()
        r.destroy()
        return True, "ok"
    except Exception as e:
        return False, str(e)
