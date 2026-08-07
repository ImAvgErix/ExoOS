"""Aether Driver MCP Server v0.7"""
from __future__ import annotations
from typing import Any, Dict, List, Optional

try:
    from mcp.server.fastmcp import FastMCP
    HAS_MCP = True
except ImportError:
    try:
        from mcp.server import MCPServer as FastMCP
        HAS_MCP = True
    except ImportError:
        HAS_MCP = False
        print("Install mcp: pip install mcp")

from aether.smart import SmartController

# Cua not required — Synthetic UIA/SendInput hands are default
ctrl = SmartController(prefer_cua=False, max_retries=3, verify=True, cache_ttl=0.35)
_browser = None

def get_browser():
    global _browser
    if _browser is None:
        from aether.browser import BrowserEngineSync
        _browser = BrowserEngineSync(headless=False)
        _browser.start()
    return _browser

if HAS_MCP:
    mcp = FastMCP("aether-driver")

    @mcp.tool()
    def status() -> Dict[str, Any]:
        return ctrl.status()

    @mcp.tool()
    def list_windows() -> List[Dict]:
        return ctrl.list_windows()

    @mcp.tool()
    def focus_window(pid: int, window_id: Optional[int] = None) -> Dict:
        return ctrl.focus_window(pid, window_id)

    @mcp.tool()
    def observe(modes: str = "vision,ocr,diff", include_image: bool = True,
                max_image_side: int = 1024, monitor: int = 1, use_cache: bool = False) -> Dict[str, Any]:
        mode_list = [m.strip() for m in modes.split(",") if m.strip()]
        return ctrl.observe(modes=mode_list, include_image=include_image,
                            max_image_side=max_image_side, monitor=monitor, use_cache=use_cache)

    @mcp.tool()
    def find_targets(query: str, min_confidence: float = 0.3) -> List[Dict]:
        targets = ctrl.find_targets(query, min_confidence=min_confidence)
        return [{"label": t.label, "kind": t.kind, "confidence": t.confidence, "x": t.x, "y": t.y,
                 "bbox": t.bbox, "source": t.source, "element_index": t.element_index} for t in targets]

    @mcp.tool()
    def smart_click(query: Optional[str] = None, x: Optional[int] = None, y: Optional[int] = None,
                    button: str = "left", require_change: bool = False) -> Dict[str, Any]:
        out = ctrl.smart_click(query=query, x=x, y=y, button=button, require_change=require_change)
        return {"success": out.success, "verified": out.verified, "message": out.message,
                "attempts": out.attempts, "backend": out.backend, "elapsed": round(out.elapsed, 3),
                "from_memory": out.from_memory,
                "target": {"label": out.target.label, "confidence": out.target.confidence,
                           "x": out.target.x, "y": out.target.y} if out.target else None}

    @mcp.tool()
    def smart_type(text: str, query: Optional[str] = None, clear: bool = False) -> Dict[str, Any]:
        out = ctrl.smart_type(text=text, query=query, clear=clear)
        return {"success": out.success, "verified": out.verified, "message": out.message,
                "backend": out.backend, "elapsed": round(out.elapsed, 3)}

    @mcp.tool()
    def smart_scroll(dy: int = 600, dx: int = 0, query: Optional[str] = None) -> Dict[str, Any]:
        out = ctrl.smart_scroll(dy=dy, dx=dx, query=query)
        return {"success": out.success, "verified": out.verified, "message": out.message, "elapsed": round(out.elapsed, 3)}

    @mcp.tool()
    def smart_drag(start_query: Optional[str] = None, end_query: Optional[str] = None,
                   start: Optional[List[int]] = None, end: Optional[List[int]] = None,
                   duration: float = 0.35) -> Dict[str, Any]:
        out = ctrl.smart_drag(start_query=start_query, end_query=end_query, start=start, end=end, duration=duration)
        return {"success": out.success, "verified": out.verified, "message": out.message, "elapsed": round(out.elapsed, 3)}

    @mcp.tool()
    def smart_hotkey(keys: List[str]) -> Dict[str, Any]:
        out = ctrl.smart_hotkey(keys)
        return {"success": out.success, "message": out.message, "backend": out.backend}

    @mcp.tool()
    def wait_until(query: Optional[str] = None, text_contains: Optional[str] = None,
                   timeout: float = 15.0, poll: float = 0.45) -> Dict[str, Any]:
        """Poll until UI text/target appears."""
        out = ctrl.wait_until(query=query, text_contains=text_contains, timeout=timeout, poll=poll)
        return {"success": out.success, "message": out.message, "elapsed": round(out.elapsed, 3),
                "target": {"label": out.target.label, "x": out.target.x, "y": out.target.y} if out.target else None}

    @mcp.tool()
    def smart_fill(fields: Dict[str, str], submit: Optional[str] = None, clear: bool = True) -> Dict[str, Any]:
        """Fill form fields by label: {"Email":"a@b.com","Password":"x"}, optional submit button query."""
        return ctrl.smart_fill(fields=fields, submit=submit, clear=clear)

    @mcp.tool()
    def batch(actions: List[Dict[str, Any]], stop_on_failure: bool = True) -> Dict[str, Any]:
        return ctrl.batch(actions, stop_on_failure=stop_on_failure)

    @mcp.tool()
    def do(goal: str, max_steps: int = 6) -> Dict:
        return ctrl.do(goal=goal, max_steps=max_steps)

    @mcp.tool()
    def clipboard_get() -> Dict[str, Any]:
        return ctrl.clipboard_get()

    @mcp.tool()
    def clipboard_set(text: str) -> Dict[str, Any]:
        return ctrl.clipboard_set(text)

    @mcp.tool()
    def kill_switch(armed: bool = True) -> Dict[str, Any]:
        """Arm/disarm emergency stop — blocks all actions when armed."""
        return ctrl.kill_switch(armed)

    @mcp.tool()
    def click(x: int, y: int, button: str = "left") -> Dict:
        r = ctrl._deliver_click(x=x, y=y, button=button)
        return {"ok": r.ok, "backend": r.backend, "message": r.message}

    @mcp.tool()
    def type_text(text: str, clear: bool = False) -> Dict:
        r = ctrl._deliver_type(text, clear=clear)
        return {"ok": r.ok, "backend": r.backend, "message": r.message}

    # Browser



    @mcp.tool()
    def list_cursors() -> List[Dict]:
        """List virtual cursors (synthetic backend)."""
        return ctrl.list_cursors()

    @mcp.tool()
    def create_cursor(cursor_id: str) -> Dict[str, Any]:
        """Create a named virtual cursor for parallel agent slots."""
        return ctrl.create_cursor(cursor_id)

    @mcp.tool()
    def queue_stats() -> Dict[str, Any]:
        """Per-cursor inject queue depth and processed counts."""
        return ctrl.queue_stats()

    @mcp.tool()
    def smart_focus(title: Optional[str] = None, pid: Optional[int] = None) -> Dict[str, Any]:
        """Focus window by title substring or pid and set a11y context."""
        return ctrl.smart_focus(title=title, pid=pid)

    @mcp.tool()
    def wait_gone(query: str, timeout: float = 15.0) -> Dict[str, Any]:
        out = ctrl.wait_gone(query=query, timeout=timeout)
        return {"success": out.success, "message": out.message, "elapsed": round(out.elapsed, 3)}

    @mcp.tool()
    def wait_change(timeout: float = 10.0) -> Dict[str, Any]:
        out = ctrl.wait_change(timeout=timeout)
        return {"success": out.success, "message": out.message, "elapsed": round(out.elapsed, 3)}

    @mcp.tool()
    def compact_observe(include_ocr: bool = True) -> Dict[str, Any]:
        """Token-efficient observation for LLM agents (no screenshot)."""
        return ctrl.compact_observe(include_ocr=include_ocr)

    @mcp.tool()
    def macro_start() -> Dict[str, Any]:
        return ctrl.macro_start()

    @mcp.tool()
    def macro_stop(save_as: Optional[str] = None) -> Dict[str, Any]:
        return ctrl.macro_stop(save_as=save_as)

    @mcp.tool()
    def macro_play(name: str, stop_on_failure: bool = True) -> Dict[str, Any]:
        return ctrl.macro_play(name, stop_on_failure=stop_on_failure)

    @mcp.tool()
    def macro_list() -> List[str]:
        return ctrl.macro_list()

    @mcp.tool()
    def browser_connect_cdp(endpoint: str = "http://127.0.0.1:9222") -> Dict[str, Any]:
        """Attach to real Chrome/Edge started with --remote-debugging-port=9222 (keeps your logins)."""
        return get_browser().connect_cdp(endpoint)

    @mcp.tool()
    def observe_annotated(max_labels: int = 30) -> Dict[str, Any]:
        """Screenshot with grounded element boxes drawn — debug vision."""
        return ctrl.observe_annotated(max_labels=max_labels)

    @mcp.tool()
    def recent_actions(n: int = 20) -> List[Dict]:
        """Tail of action log (~/.aether/action_log.jsonl)."""
        return ctrl.recent_actions(n)

    @mcp.tool()
    def browser_list_spaces() -> List[Dict]:
        return get_browser().list_spaces()

    @mcp.tool()
    def browser_create_space(name: Optional[str] = None) -> Dict:
        return {"space_id": get_browser().create_space(name), "ok": True}

    @mcp.tool()
    def browser_navigate(url: str, space_id: Optional[str] = None) -> Dict:
        return get_browser().navigate(url, space_id=space_id)

    @mcp.tool()
    def browser_snapshot(space_id: Optional[str] = None, include_screenshot: bool = True) -> Dict:
        return get_browser().snapshot(space_id=space_id, include_screenshot=include_screenshot)

    @mcp.tool()
    def browser_click(ref: Optional[int] = None, selector: Optional[str] = None,
                      x: Optional[float] = None, y: Optional[float] = None,
                      space_id: Optional[str] = None) -> Dict:
        return get_browser().click(ref=ref, selector=selector, x=x, y=y, space_id=space_id)

    @mcp.tool()
    def browser_type(text: str, ref: Optional[int] = None, selector: Optional[str] = None,
                     clear: bool = False, space_id: Optional[str] = None) -> Dict:
        return get_browser().type_text(text, ref=ref, selector=selector, clear=clear, space_id=space_id)

    @mcp.tool()
    def browser_press(key: str, space_id: Optional[str] = None) -> Dict:
        return get_browser().press(key, space_id=space_id)

    @mcp.tool()
    def browser_scroll(dy: int = 600, space_id: Optional[str] = None) -> Dict:
        return get_browser().scroll(dy=dy, space_id=space_id)

    @mcp.tool()
    def browser_wait(text: Optional[str] = None, selector: Optional[str] = None,
                     timeout: float = 15000, space_id: Optional[str] = None) -> Dict:
        return get_browser().wait_for(text=text, selector=selector, timeout=timeout, space_id=space_id)

    @mcp.tool()
    def browser_fill(fields: Dict[str, str], space_id: Optional[str] = None) -> Dict:
        """Fill browser form: {selector_or_label: value}."""
        return get_browser().fill_form(fields, space_id=space_id)

if __name__ == "__main__":
    if HAS_MCP:
        mcp.run()
    else:
        print("mcp package required")
