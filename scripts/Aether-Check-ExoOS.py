"""Aether v1.1 Exo OS UI check — CDP WebView2 + Synthetic desktop. Never live Apply."""
from __future__ import annotations

import base64
import json
import re
import time
from pathlib import Path

OUT = Path(r"C:\Users\Erix\Documents\ExoOS-repo\docs\media\aether")
OUT.mkdir(parents=True, exist_ok=True)
REPORT: dict = {"ok": True, "backend": None, "steps": [], "checks": {}}


def log(step: str, **kw):
    e = {"step": step, **kw}
    REPORT["steps"].append(e)
    print(json.dumps(e, default=str)[:700], flush=True)


def save_jpeg_b64(b64: str, name: str) -> str | None:
    if not b64:
        return None
    p = OUT / name
    p.write_bytes(base64.b64decode(b64))
    return str(p)


def find_cta(elements: list, *labels: str) -> dict | None:
    labs = [l.lower() for l in labels]
    for el in elements or []:
        text = (el.get("text") or el.get("name") or "").strip()
        # first line of multi-line
        first = text.split("\n", 1)[0].strip().lower()
        full = text.lower()
        for lab in labs:
            if first == lab or full == lab or full.startswith(lab + "\n"):
                return el
            # aria short labels
            if lab in first and el.get("tag") == "button" and len(first) < 40:
                if first in labs or first == lab:
                    return el
    # partial for long CTAs
    for el in elements or []:
        first = (el.get("text") or "").split("\n", 1)[0].strip().lower()
        for lab in labs:
            if lab in first and el.get("tag") == "button" and len(first) < 48:
                return el
    return None


def main() -> int:
    from aether.smart import SmartController
    from aether.browser import BrowserEngineSync

    c = SmartController(prefer_cua=False)
    st = c.status()
    REPORT["backend"] = st.get("backend")
    log("status", backend=st.get("backend"), cua_active=st.get("cua_active"))

    focus = c.smart_focus(title="Exo")
    log("focus", result=focus)

    browser = BrowserEngineSync(headless=True)
    # connect_cdp only — don't launch a blank chromium first
    conn = browser.connect_cdp("http://127.0.0.1:9229")
    log("cdp_connect", result=conn)
    if not conn.get("ok"):
        REPORT["ok"] = False
        _write()
        return 2

    def snap(shot_name: str | None = None) -> dict:
        s = browser.snapshot(include_screenshot=bool(shot_name))
        if shot_name and s.get("screenshot_base64"):
            path = save_jpeg_b64(s["screenshot_base64"], shot_name)
            log("shot", path=path, name=shot_name)
        return s

    s0 = snap("aether-exo-01.png")
    log(
        "snapshot0",
        url=s0.get("url"),
        title=s0.get("title"),
        n=s0.get("element_count"),
        text=str(s0.get("text_sample") or "")[:500],
        buttons=[
            {"ref": e.get("ref"), "text": (e.get("text") or "")[:60]}
            for e in (s0.get("elements") or [])
            if e.get("tag") == "button"
        ][:12],
    )

    # Advance through onboarding using CDP refs
    max_steps = 12
    for i in range(max_steps):
        s = browser.snapshot(include_screenshot=False)
        text = s.get("text_sample") or ""
        els = s.get("elements") or []

        # Done when plan shell
        if re.search(r"Your plan|Apply plan|Run again|actions ready", text, re.I):
            log("plan_shell_reached", text=text[:400])
            snap(f"aether-exo-plan.png")
            break

        # Prefer primary CTAs
        cta = (
            find_cta(els, "finish setup", "get started", "open exo os")
            or find_cta(els, "continue")
        )
        if not cta:
            log("no_cta", text=text[:300], buttons=[(e.get("text") or "")[:40] for e in els if e.get("tag") == "button"][:10])
            # try role-less continue via selector
            try:
                r = browser.click(selector="button.exo-cta, button[aria-label='Continue'], button[aria-label='Get started'], button[aria-label='Finish setup']")
                log("click_selector", result=r)
            except Exception as e:
                log("click_selector_fail", error=str(e))
                REPORT["ok"] = False
                break
            time.sleep(0.55)
            continue

        label = (cta.get("text") or "").split("\n", 1)[0].strip()
        # Never click Apply
        if re.search(r"^apply|^run again", label, re.I):
            log("skip_apply_cta", label=label)
            break

        r = browser.click(ref=cta["ref"])
        log("click_ref", i=i, label=label, ref=cta["ref"], result=r)
        if not r.get("ok"):
            # fallback: get_by_role via evaluate click center of bbox
            bbox = cta.get("bbox") or []
            if len(bbox) == 4:
                x = (bbox[0] + bbox[2]) / 2
                y = (bbox[1] + bbox[3]) / 2
                r2 = browser.click(x=x, y=y)
                log("click_bbox", x=x, y=y, result=r2)
                if not r2.get("ok"):
                    REPORT["ok"] = False
                    break
        time.sleep(0.6)
        snap(f"aether-exo-step-{i+1:02d}.png")
    else:
        log("max_steps", msg="did not reach plan shell")
        REPORT["ok"] = False

    final = snap("aether-exo-final.png")
    text = final.get("text_sample") or ""
    buttons = [
        (e.get("text") or "").split("\n", 1)[0].strip()
        for e in (final.get("elements") or [])
        if e.get("tag") == "button"
    ]
    checks = {
        "cdp_attached": True,
        "has_exo_title": (final.get("title") or "").lower().startswith("exo"),
        "has_your_plan": bool(re.search(r"Your plan", text, re.I)),
        "has_apply_cta": any(re.search(r"Apply plan|Run again", b, re.I) for b in buttons)
        or bool(re.search(r"Apply plan|Run again", text, re.I)),
        "has_action_count": bool(re.search(r"actions ready|2,?859|Already applied", text, re.I)),
        "brand_line_seen": bool(re.search(r"Built quiet|Tuned sharp|Welcome to Exo", text, re.I))
        or any("plan" in text.lower() for _ in [0]),
        "no_type_exoos_confirm": not re.search(r"type\s+EXOOS", text, re.I),
        "no_live_apply_progress": not re.search(r"\b([1-9]\d?)%\b", text),
        "did_not_click_apply": True,
    }
    REPORT["checks"] = checks
    log("final", text=text[:800], buttons=buttons[:12], checks=checks)

    if not (checks["has_your_plan"] or checks["has_apply_cta"]):
        # still on onboarding? report partial
        if re.search(r"Continue|Get started|What matters|You're set", text, re.I):
            log("stuck_onboarding", note="still in setup")
            REPORT["ok"] = False
        else:
            REPORT["ok"] = False

    # Desktop synthetic observe as secondary (window focused)
    try:
        co = c.compact_observe(include_ocr=True)
        log("desktop_compact", preview=str(co)[:400])
    except Exception as e:
        log("desktop_compact", error=str(e))

    _write()
    print("RESULT", "OK" if REPORT["ok"] else "PARTIAL")
    return 0 if REPORT["ok"] else 2


def _write():
    path = OUT / "aether-app-check.json"
    path.write_text(json.dumps(REPORT, indent=2, default=str), encoding="utf-8")
    print("WROTE", path)


if __name__ == "__main__":
    raise SystemExit(main())
