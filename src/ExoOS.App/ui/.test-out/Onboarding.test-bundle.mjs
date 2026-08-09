import { jsx, jsxs } from "react/jsx-runtime";
import { useEffect, useMemo, useRef, useState } from 'data:text/javascript,export default {};export const useEffect=()=>{};export const useMemo=(f)=>f();export const useRef=()=>({current:null});export const useState=(v)=>[v,()=>{}];';
import { Check, ChevronLeft } from 'data:text/javascript,export const Check=()=>null;export const ChevronLeft=()=>null;';
import { cn } from 'data:text/javascript,export const cn=(...a)=>a.filter(Boolean).join(" ");';
import { host } from 'data:text/javascript,export const host={};';
import { WindowChrome } from 'data:text/javascript,export const WindowChrome=()=>null;';
import { CascadeTitle, FadeIn, StageSwap, Stagger } from 'data:text/javascript,export const CascadeTitle=()=>null;export const FadeIn=()=>null;export const StageSwap=()=>null;export const Stagger=()=>null;';
const STEPS = [
  "welcome",
  "goal",
  "defender",
  "cleanup",
  "services",
  "browsers",
  "extras",
  "apps",
  "ready"
];
const BROWSER_ITEMS = [
  { id: "brave", title: "Brave", detail: "Ad-block, light Chromium" },
  { id: "helium", title: "Helium", detail: "Privacy, no bloat" },
  { id: "zen", title: "Zen", detail: "Calm Firefox fork" },
  { id: "firefox", title: "Firefox", detail: "Independent engine" },
  { id: "librewolf", title: "LibreWolf", detail: "Hardened & fast" },
  { id: "chrome", title: "Chrome", detail: "Stock Chromium" }
];
const EXTRA_ITEMS = [
  { id: "7zip", title: "7-Zip", detail: "Archives" },
  { id: "snipping", title: "Snipping Tool", detail: "Screenshots" },
  { id: "photos", title: "Photos", detail: "Gallery" },
  { id: "notepad", title: "Notepad", detail: "Notes" },
  { id: "terminal", title: "Terminal Preview", detail: "Shell" },
  { id: "pwsh", title: "PowerShell Preview", detail: "Latest PS" }
];
const APP_ITEMS = [
  { id: "steam", title: "Steam", detail: "Games" },
  { id: "discord", title: "Discord", detail: "Voice" },
  { id: "epic", title: "Epic Games", detail: "Launcher" },
  { id: "riot", title: "Riot Client", detail: "Valorant\u2026" },
  { id: "revo", title: "Revo", detail: "Uninstall" },
  { id: "obs", title: "OBS Studio", detail: "Capture" },
  { id: "spotify", title: "Spotify", detail: "Music" }
];
const DEFAULT_EXTRAS = ["7zip", "snipping", "photos", "notepad", "terminal"];
const BRAND_LINE = "Built quiet. Tuned sharp.";
function answersToOptions(a) {
  const extreme = a.goal === "fps";
  const privacy = a.goal === "privacy";
  const balanced = a.goal === "balanced";
  const b = new Set(a.browsers);
  const e = new Set(a.extras);
  const apps = new Set(a.apps);
  return {
    defenderStrip: a.defender === "strip",
    removeAi: a.cleanup === "yes" || privacy || extreme,
    removeOneDrive: a.cleanup === "yes" || privacy || extreme,
    // Edge = forced Windows bloat. Extreme always strips it; Balanced only if cleanup=yes.
    // User browsers (Chrome/Brave/Firefox/…) install separately and stay working.
    stripEdge: extreme || a.cleanup === "yes",
    privacyHosts: a.cleanup === "yes" || privacy || extreme,
    // Mild quiet: user quiet pick, Privacy, or Extreme. Deep kills (SysMain/Spooler/…) are extremeMode-only in YAML.
    serviceStrip: a.services === "quiet" || privacy || extreme,
    dismStrip: extreme,
    disableVbs: extreme,
    extremeMode: extreme,
    installDirectX: true,
    installVcRedist: true,
    installDotNet8: true,
    installDotNet10: true,
    installBrave: b.has("brave"),
    installHelium: b.has("helium"),
    installZen: b.has("zen"),
    installFirefox: b.has("firefox"),
    installLibreWolf: b.has("librewolf"),
    installChrome: b.has("chrome"),
    install7zip: e.has("7zip"),
    installSnipping: e.has("snipping"),
    installPhotos: e.has("photos"),
    installNotepad: e.has("notepad"),
    installTerminalPreview: e.has("terminal"),
    installPowerShellPreview: e.has("pwsh"),
    installSteam: apps.has("steam"),
    installDiscord: apps.has("discord"),
    installEpic: apps.has("epic"),
    installRiot: apps.has("riot"),
    installRevo: apps.has("revo"),
    installObs: apps.has("obs"),
    installSpotify: apps.has("spotify")
  };
}
function toggleId(list, id) {
  return list.includes(id) ? list.filter((x) => x !== id) : [...list, id];
}
function labelList(ids, catalog, empty) {
  if (ids.length === 0) return empty;
  const map = new Map(catalog.map((c) => [c.id, c.title]));
  return ids.map((id) => map.get(id) ?? id).join(" \xB7 ");
}
function Onboarding({ onDone }) {
  const [step, setStep] = useState(0);
  const [animKey, setAnimKey] = useState(0);
  const [dir, setDir] = useState("fwd");
  const prevStep = useRef(0);
  const [answers, setAnswers] = useState({
    goal: "fps",
    defender: "strip",
    cleanup: "yes",
    services: "quiet",
    browsers: [],
    extras: [...DEFAULT_EXTRAS],
    apps: []
  });
  const [busy, setBusy] = useState(false);
  const id = STEPS[step];
  const go = (n) => {
    setDir(n >= prevStep.current ? "fwd" : "back");
    prevStep.current = n;
    setStep(n);
    setAnimKey((k) => k + 1);
  };
  const finish = async () => {
    if (busy) return;
    setBusy(true);
    try {
      await host.setOptions(answersToOptions(answers)).catch(() => {
      });
      await host.completeOnboarding(answers).catch(() => {
      });
      try {
        window.localStorage.setItem(
          "exoos.onboarding.v1",
          JSON.stringify({ done: true, answers })
        );
      } catch {
      }
      onDone(answers);
    } finally {
      setBusy(false);
    }
  };
  const next = () => {
    if (step >= STEPS.length - 1) void finish();
    else go(step + 1);
  };
  const back = () => {
    if (step > 0) go(step - 1);
  };
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === "Enter" && !busy) next();
      if (e.key === "Escape" && step > 0) back();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [step, busy, answers]);
  const body = useMemo(() => {
    switch (id) {
      case "welcome":
        return /* @__PURE__ */ jsxs("div", { className: "flex flex-col items-center text-center", children: [
          /* @__PURE__ */ jsx(
            "div",
            {
              className: "exo-logo-in grid size-[80px] place-items-center text-[34px] font-bold tracking-tight text-fg",
              style: {
                borderRadius: 22,
                background: "linear-gradient(160deg,#2e2e32 0%,#121214 50%,#050505 100%)",
                border: "1px solid #282828",
                boxShadow: "0 20px 60px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.06)"
              },
              children: "E"
            }
          ),
          /* @__PURE__ */ jsx(
            CascadeTitle,
            {
              text: "Welcome to Exo OS",
              className: "mt-8 text-[36px] font-semibold tracking-tight leading-none"
            }
          ),
          /* @__PURE__ */ jsx(FadeIn, { delay: 0.08, className: "mt-5 max-w-sm text-[17px] font-medium leading-snug tracking-tight", children: BRAND_LINE }),
          /* @__PURE__ */ jsx(FadeIn, { delay: 0.14, className: "mt-6 max-w-sm text-[14px] leading-relaxed text-muted", children: "A few choices so the plan matches how you play." })
        ] });
      case "goal":
        return /* @__PURE__ */ jsx(
          Question,
          {
            title: "What matters most?",
            subtitle: "Sets how aggressive the plan is.",
            choices: [
              {
                id: "fps",
                title: "Maximum FPS",
                detail: "Full extreme: DISM, VBS off, HAGS, spooler off, mitigations stripped, max quiet. WU paused (all plans). Can break printers / some anti-cheat.",
                warn: true
              },
              {
                id: "balanced",
                title: "Balanced",
                detail: "Shared baseline (WU pause, input, light privacy) plus your service/cleanup picks \u2014 no spooler/mitigation strip."
              },
              {
                id: "privacy",
                title: "Privacy first",
                detail: "Telemetry quiet, AI/OneDrive strip, service strip \u2014 WU paused. Not full extreme (no spooler/mitigations/DISM)."
              }
            ],
            value: answers.goal,
            onChange: (v) => setAnswers((a) => ({ ...a, goal: v }))
          }
        );
      case "defender":
        return /* @__PURE__ */ jsx(
          Question,
          {
            title: "Windows Defender?",
            subtitle: "Some anti-cheat expects it. Hard to reverse.",
            choices: [
              {
                id: "strip",
                title: "Remove Defender",
                detail: "Lowest background load. Plan on reinstall to fully restore.",
                warn: true
              },
              {
                id: "keep",
                title: "Keep Defender",
                detail: "Safer for multiplayer and work software."
              }
            ],
            value: answers.defender,
            onChange: (v) => setAnswers((a) => ({ ...a, defender: v }))
          }
        );
      case "cleanup":
        return /* @__PURE__ */ jsx(
          Question,
          {
            title: "Bloat and extras?",
            subtitle: "Copilot, OneDrive, Edge noise, privacy hosts.",
            choices: [
              {
                id: "yes",
                title: "Clean them up",
                detail: "Strip AI surfaces, OneDrive hooks, and telemetry hosts."
              },
              {
                id: "no",
                title: "Leave them",
                detail: "Keep cloud extras and stock Microsoft features."
              }
            ],
            value: answers.cleanup,
            onChange: (v) => setAnswers((a) => ({ ...a, cleanup: v }))
          }
        );
      case "services":
        return /* @__PURE__ */ jsx(
          Question,
          {
            title: "Background services?",
            subtitle: "Quiet systems free CPU and disk while you play.",
            choices: [
              {
                id: "quiet",
                title: "Quiet them",
                detail: "Turn down telemetry, diagnostics, non-essentials."
              },
              {
                id: "leave",
                title: "Leave alone",
                detail: "Keep stock service startup."
              }
            ],
            value: answers.services,
            onChange: (v) => setAnswers((a) => ({ ...a, services: v }))
          }
        );
      case "browsers":
        return /* @__PURE__ */ jsx(
          MultiPick,
          {
            title: "Browsers",
            subtitle: "Optional. Pick any \u2014 or skip.",
            items: BROWSER_ITEMS,
            selected: answers.browsers,
            onToggle: (itemId) => setAnswers((a) => ({ ...a, browsers: toggleId(a.browsers, itemId) })),
            onClear: () => setAnswers((a) => ({ ...a, browsers: [] })),
            onSelectAll: () => setAnswers((a) => ({ ...a, browsers: BROWSER_ITEMS.map((x) => x.id) }))
          }
        );
      case "extras":
        return /* @__PURE__ */ jsx(
          MultiPick,
          {
            title: "Tools",
            subtitle: "Useful utilities. Defaults are on.",
            items: EXTRA_ITEMS,
            selected: answers.extras,
            onToggle: (itemId) => setAnswers((a) => ({ ...a, extras: toggleId(a.extras, itemId) })),
            onClear: () => setAnswers((a) => ({ ...a, extras: [] })),
            onSelectAll: () => setAnswers((a) => ({ ...a, extras: EXTRA_ITEMS.map((x) => x.id) }))
          }
        );
      case "apps":
        return /* @__PURE__ */ jsx(
          MultiPick,
          {
            title: "Apps",
            subtitle: "Launchers and everyday gaming tools.",
            items: APP_ITEMS,
            selected: answers.apps,
            onToggle: (itemId) => setAnswers((a) => ({ ...a, apps: toggleId(a.apps, itemId) })),
            onClear: () => setAnswers((a) => ({ ...a, apps: [] })),
            onSelectAll: () => setAnswers((a) => ({ ...a, apps: APP_ITEMS.map((x) => x.id) }))
          }
        );
      case "ready":
        return /* @__PURE__ */ jsx(
          Ready,
          {
            answers,
            onEdit: (target) => {
              const idx = STEPS.indexOf(target);
              if (idx >= 0) go(idx);
            }
          }
        );
    }
  }, [id, answers]);
  const cta = id === "welcome" ? "Get started" : id === "ready" ? busy ? "Saving\u2026" : "Finish setup" : "Continue";
  return /* @__PURE__ */ jsxs("div", { className: "exo-app relative flex h-dvh flex-col overflow-hidden bg-bg text-fg", children: [
    /* @__PURE__ */ jsx("div", { className: "exo-ambient" }),
    /* @__PURE__ */ jsx(WindowChrome, {}),
    /* @__PURE__ */ jsx("div", { className: "relative z-10 flex h-11 shrink-0 items-center px-3", children: step > 0 ? /* @__PURE__ */ jsx(
      "button",
      {
        type: "button",
        onClick: back,
        "aria-label": "Back",
        className: "grid size-9 place-items-center rounded-full text-muted transition-all duration-200 hover:bg-hover hover:text-fg active:scale-95",
        children: /* @__PURE__ */ jsx(ChevronLeft, { className: "size-5", strokeWidth: 1.75 })
      }
    ) : /* @__PURE__ */ jsx("span", { className: "w-9" }) }),
    /* @__PURE__ */ jsx("main", { className: "relative z-10 flex min-h-0 flex-1 flex-col items-center justify-center overflow-hidden px-8 pb-10", children: /* @__PURE__ */ jsxs("div", { className: "flex w-full max-w-lg flex-col", children: [
      /* @__PURE__ */ jsx(StageSwap, { stepKey: animKey, dir, children: body }),
      /* @__PURE__ */ jsxs("div", { className: "exo-footer-in mt-8 flex shrink-0 flex-col items-center gap-5", children: [
        /* @__PURE__ */ jsx(
          "div",
          {
            className: "exo-progress",
            role: "progressbar",
            "aria-valuemin": 1,
            "aria-valuemax": STEPS.length,
            "aria-valuenow": step + 1,
            "aria-label": `Step ${step + 1} of ${STEPS.length}`,
            children: STEPS.map((_, i) => /* @__PURE__ */ jsx(
              "span",
              {
                "data-active": i === step ? "true" : void 0,
                "data-done": i < step ? "true" : void 0,
                className: cn(
                  "exo-progress-dot h-1.5 rounded-full",
                  i === step ? "w-6 bg-fg" : i < step ? "w-1.5 bg-fg/50" : "w-1.5 bg-faint/40"
                )
              },
              i
            ))
          }
        ),
        /* @__PURE__ */ jsx(
          "button",
          {
            type: "button",
            disabled: busy,
            onClick: next,
            "aria-label": cta,
            className: "exo-cta flex h-12 w-full max-w-sm items-center justify-center rounded-full bg-fg text-[15px] font-semibold text-bg disabled:opacity-50",
            children: /* @__PURE__ */ jsx("span", { className: "exo-cta-label", children: cta }, cta)
          }
        )
      ] })
    ] }) })
  ] });
}
function Question({
  title,
  subtitle,
  choices,
  value,
  onChange
}) {
  return /* @__PURE__ */ jsxs("div", { children: [
    /* @__PURE__ */ jsx(
      CascadeTitle,
      {
        text: title,
        className: "text-[28px] font-semibold tracking-tight leading-tight"
      }
    ),
    /* @__PURE__ */ jsx(FadeIn, { delay: 0.05, className: "mt-2 text-[14px] leading-relaxed text-muted", children: subtitle }),
    /* @__PURE__ */ jsx(Stagger, { className: "mt-6 space-y-2.5", children: choices.map((c) => {
      const on = value === c.id;
      return /* @__PURE__ */ jsxs(
        "button",
        {
          type: "button",
          role: "radio",
          "aria-checked": on,
          "aria-label": c.title,
          "data-on": on,
          onClick: () => onChange(c.id),
          className: "exo-choice card flex w-full items-start gap-3.5 p-4 text-left",
          children: [
            /* @__PURE__ */ jsx(
              "span",
              {
                className: cn(
                  "mt-0.5 grid size-5 shrink-0 place-items-center rounded-full border transition-all duration-200",
                  on ? "border-fg bg-fg text-bg scale-100" : "border-faint scale-95"
                ),
                children: on && /* @__PURE__ */ jsx(Check, { className: "size-3", strokeWidth: 3 })
              }
            ),
            /* @__PURE__ */ jsxs("span", { className: "min-w-0 flex-1", children: [
              /* @__PURE__ */ jsx("span", { className: "block text-[15px] font-semibold", children: c.title }),
              /* @__PURE__ */ jsx(
                "span",
                {
                  className: cn(
                    "mt-1 block text-[13px] leading-snug",
                    c.warn ? "text-bad/90" : "text-muted"
                  ),
                  children: c.detail
                }
              )
            ] })
          ]
        },
        c.id
      );
    }) })
  ] });
}
function MultiPick({
  title,
  subtitle,
  items,
  selected,
  onToggle,
  onClear,
  onSelectAll
}) {
  return /* @__PURE__ */ jsxs("div", { children: [
    /* @__PURE__ */ jsx(
      CascadeTitle,
      {
        text: title,
        className: "text-[28px] font-semibold tracking-tight leading-tight"
      }
    ),
    /* @__PURE__ */ jsx(FadeIn, { delay: 0.05, className: "mt-2 text-[14px] leading-relaxed text-muted", children: subtitle }),
    /* @__PURE__ */ jsxs(FadeIn, { delay: 0.08, className: "mt-3 flex items-center gap-3 text-[12px]", children: [
      /* @__PURE__ */ jsx(
        "button",
        {
          type: "button",
          onClick: onSelectAll,
          className: "font-medium text-muted transition-colors hover:text-fg",
          children: "All"
        }
      ),
      /* @__PURE__ */ jsx("span", { className: "text-faint", children: "\xB7" }),
      /* @__PURE__ */ jsx(
        "button",
        {
          type: "button",
          onClick: onClear,
          className: "font-medium text-muted transition-colors hover:text-fg",
          children: "None"
        }
      ),
      /* @__PURE__ */ jsxs("span", { className: "ml-auto tabular text-faint", children: [
        selected.length,
        " selected"
      ] })
    ] }),
    /* @__PURE__ */ jsx(Stagger, { className: "mt-3 grid grid-cols-2 gap-2", children: items.map((item) => {
      const on = selected.includes(item.id);
      return /* @__PURE__ */ jsxs(
        "button",
        {
          type: "button",
          role: "checkbox",
          "aria-checked": on,
          "aria-label": item.title,
          "data-on": on,
          onClick: () => onToggle(item.id),
          className: "exo-choice card flex h-full w-full items-start gap-2.5 p-3.5 text-left",
          children: [
            /* @__PURE__ */ jsx(
              "span",
              {
                className: cn(
                  "mt-0.5 grid size-4 shrink-0 place-items-center rounded border transition-all duration-200",
                  on ? "border-fg bg-fg text-bg" : "border-faint"
                ),
                children: on && /* @__PURE__ */ jsx(Check, { className: "size-2.5", strokeWidth: 3 })
              }
            ),
            /* @__PURE__ */ jsxs("span", { className: "min-w-0 flex-1", children: [
              /* @__PURE__ */ jsx("span", { className: "block text-[13px] font-semibold leading-tight", children: item.title }),
              /* @__PURE__ */ jsx("span", { className: "mt-0.5 block text-[11px] leading-snug text-muted", children: item.detail })
            ] })
          ]
        },
        item.id
      );
    }) })
  ] });
}
function Ready({
  answers,
  onEdit
}) {
  const rows = [
    {
      label: "Focus",
      value: answers.goal === "fps" ? "Maximum FPS" : answers.goal === "privacy" ? "Privacy first" : "Balanced",
      step: "goal"
    },
    {
      label: "Defender",
      value: answers.defender === "strip" ? "Remove" : "Keep",
      step: "defender"
    },
    {
      label: "Bloat",
      value: answers.cleanup === "yes" ? "Clean up" : "Leave",
      step: "cleanup"
    },
    {
      label: "Services",
      value: answers.services === "quiet" ? "Quiet" : "Stock",
      step: "services"
    },
    {
      label: "Browsers",
      value: labelList(answers.browsers, BROWSER_ITEMS, "None"),
      step: "browsers"
    },
    {
      label: "Tools",
      value: labelList(answers.extras, EXTRA_ITEMS, "None"),
      step: "extras"
    },
    {
      label: "Apps",
      value: labelList(answers.apps, APP_ITEMS, "None"),
      step: "apps"
    }
  ];
  return /* @__PURE__ */ jsxs("div", { className: "text-center", children: [
    /* @__PURE__ */ jsx(CascadeTitle, { text: "You're set", className: "text-[26px] font-semibold tracking-tight" }),
    /* @__PURE__ */ jsx(FadeIn, { delay: 0.06, className: "mt-1.5 text-[13px] text-muted", children: "Tap a row to change it." }),
    /* @__PURE__ */ jsx("div", { className: "mt-5 grid grid-cols-2 gap-2 text-left", children: rows.map((r) => /* @__PURE__ */ jsxs(
      "button",
      {
        type: "button",
        "aria-label": `${r.label}: ${r.value}`,
        onClick: () => onEdit(r.step),
        className: "exo-ready-row exo-choice card flex min-h-[52px] flex-col justify-center gap-0.5 px-3 py-2.5 text-left",
        children: [
          /* @__PURE__ */ jsx("span", { className: "text-[10px] font-medium tracking-[0.12em] text-faint uppercase", children: r.label }),
          /* @__PURE__ */ jsx("span", { className: "truncate text-[13px] font-semibold leading-tight", children: r.value })
        ]
      },
      r.step
    )) })
  ] });
}
export {
  APP_ITEMS,
  BROWSER_ITEMS,
  EXTRA_ITEMS,
  Onboarding,
  answersToOptions,
  labelList
};
