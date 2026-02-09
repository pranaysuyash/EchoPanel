const WAITLIST_ENDPOINT =
  window.WAITLIST_ENDPOINT ||
  'https://script.google.com/macros/s/AKfycbzln1RWmoPKjI4sc6j7fic1mM_UlYX45yOr3J8wGoouBemcF5WIh304206YsvjF7YHq/exec';

const forms = document.querySelectorAll('[data-waitlist]');

const prefersReducedMotion = window.matchMedia(
  '(prefers-reduced-motion: reduce)',
).matches;

async function submitWaitlist(form) {
  const status = form.querySelector('[data-form-status]');
  const submitButton = form.querySelector('button[type="submit"]');

  if (submitButton) submitButton.disabled = true;
  if (status) status.textContent = 'Submitting…';

  const formData = new FormData(form);
  const payload = Object.fromEntries(formData.entries());
  payload.timestamp = new Date().toISOString();
  payload.page = window.location.href;

  try {
    const response = await fetch(WAITLIST_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`Request failed: ${response.status}`);
    }

    if (status) status.textContent = 'You are on the list. Check your inbox soon.';
    form.reset();
  } catch (error) {
    if (status) status.textContent = 'Something went wrong. Please try again.';
    console.error(error);
  } finally {
    if (submitButton) submitButton.disabled = false;
  }
}

forms.forEach((form) => {
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    submitWaitlist(form);
  });
});

if (!prefersReducedMotion && window.anime) {
  window.addEventListener('load', () => {
    anime({
      targets: '.hero .tag, .hero h1, .hero p, .hero-bullets li, .hero-form',
      translateY: [16, 0],
      opacity: [0, 1],
      delay: anime.stagger(80),
      duration: 600,
      easing: 'easeOutQuad',
    });

    anime({
      targets: '.panel, .menu-bar, .preview-card',
      translateY: [20, 0],
      opacity: [0, 1],
      delay: 300,
      duration: 700,
      easing: 'easeOutQuart',
    });

    anime({
      targets: '.mesh-orb',
      translateX: () => anime.random(-20, 20),
      translateY: () => anime.random(-16, 16),
      scale: [1, 1.06],
      direction: 'alternate',
      easing: 'easeInOutSine',
      duration: 6000,
      delay: anime.stagger(600),
      loop: true,
    });

    anime({
      targets: '.panel-card',
      backgroundColor: ['#f9f6f1', '#ffffff'],
      direction: 'alternate',
      easing: 'easeInOutSine',
      duration: 2800,
      delay: anime.stagger(200),
      loop: true,
    });

    anime({
      targets: '.value-card, .design-card, .role-card, .trust-card, .faq-card, .steps li',
      opacity: [0, 1],
      translateY: [12, 0],
      delay: anime.stagger(90, { start: 400 }),
      duration: 500,
      easing: 'easeOutQuad',
    });

    // Scroll-triggered animation for Flow Cards
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          anime({
            targets: '.flow-card',
            translateY: [30, 0],
            opacity: [0, 1],
            delay: anime.stagger(120),
            duration: 800,
            easing: 'easeOutExpo'
          });
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });

    const flowGrid = document.querySelector('.flow-cards');
    if (flowGrid) {
      observer.observe(flowGrid);
    }
  });
}
