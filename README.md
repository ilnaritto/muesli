<p align="center">
  <img src="https://img.shields.io/badge/English-8A5CF6?style=for-the-badge" alt="English" />
  <a href="https://github.com/ilnaritto/muesli/blob/main/README.ru.md"><img src="https://img.shields.io/badge/Русский-3A3A3A?style=for-the-badge" alt="Switch to Russian" /></a>
</p>

<p align="center">
  <img src="assets/redesign/hero-hq.jpg" alt="Muesli — UX/UI Update" width="900" />
</p>

<h1 align="center">Muesli · UX/UI Update</h1>

<p align="center">
  <strong>The same local engine. A completely reimagined interface.</strong><br>
  A design-focused fork of <a href="https://github.com/Muesli-HQ/muesli">Muesli</a> — a native macOS app for dictation and meeting transcription.
</p>

<p align="center">
  <a href="https://github.com/Muesli-HQ/muesli"><img src="https://img.shields.io/badge/fork-Muesli--HQ%2Fmuesli-8A5CF6?logo=github&logoColor=white" alt="Fork of Muesli-HQ/muesli" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/design-free%2C%20no%20resale-orange.svg" alt="Design — free, no resale" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014.2%2B-lightgrey?logo=apple" alt="macOS 14.2+" />
  <img src="https://img.shields.io/badge/languages-RU%20%C2%B7%20EN-success" alt="RU / EN" />
</p>

---

## About this fork

**Muesli** is a superb open-source app: all speech recognition runs **locally on Apple Silicon** — no cloud, no subscriptions, and your audio never leaves your Mac. The technical foundation — the models, the privacy, the transcription engine — was built by the [original author](https://github.com/Muesli-HQ/muesli).

This fork is **my take, as a product designer, on what Muesli's interface could be.** I rebuilt the navigation, the screens, and the visual language in the spirit of modern Apple and Telegram apps: card-based layouts, floating panels, careful typography, live analytics, and full Russian/English localization.

> **This is a design showcase, not a separate product.** The engine, the privacy, and the models all come from the original Muesli. Some new screens are still being finished — an honest list is in the [Status](#status) section.

---

## 35-second overview

<p align="center">
  <img src="assets/redesign/overview-hq.gif" alt="Overview of the redesigned interface" width="820" />
</p>

---

## Why Muesli

Normally this means paying two separate subscription apps: one for dictation, another for meeting notes. **Muesli does both at once — and runs right on your Mac.**

**1. Three tools in one**
- 🎙 **Dictation** — hold a hotkey, speak, release → text is pasted right where your cursor is. ~0.13s latency.
- 👥 **Meetings** — records your mic and system audio at the same time, separates speakers, and hands you a finished transcript seconds after you stop.
- 📊 **Analytics** — how much you've spoken, how much typing time you've saved, your speech habits, and your top filler words.

**2. 100% local and private**
All speech recognition runs on your Mac, on the Apple Neural Engine. Your audio goes nowhere. No cloud, no monthly subscription, no per-minute bills — it just works, for free.

**3. And when you want maximum quality — the cloud, for pennies**
Want even sharper, more structured meeting notes? Plug in an online model — OpenAI, OpenRouter, or your own ChatGPT subscription. You pay **directly for usage**, with no monthly subscription — literally pennies per meeting. Local is free; go online only when you decide to raise the bar.

**4. Native and fast**
Pure Swift — no Electron, no Python. Light, fast, and tuned for Apple Silicon, not yet another browser wrapped in an app.

**5. A design worth opening the app for**
Exactly what you see on this page: card layouts, floating panels, live analytics, templates, and full localization. A powerful engine finally gets an interface to match.

---

## What's been redesigned

### 📊 A new "Home" with voice analytics

Instead of a plain list — a dashboard that shows your voice habits at a glance: minutes spoken, words captured, typing time saved, day streak, weekly rhythm, and top filler words. All computed **locally, on your Mac**.

### 💬 A Telegram-style meeting screen + templates as tabs

A floating header with a title "pill," round action chips, and note templates turned into **tabs** right above the meeting. Switch between templates and the summary for each is recomputed and cached — so reopening is instant.

<p align="center">
  <img src="assets/redesign/templates-hq.gif" alt="Meeting templates as tabs" width="760" />
</p>

### 🤖 AI chat about a meeting

Ask about the call in your own words — "tell me more," "what were the decisions," "pull out the action items" — and get an answer based on the meeting's content. The chat works and responds from the transcript, right on the meeting page.

<p align="center">
  <img src="assets/redesign/meeting-chat-hq.jpg" alt="AI chat about a meeting" width="820" />
</p>

### 🎯 A floating pill with quick actions

A compact pill that lives on top of any app. On hover it expands into a launcher with three actions: meeting, dictation, and screen-recorded meeting — without a single extra window.

<p align="center">
  <img src="assets/redesign/floating-pill-hq.gif" alt="Floating pill" width="520" />
</p>

### 🎥 Meeting screen recording

Beyond audio, a meeting can be recorded together with your screen — the video is saved next to the transcript and available right on the meeting page. Off by default.

<p align="center">
  <img src="assets/redesign/screen-video-hq.jpg" alt="Meeting screen recording" width="820" />
</p>

### 🌍 Full RU / EN localization

Every string in the interface is translated and switches on the fly — Russian and English, no restart.

<p align="center">
  <img src="assets/redesign/localization-hq.gif" alt="RU / EN language switching" width="760" />
</p>

---

## Status

The fork is under active development. Honestly, here's what already works and what's still being finished:

**✅ Done**
- New navigation: bottom tab bar, card-based left column, custom window
- "Home" screen with live voice analytics
- Redesigned meeting screen, templates as tabs, cached summary per template
- AI chat about a meeting
- Floating pill with quick actions
- Meeting screen recording (optional)
- Full RU / EN localization

**🚧 In progress**
- Porting a few settings from the latest upstream into the new design
- Polish and testing before a public release

---

## Work with me

This fork is a clear example of what I do: I take a product with a strong technical foundation and bring its interface up to a level that makes people actually want to open the app.

I don't take on everything. I'm interested in projects with a solid engineering core that are one thing away from greatness — the design. The format depends on the project: a paid redesign, or a design partnership in products I genuinely believe in. I take on a limited number of projects at a time so each one gets my full attention.

If that sounds like your product — let's talk.

<p align="center">
  <a href="https://t.me/ilnaritto"><img src="https://img.shields.io/badge/Message%20on%20Telegram-229ED9?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram" /></a>
  &nbsp;
  <a href="https://github.com/ilnaritto/muesli/issues/new?title=Project%20discussion&body=Link%20to%20the%20project%3A%20%0AWhat%20you%27d%20like%20to%20improve%3A%20"><img src="https://img.shields.io/badge/✦%20Discuss%20a%20project-8A5CF6?style=for-the-badge" alt="Discuss a project" /></a>
</p>

---

## The original project

The entire technical foundation is the work of the original Muesli and its author. If you want the working product, full documentation, installation, and releases — they're here:

**→ [Muesli-HQ/muesli](https://github.com/Muesli-HQ/muesli)** &nbsp;·&nbsp; [Full technical README](README.original.md)

Thanks to the author for a wonderful foundation and for being open to design experiments. 🙏

---

## License

This repository contains two parts under two different sets of terms:

- **The original Muesli code** — © Pranav Hari, licensed under **[MIT](LICENSE.upstream-MIT)**. Free, as it always was.
- **The design, visual assets, and new code of this fork** — © ilnaritto. **Free to use, modify, and share — but not to sell.** Reselling, or selling the design as part of a paid product, requires written permission.

The right to sell and commercially license the design stays **with the design's author (ilnaritto)**. To buy, license, or discuss a partnership — reach out on [Telegram](https://t.me/ilnaritto) or via [Issues](https://github.com/ilnaritto/muesli/issues).

Full terms are in the **[LICENSE](LICENSE)** file.
