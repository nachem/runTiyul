/* RunTiyul landing page interactions */
(function () {
  "use strict";

  var REPO = "nachem/runTiyul";
  var doc = document.documentElement;

  /* ---------------- Theme toggle (persisted) ---------------- */
  var themeToggle = document.getElementById("themeToggle");
  try {
    var stored = localStorage.getItem("runtiyul-theme");
    if (stored === "light" || stored === "dark") {
      doc.setAttribute("data-theme", stored);
    } else if (window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches) {
      doc.setAttribute("data-theme", "light");
    }
  } catch (e) { /* localStorage may be blocked */ }

  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      var next = doc.getAttribute("data-theme") === "light" ? "dark" : "light";
      doc.setAttribute("data-theme", next);
      try { localStorage.setItem("runtiyul-theme", next); } catch (e) {}
      var meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute("content", next === "light" ? "#f5f8ff" : "#0b1020");
    });
  }

  /* ---------------- Mobile nav ---------------- */
  var navToggle = document.getElementById("navToggle");
  var navMenu = document.getElementById("navMenu");
  if (navToggle && navMenu) {
    navToggle.addEventListener("click", function () {
      var open = navMenu.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
      navToggle.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    });
    navMenu.addEventListener("click", function (ev) {
      if (ev.target.tagName === "A") {
        navMenu.classList.remove("open");
        navToggle.setAttribute("aria-expanded", "false");
      }
    });
  }

  /* ---------------- Footer year ---------------- */
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());

  /* ---------------- Reveal on scroll ---------------- */
  var revealEls = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && revealEls.length) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("in"); });
  }

  /* ---------------- Live latest-release info ---------------- */
  // Enhances download buttons with the exact asset URLs from the latest
  // release and shows the version. Falls back silently to the static
  // "releases/latest/download/..." links defined in the HTML.
  function bytesToSize(bytes) {
    if (!bytes && bytes !== 0) return "";
    var mb = bytes / (1024 * 1024);
    return mb >= 1 ? mb.toFixed(1) + " MB" : Math.round(bytes / 1024) + " KB";
  }

  function applyAsset(ids, asset) {
    if (!asset) return;
    ids.forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.setAttribute("href", asset.browser_download_url);
    });
  }

  fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
    .then(function (rel) {
      var assets = rel.assets || [];
      var apk = assets.filter(function (a) { return /\.apk$/i.test(a.name); })[0];
      var ipa = assets.filter(function (a) { return /\.ipa$/i.test(a.name); })[0];

      applyAsset(["ctaAndroid", "dlAndroid"], apk);
      applyAsset(["ctaIos", "dlIos"], ipa);

      var signingTransition = document.getElementById("androidSigningTransition");
      var versionMatch = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(rel.tag_name || "");
      if (signingTransition && versionMatch) {
        var versionParts = versionMatch.slice(1).map(Number);
        var permanentSigningAvailable = versionParts[0] > 1 ||
          (versionParts[0] === 1 && versionParts[1] > 2) ||
          (versionParts[0] === 1 && versionParts[1] === 2 && versionParts[2] >= 1);
        signingTransition.hidden = !permanentSigningAvailable;
      }

      var meta = document.getElementById("releaseMeta");
      if (meta && rel.tag_name) {
        var date = rel.published_at ? new Date(rel.published_at).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }) : "";
        var sizes = [];
        if (apk) sizes.push("APK " + bytesToSize(apk.size));
        if (ipa) sizes.push("IPA " + bytesToSize(ipa.size));
        meta.textContent = "Latest release " + rel.tag_name +
          (date ? " · " + date : "") +
          (sizes.length ? " · " + sizes.join(" · ") : "");
      }
    })
    .catch(function () {
      // No release yet (or offline). Static links remain in place.
      var note = document.getElementById("ctaNote");
      // Keep the default note; nothing else to do.
      void note;
    });
})();
