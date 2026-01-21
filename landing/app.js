const WAITLIST_ENDPOINT = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec";

const forms = document.querySelectorAll("[data-waitlist]");

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

async function submitWaitlist(form) {
  const status = form.querySelector("[data-form-status]");
  status.textContent = "Submitting…";

  const formData = new FormData(form);
  const payload = Object.fromEntries(formData.entries());
  payload.timestamp = new Date().toISOString();
  payload.page = window.location.href;

  try {
    const response = await fetch(WAITLIST_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`Request failed: ${response.status}`);
    }

    status.textContent = "You are on the list. Check your inbox soon.";
    form.reset();
  } catch (error) {
    status.textContent = "Something went wrong. Please try again.";
    console.error(error);
  }
}

forms.forEach((form) => {
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    submitWaitlist(form);
  });
});

if (!prefersReducedMotion && window.anime) {
  window.addEventListener("load", () => {
    anime({
      targets: ".hero .tag, .hero h1, .hero p, .hero-bullets li, .hero-form",
      translateY: [16, 0],
      opacity: [0, 1],
      delay: anime.stagger(80),
      duration: 600,
      easing: "easeOutQuad",
    });

    anime({
      targets: ".panel, .menu-bar",
      translateY: [20, 0],
      opacity: [0, 1],
      delay: 300,
      duration: 700,
      easing: "easeOutQuart",
    });

    anime({
      targets: "[data-hero-panel]",
      translateY: [0, -6],
      direction: "alternate",
      easing: "easeInOutSine",
      duration: 2400,
      loop: true,
    });

    anime({
      targets: "[data-hero-bar]",
      translateY: [0, -4],
      direction: "alternate",
      easing: "easeInOutSine",
      duration: 2000,
      delay: 300,
      loop: true,
    });

    anime({
      targets: ".menu-dot.listening",
      scale: [1, 1.25],
      opacity: [0.7, 1],
      direction: "alternate",
      easing: "easeInOutSine",
      duration: 1200,
      loop: true,
    });

    anime({
      targets: ".panel-card",
      backgroundColor: ["#f9f6f1", "#ffffff"],
      direction: "alternate",
      easing: "easeInOutSine",
      duration: 2800,
      delay: anime.stagger(200),
      loop: true,
    });

    anime({
      targets: ".value-card, .trust-card, .steps li",
      opacity: [0, 1],
      translateY: [12, 0],
      delay: anime.stagger(90, { start: 400 }),
      duration: 500,
      easing: "easeOutQuad",
    });

    const nodes = document.querySelectorAll("[data-flow-node]");
    const progress = document.querySelector("[data-flow-progress]");
    const head = document.querySelector("[data-flow-head]");
    const track = document.querySelector("[data-flow-track]");
    let flowTimeline;

    function setupFlow() {
      if (!nodes.length || !progress || !head || !track) {
        return;
      }
      if (flowTimeline) {
        flowTimeline.pause();
      }
      const trackRect = track.getBoundingClientRect();
      const positions = Array.from(nodes).map((node) => {
        const rect = node.getBoundingClientRect();
        return rect.left - trackRect.left + rect.width / 2;
      });

      flowTimeline = anime.timeline({
        loop: true,
        autoplay: true,
      });

      positions.forEach((x, index) => {
        flowTimeline.add(
          {
            targets: head,
            translateX: x,
            duration: 600,
            easing: "easeInOutQuad",
            update: () => {
              progress.style.width = `${x}px`;
            },
            begin: () => {
              nodes.forEach((n) => n.classList.remove("active"));
              nodes[index].classList.add("active");
            },
          },
          index === 0 ? 0 : "+=600"
        );
      });
    }

    setupFlow();
    window.addEventListener("resize", () => {
      setupFlow();
    });
  });
}
