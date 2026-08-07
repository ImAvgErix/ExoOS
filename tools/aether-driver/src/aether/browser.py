"""
Aether Browser Control Layer

Cross-platform browser automation that works on Windows *today*
(while waiting for ego lite Windows).

Design goals (inspired by ego lite, but practical now):
- Persistent profiles → reuse real logins / cookies when possible
- Structured snapshots (not raw HTML) to save tokens
- Batched-friendly actions
- Multiple independent contexts ("Spaces" analogue)
- Works with any MCP / agent (Grok, Claude Code, Codex, Hermes, etc.)

Uses Playwright. On first use it launches Chromium with a persistent
user-data-dir so sessions survive across agent runs.
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from playwright.async_api import async_playwright, Browser, BrowserContext, Page, Playwright
    HAS_PLAYWRIGHT = True
except ImportError:
    HAS_PLAYWRIGHT = False


DEFAULT_PROFILE_DIR = Path.home() / ".aether" / "browser-profiles" / "default"
DEFAULT_PROFILE_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class Space:
    """Isolated browser workspace (ego-lite Space analogue)."""
    id: str
    name: str
    context: Any = None  # BrowserContext
    page: Any = None     # Page
    created_at: float = field(default_factory=time.time)


class BrowserEngine:
    """
    Persistent, multi-space browser controller.
    Thread/async safe enough for prototype agent use.
    """

    def __init__(
        self,
        profile_dir: Optional[Path] = None,
        headless: bool = False,
        channel: Optional[str] = None,  # "chrome" | "msedge" | None (bundled chromium)
    ):
        if not HAS_PLAYWRIGHT:
            raise RuntimeError("Playwright not installed. Run: pip install playwright && playwright install chromium")
        self.profile_dir = Path(profile_dir or DEFAULT_PROFILE_DIR)
        self.profile_dir.mkdir(parents=True, exist_ok=True)
        self.headless = headless
        self.channel = channel
        self._pw: Optional[Playwright] = None
        self._browser: Optional[Browser] = None
        self._spaces: Dict[str, Space] = {}
        self._default_space_id: Optional[str] = None
        self._lock = asyncio.Lock()
        self._started = False

    async def start(self) -> None:
        if self._started:
            return
        self._pw = await async_playwright().start()
        launch_args = {
            "user_data_dir": str(self.profile_dir),
            "headless": self.headless,
            "args": [
                "--disable-blink-features=AutomationControlled",
                "--no-first-run",
                "--no-default-browser-check",
            ],
            "viewport": {"width": 1440, "height": 900},
            "ignore_default_args": ["--enable-automation"],
        }
        if self.channel:
            launch_args["channel"] = self.channel
        # Persistent context = one long-lived profile (cookies/logins survive)
        self._browser = await self._pw.chromium.launch_persistent_context(**launch_args)
        self._started = True
        # Create a default space from the first page
        pages = self._browser.pages
        page = pages[0] if pages else await self._browser.new_page()
        sid = "default"
        self._spaces[sid] = Space(id=sid, name="default", context=self._browser, page=page)
        self._default_space_id = sid

    async def stop(self) -> None:
        if self._browser:
            await self._browser.close()
        if self._pw:
            await self._pw.stop()
        self._started = False
        self._spaces.clear()

    async def ensure_started(self) -> None:
        if not self._started:
            await self.start()


    async def connect_cdp(self, endpoint: str = "http://127.0.0.1:9222") -> Dict[str, Any]:
        """
        Attach to an already-running Chrome/Edge launched with --remote-debugging-port=9222.
        This reuses the user's real profile/logins (far better than a blank automated browser).
        Example launch:
          chrome --remote-debugging-port=9222
          msedge --remote-debugging-port=9222
        """
        if not HAS_PLAYWRIGHT:
            return {"ok": False, "error": "playwright missing"}
        if self._pw is None:
            self._pw = await async_playwright().start()
        try:
            browser = await self._pw.chromium.connect_over_cdp(endpoint)
            self._browser = browser.contexts[0] if browser.contexts else await browser.new_context()
            self._started = True
            pages = self._browser.pages
            page = pages[0] if pages else await self._browser.new_page()
            sid = "cdp-default"
            self._spaces[sid] = Space(id=sid, name="cdp-default", context=self._browser, page=page)
            self._default_space_id = sid
            return {"ok": True, "endpoint": endpoint, "space_id": sid, "pages": len(pages)}
        except Exception as e:
            return {"ok": False, "error": str(e), "hint": "Start Chrome with --remote-debugging-port=9222"}

    async def list_spaces(self) -> List[Dict[str, Any]]:
        await self.ensure_started()
        out = []
        for s in self._spaces.values():
            url = ""
            title = ""
            try:
                if s.page and not s.page.is_closed():
                    url = s.page.url
                    title = await s.page.title()
            except Exception:
                pass
            out.append({"id": s.id, "name": s.name, "url": url, "title": title})
        return out

    async def create_space(self, name: Optional[str] = None) -> str:
        await self.ensure_started()
        sid = str(uuid.uuid4())[:8]
        name = name or f"space-{sid}"
        page = await self._browser.new_page()
        self._spaces[sid] = Space(id=sid, name=name, context=self._browser, page=page)
        return sid

    def _get_space(self, space_id: Optional[str] = None) -> Space:
        sid = space_id or self._default_space_id
        if sid not in self._spaces:
            raise ValueError(f"Unknown space: {sid}")
        return self._spaces[sid]

    async def navigate(self, url: str, space_id: Optional[str] = None, wait: str = "domcontentloaded") -> Dict[str, Any]:
        await self.ensure_started()
        space = self._get_space(space_id)
        await space.page.goto(url, wait_until=wait, timeout=60000)
        title = await space.page.title()
        return {"ok": True, "url": space.page.url, "title": title, "space_id": space.id}

    async def snapshot(
        self,
        space_id: Optional[str] = None,
        include_screenshot: bool = True,
        max_text_chars: int = 12000,
    ) -> Dict[str, Any]:
        """
        Structured page observation (token-efficient).
        Returns title, url, interactive elements with refs, visible text sample, optional screenshot.
        """
        await self.ensure_started()
        space = self._get_space(space_id)
        page = space.page

        title = await page.title()
        url = page.url

        # Collect interactive elements with stable-ish refs
        elements = await page.evaluate("""() => {
            const out = [];
            const sel = 'a, button, input, textarea, select, [role="button"], [role="link"], [onclick], [tabindex]';
            const nodes = Array.from(document.querySelectorAll(sel)).slice(0, 80);
            nodes.forEach((el, i) => {
                const rect = el.getBoundingClientRect();
                if (rect.width < 2 || rect.height < 2) return;
                const text = (el.innerText || el.value || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '').trim().slice(0, 120);
                out.push({
                    ref: i,
                    tag: el.tagName.toLowerCase(),
                    type: el.getAttribute('type') || null,
                    role: el.getAttribute('role') || null,
                    text: text,
                    name: el.getAttribute('name') || null,
                    href: el.getAttribute('href') || null,
                    bbox: [Math.round(rect.x), Math.round(rect.y), Math.round(rect.x+rect.width), Math.round(rect.y+rect.height)]
                });
            });
            return out;
        }""")

        # Visible text sample
        text = await page.evaluate(f"""() => {{
            const t = document.body ? document.body.innerText : '';
            return t.slice(0, {max_text_chars});
        }}""")

        result: Dict[str, Any] = {
            "space_id": space.id,
            "url": url,
            "title": title,
            "elements": elements,
            "text_sample": text,
            "element_count": len(elements),
        }

        if include_screenshot:
            try:
                png = await page.screenshot(type="jpeg", quality=65, full_page=False)
                result["screenshot_base64"] = base64.b64encode(png).decode("ascii")
                result["screenshot_format"] = "jpeg"
            except Exception as e:
                result["screenshot_error"] = str(e)

        return result

    async def click(self, ref: Optional[int] = None, selector: Optional[str] = None,
                    x: Optional[float] = None, y: Optional[float] = None,
                    space_id: Optional[str] = None) -> Dict[str, Any]:
        await self.ensure_started()
        space = self._get_space(space_id)
        page = space.page

        if ref is not None:
            # Click by element ref from last snapshot
            handle = await page.evaluate_handle(f"""() => {{
                const sel = 'a, button, input, textarea, select, [role="button"], [role="link"], [onclick], [tabindex]';
                const nodes = Array.from(document.querySelectorAll(sel)).slice(0, 80);
                return nodes[{int(ref)}] || null;
            }}""")
            el = handle.as_element()
            if el is None:
                return {"ok": False, "error": f"No element for ref={ref}"}
            await el.click(timeout=10000)
            return {"ok": True, "method": "ref", "ref": ref}

        if selector:
            await page.click(selector, timeout=10000)
            return {"ok": True, "method": "selector", "selector": selector}

        if x is not None and y is not None:
            await page.mouse.click(x, y)
            return {"ok": True, "method": "coords", "x": x, "y": y}

        return {"ok": False, "error": "Provide ref, selector, or x/y"}

    async def type_text(self, text: str, ref: Optional[int] = None, selector: Optional[str] = None,
                        clear: bool = False, space_id: Optional[str] = None) -> Dict[str, Any]:
        await self.ensure_started()
        space = self._get_space(space_id)
        page = space.page

        if ref is not None:
            handle = await page.evaluate_handle(f"""() => {{
                const sel = 'a, button, input, textarea, select, [role="button"], [role="link"], [onclick], [tabindex]';
                const nodes = Array.from(document.querySelectorAll(sel)).slice(0, 80);
                return nodes[{int(ref)}] || null;
            }}""")
            el = handle.as_element()
            if el is None:
                return {"ok": False, "error": f"No element for ref={ref}"}
            if clear:
                await el.fill("")
            await el.type(text, delay=20)
            return {"ok": True, "method": "ref", "ref": ref}

        if selector:
            if clear:
                await page.fill(selector, "")
            await page.type(selector, text, delay=20)
            return {"ok": True, "method": "selector", "selector": selector}

        # Type into focused element
        await page.keyboard.type(text, delay=20)
        return {"ok": True, "method": "focused"}

    async def press(self, key: str, space_id: Optional[str] = None) -> Dict[str, Any]:
        await self.ensure_started()
        space = self._get_space(space_id)
        await space.page.keyboard.press(key)
        return {"ok": True, "key": key}

    async def scroll(self, dy: int = 600, space_id: Optional[str] = None) -> Dict[str, Any]:
        await self.ensure_started()
        space = self._get_space(space_id)
        await space.page.mouse.wheel(0, dy)
        return {"ok": True, "dy": dy}

    async def evaluate(self, js: str, space_id: Optional[str] = None) -> Dict[str, Any]:
        """Run arbitrary JS in the page (powerful escape hatch)."""
        await self.ensure_started()
        space = self._get_space(space_id)
        result = await space.page.evaluate(js)
        return {"ok": True, "result": result}


    async def wait_for(self, text: Optional[str] = None, selector: Optional[str] = None,
                       timeout: float = 15000, space_id: Optional[str] = None) -> Dict[str, Any]:
        await self.ensure_started()
        space = self._get_space(space_id)
        page = space.page
        try:
            if selector:
                await page.wait_for_selector(selector, timeout=timeout)
                return {"ok": True, "method": "selector", "selector": selector}
            if text:
                await page.get_by_text(text, exact=False).first.wait_for(timeout=timeout)
                return {"ok": True, "method": "text", "text": text}
            return {"ok": False, "error": "need text or selector"}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    async def fill_form(self, fields: Dict[str, str], space_id: Optional[str] = None) -> Dict[str, Any]:
        """fields: {css_selector_or_label: value}. Tries selector first, then placeholder/label text."""
        await self.ensure_started()
        space = self._get_space(space_id)
        page = space.page
        results = []
        for key, value in fields.items():
            try:
                # try as selector
                loc = page.locator(key)
                if await loc.count() > 0:
                    await loc.first.fill(str(value))
                    results.append({"field": key, "ok": True, "method": "selector"})
                    continue
            except Exception:
                pass
            try:
                loc = page.get_by_label(key, exact=False)
                if await loc.count() > 0:
                    await loc.first.fill(str(value))
                    results.append({"field": key, "ok": True, "method": "label"})
                    continue
            except Exception:
                pass
            try:
                loc = page.get_by_placeholder(key, exact=False)
                if await loc.count() > 0:
                    await loc.first.fill(str(value))
                    results.append({"field": key, "ok": True, "method": "placeholder"})
                    continue
            except Exception:
                pass
            results.append({"field": key, "ok": False, "error": "not found"})
        return {"ok": all(r.get("ok") for r in results), "results": results}

    async def close_space(self, space_id: str) -> Dict[str, Any]:
        if space_id == "default":
            return {"ok": False, "error": "Cannot close default space"}
        space = self._spaces.get(space_id)
        if not space:
            return {"ok": False, "error": "Unknown space"}
        try:
            if space.page and not space.page.is_closed():
                await space.page.close()
        except Exception:
            pass
        del self._spaces[space_id]
        return {"ok": True, "closed": space_id}


# Synchronous wrapper for MCP / simple agents
class BrowserEngineSync:
    """Thin sync façade so MCP tools can call without managing event loops."""

    def __init__(self, **kwargs):
        self._engine = BrowserEngine(**kwargs)
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    def _run(self, coro):
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                # Nested — create a new loop in a thread would be better, but for prototype:
                import concurrent.futures
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                    return pool.submit(asyncio.run, coro).result()
            return loop.run_until_complete(coro)
        except RuntimeError:
            return asyncio.run(coro)

    def start(self):
        return self._run(self._engine.start())

    def connect_cdp(self, endpoint: str = "http://127.0.0.1:9222"):
        """Attach to Chrome/Edge/WebView2 remote debugging (e.g. EXOOS_CDP port 9229)."""
        return self._run(self._engine.connect_cdp(endpoint))

    def list_spaces(self):
        return self._run(self._engine.list_spaces())

    def create_space(self, name: Optional[str] = None):
        return self._run(self._engine.create_space(name))

    def navigate(self, url: str, space_id: Optional[str] = None, wait: str = "domcontentloaded"):
        return self._run(self._engine.navigate(url, space_id, wait))

    def snapshot(self, space_id: Optional[str] = None, include_screenshot: bool = True):
        return self._run(self._engine.snapshot(space_id, include_screenshot))

    def click(self, ref: Optional[int] = None, selector: Optional[str] = None,
              x: Optional[float] = None, y: Optional[float] = None, space_id: Optional[str] = None):
        return self._run(self._engine.click(ref, selector, x, y, space_id))

    def type_text(self, text: str, ref: Optional[int] = None, selector: Optional[str] = None,
                  clear: bool = False, space_id: Optional[str] = None):
        return self._run(self._engine.type_text(text, ref, selector, clear, space_id))

    def press(self, key: str, space_id: Optional[str] = None):
        return self._run(self._engine.press(key, space_id))

    def scroll(self, dy: int = 600, space_id: Optional[str] = None):
        return self._run(self._engine.scroll(dy, space_id))

    def evaluate(self, js: str, space_id: Optional[str] = None):
        return self._run(self._engine.evaluate(js, space_id))

    def wait_for(self, text=None, selector=None, timeout: float = 15000, space_id=None):
        return self._run(self._engine.wait_for(text=text, selector=selector, timeout=timeout, space_id=space_id))

    def fill_form(self, fields, space_id=None):
        return self._run(self._engine.fill_form(fields, space_id=space_id))

    def close_space(self, space_id: str):
        return self._run(self._engine.close_space(space_id))

    def stop(self):
        return self._run(self._engine.stop())
